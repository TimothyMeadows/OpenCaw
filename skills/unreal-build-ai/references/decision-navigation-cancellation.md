# Decision ownership, navigation and cancellation

Use the selected decision framework. Behavior Trees need blackboard schema and task/decorator/service abort rules; StateTree has release-dependent instance and transition semantics. Do not translate them mechanically or enable a second framework without a project decision.

Behavior Tree node templates may serve many agents. Keep mutable state in node memory or explicitly instanced tasks. A latent task finishes exactly once and unregisters timers/delegates on abort. A delayed callback cannot finish a newer execution using the old task's context.

## Observations and actions

Perception is an observation stream, not durable truth or permission to attack. Expiry, team changes, target destruction and streamed removal invalidate it. Check authoritative eligibility when applying an action. Identify which controller owns blackboard/state and when its pawn can change.

Navigation needs agent dimensions, movement modes, filters, partial-path policy and a bounded failure outcome. Distinguish no navigation data, unreachable target, partial path, cancellation and success. Cancel an owned request rather than stopping all work on a shared controller unnecessarily.

EQS results evaluate candidates asynchronously. Budget query frequency, candidate count and complexity, then reject stale decision generations. A high-scoring candidate can disappear before use. Smart Object claims also need validity checks and release on every terminal path.

| Failure | Expected behavior |
| --- | --- |
| Latent task aborted | Timer/delegate/path request released; no late completion. |
| Target disappears | Cancel/replan without dereferencing a retired actor. |
| No route | Bounded failure/backoff rather than per-frame endless retry. |
| Claim contended | Explicit retry or alternative decision. |
| Pawn replaced | Old task cannot command the replacement via a stale callback. |

Observe actual native execution and navigation. Record agent count, task/query rates and target frame budget. A compile or isolated abort test cannot certify navigation-mesh authoring or player-facing enemy behavior.

## Official references

- [Behavior Trees](https://dev.epicgames.com/documentation/en-us/unreal-engine/behavior-tree-in-unreal-engine---overview)
- [StateTree](https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-state-tree-in-unreal-engine)
- [AI perception](https://dev.epicgames.com/documentation/en-us/unreal-engine/ai-perception-in-unreal-engine)
- [Navigation](https://dev.epicgames.com/documentation/en-us/unreal-engine/navigation-system-in-unreal-engine)
- [Environment Query System](https://dev.epicgames.com/documentation/en-us/unreal-engine/environment-query-system-in-unreal-engine)
- [Smart Objects](https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview)

Use actual selected plugins and host-version APIs before authoring assets.
