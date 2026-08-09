# Simulation and bake contract

## Setup

Record solver type, Blender version, scene scale, fps, frame range, seed, substeps, quality, collision layers, effectors, control geometry, initial state, and target output. Separate preview settings from final settings.

## Cache ownership

Every required simulation declares cache identity, repository-relative path, bake owner, generated files, expected size, completion status, source/settings fingerprint, invalidation conditions, and portability. A cache is resolved only when present, bound to current inputs, and replayed successfully from a clean session.

## Acceptance

Review start-state settling, contact, penetration, tunneling, jitter, energy gain, volume loss, popping, frame continuity, loop seam, motion blur, and restart determinism. Test a low-cost diagnostic range before final bake.

Runtime VFX receives semantic timing and staged render or mesh output, never solver authority over gameplay state. Missing, external, stale, or partially baked required caches block clean delivery.
