# Native model-to-action orchestration

The .NET10 runtime separates Domain, Application, Infrastructure and CLI layers.
Shared AssetProduction workspace/hash/audit/process primitives and canonical engine
resolution are reused directly. No dependency on another workflow's application
Pipeline or external orchestrator is introduced. Selected internal motion
validation/provenance patterns are adapted; this is independently authored OpenCaw
composition, with no new third-party source/model dependency.

`model-to-action.sh --help` documents init, doctor, inspect, compose, export, review,
record, validate, status and promote. Production commands install/download nothing.
Use the existing Blender4.5 executable and an explicitly reviewed project-local
`opencaw-motion-package/v1` source GLB. Adobe integrations and declared excluded
origins are unsupported.

## Source selection

Initialization requires `--motion-package`, `--recipe`, `--source-review`, `--task`,
`--asset`, `--version`, `--actor` and an absolute `--blender`. The source review lives
in that task's cache and contains schemaVersion1, kind source-motion, approved
decision, human:true, reviewer/reason, exact motionPackageSha256/modelSha256/rigId
and a clips array binding every used source id/motionSha256. A rights object must
explicitly declare authorized:true and the model/used-clip license. It is an explicit
cooperative human assertion; no tool authenticates the reviewer or invents it.
The standalone action package preserves that exact rights object and the source
review receipt's SHA-256 alongside model, motion-package, rig and clip identities.
An approved source may remain in non-runtime staging. Source review does not
manufacture earlier runtime acceptance.

The workflow copies immutable model/package/recipe/review/engine evidence under
`.art-staging/model-to-action/<asset>/<version>/original/`. Its manifest stays in
`.opencaw/.cache/tasks/<task>/model-to-action/<asset>/<version>/`. Caller sources,
actual source clip IDs/hashes, runtime/shared assemblies, Blender binary, fixed
script inventory and canonical selection bind subsequent results. Changing them
requires explicit fresh version or affected-stage work; nothing falls back.

## Composition

The compiler expands ordered trims/rates/repeats and incoming overlaps into exact
FPS-aligned spans, disallows triple overlap, and resolves cue addresses from explicit
occurrence/offset or unique source marker. Source clip hashes remain source hashes;
the measured composite identity is separate. Initial shared composition uses
in-place clips; extracted clips fail with an explicit movement-adapter handoff.

The fixed audited bundle actually inspects, composes, exports/reimports and reviews
native Blender artifacts. Every attempt is unique and hash-bound, with bounded
logs/time/files/frames and shared owned-process cleanup. Outputs cannot select
Python or shell expressions. Failed/interrupted attempts remain evidence; retry
uses a new directory and removes stale downstream selection/acceptance. Blender
technical cue proxies are not selected-engine effect acceptance.

Export verification streams every expected frame to attempt-local binary storage
and compares the independently re-imported GLB one frame at a time. Optional
`budgets.maxVerificationBytes` defaults to 8 GiB, accepts at most 64 GiB and is
separate from runtime-package size. A fixed 256 MiB per-frame payload cap prevents
an oversized frame. All three technical verification artifacts remain hashed in
the export attempt, with corruption/completeness checks and the unchanged 1 mm
geometry tolerance; they are not promoted as runtime assets.

## Acceptance

After full native review, record separate action, independent and human-runtime
receipts. They bind current fingerprints, explicit decisions and substantive
reasons. Action/human require human:true; independent differs from the creator.
Human runtime acceptance additionally binds effective engine and exact export
model/package hashes with task-local hashed runtime-test, runtime-capture and
performance-profile files. Structural passing results do not establish aesthetics,
controller feel, GPU timing or actual gameplay.

Promotion copies only reviewed model/editable source/original motion metadata to a
new `assets/models/...` destination and records exact path rebinding and original/
promoted identities. No overwrite or automatic acceptance. Clips/cues/projectiles
are presentation: gameplay retains movement, collision, damage and target authority.

## Verification scope

`Tests/RuntimeTests.csproj` exercises real native state/hash/path/lock mechanics and
the deterministic compiler. Its Blender, engine and human/runtime producers are
explicit simulations; those tests cannot certify actual authoring or playback.
Root integration additionally runs real Blender/apphost/browser fixtures. No new
NuGet package is required; BCL-only projects target the existing .NET10 SDK.
