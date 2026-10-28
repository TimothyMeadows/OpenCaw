# Navigation authoring and lifetime

Navigation belongs to scene/world ownership; rigid-body collision belongs to the physics owner. Inspect the selected AI Navigation package, existing `NavMeshSurface`/link assets and exact Editor before changing them. The presence of `UnityEngine.AI` types does not prove that package-level surface authoring components are installed.

## Bake contract

Record world units, agent type ID, radius, height, slope, step, voxel/tile settings, collected geometry, layers and modifiers. Build separate compatible data for agent types with materially different dimensions. Confirm source transforms and bounds for additive scenes or runtime surfaces. Track the native data instance that each scene adds and removes; never remove another world's global NavMesh data during local cleanup.

Declare which obstacles carve, when stationary carving updates, and how rebaking affects active requests. A visual mesh, collider and navigation mesh can disagree; inspect all three against player routes. Verify doors, elevators, narrow gaps, slopes and changed obstacles at actual agent dimensions. A matching destination marker does not prove reachability.

## Request and movement ownership

Assign one navigation/movement owner to each actor. `NavMeshAgent`, root motion, Rigidbody and custom controllers must not independently overwrite position. Choose `updatePosition`/`updateRotation`, root-motion synchronization and physics interaction intentionally. Restore ownership on death, possession changes, cutscenes and disable/re-enable.

`SetDestination` accepting a request is not a completed valid path. Distinguish `pathPending`, complete/partial/invalid status, `hasPath`, stale paths and remaining distance. An arrival rule needs a valid resolved path, stopping distance and appropriate motion tolerance; a temporarily small or nonfinite distance must not trigger rewards. Bound repathing and stale-result application by actor/request generation, and cancel on teardown.

Use `isStopped` when intentionally retaining a path; use `ResetPath` when discarding it. The latter completes an active OffMeshLink immediately on documented versions, so it is not a neutral interruption for custom traversal. Define link-entry ownership, animation/motion handoff, failure and final placement explicitly. For custom link traversal, test death, link disable, source/destination unload and cancellation midway. Use the selected package's link API rather than assuming legacy `OffMeshLink` and newer `NavMeshLink` authoring are interchangeable.

## Verification

Native fixtures should bake known connected and disconnected regions, assert `NavMeshPathStatus`, exercise an agent's accepted path and reset/disable cleanup, then remove only their owned data. Add actual Play Mode/player scenarios for delayed path completion, obstacle carving, off-mesh interruption and unload/reload. Synchronous query tests cannot prove async movement cancellation or collision-safe gameplay.

## Sources

- [AI Navigation 2.0 surfaces](https://docs.unity3d.com/Packages/com.unity.ai.navigation@2.0/manual/NavMeshSurface.html).
- [NavMeshAgent path status](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/AI.NavMeshAgent-pathStatus.html).
- [NavMeshAgent.ResetPath](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/AI.NavMeshAgent.ResetPath.html).
- [NavMeshBuilder.BuildNavMeshData](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/AI.NavMeshBuilder.BuildNavMeshData.html).

Use matching Editor/package documentation and project-specific acceptance tolerances.
