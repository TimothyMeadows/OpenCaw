# Groom and hair-card preparation

## Choose the delivery representation

Confirm whether the consumer supports curves, polygon strands, hair cards or only a baked silhouette. Record target camera distances, required motion, strand/card and material budgets, texture dimensions, alpha policy and maximum visible layer overlap. Blender viewport hair does not imply runtime groom support. Route engine-specific import and shading through the compatible selected-engine owner; do not install a grooming addon or assume a paid plugin.

Keep authored guides, generated density and delivery geometry distinguishable. For a surface-attached groom, bind the surface mesh, attachment UV map and rest/deformation relationship. Changing that surface or UV map invalidates attachment evidence and requires reattachment/review. Preserve the immutable source and work on a versioned candidate.

## Establish flow and coverage

1. Mark growth direction, partings, hairline/edge coverage, length zones and deliberate exposed areas on the subject. Place guides to describe the large clumps and silhouette before increasing density.
2. Check root contact and interpolation across seams, sharply changing curvature, ears, eyelids and clothing. Keep roots attached to the intended surface rather than suspended above it or buried through another part.
3. Add variation within declared length, width, clump and direction bounds. Use explicit seed/input ownership when generating strands; randomness must not destroy the authored flow or make review irreproducible.
4. Inspect coverage from front, back, sides, top and expected grazing angles under neutral light. Diagnose scalp holes, intersecting clumps, oversized uniform ribbons and noisy silhouette before fine strand detail.

## When cards are selected

Allocate atlas regions for useful clump shapes and widths instead of filling every region with identical strands. Preserve source images and region ownership. UV/bake ownership defines padding at shipped mips, color/alpha semantics and reversible packing; do not infer a universal texture layout from the word hair.

Build card curvature along the groom flow and place roots beneath the visible outer layer where appropriate. Check face orientation, tangent/UV direction, intentional sidedness and silhouette at the target distance. Cards must not expose a broad flat plane when viewed from a common camera. Extra layers cost transparency overdraw even when triangle counts are small; measure both in the target runtime.

Create distance reductions that preserve the large clumps and outer contour, then reduce layers, card segmentation and texture cost deliberately. Review each transition, compressed alpha edges, mip coverage and the actual consumer's transparent/alpha-tested shading. A dense near-view groom is not an acceptable distant LOD solely because it renders correctly in Blender.

## Motion and delivery

Declare rigid attachment, skin weights or a separately selected simulation. Test turning, relevant poses and close contacts before handoff; static coverage does not certify animated attachment. Simulation work uses cache/version/replay evidence from `simulate-blender-effects`; a Blender cache is not automatically a runtime hair solver.

Deliver editable guides, bound surface/UV identities, delivery geometry/atlas ancestry, measured budgets and required distance/pose views. Block on lost attachments, unexplained scalp exposure, excessive overdraw or unsupported consumer representation. Groom approval remains separate from runtime acceptance.

## Blender reference

[Blender 4.5 Hair Curves properties](https://docs.blender.org/manual/en/4.5/modeling/curves_new/properties.html) describes surface and UV-based attachment, including reattachment after UV changes. Read the relevant curve/deformation documentation for the actual selected setup.
