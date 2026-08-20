# Validation Summary

## Final Affected Matrix

- PASS: `skill-creator` quick validation for both character skills.
- PASS: Bash syntax for all changed character commands and tests.
- PASS: Node syntax for the profile transaction library, evidence analyzer, and browser harness.
- PASS: role, skill, command, style, role-map, role-language, art-pipeline, README, memory, and repository-map validators.
- PASS: `tests/test-memory-system.sh` (9 sections); repository map is current with 35 semantic entries.
- PASS: `tests/test-selected-capability-import.sh` (7 sections), including existing GLB/FBX rigged-actor behavior.
- PASS: `tests/test-art-pipelines.sh` (6 sections), including unchanged generic CODE callers.
- PASS: `tests/test-code-character-contract.sh` (5 sections).
- PASS: `tests/test-code-character-skills.sh` (4 sections).
- PASS: `tests/test-code-character-evidence.sh` (6 sections).
- PASS: `tests/test-code-character-integration.sh` (4 sections).
- PASS: `tests/test-blender-art-capabilities.sh` (8 sections) and `tests/test-external-asset-library.sh` (7 sections), preserving adjacent art-pipeline ownership.
- PASS: source-identity exclusion scan and `git diff --check`.
- PASS: Goal completion report generation and live topology review for PRs #117–#120; every PR is open, targets its recorded stacked base, is GitHub-reported mergeable, and has auto-merge disabled.

## Behavior and Compatibility Evidence

- Generic `code-model-manifest` version 1 creation, validation, pass order, retry behavior, complete source ownership, and loaded-model rejection remain unchanged when no character profile is supplied.
- Machine calibration has a public transactional command and requires one all-pass plus one focused-fail hash-bound fixture report before a machine gate can pass; spec, manifest, or source changes stale registered calibration.
- A passing machine result requires exactly one current `machine-report` from the confined sandboxed browser path; arbitrary metric files and untrusted calibration reports cannot approve the gate.
- Browser reports bind profile, measurement specification, manifest, source, adapter, capture configuration, observation, and artifacts; fixture reports remain untrusted.
- Structure evidence covers semantic parts and anchors, stable coordinates/pivot, finite transforms/bounds, grounding, attachments, and symmetry.
- Interaction evidence applies static, articulated, and skinned checks without declaration bypass, including skeleton, influence, finite-normalized-weight, role, representative-pose, deformation, contact, semantic interaction, and lifecycle facts.
- Optimization evidence covers deterministic construction, representative actor count, generic and character budgets, optional timing limits, and repeated resource ownership.
- Readability, form, identity, materials, style, and appeal remain independent-review decisions and receive no machine approval.

## Supported-Environment Boundaries

- No dependency, browser, Three.js package, Playwright package, installer, service integration, or fallback was added.
- ShellCheck is unavailable in Windows and WSL and is not claimed.
- A live Chromium capture is not claimed because this configuration repository intentionally has no host Three.js or Playwright installation. The deterministic capture orchestration passes end-to-end with a controlled Playwright test double, while real missing Three.js, Playwright, and Chromium stops all pass.
- Unrelated Brainstorm, Windows-bootstrap, and delivery-mode suites were not used as incidental gates for this feature. Their production code was unchanged.
