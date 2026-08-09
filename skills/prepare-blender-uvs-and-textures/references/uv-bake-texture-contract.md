# UV, bake, and texture contract

## UV policy

Declare every UV channel by purpose. Measure density in pixels per world unit, permit overlap only by named policy, orient shells when directional detail requires it, and calculate padding for the smallest shipped mip. Atlases require stable region ownership; UDIMs require explicit target support and tile budgets.

## Bake policy

Bind high mesh, low mesh, cage, tangent basis, triangulation state, ray settings, anti-aliasing, output size, and map convention. Verify gradients, skew, missed rays, seams, projection leaks, and mirrored tangent behavior before accepting a bake.

## Maps and color

Declare map semantic, source color space, bit depth, channel layout, alpha meaning, compression target, and runtime sampler expectations. Treat base color and emissive as color data; treat normal, roughness, metallic, masks, depth, and packed channels as non-color data unless the target explicitly differs.

Keep unpacked source maps. Packing is a reversible delivery step with a documented channel table and no hidden destructive conversion.
