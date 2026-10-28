# Audited Blender motion batches

`motion.py` is the fixed Blender 4.5 LTS entrypoint for MODEL_TO_ANIMATION. The runtime copies only the four modules listed in `scripts.json`, verifies their exact hashes and launches Blender with factory startup, background mode and auto-execution disabled. This working-copy authoring contract applies to this workflow; it does not authorize arbitrary scripts or change standalone BLENDER policy.

Inputs are an authorized project-local GLB or this asset version's previous native working `.blend`. Raw external `.blend` files are not executable authoring inputs. The GLB must contain its own dependencies. Native stages preserve their source bytes and write a new attempt; they never overwrite a master or install addons/models/providers. Adobe authoring/provider integrations are excluded.

## Operations

| Operation | Actual work |
| --- | --- |
| inspect | Load and measure real mesh, hierarchy, materials, skin and coordinate bounds; record semantic readiness as a human review concern |
| prepare | Preserve the model in a working scene; create a stable motion root, declared part hierarchy, geometry-preserving pivots and real attachment/effect empties |
| rig | Preserve a real skin rig or construct declared bones and explicit skin weights; validate mechanical hierarchy without creating fake bones |
| author | Author bounded transform keys as actual Blender actions/slots; a targeted revision replaces only the selected action |
| retarget | Transfer mapped FK pose deltas from an actual owned/licensed source GLB, with explicit rest-axis correction and translation scaling |
| bake | Sample the selected native transform/pose actions across their full frame ranges and write independent exportable actions |
| export | Save editable source, export actual GLB actions/skins/nodes, inspect the exported clip inventory and write a hashed pending-review package |
| review | Independently import the runtime GLB; sample every complete clip and applicable transition, render local proofs and emit a scrub/playback page plus frame hashes |

Inspect/inventory checks do not establish semantic animatability. Rig points and weights are declared inputs. Automatic heat weighting has no distance-weight or provider fallback. Fused parts, missing required nodes, unweighted vertices, bad clip bindings, static named actions, invalid loops/contacts/root policy and exceeded budgets fail the affected operation.

## Declared authoring data

Recipe clips use `id`, `role`, `loop`, `rootMotion`, `startFrame`, `endFrame`, `channels` and `markers`. A channel has exactly one target (`{"node":"Hull"}` or `{"bone":"spine"}`), a property (`location`, `rotation_quaternion` or `scale`) and `[frame, value]` keyframes. Both clip endpoints are explicit. Numeric vectors are finite; scales stay positive.

All JSON quaternions, including channel values and retarget `rotationOffset`, use **[x,y,z,w]**. The script converts them to Blender's internal [w,x,y,z] order. Object vectors and declared skeleton/pivot positions use Blender metres, Z up, subject front -Y. GLB export maps (x,y,z) to (x,z,-y), yielding runtime Y up and subject front +Z. The package records both conventions; no proof-to-model raw-export rotation is reapplied.

Each declared bone has a unique name, head, tail, optional parent/deform flag and optional `maxAngle`. A skinning method is selected explicitly:

- `automatic-heat`: Blender's native heat-weight operation, followed by bounded influence normalization and real skin validation.
- `declared-groups`: exact `groups` entries with node, deform-bone name and `[vertexIndex, weight]` assignments. Every deforming vertex must receive a valid normalized result.

Rigid/articulated profiles use `rig.mode: preserve` and a declared motion root. Their bone/influence budgets can be zero. Parts specify real nodes, parents and optional world-space pivots. Anchors create actual `anchor.<id>` empty nodes; exported package anchors reference those empties, retaining the parent and local position. Runtime adapters must not apply the position twice.

## Retargeting and targeted revisions

Mapping JSON uses schemaVersion1, provider `owned` or `licensed-library`, explicit authorized rights/license, positive rootTranslationScale, `bones` pairs and complete `clips` mapping. A bone pair has source/target names, optional normalized xyzw `rotationOffset` and optional non-root translationScale. A clip mapping has target id and exact sourceClip name. Target deform bones and root must be covered. This is explicit FK transfer, with no automatic foot IK, semantic skeleton fitting or implicit vendor preset.

The source clip is resampled to the declared target range. Foot/hand contacts, proportions, equipment and source likeness still require review. Supplied input rights do not follow from model or code licenses.

An author job's optional `revisionClip` loads the previous actual motion working copy and replaces only that action. Unaffected imported/retargeted actions and keyframes remain intact. The runtime supplies a merged recipe and preserves ancestry/approvals. `motionSha256` hashes canonical sampled actual local node/bone poses plus timing/root/event semantics, rather than merely hashing clip names or declared recipe text.

## Checks and evidence limits

Loop seams compare endpoint transforms, including quaternion orientation. In-place clips may not move the authoritative root. Clip samples measure declared joint limits. Optional contacts have target, start/end seconds, maxTravel and optional groundZ/maxPenetration/referenceVelocity; reference velocity permits explicit in-place contact compensation. A contact marker alone is not a foot-lock verdict.

The exported rig declares the actual rootBone/rootNode selector. Extracted displacement is reported in runtime coordinates; an engine adapter must reject unsupported competing animated ancestors or root rotations instead of applying movement twice. Extraction does not authorize a visual controller to decide collision or travel outcomes.

Review contains every sampled start/end and intermediate time across the entire declared duration and applicable transition blends. One shared camera fit covers the motion set. Transition previews interpolate declared local poses; actual engine transition/interruption/collision acceptance remains separate. Workbench previews assess geometry/deformation and do not certify final PBR rendering. Human, independent and runtime acceptance remain pending.

Compact ordinal frame folders keep clip and transition namespaces disjoint, including a valid clip named `transition-0`, and reduce Windows path length. Report packet keys retain explicit clip/transition identity and camera labels. Rendering refuses an existing image rather than overwriting evidence; every retained image path/hash is unique.

The native fixture helper under `tests/fixtures/model-animation/create_assets.py` creates original controlled humanoid, articulated-car and rigid-ship geometry plus fitted recipes. `tests/test-model-animation-blender.py` executes actual Blender production/retarget/revision/reimport/render paths and adverse cases. These engineering fixtures are not production art or authenticated human review.

Baking preserves quaternion hemisphere continuity independently for each object and pose bone within each clip. Matrix decomposition may return antipodal quaternion representations of the same keyed pose; matching each new sample to the preceding quaternion prevents LINEAR component curves from taking an unintended subframe rotation. This changes no sampled transforms, root policy, recipe, frame count or review tolerance.
