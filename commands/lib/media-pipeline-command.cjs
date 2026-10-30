'use strict';

// Domain-neutral host commands. Domain modules own brief/content/measurement
// rules; Bubo owns setup, inference, native limits and attempt accounting.
const fs=require('fs'), path=require('path'), crypto=require('crypto');
const runtime=require('./bubo-runtime.cjs');
const contracts=require('./media-pipeline-contract.cjs');
const lifecycle=require('./media-pipeline-state.cjs');
const adapter=require('./bubo-media-adapter.cjs');
const discovery=require('./bubo-media-host.cjs');
const fail=message=>{throw new Error(message);};
const CONTROL_FLAGS=['timeout','max-log-bytes','max-private-bytes','platform-modules'];
const COMMON=['root'];
const OPERATIONS={
  brief:['brief'],
  init:['task','asset','version','brief','staging-root','workspace','contract','media'],
  revise:['state','version','brief','staging-root','workspace','contract','media'],
  status:['state'],doctor:['state','workspace','contract','media'],
  'setup-plan':['task','provider','manifest','workspace','media-state','contract','media',...CONTROL_FLAGS],
  generate:['state','provider','workspace','media-state',...CONTROL_FLAGS],
  import:['state','provider','manifest','manifests','origin'],
  validate:['state'],review:['state','review'],handoff:['state'],
  promote:['state','authorization'],recover:['state','authorization']
};
function help(domain) {
  return `${domain.toLowerCase()}-pipeline <brief|init|revise|status|doctor|setup-plan|generate|import|validate|review|handoff|promote|recover> [--root ROOT] [unique --option value arguments]\n`
    +'brief --brief JSON; init --task ID --asset NAME --version ID --brief JSON [--workspace CACHE_CHILD | --staging-root PATH] [--contract FILE] [--media FILE]\n'
    +'revise --state ASSET_JSON --version NEW_ID --brief JSON [init selections]; status --state ASSET_JSON\n'
    +'doctor [--state ASSET_JSON] [--workspace CACHE_CHILD] [--contract FILE] [--media FILE] (read-only advertised/receipt discovery; native readiness remains unverified)\n'
    +'setup-plan --task ID --provider LOCAL --manifest SETUP_JSON [--workspace CACHE_CHILD] [--media-state CACHE_CHILD] [--contract FILE] [--media FILE] [bounded controls] (dry-run only)\n'
    +'generate --state ASSET_JSON --provider LOCAL --workspace CACHE_CHILD --media-state SHARED_CACHE_CHILD [bounded controls]\n'
    +'import --state ASSET_JSON --provider LOCAL|CLOUD (--manifest JSON | --manifests JSON_ARRAY_FILE) [--origin historical-import|external-import]\n'
    +'validate --state ASSET_JSON; review --state ASSET_JSON --review REVIEW_JSON; handoff --state ASSET_JSON\n'
    +'promote|recover --state ASSET_JSON --authorization PROMOTION_JSON (explicit separate asset copying/recovery)\n'
    +'Bounded controls: --timeout SECONDS --max-log-bytes BYTES --max-private-bytes BYTES --platform-modules JSON.\n'
    +'Provider must match the explicit brief. CLOUD generation requires a separately available authorized session capability; import its real provenance instead of falling back to LOCAL. No command accepts --execute or --load. Ordinary discovery and initialization load no model or software. No implicit setup, license acceptance, generation allowance, human acceptance or promotion.';
}
function parse(values) {
  const args=[...values], operation=args.shift();
  if (!operation || ['help','--help','-h'].includes(operation) || args.includes('--help') || args.includes('-h')) return {operation:'help',options:{}};
  if (!Object.hasOwn(OPERATIONS,operation)) fail('Unknown media pipeline operation; use --help.');
  const allowed=new Set([...COMMON,...OPERATIONS[operation]]), options={};
  for(let index=0;index<args.length;index++) {
    const flag=args[index];
    if (!/^--[a-z][a-z-]*$/.test(flag)) fail('Expected unique --option value arguments.');
    const key=flag.slice(2);
    if (!allowed.has(key) || Object.hasOwn(options,key)) fail('Unknown, duplicate or protected pipeline option: '+flag);
    const value=args[++index];
    if (!value || value.startsWith('--')) fail('Missing value for '+flag+'.');
    options[key]=value;
  }
  return {operation,options};
}
function required(options,...keys) {
  for(const key of keys)if(!options[key])fail('Explicit --'+key+' is required.');
}
function read(root,name,{array=false}={}) {
  const full=runtime.projectPath(root,name), stat=fs.statSync(full);
  if(!stat.isFile() || stat.size>1048576)fail('Pipeline input must be a bounded regular JSON file.');
  const value=JSON.parse(fs.readFileSync(full,'utf8'));
  if(!value || typeof value!=='object' || (array?!Array.isArray(value):Array.isArray(value)))fail(array?'Expected a JSON array.':'Expected a JSON object.');
  return value;
}
function artifact(loaded,label,value) {
  const relative=loaded.directory+'/'+label+'/'+crypto.randomUUID()+'.json', full=runtime.projectPath(loaded.root,relative);
  const bytes=JSON.stringify(value,null,2)+'\n';
  if(Buffer.byteLength(bytes)>1048576)fail('Generated host evidence exceeds the size bound.');
  fs.mkdirSync(path.dirname(full),{recursive:true});runtime.components(full);
  const fd=fs.openSync(full,'wx',0o600);
  try{fs.writeFileSync(fd,bytes);fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
  return lifecycle.identity(loaded.root,relative);
}
function provider(options,brief) {
  required(options,'provider');
  const value=options.provider.toUpperCase();
  if(!['LOCAL','CLOUD'].includes(value))fail('Select explicit LOCAL or CLOUD provider.');
  if(brief && value!==brief.provider)fail('Selected provider conflicts with the explicit asset brief; no fallback is permitted.');
  return value;
}
function owned(spec,root,stateFile,{fresh=true}={}) {
  const loaded=lifecycle.load({root,stateFile});
  if(loaded.asset.domain!==spec.domain)fail('Asset state belongs to another production domain.');
  const status=lifecycle.status({root,stateFile});
  if(fresh && status.stale.length)fail('Asset version is stale: '+status.stale.join(', ')+'. Revise with retained ancestry.');
  lifecycle.identity(root,loaded.asset.brief);
  const brief=spec.validateBrief(read(root,loaded.asset.brief.path),{root,task:loaded.asset.task});
  if(brief.kind!==loaded.asset.modality)fail('Brief modality differs from its immutable asset identity.');
  const candidate=[...loaded.events].reverse().find(event=>event.kind==='candidate')?.data || null;
  return {root,state:loaded,brief,candidate,status};
}
function latest(context,kind,predicate=()=>true) {
  return [...context.state.events].reverse().find(event=>event.kind===kind && predicate(event.data));
}
function documentEvidence(context,event,label) {
  if(!event)fail('Current '+label+' evidence is required.');
  const ref=lifecycle.identity(context.root,event.data.evidence);
  return read(context.root,ref.path);
}
function domainGuards(spec,options) {
  const context=owned(spec,options.root,options.stateFile);
  if(!context.candidate)fail('A staged candidate is required.');
  const technical=documentEvidence(context,latest(context,'technical'),'technical');
  if(technical.status!=='passed')fail('Current passed technical evidence is required.');
  if(typeof spec.validateTechnicalReport!=='function')fail('Domain technical revalidation is unavailable.');
  spec.validateTechnicalReport(technical,context);
  const content=documentEvidence(context,latest(context,'review',data=>data.kind==='content'),'content review');
  if(content.verdict!=='accepted')fail('Current accepted content review is required.');
  spec.validateReview(content,context);
  const target=documentEvidence(context,latest(context,'review',data=>data.kind==='runtime'),'runtime review');
  if(target.verdict!=='accepted')fail('Current accepted runtime review is required.');
  spec.validateRuntimeReview(target,context);
  return context;
}
function controls(options) {
  const selected=Object.fromEntries(CONTROL_FLAGS.filter(key=>options[key]!==undefined).map(key=>[key,options[key]]));
  adapter.executionBudgets(adapter.parse(Object.entries(selected).flatMap(([key,value])=>['--'+key,value])));
  return selected;
}
function checkSpec(spec) {
  if(!spec || !['AUDIO','MUSIC','VOICE'].includes(spec.domain) || !Array.isArray(spec.modalities)
      || ['validateBrief','request','technical','validateTechnicalReport','validateReview','validateRuntimeReview'].some(name=>typeof spec[name]!=='function'))
    fail('Selected domain workflow is unavailable or incomplete in this revision.');
}
function referenceMapper(spec,root,brief,document) {
  return typeof spec.mapReference==='function'?(ref,trail)=>spec.mapReference(ref,trail,{document,root,brief}):undefined;
}
async function run(spec,values) {
  checkSpec(spec);
  const {operation,options}=parse(values);
  if(operation==='help')return help(spec.domain);
  required(options,'root');const root=contracts.rootDirectory(options.root);
  if(operation==='brief') {
    required(options,'brief');const brief=spec.validateBrief(read(root,options.brief),{root});
    return {schemaVersion:1,domain:spec.domain,kind:brief.kind,provider:brief.provider,valid:true,brief:lifecycle.identity(root,options.brief),generation:false};
  }
  if(operation==='init' || operation==='revise') {
    required(options,'version','brief');
    if(options.workspace && options['staging-root'])fail('Select --workspace or --staging-root, not both.');
    const prior=operation==='revise'?(required(options,'state'),lifecycle.load({root,stateFile:options.state})):null;
    if(prior && prior.asset.domain!==spec.domain)fail('Revision source belongs to another domain.');
    if(!prior)required(options,'task','asset');
    const task=prior?.asset.task || options.task, asset=prior?.asset.asset || options.asset;
    const brief=spec.validateBrief(read(root,options.brief),{root,task});
    if(!spec.modalities.includes(brief.kind))fail('Brief kind is unsupported by this domain.');
    const workspace=options.workspace || '.opencaw/.cache/bubo-media';
    const stagingRoot=options['staging-root'] || (options.workspace?workspace+'/staging/'+spec.domain.toLowerCase():prior?.asset.stagingRoot)
      || (brief.provider==='LOCAL'?workspace+'/staging/'+spec.domain.toLowerCase():'.art-staging/media/'+spec.domain.toLowerCase());
    const result=lifecycle.init({root,task,asset,version:options.version,domain:spec.domain,modality:brief.kind,brief:options.brief,stagingRoot,
      contract:options.contract || prior?.asset.selection?.contract,media:options.media || prior?.asset.selection?.media,
      referenceMapper:referenceMapper(spec,root,brief,'brief'),
      ...(prior?{parent:lifecycle.identity(root,prior.stateFile)}:{})});
    return {schemaVersion:1,domain:spec.domain,stateFile:result.stateFile,status:lifecycle.status({root,stateFile:result.stateFile}),generation:false};
  }
  if(operation==='status') {
    required(options,'state');const loaded=lifecycle.load({root,stateFile:options.state});
    if(loaded.asset.domain!==spec.domain)fail('Asset state belongs to another production domain.');
    return lifecycle.status({root,stateFile:options.state});
  }
  if(operation==='doctor') {
    let selection={contract:options.contract,media:options.media};
    let assetStatus=null;
    if(options.state) {
      const loaded=lifecycle.load({root,stateFile:options.state});
      if(loaded.asset.domain!==spec.domain)fail('Asset state belongs to another production domain.');
      selection={...loaded.asset.selection,...Object.fromEntries(Object.entries(selection).filter(([,value])=>value!==undefined))};
      assetStatus=lifecycle.status({root,stateFile:options.state});
    }
    const context=contracts.resolve({root,domain:spec.domain,...selection});
    const host=discovery.inspect(root,options.workspace), key={AUDIO:'sfx',MUSIC:'music',VOICE:'voice'}[spec.domain];
    return {schemaVersion:1,domain:spec.domain,context,assetStatus,workspace:host.workspace,runtime:host.runtime,capability:host.modalities[key],gpu:host.gpu,
      nativeReadiness:'unverified',generation:false,modelLoading:false,installation:false,
      limits:host.limits};
  }
  if(operation==='setup-plan') {
    required(options,'task','manifest');if(provider(options)!=='LOCAL')fail('Native setup planning requires LOCAL; no provider fallback.');
    const context=contracts.resolve({root,domain:spec.domain,contract:options.contract,media:options.media});
    if(!context.configured || !context.media)fail('Configure the selected domain and shared MEDIA contracts before setup planning.');
    const manifest=read(root,options.manifest), allowed=spec.backends || [spec.backend];
    if(!['bubo-media-setup/v1','bubo-media-provision/v1'].includes(manifest.schemaVersion) || !allowed.includes(manifest.backend)
        || manifest.task!==options.task)fail('Setup manifest task/backend/schema conflicts with this domain.');
    const selectedControls=controls(options), args=['--root',root,'--task',options.task,'--manifest',options.manifest,'--media',context.media.path];
    for(const key of ['workspace','media-state'])if(options[key])args.push('--'+key,options[key]);
    args.push(...Object.entries(selectedControls).flatMap(([key,value])=>['--'+key,value]));
    const result=await adapter.invoke('setup',adapter.parse(args),{emit:false});
    return {schemaVersion:1,domain:spec.domain,provider:'LOCAL',operation:'setup-plan',execute:false,generation:false,result:result.data};
  }
  required(options,'state');
  const context=owned(spec,root,options.state), stateOptions={root,stateFile:context.state.stateFile};
  if(operation==='generate') {
    const selected=provider(options,context.brief);
    if(context.candidate)fail('This version already has a candidate; revise with retained ancestry before another generation attempt.');
    if(selected==='CLOUD')fail('CLOUD generation requires a separately available authorized session capability. Import its real provenance; no LOCAL fallback was performed.');
    required(options,'workspace','media-state');
    const request=spec.request(context.brief,{root,asset:context.state.asset});
    const policyReferences=typeof spec.generationReferences==='function'?spec.generationReferences(context.brief,{root,asset:context.state.asset}):[];
    const result=await lifecycle.dispatch({...stateOptions,provider:selected,request,workspace:options.workspace,mediaState:options['media-state'],controls:controls(options),policyReferences});
    lifecycle.recordCandidate({...stateOptions,provider:selected,manifests:result.hostMediaProvenance,referenceMapper:referenceMapper(spec,root,context.brief,'neutral')});
    return {schemaVersion:1,domain:spec.domain,status:'staged',stateFile:context.state.stateFile,
      provenance:result.hostMediaProvenance,assetStatus:lifecycle.status(stateOptions),promotion:false};
  }
  if(operation==='import') {
    const selected=provider(options,context.brief);
    if(Boolean(options.manifest)===Boolean(options.manifests))fail('Select exactly one --manifest or --manifests JSON-array file.');
    const manifests=options.manifests?read(root,options.manifests,{array:true}):[options.manifest];
    if(!manifests.length || manifests.length>128 || manifests.some(name=>typeof name!=='string'))fail('Expected a bounded array of manifest paths.');
    lifecycle.recordCandidate({...stateOptions,provider:selected,manifests,origin:options.origin,referenceMapper:referenceMapper(spec,root,context.brief,'neutral')});
    return {schemaVersion:1,domain:spec.domain,status:'staged',stateFile:context.state.stateFile,assetStatus:lifecycle.status(stateOptions),promotion:false};
  }
  if(operation==='validate') {
    if(!context.candidate)fail('A staged candidate is required before technical validation.');
    const report=spec.technical(context), output=artifact(context.state,'technical',report);
    lifecycle.recordTechnical({...stateOptions,report:output.path});
    return {schemaVersion:1,domain:spec.domain,status:report.status,ok:report.status==='passed',report:output,checks:report.checks,promotion:false};
  }
  if(operation==='review') {
    required(options,'review');const review=read(root,options.review);
    if(!context.candidate)fail('A staged candidate is required before review.');
    if(review.kind==='content')spec.validateReview(review,context);
    else if(review.kind==='runtime')spec.validateRuntimeReview(review,context);
    else fail('Review kind must be content or runtime.');
    lifecycle.recordReview({...stateOptions,review:options.review});
    return {schemaVersion:1,domain:spec.domain,reviewKind:review.kind,verdict:review.verdict,stateFile:context.state.stateFile,promotion:false};
  }
  if(operation==='handoff') {
    domainGuards(spec,stateOptions);const plan=lifecycle.admitHandoff(stateOptions), output=artifact(context.state,'handoff',plan);
    return {...plan,domain:spec.domain,handoff:output};
  }
  if(operation==='promote' || operation==='recover') {
    required(options,'authorization');domainGuards(spec,stateOptions);
    const promotion=require('./media-pipeline-promotion.cjs');
    const method=promotion[operation==='promote'?'promote':'recover'];
    if(typeof method!=='function')fail('Explicit promotion execution is unavailable in this revision.');
    return method({...stateOptions,authorization:options.authorization,validate:()=>domainGuards(spec,stateOptions)});
  }
  fail('Unsupported domain operation.');
}
async function main(values) {
  const [domain,...args]=values;
  if(!['AUDIO','MUSIC','VOICE'].includes(domain))fail('Explicit registered domain is required.');
  const file=path.join(__dirname,domain.toLowerCase()+'-pipeline.cjs');
  if(!fs.existsSync(file))fail('Selected domain workflow is unavailable in this revision.');
  const spec=require(file);if(spec.domain!==domain)fail('Domain implementation identity mismatch.');
  const result=await run(spec,args);
  console.log(typeof result==='string'?result:JSON.stringify(result,null,2));
  if(result?.ok===false)process.exitCode=1;
}
module.exports={parse,run,help,domainGuards};
if(require.main===module)main(process.argv.slice(2)).catch(error=>{console.error(error.message);process.exitCode=1;});
