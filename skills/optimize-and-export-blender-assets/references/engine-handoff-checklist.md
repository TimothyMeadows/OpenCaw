# Verified Blender-to-engine handoff

## Select the actual consumer

Resolve ENGINE.md, then the relevant engine skill before an engine-owned edit or tool launch. Blender skill eligibility does not select an engine or authorize an incompatible producer. Use the project's actual importer/plugin, shader, version and platform; no export preset is universal.

- UNITY: [Unity scene handoff](../../unity-build-scenes/references/blender-asset-handoff.md).
- UNREAL: [Unreal native asset handoff](../../unreal-integrate-assets/references/blender-asset-handoff.md).
- GODOT: [Godot scene handoff](../../godot-build-scenes/references/blender-asset-handoff.md).
- THREEJS/BABYLONJS: use their compatible scene/material/animation owners and explicit loader/plugin versions. Inspect the independently loaded artifact, disposal and target rendering rather than assume GLB previews certify runtime behavior.
- PHASERJS: agree an explicit sprite/pre-rendered handoff. A Blender scene or animated GLB does not by itself create Phaser's 2D actor content.

## Prepare a curated export

Record the selected object/collection identities, root, units, axes, pivots, grounding, materials, textures, clips and intended LOD/collider representation. Export one intended runtime variant; keep alternate LODs, high-detail bake sources, colliders and reference cameras out of the visible model unless their consumer contract explicitly needs them. Do not delete those sources from the master.

Create controlled derived copies for required transform/modifier changes. Applying all transforms indiscriminately can destroy rig, pivot, constraint or animation semantics. Prove unit/orientation conversion with a known-size asymmetric fixture and inspect the produced artifact's bounds/root before modifying a detailed asset.

Document unsupported nodes, instances, curves, custom attributes and simulations. Bake/convert only when the selected format and consumer require it, with reviewed ancestry and measured detail loss. Do not remove hidden interiors when motion, damage, another view or an attachment may expose them.

## Verify the produced artifact

Independently re-import into a clean inspection scene and use the actual target when available. Compare scale/axes/grounding, hierarchy/pivots, normals/tangents/UVs, material slots/channels, texture paths, representative animation times/loop seams and declared collider/LOD behavior. Check the runtime variant alone; multiple overlapping versions can hide a broken selection or double geometry cost.

Record source/export hashes, tool/settings, dependencies, before/after measurements and expected/observed results. Failed exports/imports, missing target prerequisites and visual unknowns remain explicit. A successful generic inspection does not certify native import, cook/build or gameplay. Preserve source-specific motion/action review and separate human runtime acceptance before promotion.
