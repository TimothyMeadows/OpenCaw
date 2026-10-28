---
name: babylonjs-build-materials
description: Implement Babylon.js PBR, node or shader materials with explicit texture conventions, renderer support and measured cost.
engines: [BABYLONJS]
---

# Build Babylon.js Materials

## When to use

Author or diagnose game materials, node graphs, custom shaders or post-processing in Babylon.js.

## Engine and dependencies

Before edits or tool launches, run `resolve-engine.sh` and `resolve-skill.sh babylonjs-build-materials`; require compatibility and honor task override scope. Read the Babylon revision, WebGL/WebGPU selection, material contract, art pipeline and shader/texture budgets. Additional material libraries and external textures remain explicit dependencies with rights evidence.

## Workflow

1. Choose `PBRMaterial`, a supported simplified PBR material, `NodeMaterial`, or a justified `ShaderMaterial` for the effect. Keep the graph/source and exposed tuning parameters in the project rather than depending on a remote snippet at runtime.
2. Declare metallic/roughness workflow and packed texture channels. `PBRMaterial` properties differ from simplified material names: verify albedo, bump, reflection and metallic texture mappings instead of assuming glTF channel defaults on every hand-authored material.
3. Match normal orientation, UV sets, alpha-test/blend mode, sidedness, environment textures and image-processing configuration. Apply tone mapping/color transforms once across material and post-process stages.
4. Verify node/custom shader compatibility with the selected backend and revision. Bound variants, texture sizes, transparency, lights, shadows and render targets; update parameters without unnecessary recompiles. Report unsupported effects instead of silently replacing the renderer.
5. Define shared versus per-actor material ownership. Clone only when mutations need isolation; dispose owned effects, materials, textures and render targets when unused without invalidating retained scenes.

## Output and verification

Deliver reproducible material definitions, texture/channel table, lighting reference and measured cost. Inspect neutral and gameplay lighting, grazing angles, cutouts/transparency, skinned meshes and quality levels on target browsers. Capture compile failures and backend limitations. Visual inspection and profiling complement shader compilation; neither structural checks nor a black-canvas screenshot proves success. Consult the [PBR material guide](https://doc.babylonjs.com/features/featuresDeepDive/materials/using/masterPBR) for the installed version's property behavior.
