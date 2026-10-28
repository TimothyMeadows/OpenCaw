# Audited Blender action batches

`action.py` is the fixed Blender 4.5 LTS entrypoint for MODEL_TO_ACTION. The native runtime copies exactly the Python files in `scripts.json`, verifies their SHA-256 hashes, and starts the installed Blender with factory startup, background mode, auto-execution disabled and a failing Python exit code. This native process is not an operating-system sandbox. Recipes are bounded JSON data; they cannot supply scripts, expressions, drivers, addons or another authoring backend.

The bundle is self-contained. `core.py` adapts OpenCaw's internal `model-to-animation/blender/core.py` file/path, GLB, scene-loading, action-slot and mesh-inspection helpers. The action compiler, sampled pose composition, editable source NLA, composite export verification and cue-proxy review are native implementations for this workflow. No upstream/vendor code, animation library, model service or Adobe integration is included. The original MODEL_TO_ANIMATION scripts and their pins remain separate.

| Operation | Input and actual output |
| --- | --- |
| inspect | Import the immutable self-contained source GLB; verify used clip bindings, durations, hierarchy, profile, skin weights, anchors and actual in-place root samples |
| compose | Sample source transforms through explicit trims, rates, repeats and incoming overlaps; bake actual compound actions and retain muted editable source NLA strips in a new `.blend` |
| export | Save editable `.blend`, export only the requested action IDs as GLB animations, hash actual animation bytes and independently re-import every baked frame |
| review | Import the runtime GLB, render complete action ranges and every step/cue/marker boundary for every declared camera, and retain time-indexed PNGs, hashes and HTML playback |

## Input and output contract

Invoke through `commands/model-to-action.sh`. Its fixed job supplies `schemaVersion: 1`, absolute project `root`, `operation`, repository-relative `input`, `outputDir`, `result`, `asset`, `version`, `profile`, original parsed `motionPackage`, compiled `plan` and recipe `review`. `input` is the source GLB for inspect/compose, the prior fixed composed `.blend` for export, or exported GLB for review. Original package paths are ancestry; the script loads only the declared input. All outputs remain in the new asset-version attempt below `.art-staging/model-to-action/`.

Successful `opencaw-action-stage/v1` results contain `operation`, immutable `inputSha256`, actual relative `artifacts`, compiled `actions`, measured `metrics` and nonblocking `findings`. Failed operations emit no success result. Stage metrics belong outside strict compiled action rows. Exported packages preserve rig, anchors, source clip identities and all compiled timing/cues/markers. `motionSha256` on a step remains its source clip hash; the action hash describes sampled compound transforms during composition and actual exported animation/accessor bytes after export. These are distinct measurements.

The CLI owns current source/recipe/tool/engine fingerprints, source rights/review, stage order, assertions and promotion gates. Blender does not manufacture human acceptance. Metadata never substitutes for actual model/clip inspection.

## Composition and export rules

The source has one declared skinned, articulated or rigid profile. Skinned assets retain their reviewed real rig and normalized weights. Mechanical profiles retain declared nodes and do not acquire bones or combat requirements. Transform/pose channels are implemented; animated shape keys and other channel classes fail with explicit guidance. Clips labeled `extract` fail; clips falsely labeled `in-place` also fail when their evaluated root moves. This workflow does not change standalone motion extraction support.

Before Blender import, actual original GLB samplers on the declared root and its complete ancestor chain must contain constant transform values and zero cubic tangents. A short excursion between output frames cannot disappear through sampling or importer behavior. Counter-moving ancestors require a reviewed in-place bake or an explicit movement adapter. Used source clips support `LINEAR` and `STEP` interpolation; `CUBICSPLINE` fails with guidance to supply a reviewed linear/stepped bake because this Blender import path cannot certify its tangents. Actual evaluation additionally covers all imported source key times, the bake grid and interior thirds, charged against the declared inspection-frame budget.

Steps are expanded before Blender invocation. Trims refer to source seconds, rates alter duration and sampling, repetitions are finite, and incoming blends overlap exactly two adjacent spans. Output times must lie on the bake FPS grid. Half-open spans give exact shared boundaries one deterministic owner; the final endpoint is sampled explicitly. Quaternion/transform interpolation uses Blender's matrix interpolation, and every output pose is baked at the declared FPS. Muted source NLA strips preserve original actions, trims, rates and blend ranges for inspection; the fixed sampled composition owns the exported result.

`maxStepsPerAction` bounds unique source step definitions; `maxEffects` and the sum of particle capacities are bounded per action because only one action is active. `maxExpandedSteps` and baked/review frame budgets apply across the complete action package. Independent actions do not share a particle-capacity sum. Blender's hard budget bounds match the native compiler.

GLB clip names equal action IDs, with source actions namespaced only inside editable source. Export verifies actual animation channels, durations, skins, node/anchor identities, self-contained dependencies and runtime byte budget. Independent re-import compares the world-space geometry of every baked frame in both directions with a 0.001 metre maximum error. Explicit node and mesh-datablock identities preserve mesh correspondence across Blender's skinned-node wrapper insertion; importer-generated object names alone are insufficient evidence.

## Technical review and limits

Independent re-import verification stores expected float64 world-space vertices and anchor matrices in an immutable, attempt-local `verification/` spool, then compares each actual frame incrementally. It never retains complete animation geometry in memory or drops frames. `budgets.maxVerificationBytes` is optional with an 8GiB default and 64GiB maximum; exact binary, frame-index and completion-index byte demand is checked before spool creation/export. A fixed 256MiB per-frame payload bound prevents an unbounded individual frame. Original topology must remain constant; glTF vertex splitting remains supported through bidirectional nearest-vertex comparisons at the existing 0.001 metre tolerance.

The completion index is written last, binds the current plan, records exact sample order/offsets and hashes the complete files and individual frames. Truncation, corruption, missing/extra frames, escaped paths and incomplete writes fail. Closed partial files remain failed-attempt evidence; no passing package is emitted. The spool is technical evidence and is not included in runtime promotion.

Review samples zero, exact duration, the complete review-FPS grid, all expanded step boundaries, all cue boundaries and every mapped marker for every camera. Required frames cannot be silently dropped to meet a budget. Each output path is unique and refuses existing content. Compact ordinal frame paths avoid semantic-name collisions and reduce Windows path length. Reports retain action IDs, camera, exact time, PNG hash and active cue labels.

Workbench review renders actual imported deformation with **technical cue proxies**. Growing spheres, bounded particle proxies and projectile trajectories illustrate phase, attachment and fixed target placement; they do not certify production particle shaders, audio, collision or gameplay. Targets use runtime metres with +Y up/+Z forward, converted once to Blender `(x,-z,y)`. Real engine integration owns presentation quality, interruption and authoritative-state separation. The HTML is a sampled scrub/playback aid; finite samples do not constitute continuous visual or human acceptance.

`tests/fixtures/model-action/create_assets.py` authors original controlled skinned humanoid motions, an articulated car and a rigid ship using existing internal test helpers on new repository-local copies. It supplies real source GLBs, motion packages, recipes and a test-only plan oracle. `tests/test-model-action-blender.py` runs installed Blender with bounded processes to verify actual composition, deformation, root/anchor ownership, export, review and adverse cases. These are engineering fixtures, not production art or authenticated approvals.

Composition preserves quaternion hemisphere continuity per action, object and pose bone when sampled matrices become LINEAR keys. Each new quaternion is sign-aligned with the previous sample without changing its transform. Full and half-frame witness checks cover multiple turns and component joins; frame counts, root ownership, disk-backed export comparison and the 0.001 metre acceptance tolerance remain unchanged.
