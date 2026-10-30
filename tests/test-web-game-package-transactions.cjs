/* Durable init/sync rollback and confinement; injected failures, no native tools. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const {EventEmitter} = require('node:events');
const crypto = require('node:crypto');
const engines = require('../commands/lib/engine-contract.cjs');
const packaging = require('../commands/lib/web-game-package.cjs');
const base=path.resolve(__dirname,'..');
const area=path.join(base,'.opencaw/.cache/tasks/opencaw-maui-web-packaging');
fs.mkdirSync(area,{recursive:true});
const fixtures=fs.mkdtempSync(path.join(area,'transaction-fixtures-'));
const original={renameSync:fs.renameSync,writeFileSync:fs.writeFileSync,unlinkSync:fs.unlinkSync,spawn:cp.spawn,spawnSync:cp.spawnSync,platform:Object.getOwnPropertyDescriptor(process,'platform')};
let checks=0;
const eq=(a,b)=>{assert.deepEqual(a,b);checks++;};
const ok=a=>{assert.ok(a);checks++;};
const throws=(action,re)=>{assert.throws(action,re);checks++;};
const rejects=async(action,re)=>{await assert.rejects(action,re);checks++;};
const bytes=file=>fs.existsSync(file)?fs.readFileSync(file):null;
function write(dir,file,text){const target=path.join(dir,file);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,text);}
function host(name){const dir=path.join(fixtures,name);fs.mkdirSync(dir);engines.generate(dir,'THREEJS');return dir;}
const config={appId:'com.example.game',title:'Transaction Game',webRoot:'dist',output:'platforms/maui'};
function init(name){const dir=host(name);packaging.init(dir,config);return dir;}
async function ready(name){const dir=init(name);write(dir,'dist/index.html','<!doctype html><p>original</p>');write(dir,'dist/game.js','original-game');await packaging.sync(dir,{});return dir;}
function nativeState(dir){const host=path.join(dir,'platforms/maui');return {props:bytes(path.join(host,'OpenCawGame.props')),snapshot:bytes(path.join(host,'.opencaw-web-snapshot.json')),assets:packaging.tree(path.join(host,'Resources/Raw/wwwroot'))};}
function configChange(dir){const file=path.join(dir,'web-game-package.json');const data=JSON.parse(fs.readFileSync(file,'utf8'));data.buildNumber++;fs.writeFileSync(file,JSON.stringify(data,null,2)+'\n');write(dir,'dist/game.js','updated-game');}
function state(dir){return packaging.context(dir).state;}
function restore(){fs.renameSync=original.renameSync;fs.writeFileSync=original.writeFileSync;fs.unlinkSync=original.unlinkSync;cp.spawn=original.spawn;cp.spawnSync=original.spawnSync;Object.defineProperty(process,'platform',original.platform);}
function injectRename(predicate){let hit=false;fs.renameSync=(from,to)=>{if(!hit&&predicate(String(from),String(to))){hit=true;const e=new Error('injected publication failure');e.code='EIO';throw e;}return original.renameSync(from,to);};return()=>eq(hit,true);}
function filesNamed(dir,name){const found=[];function visit(current){for(const entry of fs.readdirSync(current,{withFileTypes:true})){const file=path.join(current,entry.name);if(entry.isDirectory())visit(file);else if(entry.name===name)found.push(file);}}visit(dir);return found;}
(async()=>{
  // Parent types are checked before any project/cache staging.
  for(const [name,file,opt] of [['config-parent','settings',{...config,config:'settings/package.json'}],['host-parent','platforms',config],['web-root','dist',config]]){
    const dir=host(name);write(dir,file,'foreign bytes');const before=fs.readdirSync(dir).sort();
    throws(()=>packaging.init(dir,opt),/parent type|directory|file/i);
    eq(fs.readdirSync(dir).sort(),before);eq(fs.readFileSync(path.join(dir,file),'utf8'),'foreign bytes');
  }
  const nested=init('nested');
  throws(()=>packaging.init(nested,{...config,config:'other.json',output:'platforms/maui/child',webRoot:'other-dist'}),/nest|owned/i);
  eq(fs.existsSync(path.join(nested,'platforms/maui/child')),false);
  eq(fs.existsSync(path.join(nested,'other.json')),false);

  // Initialization stages all source first and rolls back final host publication
  // if the second publication fails. Failed owned bytes and journals are retained.
  const initFailure=host('init-publication-failure');
  const assertInitHit=injectRename((from,to)=>to===path.join(initFailure,'web-game-package.json'));
  try{throws(()=>packaging.init(initFailure,config),/injected/);}finally{restore();assertInitHit();}
  eq(fs.existsSync(path.join(initFailure,'platforms/maui')),false);
  eq(fs.existsSync(path.join(initFailure,'web-game-package.json')),false);
  const initCache=path.join(initFailure,'.opencaw/.cache/packaging');
  eq(filesNamed(initCache,'pending-transaction.json').length,0);
  eq(filesNamed(initCache,'transaction-result.json').map(f=>JSON.parse(fs.readFileSync(f,'utf8')).status),['rolled-back']);
  packaging.init(initFailure,config);ok(fs.existsSync(path.join(initFailure,'platforms/maui/GameHost.csproj')));

  const copyFailure=host('init-staging-failure');let failedCopy=false;
  fs.writeFileSync=(file,...args)=>{if(!failedCopy&&String(file).includes(`${path.sep}initializations${path.sep}`)&&String(file).endsWith(`${path.sep}GamePage.cs`)){failedCopy=true;throw new Error('injected staging failure');}return original.writeFileSync(file,...args);};
  try{throws(()=>packaging.init(copyFailure,config),/injected/);}finally{restore();}
  eq(failedCopy,true);eq(fs.existsSync(path.join(copyFailure,'platforms/maui')),false);eq(fs.existsSync(path.join(copyFailure,'web-game-package.json')),false);
  packaging.init(copyFailure,config);ok(fs.existsSync(path.join(copyFailure,'web-game-package.json')));

  // A foreign directory appearing while template staging runs is never accepted
  // as an init backup and overwritten.
  const raced=host('init-foreign-race');let addedForeign=false;
  fs.writeFileSync=(file,...args)=>{
    const result=original.writeFileSync(file,...args);
    if(!addedForeign&&String(file).includes(`${path.sep}initializations${path.sep}`)&&String(file).endsWith(`${path.sep}config.json`)){
      addedForeign=true;write(raced,'platforms/maui/foreign.txt','preserve concurrent foreign content');
    }
    return result;
  };
  try{throws(()=>packaging.init(raced,config),/already exist/i);}finally{restore();}
  eq(fs.readFileSync(path.join(raced,'platforms/maui/foreign.txt'),'utf8'),'preserve concurrent foreign content');
  eq(fs.existsSync(path.join(raced,'web-game-package.json')),false);

  // Complete source validation precedes generated property changes.
  const preflight=await ready('sync-preflight');const old=nativeState(preflight);configChange(preflight);
  const unrelated=path.join(preflight,'foreign');fs.mkdirSync(unrelated);write(unrelated,'preserve.txt','keep');
  fs.symlinkSync(unrelated,path.join(preflight,'dist/linked'),process.platform==='win32'?'junction':'dir');
  await rejects(()=>packaging.sync(preflight,{}),/link|junction/i);eq(nativeState(preflight),old);eq(fs.readFileSync(path.join(unrelated,'preserve.txt'),'utf8'),'keep');

  // Each final-path rename can fail after prior publication: rollback restores
  // exact prior props/assets/snapshot and retry can complete without deleting data.
  for(const role of ['props','wwwroot','snapshot']){
    const dir=await ready('sync-failure-'+role), prior=nativeState(dir), ownedState=state(dir);configChange(dir);
    const suffix={props:'OpenCawGame.props',wwwroot:'wwwroot',snapshot:'.opencaw-web-snapshot.json'}[role];
    const assertHit=injectRename((from,to)=>to===path.join(dir,'platforms/maui',role==='wwwroot'?'Resources/Raw/wwwroot':suffix));
    try{await rejects(()=>packaging.sync(dir,{}),/injected/);}finally{restore();assertHit();}
    eq(nativeState(dir),prior);eq(fs.existsSync(path.join(ownedState,'pending-transaction.json')),false);
    ok(filesNamed(ownedState,'transaction-result.json').some(f=>JSON.parse(fs.readFileSync(f,'utf8')).status==='rolled-back'));
    await packaging.sync(dir,{});eq(packaging.verifySnapshot(packaging.context(dir)).identity.webFiles.length,2);
    eq(fs.readFileSync(path.join(dir,'platforms/maui/Resources/Raw/wwwroot/game.js'),'utf8'),'updated-game');
  }

  // An error recording commit also restores prior bytes; no false success remains.
  const recordFailure=await ready('sync-record-failure'), recordPrior=nativeState(recordFailure);configChange(recordFailure);let failedRecord=false;
  fs.writeFileSync=(file,...args)=>{if(!failedRecord&&String(file).endsWith('transaction-result.json')){failedRecord=true;throw new Error('injected result failure');}return original.writeFileSync(file,...args);};
  try{await rejects(()=>packaging.sync(recordFailure,{}),/injected/);}finally{restore();}
  eq(failedRecord,true);eq(nativeState(recordFailure),recordPrior);await packaging.sync(recordFailure,{});

  // A failed rollback preserves write-ahead state and blocks all new execution.
  // Explicit recovery restores only exact hash-owned bytes and supports retry.
  const interrupted=await ready('interrupted'), interruptedPrior=nativeState(interrupted), interruptedState=state(interrupted);configChange(interrupted);
  let publicationFailed=false,rollbackFailed=false;
  fs.renameSync=(from,to)=>{
    if(!publicationFailed&&String(to)===path.join(interrupted,'platforms/maui/.opencaw-web-snapshot.json')){publicationFailed=true;throw new Error('injected interruption');}
    if(publicationFailed&&!rollbackFailed&&String(from)===path.join(interrupted,'platforms/maui/Resources/Raw/wwwroot')){rollbackFailed=true;throw new Error('injected rollback interruption');}
    return original.renameSync(from,to);
  };
  try{await rejects(()=>packaging.sync(interrupted,{}),/injected/);}finally{restore();}
  eq(publicationFailed,true);eq(rollbackFailed,true);ok(fs.existsSync(path.join(interruptedState,'pending-transaction.json')));
  throws(()=>packaging.context(interrupted),/pending.*recover/i);
  await rejects(()=>packaging.sync(interrupted,{}),/pending.*recover/i);
  const pointer=JSON.parse(fs.readFileSync(path.join(interruptedState,'pending-transaction.json'),'utf8'));
  const journalFile=path.join(interrupted,pointer.journal), journalBytes=fs.readFileSync(journalFile);
  fs.appendFileSync(journalFile,'\n');await rejects(()=>packaging.recover(interrupted,{}),/journal changed/i);fs.writeFileSync(journalFile,journalBytes);
  const recovered=await packaging.recover(interrupted,{});eq(recovered.status,'rolled-back');eq(nativeState(interrupted),interruptedPrior);
  eq(fs.existsSync(path.join(interruptedState,'pending-transaction.json')),false);await packaging.sync(interrupted,{});

  // A crash after committed-result publication is reconciled, never rolled back
  // or reported as a new native build.
  const committed=await ready('committed-pending');configChange(committed);let failedClear=false;
  fs.unlinkSync=file=>{if(!failedClear&&String(file).endsWith('pending-transaction.json')){failedClear=true;throw new Error('injected pending clear failure');}return original.unlinkSync(file);};
  try{await rejects(()=>packaging.sync(committed,{}),/injected/);}finally{restore();}
  eq(failedClear,true);throws(()=>packaging.parse(['recover','--engine-evidence','receipt.json']),/not supported/i);
  await rejects(()=>packaging.recover(committed,{engineEvidence:'receipt.json'}),/does not accept/i);
  const commitRecovery=await packaging.recover(committed,{});eq(commitRecovery.status,'committed');eq(commitRecovery.compiled,false);
  ok(packaging.verifySnapshot(packaging.context(committed)));

  // Excluding compiler-generated content never exempts output directories from
  // link/type checks, including nested obj links.
  for(const kind of ['bin-link','obj-nested-link','obj-file']){
    const dir=await ready(kind), foreign=path.join(dir,'foreign');fs.mkdirSync(foreign);write(foreign,'untouched','keep');
    const native=path.join(dir,'platforms/maui');
    if(kind==='bin-link')fs.symlinkSync(foreign,path.join(native,'bin'),process.platform==='win32'?'junction':'dir');
    else if(kind==='obj-nested-link'){fs.mkdirSync(path.join(native,'obj'));fs.symlinkSync(foreign,path.join(native,'obj/linked'),process.platform==='win32'?'junction':'dir');}
    else write(native,'obj','foreign intermediate file');
    throws(()=>packaging.verifySnapshot(packaging.context(dir)),/link|junction|parent type/i);
    eq(fs.readFileSync(path.join(foreign,'untouched'),'utf8'),'keep');
  }
  // Artifact identity is the actual GameHost entry, not any helper executable
  // or an arbitrary file beneath a directory whose name ends in .app.
  const artifacts=await ready('artifact-identities');
  cp.spawnSync=(command,args)=>({status:0,stdout:args[0]==='--version'?'10.0.400\n':'maui-windows 10.0.20/10.0.100 fixture\n'});
  try {
    const msixPlan=packaging.plan(artifacts,{target:'WINDOWS',format:'msix'});
    ok(msixPlan.args.includes('-p:WindowsPackageType=MSIX'));
    eq(msixPlan.args.includes('-p:WindowsPackageType=Package'),false);
  } finally { restore(); }
  for(const [target,artifact,accepted,change] of [['WINDOWS','helper.exe',false],['WINDOWS','GameHost.exe',true],['MACOS','GameHost.app/Contents/Info.plist',false],['MACOS','GameHost.app/Contents/MacOS/GameHost',true],['WINDOWS','GameHost.exe',false,'engine']]){
    Object.defineProperty(process,'platform',{...original.platform,value:target==='WINDOWS'?'win32':'darwin'});
    cp.spawnSync=(command,args)=>({status:0,stdout:args[0]==='--version'?'10.0.400\n':'maui-windows 10.0.20/10.0.100 VS\nmaccatalyst 26.5.10301/10.0.100 VS\n'});
    cp.spawn=(command,args,options)=>{const child=new EventEmitter();child.pid=91919191;process.nextTick(()=>{
      const output=args[args.indexOf('-o')+1];write(output,artifact,'actual-entry-fixture');
      write(artifacts,'platforms/maui/obj/project.assets.json','{"version":3,"targets":{}}');
      if(change==='engine')fs.appendFileSync(path.join(artifacts,'ENGINE.md'),'\nChanged during native compilation.\n');
      child.emit('exit',0);
    });return child;};
    try{
      const action=()=>packaging.execute(artifacts,{operation:'package',target,format:target==='WINDOWS'?'folder':'app'});
      if(!accepted)await rejects(action,change==='engine'?/inputs changed/i:/artifact/i);
      else {
        const receipt=await action();eq(receipt.prerequisites.sdkVersion,'10.0.400');
        eq(receipt.prerequisites.installedWorkloads,[target==='WINDOWS'?{id:'maui-windows',manifestVersion:'10.0.20/10.0.100'}:{id:'maccatalyst',manifestVersion:'26.5.10301/10.0.100'}]);
        const actual=path.join(artifacts,'platforms/maui/obj/project.assets.json');
        eq(receipt.resolvedDependencies.sha256,crypto.createHash('sha256').update(fs.readFileSync(actual)).digest('hex'));
        eq(receipt.orchestratorSha256,crypto.createHash('sha256').update(fs.readFileSync(path.join(base,'commands/lib/web-game-package.cjs'))).digest('hex'));
      }
    }finally{restore();}
  }
  console.log(`Web-game packaging transactions: ${checks} checks passed (injected offline failures; no native/device/store acceptance).`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>{
  restore();const actual=fs.realpathSync(fixtures),allowed=fs.realpathSync(area);assert.ok(allowed.startsWith(fs.realpathSync(base)+path.sep));assert.ok(actual.startsWith(allowed+path.sep));fs.rmSync(actual,{recursive:true,force:true});
});
