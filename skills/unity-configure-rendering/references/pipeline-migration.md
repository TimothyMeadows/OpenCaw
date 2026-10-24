# Pipeline migration, quality and cameras

## Effective selection

Inspect both the Graphics default and every relevant Quality override, then the platform's active quality level. Record pipeline and renderer asset GUIDs, package versions and camera renderer selections. Built-in has no SRP asset; absence of a quality override does not by itself mean Built-in when a Graphics default is configured. Volumes, additional camera data and renderer features belong to their selected pipeline.

Map each camera's owner, player/display, projection, clear/composition rule, layer mask, culling and target. In URP, check supported base/overlay stacking rather than assuming arbitrary cameras combine. Define who restores the previous camera/target during cutscenes, menus and teardown. Inspect Volume layer masks, triggers, profiles and blending; avoid mutating a shared profile asset as accidental runtime state.

## Explicit migration

A requested Built-in-to-URP migration needs a recoverable source state and an inventory of shaders/materials, lighting/bakes, particles, terrain, camera effects, UI, renderer extensions and target platforms. Preserve `.meta` identities. Use supported converters only on the selected owned scope, inspect their report and identify unsupported custom shaders/effects separately. Re-running conversion must not quietly duplicate materials or overwrite deliberate fixes.

Create native baseline captures with matched camera, lighting, resolution, exposure and color-space conditions. Separate expected art-direction changes from regressions. Convert custom shaders and pass behavior deliberately; a successfully reassigned standard shader does not establish functional parity for custom rendering. Validate asset bundles/Addressables against the new pipeline and rebuild affected shader/content outputs before the player build.

## Quality and acceptance

Record per-tier render scale, antialiasing, shadow distances/cascades, light counts, texture limits and enabled effects with GPU/memory budgets. Test the weakest supported device and actual graphics API, including resize, display scaling, camera transitions and scene reload. Verify clear/depth behavior, transparent sorting, particles, decals, motion vectors and UI composition where applicable.

A native offscreen smoke test verifies a bounded resource path. It cannot certify full scene parity, the selected platform's performance or all renderer features. Store representative image comparisons and human review separately from compilation/headless results; blocked devices remain not-run.

## Sources

- [Unity render pipelines](https://docs.unity3d.com/6000.0/Documentation/Manual/render-pipelines.html).
- [Render Pipeline Converter](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/features/rp-converter.html).
- [QualitySettings.renderPipeline](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/QualitySettings-renderPipeline.html).
- [URP camera stacking](https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@17.0/manual/camera-stacking.html).
