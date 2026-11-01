'use strict';

// Explicit host asset copying only. Never synthesis, normalization or inference.
// Locks are cooperative ownership guards, not a hostile-filesystem sandbox.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const runtime=require('./bubo-runtime.cjs'),lifecycle=require('./media-pipeline-state.cjs');
const transition=require('./state-transition.cjs');
const fail=message=>{throw new Error(message);};
const canonical=value=>JSON.stringify(runtime.canonical(value));
const same=(left,right,message)=>{if(canonical(left)!==canonical(right))fail(message);};
const relative=(root,file)=>path.relative(root,file).split(path.sep).join('/');
const latest=(state,kind)=>[...state.events].reverse().find(event=>event.kind===kind);
function filesFor(plan) {
  return plan.outputs.map((source,index)=>({source,
    destination:plan.target.directory+'/'+String(index).padStart(3,'0')+path.posix.extname(source.path).toLowerCase()}));
}
function ownedDirectory(root,plan) {
  const directory=runtime.projectPath(root,plan.target.directory),files=filesFor(plan);
  if(!fs.existsSync(directory)||!fs.statSync(directory).isDirectory())fail('Owned promoted directory is missing.');
  const names=fs.readdirSync(directory).sort(),expected=files.map(file=>path.posix.basename(file.destination)).sort();
  same(names,expected,'Runtime destination is foreign, incomplete or contains unrelated files; nothing was overwritten.');
  return files.map(file=>{
    const ref=lifecycle.identity(root,file.destination);
    if(ref.sha256!==file.source.sha256)fail('Runtime destination bytes differ from this exact authorized version; nothing was overwritten.');
    return ref;
  });
}
function targetLock(root,plan,action) {
  const canonicalTarget=relative(root,runtime.projectPath(root,plan.target.directory));
  const key=process.platform==='win32'?canonicalTarget.toLowerCase():canonicalTarget;
  const digest=crypto.createHash('sha256').update(key).digest('hex');
  const file=runtime.projectPath(root,'.hephaera/.cache/media-promotions/locks/'+digest+'.json');
  fs.mkdirSync(path.dirname(file),{recursive:true});runtime.components(file);
  let fd;
  try{fd=fs.openSync(file,'wx');}catch(error){if(error.code==='EEXIST')fail('Runtime destination already has an owner. Inspect the recorded lock; stale ownership is never discarded automatically.');throw error;}
  try{
    fs.writeFileSync(fd,JSON.stringify({schemaVersion:'hephaera-promotion-lock/v1',pid:process.pid,assetSha256:plan.assetSha256,
      target:plan.target.directory,createdAt:new Date().toISOString()})+'\n');fs.fsyncSync(fd);
    return action();
  }finally{fs.closeSync(fd);fs.unlinkSync(file);}
}
function claimKey(root,directory) {
  const resolved=relative(root,runtime.projectPath(root,directory));
  const key=process.platform==='win32'?resolved.toLowerCase():resolved;
  if(resolved!==directory||!key.startsWith('assets/'))fail('Promotion ownership target must be canonical.');
  return key;
}
function claimOwner(state,plan) {
  return {schemaVersion:'hephaera-media-target-claim/v1',state:state.identity,assetSha256:plan.assetSha256,
    target:plan.target,authorization:plan.authorization,sourceEvidence:plan.sourceEvidence};
}
function overlapping(left,right){return left===right||left.startsWith(right+'/')||right.startsWith(left+'/');}
function registerTarget(state,plan) {
  const {root}=state,key=claimKey(root,plan.target.directory),owner=claimOwner(state,plan);
  const directory=runtime.projectPath(root,'.hephaera/.cache/media-promotions/claims');
  fs.mkdirSync(directory,{recursive:true});runtime.components(directory);
  const lock=runtime.projectPath(root,'.hephaera/.cache/media-promotions/.ownership-lock');let fd;
  for(let attempt=0;attempt<101;attempt++){
    try{fd=fs.openSync(lock,'wx');break;}catch(error){
      if(error.code!=='EEXIST')throw error;
      if(attempt===100)fail('Promotion ownership registry is busy; inspect its retained lock before retry.');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,10);
    }
  }
  try{
    fs.writeFileSync(fd,JSON.stringify({pid:process.pid,state:state.stateFile,createdAt:new Date().toISOString()})+'\n');fs.fsyncSync(fd);
    const entries=fs.readdirSync(directory).sort();if(entries.length>16384)fail('Promotion ownership registry exceeds its bound.');
    const known=new Set();let exact=false;
    for(const name of entries){
      if(!/^[a-f0-9]{64}\.json$/.test(name))fail('Unexpected promotion ownership claim; reconcile retained state.');
      const file=runtime.projectPath(root,relative(root,directory)+'/'+name),stat=fs.statSync(file);
      if(!stat.isFile()||stat.size>1048576)fail('Invalid promotion ownership claim.');
      const claim=JSON.parse(fs.readFileSync(file,'utf8'));
      if(!claim||Object.keys(claim).sort().join(',')!=='assetSha256,authorization,schemaVersion,sourceEvidence,state,target'||claim.schemaVersion!=='hephaera-media-target-claim/v1'||!/^[a-f0-9]{64}$/.test(claim.assetSha256||''))fail('Malformed promotion ownership claim.');
      lifecycle.identity(root,claim.state);
      const prior=lifecycle.load({root,stateFile:claim.state.path}),priorKey=claimKey(root,claim.target?.directory);
      if(name!==crypto.createHash('sha256').update(priorKey).digest('hex')+'.json')fail('Promotion ownership claim key differs from its target.');
      for(const ref of [claim.authorization,claim.sourceEvidence])if(!ref||typeof ref.path!=='string'||!/^[a-f0-9]{64}$/.test(ref.sha256||'')||relative(root,runtime.projectPath(root,ref.path))!==ref.path)fail('Malformed ownership source identity.');
      const intent=latest(prior,'promotion-started')||latest(prior,'promotion-completed');
      if(intent)same(claim,claimOwner(prior,intent.data),'Retained ownership claim differs from its promotion intent.');
      known.add(prior.stateFile);
      if(overlapping(key,priorKey)){
        same(claim,owner,'Runtime target overlaps another reserved/owned asset package; nothing was changed.');exact=true;
      }
    }
    // Pre-claim revisions may have retained intents/completions. They continue
    // to own their packages even if their content/policy is now stale. Inspect
    // only canonical lifecycle records, never media or private reference bytes.
    const tasks=runtime.projectPath(root,'.hephaera/.cache/tasks');let visited=0;
    const children=folder=>{
      runtime.components(folder);const names=fs.readdirSync(folder);if((visited+=names.length)>65536)fail('Historical promotion ownership scan exceeds its bound.');
      return names.map(name=>path.join(folder,name)).filter(file=>{runtime.components(file);return fs.statSync(file).isDirectory();});
    };
    for(const task of children(tasks))for(const domain of ['audio','music','voice']){
      const media=path.join(task,'media',domain);runtime.components(media);if(!fs.existsSync(media))continue;
      for(const asset of children(media))for(const version of children(asset)){
        const file=path.join(version,'asset.json');runtime.components(file);if(!fs.existsSync(file))continue;
        const name=relative(root,file);if(known.has(name))continue;
        const prior=lifecycle.load({root,stateFile:name}),intent=latest(prior,'promotion-started')||latest(prior,'promotion-completed');if(!intent)continue;
        if(overlapping(key,claimKey(root,intent.data.target?.directory)))same(claimOwner(prior,intent.data),owner,'Runtime target overlaps retained historical promotion ownership; explicit reconciliation is required.');
      }
    }
    if(!exact){
      const file=path.join(directory,crypto.createHash('sha256').update(key).digest('hex')+'.json'),claimFd=fs.openSync(file,'wx');
      try{fs.writeFileSync(claimFd,JSON.stringify(owner,null,2)+'\n');fs.fsyncSync(claimFd);}finally{fs.closeSync(claimFd);}
    }
  }finally{fs.closeSync(fd);fs.unlinkSync(lock);}
}
function verifyOwner(event,plan) {
  if(event.data.assetSha256!==plan.assetSha256)fail('Promotion intent names a different asset version.');
  same(event.data.authorization,plan.authorization,'Promotion intent used a different authorization; retain it for review.');
  same(event.data.sourceEvidence,plan.sourceEvidence,'Promotion intent used different source authorization evidence.');
  same(event.data.target,plan.target,'Promotion intent names a different target.');
  same(event.data.outputs,plan.outputs,'Promotion intent names different source outputs.');
}
function validatePolicy(options,plan) {
  const result=options.validate({root:options.root,stateFile:options.stateFile,plan});
  if(result===false || (result&&typeof result.then==='function'))fail('Promotion requires synchronous current domain policy validation.');
}
function execute(options,recovering) {
  if(!options||typeof options.validate!=='function')fail('Explicit current domain validation callback is required for promotion.');
  if(Object.keys(options).some(key=>!['root','stateFile','authorization','validate'].includes(key)))fail('Unknown or protected promotion option.');
  transition.assertProductionAllowed(options.root, recovering ? 'media promotion recovery' : 'media promotion');
  return lifecycle.promotionTransaction(options,transaction=>{
    const {state,plan}=transaction,{root}=state;
    validatePolicy({...options,root},plan);
    return targetLock(root,plan,()=>{
      registerTarget(state,plan);
      const completed=latest(state,'promotion-completed'),started=latest(state,'promotion-started');
      if(completed){
        verifyOwner(completed,plan);const runtimeOutputs=ownedDirectory(root,plan);
        return {schemaVersion:'hephaera-media-promotion-result/v1',promotion:true,alreadyPromoted:true,
          recovered:false,assetSha256:plan.assetSha256,runtimeOutputs,authorization:plan.authorization,sourceEvidence:plan.sourceEvidence};
      }
      if(started){
        verifyOwner(started,plan);
        if(!recovering)fail('This version already has a promotion intent. Use explicit recovery; history cannot be reset.');
      }else if(recovering)fail('No owned promotion intent exists to recover.');
      const destination=runtime.projectPath(root,plan.target.directory);
      if(fs.existsSync(destination)){
        if(!started)fail('Runtime destination already exists without this version\'s intent.');
        const runtimeOutputs=ownedDirectory(root,plan);
        validatePolicy({...options,root},transaction.revalidate());
        transaction.record('promotion-completed',{transactionId:started.data.transactionId,runtimeDirectory:plan.target.directory,
          runtimeOutputs,recovered:true,recoveryReason:'Owned exact directory was published before completion receipt.'});
        return {schemaVersion:'hephaera-media-promotion-result/v1',promotion:true,alreadyPromoted:false,recovered:true,
          assetSha256:plan.assetSha256,runtimeOutputs,authorization:plan.authorization,sourceEvidence:plan.sourceEvidence};
      }
      const transactionId=crypto.randomUUID(),stageRelative=state.directory+'/promotion-staging/'+transactionId;
      const stage=runtime.projectPath(root,stageRelative);
      transaction.record('promotion-started',{transactionId,stagingDirectory:stageRelative,
        recovering: Boolean(started),previousTransaction:started?.data.transactionId||null});
      let published=false;
      try{
        fs.mkdirSync(path.dirname(stage),{recursive:true});runtime.components(stage);fs.mkdirSync(stage);
        for(const file of filesFor(plan)){
          const source=runtime.projectPath(root,file.source.path),name=path.posix.basename(file.destination);
          lifecycle.identity(root,file.source);
          const staged=runtime.projectPath(root,stageRelative+'/'+name);
          fs.copyFileSync(source,staged,fs.constants.COPYFILE_EXCL);
          if(lifecycle.identity(root,relative(root,staged)).sha256!==file.source.sha256)fail('Staged promotion copy differs from its authorized source.');
        }
        const current=transaction.revalidate();validatePolicy({...options,root},current);
        // Every source/assertion/policy has been checked before runtime writes.
        // All media are prepared privately; the directory publication is one rename.
        runtime.components(destination);fs.mkdirSync(path.dirname(destination),{recursive:true});runtime.components(destination);
        if(fs.existsSync(destination))fail('Runtime destination appeared during preparation; nothing was overwritten.');
        fs.renameSync(stage,destination);published=true;
        const runtimeOutputs=ownedDirectory(root,plan);
        transaction.record('promotion-completed',{transactionId,runtimeDirectory:plan.target.directory,runtimeOutputs,recovered:Boolean(started)});
        return {schemaVersion:'hephaera-media-promotion-result/v1',promotion:true,alreadyPromoted:false,recovered:Boolean(started),
          assetSha256:plan.assetSha256,runtimeOutputs,authorization:plan.authorization,sourceEvidence:plan.sourceEvidence};
      }catch(error){
        if(!published && fs.existsSync(destination)) {
          try{ownedDirectory(root,plan);published=true;}catch{/* Foreign/partial directory is never adopted or overwritten. */}
        }
        try{transaction.record('promotion-failed',{transactionId,published,
          reason:published?'Runtime directory was published; recover exact ownership before any further write.':'Promotion preparation/publication failed; retained staging and intent require explicit recovery.'});}catch{/* Started intent remains authoritative even if receipt persistence failed. */}
        throw error;
      }
    });
  });
}
module.exports={promote:options=>execute(options,false),recover:options=>execute(options,true),filesFor};
