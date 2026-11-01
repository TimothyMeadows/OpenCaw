'use strict';

// Hephaera owns policy and receipts. Bubo owns installation verification,
// inference, GPU/process ownership, acceptance claims and native measurements.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const runtime = require('./bubo-runtime.cjs');
const host = require('./bubo-host-adapter.cjs');
const styles = require('./style-contract.cjs');
const transition = require('./state-transition.cjs');
const CACHE = '.hephaera/.cache', SHA = /^[a-f0-9]{64}$/, ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
const FLAGS = new Set(['root','task','manifest','workspace','media-state','media','selection','platform-modules','timeout','max-log-bytes','max-private-bytes','execute','load']);
const fail = message => { throw new Error(message); };
const canonical = value => JSON.stringify(runtime.canonical(value));
const unavailable = reason => ({ unavailable: true, reason });
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const overlap = (a,b) => runtime.within(a,b) || runtime.within(b,a);
const regular = file => fs.existsSync(file) && fs.lstatSync(file).isFile();

function parse(values) {
  const options = new Map();
  for (let index=0; index<values.length; index++) {
    const argument=values[index];
    if (!/^--[a-z][a-z-]*$/.test(argument)) fail('Expected unique --option value arguments.');
    const key=argument.slice(2);
    if (!FLAGS.has(key) || options.has(key)) fail('Unknown, protected or duplicate media option: '+argument);
    const value=key==='execute' && (index+1===values.length || values[index+1].startsWith('--')) ? 'true'
      : index+1<values.length && !values[index+1].startsWith('--') ? values[++index] : fail('Missing value for '+argument);
    if ((key==='execute' || key==='load') && value!=='true') fail(argument+' accepts only true; omit it otherwise.');
    options.set(key,value);
  }
  return options;
}

function document(file,maximum=1048576) {
  runtime.components(file);
  if (!regular(file) || fs.statSync(file).size>maximum) fail('Missing, linked or oversized media JSON.');
  const value=JSON.parse(fs.readFileSync(file,'utf8'));
  if (!value || typeof value!=='object' || Array.isArray(value)) fail('Media document must be a JSON object.');
  return value;
}

function validateMedia(file) {
  runtime.components(file);
  if (!regular(file) || fs.statSync(file).size>1048576) fail('An existing bounded MEDIA policy is required.');
  const text=fs.readFileSync(file,'utf8'), lines=text.split(/\r?\n/);
  for (const heading of ['# MEDIA.md','## Pipeline Availability','## Capability Matrix','## Destinations And Budgets','## Rights, Consent, And Provenance','## Review And Promotion'])
    if (!lines.includes(heading)) fail('MEDIA policy is missing '+heading+'.');
  let listing=false; const selected=[];
  for (const line of lines) {
    if (line==='Generated from Hephaera media pipeline templates:') { listing=true; continue; }
    if (listing && line==='---') { listing=false; continue; }
    if (listing && line.startsWith('- ')) selected.push(line.slice(2));
  }
  if (canonical(selected)!==canonical(['CLOUD','LOCAL'])) fail('MEDIA policy must explicitly configure CLOUD with LOCAL; no provider was selected implicitly.');
  if (/comfyui|comfy-cli|use-comfyui-local-generation|run-comfyui-workflow/i.test(text))
    fail('LOCAL MEDIA selects a retired execution integration; explicitly refresh the policy and preserve historical receipts.');
  for (const modality of [/image/i,/music/i,/sound.effect|sfx/i,/voice/i])
    if (!modality.test(text)) fail('LOCAL MEDIA must describe image, music, sound-effect and voice availability independently.');
  if (!/ask the user to choose|require the user to choose/i.test(text)
      || !/never (switch or )?fall back.*silently|never.*silently.*fall back/i.test(text))
    fail('MEDIA policy requires explicit provider choice and no silent fallback.');
  if (/(api[_ -]?key|access[_ -]?token|hf[_ -]?token)[\s]*[:=][\s]*[A-Za-z0-9_/-]{12,}/i.test(text))
    fail('MEDIA policy appears to contain a persisted credential.');
}

function bounded(options,key,fallback,maximum) {
  const value=options.has(key)?Number(options.get(key)):fallback;
  if (!Number.isSafeInteger(value) || value<1 || value>maximum) fail('Invalid finite --'+key+' bound.');
  return value;
}
function executionBudgets(options) {
  return {timeoutSeconds:bounded(options,'timeout',1800,86400),maxLogBytes:bounded(options,'max-log-bytes',16777216,1073741824),
    ...(options.has('max-private-bytes')?{maxPrivateBytes:bounded(options,'max-private-bytes',1,Number.MAX_SAFE_INTEGER)}:{})};
}

function sharedPath(root,approvalSha256) {
  if (!SHA.test(approvalSha256)) fail('Invalid acceptance approval identity.');
  return runtime.projectPath(root,CACHE+'/local-media/acceptance-roots/'+approvalSha256+'.json');
}
function compareBinding(file,binding) {
  if (fs.existsSync(file) && canonical(document(file))!==canonical(binding))
    fail('This approval is already bound to another shared media-state root; changing workspace cannot reset acceptance.');
}
function bindSharedState(prepared) {
  if (!prepared.sharedBinding) return null;
  transition.assertProductionAllowed(prepared.root, 'shared approval binding');
  const file=sharedPath(prepared.root,prepared.sharedBinding.approvalSha256);
  compareBinding(file,prepared.sharedBinding);
  if (!fs.existsSync(file)) {
    runtime.components(path.dirname(file)); fs.mkdirSync(path.dirname(file),{recursive:true}); runtime.components(file);
    try { fs.writeFileSync(file,JSON.stringify(prepared.sharedBinding,null,2)+'\n',{flag:'wx'}); }
    catch (error) { if (error.code!=='EEXIST') throw error; }
  }
  compareBinding(file,prepared.sharedBinding);
  return file;
}

function contextFor(operation,options,info,{policyReferences=[]}={}) {
  if(!Array.isArray(policyReferences)||policyReferences.length>256)fail('Bounded internal generation policy references are required.');
  if(policyReferences.length&&operation!=='generate')fail('Extra policy references apply only to generation.');
  if (!['setup','inspect','generate'].includes(operation)) fail('Unsupported media operation; promotion is separate.');
  if (!(options instanceof Map)) fail('Media options must be parsed.');
  for (const key of options.keys()) if (!FLAGS.has(key)) fail('Unknown or protected media option: --'+key);
  if (options.has('execute') && (operation!=='setup' || options.get('execute')!=='true')) fail('--execute applies only to explicit setup.');
  if (options.has('load') && (operation!=='inspect' || options.get('load')!=='true')) fail('--load true applies only to zero-sample inspection.');
  if (!options.get('root') || !ID.test(options.get('task')||'') || options.get('task')==='..') fail('Explicit --root and safe --task are required.');
  runtime.syntax(runtime.native(options.get('root')));
  const root=path.resolve(runtime.native(options.get('root'))); runtime.components(root);
  if (!fs.statSync(root).isDirectory()) fail('Project root must be a real directory.');
  if (operation==='generate' || operation==='setup' && options.has('execute') || operation==='inspect' && options.has('load'))
    transition.assertProductionAllowed(root, 'native media '+operation);
  const task=options.get('task'), relative=file=>path.relative(root,file).split(path.sep).join('/');
  const scoped=value=>runtime.projectPath(root,value);
  const cache=runtime.projectPath(root,CACHE);
  function cacheChild(value,label) {
    const full=scoped(value);
    if (!runtime.within(cache,full) || runtime.samePath(cache,full)) fail(label+' must be a scoped project-cache child.');
    if (fs.existsSync(full) && !fs.statSync(full).isDirectory()) fail(label+' must be a directory.');
    return full;
  }
  const workspaceFull=cacheChild(options.get('workspace')||CACHE+'/bubo-media','Workspace');
  const workspace=relative(workspaceFull), stateRoot=CACHE+'/tasks/'+task+'/bubo-media', state=scoped(stateRoot);
  const staging=scoped(workspace+'/staging'), toolsRoot=scoped(workspace+'/tools'), downloads=scoped(workspace+'/downloads');
  const mediaStateFull=cacheChild(options.get('media-state')||CACHE+'/local-media/shared-state','Shared media state');
  const mediaState=relative(mediaStateFull), bindingRoot=scoped(CACHE+'/local-media/acceptance-roots');
  if (overlap(workspaceFull,state) || overlap(workspaceFull,bindingRoot) || overlap(state,mediaStateFull)
      || overlap(mediaStateFull,staging) || overlap(mediaStateFull,toolsRoot) || overlap(mediaStateFull,downloads) || overlap(mediaStateFull,bindingRoot))
    fail('Workspace, execution state, staging, dependencies and acceptance policy require separate ownership.');
  const references=new Map(), tools=new Map(), immutable=[];
  function reference(value,kind='input') {
    const identity=typeof value==='string'?null:value;
    if (identity && (!identity || typeof identity.path!=='string' || !SHA.test(identity.sha256||''))) fail('Exact typed file identity required.');
    const file=scoped(identity?identity.path:value), rel=relative(file);
    if (identity && identity.path!==rel) fail('Evidence identities must use canonical project-relative paths.');
    if (!regular(file)) fail('Missing regular typed media reference: '+rel);
    if (runtime.within(state,file) || runtime.within(staging,file) || runtime.within(mediaStateFull,file) || runtime.within(bindingRoot,file))
      fail('Input evidence cannot overlap mutable execution/output/ledger state or host binding metadata.');
    const sha256=runtime.hash(file);
    if (identity && sha256!==identity.sha256) fail('Typed media reference hash changed.');
    const key=process.platform==='win32'?rel.toLowerCase():rel, prior=references.get(key);
    if (prior && (prior.kind!==kind || prior.sha256!==sha256)) fail('Conflicting typed reference identity or kind.');
    references.set(key,{path:rel,sha256,kind});
    if (references.size>4096) fail('Media reference bound exceeded.');
    return file;
  }
  function typedReference(identity,kind='input') {
    if (!identity || typeof identity!=='object' || Array.isArray(identity)
        || typeof identity.path!=='string' || !SHA.test(identity.sha256||''))
      fail('Exact typed file identity with path and lowercase SHA-256 required.');
    return reference(identity,kind);
  }
  function tool(identity,external=false,kind='selected-native-tool') {
    if (!identity || typeof identity.path!=='string' || !SHA.test(identity.sha256||'')) fail('Selected executable requires its exact SHA-256.');
    runtime.syntax(runtime.native(identity.path));
    const file=path.resolve(root,runtime.native(identity.path)); runtime.components(file);
    if (!external && !runtime.within(toolsRoot,file)) fail('Installed media executables must stay in the selected workspace tools.');
    if (!regular(file) || runtime.hash(file)!==identity.sha256) fail('Selected executable/module is missing or changed.');
    if (runtime.within(state,file) || runtime.within(staging,file) || runtime.within(mediaStateFull,file)) fail('Executable cannot overlap mutable media state.');
    const key=process.platform==='win32'?file.toLowerCase():file, prior=tools.get(key);
    if (prior && (prior.sha256!==identity.sha256 || prior.kind!==kind)) fail('Conflicting executable registration.');
    tools.set(key,{path:file,sha256:identity.sha256,kind});
    if (runtime.within(root,file) && references.has(process.platform==='win32'?relative(file).toLowerCase():relative(file)))
      fail('An executable cannot also be an evidence reference.');
    return file;
  }
  function installedPath(value,directory=true) {
    if (typeof value!=='string') fail('Explicit installed dependency path required.');
    const file=scoped(value);
    const admitted=directory ? runtime.within(toolsRoot,file) && !runtime.samePath(file,toolsRoot)
      : [toolsRoot,downloads].some(scope=>runtime.within(scope,file)&&!runtime.samePath(scope,file));
    if (value!==relative(file) || !admitted)
      fail('Installed dependency directories require canonical workspace/tools children; archive files require tools or downloads children.');
    if (!(directory?fs.existsSync(file)&&fs.statSync(file).isDirectory():regular(file))) fail('Declared installed dependency is missing or has the wrong path type.');
    immutable.push(file); return file;
  }
  function licenses(values) {
    if (!Array.isArray(values) || values.length<1 || values.length>16) fail('Explicit bounded license evidence is required.');
    for (const value of values) typedReference(value,'rights');
  }
  const manifest=reference(options.get('manifest')||fail('Explicit --manifest is required.'));
  const request=document(manifest);
  if (request.task!==task) fail('Media request/task ownership mismatch.');
  const capability=info.capability?.mediaBackends?.find(value=>value.id===request.backend);
  if (!capability) fail('Selected media backend is not declared by the verified Bubo runtime.');
  const mediaFile=reference(options.get('media')||'MEDIA.md','policy'); validateMedia(mediaFile);
  const localTemplate=path.join(runtime.BASE,'.styles/.pipelines/local/PIPELINE.md');
  if (runtime.within(root,localTemplate)) reference(localTemplate,'policy');
  const policy={purpose:'local-media',pipeline:'LOCAL',media:{path:relative(mediaFile),sha256:runtime.hash(mediaFile)}};
  if (capability.modality==='image') {
    const styleFile=reference('STYLE.md','policy'), style=styles.validate(styleFile);
    if (style.primary!=='LOCAL' && !options.has('selection')) fail('Images require primary LOCAL or explicit current LOCAL selection evidence.');
    if (options.has('selection')) {
      const file=reference(options.get('selection'),'policy'), selected=document(file);
      if (!runtime.within(scoped(CACHE+'/tasks/'+task),file) || selected.schemaVersion!==1 || selected.pipeline!=='LOCAL'
          || !['prompt','style'].includes(selected.selectionSource) || selected.styleContract!=='STYLE.md'
          || selected.styleSha256!==style.sha256 || selected.styleContractHash && selected.styleContractHash!==style.sha256
          || selected.selectionSource==='style' && style.primary!=='LOCAL')
        fail('Image selection must bind this task, LOCAL and the current STYLE policy.');
    }
    policy.imageStyle={path:'STYLE.md',sha256:style.sha256};
  } else if (options.has('selection')) fail('Audio does not consume a visual selection.');
  let sharedBinding=null, receiptOutput=null;
  if (operation==='setup') {
    if (!['bubo-media-setup/v1','bubo-media-provision/v1'].includes(request.schemaVersion)) fail('Unsupported native setup request schema.');
    licenses(request.licenses);
    if (request.schemaVersion==='bubo-media-provision/v1') {
      const install=scoped(request.installationRoot), download=scoped(request.downloadRoot);
      if (!runtime.within(toolsRoot,install) || runtime.samePath(install,toolsRoot)
          || !runtime.within(downloads,download) || overlap(install,download))
        fail('Provisioning requires an installation child in workspace/tools and a separate workspace/downloads root.');
      for (const name of ['bootstrapPython','git','cmake','compilerEnvironment','cudaCompiler','commandShell'])
        if (request[name]) tool(request[name],true);
      if (!request.bootstrapPython) fail('Explicit existing bootstrap Python identity required.');
    } else {
      for (const name of ['modelDirectory','environmentRoot','pythonBaseRoot','wheelhouseRoot','noticeDirectory','nativeRuntimeRoot','sourceRoot'])
        if (request[name]!=null) installedPath(request[name]);
      for (const name of ['pythonArchive','sourceArchive']) if (request[name]!=null) installedPath(request[name],false);
      if (!request.modelDirectory) fail('Explicit model directory required.');
      if (request.python) tool(request.python);
      if (request.nativeWorker) tool(request.nativeWorker);
      const receipt=scoped(request.receiptPath);
      if (!runtime.samePath(path.dirname(receipt),scoped(workspace+'/installations')) || path.extname(receipt)!=='.json'
          || runtime.within(mediaStateFull,receipt) || fs.existsSync(receipt))
        fail('Registration requires a new separate workspace receipt in installations/*.json so discovery can find it.');
      receiptOutput=relative(receipt);
    }
  } else {
    if (request.schemaVersion!=='bubo-media-request/v1' || !Array.isArray(request.items) || request.items.length<1 || request.items.length>4) fail('Explicit bounded Bubo media request required.');
    // Native image/SFX accept Int64 seeds; JSON.parse cannot preserve all of
    // those values. Reject loss-prone seeds before dispatch or provenance.
    if (request.items.some(item=>!item || !Number.isSafeInteger(item.seed) || item.seed<0))
      fail('Media seeds must be explicit nonnegative safe integers for exact host provenance.');
    typedReference(request.rights,'rights');
    const receiptFile=typedReference(request.installation), receipt=document(receiptFile,33554432);
    if (receipt.schemaVersion!=='bubo-media-installation/v1' || receipt.backend!==request.backend) fail('Installation belongs to another backend.');
    for (const name of ['modelDirectory','environmentRoot','pythonBaseRoot','wheelhouseRoot','noticeDirectory','nativeRuntimeRoot','sourceRoot'])
      if (receipt[name]!=null) installedPath(receipt[name]);
    for (const name of ['pythonArchive','sourceArchive']) if (receipt[name]!=null) installedPath(receipt[name],false);
    licenses(receipt.licenses);
    if (receipt.python) tool(receipt.python);
    if (receipt.nativeWorker) tool(receipt.nativeWorker);
    const output=scoped(request.outputDirectory);
    if (!runtime.within(staging,output)) fail('Requested media output must stay in workspace staging.');
    for (const item of request.items) if (item.voice?.reference) {
      const voice=item.voice.reference;
      for (const [name,kind] of [['audio','input'],['transcript','input'],['rights','rights'],['consent','consent']]) {
        if (!voice[name]) fail('Cloning requires all four typed local reference identities.');
        typedReference(voice[name],kind);
      }
      const consent=document(scoped(voice.consent.path));
      if (!consent.sourceEvidence) fail('Cloning consent must cite its existing source assertion.');
      typedReference(consent.sourceEvidence,'consent');
    }
    if (request.acceptance) {
      if (!options.has('media-state')) fail('Acceptance requires an explicitly retained --media-state root.');
      const approvalFile=typedReference(request.acceptance.approval,'policy'), approval=document(approvalFile);
      if (approval.schemaVersion!=='bubo-media-acceptance-budget/v1' || approval.maximumCandidates!==1 || approval.maximumRevisions!==1)
        fail('Acceptance requires its original bounded approval; the host never creates an allowance.');
      if (operation==='generate' && approval.sharedStateRoot!==mediaState)
        fail('Approval root differs from canonical execution root; preserve historical claims and refresh execution scope explicitly.');
      sharedBinding={schemaVersion:'hephaera-local-media-acceptance-root/v1',approvalSha256:request.acceptance.approval.sha256,mediaState};
      compareBinding(sharedPath(root,sharedBinding.approvalSha256),sharedBinding);
    }
  }
  if (options.has('platform-modules')) {
    const file=reference(options.get('platform-modules')), modules=document(file);
    if (modules.schemaVersion!=='hephaera-platform-modules/v1' || !Array.isArray(modules.modules) || modules.modules.length>64
        || Object.keys(modules).some(key=>!['schemaVersion','modules'].includes(key)))
      fail('Explicit bounded platform module manifest required.');
    for (const identity of modules.modules) {
      if (!identity || Object.keys(identity).some(key=>!['path','sha256'].includes(key))) fail('Exact platform module file identities required.');
      tool(identity,true,'platform-module');
    }
  }
  if (immutable.some(file=>[state,staging,mediaStateFull,bindingRoot].some(mutable=>overlap(file,mutable))))
    fail('Immutable dependencies overlap mutable media state or host policy bindings.');
  const inputs=[];
  if (info.folder && runtime.within(root,path.resolve(info.folder))) {
    const published=scoped(info.folder);
    if ([workspaceFull,state,mediaStateFull].some(value=>overlap(published,value))) fail('Workspace/state cannot overlap the Bubo dependency.');
    inputs.push(relative(published));
  }
  // Host-only purpose/consent assertions must survive native ownership waits.
  // These references add freshness requirements, never execution authority.
  for(const value of policyReferences){
    if(!value||Object.keys(value).sort().join(',')!=='path,sha256')fail('Exact internal policy identity required.');
    const file=scoped(value.path),rel=relative(file),key=process.platform==='win32'?rel.toLowerCase():rel;
    if([...tools.values()].some(tool=>runtime.samePath(tool.path,file)))fail('Policy evidence cannot alias an executable or module.');
    typedReference(value,references.get(key)?.kind||'policy');
  }
  const context={schemaVersion:'bubo-host-context/v1',projectRoot:root,task,
    roots:{state:stateRoot,staging:relative(staging),tools:[relative(toolsRoot),relative(downloads)],inputs,outputs:receiptOutput?[receiptOutput]:[],mediaState},
    policy,references:[...references.values()],tools:[...tools.values()],
    budgets:executionBudgets(options),
    permissions:{provisioning:operation==='setup'&&options.get('execute')==='true',promotion:false}};
  // Media CLI admission takes task ownership from the context/request, not a
  // --task argument (the shared CLI rejects that flag for media operations).
  const forwarded=new Map([['root',root],['manifest',relative(manifest)]]);
  for (const key of ['execute','load']) if (options.has(key)) forwarded.set(key,options.get(key));
  return {root,task,stateRoot,workspace,mediaState,context,options:forwarded,request,mediaFile,manifest:relative(manifest),sharedBinding};
}

function exportProvenance(prepared,result,info,dispatchDirectory) {
  const root=prepared.root, relative=file=>path.relative(root,file).split(path.sep).join('/');
  const dispatch=runtime.projectPath(root,dispatchDirectory);
  if (!runtime.within(runtime.projectPath(root,prepared.stateRoot),dispatch)) fail('Provenance dispatch must stay in task-owned state.');
  const native=result.data, request=prepared.request;
  if (result.schemaVersion!=='bubo-execution-result/v1' || result.apiVersion!==2
      || result.status!=='succeeded' || result.workflow!=='media' || result.operation!=='generate' || native?.status!=='generated-staged'
      || native.promotion!==false || native.humanReview!=='pending' || !Array.isArray(native.outputs) || native.outputs.length!==request.items.length)
    fail('Only successful staged native generation can produce host provenance.');
  const identity=file=>({path:relative(file),sha256:runtime.hash(file)});
  const buildReceiptFile=runtime.projectPath(info.root,info.pinned.buildReceipt);
  const buildReceipt=document(buildReceiptFile,8388608),buildBytes=fs.readFileSync(buildReceiptFile);
  if (buildReceipt.schemaVersion!=='bubo-build/v1' || buildReceipt.sourceRevision!==info.pinned.revision || buildReceipt.sourceDirty!==false
      || canonical(buildReceipt.capabilities?.build)!==canonical(info.capability?.build)
      || (info.receipt && canonical(buildReceipt)!==canonical(info.receipt)) || canonical(JSON.parse(buildBytes.toString('utf8')))!==canonical(buildReceipt))
    fail('Verified runtime source revision/build receipt changed before provenance publication.');
  const buildSnapshot=runtime.projectPath(root,path.join(dispatch,'source-build-info.json'));
  const sourceRevisionEvidence={path:relative(buildSnapshot),sha256:digest(buildBytes)};
  const resultFile=runtime.projectPath(root,path.join(dispatch,'result.json')), contextFile=runtime.projectPath(root,path.join(dispatch,'host-context.json'));
  if (canonical(document(resultFile,8388608))!==canonical(result)
      || canonical(document(contextFile,8388608))!==canonical(prepared.context)
      || runtime.hash(contextFile)!==result.hostContextSha256)
    fail('Native result/context ancestry differs from this dispatch.');
  if (!info.capability?.build || canonical(result.runtime)!==canonical(info.capability.build)
      || canonical(native.runtimeBuild)!==canonical(result.runtime)
      || native.backend!==request.backend || native.requestPath!==prepared.manifest)
    fail('Native runtime/backend/request ancestry differs.');
  const nativeFile=runtime.projectPath(root,prepared.stateRoot+'/media/'+request.requestId+'/manifest.json');
  if (canonical(document(nativeFile))!==canonical(native)) fail('Native manifest and returned generation result differ.');
  const source=runtime.projectPath(root,prepared.manifest);
  if (runtime.hash(source)!==native.requestSha256) fail('Source request changed before provenance publication.');
  const catalogFile=runtime.projectPath(info.folder,'resources/media/catalog.json');
  const catalogHash=info.catalog?.files?.['resources/media/catalog.json'];
  if (!SHA.test(catalogHash||'') || runtime.hash(catalogFile)!==catalogHash || native.catalogSha256!==catalogHash) fail('Pinned media catalog changed before provenance export.');
  const catalog=document(catalogFile);
  const catalogBytes=fs.readFileSync(catalogFile);
  if(digest(catalogBytes)!==catalogHash || canonical(JSON.parse(catalogBytes.toString('utf8')))!==canonical(catalog))
    fail('Pinned model catalogue changed during provenance preparation.');
  const catalogSnapshot=runtime.projectPath(root,path.join(dispatch,'source-media-catalog.json'));
  const modelCatalog={path:relative(catalogSnapshot),sha256:catalogHash};
  const definition=catalog.backends?.find(value=>value.id===request.backend);
  if (!definition || !Array.isArray(definition.files) || !definition.files.length) fail('Selected backend lacks pinned model provenance.');
  const modelFiles=definition.files.map(file=>({path:file.path,sha256:file.sha256,revision:file.revision,repository:file.repository}));
  const revisions=[...new Set(definition.files.map(file=>file.revision).filter(Boolean))];
  const notices=[...new Set(definition.files.map(file=>file.license).filter(Boolean))];
  const outputs=[], pending=[];
  for (let index=0; index<native.outputs.length; index++) {
    const output=native.outputs[index], item=request.items[index], file=runtime.projectPath(root,output.path);
    if (output.id!==item.id || !SHA.test(output.sha256||'') || !regular(file) || fs.statSync(file).size!==output.bytes
        || !runtime.within(runtime.projectPath(root,request.outputDirectory),file) || output.humanReview!=='pending' || output.promotion!==false)
      fail('Native staged output identity differs.');
    // Streaming integrity only: never decode, play, upload or reinterpret media.
    if (runtime.hash(file)!==output.sha256 || fs.statSync(file).size!==output.bytes) fail('Native staged output hash changed.');
    let settings=null;
    if (output.actual?.nativeMetadata) {
      const metadata=output.actual.nativeMetadata, selected=runtime.projectPath(root,metadata.path);
      if (!runtime.within(runtime.projectPath(root,request.outputDirectory),selected) || !regular(selected)
          || runtime.hash(selected)!==metadata.sha256 || path.extname(selected)!=='.json') fail('Native settings ancestry changed.');
      settings=metadata;
    }
    const manifest={schemaVersion:1,runId:request.requestId+'-'+index,createdAt:native.completedAt||new Date().toISOString(),
      backend:{kind:'local',provider:'Bubo',capability:request.backend,toolVersion:info.pinned.revision},
      modality:item.voice?'voice':item.music?'music':output.sampleRate?'sfx':'image',
      model:{name:request.backend,revision:revisions.join(';')||unavailable('No single revision disclosed.'),digest:digest(canonical(modelFiles)),
        license:notices.join(';')||unavailable('See pinned installation license evidence.')},
      workflow:{name:request.backend,revision:info.pinned.revision,digest:native.workerSourceSha256||unavailable('Native manifest does not disclose a worker source digest.')},
      generation:{prompt:item.prompt,negativePrompt:item.negativePrompt||unavailable('No negative prompt selected.'),seed:item.seed,
        parameters:{requested:item,actual:output.actual,nativeManifest:identity(nativeFile),nativeResult:identity(resultFile),
          hostContext:identity(contextFile),nativeSettings:settings,sourceRequest:identity(source),
          installation:request.installation,rights:request.rights,acceptanceClaim:native.acceptanceClaim||null,modelCatalog,
          runtime:{revision:info.pinned.revision,resourceCatalogSha256:info.pinned.resourceCatalogSha256,build:result.runtime,sourceRevisionEvidence},
          execution:native.actualSettings,timing:native.timing,cleanup:native.cleanup}},
      inputs:[{description:item.voice?.reference?'Authorized local voice reference and supplied transcript':'Authorized prompt and generation inputs',
        source:item.voice?.reference?.audio.path||request.rights.path,rights:'sha256:'+request.rights.sha256,consent:item.voice?.reference?'confirmed':'not-applicable'}],
      outputs:[{stagedPath:output.path,sha256:output.sha256,status:'staged',runtimeTarget:unavailable('No runtime promotion selected.')}],
      runtime:{destination:unavailable('No runtime promotion selected.'),budgets:request.budget},
      review:{status:'pending',reviewer:unavailable('Human review remains separate.'),reviewedAt:unavailable('No human review recorded by generation.'),
        notes:'Private task-local provenance. Validate project-relative output paths with --project-root. Generation grants no promotion or audio disclosure.'}};
    const destination=runtime.projectPath(root,path.join(dispatch,String(index).padStart(3,'0')+'.media-generation.json'));
    pending.push({destination,manifest});
  }
  // Validate every output and all ancestry before publishing any neutral row.
  fs.writeFileSync(buildSnapshot,buildBytes,{flag:'wx'});
  fs.writeFileSync(catalogSnapshot,catalogBytes,{flag:'wx'});
  for (const {destination,manifest} of pending) {
    fs.writeFileSync(destination,JSON.stringify(manifest,null,2)+'\n',{flag:'wx'}); outputs.push(relative(destination));
  }
  return outputs;
}

async function invoke(operation,options,{emit=true,policyReferences=[]}={}) {
  if (typeof emit!=='boolean') fail('Media result emission must be explicitly boolean.');
  const started=performance.now(), info=runtime.verified(), admitted=performance.now();
  const prepared=contextFor(operation,options,info,{policyReferences});
  prepared.timings={runtimeAdmissionMilliseconds:admitted-started,hostPolicyMilliseconds:performance.now()-admitted};
  const binding=bindSharedState(prepared);
  if (binding) prepared.context.references.push({path:path.relative(prepared.root,binding).split(path.sep).join('/'),sha256:runtime.hash(binding),kind:'policy'});
  const dispatchRoot=prepared.stateRoot+'/dispatch/'+crypto.randomUUID();
  const result=await host.execute('media',operation,prepared.options,{...prepared,stateRoot:dispatchRoot},info,false);
  if (result.workflow!=='media' || result.operation!==operation) fail('Bubo result names another workflow or operation.');
  let provenance=[];
  if (operation==='generate') {
    const directory=runtime.projectPath(prepared.root,dispatchRoot+'/bubo-host');
    const entries=fs.readdirSync(directory);
    if (entries.length!==1) fail('Ambiguous owned media dispatch receipt.');
    provenance=exportProvenance(prepared,result,info,path.join(directory,entries[0]));
  }
  if (emit) console.log(JSON.stringify({...result.data,hostMediaProvenance:provenance}));
  return {...result,hostMediaProvenance:provenance};
}

module.exports={parse,contextFor,invoke,validateMedia,bindSharedState,exportProvenance,executionBudgets};
if (require.main===module) {
  const [operation,...values]=process.argv.slice(2);
  if (!operation || ['help','--help','-h'].includes(operation) || values.includes('--help'))
    console.log('bubo-media <setup|inspect|generate> --root ROOT --task ID --manifest JSON [--workspace PROJECT_CACHE_CHILD] [--media-state PROJECT_CACHE_CHILD] [--media FILE] [--selection JSON] [--platform-modules JSON] [--timeout SECONDS] [--max-log-bytes BYTES] [--max-private-bytes BYTES] [--execute] [--load true]\nSetup is dry-run unless --execute is selected. Inspection never loads models unless --load true is selected. Generation grants no promotion, installation, license acceptance or public audio disclosure.');
  else Promise.resolve().then(()=>invoke(operation,parse(values))).catch(error=>{console.error(error.message);process.exitCode=1;});
}
