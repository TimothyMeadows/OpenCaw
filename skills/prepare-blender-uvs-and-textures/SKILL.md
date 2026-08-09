---
name: prepare-blender-uvs-and-textures
description: Prepare Blender 4.5 UV layouts, bake inputs, texture maps, atlases, UDIMs, and packed delivery. Use for seam planning, texel-density control, UV channels, bake cages, map verification, texture packing, and runtime texture handoff.
---

# Prepare Blender UVs and Textures

## When to use

Use when a Blender asset needs seams, measured UVs, atlases or UDIMs, bake cages, verified maps, channel packing, or staged textures.

## Workflow

1. Confirm target renderer, camera, material model, texture budget, compression, and required UV channels.
2. Place seams by visibility, distortion, deformation, and material boundaries; measure texel density rather than estimating it.
3. Choose unique UVs, mirrored regions, trim sheets, atlases, or UDIMs from the delivery contract.
4. Freeze high/low identities, cage ownership, tangent basis, ray distances, and map conventions before baking.
5. Check overlap policy, padding at target mip levels, distortion, orientation, color space, and channel packing.
6. Store source and staged textures separately and verify every image dependency in the scene report.

Read [uv-bake-texture-contract.md](references/uv-bake-texture-contract.md) for required measurements and map rules.

## Guardrails

- Do not use UDIMs or oversized maps when the target cannot consume them.
- Do not bake from an unfrozen cage or silently mix tangent bases.
- Do not pack or promote textures without reversible source-channel documentation.
