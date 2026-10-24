# Source and capability ledger

Bubo source: Timothy Meadows, MIT, commit `f597fcab07f0dc3e1c4709f23fae4a028cf04373`.
Unmodified selected originals are preserved in `vendor/bubo/`, including LICENSE.
These originals are attribution/audit sources and are excluded from compilation.

| Component | Runtime treatment |
| --- | --- |
| WorkspaceGuard/IWorkspaceGuard | Adapted into shared ../asset-production/Workspace, including project containment, Git metadata and reparse-point rejection; streaming hashes and atomic persistence added. Infrastructure/Workspace preserves this runtime's public facade. |
| ToolRegistry/IAgentTool/ToolRequest/ToolResult | Registry registration and deterministic case-insensitive lookup adapted into Application/StageRegistry; production stages register native functions. Coding tools and sandbox registration excluded. |
| TranscriptEvent | Adapted into Domain/AuditEvent and written on each state transition. |
| WorkspaceGuardTests | Original retained for audit; traversal, reserved metadata, junction/root, lock and containment cases adapted into the executable regression suite. |
| Stage runner, native processes, setup, asset manifests, approvals, finishing integration | Newly implemented OpenCaw asset-specific code; no Bubo coding loop, inference providers, Docker, bootstrap, or fixed destinations imported. |
| Shared native execution mechanics | Workspace/process ports, owned-process lifetime cleanup, persistence and audit append are reused by model-to-animation through ../asset-production/. Proof application stages remain separate and retain their existing interfaces. |

This native runner is not an operating-system sandbox. It never accepts licenses,
downloads during generation, changes sibling repositories, or generates approval.
Approval receipts record assertions made by the explicit caller; identities are not
cryptographically authenticated. Human review remains a separate operation.
