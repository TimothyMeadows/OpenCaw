'use strict';

// Host lifecycle only. Bubo owns synthesis, setup, native leases and attempts.
// These cooperative guards do not provide a hostile-filesystem sandbox.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const runtime = require('./bubo-runtime.cjs');
const host = require('./bubo-host-adapter.cjs');
const contracts = require('./media-pipeline-contract.cjs');
const engines = require('./engine-contract.cjs');
const CACHE = '.hephaera/.cache', ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/, SHA = /^[a-f0-9]{64}$/;
const fail = message => { throw new Error(message); };
const canonical = value => JSON.stringify(runtime.canonical(value));
const digest = value => crypto.createHash('sha256').update(typeof value === 'string' ? value : canonical(value)).digest('hex');
const text = (value, label, maximum = 256) => {
  if (typeof value !== 'string' || !value.trim() || value.length > maximum || /[\x00-\x1f]/.test(value)) fail('Invalid ' + label + '.');
  return value;
};
const identifier = (value, label) => { text(value, label, 80); if (!ID.test(value) || value === '.' || value === '..') fail('Invalid ' + label + '.'); return value; };
const relative = (root, file) => path.relative(root, file).split(path.sep).join('/');
function project(value) {
  if (!value) fail('Explicit resolved project root is required.');
  runtime.syntax(runtime.native(value)); const root = path.resolve(runtime.native(value)); runtime.components(root);
  if (!fs.statSync(root).isDirectory()) fail('Project root must be a real directory.');
  return root;
}
function document(root, name) {
  const file = runtime.projectPath(root, name);
  if (!fs.statSync(file).isFile() || fs.statSync(file).size > 1048576) fail('Missing or oversized lifecycle JSON.');
  const value = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('Lifecycle JSON must be an object.');
  return value;
}
function identity(root, value) {
  const name = typeof value === 'string' ? value : value?.path;
  const file = runtime.projectPath(root, name);
  if (!fs.statSync(file).isFile()) fail('Lifecycle reference must be a regular file.');
  const result = {path:relative(root, file), sha256:runtime.hash(file)};
  if (typeof value !== 'string' && (!SHA.test(value?.sha256 || '') || value.path !== result.path || value.sha256 !== result.sha256))
    fail('Lifecycle reference is noncanonical or changed.');
  return result;
}
function equal(left, right, message) { if (canonical(left) !== canonical(right)) fail(message); }
function typedReferences(root,value,mapper) {
  if (mapper!==undefined && typeof mapper!=='function') fail('Typed evidence mapper must be a trusted function.');
  const found=new Map(); let nodes=0;
  function visit(item,depth=0,trail=[]) {
    if (++nodes>8192 || depth>32) fail('Typed evidence nesting bound exceeded.');
    if (Array.isArray(item)) { for (const [index,child] of item.entries()) visit(child,depth+1,[...trail,index]); return; }
    if (!item || typeof item!=='object') return;
    if (typeof item.path==='string' && Object.hasOwn(item,'sha256')) {
      // A compiled domain may resolve documented historical reference fields.
      // Raw input bytes and declared hashes remain immutable; every mapped
      // identity still passes the normal project confinement/hash guard.
      const original={path:item.path,sha256:item.sha256};
      const mapped=mapper?mapper({...original},[...trail]):original;
      if (!mapped || mapped.sha256!==original.sha256) fail('Typed evidence mapping must preserve the declared hash.');
      const ref=identity(root,mapped);found.set(ref.path,ref);
      if (found.size>128) fail('Typed evidence reference bound exceeded.');
    }
    for (const [key,child] of Object.entries(item)) visit(child,depth+1,[...trail,key]);
  }
  visit(value);return [...found.values()];
}
function put(root, name, value) {
  const file = runtime.projectPath(root, name), encoded = JSON.stringify(value, null, 2) + '\n';
  if (Buffer.byteLength(encoded) > 1048576) fail('Lifecycle record exceeds the size bound.');
  fs.mkdirSync(path.dirname(file), {recursive:true}); runtime.components(file);
  const fd = fs.openSync(file, 'wx');
  try { fs.writeFileSync(fd, encoded); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  return identity(root, relative(root, file));
}
function nativeId({task, domain, asset, version}) {
  identifier(task, 'task'); text(asset, 'asset'); identifier(version, 'version');
  if (!['AUDIO','MUSIC','VOICE'].includes(domain)) fail('Unsupported media domain.');
  return domain.toLowerCase() + '-' + digest({task,domain,asset,version});
}
function statePath({task, domain, asset, version}) {
  nativeId({task,domain,asset,version});
  return `${CACHE}/tasks/${task}/media/${domain.toLowerCase()}/${digest(asset)}/${version}/asset.json`;
}
function lock(root, directory, action) {
  const folder = runtime.projectPath(root, directory); fs.mkdirSync(folder, {recursive:true}); runtime.components(folder);
  const file = runtime.projectPath(root, directory + '/.write-lock');
  let fd;
  try { fd = fs.openSync(file, 'wx'); } catch (error) { if (error.code === 'EEXIST') fail('Lifecycle write is already owned; inspect its lock before recovery.'); throw error; }
  try { return action(); } finally { fs.closeSync(fd); fs.unlinkSync(file); }
}
function init(options) {
  const root = project(options.root), task = identifier(options.task,'task');
  const selection={contract:options.contract || undefined,media:options.media || undefined};
  const context = contracts.resolve({root,domain:options.domain,modality:options.modality,...selection});
  if (!context.configured) fail('Configure the selected domain contract before initializing an asset.');
  const domain = context.domain, asset = text(options.asset,'asset'), version = identifier(options.version,'version');
  if (!context.modality) fail('An explicit supported modality is required for an asset.');
  identity(root, `${CACHE}/tasks/${task}/TASK.md`);
  const brief = identity(root, options.brief), briefValue=document(root,brief.path);
  const references = [...new Map([...(options.references || []).map(value => identity(root,value)),...typedReferences(root,briefValue,options.referenceMapper)].map(ref=>[ref.path,ref])).values()];
  if (references.length > 128) fail('Too many asset references.');
  const parent = options.parent ? identity(root,options.parent) : null;
  if (parent) {
    const prior = load({root,stateFile:parent.path});
    if (prior.asset.task !== task || prior.asset.domain !== domain || prior.asset.asset !== asset || prior.asset.version === version)
      fail('A revision must reference the same task/domain/asset and a different version.');
  }
  const stateFile = statePath({task,domain,asset,version}), directory = path.posix.dirname(stateFile);
  const staging=runtime.projectPath(root,options.stagingRoot || '.art-staging/media/'+domain.toLowerCase());
  if ([runtime.projectPath(root,'assets'),runtime.projectPath(root,directory)].some(scope=>runtime.within(scope,staging)||runtime.within(staging,scope)))
    fail('Non-runtime staging must not overlap assets or lifecycle state.');
  const assetRecord = {schemaVersion:'hephaera-media-asset/v1',task,domain,modality:context.modality,asset,version,
    nativeRequestId:nativeId({task,domain,asset,version}),policySha256:context.policySha256,
    stagingRoot:relative(root,staging),selection,brief,references,parent,createdAt:new Date().toISOString()};
  lock(root,directory,() => put(root,stateFile,assetRecord));
  return {stateFile,asset:assetRecord};
}
function load(options) {
  const root = project(options.root), ref = identity(root,options.stateFile), asset = document(root,ref.path);
  if (asset.schemaVersion !== 'hephaera-media-asset/v1' || !SHA.test(asset.policySha256 || '')
      || statePath(asset) !== ref.path || nativeId(asset) !== asset.nativeRequestId) fail('Invalid asset identity or state ownership.');
  const directory = path.posix.dirname(ref.path), eventsDirectory = runtime.projectPath(root,directory+'/events');
  const events = []; let previous = null;
  if (fs.existsSync(eventsDirectory)) {
    if (!fs.statSync(eventsDirectory).isDirectory()) fail('Lifecycle events must be a directory.');
    const files = fs.readdirSync(eventsDirectory).sort();
    if (files.length > 4096) fail('Lifecycle event bound exceeded.');
    for (let index=0;index<files.length;index++) {
      const expected = String(index+1).padStart(6,'0')+'.json';
      if (files[index] !== expected) fail('Incomplete or unexpected lifecycle event; inspect retained state.');
      const name = directory+'/events/'+files[index], event = document(root,name);
      if (event.schemaVersion !== 'hephaera-media-event/v1' || event.sequence !== index+1 || event.assetSha256 !== ref.sha256
          || event.previousSha256 !== previous || !['dispatch-started','dispatch-failed','dispatch-returned','candidate','technical','review','promotion-started','promotion-completed','promotion-failed'].includes(event.kind))
        fail('Lifecycle event chain or asset identity changed.');
      previous = identity(root,name).sha256; events.push(event);
    }
  }
  return {root,stateFile:ref.path,identity:ref,asset,directory,events};
}
const latest = (state,kind,predicate=()=>true) => [...state.events].reverse().find(event=>event.kind===kind && predicate(event.data));
function observe(state) {
  const {root,asset} = state, stale = [];
  let context = null;
  try {
    context = contracts.resolve({root,domain:asset.domain,modality:asset.modality,...asset.selection});
    if (!context.configured || context.policySha256 !== asset.policySha256) stale.push('domain-or-shared-policy-changed');
  } catch { stale.push('domain-or-shared-policy-invalid'); }
  for (const ref of [asset.brief,...asset.references,...(asset.parent?[asset.parent]:[])]) {
    try { identity(root,ref); } catch { stale.push('input-changed'); }
  }
  const candidate = latest(state,'candidate');
  if (candidate) for (const ref of [...(candidate.data.manifests || [candidate.data.manifest]),...candidate.data.outputs,...(candidate.data.references || [])]) {
    try { identity(root,ref); } catch { stale.push('candidate-or-provenance-changed'); }
  }
  for (const event of state.events.filter(value=>['technical','review'].includes(value.kind))) {
    try { identity(root,event.data.evidence); if (event.data.sourceEvidence) identity(root,event.data.sourceEvidence); for (const ref of event.data.references || []) identity(root,ref); }
    catch { stale.push('review-or-technical-evidence-changed'); }
  }
  for (const event of state.events.filter(value=>value.data.request)) {
    try { identity(root,event.data.request); for (const ref of [...(event.data.provenance || []),...(event.data.controlReferences || [])]) identity(root,ref); }
    catch { stale.push('native-request-or-returned-provenance-changed'); }
  }
  const promoted=latest(state,'promotion-completed');
  for(const ref of latest(state,'dispatch-started')?.data.policyReferences||[]){
    try{identity(root,ref);}catch{stale.push('dispatch-policy-changed');}
  }
  if (promoted) for (const ref of promoted.data.runtimeOutputs || []) {
    try { identity(root,ref); } catch { stale.push('promoted-output-changed'); }
  }
  if (promoted) {
    try {
      const directory=runtime.projectPath(root,promoted.data.runtimeDirectory);
      equal(fs.readdirSync(directory).sort(),promoted.data.runtimeOutputs.map(ref=>path.posix.basename(ref.path)).sort(),'Promoted directory contents changed.');
    } catch { stale.push('promoted-directory-changed'); }
  }
  const fingerprint = digest({assetSha256:state.identity.sha256,policySha256:context?.policySha256 || null,candidate:candidate?.data || null});
  return {context,stale:[...new Set(stale)],candidate,fingerprint};
}
function fresh(state) {
  const observed = observe(state);
  if (observed.stale.length) fail('Asset version is stale: '+observed.stale.join(', ')+'. Initialize a new version with retained ancestry.');
  return observed;
}
function append(state,kind,data) {
  const previous = state.events.length ? identity(state.root,state.directory+'/events/'+String(state.events.length).padStart(6,'0')+'.json').sha256 : null;
  const sequence = state.events.length+1;
  const record = {schemaVersion:'hephaera-media-event/v1',sequence,assetSha256:state.identity.sha256,previousSha256:previous,kind,data,recordedAt:new Date().toISOString()};
  put(state.root,state.directory+'/events/'+String(sequence).padStart(6,'0')+'.json',record);
  state.events.push(record);
  return record;
}
function mutate(options,action) {
  const initial = load(options);
  return lock(initial.root,initial.directory,() => { const state=load(options); return action(state,fresh(state)); });
}
function status(options) {
  const state = load(options), observed = observe(state), content = latest(state,'review',data=>data.kind==='content');
  const technical = latest(state,'technical'), promoted=latest(state,'promotion-completed');
  const promotionStarted=latest(state,'promotion-started'),promotionFailed=latest(state,'promotion-failed');
  return {schemaVersion:1,stateFile:state.stateFile,domain:state.asset.domain,modality:state.asset.modality,
    asset:state.asset.asset,version:state.asset.version,nativeRequestId:state.asset.nativeRequestId,
    assetSha256:observed.fingerprint,configured:observed.context?.configured || false,
    executionAvailable:observed.context?.executionAvailable || false,stale:observed.stale,
    stage:observed.stale.length?'stale':promoted?'promoted':observed.candidate?'staged':latest(state,'dispatch-started')?'dispatch-recorded':'planned',
    executionOrigin:observed.candidate?.data.origin || null,sourceRunIds:observed.candidate?.data.sourceRunIds || [],
    nativeDispatchRequestId:latest(state,'dispatch-started')?state.asset.nativeRequestId:null,
    technical:observed.stale.length && technical?'stale':technical?.data.status || 'pending',
    contentReview:observed.stale.length && content?'stale':content?.data.verdict || 'pending',
    promotionState:observed.stale.length && promotionStarted?'stale':promoted?'completed':promotionStarted?'recovery-required':'not-started',
    promotionNeedsRecovery:Boolean(promotionStarted && !promoted),
    publicationObserved:Boolean(promoted || promotionFailed?.data.published),
    eventCount:state.events.length,promotion:Boolean(promoted && !observed.stale.length)};
}
function cacheChild(root,name,label) {
  const full=runtime.projectPath(root,name), cache=runtime.projectPath(root,CACHE);
  if (!runtime.within(cache,full) || runtime.samePath(cache,full)) fail(label+' must be a confined cache child.');
  return relative(root,full);
}
function nativeRequest(options) {
  const state=load(options), observed=fresh(state), {root,asset}=state;
  if (observed.candidate) fail('This version already owns an imported or generated candidate; initialize a new version instead of starting another attempt.');
  if (options.provider !== 'LOCAL') fail('Native dispatch requires explicit LOCAL; CLOUD import is separate and never falls back.');
  if (!observed.context.media) fail('Shared MEDIA policy is required before dispatch preparation.');
  require('./bubo-media-adapter.cjs').validateMedia(runtime.projectPath(root,observed.context.media.path));
  const workspace=cacheChild(root,options.workspace,'Workspace'), mediaState=cacheChild(root,options.mediaState,'Shared media state');
  const request=JSON.parse(JSON.stringify(options.request));
  if (!request || request.schemaVersion !== 'bubo-media-request/v1' || !Array.isArray(request.items) || !request.items.length) fail('A supported native request is required.');
  if ((request.requestId && request.requestId !== asset.nativeRequestId) || (request.task && request.task !== asset.task)) fail('Native task/request identity is owned by this asset version.');
  const outputDirectory=workspace+'/staging/'+asset.domain.toLowerCase();
  if (request.outputDirectory && request.outputDirectory !== outputDirectory) fail('Native output base is owned by this domain.');
  const expected=asset.domain==='AUDIO'?'sfx':asset.domain==='MUSIC'?'music':'voice';
  for (const item of request.items) {
    const modality=item.voice?'voice':item.music?'music':'sfx';
    if (modality!==expected || (item.voice && item.music)) fail('Native item conflicts with the asset domain.');
  }
  const finalOutput=runtime.projectPath(root,outputDirectory+'/'+asset.nativeRequestId);
  if (!runtime.within(runtime.projectPath(root,asset.stagingRoot),finalOutput)) fail('Native output is outside this version\'s declared non-runtime staging.');
  const nativeState=runtime.projectPath(root,`${CACHE}/tasks/${asset.task}/bubo-media/media/${asset.nativeRequestId}`);
  for (const selected of [workspace,mediaState]) {
    const full=runtime.projectPath(root,selected), domainState=runtime.projectPath(root,state.directory);
    if (runtime.within(domainState,full) || runtime.within(full,domainState)) fail('Host lifecycle state cannot overlap workspace or shared ledger.');
  }
  if (fs.existsSync(finalOutput) || fs.existsSync(nativeState) || latest(state,'dispatch-started')) fail('This immutable native attempt already exists or started; recover retained evidence instead of rerunning.');
  return {request:{...request,requestId:asset.nativeRequestId,task:asset.task,outputDirectory},workspace,mediaState,
    finalOutput:relative(root,finalOutput),nativeState:relative(root,nativeState),media:observed.context.media.path};
}
async function dispatch(options) {
  if (Object.keys(options).some(key=>!['root','stateFile','provider','request','workspace','mediaState','controls','policyReferences'].includes(key))) fail('Unknown or protected dispatch option; use the documented controls whitelist.');
  const controls=options.controls || {};
  if (typeof controls!=='object' || Array.isArray(controls)
      || Object.keys(controls).some(key=>!['timeout','max-log-bytes','max-private-bytes','platform-modules'].includes(key))) fail('Unknown or protected dispatch control.');
  const adapter=require('./bubo-media-adapter.cjs'), controlArguments=[];
  for (const [key,value] of Object.entries(controls)) {
    if (typeof value!=='string' && typeof value!=='number') fail('Dispatch controls require explicit scalar values.');
    controlArguments.push('--'+key,String(value));
  }
  const parsedControls=adapter.parse(controlArguments), budgets=adapter.executionBudgets(parsedControls);
  const initial=load(options), context=fresh(initial).context;
  const suppliedPolicies=options.policyReferences||[];
  if(!Array.isArray(suppliedPolicies)||suppliedPolicies.length>128)fail('Bounded domain generation policy identities are required.');
  const policyInputs=[initial.identity,initial.asset.brief,...initial.asset.references,
    ...(context.contract?[context.contract]:[]),...(context.media?[context.media]:[]),...suppliedPolicies];
  for(const [name,sha256] of [[context.definition?.declaration,context.definition?.declarationSha256],
      [context.definition?.template,context.definition?.templateSha256]]){
    if(name){const file=path.join(runtime.BASE,'.media/pipelines',name);if(runtime.within(initial.root,file))policyInputs.push({path:relative(initial.root,file),sha256});}
  }
  if(context.entryPoint){const file=path.join(runtime.BASE,context.entryPoint.path);if(runtime.within(initial.root,file))policyInputs.push({path:relative(initial.root,file),sha256:context.entryPoint.sha256});}
  const policyReferences=[...new Map(policyInputs.map(ref=>{const value=identity(initial.root,ref);return [process.platform==='win32'?value.path.toLowerCase():value.path,value];})).values()];
  if(policyReferences.length>256)fail('Combined generation policy reference bound exceeded.');
  const controlReferences=controls['platform-modules']?[identity(initial.root,controls['platform-modules'])]:[];
  if (!context.executionAvailable) fail('Selected domain execution is unavailable; its domain workflow is not implemented.');
  const prepared=nativeRequest(options);
  let manifest;
  mutate(options,(state)=>{
    if (latest(state,'dispatch-started')) fail('This version already started dispatch.');
    manifest=state.directory+'/native-request.json';put(state.root,manifest,prepared.request);
    append(state,'dispatch-started',{request:identity(state.root,manifest),provider:'LOCAL',workspace:prepared.workspace,mediaState:prepared.mediaState,
      controls,budgets,controlReferences,policyReferences});
  });
  try {
    const result=await adapter.invoke('generate',adapter.parse(['--root',initial.root,'--task',initial.asset.task,'--manifest',manifest,
      '--workspace',prepared.workspace,'--media-state',prepared.mediaState,'--media',prepared.media,...controlArguments]),{emit:false,policyReferences});
    if (result.status!=='succeeded' || !Array.isArray(result.hostMediaProvenance) || !result.hostMediaProvenance.length)
      fail('Successful native dispatch requires complete retained host provenance.');
    mutate(options,state=>append(state,'dispatch-returned',{request:identity(state.root,manifest),status:result.status,
      provenance:result.hostMediaProvenance.map(file=>identity(state.root,file))}));
    return result;
  } catch (error) {
    // Keep the started event even when later evidence publication fails. No retry or claim reset.
    try { mutate(options,state=>append(state,'dispatch-failed',{reason:'Native dispatch or host evidence publication failed; inspect private retained receipts.'})); } catch { /* The retained start still prevents a fresh attempt. */ }
    throw error;
  }
}
function recordCandidate(options) {
  return mutate(options,(state,observed)=>{
    if (latest(state,'candidate')) fail('Candidate already exists; initialize a new version for replacement.');
    if (!['LOCAL','CLOUD'].includes(options.provider)) fail('Explicit candidate provider is required.');
    if (!observed.context.media) fail('Shared MEDIA policy is required for candidate import.');
    host.policyCommand('validate-media-contract.sh',[runtime.projectPath(state.root,observed.context.media.path)],state.root,false);
    if (options.provider==='LOCAL') require('./bubo-media-adapter.cjs').validateMedia(runtime.projectPath(state.root,observed.context.media.path));
    const names=options.manifests || [options.manifest];
    if (!Array.isArray(names) || !names.length || names.length>128) fail('A bounded complete candidate provenance set is required.');
    const manifests=names.map(name=>identity(state.root,name));
    const started=latest(state,'dispatch-started'), returned=latest(state,'dispatch-returned');
    let origin=options.origin || 'external-import';
    if (started) {
      if (options.provider!==started.data.provider) fail('A started native run cannot switch candidate provider.');
      if (!returned || returned.data.status!=='succeeded') fail('Recover successful native provenance before importing a started run.');
      equal(manifests,returned.data.provenance,'Candidate provenance does not belong to this exact completed native dispatch.');
      origin='native-dispatch';
    } else if (options.provider==='LOCAL' && !['historical-import','external-import'].includes(options.origin))
      fail('LOCAL import without this version\'s dispatch requires explicit historical-import or external-import origin.');
    else if (!['historical-import','external-import'].includes(origin)) fail('Unsupported candidate import origin.');
    const expected=state.asset.domain==='AUDIO'?'sfx':state.asset.domain==='MUSIC'?'music':'voice';
    const outputs=[], references=[], sourceRunIds=[];
    for (const manifest of manifests) {
      const value=document(state.root,manifest.path);
      // Reuse the existing provider-neutral validator; no parallel manifest schema.
      host.policyCommand('validate-media-generation-manifest.sh',['--project-root',state.root,runtime.projectPath(state.root,manifest.path)],state.root,false);
      if (value.modality!==expected || value.backend?.kind!==(options.provider==='LOCAL'?'local':'cloud-session')) fail('Candidate domain/provider differs from this asset.');
      if (started) {
        if (!value.runId.startsWith(state.asset.nativeRequestId+'-')) fail('Native candidate names another run identity.');
        equal(value.generation.parameters.sourceRequest,started.data.request,'Native candidate names a different source request.');
      }
      sourceRunIds.push(value.runId);references.push(...typedReferences(state.root,value,options.referenceMapper));
      for (const output of value.outputs) {
        if (output.status!=='staged') fail('Only unpromoted staged outputs can be imported.');
        const ref=identity(state.root,{path:output.stagedPath,sha256:output.sha256}), file=runtime.projectPath(state.root,ref.path);
        if (!runtime.within(runtime.projectPath(state.root,state.asset.stagingRoot),file)) fail('Candidate bytes require this version\'s declared non-runtime staging.');
        if (started && !runtime.within(runtime.projectPath(state.root,started.data.workspace+'/staging/'+state.asset.domain.toLowerCase()+'/'+state.asset.nativeRequestId),file))
          fail('Native candidate output belongs to another asset version.');
        outputs.push(ref);
      }
    }
    if (!outputs.length || outputs.length>128 || new Set(outputs.map(value=>value.path.toLowerCase())).size!==outputs.length) fail('Invalid candidate output set.');
    return append(state,'candidate',{manifest:manifests[0],manifests,outputs,references:[...new Map(references.map(ref=>[ref.path,ref])).values()],
      sourceRunIds,origin,provider:options.provider,review:'pending'});
  });
}
function evidence(state,observed,name,schema) {
  if (!observed.candidate) fail('A staged candidate is required.');
  const ref=identity(state.root,name), value=document(state.root,ref.path);
  if (value.schemaVersion!==schema || value.assetSha256!==observed.fingerprint) fail('Evidence names a different candidate or policy version.');
  equal(value.outputs,observed.candidate.data.outputs,'Evidence must bind every exact current output.');
  return {ref,value};
}
function recordTechnical(options) {
  return mutate(options,(state,observed)=>{
    const {ref,value}=evidence(state,observed,options.report,'hephaera-media-technical/v1');
    if (!['passed','failed'].includes(value.status) || !Array.isArray(value.checks) || !value.checks.length
        || value.checks.some(check=>!check || !['passed','failed','unavailable'].includes(check.status) || !text(check.id,'check ID') || !text(check.reason,'check reason',4096))
        || (value.status==='passed' && value.checks.some(check=>check.status!=='passed'))) fail('Technical evidence needs explicit honest check verdicts and reasons.');
    return append(state,'technical',{evidence:ref,references:typedReferences(state.root,value),status:value.status,assetSha256:observed.fingerprint});
  });
}
function engineIdentity(root) {
  const selected=engines.resolve(root);
  return {engine:selected.effectiveEngine,sha256:digest({engine:selected.effectiveEngine,contractSha256:selected.contractSha256,
    definitionSha256:selected.definitionSha256,registrySha256:selected.registrySha256})};
}
function recordReview(options) {
  return mutate(options,(state,observed)=>{
    const {ref,value}=evidence(state,observed,options.review,'hephaera-media-review/v1');
    if (!['content','runtime'].includes(value.kind) || !['accepted','rejected'].includes(value.verdict)) fail('Explicit review kind and verdict required.');
    text(value.reviewer,'reviewer');text(value.reason,'review reason',4096);
    const sourceEvidence=identity(state.root,value.sourceEvidence);
    if (sourceEvidence.path===ref.path) fail('Review cannot cite itself as human source evidence.');
    if (value.kind==='runtime') equal(value.engine,engineIdentity(state.root),'Runtime review must bind the current selected engine identity.');
    return append(state,'review',{evidence:ref,sourceEvidence,references:typedReferences(state.root,value),kind:value.kind,verdict:value.verdict,assetSha256:observed.fingerprint});
  });
}
function accepted(state,observed,kind) {
  const event=latest(state,kind==='technical'?'technical':'review',data=>kind==='technical'||data.kind===kind);
  if (!event || event.data.assetSha256!==observed.fingerprint || (kind==='technical'?event.data.status!=='passed':event.data.verdict!=='accepted')) fail('Current '+kind+' acceptance is required.');
  return document(state.root,event.data.evidence.path);
}
function admitHandoff(options) {
  const state=load(options), observed=fresh(state), technical=accepted(state,observed,'technical');
  accepted(state,observed,'content');
  const review=accepted(state,observed,'runtime'), engine=engineIdentity(state.root);
  equal(review.engine,engine,'Runtime acceptance is stale for the current selected engine.');
  const target=review.target;
  if (!target || !Array.isArray(target.sampleRates) || !target.sampleRates.length || !Array.isArray(target.channels) || !target.channels.length
      || !Array.isArray(target.codecs) || !target.codecs.length || !Number.isFinite(target.maxOutputBytes) || target.maxOutputBytes<=0
      || !Number.isFinite(target.maxAudioSeconds) || target.maxAudioSeconds<=0) fail('Explicit target codec/rate/channel/duration/byte budgets are required.');
  if (!Number.isSafeInteger(target.maxOutputBytes)
      || target.sampleRates.some(rate=>!Number.isSafeInteger(rate)||rate<=0)
      || target.channels.some(channels=>!Number.isSafeInteger(channels)||channels<=0)
      || target.codecs.some(codec=>!['wav','ogg','mp3','flac','opus','m4a','webm','aiff'].includes(codec))) fail('Target format/budgets contain unsupported or invalid values.');
  const destination=runtime.projectPath(state.root,target.directory), assets=runtime.projectPath(state.root,'assets');
  if(target.directory!==relative(state.root,destination))fail('Runtime destination requires a canonical project-relative slash path.');
  if (!runtime.within(assets,destination) || runtime.samePath(assets,destination)) fail('Runtime destination must be a scoped assets child.');
  if (fs.existsSync(destination)) {
    const started=latest(state,'promotion-started');
    if (options._promotionRecovery!==true || !started || started.data.assetSha256!==observed.fingerprint
        || canonical(started.data.target)!==canonical(target)) fail('Runtime destination already exists; overwriting is not authorized.');
  }
  if (!Array.isArray(technical.measurements) || technical.measurements.length!==observed.candidate.data.outputs.length) fail('Actual output measurements are required for runtime admission.');
  let totalBytes=0,totalSeconds=0;
  for (const [index,output] of observed.candidate.data.outputs.entries()) {
    const measurement=technical.measurements[index], file=runtime.projectPath(state.root,output.path);
    if (measurement?.path!==output.path || measurement.sha256!==output.sha256 || measurement.bytes!==fs.statSync(file).size
        || !Number.isFinite(measurement.durationSeconds) || measurement.durationSeconds<=0
        || !target.sampleRates.includes(measurement.sampleRate) || !target.channels.includes(measurement.channels)
        || !target.codecs.includes(path.extname(file).slice(1).toLowerCase())) fail('Measured candidate does not satisfy target format/budgets.');
    totalBytes+=measurement.bytes;totalSeconds+=measurement.durationSeconds;
  }
  if (totalBytes>target.maxOutputBytes || totalSeconds>target.maxAudioSeconds) fail('Candidate exceeds target byte or duration budget.');
  return {schemaVersion:'hephaera-media-handoff/v1',assetSha256:observed.fingerprint,engine,target,
    outputs:observed.candidate.data.outputs,promotion:false};
}
function admitPromotion(options) {
  const plan=admitHandoff(options), root=project(options.root), authorization=identity(root,options.authorization), value=document(root,authorization.path);
  if (value.schemaVersion!=='hephaera-media-promotion/v1' || value.authorized!==true || value.assetSha256!==plan.assetSha256)
    fail('Explicit current asset promotion authorization is required.');
  equal(value.target,plan.target,'Promotion authorization names a different runtime target.');
  equal(value.outputs,plan.outputs,'Promotion authorization names different staged outputs.');
  text(value.authorizedBy,'promotion authorizer');text(value.reason,'promotion reason',4096);
  if (!value.sourceEvidence || typeof value.sourceEvidence!=='object' || !SHA.test(value.sourceEvidence.sha256 || '')) fail('Promotion source evidence requires an exact typed identity.');
  const sourceEvidence=identity(root,value.sourceEvidence);
  if (sourceEvidence.path===authorization.path) fail('Promotion cannot cite itself as authorization evidence.');
  // Foundation supplies admission only. Domain workflows own explicit atomic copying.
  return {...plan,authorization,sourceEvidence,promotion:false,admitted:true};
}
function promotionTransaction(options,action) {
  return mutate(options,(state)=>{
    const plan=admitPromotion({...options,_promotionRecovery:true});
    return action({state,plan,
      revalidate:()=>admitPromotion({...options,_promotionRecovery:true}),
      record:(kind,data)=>{
        if (!['promotion-started','promotion-completed','promotion-failed'].includes(kind)) fail('Unsupported promotion event.');
        return append(state,kind,{...data,assetSha256:plan.assetSha256,authorization:plan.authorization,
          sourceEvidence:plan.sourceEvidence,target:plan.target,outputs:plan.outputs});
      }});
  });
}
module.exports={init,load,status,nativeId,statePath,nativeRequest,dispatch,recordCandidate,recordTechnical,recordReview,
  admitHandoff,admitPromotion,engineIdentity,identity,promotionTransaction};
