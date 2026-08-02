# Add progressive Gauntlet PR delivery

## Status

Implementation is complete on `feature/gauntlet-progressive-prs`, but final publication remains blocked on an unrerun authoritative regression after the last production root-binding correction.

## Review Notes

- User correction: host disk pressure does not authorize deleting caches, temporary data, or any other files outside the resolved repository. Future storage blockers must stop with an exact report unless the user explicitly approves an external cleanup target.

## Goal

Replace Gauntlet's single-final-PR-only delivery model with progressive, externally visible review while preserving one coherent integration branch, fresh critics, integration validation, and human merge control.

## Delivery Contract

- Create one durable integration branch named `gauntlet/<gauntlet-name>` exactly at the approved delivery-base commit; freeze the parent task, objective, constraints/permissions, base identity, static delivery policy, approved quality fingerprint, and normalized unit-manifest fingerprint when the first progress PR is accepted.
- Open or update one progress PR per active work unit from `gauntlet-work/<gauntlet-name>/<item-id>[-remediation-N]` into the integration branch. This separate namespace is required because Git cannot store a branch beneath the existing `gauntlet/<gauntlet-name>` integration ref.
- Keep all builder/critic rounds for that unit on its progress PR and post each QA verdict as a PR comment.
- Bind every critic round, QA event, and human merge to a real commit, exact live same-repository GitHub head/base SHAs, current scope, unit-manifest, quality, and execution-contract fingerprints, current integration-tip ancestry, and a newly queried unique same-PR comment per QA verdict. The comment must carry a machine-readable binding to the verdict, reviewed SHA, referenced immutable evidence, and exact affected unit set, and retain its observed author, creation/update times, and body hash.
- Make every automatic progress-publication authorization an immutable `publication-checkpoints/<item-id>/checkpoint-NNN.md` record. Bind the approved contract/fingerprints, exact quality fingerprint and `Quality bar approved at` value, exact manifest fingerprint and `Unit manifest approved at` value, exact target and chain tip, exact work branch/head, remote-ref observations, and exact remediation trigger/root; require every bound quality/manifest generation and relied-on supersession edge to be approved and active at checkpoint issuance, require the checkpoint path/hash marker in the live PR body, and consume each checkpoint at most once.
- Persist and compare the builder's actual strategy for each attempt so a failed critic or QA cycle cannot repeat the same nominal approach.
- Allow disjoint unit PRs in parallel; dependent work starts only from merged integration-branch state.
- Explicit Gauntlet approval authorizes automatic progress-PR publication, but never merge approval, merge execution, or auto-merge.
- A unit is integrated only after its latest critic and QA pass, GitHub reports a same-repository PR with `mergedBy.is_bot=false`, its observed `baseRefOid` extends the gapless frozen-base chain to `mergeCommit`, and every applicable failure has its own later causally triggered remediation merge. Every initial/remediation work head descends from the then-current integration tip, and later heads on one open PR advance by fast-forward ancestry. Completion and readiness re-query every topology or remediation terminal PR rather than trusting locally replayable metadata alone.
- After all active unit PRs merge, reject origin drift, rewinds, divergence, chain gaps, unrecorded direct integration commits, or lost base ancestry, then run a fresh critic over the exact merge-chain tip.
- Integration or promotion-QA failure creates new remediation PRs against the same integration branch and invalidates stale affected evidence.
- Successful reporting creates an immutable completion event/ledger entry that binds a canonical projection hash of the complete report while excluding only its self-referential Immutable Completion Evidence section. Every older completion is consumed exactly once by a later promotion failure, while at most the latest is active. A later, semantically bound fail may supersede one prior promotion pass for the same active completion; no pass may follow that failure without remediation, reintegration, a new head, and a new completion. Direct state edits, stale merges, rounds, progress events, and report demotion cannot bypass this.
- Serialize every Gauntlet mutation with a portable atomic lock, compare-and-swap the source contract, and install immutable evidence without clobbering.
- A human-gated promotion PR from the integration branch to the original base remains the final delivery boundary, but it links the ordered progress PR and QA ledger instead of serving as the first review surface.

## Durable State and Commands

- Add required Progress PR, Completion, and Promotion ledgers plus delivery branch fields to `GAUNTLET.md`; store append-only publication checkpoints beside it and bind their one-time consumption into opened progress-PR ledger entries.
- Store immutable PR lifecycle events under `pr-events/<item-id>/event-NNN.md`.
- Store immutable successful-completion events under `completion-events/event-NNN.md` and require exact promotion-failure consumption.
- Give every work unit a durable single-line title and inspectable scope/acceptance boundary. Freeze the normalized sorted retained ID/title/scope definitions plus canonical supersession edges, require approved append-only manifest and matching scope-title revisions, and never delete or rename retained definitions. Every per-unit checkpoint, PR event, and round must use a unit and title/scope definition present in the manifest generation active at its timestamp. Unchanged exact units may retain evidence from an approved prior manifest; added, changed, superseding, superseded, or causally affected units may not. Supersession requires exactly one approved canonical Unit History marker binding the old scope fingerprint to comma-sorted replacements, a substantive reason, and canonical approval time, with no later evidence for the superseded unit. The replacement graph must be acyclic, terminate entirely at active units, and transfer every outstanding unit-local, integration, or promotion failure root to every active descendant leaf only when every edge on the path was approved no later than the replacement cycle's publication checkpoint, before the live PR creation time; later approval cannot retroactively authorize earlier work.
- Add `record-gauntlet-pr-event.sh` for `opened`, `qa-pass`, `qa-fail`, `merged`, and `closed` events.
- Add `record-gauntlet-promotion-qa.sh` for immutable final-promotion QA pass/fail evidence and authorized terminal remediation.
- Require an open progress PR before recording a work-unit critic round.
- Require every active unit's latest progress PR to be QA-passed and merged before integration or completion.
- Add `pr-readiness-check.sh --gauntlet-progress` for automatic progress-PR publication while preserving the existing human-gated `--gauntlet` promotion check.

## Compatibility

- Preserve task-mode human readiness behavior.
- Preserve goal-mode automatic per-task PR behavior.
- Preserve existing Gauntlet status, quality-bar, critic-isolation, immutable-round, stopped/blocked, and no-auto-merge guarantees.
- Treat existing `--gauntlet` as the final promotion readiness interface.

## Verification

- Extend the isolated Gauntlet regression suite with integration-branch, progress-PR-event, event-ordering, QA-evidence, merge, remediation, completion, and readiness cases.
- Use real fixture commits/refs and deterministic fake-GitHub PR/comment observations; reject nonexistent/stale or non-descendant heads, non-fast-forward same-PR updates, mismatched fetch or push origins, fork PRs, missing/stale/reused publication checkpoints or PR-body markers, wrong remote integration tips/base lineage, semantically stale or edited QA comments, broken `baseRefOid` topology, locally forged terminal state, bot merges, unrecorded direct integration commits, manifest deletion/revision forgery, report tampering, unconsumed completion/failure events, unauthorized or cyclic supersession, stale remediation, wrong-section replay, and concurrent overwrite/lost updates.
- Validate commands, skills, roles, README/Mermaid, shell syntax, ShellCheck, full OpenCaw behavior, and `git diff --check`.
- Prove task and goal PR behavior remain unchanged.

## Current Validation Evidence

- The capped authoritative run passed phases 1–5 and reached phase 6 before exposing that remediation-root replay did not compare dynamic resolution with the immutable publication-checkpoint root/hash.
- The resolver boundary now enforces that frozen root and hash. Bash syntax, warning-level ShellCheck for the changed command library, and scoped `git diff --check` pass at command-library SHA-256 `e0ffe331c63211880da9f6f68ac495a6222447e7d63dcfcade8f98b4c9cb729e` and test SHA-256 `d81d8099c5d77e43b2a5e3f465523a60b803b56999d2101d012795a151a3648c`.
- Per the user-directed scope cap, no further full-suite rerun was started. An 8/8 current-snapshot result and supported-host full OpenCaw validation therefore remain unproven and must not be inferred from historical lane results.

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/88
