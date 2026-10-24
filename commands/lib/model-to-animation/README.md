# Native model-to-animation runtime

The .NET10 CLI composes separate Domain, Application and Infrastructure projects.
It reuses the focused `asset-production` workspace/native-process/audit primitives;
it does not copy the proof-to-model pipeline or require a reconstruction model.
Blender4.5LTS is an explicit existing executable, and canonical engine resolution
runs through OpenCaw's existing resolver. Native file/process guards are not an
operating-system sandbox. The workflow does not install software or use hosted
providers. Adobe integrations and declared excluded authoring provenance are
unsupported; ordinary negative exclusion notes are not vendor provenance.

## Inputs and stages

Run through `.opencaw/commands/model-to-animation.sh` in a host installation.
Maintainer checkouts use `commands/model-to-animation.sh`. Consult `--help`.

```bash
model-to-animation.sh init --task asset-animation --asset pilot --version v1 \
  --actor artist --model inputs/pilot.glb --rights inputs/rights.json \
  --recipe inputs/pilot-motion.json --blender /absolute/path/to/blender
```

The initial interchange file is a reviewed, self-contained project-local GLB.
Create that export explicitly for .blend/FBX sources; the command does not select
or install an importer. An optional `--editable-source` preserves .blend bytes as
ancestry without executing them. Rights require `authorized:true`. Keep source
metadata, model/clip rights and provider origin truthful. Configured external
libraries remain read-only; use existing copy/search workflows before production.

State lives below `.opencaw/.cache/tasks/<task>/model-to-animation/<asset>/<version>/`.
Originals and unique attempts live below `.art-staging/model-to-animation/`.
The manifest preserves original caller hashes and immutable snapshots; source or
contract drift requires an explicit fresh version or rerun from the affected stage.

Order is `inspect`, `prepare`, `rig`, `motion`, `bake`, `export`, `review`.
`author` and `retarget` explicitly select the motion implementation; neither falls
back. Native stages invoke only copied, audited, hash-bound fixed Blender scripts,
with factory startup, disabled auto-execution, Python failure exit status,
argument arrays, output/log/time limits and process-tree cancellation.

`retarget --motion-source inputs/motion.glb --mapping inputs/mapping.json` imports
actual compatible owned or licensed motion, not a vendor skeleton preset. Mapping
contains schemaVersion1, provider owned|licensed-library, rights authorized/license,
rootTranslationScale, bones with source/target and optional xyzw rotationOffset,
and clips with target id/sourceClip. The source and mapping are retained and hashed.

## Targeted revisions

After a complete motion stage, `author --revision revision.json` revises exactly
one existing clip while loading the actual prior motion .blend. Unaffected actions,
including retargeted actions, remain in that source. Revision JSON is:

```json
{
  "schemaVersion": 1,
  "clip": "body-lean",
  "replacement": { "id": "body-lean", "role": "response", "loop": true,
    "rootMotion": "in-place", "startFrame": 0, "endFrame": 24,
    "channels": [{"target":{"node":"Body"},"property":"rotation_quaternion",
      "keyframes":[[0,[0,0,0,1]],[12,[0.0998334166,0,0,0.9950041653]],[24,[0,0,0,1]]]}],
    "markers": [] },
  "reason": "Describe the actual requested correction."
}
```

This example assumes the recipe already declares body-lean and an actual Body
node. The replacement must contain real bounded keyframes. Profile, rig, budgets, states and other clip definitions cannot be rewritten
through this entrypoint. The complete merged recipe is saved immutably, its pointer
advances only after successful authoring, and per-clip definition hashes are retained.
Later stages use that effective recipe. Previous attempts and sampled motion hashes
remain evidence. A revision invalidates motion/final acceptance and preserves only
still-current rig approval. No unlimited retries: each attempt consumes the recipe's
explicit maxAttempts budget.

If a revision fails or the process is interrupted, repeat `author --revision` with
the intended request. The manifest retains the last successful motion separately
from the failed/running attempt and rechecks its source, recipe, inputs, outputs and
tool hashes before recovery. It never uses partial actions as the revision base.
Failed/interrupted attempt metadata and files remain evidence. Downstream stages
remain blocked until motion succeeds; rerunning an earlier production stage clears
the old recovery source and requires new motion production.

## Approvals and delivery

`status` exposes current rig/motion/independent/human fingerprints. `record` consumes
caller-supplied task-local receipts with kind, reviewer, decision=approved, reason
and fingerprint. Rig, motion and human require human:true. These are assertions;
the CLI does not authenticate humans. Rig acceptance follows actual hierarchy/rig
production and precedes motion creation. Whole-motion acceptance follows full review;
independent review requires a different creator identity. No report automatically
accepts visual quality or runtime readiness.

Human runtime acceptance also contains:

```json
{
  "runtime": {
    "status": "passed", "engine": "THREEJS",
    "modelSha256": "CURRENT_EXPORTED_MODEL_SHA256",
    "packageSha256": "CURRENT_STAGED_PACKAGE_SHA256",
    "evidence": [
      {"kind":"runtime-test","path":".opencaw/.cache/tasks/TASK/reviews/test.json","sha256":"..."},
      {"kind":"runtime-capture","path":".opencaw/.cache/tasks/TASK/reviews/capture.png","sha256":"..."},
      {"kind":"performance-profile","path":".opencaw/.cache/tasks/TASK/reviews/profile.json","sha256":"..."}
    ]
  }
}
```

Every referenced evidence file must exist in the active task and match its hash.
Actual engine behavior and human review remain external evidence, not a schema claim.
`validate` checks current file/approval identity, stage ordering and real GLB animation
bindings. `promote --destination assets/models/NAME/VERSION` requires all current
acceptance, creates a new destination, copies the exact model/editable source and
records package path rebinding, source/promoted package hashes and approval ancestry.
It never overwrites runtime output. Controlled test promotion uses explicitly
synthetic receipts and cannot establish production human or engine acceptance.

## Scope and verification

Skinned, articulated and rigid profiles avoid fake combat bones/clips. The existing
rigged-actor/v1 validator remains unchanged for its actual consumers. Phaser's 2D
contract needs explicit sprite/pre-rendered handoff and is rejected by this GLB
producer. CODE remains Three.js source-authored; using this workflow never silently
replaces its primary implementation or changes STYLE.md/ENGINE.md.

`Tests/RuntimeTests.csproj` exercises actual local persistence/hash/path/approval
mechanics with clearly labeled simulated Blender/engine process ports. It does not
prove rig deformation, motion quality or actual gameplay. Real Blender and selected-
engine integration fixtures are separately owned under `tests/`.
