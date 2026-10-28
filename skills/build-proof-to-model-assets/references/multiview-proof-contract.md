# Prepare and review one coherent six-view set

Classify the original source set first. Select the original views that genuinely supply usable canonical coverage, then generate only missing or rejected views. A single valid canonical source normally needs five additional images. Do not relabel a cropped or three-quarter painting as front; keep it as the immutable identity anchor and explicitly budget the six canonical generations it may require. Multiple originals contribute one shared coverage plan, not five generations per source.

## Freeze shared identity and cameras

Use the exact ordered slots `front`, `right`, `back`, `left`, `top`, `bottom`. Left/right mean the subject's sides. In the Z-up rig, front faces -Y, subject-right is -X and subject-left is +X. The right camera is therefore at -X and the left camera at +X; these are not screen-right/screen-left labels. Keep this orientation in prompts and asymmetric attachment checks. Preserve entity count, silhouette, proportions, pose, attachments, asymmetric details, material identity, palette and style across all six. Mirroring does not supply a second side of an asymmetric subject. Hidden surfaces are proposed completions, not newly observed facts.

The native contract uses Blender/NeRF world Z up, camera local -Z forward and +Y image up; matrices are row-major camera-to-world. Use the pipeline's fixed cardinal/polar rig, distance, horizontal FOV and positive mesh scale. Top/bottom have explicit roll; generic world-up look-at logic is singular at the poles. Keep one framing/scale convention across the set. Arbitrary illustrations do not supply measured calibration; label prescribed generated cameras `nominal-prescribed`.

Pixal3D's `meshScale` is inverse scale: its conditioning cube has half-extent `0.5 / meshScale` in camera-world units. A value of `1/6` therefore creates a six-unit cube. All prescribed cameras must sit outside that cube with a positive depth margin; positivity of the individual fields is insufficient. Verify framing against the actual padded silhouettes and camera projection before a live run. Exterior cameras alone do not establish correct calibration or visual quality. Correcting camera metadata retains image ancestry but invalidates whole-set approval and downstream results.

No per-view tight crop, stretch or silhouette enlargement is permitted during matte/input preparation. Preserve true alpha where suitable or invoke the pinned explicit BiRefNet path. Pad on a common square canvas, retain transforms and adjust horizontal FOV for centered padding. Inference receives six separate prepared images and camera JSON, never the contact sheet.

## Generate and revise

Resolve CLOUD/LOCAL capability, read MEDIA.md and establish rights, upload permissions and bounded set/per-view/revision budgets before generation. A proof-set selection never authorizes unlimited retries. Existing-proof reuse does not itself require generation, a new media contract or spending.

Retain each actual image, hash, original-source ancestry, classification fingerprint, camera, dimensions, generation receipt, exact prompt/references, disclosed provider/model/parameters or unavailable markers, revision lineage and rejection reasons. Use `prepare-proofs` to import and validate actual artifacts; the command neither generates images nor certifies their semantic consistency.

Target revisions to one angle and describe the exact defect. Preserve the other selected image bytes and previous candidates. Revision must retain the shared identity and fixed pose; if a structural reinterpretation is necessary, update classification from the originals and invalidate affected views. Any selected image, camera or classification change invalidates whole-set approval and dependent reconstruction evidence.

## Review before reconstruction

Show a labeled contact sheet and full-resolution originals/proofs. Inspect source likeness, entity/limb/part counts, occlusion completion, attachment continuity, fixed pose/proportions, side ownership, top/bottom orientation, material identity and source-specific asymmetry. Compare the six together; plausible isolated images may still contradict one another.

One human `proof-set` receipt may approve all six exact current hashes and their classification/camera/style interpretation. Use the current `status` fingerprint named `proofSet` when recording that kind. The `proof` approval kind is reserved for explicit single-view diagnostics and cannot approve six views. Missing approvals remain pending. Preserve unresolved issues and rejection history. Preprocessing approval is separate and binds actual normalized inputs.

## Reconstruction and final review

The pinned MV engine must consume exactly six frames and verified MV weights. Its native count can clamp to available frames, so `--num-views 6` alone is insufficient evidence. Preserve ordered frame/camera hashes and exact process arguments. No single-view fallback or four-view subset satisfies this workflow.

Blender review compares immutable originals, approved proofs, prepared conditioning images and six independent GLB renders. It applies one declared geometry frame transform and shared fit; it does not rotate or refit the model separately per camera. Nominal alignment is not measured pixel correspondence or automatic proof of likeness. Keep independent review and separate human runtime acceptance pending until explicitly recorded.

Upstream documents MV validation with four views; the six-view extension requires separate bounded native acceptance. Structural tests, simulated processes and real Blender fixture renders must not be presented as successful live six-view reconstruction or production quality.
