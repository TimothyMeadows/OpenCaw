# Native world, procedural and save fixtures

These source-only Automation cases target an explicitly selected **Unreal 5.8 Editor** fixture baseline. They have not been compiled or executed without that installation. They are not imported upstream examples. Required modules are Core, CoreUObject, Engine, PCG and Editor-only UnrealEd. The reflected save types require UHT as part of normal native compilation. No CQTest or third-party module is required.

Run in a dedicated test Editor process/project copy. `ProceduralRegeneration` opens a fixture map without saving; it must never replace an interactive user's unsaved Editor map. Do not package this Editor test module into a shipping game.

## Exact native tests

| Case | Real engine behavior and assertions | Limits |
| --- | --- | --- |
| `OpenCaw.UnrealFeatures.WorldStreaming` | Creates an owned initialized native game world, streams a real map through `ULevelStreamingDynamic`, finds its tagged marker while visible, unloads until its loaded level is absent, reloads a distinct marker instance, then unloads and destroys the world/context | Traditional dynamic-level lifecycle; does not certify World Partition travel, replication, collision, HLOD visuals or packaged performance |
| `OpenCaw.UnrealFeatures.ProceduralRegeneration` | Runs an actual CPU `UPCGComponent`, waits on native generation/cleanup delegates, requires real output points and managed ISM instances, compares same-seed sorted transforms, requires changed-seed differences, asserts cleanup removes instances, cancels a fresh generation and observes three additional Automation ticks for stale completion/resource revival | Nonpartitioned Editor CPU PCG only; no GPU/runtime-partitioned generation, final art, arbitrary-duration late-callback or world-destruction acceptance claim |
| `OpenCaw.UnrealFeatures.SaveMigration` | Roundtrips a reflected `USaveGame` through real `UGameplayStatics` in-memory serialization, migrates a legacy value before committing, verifies stable identity/idempotence, rejects future schema/invalid score/duplicate identity/missing definition without live mutation, rejects corrupt/truncated/empty envelopes | Fixture integrity checksum is not authentication; does not certify platform disk durability, cloud/user identity, real async I/O cancellation or full-world restore |

Every asynchronous fixture stage has a 30-second deadline; the external runner still needs its own process timeout because a native engine operation can stall before an Automation tick. Missing configuration/assets must be blocked during runner preflight. Direct test invocation reports an error rather than a successful skip. Structured reports must include all required cases with terminal results from this exact run.

## Required native asset bindings

Add explicit bindings to the fixture project's `Config/DefaultGame.ini`, using the real packages authored below:

```ini
[OpenCaw.UnrealFeatures]
StreamingLevel=/Game/OpenCawFixtures/StreamingChunk
StreamingMarkerTag=OpenCawStreamingMarker
ProceduralMap=/Game/OpenCawFixtures/ProceduralFixture
ProceduralActorTag=OpenCawProceduralActor
```

Map keys are long package names, without `.umap` or the `.ObjectName` suffix. Tags must be nonempty and match exactly one actor in their declared fixture scope. There is no StreamingHostMap dependency; the streaming test creates its own real transient world. `SaveMigration` has no binary asset/config binding.

### Streamed map authoring

In the selected Editor, create a small **non-World-Partition** level `StreamingChunk`. Add one ordinary actor tagged `OpenCawStreamingMarker`, give it a scene component, and save the native map. Avoid plugins, complex actor scripts or hard references to production maps. The dynamic load test needs a real `.umap`; do not manufacture text stand-ins or substitute an unrelated map. Place it in the relevant fixture cook set if extending the test to a packaged player.

### Procedural graph and map authoring

Explicitly enable the bundled PCG plugin for this fixture project and restart/rebuild as required. Do not enable it in any host game implicitly. Create a small CPU PCG graph with Create Points Grid producing multiple points, Transform Points with nonzero random translation/rotation and component-seed participation, and Static Mesh Spawner selecting one local test mesh. Route transformed points to the graph output as well as the spawner. Use generated ISM components attached to the source actor, not separate spawned actors; the test's managed-resource boundary is that actor. Do not use GPU nodes, landscape sampling, runtime partitioning or external services.

Create `ProceduralFixture`, add exactly one actor tagged `OpenCawProceduralActor` with the graph assigned to its `UPCGComponent`. Set generation to **On Demand**, nonpartitioned, and disable regenerate-on-editor-change/drop behavior so map loading cannot pre-generate resources before test callbacks bind. Clean generated resources before saving; the map must open without ISM instances. Include only the tagged actor's generated mesh components within that scope. Verify a native manual generation yields points and ISM instances, then clean and save again. An empty graph or graph that ignores the component seed will fail the Automation assertions.

Record actual map/graph/mesh package hashes, graph settings and dependencies in the run's task evidence. Changing a bound asset invalidates prior run evidence. The runner must resolve the actual packages through the matching Unreal installation; existence of a similarly named filesystem file is not a native type check.

## API review references

- [ULevelStreamingDynamic](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/ULevelStreamingDynamic?application_version=5.8)
- [UWorld creation and lifetime](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UWorld?application_version=5.8)
- [UPCGComponent generation, delegates and cleanup](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/PCG/UPCGComponent?application_version=5.8)
- [PCG data collection](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/PCG/FPCGDataCollection?application_version=5.8)
- [UGameplayStatics save serialization](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UGameplayStatics?application_version=5.8)
- [Editor map loading](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Editor/UnrealEd/UEditorLoadingAndSavingUtils?application_version=5.8)
