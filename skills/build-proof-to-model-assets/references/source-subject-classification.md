# Classify original sources before proof creation

Use the registered original image set as the sole image evidence of the source subject. Preserve full-resolution originals and hashes before analysis. The assistant performs vision and research; `classify` validates and imports its report rather than pretending to run an unavailable AI backend. Consult the pipeline classification schema and command help for the exact fields.

## What to establish

Identify the intended asset boundary and distinct entities: a horse, rider, saddle, armor, cloth and weapon are separate subjects or assemblies with explicit attachment and occlusion relations. Record visible proportions, articulation, silhouette, asymmetry, material and semantic parts. Reference original source IDs and precise visible regions in descriptions; never substitute a generated candidate as evidence.

Use the claim dispositions `observed`, `research-inferred`, `user-specified` and `unknown`, with high/medium/low/unknown confidence rather than invented numerical certainty. Parts record visible, partial, hidden or unknown visibility. Explain the basis, alternatives and impact of consequential inference. Maintain preservation constraints, prohibited substitutions, unknowns and conflicting originals.

Link each part to supporting claims with `claimIds` and matching disposition. A fully hidden part cannot be observed. Assess every original exactly once in `sourceViews` with `sourceId`, `view`, `usable` and `reason`. Mark only genuine canonical coverage usable; retain `oblique` or `unknown` instead of forcing a front slot. This is the source-view authority, separate from descriptive claims.

Distinguish shape from substance: a skull-shaped metallic helmet is metal equipment, not necessarily bone or an exposed skull. Preserve material highlights, armor seams and attachment evidence. Distinguish anatomy from clothing and armor rather than turning an occluding plate into a joint or limb.

For a horse with hidden legs, establish the living subject and plausible anatomical relationships, but label hidden limb placement and exact pose as inferred or unknown. Preserve intentional fantasy anatomy, stylization, amputations and asymmetry. For nonliving subjects, describe assemblies, supports, interfaces, openings, underside construction and moving/fixed relationships rather than forcing anatomical terms onto vehicles, buildings or weapons.

## Research and uncertainty

Research questions must arise from the originals: for example, equine joint relationships or how a visible saddle is supported. Use reliable anatomical, manufacturer, engineering or museum references as appropriate, retaining URL, title, retrieval date, source-derived question and supported claim IDs. Research establishes general plausibility; it does not reveal a source-specific hidden design. Record `researchStatus: not-required` with a reason when the originals and brief resolve the relevant structure.

Present consequential hidden geometry, competing material interpretations and conflicting source poses before spending on dependent images. An unknown may remain documented when it has no effect on the current asset boundary. Resolve critical conflicts or record the user's selected interpretation before preparing affected proofs. Do not demand a separate approval of every straightforward classification claim; complete-set proof approval includes the selected interpretation.

## Evidence boundary

Only registered original IDs/hashes belong in the classification's `sources`, claim/part references and research `sourceIds`. Derived source crops may support inspection if their original ancestry is retained; they do not create independent source evidence. Generated proofs, their revisions and reconstruction renders remain derivatives even after copying or renaming.

A proof defect can trigger reassessment, but reassessment returns to the originals and independent references. Do not convert a generated error into a source claim. Adding a genuine original requires a new registered source set and invalidates dependent classification and proofs.

Human approval selects an inferred completion; it does not turn that completion into an observation or certify source rights. Validate source membership and immutable hashes separately from human judgment of anatomy, structure and likeness.
