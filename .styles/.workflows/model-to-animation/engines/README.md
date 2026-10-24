# Selected-engine motion and presentation

`threejs-motion.mjs` is an executable Three.js adapter, independently authored for OpenCaw. Host applications supply a version-locked Three.js module, an actually loaded GLB, its motion package, canonical engine selection and separate authoritative movement owner. There are no runtime imports, remote assets, implicit package installs, CDN dependencies or provider calls.

Resolve `ENGINE.md` and the compatible engine feature before loading or writing. The host verifies current contract/definition/registry hashes and model/package hashes. The adapter checks THREEJS compatibility and receipt agreement, but cannot authenticate arbitrary caller data or replace the canonical resolver. Native publication/promotion approvals remain separate.

## Integration

```js
import {createMotionPresentation} from './threejs-motion.mjs';

// THREE, gltf, motionPackage and engineSelection come from the host's verified
// locked dependencies, actual asset load and canonical engine resolver.
const movementRoot = new THREE.Group();
scene.add(movementRoot);
movementRoot.add(gltf.scene);
const presentation = createMotionPresentation({
  THREE,
  visualRoot: gltf.scene,
  movementRoot,
  effectParent: scene,
  animations: gltf.animations,
  motionPackage,
  engineSelection
});

// The controller applies collision-aware movement once, then supplies state.
presentation.setParameters({speed: authoritativeSpeed});
presentation.dispatch('boost'); // Must resolve an explicit transition.
presentation.update(presentationDeltaSeconds);

// Retain the generation token when scheduling presentation callbacks.
const actorGeneration = presentation.generation;
presentation.dispatch('cancel', actorGeneration);
presentation.dispose();
```

Invoke `reset()` only for an intentional actor lifecycle reset; it restores local articulation, clears effects/default parameters and advances generation. Requests carrying an earlier generation return false. Terminal states reject ordinary transitions until reset. Clip/marker completion emits presentation signals and never automatically advances death, warp arrival or other authoritative state.

## Package bindings

Clips identify actual exported action names, duration, loop and root-motion policy. States reference clip IDs, with optional terminal policy. Transitions require an explicit known `from`, `to`, `trigger` and crossfade duration; there is no wildcard or implicit transition selection. The adapter accepts the native range up to3600 seconds per clip and30 seconds per fade, while the recipe's tighter budgets remain authoritative.

Imported glTF names may be sanitized by Three.js for animation binding. The adapter resolves the export's preserved original `userData.name` first, then exact runtime name/UUID, and rejects ambiguous identities. Do not independently sanitize manifest anchors into guessed names or apply their placement a second time. The native export is already Y-up/front+Z with Blender `(x,y,z)` mapped to `(x,z,-y)`; it does not need the proof reconstruction engine's raw-output correction.

Optional continuous parameter bindings drive actual local mechanical nodes:

```json
{
  "id": "speed", "unit": "metres-per-second",
  "min": 0, "max": 50, "default": 0,
  "bindings": [
    {"node": "Wheel.front-left", "property": "rotation", "axis": "x",
     "mode": "angular-speed", "scale": 4.545454545454546}
  ]
}
```

The scale above is a declared1/0.22-metre wheel-radius calibration in exported coordinates, not a general vehicle assumption. `angle` controls a rotation axis and `position` controls a local position axis. Parameters are finite and clamped to their declared ranges; invalid updates are rejected atomically. Clip and parameter ownership of the same node property is rejected. The visual/world root cannot be a parameter articulation target.

## Root motion and clocks

In-place motion leaves authoritative travel to the controller. Translation extraction requires a declared rootBone/rootNode, runtime-frame rootDisplacement and `rootMotionSink`; the adapter removes the sampled local translation and offers one loop-corrected delta to the controller. The controller applies it through its movement/collision rules. Rotating extracted roots require an explicitly implemented specialized engine adapter and are rejected here; in-place local rotation remains supported. Crossfading independently translating extracted roots is disabled to prevent double displacement.

Use one presentation clock in seconds. Default accepted delta is0..0.25 seconds, configurable explicitly up to1 second. Resume from long focus loss through the host's chosen pause/catch-up policy; do not inject an unbounded delta. `setPaused`, `setReducedMotion` and `setQuality(0|1|2)` control presentation without mutating gameplay. No camera/FOV or audio output is created implicitly.

## Effects and ownership

`particles` and `trail` use bounded native Three.js point primitives; trails retain emitted world-space samples rather than claiming an engine-independent ribbon shader. `material` uses isolated cloned emissive materials and restores original material ownership on disposal. Multiple effect owners cannot target the same material.

Bindings name an exported anchor, optional parameter and active states. Particle/trail bindings declare capacity, lifetime and local/world space; optional rate, size, linear RGB[3] or #RRGGBB color and velocity have bounded defaults. Linear RGB arrays remain linear; hex strings use Three.js color handling. Material effects additionally name an actual target node and bounded maxIntensity. `qualityMin` and `reducedMotionScale` are optional bounded controls.

The adapter caps32 effect bindings,16384 particles per binding and65536 aggregate capacity, with any tighter package maxParticles budget enforced. Active density decreases at lower quality. Pause freezes simulation; cancellation/reset clears phase-owned particles; disposal removes owned objects, geometry/material resources and mixer listeners/caches. It does not dispose host-owned model geometry, source materials or shared textures.

## Verification and other engines

`tests/test-model-animation-engine.cjs --protocol` labels simulated API contract checks. `--real` loads an existing configured Three.js module for actual Node animation/mixer tests, without claiming a renderer. `tests/test-model-animation-engine.py --project-root PATH --package PACKAGE [--package PACKAGE ...] --output NEW_DIR` runs actual local Three.js/WebGL/browser package verification, using existing task-local test dependencies and an installed configured browser. It never installs dependencies or downloads a browser.

The browser bridge verifies actual GLB hashes, clip bindings, skinned-vertex deformation, anchors/coordinate direction, vehicle articulation, speed/warp requests/cancellation, pause, actor-copy and lifecycle behavior. It emits hashed runtime-test JSON, runtime-capture PNG and performance-profile JSON. Performance records CPU update/render submission and actual renderer counters, not GPU timings or qualification of the user's target device. Browser page requests are constrained to the exact loopback fixture endpoint; this is not an OS network sandbox. Evidence is fixture acceptance, not human production approval.

For Babylon.js, Unity, Unreal or Godot, hand the same semantic motion contract to the existing compatible animation/movement/material/VFX owners and implement their actual native artifacts. Their state graphs and particle systems are not contained in the GLB. Record native results only when the selected tools exist. Phaser's2D path needs an explicitly selected sprite/pre-rendered conversion. Adobe integrations and vendor presets are unsupported throughout this workflow.
