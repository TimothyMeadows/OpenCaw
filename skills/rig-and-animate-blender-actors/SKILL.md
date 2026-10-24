---
name: rig-and-animate-blender-actors
description: Rig, skin, constrain, and animate Blender 4.5 actors for verified handoff. Use for character deformation, mechanical articulation, armatures, weights, actions, root motion, pivots, sockets, and motion review before runtime delivery.
engines: [AGNOSTIC]
---

# Rig and Animate Blender Actors

## When to use

Use for Blender armatures, skin weights, constraints, IK/FK, actions, NLA, root motion, sockets, or runtime actor authoring handoff.

For native model-to-animation production, route through `build-model-animations` and its explicit fixed-batch authoring contract. Skinned characters, articulated mechanisms and rigid objects have different preparation and evidence requirements; independent wheels, steering/suspension pivots and ship anchors must exist in the actual model. Preserve standalone BLENDER connected-authoring policy outside that contract.

## Workflow

1. Freeze scale, axes, grounding, bind pose, skeleton identity, naming, deformation needs, and required action roles.
2. Build control and deform ownership explicitly; validate hierarchy, roll, constraints, IK/FK, and dependency cycles.
3. Weight at representative extremes and inspect shoulders, hips, joints, face, equipment, and detachable parts.
4. Author actions with stable frame ranges, loop policy, root motion, contacts, markers, and NLA ownership.
5. Test action transitions, attachments, retargeting assumptions, and exportable deform bones.
6. Hand the reviewed actor to `prepare-rigged-runtime-actors` for runtime manifest and gameplay proof.

Read [rig-animation-authoring-contract.md](references/rig-animation-authoring-contract.md) for rig, action, and evidence rules.

## Guardrails

- Do not bind gameplay truth to control bones or editor-only constraints.
- Do not rename a published skeleton identity without an explicit compatibility migration.
- Do not claim runtime readiness from a Blender playback alone.
- Use explicit owned/licensed clip sources and independently reviewed mappings. Adobe authoring products and service integrations are excluded from model-to-animation production.
