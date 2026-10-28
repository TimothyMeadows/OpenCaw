# Component-preserving rigid LOD contract

Rigid-v2 settings may explicitly select:

```json
{"lods":{"method":"original-component-finite-collapse-v1","maxVertexSurfaceErrorMetres":[0.003,0.01]}}
```

This object belongs under `rigidParts`. Required fields are `method` and
`maxVertexSurfaceErrorMetres`:1..8 finite positive world-metre bounds, each at
most one metre and matching the authoritative recipe's `lodRatios` count before
native launch. The only optional field is `contactPolicy`, described below.
The recipe owns ratios and the complete-package triangle budget; existing rigid
settings own the LOW0 budget. Absent `contactPolicy` retains the exact existing
policy. No fallback, replacement ratio or extra numeric policy is accepted.

## Geometry and search

The ordinary path uses derivative copies of admitted non-contact parts and its
existing exact-weld policy, retaining every original closed, oriented, positive
component with at least four triangles. Reviewed sourceTopology instead preserves
its explicit owner graph; it never coordinate-welds distinct owners. Its default
retains negative boundaries and positive boundaries with internal coincident
owners exactly. The optional contact policy below changes only that latter
whole-positive-boundary retention rule. No component may disappear, split or
merge. Each level starts from the original components, rather than the previous
derivative. Source LOW0 stays immutable.

Search `r + (1-r)*i/8` for integer `i` from zero through eight, plus the previous
selected ratio when in range. Record every rejection and chosen ratio. Actual
component counts must not increase across levels. Explicit ratio-one retention
is allowed when reduction cannot satisfy the constraints; record counts and
reasons. Retention never waives error, topology, UV, normal or package budgets.

Measure every original/candidate vertex against the other corresponding
component's actual world-space triangle surface in both directions, including
representation error. Both must meet the declared bound. These checks do not
establish continuous-surface Hausdorff distance or appearance equivalence.
Every derivative trial, assembly and independent native reimport retains the
unchanged `<=1e-12` local face-area rejection. PRE-export derivative identities
own the reimport dispatch, so removing imported metadata cannot bypass it.

## Explicit protected contact rings

Optional `rigidParts.lods.contactPolicy: protected-contact-rings-v1` requires
the existing `rigidParts.sourceTopology` method `reviewed-source-corners-v1`,
its current active-task receipt and exact reviewed authoring-source binding.
This global option requires the receipt to cover every declared LOW mesh;
incomplete coverage rejects before a native launch or attempt is spent. Without
this option, the existing explicit subset behavior remains supported.
Missing/changed owner evidence blocks before tools; positions alone never
establish owners. The original finite-collapse method and error array remain
required. Unknown/empty/duplicate selectors, extra fields and implicit selection
are rejected. Omitting this field retains whole-boundary contact retention.

Retain every negative cavity boundary exactly. For affected positive boundaries,
protect the complete one-ring contact triangles: exact source corner positions,
winding, material and UV values, and distinct original owner IDs. Do not weld
coincident owners or move a protected boundary to make a reduction fit. Surrounding
positive geometry may use the existing finite trials and source-distance,
closed-topology, sign, material/UV and normal guards. Each simplified positive
boundary additionally requires complete exact rejection of improper intersections
within that boundary. Cross-boundary clearance/contact intent, continuous-surface
error and appearance remain separate; this policy cannot certify them.

Prove actual reduction away from protected triangles, exact negative/protected
retention and complete owner ancestry again on independent reimport. Retain rejected
trials and cancellation/budget evidence. A theoretical retained-count estimate is
not an achieved LOD. Run actual full-asset UV, LOD and complete-package preflight
before expensive baking. Retention does not waive declared limits: for a project
selecting200k LOW0,400k all-exported triangles,eight materials,4K textures and128MiB
runtime GLB, those same limits still apply. Normal codec2e-5, native restoration2e-4,
declared3mm fit and downstream1mm action verification are not widened here.

The selected contact policy supports at most 262,144 source LOW0 triangles per
part. One complete part-builder call shares fixed limits across source checks
and every level/trial: 16,777,216 BVH node-pair visits, 67,108,864 leaf triangle-pair
visits and 16,777,216 exact predicates. Counters reserve work before each operation;
exhaustion aborts the call instead of becoming a rejected ratio or a budget waiver.
Private immutable array fields are limited to 64MiB each. When a cancellation
callback is supplied, physical checks poll every 256 node-pair visits and every 64
leaf-pair/exact-predicate visits. Native process deadlines/cancellation remain
separate. These finite support/work limits do not guarantee reduction, complete
package admission or full-asset finish time.

## UVs, normals and evidence

Only verified constant isotropic materials without UV-dependent inputs,
textures, vertex colors, animation, volume, displacement or anisotropy may
regenerate unused derivative UVs as deterministic separate unit-grid triangles.
Source UVs are preserved. Supported textured/baked materials hold chart and
material boundaries with exact-zero native weights. Verify the entire boundary
set, both UV sides and material ownership. Unknown/unsupported graphs reject;
native COLLAPSE delimiter flags do not establish UV preservation. Never clamp.

Derivative geometric normals are explicitly authored finite nonzero directions,
not restored source normals. Verify each assembled component's selected
geometry/material/world ancestry, positive topology and two-way error again.
Whole-package limits use every exported LOW0, LOD and collider exactly once.
Per-part checks or a partial fixture cannot certify the complete package.

Helper trials remain complete in final success/failure evidence. Progress
snapshots are atomically replaced no more than once per second while callbacks
occur; this is a write-rate limit, not a heartbeat guarantee. Force terminal
records and identify unavailable helper reports. A hard interruption may leave
newer unwritten checkpoints and a preserved pending write; do not claim those
were captured. Reporting failures cannot return successful unowned outputs.

Native execution and simulated admission/failure controls are reported
separately. Primitive benchmarks do not certify a full asset's finish time.
Human visual, hierarchy, motion and runtime gates remain separate.
