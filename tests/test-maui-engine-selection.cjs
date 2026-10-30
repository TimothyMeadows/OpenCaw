/* Engine-derived MAUI selection; no workloads, native builds or installs. */
'use strict';
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const engine = require('../commands/lib/engine-contract.cjs');
const root = fs.mkdtempSync(path.join(__dirname, '.maui-engine-'));
let checks = 0;
const eq = (a,b) => { assert.deepEqual(a,b); checks++; };
const throws = (action,re) => { assert.throws(action,re); checks++; };
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function write(dir, file, contents) { const target=path.join(dir,file); fs.mkdirSync(path.dirname(target),{recursive:true}); fs.writeFileSync(target,contents); }
function host(name) { const dir=path.join(root,name); fs.mkdirSync(dir); return dir; }
function snapshot(dir) {
  const entries=[];
  function visit(base) { for(const item of fs.readdirSync(base,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))) { const file=path.join(base,item.name); entries.push([path.relative(dir,file),item.isDirectory()?'directory':sha(file)]); if(item.isDirectory())visit(file); } }
  visit(dir); return entries;
}
const platforms=['WINDOWS','MACOS','ANDROID','IOS'];
function selected(value, web) {
  eq(value.runtimeKind,web?'web':'native');
  eq(value.packaging.profile,web?'MAUI':null);
  eq(value.packaging.selectionSource,'engine');
  eq(value.packaging.platforms,web?platforms:[]);
  eq(value.packaging.nativeReadiness,web?'unverified':'not-applicable');
}
try {
  const data=JSON.parse(fs.readFileSync(path.join(engine.BASE,'.engine/registry.json'),'utf8'));
  eq(Object.hasOwn(data.engines,'MAUI'),false);
  const blank=host('default'), before=snapshot(blank);
  selected(engine.resolve(blank),true);
  eq(engine.resolve(blank).selectionSource,'default');
  eq(snapshot(blank),before);

  for(const id of Object.keys(data.engines)) {
    const dir=host(id), web=['THREEJS','BABYLONJS','PHASERJS'].includes(id);
    eq(data.engines[id].runtimeKind,web?'web':'native');
    selected(engine.generate(dir,id),web);
    fs.appendFileSync(path.join(dir,'ENGINE.md'),'\nRetain custom project instructions.\n');
    const initial=snapshot(dir);
    selected(engine.resolve(dir),web);
    selected(engine.skill(dir,'create-task-file'),web);
    selected(engine.roleCapabilities(dir,'computer-science/project-manager',{}),web);
    eq(snapshot(dir),initial);
    eq(fs.readdirSync(dir),['ENGINE.md']);
    selected(engine.generate(dir,data.engines[id].aliases[0],{inline:true}),web);
    eq(fs.readFileSync(path.join(dir,'ENGINE.md'),'utf8').includes('Retain custom project instructions.'),true);
    selected(engine.resolve(dir),web);
  }

  // Effective override selection controls packaging in both directions. Receipt
  // fields never create a second packaging selector or bypass registry freshness.
  for(const [name,projectEngine,effectiveEngine] of [['web-to-native','THREEJS','UNITY'],['native-to-web','UNITY','PHASERJS'],['web-to-web','THREEJS','BABYLONJS']]) {
    const dir=host(name), task='override-demo';
    engine.generate(dir,projectEngine);
    write(dir,`.opencaw/.cache/tasks/${task}/TASK.md`,'# Isolated packaging test\n');
    const receipt=engine.resolve(dir,{recordOverride:true,override:effectiveEngine,task,scope:'prototypes/package-demo'});
    const web=data.engines[effectiveEngine].runtimeKind==='web';
    selected(receipt,web);
    const receiptFile=path.join(dir,receipt.evidence);
    const stored=JSON.parse(fs.readFileSync(receiptFile,'utf8'));
    stored.packaging={profile:'UNTRUSTED',platforms:['LINUX','TV'],nativeReadiness:'verified'};
    stored.runtimeKind=web?'native':'web';
    fs.writeFileSync(receiptFile,JSON.stringify(stored,null,2)+'\n');
    fs.writeFileSync(receiptFile+'.sha256',sha(receiptFile)+'\n');
    const initial=snapshot(dir);
    const consumed=engine.resolve(dir,{evidence:receipt.evidence,output:'prototypes/package-demo/host/GameHost.csproj'});
    eq(consumed.effectiveEngine,effectiveEngine);
    selected(consumed,web);
    eq(snapshot(dir),initial);
  }

  // Exercise real installed paths and malformed metadata in a private baseline
  // copy, never by mutating the shared registry while other checks are running.
  const installed=host('installed'), baseline=path.join(installed,'.opencaw');
  fs.mkdirSync(path.join(baseline,'commands/lib'),{recursive:true});
  fs.copyFileSync(path.join(engine.BASE,'commands/lib/engine-contract.cjs'),path.join(baseline,'commands/lib/engine-contract.cjs'));
  fs.cpSync(path.join(engine.BASE,'.engine'),path.join(baseline,'.engine'),{recursive:true});
  const local=require(path.join(baseline,'commands/lib/engine-contract.cjs'));
  selected(local.generate(installed,'phaser'),true);
  eq(fs.readFileSync(path.join(installed,'ENGINE.md'),'utf8').includes('Read `./.opencaw/.engine/PHASERJS.md` instructions'),true);
  selected(local.resolve(installed),true);
  const registry=path.join(baseline,'.engine/registry.json');
  const mutated=JSON.parse(fs.readFileSync(registry,'utf8'));
  delete mutated.engines.PHASERJS.runtimeKind;
  fs.writeFileSync(registry,JSON.stringify(mutated));
  throws(()=>local.resolve(installed),/runtimeKind/);
  const originalContract=fs.readFileSync(path.join(installed,'ENGINE.md'),'utf8');
  throws(()=>local.generate(installed,'PHASERJS'),/runtimeKind/);
  eq(fs.readFileSync(path.join(installed,'ENGINE.md'),'utf8'),originalContract);
  const unconfigured=host('malformed-generation');
  throws(()=>local.generate(unconfigured,'PHASERJS'),/runtimeKind/);
  eq(fs.readdirSync(unconfigured),[]);
  mutated.engines.PHASERJS.runtimeKind='browser-ish';
  fs.writeFileSync(registry,JSON.stringify(mutated));
  throws(()=>local.resolve(installed),/runtimeKind/);
  mutated.engines.PHASERJS.runtimeKind='web';
  fs.writeFileSync(registry,JSON.stringify(mutated));
  selected(local.resolve(installed),true);
  throws(()=>local.packagingSelection('MAUI'),/runtimeKind/);
  console.log(`MAUI engine selection: ${checks} checks passed (offline; native readiness remains unverified).`);
} finally { fs.rmSync(root,{recursive:true,force:true}); }
