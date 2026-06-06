# ISOMETRIC_2_5D.md

This is the primary style template for isometric-first game art.

## Intent

Create a coherent 2.5D world using a fixed isometric or dimetric projection where 2D assets imply depth, elevation, occlusion, and tactical space.

## Production Rules

- Default to a 2:1 dimetric diamond for raster isometric art unless the project records a different projection in `STYLE.md`.
- Lock tile width, tile depth, elevation step, camera angle, character height, door height, and prop footprints before production assets.
- Use stable foot/contact anchors for characters and base anchors for props; sorting should follow gameplay contact points, not sprite centers.
- Separate floor, wall, roof, prop, character, VFX, overlay, shadow, and UI-marker layers.
- Slice tall assets when one sprite would break occlusion around walls, roofs, trees, cliffs, bridges, or doors.
- Express elevation with consistent wall bands, stairs, shadows, cliff tiers, ramps, and contact points.
- Keep walkable ground, blockers, doors, stairs, hazards, cover, objectives, pickups, and interactables visually distinct.

## Acceptance Checks

- Characters remain readable against roads, grass, water, cliffs, interiors, and high-detail props.
- Depth sorting works in front of and behind tall props, walls, stairs, roofs, and foreground overlays.
- Lighting direction, cast shadows, contact shadows, and value grouping agree across tiles, props, sprites, and VFX.
- Atlas exports include transparent backgrounds, padding, pivots, anchors, layer notes, and collision/readability assumptions.

## Role Fit

Use with `isometric-2-5d-art-director`, `isometric-2-5d-environment-artist`, `tile-set-artist`, `pixel-artist`, `pre-rendered-2-5d-artist`, and `game-vfx-artist`.
