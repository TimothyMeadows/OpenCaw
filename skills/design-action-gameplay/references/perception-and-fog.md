# Perception and Fog

## Shared authoritative truth

- Define one deterministic perception service for player targeting, enemy awareness, AI decisions, visibility-sensitive abilities, and tests.
- Keep perception state in simulation data. Fog, lighting, shaders, particles, and post-processing may visualize that state but never establish it.
- Distinguish at least `unseen`, `remembered`, and `currently-visible` when exploration memory is part of the design. Define exactly which gameplay actions each state permits.

## Visibility queries

- Specify observer origin, target sample points, range, field of view, height or layer rules, and blocker masks.
- Use bounded spatial candidate selection before expensive line-of-sight checks.
- Define a deterministic result for boundary contact, grazing geometry, missing collision data, moving observers, and moving blockers.
- Version or invalidate cached visibility when relevant transforms, blocker topology, teams, or perception rules change.
- Keep ray or query budgets explicit. Spread noncritical refresh work over time without delaying fairness-critical changes.

## Dynamic blockers

- Give doors, smoke, walls, terrain, destructibles, and temporary effects explicit blocker identities and lifecycle events.
- Apply topology changes atomically so targeting, AI, abilities, and presentation observe the same generation.
- Fail closed for gameplay permissions when required blocker data is unavailable; expose the degraded state for diagnostics.
- Test blockers appearing or disappearing during aiming, attacks, pursuits, and ability resolution.

## AI, targeting, and fairness

- Drive acquisition, suspicion, investigation, loss, reacquisition, and return behavior from the shared perception result plus explicit memory timers.
- Require the same blocker and range rules for equivalent player and enemy actions unless an asymmetry is deliberately documented.
- Make target selection stable under equal scores with a deterministic tie-breaker.
- Telegraph when an actor gains actionable awareness. Do not let presentation lag hide a gameplay state that can already inflict consequences.
- Define grace windows, memory duration, last-known-position behavior, and cancellation when visibility changes mid-action.

## Presentation-only fog

- Render fog from authoritative visibility data through the host renderer's normal presentation boundary.
- Treat interpolation, blur, noise, edge treatment, reveal animation, and color grading as visual choices only.
- Preserve an accessible fallback that distinguishes current visibility from remembered exploration without color or subtle opacity alone.
- On presentation failure, retain correct gameplay behavior and expose a diagnostic rather than reconstructing truth from pixels.

## Deterministic fixtures

- Use fixed coordinates and blocker shapes for clear, blocked, grazing, outside-range, outside-angle, height-separated, and same-position cases.
- Test dynamic blocker generations, simultaneous movement, cache invalidation, team changes, target tie-breaks, and query-budget exhaustion.
- Assert identical perception results with fog enabled, disabled, reduced, or replaced.
- Record performance for representative observer, target, and blocker counts with the same fixture seed.
