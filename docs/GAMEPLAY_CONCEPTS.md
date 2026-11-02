# Gameplay concept index

Use this optional index to turn a requested mechanic, visual technique, or performance problem into work for an existing Hephaera owner. Read only the relevant rows and their linked contracts. A game does not need every concept here; applicability depends on its rules, genre, target devices, and observed problems.

The topic inventory was informed by [Game Dev Cheat Sheet](https://gamedev-cheatsheet.com/). The guidance below is independently authored. No site prompts, prose, animations, or code are included.

## Choose the owner before implementation

1. State the player outcome or measured problem. Decide whether the change belongs to authoritative simulation, input, presentation, asset production, or scheduling. Record why the concept applies; leave unrelated mechanics out.
2. Read the host's `ENGINE.md`, architecture, and relevant project rules. Run [resolve-engine.sh](../commands/resolve-engine.sh) from the baseline directory (`.hephaera/` in an installed host; the repository root in a maintainer checkout).
3. Find candidates in the [engine feature catalog](../skills/INDEX.md#engine-features) and use [resolve-skill.sh](../commands/resolve-skill.sh) with each candidate skill name. Require `compatible: true` before activation or delegation. An agnostic owner coordinates policy; it does not supply another engine's APIs or satisfy missing platform prerequisites.
4. Read the compatible owner's current instructions and the host's locked versions before edits. The engine-labeled links below are examples for that engine, not a recommendation to switch engines. For a different selection, discover its equivalent owner in the catalog; if none fits, record the gap and obtain a scoped implementation decision.
5. Define expected observations and target evidence before implementation. Keep numerical timing, speed, capacity, and frame budgets specific to the project. This index adds no skill, engine, art pipeline, dependency, or automatic setup step.

Commands relative to an installed host root use `.hephaera/commands/`; links in this document are relative to the shared baseline. The [engine contract index](../.engine/INDEX.md) explains selection and capability boundaries.

## Read the tables as starting points

Each row identifies a useful existing owner and one decision or future check. Some owners provide concrete workflows; others provide related policy without a focused recipe for that concept. Specialized code or fixture coverage may be narrower still. Missing focused guidance does not establish that an engine lacks a capability.

The checks describe requirements for future selected-engine work. They are not gameplay tests executed by this document, and a linked skill does not establish that a host game implements the feature.

### Clocks, input, and actor state

Use the [gameplay runtime](../skills/build-gameplay-runtime/SKILL.md) for state and lifecycle boundaries, [action design](../skills/design-action-gameplay/SKILL.md) for verb eligibility, and compatible engine owners for implementation.

| Concept | Apply when | Existing owner and next decision or check |
| --- | --- | --- |
| Delta time | Updates must respond consistently to elapsed time. | [Clock and update-order guidance](../skills/build-gameplay-runtime/references/input-and-locomotion-feel.md#clocks-and-update-order) separates simulation and presentation; [Three.js loop policy](../.engine/THREEJS.md) remains engine-specific. Declare units, clamping, pause, and dropped time. Multiplying by delta alone does not stabilize every system. |
| Coyote time | Ledge-jump forgiveness supports the intended platforming rules. | [Late-jump grace](../skills/build-gameplay-runtime/references/input-and-locomotion-feel.md#late-jump-grace) defines support history, entitlement, expiry, and single consumption. Verify stale contacts cannot re-arm a spent jump; retain selected-engine movement authority. |
| Input buffering | A deliberately early action should remain eligible briefly. | [Action buffering](../skills/build-gameplay-runtime/references/input-and-locomotion-feel.md#action-buffering-and-single-consumption) defines identity, capacity, expiry, arbitration, and resets. [Three.js controls](../skills/threejs-build-controls/SKILL.md) is one engine's input-edge owner; buffered acceptance still checks current gameplay eligibility. |
| Acceleration and friction | Starting, stopping, or reversing needs deliberate movement tuning. | [Movement-response guidance](../skills/build-gameplay-runtime/references/input-and-locomotion-feel.md#acceleration-braking-and-friction) separates controller acceleration/braking from surface friction. [Unreal locomotion](../skills/unreal-build-movement/references/locomotion-prediction-boundaries.md) is an engine-specific example; measure stopping under the actual movement owner. |
| Finite state machine | Actor behavior needs explicit legal transitions. | [Gameplay runtime](../skills/build-gameplay-runtime/SKILL.md) owns authoritative state transitions. Specify entry, exit, cancellation, repeated requests, and reentry. Animation state can present a transition without deciding its gameplay outcome. |
| Fixed timestep | Simulation scheduling needs bounded, repeatable stepping. | [Three.js loop policy](../.engine/THREEJS.md) covers fixed updates, catch-up caps, and interpolation. Choose the tick policy; check stalls, pause, and input edges. Fixed scheduling alone does not prove cross-machine physics determinism. |

### Contact and presentation

Keep accepted hits, damage eligibility, and movement in simulation. The [feedback owner](../skills/build-gameplay-runtime/references/gameplay-feedback-and-haptics.md) coordinates bounded cosmetic responses after authoritative events; adapters do not acquire combat authority.

| Concept | Apply when | Existing owner and next decision or check |
| --- | --- | --- |
| Easing | A transition needs a deliberate progression over its duration. | [Accessible motion](../skills/build-accessible-motion-systems/SKILL.md) owns motion tokens and interruption. Distinguish duration curves from continuous damping; review reversal, bounded overshoot, reduced motion, and cleanup. |
| Screen shake | Camera emphasis helps communicate an event. | [Camera modifiers](../skills/build-gameplay-runtime/references/camera-and-runtime-audio.md#camera-modifiers) retain one base camera writer. Bound overlap and intensity, preserve authoritative aim, and verify cancellation plus reduced-motion alternatives. |
| Squash and stretch | Decorative deformation improves the selected visual language. | [Accessible motion](../skills/build-accessible-motion-systems/SKILL.md) and compatible actor-animation owners provide lifecycle policy, rather than a focused deformation recipe. Declare pivot and scale bounds; restore the base transform without changing colliders or authoritative reach. |
| Camera deadzone | Follow framing should tolerate target motion within a region. | [Camera ownership](../skills/build-gameplay-runtime/references/camera-and-runtime-audio.md#camera-ownership) covers framing and look-ahead. Check resize, zoom, small rooms, teleport, and target loss. Camera framing regions differ from analog-stick dead zones. |
| Hit stop | A brief, selected slowdown or freeze reinforces an accepted event. | [Clock and interruption policy](../skills/build-gameplay-runtime/references/gameplay-feedback-and-haptics.md#clocks-hit-stop-and-interruption) owns scoped requests. Declare participants, release clock, exclusions, and overlap; ending one request must preserve other pause or slow-motion requests. |
| Invincibility frames | Rules deliberately suspend some damage eligibility. | [Action design](../skills/design-action-gameplay/SKILL.md) owns timing and authoritative truth; its general policy needs a project-specific immunity contract. Define categories, start/end boundaries, refresh/stacking, and cancellation. A blink or VFX state cannot confer immunity. |
| Hitbox and hurtbox | An action tests attacking shapes against eligible targets. | [Action design](../skills/design-action-gameplay/SKILL.md) owns hit rules and [feedback events](../skills/build-gameplay-runtime/references/gameplay-feedback-and-haptics.md#event-and-channel-ownership) follow acceptance. Define attack/target identities, active windows, layers, and duplicate-contact policy across shapes and steps. |
| Tunneling | Fast motion misses thin collision geometry. | [Unity physics diagnostics](../skills/unity-build-physics/references/simulation-diagnostics.md#collision-and-queries) supplies a scoped example. Reproduce speed, scale, body type, and real physics cadence; choose supported sweeps/CCD. A smaller render delta cannot repair arbitrary teleports or competing transform writers. |

### Queries and optional world work

Use these techniques when world scale, agent behavior, or measured workloads justify them. A small or turn-based game may need none of the proposed scheduling, indexing, or streaming changes. [Three.js scenes](../skills/threejs-build-scenes/SKILL.md) requires explicit application implementations for physics, navigation, and AI; it is not a ready-made world simulation.

| Concept | Apply when | Existing owner and next decision or check |
| --- | --- | --- |
| Raycasting | Picking, obstruction, or another finite geometric query is needed. | [Three.js controls](../skills/threejs-build-controls/SKILL.md) covers bounded picking, layers, stable identities, and fresh transforms. Check viewport/UI ownership and thin or transformed targets. A query result alone does not authorize damage. |
| A* pathfinding | A selected graph-navigation problem benefits from heuristic search. | [Three.js navigation adapters](../skills/threejs-build-scenes/SKILL.md) and [Unreal navigation policy](../skills/unreal-build-ai/references/decision-navigation-cancellation.md) are starting points, not a portable A* implementation. Define graph/cost/heuristic rules, work limits, and no-route/replan behavior; prefer suitable selected-engine navigation. |
| Steering behaviors | Agents need bounded local movement intent. | [Unreal decision/navigation ownership](../skills/unreal-build-ai/references/decision-navigation-cancellation.md) supplies related policy, not a shared steering recipe. Specify priorities, speed/turn limits, crowd and blocked-target behavior; collision-aware movement retains authority. |
| Seeded noise | Spatial variation must be reproducible for generation or saves. | [Unreal generated-resource policy](../skills/unreal-build-procedural-content/references/determinism-and-resources.md#reproducible-inputs) covers versioned inputs and stable identities. Select noise type, coordinates, seed, parameters, and tolerance; test borders and reordered work. Seeded random values alone do not define coherent noise. |
| Spatial partitioning | Measured query cost justifies a spatial candidate index. | [Three.js collision policy](../.engine/THREEJS.md#physics-and-collision) and [web optimization](../skills/optimize-web-games/SKILL.md) offer related policy. Choose an index with bounded work; compare against exhaustive queries for borders, large/moving objects, removal, and duplicates. Streaming cells are a separate concern. |
| Time slicing | Deferrable work needs a bounded share of update time. | [Web optimization](../skills/optimize-web-games/SKILL.md) and [Unreal asynchronous decision policy](../skills/unreal-build-ai/references/decision-navigation-cancellation.md) are starting points. Define checkpoints, fairness, deadlines, cancellation, and stale-result rejection; do not defer required collision or damage decisions arbitrarily. |
| Chunk streaming | A world cannot remain fully resident at target budgets. | [Three.js loading ownership](../skills/threejs-build-scenes/SKILL.md) and [Unreal streaming](../skills/unreal-build-worlds/references/streaming-and-world-ownership.md) have different scopes. Separate requested, loaded, and gameplay-ready states; test traversal, cancellation, collision readiness, unload, and persistent edits. |

Ray queries above are distinct from ray-traced or path-traced rendering. Tracing remains deferred under the [existing Three.js rendering scope](THREEJS_POSTPROCESSING.md#rendering-scope); this index does not select a tracing renderer or library.

### Rendering and resource diagnostics

Start with the selected scene, material, animation, and performance owners. Diagnose the actual renderer and target before changing assets, quality, or resource ownership. These terms do not select an art-production pipeline.

| Concept | Apply when | Existing owner and next decision or check |
| --- | --- | --- |
| Normals | Shading suggests a surface-orientation or normal-map issue. | [Three.js materials](../skills/threejs-build-materials/SKILL.md) and [topology acceptance](../skills/model-blender-assets/references/modeling-and-topology-contract.md#topology-acceptance) cover different parts of diagnosis. Distinguish geometry normals, map conventions, tangents, and transforms; recomputation is not a universal repair. |
| Level of detail | View-dependent detail can reduce measured cost. | [Three.js scene policy](../.engine/THREEJS.md#scene-and-level-management) and [Unreal HLOD ownership](../skills/unreal-build-worlds/references/streaming-and-world-ownership.md#build-and-runtime-checks) have different scopes. Define thresholds, hysteresis, bounds, and transition review. Lower-detail assets and runtime selection require separate work; collision remains authoritative. |
| Frustum culling | Objects outside a camera view waste rendering work. | [Web optimization](../skills/optimize-web-games/SKILL.md) and [Three.js scenes](../skills/threejs-build-scenes/SKILL.md) provide related policy. Inspect animated/instanced bounds, edge reentry, and multiple cameras; presentation culling must preserve required simulation and essential cues. |
| Fragment shader | Surface appearance needs a custom per-fragment calculation. | [Three.js materials](../skills/threejs-build-materials/SKILL.md) separates GLSL and node/TSL backends. Verify host-version APIs, color, alpha, variants, and actual GPU output; fullscreen effects stay with the existing postprocessing owner. |
| Billboarding | A label, sprite, or effect should face the viewer. | [Three.js particles](THREEJS_PARTICLES.md#integrate-a-bounded-runtime) provides a bounded particle-billboard case, not a general vegetation/label recipe. Choose camera-facing or axis-locked behavior; review parent transforms, bounds, sorting, and picking where applicable. |
| Quaternions | Rotation composition or interpolation needs explicit orientation rules. | [Camera smoothing](../skills/build-gameplay-runtime/references/camera-and-runtime-audio.md#camera-ownership) and [Three.js actor integration](../skills/threejs-animate-actors/SKILL.md) are scoped starting points. Declare spaces, component/composition order, and normalization; shortest-arc interpolation must not erase intentional multi-turn motion. |
| Z-fighting | Nearly coincident surfaces produce unstable depth results. | [Three.js scenes](../skills/threejs-build-scenes/SKILL.md) provides clipping/scale policy rather than a focused repair recipe. Reproduce the conflict; inspect overlapping geometry and depth precision before a supported scoped remedy. Avoid arbitrary render-order or renderer changes. |
| Object pooling | Repeated allocation has a measured cost worth controlling. | [Web optimization](../skills/optimize-web-games/SKILL.md) provides general policy; [Quarks lifecycle](THREEJS_PARTICLES.md#integrate-a-bounded-runtime) covers a narrower effect pool. Define reset completeness, capacity/exhaustion, owner generations, and stale-callback rejection; do not infer a universal entity pool. |
| Particle system | Bounded visual effects support event readability. | [Three.js particles](THREEJS_PARTICLES.md) owns the selected Quarks integration; other engines retain their particle owners. Bound emission, lifetime, overdraw, cancellation, and disposal. CPU lifecycle evidence cannot establish GPU appearance or device performance. |
| Frame budget | Responsiveness or sustained performance needs measurable limits. | [Application profiling](../skills/profile-application-performance/SKILL.md) owns comparable workloads and distributions. Set device/build targets; capture CPU/GPU timing, stalls, memory, and measurement limits. No universal refresh target or frame-time threshold is imposed here. |
| Draw calls | Rendering submissions may be a demonstrated bottleneck. | [Web optimization](../skills/optimize-web-games/SKILL.md) measures submissions; [Three.js policy](../.engine/THREEJS.md) covers batching and instancing. Compare total cost, material constraints, and culling granularity; fewer calls alone does not prove improvement. |
| Overdraw | Layered or transparent screen coverage raises GPU cost. | [Three.js materials](../skills/threejs-build-materials/SKILL.md) owns transparent-pixel and variant budgets. Measure representative coverage and passes on the target, including effects; preserve essential cues when reducing cost. |
| Texture atlas | Grouped texture content can improve batching or delivery. | [Phaser asset policy](../.engine/PHASERJS.md) and [Unity atlas lifetime](../skills/unity-build-2d-content/references/atlas-lifetime.md) are engine-specific owners. Review padding/filtering/mips, memory, loading references, and packed target output; batching and content delivery are distinct outcomes. |

## Preserve the existing production boundaries

- New Three.js particle work uses the [Quarks owner](THREEJS_PARTICLES.md); fullscreen effects use [pmndrs postprocessing](THREEJS_POSTPROCESSING.md). Their dependency, renderer, clock, and teardown checks remain authoritative. Neither selection installs packages or changes the renderer.
- [MAUI packaging](WEB_GAME_PACKAGING.md) remains a separate capability for selected web engines. Browser or source checks do not certify packaged device behavior. Native engines retain their own exporters.
- Asset production still follows the host's `STYLE.md`, selected pipeline, and applicable media contracts. These concept links authorize no generation, download, setup, or promotion. [Model animation](../skills/build-model-animations/SKILL.md) and [action composition](../skills/build-model-actions/SKILL.md) retain their review and handoff rules; existing Bubo pins and historical evidence remain unchanged.
- Treat presentation as an adapter of truthful state. Animation callbacks, camera movement, shader output, particles, sound, and haptics cannot independently decide hits, immunity, travel arrival, costs, or rewards.

## Evidence for a future implementation

For each selected concept, record its owner, intended behavior, acceptance cases, and limits in the host's task state. Bind results to the actual source/build, effective engine, locked dependencies, renderer or physics backend, target platform/device, and relevant settings.

| Evidence | What it can establish | Remaining boundary |
| --- | --- | --- |
| Guidance and source review | A contract, implementation path, or focused gap exists in the inspected revision. | Does not establish runtime behavior, player comprehension, or equal support across engines. |
| Unit or subsystem fixture | The exercised state, math, scheduling, or lifecycle behavior passes its declared cases. | Scope stays with that fixture and backend; synthetic reports are not gameplay acceptance. |
| Actual selected-engine runtime | Observed movement, queries, rendering, transitions, or resource behavior in the tested build. | Does not cover untested engines, scenes, platforms, network conditions, or devices. |
| Target measurements and playtests | Measured performance and observed player response under recorded conditions. | Preserve sample limits and contradictory findings; physical haptics need actual hardware observation. |

Use boundary, interruption, lifecycle, and representative workload cases appropriate to the change. Record expected versus observed results and artifacts; mark unavailable runtime, GPU, device, or player checks `not-run` or `blocked` with a reason. A complete document, valid link, compiled shader, or passing report parser cannot substitute for that evidence.
