# Subagent Plan: gauntlet-progressive-prs

## Capacity
- Requested: 3
- Effective team: 3 concurrent contributors per phase (the lead plus two delegated lanes)
- Reason: Work is phased across disjoint implementation and audit assignments while the lead retains orchestration, integration, authoritative validation, and user communication. Sequential phases reuse the same three-person capacity without overlapping write ownership.

## Rules
- Resolve each lane role with `./commands/resolve-role.sh` before delegation.
- Use `explorer` for read-only lanes and `worker` for implementation lanes when Codex subagents are available.
- Worker lanes must declare disjoint write sets.
- Keep the main agent responsible for orchestration, critical-path blockers, integration, final verification, and user communication.

## Completed initial phase

The initial implementation lanes predate the adversarial replan. They are retained here as historical evidence, not as members of the current concurrently valid lane set.

#### lane-1
- Role: computer-science/devops-automator
- Agent type: worker
- Status: completed
- Scope: Implement Gauntlet integration-branch state, immutable progress-PR events, work-unit round linkage, merged-unit completion gates, and progress/final readiness behavior.
- Write set: commands/lib/gauntlet-common.sh, commands/create-gauntlet-file.sh, commands/validate-gauntlet.sh, commands/record-gauntlet-round.sh, commands/record-gauntlet-pr-event.sh, commands/create-gauntlet-completion-report.sh, commands/pr-readiness-check.sh
- Dependencies: none
- Expected output: Backward-compatible strict-mode Bash interfaces that make progressive work-unit PRs durable and keep promotion human-gated.
- Verification: Owned-script `bash -n`, focused fixture checks, and `git diff --check` for the write set.

#### lane-2
- Role: computer-science/qa-engineer
- Agent type: worker
- Status: completed
- Scope: Extend the isolated Gauntlet regression suite for integration branches, progress-PR event ordering, QA evidence, human merges, remediation PRs, completion, and task/goal compatibility.
- Write set: tests/test-gauntlet-flow.sh
- Dependencies: none
- Expected output: Network-free regression coverage for the progressive delivery contract and all retained Gauntlet invariants.
- Verification: `LC_ALL=C LANG=C bash tests/test-gauntlet-flow.sh`, ShellCheck, and `bash -n`.

#### lane-3
- Role: computer-science/technical-writer
- Agent type: worker
- Status: completed
- Scope: Rewrite the README mode comparison, Mermaid lifecycle, examples, Gauntlet delivery reference, commands, safety guidance, and progressive observability explanation.
- Write set: README.md
- Dependencies: none
- Expected output: A clear description of one integration branch, per-unit PRs with round QA comments, human merges, remediation PRs, and the final promotion boundary.
- Verification: `bash commands/validate-readme.sh`, Mermaid/source inspection, and `git diff --check -- README.md`.

## Completed hardening phase

#### lane-4
- Role: computer-science/devops-automator
- Agent type: worker
- Status: completed
- Scope: Bind every recorded SHA and progress-PR lifecycle observation to real local Git refs/objects and live GitHub state; add portable per-Gauntlet serialization/CAS; add an immutable promotion-QA event that alone can reopen a passed Gauntlet.
- Write set: commands/lib/gauntlet-common.sh, commands/record-gauntlet-round.sh, commands/record-gauntlet-pr-event.sh, commands/record-gauntlet-promotion-qa.sh, commands/pr-readiness-check.sh, commands/create-gauntlet-completion-report.sh, commands/create-gauntlet-file.sh
- Dependencies: Initial command vocabulary and independent adversarial-audit findings were complete before this phase began.
- Expected output: No nonexistent/stale commit, fabricated PR state, unrecorded terminal remediation, lost ledger update, or evidence overwrite can pass the mutation interfaces.
- Verification: owned-script `bash -n`, ShellCheck warning-level scan, deterministic fake-`gh` checks, concurrent recorder probes, and `git diff --check`.

#### lane-5
- Role: computer-science/security-engineer
- Agent type: worker
- Status: completed
- Scope: Reconstruct round, progress-PR, and promotion-QA ledgers as anchored one-to-one evidence maps; reject hashes replayed from unrelated sections, duplicate paths, stale hashes, invalid terminal transitions, and unconsumed critic rounds.
- Write set: commands/validate-gauntlet.sh
- Dependencies: The promotion-event schema was frozen and communicated before validator implementation.
- Expected output: Validation trusts only the corresponding canonical ledger line and independently rejects forged or incomplete lifecycle history.
- Verification: focused copied-fixture tamper probes, Bash syntax, ShellCheck warning-level scan, and `git diff --check`.

#### lane-6
- Role: computer-science/qa-engineer
- Agent type: worker
- Status: completed
- Scope: Replace dummy SHAs with real commits/refs, provide deterministic live-GitHub fixture observations, and add adversarial tests for stale/nonexistent SHAs, wrong-section/duplicate ledger replay, terminal remediation authorization, close-before-QA, and concurrent mutation safety.
- Write set: tests/test-gauntlet-flow.sh
- Dependencies: The mutation and validator interface contract was frozen and communicated before fixture implementation.
- Expected output: A fully offline regression suite that would fail on each audit repro and pass only with real Git/GitHub/ref and transactional evidence binding.
- Verification: focused Gauntlet suite, Bash syntax, ShellCheck warning-level scan, and `git diff --check`.

## Integration
- Merge order: lanes 1-3, main-agent policy/skill/role/context integration, lanes 4-6 evidence hardening, lanes 7-9 temporal/integrity closure, then final main-agent integration.
- Conflict risks: Hardening lanes have disjoint write sets but share a frozen promotion-event schema; lane-4 owns mutation semantics, lane-5 owns independent replay, and lane-6 owns fixture simulation. The main agent owns cross-lane integration and documentation updates.
- Final verification: Main agent runs the focused suite, command/skill/role/README validation, full OpenCaw validation in the supported environment, ShellCheck, repository-map status, and `git diff --check`.

## Final audit-closure lanes

### lane-7
- Role: computer-science/devops-automator
- Agent type: worker
- Status: in progress
- Scope: Close final command-layer temporal and replay findings, including numeric selectors, equal-second causal ordering, live promotion invariants, and time-aware manifest/quality/supersession authorization at publication-checkpoint issuance.
- Write set: commands/lib/gauntlet-common.sh, commands/validate-gauntlet.sh, commands/record-gauntlet-round.sh
- Dependencies: Lanes 4-6 and the independent adversarial findings are complete enough to define exact failing shapes.
- Expected output: Frozen command hashes whose replay cannot use future approvals or stale lexical selectors.
- Verification: owned-script Bash syntax, ShellCheck warning-level scan, focused negative fixtures, and `git diff --check`.

### lane-8
- Role: computer-science/qa-engineer
- Agent type: worker
- Status: in progress
- Scope: Harden the isolated test harness, add boundary regressions for numeric ordering, same-second chronology, live promotion state, historical revisions, and future-approval publication checkpoints, then run one authoritative frozen-suite execution.
- Write set: tests/test-gauntlet-flow.sh
- Dependencies: Lane 7 command interfaces must freeze before the authoritative run.
- Expected output: One deterministic 8-phase result against exact reported command and test hashes.
- Verification: `LC_ALL=C LANG=C bash tests/test-gauntlet-flow.sh`, Bash syntax, ShellCheck, and `git diff --check`.

### lane-9
- Role: computer-science/security-engineer
- Agent type: explorer
- Status: in progress
- Scope: Independently audit immutable evidence selectors, timeline causality, manifest/quality generation replay, supersession inheritance, completion/promotion state, and exact Git/GitHub/ref binding.
- Write set: none
- Dependencies: Review each frozen command snapshot and issue a final verdict only after lane 7 closes every concrete finding.
- Expected output: PASS/FAIL with exact repros or a no-known-bypass verdict tied to final hashes.
- Verification: read-only source inspection, targeted fixture reasoning, Bash syntax, and diff checks.

## Results

### Result: lane-3 - completed - 2026-08-01T18:59:40Z
- Summary source: `.ai/tasks/gauntlet-progressive-prs/lane-3-summary.txt`

```text
README now documents the durable integration branch, automatic work-unit and remediation PR publication, round-by-round critic and QA evidence, human-only merges, same-PR failure iteration, integration remediation, and final human-gated promotion. README validation passed with 33 anchors, 59 commands, and 11 paths; diff and obsolete-claim scans passed.
```

### Result: lane-2 - completed - 2026-08-01T19:12:34Z
- Summary source: `.ai/tasks/gauntlet-progressive-prs/lane-2-summary.txt`

```text
Expanded the isolated Gauntlet regression suite to 8 offline phases covering durable integration branches, required unit scopes, exact critic/QA/merge head SHA binding, scope and builder-strategy fingerprints, head drift, retry sequencing, immutable events, human merge gates, remediation cycles, completion SOURCE_SHA, promotion, and task/goal compatibility. At that lane snapshot, the then-current suite and static checks passed; later hardening and authoritative validation are recorded in the task evidence.
```

### Result: lane-1 - completed - 2026-08-01T19:16:41Z
- Summary source: `.ai/tasks/gauntlet-progressive-prs/lane-1-summary.txt`

```text
Implemented the hardened progressive Gauntlet delivery state: explicit base plus durable integration branch, frozen unit-scope fingerprints, exact reviewed-head SHA binding, actual builder-strategy fingerprints, immutable canonical PR events, strict round/QA/human-merge sequencing, remediation reopening, integrated-unit and completion gates, final SOURCE_SHA output, automatic progress readiness, and human-gated promotion. Owned Bash syntax, ShellCheck warning-level, help, executable, and diff checks passed.
```

### Result: lane-4 - completed - 2026-08-01T20:49:03Z
- Summary source: `.ai/tasks/gauntlet-progressive-prs/lane-4-summary.txt`

```text
Hardened every Gauntlet mutation against fabricated or stale evidence: real origin/repository, commit-object, exact local-ref, retained unit-merge ancestry, commit-tree artifact, live non-draft GitHub PR observations, and live same-PR comment queries are required. Added per-Gauntlet locking, source CAS, no-clobber evidence installation, deterministic work/remediation branches, unique QA-comment consumption, passed-state round/event/report guards, immutable remediation triggers, selective promotion-failure reopening, and exact integration-source binding. Owned Bash syntax, ShellCheck warning-level, diff, helper, reverse-ancestry, and no-mutation probes passed.
```

### Result: lane-5 - completed - 2026-08-01T20:49:03Z
- Summary source: `.ai/tasks/gauntlet-progressive-prs/lane-5-summary.txt`

```text
Rebuilt validation as anchored one-to-one replay for round, progress-PR, and promotion-QA ledgers. It rejects duplicate or unledgered evidence, stale or replayed hashes, malformed metadata, nondeterministic branches, missing/wrong/reused live QA comments, non-human merges, unconsumed close transitions, unauthorized remediation, invalid promotion archives, live progress PRs on passed runs, and any round after the completing integration pass. Owned Bash syntax, ShellCheck warning-level, and diff checks passed; later temporal/live-state closure and the final current-snapshot status are recorded in the task evidence.
```

### Result: lane-6 - completed - 2026-08-01T20:49:03Z
- Summary source: `.ai/tasks/gauntlet-progressive-prs/lane-6-summary.txt`

```text
Expanded the offline regression suite with real deterministic commit objects and refs plus exact fake-GitHub PR and issue-comment observers. Coverage proves repository/SHA/ref/artifact binding, retained merge ancestry, anchored ledger replay, missing/wrong/reused comment rejection, passed-state immutability, close sequencing, global lock contention and retry, terminal remediation authorization, promotion-QA pass/fail reopening, affected-unit selection, and final SOURCE_SHA binding. Lane-owned Bash syntax, ShellCheck warning-level, and diff checks passed; later boundary extensions and the final current-snapshot status are recorded in the task evidence.
```
