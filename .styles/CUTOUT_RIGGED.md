# CUTOUT_RIGGED.md

## Intent

Create segmented 2D characters, creatures, props, and bosses for puppet, cutout, or skeletal animation workflows.

## Production Rules

- Define root, hierarchy, pivots, rest pose, draw order, masks, attachment points, bone names, and export format.
- Segment parts where rotation or deformation is needed; use replacement drawings for hands, feet, faces, weapons, and extreme poses.
- Keep contact points stable and animation states named for runtime use.
- Combine rigged animation with cel swaps or sprite frames when deformation alone is not enough.

## Acceptance Checks

- No drifting pivots, detached limbs, unstable anchors, or broken draw order.
- Animation states document loop points, events, transitions, and gameplay timing.
- Rigs validate at gameplay scale against collision, VFX, and facing expectations.

## Role Fit

Use with `cutout-rig-animator`, `illustrative-2d-artist`, `pixel-artist`, and engineering roles that integrate animation runtime.
