# Bounded world work

Use this optional reference when a requested world, agent behavior, or measured workload needs spatial indexing, cooperative scheduling, navigation, pooling, streaming, or reproducible generated content. Select only relevant sections. Small, static, or turn-based games may need none of these techniques.

Resolve `ENGINE.md`, architecture, and compatible world/physics/navigation/control skills before APIs. Prefer suitable existing engine facilities and host owners. This agnostic guidance selects no algorithm package, worker runtime, navigation system, art pipeline, or replacement physics broad phase.

## Select and measure the work

1. State the required behavior, representative world distribution, entity/agent counts, traversal speeds, and supported targets. Distinguish a missing feature from a demonstrated performance bottleneck.
2. Capture a comparable baseline: build/device, content and inputs, warmup, duration, frame-time distribution, CPU/GPU attribution, memory, allocation, I/O, and response latency as relevant. Choose success and regression limits before changing the implementation.
3. Inspect engine-native queries, navigation, world loading, and existing application scheduling first. Require measured need and a scoped hypothesis before adding custom optimization; unavailable measurements leave the decision unproven, not permission to claim a speedup.
4. Change one ownership boundary or technique at a time, then repeat the same workload. Track correctness, worst cases, latency, memory, and readability alongside average cost. A smaller candidate count or a spread-out workload does not alone establish improvement.

## Budget and identity contract

Record limits for each selected operation; no universal cell size, refresh rate, queue capacity, or slice duration is supplied here.

| Concern | Declare before execution |
| --- | --- |
| Work | Maximum items/expansions/candidates per unit, per update, and in flight; bounded queue capacity. |
| Time | Measured update allowance and checkpoints, plus maximum response age/deadline. |
| Memory | Index/job/path/pool/resident-content limits, shared versus owned resources, and retirement rules. |
| Identity | Stable world/entity/region IDs, spawn/owner generation, request generation, and input/data revision. |
| Publication | Required snapshot freshness, authoritative commit stage, cancellation, and disposal of rejected results. |
| Exhaustion | Explicit reject/defer/partial/failure policy, diagnostics, and any previously selected safe alternative. |

## Spatial candidates and exact queries

A grid, tree, BVH, or other spatial index reduces candidates. It is a broad-phase service; the selected narrow-phase/query owner still evaluates actual geometry, layers, and gameplay eligibility. Index membership is neither visibility truth nor permission to damage.

- Choose from measured density, object/query sizes, mobility, and update cost. A streaming region and an actor-query cell can have different sizes and lifetimes; do not conflate them or silently replace an engine's physics index.
- Use a declared coordinate space and coherent simulation snapshot. Insert, move, resize, rebase, and remove objects under the same boundary convention used by queries. Bind results to stable entity IDs plus spawn generations.
- Cover all relevant extents, not just an object's center. Large objects may occupy several cells or a separately queried large-object set. Test negative coordinates, exact borders, touching bounds, zero-size and world-edge cases as the query contract requires.
- Deduplicate candidates by full entity identity when an object occupies several cells. Apply region/shape rules afterward if distinct parts are intentionally queryable.
- Define when movement updates become query-visible. Deferred updates need conservative coverage or an explicitly selected correctness-preserving query path; omitting moved entities until a later slice cannot silently change collision/damage truth.
- Treat overflow and truncated query buffers as incomplete work, not an empty/complete result. Use declared bounded continuation, rejection, or a selected safe path; do not silently drop candidates.

For a small oracle fixture, compare final accepted results with an exhaustive query over the same snapshot, geometry, filters, and boundary convention. Broad-phase false positives can be valid; false negatives cannot. Include insertion, movement, removal, large objects, borders, and duplicate candidates. This establishes correctness for those cases, not production performance.

## Cooperative scheduling and publication

Time slicing distributes deferrable work; it does not authorize delaying required contact, damage, or simulation decisions across arbitrary rendered frames. Keep authoritative tick deadlines with their existing owners. See [contact authority](damage-windows-and-contact.md) and [clock policy](input-and-locomotion-feel.md#clocks-and-update-order).

1. Split work into resumable bounded units. Set both item/expansion limits and measured time allowance, checking at safe checkpoints. A time check cannot preempt a single unbounded unit; bound or explicitly handle that unit first.
2. Limit queue size and outstanding work. State priority, urgency, aging/round-robin fairness, and maximum response latency. Define overload and missed-deadline behavior; low-priority work must not starve forever or displace required tick work.
3. Give jobs world/owner/request generations and input revisions. Cancellation retires that request; a replacement increments identity rather than sharing a mutable completion flag with the old job.
4. Compute from declared immutable/coherent inputs. Before publishing, recheck generations, relevant data revisions, deadline, target lifetime, and readiness. Reject or replan stale output instead of attaching it to a newer world or actor.
5. Publish through the engine's permitted thread and authoritative stage. Worker completion alone grants no permission to mutate scene/physics objects. Remove owned subscriptions/handles and release result resources on every terminal path.

Define pause, hidden-tab, stall, and resume behavior. An overdue queue must not run its entire backlog on resume. Bound accumulated work and discard or revalidate aged requests under the declared policy. Measure queue age, fairness, cancellations, and result rejection alongside frame cost.

## Navigation and steering

Prefer the selected navigation/movement facilities when suitable. A path is a proposal for movement, not proof of collision-free execution; steering produces desired movement intent rather than directly teleporting an actor.

- Declare agent dimensions, movement modes, traversable data, clearance, slope/step rules, filters, and destination tolerance. Distinguish missing navigation data, unreachable target, partial route, cancellation, and arrival.
- If custom graph/A* work is justified, specify node/edge identity, finite nonnegative costs, neighbor/corner-cutting rules, and heuristic assumptions. A promised optimal path needs an admissible heuristic and appropriate consistency/reopening rules. Bound expansions, memory, and time; partial/budget-exhausted results cannot be reported as success.
- Bind a route to target and navigation-data revisions. Define replan triggers, rate limits/backoff, moving/removed targets, route invalidation, and cancellation. Keep the old route only under an explicit safe-validity policy.
- For steering, define desired velocity, behavior priorities/blends, acceleration, speed, turn bounds, and zero-distance handling. Review crowd density, opposing goals, narrow passages, blocked agents, and oscillation; local avoidance does not guarantee a global route.
- Feed intent into the existing collision-aware movement owner. Keep grounded/air response, root motion, knockback, and navigation contributions under its arbitration; [locomotion guidance](input-and-locomotion-feel.md#acceleration-braking-and-friction) does not add a second movement writer.

## Bounded pools and reuse

Pool only where measured allocation/lifetime pressure justifies it. Reuse shifts cost into retained memory and reset logic; a pool is not automatically faster.

- Declare capacity, retained-resource budget, lease/return ownership, and exhaustion behavior. Reject, recycle, or grow only under the chosen bounded policy; never retire a live gameplay entity silently to satisfy a cosmetic request.
- Give each lease a new generation in addition to stable entity/slot identity. Late timers, queries, workers, and completion callbacks must not mutate the replacement occupant.
- Reset gameplay state, transforms/velocities, collision/query enablement, input/actions, contacts/immunity, navigation requests, effects, subscriptions, and resource references that the pooled type actually owns. Do not reset unrelated shared services.
- Activate only after reset and readiness checks; returning an object invalidates its lease before cleanup callbacks run. Detect double return/use-after-return, and dispose retained resources at pool-owner teardown.

Existing specialized particle pools retain their own engine/backend contracts; this checklist neither replaces them nor provides a universal entity pool implementation.

## Streaming residency and gameplay readiness

Choose streaming only when the world and target budgets require it. Use the selected engine's existing loading system; render LOD, actor-query indexing, and world residency remain separate concerns.

| State | Meaning and gate |
| --- | --- |
| Requested | Identified content/version is queued or in flight under an owned request generation. |
| Loaded | Required bytes/assets are available; scene activation, collision, navigation, or save restoration may still be incomplete. |
| Gameplay-ready | All declared required activation, collision/navigation registration, dependencies, and persistent-state restoration are complete. |
| Retiring/unloaded | New consumers are blocked as declared; owned work is invalidated, state retained, and resources released after live references end. |

Budget I/O concurrency, decode/build work, main-thread activation, resident memory, and maximum readiness latency. Choose request ranges/prefetch from traversal speed and measured tail latency; test teleport and rapid reversal separately. Define behavior at a not-ready boundary, such as a designed wait or blocked traversal, rather than allowing entry through missing collision.

Track shared versus region-owned resources and references. On unload, cancel jobs/navigation, remove index entries and owned subscriptions, save required state, and release only owned assets after consumers are safe. A late load must release its result instead of attaching to a replacement region. Reentry/restoration must be idempotent; required content failure is explicit, while absent optional decoration follows its declared policy.

## Versioned generation and saved edits

Seeded random values do not by themselves define coherent spatial noise, complete save state, or compatible regeneration. Record the actual selected generator and persistent-state contract.

| Identity | Preserve with generated content |
| --- | --- |
| Recipe | Algorithm/noise type and version, parameters, coordinates/units, bounds, source-content identities, and relevant engine/plugin version. |
| Random domains | World seed plus stable region/entity/feature-domain identities and derivation rules; keep unrelated feature streams independent. |
| Comparison | Stable output identity/order and declared numerical tolerance; record supported platform/version scope. |
| Persistent overlay | Versioned saved edits, removals/tombstones, spawned entities, inventories, and other state that regeneration must not erase. |

Derive random inputs from stable identities rather than asynchronous completion order or one shared global random stream. For spatial noise, state frequency/scale, octave settings where used, and border sampling rules; test continuity and chunk-order independence. A matching seed cannot promise cross-version/GPU bit identity or cross-platform physics determinism.

Restore the matching base recipe, then apply validated saved state under explicit conflict/order rules. Identify generated entities independently of transient render IDs or enumeration order. An unsupported recipe/save version needs a separate compatibility or migration decision; do not silently regenerate over player edits, relabel old state, or migrate existing saves through this guidance task.

## Future acceptance scenarios

These are requirements for future selected-engine implementations, not executed gameplay tests or benchmarks. Choose expected results and concrete budgets before running them.

| Scenario | Expected observation |
| --- | --- |
| Move/resize/remove objects across cell borders, including large objects | Exact filtered results match the exhaustive oracle without missing or duplicate recipients. |
| Query at negative/exact-edge coordinates or after rebasing | Insertion/query conventions and coherent transforms preserve the declared results. |
| Saturate candidate buffers, job queues, paths, or pools | Explicit bounded exhaustion policy applies; incomplete work is never mislabeled as complete success. |
| Mix urgent jobs and a sustained low-priority queue | Required tick work remains timely; declared fairness, deadlines, memory, and response-age limits hold. |
| Cancel/replace a job, target, actor, or world before completion | Old-generation/revision output is rejected and its resources released without mutating the replacement. |
| Stall, pause, hide, then resume | Work age/catch-up policy holds without a backlog spike or deferred authoritative damage/collision. |
| Missing/partial/unreachable route or moving/destroyed destination | Explicit status, bounded retry/replan, and cancellation match the navigation contract. |
| Dense crowds, opposing goals, or narrow passages | Speed/turn/acceleration limits and collision ownership hold; failures remain observable. |
| Pool return/reuse followed by an old callback or double return | Lease checks reject stale work; reset state and bounded retained memory remain correct. |
| Traverse, reverse, teleport, or fail a region load | Requested/loaded/gameplay-ready gates, activation limits, and not-ready behavior remain distinct. |
| Unload/reload with jobs, shared assets, and saved edits | Owned work retires, live shared consumers stay valid, and restoration applies once without losing edits. |
| Reorder generation, vary a feature stream, or change recipe version | Stable-domain output follows declared tolerances; unrelated streams and saved overlays remain intact; incompatible versions stop explicitly. |

## Record evidence

Keep source/build, effective engine/backend, target device, data/recipe identities, workload, settings, expected/observed results, traces, and comparable before/after distributions. Oracle or scheduler fixtures establish only their stated correctness scope. Real navigation, loading, collision readiness, sustained memory/frame cost, and player readability need actual selected-engine/target evidence.

Report unavailable runtime, device, workload, or player checks as `not-run` or `blocked` with reasons. No documentation, generated manifest, or synthetic timing report certifies a world or device. This reference authorizes no package installation, asset production, save migration, or publication.
