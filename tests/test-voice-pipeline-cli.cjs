'use strict';

// Real CLI/shared lifecycle with owned metadata and harmless nonaudio bytes.
// Every license, consent, review, measurement and runtime grant here is synthetic;
// none establishes actual human identity, acoustic quality or permission.
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const runtime=require('../commands/lib/bubo-runtime.cjs'),contracts=require('../commands/lib/media-pipeline-contract.cjs');
const lifecycle=require('../commands/lib/media-pipeline-state.cjs'),engines=require('../commands/lib/engine-contract.cjs');
const coordinator=require('../commands/lib/media-pipeline-command.cjs'),spec=require('../commands/lib/voice-pipeline.cjs');
const cache=path.basename(runtime.BASE)==='.hephaera'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.hephaera/.cache');
const evidence=path.join(cache,'tasks/hephaera-voice-pipeline/evidence/cli-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')),task='owned-voice-cli',workspace='.hephaera/.cache/owned-media',mediaState='.hephaera/.cache/shared-media-allowance';
const observations=[],unavailable={unavailable:true,reason:'Owned synthetic metadata only; no model, real speaker or acoustic observation.'};
const copy=value=>JSON.parse(JSON.stringify(value)),digest=value=>crypto.createHash('sha256').update(JSON.stringify(runtime.canonical(value))).digest('hex');
function check(value,message){assert(value,message);observations.push(message);}
function write(name,value){const full=path.join(root,name);fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,typeof value==='string'||Buffer.isBuffer(value)?value:JSON.stringify(value,null,2)+'\n');return name;}
const ref=name=>lifecycle.identity(root,name);
function cli(operation,args=[],expected=0){
  const result=cp.spawnSync(process.execPath,[path.join(runtime.BASE,'commands/lib/media-pipeline-command.cjs'),'VOICE',operation,'--root',root,...args],{encoding:'utf8',windowsHide:true});
  check(result.status===expected,'Actual VOICE CLI exit for '+operation+': '+result.stderr);
  if(expected!==0)return result.stdout.trim().startsWith('{')?JSON.parse(result.stdout):result.stderr;
  const value=JSON.parse(result.stdout);check(result.stdout.trim().startsWith('{')&&result.stdout.trim().endsWith('}'),'CLI emits one JSON object: '+operation);return value;
}
function reject(operation,args,pattern){const message=cli(operation,args,1);check(pattern.test(typeof message==='string'?message:JSON.stringify(message)),'Rejected '+operation+' at the intended boundary: '+JSON.stringify(message));}
function snapshot(folder=root){const rows=[];function visit(dir){for(const name of fs.readdirSync(dir).sort()){const full=path.join(dir,name),stat=fs.lstatSync(full);rows.push([path.relative(folder,full),stat.isDirectory()?'dir':stat.isSymbolicLink()?'link':runtime.hash(full)]);if(stat.isDirectory()&&!stat.isSymbolicLink())visit(full);}}visit(folder);return JSON.stringify(rows);}
const current=stateFile=>lifecycle.status({root,stateFile});
const media='# MEDIA.md\nGenerated from Hephaera media pipeline templates:\n- CLOUD\n- LOCAL\n---\n'+['Pipeline Availability','Capability Matrix','Destinations And Budgets','Rights, Consent, And Provenance','Review And Promotion'].map(x=>'## '+x+'\n').join('\n')+'Image, music, sound-effect SFX and voice are independent. Require the user to choose a provider. Never switch or fall back between providers silently.\n';
write('MEDIA.md',media);write(`.hephaera/.cache/tasks/${task}/TASK.md`,'# Owned synthetic VOICE test task\n');contracts.generate({root,domain:'VOICE',inline:true});
write('inputs/prompt-rights.json',{schemaVersion:'bubo-media-rights/v1',task,owner:'Owned synthetic fixture only',promptRightsConfirmed:true,generationAllowed:true});
const licenseSource=ref(write('inputs/license-source.json',{fixture:'No real license accepted'}));
const backends=['qwen3-tts-customvoice','qwen3-tts-base'];
write('inputs/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends,licenseIds:['owned-synthetic-only'],sourceEvidence:licenseSource});
for(const backend of backends)write('inputs/'+backend+'-installation.json',{schemaVersion:'bubo-media-installation/v1',backend,licenses:[ref('inputs/license.json')]});
const sampling={maximumNewTokens:512,doSample:true,temperature:0.9,topK:50,topP:1,repetitionPenalty:1.05,subtalkerDoSample:true,subtalkerTemperature:0.9,subtalkerTopK:50,subtalkerTopP:1};
const reference={audio:ref(write('inputs/owned-reference.wav','OWNED nonaudio reference bytes; no real speaker')),transcript:ref(write('inputs/owned-transcript.txt','Owned fictional words only.'))};
reference.rights=ref(write('inputs/recording-rights.json',{schemaVersion:'bubo-voice-reference-rights/v1',task,owner:'Owned synthetic fixture',audio:reference.audio,transcript:reference.transcript,recordingRightsConfirmed:true}));
const consentSource=ref(write('inputs/consent-source.json',{fixture:'Owned source; no actual human identity or permission'}));
reference.consent=ref(write('inputs/native-consent.json',{schemaVersion:'bubo-voice-consent/v1',task,speaker:'Owned synthetic speaker assertion',audio:reference.audio,transcript:reference.transcript,speakerRightsConfirmed:true,consentGranted:true,scope:'local-voice-cloning',sourceEvidence:consentSource}));
const localUseSource=ref(write('inputs/local-use-source.json',{fixture:'Owned purpose-scoped assertion only'}));
const purpose='Owned synthetic test; no real speech requested';
const localUse=ref(write('inputs/local-use.json',{schemaVersion:'hephaera-voice-local-use/v1',task,purpose,scope:'local-voice-cloning',references:[{itemId:'owned',...reference}],generationAllowed:true,sourceEvidence:localUseSource}));
function brief(kind){const cloned=kind==='consented-cloning';return {schemaVersion:'hephaera-voice-brief/v1',kind,purpose,provider:'LOCAL',spatialization:'2d',loopIntent:false,...(cloned?{localUse}:{}),request:{rights:ref('inputs/prompt-rights.json'),installation:ref('inputs/'+backends[cloned?1:0]+'-installation.json'),settings:{device:'cuda:0',precision:'bfloat16',offload:'none'},budget:{maximumOutputs:1,maximumBytesPerOutput:16777216,maximumTotalBytes:16777216,maximumPixels:4096,maximumAudioSeconds:30},items:[{id:'owned',prompt:'A fictional lantern shines beside the gate.',negativePrompt:'',seed:17,loopCandidate:false,voice:{language:'english',preset:cloned?null:'ryan',expression:cloned?'':'Calm and clear.',sampling:copy(sampling),reference:cloned?copy(reference):null}}]},technical:{maxPeak:1,maxClippedFraction:0,maxSilentFraction:1}};}
const preset=brief('preset-speech'),cloning=brief('consented-cloning');write('inputs/preset-brief.json',preset);write('inputs/cloning-brief.json',cloning);
// Read tracked native catalogue declarations only, never private cache/model files.
const catalogue=JSON.parse(fs.readFileSync(path.join(runtime.BASE,'runtime/bubo/resources/media/catalog.json'),'utf8'));
function metadata(item,kind,definition){
  const v=item.voice,files=definition.files,selected=name=>files.find(row=>row.path===name),components=['talker:bfloat16','speech-tokenizer:bfloat16',...(v.reference?['speaker-encoder:bfloat16']:[])];
  const keys=['max_new_tokens','do_sample','temperature','top_k','top_p','repetition_penalty','subtalker_dosample','subtalker_temperature','subtalker_top_k','subtalker_top_p'];
  return {protocol:'bubo-voice-settings/v1',backend:definition.id,sourceRevision:definition.source.revision,
    identities:{revision:selected('model.safetensors').revision,modelType:kind==='preset-speech'?'custom_voice':'base',modelSize:'1b7',configSha256:selected('config.json').sha256,weightsSha256:selected('model.safetensors').sha256,speechTokenizerWeightsSha256:selected('speech_tokenizer/model.safetensors').sha256,sourceRevision:definition.source.revision,sourceFiles:definition.source.runtimeSourceFiles,sourceAdaptations:definition.source.adaptations.map(row=>({path:row.path,resource:path.posix.basename(row.resource),originalSha256:row.originalSha256,replacementSha256:row.replacementSha256}))},
    text:item.prompt,language:v.language,preset:v.preset,expression:v.expression,sampling:v.sampling,upstreamSampling:Object.fromEntries(Object.values(v.sampling).map((value,index)=>[keys[index],value])),nonStreamingMode:true,
    rng:{seed:item.seed,python:'random.seed',numpy:'numpy.random.seed',torch:'torch.manual_seed',cuda:'torch.cuda.manual_seed_all',torchInitialSeed:item.seed,cudaInitialSeeds:[item.seed],scope:'per-item-process-rng',crossPlatformBitwiseReproducibility:false},
    termination:{generatedTokens:11,audioCodeFrames:10,maximumNewTokens:v.sampling.maximumNewTokens,eosTokenId:2150,eosObserved:true,lengthCapReached:false,reason:'eos',truncated:false,observation:'actual-talker-generate-sequences-before-wrapper-code-filter'},
    reference:v.reference?{originalSha256:v.reference.audio.sha256,transcriptSha256:v.reference.transcript.sha256,rightsSha256:v.reference.rights.sha256,consentSha256:v.reference.consent.sha256,decodedSha256:'a'.repeat(64),decodedPcmSha256:'b'.repeat(64),decodedFile:'reference-000.wav',decoder:'PyAV',decoderVersion:'19.0.2',decoderLibraries:{fixture:'not actual decoder observations'},container:'wav',codec:'pcm_f32le',sourceSampleRate:24000,sourceChannels:1,sampleRate:24000,channels:1,frames:24000,sampleFormat:'float32',sampleFormatConversion:'libswresample planar float32 full-scale PCM conversion',downmix:'arithmetic-mean-of-source-channels',resampling:'libswresample-mono-float32-to24000Hz',externalDataReferences:false,selfContainedDataReferences:0,denoise:false,trim:false,normalization:false,xVectorOnlyMode:false}:null,
    measurements:{sampleRate:24000,channels:1,frames:19200,peak:0.5,rms:0.1,clippedFraction:0,silentFraction:0.1},componentPrecisions:components,attention:'sdpa',normalization:false,intrinsicDecoderClamp:{minimum:-1,maximum:1,source:'Qwen3TTSTokenizerV2Decoder.forward',preserved:true},referencePrefixRemoval:v.reference?'upstream-proportional-code-prefix':null,actualOutputCount:1,humanReview:'pending',promotion:false};
}
function provenance(selected,prefix,sourceTask=task){
  const backend=backends[selected.kind==='preset-speech'?0:1],definition=catalogue.backends.find(row=>row.id===backend),item=selected.request.items[0];
  const sourceRequest={schemaVersion:'bubo-media-request/v1',requestId:'owned-historical-'+prefix.replace(/\W/g,'-'),task:sourceTask,backend,outputDirectory:workspace+'/staging/voice',...selected.request};
  const source=write(prefix+'/request.json',sourceRequest),host=write(prefix+'/context.json',{schemaVersion:'bubo-host-context/v1',projectRoot:root,task:sourceTask,policy:{purpose:'local-media',pipeline:'LOCAL',media:ref('MEDIA.md')},fixture:'No native execution'});
  const sourceRevision='1'.repeat(40),build={cliSha256:'6'.repeat(64),resourceCatalogSha256:'2'.repeat(64),assemblies:{},launch:{},fixture:'No actual native build'};
  const sourceRevisionEvidence=ref(write(prefix+'/build.json',{schemaVersion:'bubo-build/v1',sourceRevision,sourceDirty:false,capabilities:{build}}));
  const modelCatalog=ref(write(prefix+'/catalog.json',{schemaVersion:'bubo-media-catalog/v1',backends:[definition]}));
  const revisions=[...new Set(definition.files.map(file=>file.revision).filter(Boolean))],licenses=[...new Set(definition.files.map(file=>file.license).filter(Boolean))];
  const modelDigest=digest(definition.files.map(file=>({path:file.path,sha256:file.sha256,...(file.revision!==undefined?{revision:file.revision}:{}),...(file.repository!==undefined?{repository:file.repository}:{})})));
  const output=write(workspace+'/staging/voice/'+sourceRequest.requestId+'/000.wav','OWNED nonaudio fixture bytes; no sound was generated, listened to or accepted.');
  const m=metadata(item,selected.kind,definition),metadataFile=write(prefix+'/settings.json',m);
  const actualSettings={...selected.request.settings,componentPrecisions:m.componentPrecisions,modelVersion:m.identities.revision,linkedLibraryCommit:m.sourceRevision};
  const measured={id:item.id,path:output,sha256:ref(output).sha256,bytes:fs.statSync(path.join(root,output)).size,...m.measurements,requested:item,actual:{seed:item.seed,steps:null,guidance:null,scheduler:'autoregressive-sampling',nativeMetadata:ref(metadataFile)}};
  const native={schemaVersion:'bubo-media-manifest/v1',status:'generated-staged',backend,promotion:false,humanReview:'pending',outputs:[measured],hostContextSha256:ref(host).sha256,mediaPolicySha256:ref('MEDIA.md').sha256,runtimeBuild:build,requestPath:source,requestSha256:ref(source).sha256,requestedSettings:selected.request.settings,actualSettings,resourceCatalogSha256:build.resourceCatalogSha256,catalogSha256:modelCatalog.sha256,workerSourceSha256:'4'.repeat(64),unloaded:true,modelLoads:1,cleanup:{mechanism:'torch._C._cuda_clearCublasWorkspaces',allocatedBeforeWorkspaceClearBytes:1024,reservedBeforeWorkspaceClearBytes:2048,endingAllocatedBytes:0,endingReservedBytes:0}};
  const nativeFile=write(prefix+'/native.json',native),result=write(prefix+'/result.json',{schemaVersion:'bubo-execution-result/v1',apiVersion:2,status:'succeeded',workflow:'media',operation:'generate',hostContextSha256:ref(host).sha256,runtime:build,data:native});
  const neutral={schemaVersion:1,runId:sourceRequest.requestId+'-0',createdAt:new Date().toISOString(),backend:{kind:'local',provider:'Owned synthetic fixture',capability:backend,toolVersion:sourceRevision},modality:'voice',model:{name:backend,revision:revisions.join(';'),digest:modelDigest,license:licenses.join(';')},workflow:{name:'Owned synthetic fixture',revision:sourceRevision,digest:native.workerSourceSha256},generation:{prompt:item.prompt,negativePrompt:unavailable,seed:item.seed,parameters:{nativeManifest:ref(nativeFile),nativeResult:ref(result),hostContext:ref(host),sourceRequest:ref(source),installation:selected.request.installation,rights:selected.request.rights,nativeSettings:ref(metadataFile),acceptanceClaim:null,modelCatalog,runtime:{build,revision:sourceRevision,resourceCatalogSha256:build.resourceCatalogSha256,sourceRevisionEvidence},requested:measured.requested,actual:measured.actual,execution:actualSettings}},inputs:[{description:'Owned synthetic reference/metadata only',source:'fixture',rights:'No real media rights granted',consent:'not-applicable'}],outputs:[{stagedPath:output,sha256:ref(output).sha256,status:'staged',runtimeTarget:unavailable}],runtime:{destination:unavailable,budgets:selected.request.budget},review:{status:'pending',reviewer:unavailable,reviewedAt:unavailable,notes:'No human listened'}};
  return {manifestFile:write(prefix+'/neutral.json',neutral),output,outputs:[ref(output)],metadataFile};
}
function historicalCloningFixture(){
  const history='history-only-original',originalTask='owned-original-voice',originalRoot=path.join(root,history),map=identity=>({path:history+'/'+identity.path,sha256:identity.sha256});
  const old=(name,value)=>{write(history+'/'+name,value);return {path:name,sha256:ref(history+'/'+name).sha256};};
  const refs={audio:old('legacy-only/reference.wav','OWNED historical nonaudio reference'),transcript:old('legacy-only/transcript.txt','Owned historical fictional transcript.')};
  refs.rights=old('legacy-only/recording-rights.json',{schemaVersion:'bubo-voice-reference-rights/v1',task:originalTask,owner:'Owned synthetic original',audio:refs.audio,transcript:refs.transcript,recordingRightsConfirmed:true});
  const oldSource=old('legacy-only/consent-source.json',{fixture:'No actual original speaker consent'});
  refs.consent=old('legacy-only/consent.json',{schemaVersion:'bubo-voice-consent/v1',task:originalTask,speaker:'Owned synthetic original',audio:refs.audio,transcript:refs.transcript,speakerRightsConfirmed:true,consentGranted:true,scope:'local-voice-cloning',sourceEvidence:oldSource});
  const original=copy(cloning);original.request.items[0].voice.reference=refs;
  original.request.rights=old('legacy-only/prompt-rights.json',{schemaVersion:'bubo-media-rights/v1',task:originalTask,owner:'Owned original assertion',promptRightsConfirmed:true,generationAllowed:false});
  const oldLicenseSource=old('legacy-only/license-source.json',{fixture:'No actual license accepted'}),oldLicense=old('legacy-only/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends:[backends[1]],licenseIds:['owned-synthetic-only'],sourceEvidence:oldLicenseSource});
  original.request.installation=old('legacy-only/installation.json',{schemaVersion:'bubo-media-installation/v1',backend:backends[1],licenses:[oldLicense]});
  const source=provenance(original,'historical-build',originalTask),neutral=JSON.parse(fs.readFileSync(path.join(root,source.manifestFile),'utf8')),p=neutral.generation.parameters;
  for(const identity of [p.sourceRequest,p.modelCatalog,p.runtime.sourceRevisionEvidence,p.actual.nativeMetadata,...source.outputs])write(map(identity).path,fs.readFileSync(path.join(root,identity.path)));
  write(history+'/MEDIA.md',media);
  const context=JSON.parse(fs.readFileSync(path.join(root,p.hostContext.path),'utf8'));context.projectRoot=originalRoot;p.hostContext=ref(write(map(p.hostContext).path,context));
  const native=JSON.parse(fs.readFileSync(path.join(root,p.nativeManifest.path),'utf8'));native.hostContextSha256=p.hostContext.sha256;p.nativeManifest=ref(write(map(p.nativeManifest).path,native));
  const result=JSON.parse(fs.readFileSync(path.join(root,p.nativeResult.path),'utf8'));result.hostContextSha256=p.hostContext.sha256;result.data=native;p.nativeResult=ref(write(map(p.nativeResult).path,result));
  p.historicalRoot=history;p.sourceRequest=map(p.sourceRequest);p.installation=map(p.installation);p.rights=map(p.rights);p.nativeSettings=map(p.nativeSettings);p.modelCatalog=map(p.modelCatalog);p.runtime.sourceRevisionEvidence=map(p.runtime.sourceRevisionEvidence);p.actual.nativeMetadata=map(p.actual.nativeMetadata);
  neutral.outputs=neutral.outputs.map(output=>({...output,stagedPath:history+'/'+output.stagedPath}));
  const brief=copy(original);brief.historicalRoot=history;brief.request.rights=map(brief.request.rights);brief.request.installation=map(brief.request.installation);
  brief.localUse=ref(write('inputs/historical-local-use.json',{schemaVersion:'hephaera-voice-local-use/v1',task:originalTask,purpose:brief.purpose,scope:'local-voice-cloning',references:[{itemId:'owned',...refs}],generationAllowed:false,sourceEvidence:ref(write('inputs/historical-local-source.json',{fixture:'Current-root read-only host assertion; no actual human grant'}))}));
  const briefFile=write('inputs/historical-brief.json',brief),manifestFile=write('inputs/historical-neutral.json',neutral);
  check([...Object.values(refs),oldSource].every(identity=>!fs.existsSync(path.join(root,identity.path))),'Historical reference quartet and native human source exist only under original root');
  check(spec.validateBrief(brief,{root,task}).historicalRoot===history,'Domain validation accepts original-root native refs with current-root host assertions');
  return {brief,briefFile,manifestFile,output:history+'/'+source.output,outputs:source.outputs.map(map),stagingRoot:history+'/'+workspace+'/staging/voice'};
}
function contentReview(stateFile,source){return {schemaVersion:'hephaera-media-review/v1',assetSha256:current(stateFile).assetSha256,outputs:source.outputs,kind:'content',verdict:'accepted',reviewer:'Owned synthetic fixture; no human listening',reason:'Exercise exact evidence binding only',sourceEvidence:ref(write('inputs/human-source.json',{fixture:'No real human review'})),criteria:{listenedEntireOutput:true,spokenTextReviewed:true,pronunciationReviewed:true,artifactsAcceptable:true,presetOrReferenceMatchReviewed:true}};}
function runtimeReview(selected,stateFile,source,prefix){
  const engine=lifecycle.engineIdentity(root),human=ref('inputs/human-source.json'),target={directory:'assets/voice/'+prefix,codecs:['wav'],sampleRates:[24000],channels:[1],maxOutputBytes:16777216,maxAudioSeconds:30,spatialization:'2d',loopIntent:false};
  const rightsEvidence=ref(write(prefix+'/distribution.json',{schemaVersion:'hephaera-voice-distribution/v1',task,purpose:selected.purpose,rightsConfirmed:true,publicDisclosureConfirmed:true,sourceEvidence:ref(write(prefix+'/distribution-source.json',{fixture:'No real rights or disclosure granted'}))}));
  const targetEvidence=ref(write(prefix+'/target.json',{schemaVersion:'hephaera-voice-runtime-evidence/v1',task,engine,outputs:source.outputs,spatialization:'2d',loopIntent:false,playbackReviewed:true,loadDisposeReviewed:true,sourceEvidence:human}));
  const disclosureEvidence=selected.kind==='consented-cloning'?ref(write(prefix+'/disclosure.json',{schemaVersion:'hephaera-voice-disclosure/v1',task,purpose:selected.purpose,outputs:source.outputs,references:selected.request.items.map(item=>({itemId:item.id,...item.voice.reference})),disclosureAllowed:true,sourceEvidence:ref(write(prefix+'/disclosure-source.json',{fixture:'No real cloned-output disclosure permission'}))})):undefined;
  return {schemaVersion:'hephaera-media-review/v1',assetSha256:current(stateFile).assetSha256,outputs:source.outputs,kind:'runtime',verdict:'accepted',reviewer:'Owned synthetic fixture; no actual target',reason:'Exercise runtime/distribution/disclosure gates with harmless bytes',sourceEvidence:human,criteria:{targetPlaybackReviewed:true,loadDisposeReviewed:true,spatializationReviewed:true},engine,target,rightsEvidence,targetEvidence,...(disclosureEvidence?{disclosureEvidence}:{})};
}
async function main(){
  const shell=process.env.HEPHAERA_BASH||(process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'bash');
  const wrapper=cp.spawnSync(shell,[path.join(runtime.BASE,'commands/voice-pipeline.sh').replace(/\\/g,'/'),'--help'],{cwd:root,encoding:'utf8',windowsHide:true});
  check(wrapper.status===0&&/voice-pipeline/.test(wrapper.stdout)&&/setup-plan/.test(wrapper.stdout)&&/recover/.test(wrapper.stdout),'Real Bash VOICE wrapper help works outside an initialized host');
  const wrappedBrief=cp.spawnSync(shell,[path.join(runtime.BASE,'commands/voice-pipeline.sh').replace(/\\/g,'/'),'brief','--root',root,'--brief','inputs/cloning-brief.json'],{cwd:root,encoding:'utf8',windowsHide:true});
  check(wrappedBrief.status===0&&JSON.parse(wrappedBrief.stdout).valid,'Real Bash wrapper delegates explicit-root cloning brief without execution');
  const historical=historicalCloningFixture();check(cli('brief',['--brief',historical.briefFile]).valid,'Actual CLI brief validates historical cloning without current-root duplicate references');
  const historicalBriefIdentity=ref(historical.briefFile),historicalManifestIdentity=ref(historical.manifestFile);
  let historicalStage='init',historicalState;
  try{
    historicalState=cli('init',['--task',task,'--asset','Owned historical cloning','--version','v1','--brief',historical.briefFile,'--staging-root',historical.stagingRoot]).stateFile;
    historicalStage='import';cli('import',['--state',historicalState,'--provider','LOCAL','--manifest',historical.manifestFile,'--origin','historical-import']);
    historicalStage='validate';check(cli('validate',['--state',historicalState]).ok,'Actual historical cloning CLI validates exact native ancestry and current-root wrappers');
    const stored=lifecycle.load({root,stateFile:historicalState}),originalRefs=Object.values(historical.brief.request.items[0].voice.reference);
    check(originalRefs.every(identity=>stored.asset.references.some(current=>current.path===historical.brief.historicalRoot+'/'+identity.path&&current.sha256===identity.sha256)),'Historical init stores mapped freshness identities while retaining original-root native fields');
    const candidate=stored.events.find(event=>event.kind==='candidate');check(originalRefs.every(identity=>candidate.data.references.some(current=>current.path===historical.brief.historicalRoot+'/'+identity.path&&current.sha256===identity.sha256)),'Historical import records mapped requested-reference freshness without reading absent current-root paths');
    historicalStage='content';cli('review',['--state',historicalState,'--review',write('inputs/historical-content.json',contentReview(historicalState,historical))]);
    engines.generate(root,'THREEJS',{inline:true});historicalStage='runtime';const targetReview=runtimeReview(historical.brief,historicalState,historical,'historical-cloning-current');
    cli('review',['--state',historicalState,'--review',write('inputs/historical-runtime.json',targetReview)]);
    historicalStage='handoff';check(cli('handoff',['--state',historicalState]).promotion===false&&!fs.existsSync(path.join(root,targetReview.target.directory)),'Historical cloning reaches current-target handoff with separate current disclosure and no copying');
    const sourcePath=historical.brief.historicalRoot+'/legacy-only/consent-source.json',oldBytes=fs.readFileSync(path.join(root,sourcePath));write(sourcePath,{changedHistoricalConsentSource:true});
    try{reject('handoff',['--state',historicalState],/changed|stale|source/);}finally{fs.writeFileSync(path.join(root,sourcePath),oldBytes);}
    const importOnly=cli('revise',['--state',historicalState,'--version','v2','--brief',historical.briefFile]);reject('generate',['--state',importOnly.stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState],/import-only/);
    check(current(historicalState).nativeDispatchRequestId===null&&ref(historical.briefFile).sha256===historicalBriefIdentity.sha256&&ref(historical.manifestFile).sha256===historicalManifestIdentity.sha256,'Historical CLI retains immutable raw brief/neutral bytes and grants no fresh native dispatch');
  }catch(error){write('historical-cli-red.json',{schemaVersion:'hephaera-owned-historical-cli-regression/v1',stage:historicalStage,error:error.message,root,brief:historical.briefFile,manifest:historical.manifestFile,limits:['Owned synthetic metadata/nonaudio bytes only','No private media, model execution, human consent or listening']});throw error;}
  const schema=JSON.parse(fs.readFileSync(path.join(runtime.BASE,'.media/pipelines/voice/brief.schema.json'),'utf8'));
  const canonicalPath=new RegExp(schema.$defs.identity.properties.path.pattern);
  check(canonicalPath.test('inputs/owned.wav')&&!canonicalPath.test('../escape.wav')&&!canonicalPath.test('https://remote/voice.wav')&&!canonicalPath.test('inputs\\voice.wav'),'Published identity schema rejects noncanonical remote/escaping paths');
  check(schema.$defs.sampling.properties.maximumNewTokens.minimum===3&&schema.$defs.sampling.properties.maximumNewTokens.maximum===2048&&schema.$defs.localBudget.properties.maximumAudioSeconds.maximum===120,'Published schema retains actual native autoregressive/time bounds');
  for(const filename of ['brief.local.json','brief.cloning.local.json','brief.cloud.json']){
    const example=JSON.parse(fs.readFileSync(path.join(runtime.BASE,'.media/pipelines/voice/examples',filename),'utf8'));
    example.request.rights=preset.request.rights;if(example.provider==='LOCAL')example.request.installation=brief(example.kind).request.installation;
    if(example.kind==='consented-cloning'){example.request.items[0].voice.reference=reference;example.localUse=ref(write('inputs/example-local-use.json',{schemaVersion:'hephaera-voice-local-use/v1',task,purpose:example.purpose,scope:'local-voice-cloning',references:example.request.items.map(item=>({itemId:item.id,...reference})),generationAllowed:false,sourceEvidence:localUseSource}));}
    check(cli('brief',['--brief',write('inputs/example-'+filename,example)]).valid,'Published '+filename+' validates after supplying current owned synthetic evidence');
  }
  const before=snapshot();check(cli('brief',['--brief','inputs/cloning-brief.json']).valid,'Cloning brief validates exact owned local-use and native reference bindings');check(snapshot()===before,'Brief performs no state/model/output writes');
  for(const [name,change,pattern] of [
    ['diffusion',b=>b.request.items[0].steps=8,/unsupported/],['fixed-seconds',b=>b.request.items[0].seconds=3,/unsupported/],['loop',b=>b.loopIntent=true,/nonloop/],['sampler',b=>b.request.items[0].voice.sampling.doSample=false,/sampling/],['zero-temperature',b=>b.request.items[0].voice.sampling.temperature=0,/exclude zero/],['utf8-limit',b=>b.request.items[0].prompt='\u00e9'.repeat(2050),/UTF8-byte/],['case-alias',b=>b.request.items[0].voice.reference.transcript={...b.request.items[0].voice.reference.audio,path:b.request.items[0].voice.reference.audio.path.toUpperCase()},/distinct/],['remote',b=>b.request.items[0].voice.reference.audio.path='https://invalid/voice.wav',/canonical/],['wrong-purpose',b=>b.purpose+=' changed',/purpose/]
  ]){const changed=copy(cloning);change(changed);reject('brief',['--brief',write('inputs/invalid-'+name+'.json',changed)],pattern);}
  const noGeneration=copy(cloning),useRecord=JSON.parse(fs.readFileSync(path.join(root,localUse.path),'utf8'));useRecord.generationAllowed=false;noGeneration.localUse=ref(write('inputs/import-only-local-use.json',useRecord));
  check(cli('brief',['--brief',write('inputs/import-only-brief.json',noGeneration)]).valid,'Read-only cloning planning can retain generationAllowed:false');
  assert.throws(()=>spec.request(noGeneration,{root,asset:{task}}),/generation authority/);observations.push('Fresh dispatch rejects import-only local-use authority');
  const cloudClone=copy(cloning);cloudClone.provider='CLOUD';cloudClone.request.rights={path:'unreadable-private-sentinel.json',sha256:'0'.repeat(64)};
  reject('brief',['--brief',write('inputs/cloud-cloning.json',cloudClone)],/CLOUD cloning is unavailable/);
  const selfConsent=copy(cloning),consentRecord=JSON.parse(fs.readFileSync(path.join(root,reference.consent.path),'utf8'));consentRecord.sourceEvidence=reference.audio;
  selfConsent.request.items[0].voice.reference.consent=ref(write('inputs/recording-as-consent-source.json',consentRecord));
  const selfUse=JSON.parse(fs.readFileSync(path.join(root,localUse.path),'utf8'));selfUse.references=[{itemId:'owned',...selfConsent.request.items[0].voice.reference}];selfConsent.localUse=ref(write('inputs/self-source-use.json',selfUse));
  reject('brief',['--brief',write('inputs/self-source-brief.json',selfConsent)],/distinct/);
  // Refresh every binding so malformed transcripts reach the actual byte/text
  // admission gate instead of merely failing an old file hash.
  for(const [name,bytes,pattern]of [['invalid-utf8',Buffer.from([0xc0,0xaf]),/strict UTF8/],['nul-transcript',Buffer.from('Owned\0text'),/transcript/],['blank-transcript',Buffer.from(' \n'),/transcript/]]){
    const changed=copy(cloning),refs=copy(reference);refs.transcript=ref(write('inputs/'+name+'.txt',bytes));
    const rights=JSON.parse(fs.readFileSync(path.join(root,reference.rights.path),'utf8')),consent=JSON.parse(fs.readFileSync(path.join(root,reference.consent.path),'utf8'));rights.transcript=refs.transcript;consent.transcript=refs.transcript;
    refs.rights=ref(write('inputs/'+name+'-rights.json',rights));refs.consent=ref(write('inputs/'+name+'-consent.json',consent));changed.request.items[0].voice.reference=refs;
    const use=JSON.parse(fs.readFileSync(path.join(root,localUse.path),'utf8'));use.references=[{itemId:'owned',...refs}];changed.localUse=ref(write('inputs/'+name+'-use.json',use));
    reject('brief',['--brief',write('inputs/'+name+'-brief.json',changed)],pattern);
  }
  reject('brief',['--brief','inputs/preset-brief.json','--load','true'],/protected/);reject('generate',['--state','unread.json','--backend',backends[0]],/protected/);
  engines.generate(root,'THREEJS',{inline:true});
  const states=[];let presetStateSnapshot=null,presetStateDirectory=null;
  for(const selected of [preset,cloning]){
    const prefix=selected.kind,briefFile='inputs/'+(selected.kind==='preset-speech'?'preset':'cloning')+'-brief.json';
    const init=cli('init',['--task',task,'--asset','Owned '+prefix,'--version','v1','--brief',briefFile,'--workspace',workspace]),stateFile=init.stateFile;states.push(stateFile);
    check(current(stateFile).stage==='planned','Init creates independent '+prefix+' planning state');
    const revised=cli('revise',['--state',stateFile,'--version','v2','--brief',briefFile]);check(revised.stateFile!==stateFile&&current(revised.stateFile).nativeRequestId!==current(stateFile).nativeRequestId,'Revision retains ancestry and changes '+prefix+' native identity');
    const statusBefore=snapshot();cli('status',['--state',stateFile]);check(snapshot()===statusBefore,'Actual status writes no '+prefix+' state');
    const doctorBefore=snapshot(),doctor=cli('doctor',['--state',stateFile,'--workspace',workspace]);check(!doctor.modelLoading&&!doctor.generation&&doctor.nativeReadiness==='unverified'&&snapshot()===doctorBefore,'Actual doctor is read-only with honest unverified readiness');
    reject('generate',['--state',stateFile,'--provider','CLOUD','--workspace',workspace,'--media-state',mediaState],/conflicts/);
    reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--execute','true'],/protected/);
    reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--timeout','0'],/finite/);
    const source=provenance(selected,prefix);reject('import',['--state',stateFile,'--provider','LOCAL','--manifest',source.manifestFile],/origin/);
    const imported=cli('import',['--state',stateFile,'--provider','LOCAL','--manifest',source.manifestFile,'--origin','historical-import']);check(imported.assetStatus.nativeDispatchRequestId===null&&imported.assetStatus.contentReview==='pending','Historical import grants no dispatch or listening acceptance');
    reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState],/already has a candidate/);
    const validation=cli('validate',['--state',stateFile]);check(validation.ok&&validation.status==='passed','Owned native-shaped '+prefix+' provenance validates without model execution');
    const report=JSON.parse(fs.readFileSync(path.join(root,validation.report.path),'utf8'));check(report.measurements[0].sampleRate===24000&&report.measurements[0].channels===1&&report.executions[0].cleanup.endingReservedBytes===0,'Technical report retains native voice format and measured allocator cleanup');
    reject('handoff',['--state',stateFile],/content/);
    const content=contentReview(stateFile,source),missing=copy(content);delete missing.criteria.pronunciationReviewed;reject('review',['--state',stateFile,'--review',write(prefix+'/missing-pronunciation.json',missing)],/criteria/);
    reject('review',['--state',stateFile,'--review',write(prefix+'/wrong-output.json',{...content,outputs:[]})],/output set/);
    cli('review',['--state',stateFile,'--review',write(prefix+'/rejected.json',{...content,verdict:'rejected',criteria:{}})]);check(current(stateFile).contentReview==='rejected','Rejected '+prefix+' content remains in history');
    cli('review',['--state',stateFile,'--review',write(prefix+'/content.json',content)]);reject('handoff',['--state',stateFile],/runtime/);
    const review=runtimeReview(selected,stateFile,source,prefix),distribution=JSON.parse(fs.readFileSync(path.join(root,review.rightsEvidence.path),'utf8'));
    const noPublic={...distribution,publicDisclosureConfirmed:false},badReview={...review,rightsEvidence:ref(write(prefix+'/no-public.json',noPublic))};reject('review',['--state',stateFile,'--review',write(prefix+'/no-public-review.json',badReview)],/public disclosure/);
    if(selected.kind==='consented-cloning'){
      const missingDisclosure=copy(review);delete missingDisclosure.disclosureEvidence;reject('review',['--state',stateFile,'--review',write(prefix+'/no-disclosure.json',missingDisclosure)],/identity|path|disclosure/);
      const disclosure=JSON.parse(fs.readFileSync(path.join(root,review.disclosureEvidence.path),'utf8'));
      for(const [name,change,pattern]of[['purpose',d=>d.purpose+=' different',/disclosure/],['outputs',d=>d.outputs=[],/output set/],['reference',d=>d.references[0].itemId='other',/references/]]){const changed=copy(disclosure);change(changed);reject('review',['--state',stateFile,'--review',write(prefix+'/bad-'+name+'-review.json',{...review,disclosureEvidence:ref(write(prefix+'/bad-'+name+'.json',changed))})],pattern);}
      reject('review',['--state',stateFile,'--review',write(prefix+'/qa-consent-is-not-disclosure.json',{...review,disclosureEvidence:reference.consent})],/cloned-output disclosure|unsupported/);
    }
    cli('review',['--state',stateFile,'--review',write(prefix+'/runtime-review.json',review)]);
    const authorization=write(prefix+'/authorization.json',{schemaVersion:'hephaera-media-promotion/v1',authorized:true,assetSha256:current(stateFile).assetSha256,target:review.target,outputs:source.outputs,authorizedBy:'Owned synthetic fixture; no real permission',reason:'Exercise copying harmless owned bytes only',sourceEvidence:ref(write(prefix+'/promotion-source.json',{fixture:'Not a real promotion grant'}))});
    const mutations=[['inputs/license-source.json',{changed:true}],['inputs/human-source.json',{changed:true}],[prefix+'/distribution-source.json',{changed:true}],[source.output,'OWNED changed output bytes'],...(selected.kind==='consented-cloning'?[['inputs/owned-reference.wav','OWNED changed reference'],['inputs/owned-transcript.txt','Owned changed fictional transcript'],['inputs/consent-source.json',{changed:true}],['inputs/local-use-source.json',{changed:true}],[prefix+'/disclosure-source.json',{changed:true}]]:[])];
    for(const [name,value]of mutations){const old=fs.readFileSync(path.join(root,name));write(name,value);try{reject('handoff',['--state',stateFile],/changed|stale|source|identity/i);reject('promote',['--state',stateFile,'--authorization',authorization],/changed|stale|source|identity/i);check(!fs.existsSync(path.join(root,review.target.directory)),'Changed '+name+' blocks both handoff and copying');}finally{fs.writeFileSync(path.join(root,name),old);}}
    for(const [name,target,pattern]of[['rate',{...review.target,sampleRates:[48000]},/format/],['budget',{...review.target,maxAudioSeconds:0.5},/budget/],['path',{...review.target,directory:'.art-staging/not-runtime'},/assets child/]]){cli('review',['--state',stateFile,'--review',write(prefix+'/bad-target-'+name+'.json',{...review,target})]);reject('handoff',['--state',stateFile],pattern);}
    cli('review',['--state',stateFile,'--review',prefix+'/runtime-review.json']);const handoff=cli('handoff',['--state',stateFile]);check(!handoff.promotion&&!fs.existsSync(path.join(root,review.target.directory)),'Handoff keeps '+prefix+' staged and copies nothing');
    const foreign=write(review.target.directory+'/foreign.txt','OWNED destination sentinel');reject('promote',['--state',stateFile,'--authorization',authorization],/already exists/);check(fs.readFileSync(path.join(root,foreign),'utf8')==='OWNED destination sentinel','Promotion does not overwrite a foreign target');fs.unlinkSync(path.join(root,foreign));fs.rmdirSync(path.join(root,review.target.directory));
    const promoted=cli('promote',['--state',stateFile,'--authorization',authorization]);check(promoted.promotion&&fs.readFileSync(path.join(root,review.target.directory+'/000.wav'),'utf8').startsWith('OWNED nonaudio'),'Explicit gated '+prefix+' promotion copies only harmless fixture bytes');check(cli('recover',['--state',stateFile,'--authorization',authorization]).alreadyPromoted,'Recovery recognizes exact owned '+prefix+' completion');
    if(selected.kind==='preset-speech'){presetStateDirectory=path.join(root,lifecycle.load({root,stateFile}).directory);presetStateSnapshot=snapshot(presetStateDirectory);}
    else check(snapshot(presetStateDirectory)===presetStateSnapshot,'Cloning lifecycle leaves existing preset immutable version/history unchanged');
  }
  check(current(states[0]).nativeRequestId!==current(states[1]).nativeRequestId,'Preset/cloning native request namespaces stay distinct');
  const cloud=copy(preset);cloud.provider='CLOUD';cloud.request={rights:preset.request.rights,budget:{...preset.request.budget},items:[{id:'owned',prompt:preset.request.items[0].prompt,voice:{language:'Owned provider language',preset:'Owned provider preset',expression:''}}]};delete cloud.request.budget.maximumPixels;
  const cloudInit=cli('init',['--task',task,'--asset','Owned CLOUD speech','--version','v1','--brief',write('inputs/cloud.json',cloud)]);reject('generate',['--state',cloudInit.stateFile,'--provider','CLOUD'],/separately available authorized session capability/);
  const cloudOutput=write('.art-staging/media/voice/owned-cloud/000.wav','OWNED CLOUD provenance bytes; no speech generated'),manifest=JSON.parse(fs.readFileSync(path.join(root,'preset-speech/neutral.json'),'utf8'));
  manifest.backend={kind:'cloud-session',provider:'Owned synthetic provider',capability:'none',toolVersion:unavailable};manifest.generation.parameters={};manifest.outputs=[{stagedPath:cloudOutput,sha256:ref(cloudOutput).sha256,status:'staged',runtimeTarget:unavailable}];
  cli('import',['--state',cloudInit.stateFile,'--provider','CLOUD','--manifest',write('inputs/cloud-manifest.json',manifest)]);const unavailableAnalysis=cli('validate',['--state',cloudInit.stateFile],1);check(!unavailableAnalysis.ok&&unavailableAnalysis.checks.some(row=>row.status==='unavailable'),'CLOUD missing authoritative analysis stays explicitly unavailable');reject('handoff',['--state',cloudInit.stateFile],/technical/);
  const adapter=require('../commands/lib/bubo-media-adapter.cjs'),oldInvoke=adapter.invoke;
  try{
    let setupCalls=0;adapter.invoke=async(operation,options,settings)=>{setupCalls++;check(operation==='setup'&&!options.has('execute')&&settings.emit===false,'Setup-plan delegates dry-run only without execution');return {status:'succeeded',data:{fixture:'No native setup'}};};
    await coordinator.run(spec,['setup-plan','--root',root,'--task',task,'--provider','LOCAL','--manifest',write('inputs/setup.json',{schemaVersion:'bubo-media-setup/v1',task,backend:backends[0]})]);check(setupCalls===1,'Explicit setup planning reaches only existing native planning boundary');
    for(const selected of [preset,cloning]){
      const failure=cli('init',['--task',task,'--asset','Owned failed '+selected.kind,'--version','v1','--brief','inputs/'+(selected.kind==='preset-speech'?'preset':'cloning')+'-brief.json','--workspace',workspace]);let attempts=0;
      adapter.invoke=async(operation,options,settings)=>{attempts++;const request=JSON.parse(fs.readFileSync(path.join(root,options.get('manifest')),'utf8'));check(operation==='generate'&&request.requestId===current(failure.stateFile).nativeRequestId&&request.outputDirectory===workspace+'/staging/voice','Shared dispatch binds exact VOICE version/output namespace');check(request.backend===backends[selected.kind==='preset-speech'?0:1]&&request.items[0].prompt===selected.request.items[0].prompt&&!Object.hasOwn(request,'localUse')&&options.get('media-state')===mediaState,'Dispatch preserves exact kind/text/reference/sampler and original shared native ledger');if(selected.kind==='consented-cloning'){assert.deepEqual(request.items[0].voice.reference,reference);check(Array.isArray(settings?.policyReferences)&&[localUse,localUseSource].every(expected=>settings.policyReferences.some(actual=>actual.path===expected.path&&actual.sha256===expected.sha256)),'Cloning dispatch binds host-only local-use and human source to queued native freshness checks');}throw new Error('Owned simulated native cancellation; no native execution');};
      const args=['generate','--root',root,'--state',failure.stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--timeout','120'];await assert.rejects(coordinator.run(spec,args),/Owned simulated native cancellation/);observations.push('Simulated '+selected.kind+' cancellation propagates through actual shared dispatch');
      const failed=lifecycle.load({root,stateFile:failure.stateFile});check(failed.events.map(row=>row.kind).join(',')==='dispatch-started,dispatch-failed','Failed '+selected.kind+' keeps immutable start/failure history');await assert.rejects(coordinator.run(spec,args),/already exists or started/);
      const other=[...args];other[other.indexOf('--media-state')+1]='.hephaera/.cache/other-ledger';await assert.rejects(coordinator.run(spec,other),/already exists or started/);check(attempts===1&&lifecycle.load({root,stateFile:failure.stateFile}).events.length===2,'Changing shared-ledger path cannot reset started '+selected.kind+' attempts');
    }
  }finally{adapter.invoke=oldInvoke;}
  const report={assertions:observations.length,observations,root,limits:['Owned synthetic metadata and harmless nonaudio fixture bytes only','No private user recording/transcript/generated speech access, model loading, installation or native inference','No real human consent/listening/runtime acceptance/disclosure or project asset promotion','Substituted native setup/cancellation boundaries verify host composition/history only, not native execution or acoustic quality']};fs.writeFileSync(path.join(root,'results.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({assertions:observations.length,evidence:path.join(root,'results.json'),limits:report.limits}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
