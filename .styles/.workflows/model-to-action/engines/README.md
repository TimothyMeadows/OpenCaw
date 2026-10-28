# Selected-engine action presentation

`threejs-action.mjs` is an executable presentation adapter over actual baked composite GLB clips and an `opencaw-action-package/v1` timeline. The host provides its locked Three.js APIs, loaded GLB, canonical engine receipt and separate authoritative movement root. The reusable module imports nothing and performs no network access, installation, provider calls or simulation mutations.

## Integration

Resolve ENGINE.md and compatible engine skills before implementation. Verify model/package hashes and the current contract/definition/registry receipt before loading. The adapter validates receipt agreement, actual clip names/durations, binding identities, root ownership and bounded data. It cannot authenticate arbitrary caller objects or replace the canonical resolver.

```js
const movementRoot = new THREE.Group();
scene.add(movementRoot);
movementRoot.add(gltf.scene);
const actions = createActionPresentation({
  THREE,
  visualRoot: gltf.scene,
  movementRoot,
  effectParent: scene,
  animations: gltf.animations,
  actionPackage,
  engineSelection,
  onPresentationEvent: event => presentationLog(event)
});
actions.play('charge-and-cast', {targets: {target: [4, 1, -2]}});
actions.update(presentationDeltaSeconds);
actions.pause(true);
actions.cancel();
actions.dispose();
```

The action ID and target IDs must match the compiled package. `play()` validates and copies required finite world-space target points before replacing current playback. Target-array mutations cannot create homing. `maxDistance` is a visual resource bound checked against the incoming action's actual anchor pose at release. An action may charge and then fail cleanly at launch if its anchor or actor moved beyond that bound; no visual projectile is allocated and all current effects are cleared. The outgoing clip's pose cannot reject a valid incoming action. The host owns ability targeting and eligibility. Fireball arrival and markers do not deal damage, confirm contact, consume mana, or spawn an authoritative projectile.

## Rig and clock ownership

Use one presentation owner for a rig. The host must suspend or arbitrate an existing locomotion/MODEL_TO_ANIMATION mixer before this full-body action player owns the same skeleton. The adapter prevents duplicate action owners on the exact same visual root; it cannot discover arbitrary external mixers. Layered upper-body masks, IK targeting, body turning and simulation movement are separate engine work.

Skinned copies require a skeleton-aware clone; shared mutable bones across actors are rejected. Source clips/geometry/materials remain host-owned. This adapter allocates and disposes only its cue geometry, materials and scene objects. Composite root and ancestor transforms must stay in place; extracted-root actions require an explicitly implemented movement adapter and an appropriate source clip.

Supply one bounded presentation clock in seconds. Accepted delta is 0..0.25 by default, explicitly configurable up to 1 second. The player subdivides a delta at step/marker/cue boundaries so an attached release anchor is sampled at the declared instant. Pause freezes poses, cues and projectiles. Completion holds the final pose; cancel/reset/dispose restore the captured initial actor transforms and remove all owned effects. If gameplay is also writing those transforms, resolve that ownership conflict before playback.

If a presentation callback pauses the clock, playback stops at that boundary. Remaining events at the same instant stay pending until resume, and the unused portion of the interrupted update is discarded. Already acquired cue resources remain owned and valid; resuming does not repeat the consumed marker or cue.

`play` replaces the previous presentation and advances generation. `cancel`, `reset` and `dispose` invalidate old work. Synchronous event callbacks may cancel, reset, replace or dispose playback; stale steps/effects/completion do not continue into the replacement. Reentrant clock updates are rejected. Event history is capped at 128; sequence boundaries are capped at 8192 per action. Events carry instance/generation/action/time plus applicable step/cue data. They are presentation signals rather than exactly-once authoritative network or gameplay commands.

## Effects and cleanup

- `orb`: an owned low-complexity sphere attached to the real exported anchor, with bounded charge growth.
- `particles`: deterministic seeded CPU point primitives, fixed capacity and rate, bounded lifetime/backlog. Particles retain emitted world positions while their emitter follows the anchor.
- `projectile`: an owned sphere moving from the sampled release position to the captured fixed world point over the declared interval. It has no collision or hit detection.

Use `setQuality(0|1|2)` and `setReducedMotion(boolean)`. Quality 0 hides particles while retaining lightweight action/target cues; reduced motion lowers effect intensity/rate and removes charge scaling. No audio, haptics, camera shake or FOV changes are added implicitly. Effects clear on cue end, completion, cancellation, reset and disposal. `stats()` reports bounded history, particles, effect positions and owned resource counts; diagnostic counters do not prove absence of every driver/heap leak.

## Verification

`tests/test-model-action-engine.cjs` runs pure data checks and actual Three.js Node checks when the existing test package is available. Node evidence has no rendering claim. `tests/test-model-action-engine.py --project-root PATH --package PACKAGE [--package PACKAGE ...] --output NEW_DIR` runs actual local browser/WebGL checks against already exported models. It installs/downloads nothing; missing dependencies/browser return blocked with exit code 77.

Browser evidence includes source/model/package/adapter hashes, ordered steps, actual skinned deformation, anchors and exact fixed-target trajectory, pause/cancellation, resource cleanup, rendered PNGs and three typed hash-bound acceptance artifacts. Output under the fixture project's task cache uses `pathBase: project-root`; outer research output is marked `repository-root`. CPU submission timings and renderer counters through SwiftShader do not establish physical GPU or target-hardware readiness. Human acceptance remains separate.

For Unity, Unreal, Godot or Babylon.js, implement the semantic timeline and cues through the selected compatible engine owners and actual native assets/tools. This GLB does not contain a portable ability graph or particle system. Phaser's 2D path needs an explicitly selected sprite/pre-rendered handoff. Adobe integrations remain excluded.
