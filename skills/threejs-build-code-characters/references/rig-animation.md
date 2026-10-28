# Rig and animation contract

## Static

- Keep `skeletonId` null, influence count zero, and clips empty.
- Still expose deterministic update and dispose behavior when the host factory contract requires them.

## Articulated

- Use explicit semantic pivots or joints and deterministic transform ownership.
- Prove representative poses, limits, contacts, attachments, and reset behavior.
- Do not report skinning metrics for an articulated hierarchy.

## Skinned

- Declare a stable skeleton identity and cap influences per vertex.
- Bind semantic roles independently of array order or exporter naming.
- Prove bind/rest pose, deformation range, required animation roles, clip looping, root-motion ownership, contacts, and attachment/socket behavior.

## Every moving actor

- Keep time inputs explicit and deterministic.
- Avoid hidden global mixers, clocks, caches, event listeners, and retained scene references.
- Exercise repeated create, update, animation, attachment, reset, and dispose cycles.
- Measure the representative actor count; a single isolated actor is not sufficient evidence for a multi-actor budget.
