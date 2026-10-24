---
name: babylonjs-animate-actors
description: Integrate Babylon.js AnimationGroups, skeletons and actor transitions with explicit movement, instance and playback ownership.
engines: [BABYLONJS]
---

# Animate Babylon.js Actors

## When to use

Connect actor animation groups, blend poses, attach equipment or diagnose animation lifecycle errors.

## Engine and dependencies

Before edits or tool launches, run `resolve-engine.sh` and `resolve-skill.sh babylonjs-animate-actors`; require compatibility and respect task override scope. Inspect Babylon/loader versions, rig and clip contracts, gameplay state and presentation clock. Use authorized local assets under the selected art contract; do not infer generation permission.

## Workflow

1. Validate named `AnimationGroup`s, frame ranges, targeted nodes, skeletons, morphs and imported scale. Instantiate/clone actors through a supported asset-container path so each actor's skeleton and animation targets are independent where required.
2. Define state-to-group transitions, looping, `speedRatio`, weight and blending. Check APIs in the locked revision before using newer masks, additive modes or root-motion helpers. Shared clip data and actor-owned playback need distinct lifetimes.
3. Choose one movement owner. Keep clips in place or route explicitly extracted root motion through the collision-aware gameplay controller; direct animation of body transforms must not fight the physics step.
4. Subscribe to end/loop observables only where needed and retain handles. Interrupted/replaced actions invalidate old callbacks. Animation events may request presentation, while damage and progression remain governed by gameplay rules.
5. Match skeleton attachments to named nodes/bones with documented offsets. Decide pause, slow motion and culling behavior without allowing presentation clocks to change authoritative outcomes.
6. On actor removal, stop owned groups, detach observers and dispose actor-owned groups/skeleton resources; preserve shared assets until their final owner exits.

## Output and verification

Deliver a clip/target manifest, transition rules and movement/cleanup adapter. Test simultaneous copies, missing targets, interrupted one-shots, pause/resume, despawn during a callback and repeated scene loads. Capture blends, attachments and foot contact in the actual browser; group-state assertions cannot prove pose quality. Use [group animation documentation](https://doc.babylonjs.com/features/featuresDeepDive/animation/groupAnimations) matching the host revision.
