# Hephaera asset command arguments

These host commands use the pinned Bubo API v1. Run them from the project root through `./.hephaera/commands/`. Maintainer checkouts use `./commands/`. Initialize the recorded dependency and explicitly build with `initialize-bubo-runtime.sh` and `build-bubo-runtime.sh` before native work; production never builds or installs software.

All three asset commands accept `--root PROJECT` (otherwise the shell wrapper resolves the installed host). Every operation except `init` requires `--manifest FILE`. `init` requires `--task ID --asset ID --version ID --actor ID` and defaults to `.hephaera/.cache/tasks/<task>/<workflow>/<asset>/<version>/manifest.json`. Proof and motion may select another manifest beneath that active task cache; action init requires its exact canonical path. Inputs must be repository-local and rights, selection, review and tool identities must be current. Hephaera supplies protected execution context internally.

## Proof to model

Use `proof-to-model.sh OPERATION` with common arguments above.

| Operation | Additional arguments |
| --- | --- |
| `init` | Exactly one `--proof ORIGINAL_IMAGE` or `--sources SOURCE_SET_JSON`; required `--rights JSON --recipe JSON --toolchain JSON`; optional `--brief JSON --proof-metadata JSON --selection JSON --library-search JSON`. `--mode multi-view` is the default; explicit `single-view-diagnostic` is separate. |
| `classify` | `--classification JSON` binds actual original-source research and classification. |
| `prepare-proofs` | `--proof-set JSON` registers six actual images/cameras and applicable generation evidence. It does not generate them. |
| `record` | `--kind KIND --reviewer ID --evidence JSON`; optional `--artifact FILE --source FILE` where the receipt contract uses them. |
| `setup` | Omit `--execute` for dry-run. `--execute` or `--execute true` requests separately authorized provisioning; applicable licenses and complete pinned file evidence are still required. |
| `doctor`, `preprocess`, `reconstruct` | Optional `--timeout SECONDS --gpu ID --blender EXECUTABLE`, subject to toolchain bounds and operation applicability. |
| `finish` | Optional `--blender EXECUTABLE --timeout SECONDS --gpu ID --finish-settings JSON --finish-budget JSON`. Rigid-parts and extra-attempt selections require their explicit current evidence. |
| `review` | Optional `--blender EXECUTABLE --timeout SECONDS --gpu ID`. |
| `reuse` | `--reuse-manifest FILE`; register and review the receiving asset before reuse. Input ancestry and affected reviews remain enforced. |
| `validate`, `status` | No additional operation arguments. |
| `promote` | `--destination assets/models/NAME`; requires current independent and separate human runtime acceptance. |

Single-view diagnostic continuations require `--mode single-view-diagnostic` explicitly on applicable operations. They cannot complete six-view production or promote. Diagnostic `init --reuse-manifest FILE` remains subject to donor checks; multi-view init rejects that shortcut. Missing tools, models, rights, source evidence or selected-pipeline capability stop the operation.

Pinned resources are under `.hephaera/runtime/bubo/resources/proof-to-model/`, including `recipes/static-prop.json`, `toolchain.json`, schemas and technical contracts. `PIPELINE.md` remains Hephaera policy; Bubo resources do not grant generation or human approval.

## Model to animation

Use `model-to-animation.sh OPERATION` with common arguments.

| Operation | Additional arguments |
| --- | --- |
| `init` | `--model GLB --rights JSON --recipe JSON`; select the existing Blender with `--blender EXECUTABLE` (the default is `blender`). Optional `--editable-source BLEND --source-metadata JSON`. |
| `author` | Optional `--revision JSON` for an explicit targeted motion revision. |
| `retarget` | `--motion-source GLB --mapping JSON`, with explicit cleared source clips and mapping. |
| `record` | `--kind KIND --reviewer ID --evidence JSON`. |
| `doctor`, `inspect`, `prepare`, `rig`, `bake`, `export`, `review`, `validate`, `status` | No additional operation arguments; use the selected recipe, tool and current manifest. |
| `promote` | `--destination assets/models/NAME`; current rig, complete motion, independent and human runtime acceptance are required. |

Recipes, schemas, audited scripts and engine adapters live under `.hephaera/runtime/bubo/resources/model-to-animation/`. Read the Hephaera `MODEL_TO_ANIMATION` policy contract. No Adobe provider, implicit installation, skeleton substitution or automatic asset acceptance is permitted.

## Model to action

Use `model-to-action.sh OPERATION` with common arguments.

| Operation | Additional arguments |
| --- | --- |
| `init` | `--motion-package JSON --recipe JSON --source-review JSON`; select existing Blender with `--blender EXECUTABLE` (default `blender`). The source review binds actual model, rig and clip identities and rights. |
| `record` | `--kind KIND --reviewer ID --evidence JSON`. |
| `doctor`, `inspect`, `compose`, `export`, `review`, `validate`, `status` | No additional operation arguments. |
| `promote` | `--destination assets/models/NAME`; separate action, independent and human runtime acceptance must be current. |

Action resources live under `.hephaera/runtime/bubo/resources/model-to-action/`. Initial composition requires in-place clips; missing clips/anchors or unsupported root extraction stop execution. Presentation cues never own authoritative targeting, movement or damage.

## Review receipts and continuation

`record` consumes an actual receipt, rather than treating the command as approval. Supply the workflow's current kind/fingerprint, reviewer, decision and reason, plus human/runtime evidence where applicable. Use `status` for current approval fingerprints and read the pinned manifest/package schemas. Hashes, a successful technical check or a fixture receipt cannot manufacture human approval.

Execution state and receipts stay under the canonical task cache, with immutable sources and failed/versioned attempts in `.art-staging/`. A changed runtime build or host selection requires a fresh asset version with retained source ancestry and refreshed affected reviews. Historical manifests and approvals remain unchanged. Generation, installation, license acceptance, voice consent and runtime promotion require their own applicable authorization and evidence.

## Read-only Blender inspection

`inspect-blender-scene.sh SCENE.blend --root PROJECT --profile PROFILE [--blender EXECUTABLE] [--output REPORT] [--replace] [--dry-run]`

Profiles: `static-asset`, `rigged-actor`, `procedural-scene`, `render-scene`, `simulation`. Existing Blender 4.5.x is required. Dry-run queries prerequisites and creates no output. Without `--output`, stdout contains the validated v1 JSON report; otherwise it contains the report path. Existing reports require `--replace`. Sources, selected tools, Bubo dependency files and execution receipts remain read-only. Inspection requires no STYLE.md, ENGINE.md or MEDIA.md and grants no authoring or asset acceptance.
