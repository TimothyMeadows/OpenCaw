# Mass data access and lifecycle

Choose fragments for queried per-entity data, tags for composition states, and shared/chunk data when their lifetime/equality semantics fit. Excess archetype variation causes churn and poor chunk utilization. Do not imitate a conventional object graph through actor pointers in every fragment.

Declare access modes, optional requirements and processor ordering before scheduling. Read/write conflicts determine parallel safety. Query registration and execution context vary across releases; inspect actual installed headers instead of treating an old example as universal.

Processor code cannot dereference arbitrary UObject state on workers. Snapshot data or use the supported game-thread bridge. A thread-safe manager operation does not make an externally referenced actor thread-safe.

## Structural mutation

Queue additions/removals/destruction while iterating and flush at an owned safe boundary. Cached chunk/archetype views can be invalidated by immediate structural change. Specify when observers fire and deferred results become visible.

| Lifetime | Invariant |
| --- | --- |
| Reserve | Handle exists; a fully built entity is not yet promised. |
| Build/spawn | Required composition and data exist before processor consumption. |
| Despawn | External representation retires and manager destruction is safely scheduled. |
| Reuse | An old generation cannot identify a replacement entity. |
| World shutdown | Pending commands and bridges end before owner data disappears. |

An entity index alone is insufficient identity. Validate complete handles and distinguish release of an unbuilt reservation from destruction of a built entity. A standalone test manager must be initialized before use and deinitialized after work/commands end.

## Evidence

A lifecycle fixture creates an actual archetype/entity, accesses fragment data, queues destruction and checks validity after flush. A later entity must not make the retired handle valid. Native processor/query execution and representative population profiles are additional production requirements; core storage tests cannot certify crowd navigation, rendering or multiplayer.

## Official references

- [MassEntity overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-mass-entity-in-unreal-engine)
- [Entity manager API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/MassEntity/FMassEntityManager)
- [Processor API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/MassEntity/UMassProcessor)

Match type locations and query APIs to the selected engine. Optional representation/MassGameplay plugins are separate prerequisites.
