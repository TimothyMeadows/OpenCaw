---
name: review-isometric-production
description: Review isometric and 2.5D game art for projection, tile metrics, anchors, elevation, depth sorting, occlusion, lighting, walkability, and gameplay readability. Use for isometric sprites, tiles, props, environments, VFX, maps, atlas handoffs, or style reviews.
---

## When to use
Use whenever an art role creates, reviews, or hands off assets for an isometric-first game, especially when the asset interacts with tiles, elevation, collision, occlusion, characters, VFX, or UI markers.

## Workflow
1. Read `../STYLE.md`; if it references `ISOMETRIC_2_5D`, read `./.styles/ISOMETRIC_2_5D.md`.
2. Confirm the projection, tile width/depth, elevation step, camera angle, character scale, and lighting direction before judging detail quality.
3. Review anchors: character feet, prop bases, wall bases, roof slices, VFX origins, contact shadows, and atlas pivots.
4. Review depth behavior: layer names, draw order, sortable slices, roof/wall/floor separation, foreground overlays, and tall-prop occlusion.
5. Review gameplay readability: walkable ground, blockers, hazards, doors, stairs, cover, interactables, pickups, objectives, and UI markers.
6. Require handoff metadata for any asset whose runtime behavior depends on pivots, collision, animation timing, sorting, or map placement.

## Output
- pass/fail or ready/needs-work summary
- projection and scale assumptions
- anchor, pivot, layer, and sorting findings
- readability and collision concerns
- required fixes before production handoff
- downstream owner notes for art, design, engineering, QA, or documentation

## Commands
- `./commands/print-isometric-production-checklist.sh [asset-type]`
- `./commands/print-game-art-handoff-template.sh [asset-type]`
- `./commands/validate-style-contract.sh [STYLE.md]`
