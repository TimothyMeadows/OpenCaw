'use strict';

// Explicit host asset copying only. Never synthesis, normalization or inference.
// Locks are cooperative ownership guards, not a hostile-filesystem sandbox.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const runtime=require('./bubo-runtime.cjs'),lifecycle=require('./media-pipeline-state.cjs');
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
  const file=runtime.projectPath(root,'.opencaw/.cache/media-promotions/locks/'+digest+'.json');
  fs.mkdirSync(path.dirname(file),{recursive:true});runtime.components(file);
  let fd;
  try{fd=fs.openSync(file,'wx');}catch(error){if(error.code==='EEXIST')fail('Runtime destination already has an owner. Inspect the recorded lock; stale ownership is never discarded automatically.');throw error;}
  try{
    fs.writeFileSync(fd,JSON.stringify({schemaVersion:'opencaw-promotion-lock/v1',pid:process.pid,assetSha256:plan.assetSha256,
      target:plan.target.directory,createdAt:new Date().toISOString()})+'\n');fs.fsyncSync(fd);
    return action();
  }finally{fs.closeSync(fd);fs.unlinkSync(file);}
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
  return lifecycle.promotionTransaction(options,transaction=>{
    const {state,plan}=transaction,{root}=state;
    validatePolicy({...options,root},plan);
    return targetLock(root,plan,()=>{
      const completed=latest(state,'promotion-completed'),started=latest(state,'promotion-started');
      if(completed){
        verifyOwner(completed,plan);const runtimeOutputs=ownedDirectory(root,plan);
        return {schemaVersion:'opencaw-media-promotion-result/v1',promotion:true,alreadyPromoted:true,
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
        return {schemaVersion:'opencaw-media-promotion-result/v1',promotion:true,alreadyPromoted:false,recovered:true,
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
        return {schemaVersion:'opencaw-media-promotion-result/v1',promotion:true,alreadyPromoted:false,recovered:Boolean(started),
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
