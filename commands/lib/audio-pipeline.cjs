'use strict';

// AUDIO owns SFX/ambience policy; shared evidence owns generic native ancestry.
const path=require('path'),runtime=require('./bubo-runtime.cjs');
const evidence=require('./media-audio-evidence.cjs');
const {ID,fail,canonical,same,object,fields,text,number,typed,sourceRoot,originalIdentity,read,nested,readIdentity,candidateData}=evidence;
const domain='AUDIO',modalities=['sfx','ambience'],backend='stable-audio-open';
const nativeItem=item=>evidence.normalizeNativeItem(item,['width','height','music','voice']);
function validateBrief(brief,context={}){
  fields(brief,['schemaVersion','kind','purpose','provider','spatialization','loopIntent','request','technical','historicalRoot'],['schemaVersion','kind','purpose','provider','spatialization','loopIntent','request','technical'],'AUDIO brief');
  if(brief.schemaVersion!=='hephaera-audio-brief/v1'||!modalities.includes(brief.kind)||!['LOCAL','CLOUD'].includes(brief.provider)||!['2d','3d'].includes(brief.spatialization)||typeof brief.loopIntent!=='boolean')fail('Explicit supported AUDIO kind, provider, spatialization and loop intent are required.');
  text(brief.purpose,'AUDIO purpose',1024);
  if(brief.historicalRoot!==undefined){
    if(brief.provider!=='LOCAL')fail('Historical native root mapping applies only to explicit LOCAL import.');
    runtime.syntax(brief.historicalRoot);
    if(brief.historicalRoot.includes('\\')||path.isAbsolute(runtime.native(brief.historicalRoot)))fail('Historical root must use a canonical project-relative path.');
    if(context.root)sourceRoot(context.root,brief.historicalRoot);
  }
  const local=brief.provider==='LOCAL',request=brief.request;
  fields(request,local?['rights','installation','settings','budget','items','acceptance']:['rights','budget','items'],local?['rights','installation','settings','budget','items']:['rights','budget','items'],'AUDIO request');
  typed(request.rights,'rights');
  if(local){
    typed(request.installation,'installation');
    fields(request.settings,['device','precision','offload'],['device','precision','offload'],'SFX execution settings');
    if(request.settings.device!=='cuda:0'||!['float16','float32'].includes(request.settings.precision)||request.settings.offload!=='none')fail('Stable Audio requires explicit cuda:0, float16/float32 and no offload; no fallback.');
  }
  const budget=request.budget,budgetFields=['maximumOutputs','maximumBytesPerOutput','maximumTotalBytes','maximumAudioSeconds',...(local?['maximumPixels']:[])];
  fields(budget,budgetFields,budgetFields,'AUDIO output budget');
  number(budget.maximumOutputs,1,4,'output count',true);number(budget.maximumBytesPerOutput,1024,268435456,'per-output byte budget',true);
  number(budget.maximumTotalBytes,budget.maximumBytesPerOutput,1073741824,'total byte budget',true);number(budget.maximumAudioSeconds,0.25,600,'audio duration budget');
  if(local)number(budget.maximumPixels,4096,4194304,'native structural pixel budget',true);
  if(!Array.isArray(request.items)||request.items.length<1||request.items.length>Math.min(4,budget.maximumOutputs))fail('AUDIO variants must be a bounded nonempty batch.');
  const ids=new Set();
  for(const item of request.items){
    const keys=local?['id','prompt','negativePrompt','seed','steps','guidance','seconds','loopCandidate']:['id','prompt','seconds'];
    fields(item,keys,keys,'AUDIO item');text(item.id,'item ID',80);if(!ID.test(item.id)||ids.has(item.id))fail('Safe unique AUDIO item IDs are required.');ids.add(item.id);
    text(item.prompt,'SFX prompt');number(item.seconds,0.25,local?47:budget.maximumAudioSeconds,'SFX/ambience duration');
    if(item.seconds>budget.maximumAudioSeconds)fail('Item duration exceeds its explicit budget.');
    if(local){
      if(typeof item.negativePrompt!=='string'||item.negativePrompt.length>4096||item.negativePrompt.includes('\0'))fail('Invalid negative prompt.');
      number(item.seed,0,Number.MAX_SAFE_INTEGER,'exact nonnegative seed',true);number(item.steps,1,200,'SFX step count',true);number(item.guidance,1,12,'SFX guidance');
      if(item.guidance<=1&&item.negativePrompt.length)fail('Negative prompts are unsupported at guidance<=1.');
      if(item.loopCandidate!==brief.loopIntent)fail('Item loopCandidate must match the explicit brief loop intent.');
    }
  }
  if(request.acceptance!==undefined){
    fields(request.acceptance,['case','kind','approval'],['case','kind','approval'],'acceptance attempt');
    if(request.acceptance.case!=='sfx'||!['candidate','revision'].includes(request.acceptance.kind)||request.items.length!==1)fail('SFX acceptance requires one matching candidate/revision case.');
    typed(request.acceptance.approval,'acceptance approval');
    if(context.root)readIdentity(context.root,request.acceptance.approval);
  }
  fields(brief.technical,['maxPeak','maxClippedFraction','maxSilentFraction'],['maxPeak','maxClippedFraction','maxSilentFraction'],'technical policy');
  for(const [key,max] of [['maxPeak',Number.MAX_VALUE],['maxClippedFraction',1],['maxSilentFraction',1]])if(brief.technical[key]!==null)number(brief.technical[key],0,max,key);
  evidence.requireRights(backend,brief,context);return JSON.parse(JSON.stringify(brief));
}
function request(brief,{root,asset}={}){
  if(brief?.historicalRoot!==undefined)fail('Historical-root briefs are import-only and cannot authorize a new native dispatch.');
  const record=asset?.task?asset:asset?.asset;const value=validateBrief(brief,{root,task:record?.task,requireGeneration:true});
  if(value.provider!=='LOCAL')fail('CLOUD generation requires a separately selected available session capability; this command supports provenance import only.');
  if(!record?.task)fail('Task-owned asset identity is required for dispatch.');
  return {schemaVersion:'bubo-media-request/v1',task:record.task,backend,...value.request};
}
function validateObserved(actual,requested,env){
  if(actual.actual?.seed!==requested.seed||actual.actual.steps!==requested.steps||actual.actual.guidance!==requested.guidance||typeof actual.actual.scheduler!=='string')fail('Imported actual native settings differ.');
  if(actual.actual.nativeMetadata){const metadata=originalIdentity(env.root,actual.actual.nativeMetadata,env.brief.historicalRoot);read(env.root,metadata);env.reference(metadata);}
  return {actualSampling:{seed:actual.actual.seed,steps:actual.actual.steps,guidance:actual.actual.guidance,scheduler:actual.actual.scheduler}};
}
const evidenceSpec={domain,backend,nativeModality:'sfx',sampleRate:44100,channels:2,validateBrief,normalizeItem:nativeItem,validateObserved,
  cleanupUnavailable:'The SFX manifest exposes one-load/unloaded lifecycle flags, not independent allocator/driver memory counters.',
  formatDescription:'Native measured44100Hz stereo FLOAT WAV, duration and file identity retain their original bytes.'};
const technical=context=>evidence.technical(evidenceSpec,context);
function validateTechnicalReport(report,context){const expected=technical(context);same(report,expected,'Current AUDIO technical report');if(expected.status!=='passed')fail('Current authoritative AUDIO technical acceptance is unavailable or failed.');return report;}
function reviewBase(review,context,kind){
  object(review,'AUDIO review');const record=context.state?.asset||context.state;validateBrief(context.brief,{root:context.root,task:record?.task});
  if(review.schemaVersion!=='hephaera-media-review/v1')fail('Unsupported AUDIO review schema.');
  if(context.status?.assetSha256&&review.assetSha256!==context.status.assetSha256)fail('AUDIO review names another current asset fingerprint.');
  if(context.candidate)same(review.outputs,candidateData(context.candidate).outputs,'AUDIO reviewed output set');
  if(review.kind!==kind||!['accepted','rejected'].includes(review.verdict))fail('Explicit matching AUDIO review kind/verdict required.');
  typed(review.sourceEvidence,'human review source');if(context.root)readIdentity(context.root,review.sourceEvidence);
  if(review.verdict==='accepted'){
    const criteria=object(review.criteria,'AUDIO review criteria');
    const required=kind==='content'?['listenedEntireOutput','matchesBrief','unwantedSpeechMusicAbsent','artifactsAcceptable','headTailAccepted']:['targetPlaybackReviewed','loadDisposeReviewed','spatializationReviewed'];
    if(Object.keys(criteria).some(key=>![...required,'loopSeamReviewed'].includes(key)))fail('Unsupported AUDIO review criterion.');
    if(context.brief.loopIntent)required.push('loopSeamReviewed');
    if(required.some(key=>criteria[key]!==true))fail('Accepted AUDIO review requires explicit complete-listening/target and applicable loop-seam criteria.');
  }
  return review;
}
function validateReview(review,context){
  fields(review,['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria'],['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria'],'AUDIO content review');
  return reviewBase(review,context,'content');
}
function validateRuntimeReview(review,context){
  fields(review,['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria','engine','target','rightsEvidence','targetEvidence'],['schemaVersion','assetSha256','outputs','kind','verdict','reviewer','reason','sourceEvidence','criteria','engine','target'],'AUDIO runtime review');
  reviewBase(review,context,'runtime');
  if(review.verdict!=='accepted')return review;
  const record=context.state?.asset||context.state,root=context.root;
  if(review.target?.spatialization!==context.brief.spatialization||review.target?.loopIntent!==context.brief.loopIntent)fail('Runtime target must retain explicit AUDIO spatialization/loop intent.');
  const permission=read(root,review.rightsEvidence).value;
  fields(permission,['schemaVersion','task','purpose','rightsConfirmed','sourceEvidence'],['schemaVersion','task','purpose','rightsConfirmed','sourceEvidence'],'runtime distribution rights');
  if(permission.schemaVersion!=='hephaera-audio-distribution/v1'||permission.task!==record.task||permission.purpose!==context.brief.purpose||permission.rightsConfirmed!==true)fail('Separate current AUDIO distribution rights for this task/purpose are required.');
  readIdentity(root,permission.sourceEvidence);nested(root,permission);
  const target=read(root,review.targetEvidence).value;
  fields(target,['schemaVersion','task','engine','outputs','spatialization','loopIntent','playbackReviewed','loadDisposeReviewed','loopSeamReviewed','sourceEvidence'],['schemaVersion','task','engine','outputs','spatialization','loopIntent','playbackReviewed','loadDisposeReviewed','loopSeamReviewed','sourceEvidence'],'runtime playback evidence');
  if(target.schemaVersion!=='hephaera-audio-runtime-evidence/v1'||target.task!==record.task||target.spatialization!==context.brief.spatialization||target.loopIntent!==context.brief.loopIntent||target.playbackReviewed!==true||target.loadDisposeReviewed!==true||(target.loopIntent&&target.loopSeamReviewed!==true))fail('Actual current selected-engine playback/load/dispose evidence is required.');
  same(target.engine,review.engine,'Runtime target engine');same(target.outputs,review.outputs,'Runtime target output set');readIdentity(root,target.sourceEvidence);nested(root,target);
  return review;
}
module.exports={domain,modalities,backend,backends:[backend],validateBrief,request,technical,validateTechnicalReport,validateReview,validateRuntimeReview};
