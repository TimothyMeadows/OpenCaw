'use strict';

// Actual copying/concurrency/recovery of owned harmless fixture bytes only.
// Synthetic reviews below are not human/acoustic/rights acceptance evidence.
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert/strict'),crypto=require('crypto');
const runtime=require('../commands/lib/bubo-runtime.cjs'),contracts=require('../commands/lib/media-pipeline-contract.cjs');
const state=require('../commands/lib/media-pipeline-state.cjs'),promotion=require('../commands/lib/media-pipeline-promotion.cjs');
const engines=require('../commands/lib/engine-contract.cjs');
const cache=path.basename(runtime.BASE)==='.hephaera'?path.join(runtime.BASE,'.cache'):path.join(runtime.BASE,'.hephaera/.cache');
const evidence=path.join(cache,'tasks/hephaera-audio-pipeline/evidence/promotion-fixtures');fs.mkdirSync(evidence,{recursive:true});
const root=fs.mkdtempSync(path.join(evidence,'owned-')),task='owned-promotion',observations=[];
function write(name,value){const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');return name;}
const ref=name=>state.identity(root,name),check=(value,message)=>{assert(value,message);observations.push(message);};
const rejects=(action,pattern,message)=>{assert.throws(action,pattern,message);observations.push(message);};
const unavailable={unavailable:true,reason:'Owned synthetic metadata only'};
write(`.hephaera/.cache/tasks/${task}/TASK.md`,'# Owned test task\n');
write('MEDIA.md','# MEDIA.md\nGenerated from Hephaera media pipeline templates:\n- CLOUD\n---\n'+['Pipeline Availability','Capability Matrix','Destinations And Budgets','Rights, Consent, And Provenance','Review And Promotion'].map(x=>'## '+x+'\n').join('\n'));
contracts.generate({root,domain:'AUDIO',inline:true});engines.generate(root,'THREEJS',{inline:true});
function make(name,{count=1,destination='assets/audio/'+name}={}){
  const brief=write('inputs/'+name+'.brief.json',{fixture:'No media requested; metadata test only'});
  const asset=state.init({root,task,domain:'AUDIO',modality:'sfx',asset:name,version:'v1',brief,stagingRoot:'staging/'+name});
  const opts={root,stateFile:asset.stateFile},outputs=[];
  for(let index=0;index<count;index++)outputs.push(ref(write('staging/'+name+'/'+index+'.wav','Owned harmless nonaudio bytes '+name+' '+index)));
  const manifest=write('inputs/'+name+'.manifest.json',{schemaVersion:1,runId:name,createdAt:new Date().toISOString(),
    backend:{kind:'cloud-session',provider:'Owned fixture',capability:'none',toolVersion:unavailable},modality:'sfx',
    model:{name:unavailable,revision:unavailable,digest:unavailable,license:unavailable},workflow:{name:'Fixture',revision:unavailable,digest:unavailable},
    generation:{prompt:'Owned synthetic metadata',negativePrompt:unavailable,seed:0,parameters:{}},
    inputs:[{description:'Owned fixture bytes',source:'Fixture',rights:'Synthetic test only',consent:'not-applicable'}],
    outputs:outputs.map(output=>({stagedPath:output.path,sha256:output.sha256,status:'staged',runtimeTarget:unavailable})),
    runtime:{destination:unavailable,budgets:{bytes:4096}},review:{status:'pending',reviewer:unavailable,reviewedAt:unavailable,notes:'No actual listening'}});
  state.recordCandidate({...opts,manifest,provider:'CLOUD'});
  const assetSha256=state.status(opts).assetSha256;
  const technical=write('inputs/'+name+'.technical.json',{schemaVersion:'hephaera-media-technical/v1',assetSha256,outputs,status:'passed',
    checks:[{id:'synthetic',status:'passed',reason:'Metadata plumbing only; no actual waveform analysis'}],
    measurements:outputs.map(output=>({...output,bytes:fs.statSync(path.join(root,output.path)).size,durationSeconds:1,sampleRate:44100,channels:2}))});
  state.recordTechnical({...opts,report:technical});
  const human=ref(write('inputs/'+name+'.human.json',{fixture:'Synthetic source assertion, not user approval'}));
  const leaf=ref(write('inputs/'+name+'.license-source.json',{fixture:'Nested domain policy source'}));
  const rights=ref(write('inputs/'+name+'.distribution.json',{sourceEvidence:leaf,fixture:true}));
  const target={directory:destination,codecs:['wav'],sampleRates:[44100],channels:[2],maxOutputBytes:4096,maxAudioSeconds:4};
  for(const kind of ['content','runtime']){
    const review=write('inputs/'+name+'.'+kind+'.json',{schemaVersion:'hephaera-media-review/v1',assetSha256,outputs,kind,
      verdict:'accepted',reviewer:'Synthetic test only',reason:'Exercise ownership and copying, no actual acceptance',sourceEvidence:human,
      ...(kind==='runtime'?{engine:state.engineIdentity(root),target,rightsEvidence:rights}:{})});
    state.recordReview({...opts,review});
  }
  const sourceEvidence=ref(write('inputs/'+name+'.promotion-source.json',{fixture:'Synthetic copy authorization only'}));
  const authorization=write('inputs/'+name+'.authorization.json',{schemaVersion:'hephaera-media-promotion/v1',authorized:true,
    assetSha256,outputs,target,authorizedBy:'Owned fixture',reason:'Copy only test-owned harmless bytes',sourceEvidence});
  const validate=()=>{state.identity(root,leaf);};
  return {...opts,authorization,validate,target,outputs,asset,leaf,sourceEvidence};
}
const args=asset=>({root,stateFile:asset.stateFile,authorization:asset.authorization,validate:asset.validate});
function events(asset,kind){return state.load(asset).events.filter(event=>event.kind===kind);}
function childPromote(asset){
  const script='try { const p=require('+JSON.stringify(require.resolve('../commands/lib/media-pipeline-promotion.cjs'))+'); const result=p.promote({...JSON.parse(process.argv[1]),validate:()=>{}});process.stdout.write(JSON.stringify(result)); } catch(e) {process.stderr.write(e.message);process.exitCode=2;}';
  return new Promise(resolve=>{const child=cp.spawn(process.execPath,['-e',script,JSON.stringify({root,stateFile:asset.stateFile,authorization:asset.authorization})],{windowsHide:true,stdio:['ignore','pipe','pipe']});let stdout='',stderr='';child.stdout.on('data',x=>stdout+=x);child.stderr.on('data',x=>stderr+=x);child.on('exit',code=>resolve({code,stdout,stderr}));});
}
async function main(){
  const ordinary=make('ordinary',{count:2});
  rejects(()=>promotion.promote({...args(ordinary),validate:undefined}),/callback/,'Promotion cannot omit current domain policy guard');
  const result=promotion.promote(args(ordinary));
  check(result.promotion&&result.runtimeOutputs.length===2,'Explicit promotion performs actual owned fixture copies');
  check(state.status(ordinary).stage==='promoted'&&state.status(ordinary).promotion,'Status derives promotion from retained completion evidence');
  check(result.runtimeOutputs.every((output,index)=>ref(output.path).sha256===ordinary.outputs[index].sha256),'Published runtime files match every exact authorized source');
  check(promotion.promote(args(ordinary)).alreadyPromoted,'Identical completed promotion is idempotent without copying again');
  check(events(ordinary,'promotion-started').length===1&&events(ordinary,'promotion-completed').length===1,'Idempotent repeat creates no second publication history');
  const packageOwner=make('package-owner');promotion.promote(args(packageOwner));
  const packageChild=make('package-child',{destination:packageOwner.target.directory+'/child'});
  rejects(()=>promotion.promote(args(packageChild)),/overlaps/,'A second asset cannot publish inside another completed immutable package');
  check(state.status(packageOwner).promotion&&!fs.existsSync(path.join(root,packageChild.target.directory)),'Rejected nested promotion preserves the original package and its fresh completion');
  if(process.platform==='win32'){
    const caseChild=make('case-child',{destination:packageOwner.target.directory.toUpperCase()+'/child'});
    rejects(()=>promotion.promote(args(caseChild)),/overlaps/,'Windows case variants cannot bypass ancestor package ownership');
  }
  const orphan=make('orphan-claim'),open=fs.openSync;
  const firstIntent=path.join(root,path.dirname(orphan.stateFile),'events','000005.json');
  try{fs.openSync=(file,...values)=>{if(file===firstIntent)throw new Error('Owned interruption before intent');return open(file,...values);};
    rejects(()=>promotion.promote(args(orphan)),/interruption before intent/,'An interrupted event write retains its already registered orphan target claim');
  }finally{fs.openSync=open;}
  check(events(orphan,'promotion-started').length===0,'Orphan ownership does not invent a persisted intent');
  const orphanChild=make('orphan-child',{destination:orphan.target.directory+'/child'});
  rejects(()=>promotion.promote(args(orphanChild)),/overlaps/,'A pre-intent orphan claim still excludes another nested owner');
  check(promotion.promote(args(orphan)).promotion,'Only the exact original owner can continue its pre-intent reservation');
  const deepReservation=make('deep-reservation',{destination:'assets/audio/reserved-parent/child'}),originalCopy=fs.copyFileSync;
  try{fs.copyFileSync=()=>{throw new Error('Owned reserved preparation failure');};assert.throws(()=>promotion.promote(args(deepReservation)));}finally{fs.copyFileSync=originalCopy;}
  const ancestor=make('reserved-ancestor',{destination:'assets/audio/reserved-parent'});
  rejects(()=>promotion.promote(args(ancestor)),/overlaps/,'An interrupted descendant reservation excludes a later ancestor target');
  check(!fs.existsSync(path.join(root,ancestor.target.directory)),'Reservation conflict creates no runtime parent or partial package');
  check(promotion.recover(args(deepReservation)).promotion,'Original descendant owner can explicitly recover its retained reservation');
  const legacy=make('legacy-package');
  state.promotionTransaction(legacy,transaction=>{
    transaction.record('promotion-started',{transactionId:'owned-preclaim-fixture'});
    fs.mkdirSync(path.join(root,legacy.target.directory),{recursive:true});
    fs.copyFileSync(path.join(root,legacy.outputs[0].path),path.join(root,legacy.target.directory,'000.wav'));
    transaction.record('promotion-completed',{transactionId:'owned-preclaim-fixture',runtimeDirectory:legacy.target.directory,runtimeOutputs:[ref(legacy.target.directory+'/000.wav')]});
  });
  const legacyChild=make('legacy-child',{destination:legacy.target.directory+'/child'});
  rejects(()=>promotion.promote(args(legacyChild)),/historical promotion ownership/,'A retained pre-claim completion still excludes nested ownership');
  check(promotion.recover(args(legacy)).alreadyPromoted&&state.status(legacy).promotion,'Exact validated historical ownership can be registered without copying or rewriting old events');
  write(ordinary.target.directory+'/extra.txt','Unrelated bytes');
  check(state.status(ordinary).stale.includes('promoted-directory-changed'),'Unexpected runtime directory contents invalidate current promotion status');
  rejects(()=>promotion.recover(args(ordinary)),/stale/,'Recovery never adopts a modified completed runtime package');

  const foreign=make('foreign');write(foreign.target.directory+'/unrelated.txt','Keep these bytes');
  rejects(()=>promotion.promote(args(foreign)),/already exists/,'Existing unrelated runtime directory blocks promotion');
  check(fs.readFileSync(path.join(root,foreign.target.directory+'/unrelated.txt'),'utf8')==='Keep these bytes','Rejected publication preserves unrelated runtime bytes');
  const staleSource=make('stale-source');write(staleSource.outputs[0].path,'Changed');
  rejects(()=>promotion.promote(args(staleSource)),/stale/,'Changed staged content cannot publish');
  check(!fs.existsSync(path.join(root,staleSource.target.directory)),'Stale content fails before runtime writes');
  const staleAuth=make('stale-auth');write(staleAuth.sourceEvidence.path,{changed:true});
  rejects(()=>promotion.promote(args(staleAuth)),/changed/,'Changed source authorization cannot publish');
  for(const [name,destination] of [['double-slash','assets//audio/canonical'],['absolute',path.join(root,'assets/audio/canonical')],
    ...(process.platform==='win32'?[['backslash','assets\\audio\\canonical']]:[])]){
    const aliasedDestination=make('noncanonical-'+name,{destination});
    rejects(()=>promotion.promote(args(aliasedDestination)),/canonical/,'Equivalent destination spelling is rejected before ownership or runtime writes: '+name);
  }
  const nested=make('nested-license');write(nested.leaf.path,{changed:true});
  rejects(()=>promotion.promote(args(nested)),/changed/,'Domain callback rechecks nested distribution assertion sources');
  check(!fs.existsSync(path.join(root,nested.target.directory)),'Nested policy rejection creates no runtime directory');

  const interrupted=make('interrupted',{count:2}),copy=fs.copyFileSync;let copied=0;
  try{fs.copyFileSync=(...values)=>{if(++copied===2)throw new Error('Owned copy interruption');return copy(...values);};
    rejects(()=>promotion.promote(args(interrupted)),/copy interruption/,'Interrupted private copy is retained as a failed attempt');
  }finally{fs.copyFileSync=copy;}
  check(!fs.existsSync(path.join(root,interrupted.target.directory)),'Partial private staging never becomes partial runtime files');
  check(events(interrupted,'promotion-started').length===1&&events(interrupted,'promotion-failed').length===1,'Failed copy retains intent and truthful failure evidence');
  check(state.status(interrupted).promotionNeedsRecovery&&state.status(interrupted).promotionState==='recovery-required'&&!state.status(interrupted).publicationObserved,'Read-only status exposes interrupted private preparation and required recovery');
  const originalStage=events(interrupted,'promotion-started')[0].data.stagingDirectory;
  check(fs.readdirSync(path.join(root,originalStage)).length===1,'Partial original staging remains available for inspection');
  rejects(()=>promotion.promote(args(interrupted)),/explicit recovery/,'Normal repeat cannot reset an interrupted publication');
  const recovered=promotion.recover(args(interrupted));
  check(recovered.promotion&&recovered.recovered,'Explicit recovery publishes only the original exact owned version');
  check(events(interrupted,'promotion-started').length===2&&fs.existsSync(path.join(root,originalStage)),'Recovery preserves original failed intent and staging ancestry');

  const afterRename=make('after-rename'),rename=fs.renameSync;
  try{fs.renameSync=(from,to)=>{rename(from,to);throw new Error('Owned interruption after atomic publication');};
    rejects(()=>promotion.promote(args(afterRename)),/after atomic/,'Post-rename interruption remains a recoverable recorded failure');
  }finally{fs.renameSync=rename;}
  check(events(afterRename,'promotion-failed')[0].data.published===true,'Failure record reports observed successful publication truthfully');
  check(state.status(afterRename).publicationObserved&&!state.status(afterRename).promotion&&state.status(afterRename).promotionNeedsRecovery,'Read-only status discloses published-but-unreceipted runtime side effects without claiming completed promotion');
  rejects(()=>promotion.promote(args(afterRename)),/explicit recovery/,'Published but unreceipted version requires explicit recovery');
  let recopied=0;
  try{fs.copyFileSync=(...values)=>{recopied++;return copy(...values);};check(promotion.recover(args(afterRename)).recovered,'Recovery recognizes exact already-published directory');}
  finally{fs.copyFileSync=copy;}
  check(recopied===0&&events(afterRename,'promotion-completed').length===1,'Receipt recovery does not copy or overwrite existing files');

  const revoked=make('revoked-after-intent');
  try{fs.copyFileSync=()=>{throw new Error('Owned pause before copying');};assert.throws(()=>promotion.promote(args(revoked)));}finally{fs.copyFileSync=copy;}
  write(revoked.leaf.path,{revoked:true});
  rejects(()=>promotion.recover(args(revoked)),/changed/,'Recovery rechecks nested rights assertions instead of inheriting old intent');
  check(!fs.existsSync(path.join(root,revoked.target.directory)),'Revoked nested rights prevent runtime writes on recovery');
  const foreignRecovery=make('foreign-recovery');
  try{fs.copyFileSync=()=>{throw new Error('Owned private staging failure');};assert.throws(()=>promotion.promote(args(foreignRecovery)));}finally{fs.copyFileSync=copy;}
  write(foreignRecovery.target.directory+'/000.wav','Foreign contents');
  rejects(()=>promotion.recover(args(foreignRecovery)),/bytes differ/,'Owned intent cannot adopt foreign destination bytes');
  check(fs.readFileSync(path.join(root,foreignRecovery.target.directory+'/000.wav'),'utf8')==='Foreign contents','Failed recovery preserves foreign destination');

  const midCopy=make('midcopy-license');let changed=false;
  try{fs.copyFileSync=(...values)=>{copy(...values);if(!changed){changed=true;write(midCopy.leaf.path,{changed:true});}};
    rejects(()=>promotion.promote(args(midCopy)),/changed/,'Domain assertions are rechecked after private preparation before publication');
  }finally{fs.copyFileSync=copy;}
  check(!fs.existsSync(path.join(root,midCopy.target.directory)),'Policy change during preparation leaves no runtime files');

  const sameTarget='assets/audio/shared-target',left=make('left',{destination:sameTarget}),right=make('right',{destination:sameTarget});
  const concurrent=await Promise.all([childPromote(left),childPromote(right)]);
  check(concurrent.filter(x=>x.code===0).length===1&&concurrent.filter(x=>x.code===2).length===1,'Different assets cannot both publish into one target across actual processes');
  const winner=concurrent[0].code===0?left:right;
  check(ref(sameTarget+'/000.wav').sha256===winner.outputs[0].sha256,'Concurrent loser never overwrites winner bytes');
  const same=make('same-version'),simultaneous=await Promise.all([childPromote(same),childPromote(same)]);
  check(simultaneous.some(x=>x.code===0)&&events(same,'promotion-completed').length===1,'Same-version concurrent publication completes once, with exclusive ownership or exact idempotence');
  const nestedParent=make('concurrent-parent',{destination:'assets/audio/concurrent-package'}),nestedChild=make('concurrent-child',{destination:'assets/audio/concurrent-package/child'});
  const nestedRace=await Promise.all([childPromote(nestedParent),childPromote(nestedChild)]);
  check(nestedRace.filter(x=>x.code===0).length===1&&nestedRace.filter(x=>x.code===2).length===1,'Actual concurrent ancestor/descendant reservations have exactly one owner');
  check(state.status(nestedRace[0].code===0?nestedParent:nestedChild).promotion,'Concurrent nested loser cannot stale the winning package');
  const siblings=await Promise.all([childPromote(make('sibling-left')),childPromote(make('sibling-right'))]);
  check(siblings.every(x=>x.code===0),'Distinct sibling packages can publish concurrently through short registry registration');

  const aliased=make('alias-target');fs.mkdirSync(path.join(root,'borrowed'),{recursive:true});
  try{fs.symlinkSync(path.join(root,'borrowed'),path.join(root,'assets','linked'),process.platform==='win32'?'junction':'dir');
    const review=state.load(aliased).events.find(event=>event.kind==='review'&&event.data.kind==='runtime');
    const payload=JSON.parse(fs.readFileSync(path.join(root,review.data.evidence.path),'utf8'));payload.target.directory='assets/linked/new';
    write('inputs/alias-runtime.json',payload);state.recordReview({...aliased,review:'inputs/alias-runtime.json'});
    rejects(()=>promotion.promote(args(aliased)),/symbolic|junction/,'Promotion rejects a linked target ancestor before copying');
  }catch(error){if(error.code!=='EPERM')throw error;observations.push('SKIP: link fixture unavailable on this host');}
  const corrupt=make('corrupt-claim-guard'),badClaim='.hephaera/.cache/media-promotions/claims/'+('f'.repeat(64))+'.json';
  write(badClaim,{schemaVersion:'unrecognized'});
  rejects(()=>promotion.promote(args(corrupt)),/Malformed promotion ownership claim/,'Malformed persisted ownership fails closed before runtime writes');
  const validClaim=JSON.parse(fs.readFileSync(path.join(root,'.hephaera/.cache/media-promotions/claims',crypto.createHash('sha256').update(orphan.target.directory).digest('hex')+'.json'),'utf8'));
  validClaim.state.path='.hephaera/.cache/tasks/missing-owner/media/audio/missing/v1/asset.json';write(badClaim,validClaim);
  rejects(()=>promotion.promote(args(corrupt)),/ENOENT|regular file/,'An unresolvable ownership source cannot be silently discarded');
  check(!fs.existsSync(path.join(root,corrupt.target.directory)),'Invalid ownership registry creates no runtime output');
  const report={assertions:observations.length,observations,root,limits:['Owned fixture byte copying and metadata only','Synthetic review/assertion fixtures are not actual acoustic/rights/user acceptance','No models, generation, external installs or real runtime asset promotion']};
  fs.writeFileSync(path.join(root,'results.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({assertions:observations.length,evidence:path.join(root,'results.json'),limits:report.limits}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
