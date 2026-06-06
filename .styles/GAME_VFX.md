# GAME_VFX.md

## Intent

Create readable visual effects for combat, magic, weather, pickups, status changes, UI feedback, and environmental atmosphere.

## Production Rules

- Define effect intent, timing, origin, peak, dissipation, blend mode, draw order, lifetime, and gameplay meaning.
- Use silhouettes, values, motion arcs, and timing before adding glow or particle density.
- Export flipbooks with consistent frame sizes, transparent backgrounds, padding, and loop notes.
- Keep VFX proportional to gameplay importance and runtime budget.

## Acceptance Checks

- Effects do not obscure hazards, hitboxes, targeting, text, objectives, or character intent.
- One-shot and looping effects have documented frame/event timing.
- Particle counts, texture size, overdraw, and blend modes fit the target platform.

## Role Fit

Use with `game-vfx-artist`, `pixel-artist`, `illustrative-2d-artist`, and animation roles.
