# Ordinary Task Execution Reliability

## Goal

Implement the approved comparison findings as OpenCaw-native improvements and open one review PR. Do not merge.

## Scope

Extend ordinary task scaffolding, task issue recovery, candidate-bound checkpoints, focused verification guidance, and regression coverage. Preserve existing Goal/Gauntlet authorization, fresh critics, budgets, and canonical evidence. Do not introduce root-level progress/checks files or a new delivery mode.

## Assumptions

The current user request explicitly authorizes implementing these changes and publishing a review PR through the connected GitHub account. It does not authorize a merge or auto-merge. The implementation starts from main commit `694817be838c3292e130d63201d048fc56020697`.

## Execution Contract

Deliverables are the updated task commands/skills, `commands/lib/task-execution.py`, the execution-contract reference and task template, two checkpoint entrypoints, and the focused test suite wired into `validate-opencaw.sh`.

The working container has Python 3.13.5 and Git 2.47.3. Repository reads/writes use the GitHub connector because shell network access and `gh` are unavailable. No dependencies were installed. Observed capabilities are not statements about the user's machine or Codex configuration. No Gauntlet mode is active for this work.

## Work Instructions

1. Inspect current task scripts, verification matrix, mode guards, and repository rules.
2. Add durable external-write intent, marker reconciliation, local serialization, and fail-closed ambiguous recovery.
3. Extend task contracts and record/validate declared file identity, evidence, and execution bounds.
4. Add offline failure-recovery tests, review limitations, and publish for human review.

## Verification

- Optional acceptance IDs: A-006

| ID | Acceptance claim | Evidence class | Expected observation | Evidence location | Actual observation | Verdict | Limits and freshness |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A-001 | Ambiguous issue creation reconciles before retrying | automated | Lost responses/local persistence failures do not trigger a second POST; unresolved or duplicate outcomes block | evidence/regression-tests.txt | Issue recovery regressions passed | verified | Fake GitHub API; real local files and Git |
| A-002 | Declared candidate and evidence drift blocks reuse | automated | Dirty/untracked changes, changed HEAD/task, and missing evidence fail freshness validation | evidence/regression-tests.txt | Checkpoint freshness regressions passed | verified | Declared files only; not whole-workspace or semantic verification |
| A-003 | Bounds and incomplete evidence are not silently reset to completion | automated | Stopped/blocked/exhausted windows and required nonverified matrix rows block completion | evidence/regression-tests.txt | Completion and reauthorization regressions passed | verified | Cooperative checks; host enforcement remains external |
| A-004 | Existing work and history survive | automated | Existing task content, unrelated work, and prior attempts/checkpoints remain preserved | evidence/regression-tests.txt | Preservation, path, and locking regressions passed | verified | Participating local writers, not distributed locking |
| A-005 | Integration preserves existing delivery-mode contracts | automated | Bash entrypoints parse and retain the canonical Brainstorm guard; existing Goal/Gauntlet files unchanged | ../../reports/task-execution-reliability.md | Syntax/help checks passed; unchanged mode files excluded from the change set | verified | Full host-lifecycle integration was not executed |
| A-006 | Full repository suite and live GitHub CLI transport pass | automated | Existing full-suite and live CLI checks pass | ../../reports/task-execution-reliability.md | Not run in the connector-only checkout | unknown | Nonblocking for opening a review PR; must not be represented as passed |

## Review

The implementation received a separate source-review pass by the same agent, not an independent critic. The review tightened inherited bounds, malformed prior checkpoints, issue-response validation, symlink rejection, and fenced-example handling. The final focused run passed 53 tests. Python compilation, changed Bash syntax, and help entrypoints passed.

Remaining risk is explicit: Python 3.9+ is now required for the four task commands; live `gh` transport and the complete repository suite were not exercised here. Journals/checkpoints are cooperative records, not authenticated security attestations. Independent workspaces require external coordination for exactly-once behavior. Hash freshness does not establish semantic proof.

## Continuation

Status: ready for review, not merged. Code and focused verification are saved; review the PR and run broader integration in a full checkout. The next action is to inspect the review diff and validate the full host/CLI environment before merge. Do not bypass existing readiness or merge restrictions.

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/123
