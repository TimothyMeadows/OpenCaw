# MODEL_TO_ANIMATION Production Workflow

## Intent

Turn a reviewed model into a versioned, reviewed motion package and selected-engine handoff. This workflow follows PROOF_TO_MODEL, BLENDER, a licensed project-local library copy or an explicitly compatible CODE export. It does not change STYLE.md's primary art pipeline or select an engine.

The native baseline authors declared rigs/hierarchies and motion channels, retargets explicitly mapped owned or cleared source clips, bakes/exports actual animation, and produces full-motion review evidence. AI rigging, hosted motion generation and paid clip libraries are not required. Adobe products, services, adapters, vendor skeleton presets and declared provider origins are excluded.

The bounded native runner currently supports Windows job objects and Linux with `/usr/bin/setsid`. Other platforms, including macOS, stop before launching native processes until process-lifetime containment is implemented. Keep paths within the limits of the installed native tools; OpenCaw does not modify operating-system path policies.

## Inputs

- Resolve the project, ENGINE.md and compatible skills. Preserve STYLE.md, architecture, source model identity and applicable task authorization.
- Supply a repository-local reviewed GLB, explicit rights, profile, recipe, budgets and the existing matching Blender 4.5 LTS installation. Preserve an editable source as provenance when available. Export other authoring formats to the documented native interchange instead of selecting an undocumented importer.
- Inspect configured asset libraries first; work only on verified project-local copies. A model/clip license and permission to modify/redistribute are separate from a tool license.
- Keep original-image classification facts separate from model-inspection findings. Generated/model renders do not retrospectively establish anatomy or material facts about the original images.
- For retargeting, select an actual source motion GLB plus explicit target/source clip and bone mapping, rest-axis correction and root translation policy. Read current command help for exact fields. No implicit provider, skeleton convention or backend fallback.

## Production Rules

1. Use `commands/model-to-animation.sh` and the native .NET 10 runner. Consult help for `init`, `doctor`, `inspect`, `prepare`, `rig`, `author`, `retarget`, `bake`, `export`, `review`, `record`, `validate`, `status` and `promote`. The workflow installs or downloads nothing.
2. Keep manifests, approvals and reports below `.opencaw/.cache/tasks/<task>/`; immutable originals, working copies, revisions and failed attempts below `.art-staging/model-to-animation/<asset>/<version>/`. Runtime promotion is separate and uses a new declared `assets/models/...` destination.
3. Review animation readiness before authoring. Fused limbs/equipment, missing hidden geometry, incompatible pose, joint topology, independent mechanical parts and pivots can block production. Structural inventory does not certify deformation or anatomical quality.
4. Select `skinned`, `articulated` or `rigid` explicitly. A humanoid uses a real skeleton and weights; a mechanical assembly uses actual parts/pivots; a rigid hull does not need manufactured bones, attack clips or combat colliders. Existing rigged-actor/v1 remains valid only for its actual character/monster consumers.
5. Prepare declared transforms, hierarchy and anchors, then create or preserve the selected rig/hierarchy. Fitting landmarks and part ownership are explicit recipe inputs. Heat-weighting or mapping failure blocks the affected stage rather than silently substituting another algorithm.
6. Obtain current rig/hierarchy approval before authoring or retargeting. Preserve exact source/target identities, mappings, clip roles, duration/FPS, loops, contacts, root motion, marker semantics and per-clip motion hashes. `author` and `retarget` are explicit alternatives; neither silently invokes the other.
7. Author real channels or retarget actual source motion, bake every required clip, export an editable source and GLB, and independently re-import the export. A named empty action, a single midpoint render or an uninspected donor does not satisfy motion production.
8. Use targeted `author --revision JSON` for supported clip revisions. Preserve unaffected clips and immutable earlier attempts; the revised clip's motion hash and downstream bake/export/review evidence change. Read the native help and revision contract before supplying a revision; do not treat a revision as authority to replace the complete motion set or silently change the rig.
9. Review complete sampled clips and relevant transitions, including contacts, loop seams, extremes, equipment, root displacement and mechanical ownership. The report records sample times, renderer, camera and limitations. It does not manufacture human approval or certify game collisions, player feel or target performance.
10. Produce `opencaw-motion-package/v1` with source/model hashes, applicable rig/hierarchy, actual exported clip bindings, `motionSha256` identities, anchors, continuous parameters, explicit states/transitions, presentation effect bindings, provenance and budgets. Verification remains pending until the required actual evidence and separate receipts exist.
11. Integrate through the selected engine's compatible animation, movement, material, VFX, audio and camera owners. Gameplay owns movement, collision, death and travel/arrival rules; clips and particles provide presentation or controller-validated motion intent. No animation/particle completion callback independently grants gameplay outcomes.
12. Require current motion selection, independent review and separate human runtime acceptance before promotion. Bind actual runtime-test, runtime-capture and performance-profile artifacts to the effective engine, model and package hashes. Failed, missing or stale evidence remains failed/pending; reports cannot authenticate a human identity.

## Audited Blender batch-authoring contract

This workflow has an explicit authoring exception for its fixed, audited, hash-bound Blender scripts. Copy the approved bundle into an immutable attempt, verify source/copied hashes and Blender 4.5, use `--factory-startup --background --disable-autoexec`, and execute only the declared operation on repository-confined working copies. Bound process time, log bytes, files, samples, render frames and pixels; retain cancellation/failure evidence.

Recipe data cannot supply executable expressions, arbitrary Python, providers or process commands. Do not execute embedded scripts, handlers, drivers or add-ons from imported assets. Optional tools/add-ons need separate selection and audit. This exception does not change standalone BLENDER's connected-authoring policy or broaden PROOF_TO_MODEL's finishing/review exception. Native process/workspace guards are not an OS sandbox.

## Engine Handoff

The canonical resolver supplies effective selection and fresh contract/definition/registry hashes. Shared motion production never rewrites ENGINE.md or bypasses an isolated-prototype receipt's scope. CODE remains THREEJS-specific and source-authored; a motion workflow cannot replace its primary source with downloaded/generated meshes. PHASERJS requires an explicit sprite/pre-rendered handoff for 3D source material.

Three.js has an executable presentation adapter under `engines/threejs-motion.mjs`. Host projects supply their already selected, version-locked Three.js APIs and actual GLB animations. The adapter imports no package, CDN or external provider. It requires a visual child beneath a separate authoritative movement root, explicit clocks/parameters/state requests, unique anchors and bounded effect resources. Read `engines/README.md` before integration.

Unity, Unreal, Godot and Babylon.js handoffs use their compatible existing feature skills and actual installed engine versions. Their binary/native assets, controllers, particles, importer options and runtime evidence remain selected-engine work. The shared package is a handoff contract, not a working cross-engine particle system or runtime graph. Absent native prerequisites remain blocked/not-run.

## Output Contract

- Immutable reviewed input model, editable source ancestry and applicable rig/hierarchy identity.
- Real authored or retargeted clips with per-clip hashes, source rights/mappings, loop/contact/root-motion metadata, baked output and actual export bindings.
- Editable Blender working/export sources, independently re-imported GLB, motion package and full-range review frames/HTML.
- Selected-engine implementation and actual runtime/performance evidence, distinguished from simulated-process checks and structural validation.
- Separate current rig, motion, independent and human runtime acceptance assertions, failure/revision history and explicit promotion lineage.

## Acceptance Checks

Verify skinned deformation, meaningful channels, required motion coverage, finite samples, normalized weights, joint/contact limits, loop seams and exported identities. Inspect run, jump takeoff/air/land, swimming and terminal death according to the requested action set; custom anatomy needs a selected recipe and actual review.

Verify mechanical pivots, wheel/angular response, suspension/control ownership, rigid hull motion and anchors without fake skeleton/combat requirements. Use calibrated speed/acceleration parameters for ordinary motion and explicit enter/sustain/exit/cancel requests for warp. Surface dust/wakes require appropriate context.

Exercise pause, frame-rate variation, interruption, respawn/pooling, stale callbacks, independent actor copies, root-motion double application, source/rig/clip/tool/engine changes, missing prerequisites, corrupt output, path escapes, locks, timeouts, interrupted recovery and bounded resources. Effects have local/world-space, quality and reduced-motion policies; GPU particles are not promised bitwise deterministic across targets.

Require actual Blender fixtures for native authoring/export acceptance and actual selected-engine imports/playback/captures for runtime claims. Protocol simulations, a passing manifest or Blender playback cannot certify another engine or production visual quality. No provider/model installation, paid use or promotion follows from choosing this workflow.

## Role Fit

- `arts/technical-3d-artist`: model readiness, rig/hierarchy, retargeting, contacts and runtime-art ownership.
- `arts/blender-production-artist`: declared Blender working copies, authoring and exports.
- `computer-science/generative-media-pipeline-engineer`: native orchestration, ancestry, guards and recovery.
- `computer-science/gameplay-engineer`: controller ownership and selected-engine motion/effect integration.
- `arts/art-director`, `arts/game-vfx-artist` and `computer-science/qa-engineer`: independent visual/effects/technical review and actual acceptance evidence.

Use `build-model-animations` to coordinate these existing owners. No replacement role, hosted service or additional general particle engine is introduced.
