# THREEJS.md

This repository follows a **Three.js browser 3D architecture** for interactive WebGL/WebGPU-backed scenes, games, simulations, visualizers, and browser-native 3D experiences.

The architecture is optimized for:

- Three.js as the rendering layer
- TypeScript or JavaScript browser applications
- explicit game/runtime subsystem boundaries
- glTF-first asset delivery
- deterministic simulation where gameplay requires it
- measurable browser and mobile performance
- safe lifecycle management for GPU resources
- graceful degradation across browser/device capability differences

The goal is to keep the system:

- clear about what Three.js owns and what the application engine owns
- maintainable as scenes, assets, and gameplay systems grow
- resilient to browser lifecycle, resize, input, audio, and GPU-context behavior
- testable without relying only on visual inspection
- practical for turning Three.js from a renderer into a browser game runtime

---

# Core Architecture Rule

**Treat Three.js as the renderer and scene graph, not as the full game engine. Build explicit engine subsystems around it.**

Prefer:

```text
Game State / ECS -> Simulation Systems -> Render Sync -> Three.js Scene -> WebGL/WebGPU
```

Avoid:

```text
Three.js Object3D tree -> all gameplay state, input rules, physics, networking, audio, and persistence
```

Three.js should own renderable objects, cameras, lights, materials, geometries, animation playback, ray queries, and renderer integration. Gameplay identity, rules, physics state, inventory, quests, AI, combat, save data, and networking state should live in application-owned systems.

---

# Advisory Structure Example

ARCHITECTURE.md owns software structure; adapt this example to its contract.

```text
src/
  app/
  engine/
    loop/
    time/
    input/
    assets/
    audio/
    physics/
    ecs/
    scenes/
    rendering/
    scripting/
    persistence/
  game/
    entities/
    components/
    systems/
    levels/
    ui/
  infrastructure/
  tests/
```

Framework integrations such as React, Vue, Angular, Next.js, or SPA routing should stay at the application boundary. Do not let UI component lifecycles secretly own core game state unless the project intentionally uses a wrapper such as React Three Fiber and documents that ownership model.

---

# Rendering Boundary

Rendering code should be isolated behind a small engine-facing API.

Responsibilities:

- create and configure `WebGLRenderer` or an explicitly selected `WebGPURenderer`
- own the canvas, scene, camera, render targets, post-processing, and XR renderer hooks
- handle viewport resize, device pixel ratio caps, camera aspect updates, and render target resizing
- map game state into Three.js objects without making those objects the source of truth
- dispose geometries, materials, textures, render targets, controls, and loaders when scenes unload

Rules:

- prefer `WebGLRenderer` for broad compatibility unless WebGPU requirements and fallback behavior are documented
- cap pixel ratio on mobile and thermally constrained devices instead of blindly rendering at full device resolution
- use `renderer.setAnimationLoop` when XR or renderer-managed loop integration is needed
- use `requestAnimationFrame` or a renderer animation loop only as the frame scheduling mechanism, not as the whole engine architecture
- centralize render layers, cameras, raycast layers, shadow settings, tone mapping, color management, and post-processing passes
- handle WebGL context loss and restoration where the product cannot tolerate a blank canvas

---

# Game Loop and Time

Browser games need a deliberate timing model.

Rules:

- separate frame scheduling, simulation update, physics stepping, animation update, and rendering
- use a fixed timestep for physics and deterministic gameplay logic when collisions, combat timing, replays, or multiplayer correctness matter
- cap catch-up steps to avoid spiral-of-death behavior after tab throttling, device sleep, slow frames, or debugger pauses
- interpolate render transforms from the latest simulation state when fixed simulation and variable rendering are both used
- pause or degrade updates on `visibilitychange`, focus loss, route changes, modal overlays, and battery-sensitive states
- keep frame delta clamped before passing it to animation or camera smoothing code

Recommended flow:

```text
browser frame -> collect input -> fixed simulation steps -> sync render objects -> render scene
```

Use on-demand rendering only for static scenes, configurators, editors, or product viewers. Games with animation, physics, AI, networking, or real-time input generally need a continuous loop while active.

---

# Engine Subsystems

When Three.js is used as a browser game engine foundation, define these subsystems explicitly.

## Entity and State Model

- Prefer an ECS, data-oriented model, or explicit entity/system architecture for medium or large games.
- Keep gameplay state serializable and independent from Three.js object instances.
- Store references from gameplay entities to render handles, not the other way around.
- Avoid putting rules into `Object3D.userData` except for bridge metadata, debug tags, or stable IDs.

## Input

- Centralize keyboard, pointer, touch, gamepad, and virtual-control handling.
- Use Pointer Lock only for camera-control modes that need unconstrained mouse deltas, and provide fallback controls where support or user permission is unavailable.
- Poll Gamepad API state in the game loop and normalize button/axis mappings into game actions.
- Keep raw browser input events separate from gameplay commands so rebinding, accessibility, and replay tools remain possible.

## Physics and Collision

- Treat physics as a separate world with its own bodies, colliders, timestep, and synchronization step.
- Sync physics transforms into Three.js meshes after simulation, not during random render code.
- Use fixed steps for physics and cap substeps.
- Keep collision layers, triggers, raycasts, character controllers, slope rules, and world units documented.
- Prefer broad-phase-friendly static collision meshes over high-poly render meshes.

## Animation

- Use `AnimationMixer` for glTF clips and Three.js animation playback, but keep animation state machines in game/application code.
- Separate clip loading, action selection, blend rules, root motion policy, and gameplay events.
- Document whether movement is animation-driven, physics-driven, or gameplay-controller-driven.

## Audio

- Use Web Audio or Three.js audio wrappers behind an audio service.
- Require user gesture handling for audio unlock and resume behavior.
- Attach one listener to the active camera for positional audio unless the game documents another listener model.
- Keep music, ambience, UI, SFX, voice, and spatial audio buses or groups separate.

## Assets and Loading

- Prefer glTF/GLB for runtime 3D asset delivery.
- Use `GLTFLoader` with `LoadingManager` for progress, error handling, and grouped loading states.
- Support Draco, Meshopt, and KTX2/Basis texture compression only when decoder hosting, CDN paths, browser support, and fallback behavior are documented.
- Keep source assets, optimized runtime assets, thumbnails, metadata, and license records separate.
- Load by manifest or asset registry rather than scattering raw URLs through gameplay code.
- Validate missing assets, failed decoders, network errors, and partial-load states.

## Scene and Level Management

- Treat levels/scenes as lifecycle-managed modules: load, activate, pause, unload, dispose.
- Avoid long-lived hidden Three.js objects after scene transitions.
- Separate world content, UI overlays, debug helpers, cameras, lights, and transient effects.
- For large worlds, define chunking, streaming, LOD, visibility, and origin/rebasing policies before content scale grows.

## UI and Overlays

- Keep DOM/UI framework state separate from render-loop state.
- Avoid expensive DOM layout work inside the render loop.
- Define how screen-space labels, HUD, minimaps, tooltips, and in-world markers map between 3D coordinates and UI layers.
- Test pointer capture, focus, accessibility, and mobile touch behavior with both canvas and DOM overlays present.

---

# Asset Pipeline

Use an explicit asset contract before production content grows.

Recommended asset contract:

- format: GLB/glTF, texture formats, compression, and decoder requirements
- scale: world units, origin, pivot, bounds, forward/up axis, and collider proxy
- materials: PBR expectations, unlit materials, transparency policy, color space, and texture channels
- animation: clip names, loop flags, root motion policy, additive clips, and events
- variants: skins, LODs, damage states, impostors, and platform-specific reductions
- metadata: license, source file, export tool/version, optimization step, and owning feature

Rules:

- optimize for runtime delivery, not DCC convenience
- reuse geometries, materials, and textures when possible
- atlas, instance, merge, or LOD repeated content before adding more assets
- avoid high-poly render meshes as collision geometry
- keep texture sizes, shadow casters, transparency, post-processing, and skeletal counts under measured budgets

---

# Performance Rules

Measure first, then optimize the largest bottleneck.

Rendering rules:

- minimize draw calls through instancing, batching, geometry merging, material reuse, and atlas strategies
- use `InstancedMesh` or instanced glTF data for repeated objects
- use LODs, impostors, culling, and visibility layers for large scenes
- keep shadow maps, transparent materials, post-processing, and real-time lights budgeted
- avoid per-frame geometry/material/texture creation
- dispose GPU resources when no longer needed
- prefer compressed textures and optimized meshes for web delivery
- tune pixel ratio and render resolution before sacrificing core gameplay responsiveness

Browser rules:

- profile on target browsers and devices, especially mobile Safari/Chrome and integrated GPUs
- account for tab throttling, thermal throttling, battery impact, low-memory devices, and context loss
- use Web Workers or OffscreenCanvas only when the threading model, browser support, fallback, and message protocol are defined
- avoid blocking asset parsing, decompression, pathfinding, generation, or AI work on the main thread when it causes frame drops

Acceptance targets should name:

- target FPS and minimum acceptable FPS
- max load time and interactive time
- max texture memory or approximate GPU memory budget
- draw-call, triangle, light, shadow, particle, and skeleton budgets where relevant
- target devices and browsers

---

# Browser Platform Requirements

Three.js game architecture must document browser-facing requirements.

Required decisions:

- legacy WebGL 1 (only with a deliberately locked pre-r163 version; current WebGLRenderer requires WebGL 2), WebGL 2, or WebGPU renderer support and fallback path
- desktop, mobile, tablet, XR, or embedded-webview targets
- input modes: keyboard/mouse, touch, pointer lock, gamepad, virtual joystick, XR controllers
- audio unlock/resume behavior
- fullscreen, orientation, viewport, and responsive canvas policy
- persistence: localStorage, IndexedDB, backend saves, or no saves
- worker/offscreen support and fallback
- asset CDN/cache/versioning strategy
- privacy and telemetry boundaries for performance diagnostics

Do not assume every browser supports every game feature. Gate features by capability checks and keep unsupported states user-friendly.

---

# Testing and Verification

Use automated and manual checks appropriate for visual/browser runtime risk.

Test categories:

- unit tests for pure game systems, math, state machines, input mapping, asset manifests, and simulation rules
- integration tests for loader manifests, scene lifecycle, resource disposal, and physics/render sync
- browser tests for canvas creation, route lifecycle, resize behavior, input flows, audio unlock, and no-blank-canvas regressions
- visual or screenshot tests for camera framing, lighting, UI overlays, and important scenes
- performance smoke tests for FPS, frame time spikes, draw calls, asset load time, and memory trends
- target-device tests for mobile/touch, integrated GPUs, and browser-specific behavior

For 3D browser apps, Playwright verification should include screenshots and canvas-pixel checks when a blank or misframed render would be user-visible.

---

# Security and Safety

- Do not load arbitrary remote models, textures, shaders, or scripts without trust boundaries and CORS/content-security review.
- Keep asset URLs, decoder paths, save endpoints, telemetry endpoints, and multiplayer endpoints configuration-driven.
- Avoid putting secrets, privileged API tokens, or protected content in client assets.
- Validate user-generated or downloadable content before adding it to a scene.
- Treat WebGL fingerprinting, performance telemetry, and device capability collection as privacy-sensitive.

---

# Anti-Patterns

Never introduce:

- gameplay logic hidden in random `Object3D` callbacks or `userData`
- frame-rate-dependent physics, combat, cooldowns, or movement
- asset URLs scattered across components and systems
- scene transitions that leave geometries, materials, textures, audio nodes, or event listeners alive
- one giant scene module that owns input, physics, loading, rendering, UI, and gameplay rules
- unbounded particle systems, dynamic lights, transparent materials, or post-processing chains
- high-poly visual meshes used directly as collision geometry
- per-frame allocation-heavy code in hot loops
- mobile support claims without testing on real or representative devices
- calling Three.js a complete game engine without defining missing subsystems

---

# Reference Sources

- Three.js documentation and manual: https://threejs.org/docs/
- Three.js responsive rendering guidance: https://threejs.org/manual/pages/responsive.html
- Three.js cleanup guidance: https://threejs.org/manual/pages/cleanup.html
- Three.js rendering-on-demand guidance: https://threejs.org/manual/pages/rendering-on-demand.html
- Three.js physics integration guidance: https://threejs.org/manual/pages/physics.html
- Three.js OffscreenCanvas guidance: https://threejs.org/manual/pages/offscreencanvas.html
- Three.js color management guidance: https://threejs.org/manual/pages/color-management.html
- Three.js GLTFLoader documentation: https://threejs.org/docs/pages/GLTFLoader.html
- Three.js LoadingManager documentation: https://threejs.org/docs/pages/LoadingManager.html
- Three.js WebGLRenderer documentation: https://threejs.org/docs/pages/WebGLRenderer.html
- Three.js optimize-lots-of-objects guidance: https://threejs.org/manual/pages/optimize-lots-of-objects.html
- MDN WebGL best practices: https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices
- MDN Pointer Lock API: https://developer.mozilla.org/en-US/docs/Web/API/Pointer_Lock_API
- MDN Gamepad API: https://developer.mozilla.org/docs/Web/API/Gamepad_API
- MDN Web Audio API: https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API
- MDN OffscreenCanvas: https://developer.mozilla.org/docs/Web/API/OffscreenCanvas
- MDN Web Workers: https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API/Using_web_workers

---

# Code Generation Rules for Agents

When generating Three.js browser game code:

1. Start with engine subsystem boundaries, not with a monolithic scene file.
2. Define renderer, loop, input, assets, scene lifecycle, and game-state ownership before adding content.
3. Keep simulation/game state independent from Three.js objects.
4. For explicitly selected file-based assets, use glTF/GLB manifests and loading services; STYLE.md controls authoring and CODE uses procedural source as its primary mesh.
5. Cap and test device pixel ratio, resize behavior, and mobile performance.
6. Dispose resources on unload and scene transitions.
7. Add browser verification for nonblank rendering, interaction, resize, and representative performance.

When in doubt:

**Let Three.js render the world; let your application engine own the game.**


## Engine contract ownership

This engine definition owns engine APIs and engine-owned language requirements. ARCHITECTURE.md owns software structure; STYLE.md owns art production. Resolve ENGINE.md before selecting feature skills. Use host-locked versions and explicit project dependencies; do not install packages or use implicit CDNs. Engine selection never selects an art pipeline. Browser QA requires an actual browser build. Native backend services retain their own architecture.

## Native web-game packaging

This web engine automatically selects the MAUI packaging profile through the engine registry. Keep the game in its host-locked JavaScript/TypeScript toolchain and supply its static production HTML/JS/CSS/assets to the local .NET 10 HybridWebView host. MAUI packages the web build; it does not replace this engine or select an art pipeline.

Use `commands/web-game-package.sh` and read `docs/WEB_GAME_PACKAGING.md` in the shared Hephaera installation. Official targets are Windows, macOS through Mac Catalyst, Android and iOS. Selection performs no installation, scaffold, restore, build, signing or publication. Explicitly initialize/sync the host, inspect prerequisites, then build/package on a compatible host with project-specific identity and signing. Keep runtime/device testing and external store release separate. Linux and TV are not native targets; Wine/Proton compatibility of the Windows build remains unverified until actually tested.

## Default particle and VFX library

THREEJS automatically selects `three.quarks` through registry `particleBackend: THREE_QUARKS`. Resolve the engine and `threejs-build-particles` before particle work. Use the host-owned helper under `.engine/threejs/particles/` and read `docs/THREEJS_PARTICLES.md` from the shared installation for dependency inspection, explicit scaffold, lifecycle and actual target checks. Engine selection declares the default; it never installs, imports or upgrades project packages. Other engines retain their own particle implementations.

The initial verified pair is `three.quarks` 0.17.1 with `quarks.core` 0.17.1 and Three.js 0.182.0. The upstream peer minimum is Three.js 0.182.0; the host lockfile must bind the resolved core version/integrity because its upstream dependency range is wildcard. These are tested compatibility facts, not permission to replace an existing host lock. Report missing or incompatible prerequisites rather than using an older primitive backend or upgrading Three.js silently.

Use the established `WebGLRenderer` integration. The separate experimental `quarks.nodes` package and WebGPU path are not selected by this default; choosing `WebGPURenderer` does not prove Quarks support or authorize a renderer switch. Maintain one scene-owned batch renderer and the host presentation clock, with finite emission/lifetime/system budgets, cancellation, pause/resume and explicit resource ownership. Effects and completion callbacks never decide gameplay outcomes. Actual browser/GPU and MAUI WebView/device evidence remains separate from CPU/library and source checks.

New Three.js particle production uses Quarks. Historical pinned Bubo motion/action sample adapters retain their original point-based implementations and review ancestry; they are not automatically migrated or relabeled as this backend. Integrate new Quarks effects through compatible host owners and review any legacy adapter migration explicitly.

## Default postprocessing backend

Use pmndrs `postprocessing` via `threejs-build-postprocessing` for new fullscreen effects. Read `docs/THREEJS_POSTPROCESSING.md` and the bounded runtime README. Inspect host locks and explicitly scaffold if needed through `commands/threejs-postprocessing.sh`. Share the actual WebGLRenderer/presentation clock with Quarks; use one final composer render, finite DPR/physical pixel/effect budgets, owned teardown and suspend/context-loss controls. Actual WebGL2/MAUI device, color and performance evidence is separate. No automatic package install/Three upgrade, WebGPU, path tracing or heavy effect selection. HDR and custom passes need separately reviewed profiles; never silently fall back.
