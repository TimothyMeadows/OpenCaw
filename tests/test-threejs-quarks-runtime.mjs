import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createThreeQuarksRuntime, VERIFIED_VERSIONS} from '../.engine/threejs/particles/three-quarks-runtime.mjs';

const fixture = new URL('./fixtures/threejs-quarks/node_modules/', import.meta.url);
if (!fs.existsSync(new URL('three.quarks/package.json', fixture))) {
  throw new Error('Install the explicit test fixture first: npm ci --ignore-scripts --prefix tests/fixtures/threejs-quarks');
}
const THREE = await import(new URL('three/build/three.module.js', fixture));
const Quarks = await import(new URL('three.quarks/dist/three.quarks.esm.js', fixture));
const versions = Object.fromEntries(['three', 'three.quarks', 'quarks.core'].map(name => [name, JSON.parse(fs.readFileSync(new URL(`${name}/package.json`, fixture), 'utf8')).version]));
let checks = 0;
const eq = (a, b) => { assert.deepEqual(a, b); checks++; };
const ok = value => { assert.ok(value); checks++; };
const near = (a, b) => { assert.ok(Math.abs(a - b) < 1e-9, `${a} differs from ${b}`); checks++; };
const rejects = (fn, pattern) => { assert.throws(fn, pattern); checks++; };
const selection = {effectiveEngine: 'THREEJS', particles: {package: 'three.quarks'}};
const renderer = {isWebGLRenderer: true}; // CPU-only package execution, not a real WebGL context.
const options = scene => ({THREE, Quarks, scene, renderer, engineSelection: selection});
const emitter = (runtime, patch = {}) => runtime.createEmitter({id: 'effect', capacity: 32, rate: 20, lifetime: 1, speed: 0, ...patch});

eq(versions, {three: '0.182.0', 'three.quarks': '0.17.1', 'quarks.core': '0.17.1'});
eq(VERIFIED_VERSIONS, {three: '0.182.0', threeQuarks: '0.17.1', quarksCore: '0.17.1'});
rejects(() => createThreeQuarksRuntime(), /Resolve THREEJS/);
rejects(() => createThreeQuarksRuntime({...options(new THREE.Scene()), engineSelection: {effectiveEngine: 'UNITY'}}), /Resolve THREEJS/);
rejects(() => createThreeQuarksRuntime({...options(new THREE.Scene()), THREE: {...THREE, REVISION: '181'}}), /r182/);
rejects(() => createThreeQuarksRuntime({...options(new THREE.Scene()), Quarks: {...Quarks, ParticleSystem: null}}), /Missing Quarks/);
rejects(() => createThreeQuarksRuntime({...options(new THREE.Scene()), renderer: {isWebGPURenderer: true}}), /WebGLRenderer/);
rejects(() => createThreeQuarksRuntime({...options(new THREE.Scene()), scene: new THREE.Group()}), /Scene/);
rejects(() => createThreeQuarksRuntime({...options(new THREE.Scene()), maxDelta: .3}), /maxDelta/);
rejects(() => createThreeQuarksRuntime({...options(new THREE.Scene()), maxSystems: 1.1}), /integer/);

{
  const scene = new THREE.Scene(), runtime = createThreeQuarksRuntime({...options(scene), maxSystems: 2, maxParticles: 64});
  rejects(() => createThreeQuarksRuntime(options(scene)), /already/);
  const handle = emitter(runtime), system = handle.emitter.system;
  ok(system instanceof Quarks.ParticleSystem);
  ok(scene.children.some(node => node instanceof Quarks.BatchedRenderer));
  eq(runtime.stats().capacity, 32);
  eq(handle.stats().particles, 0);
  runtime.update(0); eq(system.time, 0); eq(handle.stats().particles, 0);
  runtime.update(.05); near(system.time, .05); near(runtime.stats().time, .05);
  runtime.update(0); eq(handle.stats().particles, 0); near(system.time, .05);
  runtime.update(.05); near(system.time, .1); ok(handle.stats().particles > 0);
  const before = handle.stats(); runtime.pause(); runtime.update(.1);
  eq(handle.stats(), before); near(runtime.stats().time, .1);
  runtime.resume(); runtime.update(.05); near(system.time, .15);
  handle.pause(); const time = system.time; runtime.update(.05); near(system.time, time);
  handle.play(); runtime.update(.05); near(system.time, .2);
  rejects(() => runtime.update(-1), /deltaSeconds/); rejects(() => runtime.update(NaN), /deltaSeconds/); rejects(() => runtime.update(.2), /deltaSeconds/);
  rejects(() => emitter(runtime), /already exists/);
  const pool = handle.stats().pooledParticles, token = handle.generation;
  handle.stop(); eq(handle.stats().particles, 0); eq(handle.stats().pooledParticles, pool); ok(handle.generation > token);
  eq(handle.play(token), false); eq(handle.play(), true); runtime.update(.1); runtime.update(.1); ok(handle.stats().particles > 0);
  const stoppedGeneration = handle.generation; handle.restart(); ok(handle.generation > stoppedGeneration); eq(handle.stats().particles, 0);
  runtime.clear(); eq(handle.stats().particles, 0); eq(handle.stats().active, false);
  runtime.reset(); eq(runtime.stats().time, 0); eq(runtime.stats().systems, 1);
  runtime.dispose(); runtime.dispose(); eq(runtime.stats().disposed, true); eq(runtime.stats().systems, 0); eq(scene.children.length, 0);
  eq(handle.dispose(), false); rejects(() => runtime.update(.01), /disposed/);
  const replacement = createThreeQuarksRuntime(options(scene)); replacement.dispose();
}
{
  const scene = new THREE.Scene(), runtime = createThreeQuarksRuntime({...options(scene), maxDelta: .25});
  const handle = emitter(runtime, {capacity: 27}); runtime.update(.25); near(handle.emitter.system.time, .25); near(runtime.stats().time, .25);
  for (let i = 0; i < 100; i++) runtime.update(.25);
  ok(handle.stats().particles <= 27); ok(handle.stats().pooledParticles <= 27);
  runtime.dispose();
}
{
  const scene = new THREE.Scene(), runtime = createThreeQuarksRuntime({...options(scene), maxSystems: 2, maxParticles: 64});
  const invalid = [
    [{id: 123}, /emitter id/], [{capacity: 0}, /capacity/], [{capacity: 10, rate: 20}, /capacity/], [{rate: Infinity}, /rate/],
    [{lifetime: NaN}, /lifetime/], [{count: 3}, /not both/], [{kind: 'burst', count: 5, rate: 0, looping: true}, /cannot loop/],
    [{color: [1, 0]}, /RGBA/], [{color: [2, 0, 0, 1]}, /component/], [{shape: 'mesh'}, /shapes/],
    [{space: 'screen'}, /space/], [{parent: new THREE.Group()}, /attached/], [{parent: new THREE.Scene()}, /attached/],
    [{material: new THREE.MeshStandardMaterial()}, /MeshBasicMaterial/], [{behaviors: []}, /Unknown/], [{prewarm: true}, /Unknown/]
  ];
  for (const [patch, pattern] of invalid) rejects(() => emitter(runtime, patch), pattern);
  eq(runtime.stats().systems, 0); eq(runtime.stats().batches, 0);
  emitter(runtime, {id: 'a'}); emitter(runtime, {id: 'b'}); rejects(() => emitter(runtime, {id: 'c'}), /capacity exceeded/);
  runtime.dispose();
}
{
  const scene = new THREE.Scene(), runtime = createThreeQuarksRuntime(options(scene));
  const handle = emitter(runtime, {kind: 'burst', count: 10, rate: 0, capacity: 10, autoStart: false, duration: .1});
  runtime.setQuality(1); runtime.setReducedMotion(true); handle.play(); runtime.update(.01);
  eq(handle.stats().particles, 1); // floor(10 * .5 * .25), one burst only.
  runtime.update(.01); eq(handle.stats().particles, 1);
  rejects(() => runtime.setQuality(3), /quality/); rejects(() => runtime.setReducedMotion(1), /boolean/);
  runtime.setQuality(0); eq(handle.emitter.visible, false); runtime.setQuality(2); eq(handle.emitter.visible, true);
  handle.restart(); runtime.setReducedMotion(false); runtime.update(.01); eq(handle.stats().particles, 10);
  for (let i = 0; i < 20; i++) runtime.update(.1);
  eq(handle.stats().particles, 0); eq(handle.stats().active, false); runtime.dispose();
}
{
  const scene = new THREE.Scene(), anchor = new THREE.Group(); scene.add(anchor); anchor.position.x = 3;
  const runtime = createThreeQuarksRuntime({...options(scene), maxSystems: 4, maxParticles: 48});
  const sphere = emitter(runtime, {kind: 'burst', count: 1, rate: 0, capacity: 1, shape: 'sphere', radius: 2});
  runtime.update(.01); eq(sphere.stats().particles, 1);
  const point = sphere.emitter.system.particles[0].position;
  ok(Number.isFinite(point.x + point.y + point.z)); ok(point.length() <= 2.000001);
  const local = emitter(runtime, {id: 'local', parent: anchor, space: 'local'});
  rejects(() => emitter(runtime, {id: 'over-reservation'}), /capacity exceeded/);
  runtime.update(.05); runtime.update(.05); near(local.emitter.system.particles[0].position.x, 0);
  anchor.position.x = 9; runtime.update(.05); near(local.emitter.system.particles[0].position.x, 0);
  runtime.dispose();
}
{
  const scene = new THREE.Scene(), anchor = new THREE.Group(); scene.add(anchor); anchor.position.x = 2;
  const runtime = createThreeQuarksRuntime(options(scene)), handle = emitter(runtime, {parent: anchor});
  runtime.update(.05); runtime.update(.05); near(handle.emitter.system.particles[0].position.x, 2);
  anchor.position.x = 4; runtime.update(.05);
  ok(handle.emitter.system.particles.slice(0, handle.stats().particles).some(particle => particle.position.x === 4));
  scene.remove(anchor); rejects(() => runtime.update(.05), /left its Scene/); eq(runtime.stats().systems, 0);
  const old = handle; scene.add(anchor); const fresh = emitter(runtime, {parent: anchor});
  eq(old.dispose(), false); eq(old.stop(), false); eq(old.restart(), false); eq(runtime.stats().systems, 1);
  fresh.dispose(); runtime.dispose(); ok(scene.children.includes(anchor));
}
{
  const scene = new THREE.Scene(), texture = new THREE.Texture(), sourceA = new THREE.MeshBasicMaterial({map: texture, transparent: true});
  const sourceB = new THREE.MeshBasicMaterial({transparent: true});
  let sourceDisposals = 0, textureDisposals = 0, geometryDisposals = 0, cloneDisposals = 0;
  sourceA.addEventListener('dispose', () => sourceDisposals++); sourceB.addEventListener('dispose', () => sourceDisposals++); texture.addEventListener('dispose', () => textureDisposals++);
  const runtime = createThreeQuarksRuntime(options(scene));
  const a = emitter(runtime, {id: 'a', material: sourceA}), b = emitter(runtime, {id: 'b', material: sourceB});
  const batchRenderer = scene.children.find(node => node.type === 'BatchedRenderer'); eq(batchRenderer.batches.length, 2);
  for (const batch of batchRenderer.batches) {
    batch.geometry.addEventListener('dispose', () => geometryDisposals++);
    batch.material.addEventListener('dispose', () => cloneDisposals++);
    batch.settings.material.addEventListener('dispose', () => cloneDisposals++);
  }
  a.dispose(); eq(batchRenderer.batches.length, 1); eq(batchRenderer.systemToBatchIndex.get(b.emitter.system), 0);
  runtime.update(.05); near(b.emitter.system.time, .05); runtime.dispose();
  eq(geometryDisposals, 2); eq(cloneDisposals, 4); eq(sourceDisposals, 0); eq(textureDisposals, 0);
  sourceA.dispose(); sourceB.dispose(); texture.dispose(); eq(sourceDisposals, 2); eq(textureDisposals, 1);
}
{
  const scene = new THREE.Scene(), runtime = createThreeQuarksRuntime(options(scene));
  for (let i = 0; i < 50; i++) {
    const handle = emitter(runtime, {id: 'recycled'}); runtime.update(.01); handle.dispose();
    eq(runtime.stats().batches, 0); eq(runtime.stats().capacity, 0);
  }
  const handle = emitter(runtime); handle.emitter.system.emissionBursts.push({time: 0, count: new Quarks.ConstantValue(100000), probability: 1});
  rejects(() => runtime.update(.01), /burst configuration changed/); eq(handle.stats().particles, 0);
  runtime.dispose();
}
{
  const scene = new THREE.Scene(); scene.add(new Quarks.BatchedRenderer());
  rejects(() => createThreeQuarksRuntime(options(scene)), /already contains/);
}
console.log(`Three.quarks runtime: ${checks} actual-library CPU/lifecycle checks passed; no WebGL, shader, browser, mobile/MAUI or device rendering acceptance.`);
