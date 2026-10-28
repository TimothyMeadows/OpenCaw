# Blender asset handoff to Unreal

## Select native import deliberately

Resolve UNREAL and this skill before writes or tool launches. Inspect the actual Editor version, chosen legacy FBX/Interchange or other importer, enabled plugins, target platform and asset conventions. Do not switch import pipelines or enable optional systems silently. Preserve reviewed repository-local source/export identities, native package paths and intended referencers.

Use a known-dimension asymmetric fixture to validate Blender-to-Unreal unit/orientation conversion, root/pivots, grounding, bounds and material slots. Record importer/exporter settings rather than apply a universal transform preset. FBX compatibility is version-specific; consult the selected pipeline's documentation and test its actual exported file before assuming every FBX variant behaves alike.

## Static and articulated content

Import only the intended visible runtime variant. Review authored LODs, material slot correspondence, screen-size transitions and collision policy with the target renderer. Preserve collision sources and detailed masters separately; do not automatically show them alongside LOD0 or assume Nanite replaces collision and memory budgets. Mechanical parts retain real pivots and hierarchy; a static mesh cannot prove its assemblies animate independently.

Skeletal imports require the actual reviewed skeleton/bind pose, scale, bone hierarchy and selected animation ranges. Verify retarget/morph/attachment support explicitly; do not invent an articulated asset's Humanoid-equivalent skeleton. Binary .uasset/.umap authoring remains native Editor work, not text generation. Reimport must retain intended package references and settings, with changed subassets or skeleton compatibility reviewed before replacement.

## Surface and target evidence

Blender shader graphs do not become equivalent native materials automatically. Record each texture's channel meaning, color/non-color import, normal convention, opacity mode and two-sided behavior. A packed image is usable only when the selected Unreal material reads the declared channels. Inspect neutral metallic/roughness response, grazing normals, hair/foliage alpha and emissive surfaces after import; bloom cannot substitute for actual illumination or an animated presentation implementation.

Reopen imported packages, verify scale/hierarchy, normals/UVs, material assignment and dependencies, then cook/load the actual runtime asset and measure budgets. Test reimport without duplicate packages or lost references. Include representative LOD/collision behavior and full motion/loop evidence when applicable. Keep failed/missing native checks explicit; a generic GLB inspector or clean command exit cannot certify an Unreal package or packaged gameplay.

## Primary references

- [Epic FBX content pipeline](https://dev.epicgames.com/documentation/en-us/unreal-engine/fbx-content-pipeline): select documentation matching the project's actual importer/version.
- [Epic Interchange framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/interchange-framework-in-unreal-engine): use only when selected and available.
