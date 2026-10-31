// Independently authored bounded starter integration; host supplies locked libraries.
export const VERIFIED_VERSIONS = Object.freeze({three: '0.182.0', threeQuarks: '0.17.1', quarksCore: '0.17.1'});
const owners = new WeakMap();
const fail = message => { throw new Error(message); };
const finite = (value, low, high, name) => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < low || value > high) fail(`${name} must be finite within ${low}..${high}.`);
  return value;
};
const integer = (value, low, high, name) => {
  finite(value, low, high, name);
  if (!Number.isSafeInteger(value)) fail(`${name} must be an integer.`);
  return value;
};
function sameScene(node, scene) {
  const seen = new Set();
  while (node?.parent) {
    if (seen.has(node)) return false;
    seen.add(node); node = node.parent;
  }
  return node === scene;
}
function recipe(input, maxDelta, maxParticles) {
  const allowed = ['id', 'kind', 'capacity', 'rate', 'count', 'lifetime', 'duration', 'looping', 'size', 'speed', 'color', 'space', 'parent', 'material', 'shape', 'radius', 'autoStart'];
  if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some(key => !allowed.includes(key))) fail('Unknown or invalid particle recipe fields.');
  if (typeof input.id !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(input.id)) fail('A safe unique emitter id is required.');
  const kind = input.kind ?? 'rate';
  if (!['rate', 'burst'].includes(kind)) fail('kind must be rate or burst.');
  const capacity = integer(input.capacity, 1, Math.min(16384, maxParticles), 'capacity');
  const lifetime = finite(input.lifetime ?? 1, .001, 60, 'lifetime');
  const rate = finite(input.rate ?? (kind === 'rate' ? 10 : 0), 0, 10000, 'rate');
  const count = integer(input.count ?? (kind === 'burst' ? 10 : 0), 0, capacity, 'count');
  if ((kind === 'burst' && rate !== 0) || (kind === 'rate' && count !== 0)) fail('Choose time emission or one bounded burst, not both.');
  if (kind === 'rate' && Math.ceil(rate * (lifetime + maxDelta)) + 2 > capacity) fail('capacity must cover rate * (lifetime + maxDelta), rounded up, plus two safety particles.');
  const duration = finite(input.duration ?? 1, .001, 3600, 'duration');
  const looping = input.looping ?? kind === 'rate';
  if (typeof looping !== 'boolean' || (kind === 'burst' && looping)) fail('looping must be boolean; burst emitters cannot loop.');
  const shape = input.shape ?? 'point';
  if (!['point', 'sphere'].includes(shape)) fail('The starter supports point and sphere shapes only.');
  const space = input.space ?? 'world';
  if (!['world', 'local'].includes(space)) fail('space must be world or local.');
  const color = input.color ?? [1, 1, 1, 1];
  if (!Array.isArray(color) || color.length !== 4) fail('color must contain four linear RGBA values.');
  color.forEach(value => finite(value, 0, 1, 'color component'));
  if (input.autoStart !== undefined && typeof input.autoStart !== 'boolean') fail('autoStart must be boolean.');
  return Object.freeze({...input, kind, capacity, lifetime, rate, count, duration, looping, shape, space,
    size: finite(input.size ?? .1, .0001, 1000, 'size'), speed: finite(input.speed ?? 1, 0, 10000, 'speed'),
    radius: finite(input.radius ?? 1, 0, 10000, 'radius'), color: Object.freeze([...color]), autoStart: input.autoStart ?? true});
}

/** Scene-owned WebGL starter. No scheduler, package loader or gameplay callbacks. */
export function createThreeQuarksRuntime({THREE, Quarks, scene, renderer, engineSelection, maxSystems = 32, maxParticles = 65536, maxDelta = .1} = {}) {
  if (engineSelection?.effectiveEngine !== 'THREEJS' || engineSelection?.particles?.package !== 'three.quarks') fail('Resolve THREEJS with its selected three.quarks capability first.');
  if (!THREE || !/^\d+$/.test(String(THREE.REVISION)) || Number(THREE.REVISION) < 182) fail('The verified Quarks package requires Three.js r182 or newer.');
  for (const key of ['BatchedRenderer', 'ParticleSystem', 'ConstantValue', 'ConstantColor', 'PointEmitter', 'SphereEmitter']) if (typeof Quarks?.[key] !== 'function') fail(`Missing Quarks API ${key}; verify the installed package pair.`);
  if (Quarks?.RenderMode?.BillBoard !== 0 || typeof THREE.PlaneGeometry !== 'function' || typeof THREE.MeshBasicMaterial !== 'function') fail('Unsupported particle API surface.');
  if (!scene?.isScene || scene.type !== 'Scene' || typeof scene.add !== 'function' || typeof scene.updateMatrixWorld !== 'function') fail('An actual Three.js Scene is required.');
  if (renderer?.isWebGLRenderer !== true || renderer?.isWebGPURenderer === true) fail('This particle integration requires WebGLRenderer; WebGPU is not selected or substituted.');
  integer(maxSystems, 1, 128, 'maxSystems'); integer(maxParticles, 1, 65536, 'maxParticles'); finite(maxDelta, .001, .25, 'maxDelta');
  if (owners.has(scene)) fail('This scene already has an owned Quarks runtime.');
  let existing = false;
  scene.traverse(node => { if (node.type === 'BatchedRenderer') existing = true; });
  if (existing) fail('The scene already contains a BatchedRenderer; share its owner instead of creating another.');

  const batchRenderer = new Quarks.BatchedRenderer();
  if (!Array.isArray(batchRenderer.batches) || !(batchRenderer.systemToBatchIndex instanceof Map) || typeof batchRenderer.deleteSystem !== 'function') fail('Unsupported BatchedRenderer ownership API.');
  const geometry = new THREE.PlaneGeometry(1, 1);
  const defaultMaterial = new THREE.MeshBasicMaterial({transparent: true, depthWrite: false});
  const records = new Map();
  let disposed = false, paused = false, updating = false, allocated = 0, elapsed = 0, generation = 0, quality = 2, reducedMotion = false;
  owners.set(scene, batchRenderer); scene.add(batchRenderer);
  const alive = () => { if (disposed) fail('Particle runtime is disposed.'); };
  const recordAlive = record => !disposed && !record.disposed && records.get(record.id) === record;

  function releaseEmptyBatches() {
    // These collections and dispose() are public in the verified 0.17.1 API.
    for (let i = batchRenderer.batches.length - 1; i >= 0; i--) {
      const batch = batchRenderer.batches[i];
      if (batch.systems.size) continue;
      const materials = new Set([batch.material, batch.settings.material]);
      batch.dispose(); // SpriteBatch.dispose releases its generated geometry only.
      for (const material of materials) material.dispose();
      batchRenderer.remove(batch); batchRenderer.batches.splice(i, 1);
    }
    batchRenderer.systemToBatchIndex.clear();
    batchRenderer.batches.forEach((batch, index) => { for (const system of batch.systems) batchRenderer.systemToBatchIndex.set(system, index); });
  }
  function updateEmission(record) {
    const scale = [0, .5, 1][quality] * (reducedMotion ? .25 : 1);
    record.currentRate = record.config.rate * scale;
    record.rate.value = record.currentRate;
    if (record.burst) record.burst.value = Math.floor(record.config.count * scale);
    record.system.emitter.visible = quality !== 0;
  }
  function stop(record) {
    if (!recordAlive(record)) return false;
    record.system.stop(); record.active = false; record.elapsed = 0; record.generation++;
    return true;
  }
  function remove(record) {
    if (!recordAlive(record)) return false;
    stop(record); record.system.dispose();
    record.system.particles.length = 0; // Release the pool this helper alone created.
    records.delete(record.id); allocated -= record.config.capacity; record.disposed = true;
    releaseEmptyBatches();
    return true;
  }
  function assertOwnedConfiguration(record) {
    const s = record.system, c = record.config;
    if (s.emissionOverTime !== record.rate || record.rate.value !== record.currentRate || s.startLife !== record.life || record.life.value !== c.lifetime || s.emissionOverDistance !== record.distance || record.distance.value !== 0 || s.emissionBursts !== record.bursts || s.behaviors.length !== 0 || s.prewarm || s.autoDestroy || s.onlyUsedByOther || s.duration !== c.duration || s.looping !== c.looping || s.worldSpace !== (c.space === 'world') || s.getRendererSettings().material !== record.material || s.getRendererSettings().instancingGeometry !== geometry) fail('Owned particle configuration was mutated outside the helper; remove and recreate an explicitly reviewed emitter.');
    if ((!record.burst && record.bursts.length !== 0) || (record.burst && (record.bursts.length !== 1 || record.bursts[0].count !== record.burst || record.burst.value !== record.currentCount || record.bursts[0].time !== 0 || record.bursts[0].probability !== 1))) fail('Owned burst configuration changed.');
  }
  function createEmitter(input) {
    alive(); if (updating) fail('Cannot change particle inventory during update.');
    const c = recipe(input, maxDelta, maxParticles);
    if (records.has(c.id)) fail('Emitter id already exists.');
    if (records.size >= maxSystems || allocated + c.capacity > maxParticles) fail('Scene particle/system capacity exceeded.');
    const parent = c.parent ?? scene;
    if (!parent?.isObject3D || !sameScene(parent, scene)) fail('Emitter parent must be attached beneath the owned Scene.');
    const material = c.material ?? defaultMaterial;
    if (!material?.isMeshBasicMaterial || typeof material.clone !== 'function' || typeof material.dispose !== 'function') fail('The bounded billboard starter accepts a borrowed MeshBasicMaterial.');
    const rate = new Quarks.ConstantValue(c.rate), life = new Quarks.ConstantValue(c.lifetime), distance = new Quarks.ConstantValue(0);
    const burst = c.kind === 'burst' ? new Quarks.ConstantValue(c.count) : null;
    const bursts = burst ? [{time: 0, count: burst, cycle: 1, interval: 0, probability: 1}] : [];
    const system = new Quarks.ParticleSystem({duration: c.duration, looping: c.looping, prewarm: false, autoDestroy: false,
      startLife: life, startSpeed: new Quarks.ConstantValue(c.speed), startSize: new Quarks.ConstantValue(c.size),
      startColor: new Quarks.ConstantColor(new THREE.Vector4(...c.color)), emissionOverTime: rate, emissionOverDistance: distance,
      emissionBursts: bursts, behaviors: [], shape: c.shape === 'sphere' ? new Quarks.SphereEmitter({radius: c.radius}) : new Quarks.PointEmitter(),
      worldSpace: c.space === 'world', material, instancingGeometry: geometry, renderMode: Quarks.RenderMode.BillBoard});
    const record = {id: c.id, config: c, system, rate, life, distance, burst, bursts, material, currentRate: c.rate, currentCount: c.count, active: c.autoStart, elapsed: 0, generation: 0, disposed: false};
    try {
      parent.add(system.emitter); batchRenderer.addSystem(system);
      // addSystem already uses the current settings. Clearing this public flag
      // avoids Quarks deleting/readding the Map key inside its first update.
      system.neededToUpdateRender = false;
      records.set(c.id, record); allocated += c.capacity;
      updateEmission(record); record.currentCount = burst?.value ?? 0;
      if (!c.autoStart) system.stop();
    } catch (error) {
      system.dispose(); releaseEmptyBatches(); throw error;
    }
    const tokenValid = token => token === undefined || token === record.generation;
    return Object.freeze({
      id: c.id, emitter: system.emitter,
      get generation() { return record.generation; },
      play(token) { if (!recordAlive(record) || !tokenValid(token)) return false; record.active = true; system.play(); return true; },
      pause(token) { if (!recordAlive(record) || !tokenValid(token)) return false; system.pause(); return true; },
      restart(token) { if (!recordAlive(record) || !tokenValid(token)) return false; system.restart(); record.generation++; record.elapsed = 0; record.active = true; return true; },
      stop(token) { return tokenValid(token) && stop(record); },
      clear(token) { return tokenValid(token) && stop(record); },
      dispose(token) { return tokenValid(token) && remove(record); },
      stats() { return Object.freeze({id: c.id, disposed: !recordAlive(record), generation: record.generation, active: recordAlive(record) && record.active, paused: system.paused, particles: system.particleNum, pooledParticles: system.particles.length, capacity: c.capacity, time: record.elapsed}); }
    });
  }
  function update(deltaSeconds) {
    alive(); finite(deltaSeconds, 0, maxDelta, 'deltaSeconds');
    if (updating) fail('Particle update cannot be reentrant.');
    if (paused || deltaSeconds === 0) return api.stats();
    for (const record of records.values()) {
      if (!sameScene(record.system.emitter, scene)) { remove(record); fail('An owned emitter left its Scene; it has been released.'); }
      assertOwnedConfiguration(record);
    }
    updating = true;
    try {
      const steps = Math.ceil(deltaSeconds / .1), step = deltaSeconds / steps;
      for (let i = 0; i < steps; i++) {
        scene.updateMatrixWorld(true);
        batchRenderer.update(step);
        for (const record of records.values()) {
          if (record.system.particleNum > record.config.capacity || record.system.particles.length > record.config.capacity) { remove(record); fail('Particle capacity was breached; the offending owned system was released.'); }
          if (record.active && !record.system.paused) {
            record.elapsed += step;
            if (!record.config.looping && record.elapsed >= record.config.duration + record.config.lifetime + .1) stop(record);
          }
        }
      }
      elapsed += deltaSeconds;
    } finally { updating = false; }
    return api.stats();
  }
  const api = Object.freeze({
    createEmitter, update,
    pause() { alive(); paused = true; }, resume() { alive(); paused = false; },
    clear() { alive(); for (const record of records.values()) stop(record); generation++; },
    reset() { alive(); for (const record of records.values()) stop(record); elapsed = 0; generation++; },
    remove(id) { alive(); const record = records.get(id); return record ? remove(record) : false; },
    setQuality(value) { alive(); integer(value, 0, 2, 'quality'); quality = value; for (const record of records.values()) { updateEmission(record); record.currentCount = record.burst?.value ?? 0; } },
    setReducedMotion(value) { alive(); if (typeof value !== 'boolean') fail('reducedMotion must be boolean.'); reducedMotion = value; for (const record of records.values()) { updateEmission(record); record.currentCount = record.burst?.value ?? 0; } },
    stats() { return Object.freeze({disposed, paused, generation, systems: records.size, capacity: allocated, particles: [...records.values()].reduce((n, r) => n + r.system.particleNum, 0), pooledParticles: [...records.values()].reduce((n, r) => n + r.system.particles.length, 0), batches: batchRenderer.batches.length, time: elapsed, quality, reducedMotion}); },
    dispose() {
      if (disposed) return;
      for (const record of [...records.values()]) remove(record);
      releaseEmptyBatches(); batchRenderer.removeFromParent(); geometry.dispose(); defaultMaterial.dispose();
      owners.delete(scene); disposed = true; generation++;
    }
  });
  return api;
}
