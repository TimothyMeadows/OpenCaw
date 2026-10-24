---
name: test-playable-games
description: Verify playable games through deterministic review states, risk-based system tests, real controls, representative devices, performance evidence, and player-experience checks. Use for game QA, regression planning, balance verification, asset review, or release confidence.
engines: [AGNOSTIC]
---

# Test Playable Games

## When to use

- Testing a vertical slice, gameplay system, level, or release candidate.
- Creating deterministic fixtures for hard-to-reach game states.
- Investigating control, combat, progression, persistence, visual, or performance defects.

## Workflow

1. Build a matrix across device, input, viewport, save state, game mode, system, and risk.
2. Prefer deterministic review routes or seeded states that do not modify real saves.
3. Test controls, camera, traversal, combat, enemies, inventory, objectives, feedback, pause, restart, and recovery as applicable.
4. Verify fairness and comprehension: anticipation, hit confirmation, target visibility, hazards, state changes, and failure causes.
5. Exercise persistence boundaries, repeated transitions, cleanup, mobile layout, and performance fixtures.
6. Capture concise evidence with build, engine/runtime, platform, inputs/devices, scope, reproduction steps, expected and observed behavior, status, artifacts, severity, and residual risk. Use explicit blocked/not-run verdicts with reasons for unavailable prerequisites; structural report validation is not gameplay acceptance.
7. Select compatible engine tooling through `resolve-skill.sh`. Browser QA may exercise a Unity or other engine's web build; it does not certify the native build or its native UI. Record which surface and build the evidence actually covers.
8. For UI, test modal exclusivity and pause policy, focus fallback/restoration, remapping/device changes, safe areas/text scale/localization, and HUD snapshot/event ordering, teardown, and repeated reopen.
9. For gameplay feedback, test overlapping effects, clock/pause ownership, expiration, interruption, repeated cleanup, and reduced-intensity alternatives. For haptics, test per-player/device routing, disabled/unsupported cases, API failure, cancellation, disconnect/reconnect, late callbacks, and stale-queue rejection. Mocks establish adapter behavior; physical output requires a supported controller or mobile device and an actual-device observation.

Use `validate-gameplay-review.sh --profile general|design|ui|feedback` for report structure. Specialized profiles require an environment/scope section and scenario evidence; a structurally valid report may still contain failed, blocked, or not-run scenarios.

## Output

- A risk-based game test matrix.
- Pass or fail evidence with screenshots, traces, videos, metrics, or logs.
- A release recommendation and prioritized defect list.

## Guardrails

- Do not treat a scripted unit test as proof of player experience or physically felt haptic output.
- Do not use production accounts or saves for destructive QA.
- Do not approve a game after testing only the happy path or one device class.
