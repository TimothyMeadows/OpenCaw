---
name: author-blender-materials-and-lookdev
description: Author Blender 4.5 PBR or stylized materials and controlled look development from the active OpenCaw style contract. Use for shader graphs, reusable node groups, colorspace, material response, style translation, and renderer-compatible look approval.
---

# Author Blender Materials and Lookdev

## When to use

Use when the active visual style must become Blender material, shader-node, colorspace, reusable look-development, or target-renderer decisions.

## Workflow

1. Read `STYLE.md`; translate its shape, palette, value, texture, lighting, and readability rules into explicit Blender decisions.
2. Choose PBR, stylized, or hybrid shading and declare the target render or runtime translation.
3. Establish material, node-group, parameter, texture, colorspace, and ownership conventions.
4. Build reusable shaders with bounded complexity and predictable defaults.
5. Review in controlled neutral light and representative final light across required camera distances.
6. Record unsupported nodes, bakes, approximations, and export substitutions before handoff.

Read [material-lookdev-contract.md](references/material-lookdev-contract.md) for style translation and shader evidence.

## Guardrails

- Do not invent a new style contract or override the active one.
- Do not use display-referred color data as linear material data.
- Do not approve a material only in one flattering light or hide export incompatibility.
