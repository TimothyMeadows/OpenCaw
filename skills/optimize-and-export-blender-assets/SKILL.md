---
name: optimize-and-export-blender-assets
description: Measure, optimize, package, and export Blender 4.5 assets to GLB, FBX, USD, or Alembic with engine-neutral verification. Use for budgets, LODs, collision proxies, transforms, dependencies, format selection, export staging, and runtime handoff.
---

# Optimize and Export Blender Assets

## When to use

Use when a Blender asset needs measured budgets, LODs, collision proxies, transform policy, dependency packaging, export, or independent re-import verification.

## Workflow

1. Freeze target format, coordinate system, units, pivots, hierarchy, animation, materials, collisions, dependencies, and budgets.
2. Measure the current candidate before changing topology, textures, materials, modifiers, bones, actions, or caches.
3. Create reversible LOD, proxy, bake, and simplification steps from an immutable source.
4. Apply only delivery-required transforms and modifiers; record exclusions and format substitutions.
5. Export to a staging path and re-import or inspect the produced artifact independently.
6. Route static assets through `prepare-game-art-handoff` and rigged actors through `prepare-rigged-runtime-actors`.

Read [optimization-export-contract.md](references/optimization-export-contract.md) for formats, budgets, and proof.

## Guardrails

- Do not optimize by overwriting the authored master.
- Do not trust exporter success as proof of hierarchy, animation, material, or collision correctness.
- Do not promote staged output without measured budgets and representative target review.
