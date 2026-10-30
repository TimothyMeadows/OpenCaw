'use strict';

// MUSIC policy only. Bubo owns synthesis, model pins and native resource ownership.
const path=require('path'),crypto=require('crypto'),runtime=require('./bubo-runtime.cjs');
const evidence=require('./media-audio-evidence.cjs');
const {ID,fail,same,object,fields,text,number,typed,sourceRoot,originalIdentity,read,nested,readIdentity,candidateData}=evidence;
const domain='MUSIC',modalities=['instrumental','supplied-lyrics'],backend='ace-step-turbo';
const languages=new Set('ar az bg bn ca cs da de el en es fa fi fr he hi hr ht hu id is it ja ko la lt ms ne nl no pa pl pt ro ru sa sk sr sv sw ta te th tl tr uk ur vi yue zh'.split(' '));
function nativeItem(item){
  const value=evidence.normalizeNativeItem(item,['width','height','voice']);
  // Retained raw GenerationItem JSON may omit its documented empty-string default.
  // Fresh briefs remain explicit; null and nonempty recorded values still differ.
  if(!Object.hasOwn(value,'negativePrompt'))value.negativePrompt='';
  return value;
}
const lyricsHash=value=>crypto.createHash('sha256').update(value,'utf8').digest('hex');
function lyricsRights(brief,{root,task,requireGeneration=false}={}){
  if(brief.kind==='instrumental'){
    if(brief.lyricsRights!==undefined)fail('Instrumental does not accept supplied-lyrics rights.');
    return;
  }
  typed(brief.lyricsRights,'lyrics rights');
  if(!root)return;
  const rights=read(root,brief.lyricsRights).value;
  fields(rights,['schemaVersion','task','purpose','lyrics','rightsConfirmed','generationAllowed','sourceEvidence'],['schemaVersion','task','purpose','lyrics','rightsConfirmed','generationAllowed','sourceEvidence'],'lyrics rights');
  if(rights.schemaVersion!=='opencaw-music-lyrics-rights/v1'||!ID.test(rights.task||'')||rights.purpose!==brief.purpose||rights.rightsConfirmed!==true||typeof rights.generationAllowed!=='boolean'
      ||(requireGeneration&&(rights.generationAllowed!==true||rights.task!==task)))fail('Exact supplied-lyrics rights and applicable current task generation authority are required.');
  if(!Array.isArray(rights.lyrics)||rights.lyrics.length!==brief.request.items.length)fail('Lyrics rights must cover the complete ordered item set.');
  for(let i=0;i<rights.lyrics.length;i++){
    const entry=rights.lyrics[i],item=brief.request.items[i];
    fields(entry,['itemId','lyricsSha256'],['itemId','lyricsSha256'],'lyrics rights item');
    if(entry.itemId!==item.id||entry.lyricsSha256!==lyricsHash(item.music.lyrics))fail('Lyrics rights differ from exact supplied UTF8 lyrics or item order.');
  }
  readIdentity(root,rights.sourceEvidence);nested(root,rights);
}
function musicOptions(music,kind){
  const keys=['mode','lyrics','vocalLanguage','bpm','keyScale','timeSignature','shift'];fields(music,keys,keys,'music options');
  if(music.mode!==kind||typeof music.lyrics!=='string'||music.lyrics.length>4096||music.lyrics.includes('\0'))fail('Exact supported music mode and bounded supplied lyrics are required.');
  if(kind==='instrumental'?(music.lyrics!==''||music.vocalLanguage!=='unknown'):(!music.lyrics.trim()||!languages.has(music.vocalLanguage)))fail('Instrumental requires empty lyrics/unknown language; supplied lyrics require text and an explicit supported language.');
  if(music.bpm!==null)number(music.bpm,30,300,'music BPM',true);
  if(typeof music.keyScale!=='string'||(music.keyScale!==''&&!/^[A-G](#|b)? (major|minor)$/i.test(music.keyScale))||!['','2','3','4','6'].includes(music.timeSignature))fail('Unsupported explicit music key or time signature.');
  number(music.shift,1,5,'music shift');
}
function validateBrief(brief,context={}){
  fields(brief,['schemaVersion','kind','purpose','provider','spatialization','loopIntent','request','technical','historicalRoot','lyricsRights'],['schemaVersion','kind','purpose','provider','spatialization','loopIntent','request','technical'],'MUSIC brief');
  if(brief.schemaVersion!=='opencaw-music-brief/v1'||!modalities.includes(brief.kind)||!['LOCAL','CLOUD'].includes(brief.provider)||!['2d','3d'].includes(brief.spatialization)||typeof brief.loopIntent!=='boolean')fail('Explicit supported MUSIC kind, provider, spatialization and loop intent are required.');
  text(brief.purpose,'MUSIC purpose',1024);
  if(brief.historicalRoot!==undefined){
    if(brief.provider!=='LOCAL')fail('Historical native root mapping applies only to explicit LOCAL import.');
    runtime.syntax(brief.historicalRoot);
    if(brief.historicalRoot.includes('\\')||path.isAbsolute(runtime.native(brief.historicalRoot)))fail('Historical root must use a canonical project-relative path.');
    if(context.root)sourceRoot(context.root,brief.historicalRoot);
  }
  const local=brief.provider==='LOCAL',request=brief.request;
  fields(request,local?['rights','installation','settings','budget','items','acceptance']:['rights','budget','items'],local?['rights','installation','settings','budget','items']:['rights','budget','items'],'MUSIC request');
  typed(request.rights,'rights');
  if(local){
    typed(request.installation,'installation');fields(request.settings,['device','precision','offload'],['device','precision','offload'],'music execution settings');
    if(request.settings.device!=='cuda:0'||request.settings.precision!=='bfloat16'||request.settings.offload!=='none')fail('ACE-Step requires explicit cuda:0, bfloat16 and no offload; no fallback.');
  }
  const budget=request.budget,keys=['maximumOutputs','maximumBytesPerOutput','maximumTotalBytes','maximumAudioSeconds',...(local?['maximumPixels']:[])];
  fields(budget,keys,keys,'MUSIC output budget');number(budget.maximumOutputs,1,4,'output count',true);
  number(budget.maximumBytesPerOutput,1024,268435456,'per-output byte budget',true);number(budget.maximumTotalBytes,budget.maximumBytesPerOutput,1073741824,'total byte budget',true);
  number(budget.maximumAudioSeconds,0.25,600,'audio duration budget');if(local)number(budget.maximumPixels,4096,4194304,'native structural pixel budget',true);
  if(!Array.isArray(request.items)||request.items.length<1||request.items.length>Math.min(4,budget.maximumOutputs))fail('MUSIC variants must be a bounded nonempty batch.');
  const ids=new Set();
  for(const item of request.items){
    const itemKeys=local?['id','prompt','negativePrompt','seed','steps','guidance','seconds','loopCandidate','music']:['id','prompt','seconds','music'];fields(item,itemKeys,itemKeys,'MUSIC item');
    text(item.id,'item ID',80);if(!ID.test(item.id)||ids.has(item.id))fail('Safe unique MUSIC item IDs are required.');ids.add(item.id);
    text(item.prompt,'music caption',512);number(item.seconds,10,600,'music whole-second duration',true);
    if(item.seconds>budget.maximumAudioSeconds)fail('Item duration exceeds its explicit budget.');musicOptions(item.music,brief.kind);
    if(local){
      if(item.negativePrompt!=='')fail('Music negative prompts are unsupported.');
      number(item.seed,0,2147483647,'music int32 seed',true);number(item.steps,1,8,'music step count',true);
      if(item.guidance!==1)fail('Music requires guidance1.');if(item.loopCandidate!==brief.loopIntent)fail('Item loopCandidate must match the explicit brief loop intent.');
    }
  }
  if(request.acceptance!==undefined){
    fields(request.acceptance,['case','kind','approval'],['case','kind','approval'],'acceptance attempt');
    if(request.acceptance.case!==brief.kind||!['candidate','revision'].includes(request.acceptance.kind)||request.items.length!==1)fail('Music acceptance requires one matching candidate/revision case.');
    typed(request.acceptance.approval,'acceptance approval');if(context.root)readIdentity(context.root,request.acceptance.approval);
  }
  fields(brief.technical,['maxPeak','maxClippedFraction','maxSilentFraction'],['maxPeak','maxClippedFraction','maxSilentFraction'],'technical policy');
  for(const [key,max] of [['maxPeak',Number.MAX_VALUE],['maxClippedFraction',1],['maxSilentFraction',1]])if(brief.technical[key]!==null)number(brief.technical[key],0,max,key);
  evidence.requireRights(backend,brief,context);lyricsRights(brief,context);return JSON.parse(JSON.stringify(brief));
}
function request(brief,{root,asset}={}){
  if(brief?.historicalRoot!==undefined)fail('Historical-root briefs are import-only and cannot authorize a new native dispatch.');
  const record=asset?.task?asset:asset?.asset;
  if(!record?.task)fail('Task-owned asset identity is required for dispatch.');
  const value=validateBrief(brief,{root,task:record.task,requireGeneration:true});
  if(value.provider!=='LOCAL')fail('CLOUD generation requires a separately selected available session capability; this command supports provenance import only.');
  return {schemaVersion:'bubo-media-request/v1',task:record.task,backend,...value.request};
}
function validateObserved(actual,requested,env){
  if(actual.actual?.seed!==requested.seed||actual.actual.steps!==requested.steps||actual.actual.guidance!==1||actual.actual.scheduler!=='ode/euler')fail('Actual music sampling settings differ from the exact request.');
  const identity=originalIdentity(env.root,actual.actual.nativeMetadata,env.brief.historicalRoot),metadata=read(env.root,identity).value;env.reference(identity);
  const m=requested.music,p=object(metadata.params,'music observed params'),c=object(metadata.config,'music observed config');
  if(metadata.protocol!=='bubo-music-settings/v1'||!/^([a-f0-9]{40}|[a-f0-9]{64})$/.test(metadata.sourceRevision||'')||metadata.mode!==m.mode||metadata.planningLmLoaded!==false||metadata.lmMetadata!==null
      ||metadata.innerSeed!==requested.seed||metadata.normalization!==false||metadata.cpuDecode!==false||metadata.actualOutputCount!==1||metadata.sampleRate!==48000||metadata.attention!=='sdpa')fail('Actual music mode/planning-LM/raw-amplitude metadata differs.');
  const expected={caption:requested.prompt,lyrics:m.mode==='instrumental'?'[Instrumental]':m.lyrics,instrumental:m.mode==='instrumental',vocal_language:m.vocalLanguage,duration:requested.seconds,seed:requested.seed,inference_steps:requested.steps,
    guidance_scale:1,shift:m.shift,keyscale:m.keyScale,timesignature:m.timeSignature,bpm:m.bpm,task_type:'text2music',infer_method:'ode',sampler_mode:'euler',thinking:false,use_cot_metas:false,use_cot_caption:false,
    use_cot_language:false,use_cot_lyrics:false,enable_normalization:false,dcw_enabled:false,fade_in_duration:0,fade_out_duration:0,latent_shift:0,latent_rescale:1,reference_audio:null,src_audio:null,audio_codes:''};
  for(const [key,value] of Object.entries(expected))same(p[key],value,'Actual music '+key);
  if(c.batch_size!==1||c.allow_lm_batch!==false||c.use_random_seed!==false||c.audio_format!=='wav32')fail('Actual music batch/random-seed/raw-format configuration differs.');same(c.seeds,[requested.seed],'Actual music seeds');
  if(!Array.isArray(metadata.conditioning)||metadata.conditioning.length!==2)fail('Music requires complete caption/lyrics conditioning evidence.');
  for(let i=0;i<2;i++){
    const row=metadata.conditioning[i],limit=i===0?256:2048;
    fields(row,['text','tokenCount','maximumTokens','truncated'],['text','tokenCount','maximumTokens','truncated'],'music conditioning');
    text(row.text,'formatted music conditioning',32768);number(row.tokenCount,1,limit,'conditioning token count',true);
    if(row.maximumTokens!==limit||row.truncated!==false)fail('Music conditioning was truncated or has unsupported token limits.');
  }
  return {actualSampling:{seed:requested.seed,steps:requested.steps,guidance:1,scheduler:'ode/euler'},nativeMetadata:identity,music:{mode:m.mode,lyricsSha256:lyricsHash(m.lyrics),vocalLanguage:m.vocalLanguage,bpm:m.bpm,keyScale:m.keyScale,timeSignature:m.timeSignature,shift:m.shift,
    sourceRevision:metadata.sourceRevision,planningLmLoaded:false,normalization:false,cpuDecode:false,conditioning:metadata.conditioning}};
}
function inspectBatch(native){
  const cleanup=native.cleanup;
  fields(cleanup,['mechanism','allocatedBeforeWorkspaceClearBytes','reservedBeforeWorkspaceClearBytes','endingAllocatedBytes','endingReservedBytes'],['mechanism','allocatedBeforeWorkspaceClearBytes','reservedBeforeWorkspaceClearBytes','endingAllocatedBytes','endingReservedBytes'],'music cleanup');
  for(const key of ['allocatedBeforeWorkspaceClearBytes','reservedBeforeWorkspaceClearBytes','endingAllocatedBytes','endingReservedBytes'])number(cleanup[key],0,Number.MAX_SAFE_INTEGER,'music cleanup '+key,true);
  if(cleanup.mechanism!=='torch._C._cuda_clearCublasWorkspaces'||cleanup.endingAllocatedBytes!==0)fail('Music requires measured zero-allocation workspace/model cleanup.');
  return {cleanup,aggregateDriverMemory:{unavailable:true,reason:'Native allocator/reservation counters do not measure aggregate driver/GPU memory.'}};
}
const evidenceSpec={domain,backend,nativeModality:'music',sampleRate:48000,channels:2,validateBrief,normalizeItem:nativeItem,validateObserved,inspectBatch,
  formatDescription:'Native measured48000Hz stereo FLOAT WAV and complete raw amplitudes retain their original bytes; no normalization, mastering or edits.'};
const technical=context=>evidence.technical(evidenceSpec,context);
function validateTechnicalReport(report,context){const expected=technical(context);same(report,expected,'Current MUSIC technical report');if(expected.status!=='passed')fail('Current authoritative MUSIC technical acceptance is unavailable or failed.');return report;}
function reviewBase(review,context,kind){
  object(review,'MUSIC review');const record=context.state?.asset||context.state;validateBrief(context.brief,{root:context.root,task:record?.task});
  if(review.schemaVersion!=='opencaw-media-review/v1')fail('Unsupported MUSIC review schema.');
  if(context.status?.assetSha256&&review.assetSha256!==context.status.assetSha256)fail('MUSIC review names another current asset fingerprint.');
  if(context.candidate)same(review.outputs,candidateData(context.candidate).outputs,'MUSIC reviewed output set');
  if(review.kind!==kind||!['accepted','rejected'].includes(review.verdict))fail('Explicit matching MUSIC review kind/verdict required.');
  text(review.reviewer,'MUSIC reviewer',160);text(review.reason,'MUSIC review reason',4096);typed(review.sourceEvidence,'human review source');if(context.root)readIdentity(context.root,review.sourceEvidence);
  if(review.verdict==='accepted'){
    const criteria=object(review.criteria,'MUSIC review criteria'),required=kind==='content'?['listenedEntireOutput','matchesBrief','intendedVocalContentReviewed','artifactsAcceptable','headTailAccepted']:['targetPlaybackReviewed','loadDisposeReviewed','spatializationReviewed'];
    if(kind==='content'&&context.brief.kind==='supplied-lyrics')required.push('everySuppliedLineReviewed');
    if(Object.keys(criteria).some(key=>![...required,'loopSeamReviewed'].includes(key)))fail('Unsupported MUSIC review criterion.');
    if(context.brief.loopIntent||criteria.loopSeamReviewed!==undefined)required.push('loopSeamReviewed');
    if(required.some(key=>criteria[key]!==true))fail('Accepted MUSIC review requires complete-track/vocal/line/target and applicable loop-seam criteria.');
  }
  return review;
}
function validateReview(review,context){
  const keys=['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria'];fields(review,keys,keys,'MUSIC content review');return reviewBase(review,context,'content');
}
function validateRuntimeReview(review,context){
  fields(review,['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria','engine','target','rightsEvidence','targetEvidence'],['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria','engine','target'],'MUSIC runtime review');
  reviewBase(review,context,'runtime');if(review.verdict!=='accepted')return review;
  const record=context.state?.asset||context.state,root=context.root;
  if(review.target?.spatialization!==context.brief.spatialization||review.target?.loopIntent!==context.brief.loopIntent)fail('Runtime target must retain explicit MUSIC spatialization/loop intent.');
  const permission=read(root,review.rightsEvidence).value;
  fields(permission,['schemaVersion','task','purpose','rightsConfirmed','sourceEvidence'],['schemaVersion','task','purpose','rightsConfirmed','sourceEvidence'],'runtime distribution rights');
  if(permission.schemaVersion!=='opencaw-music-distribution/v1'||permission.task!==record.task||permission.purpose!==context.brief.purpose||permission.rightsConfirmed!==true)fail('Separate current MUSIC distribution rights for this task/purpose are required.');
  readIdentity(root,permission.sourceEvidence);nested(root,permission);
  const target=read(root,review.targetEvidence).value;
  fields(target,['schemaVersion','task','engine','outputs','spatialization','loopIntent','playbackReviewed','loadDisposeReviewed','loopSeamReviewed','sourceEvidence'],['schemaVersion','task','engine','outputs','spatialization','loopIntent','playbackReviewed','loadDisposeReviewed','loopSeamReviewed','sourceEvidence'],'runtime playback evidence');
  if(target.schemaVersion!=='opencaw-music-runtime-evidence/v1'||target.task!==record.task||target.spatialization!==context.brief.spatialization||target.loopIntent!==context.brief.loopIntent||target.playbackReviewed!==true||target.loadDisposeReviewed!==true||(target.loopIntent&&target.loopSeamReviewed!==true))fail('Actual current selected-engine playback/load/dispose evidence is required.');
  same(target.engine,review.engine,'Runtime target engine');same(target.outputs,review.outputs,'Runtime target output set');readIdentity(root,target.sourceEvidence);nested(root,target);return review;
}
function generationReferences(brief,context){
  request(brief,context);
  if(brief.kind!=='supplied-lyrics')return [];
  const record=read(context.root,brief.lyricsRights).value;
  return [brief.lyricsRights,record.sourceEvidence].map(ref=>({...ref}));
}
module.exports={domain,modalities,backend,backends:[backend],validateBrief,request,generationReferences,technical,validateTechnicalReport,validateReview,validateRuntimeReview};
