# Progressive Gauntlet PR delivery validation

## Outcome

Implementation is present on `feature/gauntlet-progressive-prs`. Bounded static, documentation, skill, role-map, and task-plan checks pass. Final end-to-end validation is incomplete because the last authoritative run exposed an immutable remediation-root replay defect in phase 6; the defect is patched, but the user-directed scope cap intentionally stopped another full rerun.

## Passed checks

- `bash -n commands/lib/gauntlet-common.sh commands/record-gauntlet-pr-event.sh commands/pr-readiness-check.sh tests/test-gauntlet-flow.sh`
- `shellcheck --severity=warning commands/lib/gauntlet-common.sh commands/record-gauntlet-pr-event.sh commands/pr-readiness-check.sh`
- `bash commands/validate-readme.sh`
- `bash commands/validate-skill-safety.sh`
- `bash commands/generate-role-skill-map.sh --check`
- `bash commands/validate-role-language-alignment.sh`
- `bash commands/validate-subagent-plan.sh .ai/tasks/gauntlet-progressive-prs/SUBAGENTS.md`
- Focused autonomous-window policy regression across `AGENTS.md`, README, the Gauntlet skill, and the project-manager role.
- `git diff --check`
- Independent command and regression audits of terminal-state CAS, CRLF publication classification, stale-chain readiness, and immutable remediation-root replay.

## Authoritative regression status

- `tests/test-gauntlet-flow.sh` SHA-256: `c9eacfd19a552642c3eb6afc9202bd3b1810a34beee31d9bb8cac71829e41b45`
- Current `commands/lib/gauntlet-common.sh` SHA-256: `a2d8a52f34ca3b0b041f104d36eb9d4feef84d9afe1dae1901225e2cde200277`
- The capped run passed phases 1–5 and reached phase 6 on the immediately preceding command-library snapshot.
- Phase 6 proved dynamic remediation-root replay could diverge from the immutable publication-checkpoint root after same-second ledger tampering.
- The resolver now requires the dynamically resolved root to equal the checkpoint's frozen root, verifies the canonical evidence hash, and enforces `none`/`none` for initial work.
- A fresh 8/8 run against the current hashes was not performed. This is a validation caveat, not a claimed pass.
- The later policy-only update replaces unlimited continuation with a 45-minute/two-failed-epoch human reauthorization checkpoint and was validated with bounded static checks rather than another full-suite run.

## Environment note

`validate-role-skill-map.sh` validates all 47 references and then encounters the checkout's pre-existing non-executable `generate-role-skill-map.sh` mode on macOS. Invoking the generator explicitly with Bash reports that the generated map is current.

## PR readiness

Normal readiness remains blocked by the missing current-snapshot 8/8 result. A draft PR may be published only if the user explicitly accepts this validation caveat; merge and auto-merge remain unauthorized.
