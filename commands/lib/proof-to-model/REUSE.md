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
| Explicit finishing preparation and conservative proxies | Newly authored OpenCaw settings validation, stage-local snapshots, working-low voxel preparation, real QuadriFlow completion checks and measured kdop-26 convex proxies. Original high meshes remain baking sources; no external helper/application code or automatic repair backend is imported. |
| Explicit solver coordinates | Newly authored power-of-two working-mesh/object-scale adapter, world/triangle input invariants and restoration, informed by pinned Blender/QuadriFlow unit behavior. No external implementation is imported; physical geometry and source topology are not changed to satisfy the tool's local-coordinate threshold. |
| Human-authorized one-attempt finish recovery | Newly authored strict task-local budget receipts, current-manifest/count binding and immutable snapshots/history. No existing attempt, conditioning input, model pin or toolchain budget is reset. |
| Bounded solver-input preparation | Newly authored one-main-component Collapse orchestration, exact retention of disconnected components, world-box vertex selection with exact held-identity/coordinate checks, component invariants and full vertex-to-opposing-surface error checks. Uses installed Blender operations; no external repair application/algorithm is imported and no continuous Hausdorff claim is made. |
| Blender child temporary routing | Newly authored attempt-local child environment, path/reparse/Windows-length checks, failure provenance and controlled-process tests. Existing entrypoints disable bytecode before helper imports; native guards are not an OS sandbox. |
| Exact-hull construction refinement | Newly authored bounded, deterministic, point-preserving diagonal refinement with global actual-point support checks. Pinned native quantization behavior informs the correction; no Bullet/Blender implementation is imported. Independent convexity validation and existing tolerances remain unchanged. |
| Explicit rigid-part finishing | Newly authored reviewed HIGH/LOW handoff and repair ancestry, grouped real atlas baking, exact material preservation, per-part distance/pivot/LOD0 checks and bounded native memory policy. Reuses OpenCaw geometry/export/owned-process primitives; no external application, fallback backend or imported algorithm is added. |

This native runner is not an operating-system sandbox. It never accepts licenses,
downloads during generation, changes sibling repositories, or generates approval.
Approval receipts record assertions made by the explicit caller; identities are not
cryptographically authenticated. Human review remains a separate operation.
