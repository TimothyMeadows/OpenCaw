# Ordinary Task Execution Contract

## Purpose

Turn an ordinary request into a bounded, resumable task using the existing `.ai/tasks/<task>/` structure. This extends task execution, not the delivery-mode hierarchy. Populate the contract from the conversation; do not make users learn placeholder syntax or repeat decisions already established.

Use [the task template](task-template.md) for substantial work. Existing task files are left untouched by scaffolding. When continuing legacy work, merge only missing sections after inspecting the current instructions and user edits. Small changes do not require an elaborate experiment ledger.

## Contract and baseline

Before implementation, record the deliverable paths, scope/exclusions, source material, expected observations, required acceptance IDs, and applicable authorization. Use the existing [acceptance-evidence matrix](../../verify-and-explain/references/acceptance-evidence-matrix.md), with its eight columns and `verified`, `contradicted`, `inferred`, `unknown`, and `stale` verdicts.

Keep the matrix in `TASK.md`, or provide its project-relative file with `--acceptance`. It must have unique stable IDs and exactly one real table, not a fenced example. Escape cell-internal pipes as `&#124;`. Put `- Optional acceptance IDs: none` in `TASK.md`, replacing `none` only with a comma-separated list of predeclared nonblocking IDs. Declare their residual risk before verification. Required rows must be verified for completion; optional rows may be inferred/unknown, but contradictions and stale evidence still block.

Capture a relevant reproduction, behavior observation, or measurement before editing. Compare the same workload and environment when claiming an improvement. Include uncommitted and untracked candidate files; HEAD alone does not identify them. Preserve unrelated user work. Undo only the agent's unsuccessful changes, not the whole worktree.

For meaningful experiments, record hypothesis, bounded change, observation, keep/revert disposition, and the evidence that motivates the next approach. Do not repeat an unchanged failed strategy without an identified reason; a bounded retry after an observed transient failure can be legitimate.

## Requested, observed, and enforced

Keep these categories separate in the task's capabilities table:

- Requested policy: permitted paths/actions, required tools, reviewer isolation, and agreed execution bounds.
- Observed availability: capabilities or settings actually exposed by a trustworthy interface, with relevant evidence.
- External enforcement: restrictions actually applied by the host, sandbox, broker, or service.

Mark unavailable model/effort/usage settings explicitly; do not infer them from the agent's identity. Optional missing telemetry does not block useful work. Required missing tools, sources, or reviewer isolation do block the affected work. Confirm one required source is readable before a long execution window. Never claim that Markdown configures model effort, caps spending, or creates a sandbox.

The host/orchestrator is responsible for hard wall-clock limits, cancellation, tool permissions, and spending enforcement where supported. Task commands are cooperative checks, not a hostile-filesystem sandbox or an authorization service. Do not store credentials, environment values, personal paths, or provider secrets in task evidence.

## Checkpoints and resumption

These commands require existing Python 3.9+, Git, and the normal OpenCaw Bash runtime. Issue creation also requires authenticated `gh`. Nothing is installed automatically. Run commands from the mounted baseline, or prefix their paths with the mount name from the host root.

```bash
./commands/record-task-checkpoint.sh checkout-fix \
  --artifact src/Checkout.cs \
  --artifact tests/CheckoutTests.cs \
  --artifact config/checkout.json \
  --evidence .ai/tasks/checkout-fix/evidence/tests.txt \
  --status ready-for-review \
  --next-action "Review current evidence and prepare the human readiness summary."

./commands/validate-task-checkpoint.sh checkout-fix --phase resume
./commands/validate-task-checkpoint.sh checkout-fix --phase complete
```

Record after meaningful stages and before handoff. Finalize task notes first: `TASK.md` is hash-bound too. Declare every relevant input, implementation, configuration, output, and evidence file. Repeated `--artifact` and `--evidence` flags accept regular project-relative files; symlinks and path escapes are rejected. Checkpoints never modify or stage candidate files.

The checkpoint stores the actual Git HEAD, SHA-256/size/executable state of declared files, task contract, acceptance matrix, external-operation state, status, window, and concrete next action. Files are hashed regardless of whether Git tracks or has committed them. The current project must be its own Git root and have a commit. Checkpoints are numbered under the task's `checkpoints/` directory, and the latest is always used. Retain their history and referenced failing/superseded evidence.

A successful validation establishes only mechanical freshness of **declared files**, not whole-workspace coverage, semantic correctness, or an external system's current state. Work in a quiescent workspace: repeated hashing detects ordinary drift but is not an atomic snapshot against hostile concurrent writers. Inspect referenced files and current external observations before trusting the handoff. Missing or changed evidence is a blocker, not an invitation to regenerate a passing label. Re-running affected checks is required; rehashing old output does not refresh proof.

`--phase resume` permits unfinished acceptance conditions so investigation can continue. `--phase complete` additionally requires ready-for-review/completed status, saved evidence, acceptable matrix verdicts, and no pending external-write outcomes. Both reject stopped/blocked/exhausted windows. Validation is read-only and does not publish anything. Semantic review and the applicable readiness gate remain mandatory.

Checkpoint only after context cleanup when that cleanup changes the task file. If later compaction rewrites a bound file, treat the checkpoint as stale and inspect the change. Do not use ordinary checkpoints to bypass Goal ordering, reset Gauntlet, or replace its fresh critics, immutable events, fingerprints, budgets, or publication checkpoints.

## Execution windows

Use agreed limits rather than inventing a new universal default:

```bash
./commands/record-task-checkpoint.sh checkout-fix \
  --artifact src/Checkout.cs \
  --next-action "Run the focused recovery check." \
  --deadline 2026-10-08T18:00:00Z \
  --failed-epochs 1 --max-failed-epochs 2
```

The deadline must be canonical UTC. Counts are observations supplied by the executor; these commands cannot measure an unseen agent session. Check bounds before each build/audit/full-validation step, not just at handoff. A full-validation epoch is one frozen candidate evaluated against the agreed suite; targeted diagnosis does not reset its count. The existing Gauntlet window remains unchanged.

Later checkpoints inherit omitted bounds and failure counts. They cannot silently lengthen an existing window or lower its failure count. At exhaustion, recording saves a stopped checkpoint and the next action; validation refuses resumption. A stopped/blocked status remains stopped across later checkpoints unless explicit human reauthorization is supplied. To start another authorized window, preserve prior records and pass `--reauthorize-window "<explicit human authorization reason>"` with the new deadline/count as appropriate. This input records authorization evidence; it does not independently authenticate the human or grant tool permissions. Do not infer it from a generic request to continue unrelated work.

## External-write recovery

Task issue creation writes durable intent under `operations/create-issue.json` **before** its GitHub POST. The operation identity binds the stable task name to GitHub's numeric repository identity. An exact marker is included in the issue body. Repository reads use paginated REST issue listings including closed issues, not title matching or indexed search. Requests are pinned to `github.com`; credential-bearing/plaintext/other-host origins are rejected, and the host repository is never replaced by a parent or mounted-baseline fallback.

On an interrupted result, the next run inspects the remote marker. One matching issue repairs local tracking; multiple matches block. A confirmed journal repairs a failure that occurred before `TASK.md` or `OPEN_ISSUES.md` was saved. Imported/legacy links in the explicit Issue section are checked against the same repository and reused. Closed issues are not re-added to open-issue tracking. Standalone issue creation now requires its task file to exist.

```bash
./commands/create-task-issue.sh checkout-fix --reconcile-only
```

This may repair local records but never creates a remote issue. **No match does not prove that an earlier write failed.** After an ambiguous POST, automatic re-creation stays blocked. Only explicit human investigation and authorization permits:

```bash
./commands/create-task-issue.sh checkout-fix \
  --retry-confirmed-absent "Owner inspected the remote outcome and explicitly authorized another attempt."
```

The previous attempt and reason are retained. Do not remove the journal to force a retry. A local lock serializes participating task commands and their open-issue updates. An abandoned lock must be investigated before removal; it is never auto-deleted as stale. This is not a distributed exactly-once guarantee: independent workspaces or legacy writers need external coordination, and providers with true idempotency support should use it. Mutable journals/checkpoints are inspectable recovery records, not tamper-proof security attestations.

## Verification

Run the offline regression suite with `bash tests/test-task-execution.sh`. It uses real temporary Git repositories and filesystem writes inside the test checkout, with a fake GitHub API. It never posts real issues. The suite is also included in `commands/validate-opencaw.sh`; use focused validation for this feature instead of incidentally running unrelated Gauntlet regression work.
