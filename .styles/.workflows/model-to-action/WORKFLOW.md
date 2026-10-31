# MODEL_TO_ACTION Production Workflow

## Intent

Compose reviewed single animations into a named, ordered action with timing, trims, rates, repetitions, blends and model-attached presentation effects. Examples include a dance pattern, a prescribed kick/punch combination and charging then casting a visual fireball toward a fixed target. MODEL_TO_ANIMATION owns source rigs and individual clips; this downstream pipeline creates their compound action and preserves the primary STYLE.md pipeline and ENGINE.md selection.

An action package is presentation data. Gameplay owns movement, collisions, target eligibility, damage, costs, cooldowns and authoritative projectile outcomes. A presentation marker, clip completion or visual target arrival cannot independently decide those outcomes.

## Inputs

Execution resources, schemas, recipes and technical contracts belong to the pinned `runtime/bubo/resources/model-to-action/` dependency. OpenCaw retains this policy contract and `commands/model-to-action.sh`; production invokes the verified prebuilt Bubo CLI. Initialize/build explicitly before native work; never use a sibling checkout or build/install during generation.

- Resolve project paths, ENGINE.md, STYLE.md and compatible coordinating/engine skills. Inspect configured external libraries first and use verified repository-local copies.
- Supply a reviewed `opencaw-motion-package/v1`, its actual compatible self-contained GLB and explicit source clip/rig identities. Preserve original package, model, source rights, mappings and per-clip motion hashes.
- Record human source-motion selection bound to the exact package/model/rig and every used clip, with `rights: {authorized: true, license: TEXT}` covering the source model and selected motions. This is recorded permission/provenance, not license acceptance on the user's behalf. The assertion may review staged clips; it does not fabricate prior runtime approval.
- Supply an explicit recipe, bake FPS, bounded steps/effects, real anchor identities, target binding policies and technical review settings. Missing clips, anchors, markers or settings block the affected operation.

## Production rules

1. Use `commands/model-to-action.sh` with the existing .NET 10 runtime and Blender 4.5 LTS. Consult help for `init`, `doctor`, `inspect`, `compose`, `export`, `review`, `record`, `validate`, `status` and `promote`. No installation or provider selection is implied.
2. State, receipts and evidence live below `.opencaw/.cache/tasks/<task>/model-to-action/<asset>/<version>/`; immutable source copies, attempts and review exports below `.art-staging/model-to-action/<asset>/<version>/`. Failed/replaced attempts remain evidence.
3. Inspect actual source clip channels, compatible rig/hierarchy, skin/part ownership, scale and anchors before composition. Choose skinned, articulated or rigid according to the real source. Preserve old rigged-actor/v1 and existing motion production independently.
4. Compile ordered, bounded source clip spans. Source trims use source seconds; rate changes span length; repetitions have explicit occurrence IDs. Incoming blends overlap adjacent spans without gaps or triple overlap. Bake timing must fit the explicit FPS; no silent rounding or source loop.
5. Resolve cue offsets and source markers against the exact step occurrence and trim/rate. Reject missing/ambiguous/out-of-trim markers, invalid target policies, empty spans and exceeded budgets. Preserve source clip hashes alongside the new composite motion hash.
6. Initial shared composition requires in-place source clips. Inspect original GLB root/ancestor samplers before import, including subframe motion. Moving or compensating root ancestors require a reviewed in-place bake; used clips require `LINEAR`/`STEP` interpolation because this Blender import path cannot certify cubic tangents. Reject extracted-root clips with guidance to author an in-place counterpart or explicitly implement engine-specific controller extraction. This does not remove standalone MODEL_TO_ANIMATION extraction support.
7. Compose through only this workflow's fixed, audited, hash-bound Blender batch bundle on repository-local copies. Use factory startup, disabled autoexec, Python failure exit status, bounded files/logs/time/samples and owned-process cleanup. Do not run embedded scripts, arbitrary expressions, add-ons or user-selected executables from recipe data.
8. Preserve an editable compound timeline and export actual baked composite clips to GLB. Independently re-import the exported model and verify duration, pose/channel bindings, hierarchy, skin/material identity, budgets and actual action names. An action label or empty strip is not motion output.
   Every baked frame is compared using bounded disk-backed expected geometry rather than retaining the whole sequence in memory. Optional `budgets.maxVerificationBytes` defaults to 8 GiB (maximum 64 GiB); a fixed 256 MiB single-frame payload bound also applies. Preflight the measured payload before export. Retain the three hash-bound technical verification artifacts in their attempt, outside the runtime package; missing, corrupt, oversized or incomplete evidence fails the stage. The 1 mm comparison tolerance and full frame coverage remain unchanged.
9. Review full sampled sequences and important boundaries, including blend contacts, release timing and interruption. Blender review may use clearly labeled cue proxies; actual selected-engine effects and target behavior need separate runtime evidence.
10. Export `opencaw-action-package/v1` with actual composite clips, expanded steps, resolved markers/cues, original motion ancestry, anchors, fixed-target policies, tool/recipe/engine identities and budgets. GLB supplies animations; engine presentation implements the external timeline/cue contract.
11. Require current human action selection, a different independent reviewer and separate human runtime acceptance before explicit promotion into a new `assets/models/...` destination. Bind actual runtime-test, runtime-capture and performance-profile artifacts to the current package/model/engine. Cooperative receipts are assertions, not authenticated identity or automatic quality acceptance.

## Selected-engine presentation

Read [engines/README.md](engines/README.md) for the executable Three.js adapter. The host supplies its locked Three.js APIs and actual GLB. New particle production uses the selected host-locked three.quarks owner; the pinned sample adapter retains historical point primitives and requires explicit reviewed integration rather than relabeling it Quarks. No CDN, provider or automatic download is selected. Only one full-body presentation owner may write a rig at a time. Suspend/arbitrate locomotion and existing motion mixers before action ownership; this workflow supplies no implicit upper-body masking, IK, aiming/body turn or combat controller.

Effects use actual exported anchors. Charge cues follow the actor; visual projectiles detach at the sampled release pose and travel to a fixed world point copied at action start. Targets do not home after caller mutation. Pause freezes the presentation clock. Cancel/supersede/reset/dispose invalidate stale callbacks and release every owned attachment, particle and projectile, including callback-triggered interruption. Shared model assets and controller movement stay host-owned.

Target distance limits bound visual resources at the actual release pose. Finite target points are validated and copied before replacing the current action; an outgoing action's different pose cannot decide their range. Charging may start before a moved anchor fails the range check at launch. That failure cancels the presentation and clears its effects without allocating a projectile. Gameplay separately validates ability targets and outcomes.

Other engine skills own their actual native timelines, state graphs, importers and effects. Missing Editors/SDKs and unavailable device checks remain blocked/not-run. Phaser requires an explicit 2D sprite/pre-rendered handoff. No native or artistic claim follows from simulation, a Blender proxy or a passing schema.

## Output and verification

- Immutable motion/model/rig/clip ancestry and human source selection.
- Versioned recipe and resolved ordered timeline, editable compound source, actual exported clips and package hashes.
- Complete technical sequence/boundary review, actual selected-engine playback/effect captures and measured limitations.
- Separate action/independent/human-runtime acceptance and explicit immutable promotion history.

Test trims/rates/repetitions/blends/markers and source drift; missing/corrupt outputs, interrupted jobs, path escapes, locks and budgets. Exercise dance, combination and charge/cast with real exported clips; actual deformation, cue timing, fixed-target snapshots, variable frame deltas, pause, cancellation, replacement, reentrant callbacks, independent copies and repeated disposal. Report actual Blender/browser results separately from protocol simulations. Physical GPU/target hardware, animation aesthetics, combat correctness and human runtime acceptance require their own evidence.

Adobe products, services, presets and authoring integrations remain excluded. Optional models, paid libraries, uploads, downloads, service activation and license acceptance require separate selection. The selected engine particle owner is required for new effects; `build-model-actions` coordinates existing art, gameplay, VFX and QA owners.
