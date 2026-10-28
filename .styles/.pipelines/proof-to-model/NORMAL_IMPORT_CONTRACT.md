# Rigid stored-normal import contract

Identifier: `opencaw-rigid-input-normals/v1`.

Rigid-v2 settings may explicitly select
`rigidParts.importNormals: {"method":"stored-corner-fan-v1"}`. No other fields,
caller tolerances or fallback are accepted. Omission retains the existing raw
import path. This conversion runs before working-state preservation snapshots;
it never widens the existing `2e-5` working or stored-codec checks.

## Authority and eligibility

The immutable GLB's SHA-bound float32 NORMAL vectors supply the targets.
Validate finite stored unit lengths with absolute error at most
`8 * float32 epsilon` (`9.5367431640625e-7`) before normalization. Admit every
selected mesh and its exact oriented POSITION/UV/material corner ownership,
typed source/node/material references, supported static features and ancestors
before skipping zero-free meshes. Unknown, stale, ambiguous, missing, unsupported
or nonfinite data rejects; geometric normals are never replacement targets.

Compare independently composed source frames with realized native frames:
maximum matrix-component residual `1e-6`, parent depth at most32 and the existing
positive, nonsingular, bounded-condition frame checks. Local and world direction
errors are Euclidean L2 distances between normalized float64 vectors; each side
uses its own independently bound inverse-transpose frame.

## Conversion and budgets

Only finite zero native directions trigger fan conversion. On owned working
meshes, prepare complete mapped corner fans using bounded tiny donors and
declared sharp-edge/packed-normal changes. Each repaired fan must remain within
`2e-4` of its incoming stored targets in local and world frames, for working and
predicted/actual re-exported directions. A previously valid corner's
source-relative working error may increase by at most `2e-5`. Outside the
affected fans, raw normal codes and decoded float32 bits remain exact. Geometry,
UVs, winding, material ownership and unrelated data remain unchanged.

One import batch shares before-operation limits across every mesh, rejected
mask and restart:8,192 mask evaluations,4,096 joint candidate states,4,096 whole
restart states,131,072 packed-code probes and128 historically touched
source-node-qualified vertices. Preserve the stricter per-mesh/per-vertex and
donor limits as well. Exhaustion rejects before the bounded operation; final
accepted counts cannot substitute for all attempted work.

Prepare detached candidates first. Commit only after every source and candidate
passes; rebind existing object data without replacing object identities,
parents, frames or UI. Keep raw mesh contents through all guards and rollback.
Intentionally retained raw orphan data lasts until the next owned scene reset
or process exit. Capture its evidence before reset; only immutable NumPy
contexts survive. Failure disposes owned scratch data and restores owned
bindings/state; externally poisoned raw data is detected without a false
preservation claim. Optional test callbacks and production process cancellation
remain distinct; the native runner owns time, memory and process lifetime.

## Verification and interpretation

Verify final stored bytes against independent PRE-export intent under
`NORMAL_EXPORT_CONTRACT.md` before allowing the final reimport decoder. Retain
raw and adapted DCC findings separately. Every initial mesh and every unchanged
final LOW0 mesh carries complete corner coverage, source/array/frame hashes and
source-to-raw/working/stored/effective loss summaries, worst witnesses and
diagnostic counts. Authored LODs and colliders bind their own PRE-export intent;
changed geometry does not invent original-source normal correspondence.

The repaired-fan bound is not whole-source or cumulative fidelity. Native decode
can already drift outside repaired fans, and successive conversions can exceed
`2e-4` cumulatively. Preserve failed comparisons and unavailable evidence.
Neither this contract nor structural/native checks approve appearance,
animation readiness or human runtime acceptance.
