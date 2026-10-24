# Native PROOF_TO_MODEL runtime

Requires .NET 10 SDK, Blender 4.5 LTS and, for reconstruction, the pinned native
Pixal3D CUDA toolchain. No Docker daemon or sibling checkout is used. Native
execution is bounded and logged; it is not an operating-system sandbox.

The CLI composes separate application, infrastructure and domain assemblies.
The application depends on its workspace, process and alpha-processing ports;
infrastructure implements those ports. Production assemblies use only the .NET
base libraries. Tests are an independent executable with no test-framework or
package download requirement.

## Initialize an asset

All supplied asset files must already be inside the resolved project root, with
no symbolic links or junctions. Use the existing external-library listing/copy
commands first when libraries are configured; record their copy/provenance
receipts in proof metadata. Never execute assets directly from a library.

Install the shared baseline at `/project/.opencaw`. Task manifests, approval
receipts and persistent reports belong under `/project/.opencaw/.cache/tasks/`;
the mount and cache must both be real directories, without links or junctions.
The retired `.ai` state layout is not accepted for active manifests or approvals.
Asset working copies remain in `.art-staging/`, tools in `.local/`, and promoted
runtime assets in `assets/models/`.

When STYLE configures libraries, `init --library-search search.json` is mandatory.
The search receipt must contain the current `styleContractHash` and a `libraries`
array covering each configured `id` and exact `root`. Each entry needs
`available: true`, a reason, and `result: "no-suitable-match"` or `"selected"`.
Selected entries additionally reference `copyEvidence`, the repository-local JSON
receipt from `copy-external-asset.sh`. The runtime verifies its style/library
identity and every copied file hash, embeds the receipt in proof metadata, and
invalidates lineage if copies change. It neither probes unconfigured locations
nor manufactures search evidence. An unavailable library blocks initialization.

`rights.json` must contain an explicit `authorized: true` assertion from the
caller. `brief.json` minimally contains:

```json
{
  "purpose": "Static environment prop",
  "scale": { "units": "metres", "metersPerUnit": 1 },
  "interfaces": []
}
```

The runtime copies the brief and original sources into versioned staging. It snapshots the
recipe budgets and current rights hash in the brief. The native export contract
uses metres; another unit scale is rejected rather than inferred. A brief may be
omitted for a technical diagnostic asset, but such an asset cannot be promoted.

```bash
.opencaw/commands/proof-to-model.sh init --root /project --task asset-production \
  --asset barrel --version v1 --actor artist \
  --proof inputs/barrel.png --rights inputs/rights.json --brief inputs/brief.json \
  --recipe .opencaw/.styles/.pipelines/proof-to-model/recipes/static-prop.json \
  --toolchain .opencaw/.styles/.pipelines/proof-to-model/toolchain.json
```

Use `--proof-metadata` to supply exact prompt, references, provider, model,
parameters, seed and reuse ancestry. An authorized pre-existing image gets
explicit unavailable markers for metadata not supplied; these markers never
represent invented generation settings. Creating a proof with CLOUD/LOCAL stays
under the existing style/media contracts and their generation budgets.

New assets use manifest v2 and six-view production. `--proof` registers one
immutable original, not an implicitly approved front view. For multiple originals,
use `--sources inputs/sources.json` instead, with this input shape:

```json
{
  "schemaVersion": 1,
  "images": [
    { "id": "source-front", "path": "inputs/barrel-front.png" },
    { "id": "source-back", "path": "inputs/barrel-back.png" }
  ]
}
```

The stored source set binds copied immutable bytes and hashes. The manifest's
legacy `proof` field remains an original anchor; generated images never replace
its role as source-classification evidence.

## Source classification and six-angle proofs

The first creative step is source-only inspection and research. Use
`build-proof-to-model-assets` and its source-classification reference to identify
living anatomy or nonliving structure, entity/part/attachment relationships,
materials, pose, silhouette, asymmetry and occlusion. A horse and rider remain
distinct entities; hidden legs need plausible but explicitly inferred placement.
A metallic skull-shaped helmet remains armor rather than bone. Preserve
intentional fantasy anatomy and do not use a generic template to erase it.

Author the classification report against the actual registered source-set hash.
Its `sources` binds every original ID/hash; claims, parts and research reference
only those originals. Separate observed, research-inferred, user-specified and
unknown claims, research support, alternatives, impact, preservation constraints
and unresolved conflicts. Assess each original exactly once in `sourceViews`
with `sourceId`, `view`, `usable` and `reason`; only canonical views can be usable.
Generated proofs, revisions and model renders cannot
become classification evidence by copying, renaming or relabeling. A generated
defect may prompt reassessment of originals; it does not establish source facts.

```bash
.opencaw/commands/proof-to-model.sh classify --root /project --manifest .opencaw/.cache/tasks/.../manifest.json \
  --classification inputs/classification.json
.opencaw/commands/proof-to-model.sh prepare-proofs --root /project --manifest .opencaw/.cache/tasks/.../manifest.json \
  --proof-set inputs/proof-set.json
```

These commands validate and register actual assistant/provider-produced
artifacts. They do not perform vision, web research or image generation.
Consult the checked-in `source-set.schema.json`, `classification.schema.json`
and `proof-set.schema.json` for the full records and current command help for
supported options. Critical unresolved conflicts block proof preparation;
ordinary classification does not manufacture a separate human approval.
Its `proof-plan.json` reports usable original coverage, missing angles, minimum
generation count and blocking unknowns; it never executes generation.

Select six ordered images: front, subject-right, back, subject-left, top and
bottom. A usable canonical source supplies one slot and normally needs five
additional images. An oblique/cropped source stays an anchor and can require six
canonical generations; make that extra cost explicit. Multiple originals supply
one shared coverage plan. Freeze identity, pose, scale, proportions, materials,
attachments and side-specific asymmetry across views. Do not mirror an asymmetric
subject to manufacture its other side.

Generation/revisions use explicitly selected CLOUD/LOCAL capabilities under
MEDIA.md, rights and bounded set/per-view/revision budgets. Keep actual provider
receipts, prompts/references, model disclosures or unavailable markers, image
hashes and revision ancestry. Revise only the selected angle, retaining rejected
candidates and other image bytes. Show full-resolution originals and all six
current proofs; obtain human approval of the entire hash-bound set and its
classification/camera interpretation. An accepted inferred underside is still
a design completion, not an observed source feature.

The camera contract is row-major Blender/NeRF camera-to-world, world Z up,
camera local -Z forward and +Y image up. Use exact cardinal/polar matrices,
explicit top/bottom roll, positive `meshScale`, distance and horizontal
`cameraAngleX`. Prescribed generated views use `nominal-prescribed` calibration;
an arbitrary illustration does not establish measured camera parameters.
Front faces -Y; subject-right is -X and subject-left is +X. Prompts and
side-specific attachments must use these subject-relative labels. An optional
per-view `cameraAngleX` overrides the shared horizontal FOV.

Mounted baselines work through the wrapper's trusted `--baseline-root`. The CLI
copies the three fixed reviewed Blender entrypoints into each attempt, hashes
the source and copied bundle, checks the actual Blender version, and records
its executable hash. Arbitrary `--pipeline-dir` overrides are rejected.

## Dependencies

`setup` is a dry run unless `--execute` is passed. `doctor` measures installed
tools and current NVIDIA driver/CUDA compatibility; it does not install drivers.

```bash
.opencaw/commands/proof-to-model.sh setup --root /project --manifest .opencaw/.cache/tasks/.../manifest.json
.opencaw/commands/proof-to-model.sh setup --root /project --manifest .opencaw/.cache/tasks/.../manifest.json --execute
```

Execution requires explicit acceptance of each applicable license by the actual
installing person or organization. OpenCaw authorship does not accept model
terms for other users. Use a task-local copy of the toolchain with the authorized
acceptance flags; shipped defaults remain false. Every downloaded file has an
HTTPS source, exact byte size and SHA-256 pin. Archives are checked before safe
ZIP/tar extraction, link and traversal entries are rejected, and every extracted
binary/library is hash-bound to an installation receipt. Model hashes and receipt
identity are checked during native generation. Ordinary asset commands never
download dependencies.

Six-view production uses the separately pinned Q8 MV model set, not the retained
SV diagnostic flow weights. Four new MV flows total approximately 5.45 GiB;
the complete nine-model set is approximately 7.54 GiB. Existing shared bytes can
be reused only after exact hash verification; separate directories can require
additional disk copies. No new anatomy model, paid reference database or hosted
reconstruction service is mandatory. Prior scoped installation/test approval
does not authorize another download or generation run.

Single-view diagnostics require explicit `init --mode single-view-diagnostic`
and `toolchain.single-view-diagnostic.json`. They retain the historical workflow
and `proof` approval kind with four arbitrary orthographic review views, labeled
diagnostic. A diagnostic `proof` receipt cannot approve a v2 proof set. They never
satisfy six-view production and cannot promote runtime assets. Preserve historical manifests rather than silently
rewriting them; begin a fresh asset version for migration.

## Ordered workflow and approvals

Each command takes `--root` and `--manifest`. Use `status` for the manifest and
current approval fingerprints, then supply an explicit JSON receipt to `record`:

```json
{
  "kind": "proof-set",
  "reviewer": "human-reviewer",
  "decision": "approved",
  "reason": "Approved all six current views and their shared interpretation.",
  "fingerprint": "COPY_CURRENT_STATUS_FINGERPRINT",
  "human": true
}
```

```bash
.opencaw/commands/proof-to-model.sh record --root /project --manifest .opencaw/.cache/tasks/asset-production/.../manifest.json \
  --kind proof-set --reviewer human-reviewer --evidence .opencaw/.cache/tasks/asset-production/reviews/proof-set.json
```

Receipts record explicit caller assertions. The CLI cannot authenticate a human
identity. It never emits its own human approvals. The v2 `proof-set` receipt uses
the current `status` fingerprint named `proofSet`. Proof-set selection and final
`human` acceptance require `human: true`; independent review requires a reviewer
different from the creator, explicit reasons, and current artifact fingerprints.
Changed receipt content invalidates its hash binding.

1. Run `classify` and `prepare-proofs`, review all six, and record `proof-set`. Then
   run `preprocess` for every selected view. Suitable real PNG alpha is preserved;
   opaque RGBA requires explicit BiRefNet, with no threshold-matting fallback.
   Retain cutouts, masks and ancestry; use common square padding without stretching,
   independent tight crops or per-view silhouette enlargement. Retain original
   dimensions, padding transforms and adjusted per-view horizontal FOV.
2. Inspect and record `preprocessing`, then run `reconstruct`. Its native process
   uses pinned argument arrays and actual MV weights with `--views`, `--num-views 6`
   and camera JSON. Validate all six actual frame hashes/counts because the engine
   can clamp requested views to available inputs. Retain the exact submitted
   images/cameras, raw GLB, execution settings and logs. No contact sheet,
   four-view subset or SV fallback substitutes for six frames.
3. Run `finish` for actual Blender retopology, UV/bake, LOD/collision and export.
   A recipe requiring rigging/animation explicitly leaves subject work pending.
4. For guided subject work, create a derivative GLB in this asset's staging tree,
   then `record --kind rigging` or `animation --artifact <derivative.glb>`. The
   first import also requires `--source <matching-editable.blend>` inside the
   same staging version. The receipt needs `artifactHash`, `sourceHash` and a
   subject expert's explicit `sourceCorrespondence` explanation. Both are copied
   immutably and both replace their static counterparts on promotion. Independent
   review must check their correspondence; hashes alone cannot prove two different
   formats represent the same authored rig. Its fingerprint is the pre-import status
   fingerprint; the resulting approval binds the copied derivative. The GLB must
   contain actual skins/animations, and the real Blender review checks imported
   deform/animation structures. Record the other applicable kind against the
   same derivative without `--artifact` when both are needed. New subject work
   invalidates downstream review and acceptance.
5. Run `review` to compare originals, approved proofs, prepared conditioning
   images and six matching perspective GLB renders of the final static or guided
   asset. The review records exact matrices/FOV, declared input geometry frame and
   one common bounds fit. Raw native exports and already-corrected proof-frame
   assets require distinct frame declarations so correction is never applied
   twice. Nominal alignment is not measured pixel correspondence or automatic
   likeness/anatomy acceptance. Record `independent`, followed by separate `human`
   runtime acceptance. Neither report generation nor technical validation accepts
   an asset for a person.
6. `validate` checks ordered completion and current hashes. Explicit `promote
   --destination assets/models/<name>/<version>` requires all applicable fresh
   approvals, an immutable brief, and a new destination. It never overwrites.

After `init`, `classify`, `prepare-proofs` and the target's own `proof-set`
approval, complete approved donors can be imported with `reuse --reuse-manifest
<donor-manifest>`. V2 initialization does not import donors or their approvals.
The donor must be repository-local, pass current hash/rights/approval validation,
and match original sources, classification, all six views/cameras, style, recipe
and MV toolchain. A single-view donor cannot satisfy six-view production. New rights additionally
require `reuseAuthorized: true`. Copies retain the donor manifest hash and full
input/output ancestry and original receipts. Reuse records `nativeExecution: false`;
the target still requires its own preprocessing approval and final reviews.
Interrupted imports resume only matching completed reuse preprocessing, preserving
its exact attempt and bytes. Incomplete or incompatible
ancestry fails explicitly instead of silently regenerating or inventing evidence.

## Recovery and budgets

An asset lock prevents concurrent state mutation. The selected GPU lock and
`CUDA_VISIBLE_DEVICES` assignment cover engine execution. A separate setup lock
prevents conflicting installs. Each stage writes a new immutable attempt;
interrupted/failed attempts remain visible. Rerunning an invalid stage invalidates
dependent stages and reviews, subject to the explicit attempt budget. Changed
style requires a new version. Timeout overrides may reduce, but cannot expand,
the configured deadline. Logs are bounded by actual UTF-8 bytes.

Windows uses an owned kill-on-close job; Linux uses a process group when `setsid`
is available. Cancellation, timeout and log failures terminate the owned process
tree and bound stream draining. These are lifetime controls, not an OS sandbox.

Run `tests/test-proof-to-model.sh` for controlled native/state regression tests.
They deliberately distinguish simulated policy fixtures from the separate real
Blender and live reconstruction acceptance evidence.

Run `python tests/test-proof-model-blender.py` for real controlled Blender
finishing/reimport and six-camera review fixtures. Their six-color synthetic
geometry verifies orientation and comparison behavior; it is not generated art
or a live Pixal3D reconstruction. Upstream reports MV validation with four views;
six-view quality/resource acceptance requires a separately authorized bounded
native run with verified MV prerequisites. Missing models/tools/licenses leave
that acceptance blocked/not-run.
