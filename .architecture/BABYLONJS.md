# BABYLONJS.md

This repository follows a **Babylon.js browser 3D game architecture** for WebGL/WebGPU-backed games, simulations, product experiences, XR scenes, and browser-native interactive 3D applications.

The architecture is optimized for:

- Babylon.js as the browser 3D game and rendering engine foundation
- TypeScript or JavaScript applications using ES modules and tree-shakeable packages
- explicit ownership between Babylon runtime objects and project-owned gameplay systems
- glTF/GLB-first asset loading and production pipelines
- PBR, environment lighting, shadows, post-processing, and material budgets
- physics, animation, GUI, input, audio, WebXR, and debug tooling as deliberate subsystems
- browser lifecycle, resize, input, audio-unlock, context-loss, and mobile-performance constraints
- measurable runtime performance and testable gameplay logic

The goal is to keep the system:

- clear about what Babylon owns and what the application/game owns
- production-ready beyond Playground prototypes
- resilient to scene transitions, asset failures, device capability differences, and long sessions
- friendly to large asset pipelines and team-authored scenes
- practical for turning Babylon.js into a full browser game runtime without hiding all behavior in meshes and callbacks

---

# Core Architecture Rule

**Use Babylon.js as the rendering and game-runtime foundation, but keep durable gameplay state, progression, persistence, networking, and feature rules in project-owned systems.**

Prefer:

```text
Game State / ECS -> Simulation Systems -> Babylon Scene Sync -> Babylon Engine -> WebGL/WebGPU
```

Avoid:

```text
Babylon Mesh / Node tree -> all gameplay truth, save data, input rules, networking, quests, inventory, and UI state
```

Babylon should own the engine, scene graph, cameras, meshes, materials, lights, animation groups, particles, physics plugin integration, GUI textures, XR session helpers, render loop, and debug surfaces. The project should own gameplay identity, rules, state machines, save data, asset manifests, networking contracts, analytics, entitlement checks, and tests.

---

# Recommended Structure

```text
src/
  app/
    createEngine.ts
    createScene.ts
    babylonConfig.ts
  engine/
    loop/
    time/
    input/
    assets/
    audio/
    physics/
    ecs/
    rendering/
    scenes/
    gui/
    xr/
    debug/
  game/
    entities/
    components/
    systems/
    levels/
    cameras/
    animation/
    progression/
    ui/
    state/
  infrastructure/
  tests/
assets/
  models/
  textures/
  environments/
  audio/
  manifests/
tools/
  assets/
```

Framework integrations such as React, Vue, Angular, Next.js, or SPA routing should stay at the application boundary. Do not let component lifecycles accidentally create duplicate engines, scenes, input bindings, render loops, or audio contexts.

---

# Engine and Scene Ownership

Create one owning Babylon engine per embedded runtime unless the product intentionally uses multiple canvases.

Rules:

- centralize `Engine` or `WebGPUEngine` creation in one application boundary
- choose WebGL or WebGPU deliberately and document fallback behavior
- keep the canvas, engine options, antialiasing, stencil/depth settings, hardware scaling, offline support, context-loss behavior, and resize policy explicit
- use ES module packages such as `@babylonjs/core`, `@babylonjs/loaders`, `@babylonjs/gui`, and `@babylonjs/inspector` for production builds
- prefer direct module imports and documented side-effect imports over importing all of Babylon when bundle size matters
- avoid using Babylon's public CDN for production builds; host pinned packages and decoder assets through the project's own deployment path
- dispose scenes, textures, materials, meshes, observables, GUI textures, physics objects, and post-processes when they leave ownership
- prevent hot reload, route remounts, or modal shell changes from creating duplicate engines or render loops

Recommended startup flow:

```text
create canvas -> create engine -> load runtime config -> create scene -> load assets -> attach input -> start loop
```

---

# Scene Architecture

Use scenes as lifecycle-managed runtime containers, not as the only project organization model.

Recommended scene categories:

- `BootScene`: device checks, engine setup, feature detection, telemetry defaults
- `LoadingScene`: progress UI, asset manifest loading, shader/material warmup
- `MenuScene`: menu cameras, GUI, settings, account/session routing
- `GameplayScene`: world content, gameplay systems, cameras, lights, physics, animation, particles
- `HudScene` or GUI layer: screen-space overlays, prompts, minimap, interaction hints
- `DebugScene` or debug layer: inspector, performance counters, physics/collider views

Rules:

- separate scene creation, asset loading, activation, pause/resume, unload, and disposal
- keep reusable systems outside individual scene files
- keep scene-local Babylon nodes distinct from durable game state
- create stable node naming conventions for imported meshes, cameras, lights, sockets, spawn points, and VFX anchors
- keep render layers, layer masks, collision groups, camera rigs, and highlight/outline policies documented
- make scene transitions explicit so old observers, timers, physics bodies, sounds, and GUI controls do not survive accidentally

---

# Game Loop and Time

Babylon's render loop schedules rendering, but game correctness still needs a timing model.

Rules:

- use the engine render loop as the browser frame driver
- separate input sampling, fixed simulation, physics stepping, animation updates, render synchronization, and scene rendering
- use a fixed timestep for deterministic movement, physics-like interactions, combat timing, replays, or multiplayer correctness
- cap catch-up steps after tab throttling, device sleep, breakpoint pauses, and slow frames
- clamp deltas before passing them to camera smoothing, animation blending, particles, or tweens
- pause or degrade updates on `visibilitychange`, route changes, overlays, focus loss, and battery-sensitive states
- keep game systems independent enough to unit test without a live WebGL context

Recommended flow:

```text
browser frame -> collect input -> fixed simulation steps -> sync Babylon nodes -> scene.render()
```

Use on-demand rendering only for static viewers, editors, configurators, or turn-based experiences that do not require continuous animation.

---

# State and Entity Model

Babylon nodes are presentation and interaction objects. They should not be the only source of game truth.

Rules:

- keep durable state serializable and independent from `Mesh`, `TransformNode`, `Scene`, or `AnimationGroup` instances
- store stable entity IDs and render handles rather than deriving all state from mesh names
- use `metadata` or reserved node properties only for bridge data, debug tags, authored IDs, or editor/runtime links
- prefer an ECS, data-oriented model, finite-state machines, or focused systems for medium and large games
- keep gameplay commands separate from pointer/camera callbacks
- document ownership for spawned entities, pooled entities, imported level nodes, decals, particles, GUI controls, and audio emitters
- validate entity lifecycle: create, activate, update, disable, pool, dispose

---

# Assets and Loading

Use an explicit asset contract before production content grows.

Rules:

- prefer glTF/GLB for runtime 3D assets
- load production assets through manifests, registries, or asset services rather than scattered URLs
- use Babylon loader module functions where they improve tree shaking and plugin options
- import required loaders explicitly, such as `@babylonjs/loaders/glTF`
- use `AssetsManager`, asset containers, or project loaders for grouped loading, progress, retry, cancellation, and scene ownership
- document decoder hosting for Draco, Meshopt, KTX2/Basis, Havok, or other WASM/worker-backed resources
- separate source art, optimized runtime exports, thumbnails, metadata, licensing, and generated files
- handle missing files, failed decoders, partial loads, unsupported extensions, CORS errors, and slow networks
- validate imported roots, pivots, units, bounds, sockets, animation groups, material names, collision proxies, and LODs

Recommended asset contract:

```text
asset id -> source file -> runtime file -> loader options -> scale/origin -> materials -> animations -> colliders -> license -> owner
```

---

# Materials, Lighting, and Rendering

Babylon provides strong high-level rendering features. Use them with budgets.

Rules:

- prefer PBR materials for physically plausible 3D scenes unless the art direction requires unlit, stylized, toon, or custom shader materials
- define environment texture, color management, exposure, tone mapping, and image-processing defaults in one rendering policy
- use prefiltered environment textures for production PBR lighting
- document real-time light count, shadow-caster count, shadow-map sizes, reflection probes, post-processes, transparency, particles, and skeletal mesh budgets
- use material reuse, texture atlases, texture compression, instances, thin instances, LODs, impostors, and culling before adding content scale
- avoid creating materials, textures, meshes, or post-processes every frame
- centralize render pipelines, post-process chains, outline/highlight layers, glow layers, render targets, and camera layer masks
- test scenes on low-end mobile, integrated GPUs, high-DPI displays, and throttled browser profiles

Rendering policy should document:

- WebGL/WebGPU choice and fallback
- target frame rate and resolution scaling
- device pixel ratio cap
- shadow policy
- texture-size limits
- transparency sorting expectations
- post-processing budget
- XR performance constraints when applicable

---

# Physics and Collision

Treat Babylon physics as a subsystem with explicit game rules around it.

Rules:

- choose and document the physics plugin, such as Havok, and how its WASM/assets are loaded
- keep physics world setup, gravity, timestep, collision groups, trigger layers, and material/friction policy centralized
- sync gameplay entities to physics bodies and Babylon nodes in a predictable order
- use simplified collision meshes or authored collider proxies instead of high-poly render meshes
- separate triggers, hit detection, navigation blockers, pickups, and physical collisions
- avoid letting physics impulses become the only authority for gameplay rules unless that is the design
- keep deterministic or multiplayer-critical simulation rules server-owned when using networking
- expose debug views for colliders, raycasts, contact points, and physics performance

---

# Input, Cameras, and Controls

Babylon cameras and camera inputs are useful defaults; game controls still need an action layer.

Rules:

- map raw keyboard, pointer, touch, camera input, gamepad, and XR controller events into game actions
- document camera type and intent, such as `UniversalCamera`, `ArcRotateCamera`, custom follow camera, cinematic camera, or `WebXRCamera`
- attach camera controls deliberately and remove or customize inputs that conflict with gameplay
- use Pointer Lock only for camera modes that need unconstrained mouse movement and provide fallback behavior
- poll gamepad state through a normalized action mapper
- separate camera smoothing, collision, occlusion, zoom, follow targets, and shake from gameplay state changes
- handle focus, pointer capture, browser gestures, fullscreen, orientation, and mobile virtual controls

---

# Animation

Use Babylon animation groups and clips as presentation data, with gameplay-owned animation state.

Rules:

- import named animation groups from glTF/GLB where possible
- document clip names, loop behavior, blend rules, root motion policy, event markers, and fallback idle states
- keep animation state machines in game systems or character controllers
- avoid making gameplay correctness depend on animation callback timing alone
- validate skeletal scale, bind pose, bone naming, socket/attachment nodes, and retargeting assumptions
- pool or dispose animation-heavy entities intentionally
- test animation transitions in real gameplay camera angles, not only in isolated viewers

---

# GUI and UI Layers

Choose deliberately between Babylon GUI, DOM UI, and framework UI.

Rules:

- use Babylon GUI for in-world panels, diegetic controls, XR-friendly surfaces, and canvas-integrated HUDs
- use DOM or framework UI for complex forms, account flows, accessibility-heavy menus, long text, settings pages, and responsive application chrome
- keep UI state outside Babylon GUI controls when it must persist across scenes or route changes
- define how screen-space labels, reticles, tooltips, health bars, minimaps, and prompts project from world coordinates
- avoid expensive GUI pointer-move handling on complex meshes unless the interaction needs it
- test high-DPI text, localization, focus order, controller navigation, touch targets, and mobile safe areas
- keep HUD and in-world markers readable against lighting, post-processing, bloom, and camera movement

---

# Audio

Browser game audio requires lifecycle and user-gesture handling.

Rules:

- unlock and resume audio only after a user gesture when browsers require it
- separate music, ambience, UI, SFX, voice, and spatial audio buses or groups
- attach listener behavior to the active camera or document an alternative listener model
- keep positional audio emitters lifecycle-managed with entities
- handle mute, pause, tab visibility, route changes, device sleep, and output-device changes
- keep audio assets in manifests with loop points, compression choices, loudness targets, and ownership

---

# WebXR and Multi-Device Runtime

Use Babylon WebXR helpers when XR is part of the product.

Rules:

- define whether XR is required, optional, or experimental
- document supported modes: inline, immersive VR, immersive AR, hand tracking, controller input, teleportation, anchors, hit testing, or passthrough
- keep non-XR camera and input paths functional unless the product is XR-only
- budget XR scenes more aggressively than flat-screen scenes
- keep comfort rules explicit: locomotion mode, snap/smooth turn, teleport, height calibration, vignette, and motion-sickness constraints
- use mesh-based GUI or XR-compatible controls rather than assuming fullscreen 2D GUI works in immersive sessions
- test entry/exit, lost tracking, controller disconnect, permissions, and unsupported devices

---

# Browser Integration

Babylon games still live inside the browser platform.

Rules:

- handle `resize`, device pixel ratio changes, orientation changes, fullscreen entry/exit, focus loss, and `visibilitychange`
- use browser storage, backend persistence, and cache policy deliberately; do not treat local IndexedDB/cache behavior as durable save storage without a product decision
- keep service worker, asset caching, compression, CDN, and cache-busting policies explicit
- avoid blocking the main thread with heavy parsing, pathfinding, mesh generation, or save serialization
- use Web Workers or WASM where heavy CPU work is measurable and isolated cleanly
- document CORS, cross-origin isolation, SharedArrayBuffer needs, and WASM decoder hosting when relevant
- provide graceful errors for unsupported WebGL/WebGPU, disabled hardware acceleration, lost contexts, and low-memory devices

---

# Debugging and Observability

Production Babylon projects need visibility beyond visual inspection.

Rules:

- enable the Inspector and debug layer only in development or privileged debug builds
- use performance counters, scene instrumentation, engine FPS, GPU frame timing where available, and custom telemetry
- expose debug overlays for draw calls, active meshes, texture memory, skeletons, particles, physics bodies, collisions, asset load time, and input state
- log asset load failures with asset ID, URL, loader, decoder, and scene owner
- capture recoverable context loss, unsupported feature paths, WebGPU fallback, and device capability decisions
- add screenshot or pixel checks for critical scenes in browser automation when feasible
- keep debug tooling tree-shakeable or excluded from production bundles

---

# Testing and Validation

Test gameplay systems separately from Babylon surfaces, then verify browser rendering paths.

Recommended coverage:

- pure unit tests for gameplay rules, state machines, inventory, progression, combat, and deterministic simulation
- asset manifest validation for missing files, duplicate IDs, invalid loader options, license metadata, texture size, and decoder requirements
- scene smoke tests for engine creation, scene load, render frame, resize, dispose, and reload
- browser tests for input, fullscreen, audio unlock, pointer lock, gamepad mapping, UI overlays, and route lifecycle
- screenshot or canvas-pixel checks for nonblank scenes, visible cameras, major UI states, and lighting regressions
- performance tests for representative scenes on target device classes

Validation should fail when:

- a scene cannot load all required assets
- a render frame is blank unexpectedly
- engine or scene disposal leaves duplicate loops or leaked observers
- asset budgets exceed documented limits
- production bundles import debug-only packages

---

# Anti-Patterns

Avoid:

- building the whole game inside one `createScene` function
- treating mesh names as the only gameplay model
- importing the entire Babylon namespace into every production module by habit
- relying on CDN scripts for production deployments
- leaving observers, GUI controls, physics bodies, or audio emitters alive after scene disposal
- creating new materials, textures, meshes, vectors, or arrays every frame in hot paths without profiling
- using render meshes as collision for complex levels
- hiding business rules in pointer handlers, animation callbacks, or material metadata
- assuming WebGPU, XR, gamepad, pointer lock, high-DPI, or audio autoplay behavior is universally available
- shipping without asset failure states, feature fallback, performance budgets, and low-end device tests

---

# Code Generation Rules

When generating Babylon.js code:

- use TypeScript when the host project supports it
- prefer ES module imports from `@babylonjs/*` packages
- include required loader and feature side-effect imports explicitly
- centralize engine and scene creation
- keep Babylon runtime objects behind clear system boundaries
- keep gameplay state serializable and testable outside Babylon
- include resize, visibility, audio-unlock, and disposal behavior
- add asset manifests instead of hard-coding many URLs
- use glTF/GLB for 3D assets unless the project documents another pipeline
- include debug tooling only behind environment gates
- include browser verification for visible 3D scenes when changing rendering behavior
