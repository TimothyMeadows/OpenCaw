---
name: test-playable-games
description: Verify playable games through deterministic review states, risk-based system tests, real controls, representative devices, performance evidence, and player-experience checks. Use for game QA, regression planning, balance verification, asset review, or release confidence.
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
6. Capture concise evidence with reproduction steps, expected and actual behavior, severity, and residual risk.

## Output

- A risk-based game test matrix.
- Pass or fail evidence with screenshots, traces, videos, metrics, or logs.
- A release recommendation and prioritized defect list.

## Guardrails

- Do not treat a scripted unit test as proof of game feel.
- Do not use production accounts or saves for destructive QA.
- Do not approve a game after testing only the happy path or one device class.
