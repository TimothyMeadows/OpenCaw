# PAINTERLY_2D.md

## Intent

Create high-resolution painted 2D assets with controlled value, atmosphere, material texture, and game-scale readability.

## Production Rules

- Establish brush language, rendering finish, edge softness, palette, lighting temperature, and focal detail rules.
- Keep high-detail rendering away from gameplay-critical boundaries unless it improves recognition.
- Use value grouping and silhouette control to prevent painterly noise from reducing readability.
- Export clean raster assets with documented anchors, transparent backgrounds, and atlas/compression expectations.

## Acceptance Checks

- Assets remain legible after downscaling, compression, and placement in game scenes.
- Materials and lighting stay consistent across characters, props, structures, and backgrounds.
- Detail does not hide collision, pathing, hazards, pickups, or objectives.

## Role Fit

Use with `illustrative-2d-artist`, `pre-rendered-2-5d-artist`, and `isometric-2-5d-art-director`.
