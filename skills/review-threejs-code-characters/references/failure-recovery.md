# Reviewer decisions and escalation

- `pass`: every frozen question is answered by current evidence with no material gate-specific gap.
- `revise-code`: the contract is clear, but visible implementation or current evidence fails it.
- `revise-spec`: the packet exposes a contradictory, impossible, or materially incomplete acceptance contract.
- `request-input`: an external decision is required to judge the frozen question responsibly.
- `stop`: reviewer independence, evidence integrity, selected pipeline, or required tooling cannot be established.

For every non-pass decision, provide a stable lowercase failure class and concise remaining gaps. Describe what is observed; do not prescribe or execute the builder's next implementation strategy. A later review must be a fresh concrete invocation and bind to the new hashes.
