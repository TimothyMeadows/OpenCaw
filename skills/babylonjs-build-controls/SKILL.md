---
name: babylonjs-build-controls
description: Implement Babylon.js camera inputs, picking and player actions with modal isolation and device-aware feedback.
engines: [BABYLONJS]
---

# Build Babylon.js Controls

## When to use

Integrate camera inputs, world interaction or keyboard, touch and controller actions in a Babylon game.

## Engine and dependencies

Before edits or tool launches, run `resolve-engine.sh` and `resolve-skill.sh babylonjs-build-controls`; require compatibility and respect task override scope. Read the locked Babylon version, chosen camera, action bindings, local-player assignments and browser capabilities. Device input, XR and physics plugins remain explicit project choices.

## Workflow

1. Pick the camera/input manager deliberately: for example `ArcRotateCamera` for inspection or a selected gameplay camera with its own action adapter. Configure `camera.inputs` and `attachControl` consistently; `detachControl` on suspension and teardown. Avoid default camera keyboard bindings also moving the player unexpectedly.
2. Convert `scene.onPointerObservable` and keyboard/gamepad events into gameplay actions. Own each observer handle and remove it once. Keep simulation updates separate from event timing; clear held actions on focus loss, pointer cancellation and device disconnect.
3. Use `scene.pick`/ray picking with predicates, collision layers and stable entity mappings. Respect the active camera/viewport and transform state. Pick results indicate spatial hits, not permission to execute gameplay actions.
4. Route GUI/modal input before world interaction; define pointer capture/lock, drag thresholds and back/cancel. Only request browser-privileged interaction from a user gesture and preserve an unlocked path after rejection.
5. Apply per-player dead zones, sensitivity, rebinding and active-device prompts. A browser haptic adapter must capability-check the assigned controller, bound effects, honor intensity settings and stop on pause, disconnect or ownership change. Rejected promises and unavailable motors do not affect simulation.

## Output and verification

Deliver camera/action adapters, pick policy and ownership cleanup. Check touch/mouse parity, scaled canvases, split viewports, modal click-through, focus restoration, reconnect and held-action clearing. Test unsupported and cancelled haptic output; only physical hardware confirms tactile output. Inspect version-matched [Scene APIs](https://doc.babylonjs.com/typedoc/classes/BABYLON.Scene) for observable and picking signatures.
