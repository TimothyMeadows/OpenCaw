---
name: gauntlet-flow
description: Run an explicitly requested OpenCaw Gauntlet as a persistent builder-versus-critic loop against a human-approved quality bar. Use when a user says `gauntlet`, `gauntlet mode`, `gauntlet flow`, or a planning artifact declares `Flow: gauntlet` for an ambitious deliverable that can be inspected with concrete evidence.
---

## When to use

Use only for an explicit Gauntlet request. Ordinary assignments remain task mode, and ordered multi-task delivery remains goal mode.

## Workflow

1. Create or link one parent task and issue, then create `.ai/gauntlets/<name>/GAUNTLET.md`.
2. Define the objective, inspectable artifact, constraints, and quality bar. If the lead proposes the bar, pause until the user approves it. Freeze the approved bar for the run.
3. Decompose the deliverable into stable, independently judgeable work units. Record split, merge, and supersession decisions; never erase failed work from the history.
4. Keep coupled work under one sequential owner. Use project-manager subagent lanes only for units with disjoint write sets.
5. For each unit, let a builder change and verify the real artifact. Then start a separate critic with fresh context.
6. Give the critic only the objective, current work-unit ID and frozen scope (or complete-artifact scope for integration), approved bar, constraints, and real artifact or verifier evidence. Do not provide the builder's history or justification.
7. Require the critic to inspect the artifact, compare it with the bar, check guardrails, and return `pass`, `fail`, or `blocked` with the largest remaining gap and next strategy.
8. Record every round with `record-gauntlet-round.sh`. On failure, route the gap to the builder, require and record the changed builder strategy in `Review Notes`, and use a new critic invocation for the next round. Keep the builder-strategy note out of the critic packet.
9. After every active unit passes, run a new integration critic over the complete artifact. Reopen affected units if integration fails; the bundled recorder conservatively reopens every active unit so no stale pass survives.
10. Generate `GAUNTLET_REPORT.md` only after complete validation, or generate an explicitly PR-ineligible stopped/blocked report when the user interrupts or progress is impossible.
11. Run final local validation and the normal human PR readiness gate. Open one final PR only after approval, then feed any post-PR QA failure back into the same Gauntlet and PR.

## Critic context packet

Provide only:

- the frozen objective and approved quality bar
- the current work-unit ID and frozen unit scope, or complete-artifact scope for integration
- applicable constraints and guardrails
- artifact paths, rendered output, tests, measurements, citations, or other direct evidence
- a request for `Artifact Inspected`, `Bar Comparison`, `Guardrail Results`, `Verdict`, `Largest Remaining Gap`, and `Next Strategy`

Prefer a native fresh subagent. If unavailable, use a fresh isolated session. If neither is possible, block the run rather than allow the builder to grade itself.

## Output

- `.ai/gauntlets/<name>/GAUNTLET.md`
- immutable `rounds/<item-id>/round-NNN.md` evidence
- latest work-unit and integration verdicts
- `GAUNTLET_REPORT.md` with completion or incomplete status
- a human-gated final PR readiness report when and only when the Gauntlet passes

## Guardrails

- Never activate Gauntlet mode implicitly.
- Never start building before the quality bar is approved.
- Never change the bar without new user approval; a change invalidates affected pass evidence.
- For an approved bar revision, retain prior rounds, add the revision to `Work Units / Unit History`, reopen every active unit, clear integration evidence, reset the current bar fingerprint to `pending`, and reset PR eligibility to `no`. The next accepted round freezes the new fingerprint.
- Never let a builder act as critic or reuse a critic invocation for another round.
- Never grade a builder-authored summary instead of the actual artifact or verifier output.
- Never parallelize coupled work merely because capacity is available.
- Do not impose an automatic attempt, time, cost, or diminishing-return limit. Continue until success or explicit user interruption, subject to safety, permission, platform-policy, and unrecoverable-blocker stops. This does not authorize unapproved paid services or external actions; record any user-approved resource boundary under constraints and treat reaching it as a permission blocker.
- A stopped or blocked report is not completion evidence and is never PR-eligible.
- Gauntlet mode retains human PR readiness approval and never authorizes merge, approval, or auto-merge.

## Commands

`./commands/create-gauntlet-file.sh "<name>" ["Title"] --task "<task-name>" [--dry-run]`

`./commands/validate-gauntlet.sh "<name|path>" [--phase ready|complete]`

`./commands/record-gauntlet-round.sh "<gauntlet>" "<item-id>" "<verdict>" "<builder-id>" "<critic-id>" "<native-subagent|fresh-session>" "<critic-report.md>" [--dry-run]`

`./commands/create-gauntlet-completion-report.sh "<gauntlet>" [--status complete|stopped|blocked] [--dry-run]`
