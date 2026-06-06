# HD_2D.md

## Intent

Combine high-detail 2D sprites with depth-rich scenes, lighting, post-processing, or 3D-like staging while preserving 2D gameplay readability.

## Production Rules

- Define how 2D sprites coexist with depth layers, lighting, shadows, camera movement, and environmental scale.
- Keep sprite anchors and billboard behavior explicit when assets exist in a depth-staged world.
- Use lighting and atmospheric effects to enhance depth without washing out silhouettes.
- Preserve readable tactical space even when scenes use cinematic composition or heavy atmosphere.

## Acceptance Checks

- Characters and interactables remain readable over high-detail backgrounds.
- Depth effects do not contradict movement, collision, sorting, or UI markers.
- Lighting and post effects can be disabled or tuned without destroying core readability.

## Role Fit

Use with `isometric-2-5d-art-director`, `pre-rendered-2-5d-artist`, `illustrative-2d-artist`, and `game-vfx-artist`.
