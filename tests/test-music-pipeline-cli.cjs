'use strict';

// Actual CLI and coordinator boundaries with owned metadata/harmless bytes.
// Native requests, license assertions, human/runtime reviews and measurement
// counters below are synthetic fixtures, not real consent or acoustic evidence.
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const runtime=require('../commands/lib/bubo-runtime.cjs'),contracts=require('../commands/lib/media-pipeline-contract.cjs');
const lifecycle=require('../commands/lib/media-pipeline-state.cjs'),engines=require('../commands/lib/engine-contract.cjs');
const coordinator=require('../commands/lib/media-pipeline-command.cjs'),spec=require('../commands/lib/music-pipeline.cjs');
const cache=path.basename(runtime.BASE)==='.hephaera'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.hephaera/.cache');
const evidence=path.join(cache,'tasks/hephaera-music-pipeline/evidence/cli-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')),task='owned-music-cli',workspace='.hephaera/.cache/owned-media',mediaState='.hephaera/.cache/shared-media-allowance';
const observations=[],unavailable={unavailable:true,reason:'Owned synthetic fixture; not a real provider/model/acoustic observation.'};
const copy=value=>JSON.parse(JSON.stringify(value));
function check(value,message){assert(value,message);observations.push(message);}
function write(name,value){const full=path.join(root,name);fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,typeof value==='string'||Buffer.isBuffer(value)?value:JSON.stringify(value,null,2)+'\n');return name;}
const ref=name=>lifecycle.identity(root,name);
function cli(operation,args=[],expected=0){
  const result=cp.spawnSync(process.execPath,[path.join(runtime.BASE,'commands/lib/media-pipeline-command.cjs'),'MUSIC',operation,'--root',root,...args],{encoding:'utf8',windowsHide:true});
  check(result.status===expected,'Actual CLI exit for '+operation+': '+result.stderr);
  if(expected!==0)return result.stdout.trim().startsWith('{')?JSON.parse(result.stdout):result.stderr;
  const value=JSON.parse(result.stdout);check(result.stdout.trim().startsWith('{')&&result.stdout.trim().endsWith('}'),'CLI emits one JSON object: '+operation);return value;
}
function reject(operation,args,pattern){const message=cli(operation,args,1);check(pattern.test(message),'Rejected '+operation+' for the stated boundary: '+message);}
function snapshot(folder=root){const rows=[];function visit(dir){for(const name of fs.readdirSync(dir).sort()){const full=path.join(dir,name),stat=fs.lstatSync(full);rows.push([path.relative(folder,full),stat.isDirectory()?'dir':stat.isSymbolicLink()?'link':runtime.hash(full)]);if(stat.isDirectory()&&!stat.isSymbolicLink())visit(full);}}visit(folder);return JSON.stringify(rows);}
const media='# MEDIA.md\nGenerated from Hephaera media pipeline templates:\n- CLOUD\n- LOCAL\n---\n'+['Pipeline Availability','Capability Matrix','Destinations And Budgets','Rights, Consent, And Provenance','Review And Promotion'].map(x=>'## '+x+'\n').join('\n')+'Image, music, sound-effect SFX and voice are independent. Require the user to choose a provider. Never switch or fall back between providers silently.\n';
write('MEDIA.md',media);write(`.hephaera/.cache/tasks/${task}/TASK.md`,'# Owned synthetic task\n');contracts.generate({root,domain:'MUSIC',inline:true});
write('inputs/rights.json',{schemaVersion:'bubo-media-rights/v1',task,owner:'Owned synthetic assertion only',promptRightsConfirmed:true,generationAllowed:true});
write('inputs/license-source.json',{fixture:'Not an actual license acceptance'});
write('inputs/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends:['ace-step-turbo'],licenseIds:['owned-fixture-only'],sourceEvidence:ref('inputs/license-source.json')});
write('inputs/installation.json',{schemaVersion:'bubo-media-installation/v1',backend:'ace-step-turbo',licenses:[ref('inputs/license.json')]});
const brief={schemaVersion:'hephaera-music-brief/v1',kind:'supplied-lyrics',purpose:'Owned test fixture, no real media requested',provider:'LOCAL',spatialization:'2d',loopIntent:false,
  request:{rights:ref('inputs/rights.json'),installation:ref('inputs/installation.json'),settings:{device:'cuda:0',precision:'bfloat16',offload:'none'},
    budget:{maximumOutputs:1,maximumBytesPerOutput:33554432,maximumTotalBytes:33554432,maximumPixels:4096,maximumAudioSeconds:20},
    items:[{id:'owned',prompt:'Owned harmless metadata fixture',negativePrompt:'',seed:17,steps:8,guidance:1,seconds:20,loopCandidate:false,music:{mode:'supplied-lyrics',lyrics:'[Verse]\nWe carry our own light.\nCaf\u00e9 skies rise.\n',vocalLanguage:'en',bpm:100,keyScale:'C major',timeSignature:'4',shift:3}}]},
  technical:{maxPeak:1,maxClippedFraction:0,maxSilentFraction:1}};
const lyricSource=ref(write('inputs/lyrics-source.json',{fixture:'Owned synthetic lyric permission only, not actual consent'}));
const lyricRights=write('inputs/lyrics-rights.json',{schemaVersion:'hephaera-music-lyrics-rights/v1',task,purpose:brief.purpose,lyrics:brief.request.items.map(item=>({itemId:item.id,lyricsSha256:crypto.createHash('sha256').update(item.music.lyrics,'utf8').digest('hex')})),rightsConfirmed:true,generationAllowed:true,sourceEvidence:lyricSource});
brief.lyricsRights=ref(lyricRights);
write('inputs/brief.json',brief);
function nativeSettings(item){
  const m=item.music;
  return {protocol:'bubo-music-settings/v1',sourceRevision:'a'.repeat(40),mode:m.mode,planningLmLoaded:false,lmMetadata:null,innerSeed:item.seed,normalization:false,cpuDecode:false,attention:'sdpa',actualOutputCount:1,sampleRate:48000,
    conditioning:[{text:'Owned caption: '+item.prompt,maximumTokens:256,tokenCount:30,truncated:false},{text:'Owned supplied text: '+m.lyrics,maximumTokens:2048,tokenCount:20,truncated:false}],
    params:{caption:item.prompt,lyrics:m.mode==='instrumental'?'[Instrumental]':m.lyrics,instrumental:m.mode==='instrumental',vocal_language:m.vocalLanguage,bpm:m.bpm,keyscale:m.keyScale,timesignature:m.timeSignature,shift:m.shift,duration:item.seconds,seed:item.seed,inference_steps:item.steps,guidance_scale:1,task_type:'text2music',infer_method:'ode',sampler_mode:'euler',thinking:false,use_cot_metas:false,use_cot_caption:false,use_cot_language:false,use_cot_lyrics:false,enable_normalization:false,dcw_enabled:false,fade_in_duration:0,fade_out_duration:0,latent_shift:0,latent_rescale:1,reference_audio:null,src_audio:null,audio_codes:''},
    config:{batch_size:1,allow_lm_batch:false,use_random_seed:false,seeds:[item.seed],audio_format:'wav32'}};
}
function current(stateFile){return lifecycle.status({root,stateFile});}
function provenance(stateFile,selected=brief,prefix='inputs'){
  const sourceRequest={schemaVersion:'bubo-media-request/v1',requestId:'original-owned-historical-run-'+prefix.replace(/\W/g,'-'),task,backend:'ace-step-turbo',outputDirectory:workspace+'/staging/music',...selected.request};
  const sourceRevision='1'.repeat(40),workerSourceSha256='4'.repeat(64);
  const source=write(prefix+'/source-request.json',sourceRequest),host=write(prefix+'/native-context.json',{schemaVersion:'bubo-host-context/v1',projectRoot:root,task,policy:{purpose:'local-media',pipeline:'LOCAL',media:ref('MEDIA.md')},fixture:'No native execution occurred'});
  const build={cliSha256:'6'.repeat(64),resourceCatalogSha256:'2'.repeat(64),assemblies:{},launch:{},fixture:'Owned nonexistent build only'};
  const sourceRevisionEvidence=ref(write(prefix+'/build-info.json',{schemaVersion:'bubo-build/v1',sourceRevision,sourceDirty:false,capabilities:{build}}));
  const modelFiles=[{path:'owned-model.bin',sha256:'7'.repeat(64),revision:'owned-fixture-snapshot',repository:'owned/fixture',license:'OWNED synthetic license only'}];
  const modelCatalog=ref(write(prefix+'/catalog.json',{schemaVersion:'bubo-media-catalog/v1',backends:[{id:'ace-step-turbo',files:modelFiles}]}));
  const modelDigest=crypto.createHash('sha256').update(JSON.stringify(runtime.canonical(modelFiles.map(({path,sha256,revision,repository})=>({path,sha256,revision,repository}))))).digest('hex');
  const output=write(workspace+'/staging/music/'+sourceRequest.requestId+'/000.wav','OWNED nonaudio bytes; no sound was generated or reviewed.');
  const measured={id:'owned',path:output,sha256:ref(output).sha256,bytes:fs.statSync(path.join(root,output)).size,sampleRate:48000,channels:2,frames:960000,peak:0.5,rms:0.1,clippedFraction:0,silentFraction:0.1,
    requested:selected.request.items[0],actual:{seed:17,steps:8,guidance:1,scheduler:'ode/euler',nativeMetadata:ref(write(prefix+'/native-settings.json',nativeSettings(selected.request.items[0])))}};
  const native={schemaVersion:'bubo-media-manifest/v1',status:'generated-staged',backend:'ace-step-turbo',promotion:false,humanReview:'pending',
    outputs:[measured],hostContextSha256:ref(host).sha256,mediaPolicySha256:ref('MEDIA.md').sha256,runtimeBuild:build,requestPath:source,requestSha256:ref(source).sha256,
    requestedSettings:selected.request.settings,actualSettings:selected.request.settings,resourceCatalogSha256:build.resourceCatalogSha256,catalogSha256:modelCatalog.sha256,workerSourceSha256,unloaded:true,modelLoads:1,cleanup:{mechanism:'torch._C._cuda_clearCublasWorkspaces',allocatedBeforeWorkspaceClearBytes:1024,reservedBeforeWorkspaceClearBytes:2048,endingAllocatedBytes:0,endingReservedBytes:512}};
  const nativeFile=write(prefix+'/native-manifest.json',native),result=write(prefix+'/native-result.json',{schemaVersion:'bubo-execution-result/v1',apiVersion:2,status:'succeeded',workflow:'media',operation:'generate',hostContextSha256:ref(host).sha256,runtime:build,data:native});
  const manifest={schemaVersion:1,runId:sourceRequest.requestId+'-0',createdAt:new Date().toISOString(),backend:{kind:'local',provider:'Owned fixture',capability:'ace-step-turbo',toolVersion:sourceRevision},
    modality:'music',model:{name:'ace-step-turbo',revision:'owned-fixture-snapshot',digest:modelDigest,license:'OWNED synthetic license only'},workflow:{name:'Owned synthetic fixture',revision:sourceRevision,digest:workerSourceSha256},
    generation:{prompt:selected.request.items[0].prompt,negativePrompt:unavailable,seed:17,parameters:{nativeManifest:ref(nativeFile),nativeResult:ref(result),hostContext:ref(host),sourceRequest:ref(source),modelCatalog,runtime:{build,revision:sourceRevision,resourceCatalogSha256:build.resourceCatalogSha256,sourceRevisionEvidence},requested:measured.requested,actual:measured.actual,execution:selected.request.settings}},
    inputs:[{description:'Owned synthetic bytes only',source:'fixture',rights:'No actual model/media license asserted',consent:'not-applicable'}],
    outputs:[{stagedPath:output,sha256:ref(output).sha256,status:'staged',runtimeTarget:unavailable}],runtime:{destination:unavailable,budgets:selected.request.budget},review:{status:'pending',reviewer:unavailable,reviewedAt:unavailable,notes:'No actual human listening'}};
  return {manifestFile:write(prefix+'/neutral-manifest.json',manifest),output,outputs:[ref(output)]};
}
async function main(){
  const help=cp.spawnSync(process.execPath,[path.join(runtime.BASE,'commands/lib/media-pipeline-command.cjs'),'MUSIC','--help'],{cwd:root,encoding:'utf8'});
  check(help.status===0&&/setup-plan/.test(help.stdout)&&/recover/.test(help.stdout),'Actual help works without initializing or resolving a host');
  const shell=process.env.HEPHAERA_BASH||(process.platform==='win32'?'C:/Program Files/Git/bin/bash.exe':'bash');
  const wrapper=cp.spawnSync(shell,[path.join(runtime.BASE,'commands/music-pipeline.sh').replace(/\\/g,'/'),'--help'],{cwd:root,encoding:'utf8'});
  check(wrapper.status===0&&/music-pipeline/.test(wrapper.stdout),'Real Bash MUSIC wrapper help works outside initialized host');
  const schema=JSON.parse(fs.readFileSync(path.join(runtime.BASE,'.media/pipelines/music/brief.schema.json'),'utf8'));
  const keyPattern=new RegExp(schema.$defs.music.properties.keyScale.pattern);
  check(keyPattern.test('GB MAJOR')&&keyPattern.test('Gb major')&&!keyPattern.test('H minor'),'Published key schema preserves native case-insensitive flat keys and rejects unsupported keys');
  check(schema.$defs.localItem.properties.seconds.minimum===10&&schema.$defs.localItem.properties.seconds.maximum===600&&schema.$defs.localItem.properties.steps.maximum===8&&schema.$defs.localRequest.properties.settings.properties.precision.const==='bfloat16','Published schema retains actual native duration, step and precision limits');
  for(const filename of ['brief.local.json','brief.song.local.json','brief.cloud.json']){
    const example=JSON.parse(fs.readFileSync(path.join(runtime.BASE,'.media/pipelines/music/examples',filename),'utf8'));
    example.request.rights=brief.request.rights;if(example.provider==='LOCAL')example.request.installation=brief.request.installation;
    if(example.kind==='supplied-lyrics')example.lyricsRights=ref(write('inputs/example-'+filename+'.lyrics.json',{schemaVersion:'hephaera-music-lyrics-rights/v1',task,purpose:example.purpose,lyrics:example.request.items.map(item=>({itemId:item.id,lyricsSha256:crypto.createHash('sha256').update(item.music.lyrics,'utf8').digest('hex')})),rightsConfirmed:true,generationAllowed:false,sourceEvidence:lyricSource}));
    write('inputs/example-'+filename,example);check(cli('brief',['--brief','inputs/example-'+filename]).valid,'Published '+filename+' validates after supplying only current owned evidence references');
  }
  const beforeBrief=snapshot();check(cli('brief',['--brief','inputs/brief.json']).valid===true,'Supported explicit native brief validates without execution');
  check(snapshot()===beforeBrief,'Brief validation creates no state or outputs');
  reject('brief',['--brief','inputs/brief.json','--execute'],/protected/);
  reject('brief',['--brief','inputs/brief.json','--load','true'],/protected/);
  reject('generate',['--state','unread.json','--backend','ace-step-turbo'],/protected/);
  reject('init',['--task',task,'--asset','owned','--version','v1','--brief','inputs/brief.json','--task',task],/duplicate/);
  reject('init',['--task',task,'--asset','owned','--version','v1','--brief','inputs/brief.json','--workspace',workspace,'--staging-root','.art-staging/owned'],/not both/);
  const init=cli('init',['--task',task,'--asset','Owned song','--version','v1','--brief','inputs/brief.json','--workspace',workspace]);
  const stateFile=init.stateFile;check(current(stateFile).stage==='planned','Actual init creates independent planning state only');
  reject('generate',['--state',stateFile,'--provider','CLOUD','--workspace',workspace,'--media-state',mediaState],/conflicts/);
  reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--execute','true'],/protected/);
  reject('generate',['--state',stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--timeout','0'],/finite/);
  const malformed=JSON.parse(JSON.stringify(brief));malformed.request.items[0].seconds=601;write('inputs/too-long.json',malformed);
  reject('init',['--task',task,'--asset','too long track','--version','v1','--brief','inputs/too-long.json'],/duration/);
  const badPlanning=copy(brief);badPlanning.request.items[0].music.planningLm=true;
  reject('brief',['--brief',write('inputs/unsupported-planning.json',badPlanning)],/unsupported fields/);
  const changedLyrics=copy(brief);changedLyrics.request.items[0].music.lyrics+=' ';
  reject('brief',['--brief',write('inputs/changed-lyrics.json',changedLyrics)],/exact supplied UTF8 lyrics/);
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
  check(technicalReport.measurements[0].music.lyricsSha256===crypto.createHash('sha256').update(brief.request.items[0].music.lyrics,'utf8').digest('hex')&&!technicalReport.measurements[0].music.planningLmLoaded&&technicalReport.executions[0].cleanup.endingReservedBytes===512,'Actual CLI retains exact lyric identity, disabled planning and honest measured cleanup counters');
  reject('handoff',['--state',stateFile],/content/);
  const fingerprint=current(stateFile).assetSha256,reviewSource=ref(write('inputs/human-source.json',{fixture:'Synthetic review source; no human listened'}));
  const content={schemaVersion:'hephaera-media-review/v1',assetSha256:fingerprint,outputs:source.outputs,kind:'content',verdict:'accepted',reviewer:'Owned synthetic fixture only',reason:'Test explicit evidence binding, not acoustic quality',sourceEvidence:reviewSource,
    criteria:{listenedEntireOutput:true,matchesBrief:true,intendedVocalContentReviewed:true,everySuppliedLineReviewed:true,artifactsAcceptable:true,headTailAccepted:true}};
  const missing=write('inputs/incomplete-review.json',{...content,criteria:{}});reject('review',['--state',stateFile,'--review',missing],/criteria/);
  const missingLine=copy(content);delete missingLine.criteria.everySuppliedLineReviewed;
  reject('review',['--state',stateFile,'--review',write('inputs/unchecked-lines.json',missingLine)],/criteria/);
  const loopClaim=copy(content);loopClaim.criteria.loopSeamReviewed=false;
  reject('review',['--state',stateFile,'--review',write('inputs/unreviewed-loop.json',loopClaim)],/criteria/);
  reject('review',['--state',stateFile,'--review',write('inputs/wrong-output-review.json',{...content,outputs:[]})],/output set/);
  cli('review',['--state',stateFile,'--review',write('inputs/rejected-review.json',{...content,verdict:'rejected',criteria:{}})]);
  check(current(stateFile).contentReview==='rejected','Explicit rejected content verdict remains in immutable history');
  cli('review',['--state',stateFile,'--review',write('inputs/content-review.json',content)]);
  reject('handoff',['--state',stateFile],/runtime/);
  engines.generate(root,'THREEJS',{inline:true});const engine=lifecycle.engineIdentity(root);
  const target={directory:'assets/music/owned-fixture',codecs:['wav'],sampleRates:[48000],channels:[2],maxOutputBytes:33554432,maxAudioSeconds:20,spatialization:'2d',loopIntent:false};
  const distributionSource=ref(write('inputs/distribution-source.json',{fixture:'Synthetic distribution assertion, no real rights granted'}));
  const distribution=ref(write('inputs/distribution.json',{schemaVersion:'hephaera-music-distribution/v1',task,purpose:brief.purpose,rightsConfirmed:true,sourceEvidence:distributionSource}));
  const targetEvidence=ref(write('inputs/target-evidence.json',{schemaVersion:'hephaera-music-runtime-evidence/v1',task,engine,outputs:source.outputs,spatialization:'2d',loopIntent:false,playbackReviewed:true,loadDisposeReviewed:true,loopSeamReviewed:false,sourceEvidence:reviewSource}));
  const runtimeReview={schemaVersion:'hephaera-media-review/v1',assetSha256:fingerprint,outputs:source.outputs,kind:'runtime',verdict:'accepted',reviewer:content.reviewer,reason:content.reason,sourceEvidence:reviewSource,
    criteria:{targetPlaybackReviewed:true,loadDisposeReviewed:true,spatializationReviewed:true},engine,target,rightsEvidence:distribution,targetEvidence};
  const missingDistribution=copy(runtimeReview);delete missingDistribution.rightsEvidence;
  reject('review',['--state',stateFile,'--review',write('inputs/missing-distribution.json',missingDistribution)],/identity|rights|path/i);
  reject('review',['--state',stateFile,'--review',write('inputs/wrong-spatialization.json',{...runtimeReview,target:{...target,spatialization:'3d'}})],/spatialization/);
  cli('review',['--state',stateFile,'--review',write('inputs/runtime-review.json',runtimeReview)]);
  for(const [name,changed,reason] of [
    ['inputs/lyrics-source.json',{changed:true},'Current lyric permission source'],
    ['inputs/distribution.json',{changed:true},'Current distribution record'],
    ['inputs/distribution-source.json',{changed:true},'Nested distribution permission source'],
    ['inputs/human-source.json',{changed:true},'Human/target source'],
    ['MEDIA.md',media+'\nChanged policy\n','Shared media policy'],
    [source.output,'OWNED changed output bytes','Exact staged output']
  ]){
    const before=fs.readFileSync(path.join(root,name));write(name,changed);
    try{reject('handoff',['--state',stateFile],/changed|stale|source|identity|distribution/i);check(!fs.existsSync(path.join(root,target.directory)),reason+' mutation cannot copy runtime files');}
    finally{fs.writeFileSync(path.join(root,name),before);}
  }
  for(const [name,invalidTarget,pattern] of [
    ['outside-assets',{...target,directory:'.art-staging/forbidden'},/assets child/],
    ['wrong-codec',{...target,codecs:['ogg']},/format/],
    ['wrong-rate',{...target,sampleRates:[44100]},/format/],
    ['too-short',{...target,maxAudioSeconds:10},/budget/],
    ['too-small',{...target,maxOutputBytes:1},/budget/]
  ]){
    cli('review',['--state',stateFile,'--review',write('inputs/'+name+'-runtime.json',{...runtimeReview,target:invalidTarget})]);
    reject('handoff',['--state',stateFile],pattern);
  }
  cli('review',['--state',stateFile,'--review','inputs/runtime-review.json']);
  const handoff=cli('handoff',['--state',stateFile]);check(handoff.promotion===false&&!fs.existsSync(path.join(root,target.directory)),'Actual handoff does not copy files');
  const authorization=write('inputs/promotion.json',{schemaVersion:'hephaera-media-promotion/v1',authorized:true,assetSha256:fingerprint,target,outputs:source.outputs,authorizedBy:'Owned synthetic fixture; not a real permission',reason:'Exercise copying of harmless bytes inside owned fixture',sourceEvidence:ref(write('inputs/promotion-source.json',{fixture:'No real asset promotion authorization'}))});
  const invalidAuthorization=JSON.parse(fs.readFileSync(path.join(root,authorization),'utf8'));invalidAuthorization.outputs=[];
  reject('promote',['--state',stateFile,'--authorization',write('inputs/wrong-authorization.json',invalidAuthorization)],/different staged outputs/);
  for(const name of ['inputs/lyrics-source.json','inputs/distribution-source.json']){
    const before=fs.readFileSync(path.join(root,name));write(name,{changedBeforePromotion:true});
    try{reject('promote',['--state',stateFile,'--authorization',authorization],/changed|stale|source/i);}
    finally{fs.writeFileSync(path.join(root,name),before);}
  }
  const marker=write(target.directory+'/foreign.txt','OWNED foreign-destination sentinel');
  reject('promote',['--state',stateFile,'--authorization',authorization],/already exists/);
  check(fs.readFileSync(path.join(root,marker),'utf8')==='OWNED foreign-destination sentinel','Promotion never overwrites an existing foreign destination');
  fs.unlinkSync(path.join(root,marker));fs.rmdirSync(path.join(root,target.directory));
  const promoted=cli('promote',['--state',stateFile,'--authorization',authorization]);
  check(promoted.promotion===true&&fs.readFileSync(path.join(root,target.directory+'/000.wav'),'utf8').startsWith('OWNED nonaudio'),'Explicit CLI promotion copies only owned fixture bytes after all gates');
  const recovered=cli('recover',['--state',stateFile,'--authorization',authorization]);check(recovered.alreadyPromoted===true,'Explicit recovery recognizes exactly owned completed fixture without re-copying');
  const sourceBefore=fs.readFileSync(path.join(root,'inputs/license-source.json'));write('inputs/license-source.json',{changed:true});
  reject('recover',['--state',stateFile,'--authorization',authorization],/source changed|changed/);fs.writeFileSync(path.join(root,'inputs/license-source.json'),sourceBefore);
  const songStateDirectory=path.join(root,lifecycle.load({root,stateFile}).directory),songStateBefore=snapshot(songStateDirectory);
  const instrumental=copy(brief);instrumental.kind='instrumental';delete instrumental.lyricsRights;instrumental.loopIntent=true;
  instrumental.request.items[0].loopCandidate=true;instrumental.request.items[0].music={mode:'instrumental',lyrics:'',vocalLanguage:'unknown',bpm:null,keyScale:'GB MAJOR',timeSignature:'4',shift:3};
  const instrumentalBrief=write('inputs/instrumental-brief.json',instrumental);
  const instrumentalInit=cli('init',['--task',task,'--asset','Owned instrumental loop','--version','v1','--brief',instrumentalBrief,'--workspace',workspace]);
  check(instrumentalInit.stateFile!==stateFile&&current(instrumentalInit.stateFile).nativeRequestId!==current(stateFile).nativeRequestId,'Instrumental and song keep independent immutable asset/native identities');
  const instrumentalSource=provenance(instrumentalInit.stateFile,instrumental,'inputs/instrumental');
  cli('import',['--state',instrumentalInit.stateFile,'--provider','LOCAL','--manifest',instrumentalSource.manifestFile,'--origin','historical-import']);
  check(cli('validate',['--state',instrumentalInit.stateFile]).ok,'Instrumental native metadata validates without supplied lyric authority');
  const instrumentalReview={...content,assetSha256:current(instrumentalInit.stateFile).assetSha256,outputs:instrumentalSource.outputs,criteria:{listenedEntireOutput:true,matchesBrief:true,intendedVocalContentReviewed:true,artifactsAcceptable:true,headTailAccepted:true}};
  reject('review',['--state',instrumentalInit.stateFile,'--review',write('inputs/instrumental-unreviewed-seam.json',instrumentalReview)],/loop-seam criteria/);
  instrumentalReview.criteria.loopSeamReviewed=true;
  cli('review',['--state',instrumentalInit.stateFile,'--review',write('inputs/instrumental-reviewed-seam.json',instrumentalReview)]);
  check(current(instrumentalInit.stateFile).contentReview==='accepted'&&current(instrumentalInit.stateFile).promotion===false,'Explicit owned seam verdict can accept content while instrumental remains staged');
  check(snapshot(songStateDirectory)===songStateBefore,'Independent instrumental lifecycle leaves song version/history unchanged');
  const cloudRights=ref(write('inputs/cloud-rights.json',{schemaVersion:'bubo-media-rights/v1',task:'original-source-task',owner:'Owned historical assertion only',promptRightsConfirmed:true,generationAllowed:false}));
  const cloud=JSON.parse(JSON.stringify(brief));cloud.provider='CLOUD';cloud.request={rights:cloudRights,budget:{maximumOutputs:1,maximumBytesPerOutput:33554432,maximumTotalBytes:33554432,maximumAudioSeconds:20},items:[{id:'owned',prompt:'Owned fixture',seconds:20,music:brief.request.items[0].music}]};write('inputs/cloud-brief.json',cloud);
  const cloudInit=cli('init',['--task',task,'--asset','Owned CLOUD import','--version','v1','--brief','inputs/cloud-brief.json']);
  reject('generate',['--state',cloudInit.stateFile,'--provider','CLOUD'],/separately available authorized session capability/);
  const cloudOutput=write('.art-staging/media/music/owned-cloud/000.wav','OWNED CLOUD-origin bytes, not generated music');
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
    write('inputs/setup.json',{schemaVersion:'bubo-media-setup/v1',task,backend:'ace-step-turbo'});
    await coordinator.run(spec,['setup-plan','--root',root,'--task',task,'--provider','LOCAL','--manifest','inputs/setup.json']);check(setupCalled,'Explicit setup-plan reaches the existing setup boundary');
    let dispatchCalled=false,recorded=false;
    lifecycle.dispatch=async(options)=>{dispatchCalled=true;check(options.request.items[0].seconds===20&&!Object.hasOwn(options.request.items[0],'durationSeconds'),'Coordinator builds exact native seconds field');check(options.mediaState===mediaState&&options.controls.timeout==='120','Coordinator preserves physical shared ledger and explicit limits');return {status:'succeeded',hostMediaProvenance:[source.manifestFile]};};
    lifecycle.recordCandidate=options=>{recorded=true;check(options.manifests[0]===source.manifestFile&&options.provider==='LOCAL','Coordinator imports complete returned provenance without resetting origin/claims');};
    await coordinator.run(spec,['generate','--root',root,'--state',revised.stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--timeout','120']);
    check(dispatchCalled&&recorded,'Explicit generate composes native request and staged provenance boundaries');
  }finally{adapter.invoke=oldInvoke;lifecycle.dispatch=oldDispatch;lifecycle.recordCandidate=oldRecord;}
  const failure=cli('init',['--task',task,'--asset','Owned retained failure','--version','v1','--brief','inputs/brief.json','--workspace',workspace]);
  let failedCalls=0;
  try{
    adapter.invoke=async(operation,options)=>{
      failedCalls++;
      const submitted=JSON.parse(fs.readFileSync(path.join(root,options.get('manifest')),'utf8'));
      check(operation==='generate'&&submitted.requestId===current(failure.stateFile).nativeRequestId&&submitted.outputDirectory===workspace+'/staging/music','Real shared dispatch binds the MUSIC version request/output namespace');
      check(submitted.items[0].music.lyrics===brief.request.items[0].music.lyrics&&!Object.hasOwn(submitted,'lyricsRights')&&options.get('media-state')===mediaState,'Real dispatch preserves exact supplied text and physical native ledger without host-only fields');
      throw new Error('Owned simulated cancellation before native execution');
    };
    const args=['generate','--root',root,'--state',failure.stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState,'--timeout','120'];
    await assert.rejects(coordinator.run(spec,args),/Owned simulated cancellation/);observations.push('Native-boundary cancellation/error propagates through actual shared dispatch');
    const failed=lifecycle.load({root,stateFile:failure.stateFile});
    check(failed.events.map(event=>event.kind).join(',')==='dispatch-started,dispatch-failed'&&current(failure.stateFile).stage==='dispatch-recorded','Failed attempt retains immutable start/failure and original request identity');
    await assert.rejects(coordinator.run(spec,args),/already exists or started/);observations.push('A failed started MUSIC version cannot retry or reset a candidate allowance');
    const changedLedger=[...args];changedLedger[changedLedger.indexOf('--media-state')+1]='.hephaera/.cache/another-shared-state';
    await assert.rejects(coordinator.run(spec,changedLedger),/already exists or started/);observations.push('Changing a workspace ledger does not replenish a started attempt');
    check(failedCalls===1&&lifecycle.load({root,stateFile:failure.stateFile}).events.length===2,'Blocked retries never enter native boundary or rewrite failure history');
  }finally{adapter.invoke=oldInvoke;}
  const report={assertions:observations.length,observations,root,limits:['Owned fixture metadata and harmless nonaudio bytes only','No model, actual license acceptance, native inference, listening/runtime review or real project asset promotion','Substituted native boundaries prove coordinator argument composition and host failure retention only; not native cancellation execution']};
  fs.writeFileSync(path.join(root,'results.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({assertions:observations.length,evidence:path.join(root,'results.json'),limits:report.limits}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
