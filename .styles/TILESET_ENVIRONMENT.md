# TILESET_ENVIRONMENT.md

## Intent

Create reusable terrain, biome, settlement, dungeon, and structure kits that assemble cleanly into readable maps.

## Production Rules

- Define tile dimensions, masks, anchors, collision hints, walkability, render layers, and atlas grouping.
- Build base tiles, edge tiles, corner tiles, diagonals, transitions, feature tiles, statics, elevation pieces, and decorative variants.
- Keep terrain grammar consistent across roads, water, cliffs, shores, walls, floors, roofs, bridges, interiors, and vegetation.
- Use enough variants to reduce repetition without hiding navigation or gameplay boundaries.

## Acceptance Checks

- Seam tests cover every intended neighbor arrangement.
- Walkable ground, blockers, hazards, cover, doors, stairs, ledges, and interactables are visually distinct.
- Assembled maps preserve lighting direction, texture scale, palette, and character readability.

## Role Fit

Use with `tile-set-artist`, `isometric-2-5d-environment-artist`, and `isometric-2-5d-art-director`.
