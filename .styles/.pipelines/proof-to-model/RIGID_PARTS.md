# Explicit rigid-parts finishing

Use this route for reviewed rigid or articulated assemblies with authored HIGH
and LOW parts. Select `method: rigid-parts` in schemaVersion2 finishing settings;
default settings and schemaVersion1 continue to require QuadriFlow. A failed
solver never selects this route. It does not replace reconstruction, rigging,
animation or human acceptance.

## Prepare the actual input

Preserve the original reconstruction and editable master. Use an authorized
connected Blender working copy to establish semantic ownership, concealed
surfaces, source-faithful repairs, actual hinges and pivots. Distinguish source
observation from inferred construction. Preserve the detailed authored HIGH
surfaces and prepare LOW geometry appropriate to rigid motion. Do not relabel a
reduced proxy HIGH to manufacture zero error.

Export one embedded prepared GLB containing exactly the declared HIGH/LOW mesh
pairs. Preserve matching local geometry, transforms and material intent for
unchanged parts. Use separate names for every pair, stable unique part IDs, a
stationary root and an acyclic parent graph. Declare pivots in the shared
proof-frame world metres. Record source-to-prepared normalization explicitly;
the native route does not apply the reconstruction frame correction twice.

The handoff schema is [rigid-handoff.schema.json](rigid-handoff.schema.json).
Bind the exact retained reconstruction hash, prepared GLB, source-to-prepared
matrix, authoring evidence and parts. Authoring evidence binds the actual
original/master/script dependencies and per-part HIGH/LOW counts and intentional
repairs. It preserves ancestry; a JSON assertion alone does not prove it.

Each part declares its triangle and positive vertex-to-surface error limits.
These are final authored HIGH/LOW bounds. The separate schemaVersion1
`quadriFlow.simplification` limit still measures its own prepared solver input;
do not reinterpret or silently relax it for another stage. Record deliberate
modeling repairs separately from measured reduction. Changed settings or parts
invalidate their input review.

## Material and collision applicability

- `materialMode: preserve` requires exact HIGH/LOW geometry and material intent
  with valid portable materials, UVs and packed dependencies. Use it for actual
  unchanged manufactured parts; it cannot skip baking on reduced geometry.
- `materialMode: bake` requires a named `bakeGroup`. Its parts share a real
  packed atlas and output material. The fixed script packs a temporary joined
  LOW helper, scatters exact per-part UVs and bakes each actual HIGH onto its
  corresponding LOW. Preserve tangent convention, ray/cage settings and texture
  provenance. No constant or placeholder bake can stand in for the operation.
- Optional schemaVersion2 `rigidParts.uvAtlas` explicitly selects
  `{"method":"smart-project-pixels","islandMarginPixels":2}`. The closed
  object requires both fields and an exact JSON integer of1..64 pixels;
  admission and Blender independently require pixels <= recipe.textureSize/8.
  Only grouped baked LOW packing uses SmartProject's `FRACTION` margin of
  pixels/textureSize, with the existing projection angle and scale-to-bounds.
  Absent selection retains the exact recipe-driven call. Selected packing must
  finish, preserve triangle/loop/normal ancestry, and produce finite,
  nondegenerate per-triangle UVs inside the unit tile before scatter or baking.
  In this explicit mode, source-to-LOW accumulation uses zero per-part dilation.
  One independent margin-zero white-EMIT bake on the existing joined UV helper
  supplies coverage. Each of the five maps then receives one all-chart image
  EMIT padding pass with the unchanged recipe-derived dilation radius, a Closest
  sampler and distinct byte-backed source/destination images. Padding leaves
  the fresh destination uncleared so unowned pixels beyond the padding radius
  retain the channel's generated default, including neutral-blue normal data.
  Verify every
  occupied RGB texel against the unpadded source within one stored byte of
  quantization; black is valid data. Reject cancelled/failed operators, empty or
  malformed masks, nonfinite pixels and changed occupied texels. Temporary
  materials/images are removed and helper material ownership, selection and bake
  settings are restored on failure and success; successful passes also verify
  unchanged helper geometry, UVs and normals. The absent-option legacy bake path
  is unchanged.
  The atlas report records actual coverage, pixel drift, comparison-buffer
  bounds, zero per-part and global padding radii, sampler and source hashes,
  alongside packing method, pixels, fraction and texture size. Requested
  padding and summed triangle UV area do not prove raster spacing, coverage,
  lack of overlap or visual acceptance. Failure never changes the selected
  method or margin automatically; settings retain their normal hash binding.
- Optional `uvAtlas.triangleRepair` selects the closed, bounded `density-preserving-isolated-cells-v1` method. Read [TRIANGLE_ATLAS_CONTRACT.md](TRIANGLE_ATLAS_CONTRACT.md) for exact overlap checks, adaptive charts, stored-float density certificates and separate native raster/bake/visual requirements. Omission retains the previous packing path; failure never selects this repair automatically.
- Declare collision applicability and a reason per semantic part. Applicable
  parts receive the selected exact-hull or conservative kdop-26 construction and
  unchanged measured convexity/containment/face/volume checks. An internal
  presentation part may explicitly declare collision not applicable.
- Rigid-v2 `kdop-26` may explicitly set `frame: principal-axes-v1`. The support
  directions use a deterministic right-handed basis from all exact unique
  HIGH/LOW world positions; covariance, tie decisions and basis are reported.
  The world-centred origin, encoding, containment, face and volume limits remain
  unchanged. Unsupported or degenerate covariance rejects without a fallback.
  Omitted `frame`, or explicit `frame: world`, retains world-aligned directions.
  Principal axes can improve a slanted thin part's proxy, but do not guarantee
  that any particular part satisfies its selected volume limit.

Measure actual closed LOW topology, full bidirectional every-vertex distances
to the opposing triangle surfaces, transforms, material correspondence and
per-part/aggregate budgets. These measurements are not a continuous Hausdorff
or visual-quality proof. Preserve source identities and the actual method in
the stage report.

## Reviewed source-corner topology

When GLB seams or coincident contact branches obscure authored vertex ownership,
optional `rigidParts.sourceTopology` explicitly selects:

```json
{
  "method": "reviewed-source-corners-v1",
  "receipt": ".opencaw/.cache/tasks/TASK/source-topology.json",
  "receiptSha256": "<lowercase SHA256>"
}
```

This also requires the explicit constrained `rigidParts.lods` method described
below. The active task's receipt must bind the exact prepared GLB and appear
with its exact path/hash in reviewed authoring evidence's `sources`. Preserve
the original HIGH and declared semantic-part hierarchy; distinct vertex owners
do not become additional parts. Missing, changed or invalid selected evidence
rejects without a coordinate-weld fallback or another engine selection.

The closed version1 `rigid-source-corner-topology` receipt is limited to64MiB
and depth12. Its1..512 entries select a subset of existing LOW nodes and bind
actual GLB node indices, indexed-corner counts and complete source-owner IDs.
`ownersI32LEHex` stores lowercase little-endian signed32-bit IDs with a decoded
byte SHA256; IDs must be in range and cover every declared owner. Capture these
from actual authored native topology through the fixed helper's complete stored
corner mapping, preserving oriented geometry, UV and material correspondence.
Do not invent owners, dummy UVs or custom runtime attributes to force a match.

Native verification constructs a topology-only inspection copy and the
constrained LOD input from proven owners. The reviewed render LOW and its
normals, UVs, materials and frame remain protected. Without this selection,
ordinary exact-coordinate welding remains unchanged. Ownership evidence is an
index representation proof: existing manifold, orientation, area, normal,
source-distance and budget checks remain required. It does not establish the
absence of geometric intersections, physical holes or overlaps, or visual
readiness. LOD production retains justified negative cavity boundaries and
positive components with distinct owners at coincident positions inside that
component exactly. Other positive components may reduce under the existing
UV/source-distance guards; contact positions between separate components and
physical clearance are not thereby preserved or proved. Never flip, fill or
discard a retained boundary to obtain a reduction. Retention cannot waive
package budgets.

## Review, resources and execution

An independent technical preparation review must bind the exact complete
handoff hash and authoring-evidence hash, as well as raw and prepared model
hashes. Its task-local review reference lives in `settings.rigidParts`, outside
the handoff, avoiding a self-hash cycle. It records `human: false`; it cannot
approve the finished model, rig, motion or runtime.

Use the existing command:

```bash
./commands/proof-to-model.sh finish --finish-settings inputs/rigid-settings.json
```

Supply the command's normal project/task/asset arguments as shown by `--help`.
Settings follow [finishing-settings.schema.json](finishing-settings.schema.json)
and explicitly declare the handoff/review hashes, LOD0 triangle limit, GLB byte
limit and native memory budget. All dependency paths/hashes are checked before
spending an attempt and retained as stage inputs. Existing exact-manifest/count
finish-budget recovery remains required when its configured attempts are spent.

The memory policy must be supported before launch. Windows owned-job aggregate
committed-memory accounting is distinct from resident RAM or GPU usage; document
launch-assignment limitations. Unsupported enforcement blocks rather than
running without the selected policy. Argument arrays, cancellation, deadlines,
bounded logs, attempt-local temporary files and owned-tree cleanup remain in
force. Native execution is not an OS sandbox.

Only the fixed audited/hash-bound `finish.py`, `rigid_finish.py`,
`rigid_source_topology.py`, `common.py` and `review.py` bundle may execute this
native route. A handoff or receipt cannot select arbitrary code,
install an add-on, execute embedded source or download dependencies. Standalone
BLENDER connected-authoring policy remains unchanged.

## Output and acceptance

Optional rigid-v2 profiles require explicit selection. The
[stored-normal import contract](NORMAL_IMPORT_CONTRACT.md) binds incoming GLB
directions to bounded native working conversion without widening existing
preservation or codec checks. The
[constrained LOD contract](CONSTRAINED_LOD_CONTRACT.md) uses recipe-owned ratios, explicit per-level
error limits, material-aware UV constraints and complete-package budgets.
Omission retains the prior paths; neither profile is an automatic fallback.
Example optional fields under `rigidParts` are:

```json
{
  "importNormals": {"method": "stored-corner-fan-v1"},
  "lods": {
    "method": "original-component-finite-collapse-v1",
    "maxVertexSurfaceErrorMetres": [0.003, 0.01]
  }
}
```

Optional `lods.contactPolicy: protected-contact-rings-v1` requires the existing
reviewed `sourceTopology` receipt; it is never selected after a failed trial.
Absent selection retains exact whole-boundary contact retention. The selected
policy preserves every negative cavity boundary and complete positive contact
one-ring triangles, with exact positions, winding, material/UV data and distinct
original owner IDs. Surrounding positive geometry may reduce only through the
existing finite guards plus complete exact improper-intersection rejection
within each simplified positive boundary. No coordinate weld or cross-boundary
clearance/visual certificate is implied. See the constrained LOD contract for
the actual reduction, reimport and full UV/LOD/package preflight requirements.
Recipe ratios and all asset/package/material/texture/GLB limits remain unchanged;
contact retention cannot waive them or widen normal, fit or action tolerances.

LOD error entries must match `recipe.lodRatios` before native launch. Native
normal fidelity is reported across all source corners, including failures
outside repaired fans; fan precision is not a whole-artifact bound. Explicit
LOD component retention records its reason/count and cannot waive any budget.
The saved native preview shows only LOW0, retaining HIGH, alternate LODs and
colliders hidden. Full GLB export still includes the declared complete package.

Save editable HIGH/LOW/atlas source and export measured runtime geometry, LODs
and applicable colliders with part ancestry. Enforce explicit LOD0 limits and
the recipe's all-LOD/material/texture limits separately; count all geometry and
the actual embedded GLB payload. Independently re-import the export and compare
transforms, hierarchy/pivots, geometry, material/UV/texture correspondence and
collision lineage.

For source-owned parts, the fixed native capture records actual exported LOW0
and LOD corner ownership in output `source-topology.json`. Preserve that stage
artifact and its byte-identical active-task copy under
`rigid-topology-exports/`. The strict loader binds the final GLB hash and verifies
every selected derivative again through independent re-import. This export
receipt preserves representation evidence; it grants no model, motion or
runtime acceptance.

Static shading export follows the versioned
[normal export contract](NORMAL_EXPORT_CONTRACT.md). Pivot placement and UV
packing preserve the working mesh's geometry and normal data. Verify actual
stored GLB normals against independently captured source-local intent through
the pinned exporter codec; report source quantization and native DCC normal
reencoding separately. Native geometry, UV, material, hierarchy, pivot and
collision checks remain required. This is not a geometric-normal or visual
quality acceptance.

The all-LOD/collider package is not a curated animation render set. Prepare and
review a compatible LOD0 handoff before MODEL_TO_ANIMATION. Complete visual and
technical review and distinct human model/hierarchy/motion/runtime gates remain
required. Schema validation, a completed bake or a small fixture never certifies
the finished asset's source likeness or production readiness.
