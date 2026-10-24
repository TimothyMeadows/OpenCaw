# Determinism and generated-resource ownership

Inspect the installed plugin headers and project conventions. The official references below use Unreal 5.8; PCG, GPU execution, Geometry Script and Dynamic Mesh capabilities must be checked for the actual release and platform.

## Reproducible inputs

Track graph/recipe version, seed, source packages/transforms, sampling bounds, relevant world state and engine/plugin version. Sort input identities before deriving per-instance seeds; avoid depending on map/set iteration order or task completion order. Use `FRandomStream` or the selected generator's seeded interface for project-owned stochastic steps rather than a global random source. Define tolerance and ordering for output comparisons; do not promise cross-version or cross-GPU bit-identical output without evidence.

Give generated objects stable identities derived from their generator/domain and source identity. Separate the generator's resources from hand-authored objects. If users can override generated content, define which changes are retained and where overrides are stored; do not overwrite arbitrary actor edits on every reconstruction-script rerun.

## PCG execution

Choose non-partitioned, partitioned/hierarchical or runtime generation from the project's needs. Their scheduling, cleanup ranges and output lifetime differ. `UPCGComponent::GenerateLocal` schedules local generation; it does not synchronously prove completed output. Networked generation APIs do not make arbitrary generated gameplay authoritative or deterministic across peers. Decide which side owns gameplay state and which generated results are presentation.

Bind owned completion/cancellation callbacks before starting, check the expected generation ID before consuming output, and retain input UObjects through their required lifetime. Use supported component cleanup APIs for managed resources; do not scan the world and delete actors based only on a shared name/tag. Cleanup can be asynchronous too. Wait for completion, verify resource removal, and detach delegates before releasing the owner. Repeated generation must replace or reuse only its own resources rather than accumulating duplicates.

For World Partition, inspect data-layer/HLOD inheritance and generation bounds. A generated static mesh, actor, navigation contribution or collision body may survive differently from the original PCG component; verify unloading and regeneration with the real chosen generation mode. Graph dependencies and referenced meshes/materials need cook inclusion even when loaded through soft paths.

## Procedural geometry

Check the selected mesh API's runtime support before writing code. Author mesh buffers on an allowed thread and commit engine-object changes under documented ownership. Bound vertex/index counts and handle empty or degenerate inputs before assigning collision or material sections. If asynchronous cooking is selected, reject stale completion after mesh replacement/teardown. A visible mesh does not establish valid tangents, UVs, collision or navigation.

A bake is a distinct operation: create actual editable native packages using supported asset tooling, preserve input ancestry, and re-open/cook the baked result. Keep the runtime generator available only when required by the product. Existing media and art review/promotion controls apply to source and generated content.

## Verification recipe

Use a small CPU PCG graph with deterministic seeded random transforms and both point output and managed mesh instances. Require at least one point and one instance. Capture sorted transforms/seeds, clean the component, assert no managed instances remain, then generate with the same seed and compare. Change the seed and require an output change. Finally request generation and destroy/cancel the owner; verify its generated components are removed and no later completion mutates another owner. Label this fixture's generation mode explicitly; it does not certify GPU or partitioned runtime generation.

## Official references

- [PCG framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/procedural-content-generation-framework-in-unreal-engine?application_version=5.8)
- [PCG generation modes](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-pcg-generation-modes-in-unreal-engine?application_version=5.8)
- [UPCGComponent execution and cleanup](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/PCG/UPCGComponent?application_version=5.8)
- [PCG and World Partition](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-pcg-with-world-partition-in-unreal-engine?application_version=5.8)
- [Geometry Scripting](https://dev.epicgames.com/documentation/en-us/unreal-engine/geometry-scripting-users-guide-in-unreal-engine?application_version=5.8)
- [UDynamicMeshComponent](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/GeometryFramework/UDynamicMeshComponent?application_version=5.8)
