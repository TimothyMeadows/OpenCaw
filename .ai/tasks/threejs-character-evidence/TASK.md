# Add deterministic Three.js character evidence and runtime gates

## Status

Implemented; local validation passed in Goal Flow.

## Flow

Goal Flow: enabled.

## Goal

`.ai/goals/threejs-code-characters/GOAL.md`

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/115

## Scope

- Add a test-only browser adapter and deterministic evidence command using only host-approved installed tooling.
- Capture configurable views, semantic masks, isolated parts, intended-size readability evidence, runtime captures, and revision comparisons.
- Add structure, grounding, attachment, symmetry, determinism, static/articulated/skinned motion, animation/contact, contextual budget, and repeated lifecycle gates.
- Add independently authored passing and focused failing calibration fixtures for every trusted machine gate.
- Enforce loopback-only OS-assigned ports, browser sandboxing, path containment, concurrency, and repository-confined outputs.

## Deliverables

- `commands/measure-code-character-evidence.sh` and its deterministic browser harness
- review-adapter reference contract used by the skills and profile
- runtime gate implementations and measurement report schema
- positive/negative calibration fixtures and end-to-end tests

## Acceptance Criteria

- Missing Three.js, Playwright, or browser tooling stops clearly without installation or fallback.
- Machine results are descriptive evidence tied to explicit contextual thresholds and calibration fixtures; they cannot independently approve aesthetic gates.
- Static, articulated, and skinned models receive only applicable checks and cannot bypass required behavior by declaring another mode.
- Repeated create/update/animation/attachment/dispose cycles expose stale state or resource growth.
- Every machine gate proves at least one passing and one failing deterministic fixture.

## Validation

- Node and Bash syntax, ShellCheck when available, and browser-harness security tests.
- Multi-view, semantic-mask, isolation, comparison, motion, budget, lifecycle, path, concurrency, and calibration regressions.
- Generic CODE and GLB/FBX rigged-actor compatibility regressions.
- `git diff --check`.

## Branch

- Base: `feature/threejs-character-skills`
- Head: `feature/threejs-character-evidence`
- Depends on: `threejs-character-skills`

## Review Notes

- Added explicit normalized grounding/contact thresholds, construction-run counts, and lifecycle-cycle counts to each generated machine-gate contract.
- Kept calibration analysis untrusted and limited trusted reports to sandboxed, loopback-only browser capture using host-installed Three.js and Playwright.
- Emitted descriptive checks for exactly the three machine gates; readability, form, materials, style, identity, and appeal remain reviewer-owned.
- Added deterministic pass/focused-fail fixtures for structure, interaction, and optimization plus static, articulated, skinned, attachment, symmetry, lifecycle, capture, comparison, budget, path, concurrency, and missing-tool regressions.
- Verified the capture orchestration with a controlled browser test double because this repository does not install Three.js or Playwright; separately proved clear no-install stops for missing Three.js, Playwright, and Chromium.
