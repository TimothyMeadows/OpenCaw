# Shader authoring, graphs and variants

## Target and asset ownership

Inspect Editor, render-pipeline and Shader Graph versions, target/subtarget, surface state, graphics APIs and build platform. A graph asset is an authored native asset with serialized identities and dependencies. Use its supported Editor workflow; do not fabricate undocumented graph JSON or replace `.meta` identities. Preserve material properties and consumer references during parameter renames or shader replacement.

Separate renderer/resource configuration from material behavior. URP/HDRP conversion is an explicit migration, not a side effect of choosing a shader. Record relevant vertex attributes, texture semantics, lighting requirements and expected passes. Rendering an unlit preview does not establish depth, shadow, motion-vector or lighting compatibility.

## Graph and HLSL integration

For Shader Graph, choose the correct target, precision, coordinate spaces, property exposure and keyword mode. A Custom Function needs explicit input/output types, precision suffixes, includes and supported stages. Keep any HLSL include repository-local with reviewable provenance. Validate derivatives, texture sampling, platform limitations and variant-dependent code in the intended stage/backend.

Programmatic reflected-node authoring APIs are version-specific. Inspect the installed package's public supported surface before using them; internal reflection into editor assemblies is not a stable universal contract. If an operation requires an unavailable or preview API, report that constraint and use the explicitly chosen supported authoring path. Do not silently switch a graph to handwritten HLSL or install a newer package to satisfy an example.

## Variants and resources

Inventory local/global keywords and actual feature combinations. Decide which variants must remain in player content and inspect build-time stripping results. Editor preview compilation and a ShaderVariantCollection asset do not guarantee every required runtime combination survives platform stripping. Exercise representative scene/material variants in the built player, including dynamically loaded content. Measure first-use shader warmup, memory and stutter rather than assuming prewarming is free.

Own per-renderer material instances and shared assets separately. MaterialPropertyBlock can avoid instances in some workflows, but verify its interaction with the project's batching path rather than claiming it always improves SRP performance. Dispose owned runtime materials, buffers and textures on scene/actor teardown; do not destroy shared imported assets. Use consistent color/data sampling, normal-map import and tangent conventions.

## Acceptance

Compile the shader and actual target player, fail on compiler errors and unsupported fallbacks, then inspect real images and Frame Debugger/GPU measurements. Include opaque/transparent ordering, alpha edges, lighting extremes, instancing, LODs, quality tiers and graphics APIs. Headless compilation cannot certify visuals. A reflection lookup or graph serialization round trip cannot certify that a pass ran.

## Sources

- [Shader Graph 17 custom functions](https://docs.unity3d.com/Packages/com.unity.shadergraph@17.0/manual/Custom-Function-Node.html).
- [Shader keyword variants](https://docs.unity3d.com/6000.0/Documentation/Manual/shader-keywords.html).
- [ShaderVariantCollection](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/ShaderVariantCollection.html).
- [MaterialPropertyBlock](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/MaterialPropertyBlock.html).

Match package/version documentation to project evidence; these links do not authorize upgrades.
