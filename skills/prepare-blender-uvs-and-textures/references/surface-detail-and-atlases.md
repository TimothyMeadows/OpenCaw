# Surface detail and atlas delivery

## Density and detail allocation

Measure texel density against the real surface, not the size of the image alone. For a square texture, linear density along an edge is `texture resolution × UV edge length / world edge length`. For an approximately uniform island, use `texture resolution × sqrt(UV area / world area)`; report stretch and anisotropy separately. A half-tile-wide UV span on a one-metre edge at 2048 resolution provides 1024 pixels/metre, not 4096. Rectangular textures require per-axis measurement or a pixel-area calculation with both dimensions.

Set density ranges from target camera distance and the detail that must survive. Prioritize readable facial, mechanical or signature features deliberately; document exceptions rather than enlarging every island. Review the checker, final texture and smallest shipped mip at target scale. Distortion, seams and mirrored tangent behavior still require inspection even when average density passes.

## Hair cards, foliage and repeated surfaces

Assign stable atlas regions to named clumps, leaf families, trims or panels. Retain source masks and a region-to-material/mesh table so rebakes do not silently change consumers. Separate opacity, strand/leaf direction and authored wind/root masks from color; record the shader's channel semantics. Groom-derived cards and foliage need an approved source mesh/curve identity and preserved tangent/orientation information where their consumer requires it.

Plan dilation and island spacing for the smallest shipped mip, compression and filtering. Inspect actual downsampled results on contrasting backgrounds for halos, cross-island bleed, lost fine strands and foliage popping. Test backfaces, sorting/coverage and overdraw using the selected engine/material; adding alpha cards can increase cost despite lower triangle counts. Atlas packing is not proof that the target supports curves, transmission, two-sided lighting or a chosen transparency mode.

## High-to-low detail and channels

Keep source high detail and low topology distinct, freeze triangulation/tangent and cage/ray settings, then inspect grazing highlights, panel edges and overlapping assemblies for projection leaks. Do not bake a moving part's shading from its neighbor into a shared fixed surface. Preserve suitable UVs; a new unwrap or atlas revision invalidates its bake and dependent review.

Maintain an explicit table for each delivered image: semantic, source channel, destination channel, color/non-color interpretation, alpha meaning, normal convention and shader consumer. Keep unpacked sources and document any inversion such as roughness to smoothness. There is no universal Unity mask layout: use the selected shader/pipeline owner. glTF metallic-roughness uses green roughness and blue metallic; occlusion uses red when present, and sharing that image is a deliberate compatible choice. Do not infer target normal-map orientation or green-channel inversion from the file extension.

## Evidence

Deliver density measurements, checker/stretch views, atlas-region ownership, source/cage/bake settings, unpacked and packed identities, mip/alpha samples and selected-target review. Missing shader support, map dependencies or applicable target testing blocks that delivery claim. Existing UV/bake provenance and independent review remain required.

## Primary references

- [Blender 4.5 glTF export](https://docs.blender.org/manual/en/4.5/addons/import_export/scene_gltf2.html): supported material translation, channels and limitations.
- [glTF 2.0 material specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials): use the actual consumer and supported extensions.
