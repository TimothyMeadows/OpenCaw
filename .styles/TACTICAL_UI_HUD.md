# TACTICAL_UI_HUD.md

## Intent

Create HUD, minimap, selection, targeting, status, and tactical overlay art that remains readable during gameplay.

## Production Rules

- Define semantic states for selected, hover, disabled, danger, objective, ally, enemy, neutral, blocked, pathable, and interactable.
- Use shape, iconography, outline, motion, and contrast so meaning does not rely on color alone.
- Reserve strongest contrast and motion for immediate player decisions.
- Test UI markers against dense terrain, VFX, characters, fog, shadows, and camera zooms.

## Acceptance Checks

- Text, reticles, minimap elements, targeting markers, and status icons meet contrast/readability expectations.
- HUD and markers do not hide hazards, pickups, hit feedback, or movement cues.
- Overlay scale and placement are stable across desktop/mobile viewports when relevant.

## Role Fit

Use with `css-vector-artist`, `flat-minimalist-game-artist`, `isometric-2-5d-art-director`, and `qa-engineer`.
