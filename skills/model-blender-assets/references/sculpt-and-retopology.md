# Sculpt and retopology decisions

## Preserve what the next operation needs

Before changing topology, record the source hash, scale, finest required feature, thin walls/gaps, material and UV boundaries, shape keys, rig/deformation needs and delivery budget. Keep separate high-detail and derived working candidates. Decide which attributes must survive and how correspondence will be verified; similarity of silhouette alone does not preserve weights, UVs or material assignments.

If expressions already exist, inspect vertex count, order and correspondence before a topology edit. Preserve the keyed original and choose explicitly between a topology-preserving change and a versioned rebuild/transfer of the basis, every required shape key, weights and dependent corrective/driver bindings. Matching counts alone do not prove correspondence. An approximate surface transfer is a candidate to review, not preserved expression identity. Recheck isolated expressions, combinations, neutral return and weighted extremes; invalidate dependent bake, rig, clip and export evidence when their inputs change. Missing correspondence or an unreviewed transfer blocks the affected expression/motion handoff.

| Method | Appropriate purpose | Required caution |
| --- | --- | --- |
| Sculpt on an established base with Multiresolution | Refine forms while retaining a useful base and subdivision-level relationship for later baking. | Preserve base topology and level identity; changing topology or using Apply Base changes the low/high relationship. Keep displacement dependencies with the source. |
| Voxel remeshing | Rebuild volume during shape exploration or selected repair when uniform spatial resolution is useful. | Resolution can erase thin walls, gaps and small features or merge nearby parts. It does not supply deformation-directed loops. |
| QuadriFlow | Derive a candidate quad layout for a suitable surface and intended downstream operation. | Inspect solver completion, feature/boundary preservation and actual output. Quad output does not automatically make a character deformation-ready or repair intersecting surfaces. |
| Manual retopology | Place loops around intentional bends, openings, hard transitions and known deformation regions. | Inspect surface snapping/projection and back-face capture; redistribute density where it changes shape or deformation. |
| Decimation or targeted simplification | Reduce an otherwise suitable static candidate under measured shape/material constraints. | Protect required silhouettes, boundaries, cavities and small assemblies; inspect shading and bake correspondence after reduction. |

These choices are distinct. Do not call voxel remeshing quad retopology or make all-quads a universal acceptance rule. A selected fixed production pipeline may permit only specific methods; this reference does not authorize changing those methods after a failure.

## Build a useful low/high pair

1. Approve primary proportions and large forms before high-frequency sculpting. Allocate detail to geometry or texture from the required silhouette, parallax, shading and camera distance.
2. Keep rigid parts independent where required. Set remesh resolution against the smallest feature and gap to preserve, with an explicit memory/geometry bound; perform a bounded diagnostic on a candidate before committing to a dense result.
3. For a deforming low mesh, place loops around the actual joint and closing regions, then test representative extremes. A visually uniform quad grid cannot replace this inspection.
4. Compare high and low in matched front/side/back views, silhouettes and feature close-ups. Record the chosen surface-distance measurement and tolerance, outliers, missing components and attribute checks. A measured average cannot hide a lost finger, cavity or attachment.
5. Freeze final low triangulation and high/low correspondence before the UV/bake handoff. Multires baking compares declared subdivision levels; do not use a different evaluated base unknowingly. Preserve the old pair when a repair or topology change invalidates the accepted bake.

Deliver editable high and low sources, method/settings and part ancestry, attribute-transfer findings, before/after counts and shape/deformation evidence. Failed solvers, corrupt geometry, unaccounted attribute loss or exceeded budgets remain failures. Do not silently change algorithms, reset attempt accounting or manufacture acceptance from a nonempty mesh.

## Blender references

- [Blender 4.5 remeshing and retopology](https://docs.blender.org/manual/en/4.5/modeling/meshes/retopology.html): voxel, QuadriFlow and deformation-specific topology.
- [Blender 4.5 Multiresolution](https://docs.blender.org/manual/en/4.5/modeling/modifiers/generate/multiresolution.html): subdivision levels, base-mesh ownership and baking.

These references explain authoring methods; they do not constitute executed Blender fixtures or evidence that a particular derived asset passed.
