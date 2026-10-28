# Vegetation production

## Decide what must survive at distance

Start from the plant's approved species or stylized structure, growth habit, silhouette, camera range and seasonal condition. Record supported observations separately from inferred hidden branching. Define a trunk/branch/leaf hierarchy and variation limits; random rotation and scale cannot repair an implausible growth structure.

Choose authored geometry, cards or a hybrid for the declared viewing distances. Build the trunk and principal branch silhouette first, then branch clusters and foliage coverage. Keep attachment ownership clear so leaves do not float away from their branches when wind or LOD changes. An approved high-detail source remains immutable; simplified variants are derived assets.

## Placement and surface controls

Use declared density masks, slope/height restrictions, exclusion regions, bounds and stable seeds for scattering. Check the edges of clearings, walkable paths and adjacent assets; surface normals alone do not guarantee plausible orientation or usable clearances. Test a sparse and a dense case. Bound geometry, alpha coverage, material slots and evaluation costs before realizing instances.

For leaf cards, preserve the source atlas and region identities, crop transparencies deliberately, provide mip-aware padding and document alpha mode and texture colour semantics through the UV owner. Inspect both sides, backlighting and oblique angles in the actual target. A two-sided material is an explicit rendering decision with a cost; it must not hide incorrect orientation or solve all thin-surface shading by assumption.

## Wind and movable regions

Declare whether the result is a static mesh, baked clip or target-engine deformation. Record local root-to-tip weights, branch stiffness regions, per-instance phase and the coordinate space used by each control. Inspect attribute names, data types and domains before export, then verify the target channel mapping after re-import. Raw Geometry Nodes attributes are not proof that the engine received wind controls.

Test still, representative and maximum agreed wind, including branch junctions and root anchoring. Avoid trunk translation, branch separation, intersecting clusters and synchronized motion across the whole stand unless intentional. Tie preview motion to an explicit clock; engine presentation does not gain authority over collisions or gameplay outcomes. Shader wind, alpha modes and selected engine integrations belong to compatible engine skills.

## LOD and complete-scene review

Review near, middle and far views for canopy volume, leaf distribution, silhouettes, alpha shimmer, normal response, overdraw and transitions. Build each LOD around what those views need; uniform decimation can collapse thin cards or remove the branches carrying the silhouette. Impostors or billboards require a selected engine/format path and real target evidence rather than an assumed universal exporter option.

Deliver the plant master, approved variation inputs, atlas/mask provenance, LOD lineage and a representative grouped planting with measured target costs. Missing importer support, lost masks or unreviewed transition popping blocks the affected handoff. Source rights, geometry correctness, motion review and human acceptance remain separate checks.

The [Blender 4.5 attribute reference](https://docs.blender.org/manual/en/4.5/modeling/geometry_nodes/attributes_reference.html) explains storage domains and conversions. Runtime attribute semantics must be specified and tested with the selected consumer.
