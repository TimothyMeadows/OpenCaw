# Blender asset handoff to Unity

## Resolve before importing

Require successful UNITY engine and skill resolution before Editor or project edits. Record ProjectVersion.txt, selected platform, package lock, model importer, render pipeline/shader and animation requirements. Use the repository-local staged export and source provenance; retain its reviewed .blend master without opening an external library source. A Blender screenshot cannot establish Unity rendering or runtime correctness.

## Import and identity

Choose a project-supported interchange format and importer deliberately. Do not assume a direct .blend import is dependency-free or install a converter implicitly. Use a known-size asymmetric fixture to check units, forward/up orientation, grounding, pivots and material slots before processing the detailed asset. Preserve existing .meta GUIDs, import settings, prefab bindings and intended overrides on reimport; inspect subasset identity changes before accepting replacement meshes or clips.

Curate one intended LOD/visible variant. Configure LODGroup, collision and object visibility through actual project conventions; alternate meshes and collider sources must not all render together. Keep source normals/tangents or importer recalculation an explicit, tested choice. Verify lightmap UV requirements only where the lighting workflow needs them. Static, Generic and Humanoid rig import choices follow actual topology/hierarchy and motion needs, not the file name.

## Material and texture translation

Select the shader before assigning packed maps. HDRP 17's mask map uses red metallic, green ambient occlusion, blue detail mask and alpha smoothness; import it as non-color data. This layout is not a universal Unity convention. Built-in, URP and custom shaders need their own selected channel/smoothness rules. Keep unpacked sources and record any roughness inversion, normal import convention, alpha coverage and two-sided approximation.

Custom Blender nodes, hair curves, simulations and animated material properties require a supported conversion or explicit runtime implementation. Verify the actual imported material and textures in neutral and representative project lighting. Choose the project's existing UI, rendering and motion owners for additional work rather than install packages to make a preview match.

## Evidence and failure behavior

Reimport a controlled candidate, reopen the intended prefab/scene and inspect scale, root, hierarchy, tangents, material slots, texture channels and bounds. For animation, check clip ranges, rig/avatar mapping when applicable, contacts, loop seams and attachments in the real player; source review does not certify the imported clip. Measure target memory/render cost and confirm the intended LOD/collider behavior. Preserve source/export/import settings and hashes, expected/observed results and blocked/not-run checks. Missing Editor/platform/importer support blocks native acceptance without invalidating a useful generic Blender inspection.

## Primary references

- [Unity model import](https://docs.unity3d.com/6000.0/Documentation/Manual/ImportingModelFiles.html): match the project's Editor and importer version.
- [HDRP 17 mask and detail maps](https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@17.0/manual/Mask-Map-and-Detail-Map.html): shader-specific channel semantics.
