---
name: rig-and-animate-blender-actors
description: Rig, skin, constrain, and animate Blender 4.5 characters and creatures for verified handoff. Use for armatures, weights, IK/FK, constraints, actions, NLA, root motion, sockets, deformation review, and preparation for runtime actor delivery.
---

# Rig and Animate Blender Actors

## When to use

Use for Blender armatures, skin weights, constraints, IK/FK, actions, NLA, root motion, sockets, or runtime actor authoring handoff.

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
