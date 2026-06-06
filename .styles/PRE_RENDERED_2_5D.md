# PRE_RENDERED_2_5D.md

## Intent

Create 2D or 2.5D sprites from 3D or high-detail source assets while matching the target game's camera, lighting, scale, and atlas pipeline.

## Production Rules

- Lock orthographic camera angle, render size, lighting, shadow, scale, material style, and transparent export settings before batching.
- Preserve repeatable render presets and source notes for later facings or fixes.
- Export directional sets when gameplay requires facing, rotation, or animation states.
- Clean alpha, padding, halos, compression artifacts, and cropped shadows before handoff.

## Acceptance Checks

- Rendered assets match the project projection, value range, shadow direction, and sprite scale.
- Final sprites read in assembled game scenes after downscaling and compression.
- Source files or render settings are traceable enough for future revisions.

## Role Fit

Use with `pre-rendered-2-5d-artist`, `isometric-2-5d-art-director`, and `pixel-artist`.
