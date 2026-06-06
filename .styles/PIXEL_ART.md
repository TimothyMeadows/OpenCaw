# PIXEL_ART.md

## Intent

Create crisp raster art with deliberate pixel placement, stable scale, readable silhouettes, and palette discipline.

## Production Rules

- Lock pixels-per-unit, camera scale, sprite dimensions, outline weight, and export scale before production.
- Use limited palette ramps for light, shadow, material, damage, magic, biome compatibility, and UI states.
- Keep sprites readable at gameplay scale before adding interior detail.
- Maintain consistent frame sizes, anchor points, row order, transparency, and directional mapping in sprite sheets.
- Use point filtering or equivalent crisp rendering unless the project explicitly chooses smoothed high-resolution raster art.

## Acceptance Checks

- No blurred upscale, inconsistent pixel density, cropped limbs, malformed anatomy, broken transparency, or accidental text.
- Animation keeps planted feet, stable anchors, clear anticipation/contact/recovery, and consistent facing.
- Sprites are validated on representative tiles, backgrounds, VFX, and UI overlays.

## Role Fit

Use with `pixel-artist`, `tile-set-artist`, `game-vfx-artist`, and isometric roles when pixel art is used in a 2.5D view.
