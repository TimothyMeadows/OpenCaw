#!/usr/bin/env node
'use strict';
// Protocol fixtures remain explicitly simulated. --real additionally uses the
// selected, task-local Three.js package; it does not install dependencies.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {pathToFileURL} = require('node:url');
const ROOT = path.resolve(__dirname, '..');
const TASK = path.join(ROOT, '.hephaera/.cache/tasks/model-to-animation-design');
const ADAPTER = path.join(ROOT, 'runtime/bubo/resources/model-to-animation/engines/threejs-motion.mjs');

function protocolThree() {
  class Vector3 {
    constructor(x = 0, y = 0, z = 0) { Object.assign(this, {x, y, z}); }
    set(x, y, z) { Object.assign(this, {x, y, z}); return this; }
    clone() { return new Vector3(this.x, this.y, this.z); }
    copy(other) { return this.set(other.x, other.y, other.z); }
    add(other) { this.x += other.x; this.y += other.y; this.z += other.z; return this; }
    sub(other) { this.x -= other.x; this.y -= other.y; this.z -= other.z; return this; }
    multiplyScalar(value) { this.x *= value; this.y *= value; this.z *= value; return this; }
    fromArray(values) { return this.set(...values); }
    toArray() { return [this.x, this.y, this.z]; }
  }
  class Events {
    constructor() { this.listeners = new Map(); }
    addEventListener(type, listener) { if (!this.listeners.has(type)) this.listeners.set(type, new Set()); this.listeners.get(type).add(listener); }
    removeEventListener(type, listener) { this.listeners.get(type)?.delete(listener); }
    dispatchEvent(event) { for (const listener of this.listeners.get(event.type) || []) listener(event); }
  }
  let sequence = 0;
  class Object3D extends Events {
    constructor() { super(); this.name = ''; this.uuid = 'protocol-' + sequence++; this.position = new Vector3(); this.rotation = {x: 0, y: 0, z: 0}; this.children = []; this.parent = null; }
    add(...children) { children.forEach(child => { child.removeFromParent(); child.parent = this; this.children.push(child); }); return this; }
    removeFromParent() { if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1); this.parent = null; }
    traverse(visitor) { visitor(this); [...this.children].forEach(child => child.traverse(visitor)); }
    getObjectByName(name) { let found = null; this.traverse(node => { if (node.name === name) found = node; }); return found; }
    updateWorldMatrix() {}
    getWorldPosition(result) { result.copy(this.position); for (let node = this.parent; node; node = node.parent) result.add(node.position); return result; }
    localToWorld(point) { for (let node = this; node; node = node.parent) point.add(node.position); return point; }
    worldToLocal(point) { for (let node = this; node; node = node.parent) point.sub(node.position); return point; }
  }
  class Color { constructor(value = '#000000') { this.value = value; } set(value) { this.value = value; return this; } setRGB(...value) { this.value = value; return this; } copy(other) { return this.set(other.value); } clone() { return new Color(this.value); } }
  class Material extends Events { constructor(options = {}) { super(); Object.assign(this, options); this.emissive = new Color(); this.emissiveIntensity = 0.2; } clone() { const result = new Material(); result.emissive.copy(this.emissive); result.emissiveIntensity = this.emissiveIntensity; return result; } dispose() { this.dispatchEvent({type: 'dispose'}); } }
  class BufferGeometry extends Events { constructor() { super(); this.attributes = {}; } setAttribute(name, attribute) { this.attributes[name] = attribute; } setDrawRange(start, count) { this.drawRange = {start, count}; } dispose() { this.dispatchEvent({type: 'dispose'}); } }
  class BufferAttribute { constructor(array, itemSize) { this.array = array; this.itemSize = itemSize; } }
  class Points extends Object3D { constructor(geometry, material) { super(); this.geometry = geometry; this.material = material; } }
  class Action {
    constructor(mixer, clip) { this.mixer = mixer; this.clip = clip; this.time = 0; this.running = false; this.timeScale = 1; }
    reset() { this.time = 0; return this; } setEffectiveTimeScale(value) { this.timeScale = value; return this; } setEffectiveWeight() { return this; }
    setLoop(mode) { this.loop = mode; return this; } play() { this.running = true; return this; } stop() { this.running = false; return this; }
    crossFadeTo(other) { this.stop(); other.play(); return this; }
  }
  class AnimationMixer extends Events {
    constructor(root) { super(); this.root = root; this.time = 0; this.actions = new Map(); }
    clipAction(clip) { if (!this.actions.has(clip)) this.actions.set(clip, new Action(this, clip)); return this.actions.get(clip); }
    stopAllAction() { this.actions.forEach(action => action.stop()); } uncacheRoot() { this.actions.clear(); }
    update(dt) {
      this.time += dt;
      this.actions.forEach(action => {
        if (!action.running) return;
        action.time += dt * action.timeScale;
        if (action.time >= action.clip.duration) {
          if (action.loop === 2201) { const count = Math.floor(action.time / action.clip.duration); action.time %= action.clip.duration; this.dispatchEvent({type: 'loop', action, loopDelta: count}); }
          else { action.time = action.clip.duration; action.running = false; this.dispatchEvent({type: 'finished', action}); }
        }
        for (const track of action.clip.tracks) {
          if (!track.name.endsWith('.position')) continue;
          const node = this.root.getObjectByName(track.name.slice(0, -9));
          if (!node) continue;
          let index = 0; while (index + 1 < track.times.length && track.times[index + 1] < action.time) index++;
          const next = Math.min(index + 1, track.times.length - 1);
          const alpha = next === index ? 0 : (action.time - track.times[index]) / (track.times[next] - track.times[index]);
          node.position.fromArray([0, 1, 2].map(axis => track.values[index * 3 + axis] * (1 - alpha) + track.values[next * 3 + axis] * alpha));
        }
      });
    }
  }
  class VectorKeyframeTrack { constructor(name, times, values) { Object.assign(this, {name, times, values}); } getValueSize() { return 3; } }
  class QuaternionKeyframeTrack extends VectorKeyframeTrack { getValueSize() { return 4; } }
  class AnimationClip { constructor(name, duration, tracks) { Object.assign(this, {name, duration, tracks}); } }
  return {Vector3, Color, Group: Object3D, Object3D, AnimationMixer, AnimationClip, VectorKeyframeTrack, QuaternionKeyframeTrack, BufferGeometry, BufferAttribute, Points, PointsMaterial: Material, MeshStandardMaterial: Material, LoopRepeat: 2201, LoopOnce: 2200};
}

const selection = () => ({effectiveEngine: 'THREEJS', projectEngine: 'THREEJS', selectionSource: 'contract', contractSha256: 'a'.repeat(64), definitionSha256: 'b'.repeat(64), registrySha256: 'c'.repeat(64)});
function packageData() {
  return {
    schemaVersion: 'hephaera-motion-package/v1', profile: 'skinned', engine: selection(), coordinateSystem: {runtimeUp: '+Y'}, rig: {rootBone: 'Root'},
    clips: ['idle', 'run', 'jump', 'death'].map(id => ({id, action: id, role: id, duration: 1, loop: ['idle', 'run'].includes(id), rootMotion: 'in-place', markers: [{time: 0.25, event: 'contact'}]})),
    anchors: [{id: 'exhaust', node: 'anchor.exhaust'}],
    parameters: [{id: 'speed', unit: 'metres-per-second', min: 0, max: 10, default: 0, bindings: [{node: 'wheel', property: 'rotation', axis: 'x', mode: 'angular-speed', scale: 2}]}],
    states: [{id: 'idle', clip: 'idle'}, {id: 'run', clip: 'run'}, {id: 'jump', clip: 'jump'}, {id: 'dead', clip: 'death', terminal: true}, {id: 'warp-enter'}, {id: 'warp-sustain'}, {id: 'warp-exit'}],
    transitions: [{from: 'idle', to: 'run', trigger: 'move', duration: 0.1}, {from: 'run', to: 'jump', trigger: 'jump', duration: 0.05}, ...['idle', 'run', 'jump', 'warp-enter', 'warp-sustain', 'warp-exit'].map(from => ({from, to: 'dead', trigger: 'die', duration: 0.1})), {from: 'idle', to: 'warp-enter', trigger: 'warp', duration: 0}, {from: 'warp-enter', to: 'warp-sustain', trigger: 'ready', duration: 0}, {from: 'warp-sustain', to: 'warp-exit', trigger: 'arrive', duration: 0}, {from: 'warp-enter', to: 'idle', trigger: 'cancel', duration: 0}, {from: 'warp-sustain', to: 'idle', trigger: 'cancel', duration: 0}, {from: 'warp-exit', to: 'idle', trigger: 'settled', duration: 0}],
    effects: [{id: 'exhaust', type: 'particles', anchor: 'exhaust', parameter: 'speed', states: ['run', 'warp-enter', 'warp-sustain'], maxParticles: 16, lifetime: 0.2, rate: 80, space: 'world', velocity: [0, 0, -2], color: '#80aaff'}, {id: 'glow', type: 'material', anchor: 'exhaust', target: 'thruster', parameter: 'speed', maxIntensity: 3, states: ['warp-enter', 'warp-sustain'], reducedMotionScale: 0.1}],
    provenance: {provider: 'owned', rights: 'Synthetic original fixture; no production acceptance'}, budgets: {maxParticles: 64}
  };
}

function fixture(THREE, overrides = {}) {
  const scene = new THREE.Group(), movementRoot = new THREE.Group(), visualRoot = new THREE.Group();
  scene.name = 'scene'; movementRoot.name = 'authoritative'; movementRoot.position.set(10, 0, 0); visualRoot.name = 'visual'; scene.add(movementRoot); movementRoot.add(visualRoot);
  const root = new THREE.Group(); root.name = 'Root'; const hips = new THREE.Group(); hips.name = 'hips'; root.add(hips); visualRoot.add(root);
  const wheel = new THREE.Group(); wheel.name = 'wheel'; visualRoot.add(wheel);
  const anchor = new THREE.Group(); anchor.name = 'anchor.exhaust'; anchor.position.set(0, 0, -0.5); visualRoot.add(anchor);
  const thruster = new THREE.Group(); thruster.name = 'thruster'; thruster.material = new THREE.MeshStandardMaterial({emissive: '#000000', emissiveIntensity: 0.2}); visualRoot.add(thruster);
  const animations = ['idle', 'run', 'jump', 'death'].map((id, index) => new THREE.AnimationClip(id, 1, [new THREE.VectorKeyframeTrack('hips.position', [0, 0.5, 1], [0, 0, 0, 0, 0.1 + index * 0.1, 0, 0, 0, 0])]));
  return {THREE, scene, movementRoot, visualRoot, animations, effectParent: scene, motionPackage: packageData(), engineSelection: selection(), root, hips, wheel, anchor, thruster, ...overrides};
}

async function runSuite(THREE, real) {
  const {createMotionPresentation, validateMotionPresentation} = await import(pathToFileURL(ADAPTER).href);
  let assertions = 0;
  const check = (condition, message) => { assert.ok(condition, message); assertions++; };
  const rejects = (fn, message) => { assert.throws(fn, undefined, message); assertions++; };
  const clone = value => JSON.parse(JSON.stringify(value));
  const valid = packageData(); check(validateMotionPresentation(valid, selection()).particleCapacity === 16, 'actual capacity derives from declared effects');
  const badSelection = selection(); badSelection.effectiveEngine = 'UNITY'; rejects(() => validateMotionPresentation(valid, badSelection), 'wrong engine blocks adapter');
  rejects(() => validateMotionPresentation(valid, {effectiveEngine: 'THREEJS'}), 'plain engine label cannot substitute for canonical selection evidence');
  for (const [label, mutate] of [
    ['stale selection', p => p.engine.contractSha256 = '0'.repeat(64)],
    ['unknown profile', p => p.profile = 'vehicle-with-fake-skeleton'],
    ['duplicate clip', p => p.clips.push(clone(p.clips[0]))],
    ['missing state clip', p => p.states[0].clip = 'absent'],
    ['ambiguous transition', p => p.transitions.push(clone(p.transitions[0]))],
    ['missing transition target', p => p.transitions[0].to = 'absent'],
    ['invalid clip duration', p => p.clips[0].duration = 0],
    ['missing root policy', p => delete p.clips[0].rootMotion],
    ['out-of-range marker', p => p.clips[0].markers[0].time = 2],
    ['duplicate marker', p => p.clips[0].markers.push(clone(p.clips[0].markers[0]))],
    ['zero parameter range', p => p.parameters[0].max = 0],
    ['parameter binding conflict', p => p.parameters.push({...clone(p.parameters[0]), id: 'another'})],
    ['invalid articulation axis', p => p.parameters[0].bindings[0].axis = 'w'],
    ['invalid articulation mode', p => p.parameters[0].bindings[0].mode = 'arbitrary-code'],
    ['missing effect anchor', p => p.effects[0].anchor = 'absent'],
    ['missing effect state', p => p.effects[0].states = ['absent']],
    ['unbounded particles', p => p.effects[0].maxParticles = 1000000],
    ['aggregate particle budget', p => p.budgets.maxParticles = 8],
    ['invalid effect space', p => p.effects[0].space = 'global-auto'],
    ['zero particle lifetime', p => p.effects[0].lifetime = 0],
    ['invalid material target', p => delete p.effects[1].target],
    ['excluded declared origin', p => p.provenance.provider = 'Adobe'],
    ['excluded declared motion origin', p => p.provenance.motion = {vendor: 'Mixamo'}]
  ]) {
    const value = clone(valid); mutate(value); rejects(() => validateMotionPresentation(value, selection()), label);
  }
  let f = fixture(THREE); const originalMaterial = f.thruster.material;
  const presentation = createMotionPresentation(f);
  f.motionPackage.states[0].id = 'mutated-shared-content'; f.motionPackage.parameters[0].max = 1000;
  check(presentation.state === 'idle', 'presentation retains the approved state snapshot when host content objects mutate');
  presentation.setParameters({speed: 50});
  check(presentation.stats().parameters.speed === 10, 'parameter limits cannot change through later shared content mutation');
  presentation.setParameters({speed: 0});
  check(presentation.state === 'idle' && presentation.generation === 1, 'explicit initial state and generation');
  check(f.scene.children.length === 2 && f.thruster.material !== originalMaterial, 'world effect and isolated material are actual owned resources');
  const startMovement = f.movementRoot.position.toArray();
  check(presentation.dispatch('move'), 'valid transition applies');
  for (let i = 0; i < 30; i++) presentation.update(1 / 60);
  check(f.hips.position.y > 0.01, 'actual animation channels change the visual hierarchy');
  check(JSON.stringify(f.movementRoot.position.toArray()) === JSON.stringify(startMovement), 'animation never moves authoritative root');
  check(presentation.stats().events.some(event => event.type === 'marker' && event.marker === 'contact'), 'marker signals are observable presentation events');
  presentation.setParameters({speed: 5}); presentation.update(0.1);
  check(Math.abs(f.wheel.rotation.x - 1) < 1e-6, 'vehicle wheel responds to physical speed through calibrated parameter binding');
  check(presentation.stats().particles > 0 && presentation.stats().particles <= 16, 'bounded effect emission responds to speed');
  for (let i = 0; i < 120; i++) presentation.update(1 / 60);
  check(presentation.stats().particles <= presentation.stats().particleCapacity, 'sustained speed cannot exceed allocated effect capacity');
  const beforePause = presentation.stats(); const beforeWheel = f.wheel.rotation.x;
  presentation.setPaused(true); presentation.update(0.1);
  check(presentation.stats().mixerTime === beforePause.mixerTime && f.wheel.rotation.x === beforeWheel, 'pause freezes animation, articulation and effect time');
  presentation.setPaused(false);
  presentation.setReducedMotion(true); presentation.update(0.1);
  check(presentation.stats().particles === 0, 'reduced motion default suppresses speed particles');
  presentation.setReducedMotion(false); presentation.setQuality(0); presentation.update(0.1);
  check(presentation.stats().particles <= 4, 'low quality bounds active effect density');
  const parameters = presentation.stats().parameters;
  rejects(() => presentation.setParameters({speed: 3, missing: 1}), 'invalid parameter update fails atomically');
  check(presentation.stats().parameters.speed === parameters.speed, 'failed parameter update preserves prior accepted values');
  rejects(() => presentation.update(Number.NaN), 'nonfinite clock input rejects');
  rejects(() => presentation.update(3), 'unbounded catch-up delta rejects');
  rejects(() => presentation.setQuality(0.5), 'quality tiers are discrete');
  const staleGeneration = presentation.generation; presentation.reset();
  check(!presentation.dispatch('move', staleGeneration), 'late prior-generation callback cannot transition reused actor');
  check(presentation.dispatch('warp'), 'warp enters only through explicit gameplay request');
  presentation.setParameters({speed: 10}); presentation.update(0.1);
  check(presentation.state === 'warp-enter', 'effect/animation time does not decide authoritative warp readiness');
  check(f.thruster.material.emissiveIntensity > originalMaterial.emissiveIntensity, 'selected warp phase drives actual isolated material response');
  check(presentation.dispatch('ready') && presentation.state === 'warp-sustain', 'explicit readiness enters sustain phase');
  check(presentation.dispatch('cancel') && presentation.state === 'idle' && presentation.stats().particles === 0, 'warp cancellation clears phase-owned effects');
  check(presentation.dispatch('die') && presentation.state === 'dead', 'death interruption enters terminal state');
  for (let i = 0; i < 70; i++) presentation.update(1 / 60);
  check(presentation.stats().events.some(event => event.type === 'clip-finished'), 'nonlooping action completion is recorded without gameplay mutation');
  check(!presentation.dispatch('move') && !presentation.dispatch('warp'), 'terminal death cannot silently restart movement or warp');
  presentation.reset(); check(presentation.state === 'idle' && Math.abs(f.wheel.rotation.x) < 1e-10, 'respawn resets local articulation and presentation state');
  const ownedMaterial = f.thruster.material; let disposedMaterial = false; ownedMaterial.addEventListener('dispose', () => { disposedMaterial = true; });
  presentation.dispose(); presentation.dispose();
  check(presentation.stats().disposed && presentation.stats().particles === 0, 'disposal is idempotent and empties effects');
  check(f.scene.children.length === 1 && f.thruster.material === originalMaterial && disposedMaterial, 'disposal removes owned effects and restores shared source material');
  rejects(() => presentation.update(0.01), 'disposed instance cannot resume');
  for (const mutation of [
    f => { f.visualRoot = f.movementRoot; },
    f => { f.visualRoot.removeFromParent(); },
    f => { f.animations = f.animations.slice(1); },
    f => { f.animations[0].duration = 2; },
    f => { f.animations[0].tracks = []; },
    f => { f.motionPackage.anchors[0].node = 'absent'; },
    f => { const other = new THREE.Group(); other.name = 'anchor.exhaust'; f.visualRoot.add(other); },
    f => { f.effectParent = null; },
    f => { f.motionPackage.parameters[0].bindings[0].node = 'visual'; },
    f => { f.animations[0].tracks.push(new THREE.VectorKeyframeTrack('wheel.position', [0, 1], [0, 0, 0, 1, 0, 0])); f.motionPackage.parameters[0].bindings[0] = {node: 'wheel', property: 'position', axis: 'y', mode: 'position', scale: 1}; },
    f => { f.motionPackage.effects.push({...clone(f.motionPackage.effects[1]), id: 'duplicate-owner'}); }
  ]) {
    const value = fixture(THREE); mutation(value);
    const childCount = value.scene.children.length; rejects(() => createMotionPresentation(value), 'invalid producer/binding context rejects before resource ownership');
    check(value.scene.children.length === childCount, 'rejected construction leaves no owned scene resource');
  }
  const frameResults = [];
  for (const fps of [15, 30, 60]) {
    const value = fixture(THREE); const p = createMotionPresentation(value); p.setParameters({speed: 2});
    for (let i = 0; i < fps; i++) p.update(1 / fps);
    frameResults.push(value.wheel.rotation.x); p.dispose();
  }
  check(Math.max(...frameResults) - Math.min(...frameResults) < 1e-6, 'parameter articulation agrees across declared frame rates');
  f = fixture(THREE); f.motionPackage.clips[0].rootMotion = 'extract'; f.motionPackage.clips[0].rootDisplacement = [1, 0, 0];
  f.animations[0] = new THREE.AnimationClip('idle', 1, [new THREE.VectorKeyframeTrack('Root.position', [0, 1], [0, 0, 0, 1, 0, 0])]);
  rejects(() => createMotionPresentation(f), 'extraction cannot implicitly move the world without controller sink');
  const extracted = []; f.rootMotionSink = event => extracted.push(event.translation);
  const rootMotion = createMotionPresentation(f);
  for (let i = 0; i < 90; i++) rootMotion.update(1 / 60);
  check(Math.abs(extracted.reduce((sum, value) => sum + value[0], 0) - 1.5) < 1e-4, 'translation extraction includes loop displacement once');
  check(Math.abs(f.root.position.x) < 1e-6 && f.movementRoot.position.x === 10, 'extracted translation is removed locally and only offered to controller');
  rootMotion.dispose();
  f = fixture(THREE); f.motionPackage.clips[0].rootMotion = 'extract'; f.motionPackage.clips[0].rootDisplacement = [0, 0, 0]; f.rootMotionSink = () => {};
  f.animations[0] = new THREE.AnimationClip('idle', 1, [new THREE.QuaternionKeyframeTrack('Root.quaternion', [0, 1], [0, 0, 0, 1, 0, 1, 0, 0])]);
  rejects(() => createMotionPresentation(f), 'unsupported rotating-root extraction blocks with explicit adapter guidance');
  for (const property of ['position', 'quaternion', 'scale']) {
    const value = fixture(THREE), parent = new THREE.Group(); parent.name = 'MotionRoot'; value.visualRoot.add(parent); parent.add(value.root);
    value.motionPackage.clips[0].rootMotion = 'extract'; value.motionPackage.clips[0].rootDisplacement = [1, 0, 0];
    let sinkCalls = 0; value.rootMotionSink = () => { sinkCalls++; };
    const track = property === 'quaternion'
      ? new THREE.QuaternionKeyframeTrack('MotionRoot.quaternion', [0, 1], [0, 0, 0, 1, 0, 1, 0, 0])
      : new THREE.VectorKeyframeTrack('MotionRoot.' + property, [0, 1], property === 'scale' ? [1, 1, 1, 2, 1, 1] : [0, 0, 0, 1, 0, 0]);
    value.animations[0] = new THREE.AnimationClip('idle', 1, [track]);
    const original = value.thruster.material, count = value.scene.children.length;
    assert.throws(() => createMotionPresentation(value), /Animated ancestors/, 'unsupported animated ancestor fails before playback'); assertions++;
    check(sinkCalls === 0 && value.movementRoot.position.x === 10 && value.scene.children.length === count && value.thruster.material === original, 'ancestor rejection leaves movement and owned resources untouched');
  }
  f = fixture(THREE); const fixedParent = new THREE.Group(); fixedParent.name = 'MotionRoot'; f.visualRoot.add(fixedParent); fixedParent.add(f.root);
  f.motionPackage.clips[0].rootMotion = 'extract'; f.motionPackage.clips[0].rootDisplacement = [1, 0, 0]; f.rootMotionSink = event => { f.movementRoot.position.x += event.translation[0]; };
  f.animations[0] = new THREE.AnimationClip('idle', 1, [new THREE.VectorKeyframeTrack('Root.position', [0, 1], [0, 0, 0, 1, 0, 0]), new THREE.VectorKeyframeTrack('MotionRoot.position', [0, 1], [0, 0, 0, 0, 0, 0])]);
  const supportedExtraction = createMotionPresentation(f); supportedExtraction.update(.25); supportedExtraction.update(.25);
  const rootWorld = f.root.getWorldPosition(new THREE.Vector3());
  check(Math.abs(f.movementRoot.position.x - 10.5) < 1e-6 && Math.abs(rootWorld.x - 10.5) < 1e-6, 'constant ancestor export channels permit translation exactly once in visual world space'); supportedExtraction.dispose();
  for (const extractedClip of ['idle', 'run']) for (const target of ['Root', 'MotionRoot']) for (const property of ['position', 'rotation']) {
    const value = fixture(THREE), parent = new THREE.Group(); parent.name = 'MotionRoot'; value.visualRoot.add(parent); parent.add(value.root);
    const index = value.motionPackage.clips.findIndex(clip => clip.id === extractedClip);
    value.motionPackage.clips[index].rootMotion = 'extract'; value.motionPackage.clips[index].rootDisplacement = [1, 0, 0];
    value.animations[index] = new THREE.AnimationClip(extractedClip, 1, [new THREE.VectorKeyframeTrack('Root.position', [0, 1], [0, 0, 0, 1, 0, 0])]);
    value.motionPackage.parameters[0].bindings = [{node: target, property, axis: 'x', mode: property === 'position' ? 'position' : 'angle', scale: 1}];
    let calls = 0; value.rootMotionSink = () => { calls++; };
    const material = value.thruster.material, count = value.scene.children.length;
    assert.throws(() => createMotionPresentation(value), /Parameter articulation cannot own extracted roots or their ancestors/, 'parameter ownership cannot bypass extraction preflight through another state or transform property'); assertions++;
    check(calls === 0 && value.movementRoot.position.x === 10 && parent.position.x === 0 && value.thruster.material === material && value.scene.children.length === count, 'conflicting parameter/root ownership rejects before movement, material cloning or effect creation');
  }
  for (const operation of ['reset', 'dispose', 'self-transition']) {
    const value = fixture(THREE); value.motionPackage.clips[0].markers.push({time: .25, event: 'stale-second'});
    value.motionPackage.transitions.push({from: 'idle', to: 'idle', trigger: 'restart', duration: 0});
    let p, enabled = false; const seen = [];
    value.onPresentationEvent = event => {
      seen.push(event);
      if (enabled && event.type === 'marker' && event.marker === 'contact') {
        enabled = false;
        if (operation === 'self-transition') p.dispatch('restart'); else p[operation]();
      }
    };
    p = createMotionPresentation(value); enabled = true; p.setParameters({speed: 5}); p.update(.25);
    check(!seen.some(event => event.marker === 'stale-second'), operation + ' aborts remaining old-clip markers');
    check(value.wheel.rotation.x === 0 && p.stats().particles === 0, operation + ' aborts old-frame articulation and effects');
    check(operation !== 'dispose' || p.stats().disposed, 'callback disposal completes safely after native mixer iteration');
    if (operation !== 'dispose') {
      p.update(.25);
      check(seen.filter(event => event.marker === 'contact').length === 2, operation + ' retains the new clip cursor instead of overwriting it with old time');
      p.dispose();
    }
  }
  for (const operation of ['reset', 'dispose']) {
    const value = fixture(THREE); let p, enabled = false; const seen = [];
    value.onPresentationEvent = event => { seen.push(event); if (enabled && event.type === 'clip-finished') { enabled = false; p[operation](); } };
    p = createMotionPresentation(value); p.reset('dead'); p.setParameters({speed: 5}); enabled = true;
    for (let frame = 0; frame < 4; frame++) p.update(.25);
    check(seen.filter(event => event.type === 'clip-finished').length === 1, 'finished callback is delivered once outside mixer action iteration');
    check(value.wheel.rotation.x === 0 && p.stats().particles === 0, operation + ' from completion prevents remaining old-frame writes');
    if (operation !== 'dispose') { check(p.state === 'idle', 'completion reset owns the new presentation state'); p.dispose(); }
  }
  for (const operation of ['reset', 'dispose']) {
    const value = fixture(THREE); value.motionPackage.clips[0].rootMotion = 'extract'; value.motionPackage.clips[0].rootDisplacement = [1, 0, 0];
    value.animations[0] = new THREE.AnimationClip('idle', 1, [new THREE.VectorKeyframeTrack('Root.position', [0, 1], [0, 0, 0, 1, 0, 0])]);
    let p, calls = 0; value.rootMotionSink = () => { calls++; p[operation](); };
    p = createMotionPresentation(value); p.setParameters({speed: 5}); p.update(.25);
    check(calls === 1 && value.wheel.rotation.x === 0 && p.stats().particles === 0, operation + ' from controller sink aborts later old-frame writes');
    check(value.root.position.x === 0, 'controller callback cannot leave extracted visual translation applied twice');
    if (operation !== 'dispose') p.dispose();
  }
  f = fixture(THREE); let reentrant, attemptReentry = false;
  f.onPresentationEvent = event => { if (attemptReentry && event.type === 'marker') { attemptReentry = false; rejects(() => reentrant.update(.1), 'host callback cannot reenter the presentation clock'); } };
  reentrant = createMotionPresentation(f); attemptReentry = true; reentrant.update(.25); check(reentrant.state === 'idle', 'rejected nested clock leaves the outer update valid'); reentrant.dispose();
  return {assertions, mode: real ? 'actual-threejs-node' : 'simulated-protocol', threeRevision: THREE.REVISION || 'unavailable:protocol-stub', realRenderer: false, visualAcceptance: false};
}

async function main() {
  const values = process.argv.slice(2);
  if (values.includes('--browser')) { await browserFixture(values); return; }
  const real = values.includes('--real');
  const option = (name, fallback) => { const i = values.indexOf(name); return i >= 0 ? values[i + 1] : fallback; };
  const directory = path.resolve(option('--dependencies', process.env.HEPHAERA_MOTION_DEPENDENCIES || path.join(TASK, 'dependency-audit/browser-fixture/node_modules')));
  let THREE;
  if (real) {
    const modulePath = path.join(directory, 'three/build/three.module.js');
    if (!fs.existsSync(modulePath)) { console.error('BLOCKED: existing Three.js fixture dependency unavailable; no software installed.'); process.exitCode = 77; return; }
    THREE = await import(pathToFileURL(modulePath).href);
  } else THREE = protocolThree();
  const report = await runSuite(THREE, real);
  console.log(`PASS: ${report.assertions} ${report.mode} assertions; no live asset quality or renderer acceptance claimed`);
  const evidence = option('--evidence', null);
  if (evidence) { fs.mkdirSync(path.dirname(path.resolve(evidence)), {recursive: true}); fs.writeFileSync(evidence, JSON.stringify(report, null, 2) + '\n'); }
}

async function browserFixture(values) {
  const http = require('node:http');
  const crypto = require('node:crypto');
  const option = name => { const index = values.indexOf(name); return index >= 0 ? values[index + 1] : null; };
  const configFile = path.resolve(option('--config') || '');
  const isInside = (base, file) => file === base || file.startsWith(base + path.sep);
  const confined = file => {
    const absolute = path.resolve(file);
    if (!isInside(ROOT, absolute)) throw new Error('Fixture file escapes the repository');
    let current = ROOT;
    for (const segment of path.relative(ROOT, absolute).split(path.sep).filter(Boolean)) {
      current = path.join(current, segment);
      if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) throw new Error('Fixture links/junctions are unsupported');
    }
    return absolute;
  };
  confined(configFile);
  const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
  if (config.schemaVersion !== 1 || !Array.isArray(config.packages) || config.packages.length < 1 || config.packages.length > 8) throw new Error('Bounded actual fixture package inventory is required');
  const output = confined(config.output);
  const dependencies = confined(config.dependencies);
  confined(config.projectRoot);
  const evidenceRoot = isInside(config.projectRoot, output) ? config.projectRoot : ROOT;
  if (!isInside(ROOT, output) || !isInside(ROOT, dependencies) || !isInside(ROOT, config.projectRoot)) throw new Error('Browser fixture paths must stay inside the repository');
  if (fs.readdirSync(output).some(name => !['browser-config.json', 'browser.log'].includes(name))) throw new Error('Browser attempt already contains evidence; use a new output directory');
  const packages = config.packages.map(file => {
    confined(file);
    const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
    const model = fs.realpathSync(confined(path.resolve(config.projectRoot, manifest.model.path)));
    if (!isInside(fs.realpathSync(config.projectRoot), model)) throw new Error('Model escapes the fixture project');
    const bytes = fs.readFileSync(model);
    if (crypto.createHash('sha256').update(bytes).digest('hex') !== manifest.model.sha256) throw new Error('Fixture model hash mismatch');
    return {file, manifest, model};
  });
  const chromium = require(path.join(dependencies, 'playwright-core')).chromium;
  const requests = [], blocked = [];
  const fixtures = packages.map((entry, index) => ({package: entry.manifest, modelUrl: `/model/${index}.glb`, name: path.basename(path.dirname(entry.file)), sha256: entry.manifest.model.sha256}));
  const pageSource = browserPage();
  const server = http.createServer((request, response) => {
    const address = new URL(request.url, 'http://127.0.0.1');
    let file = null;
    requests.push(address.pathname);
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    if (address.pathname === '/') { response.setHeader('Content-Type', 'text/html; charset=utf-8'); response.end(pageSource); return; }
    if (address.pathname === '/fixtures.json') { response.setHeader('Content-Type', 'application/json'); response.end(JSON.stringify({fixtures, engineSelection: config.engineSelection})); return; }
    if (address.pathname === '/adapter.mjs') file = ADAPTER;
    else if (/^\/model\/\d+\.glb$/.test(address.pathname)) file = packages[Number(address.pathname.match(/\d+/)[0])]?.model;
    else if (address.pathname.startsWith('/deps/')) {
      const relative = decodeURIComponent(address.pathname.slice(6));
      if (relative.includes('\\') || relative.split('/').some(segment => ['.', '..'].includes(segment))) { response.writeHead(403); response.end(); return; }
      const candidate = path.resolve(dependencies, relative);
      if (isInside(dependencies, candidate) && fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
        const real = fs.realpathSync(confined(candidate));
        if (isInside(fs.realpathSync(dependencies), real)) file = real;
      }
    }
    if (!file || !fs.existsSync(file)) { response.writeHead(404); response.end(); return; }
    response.setHeader('Content-Type', /\.m?js$/.test(file) ? 'text/javascript; charset=utf-8' : file.endsWith('.json') ? 'application/json' : 'model/gltf-binary');
    fs.createReadStream(file).pipe(response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  let context;
  const consoleErrors = [];
  try {
    context = await chromium.launchPersistentContext(path.join(output, 'browser-profile'), {
      executablePath: config.browserExecutable, headless: true, viewport: {width: 720, height: 560}, serviceWorkers: 'block',
      args: ['--disable-background-networking', '--disable-component-update', '--disable-sync', '--no-first-run', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
    });
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.origin === origin || ['data:', 'blob:'].includes(url.protocol)) return route.continue();
      blocked.push(route.request().url()); return route.abort('blockedbyclient');
    });
    const page = await context.newPage();
    page.on('pageerror', error => consoleErrors.push(error.message));
    await page.goto(origin, {waitUntil: 'networkidle'});
    await page.waitForFunction(() => window.__HEPHAERA_MOTION_DONE, null, {timeout: 120000});
    const result = await page.evaluate(() => window.__HEPHAERA_MOTION_RESULT);
    if (result.error) throw new Error(result.error);
    assert.equal(result.status, 'passed'); assert.equal(result.realRenderer, true); assert.ok(result.cases.length);
    const captureFrames = result.captureFrames || [];
    assert.ok(captureFrames.length > 0 && captureFrames.length <= 64, 'bounded actual frame capture discovery');
    const captures = [];
    for (let index = 0; index < captureFrames.length; index++) {
      const frame = captureFrames[index];
      assert.ok(/^data:image\/png;base64,/.test(frame.dataUrl) && frame.dataUrl.length < 8 * 1024 * 1024, 'bounded PNG capture');
      const bytes = Buffer.from(frame.dataUrl.slice(frame.dataUrl.indexOf(',') + 1), 'base64');
      assert.ok(bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])), 'actual PNG signature');
      const name = `runtime-frame-${index.toString().padStart(2, '0')}-${frame.profile}-${String(frame.clip).replace(/[^A-Za-z0-9_-]/g, '_')}.png`;
      const file = path.join(output, name); fs.writeFileSync(file, bytes);
      const {dataUrl, ...metadata} = frame;
      captures.push({...metadata, path: path.relative(evidenceRoot, file).replace(/\\/g, '/'), sha256: crypto.createHash('sha256').update(bytes).digest('hex')});
    }
    delete result.captureFrames;
    result.captures = captures;
    const capture = path.join(output, 'runtime-capture.png');
    const representative = captures.find(item => item.clip === 'run') || captures.find(item => item.clip === 'warp-sustain-effects') || captures[0];
    fs.copyFileSync(path.join(evidenceRoot, representative.path), capture);
    await page.screenshot({path: path.join(output, 'runtime-overview.png'), fullPage: true});
    const network = await page.evaluate(async () => { try { await fetch('https://hephaera-network-test.invalid/blocked'); return false; } catch { return true; } });
    assert.ok(network && blocked.some(url => url.includes('hephaera-network-test.invalid')), 'external browser page request was blocked before transport');
    assert.deepEqual(consoleErrors, [], 'no uncaught browser errors');
    const report = {...result, engine: 'THREEJS', engineSelection: config.engineSelection, adapterSha256: crypto.createHash('sha256').update(fs.readFileSync(ADAPTER)).digest('hex'), nativeInference: false, browserExecutable: config.browserExecutable, fixturePackages: packages.map(entry => ({path: entry.file, sha256: crypto.createHash('sha256').update(fs.readFileSync(entry.file)).digest('hex'), modelSha256: entry.manifest.model.sha256})), requests, blockedRequests: blocked, limits: 'Controlled fixtures; browser request routing is not an OS network sandbox or production human acceptance.'};
    const testPath = path.join(output, 'runtime-test.json'); fs.writeFileSync(testPath, JSON.stringify(report, null, 2) + '\n');
    const perfPath = path.join(output, 'performance-profile.json'); fs.writeFileSync(perfPath, JSON.stringify({schemaVersion: 1, status: 'passed', engine: 'THREEJS', source: 'actual headless browser WebGLRenderer', threeRevision: result.threeRevision, cases: result.cases.map(entry => ({name: entry.name, frames: entry.frames, frameCpuMs: entry.frameCpuMs, peakParticles: entry.peakParticles, rendererInfo: entry.rendererInfo, maxParticleCapacity: entry.maxParticleCapacity})), limitation: 'CPU update/render submission timings and observed renderer counters; not GPU frame timings or target hardware qualification.'}, null, 2) + '\n');
    const evidence = [['runtime-test', testPath], ['runtime-capture', capture], ['performance-profile', perfPath]].map(([kind, file]) => ({kind, path: path.relative(evidenceRoot, file).replace(/\\/g, '/'), sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}));
    fs.writeFileSync(path.join(output, 'engine-evidence.json'), JSON.stringify({schemaVersion: 1, status: 'passed', engine: 'THREEJS', actualBrowser: true, evidenceRoot, pathBase: evidenceRoot === config.projectRoot ? 'project-root' : 'repository-root', evidence}, null, 2) + '\n');
    console.log(`PASS: actual Three.js ${result.threeRevision} browser WebGL fixture, ${result.assertions} assertions, ${result.cases.length} packages; no human acceptance claimed`);
  } finally {
    if (context) await context.close();
    await new Promise(resolve => server.close(resolve));
  }
}

function browserPage() {
  return `<!doctype html><html><head><meta charset="utf-8"><title>Hephaera motion acceptance fixture</title><link rel="icon" href="data:,"><style>body{margin:0;background:#151824;color:#e6ecff;font:15px sans-serif}header{padding:12px}canvas{display:block}pre{white-space:pre-wrap;padding:12px;font-size:12px}</style><script type="importmap">{"imports":{"three":"/deps/three/build/three.module.js","three/addons/":"/deps/three/examples/jsm/"}}</script></head><body><header>Controlled native model-to-animation fixture; no production acceptance</header><main></main><pre id="status">Loading actual staged GLB and host-local Three.js…</pre><script type="module">
import * as THREE from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {clone as cloneSkeleton} from 'three/addons/utils/SkeletonUtils.js';
import {createMotionPresentation} from '/adapter.mjs';
const result={schemaVersion:1,status:'running',realRenderer:true,threeRevision:THREE.REVISION,assertions:0,cases:[],captureFrames:[]};
const check=(value,message)=>{if(!value)throw new Error(message);result.assertions++};
const near=(a,b,t=1e-5)=>Math.abs(a-b)<=t;
const lookup=(root,name)=>{const original=[],runtime=[];root.traverse(n=>{if(n.userData?.name===name)original.push(n);if(n.name===name)runtime.push(n)});const found=original.length?original:runtime;if(found.length!==1)throw new Error('Ambiguous/missing exported node '+name);return found[0]};
const hash=async bytes=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(v=>v.toString(16).padStart(2,'0')).join('');
const observeSkin=root=>{const values=[];root.updateMatrixWorld(true);root.traverse(node=>{if(node.isSkinnedMesh){node.skeleton.update();const count=node.geometry.attributes.position.count;for(let i=0;i<count;i+=Math.max(1,Math.ceil(count/96))){const p=new THREE.Vector3();node.getVertexPosition(i,p);values.push(...p.toArray())}}});return values};
const metrics=values=>{const sorted=[...values].sort((a,b)=>a-b);return{median:sorted[Math.floor(sorted.length/2)],p95:sorted[Math.floor(sorted.length*.95)],max:Math.max(...sorted)}};
const renderer=new THREE.WebGLRenderer({antialias:false,preserveDrawingBuffer:true});renderer.setSize(720,430);renderer.setPixelRatio(1);document.querySelector('main').append(renderer.domElement);renderer.setClearColor('#151824');
const scene=new THREE.Scene();scene.add(new THREE.HemisphereLight(0xe7efff,0x34384a,2));const light=new THREE.DirectionalLight(0xffffff,3);light.position.set(3,5,4);scene.add(light);const camera=new THREE.PerspectiveCamera(42,720/430,.01,10000);
try{
 const config=await fetch('/fixtures.json').then(r=>r.json());check(config.fixtures.length>0,'No actual package discovery');
 for(const fixture of config.fixtures){
  const pkg=fixture.package,bytes=await fetch(fixture.modelUrl).then(r=>{if(!r.ok)throw new Error('Model fetch failed');return r.arrayBuffer()});check(await hash(bytes)===fixture.sha256,'Browser consumed different GLB bytes');
  const gltf=await new GLTFLoader().parseAsync(bytes,location.origin+'/');const world=new THREE.Group();world.name='fixture-authority';scene.add(world);const visual=gltf.scene;world.add(visual);const box=new THREE.Box3().setFromObject(visual),size=box.getSize(new THREE.Vector3()),center=box.getCenter(new THREE.Vector3());const distance=Math.max(size.x,size.y,size.z,1)*2.4;
  const focus=()=>{const c=center.clone().add(world.position);camera.position.copy(c).add(new THREE.Vector3(distance*.7,distance*.45,distance));camera.lookAt(c)};focus();renderer.render(scene,camera);const initialPixel=renderer.domElement.toDataURL();
  check(pkg.coordinateSystem?.runtimeUp==='+Y'&&pkg.coordinateSystem?.runtimeForward==='+Z','Runtime axes differ from exported Y-up/front+Z contract');
  let meshes=0,skins=0;visual.traverse(node=>{if(node.isMesh)meshes++;if(node.isSkinnedMesh){skins++;check(node.skeleton.bones.length>0,'Empty actual skeleton');check(node.geometry.attributes.skinWeight&&node.geometry.attributes.skinIndex,'Actual skin attributes missing')}});check(meshes>0,'Empty imported mesh discovery');if(pkg.profile==='skinned')check(skins>0,'Skinned package imported no real skinned meshes');
  const anchors=[];for(const anchor of pkg.anchors){const node=lookup(visual,anchor.node);anchors.push({id:anchor.id,runtimeName:node.name,exportedName:node.userData?.name||node.name});if(pkg.profile==='rigid'&&anchor.id.includes('exhaust')&&anchor.position){const expected=[anchor.position[0],anchor.position[2],-anchor.position[1]];check(node.position.toArray().every((v,i)=>near(v,expected[i])),'Exhaust anchor did not preserve native->glTF direction/offset')}}
  const modelRootBefore=world.position.clone();const clock=[],events=[],extracted=[];let frameExtraction=new THREE.Vector3();const rootBone=pkg.rig?.rootBone||pkg.rig?.rootNode;const extractionNode=rootBone?lookup(visual,rootBone):null;const extractionRest=extractionNode?.position.clone();const presentation=createMotionPresentation({THREE,visualRoot:visual,movementRoot:world,effectParent:scene,animations:gltf.animations,motionPackage:pkg,engineSelection:config.engineSelection,onPresentationEvent:e=>events.push(e),rootMotionSink:event=>{check(event.translation.length===3&&event.translation.every(Number.isFinite),'Controller received invalid extracted translation');const delta=new THREE.Vector3().fromArray(event.translation);frameExtraction.add(delta);world.position.add(delta);extracted.push(event)}});let frames=0,peak=0;let changedPose=false;const stateFor=clip=>pkg.states.find(s=>s.clip===clip.id);
  const renderStep=dt=>{const before=world.position.clone(),rootBefore=extractionNode?.getWorldPosition(new THREE.Vector3()),start=performance.now();frameExtraction.set(0,0,0);presentation.update(dt);focus();renderer.render(scene,camera);clock.push(performance.now()-start);frames++;peak=Math.max(peak,presentation.stats().particles);check(world.position.clone().sub(before).distanceTo(frameExtraction)<1e-9,'Presentation changed movement beyond the explicit controller-owned extraction sink');const activeClip=pkg.clips.find(c=>c.id===pkg.states.find(s=>s.id===presentation.state)?.clip);if(activeClip?.rootMotion==='extract'&&dt>0){check(extractionNode.position.distanceTo(extractionRest)<1e-6,'Extracted root retained duplicate visual translation');check(extractionNode.getWorldPosition(new THREE.Vector3()).sub(rootBefore).distanceTo(frameExtraction)<1e-5,'Extracted world motion was applied more than once')}check(presentation.stats().particles<=presentation.stats().particleCapacity,'Effects exceeded actual allocated capacity')};
  for(const clip of pkg.clips){const imported=gltf.animations.find(a=>a.name===(clip.action||clip.id));check(imported&&imported.tracks.length>0,'Actual clip channels missing '+clip.id);const state=stateFor(clip);check(state,'No presentation state for exported clip '+clip.id);presentation.reset(state.id);renderStep(0);const before=observeSkin(visual);for(let i=0;i<11;i++)renderStep(clip.duration*.37/11);const after=observeSkin(visual);if(before.length&&after.some((v,i)=>Math.abs(v-before[i])>1e-5))changedPose=true;result.captureFrames.push({profile:pkg.profile,name:fixture.name,clip:clip.id,modelSha256:fixture.sha256,time:clip.duration*.37,dataUrl:renderer.domElement.toDataURL()});for(const binding of clip.bindings||[])lookup(visual,binding.node);const stateBefore=presentation.state;for(let t=clip.duration*.37;t<clip.duration+.1;t+=1/30)renderStep(Math.min(1/30,clip.duration+.1-t));check(presentation.state===stateBefore,'Clip completion changed authoritative presentation request');}
  if(pkg.profile==='skinned')check(changedPose,'Actual skinned vertices never deformed across required motion samples');
  presentation.reset();const speed=pkg.parameters.find(p=>p.id==='speed');if(speed){presentation.setParameters({speed:speed.max});for(let i=0;i<20;i++){world.position.z+=speed.max/60;renderStep(1/60)}}
  const requestPath=target=>{const queue=[{state:presentation.state,path:[]}],seen=new Set();while(queue.length){const entry=queue.shift();if(entry.state===target){for(const edge of entry.path)check(presentation.dispatch(edge.trigger)&&presentation.state===edge.to,'Declared phase transition failed');return true}if(seen.has(entry.state))continue;seen.add(entry.state);for(const edge of pkg.transitions.filter(t=>t.from===entry.state))queue.push({state:edge.to,path:[...entry.path,edge]})}return false};
  const enter=pkg.states.find(s=>s.id==='warp-enter'),sustain=pkg.states.find(s=>s.id==='warp-sustain');if(enter&&sustain){presentation.reset();check(requestPath(enter.id),'Native warp-enter request path missing');if(speed)presentation.setParameters({speed:speed.max});for(let i=0;i<12;i++)renderStep(1/30);check(presentation.state===enter.id,'Timer/clip completion advanced warp without authoritative request');const cancel=pkg.transitions.find(t=>t.from===enter.id&&t.trigger==='cancel');check(cancel&&presentation.dispatch(cancel.trigger),'Declared warp-entry cancellation missing');check(presentation.stats().particles===0,'Warp cancellation retained old effect ownership');check(requestPath(enter.id),'Warp retry path missing');const toSustain=pkg.transitions.find(t=>t.from===enter.id&&t.to===sustain.id);check(toSustain&&presentation.dispatch(toSustain.trigger),'Native warp-sustain request missing');for(let i=0;i<12;i++)renderStep(1/30);check(presentation.stats().particles>0,'Actual warp speed effects emitted no particles');result.captureFrames.push({profile:pkg.profile,name:fixture.name,clip:'warp-sustain-effects',modelSha256:fixture.sha256,time:presentation.stats().mixerTime,dataUrl:renderer.domElement.toDataURL()});const exit=pkg.transitions.find(t=>t.from===sustain.id&&t.to==='warp-exit');check(exit&&presentation.dispatch(exit.trigger),'Declared warp-exit transition missing');const settle=pkg.transitions.find(t=>t.from==='warp-exit'&&['cruise','idle'].includes(t.to));check(settle&&presentation.dispatch(settle.trigger),'Declared warp settling request missing');}
  const driven=pkg.parameters.flatMap(p=>(p.bindings||[]).map(binding=>({p,binding})));for(const {p,binding}of driven){const node=lookup(visual,binding.node),before=node[binding.property][binding.axis];presentation.setParameters({[p.id]:p.max});renderStep(.1);check(Math.abs(node[binding.property][binding.axis]-before)>1e-6,'Mechanical parameter did not drive actual node '+binding.node)}
  const paused=presentation.stats().mixerTime;presentation.setPaused(true);renderStep(.1);check(presentation.stats().mixerTime===paused,'Pause changed actual animation clock');presentation.setPaused(false);presentation.setReducedMotion(true);renderStep(.1);check(presentation.stats().particles===0||pkg.effects.some(e=>(e.reducedMotionScale||0)>0),'Reduced motion retained unbounded/high-motion effect');presentation.setReducedMotion(false);
  const token=presentation.generation;presentation.reset();const possible=pkg.transitions.find(t=>t.from===presentation.state);if(possible)check(!presentation.dispatch(possible.trigger,token),'Prior-generation request affected respawned actor');
  const clone=cloneSkeleton(visual);let originalBone=null,clonedBone=null;visual.traverse(n=>{if(n.isBone&&!originalBone)originalBone=n});clone.traverse(n=>{if(n.isBone&&!clonedBone)clonedBone=n});if(originalBone){check(clonedBone&&originalBone!==clonedBone,'Skeleton-aware duplicate shares mutable bone');const old=originalBone.rotation.x;clonedBone.rotation.x+=.2;check(originalBone.rotation.x===old,'Duplicate pose mutated original actor')}
  const pixelAfter=renderer.domElement.toDataURL();check(initialPixel!==pixelAfter,'No actual rendered image change observed');const beforeDispose=renderer.info.memory.geometries;presentation.dispose();renderer.render(scene,camera);const afterDispose=renderer.info.memory.geometries;check(afterDispose<=beforeDispose,'Disposal grew native renderer geometry inventory');check(presentation.stats().particles===0,'Disposal left particles');
  if(pkg.clips.some(c=>c.rootMotion==='extract'))check(extracted.some(e=>new THREE.Vector3().fromArray(e.translation).length()>1e-5),'Actual extracted clip produced no controller-owned displacement');
  const item={name:fixture.name,profile:pkg.profile,modelSha256:fixture.sha256,clips:pkg.clips.map(c=>c.id),anchors,skinnedMeshes:skins,actualSkinnedVertexChange:changedPose,extraction:{samples:extracted.length,total:extracted.reduce((sum,e)=>sum.add(new THREE.Vector3().fromArray(e.translation)),new THREE.Vector3()).toArray(),authority:'explicit host controller sink; local extracted root reset each frame'},frames,frameCpuMs:metrics(clock),peakParticles:peak,maxParticleCapacity:presentation.stats().particleCapacity,rendererInfo:{calls:renderer.info.render.calls,triangles:renderer.info.render.triangles,points:renderer.info.render.points,geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures},movementObserved:world.position.distanceTo(modelRootBefore)};result.cases.push(item);document.querySelector('#status').textContent=JSON.stringify({...result,captureFrames:result.captureFrames.map(({dataUrl,...metadata})=>metadata)},null,2);world.removeFromParent();
 }
 check(result.cases.length===config.fixtures.length,'Incomplete actual package results');result.status='passed';window.__HEPHAERA_MOTION_RESULT=result;
}catch(error){window.__HEPHAERA_MOTION_RESULT={...result,status:'failed',error:error.stack}}finally{const {captureFrames,...summary}=window.__HEPHAERA_MOTION_RESULT;document.querySelector('#status').textContent=JSON.stringify({...summary,captureFrames:captureFrames.map(({dataUrl,...metadata})=>metadata)},null,2);window.__HEPHAERA_MOTION_DONE=true}
</script></body></html>`;
}
if (require.main === module) main().catch(error => { console.error(error.stack); process.exitCode = 1; });
module.exports = {packageData, selection, fixture, runSuite};
