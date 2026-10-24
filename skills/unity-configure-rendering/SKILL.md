---
name: unity-configure-rendering
description: Configure Unity render pipelines, cameras, quality and Render Graph resources, including explicitly requested pipeline migrations.
engines: [UNITY]
---

# Unity Configure Rendering

## When to use

Configure Built-in, URP or HDRP rendering, camera/Volume behavior, quality tiers or custom renderer features. Use for an explicitly requested pipeline migration; material/shader implementation stays with the materials owner.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unity-configure-rendering` before edits or tool launches. Require effective `UNITY` compatibility and respect recorded task override scope. A skill request never changes engine selection.

Inspect the actual Editor and pipeline package versions, Graphics/Quality assets and per-tier overrides, selected renderer assets, graphics APIs, color space, cameras, XR and build targets. Resolve supported APIs from the installed package; preview features and packages require explicit selection.

## Workflow

1. Trace the effective pipeline for each target quality level. A project-wide default alone does not establish which renderer a player uses. Record current output and budgets before changing settings.
2. Configure camera ownership, projection, clipping, stacking/composition, render targets and Volume masks/weights. Prevent duplicate presentation owners, leaked camera targets and unintended per-camera feature costs.
3. Select quality settings from measured target-device limits: render scale, antialiasing, shadows, lights, depth/opaque textures, HDR and postprocessing. Keep gameplay cues readable across tiers.
4. Implement custom features using the installed pipeline's extension points. In Render Graph, declare access/dependencies and resource lifetime explicitly; do not persist transient handles between frames. Read [renderer resources](references/render-graph-resources.md) before changing passes.
5. Treat Built-in-to-URP conversion as a separate reviewed migration with an asset inventory, saved originals and comparison scenes. Do not run broad converters incidentally. Use [pipeline migration and cameras](references/pipeline-migration.md).

## Verification

Compile and build the selected player backend; inspect actual pipeline/renderer selection, shader errors and variant inclusion. Compare camera composition, depth, transparencies, lighting and postprocessing on representative scenes and quality tiers. Exercise resize, camera enable/disable, scene changes and renderer-feature disposal. Measure GPU time and memory on target hardware.

## Output

Native-authored pipeline/renderer/Volume assets, camera/resource ownership, measured quality decisions and before/after comparisons. Record environment, expected/observed results and unavailable checks. Null graphics, compilation and headless report success cannot certify rendered appearance or GPU budgets.
