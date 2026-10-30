'use strict';

// AUDIO host policy only. Bubo owns synthesis, decoding, measurements and pins.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const runtime=require('./bubo-runtime.cjs');
const domain='AUDIO',modalities=['sfx','ambience'],backend='stable-audio-open';
const SHA=/^[a-f0-9]{64}$/,ID=/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/;
const fail=message=>{throw new Error(message);};
const canonical=value=>JSON.stringify(runtime.canonical(value));
function same(a,b,label){if(canonical(a)!==canonical(b))fail(label+' differs from its exact source.');}
function nativeItem(item){
  object(item,'recorded native SFX item');const value={...item};
  // The native DTO serializes these absent optional controls as null. This is
  // equivalent to omission, never permission to ignore a supplied control.
  for(const key of ['width','height','music','voice'])if(value[key]===null)delete value[key];
  return value;
}
function object(value,label){if(!value||typeof value!=='object'||Array.isArray(value))fail(label+' must be an object.');return value;}
function fields(value,allowed,required,label){object(value,label);if(Object.keys(value).some(key=>!allowed.includes(key))||required.some(key=>!Object.hasOwn(value,key)))fail(label+' has missing or unsupported fields.');}
function text(value,label,max=4096){if(typeof value!=='string'||!value.trim()||value.length>max||value.includes('\0'))fail('Invalid '+label+'.');return value;}
function number(value,min,max,label,integer=false){if(!Number.isFinite(value)||value<min||value>max||(integer&&!Number.isSafeInteger(value)))fail('Unsupported '+label+'.');return value;}
function typed(value,label='file identity'){fields(value,['path','sha256'],['path','sha256'],label);text(value.path,label+' path');if(!SHA.test(value.sha256))fail('Invalid '+label+' SHA-256.');return value;}
function sourceRoot(root,historicalRoot){
  if(historicalRoot===undefined)return root;
  text(historicalRoot,'historical source root');const full=runtime.projectPath(root,historicalRoot);
  if(path.relative(root,full).split(path.sep).join('/')!==historicalRoot||!fs.statSync(full).isDirectory())fail('Historical root must be an existing canonical project-confined directory.');
  return full;
}
function originalIdentity(root,identity,historicalRoot){
  typed(identity);if(historicalRoot===undefined)return identity;
  const base=sourceRoot(root,historicalRoot),full=runtime.projectPath(base,identity.path);
  if(path.relative(base,full).split(path.sep).join('/')!==identity.path)fail('Historical input identity must remain relative to its original root.');
  return {path:path.relative(root,full).split(path.sep).join('/'),sha256:identity.sha256};
}
function disclosed(value,expected,label){
  if(expected!==undefined&&expected!==null){if(value!==expected)fail(label+' contradicts the disclosed native identity.');return;}
  if(!value||typeof value!=='object'||value.unavailable!==true||typeof value.reason!=='string'||!value.reason.trim())fail(label+' requires an explicit unavailable marker when undisclosed.');
}
function revision(root,parameters,native,result,hostContext,originalRoot){
  let value=typeof result.runtime.sourceRevision==='string'?result.runtime.sourceRevision:null;
  const evidence=parameters.runtime?.sourceRevisionEvidence;
  if(evidence){
    const record=read(root,evidence,8388608).value;
    if(record.schemaVersion==='bubo-build/v1'){
      if(record.sourceDirty!==false)fail('Native source-revision receipt is dirty or unverified.');
      same(record.capabilities?.build,result.runtime,'Source-revision build receipt');
    }else{
      if(!Array.isArray(record.command)||record.command[1]!=='media'||record.command[2]!=='generate'||!Number.isFinite(Date.parse(record.startedAt))||!Number.isFinite(Date.parse(native.completedAt))||Date.parse(record.startedAt)>Date.parse(native.completedAt))fail('Historical source-revision evidence is not the original bounded generation invocation.');
      const option=name=>{const positions=record.command.flatMap((item,index)=>item===name?[index]:[]);if(positions.length!==1||typeof record.command[positions[0]+1]!=='string')fail('Historical invocation is missing its exact '+name+'.');return record.command[positions[0]+1];};
      if(option('--api-version')!=='1'||!runtime.samePath(path.resolve(runtime.native(option('--root'))),originalRoot))fail('Historical source invocation identifies another root/API.');
      const manifestPath=originalIdentity(root,{path:option('--manifest'),sha256:parameters.sourceRequest.sha256},parameters.historicalRoot).path;
      const contextPath=originalIdentity(root,{path:option('--host-context'),sha256:parameters.hostContext.sha256},parameters.historicalRoot).path;
      if(manifestPath!==parameters.sourceRequest.path||contextPath!==parameters.hostContext.path)fail('Historical invocation differs from retained native request/context evidence.');
    }
    if(typeof record.sourceRevision!=='string'||!/^([a-f0-9]{40}|[a-f0-9]{64})$/.test(record.sourceRevision))fail('Source-revision evidence must disclose an exact commit.');
    if(value!==null&&value!==record.sourceRevision)fail('Native source revision and retained source receipt contradict.');
    value=record.sourceRevision;
  }
  if(value!==null&&!/^([a-f0-9]{40}|[a-f0-9]{64})$/.test(value))fail('Disclosed native source revision is not an exact commit.');
  return value;
}
function read(root,identity,maximum=1048576){
  typed(identity);const file=runtime.projectPath(root,identity.path);
  if(path.relative(root,file).split(path.sep).join('/')!==identity.path||!fs.statSync(file).isFile()||fs.statSync(file).size>maximum||runtime.hash(file)!==identity.sha256)fail('Referenced AUDIO evidence is noncanonical, changed or oversized.');
  return {file,value:JSON.parse(fs.readFileSync(file,'utf8'))};
}
function nested(root,value,depth=0,historicalRoot){
  if(depth>24)fail('AUDIO assertion nesting bound exceeded.');
  if(Array.isArray(value)){if(value.length>256)fail('AUDIO assertion array bound exceeded.');for(const item of value)nested(root,item,depth+1,historicalRoot);return;}
  if(!value||typeof value!=='object')return;
  if(typeof value.path==='string'&&Object.hasOwn(value,'sha256'))readIdentity(root,originalIdentity(root,value,historicalRoot));
  for(const item of Object.values(value))nested(root,item,depth+1,historicalRoot);
}
function readIdentity(root,identity){typed(identity);const file=runtime.projectPath(root,identity.path);if(path.relative(root,file).split(path.sep).join('/')!==identity.path||!fs.statSync(file).isFile()||runtime.hash(file)!==identity.sha256)fail('Nested AUDIO assertion source changed.');return file;}
function rights(brief,{root,task,requireGeneration=false}={}){
  typed(brief.request.rights,'rights');
  if(!root)return;
  const value=read(root,brief.request.rights).value;
  fields(value,['schemaVersion','task','owner','promptRightsConfirmed','generationAllowed'],['schemaVersion','task','owner','promptRightsConfirmed','generationAllowed'],'generation rights');
  if(value.schemaVersion!=='bubo-media-rights/v1'||value.promptRightsConfirmed!==true||typeof value.generationAllowed!=='boolean'
      ||(requireGeneration&&(value.generationAllowed!==true||(task&&value.task!==task))))fail('Current scoped prompt rights and applicable task-bound generation authority are required.');
  text(value.task,'rights task',80);text(value.owner,'rights owner',160);
  if(!ID.test(value.task))fail('Prompt rights must name a safe original task identity.');
  if(brief.provider==='LOCAL'){
    const receipt=read(root,brief.request.installation,33554432).value;
    if(receipt.schemaVersion!=='bubo-media-installation/v1'||receipt.backend!==backend||!Array.isArray(receipt.licenses)||receipt.licenses.length<1||receipt.licenses.length>16)fail('Applicable LOCAL installation/license assertions are required.');
    for(const ref of receipt.licenses){
      const license=read(root,originalIdentity(root,ref,brief.historicalRoot)).value;
      if(license.schemaVersion!=='bubo-media-license-evidence/v1'||license.accepted!==true||!Array.isArray(license.backends)||!license.backends.includes(backend)||!Array.isArray(license.licenseIds)||!license.licenseIds.length)fail('Applicable explicit license evidence is missing.');
      if(license.licenseIds.some(id=>typeof id!=='string'||!id.trim()))fail('Explicit nonempty license identifiers are required.');
      if(license.sourceEvidence!==undefined)readIdentity(root,originalIdentity(root,license.sourceEvidence,brief.historicalRoot));
      nested(root,license,0,brief.historicalRoot);
    }
  }
}
function validateBrief(brief,context={}){
  fields(brief,['schemaVersion','kind','purpose','provider','spatialization','loopIntent','request','technical','historicalRoot'],['schemaVersion','kind','purpose','provider','spatialization','loopIntent','request','technical'],'AUDIO brief');
  if(brief.schemaVersion!=='opencaw-audio-brief/v1'||!modalities.includes(brief.kind)||!['LOCAL','CLOUD'].includes(brief.provider)||!['2d','3d'].includes(brief.spatialization)||typeof brief.loopIntent!=='boolean')fail('Explicit supported AUDIO kind, provider, spatialization and loop intent are required.');
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
  rights(brief,context);return JSON.parse(JSON.stringify(brief));
}
function request(brief,{root,asset}={}){
  if(brief?.historicalRoot!==undefined)fail('Historical-root briefs are import-only and cannot authorize a new native dispatch.');
  const record=asset?.task?asset:asset?.asset;const value=validateBrief(brief,{root,task:record?.task,requireGeneration:true});
  if(value.provider!=='LOCAL')fail('CLOUD generation requires a separately selected available session capability; this command supports provenance import only.');
  if(!record?.task)fail('Task-owned asset identity is required for dispatch.');
  return {schemaVersion:'bubo-media-request/v1',task:record.task,backend,...value.request};
}
function candidateData(value){return value?.kind==='candidate'?value.data:value;}
function technical(context){
  const {root,state,brief,status}=context,candidate=candidateData(context.candidate),record=state?.asset||state;
  const checked=validateBrief(brief,{root,task:record?.task});
  if(!candidate||!Array.isArray(candidate.outputs)||!status?.assetSha256)fail('Current candidate and composite fingerprint are required.');
  if(candidate.provider!==checked.provider)fail('Candidate provider differs from its explicit AUDIO brief.');
  const report={schemaVersion:'opencaw-media-technical/v1',assetSha256:status.assetSha256,outputs:candidate.outputs,status:'passed',checks:[],measurements:[],references:[],generationIdentities:[],unavailable:{lufs:{unavailable:true,reason:'No loudness analyzer was selected; native metrics are peak/RMS/clipping/silence.'},loopQuality:{unavailable:true,reason:'Only an actual complete listening/seam review establishes a usable loop.'},cleanupCounters:{unavailable:true,reason:'The SFX manifest exposes one-load/unloaded lifecycle flags, not independent allocator/driver memory counters.'}}};
  const check=(id,passed,reason)=>{report.checks.push({id,status:passed?'passed':'failed',reason});if(!passed)report.status='failed';};
  if(candidate.provider!=='LOCAL'){
    report.status='failed';report.checks.push({id:'authoritative-analysis',status:'unavailable',reason:'Imported CLOUD media has no compatible native measurement ancestry; provide a supported separately selected analysis capability before technical acceptance.'});return report;
  }
  const manifests=candidate.manifests||[candidate.manifest];
  if(!manifests.length||manifests.length>128)fail('Complete bounded native provenance is required.');
  const mapped=new Map();
  for(const manifestIdentity of manifests){
    const neutral=read(root,manifestIdentity).value,parameters=neutral.generation?.parameters;
    if(neutral.schemaVersion!==1||neutral.modality!=='sfx'||neutral.backend?.kind!=='local'||neutral.backend.capability!==backend||!parameters)fail('AUDIO native provenance identifies another capability.');
    const native=read(root,parameters.nativeManifest).value,result=read(root,parameters.nativeResult,8388608).value,hostContext=read(root,parameters.hostContext,8388608).value,source=read(root,parameters.sourceRequest).value;
    if(parameters.historicalRoot!==checked.historicalRoot)fail('Historical-root mapping differs between the brief and retained provenance.');
    if(checked.historicalRoot!==undefined&&!['historical-import','external-import'].includes(candidate.origin))fail('Historical-root media requires an explicit import origin, never a new dispatch claim.');
    const originalRoot=sourceRoot(root,checked.historicalRoot),recordedRoot=typeof hostContext.projectRoot==='string'?runtime.native(hostContext.projectRoot):null;
    if(typeof recordedRoot!=='string'||!path.isAbsolute(recordedRoot)||!runtime.samePath(path.resolve(recordedRoot),originalRoot))fail('Original host-context projectRoot differs from the declared current project-confined source root.');
    report.references.push(manifestIdentity,parameters.nativeManifest,parameters.nativeResult,parameters.hostContext,parameters.sourceRequest);
    if(native.schemaVersion!=='bubo-media-manifest/v1'||native.status!=='generated-staged'||native.backend!==backend||native.promotion!==false||native.humanReview!=='pending'||!Array.isArray(native.outputs))fail('Only successful native staged SFX measurements are accepted.');
    if(result.schemaVersion!=='bubo-execution-result/v1'||result.apiVersion!==1||result.status!=='succeeded'||result.workflow!=='media'||result.operation!=='generate'||result.hostContextSha256!==parameters.hostContext.sha256||native.hostContextSha256!==parameters.hostContext.sha256)fail('Native result/host-context ancestry differs.');
    if(hostContext.schemaVersion!=='bubo-host-context/v1'||hostContext.policy?.purpose!=='local-media'||hostContext.policy.pipeline!=='LOCAL'||hostContext.policy.media?.sha256!==native.mediaPolicySha256)fail('Native host context lacks the recorded LOCAL media authority.');
    object(result.runtime,'actual native runtime build');
    same(result.data,native,'Native returned manifest');same(result.runtime,parameters.runtime?.build,'Native runtime');same(native.runtimeBuild,result.runtime,'Native build');
    const sourceRevision=revision(root,parameters,native,result,hostContext,originalRoot);
    disclosed(neutral.backend.toolVersion,sourceRevision,'Neutral backend version');disclosed(neutral.workflow?.revision,sourceRevision,'Neutral workflow revision');disclosed(parameters.runtime.revision,sourceRevision,'Claimed native runtime revision');
    if(parameters.runtime.sourceRevisionEvidence)report.references.push(parameters.runtime.sourceRevisionEvidence);
    if(!SHA.test(result.runtime.resourceCatalogSha256||'')||native.resourceCatalogSha256!==result.runtime.resourceCatalogSha256)fail('Native resource catalogs contradict the actual build.');
    disclosed(parameters.runtime.resourceCatalogSha256,result.runtime.resourceCatalogSha256,'Claimed runtime resource catalog');
    disclosed(neutral.workflow?.digest,native.workerSourceSha256,'Neutral workflow worker digest');
    if(parameters.modelCatalog){
      if(parameters.modelCatalog.sha256!==native.catalogSha256)fail('Model catalogue snapshot differs from the native generation catalogue.');
      const catalog=read(root,parameters.modelCatalog).value,definitions=catalog.backends?.filter(item=>item.id===backend),definition=definitions?.[0];
      if(definitions?.length!==1||!definition||!Array.isArray(definition.files)||!definition.files.length||definition.files.length>4096)fail('Selected native catalogue lacks bounded model provenance.');
      const files=definition.files.map(file=>{
        if(typeof file.path!=='string'||!SHA.test(file.sha256||''))fail('Native catalogue model identity is malformed.');
        return {path:file.path,sha256:file.sha256,...(file.revision!==undefined?{revision:file.revision}:{}),...(file.repository!==undefined?{repository:file.repository}:{})};
      });
      const revisions=[...new Set(definition.files.map(file=>file.revision).filter(Boolean))],licenses=[...new Set(definition.files.map(file=>file.license).filter(Boolean))];
      const modelDigest=crypto.createHash('sha256').update(canonical(files)).digest('hex');
      disclosed(neutral.model?.name,backend,'Neutral model name');disclosed(neutral.model?.revision,revisions.join(';')||null,'Neutral model revision');
      disclosed(neutral.model?.digest,modelDigest,'Neutral model digest');disclosed(neutral.model?.license,licenses.join(';')||null,'Neutral model license');
      report.references.push(parameters.modelCatalog);
    }
    report.generationIdentities.push({sourceRunId:source.requestId,historicalRoot:checked.historicalRoot||null,
      sourceRevision:sourceRevision||{unavailable:true,reason:'The retained native build and supplied original metadata disclose no exact source commit.'},
      resourceCatalogSha256:result.runtime.resourceCatalogSha256,workerSourceSha256:native.workerSourceSha256||{unavailable:true,reason:'The original native manifest does not disclose a worker source digest.'}});
    if(source.schemaVersion!=='bubo-media-request/v1'||!ID.test(source.requestId||'')||!ID.test(source.task||'')||!Array.isArray(source.items)||source.items.length<1||source.items.length>4)fail('Native source request is incomplete or unsupported.');
    if(originalIdentity(root,{path:native.requestPath,sha256:native.requestSha256},checked.historicalRoot).path!==parameters.sourceRequest.path||native.requestSha256!==parameters.sourceRequest.sha256||source.backend!==backend||hostContext.task!==source.task)fail('Native source-request/task ancestry differs.');
    same(source.settings,checked.request.settings,'Explicit native execution settings');same(source.budget,checked.request.budget,'Explicit native output budget');same(source.items.map(nativeItem),checked.request.items,'Actual requested item set');
    same(native.requestedSettings,source.settings,'Native requested settings');same(parameters.execution,native.actualSettings,'Native observed execution');
    if(native.actualSettings?.device!==source.settings.device||native.actualSettings.precision!==source.settings.precision||native.actualSettings.offload!==source.settings.offload)fail('Native execution changed device, precision or offload.');
    same(originalIdentity(root,source.rights,checked.historicalRoot),checked.request.rights,'Native prompt rights');same(originalIdentity(root,source.installation,checked.historicalRoot),checked.request.installation,'Native installation identity');
    if(native.unloaded!==true||native.modelLoads!==1)fail('Native execution did not report its required one-load/unload lifecycle.');
    for(const output of neutral.outputs||[]){
      const measured=native.outputs.find(item=>originalIdentity(root,{path:item.path,sha256:item.sha256},checked.historicalRoot).path===output.stagedPath&&item.sha256===output.sha256);
      if(!measured||mapped.has(output.stagedPath))fail('Native output identity is missing or duplicated.');
      same(nativeItem(parameters.requested),nativeItem(measured.requested),'Neutral requested item');same(parameters.actual,measured.actual,'Neutral actual sampling settings');
      mapped.set(output.stagedPath,{measured,parameters});
    }
  }
  if(mapped.size!==candidate.outputs.length||candidate.outputs.length!==checked.request.items.length)fail('Provenance does not cover exactly the complete requested candidate set.');
  let total=0;
  for(const output of candidate.outputs){
    readIdentity(root,output);const match=mapped.get(output.path);if(!match||match.measured.sha256!==output.sha256)fail('Candidate/native measurements differ.');
    const actual=match.measured,bytes=fs.statSync(runtime.projectPath(root,output.path)).size;
    if(actual.bytes!==bytes||actual.sampleRate!==44100||actual.channels!==2||!Number.isSafeInteger(actual.frames)||actual.frames<=0||!Number.isFinite(actual.peak)||actual.peak<0||!Number.isFinite(actual.rms)||actual.rms<0||!Number.isFinite(actual.clippedFraction)||actual.clippedFraction<0||actual.clippedFraction>1||!Number.isFinite(actual.silentFraction)||actual.silentFraction<0||actual.silentFraction>1)fail('Actual native measured SFX format/counters are invalid.');
    const requested=checked.request.items.find(item=>item.id===actual.id);
    if(!requested)fail('Measured native item differs from this AUDIO brief.');same(nativeItem(actual.requested),requested,'Measured native request');
    if(actual.actual?.seed!==requested.seed||actual.actual.steps!==requested.steps||actual.actual.guidance!==requested.guidance||typeof actual.actual.scheduler!=='string')fail('Imported actual native settings differ.');
    if(actual.actual.nativeMetadata){const metadata=originalIdentity(root,actual.actual.nativeMetadata,checked.historicalRoot);read(root,metadata);report.references.push(metadata);}
    const durationSeconds=actual.frames/actual.sampleRate;total+=bytes;
    const measurement={path:output.path,sha256:output.sha256,bytes,durationSeconds,sampleRate:actual.sampleRate,channels:actual.channels,frames:actual.frames,peak:actual.peak,rms:actual.rms,clippedFraction:actual.clippedFraction,silentFraction:actual.silentFraction,amplitudePreserved:true,actualSampling:{seed:actual.actual.seed,steps:actual.actual.steps,guidance:actual.actual.guidance,scheduler:actual.actual.scheduler}};
    report.measurements.push(measurement);
    check(actual.id+'-format',path.extname(output.path).toLowerCase()==='.wav'&&durationSeconds<=checked.request.budget.maximumAudioSeconds&&Math.abs(durationSeconds-requested.seconds)<=1/44100+1e-9,'Native measured44100Hz stereo FLOAT WAV, duration and file identity retain their original bytes.');
    check(actual.id+'-bytes',bytes<=checked.request.budget.maximumBytesPerOutput,'Actual per-output bytes stay within explicit native budget.');
    for(const [policy,key] of [['maxPeak','peak'],['maxClippedFraction','clippedFraction'],['maxSilentFraction','silentFraction']])check(actual.id+'-'+key,checked.technical[policy]===null||actual[key]<=checked.technical[policy],`Reported native ${key}=${actual[key]}; explicit threshold=${checked.technical[policy]===null?'observe only':checked.technical[policy]}. No normalization or repair applied.`);
  }
  check('total-output-budget',candidate.outputs.length<=checked.request.budget.maximumOutputs&&total<=checked.request.budget.maximumTotalBytes,'Current complete output count and total bytes fit the explicit batch budget.');
  report.references=[...new Map(report.references.map(ref=>[ref.path,ref])).values()];return report;
}
function validateTechnicalReport(report,context){const expected=technical(context);same(report,expected,'Current AUDIO technical report');if(expected.status!=='passed')fail('Current authoritative AUDIO technical acceptance is unavailable or failed.');return report;}
function reviewBase(review,context,kind){
  object(review,'AUDIO review');const record=context.state?.asset||context.state;validateBrief(context.brief,{root:context.root,task:record?.task});
  if(review.schemaVersion!=='opencaw-media-review/v1')fail('Unsupported AUDIO review schema.');
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
  if(permission.schemaVersion!=='opencaw-audio-distribution/v1'||permission.task!==record.task||permission.purpose!==context.brief.purpose||permission.rightsConfirmed!==true)fail('Separate current AUDIO distribution rights for this task/purpose are required.');
  readIdentity(root,permission.sourceEvidence);nested(root,permission);
  const target=read(root,review.targetEvidence).value;
  fields(target,['schemaVersion','task','engine','outputs','spatialization','loopIntent','playbackReviewed','loadDisposeReviewed','loopSeamReviewed','sourceEvidence'],['schemaVersion','task','engine','outputs','spatialization','loopIntent','playbackReviewed','loadDisposeReviewed','loopSeamReviewed','sourceEvidence'],'runtime playback evidence');
  if(target.schemaVersion!=='opencaw-audio-runtime-evidence/v1'||target.task!==record.task||target.spatialization!==context.brief.spatialization||target.loopIntent!==context.brief.loopIntent||target.playbackReviewed!==true||target.loadDisposeReviewed!==true||(target.loopIntent&&target.loopSeamReviewed!==true))fail('Actual current selected-engine playback/load/dispose evidence is required.');
  same(target.engine,review.engine,'Runtime target engine');same(target.outputs,review.outputs,'Runtime target output set');readIdentity(root,target.sourceEvidence);nested(root,target);
  return review;
}
module.exports={domain,modalities,backend,backends:[backend],validateBrief,request,technical,validateTechnicalReport,validateReview,validateRuntimeReview};
