# PARALLAX_BACKGROUND.md

## Intent

Create layered backgrounds that imply depth through independent scroll speeds, repeat behavior, atmosphere, and value separation.

## Production Rules

- Define background layers, order, scroll scale, repeat size, viewport coverage, loop behavior, and camera constraints.
- Keep far layers slower and lower contrast than foreground gameplay elements.
- Make infinite-scroll textures seamless and large enough for target viewports.
- Keep detail density and contrast away from critical gameplay focus zones unless used as intentional landmarks.

## Acceptance Checks

- No visible seams, gaps, or mismatched horizon/perspective cues during camera movement.
- Gameplay silhouettes, HUD, text, and markers remain readable over backgrounds.
- Layers behave correctly across aspect ratios, zoom levels, and camera speeds.

## Role Fit

Use with `parallax-background-artist`, `game-vfx-artist`, and environment roles.
