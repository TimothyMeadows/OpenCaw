# Material production

Use this when changing material graphs, runtime material parameters or platform shader behavior. First record the engine build, RHI, feature level, shading path and relevant project settings. A preview on a desktop renderer is not a mobile compatibility test.

## Graph and asset contract

Native Material assets define domain, blend mode, shading model, sidedness and outputs. These choices change lighting, shadow, depth and pass behavior. Author and compile real graphs in the Editor or supported audited automation. Preserve source textures and recorded art direction; a valid material does not confer rights to its inputs.

Classify color textures, masks, normal maps and packed channels before import. Verify sRGB/compression, tangent-space conventions, UV sets and material-slot correspondence on the actual mesh. Diagnose roughness, normals and exposure independently before adding artistic compensation. Record tile density and mip behavior at target camera distances.

## Runtime parameter ownership

Use Material Instance Constants for authored variants. Create and retain a Dynamic Material Instance once per intended owner/slot, using `UMeshComponent::CreateDynamicMaterialInstance` or the appropriate primitive-component API for the project version. Store it through a GC-visible reference and verify the requested slot. `SetScalarParameterValue`, `SetVectorParameterValue` and texture updates operate on the owned instance; repeatedly creating instances during tick leaks cost and invalidates other owners' references.

Parameter collections are shared per world. Assign one coordinator for global weather/time state and separate that from local damage, dissolve or highlighting. Reset owned values on pool return, actor reuse and interrupted effects. A material animation uses an explicit game or real-time clock and must not decide authoritative hit outcomes.

Static switches increase permutation count. Estimate combinations before adding a new boolean to a base material, and verify that cooked targets contain intended variants. A dynamic scalar does not remove the need to measure expensive enabled branches.

## Selected rendering features

Substrate, Runtime Virtual Textures, Virtual Textures, Nanite-related deformation and advanced translucency are project/version/platform choices. Inspect installed support and actual settings; do not change shading infrastructure as a side effect of fixing one asset. If the selected feature is unavailable, report the incompatibility and obtain an explicit design choice.

World Position Offset must fit mesh/culling bounds and shadow behavior. Test displaced silhouettes and far/near transitions, including the selected Nanite path. Masking, translucency and post-process effects need overdraw and accessibility review in representative overlap; shader instruction estimates alone miss bandwidth and pass cost.

## Measured acceptance

Compare the same scene/camera, light/exposure setup, resolution, scalability and artifact revision before/after. Record GPU frame/pass timings, material complexity diagnostics, texture residency and shader compile/cook warnings. Include an on-device packaged sample for each supported rendering tier. Use lit, neutral lighting, grazing-angle, close and gameplay-distance captures to evaluate materials. NullRHI compilation verifies neither appearance nor GPU cost.

Official references, with version matching:

- [Material instances and parameters](https://dev.epicgames.com/documentation/en-us/unreal-engine/instanced-materials-in-unreal-engine)
- [Material properties](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-material-properties)
- [Substrate overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-substrate-materials-in-unreal-engine)
