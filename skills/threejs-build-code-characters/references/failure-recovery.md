# Character gate failure recovery

Use these decisions consistently:

- `revise-code`: the frozen contract is sound and implementation or evidence must change.
- `revise-spec`: the frozen profile is wrong or incomplete; revise it explicitly and invalidate stale results.
- `request-input`: a user or product decision materially controls the acceptance target.
- `stop`: the selected pipeline, host dependency, rights basis, tool availability, or safety boundary cannot be satisfied.

After any non-pass result, change the concrete builder strategy. Reusing the same strategy is not a new attempt. When one failure class reaches the repeated-failure limit, do not continue `revise-code`; escalate to specification revision, input, or stop. Never weaken thresholds, relabel a fixture, change motion mode, or omit a required gate solely to obtain a pass.

Before retrying, verify the profile, generic manifest, source, evidence, and calibration hashes are current. Treat a stale result as evidence for an earlier revision, not as a current pass.
