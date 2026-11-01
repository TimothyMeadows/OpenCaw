/* Declarative postprocessing routing only; no package installation or GPU claims. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const engine = require('../commands/lib/engine-contract.cjs');
const parent = path.join(engine.BASE, '.hephaera/.cache/tasks/hephaera-threejs-postprocessing');
fs.mkdirSync(parent, {recursive:true});
const root = fs.mkdtempSync(path.join(parent, 'engine-fixtures-'));
const registry = JSON.parse(fs.readFileSync(path.join(engine.BASE, '.engine/registry.json'), 'utf8'));
let checks = 0;
const eq = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const throws = (action, pattern) => { assert.throws(action, pattern); checks++; };
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const expected = {
  backend: 'PMNDRS_POSTPROCESSING', package: 'postprocessing', skill: 'threejs-build-postprocessing',
  selectionSource: 'engine', renderer: 'WebGLRenderer', context: 'webgl2',
  testedVersion: '6.39.5', testedThreeVersion: '0.182.0', profile: 'ldr', readiness: 'unverified'
};
function write(dir, file, text) { const target=path.join(dir,file); fs.mkdirSync(path.dirname(target),{recursive:true}); fs.writeFileSync(target,text); }
function host(name) { const dir=path.join(root,name); fs.mkdirSync(dir); return dir; }
function snapshot(dir) {
  const entries=[];
  function visit(base) { for(const item of fs.readdirSync(base,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))) { const file=path.join(base,item.name); entries.push([path.relative(dir,file),item.isDirectory()?'directory':sha(file)]); if(item.isDirectory())visit(file); } }
  visit(dir); return entries;
}
function selected(value, id) {
  eq(value.postprocessing, id==='THREEJS' ? expected : null);
  eq(value.packaging.profile, registry.engines[id].runtimeKind==='web' ? 'MAUI' : null);
  eq(value.packaging.platforms, registry.engines[id].runtimeKind==='web' ? ['WINDOWS','MACOS','ANDROID','IOS'] : []);
}
try {
  const blank=host('default'), initial=snapshot(blank);
  selected(engine.resolve(blank),'THREEJS');
  eq(engine.resolve(blank).selectionSource,'default');
  eq(snapshot(blank),initial);
  eq(fs.existsSync(path.join(blank,'package.json')),false);
  eq(fs.existsSync(path.join(blank,'node_modules')),false);
  eq(registry.engines.THREEJS.skills.includes('threejs-build-postprocessing'),true);
  eq(engine.classify('threejs-build-postprocessing'),'THREEJS');

  for(const [id,definition] of Object.entries(registry.engines)) {
    const dir=host(id);
    eq(definition.postprocessingBackend,id==='THREEJS'?'PMNDRS_POSTPROCESSING':null);
    selected(engine.generate(dir,id),id);
    fs.appendFileSync(path.join(dir,'ENGINE.md'),'\nKeep custom engine guidance.\n');
    for(const alias of [id,...definition.aliases]) selected(engine.generate(dir,alias),id);
    const before=snapshot(dir);
    selected(engine.resolve(dir),id);
    const skill=engine.skill(dir,'threejs-build-postprocessing');
    selected(skill,id); eq(skill.compatible,id==='THREEJS');
    if(id!=='THREEJS') eq(/requires THREEJS/.test(skill.exclusionReason),true);
    selected(engine.roleCapabilities(dir,'computer-science/project-manager',{}),id);
    eq(snapshot(dir),before);
    eq(fs.readdirSync(dir),['ENGINE.md']);
    selected(engine.generate(dir,id,{inline:true}),id);
    selected(engine.resolve(dir),id);
    eq(fs.readFileSync(path.join(dir,'ENGINE.md'),'utf8').includes('Keep custom engine guidance.'),true);
  }

  // The effective engine owns this capability. Extra receipt fields are not a
  // postprocessing selector, renderer override or readiness attestation.
  for(const [name,project,effective] of [
    ['native-to-three','UNITY','THREEJS'], ['three-to-native','THREEJS','UNITY'],
    ['three-to-babylon','THREEJS','BABYLONJS'], ['phaser-to-three','PHASERJS','THREEJS']
  ]) {
    const dir=host(name), task='postprocessing-demo';
    engine.generate(dir,project); write(dir,`.hephaera/.cache/tasks/${task}/TASK.md`,'# Isolated postprocessing routing fixture\n');
    const receipt=engine.resolve(dir,{recordOverride:true,override:effective,task,scope:'prototypes/postprocessing-demo'});
    selected(receipt,effective);
    const file=path.join(dir,receipt.evidence), stored=JSON.parse(fs.readFileSync(file,'utf8'));
    stored.postprocessing={backend:'OTHER',package:'postprocessing.nodes',renderer:'WebGPURenderer',readiness:'ready',testedVersion:'999'};
    fs.writeFileSync(file,JSON.stringify(stored,null,2)+'\n');fs.writeFileSync(file+'.sha256',sha(file)+'\n');
    const before=snapshot(dir);
    const consumed=engine.resolve(dir,{evidence:receipt.evidence,output:'prototypes/postprocessing-demo/src/postprocessing.mjs'});
    eq(consumed.effectiveEngine,effective);selected(consumed,effective);
    eq(snapshot(dir),before);
  }

  // Installed baseline paths and malformed metadata are isolated from the
  // shared registry so this suite can run beside other candidate checks.
  const installed=host('installed'), baseline=path.join(installed,'.hephaera');
  fs.mkdirSync(path.join(baseline,'commands/lib'),{recursive:true});
  fs.copyFileSync(path.join(engine.BASE,'commands/lib/engine-contract.cjs'),path.join(baseline,'commands/lib/engine-contract.cjs'));
  for(const definition of Object.values(registry.engines)) write(baseline,`.engine/${definition.definition}`,fs.readFileSync(path.join(engine.BASE,'.engine',definition.definition)));
  write(baseline,'.engine/registry.json',JSON.stringify(registry));
  const local=require(path.join(baseline,'commands/lib/engine-contract.cjs'));
  selected(local.generate(installed,'three.js'),'THREEJS');
  selected(local.resolve(installed),'THREEJS');
  eq(fs.readFileSync(path.join(installed,'ENGINE.md'),'utf8').includes('Read `./.hephaera/.engine/THREEJS.md` instructions'),true);
  const file=path.join(baseline,'.engine/registry.json');
  for(const [id,value] of [['THREEJS',undefined],['THREEJS',null],['THREEJS','OTHER'],['BABYLONJS','PMNDRS_POSTPROCESSING'],['GODOT','PMNDRS_POSTPROCESSING']]) {
    const changed=structuredClone(registry);
    if(value===undefined)delete changed.engines[id].postprocessingBackend;else changed.engines[id].postprocessingBackend=value;
    fs.writeFileSync(file,JSON.stringify(changed));
    throws(()=>local.postprocessingSelection(id),/postprocessingBackend/);
    const fresh=host('invalid-'+id+'-'+String(value));
    throws(()=>local.generate(fresh,id),/postprocessingBackend/);
    eq(fs.readdirSync(fresh),[]);
  }
  fs.writeFileSync(file,JSON.stringify(registry));
  const before=fs.readFileSync(path.join(installed,'ENGINE.md'),'utf8');
  const changed=structuredClone(registry);changed.engines.THREEJS.postprocessingBackend='OTHER';fs.writeFileSync(file,JSON.stringify(changed));
  throws(()=>local.generate(installed,'THREEJS'),/postprocessingBackend/);
  eq(fs.readFileSync(path.join(installed,'ENGINE.md'),'utf8'),before);
  throws(()=>local.resolve(installed),/postprocessingBackend/);
  throws(()=>local.postprocessingSelection('UNKNOWN'),/postprocessingBackend/);
  console.log(`Three.js postprocessing selection: ${checks} checks passed (declarative only; package/GPU readiness remains unverified).`);
} finally {
  // Only this suite's checked project-local fixture directory is removed.
  if(!path.resolve(root).startsWith(path.resolve(parent)+path.sep))throw new Error('Fixture cleanup left its project scope.');
  fs.rmSync(root,{recursive:true,force:true});
}
