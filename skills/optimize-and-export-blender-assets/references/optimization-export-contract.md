# Optimization and export contract

## Measure first

Record source and candidate totals for objects, vertices, triangles, draw-relevant material slots, textures and memory, bones, influences, actions, morph targets, instances, modifiers, caches, and package bytes. Budget against the representative target, not an isolated editor.

## Delivery transformations

LODs, decimation, baking, atlas conversion, modifier application, collision proxies, transform application, dependency packing, and animation reduction are reversible derived steps. Bind each derived file to its source and settings.

## Format decisions

- GLB: prefer for portable real-time meshes, PBR materials, skins, morphs, and animations.
- FBX: use only when a target workflow requires it and record axis, unit, bone, and animation quirks.
- USD: use for scene composition or interchange where the consumer's supported subset is known.
- Alembic: use for baked geometry caches where editability and rig semantics are not required.

## Proof

Re-import or independently inspect the staged artifact. Verify transforms, hierarchy, normals, UVs, materials, textures, animations, cameras, instances, collisions, scale, bounds, dependency completeness, budgets, and representative target behavior.
