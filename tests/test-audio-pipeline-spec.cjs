'use strict';

// Host-domain policy fixtures only. Synthetic bytes and native-shaped receipts
// establish no real installation, inference, acoustic measurement or listening.
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),crypto=require('crypto');
const runtime=require('../commands/lib/bubo-runtime.cjs'),spec=require('../commands/lib/audio-pipeline.cjs');
const cache=path.basename(runtime.BASE)==='.hephaera'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.hephaera/.cache');
const evidence=path.join(cache,'tasks/hephaera-audio-pipeline/evidence/spec-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')),task='owned-audio';let sequence=0;const observations=[];
const check=(value,message)=>{assert(value,message);observations.push(message);};
const rejects=(action,pattern,message)=>{assert.throws(action,pattern,message);observations.push(message);};
const copy=value=>JSON.parse(JSON.stringify(value));
function write(name,value){const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,typeof value==='string'||Buffer.isBuffer(value)?value:JSON.stringify(value,null,2)+'\n');return name;}
const identity=name=>({path:name,sha256:runtime.hash(path.join(root,name))});
const permissionSource=identity(write('inputs/license-source.txt','OWNED synthetic terms-source fixture; no real acceptance'));
const license=identity(write('inputs/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends:[spec.backend],licenseIds:['OWNED-not-an-actual-license'],sourceEvidence:permissionSource}));
const installation=identity(write('inputs/installation.json',{schemaVersion:'bubo-media-installation/v1',backend:spec.backend,licenses:[license],fixture:'No model or installed runtime exists'}));
const rights=identity(write('inputs/rights.json',{schemaVersion:'bubo-media-rights/v1',task,owner:'Owned fixture only',promptRightsConfirmed:true,generationAllowed:true}));
write('MEDIA.md','Owned synthetic native-policy source; not a configured provider');
const base=JSON.parse(fs.readFileSync(path.join(runtime.BASE,'.media/pipelines/audio/examples/brief.local.json'),'utf8'));
base.purpose='Owned test purpose';base.request.rights=rights;base.request.installation=installation;base.request.items[0]={id:'owned',prompt:'Synthetic fixture only',negativePrompt:'',seed:9,steps:10,guidance:7,seconds:1,loopCandidate:false};
base.request.budget.maximumAudioSeconds=2;
function fixture(brief=base,{mutateSource=()=>{},mutateNative=()=>{},mutateNeutral=()=>{},mutateResult=()=>{}}={}){
  const name='run-'+(++sequence),prefix='staging/'+name,sourceRevision='1'.repeat(40),build={cliSha256:'6'.repeat(64),resourceCatalogSha256:'2'.repeat(64),assemblies:{},launch:{}};
  const request={...spec.request(brief,{root,asset:{task}}),requestId:name,outputDirectory:'staging'};mutateSource(request);
  const sourceRequest=identity(write(prefix+'/source-request.json',request));
  const modelFiles=[{path:'owned-model.bin',sha256:'7'.repeat(64),revision:'owned-snapshot',repository:'owned/repository',license:'OWNED not actual terms'}];
  const modelCatalog=identity(write(prefix+'/model-catalog.json',{schemaVersion:'bubo-media-catalog/v1',backends:[{id:spec.backend,files:modelFiles}]}));
  const modelDigest=crypto.createHash('sha256').update(JSON.stringify(runtime.canonical(modelFiles.map(({path,sha256,revision,repository})=>({path,sha256,revision,repository}))))).digest('hex');
  const media=identity('MEDIA.md'),context={schemaVersion:'bubo-host-context/v1',projectRoot:root,task:request.task,policy:{purpose:'local-media',pipeline:'LOCAL',media}};
  const hostContext=identity(write(prefix+'/host-context.json',context));
  const outputs=request.items.map(item=>{
    const output=write(prefix+'/'+item.id+'.wav','OWNED synthetic nonaudio bytes, no acoustic claim');
    return {id:item.id,path:output,sha256:identity(output).sha256,bytes:fs.statSync(path.join(root,output)).size,
      sampleRate:44100,channels:2,frames:Math.round(item.seconds*44100),peak:0.8,rms:0.2,clippedFraction:0,silentFraction:0.1,
      requested:item,actual:{seed:item.seed,steps:item.steps,guidance:item.guidance,scheduler:'Owned fixed scheduler',nativeMetadata:null},humanReview:'pending',promotion:false};
  });
  const native={schemaVersion:'bubo-media-manifest/v1',status:'generated-staged',requestPath:sourceRequest.path,requestSha256:sourceRequest.sha256,
    hostContextSha256:hostContext.sha256,mediaPolicySha256:media.sha256,backend:spec.backend,runtimeBuild:build,
    requestedSettings:request.settings,actualSettings:{...request.settings,deviceName:'Owned synthetic GPU metadata'},modelLoads:1,unloaded:true,cleanup:null,outputs,humanReview:'pending',promotion:false,
    resourceCatalogSha256:build.resourceCatalogSha256,catalogSha256:modelCatalog.sha256,workerSourceSha256:'4'.repeat(64),completedAt:'2026-10-30T01:00:00Z'};
  const sourceRevisionEvidence=identity(write(prefix+'/build-info.json',{schemaVersion:'bubo-build/v1',sourceRevision,sourceDirty:false,capabilities:{build}}));
  mutateNative(native);const nativeManifest=identity(write(prefix+'/native-manifest.json',native));
  const result={schemaVersion:'bubo-execution-result/v1',apiVersion:2,workflow:'media',operation:'generate',status:'succeeded',runtime:build,data:native,hostContextSha256:hostContext.sha256};
  mutateResult(result);
  const nativeResult=identity(write(prefix+'/result.json',result)),manifests=[];
  for(const output of native.outputs){
    const unavailable={unavailable:true,reason:'Owned metadata fixture; no provider operation occurred'};
    const neutral={schemaVersion:1,runId:name+'-0',createdAt:native.completedAt,modality:'sfx',backend:{kind:'local',provider:'Bubo',capability:spec.backend,toolVersion:sourceRevision},
      model:{name:spec.backend,revision:'owned-snapshot',digest:modelDigest,license:'OWNED not actual terms'},
      workflow:{name:spec.backend,revision:sourceRevision,digest:native.workerSourceSha256},
      generation:{prompt:output.requested.prompt,negativePrompt:output.requested.negativePrompt||unavailable,seed:output.requested.seed,parameters:{
      nativeManifest,nativeResult,hostContext,sourceRequest,modelCatalog,runtime:{build,revision:sourceRevision,resourceCatalogSha256:build.resourceCatalogSha256,sourceRevisionEvidence},execution:native.actualSettings,requested:output.requested,actual:output.actual}},
      inputs:[{description:'Owned fixture',source:'Owned byte source',rights:'Synthetic rights only',consent:'not-applicable'}],
      outputs:[{stagedPath:output.path,sha256:output.sha256,status:'staged',runtimeTarget:unavailable}],runtime:{destination:unavailable,budgets:request.budget},
      review:{status:'pending',reviewer:unavailable,reviewedAt:unavailable,notes:'No actual human review'}};
    mutateNeutral(neutral);manifests.push(identity(write(prefix+'/'+output.id+'.neutral.json',neutral)));
  }
  const candidate={provider:'LOCAL',manifests,outputs:native.outputs.map(output=>({path:output.path,sha256:output.sha256}))};
  return {root,state:{asset:{task,domain:'AUDIO'}},brief,candidate,status:{assetSha256:'a'.repeat(64)},native,manifests,sourceRequest};
}
function historicalFixture({wrongRoot=false,mutateInvocation=()=>{},mutateNeutral=()=>{}}={}){
  const current=fixture(),history='history/original-'+(++sequence),originalTask='old-audio',sourceRevision='1'.repeat(40);
  const oldSource=identity(write(history+'/inputs/license-source.txt','OWNED original license assertion, no real terms accepted'));
  const oldLicense=identity(write(history+'/inputs/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends:[spec.backend],licenseIds:['OWNED fixture only'],sourceEvidence:{path:'inputs/license-source.txt',sha256:oldSource.sha256}}));
  const oldRights=identity(write(history+'/inputs/rights.json',{schemaVersion:'bubo-media-rights/v1',task:originalTask,owner:'Owned historical fixture',promptRightsConfirmed:true,generationAllowed:true}));
  const oldInstallation=identity(write(history+'/installations/sfx.json',{schemaVersion:'bubo-media-installation/v1',backend:spec.backend,licenses:[{path:'inputs/license.json',sha256:oldLicense.sha256}]}));
  const brief=copy(base);brief.historicalRoot=history;brief.request.rights=oldRights;brief.request.installation=oldInstallation;
  const nativeRequest={schemaVersion:'bubo-media-request/v1',requestId:'old-native',task:originalTask,backend:spec.backend,outputDirectory:'staging',
    rights:{path:'inputs/rights.json',sha256:oldRights.sha256},installation:{path:'installations/sfx.json',sha256:oldInstallation.sha256},settings:brief.request.settings,budget:brief.request.budget,items:brief.request.items.map(item=>({...item,width:null,height:null}))};
  const sourceRequest=identity(write(history+'/inputs/request.json',nativeRequest)),oldMedia=identity(write(history+'/inputs/media.json','Owned original media policy assertion'));
  const host={schemaVersion:'bubo-host-context/v1',projectRoot:wrongRoot?root:path.join(root,history),task:originalTask,policy:{purpose:'local-media',pipeline:'LOCAL',media:{path:'inputs/media.json',sha256:oldMedia.sha256}}};
  const hostContext=identity(write(history+'/context.json',host));
  const output=identity(write(history+'/staging/old-native/000.wav','OWNED original synthetic nonaudio bytes'));
  const templateNative=current.native,measured={...copy(templateNative.outputs[0]),path:'staging/old-native/000.wav',sha256:output.sha256,bytes:fs.statSync(path.join(root,output.path)).size,requested:nativeRequest.items[0]};
  const native={...copy(templateNative),requestPath:'inputs/request.json',requestSha256:sourceRequest.sha256,hostContextSha256:hostContext.sha256,mediaPolicySha256:oldMedia.sha256,
    rights:nativeRequest.rights,installation:nativeRequest.installation,outputs:[measured]};
  const nativeManifest=identity(write(history+'/state/native-manifest.json',native));
  const result={schemaVersion:'bubo-execution-result/v1',apiVersion:1,workflow:'media',operation:'generate',status:'succeeded',runtime:native.runtimeBuild,data:native,hostContextSha256:hostContext.sha256};
  const nativeResult=identity(write('inputs/original-result-'+sequence+'.json',result));
  const invocation={sourceRevision,startedAt:'2026-10-30T00:59:00Z',command:['Owned-bubo.exe','media','generate','--api-version','1','--root',path.join(root,history),'--host-context','context.json','--manifest','inputs/request.json']};mutateInvocation(invocation);
  const sourceRevisionEvidence=identity(write('inputs/original-invocation-'+sequence+'.json',invocation));
  const neutral=JSON.parse(fs.readFileSync(path.join(root,current.manifests[0].path),'utf8'));
  neutral.runId='old-native-0';neutral.generation.parameters={...neutral.generation.parameters,nativeManifest,nativeResult,hostContext,sourceRequest,
    historicalRoot:history,requested:measured.requested,actual:measured.actual,execution:native.actualSettings,
    runtime:{...neutral.generation.parameters.runtime,sourceRevisionEvidence}};
  neutral.outputs=[{stagedPath:output.path,sha256:output.sha256,status:'staged',runtimeTarget:{unavailable:true,reason:'Owned retained fixture; no promotion'}}];mutateNeutral(neutral);
  const manifest=identity(write('inputs/historical-wrapper-'+sequence+'.json',neutral));
  return {root,state:{asset:{task,domain:'AUDIO'}},brief,candidate:{provider:'LOCAL',origin:'historical-import',manifest,manifests:[manifest],outputs:[output]},status:current.status,historicalRoot:history,native};
}
try{
  check(spec.domain==='AUDIO'&&spec.modalities.includes('ambience'),'AUDIO owns SFX and ambience independently');
  check(spec.validateBrief(base,{root,task}).kind==='sfx','Actual native-shaped local brief validates current typed rights/licenses');
  const ambience=copy(base);ambience.kind='ambience';ambience.loopIntent=true;ambience.request.items[0].loopCandidate=true;
  check(spec.validateBrief(ambience,{root,task}).kind==='ambience','Ambience uses the same supported SFX settings with explicit loop intent');
  for(const [label,change] of [
    ['unknown top-level control',b=>b.normalize=true],['unsupported width',b=>b.request.items[0].width=256],
    ['old duration alias',b=>{b.request.items[0].durationSeconds=1;delete b.request.items[0].seconds;}],
    ['old budget aliases',b=>b.request.budget.maxOutputs=1],['hidden provider fallback',b=>b.provider='AUTO'],
    ['long local ambience',b=>{b.kind='ambience';b.request.items[0].seconds=48;}],['too-short duration',b=>b.request.items[0].seconds=0.1],
    ['fractional seed',b=>b.request.items[0].seed=1.5],['unsafe rounded seed',b=>b.request.items[0].seed=Number.MAX_SAFE_INTEGER+1],
    ['unsupported precision',b=>b.request.settings.precision='bfloat16'],['implicit device fallback',b=>b.request.settings.device='cpu'],
    ['unsupported offload',b=>b.request.settings.offload='auto'],['unsupported steps',b=>b.request.items[0].steps=201],
    ['unsupported guidance',b=>b.request.items[0].guidance=13],['ignored negative prompt',b=>{b.request.items[0].guidance=1;b.request.items[0].negativePrompt='noise';}],
    ['loop contradiction',b=>b.loopIntent=true],['extra variant beyond count',b=>b.request.items.push({...b.request.items[0],id:'extra'})],
    ['duplicate item ID',b=>{b.request.budget.maximumOutputs=2;b.request.items.push(copy(b.request.items[0]));}],
    ['wrong acceptance case',b=>b.request.acceptance={case:'music',kind:'candidate',approval:rights}],
    ['negative technical threshold',b=>b.technical.maxPeak=-1],['infinite byte budget',b=>b.request.budget.maximumTotalBytes=Infinity]
  ]){const value=copy(base);change(value);rejects(()=>spec.validateBrief(value,{root,task}),/Unsupported|unsupported|requires|require|Invalid|invalid|exceeds|match|matching|bounded|unique|must|finite|fields|Negative|fallback|variation/i,label+' fails before native claims');}
  const native=spec.request(base,{root,asset:{task}});
  check(native.backend==='stable-audio-open'&&native.settings.precision==='float16'&&native.items[0].seconds===1,'Request builder uses actual pinned native DTO names and selected backend');
  check(native.requestId===undefined&&native.outputDirectory===undefined,'Native version-owned request/output paths remain shared lifecycle authority');
  const noGeneration=copy(base);noGeneration.request.rights=identity(write('inputs/import-rights.json',{schemaVersion:'bubo-media-rights/v1',task:'original-task',owner:'Owned historical fixture',promptRightsConfirmed:true,generationAllowed:false}));
  check(spec.validateBrief(noGeneration,{root,task}).request.rights.path==='inputs/import-rights.json','Historical planning/import needs no fresh generation grant or task relabeling');
  rejects(()=>spec.request(noGeneration,{root,asset:{task}}),/generation authority/,'Actual dispatch requires current task generation permission');
  const beforeSource=fs.readFileSync(path.join(root,permissionSource.path));write(permissionSource.path,'Changed assertion bytes');
  rejects(()=>spec.validateBrief(base,{root,task}),/source changed/,'Nested license-source mutation cannot hide behind unchanged receipt JSON');fs.writeFileSync(path.join(root,permissionSource.path),beforeSource);
  const context=fixture(),report=spec.technical(context);
  check(report.status==='passed'&&report.measurements[0].durationSeconds===1&&report.measurements[0].sampleRate===44100,'Native-shaped current receipt chain supplies its measured duration/format');
  check(report.measurements[0].peak===0.8&&report.measurements[0].amplitudePreserved,'Native measured peak and amplitude are preserved');
  check(report.unavailable.lufs.unavailable&&report.unavailable.loopQuality.unavailable&&report.unavailable.cleanupCounters.unavailable,'Unsupported loudness/loop/driver counters remain explicitly unavailable');
  check(spec.validateTechnicalReport(report,context)===report,'Current complete report semantically revalidates native measurements');
  const nullable=fixture(base,{mutateNative:n=>Object.assign(n.outputs[0].requested,{width:null,height:null,music:null,voice:null})});
  check(spec.technical(nullable).status==='passed','Native serialized absent optional controls remain compatible as null without rewriting the original request');
  check(spec.technical(fixture(base,{mutateSource:r=>Object.assign(r.items[0],{width:null,height:null})})).status==='passed','Historical native raw requests with explicit null optional dimensions retain semantic ancestry');
  rejects(()=>spec.technical(fixture(base,{mutateNative:n=>n.outputs[0].requested.width=64})),/differs/,'Non-null native image controls are never normalized away');
  const forged=copy(report);forged.measurements[0].peak=0.1;rejects(()=>spec.validateTechnicalReport(forged,context),/differs/,'Generic-core technical-report forgery cannot bypass current AUDIO analysis');
  const strict=copy(base);strict.technical.maxPeak=0.5;check(spec.technical(fixture(strict)).status==='failed','Explicit peak threshold fails honestly without normalizing bytes');
  for(const [label,options] of [
    ['altered sample rate',{mutateNative:n=>n.outputs[0].sampleRate=48000}],['missing measurements',{mutateNative:n=>delete n.outputs[0].rms}],
    ['wrong actual settings',{mutateNative:n=>n.outputs[0].actual.seed=123}],['wrong native requested settings',{mutateSource:r=>r.settings.precision='float32'}],
    ['neutral actual mismatch',{mutateNeutral:n=>n.generation.parameters.actual={seed:111}}],['wrong native backend',{mutateNative:n=>n.backend='ace-step-turbo'}],
    ['failed unload',{mutateNative:n=>n.unloaded=false}],
    ['contradictory backend version',{mutateNeutral:n=>n.backend.toolVersion='9'.repeat(40)}],
    ['contradictory workflow revision',{mutateNeutral:n=>n.workflow.revision='9'.repeat(40)}],
    ['contradictory worker digest',{mutateNeutral:n=>n.workflow.digest='9'.repeat(64)}],
    ['contradictory runtime revision',{mutateNeutral:n=>n.generation.parameters.runtime.revision='9'.repeat(40)}],
    ['contradictory resource catalog',{mutateNeutral:n=>n.generation.parameters.runtime.resourceCatalogSha256='9'.repeat(64)}],
    ['contradictory model name',{mutateNeutral:n=>n.model.name='wrong-model'}],
    ['contradictory model revision',{mutateNeutral:n=>n.model.revision='wrong-revision'}],
    ['contradictory model digest',{mutateNeutral:n=>n.model.digest='9'.repeat(64)}],
    ['contradictory model license',{mutateNeutral:n=>n.model.license='wrong-license'}],
    ['contradictory model catalogue snapshot',{mutateNeutral:n=>n.generation.parameters.modelCatalog.sha256='9'.repeat(64)}]
  ])rejects(()=>spec.technical(fixture(base,options)),/differ|invalid|another|Only|lifecycle|native/i,label+' is rejected from authoritative analysis');
  const duration=spec.technical(fixture(base,{mutateNative:n=>n.outputs[0].frames=88200}));check(duration.status==='failed','Requested duration cannot replace conflicting actual frame measurement');
  const changed=fixture();fs.appendFileSync(path.join(root,changed.candidate.outputs[0].path),'changed');rejects(()=>spec.technical(changed),/source changed/,'Current staged byte hash is rechecked before analysis');
  const incomplete=fixture();incomplete.candidate.outputs=[];rejects(()=>spec.technical(incomplete),/complete requested candidate/,'Missing variant output cannot pass complete-batch technical coverage');
  const cloud=JSON.parse(fs.readFileSync(path.join(runtime.BASE,'.media/pipelines/audio/examples/brief.cloud.json'),'utf8'));cloud.request.rights=rights;
  const cloudContext={root,state:{asset:{task}},brief:cloud,candidate:{provider:'CLOUD',outputs:context.candidate.outputs},status:context.status};
  check(spec.technical(cloudContext).checks[0].status==='unavailable','Missing CLOUD analysis stays unavailable rather than borrowing requested metrics');
  rejects(()=>spec.request(cloud,{root,asset:{task}}),/session capability/,'CLOUD generation cannot silently fall back to LOCAL');
  rejects(()=>spec.technical(fixture(base,{mutateResult:r=>r.apiVersion=1})),/ancestry differs/,'API1 evidence cannot masquerade as a current API2 dispatch');
  const history=historicalFixture(),historyReport=spec.technical(history);
  check(historyReport.status==='passed'&&historyReport.generationIdentities[0].sourceRevision==='1'.repeat(40),'Original-root import retains actual original commit and typed raw source evidence without rewriting it');
  check(historyReport.generationIdentities[0].sourceRunId==='old-native','Retained original run ID is not relabeled as a current dispatch');
  rejects(()=>spec.request(history.brief,{root,asset:{task}}),/import-only/,'A historical-root brief cannot authorize a new native generation');
  const outside=copy(history.brief);outside.historicalRoot='../outside';rejects(()=>spec.validateBrief(outside,{root,task}),/Traversal|escapes/,'Historical root cannot escape the current project');
  rejects(()=>spec.technical(historicalFixture({wrongRoot:true})),/projectRoot/,'Rooted import requires the exact untouched original context projectRoot');
  rejects(()=>spec.technical(historicalFixture({mutateNeutral:n=>n.generation.parameters.historicalRoot='another-root'})),/mapping differs/,'Brief and provenance cannot select different original roots');
  rejects(()=>spec.technical(historicalFixture({mutateInvocation:i=>i.sourceRevision='9'.repeat(40)})),/contradicts/,'Original invocation revision cannot contradict normalized provenance');
  rejects(()=>spec.technical(historicalFixture({mutateInvocation:i=>i.command[i.command.indexOf('--manifest')+1]='inputs/other.json'})),/invocation differs/,'Invocation must bind the original request and context, not just a claimed version');
  const unanchored=fixture(base,{mutateNeutral:n=>{delete n.generation.parameters.runtime.sourceRevisionEvidence;const unknown={unavailable:true,reason:'Owned legacy build has no revision disclosure'};n.backend.toolVersion=unknown;n.workflow.revision=unknown;n.generation.parameters.runtime.revision=unknown;}});
  check(spec.technical(unanchored).generationIdentities[0].sourceRevision.unavailable,'Truly undisclosed source revision remains explicit unavailable rather than a current PIN guess');
  rejects(()=>spec.technical(fixture(base,{mutateNeutral:n=>n.workflow.digest={unavailable:true,reason:'hide known digest'}})),/contradicts/,'A disclosed native worker digest cannot be hidden behind unavailable');
  const humanSource=identity(write('inputs/listening-source.json',{fixture:'Synthetic human-source assertion only, not an actual listening verdict'}));
  const content={schemaVersion:'hephaera-media-review/v1',assetSha256:context.status.assetSha256,outputs:context.candidate.outputs,kind:'content',verdict:'accepted',reviewer:'Owned fixture',reason:'Exercise validation plumbing only',sourceEvidence:humanSource,
    criteria:{listenedEntireOutput:true,matchesBrief:true,unwantedSpeechMusicAbsent:true,artifactsAcceptable:true,headTailAccepted:true}};
  check(spec.validateReview(content,context)===content,'Explicit complete AUDIO review criteria validate synthetic source plumbing');
  const missed=copy(content);missed.criteria.headTailAccepted=false;rejects(()=>spec.validateReview(missed,context),/complete-listening/,'Incomplete full-output content criteria reject acceptance');
  const loopContext={...context,brief:ambience};rejects(()=>spec.validateReview(content,loopContext),/loop-seam/,'Loop intent requires separately explicit seam review');
  const loopReview=copy(content);loopReview.criteria.loopSeamReviewed=true;check(spec.validateReview(loopReview,loopContext)===loopReview,'Explicit seam criterion completes only the requested loop review gate');
  const rejected={...content,verdict:'rejected',criteria:{matchesBrief:false}};check(spec.validateReview(rejected,context).verdict==='rejected','Explicit rejection remains recordable without fabricating positive criteria');
  const engine={engine:'THREEJS',sha256:'3'.repeat(64)},distributionSource=identity(write('inputs/distribution-source.json',{fixture:'Not real distribution authorization'}));
  const rightsEvidence=identity(write('inputs/distribution.json',{schemaVersion:'hephaera-audio-distribution/v1',task,purpose:base.purpose,rightsConfirmed:true,sourceEvidence:distributionSource}));
  const playbackSource=identity(write('inputs/playback-source.json',{fixture:'Not real target playback'}));
  const targetEvidence=identity(write('inputs/target.json',{schemaVersion:'hephaera-audio-runtime-evidence/v1',task,engine,outputs:context.candidate.outputs,spatialization:'2d',loopIntent:false,playbackReviewed:true,loadDisposeReviewed:true,loopSeamReviewed:false,sourceEvidence:playbackSource}));
  const runtimeReview={...content,kind:'runtime',criteria:{targetPlaybackReviewed:true,loadDisposeReviewed:true,spatializationReviewed:true},engine,target:{spatialization:'2d',loopIntent:false},rightsEvidence,targetEvidence};
  check(spec.validateRuntimeReview(runtimeReview,context)===runtimeReview,'Runtime review binds separate rights and selected-engine source evidence');
  const noRights=copy(runtimeReview);delete noRights.rightsEvidence;rejects(()=>spec.validateRuntimeReview(noRights,context),/identity|object/,'Generation rights cannot replace separate runtime distribution evidence');
  const originalDistribution=fs.readFileSync(path.join(root,distributionSource.path));write(distributionSource.path,'changed');rejects(()=>spec.validateRuntimeReview(runtimeReview,context),/source changed/,'Nested distribution assertion mutation blocks target admission');fs.writeFileSync(path.join(root,distributionSource.path),originalDistribution);
  const originalPlayback=fs.readFileSync(path.join(root,playbackSource.path));write(playbackSource.path,'changed');rejects(()=>spec.validateRuntimeReview(runtimeReview,context),/source changed/,'Nested playback source mutation blocks target admission');fs.writeFileSync(path.join(root,playbackSource.path),originalPlayback);
  const wrongSpatial=copy(runtimeReview);wrongSpatial.target.spatialization='3d';rejects(()=>spec.validateRuntimeReview(wrongSpatial,context),/spatialization/,'Runtime spatialization cannot silently change the reviewed brief intent');
  const result={assertions:observations.length,observations,limits:['Owned metadata and native-shaped receipt fixtures only','No actual model installation/inference/decoding/acoustic analysis/human review/runtime promotion'],nativeShapeSource:'runtime/bubo/src/media/Domain/Contracts.cs and Application/MediaService.cs'};
  fs.writeFileSync(path.join(evidence,'latest.json'),JSON.stringify(result,null,2)+'\n');console.log('AUDIO spec checks passed: '+observations.length+' assertions; no models or real media used.');
}finally{
  if(!runtime.within(evidence,root)||path.dirname(root)!==evidence||!path.basename(root).startsWith('owned-'))throw new Error('Refusing unsafe owned fixture cleanup');
  fs.rmSync(root,{recursive:true,force:true});
}
