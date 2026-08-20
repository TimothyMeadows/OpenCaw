# Validation Summary

## Focused Results

- PASS: `tests/test-code-character-evidence.sh` (6 sections).
- PASS: Node syntax for the analyzer and browser harness.
- PASS: Bash syntax for the command wrapper and focused test.
- PASS: JSON parsing for the profile, observation, evidence-report schemas and all calibration fixtures.
- PASS: browser-harness confinement and orchestration checks: OS-assigned loopback port, sandboxed headless launch, blocked service workers and external requests, repository paths, output locks, atomic reports, and failed-capture cleanup.
- PASS: missing Three.js, Playwright, and Chromium stop clearly without installation, fallback, sandbox disabling, or partial output.
- PASS: `skill-creator` quick validation for both character skills.
- PASS: command, art-pipeline, skill, role-map, role-language, and generated-map validators.
- PASS: source-identity exclusion scan and `git diff --check`.

## Calibration and Applicability

- PASS: independently stored passing and focused failing fixtures for `structure-integrity`, `interaction-runtime`, and `optimization-budget`.
- PASS: grounding, attachment, symmetry, semantic-part, semantic-mask, isolated-part, intended-size, comparison, determinism, lifecycle, contextual budget, and capture-security failures are descriptive and gate-specific.
- PASS: static checks use explicit not-applicable outcomes; articulated and skinned contracts prove applicable roles, motion, skeleton identity, and influence limits without mode-declaration bypass.
- PASS: repeated create/update/animation/attachment/dispose observations reject stale callbacks and resource growth.
- PASS: fixture reports remain untrusted; sandboxed browser capture reports are the only trusted machine-evidence mode and emit no aesthetic verdicts.

## Compatibility

- PASS: `tests/test-code-character-contract.sh` (5 sections).
- PASS: `tests/test-code-character-skills.sh` (4 sections).
- PASS: `tests/test-art-pipelines.sh` (6 sections), covering generic CODE behavior.
- PASS: `tests/test-selected-capability-import.sh` (7 sections), covering the existing GLB/FBX rigged-actor manifest surface.

## Not Run

- ShellCheck is unavailable in Windows and WSL and is not claimed.
- A live Chromium capture is not run because this configuration repository intentionally has no host Three.js or Playwright installation. The deterministic harness is exercised end-to-end with a controlled Playwright test double, while the real missing-tool paths are executable and passing.
