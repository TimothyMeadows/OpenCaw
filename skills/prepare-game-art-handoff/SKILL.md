---
name: prepare-game-art-handoff
description: Prepare game art assets for implementation handoff with style references, source/runtime file paths, atlas metadata, pivots, anchors, animation rows, collision assumptions, sorting layers, licensing, and validation checks. Use when art roles deliver assets to engineering, QA, game design, or documentation.
---

## When to use
Use when sprites, tiles, props, VFX, UI icons, parallax layers, generated concepts, pre-rendered assets, or isometric art need to move from concept or production into an engine/runtime workflow.

## Workflow
1. Read `../STYLE.md` and any relevant `.styles` template before describing the handoff.
2. Identify asset type, owner role, source file, runtime export, intended engine/runtime, and target scene or feature.
3. Record metadata needed by implementation: dimensions, frame grid, atlas key, padding, pivot, anchor, origin, sorting layer, collision hints, animation names, loop rules, and compression expectations.
4. For isometric assets, include projection, tile footprint, elevation unit, contact point, wall/roof/floor layer expectations, and occlusion strategy.
5. Include validation evidence or required checks: style contract, readability, transparency, seams, animation playback, sorting, contrast, performance budget, and licensing.
6. Name downstream responsibilities clearly so art, design, engineering, QA, and documentation do not infer hidden contracts.

## Output
- concise handoff brief
- source and runtime asset paths
- metadata table or manifest-ready fields
- open questions and blocked assumptions
- validation checklist
- downstream role responsibilities

## Commands
- `./commands/print-game-art-handoff-template.sh [asset-type] [engine]`
- `./commands/print-isometric-production-checklist.sh [asset-type]`
- `./commands/inspect-animation-sheet-folder.sh [folder] [cell-size]`
- `./commands/validate-style-contract.sh [STYLE.md]`
