# Blender asset handoff to Godot

## Import authority and editable ownership

Resolve GODOT and this skill before project edits or Editor launches. Record exact Godot version, renderer/platform, selected format/importer, material/shader and animation requirements. Use an explicitly staged repository-local export with source identities. Direct .blend import can invoke an external Blender installation; select it deliberately when configured, rather than silently adding a dependency or backend. An exported glTF/GLB is a separate explicit handoff choice.

Keep the imported scene as derived content. Put project-owned behavior and intentional overrides in inherited/wrapper scenes or supported import customization. Preserve resource UIDs, import settings and references; never edit generated import-cache output as authored source. Reimport a controlled fixture to verify intended overrides and bindings survive.

## Geometry and surface checks

Use a known-size asymmetric fixture to verify units, orientation, root/pivots, grounding, transforms and bounds. Curate the runtime-visible variant and decide explicitly how imported or generated LODs and collision are consumed. Naming suffixes/custom import rules can change node types and generated resources; use the selected Godot version's behavior and inspect results instead of applying blanket renames to the master.

Verify material slots, UVs, normals/tangents, textures, channel selectors, color semantics, opacity/culling and renderer support in an actual imported scene. Do not assume Blender nodes, curves, simulations or animated emission transfer as native runtime features. Keep authored source channels and any conversion recipe so material correction is reversible. Review hair/foliage coverage and overdraw under the selected renderer at representative distances.

## Animation and acceptance

For moving content, validate actual hierarchy/skeleton identity, clip names/ranges, tracks, loop boundaries, contacts, pivots and attachment paths after import. Configure AnimationPlayer/AnimationTree behavior through compatible Godot owners; a file does not supply a complete game controller or authoritative motion. Mechanical and rigid profiles do not imply a humanoid skeleton.

Reload the scene, reimport the same source and load it in a real target build. Inspect scale/materials/animation, dependency inclusion, intended LOD/collision behavior and measured cost. Preserve source/export/settings hashes, expected/observed results and blocked/not-run checks. Missing Editor/export templates or renderer support blocks the affected native claim; do not substitute browser or generic Blender evidence for it.

## Primary references

- [Godot importing 3D scenes](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/index.html): follow the project's installed release, including import configuration and inherited scenes.
- [Godot available 3D formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html): direct .blend and exported interchange have different prerequisites.
