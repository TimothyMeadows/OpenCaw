# Acceptance And Evidence Matrix

Use this reference when a claim has several acceptance conditions or requires more than one kind of proof. The matrix makes coverage and uncertainty inspectable; it is not a substitute for running the verification.

## Matrix contract

Create one row per independently judgeable acceptance claim. Use stable IDs so failures and later evidence refer to the same condition.

| ID | Acceptance claim | Evidence class | Expected observation | Evidence location | Actual observation | Verdict | Limits and freshness |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A-001 | Concrete behavior or invariant | automated, runtime, visual, performance, or external-state | Observable pass condition | Command, artifact, capture, metric, or target | What was actually observed | verified, contradicted, inferred, unknown, or stale | Coverage gaps, environment, revision, and observation time |

Split a row when its parts can pass or fail independently. When a claim needs complementary evidence, repeat the acceptance ID with a qualified suffix and explain why no single observation is sufficient.

## Evidence classes

- `automated`: deterministic tests, static checks, schema validation, or reproducible command output.
- `runtime`: behavior observed in the running artifact, including lifecycle and failure recovery.
- `visual`: screenshots, recordings, or inspected render states tied to a scenario and viewport.
- `performance`: measured metrics with units, workload, environment, sampling method, and a declared budget.
- `external-state`: a current observation of a system outside the repository, including target identity and observation time.

Choose the class that proves the claim. A successful build cannot verify runtime behavior, a screenshot cannot establish keyboard behavior, and a reachable endpoint cannot establish the deployed revision.

## Workflow

1. Freeze the candidate revision, environment, and acceptance claims before collecting evidence.
2. Define the expected observation and suitable evidence class for each row.
3. Exercise positive, negative, boundary, recovery, and permission-sensitive scenarios where they affect the claim.
4. Record the exact command or artifact, actual observation, revision, and relevant environment facts.
5. Mark contradictions directly. Do not average conflicting observations or hide them in an overall percentage.
6. Mark missing proof `unknown`; mark evidence invalidated by a newer revision or external change `stale`.
7. State the final result from blocking rows first, then residual risk and the smallest useful next action.

## Verdict rules

- `verified` requires evidence that directly observes the entire stated claim for the frozen candidate.
- `contradicted` means an authoritative observation violates the expected condition.
- `inferred` means evidence supports the conclusion indirectly; identify the missing direct observation.
- `unknown` means suitable evidence is absent, inaccessible, or inconclusive.
- `stale` means the evidence no longer represents the candidate or current external state.

An overall pass requires every required row to be verified. Optional rows may remain inferred or unknown only when their non-blocking status and residual risk were declared before verification.

## Evidence handling

- Prefer repository-relative artifact paths and exact revisions over transient console excerpts.
- Keep external observations minimal, time-bound, and free of credentials or private account data.
- Redact sensitive values without removing the fact needed to understand the result.
- Preserve failing evidence when it explains a later remediation; add new evidence rather than rewriting history.
- Say when a tool, environment, account boundary, or unavailable target limits the conclusion.

## Review checks

- Every acceptance claim has a stable ID, expected observation, evidence class, and verdict.
- Evidence locations exist or external observations name a reproducible inspection method.
- Each verified verdict is supported by evidence that directly matches the claim.
- Negative and recovery behavior are covered where failure could lose data, weaken access control, or misstate delivery.
- Performance results include units, workload, environment, and budget.
- Visual evidence identifies the state and viewport it represents.
- External-state evidence identifies the target, immutable identity when available, and observation time.
- The summary reports contradictions, unknowns, stale evidence, and residual risk without overstating confidence.
