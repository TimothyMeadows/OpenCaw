# Subject articulation and deformation

## Establish what can move

Inspect the actual mesh and approved subject references before choosing controls. List each moving assembly, its attachment, motion range, deformation requirement and output consumer. Distinguish observed construction from inferred concealed joints. Do not add limbs or joints solely because a familiar rig template contains them.

Choose the existing motion profile deliberately:

| Profile | Required preparation | Stop condition |
| --- | --- | --- |
| Skinned | Stable deforming topology, bind pose, skeleton identity, weights and target influence limits | Missing deformation zones, unsupported topology changes or incompatible skeleton |
| Articulated | Independently movable rigid parts, complete concealed surfaces, parentage, pivots and axes | Fused components, exposed holes or rotation about a guessed attachment |
| Rigid | Reviewed intact body and explicitly needed presentation anchors | A requested movement would require unmodeled independent parts |

Repair an unready model through its selected modeling workflow and review that repair before rigging. A valid hierarchy or imported clip does not establish readiness. Record the source identity, repair ancestry, scale, rest state and chosen profile with the existing handoff evidence.

## Build controls without changing the subject

Identify rest axes and hinge directions in the subject's local space. Check bone roll, parent scale inheritance and constraints before weighting; mirrored names alone do not establish mirrored behavior. Preserve intentional root, grounding and attachment transforms. Changing rest pose or applying transforms after binding needs an explicit migration and renewed motion checks.

Separate animator controls from exported deform/attachment nodes. Use automatic weights only as a starting result to inspect; protect existing authored groups before rebinding. Assign rigid plates and equipment to their actual owners so nearby soft tissue does not pull them into a joint. Select volume-preserving deformation only when required and verify its exported approximation; a Blender modifier's behavior is not automatically portable.

## Choose representative subject tests

Set motion ranges from the brief and source-supported anatomy or construction. Record expected contact and clearance, then examine the complete movement and intermediate poses at target and close review distances.

| Subject | Diagnostic motion | Inspect before authoring a full clip |
| --- | --- | --- |
| Humanoid | Reach, crossed-arm reach, crouch, step and torso twist within the required range | Shoulder/armpit collapse, hip creases, elbow/knee compression, foot contact and clothing/equipment intersections |
| Creature | Required stance, gait contacts, turning, jaw movement and declared tail/wing extremes | Actual joint count and posture, chest/limb separation, foot placement, membrane or feather attachment and collision |
| Mechanism or vehicle | Each hinge, slider, steering/suspension channel or rotating assembly independently, then in combination | Correct centers/axes, parent motion, panel clearance, exposed surfaces and absence of unintended deformation |

Do not prescribe one bone count, pole location or twist-weight ratio for every subject. Introduce corrective shapes, twist distribution or extra controls only for demonstrated failures and within the export budget. Repeat the diagnostic after each change, including mirrored and asymmetric poses where relevant.

## Facial motion and rotating mechanisms

For a face, identify whether motion belongs to organic skin, a rigid jaw, eyelid geometry or mechanical panels. Choose bones, shape keys or a supported combination from that construction. Stabilize topology before authoring shape keys. Review isolated expressions and combinations: lid closure around the eye, jaw opening, lip contact, asymmetry and return to neutral. Do not simulate a blink by crushing a rigid eyeball merely to hide an eyelid defect.

When topology changes after expressions were authored, stop treating the old keys and weights as compatible. Preserve their source, inspect actual vertex correspondence, and select a reviewed basis/key/weight transfer or rebuild through the modeling owner. Include every required expression, corrective and dependent binding in the migration. Renew neutral, isolated/combined expression and deformation review before accepting new rig/clip/export evidence; matching names or vertex counts cannot establish compatibility.

Scale animation is a deliberate compatibility choice rather than universally forbidden or required. Check scale inheritance, shear, normals, attachment behavior and actual target support. Bake editor-only drivers or constraints into supported channels when the handoff requires it; preserve the editable control source and compare the baked result independently.

For gears, record shaft ownership, tooth counts, ratio, direction and allowed phase from the actual arrangement. Animate separate geometry, not a texture that suggests articulation. Sample rotating channels sufficiently to preserve direction and full revolutions through export, then test re-imported complete turns and their parent transforms. For a multi-part motion, one declared owner drives each channel; an idle and action must not simultaneously write the same mechanism.

## Evidence and handoff

Keep a named diagnostic motion range, before/after defect views, measured contact/clearance where required, and current model/rig/clip identities. Review transitions, loop seams, interruption and reset through the owning motion workflow. A still frame cannot certify deformation or motion. Unsupported target features and unavailable native tests remain blocked/not-run; do not replace them with a manifest-only pass.

These are subject-preparation procedures, not an executable rig generator. They do not authorize arbitrary scripts or change the fixed audited MODEL_TO_ANIMATION or MODEL_TO_ACTION bundles. Authoritative movement, targeting and collision remain outside animation playback.

## Blender 4.5 references

- [Armature deformation](https://docs.blender.org/manual/en/4.5/modeling/modifiers/deform/armature.html): weights, modifier ownership and volume preservation.
- [Bone relations](https://docs.blender.org/manual/en/4.5/animation/armatures/bones/properties/relations.html): scale inheritance and parent behavior.
- [Shape keys](https://docs.blender.org/manual/en/4.5/animation/shape_keys/introduction.html): topology and facial deformation choices.
