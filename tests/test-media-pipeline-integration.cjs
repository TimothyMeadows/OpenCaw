'use strict';

// Actual installed host commands and context/binding code; all permissions,
// reviews and media bytes below are synthetic. No Bubo process/model runs.
const assert = require('assert/strict'), fs = require('fs'), path = require('path'), cp = require('child_process');
const source = path.resolve(__dirname, '..');
const cache = path.basename(source) === '.opencaw' ? path.join(source, '.cache') : path.join(source, '.opencaw/.cache');
const evidence = path.join(cache, 'tasks/opencaw-parallel-media-pipeline-qa/evidence/integration-fixtures');
fs.mkdirSync(evidence, {recursive:true});
const fixture = fs.mkdtempSync(path.join(evidence, 'owned-')), observations = [], hosts = [];
const environment = {...process.env, GIT_CONFIG_NOSYSTEM:'1', GIT_CONFIG_GLOBAL:path.join(fixture,'gitconfig'),
  GIT_ALLOW_PROTOCOL:'file', GIT_TERMINAL_PROMPT:'0', GIT_AUTHOR_NAME:'OpenCaw owned fixture', GIT_AUTHOR_EMAIL:'fixture@example.invalid',
  GIT_COMMITTER_NAME:'OpenCaw owned fixture', GIT_COMMITTER_EMAIL:'fixture@example.invalid'};
for (const key of Object.keys(environment)) if (['OPENCAW_PROJECT_ROOT','GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE'].includes(key) || /^GIT_CONFIG_(COUNT|KEY_|VALUE_)/.test(key)) delete environment[key];
fs.writeFileSync(environment.GIT_CONFIG_GLOBAL, '[core]\n autocrlf = false\n[commit]\n gpgsign = false\n');
const task = 'owned-mixed-media', workspace = '.opencaw/.cache/owned-media', mediaState = '.opencaw/.cache/shared-media-allowance';
const domains = ['AUDIO','MUSIC','VOICE'], kinds = {AUDIO:'sfx',MUSIC:'instrumental',VOICE:'preset-speech'};
const visual = ['CLOUD','LOCAL','PROOF_TO_MODEL','CODE','BLENDER'];
const mediaText = '# MEDIA.md\nGenerated from OpenCaw media pipeline templates:\n- CLOUD\n- LOCAL\n---\n'
  + ['Pipeline Availability','Capability Matrix','Destinations And Budgets','Rights, Consent, And Provenance','Review And Promotion'].map(x=>'## '+x+'\n').join('\n')
  + 'Image, music, sound-effect SFX and voice are independent. Require the user to choose a provider. Never switch or fall back between providers silently.\n';
const unavailable = {unavailable:true,reason:'Owned synthetic metadata; no provider/model/acoustic observation.'};
const copy = value => JSON.parse(JSON.stringify(value));
function check(value,message) { assert(value,message); observations.push(message); }
function rejects(action,pattern,message) { assert.throws(action,pattern,message); observations.push(message); }
function execute(executable,args,cwd=fixture,expected=0) {
  if(executable==='git')args=['-c','core.longpaths=true',...args];
  const result=cp.spawnSync(executable,args,{cwd,env:environment,encoding:'utf8',windowsHide:true,timeout:120000,maxBuffer:8*1024*1024});
  assert.ifError(result.error); assert.equal(result.status,expected,JSON.stringify({executable,args,status:result.status,stdout:result.stdout,stderr:result.stderr}));
  return result;
}
const git = (root,...args) => execute('git',['-C',root,...args]).stdout.trim();
const revision = git(source,'rev-parse','HEAD');
const bash = process.env.OPENCAW_BASH || (process.platform==='win32' ? path.join(process.env.ProgramFiles || 'C:/Program Files','Git/bin/bash.exe') : 'bash');
function write(root,name,value) {
  const file=path.join(root,name); fs.mkdirSync(path.dirname(file),{recursive:true});
  fs.writeFileSync(file,typeof value==='string'||Buffer.isBuffer(value)?value:JSON.stringify(value,null,2)+'\n'); return name;
}
function snapshot(root) {
  const rows=[];
  function walk(directory) {
    if(!fs.existsSync(directory))return;
    for(const name of fs.readdirSync(directory).sort()) {
      if(name==='.git')continue;
      const file=path.join(directory,name),stat=fs.lstatSync(file),relative=path.relative(root,file);
      rows.push([relative,stat.isSymbolicLink()?'link:'+fs.readlinkSync(file):stat.isDirectory()?'directory':require('crypto').createHash('sha256').update(fs.readFileSync(file)).digest('hex')]);
      if(stat.isDirectory()&&!stat.isSymbolicLink())walk(file);
    }
  }
  walk(root);return JSON.stringify(rows);
}
function style(primary) {
  return '# STYLE.md\nGenerated from OpenCaw style templates:\n- CEL_SHADED_COMIC\nPrimary OpenCaw art pipeline:\n- '+primary
    +'\nAllowed OpenCaw art pipelines:\n'+visual.map(x=>'- '+x+'\n').join('')+'---\n'
    +'A prompt override applies only to this task and does not rewrite STYLE.md. Never switch or fall back silently.\n';
}
function install(form) {
  const root=path.join(fixture,form+'-host');fs.mkdirSync(root);
  execute('git',['init','-q','--initial-branch=main',root]);
  write(root,'host-owned.txt','Owned host content must remain unchanged.\n');
  git(root,'add','host-owned.txt');git(root,'commit','-qm','Owned host fixture');
  const baseline=path.join(root,'.opencaw');
  if(form==='clone')execute('git',['clone','-q','--shared','--no-checkout',source,baseline]);
  else git(root,'-c','protocol.file.allow=always','submodule','add','-q',source,'.opencaw');
  git(baseline,'checkout','-q','--detach',revision);
  if(form==='submodule')git(root,'add','.opencaw');
  check(git(baseline,'rev-parse','HEAD')===revision,form+': actual baseline checks out explicit source commit');
  check(form==='clone'?fs.statSync(path.join(baseline,'.git')).isDirectory():fs.statSync(path.join(baseline,'.git')).isFile(),form+': actual Git installation form is retained');
  const local = name => require(path.join(baseline,'commands/lib',name+'.cjs'));
  return {form,root,baseline,runtime:local('bubo-runtime'),contracts:local('media-pipeline-contract'),state:local('media-pipeline-state'),
    engines:local('engine-contract'),adapter:local('bubo-media-adapter'),coordinator:local('media-pipeline-command'),
    specs:Object.fromEntries(domains.map(domain=>[domain,local(domain.toLowerCase()+'-pipeline')]))};
}
function cli(host,domain,operation,args=[],expected=0) {
  const result=execute(process.execPath,[path.join(host.baseline,'commands/lib/media-pipeline-command.cjs'),domain,operation,'--root',host.root,...args],host.root,expected);
  check(result.status===expected,host.form+': installed '+domain+' '+operation+' exits as expected');
  return expected?result.stderr:JSON.parse(result.stdout);
}
function makeBrief(host,domain) {
  const {root,state}=host,backend={AUDIO:'stable-audio-open',MUSIC:'ace-step-turbo',VOICE:'qwen3-tts-customvoice'}[domain];
  const brief=JSON.parse(fs.readFileSync(path.join(host.baseline,'.media/pipelines',domain.toLowerCase(),'examples/brief.local.json'),'utf8'));
  brief.purpose='Owned combined fixture; no real media requested';
  brief.request.rights=state.identity(root,'inputs/rights.json');
  brief.request.installation=state.identity(root,write(root,'inputs/'+domain+'-installation.json',{
    schemaVersion:'bubo-media-installation/v1',backend,licenses:[state.identity(root,'inputs/license.json')]}));
  return {brief,file:write(root,'inputs/'+domain+'-brief.json',brief)};
}
function metadataCandidate(host,asset,{label=asset.domain,count=1}={}) {
  const {root,state}=host,domain=asset.domain,ref=name=>state.identity(root,name);
  const outputs=Array.from({length:count},(_,index)=>ref(write(root,workspace+'/staging/'+domain.toLowerCase()+'/'+asset.nativeRequestId+'/owned-'+index+'.wav','OWNED nonaudio bytes; not an acoustic test')));
  const sourceRef=ref(write(root,'inputs/'+label+'-provenance-source.json',{fixture:'Owned synthetic provenance'}));
  const manifest=write(root,'inputs/'+label+'-neutral.json',{schemaVersion:1,runId:'owned-'+label.toLowerCase(),createdAt:new Date().toISOString(),
    backend:{kind:'local',provider:'Owned metadata fixture',capability:'none',toolVersion:unavailable},modality:{AUDIO:'sfx',MUSIC:'music',VOICE:'voice'}[domain],
    model:{name:unavailable,revision:unavailable,digest:unavailable,license:unavailable},workflow:{name:'Owned metadata fixture',revision:unavailable,digest:unavailable},
    generation:{prompt:'Owned fixture',negativePrompt:unavailable,seed:17,parameters:{source:sourceRef}},
    inputs:[{description:'Owned harmless bytes',source:'fixture',rights:'Synthetic assertion only',consent:'not-applicable'}],
    outputs:outputs.map(value=>({stagedPath:value.path,sha256:value.sha256,status:'staged',runtimeTarget:unavailable})),runtime:{destination:unavailable,budgets:{maxOutputBytes:4096}},
    review:{status:'pending',reviewer:unavailable,reviewedAt:unavailable,notes:'No human listened'}});
  const options={root,stateFile:asset.stateFile};
  state.recordCandidate({...options,provider:'LOCAL',manifest,origin:'external-import'});
  const assetSha256=state.status(options).assetSha256;
  const technical=write(root,'inputs/'+label+'-technical.json',{schemaVersion:'opencaw-media-technical/v1',assetSha256,outputs,status:'passed',
    checks:[{id:'owned-metadata-only',status:'passed',reason:'Exercise shared lifecycle isolation; no actual acoustic measurement'}],
    measurements:outputs.map(value=>({...value,bytes:fs.statSync(path.join(root,value.path)).size,durationSeconds:1,sampleRate:24000,channels:1}))});
  state.recordTechnical({...options,report:technical});
  const human=ref(write(root,'inputs/'+label+'-human-source.json',{fixture:'Synthetic review source; not human acceptance'}));
  const review=write(root,'inputs/'+label+'-content-review.json',{schemaVersion:'opencaw-media-review/v1',assetSha256,outputs,kind:'content',verdict:'accepted',
    reviewer:'Owned synthetic fixture',reason:'Exercise common state only; no listening claim',sourceEvidence:human});
  state.recordReview({...options,review});return {options,outputs,human};
}
function handoffMatrix(host) {
  // Exercise common admission only. Domain CLI suites separately require real
  // analyzer/content/target/distribution/disclosure evidence before delegation.
  const {root,state,engines,form}=host;
  const brief=write(root,'inputs/common-handoff-brief.json',{fixture:'Shared admission metadata only; no native request or acoustic claim'});
  const created=state.init({root,task,domain:'AUDIO',modality:'sfx',asset:'owned two-output handoff fixture',version:'v1',brief,stagingRoot:workspace+'/staging/audio'});
  const asset={...created.asset,stateFile:created.stateFile},selected=metadataCandidate(host,asset,{label:'common-handoff',count:2});
  for(const engine of ['THREEJS','UNITY']) {
    engines.generate(root,engine);
    rejects(()=>state.admitHandoff(selected.options),/runtime acceptance/,form+': '+engine+' missing target runtime review blocks shared handoff');
    check(!fs.existsSync(path.join(root,'assets')),form+': '+engine+' missing target evidence creates no runtime assets');
  }
  const bytes=fs.statSync(path.join(root,selected.outputs[0].path)).size;
  const valid={directory:'assets/audio/owned-common-handoff',sampleRates:[24000],channels:[1],codecs:['wav'],maxOutputBytes:bytes*2,maxAudioSeconds:2};
  let sequence=0;
  function runtimeReview(target,engine=state.engineIdentity(root)) {
    const review=write(root,'inputs/common-runtime-'+(++sequence)+'.json',{schemaVersion:'opencaw-media-review/v1',assetSha256:state.status(selected.options).assetSha256,
      outputs:selected.outputs,kind:'runtime',verdict:'accepted',reviewer:'Synthetic common-admission fixture',reason:'No actual target playback or user acceptance',
      sourceEvidence:state.identity(root,write(root,'inputs/common-runtime-source-'+sequence+'.json',{fixture:'Synthetic target source, no player executed'})),engine,target});
    state.recordReview({...selected.options,review});
  }
  engines.generate(root,'THREEJS');runtimeReview(valid);
  check(state.admitHandoff(selected.options).engine.engine==='THREEJS'&&!state.admitHandoff(selected.options).promotion,form+': exact synthetic THREEJS admission produces a plan without promotion');
  const prior=state.engineIdentity(root);engines.generate(root,'UNITY');
  rejects(()=>state.admitHandoff(selected.options),/stale.*engine/,form+': changed engine invalidates previous target review');
  rejects(()=>runtimeReview(valid,prior),/current selected engine/,form+': old-engine runtime evidence cannot be newly recorded');
  for(const [name,target,reason] of [
    ['missing format',{},/Explicit target codec/],['codec',{...valid,codecs:['ogg']},/target format/],
    ['rate',{...valid,sampleRates:[48000]},/target format/],['channels',{...valid,channels:[2]},/target format/],
    ['aggregate bytes',{...valid,maxOutputBytes:bytes+1},/byte or duration budget/],
    ['aggregate duration',{...valid,maxAudioSeconds:1.5},/byte or duration budget/]
  ]) {runtimeReview(target);rejects(()=>state.admitHandoff(selected.options),reason,form+': '+name+' rejects despite current exact synthetic review identity');}
  runtimeReview(valid);const plan=state.admitHandoff(selected.options);
  check(plan.engine.engine==='UNITY'&&plan.outputs.length===2&&!plan.promotion,form+': compatible synthetic UNITY shared admission still copies no asset');
  const engineFile=path.join(root,'ENGINE.md'),engineBytes=fs.readFileSync(engineFile);fs.appendFileSync(engineFile,'\nOwned target contract change.\n');
  rejects(()=>state.admitHandoff(selected.options),/stale.*engine/,form+': same engine with changed contract invalidates prior target review');fs.writeFileSync(engineFile,engineBytes);
}
function bindingMatrix(host,prepared) {
  const {root,state,adapter}=host,ref=name=>state.identity(root,name);
  const approval=ref(write(root,'inputs/shared-approval.json',{schemaVersion:'bubo-media-acceptance-budget/v1',maximumCandidates:1,maximumRevisions:1,
    sharedStateRoot:mediaState,fixture:'Owned host-binding fixture; no generation authority'}));
  const claim=write(root,mediaState+'/claims/owned-used-sentinel.json',{fixture:true,candidateUsed:true,revisionUsed:true}),claimBytes=fs.readFileSync(path.join(root,claim));
  const modelDirectory=workspace+'/tools/models/owned';fs.mkdirSync(path.join(root,modelDirectory),{recursive:true});
  const python=ref(write(root,workspace+'/tools/environment/python-owned.bin','OWNED nonexecutable tool identity'));
  const infos={capability:{mediaBackends:[['flux-schnell','image'],['stable-audio-open','sfx'],['ace-step-turbo','music'],['qwen3-tts-customvoice','preset-speech'],['qwen3-tts-base','consented-cloning']].map(([id,modality])=>({id,modality}))}};
  const reference={audio:ref(write(root,'inputs/synthetic-reference.wav','OWNED nonaudio reference fixture')),
    transcript:ref(write(root,'inputs/synthetic-transcript.txt','Owned fictional reference; no private speaker.')),
    rights:ref(write(root,'inputs/synthetic-recording-rights.json',{fixture:'Owned host-context shape only'}))};
  reference.consent=ref(write(root,'inputs/synthetic-consent.json',{fixture:'Not an actual consent grant',sourceEvidence:ref(write(root,'inputs/synthetic-consent-source.json',{fixture:'Owned synthetic source'}))}));
  const profiles=[['image','flux-schnell',copy(prepared.AUDIO.request)],['sfx','stable-audio-open',copy(prepared.AUDIO.request)],
    ['instrumental','ace-step-turbo',copy(prepared.MUSIC.request)],['song','ace-step-turbo',copy(prepared.MUSIC.request)],
    ['preset','qwen3-tts-customvoice',copy(prepared.VOICE.request)],['cloning','qwen3-tts-base',copy(prepared.VOICE.request)]];
  let bindingFile,bindingBytes;const outputRoots=[];
  const selection=write(root,'.opencaw/.cache/tasks/'+task+'/owned-local-selection.json',{schemaVersion:1,pipeline:'LOCAL',selectionSource:'prompt',styleContract:'STYLE.md',styleSha256:host.runtime.hash(path.join(root,'STYLE.md'))});
  for(const [profile,backend,request] of profiles) {
    request.backend=backend;request.requestId='owned-'+profile;request.outputDirectory=workspace+'/staging/'+profile;request.acceptance={approval};
    if(profile==='song')request.items[0].music={...request.items[0].music,mode:'supplied-lyrics',lyrics:'Owned fictional line for a metadata fixture.'};
    if(profile==='cloning')request.items[0].voice={...request.items[0].voice,preset:null,expression:'',reference:copy(reference)};
    request.installation=ref(write(root,'inputs/'+profile+'-context-installation.json',{schemaVersion:'bubo-media-installation/v1',backend,modelDirectory,python,licenses:[ref('inputs/license.json')]}));
    const manifest=write(root,'inputs/'+profile+'-context-request.json',request);
    const args=['--root',root,'--task',task,'--manifest',manifest,'--workspace',workspace,'--media-state',mediaState,...(profile==='image'?['--selection',selection]:[])];
    const before=snapshot(path.join(root,mediaState)),bindingBefore=snapshot(path.join(root,'.opencaw/.cache/local-media/acceptance-roots'));
    const context=adapter.contextFor('generate',adapter.parse(args),infos);
    check(context.mediaState===mediaState&&context.context.roots.mediaState===mediaState,host.form+': '+profile+' context uses the same physical approval ledger');
    check(snapshot(path.join(root,mediaState))===before,host.form+': '+profile+' context does not create, reserve or reset claim files');
    check(snapshot(path.join(root,'.opencaw/.cache/local-media/acceptance-roots'))===bindingBefore,host.form+': '+profile+' context alone creates no approval binding');
    check(!context.context.permissions.provisioning&&!context.context.permissions.promotion,host.form+': '+profile+' binding context grants neither provisioning nor promotion');
    const file=adapter.bindSharedState(context);
    if(!bindingFile){bindingFile=file;bindingBytes=fs.readFileSync(file);}
    check(file===bindingFile&&fs.readFileSync(file).equals(bindingBytes),host.form+': '+profile+' reuses one immutable approval binding');
    check(snapshot(path.join(root,mediaState))===before,host.form+': '+profile+' explicit binding writes no native claim');
    for(const operation of ['inspect','generate']) {
      const wrong=[...args];wrong[wrong.indexOf('--media-state')+1]='.opencaw/.cache/another-ledger';
      rejects(()=>adapter.contextFor(operation,adapter.parse(wrong),infos),operation==='inspect'?/already bound/:/Approval root differs/,host.form+': '+profile+' '+operation+' cannot reroot approval');
    }
    outputRoots.push(request.outputDirectory);
  }
  check(new Set(outputRoots).size===profiles.length,host.form+': six native profiles keep separate staging roots while sharing approval identity');
  check(fs.readFileSync(bindingFile).equals(bindingBytes)&&fs.readFileSync(path.join(root,claim)).equals(claimBytes),host.form+': rejected reroots preserve binding and consumed sentinel bytes');
}
async function exercise(host) {
  const {root,baseline,contracts,state,engines,runtime,adapter,coordinator,specs,form}=host;
  const start=snapshot(root),absent=contracts.resolveAll({root,visual:true});
  check(snapshot(root)===start,form+': absent aggregate discovery writes no files');
  check(!absent.contexts.visual.configured&&domains.every(d=>!absent.contexts[d.toLowerCase()].configured),form+': unrelated absent contracts remain optional');
  for(const domain of domains) {
    const help=execute(bash,[path.join(baseline,'commands',domain.toLowerCase()+'-pipeline.sh').replace(/\\/g,'/'),'--help'],root);
    check(help.stdout.includes(domain.toLowerCase()+'-pipeline'),form+': installed thin '+domain+' wrapper is loadable without runtime initialization');
    contracts.generate({root,domain});
  }
  engines.generate(root,'THREEJS');write(root,'MEDIA.md',mediaText);
  write(root,'.opencaw/.cache/tasks/'+task+'/TASK.md','# Owned synthetic mixed-domain task\n');
  write(root,'inputs/rights.json',{schemaVersion:'bubo-media-rights/v1',task,owner:'Owned synthetic assertion only',promptRightsConfirmed:true,generationAllowed:true});
  write(root,'inputs/license-source.json',{fixture:'No external terms accepted'});
  write(root,'inputs/license.json',{schemaVersion:'bubo-media-license-evidence/v1',accepted:true,backends:['stable-audio-open','ace-step-turbo','qwen3-tts-customvoice'],licenseIds:['owned-fixture-only'],sourceEvidence:state.identity(root,'inputs/license-source.json')});
  for(const primary of visual) {
    write(root,'STYLE.md',style(primary));const before=snapshot(root),all=contracts.resolveAll({root,visual:true});
    check(all.contexts.visual.pipeline===primary&&domains.every(d=>all.contexts[d.toLowerCase()].configured),form+': four contexts coexist under '+primary);
    check(snapshot(root)===before,form+': '+primary+' combined discovery creates no files');
    for(const absentDomain of domains) {
      const name=path.join(root,absentDomain+'.md'),bytes=fs.readFileSync(name);fs.unlinkSync(name);
      try {const value=contracts.resolveAll({root,visual:true});check(!value.contexts[absentDomain.toLowerCase()].configured&&domains.filter(d=>d!==absentDomain).every(d=>value.contexts[d.toLowerCase()].configured)&&value.contexts.visual.pipeline===primary,form+': missing '+absentDomain+' preserves the other contexts under '+primary);}
      finally {fs.writeFileSync(name,bytes);}
    }
  }
  const aggregate=execute(process.execPath,[path.join(baseline,'commands/lib/media-pipeline-contract.cjs'),'resolve','--root',root,'--all','--visual'],root);
  check(JSON.parse(aggregate.stdout).contexts.visual.pipeline==='BLENDER',form+': actual installed aggregate CLI retains selected visual pipeline');
  for(const [modality,domain] of [['sfx','AUDIO'],['ambience','AUDIO'],['instrumental','MUSIC'],['song','MUSIC'],['tts','VOICE'],['voice-clone','VOICE']]) {
    const routed=execute(process.execPath,[path.join(baseline,'commands/lib/media-pipeline-contract.cjs'),'resolve','--root',root,'--modality',modality],root);
    check(JSON.parse(routed.stdout).domain===domain,form+': ordinary '+modality+' routes to '+domain);
  }
  const briefs=Object.fromEntries(domains.map(domain=>[domain,makeBrief(host,domain)])),assets={},prepared={};
  const engineFile=path.join(root,'ENGINE.md'),styleFile=path.join(root,'STYLE.md'),engineBytes=fs.readFileSync(engineFile),styleBytes=fs.readFileSync(styleFile);
  fs.unlinkSync(engineFile);fs.unlinkSync(styleFile);
  try {
    for(const domain of domains) {
      const planned=cli(host,domain,'init',['--task',task,'--asset','generation without visual context','--version','planning-only','--brief',briefs[domain].file,'--workspace',workspace]);
      const asset=state.load({root,stateFile:planned.stateFile}).asset;
      state.nativeRequest({root,stateFile:planned.stateFile,provider:'LOCAL',workspace,mediaState,request:specs[domain].request(briefs[domain].brief,{root,asset})});
      check(planned.status.stage==='planned'&&!fs.existsSync(engineFile)&&!fs.existsSync(styleFile),form+': '+domain+' generation planning creates neither ENGINE nor STYLE');
    }
  } finally {fs.writeFileSync(engineFile,engineBytes);fs.writeFileSync(styleFile,styleBytes);}
  for(const domain of domains) {
    const created=cli(host,domain,'init',['--task',task,'--asset','same human asset','--version','v1','--brief',briefs[domain].file,'--workspace',workspace]);
    assets[domain]={...state.load({root,stateFile:created.stateFile}).asset,stateFile:created.stateFile};
    prepared[domain]=state.nativeRequest({root,stateFile:created.stateFile,provider:'LOCAL',workspace,mediaState,request:specs[domain].request(briefs[domain].brief,{root,asset:assets[domain]})});
    const doctor=cli(host,domain,'doctor',['--state',created.stateFile,'--workspace',workspace]);
    check(doctor.nativeReadiness==='unverified'&&!doctor.runtime.initialized&&doctor.generation===false,form+': '+domain+' doctor exposes missing native initialization without inference');
  }
  for(const field of ['stateFile','nativeRequestId'])check(new Set(domains.map(d=>assets[d][field])).size===3,form+': same human name has distinct '+field+' across domains');
  for(const field of ['nativeState','finalOutput'])check(new Set(domains.map(d=>prepared[d][field])).size===3,form+': same human name has distinct '+field+' across domains');
  check(new Set(domains.map(d=>path.resolve(root,prepared[d].mediaState))).size===1,form+': all planned domains retain one physical native approval root');
  const staged=Object.fromEntries(domains.map(d=>[d,metadataCandidate(host,assets[d])]));
  check(domains.every(d=>state.status(staged[d].options).contentReview==='accepted'),form+': independent synthetic content-review histories coexist');
  for(const d of domains)rejects(()=>state.admitHandoff(staged[d].options),/runtime acceptance/,form+': '+d+' missing actual target review blocks handoff');
  const visualHash=runtime.hash(path.join(root,'STYLE.md')),otherBefore=['MUSIC','VOICE'].map(d=>snapshot(path.join(root,path.posix.dirname(assets[d].stateFile))));
  const audioSource=path.join(root,staged.AUDIO.human.path),sourceBytes=fs.readFileSync(audioSource);fs.appendFileSync(audioSource,' ');
  check(state.status(staged.AUDIO.options).contentReview==='stale'&&['MUSIC','VOICE'].every(d=>state.status(staged[d].options).contentReview==='accepted'),form+': changed AUDIO review source does not stale MUSIC/VOICE');fs.writeFileSync(audioSource,sourceBytes);
  const audioPolicy=path.join(root,'AUDIO.md'),policyBytes=fs.readFileSync(audioPolicy);fs.appendFileSync(audioPolicy,'\nOwned AUDIO-only policy instruction.\n');
  check(state.status(staged.AUDIO.options).stage==='stale'&&['MUSIC','VOICE'].every(d=>state.status(staged[d].options).stale.length===0),form+': AUDIO policy invalidation remains scoped');fs.writeFileSync(audioPolicy,policyBytes);
  fs.appendFileSync(path.join(root,'MEDIA.md'),'\nOwned shared policy change.\n');
  check(domains.every(d=>state.status(staged[d].options).stage==='stale'),form+': shared MEDIA policy invalidates every domain review');write(root,'MEDIA.md',mediaText);
  const failed=cli(host,'AUDIO','revise',['--state',assets.AUDIO.stateFile,'--version','missing-runtime','--brief',briefs.AUDIO.file]);
  const failure=cli(host,'AUDIO','generate',['--state',failed.stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState],1);
  check(/not initialized/.test(failure)&&state.status({root,stateFile:failed.stateFile}).eventCount===2,form+': actual missing-runtime dispatch failure retains started/failed history before native launch');
  const canceled=cli(host,'AUDIO','revise',['--state',assets.AUDIO.stateFile,'--version','canceled-host-fixture','--brief',briefs.AUDIO.file]);
  const invoke=adapter.invoke;
  try {
    adapter.invoke=async(operation,options,guards)=>{check(operation==='generate'&&options.get('media-state')===mediaState,form+': canceled host fixture forwards the same approval root');check(guards.policyReferences.some(r=>r.path==='AUDIO.md')&&!guards.policyReferences.some(r=>['MUSIC.md','VOICE.md'].includes(r.path)),form+': dispatch guards contain only the selected domain contract');throw new Error('Owned simulated cancellation; no native process started');};
    await assert.rejects(coordinator.run(specs.AUDIO,['generate','--root',root,'--state',canceled.stateFile,'--provider','LOCAL','--workspace',workspace,'--media-state',mediaState]),/Owned simulated cancellation/);
    observations.push(form+': substituted cancellation propagates while retaining host history');
  } finally {adapter.invoke=invoke;}
  check(state.status({root,stateFile:canceled.stateFile}).eventCount===2,form+': canceled host fixture cannot erase its started event');
  check(['MUSIC','VOICE'].every((d,i)=>snapshot(path.join(root,path.posix.dirname(assets[d].stateFile)))===otherBefore[i]&&state.status(staged[d].options).contentReview==='accepted'),form+': AUDIO failures/cancellation leave other review namespaces byte-identical');
  check(runtime.hash(path.join(root,'STYLE.md'))===visualHash,form+': media state/failure operations never change visual selection');
  handoffMatrix(host);
  bindingMatrix(host,prepared);
  rejects(()=>runtime.verified(),/not initialized/,form+': native execution admission remains explicitly unavailable');
  check(!fs.existsSync(path.join(root,'assets'))&&fs.readFileSync(path.join(root,'host-owned.txt'),'utf8')==='Owned host content must remain unchanged.\n',form+': no runtime asset promotion or unrelated host-content mutation');
  hosts.push({form,root,baseline,revision,domainStates:Object.fromEntries(domains.map(d=>[d,assets[d].stateFile])),nativeInitialized:false});
}
async function main() {
  for(const form of ['clone','submodule'])await exercise(install(form));
  const result={status:'pass',assertions:observations.length,platform:process.platform,sourceRevision:revision,observations,hosts,
    limits:['Owned synthetic permissions, reviews, metadata and harmless nonaudio bytes only','Actual installed CLI/context/binding code; no Bubo process/model/inference/setup/download or actual terms acceptance',
      'Metadata lifecycle fixtures bypass domain acoustic validation and cannot establish sound quality or human/target acceptance','Cancellation substitution proves host propagation only; actual native ownership/claim/cancellation is separate pinned CPU/CI evidence',
      'Six-profile binding uses synthetic capability metadata and consumed-claim sentinel; no native acceptance claim is created or spent','Shared GPU includes visual reconstruction and media; the shared six-case acceptance ledger applies to LOCAL media only','No private recordings/transcripts/generated speech or real asset promotion']};
  fs.writeFileSync(path.join(fixture,'results.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify({assertions:result.assertions,evidence:path.join(fixture,'results.json'),limits:result.limits}));
}
main().catch(error=>{fs.writeFileSync(path.join(fixture,'failure.json'),JSON.stringify({status:'fail',sourceRevision:revision,assertions:observations.length,observations,error:error.stack},null,2)+'\n');console.error(error.stack);process.exitCode=1;});
