# WEB_ATMOSPHERIC.md

## Intent

Create immersive web scenes through depth, light, color, and controlled motion while keeping the content and interaction path primary.

## Production Rules

- Establish a static composition with readable content before adding parallax, particles, canvas, video, or 3D layers.
- Assign every atmospheric layer a communication purpose, quality tier, loading strategy, and motion fallback.
- Protect text with stable contrast surfaces rather than relying on a favorable frame of moving imagery.
- Pause offscreen or hidden effects and cap density, resolution, and update frequency by device profile.
- Avoid rapid flashes, involuntary camera motion, and continuous movement near reading content.

## Acceptance Checks

- Core content and actions remain complete when effects fail or are disabled.
- Reduced-motion mode removes nonessential movement without leaving blank structure.
- Loading, memory, and frame-time measurements satisfy the host budgets.
- Layer order, pointer behavior, focus, and scrolling remain predictable.

## Role Fit

Use with `web-experience-designer`, `frontend-developer`, `art-director`, and `qa-engineer`.
