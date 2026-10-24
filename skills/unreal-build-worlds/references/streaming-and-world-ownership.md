# Streaming and world ownership

Match APIs to the installed Unreal release. These official links use a 5.8 review baseline; older projects and experimental world features require their own compatibility checks.

## Choose the existing world system deliberately

Traditional streamed sublevels and dynamic `ULevelStreamingDynamic` instances have explicit level ownership. World Partition uses streaming sources and generated cells within a persistent world. Level Instances package reusable world composition; their identity and load lifecycle differ from an ordinary actor prefab. Do not convert between these systems to satisfy a generic rule.

For World Partition, inspect spatial loading, runtime grids, streaming ranges and actor reference clusters. A hard reference can bind actors' loading lifetimes; moving a file does not isolate that dependency. Document always-loaded gameplay owners and avoid having them retain transient cell actors indefinitely. Choose source range from traversal speed, load latency, memory and visibility requirements, then measure on the target rather than prescribing a universal cell size.

## Readiness and state

Distinguish requested, loaded and activated/visible states. `UWorldPartitionSubsystem` streaming completion and source/provider lifetimes are relevant only for that world; a global percentage cannot establish every gameplay prerequisite. A dynamic streaming-level request returns an object representing work, not a ready actor set. Bind completion/state changes with an owner that removes its delegates and invalidates pending work on travel or cancellation.

Treat Data Layer Assets as project definitions and Data Layer Instances as world-specific state. Only runtime layers participate in gameplay activation. Inspect the matching-version manager APIs (`UDataLayerManager` where applicable); do not paste deprecated subsystem calls without checking migration notes. Define server authority, client visibility and initial state explicitly. A layer being loaded does not necessarily make its contents visible or interactable.

Use a project-stable GUID or authored identity for persistence. Actor names, PIE prefixes, transient streaming package names and raw pointers cannot identify a particular object across sessions. Level Instance duplication requires an instance identity as well as a local object identity. Cross-cell interactions must handle an absent target and retry or reject according to gameplay rules, rather than keeping every cell alive.

On unload, release actor/component subscriptions, tasks, timers and per-world caches. A weak pointer protects lifetime but does not prove a request belongs to the current world generation. After reloading, initialization and restoration must be idempotent; missing optional decoration must not block authoritative state, while missing required content must remain explicit.

## Build and runtime checks

HLOD is a rendering representation, not an authoritative gameplay or collision replacement. Select layer rules/materials and rebuild only intended dependencies; inspect package deletions as well as additions. World Partition builders can modify large package sets, so bind their scopes and outputs to task evidence. Navigation, PCG outputs, HLODs, data-layer assets and soft-loaded maps require explicit cook inclusion.

For a controlled fixture, load a real level containing a tagged marker, observe visibility and actor availability, unload it, assert the loaded level is absent, then reload and identify a fresh marker instance. Record timeout and teardown paths. This proves that fixture's streaming lifecycle; separate tests are required for World Partition source travel, replication, HLOD visuals and packaged-world performance.

## Official references

- [World Partition](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine?application_version=5.8)
- [Data Layers](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition---data-layers-in-unreal-engine?application_version=5.8)
- [Level Instancing](https://dev.epicgames.com/documentation/en-us/unreal-engine/level-instancing-in-unreal-engine?application_version=5.8)
- [World Partition HLODs](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition---hierarchical-level-of-detail-in-unreal-engine?application_version=5.8)
- [World Partition builders](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-builder-commandlet-reference?application_version=5.8)
- [ULevelStreamingDynamic](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/ULevelStreamingDynamic?application_version=5.8)
