'use strict';

// Owned native-shaped metadata only: no synthesis, decoding or real human verdicts.
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),crypto=require('crypto');
const runtime=require('../commands/lib/bubo-runtime.cjs'),spec=require('../commands/lib/music-pipeline.cjs');
const cache=path.basename(runtime.BASE)==='.hephaera'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.hephaera/.cache');
const evidence=path.join(cache,'tasks/hephaera-music-pipeline/evidence/spec-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')),task='owned-music',observations=[];let sequence=0;
const check=(value,message)=>{assert(value,message);observations.push(message);};
const rejects=(action,pattern,message)=>{assert.throws(action,pattern,message);observations.push(message);};
const copy=value=>JSON.parse(JSON.stringify(value));
function write(name,value){const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,typeof value==='string'||Buffer.isBuffer(value)?value:JSON.stringify(value,null,2)+'\n');return name;}
const identity=name=>({path:name,sha256:runtime.hash(path.join(root,name))});
const sha=value=>crypto.createHash('sha256').update(value,'utf8').digest('hex');
const source=identity(write('inputs/license-source.txt','Owned synthetic assertion, no terms accepted'));
const license=identity(write('inputs/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends:[spec.backend],licenseIds:['OWNED fixture'],sourceEvidence:source}));
const installation=identity(write('inputs/installation.json',{schemaVersion:'bubo-media-installation/v1',backend:spec.backend,licenses:[license]}));
const rights=identity(write('inputs/rights.json',{schemaVersion:'bubo-media-rights/v1',task,owner:'Owned fixture',promptRightsConfirmed:true,generationAllowed:true}));
write('MEDIA.md','Owned policy-source assertion, no configured provider');
const base={schemaVersion:'hephaera-music-brief/v1',kind:'instrumental',purpose:'Owned test purpose',provider:'LOCAL',spatialization:'2d',loopIntent:false,
  request:{rights,installation,settings:{device:'cuda:0',precision:'bfloat16',offload:'none'},budget:{maximumOutputs:1,maximumBytesPerOutput:268435456,maximumTotalBytes:268435456,maximumPixels:4096,maximumAudioSeconds:600},
    items:[{id:'owned',prompt:'Original instrumental fixture, calm piano, rising middle then resolve',negativePrompt:'',seed:9,steps:8,guidance:1,seconds:10,loopCandidate:false,
      music:{mode:'instrumental',lyrics:'',vocalLanguage:'unknown',bpm:null,keyScale:'',timeSignature:'',shift:3}}]},technical:{maxPeak:null,maxClippedFraction:null,maxSilentFraction:null}};
function authorizeLyrics(brief,changes={}){
  const assertion=identity(write('inputs/lyrics-source-'+(++sequence)+'.txt','Owned original-lyrics fixture; not actual rights consent'));
  brief.lyricsRights=identity(write('inputs/lyrics-rights-'+sequence+'.json',{schemaVersion:'hephaera-music-lyrics-rights/v1',task,purpose:brief.purpose,
    lyrics:brief.request.items.map(item=>({itemId:item.id,lyricsSha256:sha(item.music.lyrics)})),rightsConfirmed:true,generationAllowed:true,sourceEvidence:assertion,...changes}));
  return brief;
}
function song(){const brief=copy(base);brief.kind='supplied-lyrics';brief.request.items[0].music={mode:'supplied-lyrics',lyrics:'[Verse]\nWe carry our own light.\nCafé skies, 新しい日.\n',vocalLanguage:'en',bpm:120,keyScale:'D minor',timeSignature:'4',shift:3};return authorizeLyrics(brief);}
function settings(item){
  const m=item.music;
  return {protocol:'bubo-music-settings/v1',sourceRevision:'a'.repeat(40),mode:m.mode,planningLmLoaded:false,lmMetadata:null,innerSeed:item.seed,normalization:false,cpuDecode:false,actualOutputCount:1,sampleRate:48000,attention:'sdpa',
    params:{caption:item.prompt,lyrics:m.mode==='instrumental'?'[Instrumental]':m.lyrics,instrumental:m.mode==='instrumental',vocal_language:m.vocalLanguage,duration:item.seconds,seed:item.seed,inference_steps:item.steps,guidance_scale:1,
      shift:m.shift,keyscale:m.keyScale,timesignature:m.timeSignature,bpm:m.bpm,task_type:'text2music',infer_method:'ode',sampler_mode:'euler',thinking:false,use_cot_metas:false,use_cot_caption:false,use_cot_language:false,use_cot_lyrics:false,
      enable_normalization:false,dcw_enabled:false,fade_in_duration:0,fade_out_duration:0,latent_shift:0,latent_rescale:1,reference_audio:null,src_audio:null,audio_codes:''},
    config:{batch_size:1,allow_lm_batch:false,use_random_seed:false,seeds:[item.seed],audio_format:'wav32'},
    conditioning:[{text:'Formatted instruction and original caption: '+item.prompt,tokenCount:30,maximumTokens:256,truncated:false},{text:'Formatted original lyrics: '+(m.mode==='instrumental'?'[Instrumental]':m.lyrics),tokenCount:20,maximumTokens:2048,truncated:false}],
    humanReview:'pending',promotion:false};
}
function fixture(brief=base,{mutateSource=()=>{},mutateNative=()=>{},mutateNeutral=()=>{},mutateMetadata=()=>{}}={}){
  const prefix='staging/run-'+(++sequence),sourceRevision='1'.repeat(40),build={cliSha256:'6'.repeat(64),resourceCatalogSha256:'2'.repeat(64),assemblies:{},launch:{}};
  const request={...spec.request(brief,{root,asset:{task}}),requestId:'run-'+sequence,outputDirectory:'staging'};mutateSource(request);
  const sourceRequest=identity(write(prefix+'/request.json',request));
  const media=identity('MEDIA.md'),hostContext=identity(write(prefix+'/context.json',{schemaVersion:'bubo-host-context/v1',projectRoot:root,task:request.task,policy:{purpose:'local-media',pipeline:'LOCAL',media}}));
  const modelFiles=[{path:'owned-model.bin',sha256:'7'.repeat(64),revision:'owned-snapshot',repository:'owned/repository',license:'OWNED fixture'}];
  const modelCatalog=identity(write(prefix+'/catalog.json',{schemaVersion:'bubo-media-catalog/v1',backends:[{id:spec.backend,files:modelFiles}]}));
  const modelDigest=sha(JSON.stringify(runtime.canonical(modelFiles.map(({path,sha256,revision,repository})=>({path,sha256,revision,repository})))));
  const outputs=request.items.map(item=>{
    const metadata=settings(item);mutateMetadata(metadata);const nativeMetadata=identity(write(prefix+'/'+item.id+'.settings.json',metadata));
    const output=write(prefix+'/'+item.id+'.wav','Owned synthetic nonaudio bytes: no acoustic claim; run/item='+prefix+'/'+item.id);
    return {id:item.id,path:output,sha256:identity(output).sha256,bytes:fs.statSync(path.join(root,output)).size,sampleRate:48000,channels:2,frames:item.seconds*48000,peak:1.4,rms:0.2,clippedFraction:0.03,silentFraction:0.1,
      requested:item,actual:{seed:item.seed,steps:item.steps,guidance:1,scheduler:'ode/euler',nativeMetadata},humanReview:'pending',promotion:false};
  });
  const native={schemaVersion:'bubo-media-manifest/v1',status:'generated-staged',requestPath:sourceRequest.path,requestSha256:sourceRequest.sha256,hostContextSha256:hostContext.sha256,mediaPolicySha256:media.sha256,backend:spec.backend,runtimeBuild:build,
    requestedSettings:request.settings,actualSettings:{...request.settings,deviceName:'Owned synthetic GPU'},modelLoads:1,unloaded:true,
    cleanup:{mechanism:'torch._C._cuda_clearCublasWorkspaces',allocatedBeforeWorkspaceClearBytes:1024,reservedBeforeWorkspaceClearBytes:2048,endingAllocatedBytes:0,endingReservedBytes:512},
    outputs,humanReview:'pending',promotion:false,resourceCatalogSha256:build.resourceCatalogSha256,catalogSha256:modelCatalog.sha256,workerSourceSha256:'4'.repeat(64),completedAt:'2026-10-30T01:00:00Z'};
  mutateNative(native);const nativeManifest=identity(write(prefix+'/native.json',native));
  const sourceRevisionEvidence=identity(write(prefix+'/build.json',{schemaVersion:'bubo-build/v1',sourceRevision,sourceDirty:false,capabilities:{build}}));
  const nativeResult=identity(write(prefix+'/result.json',{schemaVersion:'bubo-execution-result/v1',apiVersion:2,workflow:'media',operation:'generate',status:'succeeded',runtime:build,data:native,hostContextSha256:hostContext.sha256}));
  const manifests=native.outputs.map(output=>{
    const neutral={schemaVersion:1,runId:request.requestId+'-'+output.id,createdAt:native.completedAt,modality:'music',backend:{kind:'local',provider:'Bubo',capability:spec.backend,toolVersion:sourceRevision},
      model:{name:spec.backend,revision:'owned-snapshot',digest:modelDigest,license:'OWNED fixture'},workflow:{name:spec.backend,revision:sourceRevision,digest:native.workerSourceSha256},
      generation:{prompt:output.requested.prompt,seed:output.requested.seed,parameters:{nativeManifest,nativeResult,hostContext,sourceRequest,modelCatalog,runtime:{build,revision:sourceRevision,resourceCatalogSha256:build.resourceCatalogSha256,sourceRevisionEvidence},execution:native.actualSettings,requested:output.requested,actual:output.actual}},
      outputs:[{stagedPath:output.path,sha256:output.sha256,status:'staged'}]};mutateNeutral(neutral);return identity(write(prefix+'/'+output.id+'.neutral.json',neutral));
  });
  return {root,state:{asset:{task,domain:'MUSIC'}},brief,candidate:{provider:'LOCAL',manifests,outputs:native.outputs.map(item=>({path:item.path,sha256:item.sha256}))},status:{assetSha256:'a'.repeat(64)},native};
}
try{
  check(spec.domain==='MUSIC'&&spec.modalities.join(',')==='instrumental,supplied-lyrics','MUSIC independently declares instrumental and supplied-lyric modes');
  check(!fs.readFileSync(require.resolve('../commands/lib/music-pipeline.cjs'),'utf8').includes("require('./audio-pipeline"),'MUSIC has no AUDIO runtime import');
  check(spec.validateBrief(base,{root,task}).kind==='instrumental','Current native-shaped instrumental request validates');
  const vocal=song();check(spec.validateBrief(vocal,{root,task}).request.items[0].music.lyrics===vocal.request.items[0].music.lyrics,'Unicode, exact whitespace, supplied lines and section text remain byte-for-byte intact');
  const dispatched=spec.request(vocal,{root,asset:{task}});check(dispatched.backend==='ace-step-turbo'&&dispatched.items[0].music.mode==='supplied-lyrics'&&!dispatched.lyricsRights,'Only actual native DTO fields cross the boundary; host-only lyric rights stay host-owned');
  check(dispatched.requestId===undefined&&dispatched.outputDirectory===undefined,'Shared lifecycle owns domain/version collision-safe native identities');
  const upper=copy(base);Object.assign(upper.request.items[0],{seed:2147483647,steps:1,seconds:600,prompt:'x'.repeat(512)});Object.assign(upper.request.items[0].music,{bpm:300,shift:5,keyScale:'Gb MAJOR',timeSignature:'6'});
  check(spec.validateBrief(upper,{root,task}).request.items[0].seconds===600,'Actual DTO upper caption/seed/duration/BPM/shift limits accept exact inclusive boundaries');
  const lower=copy(base);Object.assign(lower.request.items[0],{seed:0,steps:8,seconds:10});Object.assign(lower.request.items[0].music,{bpm:30,shift:1});
  check(spec.validateBrief(lower,{root,task}).request.items[0].music.bpm===30,'Actual DTO lower music limits remain available');
  for(const [label,change] of [
    ['unknown mastering',b=>b.mastering=true],['invented planning control',b=>b.request.planningLm=true],['stem control',b=>b.request.items[0].stems=true],['unsupported voice object',b=>b.request.items[0].voice={}],
    ['image width',b=>b.request.items[0].width=256],['provider fallback',b=>b.provider='AUTO'],['CPU fallback',b=>b.request.settings.device='cpu'],['wrong precision',b=>b.request.settings.precision='float16'],['offload fallback',b=>b.request.settings.offload='auto'],
    ['caption overflow',b=>b.request.items[0].prompt='x'.repeat(513)],['caption NUL',b=>b.request.items[0].prompt='x\0'],['short duration',b=>b.request.items[0].seconds=9],['long duration',b=>b.request.items[0].seconds=601],['fractional duration',b=>b.request.items[0].seconds=10.5],
    ['negative seed',b=>b.request.items[0].seed=-1],['seed overflow',b=>b.request.items[0].seed=2147483648],['fractional seed',b=>b.request.items[0].seed=0.1],['zero steps',b=>b.request.items[0].steps=0],['too many steps',b=>b.request.items[0].steps=9],
    ['wrong guidance',b=>b.request.items[0].guidance=2],['negative prompt',b=>b.request.items[0].negativePrompt='silence'],['loop contradiction',b=>b.loopIntent=true],['mixed song mode',b=>b.request.items[0].music.mode='supplied-lyrics'],['instrumental lyrics',b=>b.request.items[0].music.lyrics='a line'],
    ['instrumental language',b=>b.request.items[0].music.vocalLanguage='en'],['unknown music field',b=>b.request.items[0].music.referenceAudio='secret.wav'],['missing BPM',b=>delete b.request.items[0].music.bpm],['low BPM',b=>b.request.items[0].music.bpm=29],['high BPM',b=>b.request.items[0].music.bpm=301],
    ['fractional BPM',b=>b.request.items[0].music.bpm=120.5],['unsupported key',b=>b.request.items[0].music.keyScale='H minor'],['unsupported meter',b=>b.request.items[0].music.timeSignature='7'],['low shift',b=>b.request.items[0].music.shift=0.9],['high shift',b=>b.request.items[0].music.shift=5.1],
    ['nonfinite shift',b=>b.request.items[0].music.shift=Infinity],['old budget alias',b=>b.request.budget.maxOutputs=1],['output count overflow',b=>b.request.budget.maximumOutputs=5],['nonfinite byte budget',b=>b.request.budget.maximumTotalBytes=Infinity],
    ['too small pixel bound',b=>b.request.budget.maximumPixels=1],['duration budget breach',b=>b.request.budget.maximumAudioSeconds=9],['negative peak policy',b=>b.technical.maxPeak=-1],['unsupported threshold',b=>b.technical.maxSilentFraction=1.1],
    ['wrong acceptance case',b=>b.request.acceptance={case:'supplied-lyrics',kind:'candidate',approval:rights}],['untyped approval',b=>b.request.acceptance={case:'instrumental',kind:'candidate',approval:'yes'}]
  ]){const brief=copy(base);change(brief);rejects(()=>spec.validateBrief(brief,{root,task}),/./,label+' rejects before native dispatch');}
  const two=copy(base);two.request.budget.maximumOutputs=2;two.request.items.push({...copy(two.request.items[0]),id:'second'});check(spec.validateBrief(two,{root,task}).request.items.length===2,'Explicit bounded distinct multiple music variants validate');
  const duplicate=copy(two);duplicate.request.items[1].id='owned';rejects(()=>spec.validateBrief(duplicate,{root,task}),/unique/,'Duplicate track identity cannot share result ancestry');
  const accept=copy(base);accept.request.acceptance={case:'instrumental',kind:'revision',approval:rights};check(spec.validateBrief(accept,{root,task}).request.acceptance.kind==='revision','Existing typed single-output acceptance attempt is preserved');
  const tooMany=copy(two);tooMany.request.acceptance=accept.request.acceptance;rejects(()=>spec.validateBrief(tooMany,{root,task}),/one matching/,'Acceptance cannot replenish a native allowance with extra tracks');
  for(const [label,change] of [
    ['missing lyric rights',b=>delete b.lyricsRights],['untyped lyric rights',b=>b.lyricsRights={}],['changed trailing whitespace',b=>b.request.items[0].music.lyrics+=' '],['changed newline',b=>b.request.items[0].music.lyrics=b.request.items[0].music.lyrics.replace(/\n/g,'\r\n')],
    ['unknown singing language',b=>b.request.items[0].music.vocalLanguage='unknown'],['unsupported language',b=>b.request.items[0].music.vocalLanguage='xx'],['blank song',b=>b.request.items[0].music.lyrics=' '],['lyrics overflow',b=>b.request.items[0].music.lyrics='a'.repeat(4097)],['lyrics NUL',b=>b.request.items[0].music.lyrics='a\0'],['changed purpose',b=>b.purpose='Another purpose']
  ]){const brief=copy(vocal);change(brief);rejects(()=>spec.validateBrief(brief,{root,task}),/./,label+' cannot satisfy exact supplied-lyric rights');}
  const vocalTwo=copy(vocal);vocalTwo.request.budget.maximumOutputs=2;vocalTwo.request.items.push({...copy(vocalTwo.request.items[0]),id:'second'});authorizeLyrics(vocalTwo);
  check(spec.validateBrief(vocalTwo,{root,task}).request.items.length===2,'Lyric authorization covers each exact ordered track');
  vocalTwo.request.items.reverse();rejects(()=>spec.validateBrief(vocalTwo,{root,task}),/order/,'Reordering tracks invalidates exact lyric-rights mapping');
  const historical=authorizeLyrics(copy(vocal),{task:'old-task',generationAllowed:false});check(spec.validateBrief(historical,{root,task}).kind==='supplied-lyrics','Historical lyric review/import need no fabricated fresh generation grant');
  rejects(()=>spec.request(historical,{root,asset:{task}}),/current task generation authority/,'Historical lyric authority cannot authorize a new song attempt');
  const wrongTask=authorizeLyrics(copy(vocal),{task:'another-task'});rejects(()=>spec.request(wrongTask,{root,asset:{task}}),/current task/,'Different task lyric grant cannot dispatch under current task');
  for(const [label,changes] of [['unconfirmed rights',{rightsConfirmed:false}],['wrong rights schema',{schemaVersion:'other'}],['unsupported host permission',{distribute:true}]]){
    const brief=authorizeLyrics(copy(vocal),changes);rejects(()=>spec.validateBrief(brief,{root,task}),/./,label+' cannot create supplied-lyric authority');
  }
  const lyricsRecord=JSON.parse(fs.readFileSync(path.join(root,vocal.lyricsRights.path),'utf8')),lyricsSource=lyricsRecord.sourceEvidence;
  const original=fs.readFileSync(path.join(root,lyricsSource.path));write(lyricsSource.path,'changed');rejects(()=>spec.validateBrief(vocal,{root,task}),/source changed/,'Nested lyric assertion mutation invalidates unchanged rights JSON');fs.writeFileSync(path.join(root,lyricsSource.path),original);
  const context=fixture(),report=spec.technical(context);check(report.status==='passed'&&report.measurements[0].sampleRate===48000&&report.measurements[0].channels===2,'Complete native receipt chain retains actual48000Hz stereo measurements');
  check(report.measurements[0].peak===1.4&&report.measurements[0].amplitudePreserved&&report.measurements[0].clippedFraction===0.03,'Raw amplitudes above unity and clipping observations are preserved without normalization');
  check(report.executions[0].cleanup.endingAllocatedBytes===0&&report.executions[0].cleanup.endingReservedBytes===512&&!report.unavailable.cleanupCounters,'Measured allocator cleanup accepts reserved memory honestly without claiming all GPU memory is zero');
  check(report.executions[0].aggregateDriverMemory.unavailable&&report.unavailable.lufs.unavailable&&report.unavailable.loopQuality.unavailable,'Unmeasured aggregate-driver memory, loudness and acoustic loop quality stay unavailable');
  check(spec.validateTechnicalReport(report,context)===report,'Current music report revalidates actual complete ancestry and metadata');
  const vocalReport=spec.technical(fixture(vocal));check(vocalReport.status==='passed'&&vocalReport.measurements[0].music.lyricsSha256===sha(vocal.request.items[0].music.lyrics),'Actual supplied text/settings and disabled planning are bound to measured song metadata');
  check(spec.technical(fixture(two)).measurements.length===2,'Technical provenance covers complete variant batch');
  const firstRun=fixture(two),secondRun=fixture(two);
  check(spec.technical(firstRun).status==='passed'&&spec.technical(secondRun).status==='passed','Two separate complete native runs retain valid requests/results/metadata for both requested music item IDs');
  const crossRun=(firstIndex,secondIndex)=>({...firstRun,candidate:{provider:'LOCAL',
    manifests:[firstRun.candidate.manifests[firstIndex],secondRun.candidate.manifests[secondIndex]],
    outputs:[firstRun.candidate.outputs[firstIndex],secondRun.candidate.outputs[secondIndex]]}});
  check(spec.technical(crossRun(0,1)).status==='passed','A complete original A/B wrapper selection across valid full native runs retains exact requested item coverage');
  const repeatedItem=crossRun(0,0);
  check(repeatedItem.candidate.outputs[0].path!==repeatedItem.candidate.outputs[1].path&&repeatedItem.candidate.outputs[0].sha256!==repeatedItem.candidate.outputs[1].sha256,'Repeated A selection uses distinct actual fixture run paths and byte hashes rather than a duplicated path or forged receipt');
  rejects(()=>spec.technical(repeatedItem),/duplicate|coverage|requested item/i,'Two valid full native A/B runs cannot substitute distinct A/A outputs for the requested complete A/B item set');
  check(spec.technical(fixture(base,{mutateSource:r=>Object.assign(r.items[0],{width:null,height:null,voice:null})})).status==='passed','Native absent optional controls serialized as null retain exact semantics');
  const omittedNegative=fixture(base,{mutateSource:r=>delete r.items[0].negativePrompt,mutateNative:n=>n.outputs[0].requested.negativePrompt=''});
  check(spec.technical(omittedNegative).status==='passed','Original raw GenerationItem JSON may omit negativePrompt while the native requested record serializes its documented empty default');
  for(const value of [null,'contradictory negative prompt'])rejects(()=>spec.technical(fixture(base,{mutateSource:r=>r.items[0].negativePrompt=value})),/differs/,'An explicit recorded '+JSON.stringify(value)+' negative prompt cannot inherit the absent-key default');
  const omittedFresh=copy(base);delete omittedFresh.request.items[0].negativePrompt;rejects(()=>spec.validateBrief(omittedFresh,{root,task}),/fields/,'Fresh MUSIC briefs still require explicit empty negativePrompt');
  const strict=copy(base);strict.technical.maxPeak=1;check(spec.technical(fixture(strict)).status==='failed','Explicit raw peak policy can fail without altering the output');
  const forged=copy(report);forged.measurements[0].music.planningLmLoaded=true;rejects(()=>spec.validateTechnicalReport(forged,context),/differs/,'Forged passed report cannot skip native music revalidation');
  for(const [label,change] of [
    ['wrong protocol',m=>m.protocol='other'],['instrumental relabeled song',m=>m.mode='supplied-lyrics'],['planning LM loaded',m=>m.planningLmLoaded=true],['LM output metadata',m=>m.lmMetadata={}],['different inner seed',m=>m.innerSeed=99],
    ['hidden peak normalization',m=>m.normalization=true],['CPU decode fallback',m=>m.cpuDecode=true],['extra output',m=>m.actualOutputCount=2],['wrong rate',m=>m.sampleRate=44100],['attention fallback',m=>m.attention='flash'],
    ['changed caption',m=>m.params.caption='another caption'],['generated lyrics',m=>m.params.lyrics='invented'],['wrong instrumental intent',m=>m.params.instrumental=false],['wrong language',m=>m.params.vocal_language='en'],['changed duration',m=>m.params.duration=11],
    ['changed seed',m=>m.params.seed=99],['changed steps',m=>m.params.inference_steps=9],['changed guidance',m=>m.params.guidance_scale=2],['changed shift',m=>m.params.shift=4],['changed BPM',m=>m.params.bpm=90],['changed key',m=>m.params.keyscale='C major'],['changed meter',m=>m.params.timesignature='4'],
    ['changed task',m=>m.params.task_type='cover'],['changed solver',m=>m.params.infer_method='sde'],['changed sampler',m=>m.params.sampler_mode='other'],['thinking enabled',m=>m.params.thinking=true],['planning metas',m=>m.params.use_cot_metas=true],['planning caption',m=>m.params.use_cot_caption=true],
    ['planning language',m=>m.params.use_cot_language=true],['planning lyrics',m=>m.params.use_cot_lyrics=true],['normalization enabled',m=>m.params.enable_normalization=true],['DCW edit',m=>m.params.dcw_enabled=true],['fade in',m=>m.params.fade_in_duration=1],['fade out',m=>m.params.fade_out_duration=1],
    ['latent shift',m=>m.params.latent_shift=0.1],['latent rescale',m=>m.params.latent_rescale=0.9],['reference conditioning',m=>m.params.reference_audio='private.wav'],['source audio edit',m=>m.params.src_audio='source.wav'],['audio-code input',m=>m.params.audio_codes='codes'],
    ['batch fanout',m=>m.config.batch_size=2],['LM batch',m=>m.config.allow_lm_batch=true],['random seed',m=>m.config.use_random_seed=true],['extra seed',m=>m.config.seeds.push(3)],['hidden PCM quantization',m=>m.config.audio_format='wav16'],
    ['missing conditioning',m=>m.conditioning=[]],['truncated caption',m=>m.conditioning[0].truncated=true],['truncated lyric',m=>m.conditioning[1].truncated=true],['caption token overflow',m=>m.conditioning[0].tokenCount=257],['lyric token overflow',m=>m.conditioning[1].tokenCount=2049],
    ['incorrect caption bound',m=>m.conditioning[0].maximumTokens=2048],['empty conditioning',m=>m.conditioning[1].text=''],['missing raw flag',m=>delete m.normalization]
  ])rejects(()=>spec.technical(fixture(base,{mutateMetadata:change})),/./,label+' fails authoritative native music validation');
  for(const [label,change] of [
    ['wrong actual scheduler',n=>n.outputs[0].actual.scheduler='other'],['different actual seed',n=>n.outputs[0].actual.seed=10],['missing settings file',n=>delete n.outputs[0].actual.nativeMetadata],['wrong rate',n=>n.outputs[0].sampleRate=44100],['missing metrics',n=>delete n.outputs[0].rms],
    ['wrong cleanup mechanism',n=>n.cleanup.mechanism='invented'],['allocation leak',n=>n.cleanup.endingAllocatedBytes=1],['negative reservation',n=>n.cleanup.endingReservedBytes=-1],['missing cleanup',n=>n.cleanup=null],['missing cleanup counter',n=>delete n.cleanup.allocatedBeforeWorkspaceClearBytes],['failed unload',n=>n.unloaded=false],
    ['wrong native modality',n=>n.backend='stable-audio-open']
  ])rejects(()=>spec.technical(fixture(base,{mutateNative:change})),/./,label+' cannot pass technical acceptance');
  check(spec.technical(fixture(base,{mutateNative:n=>n.outputs[0].frames+=100})).status==='failed','Requested duration cannot hide conflicting measured native frames');
  const changed=fixture();fs.appendFileSync(path.join(root,changed.candidate.outputs[0].path),'changed');rejects(()=>spec.technical(changed),/changed/,'Changed staged bytes invalidate native measurement ancestry');
  const changedMetadata=fixture();fs.appendFileSync(path.join(root,changedMetadata.native.outputs[0].actual.nativeMetadata.path),' ');rejects(()=>spec.technical(changedMetadata),/changed/,'Changed settings bytes cannot retain their old metadata identity');
  const cloud=copy(vocal);cloud.provider='CLOUD';delete cloud.request.settings;delete cloud.request.installation;delete cloud.request.budget.maximumPixels;cloud.request.items=cloud.request.items.map(({id,prompt,seconds,music})=>({id,prompt,seconds,music}));
  check(spec.validateBrief(cloud,{root,task}).kind==='supplied-lyrics','CLOUD import retains exact supplied lyrics and rights without invented native controls');
  rejects(()=>spec.request(cloud,{root,asset:{task}}),/session capability/,'CLOUD dispatch never silently falls back to LOCAL');
  check(spec.technical({...context,brief:cloud,candidate:{...context.candidate,provider:'CLOUD'}}).checks[0].status==='unavailable','Unsupported CLOUD measurements remain unavailable');
  const human=identity(write('inputs/human-source.json',{fixture:'Not actual human listening'}));
  const content={schemaVersion:'hephaera-media-review/v1',assetSha256:context.status.assetSha256,outputs:context.candidate.outputs,kind:'content',verdict:'accepted',reviewer:'Owned fixture',reason:'Schema plumbing only',sourceEvidence:human,
    criteria:{listenedEntireOutput:true,matchesBrief:true,intendedVocalContentReviewed:true,artifactsAcceptable:true,headTailAccepted:true}};
  check(spec.validateReview(content,context)===content,'Complete instrumental/vocal-intent/full-track criteria validate fixture review plumbing');
  for(const key of Object.keys(content.criteria)){const missed=copy(content);missed.criteria[key]=false;rejects(()=>spec.validateReview(missed,context),/complete-track/,key+' cannot be skipped in accepted full-track review');}
  const songContext=fixture(vocal),songReview={...copy(content),outputs:songContext.candidate.outputs};rejects(()=>spec.validateReview(songReview,songContext),/complete-track/,'Song acceptance requires explicit every-supplied-line review');
  songReview.criteria.everySuppliedLineReviewed=true;check(spec.validateReview(songReview,songContext)===songReview,'Song every-line review is required independently of audible vocal intent');
  const looping=copy(base);looping.loopIntent=true;looping.request.items[0].loopCandidate=true;rejects(()=>spec.validateReview(content,{...context,brief:looping}),/loop-seam/,'Unreviewed loop cannot be accepted from a generated candidate flag');
  const loopReview=copy(content);loopReview.criteria.loopSeamReviewed=true;check(spec.validateReview(loopReview,{...context,brief:looping})===loopReview,'Explicit seam review completes only the requested loop gate');
  const falseClaim=copy(content);falseClaim.criteria.loopSeamReviewed=false;rejects(()=>spec.validateReview(falseClaim,context),/loop-seam/,'A claimed loop-review field cannot be silently ignored on nonloop briefs');
  const rejected={...copy(content),verdict:'rejected',criteria:{matchesBrief:false}};check(spec.validateReview(rejected,context).verdict==='rejected','Failed complete listening remains explicitly recordable without invented positive criteria');
  const engine={engine:'THREEJS',sha256:'3'.repeat(64)},distributionSource=identity(write('inputs/distribution-source.txt','Owned synthetic distribution assertion'));
  const rightsEvidence=identity(write('inputs/distribution.json',{schemaVersion:'hephaera-music-distribution/v1',task,purpose:base.purpose,rightsConfirmed:true,sourceEvidence:distributionSource}));
  const playbackSource=identity(write('inputs/playback-source.txt','Owned synthetic target assertion'));
  const targetEvidence=identity(write('inputs/target.json',{schemaVersion:'hephaera-music-runtime-evidence/v1',task,engine,outputs:context.candidate.outputs,spatialization:'2d',loopIntent:false,playbackReviewed:true,loadDisposeReviewed:true,loopSeamReviewed:false,sourceEvidence:playbackSource}));
  const runtimeReview={...copy(content),kind:'runtime',criteria:{targetPlaybackReviewed:true,loadDisposeReviewed:true,spatializationReviewed:true},engine,target:{spatialization:'2d',loopIntent:false},rightsEvidence,targetEvidence};
  check(spec.validateRuntimeReview(runtimeReview,context)===runtimeReview,'Separate current distribution and exact selected-engine playback/load/dispose evidence validate fixture plumbing');
  const noDistribution=copy(runtimeReview);delete noDistribution.rightsEvidence;rejects(()=>spec.validateRuntimeReview(noDistribution,context),/identity|object/,'Prompt generation rights cannot substitute for current runtime distribution rights');
  const wrongPermission=identity(write('inputs/other-distribution.json',{schemaVersion:'hephaera-music-distribution/v1',task:'other-task',purpose:base.purpose,rightsConfirmed:true,sourceEvidence:distributionSource}));
  rejects(()=>spec.validateRuntimeReview({...copy(runtimeReview),rightsEvidence:wrongPermission},context),/current MUSIC distribution/,'Historical or another-task distribution evidence cannot authorize this runtime handoff');
  const wrongPlayback=identity(write('inputs/other-target.json',{schemaVersion:'hephaera-music-runtime-evidence/v1',task,engine,outputs:[],spatialization:'2d',loopIntent:false,playbackReviewed:true,loadDisposeReviewed:true,loopSeamReviewed:false,sourceEvidence:playbackSource}));
  rejects(()=>spec.validateRuntimeReview({...copy(runtimeReview),targetEvidence:wrongPlayback},context),/output set/,'Playback of another track set cannot establish current target acceptance');
  const wrongTarget=copy(runtimeReview);wrongTarget.target.spatialization='3d';rejects(()=>spec.validateRuntimeReview(wrongTarget,context),/spatialization/,'Target cannot silently change intended spatialization');
  const stale=copy(runtimeReview);stale.assetSha256='b'.repeat(64);rejects(()=>spec.validateRuntimeReview(stale,context),/fingerprint/,'Runtime review is bound to exact current composite asset identity');
  for(const [label,ref] of [['distribution',distributionSource],['playback',playbackSource]]){const bytes=fs.readFileSync(path.join(root,ref.path));write(ref.path,'changed');rejects(()=>spec.validateRuntimeReview(runtimeReview,context),/changed/,label+' underlying source mutation invalidates runtime acceptance');fs.writeFileSync(path.join(root,ref.path),bytes);}
  const songTarget=identity(write('inputs/song-target.json',{schemaVersion:'hephaera-music-runtime-evidence/v1',task,engine,outputs:songContext.candidate.outputs,spatialization:'2d',loopIntent:false,playbackReviewed:true,loadDisposeReviewed:true,loopSeamReviewed:false,sourceEvidence:playbackSource}));
  const songRuntime={...copy(runtimeReview),outputs:songContext.candidate.outputs,targetEvidence:songTarget};check(spec.validateRuntimeReview(songRuntime,songContext)===songRuntime,'Exact song target evidence and current distribution remain separate from lyric-generation authority');
  const lyricSourceBytes=fs.readFileSync(path.join(root,lyricsSource.path));write(lyricsSource.path,'changed after song target review');
  rejects(()=>spec.validateRuntimeReview(songRuntime,songContext),/changed/,'Song runtime revalidation rehashes underlying lyric rights before handoff or promotion');fs.writeFileSync(path.join(root,lyricsSource.path),lyricSourceBytes);
  const result={assertions:observations.length,observations,limits:['Native-shaped owned metadata and nonaudio bytes only','No installation, inference, actual listening, acoustic quality or real runtime promotion'],nativeShapeSource:'runtime/bubo/src/media/Domain/Contracts.cs; Infrastructure/FixedMediaWorker.cs; Application/MediaService.cs; resources/media/music/worker.py'};
  fs.writeFileSync(path.join(evidence,'latest.json'),JSON.stringify(result,null,2)+'\n');console.log('MUSIC spec checks passed: '+observations.length+' assertions; no models or real media used.');
}finally{
  if(!runtime.within(evidence,root)||path.dirname(root)!==evidence||!path.basename(root).startsWith('owned-'))throw new Error('Refusing unsafe owned fixture cleanup');
  fs.rmSync(root,{recursive:true,force:true});
}
