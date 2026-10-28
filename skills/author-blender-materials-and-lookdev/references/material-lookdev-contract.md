# Material and look-development contract

## Translate the active style

Convert `STYLE.md` into a decision table for geometry language, palette/value ranges, surface breakup, edge treatment, texture frequency, outline or ramp policy, lighting response, camera distance, and disallowed motifs. This translation applies the selected style; it does not create or replace a style template.

## Shader ownership

Give materials and reusable node groups stable names, documented inputs, safe defaults, bounded node cost, and one owner. Separate authored textures from generated masks and distinguish look-development controls from exportable runtime parameters.

## Color and render compatibility

Declare every texture colorspace, scene color transform, target render engine, and known runtime substitutions. Avoid engine-specific nodes in a portable path unless a bake or fallback is specified.

## Evidence

Capture neutral-light material spheres or swatches, representative asset views, final-light views, extreme roughness/metal response, texture-missing fallback, and target export comparison. Approval is bound to the material graph and image dependency identities in the scene report.

## Constructed surface detail

Identify what must read as silhouette geometry, geometric relief, baked normal detail or roughness/color variation at the target camera. Give bevels and layered plates enough physical scale to produce coherent highlights; do not substitute dark painted seams for required thickness or clearances. Separate metal surfaces from dielectric coatings, transparent covers and emissive interiors rather than force one material family over every part.

Inspect metal response under broad and narrow reflections, then at the final camera. Flat color alone cannot establish metallic appearance. Keep wear and texture frequency consistent with construction and scale; procedural noise is not a substitute for intended panel, tooth or feather structure. Repeat the inspection after baking and re-import.

Groom/foliage materials require explicit two-sided, opacity/coverage, tangent and wind-mask consumers. Curves or custom Blender nodes are not automatically portable. Route source-channel and mip policy through UV/texturing, and choose target approximations explicitly through the selected engine owner.

Emissive color, glare and actual scene illumination are different outputs. Review emissive accents without clipped highlights concealing surface defects. A static exported material is not evidence of portable animated emission; downstream motion/effects owners must provide the supported animation or engine presentation implementation.
