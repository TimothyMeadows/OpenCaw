# Rig and animation authoring contract

## Skeleton

Record units, axes, grounding, bind pose, deform and control bone sets, hierarchy, bone roll, scale inheritance, constraints, custom properties, sockets, and stable skeleton identity. Export only the documented deform and attachment contract.

## Skinning

Test normalized weights, maximum influences, unweighted vertices, locked regions, mirrored naming, volume preservation, intersections, and deformation at required extremes. Correct weights at the source rather than hiding failures in a runtime modifier.

## Actions and NLA

Every action has a semantic role, frame range, fps, loop policy, root-motion policy, contact markers, expected start/end pose, and skeleton identity. Define whether NLA tracks are authoring organization or shipped composition. Avoid action assignment that depends on current UI state.

## Runtime handoff

The Blender result is authored evidence, not a runtime verdict. `prepare-rigged-runtime-actors` owns runtime format, compatible skeleton manifest, collider contract, loading/disposal, budgets, and gameplay proof.

## Profiled mechanical and rigid motion

`build-model-animations` supplies a separate motion-package contract for skinned, articulated and rigid assets. Mechanical parts need stable semantic nodes, real separation, pivots, axis limits and parameter ownership. A rigid hull needs anchors and local response only when declared; do not add an artificial skeleton. Keep wheel/steering/suspension and thruster/control-surface ownership explicit. A fused display mesh requires modeling repair before independent articulation.

Review complete clips and transition windows, loop seams, root displacement, contact, pose extremes and attachments. Declare in-place versus extracted root motion and prevent duplicate controller/clip translation. Retarget using actual source clip provenance, target rig identity, explicit mappings and rest-axis/scale corrections; a clip name is insufficient evidence of compatibility. Native motion production uses only its fixed audited scripts and records exact source/tool/output hashes.
