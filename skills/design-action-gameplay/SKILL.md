---
name: design-action-gameplay
description: Specify fair, readable action gameplay across player verbs, combat timing, enemy decisions, perception, encounters, feedback, and deterministic tests. Use for melee, ranged, ability, dodge, lock-on, enemy AI, fog or visibility, and encounter tuning.
---

# Design Action Gameplay

## When to use

- Designing or revising an action combat loop.
- Tuning enemy behavior, perception, counterplay, or encounter roles.
- Turning game feel into implementable state and timing contracts.

## Workflow

1. Define every player verb with inputs, eligibility, commitment, timing phases, costs, outcomes, cancellation, and feedback.
2. Separate authoritative combat truth from animation, VFX, camera, audio, and UI presentation.
3. Model enemy perception, intent, action selection, motion, recovery, and return behavior explicitly.
4. Compose encounters from readable roles, space, pacing, pressure, recovery, and escalation.
5. Require anticipation, counterplay, consistent hit rules, and visible failure causes.
6. Create deterministic tests for state transitions, timing boundaries, targeting, occlusion, damage, and fairness.

## References

- Read [perception-and-fog.md](references/perception-and-fog.md) for shared perception truth, line-of-sight blockers, presentation-only fog, and AI/targeting integration.
- Read [encounter-acceptance.md](references/encounter-acceptance.md) for role composition, pressure budgets, fair transitions, tuning, and deterministic encounter fixtures.

## Output

- A combat and enemy decision specification.
- Encounter composition and tuning ranges.
- Feedback requirements and deterministic acceptance scenarios.

## Guardrails

- Do not hide unfair damage behind visual spectacle.
- Do not infer combat truth from rendered pixels or animation completion.
- Do not tune only from static numbers when playtest evidence contradicts them.
