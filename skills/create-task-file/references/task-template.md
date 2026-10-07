# {{TASK_TITLE}}

## Goal

Describe the requested observable outcome.

## Scope

Name allowed changes, exclusions, and existing work that must be preserved.

## Assumptions

Separate established facts from unresolved decisions. Ask only when a missing
answer materially changes the outcome, safety, or authorization.

## Execution Contract

### Deliverables

List exact project-relative output paths and the expected result at each path.

### Sources and Starting State

Record relevant source paths or URLs and observation dates. For a behavioral
change, record a reproduction or measurement before editing. Identify the
candidate revision and relevant dirty/untracked files; a commit alone does not
identify uncommitted work. Do not reset unrelated work to establish a baseline.

### Authorization and Capabilities

| Capability | Requested policy | Observed availability | External enforcement |
| --- | --- | --- | --- |
| Tools and source access | Define required access | unavailable until checked | unavailable until confirmed |
| Write scope and external actions | Define allowed changes/actions | unavailable until checked | unavailable until confirmed |
| Review isolation | Define the required review method | unavailable until checked | unavailable until confirmed |
| Model, effort, and usage | Use configured session settings | unavailable unless exposed by a trusted interface | not established by this task text |

Probe one required source before a long run. Required missing access blocks the
relevant work; optional missing telemetry does not. Do not install software,
change providers, fabricate settings, or claim sandbox enforcement from prose.

### Execution Bounds

Record authorized time, retry/full-validation, and spending bounds, or explicitly
state that no task-specific bound was agreed. Distinguish advisory checks from
host-enforced limits. Check before every bounded action; stop at exhaustion and
preserve the next action. Only explicit human reauthorization starts a new window.
Existing Goal/Gauntlet mode contracts and stricter limits still apply.

## Work Instructions

Choose one bounded step, make the scoped change, run relevant checks, preserve
useful work, and record the result. For experiments, record hypothesis, change,
observation, keep/revert decision, and the reason for the next approach. Retry a
failed approach only after identifying new evidence or a relevant change.
Before retrying an external write, reconcile whether it already succeeded.

## Verification

Use the canonical `verify-and-explain` acceptance-evidence matrix below. Replace
the initial unknown row with independently judgeable claims and stable IDs before
implementation. Declare optional/nonblocking IDs and residual risk before
verification; never weaken acceptance to obtain a pass. Escape pipes within cells
as `&#124;` so the Markdown table remains machine-readable.

- Optional acceptance IDs: none

| ID | Acceptance claim | Evidence class | Expected observation | Evidence location | Actual observation | Verdict | Limits and freshness |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A-001 | Define the requested observable result | automated | Define the pass condition | unavailable | Not yet checked | unknown | Not yet observed |

## Review

Identify the actual review method, result, unknowns, and residual risk. A recorded
hash proves file identity, not correctness. Re-run affected checks after candidate
changes; copying old evidence into a new checkpoint does not refresh it. Required
claims must be verified before completion. Keep failed and superseded evidence.

## Continuation

Record current status, last verified candidate, remaining acceptance conditions,
pending external operations, decisions, and one concrete next action. Keep
execution details here or in this task folder, not root-level progress files.

For substantial work, use `record-task-checkpoint.sh` after meaningful stages and
before handoff, declaring every relevant candidate/input/output and evidence file.
Use `validate-task-checkpoint.sh --phase resume` before trusting a saved handoff and
`--phase complete` before completion/readiness. Hashes include declared dirty and
untracked files. Validation is deliberately scoped to declared files, not the
whole workspace. Re-inspect external state and semantic evidence separately.

A stale/missing checkpoint requires inspection and affected verification, not
blind regeneration. Checkpoints never grant publication or merge permission and
never replace Goal/Gauntlet canonical state or immutable evidence.

## Issue
