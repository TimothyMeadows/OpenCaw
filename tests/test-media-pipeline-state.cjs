'use strict';

// Owned metadata and harmless bytes only: no model, native synthesis, real
// listening verdict, private recording, runtime copying or promotion occurs.
const assert=require('assert/strict'), fs=require('fs'),path=require('path'),cp=require('child_process');
const runtime=require('../commands/lib/bubo-runtime.cjs'),contracts=require('../commands/lib/media-pipeline-contract.cjs');
const state=require('../commands/lib/media-pipeline-state.cjs'),engines=require('../commands/lib/engine-contract.cjs');
const cache=path.basename(runtime.BASE)==='.opencaw'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.opencaw/.cache');
const evidence=path.join(cache,'tasks/opencaw-media-pipeline-domains/evidence/state-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')), task='owned-media', workspace='.opencaw/.cache/owned-media', mediaState='.opencaw/.cache/shared-allowance';
const observations=[];
const check=(value,message)=>{assert(value,message);observations.push(message);};
const rejects=(action,pattern,message)=>{assert.throws(action,pattern,message);observations.push(message);};
function write(name,value) {const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,typeof value==='string'||Buffer.isBuffer(value)?value:JSON.stringify(value,null,2)+'\n');return name;}
const ref=name=>state.identity(root,name);
const unavailable={unavailable:true,reason:'Owned fixture; no provider or inference involved.'};
const media='# MEDIA.md\nGenerated from OpenCaw media pipeline templates:\n- CLOUD\n- LOCAL\n---\n'
  +['Pipeline Availability','Capability Matrix','Destinations And Budgets','Rights, Consent, And Provenance','Review And Promotion'].map(x=>'## '+x+'\n').join('\n')
  +'Image, music, sound-effect SFX and voice are separately declared. Require the user to choose a provider. Never switch or fall back between providers silently.\n';
write('MEDIA.md',media);write(`.opencaw/.cache/tasks/${task}/TASK.md`,'# Owned synthetic task only\n');
write('inputs/rights.json',{fixture:'Synthetic rights metadata, no actual approval'});
write('inputs/brief.json',{fixture:'Owned brief; no real media requested',rights:ref('inputs/rights.json')});
for(const domain of ['AUDIO','MUSIC','VOICE'])contracts.generate({root,domain,inline:true});
const modalities={AUDIO:'sfx',MUSIC:'instrumental',VOICE:'preset-speech'};
function initialize(domain='AUDIO',version='v1',asset='same human asset',extra={}) {
  return state.init({root,task,domain,modality:modalities[domain],asset,version,brief:'inputs/brief.json',
    stagingRoot:workspace+'/staging/'+domain.toLowerCase(),...extra});
}
const options=asset=>({root,stateFile:asset.stateFile});
function request(asset,extra={}) {
  const item=asset.asset.domain==='MUSIC'?{id:'owned',music:{instrumental:true}}:asset.asset.domain==='VOICE'?{id:'owned',voice:{preset:'Owned'}}:{id:'owned',durationSeconds:1};
  return state.nativeRequest({...options(asset),provider:'LOCAL',workspace,mediaState,request:{schemaVersion:'bubo-media-request/v1',backend:'owned-nonexecutable',items:[item],...extra}});
}
function candidate(asset,name='owned',extra={}) {
  const output=write(`${workspace}/staging/${asset.asset.domain.toLowerCase()}/${asset.asset.nativeRequestId}/${name}.wav`,'OWNED nonaudio bytes; no acoustic quality claim');
  const provenance=write(`inputs/${asset.asset.nativeRequestId}.source.json`,{fixture:'Synthetic provider provenance only'});
  const provider=extra.provider || 'CLOUD';
  const manifest={schemaVersion:1,runId:extra.runId || asset.asset.nativeRequestId,createdAt:new Date().toISOString(),
    backend:{kind:provider==='LOCAL'?'local':'cloud-session',provider:'Owned fixture',capability:'none',toolVersion:unavailable},
    modality:asset.asset.domain==='AUDIO'?'sfx':asset.asset.domain==='MUSIC'?'music':'voice',
    model:{name:unavailable,revision:unavailable,digest:unavailable,license:unavailable},
    workflow:{name:'Owned metadata fixture',revision:unavailable,digest:unavailable},
    generation:{prompt:'Owned fixture only',negativePrompt:unavailable,seed:0,parameters:{source:ref(provenance),...extra.parameters}},
    inputs:[{description:'Owned synthetic bytes',source:'Owned fixture',rights:'Synthetic fixture only',consent:'not-applicable'}],
    outputs:[{stagedPath:output,sha256:ref(output).sha256,status:'staged',runtimeTarget:unavailable}],
    runtime:{destination:unavailable,budgets:{maxOutputBytes:4096}},review:{status:'pending',reviewer:unavailable,reviewedAt:unavailable,notes:'No real listening review'}};
  const manifestFile=write(`inputs/${asset.asset.nativeRequestId}.manifest.json`,manifest);
  if (extra.record!==false)state.recordCandidate({...options(asset),manifest:manifestFile,provider,origin:extra.origin});
  return {output,provenance,manifestFile,outputs:[ref(output)]};
}
function technical(asset,selected,suffix='technical',extra={}) {
  const report={schemaVersion:'opencaw-media-technical/v1',assetSha256:state.status(options(asset)).assetSha256,outputs:selected.outputs,
    status:'passed',checks:[{id:'owned-metadata',status:'passed',reason:'Synthetic metadata fixture; no actual acoustic measurement'}],
    measurements:selected.outputs.map(output=>({...output,bytes:fs.statSync(path.join(root,output.path)).size,durationSeconds:1,sampleRate:24000,channels:1})),...extra};
  const file=write(`inputs/${asset.asset.nativeRequestId}.${suffix}.json`,report);
  state.recordTechnical({...options(asset),report:file});return {file,report};
}
function review(asset,selected,kind='content',suffix='',extra={}) {
  const sourceEvidence=ref(write(`inputs/${asset.asset.nativeRequestId}.${kind}${suffix}.source.json`,{fixture:'Synthetic human-source metadata only; not a real user approval'}));
  const value={schemaVersion:'opencaw-media-review/v1',assetSha256:state.status(options(asset)).assetSha256,outputs:selected.outputs,
    kind,verdict:'accepted',reviewer:'Owned fixture identity; no human listening',reason:'Exercise explicit evidence plumbing only',sourceEvidence,...extra};
  const file=write(`inputs/${asset.asset.nativeRequestId}.${kind}${suffix}.review.json`,value);
  state.recordReview({...options(asset),review:file});return {file,value};
}
async function main() {
  const assets=['AUDIO','MUSIC','VOICE'].map(domain=>initialize(domain));
  check(new Set(assets.map(x=>x.stateFile)).size===3,'Same human asset names have independent domain state paths');
  check(new Set(assets.map(x=>x.asset.nativeRequestId)).size===3,'Same names have distinct domain-owned native request IDs');
  for(const asset of assets)check(/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(asset.asset.nativeRequestId),'Native identity remains within supported 80-character syntax');
  const prepared=assets.map(asset=>request(asset));
  check(new Set(prepared.map(x=>x.finalOutput)).size===3,'Native final output paths remain distinct across domains');
  check(new Set(prepared.map(x=>x.nativeState)).size===3,'Native state IDs remain distinct under the adapter task state');
  check(prepared.every(x=>x.mediaState===mediaState),'Every domain retains the same physical shared attempt ledger');
  check(prepared.every(x=>x.finalOutput===x.request.outputDirectory+'/'+x.request.requestId),'Native final output correctly includes native-appended requestId');
  check(state.status(options(assets[0])).stage==='planned','Initialization creates planning state without outputs or inference');
  check(state.status(options(assets[0])).executionAvailable===false,'Configured contracts do not fabricate executable domain readiness');
  await assert.rejects(state.dispatch({...options(assets[0])}),/unavailable/);observations.push('Domain execution rejects before dispatch until its implementation exists');
  for(const controls of [{timeout:0},{timeout:86401},{'max-log-bytes':0},{'max-private-bytes':Number.MAX_SAFE_INTEGER+1},{'max-private-bytes':Infinity}]) {
    await assert.rejects(state.dispatch({...options(assets[0]),controls}),/Invalid finite/);observations.push('Invalid finite dispatch control is rejected before native start');
  }
  await assert.rejects(state.dispatch({...options(assets[0]),controls:{execute:true}}),/protected/);observations.push('Setup/protected controls cannot enter generation dispatch');
  await assert.rejects(state.dispatch({...options(assets[0]),timeout:123}),/Unknown/);observations.push('Undocumented top-level execution options are rejected instead of ignored');
  rejects(()=>initialize(),/EEXIST|owned/,'Duplicate versions preserve immutable asset records');
  const revision=initialize('AUDIO','v2','same human asset',{parent:ref(assets[0].stateFile)});
  check(revision.asset.nativeRequestId!==assets[0].asset.nativeRequestId,'Revisions get fresh native identities with retained parent ancestry');
  rejects(()=>initialize('MUSIC','bad-parent','other',{parent:ref(assets[0].stateFile)}),/same task/,'Cross-domain or unrelated revision ancestry is rejected');
  rejects(()=>initialize('AUDIO','..'),/Invalid/,'Version traversal is rejected');
  rejects(()=>initialize('AUDIO','unsafe','bad',{stagingRoot:'assets/audio'}),/staging/,'Runtime assets cannot masquerade as staging');
  rejects(()=>request(assets[0],{requestId:'wrong'}),/owned/,'Caller cannot override version-owned native request ID');
  rejects(()=>request(assets[0],{task:'wrong'}),/owned/,'Caller cannot override version-owned native task');
  rejects(()=>request(assets[0],{items:[{id:'owned',music:{}}]}),/conflicts/,'Cross-domain native payload is rejected');
  rejects(()=>request(assets[0],{outputDirectory:'assets/audio'}),/owned/,'Caller cannot redirect native staging into runtime');
  rejects(()=>state.nativeRequest({...options(assets[0]),provider:'CLOUD',workspace,mediaState,request:{}}),/explicit LOCAL/,'Native preparation never silently falls back from CLOUD');
  const directory=path.posix.dirname(assets[0].stateFile), lockFile=write(directory+'/.write-lock','Owned active-write fixture');
  rejects(()=>initialize(),/already owned/,'Exclusive state lock rejects another writer');fs.unlinkSync(path.join(root,lockFile));
  const voiceBefore=fs.readFileSync(path.join(root,'VOICE.md'));
  fs.appendFileSync(path.join(root,'VOICE.md'),'\nVoice-only local instruction.\n');
  check(state.status(options(assets[0])).stale.length===0,'VOICE-only policy change leaves AUDIO current');
  check(state.status(options(assets[2])).stale.includes('domain-or-shared-policy-changed'),'VOICE-only change stales its dependent asset');
  fs.writeFileSync(path.join(root,'VOICE.md'),voiceBefore);
  fs.appendFileSync(path.join(root,'MEDIA.md'),'\nShared policy changed.\n');
  check(assets.every(asset=>state.status(options(asset)).stale.includes('domain-or-shared-policy-changed')),'Shared MEDIA change stales every affected domain');
  write('MEDIA.md',media);
  const originalRights=fs.readFileSync(path.join(root,'inputs/rights.json'));write('inputs/rights.json',{changed:true});
  check(state.status(options(assets[0])).stale.includes('input-changed'),'Typed nested brief references are rehashed without rewriting the brief');
  fs.writeFileSync(path.join(root,'inputs/rights.json'),originalRights);
  const selected=candidate(assets[0]);
  check(state.status(options(assets[0])).contentReview==='pending','Importing provenance never accepts human content review');
  rejects(()=>state.recordCandidate({...options(assets[0]),manifest:selected.manifestFile,provider:'CLOUD'}),/already exists/,'A second candidate cannot overwrite one version');
  rejects(()=>state.admitHandoff(options(assets[0])),/technical/,'Handoff is ineligible without actual current technical evidence');
  technical(assets[0],selected);review(assets[0],selected);
  rejects(()=>state.admitHandoff(options(assets[0])),/runtime/,'Content and technical review do not imply target acceptance');
  const badReview=write('inputs/wrong-review.json',{schemaVersion:'opencaw-media-review/v1',assetSha256:'0'.repeat(64),outputs:selected.outputs});
  rejects(()=>state.recordReview({...options(assets[0]),review:badReview}),/different/,'Review for another fingerprint is rejected');
  engines.generate(root,'THREEJS',{inline:true});
  const target={directory:'assets/audio/owned-v1',codecs:['wav'],sampleRates:[24000],channels:[1],maxOutputBytes:4096,maxAudioSeconds:2};
  const runtimeReview=review(assets[0],selected,'runtime','',{engine:state.engineIdentity(root),target});
  const handoff=state.admitHandoff(options(assets[0]));
  check(handoff.promotion===false && !fs.existsSync(path.join(root,target.directory)),'Handoff returns a guarded plan without runtime writes');
  rejects(()=>state.admitPromotion({...options(assets[0]),authorization:'inputs/missing.json'}),/ENOENT/,'Promotion requires separate explicit authorization');
  const promotionSource=ref(write('inputs/explicit-promotion-source.json',{fixture:'Separate synthetic promotion assertion, never a real authorization'}));
  const authorization=write('inputs/promotion.json',{schemaVersion:'opencaw-media-promotion/v1',authorized:true,assetSha256:handoff.assetSha256,
    target,outputs:handoff.outputs,authorizedBy:'Owned fixture only',reason:'Exercise admission without copying runtime files',sourceEvidence:promotionSource});
  const admitted=state.admitPromotion({...options(assets[0]),authorization});
  check(admitted.admitted===true,'Exact explicit authorization admits a promotion plan');
  check(admitted.sourceEvidence.sha256===promotionSource.sha256,'Promotion plan retains the exact source authorization identity');
  const sourceBefore=fs.readFileSync(path.join(root,promotionSource.path));
  write(promotionSource.path,{changed:true});
  rejects(()=>state.admitPromotion({...options(assets[0]),authorization}),/stale|changed/,'Changed source assertions cannot silently reuse an authorization');
  fs.writeFileSync(path.join(root,promotionSource.path),sourceBefore);
  const plainSource=write('inputs/promotion-unbound.json',{...JSON.parse(fs.readFileSync(path.join(root,authorization),'utf8')),sourceEvidence:promotionSource.path});
  rejects(()=>state.admitPromotion({...options(assets[0]),authorization:plainSource}),/typed identity/,'Promotion rejects an unbound plain-path source assertion');
  check(!fs.existsSync(path.join(root,target.directory)),'Promotion admission performs no runtime copying');
  const beforeOutput=fs.readFileSync(path.join(root,selected.output));fs.appendFileSync(path.join(root,selected.output),'changed');
  check(state.status(options(assets[0])).stale.includes('candidate-or-provenance-changed'),'Changed output bytes stale reviews');
  rejects(()=>state.admitPromotion({...options(assets[0]),authorization}),/stale/,'Changed bytes block previously admitted promotion');
  fs.writeFileSync(path.join(root,selected.output),beforeOutput);
  const beforeProvenance=fs.readFileSync(path.join(root,selected.provenance));write(selected.provenance,{changed:true});
  rejects(()=>state.admitHandoff(options(assets[0])),/stale/,'Nested provenance references are rehashed before handoff');
  fs.writeFileSync(path.join(root,selected.provenance),beforeProvenance);
  const beforeReview=fs.readFileSync(path.join(root,runtimeReview.file));fs.appendFileSync(path.join(root,runtimeReview.file),' ');
  rejects(()=>state.admitHandoff(options(assets[0])),/stale/,'Changed review evidence cannot inherit old acceptance');
  fs.writeFileSync(path.join(root,runtimeReview.file),beforeReview);
  engines.generate(root,'BABYLONJS',{inline:true});rejects(()=>state.admitHandoff(options(assets[0])),/stale/,'Changed engine contract invalidates target review');
  engines.generate(root,'THREEJS',{inline:true});
  review(assets[0],selected,'content','-rejected',{verdict:'rejected'});
  rejects(()=>state.admitHandoff(options(assets[0])),/content/,'A later explicit rejection supersedes earlier content acceptance');
  review(assets[0],selected,'content','-accepted');
  for(const [suffix,changed,pattern,message] of [
    ['traversal',{directory:'../outside'},/Traversal|escapes/,'Target traversal is rejected before any runtime write'],
    ['cache',{directory:'.opencaw/.cache/runtime'},/assets child/,'Runtime handoff cannot target the cache'],
    ['bytes',{maxOutputBytes:1},/exceeds/,'Actual candidate bytes enforce target byte budget'],
    ['duration',{maxAudioSeconds:0.5},/exceeds/,'Actual declared duration enforces target budget'],
    ['rate',{sampleRates:[48000]},/format/,'Unsupported target sample-rate acceptance is rejected'],
    ['invalid-rate',{sampleRates:[0]},/invalid/,'Zero and invalid target formats are rejected'],
    ['channels',{channels:[2]},/format/,'Target channel mismatch is rejected'],
    ['codec',{codecs:['mp3']},/format/,'Target codec mismatch is rejected']
  ]) {
    review(assets[0],selected,'runtime','-'+suffix,{engine:state.engineIdentity(root),target:{...target,...changed}});
    rejects(()=>state.admitHandoff(options(assets[0])),pattern,message);
  }
  review(assets[0],selected,'runtime','-restored',{engine:state.engineIdentity(root),target});
  write(target.directory+'/existing.txt','Owned unrelated asset fixture');
  rejects(()=>state.admitHandoff(options(assets[0])),/already exists/,'Existing runtime destination cannot be overwritten');
  check(fs.readFileSync(path.join(root,target.directory+'/existing.txt'),'utf8')==='Owned unrelated asset fixture','Rejected admission preserves unrelated runtime bytes');
  const broken=initialize('AUDIO','broken','broken');write(path.posix.dirname(broken.stateFile)+'/events/000001.json','{');
  rejects(()=>state.status(options(broken)),/JSON|Expected/,'Interrupted event JSON is visible corruption, never silently dropped');
  const gap=initialize('AUDIO','gap','gap');write(path.posix.dirname(gap.stateFile)+'/events/000002.json',{});
  rejects(()=>state.status(options(gap)),/Incomplete/,'Event sequence gaps block replay');
  const alias=path.join(root,'linked-input');
  try {fs.symlinkSync(path.join(root,'inputs'),alias,process.platform==='win32'?'junction':'dir');
    rejects(()=>initialize('AUDIO','linked','linked',{brief:'linked-input/brief.json'}),/symbolic|junction/,'Native path reader rejects linked input ancestors');
  } catch(error) {if(error.code!=='EPERM')throw error;observations.push('SKIP: host lacks permission for link fixture');}
  if(process.platform==='win32')rejects(()=>initialize('AUDIO','alias','alias',{brief:'inputs./brief.json'}),/aliases/,'Windows path aliases fail before lifecycle writes');
  const childOptions={root,task,domain:'AUDIO',modality:'sfx',asset:'concurrent asset',version:'v1',brief:'inputs/brief.json'};
  const script='try { require('+JSON.stringify(require.resolve('../commands/lib/media-pipeline-state.cjs'))+').init(JSON.parse(process.argv[1]));process.exit(0); } catch(e) {process.stderr.write(e.message);process.exit(2);}';
  const child=()=>new Promise(resolve=>{const process=cp.spawn(global.process.execPath,['-e',script,JSON.stringify(childOptions)],{windowsHide:true,stdio:['ignore','pipe','pipe']});let stderr='';process.stderr.on('data',x=>stderr+=x);process.on('exit',code=>resolve({code,stderr}));});
  const concurrent=await Promise.all([child(),child()]);check(concurrent.filter(x=>x.code===0).length===1 && concurrent.filter(x=>x.code===2).length===1,'Two actual processes cannot both initialize the same immutable version');
  check(concurrent.find(x=>x.code===2).stderr.match(/EEXIST|owned/),'Concurrent loser reports exclusive ownership or immutable duplicate');
  // Exercise async dispatch bookkeeping with an explicitly substituted fixture
  // boundary. No real Bubo method/model is invoked by this simulation.
  const adapter=require('../commands/lib/bubo-media-adapter.cjs'),oldInvoke=adapter.invoke,oldResolve=contracts.resolve;
  const failed=initialize('AUDIO','dispatch-failure','dispatch failure');
  try {
    contracts.resolve=options=>({...oldResolve(options),executionAvailable:true});
    adapter.invoke=async()=>{throw new Error('Owned simulated publication failure after native boundary');};
    await assert.rejects(state.dispatch({...options(failed),request:{schemaVersion:'bubo-media-request/v1',items:[{id:'owned'}]},provider:'LOCAL',workspace,mediaState}),/simulated/);
    observations.push('Failed native/publication simulation retains started attempt event');
    check(state.status(options(failed)).eventCount===2,'Started and failed dispatch remain immutable history');
    rejects(()=>request(failed),/already exists or started/,'Failed host publication never permits a fresh same-version attempt');
    const nativeAsset=initialize('AUDIO','native','native owned'),otherAsset=initialize('AUDIO','other-native','different asset');
    const otherCandidate=candidate(otherAsset,'other',{provider:'LOCAL',record:false});
    let generated;
    const platformModules=write('inputs/platform-modules.json',{schemaVersion:'opencaw-platform-modules/v1',modules:[]});
    const controls={timeout:120,'max-log-bytes':65536,'max-private-bytes':1048576,'platform-modules':platformModules};
    adapter.invoke=async(operation,parsed)=>{
      check(operation==='generate' && parsed.get('media-state')===mediaState,'Dispatch forwards the original physical shared allowance root');
      check(Object.entries(controls).every(([key,value])=>parsed.get(key)===String(value)),'Every selected bounded/platform control reaches the existing adapter unchanged');
      generated=candidate(nativeAsset,'native',{provider:'LOCAL',record:false,runId:nativeAsset.asset.nativeRequestId+'-0',parameters:{sourceRequest:ref(parsed.get('manifest'))}});
      return {status:'succeeded',hostMediaProvenance:[generated.manifestFile]};
    };
    await state.dispatch({...options(nativeAsset),request:{schemaVersion:'bubo-media-request/v1',items:[{id:'owned'}]},provider:'LOCAL',workspace,mediaState,controls});
    const started=state.load(options(nativeAsset)).events.find(event=>event.kind==='dispatch-started');
    check(started.data.budgets.timeoutSeconds===120 && started.data.controlReferences[0].sha256===ref(platformModules).sha256,'Dispatch retains enforced bounds and exact platform manifest identity');
    rejects(()=>state.recordCandidate({...options(nativeAsset),provider:'LOCAL',manifest:otherCandidate.manifestFile}),/exact completed native dispatch/,'Same-domain candidate transplant cannot replace another native asset version');
    rejects(()=>state.recordCandidate({...options(nativeAsset),provider:'CLOUD',manifest:generated.manifestFile}),/cannot switch/,'A started LOCAL run cannot import a CLOUD fallback');
    state.recordCandidate({...options(nativeAsset),provider:'LOCAL',manifest:generated.manifestFile});
    check(state.status(options(nativeAsset)).executionOrigin==='native-dispatch','Completed native provenance stays bound to its own dispatch identity');
    check(state.status(options(nativeAsset)).sourceRunIds[0]===nativeAsset.asset.nativeRequestId+'-0','Status preserves the actual emitted source run ID');
    const platformBefore=fs.readFileSync(path.join(root,platformModules));fs.appendFileSync(path.join(root,platformModules),' ');
    check(state.status(options(nativeAsset)).stale.includes('native-request-or-returned-provenance-changed'),'Changed selected platform evidence stales the recorded run');
    fs.writeFileSync(path.join(root,platformModules),platformBefore);
    rejects(()=>state.recordCandidate({...options(otherAsset),provider:'LOCAL',manifest:otherCandidate.manifestFile}),/explicit historical-import/,'LOCAL provenance without dispatch requires an explicit import origin');
    state.recordCandidate({...options(otherAsset),provider:'LOCAL',manifest:otherCandidate.manifestFile,origin:'historical-import'});
    const imported=state.status(options(otherAsset));
    check(imported.executionOrigin==='historical-import' && imported.nativeDispatchRequestId===null,'Historical LOCAL import never advertises a new native dispatch');
  } finally {adapter.invoke=oldInvoke;contracts.resolve=oldResolve;}
  const result={assertions:observations.length,observations,root,limits:['Owned metadata and harmless bytes only','No real acoustic measurement, human listening, native inference, installation or runtime promotion','Async dispatch substitution proves host bookkeeping only']};
  fs.writeFileSync(path.join(root,'results.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify({assertions:observations.length,evidence:path.join(root,'results.json'),limits:result.limits}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
