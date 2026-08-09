# Material and look-development contract

## Translate the active style

Convert `STYLE.md` into a decision table for geometry language, palette/value ranges, surface breakup, edge treatment, texture frequency, outline or ramp policy, lighting response, camera distance, and disallowed motifs. This translation applies the selected style; it does not create or replace a style template.

## Shader ownership

Give materials and reusable node groups stable names, documented inputs, safe defaults, bounded node cost, and one owner. Separate authored textures from generated masks and distinguish look-development controls from exportable runtime parameters.

## Color and render compatibility

Declare every texture colorspace, scene color transform, target render engine, and known runtime substitutions. Avoid engine-specific nodes in a portable path unless a bake or fallback is specified.

## Evidence

Capture neutral-light material spheres or swatches, representative asset views, final-light views, extreme roughness/metal response, texture-missing fallback, and target export comparison. Approval is bound to the material graph and image dependency identities in the scene report.
