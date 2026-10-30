'use strict';

// Actual CLI and coordinator boundaries with owned metadata/harmless bytes.
// Native requests, license assertions, human/runtime reviews and measurement
// counters below are synthetic fixtures, not real consent or acoustic evidence.
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),cp=require('child_process');
const runtime=require('../commands/lib/bubo-runtime.cjs'),contracts=require('../commands/lib/media-pipeline-contract.cjs');
const lifecycle=require('../commands/lib/media-pipeline-state.cjs'),engines=require('../commands/lib/engine-contract.cjs');
const coordinator=require('../commands/lib/media-pipeline-command.cjs'),spec=require('../commands/lib/audio-pipeline.cjs');
const cache=path.basename(runtime.BASE)==='.opencaw'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.opencaw/.cache');
const evidence=path.join(cache,'tasks/opencaw-audio-pipeline/evidence/cli-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')),task='owned-audio-cli',workspace='.opencaw/.cache/owned-media',mediaState='.opencaw/.cache/shared-media-allowance';
const observations=[],unavailable={unavailable:true,reason:'Owned synthetic fixture; not a real provider/model/acoustic observation.'};
function check(value,message){assert(value,message);observations.push(message);}
function write(name,value){const full=path.join(root,name);fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,typeof value==='string'||Buffer.isBuffer(value)?value:JSON.stringify(value,null,2)+'\n');return name;}
const ref=name=>lifecycle.identity(root,name);
function cli(operation,args=[],expected=0){
  const result=cp.spawnSync(process.execPath,[path.join(runtime.BASE,'commands/lib/media-pipeline-command.cjs'),'AUDIO',operation,'--root',root,...args],{encoding:'utf8',windowsHide:true});
  check(result.status===expected,'Actual CLI exit for '+operation+': '+result.stderr);
  if(expected!==0)return result.stdout.trim().startsWith('{')?JSON.parse(result.stdout):result.stderr;
  const value=JSON.parse(result.stdout);check(result.stdout.trim().startsWith('{')&&result.stdout.trim().endsWith('}'),'CLI emits one JSON object: '+operation);return value;
}
function reject(operation,args,pattern){const message=cli(operation,args,1);check(pattern.test(message),'Rejected '+operation+' for the stated boundary: '+message);}
function snapshot(folder=root){const rows=[];function visit(dir){for(const name of fs.readdirSync(dir).sort()){const full=path.join(dir,name),stat=fs.lstatSync(full);rows.push([path.relative(folder,full),stat.isDirectory()?'dir':stat.isSymbolicLink()?'link':runtime.hash(full)]);if(stat.isDirectory()&&!stat.isSymbolicLink())visit(full);}}visit(folder);return JSON.stringify(rows);}
const media='# MEDIA.md\nGenerated from OpenCaw media pipeline templates:\n- CLOUD\n- LOCAL\n---\n'+['Pipeline Availability','Capability Matrix','Destinations And Budgets','Rights, Consent, And Provenance','Review And Promotion'].map(x=>'## '+x+'\n').join('\n')+'Image, music, sound-effect SFX and voice are independent. Require the user to choose a provider. Never switch or fall back between providers silently.\n';
write('MEDIA.md',media);write(`.opencaw/.cache/tasks/${task}/TASK.md`,'# Owned synthetic task\n');contracts.generate({root,domain:'AUDIO',inline:true});
write('inputs/rights.json',{schemaVersion:'bubo-media-rights/v1',task,owner:'Owned synthetic assertion only',promptRightsConfirmed:true,generationAllowed:true});
write('inputs/license-source.json',{fixture:'Not an actual license acceptance'});
write('inputs/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends:['stable-audio-open'],licenseIds:['owned-fixture-only'],sourceEvidence:ref('inputs/license-source.json')});
write('inputs/installation.json',{schemaVersion:'bubo-media-installation/v1',backend:'stable-audio-open',licenses:[ref('inputs/license.json')]});
const brief={schemaVersion:'opencaw-audio-brief/v1',kind:'sfx',purpose:'Owned test fixture, no real media requested',provider:'LOCAL',spatialization:'2d',loopIntent:false,
  request:{rights:ref('inputs/rights.json'),installation:ref('inputs/installation.json'),settings:{device:'cuda:0',precision:'float16',offload:'none'},
    budget:{maximumOutputs:1,maximumBytesPerOutput:1048576,maximumTotalBytes:1048576,maximumPixels:4096,maximumAudioSeconds:2},
    items:[{id:'owned',prompt:'Owned harmless metadata fixture',negativePrompt:'',seed:17,steps:20,guidance:7,seconds:1,loopCandidate:false}]},
  technical:{maxPeak:1,maxClippedFraction:0,maxSilentFraction:1}};
write('inputs/brief.json',brief);
function current(stateFile){return lifecycle.status({root,stateFile});}
function provenance(stateFile){
  const sourceRequest={schemaVersion:'bubo-media-request/v1',requestId:'original-owned-historical-run',task,backend:'stable-audio-open',outputDirectory:workspace+'/staging/audio',...brief.request};
  const sourceRevision='1'.repeat(40),workerSourceSha256='4'.repeat(64);
  const source=write('inputs/source-request.json',sourceRequest),host=write('inputs/native-context.json',{schemaVersion:'bubo-host-context/v1',projectRoot:root,task,policy:{purpose:'local-media',pipeline:'LOCAL',media:ref('MEDIA.md')},fixture:'No native execution occurred'});
  const build={cliSha256:'6'.repeat(64),resourceCatalogSha256:'2'.repeat(64),assemblies:{},launch:{},fixture:'Owned nonexistent build only'};
  const sourceRevisionEvidence=ref(write('inputs/build-info.json',{schemaVersion:'bubo-build/v1',sourceRevision,sourceDirty:false,capabilities:{build}}));
  const output=write(workspace+'/staging/audio/original-owned-historical-run/000.wav','OWNED nonaudio bytes; no sound was generated or reviewed.');
  const measured={id:'owned',path:output,sha256:ref(output).sha256,bytes:fs.statSync(path.join(root,output)).size,sampleRate:44100,channels:2,frames:44100,peak:0.5,rms:0.1,clippedFraction:0,silentFraction:0.1,
    requested:brief.request.items[0],actual:{seed:17,steps:20,guidance:7,scheduler:'Owned synthetic scheduler'}};
  const native={schemaVersion:'bubo-media-manifest/v1',status:'generated-staged',backend:'stable-audio-open',promotion:false,humanReview:'pending',
    outputs:[measured],hostContextSha256:ref(host).sha256,mediaPolicySha256:ref('MEDIA.md').sha256,runtimeBuild:build,requestPath:source,requestSha256:ref(source).sha256,
    requestedSettings:brief.request.settings,actualSettings:brief.request.settings,resourceCatalogSha256:build.resourceCatalogSha256,workerSourceSha256,unloaded:true,modelLoads:1,cleanup:null};
  const nativeFile=write('inputs/native-manifest.json',native),result=write('inputs/native-result.json',{schemaVersion:'bubo-execution-result/v1',apiVersion:1,status:'succeeded',workflow:'media',operation:'generate',hostContextSha256:ref(host).sha256,runtime:build,data:native});
  const manifest={schemaVersion:1,runId:sourceRequest.requestId+'-0',createdAt:new Date().toISOString(),backend:{kind:'local',provider:'Owned fixture',capability:'stable-audio-open',toolVersion:sourceRevision},
    modality:'sfx',model:{name:unavailable,revision:unavailable,digest:unavailable,license:unavailable},workflow:{name:'Owned synthetic fixture',revision:sourceRevision,digest:workerSourceSha256},
    generation:{prompt:brief.request.items[0].prompt,negativePrompt:unavailable,seed:17,parameters:{nativeManifest:ref(nativeFile),nativeResult:ref(result),hostContext:ref(host),sourceRequest:ref(source),runtime:{build,revision:sourceRevision,resourceCatalogSha256:build.resourceCatalogSha256,sourceRevisionEvidence},requested:measured.requested,actual:measured.actual,execution:brief.request.settings}},
    inputs:[{description:'Owned synthetic bytes only',source:'fixture',rights:'No actual model/media license asserted',consent:'not-applicable'}],
    outputs:[{stagedPath:output,sha256:ref(output).sha256,status:'staged',runtimeTarget:unavailable}],runtime:{destination:unavailable,budgets:brief.request.budget},review:{status:'pending',reviewer:unavailable,reviewedAt:unavailable,notes:'No actual human listening'}};
  return {manifestFile:write('inputs/neutral-manifest.json',manifest),output,outputs:[ref(output)]};
}
async function main(){
  const help=cp.spawnSync(process.execPath,[path.join(runtime.BASE,'commands/lib/media-pipeline-command.cjs'),'AUDIO','--help'],{cwd:root,encoding:'utf8'});
  check(help.status===0&&/setup-plan/.test(help.stdout)&&/recover/.test(help.stdout),'Actual help works without initializing or resolving a host');
  const shell=process.env.OPENCAW_BASH||(process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'bash');
  const wrapper=cp.spawnSync(shell,[path.join(runtime.BASE,'commands/audio-pipeline.sh').replace(/\\/g,'/'),'--help'],{cwd:root,encoding:'utf8'});
  check(wrapper.status===0&&/audio-pipeline/.test(wrapper.stdout),'Real Bash AUDIO wrapper help works outside initialized host');
  const beforeBrief=snapshot();check(cli('brief',['--brief','inputs/brief.json']).valid===true,'Supported explicit native brief validates without execution');
  check(snapshot()===beforeBrief,'Brief validation creates no state or outputs');
  reject('brief',['--brief','inputs/brief.json','--execute'],/protected/);
  reject('init',['--task',task,'--asset','owned','--version','v1','--brief','inputs/brief.json','--task',task],/duplicate/);
  reject('init',['--task',task,'--asset','owned','--version','v1','--brief','inputs/brief.json','--workspace',workspace,'--staging-root','.art-staging/owned'],/not both/);
  const init=cli('init',['--task',task,'--asset','Owned effect','--version','v1','--brief','inputs/brief.json','--workspace',workspace]);
  const stateFile=init.stateFile;check(current(stateFile).stage==='planned','Actual init creates independent planning state only');
  reject('generate',['--state',stateFile,'--provider','CLOUD','--workspace',workspace,'--media-state',mediaState],/conflicts/);
  reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--execute','true'],/protected/);
  reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--timeout','0'],/finite/);
  const malformed=JSON.parse(JSON.stringify(brief));malformed.request.items[0].seconds=60;write('inputs/too-long.json',malformed);
  reject('init',['--task',task,'--asset','too long ambience','--version','v1','--brief','inputs/too-long.json'],/duration/);
  const revised=cli('revise',['--state',stateFile,'--version','v2','--brief','inputs/brief.json']);
  check(revised.stateFile!==stateFile&&current(revised.stateFile).nativeRequestId!==current(stateFile).nativeRequestId,'Actual revision retains ancestry and gets distinct native identity');
  const beforeStatus=snapshot();check(cli('status',['--state',stateFile]).stage==='planned','Status describes current planning stage');check(snapshot()===beforeStatus,'Status performs no filesystem writes');
  const beforeDoctor=snapshot(),doctor=cli('doctor',['--state',stateFile,'--workspace',workspace]);
  check(doctor.modelLoading===false&&doctor.generation===false&&doctor.nativeReadiness==='unverified','Actual doctor reports read-only unverified native readiness');check(snapshot()===beforeDoctor,'Actual doctor creates no host/model/state files');
  const source=provenance(stateFile);
  reject('import',['--state',stateFile,'--provider','LOCAL','--manifest',source.manifestFile],/origin/);
  const imported=cli('import',['--state',stateFile,'--provider','LOCAL','--manifest',source.manifestFile,'--origin','historical-import']);
  check(imported.assetStatus.contentReview==='pending'&&imported.assetStatus.nativeDispatchRequestId===null,'Actual historical import grants neither a new run nor listening acceptance');
  reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState],/already has a candidate/);
  const validation=cli('validate',['--state',stateFile]);check(validation.ok===true&&validation.status==='passed','Native-shaped owned provenance passes domain technical ancestry checks');
  const technicalReport=JSON.parse(fs.readFileSync(path.join(root,validation.report.path),'utf8'));
  check(technicalReport.generationIdentities[0].sourceRevision==='1'.repeat(40)&&technicalReport.generationIdentities[0].resourceCatalogSha256==='2'.repeat(64),'Actual CLI technical report preserves disclosed source-build and resource identities');
  reject('handoff',['--state',stateFile],/content/);
  const fingerprint=current(stateFile).assetSha256,reviewSource=ref(write('inputs/human-source.json',{fixture:'Synthetic review source; no human listened'}));
  const content={schemaVersion:'opencaw-media-review/v1',assetSha256:fingerprint,outputs:source.outputs,kind:'content',verdict:'accepted',reviewer:'Owned synthetic fixture only',reason:'Test explicit evidence binding, not acoustic quality',sourceEvidence:reviewSource,
    criteria:{listenedEntireOutput:true,matchesBrief:true,unwantedSpeechMusicAbsent:true,artifactsAcceptable:true,headTailAccepted:true}};
  const missing=write('inputs/incomplete-review.json',{...content,criteria:{}});reject('review',['--state',stateFile,'--review',missing],/criteria/);
  cli('review',['--state',stateFile,'--review',write('inputs/content-review.json',content)]);
  reject('handoff',['--state',stateFile],/runtime/);
  engines.generate(root,'THREEJS',{inline:true});const engine=lifecycle.engineIdentity(root);
  const target={directory:'assets/audio/owned-fixture',codecs:['wav'],sampleRates:[44100],channels:[2],maxOutputBytes:1048576,maxAudioSeconds:2,spatialization:'2d',loopIntent:false};
  const distribution=ref(write('inputs/distribution.json',{schemaVersion:'opencaw-audio-distribution/v1',task,purpose:brief.purpose,rightsConfirmed:true,sourceEvidence:reviewSource}));
  const targetEvidence=ref(write('inputs/target-evidence.json',{schemaVersion:'opencaw-audio-runtime-evidence/v1',task,engine,outputs:source.outputs,spatialization:'2d',loopIntent:false,playbackReviewed:true,loadDisposeReviewed:true,loopSeamReviewed:false,sourceEvidence:reviewSource}));
  const runtimeReview={schemaVersion:'opencaw-media-review/v1',assetSha256:fingerprint,outputs:source.outputs,kind:'runtime',verdict:'accepted',reviewer:content.reviewer,reason:content.reason,sourceEvidence:reviewSource,
    criteria:{targetPlaybackReviewed:true,loadDisposeReviewed:true,spatializationReviewed:true},engine,target,rightsEvidence:distribution,targetEvidence};
  cli('review',['--state',stateFile,'--review',write('inputs/runtime-review.json',runtimeReview)]);
  const handoff=cli('handoff',['--state',stateFile]);check(handoff.promotion===false&&!fs.existsSync(path.join(root,target.directory)),'Actual handoff does not copy files');
  const authorization=write('inputs/promotion.json',{schemaVersion:'opencaw-media-promotion/v1',authorized:true,assetSha256:fingerprint,target,outputs:source.outputs,authorizedBy:'Owned synthetic fixture; not a real permission',reason:'Exercise copying of harmless bytes inside owned fixture',sourceEvidence:ref(write('inputs/promotion-source.json',{fixture:'No real asset promotion authorization'}))});
  const promoted=cli('promote',['--state',stateFile,'--authorization',authorization]);
  check(promoted.promotion===true&&fs.readFileSync(path.join(root,target.directory+'/000.wav'),'utf8').startsWith('OWNED nonaudio'),'Explicit CLI promotion copies only owned fixture bytes after all gates');
  const recovered=cli('recover',['--state',stateFile,'--authorization',authorization]);check(recovered.alreadyPromoted===true,'Explicit recovery recognizes exactly owned completed fixture without re-copying');
  const sourceBefore=fs.readFileSync(path.join(root,'inputs/license-source.json'));write('inputs/license-source.json',{changed:true});
  reject('recover',['--state',stateFile,'--authorization',authorization],/source changed|changed/);fs.writeFileSync(path.join(root,'inputs/license-source.json'),sourceBefore);
  const cloudRights=ref(write('inputs/cloud-rights.json',{schemaVersion:'bubo-media-rights/v1',task:'original-source-task',owner:'Owned historical assertion only',promptRightsConfirmed:true,generationAllowed:false}));
  const cloud=JSON.parse(JSON.stringify(brief));cloud.provider='CLOUD';cloud.request={rights:cloudRights,budget:{maximumOutputs:1,maximumBytesPerOutput:1048576,maximumTotalBytes:1048576,maximumAudioSeconds:2},items:[{id:'owned',prompt:'Owned fixture',seconds:1}]};write('inputs/cloud-brief.json',cloud);
  const cloudInit=cli('init',['--task',task,'--asset','Owned CLOUD import','--version','v1','--brief','inputs/cloud-brief.json']);
  reject('generate',['--state',cloudInit.stateFile,'--provider','CLOUD'],/separately available authorized session capability/);
  const cloudOutput=write('.art-staging/media/audio/owned-cloud/000.wav','OWNED CLOUD-origin bytes, not generated audio');
  const cloudManifest=JSON.parse(fs.readFileSync(path.join(root,source.manifestFile),'utf8'));
  cloudManifest.backend={kind:'cloud-session',provider:'Owned synthetic session',capability:'none',toolVersion:unavailable};cloudManifest.generation.parameters={};cloudManifest.outputs=[{stagedPath:cloudOutput,sha256:ref(cloudOutput).sha256,status:'staged',runtimeTarget:unavailable}];
  cli('import',['--state',cloudInit.stateFile,'--provider','CLOUD','--manifest',write('inputs/cloud-manifest.json',cloudManifest)]);
  const unavailableAnalysis=cli('validate',['--state',cloudInit.stateFile],1);
  check(unavailableAnalysis.ok===false&&unavailableAnalysis.checks.some(check=>check.status==='unavailable'),'CLOUD import with missing authoritative analysis stays explicitly unverified');
  reject('handoff',['--state',cloudInit.stateFile],/technical/);
  // Substituted adapter boundaries establish argument/dispatch composition,
  // not native installation, inference, model readiness or generated outputs.
  const adapter=require('../commands/lib/bubo-media-adapter.cjs'),oldInvoke=adapter.invoke,oldDispatch=lifecycle.dispatch,oldRecord=lifecycle.recordCandidate;
  try{
    let setupCalled=false;
    adapter.invoke=async(operation,options,settings)=>{setupCalled=true;check(operation==='setup'&&!options.has('execute')&&settings.emit===false,'Coordinator setup planning delegates silent dry-run only');return {status:'succeeded',data:{fixture:'No real native setup'}};};
    write('inputs/setup.json',{schemaVersion:'bubo-media-setup/v1',task,backend:'stable-audio-open'});
    await coordinator.run(spec,['setup-plan','--root',root,'--task',task,'--provider','LOCAL','--manifest','inputs/setup.json']);check(setupCalled,'Explicit setup-plan reaches the existing setup boundary');
    let dispatchCalled=false,recorded=false;
    lifecycle.dispatch=async(options)=>{dispatchCalled=true;check(options.request.items[0].seconds===1&&!Object.hasOwn(options.request.items[0],'durationSeconds'),'Coordinator builds exact native seconds field');check(options.mediaState===mediaState&&options.controls.timeout==='120','Coordinator preserves physical shared ledger and explicit limits');return {status:'succeeded',hostMediaProvenance:[source.manifestFile]};};
    lifecycle.recordCandidate=options=>{recorded=true;check(options.manifests[0]===source.manifestFile&&options.provider==='LOCAL','Coordinator imports complete returned provenance without resetting origin/claims');};
    await coordinator.run(spec,['generate','--root',root,'--state',revised.stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--timeout','120']);
    check(dispatchCalled&&recorded,'Explicit generate composes native request and staged provenance boundaries');
  }finally{adapter.invoke=oldInvoke;lifecycle.dispatch=oldDispatch;lifecycle.recordCandidate=oldRecord;}
  const report={assertions:observations.length,observations,root,limits:['Owned fixture metadata and harmless nonaudio bytes only','No model, actual license acceptance, native inference, listening/runtime review or real project asset promotion','Substituted native boundaries prove coordinator argument composition only']};
  fs.writeFileSync(path.join(root,'results.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({assertions:observations.length,evidence:path.join(root,'results.json'),limits:report.limits}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
