/* OpenCaw action presentation. Host-owned Three.js, assets and gameplay.
 * No imports, network, providers, installation or authoritative simulation.
 * Lifecycle/identity rules follow OpenCaw's existing motion presentation.
 */
const EPS = 1e-8;
const activeRoots = new WeakMap();
const number = (v, label) => { if (typeof v !== 'number' || !Number.isFinite(v)) throw new Error(`${label} must be finite`); return v; };
const bounded = (v, min, max, label) => { number(v, label); if (v < min || v > max) throw new Error(`${label} exceeds ${min}..${max}`); return v; };
const integer = (v, min, max, label) => { bounded(v, min, max, label); if (!Number.isInteger(v)) throw new Error(`${label} must be an integer`); return v; };
const text = (v, label) => { if (typeof v !== 'string' || !v.trim()) throw new Error(`${label} is required`); return v; };
const id = (v, label) => { text(v, label); if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$/.test(v) || v === '..') throw new Error(`Invalid ${label}`); return v; };
const hash = (v, label) => { if (typeof v !== 'string' || !/^[a-f0-9]{64}$/.test(v)) throw new Error(`${label} requires SHA-256`); return v; };
const vector = (v, label) => { if (!Array.isArray(v) || v.length !== 3) throw new Error(`${label} requires xyz`); return v.map(x => number(x, label)); };
const list = (v, label) => { if (!Array.isArray(v)) throw new Error(`${label} must be an array`); return v; };
const unique = (values, label) => { const map = new Map(); for (const value of list(values, label)) { if (!value || typeof value !== 'object') throw new Error(`Invalid ${label}`); id(value.id, `${label}.id`); if (map.has(value.id)) throw new Error(`Duplicate ${label}: ${value.id}`); map.set(value.id, value); } return map; };
const copy = value => JSON.parse(JSON.stringify(value));
const frameAligned = (time, fps) => Math.abs(time * fps - Math.round(time * fps)) < 1e-5;

function origins(value, key = '') {
  if (Array.isArray(value)) value.forEach(child => origins(child, key));
  else if (value && typeof value === 'object') Object.entries(value).forEach(([name, child]) => origins(child, name.replace(/[-_]/g, '').toLowerCase()));
  else if (typeof value === 'string') {
    if (/^(provider|vendor|tool|authoringtool|sourceprovider|sourcetool|createdwith|generator)$/.test(key)
      && /\b(adobe|mixamo|firefly|photoshop|illustrator|after\s+effects|substance(?:\s*3d|\s+painter|\s+designer)?)\b/i.test(value)) throw new Error('Excluded authoring/provider provenance');
    if (/^(source|sourceuri|sourceurl|origin|sourceorigin|url)$/.test(key)) {
      if (/^\s*(adobe|mixamo|firefly|adobe\s+(mixamo|firefly|photoshop|illustrator)|substance(?:\s*3d|\s+painter|\s+designer)?)\s*$/i.test(value)) throw new Error('Excluded source provenance');
      let url; try { url = new URL(value); } catch { return; }
      if (/(^|\.)(adobe\.com|adobe\.io|mixamo\.com|substance3d\.com)$/i.test(url.hostname)) throw new Error('Excluded source provenance');
    }
  }
}

/** Pure preflight of the compiled, exported handoff; caller verifies file hashes. */
export function validateActionPresentation(input, selection) {
  if (selection?.effectiveEngine !== 'THREEJS') throw new Error('Resolve THREEJS before using this adapter');
  hash(selection.definitionSha256, 'engine definition'); hash(selection.registrySha256, 'engine registry');
  if (selection.selectionSource !== 'default') hash(selection.contractSha256, 'engine contract');
  if (input?.schemaVersion !== 'opencaw-action-package/v1') throw new Error('Expected opencaw-action-package/v1');
  if (!['skinned', 'articulated', 'rigid'].includes(input.profile)) throw new Error('Unknown action profile');
  if (input.engine?.effectiveEngine !== 'THREEJS') throw new Error('Package engine conflicts with current selection');
  for (const field of ['contractSha256', 'definitionSha256', 'registrySha256']) if (input.engine[field] !== selection[field]) throw new Error(`Stale package engine ${field}`);
  integer(input.fps, 1, 120, 'fps');
  if (input.coordinateSystem?.runtimeUp !== '+Y' || input.coordinateSystem?.runtimeForward !== '+Z') throw new Error('Explicit glTF runtime coordinates required');
  hash(input.model?.sha256, 'model'); text(input.model?.path, 'model path');
  hash(input.sourceMotion?.packageSha256, 'source motion package'); hash(input.sourceMotion?.modelSha256, 'source model');
  text(input.sourceMotion?.rigId, 'source rig identity');
  const rig = input.rig;
  if (!rig || !(rig.rootBone || rig.rootNode)) throw new Error('Actual source root identity required for in-place verification');
  origins(input.provenance); origins(input.sourceMotion);
  const data = copy(input), budgets = data.budgets || {};
  const limits = {maxActions: [1, 128], maxStepsPerAction: [1, 1024], maxExpandedSteps: [1, 4096], maxActionSeconds: [1 / 120, 3600], maxEffects: [1, 256], maxParticles: [1, 65536], maxFrames: [1, 1000000], maxReviewFrames: [1, 10000], maxRuntimeBytes: [1, 1073741824], timeoutSeconds: [1, 86400], maxLogBytes: [1024, 1073741824], maxAttempts: [1, 100]};
  for (const [name, [min, max]] of Object.entries(limits)) (name === 'maxActionSeconds' ? bounded : integer)(budgets[name], min, max, name);
  const sourceClips = unique(data.sourceMotion.clips, 'source clips');
  for (const clip of sourceClips.values()) { hash(clip.motionSha256, 'source clip'); if (clip.rootMotion && clip.rootMotion !== 'in-place') throw new Error('Action composition requires in-place source clips; author an in-place counterpart'); }
  const anchors = unique(data.anchors, 'anchors');
  for (const anchor of anchors.values()) text(anchor.node, 'actual anchor node');
  const targets = unique(data.targets, 'targets');
  for (const target of targets.values()) { if (target.mode !== 'fixed-world-point') throw new Error('Only explicit fixed world targets are supported'); bounded(target.maxDistance, .001, 1e6, 'target distance'); }
  const actions = unique(data.actions, 'actions');
  if (!actions.size || actions.size > budgets.maxActions) throw new Error('Action inventory exceeds budget');
  for (const action of actions.values()) {
    text(action.role, 'action role'); id(action.clip, 'composite clip'); hash(action.motionSha256, 'composite motion');
    bounded(action.duration, 1 / data.fps, budgets.maxActionSeconds, 'action duration');
    if (!frameAligned(action.duration, data.fps) || action.duration * data.fps + 1 > budgets.maxFrames) throw new Error('Action frame budget or bake alignment violated');
    if (action.rootMotion && action.rootMotion !== 'in-place') throw new Error('Action root extraction requires a separately implemented movement adapter');
    const steps = list(action.steps, 'expanded steps');
    if (!steps.length || steps.length > budgets.maxExpandedSteps) throw new Error('Expanded step budget violated');
    const stepIds = new Set(), identities = new Set(); let previous;
    for (const step of steps) {
      id(step.id, 'step'); id(step.clip, 'source clip'); integer(step.occurrence, 0, 15, 'step occurrence');
      const key = `${step.id}:${step.occurrence}`; if (identities.has(key)) throw new Error('Duplicate expanded step'); identities.add(key); stepIds.add(step.id);
      if (!sourceClips.has(step.clip) || sourceClips.get(step.clip).motionSha256 !== step.motionSha256) throw new Error('Source step identity is stale');
      bounded(step.start, 0, action.duration, 'step start'); bounded(step.end, step.start + EPS, action.duration, 'step end');
      bounded(step.sourceStart, 0, 3600, 'source trim start'); bounded(step.sourceEnd, step.sourceStart + EPS, 3600, 'source trim end');
      bounded(step.rate, .1, 4, 'source rate'); bounded(step.blendIn, 0, 30, 'step blend');
      if (Math.abs((step.sourceEnd - step.sourceStart) / step.rate - (step.end - step.start)) > 1e-5) throw new Error('Step span does not match trim/rate');
      if (!frameAligned(step.start, data.fps) || !frameAligned(step.end, data.fps)) throw new Error('Step bake alignment violated');
      if (!previous && (step.start !== 0 || step.blendIn !== 0)) throw new Error('First step must start at zero without blend');
      if (previous && (Math.abs(step.start - (previous.end - step.blendIn)) > 1e-5 || step.blendIn >= Math.min(previous.end - previous.start, step.end - step.start) - EPS)) throw new Error('Step continuity/overlap invalid');
      if (previous && step.start < previous.start - EPS) throw new Error('Step order reversed');
      const earlier = steps[steps.indexOf(step) - 2]; if (earlier && step.start < earlier.end - EPS) throw new Error('Triple overlaps are unsupported');
      previous = step;
    }
    if (stepIds.size > budgets.maxStepsPerAction || Math.abs(previous.end - action.duration) > 1e-5) throw new Error('Step inventory/end does not match action');
    const cues = unique(action.cues, 'cues'); let particles = 0;
    if (cues.size > budgets.maxEffects) throw new Error('Effect budget violated');
    for (const cue of cues.values()) {
      if (!['orb', 'particles', 'projectile'].includes(cue.type)) throw new Error('Unknown action cue type');
      if (!anchors.has(cue.anchor)) throw new Error('Missing action cue anchor');
      bounded(cue.start, 0, action.duration, 'cue start'); bounded(cue.end, cue.start + EPS, action.duration, 'cue end');
      if (!/^#[a-f0-9]{6}$/i.test(cue.color)) throw new Error('Cue color must be #RRGGBB');
      bounded(cue.radius, .001, 10, 'cue radius');
      if (cue.type === 'particles') { integer(cue.capacity, 1, budgets.maxParticles, 'particle capacity'); bounded(cue.rate, 0, 1000, 'particle rate'); integer(cue.seed, 0, 2147483647, 'particle seed'); particles += cue.capacity; }
      if (cue.type === 'projectile' && !targets.has(cue.target)) throw new Error('Missing declared fixed target');
    }
    if (particles > budgets.maxParticles) throw new Error('Aggregate particle budget violated');
    const markers = unique(action.markers || [], 'markers');
    if (markers.size + steps.length * 2 + cues.size * 2 > 8192) throw new Error('Action boundary inventory exceeds adapter budget');
    for (const marker of markers.values()) { bounded(marker.at, 0, action.duration, 'marker time'); text(marker.name, 'marker name'); if (!identities.has(`${marker.step}:${marker.occurrence}`)) throw new Error('Marker has missing step occurrence'); }
  }
  return {data, actions, anchors, targets, sourceClips};
}

function node(root, identity) {
  const original = [], exact = [];
  root.traverse(item => { if (item.userData?.name === identity) original.push(item); if (item.name === identity || item.uuid === identity) exact.push(item); });
  const matches = original.length ? original : exact;
  if (matches.length !== 1) throw new Error(`Expected one actual node for ${identity}; found ${matches.length}`);
  return matches[0];
}

function preflight(THREE, root, actions, animations, rig) {
  const clips = new Map();
  for (const clip of animations) { if (clips.has(clip.name)) throw new Error('Duplicate actual composite clip name'); clips.set(clip.name, clip); }
  const actualRoot = node(root, rig.rootBone || rig.rootNode), ancestors = new Set([actualRoot]);
  for (let item = actualRoot.parent; item; item = item.parent) { ancestors.add(item); if (item === root) break; }
  const members = new Set(); root.traverse(item => members.add(item));
  root.traverse(item => { if (item.isSkinnedMesh && item.skeleton.bones.some(bone => !members.has(bone))) throw new Error('Skeleton bones must belong to this actor; use skeleton-aware clones'); });
  for (const action of actions.values()) {
    const clip = clips.get(action.clip);
    if (!clip?.tracks?.length || Math.abs(clip.duration - action.duration) > Math.max(.0001, action.duration * .00001)) throw new Error(`Missing/mismatched actual composite clip ${action.clip}`);
    for (const track of clip.tracks) {
      const parsed = THREE.PropertyBinding.parseTrackName(track.name);
      let target = parsed.nodeName ? node(root, parsed.nodeName) : root;
      if (parsed.objectName === 'bones') target = node(root, parsed.objectIndex);
      if (!['position', 'quaternion', 'scale', 'morphTargetInfluences'].includes(parsed.propertyName)) throw new Error(`Unsupported animation property ${parsed.propertyName}`);
      const width = track.getValueSize();
      if (!width || !track.times.length || Array.from(track.times).some(t => !Number.isFinite(t) || t < -EPS || t > action.duration + .001) || Array.from(track.values).some(v => !Number.isFinite(v))) throw new Error('Corrupt actual animation samples');
      if (ancestors.has(target) && ['position', 'quaternion', 'scale'].includes(parsed.propertyName)) {
        const start = Array.from(track.values.slice(0, width));
        if (Array.from(track.values).some((v, i) => Math.abs(v - start[i % width]) > 1e-6)) throw new Error('Composite root or ancestor moves: supply in-place source clips');
      }
    }
  }
  return clips;
}

function effect(THREE, cue, anchor, parent, target, time, quality, reduced, account) {
  let geometry, material, object, dead = false;
  const from = anchor.getWorldPosition(new THREE.Vector3()), end = target && new THREE.Vector3().fromArray(target);
  try {
    if (cue.type === 'particles') {
      geometry = new THREE.BufferGeometry(); account.created++;
      geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(cue.capacity * 3), 3));
      geometry.setDrawRange(0, 0);
      material = new THREE.PointsMaterial({color: cue.color, size: cue.radius, sizeAttenuation: true, transparent: true, opacity: reduced ? .25 : .7, depthWrite: false}); account.created++;
      object = new THREE.Points(geometry, material);
    } else {
      geometry = new THREE.SphereGeometry(cue.radius, 12, 8); account.created++;
      material = new THREE.MeshBasicMaterial({color: cue.color, transparent: true, opacity: reduced ? .35 : .7, depthWrite: false}); account.created++;
      object = new THREE.Mesh(geometry, material);
    }
    object.userData.opencawActionCue = cue.id;
    if (cue.type === 'orb') anchor.add(object); else parent.add(object);
  } catch (error) {
    try { object?.removeFromParent(); } catch { /* Preserve original acquisition failure. */ }
    for (const resource of [geometry, material]) if (resource) { try { resource.dispose(); } catch { /* Finish all owned cleanup. */ } account.disposed++; }
    throw error;
  }
  let random = cue.seed || 1, accumulated = 0, next = 0;
  const particles = cue.type === 'particles' ? Array.from({length: cue.capacity}, () => ({age: Infinity, world: new THREE.Vector3(), velocity: new THREE.Vector3()})) : null;
  const rng = () => { random = (Math.imul(random, 1664525) + 1013904223) >>> 0; return random / 4294967296; };
  function update(at, dt, nextQuality = quality, nextReduced = reduced) {
    if (dead) return;
    quality = nextQuality; reduced = nextReduced;
    material.opacity = reduced ? .25 : .7;
    const u = Math.max(0, Math.min(1, (at - cue.start) / (cue.end - cue.start)));
    object.visible = quality > 0 || cue.type !== 'particles';
    if (cue.type === 'orb') object.scale.setScalar(reduced ? 1 : .5 + .5 * u * u * (3 - 2 * u));
    else if (cue.type === 'projectile') object.position.copy(parent.worldToLocal(from.clone().lerp(end, u)));
    else {
      const lifetime = Math.min(.5, cue.end - cue.start), scale = reduced ? .15 : quality / 2;
      for (const p of particles) { p.age += dt; if (p.age < lifetime) p.world.addScaledVector(p.velocity, dt); }
      accumulated += cue.rate * dt * scale;
      for (let n = Math.min(cue.capacity, Math.floor(accumulated)); n > 0; n--) {
        accumulated -= 1; const p = particles[next++ % cue.capacity]; p.age = 0; anchor.getWorldPosition(p.world);
        p.velocity.set((rng() - .5) * cue.radius * 3, rng() * cue.radius * 3, (rng() - .5) * cue.radius * 3);
      }
      // Limit catch-up rather than accumulating an unbounded spawn backlog.
      accumulated = Math.min(accumulated, 1);
      let count = 0; const attribute = geometry.getAttribute('position');
      for (const p of particles) if (p.age < lifetime) { const local = parent.worldToLocal(p.world.clone()); attribute.setXYZ(count++, local.x, local.y, local.z); }
      geometry.setDrawRange(0, count); attribute.needsUpdate = true; account.peakParticles = Math.max(account.peakParticles, count);
    }
  }
  update(time, 0);
  return {cue, object, from: from.toArray(), target: target && [...target], update,
    dispose() {
      if (dead) return; dead = true;
      let failure;
      for (const release of [() => object.removeFromParent(), () => geometry.dispose(), () => material.dispose()]) {
        try { release(); } catch (error) { failure ||= error; }
      }
      account.disposed += 2;
      if (failure) throw failure;
    },
    get particles() { return cue.type === 'particles' ? geometry.drawRange.count : 0; }};
}

/** A presentation clock over actual baked action clips; never an ability authority. */
export function createActionPresentation({THREE, visualRoot, movementRoot, effectParent = movementRoot?.parent, animations = [], actionPackage, engineSelection, onPresentationEvent = () => {}, maxDelta = .25}) {
  const data = validateActionPresentation(actionPackage, engineSelection);
  if (!THREE?.AnimationMixer || !THREE.PropertyBinding || !THREE.Vector3) throw new Error('Host-owned Three.js APIs required');
  if (!visualRoot?.traverse || !movementRoot || visualRoot === movementRoot || !effectParent?.add) throw new Error('Distinct visual/movement roots and effect parent required');
  let parent = visualRoot.parent; while (parent && parent !== movementRoot) parent = parent.parent;
  if (parent !== movementRoot) throw new Error('Visual root must be beneath authoritative movement root');
  if (activeRoots.has(visualRoot)) throw new Error('This visual actor already has an action presentation owner');
  bounded(maxDelta, 1 / 120, 1, 'maxDelta');
  const clips = preflight(THREE, visualRoot, data.actions, animations, data.data.rig);
  const anchors = new Map([...data.anchors].map(([id, value]) => [id, node(visualRoot, value.node)]));
  const mixer = new THREE.AnimationMixer(visualRoot), owned = new Map(), account = {created: 0, disposed: 0, peakParticles: 0};
  let generation = 0, serial = 0, current = null, elapsed = 0, paused = false, disposed = false, running = false, quality = 2, reduced = false;
  const history = [], rest = [];
  visualRoot.traverse(item => rest.push({item, position: item.position.clone(), quaternion: item.quaternion.clone(), scale: item.scale.clone()}));
  const live = () => { if (disposed) throw new Error('Action presentation is disposed'); };
  const token = () => ({generation, current});
  const valid = value => !disposed && value.generation === generation && value.current === current;
  const emit = (type, detail, value) => {
    if (!valid(value)) return false;
    const event = Object.freeze({type, generation, instance: current?.instance || null, action: current?.definition.id || null, time: elapsed, ...detail});
    history.push(event); if (history.length > 128) history.shift();
    onPresentationEvent(event);
    return valid(value);
  };
  function clear() {
    const released = [...owned.values()]; owned.clear(); let failure;
    for (const value of released) { try { value.dispose(); } catch (error) { failure ||= error; } }
    if (failure) throw failure;
  }
  function restore() { mixer.stopAllAction(); for (const value of rest) { value.item.position.copy(value.position); value.item.quaternion.copy(value.quaternion); value.item.scale.copy(value.scale); } visualRoot.updateMatrixWorld(true); }
  function halt(type, notify = true) {
    const old = current;
    generation++; current = null; elapsed = 0; const value = token();
    restore(); clear();
    if (notify && old && valid(value)) emit(type, {previousAction: old.definition.id, previousInstance: old.instance}, value);
    return value;
  }
  function boundaries(definition) {
    const result = [];
    for (const step of definition.steps) { result.push({at: step.start, rank: 3, type: 'step-enter', step: step.id, occurrence: step.occurrence}); result.push({at: step.end, rank: 0, type: 'step-exit', step: step.id, occurrence: step.occurrence}); }
    for (const cue of definition.cues) { result.push({at: cue.start, rank: 4, type: 'cue-start', cue}); result.push({at: cue.end, rank: 1, type: 'cue-end', cue}); }
    for (const marker of definition.markers || []) result.push({at: marker.at, rank: 2, type: 'marker', marker});
    return result.sort((a, b) => a.at - b.at || a.rank - b.rank || String(a.cue?.id || a.marker?.id || `${a.step}:${a.occurrence}`).localeCompare(String(b.cue?.id || b.marker?.id || `${b.step}:${b.occurrence}`), 'en'));
  }
  function processBoundaries(value) {
    while (valid(value) && !paused && current.cursor < current.boundaries.length && current.boundaries[current.cursor].at <= elapsed + EPS) {
      const boundary = current.boundaries[current.cursor++];
      if (boundary.type === 'cue-start') {
        const cue = boundary.cue, anchor = anchors.get(cue.anchor), target = current.targets[cue.target];
        if (cue.type === 'projectile') {
          const origin = anchor.getWorldPosition(new THREE.Vector3());
          if (origin.distanceTo(new THREE.Vector3().fromArray(target)) > data.targets.get(cue.target).maxDistance) throw new Error('Fixed target exceeds distance at release');
        }
        const acquired = effect(THREE, cue, anchor, effectParent, target, elapsed, quality, reduced, account);
        if (!valid(value)) { acquired.dispose(); return; }
        owned.set(cue.id, acquired);
        if (!emit('cue-start', {cue: cue.id, cueType: cue.type, anchor: cue.anchor, target: acquired.target && [...acquired.target], origin: acquired.from}, value)) return;
      } else if (boundary.type === 'cue-end') {
        const ended = owned.get(boundary.cue.id);
        const worldPosition = ended?.object.getWorldPosition(new THREE.Vector3()).toArray();
        const target = ended?.target && [...ended.target];
        owned.delete(boundary.cue.id); ended?.dispose();
        if (!valid(value)) return;
        if (!emit('cue-end', {cue: boundary.cue.id, cueType: boundary.cue.type, worldPosition, target}, value)) return;
      } else if (boundary.type === 'marker') {
        if (!emit('marker', {marker: boundary.marker.name, markerId: boundary.marker.id, step: boundary.marker.step, occurrence: boundary.marker.occurrence}, value)) return;
      } else if (!emit(boundary.type, {step: boundary.step, occurrence: boundary.occurrence}, value)) return;
    }
  }
  const api = {
    get generation() { return generation; }, get state() { return disposed ? 'disposed' : current ? (current.complete ? 'complete' : paused ? 'paused' : 'playing') : 'idle'; },
    get currentAction() { return current?.definition.id || null; },
    play(actionId, options = {}) {
      live(); const definition = data.actions.get(actionId); if (!definition) throw new Error('Unknown compiled action');
      const targets = {};
      for (const cue of definition.cues) if (cue.type === 'projectile') targets[cue.target] = vector(options.targets?.[cue.target], 'fixed target snapshot');
      const cleared = halt('action-cancelled', false); if (!valid(cleared)) return current?.instance || null;
      paused = false;
      const action = mixer.clipAction(clips.get(definition.clip)); action.reset(); action.setLoop(THREE.LoopOnce, 1); action.clampWhenFinished = true; action.play();
      current = {definition, action, instance: ++serial, targets, boundaries: boundaries(definition), cursor: 0, complete: false};
      mixer.update(0); visualRoot.updateMatrixWorld(true);
      const value = token();
      try { if (emit('action-started', {}, value)) processBoundaries(value); }
      catch (error) { if (valid(value)) halt('action-failed', false); throw error; }
      return current?.instance || null;
    },
    update(dt) {
      live(); bounded(dt, 0, maxDelta, 'presentation delta'); if (running) throw new Error('Action clock cannot reenter');
      if (paused || !current || current.complete || dt === 0) return;
      const value = token(), end = Math.min(current.definition.duration, elapsed + dt); running = true;
      try {
        processBoundaries(value);
        let iterations = 0;
        while (valid(value) && !paused && elapsed < end - EPS) {
          if (++iterations > 8192) throw new Error('Action boundary subdivision budget exceeded');
          const next = current.boundaries[current.cursor]?.at ?? end;
          const destination = Math.min(end, Math.max(elapsed, next));
          const delta = destination - elapsed;
          if (delta > EPS) { mixer.update(delta); if (!valid(value)) return; elapsed = destination; visualRoot.updateMatrixWorld(true); for (const item of owned.values()) item.update(elapsed, delta, quality, reduced); }
          processBoundaries(value);
          if (delta <= EPS && valid(value) && current.boundaries[current.cursor]?.at > elapsed + EPS) elapsed = Math.min(end, elapsed + EPS);
        }
        if (valid(value) && !paused && elapsed >= current.definition.duration - EPS) { elapsed = current.definition.duration; processBoundaries(value); if (!valid(value) || paused) return; current.complete = true; clear(); if (valid(value)) emit('action-complete', {}, value); }
      } catch (error) { if (valid(value)) halt('action-failed', false); throw error; }
      finally { running = false; }
    },
    pause(value) { live(); if (typeof value !== 'boolean') throw new Error('Pause state must be boolean'); paused = value; },
    cancel() { live(); halt('action-cancelled'); },
    reset() { live(); paused = false; history.length = 0; halt('action-reset'); },
    setQuality(value) { live(); integer(value, 0, 2, 'quality'); quality = value; for (const item of owned.values()) item.update(elapsed, 0, quality, reduced); },
    setReducedMotion(value) { live(); if (typeof value !== 'boolean') throw new Error('Reduced motion must be boolean'); reduced = value; for (const item of owned.values()) item.update(elapsed, 0, quality, reduced); },
    stats() { return {state: api.state, generation, instance: current?.instance || null, time: elapsed, activeEffects: owned.size, liveParticles: [...owned.values()].reduce((n, item) => n + item.particles, 0), peakParticles: account.peakParticles, ownedResources: account.created - account.disposed, resourcesCreated: account.created, resourcesDisposed: account.disposed, eventHistory: history.length, events: history.map(event => ({...event})), effects: [...owned.values()].map(item => ({id: item.cue.id, type: item.cue.type, worldPosition: item.object.getWorldPosition(new THREE.Vector3()).toArray(), target: item.target && [...item.target]}))}; },
    dispose() {
      if (disposed) return; disposed = true; generation++; current = null; elapsed = 0;
      try { restore(); clear(); }
      finally { for (const clip of clips.values()) mixer.uncacheClip(clip); mixer.uncacheRoot(visualRoot); activeRoots.delete(visualRoot); }
    }
  };
  activeRoots.set(visualRoot, api);
  return api;
}
