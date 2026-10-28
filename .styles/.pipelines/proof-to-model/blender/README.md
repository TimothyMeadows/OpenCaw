# Native Blender finishing and review

These fixed, first-party batch entrypoints run with Blender **4.5 LTS**, factory startup and automatic script execution disabled. They are native processes, not an OS sandbox. The orchestrator must hash/audit these scripts and constrain execution time before invocation. Do not substitute arbitrary Python scripts or edit the source GLB.

Invoke `finish.py -- --job <job.json>` through Blender's `--background --factory-startup --disable-autoexec --python-exit-code 1 --python` options. The shared job schema supplies a resolved project `root`, repository-relative `input`, new/empty `outputDir`, `result` below that directory, and the explicit recipe. Existing attempt output is never overwritten. All resources must be embedded in GLB; URI dependencies, symlinks, junctions and escaping paths are rejected before import. Static finishing also rejects animated/rigged inputs; guided review permits them only with explicit matching recipe requirements.

## Finishing behavior

- Preserve a hash-verified source copy. Create working candidates and weld glTF seam duplicates at a fixed one-micrometre tolerance. Optional explicit `finishingSettings` may select voxel preparation with a bounds-based grid budget and actual prepared-triangle limit; preserve the imported high source for baking and the prepared intermediate hidden in the editable master. Require usable manifold/oriented topology and successful deterministic-seed QuadriFlow before unwrapping/baking. Every imported mesh is a semantic part; a supplied `parts` list must exactly identify them. A warning or unchanged failed source cannot stand in for retopology, and no repair mode is selected automatically.
- Check the actual QuadriFlow input predicates, including Blender4.5.10's componentwise float32 `1e-4` short-edge test in mesh-local units; a nonzero Euclidean length alone is insufficient. Optional explicit `quadriFlow.coordinateScale` selects a power-of-two solver representation1..1024, default1. Scale the working mesh coordinates and compensate the existing object scale, verify unchanged world vertices and triangle inputs, then invoke actual QuadriFlow in FACES mode with symmetry and attribute preservation explicitly disabled. Restore physical coordinates and the original transform before baking/export, including failures. Report the selected factor, predicates, invariants and actual operator result. No automatic factor escalation, short-edge cluster collapse, component deletion or project/world scaling is permitted; all output topology checks remain required. Preserve the original high and prepared intermediate. [Pinned Blender predicate](https://github.com/blender/blender/blob/6dc0b208d1b5/source/blender/editors/object/object_remesh.cc#L626).
- Unwrap new topology with Smart UV Project using the recipe margin and measure unit-tile coordinates and summed UV area. QuadriFlow face targets are approximate and reported, while final triangle budgets are enforced.
- Optional explicit `quadriFlow.simplification` applies at most one Collapse to each above-cap preparation, preserving the original preparation/HIGH. Below-cap parts report an actual measured no-op. Named world boxes select prepared vertices that must survive exactly once with bit-identical coordinates; zero collapse weights request preservation, and independent identity/coordinate checks enforce it. Require the measured input cap, unchanged per-component identity/Euler/orientation/manifoldness, and every source/candidate vertex's nearest opposing surface error within the explicit budget. Report both directions, held-vertex results and box coverage; holding vertices does not certify unchanged face interiors, and this vertex metric is not continuous Hausdorff distance. No automatic cap/tolerance/weight escalation or undocumented skip is permitted. The solver's own intermediate growth remains unbounded; input reduction is risk reduction, not a memory/success guarantee.
- A disconnected simplification reduces only its largest actual-triangle component, with lowest original ID breaking ties. Retain every other component's coordinates, polygon/corner order, actual tessellation and supported attributes exactly; subtract their triangles from the total cap. Verify isolation and recombination in the unchanged local frame, then enforce all whole-mesh guards. Insufficient capacity or unsupported/changed preservation rejects and restores the source.
- Bake source-to-candidate base color, tangent normal, AO, roughness and metallic maps on CPU. Record ray/cage settings. Base color and metallic are transported from each source Principled input's actual value/link using a temporary emission surface, avoiding diffuse-weight loss on metals; source graphs are restored afterward, including failure paths. Material correspondence is collapsed to one baked material per semantic part. Custom non-Principled shaders require explicit preparation; they are not guessed.
- Generate each declared LOD from LOD0 and require strictly decreasing measured triangles. Collision defaults to an exact hull per semantic part, failing when it exceeds `colliderMaxFaces`. Explicit `kdop-26` selects a conservative convex approximation from world-space support planes, with padding and a volume-ratio budget. Verify every source-part vertex is contained, the proxy is closed/convex with positive volume, and actual face/volume limits pass. Record the approximation and exact-hull comparison; never silently substitute a concave/decimated proxy or an undocumented box.
- Native hull topology is built on quantized coordinates. Exact-hull construction may refine an unsupported adjacent triangle diagonal only when both replacement facets support every actual source/hull point. The bounded deterministic refinement preserves vertex bytes, transform and face count, then runs the unchanged independent collision validator. Missing support points, ambiguity or an exhausted budget rejects; validation never repairs an arbitrary concave proxy or raises its tolerance. This does not change `kdop-26`.
- Save the editable blend (including preserved high meshes) and a fully embedded GLB containing the runtime meshes, named LODs, collision meshes and semantic metadata. `maxTriangles` counts **all** exported geometry, including every LOD and collider. `maxTextureBytes` bounds both separate bake maps and the actual embedded runtime texture payload. LOD/collision metadata is descriptive; each host engine still needs its normal import binding.
- Independently import the GLB into an empty scene and compare mesh identity/counts, aggregate triangles, bounds/transforms, hierarchy, material assignments, UVs and embedded texture dimensions. Success requires actual artifacts and source hash stability. Rigging or animation requirements block this static recipe until subject-specific work supplies an appropriate workflow.

## Review behavior

Explicit schemaVersion2 `rigid-parts` finishing uses the fixed `rigid_finish.py`
extension described in [RIGID_PARTS.md](../RIGID_PARTS.md). It accepts reviewed
HIGH/LOW pairs in the proof frame, retains exact unchanged materials or performs
real grouped atlas bakes, and verifies per-part distances, pivots, hierarchy,
LOD0/all-LOD budgets, colliders and actual re-import. Default/v1 QuadriFlow and
its completion checks remain separate. No failure selects another method.

The rigid static exporter implements
[`opencaw-rigid-static-normals/v1`](../NORMAL_EXPORT_CONTRACT.md). Pivot parenting
and UV scatter preserve actual LOW data and world normals. A pre-export source
snapshot and pinned native codec independently verify stored GLB NORMAL data;
native reimport retains geometry/UV/material/hierarchy/collision checks and
reports DCC normal approximation separately. Codec equality does not mean
lossless source transport or geometric/visual acceptance. Unsupported codec
revisions or attribute correspondence fail explicitly.

Explicit pixel-atlas mode accumulates each HIGH-to-LOW map with zero per-part
dilation, then pads all charts together on the existing joined UV helper using
one native image-to-image EMIT pass per channel. The recipe still determines the
global padding radius. A separate margin-zero white-EMIT mask verifies every
occupied RGB texel before/after all five maps within one stored byte; black
remains valid. Source and destination are distinct byte-backed images with
matching color spaces/defaults and a Closest sampler. Padding does not clear the
fresh destination, preserving generated defaults beyond the padding radius;
the independent black-background coverage bake remains cleared. Reports bind coverage,
unpadded pixel hashes, actual radii and maximum drift. Chunked NumPy comparisons
bound explicit buffers; process memory/time enforcement remains native. Temporary
images/materials are removed, helper material ownership, selection and bake
settings are restored, and successful passes verify unchanged helper geometry,
UVs and normals. Cancellation and failed validation reject the result. Packing without the
explicit pixel option retains its original per-part behavior. Occupied-texel
preservation does not certify mip/filter quality or source likeness.

`review.py` uses the same job envelope plus a repository-relative `proof` image. It independently loads the exported GLB, hides nonzero LODs/colliders, and creates four actual CPU-rendered orthographic views and an HTML comparison beside the original proof. Hashes bind the page to its inputs. This creates review evidence; it always leaves independent and human acceptance pending.

Rigid-v2 also has explicit [stored-normal import](../NORMAL_IMPORT_CONTRACT.md)
and [component-preserving LOD](../CONSTRAINED_LOD_CONTRACT.md) profiles. Both are
part of the fixed five-script rigid bundle: `finish.py`, `common.py`,
`review.py`, `rigid_finish.py` and `rigid_source_topology.py`. Default/v1 uses
its original three-script bundle. The import profile
admits every source mesh/frame/corner and shares before-operation budgets
across all attempts; it retains full-source loss diagnostics independently of
repaired-fan bounds. The LOD profile preserves original components, measured
error and material-dependent UV boundaries with the unchanged native face-area
floor, then checks the complete exported inventory including colliders.
Atomic progress snapshots are rate-limited, while final available evidence
remains complete. Neither profile authorizes another backend or human approval.

Optional `rigidParts.sourceTopology` selects `reviewed-source-corners-v1` with
an exact receipt path/hash and requires the explicit constrained LOD profile.
The receipt remains under the active task and is also bound by reviewed
authoring `sources`; it selects only declared LOW nodes. The fixed helper maps
all actual stored corners to authored native owners and builds private topology
inspection/LOD copies while preserving the render LOW, original HIGH and
semantic hierarchy. Unselected LOWs retain ordinary exact-coordinate welding.
Selected missing, stale or ambiguous evidence fails without a weld fallback.

This proves index representation, not physical intersection clearance, area,
normal quality or visual readiness. LODs retain justified negative boundaries
and positive components with distinct coincident owners inside the same
component exactly. Other positive components may reduce under the existing
UV/source-distance guards; separate-component contacts and physical clearance
are not certified. All error and package limits remain required. Final native
capture writes output
`source-topology.json` and an identical active-task evidence copy, binds the
actual GLB hash, and verifies selected LOW0/LOD ownership through independent
re-import. Read [RIGID_PARTS.md](../RIGID_PARTS.md) for receipt limits and review
requirements. This adds no arbitrary authoring script, add-on, generation,
installation or dependency permission.

Guided rigging/animation derivatives are reviewable when the original recipe explicitly requires those capabilities. Review checks actual GLB skin joints, imported deform bones/weights, animation channels/samplers and a measurable imported action timeline. It rechecks the derivative's geometry/material/embedded-texture budgets and renders a midpoint animation pose using evaluated scene bounds. It records actual action ranges, bone counts and the rendered frame; it does not claim automatic rigging or animation creation. Missing required structures fail, and undeclared rig/animation content remains rejected. The static finishing entrypoint is unchanged.

`tests/test-proof-model-blender.py` runs real Blender with explicitly synthetic engineering fixtures. It exercises complete finishing/review, multiple semantic parts/materials and transformed source hierarchy, immutable source/attempts, geometry budgets, malformed resources, static required-animation rejection, and guided rig/animation derivative review including missing requirements and derivative budget rejection. These fixture results are not a live proof-to-model reconstruction claim.
