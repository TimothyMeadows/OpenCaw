---
name: build-procedural-blender-scenes
description: Build deterministic Blender 4.5 Geometry Nodes systems, modular kits, instanced assemblies, and procedural set dressing. Use for reproducible scene generation, seed policy, instance ownership, realization decisions, modular placement, and procedural export handoff.
---

# Build Procedural Blender Scenes

## When to use

Use for Geometry Nodes, modular kits, deterministic instancing, procedural placement, realization policy, or reproducible scene assembly.

## Workflow

1. Define inputs, stable identifiers, seed ownership, bounds, asset sources, and the inspectable output contract.
2. Separate authored kit pieces from procedural composition and keep dependencies repository-confined.
3. Prefer instances until editing, simulation, render, or export requires realization.
4. Bound density, recursion, node evaluation, memory, and worst-case geometry with measurable limits.
5. Test the same inputs and seed for repeatable structure and named output.
6. Record realization, baking, regeneration, and manual-override policy before staging.

Read [procedural-scene-contract.md](references/procedural-scene-contract.md) for deterministic and realization requirements.

## Guardrails

- Do not depend on scene order, selection, wall-clock time, or undeclared randomness.
- Do not realize instances by default or conceal unbounded output behind viewport culling.
- Do not ship a procedural scene without a regeneration or frozen-output policy.
