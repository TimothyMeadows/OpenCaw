---
name: plan-hybrid-game-assets
description: Plan a traceable game asset pipeline across procedural, imported, generated, sprite, UI, audio, VFX, and fallback media. Use when choosing how an asset should be created, licensed, optimized, integrated, reviewed, and handed off to a runtime.
---

# Plan Hybrid Game Assets

## When to use

- Selecting an asset production method for a game feature.
- Combining multiple asset types in one coherent runtime.
- Auditing asset provenance, formats, budgets, fallbacks, or handoff completeness.

## Workflow

1. Classify each asset by player-facing purpose, camera, scale, state count, reuse, and runtime constraints.
2. Choose the simplest production lane that can meet the visual and interaction requirement.
3. Record source, creator, license, generation or conversion steps, and modification rights.
4. Define source and runtime formats, naming, dimensions, pivots, anchors, compression, LOD, atlas, and fallback behavior.
5. Validate the asset in representative gameplay rather than only an isolated viewer.
6. Hand off through `prepare-game-art-handoff` with ownership and acceptance evidence.

When Blender is the selected production lane, use `direct-blender-production` to establish the immutable source, working-copy, backend, checkpoint, inspection, staging, and review contract.

## Output

- An asset decision matrix and production plan.
- Provenance, format, budget, fallback, and integration metadata.
- Runtime review scenarios and handoff acceptance criteria.

## Guardrails

- Do not assume generated, purchased, or downloaded assets are automatically redistributable.
- Do not call a concept image a runtime-ready asset.
- Do not choose a heavy asset lane when a simpler form meets the gameplay need.
