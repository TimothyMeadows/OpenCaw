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

The runtime copies the brief and proof into versioned staging. It snapshots the
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

## Ordered workflow and approvals

Each command takes `--root` and `--manifest`. Use `status` for the manifest and
current approval fingerprints, then supply an explicit JSON receipt to `record`:

```json
{
  "kind": "proof",
  "reviewer": "human-reviewer",
  "decision": "approved",
  "reason": "Selected the staged silhouette and subject view.",
  "fingerprint": "COPY_CURRENT_STATUS_FINGERPRINT",
  "human": true
}
```

```bash
.opencaw/commands/proof-to-model.sh record --root /project --manifest .opencaw/.cache/tasks/asset-production/.../manifest.json \
  --kind proof --reviewer human-reviewer --evidence .opencaw/.cache/tasks/asset-production/reviews/proof.json
```

Receipts record explicit caller assertions. The CLI cannot authenticate a human
identity. It never emits its own human approvals. Proof selection and final
`human` acceptance require `human: true`; independent review requires a reviewer
different from the creator, explicit reasons, and current artifact fingerprints.
Changed receipt content invalidates its hash binding.

1. Record `proof`, then run `preprocess`. Suitable real PNG alpha is preserved;
   opaque RGBA requires explicit BiRefNet, with no threshold-matting fallback.
   The stage retains cutout, mask, normalization ancestry and disclosed transforms.
2. Inspect and record `preprocessing`, then run `reconstruct`. Its native process
   uses pinned argument arrays and retains raw GLB, single-view inputs/transforms,
   exact execution settings and process logs.
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
5. Run `review` to render proof comparisons and representative views of the final
   static or guided asset. Record `independent`, followed by separate `human`
   runtime acceptance. Neither report generation nor technical validation accepts
   an asset for a person.
6. `validate` checks ordered completion and current hashes. Explicit `promote
   --destination assets/models/<name>/<version>` requires all applicable fresh
   approvals, an immutable brief, and a new destination. It never overwrites.

Complete approved donor manifests can be reused via `init --reuse-manifest`.
The donor must be repository-local, pass current hash/rights/approval validation,
and match the new proof, style, recipe and toolchain. New rights additionally
require `reuseAuthorized: true`. Copies retain the donor manifest hash and full
input/output ancestry; new asset reviews are required. Incomplete or incompatible
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
