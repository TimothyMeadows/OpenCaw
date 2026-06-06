# PHASERJS.md

This repository follows a **Phaser.js browser game architecture** for HTML5 games that run in desktop and mobile browsers using Phaser's scene, renderer, input, audio, animation, loader, and physics systems.

The architecture is optimized for:

- Phaser as the browser game engine foundation
- JavaScript or TypeScript game code
- explicit Scene lifecycle ownership
- asset-manifest-driven loading
- deterministic game state outside ad hoc object callbacks
- mobile-friendly 2D rendering performance
- browser input, audio, fullscreen, orientation, and visibility constraints
- testable game systems around Phaser runtime surfaces

The goal is to keep the system:

- clear about what Phaser owns and what project-specific game systems own
- organized around Scenes, systems, and asset contracts
- stable across route changes, restarts, pause/resume, and mobile browser behavior
- measurable for frame time, memory, asset load time, and input latency
- simple enough for fast iteration without turning every Scene into a hidden global object

---

# Core Architecture Rule

**Use Phaser as the runtime engine, but keep game rules, progression, save state, asset manifests, and feature systems explicit.**

Prefer:

```text
Game Config -> Boot/Preload Scene -> Gameplay Scenes -> Game Systems -> Phaser Objects
```

Avoid:

```text
one giant Scene -> all input, all state, all physics, all UI, all loading, all save behavior
```

Phaser owns the game loop, Scene lifecycle, display list, renderer, cameras, loader, texture/cache managers, input plugins, sound, animations, time, tweens, and physics integration. The project should still define its own game-state model, save data, level manifests, entity definitions, progression rules, service integration, and testing boundaries.

---

# Recommended Structure

```text
src/
  app/
    createGame.ts
    phaserConfig.ts
  game/
    scenes/
      BootScene.ts
      PreloadScene.ts
      MainMenuScene.ts
      GameplayScene.ts
      HudScene.ts
      PauseScene.ts
    systems/
      input/
      combat/
      movement/
      spawning/
      progression/
      camera/
      audio/
    entities/
    levels/
    ui/
    state/
    assets/
      manifests/
      atlases/
      audio/
      tilemaps/
  infrastructure/
  tests/
```

Keep framework integration, routing, account flows, and page shell code outside the Phaser Scene tree. Phaser Scenes should be easy to start, stop, restart, pause, resume, and test in isolation.

---

# Game Instance and Configuration

Phaser games should have one owning `Phaser.Game` instance per embedded game runtime.

Rules:

- centralize `Phaser.Game` creation in one application boundary
- keep game configuration explicit: renderer type, parent element, dimensions, scale mode, background, physics, input, plugins, pixel-art flags, and scene list
- prefer `Phaser.AUTO` when the product accepts Phaser's WebGL/Canvas selection, and document when a renderer must be forced
- avoid creating duplicate game instances during hot reload, route remounts, tab navigation, or UI framework lifecycle churn
- destroy the game instance on permanent unmounts or app shutdowns
- keep configuration environment-driven for asset base URLs, debug flags, telemetry, save endpoints, and feature gates

---

# Scene Architecture

Scenes are Phaser's primary unit of organization. Use them deliberately.

Recommended Scene roles:

- `BootScene`: minimal configuration, device checks, global registry defaults, plugin setup
- `PreloadScene`: shared assets, loading UI, asset manifests, texture/audio/font preparation
- `MainMenuScene`: menu flow and game-start routing
- `GameplayScene`: world simulation, entities, tilemaps, physics, gameplay cameras
- `HudScene`: HUD, overlays, score, timers, inventory, minimaps, prompts
- `PauseScene`: pause UI, settings, restart/quit flow
- `TransitionScene`: fades, loading bridges, or world transitions when needed

Rules:

- use `init`, `preload`, `create`, and `update` for their intended lifecycle responsibilities
- keep shared assets in boot/preload flows and scene-specific assets in the scene that uses them
- treat Scene shutdown and destroy as cleanup points for events, timers, tweens, listeners, subscriptions, and external resources
- communicate between Scenes through explicit events, scene plugins, registry values, or an application state service
- avoid reaching into sibling Scenes for hidden state unless the contract is documented
- use simultaneous Scenes for HUD, pause overlays, debug overlays, and transitions when it keeps responsibilities cleaner

---

# State and Game Systems

Phaser Game Objects are render and interaction objects, not the only domain model.

Rules:

- keep durable state such as progress, inventory, quests, unlocks, settings, player stats, save data, and analytics state in project-owned models
- keep transient simulation state in entities/components/systems or focused feature modules
- use Phaser `DataManager` for object-local or scene-local data, not as an unbounded substitute for an application model
- use the global registry sparingly for small cross-scene values such as settings, session flags, or score snapshots
- keep gameplay rules out of raw pointer handlers and animation callbacks when they belong in systems
- model entity lifecycle explicitly: spawn, activate, update, disable, recycle, destroy
- prefer finite-state machines, behavior modules, or ECS-style systems when entity behavior becomes complex

---

# Asset Pipeline

Use Phaser's Loader and cache systems through manifests and named contracts.

Rules:

- use unique, namespaced asset keys
- load shared assets in `BootScene` or `PreloadScene`
- load scene-local assets in the owning Scene and remove them when memory matters
- prefer texture atlases or multi-atlases for sprites that animate together or share draw paths
- use sprite sheets only when frame dimensions and spacing are stable
- use file packs or asset manifests for level, biome, character, UI, audio, and localization asset groups
- keep raw asset URLs out of gameplay systems
- document frame dimensions, atlas keys, animation keys, audio keys, tilemap keys, bitmap font keys, and plugin assets
- handle loader progress, completion, and errors; do not assume every asset request succeeds
- keep source art, optimized runtime exports, metadata, licensing, and generated files separate

Recommended asset manifest shape:

```text
asset key -> type -> url(s) -> frame config -> owning scene/pack -> license/source -> memory notes
```

---

# Rendering, Cameras, and Scale

Phaser is a 2D engine with strong Scene, Camera, Game Object, and Scale Manager systems. Use those systems rather than manual DOM/canvas manipulation.

Rules:

- choose a base game size intentionally and document it
- use the Scale Manager for fit, resize, expand, fullscreen, orientation, and parent-container behavior
- keep UI layout aware of `gameSize`, `baseSize`, and `displaySize`
- use cameras for world view, HUD exclusion, minimaps, follow behavior, bounds, dead zones, zoom, rotation, and screen effects
- keep world coordinates, screen coordinates, UI coordinates, and camera transforms separate
- define pixel-art rendering choices: round pixels, antialiasing, camera zoom, and texture filtering
- do not use CSS transforms as a substitute for Phaser scale/camera policy unless the embedding shell explicitly owns presentation

---

# Input Architecture

Phaser provides unified pointer, keyboard, and gamepad handling. The game should still define action mapping.

Rules:

- map raw input events to semantic game actions such as move, interact, attack, cancel, pause, select, drag, and zoom
- keep rebinding, accessibility, mobile controls, and controller mappings behind an input service
- enable Game Object input only where needed with `setInteractive`
- use Scene input plugins for local scene behavior and avoid global listeners that survive scene shutdown
- normalize pointer/touch/mouse interactions into the same gameplay commands when possible
- poll or handle gamepad state through a consistent action layer
- account for focus loss, fullscreen changes, orientation changes, and browser gestures on mobile

---

# Physics

Choose Phaser physics based on gameplay needs.

Rules:

- use Arcade Physics for fast rectangle/circle collision, platformers, top-down games, simple puzzles, and broad arcade behavior
- use Matter Physics when bodies need polygons, compound bodies, constraints, joints, sensors, or more advanced full-body simulation
- do not mix Arcade and Matter casually in the same gameplay area without an explicit bridge contract
- define world units, gravity, collision categories, static bodies, dynamic bodies, sensors, triggers, and debug overlay behavior
- keep render sprites and physics bodies synchronized through systems, not scattered callbacks
- avoid high-detail visual shapes as collision shapes
- turn off physics debug in production builds
- use fixed or bounded physics updates when gameplay correctness requires stable collision timing

---

# Animation, Tweens, and Time

Use Phaser's animation, tween, and clock systems as runtime services, with gameplay intent kept explicit.

Rules:

- define global animation keys for shared character, VFX, UI, and item animations
- keep animation state machines separate from the animation clip definitions
- use tweens for presentation, juice, UI, camera, and simple motion, not as hidden gameplay state unless documented
- use timers and delayed calls through Scene time systems so pause/resume and Scene shutdown are manageable
- document animation frame rate, loop behavior, chain behavior, interrupt rules, event timing, and hit-frame timing
- avoid creating unbounded tweens, timers, or animation chains inside `update`

---

# Audio

Use Phaser sound through an audio system that understands browser restrictions.

Rules:

- handle browser audio unlock and resume behavior from user gestures
- separate music, ambience, UI, SFX, voice, and gameplay-important sounds
- use audio sprites when they reduce request overhead and fit the content pipeline
- stop, pause, resume, or fade sounds explicitly during Scene transitions and app lifecycle events
- keep audio keys and volume/mute settings in a durable settings model
- support missing or failed audio loads gracefully

---

# Browser Platform Requirements

Browser Phaser games must define platform assumptions up front.

Required decisions:

- target browsers and devices
- desktop, mobile, tablet, embedded webview, or packaged wrapper targets
- WebGL, Canvas, or auto renderer policy
- base resolution, scale mode, orientation, fullscreen, and safe-area behavior
- input modes: keyboard/mouse, touch, gamepad, virtual controls, drag/drop
- audio unlock behavior
- save strategy: localStorage, IndexedDB, backend save, or no saves
- offline/cache strategy and asset versioning
- analytics, crash reporting, and performance telemetry boundaries
- accessibility expectations for contrast, text, remapping, reduced motion, and captions where relevant

Do not claim mobile readiness until performance, input, audio, orientation, and fullscreen behavior have been tested on representative devices.

---

# Performance Rules

Measure on target devices before and after optimization.

Rules:

- prefer atlases and batching-friendly assets over many small texture switches
- reuse objects through pools for bullets, particles, enemies, pickups, hit effects, and temporary UI where churn is high
- avoid per-frame allocation-heavy code in `update`
- avoid creating tweens, timers, graphics, textures, groups, emitters, or physics bodies repeatedly inside hot loops
- use `active`, `visible`, groups, cameras, culling, and pooling deliberately
- keep particle counts, lights, masks, blend modes, large transparent sprites, and post-FX under budget
- keep tilemap layer count, collision layer complexity, and camera effects budgeted
- disable debug rendering in production
- keep texture sizes and audio sizes appropriate for mobile memory limits
- profile frame time, draw calls where available, physics cost, loader time, memory, and GC spikes
- test Safari, Chrome, Firefox, mobile Chrome, and mobile Safari where those platforms are supported

Acceptance targets should name:

- target FPS and minimum acceptable FPS
- maximum initial load and scene-transition load time
- target base resolution and scale mode
- maximum texture/audio memory expectations
- supported input modes
- lowest supported device class

---

# Packaging and Deployment

Keep the game deployable as a browser app.

Rules:

- prefer modern bundling with explicit asset copying and hashed output
- keep Phaser imports, plugins, and examples out of production bundles unless used
- serve assets with correct MIME types, cache headers, compression, and CORS policy
- version asset manifests so cached HTML/JS and cached assets do not disagree
- keep service workers conservative unless offline play is a requirement
- keep CSP compatible with the renderer, audio, fonts, workers, asset CDN, telemetry, and embedding requirements
- define whether the game can run inside an iframe and whether fullscreen is allowed
- document packaging tradeoffs for Capacitor, Cordova, Electron, or native wrappers if browser deployment is not enough

---

# Testing and Verification

Use automated tests for systems and browser checks for runtime behavior.

Test categories:

- unit tests for pure systems: state machines, movement rules, damage, scoring, inventory, level parsing, input mapping, and save serialization
- Scene lifecycle tests for create/shutdown/restart behavior where test harness support exists
- asset manifest tests for missing keys, duplicate keys, wrong frame dimensions, and missing audio/atlas/tilemap files
- browser tests for canvas creation, nonblank render, resize/scale behavior, route mount/unmount, keyboard/pointer/touch flows, and fullscreen/orientation behavior
- visual tests for key scenes, HUD overlays, camera framing, tilemap alignment, and animation readiness
- performance smoke tests for FPS, frame time spikes, object counts, physics cost, and loader time

When Playwright is available, include a canvas nonblank check and a screenshot for critical scenes. Do not rely only on unit tests for a canvas game.

---

# Security and Safety

- Do not load arbitrary remote scripts, plugins, asset packs, or user-generated assets without trust boundaries.
- Keep API endpoints, asset hosts, telemetry, and save services configuration-driven.
- Never put secrets in client game code or source-controlled assets.
- Treat performance telemetry, device capability checks, and analytics as privacy-sensitive.
- Validate downloaded level data, save data, and user-generated content before applying it to a live Scene.
- Keep license and attribution records for asset packs, fonts, audio, plugins, and generated art.

---

# Anti-Patterns

Never introduce:

- one Scene that owns every feature forever
- duplicate `Phaser.Game` instances caused by framework remounts
- gameplay rules hidden in raw pointer callbacks, tween callbacks, or animation-complete handlers
- raw asset URLs scattered through game logic
- global registry abuse for all state
- Scene transitions that leave event listeners, tweens, timers, audio, emitters, or physics bodies alive
- unbounded object creation in `update`
- production builds with debug physics, debug graphics, or verbose loader logging enabled
- mobile support claims without real device checks
- custom rendering, scaling, or input systems that fight Phaser's built-in managers without a documented reason

---

# Reference Sources

- Phaser docs tooling: https://phaser.io/tools/phaser-docs
- Phaser getting started / what is Phaser: https://docs.phaser.io/phaser/getting-started/what-is-phaser
- Phaser Game concept: https://docs.phaser.io/phaser/concepts/game
- Phaser Scene concept: https://docs.phaser.io/phaser/concepts/scenes
- Phaser Scene API: https://docs.phaser.io/api-documentation/class/scene
- Phaser Loader concept: https://docs.phaser.io/phaser/concepts/loader
- Phaser Input concept: https://docs.phaser.io/phaser/concepts/input
- Phaser Scale Manager concept: https://docs.phaser.io/phaser/concepts/scale-manager
- Phaser Animations concept: https://docs.phaser.io/phaser/concepts/animations
- Phaser Physics concept: https://docs.phaser.io/phaser/concepts/physics
- Phaser Arcade Physics concept: https://docs.phaser.io/phaser/concepts/physics/arcade
- Phaser Matter Physics concept: https://docs.phaser.io/phaser/concepts/physics/matter
- MDN Gamepad API: https://developer.mozilla.org/docs/Web/API/Gamepad_API
- MDN Web Audio API: https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API
- MDN Web Storage API: https://developer.mozilla.org/en-US/docs/Web/API/Web_Storage_API
- MDN IndexedDB API: https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API

---

# Code Generation Rules for Agents

When generating Phaser game code:

1. Start with the Scene plan and game configuration.
2. Define asset manifests, keys, and preload ownership before referencing assets.
3. Keep gameplay state and save data outside raw Phaser Game Objects.
4. Add input mapping, physics choice, animation keys, and UI Scene boundaries explicitly.
5. Use pools or groups for high-churn objects.
6. Clean up events, tweens, timers, audio, emitters, and external subscriptions on Scene shutdown.
7. Verify canvas rendering, resize behavior, input, and representative performance in a browser.

When in doubt:

**Let Phaser run the game, but keep your game architecture explicit.**
