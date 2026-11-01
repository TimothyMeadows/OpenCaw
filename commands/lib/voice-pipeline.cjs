'use strict';

// VOICE policy only. Bubo owns model identities, decoding and synthesis.
const fs=require('fs'),path=require('path'),{TextDecoder}=require('util');
const runtime=require('./bubo-runtime.cjs'),evidence=require('./media-audio-evidence.cjs');
const {SHA,ID,fail,same,object,fields,text,number,typed,read,readIdentity,nested,originalIdentity,candidateData}=evidence;
const domain='VOICE',modalities=['preset-speech','consented-cloning'],backends=['qwen3-tts-customvoice','qwen3-tts-base'];
const languages=new Set('chinese english french german italian japanese korean portuguese russian spanish'.split(' '));
const presets=new Set('aiden dylan eric ono_anna ryan serena sohee uncle_fu vivian'.split(' '));
const samplingKeys=['maximumNewTokens','doSample','temperature','topK','topP','repetitionPenalty','subtalkerDoSample','subtalkerTemperature','subtalkerTopK','subtalkerTopP'];
const upstreamKeys=['max_new_tokens','do_sample','temperature','top_k','top_p','repetition_penalty','subtalker_dosample','subtalker_temperature','subtalker_top_k','subtalker_top_p'];
const referenceKeys=['audio','transcript','rights','consent'];
const backendFor=kind=>backends[modalities.indexOf(kind)];
function localIdentity(identity,label='local voice identity'){
  typed(identity,label);
  if(identity.path.includes(':')||identity.path.includes('\\')||identity.path.startsWith('/')||identity.path.split('/').some(part=>!part||part==='.'||part==='..'))fail('Voice identities require canonical local project-relative paths.');
  runtime.syntax(identity.path);return identity;
}
function distinct(identities){if(new Set(identities.map(ref=>ref.path.toLowerCase())).size!==identities.length)fail('Voice recording, transcript, rights, consent and human source require distinct file identities.');}
function sampling(value){
  fields(value,samplingKeys,samplingKeys,'voice sampling');number(value.maximumNewTokens,3,2048,'voice token cap',true);
  if(value.doSample!==true||value.subtalkerDoSample!==true)fail('Voice requires explicit talker and subtalker sampling.');
  for(const key of ['temperature','subtalkerTemperature','topP','subtalkerTopP']){number(value[key],0,key.endsWith('Temperature')||key==='temperature'?2:1,key);if(value[key]===0)fail('Voice sampling bounds exclude zero.');}
  for(const key of ['topK','subtalkerTopK'])number(value[key],1,200,key,true);
  number(value.repetitionPenalty,1,2,'repetition penalty');
}
function voiceOptions(value,kind,local){
  const keys=local?['language','preset','expression','sampling','reference']:['language','preset','expression'];fields(value,keys,keys,'voice options');
  if(local){if(!languages.has(value.language))fail('Unsupported explicit voice language.');sampling(value.sampling);}
  else{text(value.language,'provider-declared voice language',160);text(value.preset,'provider-declared voice preset',160);}
  if(typeof value.expression!=='string'||value.expression.length>512||value.expression.includes('\0'))fail('Unsupported bounded voice expression.');
  if(!local)return;
  if(kind==='preset-speech'){if(!presets.has(value.preset)||value.reference!==null)fail('Preset speech requires a supported preset and no cloning reference.');}
  else{
    if(value.preset!==null||value.expression!=='')fail('Cloning does not support preset or expression controls.');
    fields(value.reference,referenceKeys,referenceKeys,'voice reference');for(const ref of Object.values(value.reference))localIdentity(ref);distinct(Object.values(value.reference));
  }
}
function acceptance(brief,{root}={}){
  const value=brief.request.acceptance;if(value===undefined)return;
  fields(value,['case','kind','approval'],['case','kind','approval'],'voice acceptance attempt');
  if(value.case!==brief.kind||!['candidate','revision'].includes(value.kind)||brief.request.items.length!==1)fail('Voice acceptance requires one matching bounded candidate/revision case.');
  localIdentity(value.approval,'existing acceptance approval');if(!root)return;
  const approval=read(root,value.approval).value,keys=['schemaVersion','sharedStateRoot','cases','maximumCandidates','maximumRevisions'];fields(approval,keys,keys,'existing native acceptance approval');
  const cases=['image','sfx','instrumental','supplied-lyrics','preset-speech','consented-cloning'];
  if(approval.schemaVersion!=='bubo-media-acceptance-budget/v1'||approval.maximumCandidates!==1||approval.maximumRevisions!==1||!Array.isArray(approval.cases)||approval.cases.length!==6||new Set(approval.cases).size!==6||cases.some(c=>!approval.cases.includes(c)))fail('Existing native six-case one-candidate/one-revision approval is required; host creates no budget.');
  localIdentity({path:approval.sharedStateRoot,sha256:'0'.repeat(64)},'shared acceptance state root');
}
function referenceSet(brief){return brief.request.items.map(item=>({itemId:item.id,...item.voice.reference}));}
function cloningAuthority(brief,{root,task,requireGeneration=false}={}){
  if(brief.kind!=='consented-cloning'){if(brief.localUse!==undefined)fail('Preset speech does not accept cloning local-use evidence.');return;}
  localIdentity(brief.localUse,'purpose-bound local-use evidence');if(!root)return;
  const original=ref=>originalIdentity(root,ref,brief.historicalRoot),referenceTask=requireGeneration?task:undefined;
  let observedTask=null,scope=null;
  for(const item of brief.request.items){
    const refs=item.voice.reference,identities=Object.values(refs).map(original);
    for(const ref of identities)readIdentity(root,ref);
    const audio=runtime.projectPath(root,original(refs.audio).path),transcriptFile=runtime.projectPath(root,original(refs.transcript).path);
    if(fs.statSync(audio).size<1||fs.statSync(audio).size>20971520||!['.m4a','.wav'].includes(path.extname(audio).toLowerCase()))fail('Voice recording requires a bounded local M4A or WAV file.');
    const transcriptBytes=fs.readFileSync(transcriptFile);if(transcriptBytes.length<1||transcriptBytes.length>16384)fail('Reference transcript requires1byte..16KiB.');
    let transcript;try{transcript=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(transcriptBytes);}catch{fail('Reference transcript must be strict UTF8.');}text(transcript,'exact reference transcript',4096);
    const rights=read(root,original(refs.rights)).value,consent=read(root,original(refs.consent)).value;
    fields(rights,['schemaVersion','task','owner','audio','transcript','recordingRightsConfirmed'],['schemaVersion','task','owner','audio','transcript','recordingRightsConfirmed'],'recording rights');
    fields(consent,['schemaVersion','task','speaker','audio','transcript','speakerRightsConfirmed','consentGranted','scope','sourceEvidence'],['schemaVersion','task','speaker','audio','transcript','speakerRightsConfirmed','consentGranted','scope','sourceEvidence'],'native voice consent');
    text(rights.owner,'recording rights owner',160);text(consent.speaker,'consenting speaker assertion',160);
    if(rights.schemaVersion!=='bubo-voice-reference-rights/v1'||consent.schemaVersion!=='bubo-voice-consent/v1'||!ID.test(rights.task||'')||consent.task!==rights.task||(referenceTask&&rights.task!==referenceTask)||rights.recordingRightsConfirmed!==true||consent.speakerRightsConfirmed!==true||consent.consentGranted!==true||!['local-voice-cloning','local-voice-cloning-qa'].includes(consent.scope))fail('Current reference-bound native rights and local consent scope are required.');
    same(rights.audio,refs.audio,'Recording rights audio');same(rights.transcript,refs.transcript,'Recording rights transcript');same(consent.audio,refs.audio,'Native consent audio');same(consent.transcript,refs.transcript,'Native consent transcript');
    localIdentity(consent.sourceEvidence,'recorded human consent source');distinct([...Object.values(refs),consent.sourceEvidence]);readIdentity(root,original(consent.sourceEvidence));
    if(consent.scope==='local-voice-cloning-qa'&&brief.request.acceptance?.case!=='consented-cloning')fail('QA-only native consent requires its actual matching bounded cloning acceptance case.');
    if(observedTask!==null&&(observedTask!==rights.task||scope!==consent.scope))fail('Complete cloning references must share their declared task and local-use scope.');observedTask=rights.task;scope=consent.scope;
  }
  const assertion=read(root,brief.localUse).value,keys=['schemaVersion','task','purpose','scope','references','generationAllowed','sourceEvidence'];fields(assertion,keys,keys,'purpose-bound local use');
  if(assertion.schemaVersion!=='hephaera-voice-local-use/v1'||assertion.task!==observedTask||assertion.purpose!==brief.purpose||assertion.scope!==scope||typeof assertion.generationAllowed!=='boolean'||(requireGeneration&&(assertion.task!==task||assertion.generationAllowed!==true)))fail('Exact current task/purpose/scope local-use generation authority is required.');
  same(assertion.references,referenceSet(brief),'Complete ordered local-use reference set');localIdentity(assertion.sourceEvidence,'local-use human source');
  distinct([brief.localUse,assertion.sourceEvidence]);
  for(const item of brief.request.items)for(const ref of Object.values(item.voice.reference))distinct([brief.localUse,assertion.sourceEvidence,original(ref)]);
  readIdentity(root,assertion.sourceEvidence);
}
function nativeItem(item){
  const value=evidence.normalizeNativeItem(item,['steps','guidance','seconds','width','height','music']);
  // These two values have documented GenerationItem defaults; fresh briefs require both.
  if(!Object.hasOwn(value,'negativePrompt'))value.negativePrompt='';if(!Object.hasOwn(value,'loopCandidate'))value.loopCandidate=false;return value;
}
function validateBrief(brief,context={}){
  const keys=['schemaVersion','kind','purpose','provider','spatialization','loopIntent','request','technical','historicalRoot','localUse'];fields(brief,keys,keys.slice(0,8),'VOICE brief');
  if(brief.schemaVersion!=='hephaera-voice-brief/v1'||!modalities.includes(brief.kind)||!['LOCAL','CLOUD'].includes(brief.provider)||!['2d','3d'].includes(brief.spatialization)||brief.loopIntent!==false)fail('Explicit supported VOICE kind/provider/spatialization and nonloop intent are required.');
  // The native grant is local-only. Reject before opening any reference or consent file.
  if(brief.provider==='CLOUD'&&brief.kind==='consented-cloning')fail('CLOUD cloning is unavailable under local-only reference consent; no upload or provider fallback.');
  text(brief.purpose,'VOICE purpose',1024);const local=brief.provider==='LOCAL',request=brief.request;
  if(brief.historicalRoot!==undefined){if(!local)fail('Historical root applies only to LOCAL provenance import.');localIdentity({path:brief.historicalRoot,sha256:'0'.repeat(64)},'historical root');if(context.root)evidence.sourceRoot(context.root,brief.historicalRoot);}
  const requestKeys=local?['rights','installation','settings','budget','items','acceptance']:['rights','budget','items'];fields(request,requestKeys,requestKeys.filter(k=>k!=='acceptance'),'VOICE request');typed(request.rights,'prompt rights');
  if(local){typed(request.installation,'installation');fields(request.settings,['device','precision','offload'],['device','precision','offload'],'voice execution settings');if(request.settings.device!=='cuda:0'||request.settings.precision!=='bfloat16'||request.settings.offload!=='none')fail('Voice requires explicit cuda:0/bfloat16/none; no fallback.');}
  const budgetKeys=['maximumOutputs','maximumBytesPerOutput','maximumTotalBytes','maximumAudioSeconds',...(local?['maximumPixels']:[])],b=request.budget;fields(b,budgetKeys,budgetKeys,'VOICE budget');
  number(b.maximumOutputs,1,4,'voice output count',true);number(b.maximumBytesPerOutput,1024,268435456,'per-output byte budget',true);number(b.maximumTotalBytes,b.maximumBytesPerOutput,1073741824,'total byte budget',true);number(b.maximumAudioSeconds,0.25,120,'voice measured duration budget');if(local)number(b.maximumPixels,4096,4194304,'native structural pixel budget',true);
  if(!Array.isArray(request.items)||request.items.length<1||request.items.length>Math.min(4,b.maximumOutputs))fail('Voice requires1..4 bounded items.');const ids=new Set();
  for(const item of request.items){
    const itemKeys=local?['id','prompt','negativePrompt','seed','loopCandidate','voice']:['id','prompt','voice'];fields(item,itemKeys,itemKeys,'VOICE item');text(item.id,'voice item ID',80);
    if(!ID.test(item.id)||ids.has(item.id))fail('Safe unique voice item IDs are required.');ids.add(item.id);text(item.prompt,'exact spoken text',4096);if(Buffer.byteLength(item.prompt,'utf8')>4096)fail('Spoken text exceeds the native4096UTF8-byte limit.');
    voiceOptions(item.voice,brief.kind,local);if(local){number(item.seed,0,2147483647,'voice int32 seed',true);if(item.negativePrompt!==''||item.loopCandidate!==false)fail('Voice negative prompts and loop generation are unsupported.');}
  }
  fields(brief.technical,['maxPeak','maxClippedFraction','maxSilentFraction'],['maxPeak','maxClippedFraction','maxSilentFraction'],'voice technical policy');for(const [key,max] of [['maxPeak',Number.MAX_VALUE],['maxClippedFraction',1],['maxSilentFraction',1]])if(brief.technical[key]!==null)number(brief.technical[key],0,max,key);
  acceptance(brief,context);evidence.requireRights(backendFor(brief.kind),brief,context);cloningAuthority(brief,context);return JSON.parse(JSON.stringify(brief));
}
function request(brief,{root,asset}={}){
  if(!root)fail('Current project root is required to rehash voice dispatch authority.');if(brief?.historicalRoot!==undefined)fail('Historical-root briefs are import-only.');const record=asset?.task?asset:asset?.asset;if(!record?.task)fail('Task-owned asset identity is required.');
  const value=validateBrief(brief,{root,task:record.task,requireGeneration:true});if(value.provider!=='LOCAL')fail('CLOUD preset speech is provenance-import only; no available generation adapter.');
  return {schemaVersion:'bubo-media-request/v1',task:record.task,backend:backendFor(value.kind),...value.request};
}
function generationReferences(brief,context={}){
  if(brief?.provider!=='LOCAL'||brief?.kind!=='consented-cloning')return [];
  // Host-only purpose authority must remain fresh while native admission is queued.
  // Reuse the declared identities; hashing current bytes into new identities would
  // silently authorize a changed assertion after request() admitted it.
  request(brief,context);const assertion=read(context.root,brief.localUse).value;
  return [brief.localUse,assertion.sourceEvidence].map(identity=>({...identity}));
}
function mapReference(identity,trail,{document,root,brief}={}){
  const value={...identity};
  if(brief?.provider!=='LOCAL'||brief?.kind!=='consented-cloning'||brief.historicalRoot===undefined||!Array.isArray(trail)||trail.length!==6)return value;
  let native=false;
  if(document==='brief'&&trail[0]==='request'&&trail[1]==='items'&&trail[3]==='voice'&&trail[4]==='reference'){
    const index=trail[2],numeric=typeof index==='number'?index:typeof index==='string'&&/^(0|[1-9][0-9]*)$/.test(index)?Number(index):NaN;
    native=Number.isSafeInteger(numeric)&&numeric>=0&&numeric<brief.request.items.length;
  }else if(document==='neutral')native=trail.slice(0,5).every((key,index)=>key===['generation','parameters','requested','voice','reference'][index]);
  // Only copied native quartet identities remain original-root-relative. Host
  // wrappers, local-use/disclosure sources and outputs already use current root.
  return native&&referenceKeys.includes(trail[5])?originalIdentity(root,value,brief.historicalRoot):value;
}
function inspectBatch(native,result,source,env){
  const cleanup=native.cleanup,keys=['mechanism','allocatedBeforeWorkspaceClearBytes','reservedBeforeWorkspaceClearBytes','endingAllocatedBytes','endingReservedBytes'];fields(cleanup,keys,keys,'voice cleanup');for(const key of keys.slice(1))number(cleanup[key],0,Number.MAX_SAFE_INTEGER,key,true);
  if(cleanup.mechanism!=='torch._C._cuda_clearCublasWorkspaces'||cleanup.endingAllocatedBytes!==0||cleanup.endingReservedBytes!==0)fail('Voice requires measured zero allocated and reserved cleanup counters.');
  const expected=['talker:bfloat16','speech-tokenizer:bfloat16',...(env.brief.kind==='consented-cloning'?['speaker-encoder:bfloat16']:[])];same(native.actualSettings.componentPrecisions,expected,'Actual voice component precision');
  return {cleanup,aggregateDriverMemory:{unavailable:true,reason:'Allocator counters do not measure aggregate driver/GPU memory.'}};
}
function validateObserved(actual,requested,env){
  if(actual.actual?.seed!==requested.seed||actual.actual.scheduler!=='autoregressive-sampling'||(actual.actual.steps!==null&&actual.actual.steps!==undefined)||(actual.actual.guidance!==null&&actual.actual.guidance!==undefined))fail('Actual voice sampling differs from its explicit autoregressive request.');
  const identity=originalIdentity(env.root,actual.actual.nativeMetadata,env.brief.historicalRoot),m=read(env.root,identity).value;env.reference(identity);
  const v=requested.voice,backend=backendFor(env.brief.kind),t=object(m.termination,'voice termination');
  if(m.protocol!=='bubo-voice-settings/v1'||m.backend!==backend||!/^([a-f0-9]{40}|[a-f0-9]{64})$/.test(m.sourceRevision||'')||m.text!==requested.prompt||m.language!==v.language||m.preset!==v.preset||m.expression!==v.expression||m.nonStreamingMode!==true||m.normalization!==false||m.attention!=='sdpa'||m.actualOutputCount!==1||m.humanReview!=='pending'||m.promotion!==false)fail('Actual voice text/control/raw-output metadata differs.');
  same(m.sampling,v.sampling,'Actual voice sampler');same(m.upstreamSampling,Object.fromEntries(samplingKeys.map((key,index)=>[upstreamKeys[index],v.sampling[key]])),'Actual upstream voice sampler');
  const rng={seed:requested.seed,python:'random.seed',numpy:'numpy.random.seed',torch:'torch.manual_seed',cuda:'torch.cuda.manual_seed_all',torchInitialSeed:requested.seed,scope:'per-item-process-rng',crossPlatformBitwiseReproducibility:false};for(const [key,value] of Object.entries(rng))same(m.rng?.[key],value,'Actual voice RNG '+key);
  if(!Array.isArray(m.rng.cudaInitialSeeds)||!m.rng.cudaInitialSeeds.length||m.rng.cudaInitialSeeds.some(seed=>seed!==requested.seed))fail('Actual CUDA voice RNG seeds differ.');
  number(t.generatedTokens,3,v.sampling.maximumNewTokens,'actual voice generated tokens',true);
  if(t.reason!=='eos'||t.eosObserved!==true||t.truncated!==false||t.eosTokenId!==2150||t.maximumNewTokens!==v.sampling.maximumNewTokens||t.audioCodeFrames!==t.generatedTokens-1||t.lengthCapReached!==(t.generatedTokens===t.maximumNewTokens)||t.observation!=='actual-talker-generate-sequences-before-wrapper-code-filter'||Math.abs(actual.frames-t.audioCodeFrames*1920)>(v.reference?1:0))fail('Voice requires observed EOS, no truncation and exact generated token/code-frame accounting.');
  same(m.intrinsicDecoderClamp,{minimum:-1,maximum:1,source:'Qwen3TTSTokenizerV2Decoder.forward',preserved:true},'Retained intrinsic voice decoder clamp');
  for(const key of ['sampleRate','channels','frames','peak','rms','clippedFraction','silentFraction'])if(!Number.isFinite(m.measurements?.[key])||Math.abs(m.measurements[key]-actual[key])>1e-9)fail('Actual voice measurements differ from native waveform inspection.');
  if(actual.peak>1||actual.rms>1)fail('Voice measurements contradict retained intrinsic decoder clamp.');
  const components=['talker:bfloat16','speech-tokenizer:bfloat16',...(v.reference?['speaker-encoder:bfloat16']:[])];same(m.componentPrecisions,components,'Observed voice component precision');
  if(v.reference){
    const r=object(m.reference,'observed private reference');for(const [key,ref] of Object.entries(v.reference))if(r[{audio:'originalSha256',transcript:'transcriptSha256',rights:'rightsSha256',consent:'consentSha256'}[key]]!==ref.sha256)fail('Observed voice reference ancestry differs.');
    const referenceIndex=env.brief.request.items.findIndex(item=>item.id===requested.id);
    if(r.decoder!=='PyAV'||r.decoderVersion!=='19.0.2'||r.externalDataReferences!==false||r.denoise!==false||r.trim!==false||r.normalization!==false||r.xVectorOnlyMode!==false||r.sampleRate!==24000||r.channels!==1||r.sampleFormat!=='float32'||r.sampleFormatConversion!=='libswresample planar float32 full-scale PCM conversion'||r.downmix!=='arithmetic-mean-of-source-channels'||r.resampling!=='libswresample-mono-float32-to24000Hz'||r.decodedFile!=='reference-'+String(referenceIndex).padStart(3,'0')+'.wav'||!SHA.test(r.decodedSha256||'')||!SHA.test(r.decodedPcmSha256||'')||m.referencePrefixRemoval!=='upstream-proportional-code-prefix')fail('Observed voice reference conversion/prefix profile differs.');
    number(r.frames,24000,720000,'decoded reference frames',true);number(r.sourceSampleRate,8000,192000,'reference source rate',true);if(![1,2].includes(r.sourceChannels)||!['mov','wav'].includes(r.container)||(r.container==='mov'?r.codec!=='aac':!/^pcm_/.test(r.codec||'')))fail('Unsupported native reference container/codec.');number(r.selfContainedDataReferences,r.container==='mov'?1:0,r.container==='mov'?65536:0,'self-contained decoder references',true);object(r.decoderLibraries,'reference decoder libraries');
  }else if(m.reference!==null||m.referencePrefixRemoval!==null)fail('Preset speech cannot inherit cloning metadata.');
  return {actualSampling:{seed:requested.seed,scheduler:'autoregressive-sampling',sampling:v.sampling},nativeMetadata:identity,voice:{language:v.language,preset:v.preset,expression:v.expression,sourceRevision:m.sourceRevision,identities:m.identities,termination:t,intrinsicDecoderClamp:m.intrinsicDecoderClamp,reference:m.reference,referencePrefixRemoval:m.referencePrefixRemoval}};
}
function bindObservedIdentities(report,context){
  // Compare retained evidence, never host-maintained copies of native model pins.
  const candidate=candidateData(context.candidate),byMetadata=new Map();
  for(const identity of candidate.manifests||[candidate.manifest]){
    const p=read(context.root,identity).value.generation.parameters;if(!p.modelCatalog)fail('Voice requires retained native model/source catalogue identity.');
    const source=read(context.root,p.sourceRequest).value,native=read(context.root,p.nativeManifest).value,host=read(context.root,p.hostContext).value;
    if(context.brief.kind==='consented-cloning'){
      const localUse=read(context.root,context.brief.localUse).value,record=context.state?.asset||context.state;
      if(source.task!==localUse.task)fail('Original cloning request must bind its actual local-use task.');
      if(source.task!==record?.task&&!['historical-import','external-import'].includes(candidate.origin))fail('Original-task cloning consent is read-only import authority, never a new dispatch claim.');
    }
    const recordedAcceptance=source.acceptance==null?undefined:{...source.acceptance,approval:originalIdentity(context.root,source.acceptance.approval,context.brief.historicalRoot)};
    same(recordedAcceptance,context.brief.request.acceptance,'Retained original voice acceptance attempt');
    if(recordedAcceptance){
      const approval=read(context.root,recordedAcceptance.approval).value;
      if(host.roots?.mediaState!==approval.sharedStateRoot||native.acceptanceClaim!==approval.sharedStateRoot+'/acceptance/'+recordedAcceptance.case+'/'+recordedAcceptance.kind+'.json')fail('Voice original acceptance claim differs from its explicitly shared native allowance.');
      const claimPath=originalIdentity(context.root,{path:native.acceptanceClaim,sha256:'0'.repeat(64)},context.brief.historicalRoot).path,claimIdentity={path:claimPath,sha256:runtime.hash(runtime.projectPath(context.root,claimPath))},claim=read(context.root,claimIdentity).value;
      const claimKeys=['schemaVersion','case','kind','requestId','requestSha256','budgetApprovalSha256','hostContextSha256','candidateClaimSha256','claimedAt'];fields(claim,claimKeys,claimKeys,'original native voice allowance claim');
      if(claim.schemaVersion!=='bubo-media-acceptance-claim/v1'||claim.case!==recordedAcceptance.case||claim.kind!==recordedAcceptance.kind||claim.requestId!==source.requestId||claim.requestSha256!==p.sourceRequest.sha256||claim.budgetApprovalSha256!==recordedAcceptance.approval.sha256||claim.hostContextSha256!==p.hostContext.sha256||!Number.isFinite(Date.parse(claim.claimedAt))||Date.parse(claim.claimedAt)>Date.parse(native.completedAt))fail('Original voice acceptance claim is missing exact request/approval/context ancestry.');
      if(claim.kind==='candidate'){if(claim.candidateClaimSha256!==null)fail('Candidate voice allowance cannot inherit a prior candidate claim.');}
      else{
        const priorPath=originalIdentity(context.root,{path:approval.sharedStateRoot+'/acceptance/'+claim.case+'/candidate.json',sha256:claim.candidateClaimSha256},context.brief.historicalRoot),prior=read(context.root,priorPath).value;
        if(prior.schemaVersion!=='bubo-media-acceptance-claim/v1'||prior.case!==claim.case||prior.kind!=='candidate'||prior.budgetApprovalSha256!==recordedAcceptance.approval.sha256||prior.requestId===source.requestId)fail('Voice revision must retain its actual original candidate allowance ancestry.');report.references.push(priorPath);
      }
      report.references.push(recordedAcceptance.approval,claimIdentity);
    }else if(native.acceptanceClaim!==undefined&&native.acceptanceClaim!==null)fail('Voice native claim cannot be detached from the original acceptance request.');
    const catalog=read(context.root,p.modelCatalog).value,definition=catalog.backends?.find(row=>row.id===backendFor(context.brief.kind));if(!definition?.source)fail('Voice native catalogue source closure is missing.');
    byMetadata.set(p.actual.nativeMetadata.path,{p,definition});
  }
  for(const measurement of report.measurements){
    const binding=byMetadata.get(measurement.nativeMetadata.path);if(!binding)fail('Voice settings lack exact catalogue/runtime ancestry.');const {p,definition}=binding,m=read(context.root,measurement.nativeMetadata).value,i=object(m.identities,'observed model identities'),files=definition.files;
    const selected=name=>{const hits=files.filter(file=>file.path===name);if(hits.length!==1)fail('Voice catalogue model identity missing or duplicated.');return hits[0];};
    for(const [key,name] of [['configSha256','config.json'],['weightsSha256','model.safetensors'],['speechTokenizerWeightsSha256','speech_tokenizer/model.safetensors']])same(i[key],selected(name).sha256,'Observed voice '+key);
    same(i.revision,selected('model.safetensors').revision,'Observed voice model revision');same(i.revision,p.execution.modelVersion,'Actual native voice model version');same(m.sourceRevision,definition.source.revision,'Observed voice source revision');same(i.sourceRevision,m.sourceRevision,'Voice identity source revision');same(p.execution.linkedLibraryCommit,m.sourceRevision,'Actual native linked voice source');same(i.sourceFiles,definition.source.runtimeSourceFiles,'Observed voice runtime source closure');
    const adaptations=definition.source.adaptations.map(row=>({path:row.path,resource:path.posix.basename(row.resource),originalSha256:row.originalSha256,replacementSha256:row.replacementSha256}));same(i.sourceAdaptations,adaptations,'Observed voice source adaptations');
    if(i.modelType!==(context.brief.kind==='preset-speech'?'custom_voice':'base')||i.modelSize!=='1b7')fail('Observed voice model type/size differs.');
  }
}
function technical(context){const kind=context.brief?.kind,report=evidence.technical({domain,backend:backendFor(kind),nativeModality:'voice',sampleRate:24000,channels:1,validateBrief,normalizeItem:nativeItem,validateObserved,inspectBatch,formatDescription:'Native24000Hz mono FLOAT WAV, raw output and intrinsic decoder clamp remain unchanged.'},context);if(context.brief.provider==='LOCAL')bindObservedIdentities(report,context);return report;}
function validateTechnicalReport(report,context){const expected=technical(context);same(report,expected,'Current VOICE technical report');if(expected.status!=='passed')fail('Current authoritative VOICE technical acceptance is unavailable or failed.');return report;}
function reviewBase(review,context,kind){
  object(review,'VOICE review');const record=context.state?.asset||context.state;validateBrief(context.brief,{root:context.root,task:record?.task});
  if(review.schemaVersion!=='hephaera-media-review/v1'||review.kind!==kind||!['accepted','rejected'].includes(review.verdict))fail('Explicit matching VOICE review schema/kind/verdict required.');
  if(context.status?.assetSha256&&review.assetSha256!==context.status.assetSha256)fail('VOICE review names another current asset fingerprint.');if(context.candidate)same(review.outputs,candidateData(context.candidate).outputs,'VOICE reviewed output set');
  text(review.reviewer,'VOICE reviewer',160);text(review.reason,'VOICE review reason',4096);typed(review.sourceEvidence,'human review source');if(context.root)readIdentity(context.root,review.sourceEvidence);
  if(review.verdict==='accepted'){const required=kind==='content'?['listenedEntireOutput','spokenTextReviewed','pronunciationReviewed','artifactsAcceptable','presetOrReferenceMatchReviewed']:['targetPlaybackReviewed','loadDisposeReviewed','spatializationReviewed'];fields(review.criteria,required,required,'VOICE review criteria');if(required.some(key=>review.criteria[key]!==true))fail('Accepted VOICE review requires complete spoken-content/match or runtime criteria.');}return review;
}
function validateReview(review,context){const keys=['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria'];fields(review,keys,keys,'VOICE content review');return reviewBase(review,context,'content');}
function validateRuntimeReview(review,context){
  const keys=['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria','engine','target','rightsEvidence','targetEvidence','disclosureEvidence'];fields(review,keys,keys.slice(0,11),'VOICE runtime review');reviewBase(review,context,'runtime');if(review.verdict!=='accepted')return review;
  const root=context.root,record=context.state?.asset||context.state,brief=context.brief;
  if(review.target?.spatialization!==brief.spatialization||review.target?.loopIntent!==false)fail('VOICE runtime target must retain explicit spatialization and nonloop intent.');
  const permission=read(root,review.rightsEvidence).value,permissionKeys=['schemaVersion','task','purpose','rightsConfirmed','publicDisclosureConfirmed','sourceEvidence'];fields(permission,permissionKeys,permissionKeys,'VOICE distribution rights');
  if(permission.schemaVersion!=='hephaera-voice-distribution/v1'||permission.task!==record.task||permission.purpose!==brief.purpose||permission.rightsConfirmed!==true||permission.publicDisclosureConfirmed!==true)fail('Separate current VOICE distribution and public disclosure rights are required.');readIdentity(root,permission.sourceEvidence);nested(root,permission);
  const target=read(root,review.targetEvidence).value,targetKeys=['schemaVersion','task','engine','outputs','spatialization','loopIntent','playbackReviewed','loadDisposeReviewed','sourceEvidence'];fields(target,targetKeys,targetKeys,'VOICE target evidence');
  if(target.schemaVersion!=='hephaera-voice-runtime-evidence/v1'||target.task!==record.task||target.spatialization!==brief.spatialization||target.loopIntent!==false||target.playbackReviewed!==true||target.loadDisposeReviewed!==true)fail('Actual current VOICE target playback/load/dispose evidence is required.');same(target.engine,review.engine,'VOICE target engine');same(target.outputs,review.outputs,'VOICE target output set');readIdentity(root,target.sourceEvidence);nested(root,target);
  if(brief.kind==='consented-cloning'){
    const disclosure=read(root,review.disclosureEvidence).value,disclosureKeys=['schemaVersion','task','purpose','outputs','references','disclosureAllowed','sourceEvidence'];fields(disclosure,disclosureKeys,disclosureKeys,'cloned-output disclosure');
    if(disclosure.schemaVersion!=='hephaera-voice-disclosure/v1'||disclosure.task!==record.task||disclosure.purpose!==brief.purpose||disclosure.disclosureAllowed!==true)fail('Separate explicit current cloned-output disclosure grant is required.');same(disclosure.outputs,review.outputs,'Disclosed voice output set');same(disclosure.references,referenceSet(brief),'Disclosed ordered voice references');
    localIdentity(disclosure.sourceEvidence,'cloned-output disclosure human source');distinct([review.disclosureEvidence,disclosure.sourceEvidence]);readIdentity(root,disclosure.sourceEvidence);
    for(const output of disclosure.outputs){distinct([review.disclosureEvidence,disclosure.sourceEvidence,output]);readIdentity(root,output);}
    for(const reference of disclosure.references)for(const key of referenceKeys){const ref=originalIdentity(root,reference[key],brief.historicalRoot);distinct([review.disclosureEvidence,disclosure.sourceEvidence,ref]);readIdentity(root,ref);}
  }else if(review.disclosureEvidence!==undefined)fail('Preset speech does not accept cloned-output disclosure evidence.');return review;
}
module.exports={domain,modalities,backends,validateBrief,request,generationReferences,mapReference,technical,validateTechnicalReport,validateReview,validateRuntimeReview};
