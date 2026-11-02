# Rendering diagnostics

Use this optional reference when a requested scene has incorrect visibility, detail transitions, shading, orientation, depth, or measured render cost. Diagnose the relevant symptom rather than installing every technique. Visual acceptance and performance improvement are separate claims.

Resolve `ENGINE.md`, the actual renderer/backend and locked versions, and compatible scene/material/animation/profiling skills before APIs. Preserve the host renderer, clocks, asset ancestry, and `STYLE.md` pipeline. This agnostic reference supplies no renderer switch, package, asset generation, or universal frame-rate target.

## Capture the failing case

Record source/build, target device/runtime, viewport/DPR, camera/projection, world units, renderer/color/depth settings, content/pose, and repeatable camera/input path. Capture the defect before changing it; compare the same workload and quality settings afterward.

| Symptom | First distinctions |
| --- | --- |
| Object disappears or pops | Bounds versus camera/layers, LOD selection, loading/readiness, or a genuinely absent object. |
| Shading changes under movement | Geometry normals/tangents, normal-map basis, transforms, light/environment, or shader/backend mismatch. |
| Label or actor spins/flips | Coordinate/composition order, billboard constraint, singular view, or rotation-path intent. |
| Surfaces flicker | Duplicate/coplanar geometry, depth precision, transparency sorting, or an intentional overlay. |
| Frame cost rises | CPU scheduling/submission, GPU pixels/passes/shaders, memory/residency, or loading; counters alone do not identify the limit. |

## Conservative bounds and visibility

A bound must contain the rendered shape for the state and transform being tested. Static rest-pose geometry bounds may not contain skinned, morphed, displaced, instanced, billboarded, or cosmetically stretched output.

- Inspect local versus world bounds, parent transforms, scale, and the stage at which matrices/bounds become current. Update or conservatively expand them through the selected engine's supported ownership path when pose, instance transforms, geometry, or shader displacement changes.
- Include the maximum reviewed deformation/particle size where CPU bounds cannot observe shader motion. A conservative envelope needs measured culling cost; disabling culling globally is not a verified repair.
- For instances, check both per-instance transforms/identity and the aggregate bound used by the renderer. Moving one instance outside a stale aggregate must not hide it; batching can reduce culling granularity.
- Evaluate all required cameras/passes: split view, minimap, shadows, reflections, or other selected views. A main-camera result cannot globally hide an object still required elsewhere. Declare per-view versus shared visibility policy explicitly.
- Keep authoritative simulation, action windows, immunity, collision, and persistence valid offscreen. Animation supplying root motion or gameplay query anchors cannot be skipped merely because its mesh is culled.
- If purely cosmetic pose work is reduced, define its clock/sampling policy and refresh the current pose, anchors, matrices, and bounds before reentry is rendered or queried. Do not replay missed visual callbacks as new gameplay outcomes.

Use edge reentry, rapid turns, teleport, extreme poses, moving instances, and multiple cameras to isolate failures. Distinguish frustum culling from occlusion, layers, streaming, and gameplay perception; one system's visibility flag is not all of them.

## Runtime LOD and asset ancestry

Use the selected engine's existing LOD facilities where suitable. Lower-detail asset production and runtime level selection are separate operations with separate evidence.

- Declare screen-coverage/distance criteria, camera/viewport dependencies, quality tiers, and maximum detail cost. Use distinct enter/exit thresholds or another explicit hysteresis rule to avoid oscillation near a boundary.
- Retain stable actor identity, animation/action state, attachments, material intent, and conservative bounds across levels. Define selected multi-camera/shadow policy instead of letting the last camera overwrite a global level unpredictably.
- Review transitions at gameplay distance, during motion, and at thresholds. Cross-fades or extra representations can increase overdraw/memory; measure rather than assuming a smoother transition is cheaper.
- Preserve source/LOD ancestry, rights, reviewed export identities, and production budgets under the selected asset pipeline. A runtime diagnostic does not authorize generating, remeshing, or promoting another model.
- Visual LOD cannot silently swap authoritative colliders, targeting reach, navigation, or persistent state. Any separately selected collision simplification needs its own physics/gameplay contract and verification.

## Normals, tangents, and material spaces

Geometry normals describe mesh orientation; a normal map encodes perturbations interpreted through a declared basis. Diagnose both without assuming one universal recomputation fixes every shading problem.

- Compare a simple known material/light setup with the failing one. Inspect winding, hard/smooth edges, seams, degenerate/duplicate faces, UVs, and export triangulation before changing shader complexity.
- Declare object/world/view/tangent spaces, axis/handedness conventions, UV orientation, normal-map channels, and tangent generation. Map conventions and tangent handedness must match the actual material/export path.
- Inspect negative, mirrored, and nonuniform parent scale. Use the supported normal transform for the actual model transform; normals do not generally transform like positions. Singular/zero-scale transforms need an explicit repair or rejection policy.
- Check tangents and basis continuity after topology/UV changes, deformation, or export. Recomputing geometry normals can erase authored hard edges while leaving a wrong map convention untouched.
- Treat normal maps as data under the existing color pipeline. Verify channel interpretation, lighting/output conversion, alpha mode, and backend-supported shader APIs with the selected material owner. Compilation alone cannot establish correct shading or art agreement.

Review grazing angles, mirrored pieces, nonuniform transforms, animated poses, and the target renderer. Keep any modeling repair under its existing authoring/review workflow.

## Billboard constraints and spaces

Choose full camera-facing, axis-locked, or another explicit orientation rule for the visual. State pivot, facing axis, coordinate space, parent transform, size policy, and whether picking must match its visible geometry.

- Build orientation in the declared space and convert through the parent correctly; a world-facing rotation assigned as a local rotation can fail under transformed parents. Inspect inherited nonuniform/mirrored scale separately.
- For axis locking, define what happens when the camera direction approaches the locked axis or coincides with the pivot. Use a declared stable orientation/last-valid policy rather than undefined normalization, sign flips, or jitter.
- In multiple views, assign orientation per view/pass or select a documented shared policy. One camera's mutable billboard transform cannot accidentally leak into another camera's render or query.
- Bounds must cover the allowed rotations and size range. Review sorting, depth, readability, and optional pick mapping at front/side/overhead views; keep authoritative collider/movement transforms outside cosmetic billboarding.

Particle billboards remain with the selected particle owner. This diagnosis neither replaces Quarks nor certifies a general label/vegetation implementation from a particle fixture.

## Quaternion paths and bounded easing

Declare component order, normalization policy, coordinate space, composition order, and the owner of the base orientation. Parent/local/world conversions and interpolation intent are separate questions.

- Equivalent quaternion signs can represent the same orientation. For a selected shortest-arc interpolation, handle that equivalence and near-opposite/degenerate inputs through the host's supported math behavior; verify the actual path, not only the final orientation.
- Endpoint orientations alone do not preserve turn count. Intentional spins or multi-turn motion need authored intermediate samples or another explicit continuous path/turn representation; do not replace them with an assumed shortest arc.
- Separate duration-based easing from continuous damping. State clock, units, interruption/reversal, and target changes; repeated frame-based blending does not by itself establish frame-rate-stable response.
- An easing curve may deliberately overshoot. Preserve that intent within declared value/angle/scale bounds and restoration rules instead of blindly clamping every curve or allowing unbounded extrapolation. Handle completion, cancellation, and owner reuse without stale modifiers.
- Keep decorative orientation/scale distinct from authoritative aim, movement, and hit geometry. Use [camera ownership](camera-and-runtime-audio.md#camera-ownership) and [feedback deformation](gameplay-feedback-and-haptics.md#cosmetic-deformation-and-protection-cues) for composition and reduced-motion behavior.

## Depth conflict and Z-fighting

Reproduce the camera angles/distances that trigger flicker. First distinguish an opaque depth conflict from transparent sorting or two unintended copies of the same surface.

1. Inspect duplicate/coplanar faces, overlapping instances, export scale, and intended surface separation. Remove accidental duplication through the existing asset owner rather than hiding it with arbitrary render order.
2. Inspect world scale, camera projection, and near/far clipping against required visible content. Choose a justified range and verify clipping across gameplay cameras before changing it; a smaller near plane is not automatically better depth precision.
3. For an intentional decal/overlay, choose a scoped remedy supported by the actual renderer/material, such as a reviewed offset or dedicated decal path. Verify grazing views, shadows, intersections, and transparent content; do not disable depth testing globally.
4. Different depth encodings or renderer modes can affect materials, shadows, postprocessing, and target support. They require an explicit compatible host decision and fresh validation, never a silent switch to make one artifact disappear.

## Measure cost with visual agreement

Capture comparable CPU/GPU/frame distributions, stalls, memory/resource trends, passes/submissions, pixels/overdraw, and loading as supported. Record unavailable GPU timing honestly. Set target-specific budgets and sustained workloads rather than a universal FPS threshold.

- Batching/instancing/material reuse can lower submissions while increasing update work, aggregate bounds, memory, or invisible rendering. Compare complete cost and culling behavior.
- Transparent coverage, full-screen passes, shader variants, resolution/DPR, and effect overlap can dominate despite low triangle or particle counts. Preserve essential cues and selected accessibility settings.
- Atlases affect batching, sampling, memory, and delivery separately. Review padding/mips/filtering/compression and live content references on target; preserve asset rights and the selected production pipeline.
- For THREEJS, retain the existing Quarks particle owner and pmndrs postprocessing owner on the host renderer/presentation clock. Do not add another render loop, final output pass, implicit fallback, or tracing package. Other engines retain their own owners.

Raycasting for picking/collision is a geometric query, distinct from ray-traced or path-traced rendering. Tracing remains deferred under the existing Three.js scope. MAUI packaging does not certify WebView GPU/color/lifecycle/performance behavior; actual packaged targets need separate evidence under the existing packaging contract.

## Future acceptance scenarios

These are requirements for future selected-engine work, not executed rendering tests or benchmarks. Record expected results, representative content, and tolerances before changing the host.

| Scenario | Expected observation |
| --- | --- |
| Animated/morphed/displaced actor or moved instance reaches view edge | Current conservative bounds retain required pixels without unexplained disappearance. |
| Main camera culls an object still needed by another view/pass | Declared multi-view visibility/LOD/billboard policy preserves that view without global-state leakage. |
| Offscreen attack or movement continues, then the actor reenters | Authoritative outcomes remain valid; current pose/anchors/bounds appear without stale or replayed gameplay events. |
| Oscillate near LOD thresholds, resize, or change cameras | Hysteresis and view policy hold; state/attachments stay stable and transition cost is measured. |
| Compare LODs during motion and collision/query interaction | Reviewed asset ancestry persists; visual detail does not silently change gameplay geometry or identity. |
| Mirrored/nonuniform/degenerate transforms or changed UV/topology | Declared normal/tangent/map-space rules hold; unsupported singular inputs are handled explicitly. |
| Billboard under a transformed parent, overhead/coincident camera, or two views | Axis/space/singular policy remains stable; bounds and selected pick mapping match visible output. |
| Equivalent-sign, near-opposite, and authored multi-turn rotation paths | Chosen arc/turn intent survives composition/interpolation and actual runtime playback. |
| Overshooting ease, reversal, cancellation, and pooled reuse | Explicit bounds and restoration hold; decorative motion cannot move authoritative geometry. |
| Coplanar/duplicate/decal surfaces across camera ranges | Cause-specific depth remedy works without new clipping, sorting, shadow, or output regressions. |
| Batch/atlas/shader/effect change under the same workload | Comparable CPU/GPU/memory plus visual evidence supports any claimed gain; a lower counter alone is insufficient. |
| Suspend/resume, resize, context loss, or packaged-device use | Existing renderer/effect ownership recovers or reports failure truthfully; untested targets remain explicit. |

## Record evidence and limits

Bind captures and measurements to build, engine/backend, dependencies, device/driver/runtime, scene, cameras, settings, and workload. Source/math tests establish their stated scope; actual rendered pixels, sustained performance, device lifecycle, and player readability need runtime/target review. A CPU lifecycle pass or successful package build cannot supply GPU acceptance.

Mark unavailable browser/native/WebGL/MAUI/device/player checks `not-run` or `blocked` with reasons. Preserve source/fixture/runtime distinctions when handing off changes; this reference itself establishes no game improvement or universal engine coverage.
