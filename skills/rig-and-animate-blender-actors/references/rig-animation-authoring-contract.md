# Rig and animation authoring contract

## Skeleton

Record units, axes, grounding, bind pose, deform and control bone sets, hierarchy, bone roll, scale inheritance, constraints, custom properties, sockets, and stable skeleton identity. Export only the documented deform and attachment contract.

## Skinning

Test normalized weights, maximum influences, unweighted vertices, locked regions, mirrored naming, volume preservation, intersections, and deformation at required extremes. Correct weights at the source rather than hiding failures in a runtime modifier.

## Actions and NLA

Every action has a semantic role, frame range, fps, loop policy, root-motion policy, contact markers, expected start/end pose, and skeleton identity. Define whether NLA tracks are authoring organization or shipped composition. Avoid action assignment that depends on current UI state.

## Runtime handoff

The Blender result is authored evidence, not a runtime verdict. `prepare-rigged-runtime-actors` owns runtime format, compatible skeleton manifest, collider contract, loading/disposal, budgets, and gameplay proof.
