/* OpenCaw motion presentation for a host-owned, version-locked Three.js runtime.
 * This module owns local animation/effects. The host owns movement and gameplay.
 * It performs no imports, network access, installation, provider calls or uploads.
 */

const PROFILES = new Set(['skinned', 'articulated', 'rigid']);
const EFFECTS = new Set(['particles', 'trail', 'material']);
const MAX_EFFECTS = 32;
const MAX_PARTICLES = 65536;
const finite = (value, label) => {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${label} must be finite`);
  return value;
};
const text = (value, label) => {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${label} is required`);
  return value;
};
const list = (value, label) => {
  if (!Array.isArray(value)) throw new Error(`${label} must be an array`);
  return value;
};
const bounded = (value, low, high, label) => {
  finite(value, label);
  if (value < low || value > high) throw new Error(`${label} is outside ${low}..${high}`);
  return value;
};
const unique = (values, label) => {
  const result = new Map();
  for (const value of list(values, label)) {
    if (!value || typeof value !== 'object') throw new Error(`${label} entry must be an object`);
    const id = text(value.id, `${label}.id`);
    if (result.has(id)) throw new Error(`Duplicate ${label} identity: ${id}`);
    result.set(id, value);
  }
  return result;
};
const clamp01 = value => Math.min(1, Math.max(0, value));
const color = value => {
  if (Array.isArray(value) && value.length === 3) { value.forEach(channel => bounded(channel, 0, 1, 'linear RGB color')); return value; }
  if (typeof value !== 'string' || !/^#[\da-f]{6}$/i.test(value)) throw new Error('Effect color must be linear RGB[3] or #RRGGBB');
  return value;
};
const vector = (value, label) => {
  if (!Array.isArray(value) || value.length !== 3) throw new Error(`${label} needs three numbers`);
  value.forEach(item => finite(item, label));
  return value;
};

function supportedOrigins(value, key = '') {
  if (Array.isArray(value)) value.forEach(item => supportedOrigins(item, key));
  else if (value && typeof value === 'object') Object.entries(value).forEach(([name, child]) => supportedOrigins(child, name));
  else if (typeof value === 'string' && /provider|vendor|backend|generator|sourceUri/i.test(key)
    && /\b(?:adobe|mixamo)\b/i.test(value)) throw new Error('Excluded provider provenance is unsupported by this workflow');
}

/** Validate data and selection before constructing mixers, resources or listeners. */
export function validateMotionPresentation(motionPackage, engineSelection) {
  if (!engineSelection || engineSelection.effectiveEngine !== 'THREEJS') throw new Error('Resolve THREEJS before loading this engine adapter');
  const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
  if ((!hash(engineSelection.contractSha256) && engineSelection.selectionSource !== 'default')
    || !hash(engineSelection.registrySha256) || !hash(engineSelection.definitionSha256)) throw new Error('Canonical engine selection evidence is required');
  if (!motionPackage || motionPackage.schemaVersion !== 'opencaw-motion-package/v1') throw new Error('Expected opencaw-motion-package/v1');
  if (!PROFILES.has(motionPackage.profile)) throw new Error('Unknown motion profile');
  if (motionPackage.engine && motionPackage.engine.effectiveEngine !== engineSelection.effectiveEngine) throw new Error('Package engine conflicts with effective selection');
  if (motionPackage.engine?.contractSha256 && motionPackage.engine.contractSha256 !== engineSelection.contractSha256) throw new Error('Package engine evidence is stale');
  supportedOrigins(motionPackage.provenance);
  const clips = unique(motionPackage.clips, 'clips');
  const states = unique(motionPackage.states, 'states');
  const anchors = unique(motionPackage.anchors, 'anchors');
  const parameters = unique(motionPackage.parameters, 'parameters');
  const effects = unique(motionPackage.effects, 'effects');
  if (!states.size) throw new Error('At least one presentation state is required');
  if (effects.size > MAX_EFFECTS) throw new Error('Effect inventory exceeds the adapter budget');
  for (const clip of clips.values()) {
    text(clip.role, 'clip.role');
    bounded(clip.duration, 1 / 120, 3600, 'clip.duration');
    if (typeof clip.loop !== 'boolean') throw new Error('Clip loop policy is required');
    if (!['in-place', 'extract'].includes(clip.rootMotion)) throw new Error('Clip root-motion policy is required');
    const times = new Set();
    for (const marker of list(clip.markers || [], 'clip.markers')) {
      bounded(marker.time, 0, clip.duration, 'marker.time'); text(marker.event, 'marker.event');
      const key = `${marker.time}:${marker.event}`;
      if (times.has(key)) throw new Error('Duplicate presentation marker');
      times.add(key);
    }
  }
  for (const state of states.values()) if (state.clip && !clips.has(state.clip)) throw new Error(`State has a missing clip: ${state.id}`);
  const transitions = list(motionPackage.transitions, 'transitions');
  const transitionKeys = new Set();
  for (const transition of transitions) {
    if (!states.has(transition.from)) throw new Error('Transition source does not resolve');
    if (!states.has(transition.to)) throw new Error('Transition target does not resolve');
    text(transition.trigger, 'transition.trigger'); bounded(transition.duration, 0, 30, 'transition.duration');
    const key = `${transition.from}:${transition.trigger}`;
    if (transitionKeys.has(key)) throw new Error('Ambiguous presentation transition');
    transitionKeys.add(key);
  }
  const transformOwners = new Set();
  for (const parameter of parameters.values()) {
    finite(parameter.min, 'parameter.min'); finite(parameter.max, 'parameter.max');
    if (parameter.max <= parameter.min) throw new Error('Parameter range must be nonzero');
    bounded(parameter.default, parameter.min, parameter.max, 'parameter.default'); text(parameter.unit, 'parameter.unit');
    for (const binding of list(parameter.bindings || [], 'parameter.bindings')) {
      text(binding.node, 'parameter binding node');
      if (!['x', 'y', 'z'].includes(binding.axis)) throw new Error('Articulation axis must be x/y/z in runtime coordinates');
      if (!['rotation', 'position'].includes(binding.property)) throw new Error('Unsupported articulation property');
      if (!['angular-speed', 'angle', 'position'].includes(binding.mode)
        || (binding.mode === 'position') !== (binding.property === 'position')) throw new Error('Articulation mode/property mismatch');
      finite(binding.scale, 'articulation scale'); finite(binding.offset ?? 0, 'articulation offset');
      const key = `${binding.node}:${binding.property}:${binding.axis}`;
      if (transformOwners.has(key)) throw new Error('Multiple parameters own one articulation axis');
      transformOwners.add(key);
    }
  }
  let particles = 0;
  for (const effect of effects.values()) {
    if (!EFFECTS.has(effect.type)) throw new Error('Unsupported effect type');
    if (!anchors.has(effect.anchor)) throw new Error(`Effect anchor does not resolve: ${effect.id}`);
    if (effect.parameter && !parameters.has(effect.parameter)) throw new Error('Effect parameter does not resolve');
    for (const state of list(effect.states || [], 'effect.states')) if (!states.has(state)) throw new Error('Effect state does not resolve');
    bounded(effect.reducedMotionScale ?? 0, 0, 1, 'reducedMotionScale');
    bounded(effect.qualityMin ?? 0, 0, 2, 'qualityMin');
    if (effect.color !== undefined) color(effect.color);
    if (effect.type === 'material') {
      text(effect.target, 'material effect target'); bounded(effect.maxIntensity ?? 2, 0, 50, 'maxIntensity');
    } else {
      if (!Number.isInteger(effect.maxParticles)) throw new Error('Particle capacity must be an integer');
      bounded(effect.maxParticles, 1, 16384, 'maxParticles'); particles += effect.maxParticles;
      bounded(effect.lifetime, 0.01, 60, 'particle lifetime');
      bounded(effect.rate ?? effect.maxParticles / effect.lifetime, 0, 65536, 'particle rate');
      bounded(effect.size ?? 0.05, 0.0001, 100, 'particle size');
      vector(effect.velocity || [0, 0, -1], 'particle velocity');
      if (!['local', 'world'].includes(effect.space)) throw new Error('Effect space must be local or world');
    }
  }
  if (particles > MAX_PARTICLES || particles > (motionPackage.budgets?.maxParticles ?? MAX_PARTICLES)) throw new Error('Aggregate particle capacity exceeds budget');
  return {clips, states, anchors, parameters, effects, transitions, particleCapacity: particles};
}

function findNode(root, name) {
  const originals = [], exact = [];
  // GLTFLoader preserves the exported name in userData.name while sanitizing
  // Object3D.name for PropertyBinding. Prefer that original identity so names
  // such as anchor.exhaust do not collide with an actual anchor_exhaust node.
  root.traverse(node => {
    if (node.userData?.name === name) originals.push(node);
    if (node.name === name || node.uuid === name) exact.push(node);
  });
  const nodes = originals.length ? originals : exact;
  if (nodes.length !== 1) throw new Error(`Expected exactly one node for ${name}; found ${nodes.length}`);
  return nodes[0];
}

function varyingTrack(track) {
  const width = track.getValueSize?.();
  if (!Number.isInteger(width) || width < 1 || !track.values?.length || track.values.length % width) throw new Error('Extracted motion requires valid sampled transform channels');
  const reference = Array.from(track.values.slice(0, width));
  return Array.from(track.values).some((value, index) => !Number.isFinite(value) || Math.abs(value - reference[index % width]) > 1e-6);
}

function transformTrackTarget(THREE, root, track) {
  // Animation tracks address runtime PropertyBinding names, unlike manifest
  // identities, which may retain GLTFLoader's original userData.name.
  const parsed = THREE.PropertyBinding?.parseTrackName
    ? THREE.PropertyBinding.parseTrackName(track.name)
    : {nodeName: track.name.slice(0, track.name.lastIndexOf('.')), propertyName: track.name.slice(track.name.lastIndexOf('.') + 1)};
  if (!['position', 'quaternion', 'rotation', 'scale'].includes(parsed.propertyName)) return null;
  const candidates = [];
  root.traverse(node => { if (node.name === parsed.nodeName || node.uuid === parsed.nodeName) candidates.push(node); });
  let node = parsed.nodeName === undefined || parsed.nodeName === '' || parsed.nodeName === '.' ? root : candidates.length === 1 ? candidates[0] : null;
  if (parsed.objectName === 'bones') {
    const bones = [];
    (node || root).traverse(child => { if (child.name === parsed.objectIndex && (child.isBone || child === root)) bones.push(child); });
    node = bones.length === 1 ? bones[0] : null;
  } else if (parsed.objectName) throw new Error('Extracted motion requires directly bound transform nodes');
  if (!node) throw new Error(`Extracted motion has an ambiguous or missing runtime track target: ${track.name}`);
  return {node, property: parsed.propertyName};
}

function makeParticles(THREE, binding, anchor, effectParent) {
  const capacity = binding.maxParticles;
  const positions = new Float32Array(capacity * 3);
  const velocities = new Float32Array(capacity * 3);
  const ages = new Float64Array(capacity);
  const geometry = new THREE.BufferGeometry();
  const attribute = new THREE.BufferAttribute(positions, 3);
  geometry.setAttribute('position', attribute); geometry.setDrawRange(0, 0);
  const selectedColor = Array.isArray(binding.color) ? new THREE.Color().setRGB(...binding.color) : binding.color || '#70baff';
  const material = new THREE.PointsMaterial({color: selectedColor, size: binding.size || 0.05, transparent: true, opacity: 0.85, depthWrite: false, sizeAttenuation: true});
  const points = new THREE.Points(geometry, material); points.name = `opencaw.effect.${binding.id}`; points.frustumCulled = false;
  const parent = binding.space === 'local' ? anchor : effectParent;
  parent.add(points);
  const position = new THREE.Vector3(), velocity = new THREE.Vector3(), endpoint = new THREE.Vector3();
  let alive = 0, carry = 0;
  const clear = () => { alive = 0; carry = 0; geometry.setDrawRange(0, 0); };
  return {
    get alive() { return alive; },
    clear,
    update(dt, amount, density) {
      const limit = Math.max(1, Math.floor(capacity * density));
      for (let index = alive - 1; index >= 0; index--) {
        ages[index] += dt;
        if (ages[index] >= binding.lifetime || index >= limit) {
          const last = --alive;
          if (index !== last) {
            ages[index] = ages[last];
            positions.copyWithin(index * 3, last * 3, last * 3 + 3);
            velocities.copyWithin(index * 3, last * 3, last * 3 + 3);
          }
        } else for (let axis = 0; axis < 3; axis++) positions[index * 3 + axis] += velocities[index * 3 + axis] * dt;
      }
      carry = Math.min(capacity, carry + (binding.rate ?? capacity / binding.lifetime) * amount * dt);
      let emit = Math.min(Math.floor(carry), Math.max(0, limit - alive)); carry -= Math.floor(carry);
      anchor.updateWorldMatrix(true, false);
      while (emit-- > 0) {
        position.set(0, 0, 0);
        velocity.fromArray(binding.velocity || [0, 0, -1]);
        if (binding.space === 'world') {
          // Transform two points so the velocity respects anchor/parent transforms.
          endpoint.copy(velocity); anchor.localToWorld(position); anchor.localToWorld(endpoint);
          parent.worldToLocal(position); parent.worldToLocal(endpoint); velocity.copy(endpoint).sub(position);
        }
        positions.set(position.toArray(), alive * 3); velocities.set(velocity.toArray(), alive * 3); ages[alive] = 0; alive++;
      }
      attribute.needsUpdate = true; geometry.setDrawRange(0, alive);
    },
    dispose() { clear(); points.removeFromParent(); geometry.dispose(); material.dispose(); }
  };
}

function makeMaterial(binding, target) {
  const original = target.material;
  const originalList = Array.isArray(original) ? original : [original];
  if (!originalList.length || originalList.some(material => !material?.emissive || typeof material.clone !== 'function')) throw new Error('Material effect requires cloneable emissive materials');
  const clones = originalList.map(material => material.clone());
  target.material = Array.isArray(original) ? clones : clones[0];
  const base = clones.map(material => ({intensity: material.emissiveIntensity ?? 1, color: material.emissive.clone()}));
  return {
    get alive() { return 0; },
    clear() { clones.forEach((material, index) => { material.emissiveIntensity = base[index].intensity; material.emissive.copy(base[index].color); }); },
    update(_dt, amount) {
      clones.forEach((material, index) => {
        material.emissiveIntensity = base[index].intensity + (binding.maxIntensity ?? 2) * amount;
        if (binding.color && amount > 0) {
          if (Array.isArray(binding.color)) material.emissive.setRGB(...binding.color);
          else material.emissive.set(binding.color);
        }
        else material.emissive.copy(base[index].color);
      });
    },
    dispose() { this.clear(); target.material = original; clones.forEach(material => material.dispose()); }
  };
}

/** Construct presentation under a visual child of a separate authoritative root.
 * API state changes are requests from gameplay; clip events never advance gameplay.
 * Translation extraction supports a declared root node and a controller-owned sink.
 */
export function createMotionPresentation({THREE, visualRoot, movementRoot, animations = [], motionPackage, engineSelection, effectParent = movementRoot?.parent, initialState, onPresentationEvent = () => {}, rootMotionSink = null, maxDelta = 0.25}) {
  // Treat the approved content as a snapshot; mutable host state lives elsewhere.
  motionPackage = typeof globalThis.structuredClone === 'function' ? globalThis.structuredClone(motionPackage) : JSON.parse(JSON.stringify(motionPackage));
  const data = validateMotionPresentation(motionPackage, engineSelection);
  if (!THREE?.AnimationMixer || !THREE.Vector3) throw new Error('Host-owned Three.js APIs are required');
  if (!visualRoot?.traverse || !movementRoot || visualRoot === movementRoot) throw new Error('Use distinct visual and authoritative movement roots');
  let ancestor = visualRoot.parent;
  while (ancestor && ancestor !== movementRoot) ancestor = ancestor.parent;
  if (ancestor !== movementRoot) throw new Error('Visual asset must be beneath the authoritative movement root');
  bounded(maxDelta, 1 / 120, 1, 'maxDelta');
  const clipByName = new Map();
  for (const clip of animations) {
    if (clipByName.has(clip.name)) throw new Error(`Ambiguous exported clip: ${clip.name}`);
    clipByName.set(clip.name, clip);
  }
  const rootNodeName = motionPackage.rig?.rootBone || motionPackage.rig?.rootNode;
  const clipDefinitions = new Map();
  const articulationDefinitions = [];
  for (const [id, definition] of data.clips) {
    const clip = clipByName.get(definition.action || definition.id);
    if (!clip || !clip.tracks?.length || !(clip.duration > 0)) throw new Error(`Missing actual animation channels: ${id}`);
    if (Math.abs(clip.duration - definition.duration) > Math.max(1 / 60, definition.duration * 0.001)) throw new Error(`Actual clip duration differs from package: ${id}`);
    let rootNode = null;
    if (definition.rootMotion === 'extract') {
      if (typeof rootMotionSink !== 'function' || !rootNodeName) throw new Error('Extracted motion requires a declared root and controller-owned rootMotionSink');
      vector(definition.rootDisplacement, 'rootDisplacement');
      if (motionPackage.coordinateSystem?.runtimeUp !== '+Y') throw new Error('Root displacement must be recorded in exported runtime coordinates');
      rootNode = findNode(visualRoot, rootNodeName);
      const ancestors = new Set();
      for (let parent = rootNode.parent; parent; parent = parent.parent) { ancestors.add(parent); if (parent === visualRoot) break; }
      for (const track of clip.tracks) {
        const target = transformTrackTarget(THREE, visualRoot, track);
        if (!target || !varyingTrack(track)) continue;
        if (ancestors.has(target.node)) throw new Error('Animated ancestors of an extracted root require an explicitly authored engine-specific root-motion adapter');
        if (target.node === rootNode && ['quaternion', 'rotation', 'scale'].includes(target.property)) throw new Error('Rotating or scaling extracted roots require an explicitly authored engine-specific root-motion adapter');
      }
    }
    clipDefinitions.set(id, {definition, clip, rootNode});
  }
  for (const parameter of data.parameters.values()) for (const binding of parameter.bindings || []) {
    const node = findNode(visualRoot, binding.node);
    if (node === visualRoot) throw new Error('Parameter articulation cannot own the visual/world asset root');
    for (const {rootNode} of clipDefinitions.values()) {
      for (let owner = rootNode; owner; owner = owner.parent) {
        if (owner === node) throw new Error('Parameter articulation cannot own extracted roots or their ancestors');
        if (owner === visualRoot) break;
      }
    }
    const property = binding.property === 'rotation' ? 'quaternion' : 'position';
    for (const {clip} of clipDefinitions.values()) if (clip.tracks.some(track => track.name.startsWith(node.name + '.') && track.name.endsWith('.' + property))) throw new Error(`Clip and parameter both own ${binding.node}.${binding.property}`);
    articulationDefinitions.push({parameter: parameter.id, binding, node, initial: node[binding.property][binding.axis], angle: 0});
  }
  const anchorNodes = new Map([...data.anchors].map(([id, entry]) => [id, findNode(visualRoot, text(entry.node, 'anchor.node'))]));
  const effectDefinitions = [];
  const materialTargets = new Set();
  for (const effect of data.effects.values()) {
    const anchor = anchorNodes.get(effect.anchor);
    if (effect.type !== 'material' && effect.space === 'world' && !effectParent?.add) throw new Error('World-space effects require an explicit effect parent');
    if (effect.type !== 'material' && ![THREE.BufferGeometry, THREE.BufferAttribute, THREE.Points, THREE.PointsMaterial].every(value => typeof value === 'function')) throw new Error('Host Three.js particle primitives are unavailable');
    const target = effect.type === 'material' ? findNode(visualRoot, effect.target) : null;
    if (target && !target.material) throw new Error('Material effect target has no material');
    if (target && materialTargets.has(target)) throw new Error('Multiple effects cannot own one material target');
    if (target) materialTargets.add(target);
    effectDefinitions.push({binding: effect, anchor, target});
  }
  const selectedInitial = initialState || motionPackage.initialState || data.states.keys().next().value;
  if (!data.states.has(selectedInitial)) throw new Error('Initial presentation state does not resolve');
  const mixer = new THREE.AnimationMixer(visualRoot);
  const actions = new Map();
  const ownedEffects = [];
  try {
    for (const [id, entry] of clipDefinitions) actions.set(id, {...entry, action: mixer.clipAction(entry.clip), restRoot: entry.rootNode?.position.clone()});
    for (const entry of effectDefinitions) ownedEffects.push({...entry, effect: entry.target ? makeMaterial(entry.binding, entry.target) : makeParticles(THREE, entry.binding, entry.anchor, effectParent)});
  } catch (error) {
    ownedEffects.forEach(entry => entry.effect.dispose()); mixer.stopAllAction(); mixer.uncacheRoot(visualRoot); throw error;
  }
  const values = new Map([...data.parameters].map(([id, parameter]) => [id, parameter.default]));
  let state = null, active = null, generation = 1, epoch = 0, serial = 0, paused = false, disposed = false, reducedMotion = false, quality = 2, updating = false, runningFrame = false, updateToken = null, pendingFinished = null, loopDelta = 0, sampleTime = 0;
  const rootSample = new THREE.Vector3(), previousRootSample = new THREE.Vector3();
  const events = [];
  const ensureLive = () => { if (disposed) throw new Error('Motion presentation has been disposed'); };
  const snapshot = () => ({generation, epoch, state, active});
  const current = token => !disposed && token.generation === generation && token.epoch === epoch && token.state === state && token.active === active;
  const emit = (type, detail = {}, token = snapshot()) => {
    if (!current(token)) return false;
    const event = Object.freeze({type, ...detail, generation: token.generation, serial: ++serial, state: token.state?.id});
    events.push(event); if (events.length > 128) events.shift();
    onPresentationEvent(event);
    return current(token);
  };
  const sampleRoot = (entry = active) => {
    visualRoot.updateWorldMatrix(true, true);
    entry.rootNode.getWorldPosition(rootSample); visualRoot.worldToLocal(rootSample);
  };
  const onLoop = event => { if (updating && updateToken && current(updateToken) && event.action === updateToken.active?.action) loopDelta += event.loopDelta; };
  // Never invoke host callbacks while AnimationMixer is iterating its actions:
  // reset/dispose can remove those actions and invalidate the native iteration.
  const onFinished = event => { if (updating && updateToken && current(updateToken) && event.action === updateToken.active?.action) pendingFinished = event.action; };
  mixer.addEventListener('loop', onLoop); mixer.addEventListener('finished', onFinished);
  const clearEffects = () => ownedEffects.forEach(entry => entry.effect.clear());
  function enter(next, duration = 0) {
    const previous = active;
    state = data.states.get(next); active = state.clip ? actions.get(state.clip) : null;
    epoch++;
    const token = snapshot();
    loopDelta = 0; sampleTime = 0;
    if (previous?.rootNode) previous.rootNode.position.copy(previous.restRoot);
    if (active) {
      // Previously fading actions can still own ancestor channels. Translation
      // extraction always has sole mixer ownership, including on interruption.
      if (active.rootNode || previous?.rootNode) mixer.stopAllAction();
      active.action.reset(); active.action.setEffectiveTimeScale(1); active.action.setEffectiveWeight(1);
      active.action.setLoop(active.definition.loop ? THREE.LoopRepeat : THREE.LoopOnce, active.definition.loop ? Infinity : 1);
      active.action.clampWhenFinished = !active.definition.loop; active.action.play();
      if (previous && previous !== active && duration > 0) previous.action.crossFadeTo(active.action, duration, false);
      else if (previous && previous !== active) previous.action.stop();
      // Root extraction cannot blend two independently translating root tracks.
      if (active.rootNode || previous?.rootNode) {
        if (previous && previous !== active) previous.action.stop();
        mixer.update(0);
        if (active.rootNode) { sampleRoot(); previousRootSample.copy(rootSample); active.rootNode.position.copy(active.restRoot); }
      }
    } else previous?.action.stop();
    clearEffects();
    if (!emit('state-entered', {clip: token.state.clip || null}, token)) return;
    if (token.active) for (const marker of token.active.definition.markers || []) if (marker.time === 0 && !emit('marker', {clip: token.active.definition.id, marker: marker.event, time: 0}, token)) return;
  }
  enter(selectedInitial);
  function markerEvents(before, after, loops, token) {
    if (!token.active) return current(token);
    const definition = token.active.definition;
    if (after < 0 || after > definition.duration + 1e-3) throw new Error('Animation time exceeded the declared clip range');
    for (const marker of definition.markers || []) {
      if (loops === 0 && marker.time > before && marker.time <= after) {
        if (!emit('marker', {clip: definition.id, marker: marker.event, time: marker.time}, token)) return false;
      }
      else if (loops > 0) {
        if (marker.time > before && !emit('marker', {clip: definition.id, marker: marker.event, time: marker.time}, token)) return false;
        for (let loop = 1; loop < loops; loop++) if (!emit('marker', {clip: definition.id, marker: marker.event, time: marker.time}, token)) return false;
        if (marker.time <= after && !emit('marker', {clip: definition.id, marker: marker.event, time: marker.time}, token)) return false;
      }
    }
    return current(token);
  }
  return {
    get generation() { return generation; },
    get state() { return state.id; },
    dispatch(trigger, token = generation) {
      ensureLive(); if (token !== generation || state.terminal) return false;
      const transition = data.transitions.find(item => item.from === state.id && item.trigger === trigger);
      if (!transition) return false;
      enter(transition.to, transition.duration); return true;
    },
    setParameters(next) {
      ensureLive();
      const updates = Object.entries(next).map(([id, value]) => {
        const parameter = data.parameters.get(id); if (!parameter) throw new Error(`Unknown motion parameter: ${id}`);
        finite(value, id); return [id, Math.min(parameter.max, Math.max(parameter.min, value))];
      });
      updates.forEach(([id, value]) => values.set(id, value));
    },
    setPaused(value) { ensureLive(); if (typeof value !== 'boolean') throw new Error('Pause state must be boolean'); paused = value; },
    setReducedMotion(value) { ensureLive(); if (typeof value !== 'boolean') throw new Error('Reduced motion must be boolean'); reducedMotion = value; clearEffects(); },
    setQuality(value) { ensureLive(); if (!Number.isInteger(value)) throw new Error('Quality must be 0/1/2'); bounded(value, 0, 2, 'quality'); quality = value; clearEffects(); },
    update(dt) {
      ensureLive(); bounded(dt, 0, maxDelta, 'presentation delta'); if (paused || dt === 0) return;
      if (runningFrame) throw new Error('Presentation update cannot reenter its own clock');
      const token = snapshot();
      runningFrame = true;
      try {
        loopDelta = 0; pendingFinished = null; updating = true; updateToken = token;
        try { mixer.update(dt); } finally { updating = false; updateToken = null; }
        if (!current(token)) return;
        const before = sampleTime, nextTime = token.active?.action.time || 0;
        // Publish the old frame's cursor before callbacks. A reset must own its
        // new cursor, even when it reuses the very same AnimationAction object.
        sampleTime = nextTime;
        if (!markerEvents(before, nextTime, loopDelta, token)) return;
        if (pendingFinished && !emit('clip-finished', {clip: token.active.definition.id}, token)) return;
        if (!current(token)) return;
        if (token.active?.rootNode) {
          sampleRoot(token.active);
          const translation = rootSample.clone().sub(previousRootSample);
          translation.add(new THREE.Vector3().fromArray(token.active.definition.rootDisplacement).multiplyScalar(loopDelta));
          previousRootSample.copy(rootSample); token.active.rootNode.position.copy(token.active.restRoot);
          rootMotionSink({translation: translation.toArray(), generation: token.generation, state: token.state.id, clip: token.active.definition.id});
          if (!current(token)) return;
        }
        for (const item of articulationDefinitions) {
          if (!current(token)) return;
          const amount = values.get(item.parameter) * item.binding.scale;
          if (item.binding.mode === 'angular-speed') item.angle = (item.angle + amount * dt) % (Math.PI * 2);
          item.node[item.binding.property][item.binding.axis] = item.initial + (item.binding.offset || 0) + (item.binding.mode === 'angular-speed' ? item.angle : amount);
        }
        const density = [0.25, 0.5, 1][quality];
        for (const item of ownedEffects) {
          if (!current(token)) return;
          const parameter = item.binding.parameter ? data.parameters.get(item.binding.parameter) : null;
          let amount = parameter ? clamp01((values.get(parameter.id) - parameter.min) / (parameter.max - parameter.min)) : 1;
          if (item.binding.states?.length && !item.binding.states.includes(token.state.id)) amount = 0;
          if (quality < (item.binding.qualityMin || 0)) amount = 0;
          if (reducedMotion) amount *= item.binding.reducedMotionScale ?? 0;
          item.effect.update(dt, amount, density);
        }
      } finally { runningFrame = false; }
    },
    reset(next = selectedInitial) {
      ensureLive(); if (!data.states.has(next)) throw new Error('Reset state does not resolve');
      generation++; mixer.stopAllAction();
      for (const item of articulationDefinitions) { item.angle = 0; item.node[item.binding.property][item.binding.axis] = item.initial; }
      for (const entry of actions.values()) entry.rootNode?.position.copy(entry.restRoot);
      for (const [id, parameter] of data.parameters) values.set(id, parameter.default);
      clearEffects(); enter(next);
    },
    stats() { return {generation, state: state?.id, disposed, paused, mixerTime: mixer.time, parameters: Object.fromEntries(values), particleCapacity: data.particleCapacity, particles: ownedEffects.reduce((sum, item) => sum + item.effect.alive, 0), effects: ownedEffects.length, events: events.slice()}; },
    dispose() {
      if (disposed) return;
      disposed = true; generation++; mixer.removeEventListener('loop', onLoop); mixer.removeEventListener('finished', onFinished);
      mixer.stopAllAction(); mixer.uncacheRoot(visualRoot); ownedEffects.forEach(item => item.effect.dispose());
      for (const item of articulationDefinitions) item.node[item.binding.property][item.binding.axis] = item.initial;
      for (const entry of actions.values()) entry.rootNode?.position.copy(entry.restRoot);
    }
  };
}
