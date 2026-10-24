# Tile topology and pixel presentation

## Tilemap authoring

Confirm Grid layout, cell size/gap, orientation, sorting, chunk behavior and collider ownership. Preserve Tile assets and their `.meta` identities. Separate terrain appearance, gameplay occupancy and collision semantics; painting an attractive tile must not silently change navigation or damage rules.

For RuleTiles, write a small expected-neighborhood table before generating rules: center type, relative cells, required matches/nonmatches, chosen output sprite, allowed rotations/mirroring and collider result. Include isolated cells, straight boundaries, inside/outside corners, narrow passages, holes and neighboring tile families. Rule order can change which match wins. Custom RuleTile subclasses can redefine neighbor equivalence, so inspect their actual implementation. Do not derive a universal rule set from file names or an assumed 47-tile layout.

A meaningful native fixture paints declared cells into a real Tilemap, refreshes the affected cells, checks the resulting sprite/transform/collider settings and removes a neighbor to force a second result. Clearing and reloading a scene should retain the same output. These checks validate the supplied topology table, not an artist's intended world grammar; that intent still needs review.

For animated/random tiles, state seed and timing requirements. Avoid gameplay authority derived from a randomly selected visual frame. Regeneration must preserve project-authored cells and references outside the selected region. Rebuild composite colliders and navigation only through the selected physics/navigation workflows and verify their final geometry.

## Pixel-perfect presentation

Inspect the selected Pixel Perfect package/camera and renderer compatibility. Record source pixels per unit, reference resolution, integer scaling/crop policy, camera movement and UI scaling. Pixel snapping is a presentation decision; do not round authoritative motion or collision coordinates to conceal camera jitter. Verify transforms through parent scale and rotation, sprite pivots, texture filtering and render-target upscaling.

Capture stationary and scrolling scenes at the declared resolutions and fractional display scales. Check seams, subpixel shimmer, camera follow, animations, diagonal motion and overlay UI. A headless tile-data assertion cannot certify display appearance.

## Sources

- [2D Tilemap Extras 3.0 RuleTile](https://docs.unity3d.com/Packages/com.unity.2d.tilemap.extras@3.0/manual/RuleTile.html).
- [2D Pixel Perfect 5.0](https://docs.unity3d.com/Packages/com.unity.2d.pixel-perfect@5.0/manual/index.html).
- [TilemapCollider2D](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Tilemaps.TilemapCollider2D.html).

Use installed-version documentation and explicitly selected packages.
