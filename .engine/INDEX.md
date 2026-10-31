# Game Engine Catalog

Select one engine in repository-root ENGINE.md. Unconfigured repositories default to THREEJS; conflicting existing evidence requires migration. Blender is an asset tool, not a game engine.

| Identifier | Aliases | Engine-owned language | Prerequisites |
| --- | --- | --- | --- |
| THREEJS | three.js, three | TypeScript/JavaScript, shaders | Host packages and browser tooling; automatic three.quarks particles; physics/networking explicitly selected |
| BABYLONJS | babylon.js, babylon | TypeScript/JavaScript, shaders | Host packages, browser tooling, explicit physics plugin |
| PHASERJS | phaser, phaser.js | TypeScript/JavaScript | Host-locked package major and browser tooling; Arcade or Matter |
| UNITY | unity, unity3d | Editor-compatible C# | Matching licensed Editor and platform modules; packages explicit |
| UNREAL | unreal engine, ue, ue5 | C++/Blueprint | Matching licensed Editor/compiler/SDK; optional plugins explicit |
| GODOT | godot engine, godot4 | Project-selected GDScript/C# | Matching Editor/export templates; .NET Editor/SDK for C# |

## Commands and output

`generate-engine.sh [--inline] [ENGINE]` preserves custom text outside its managed block. `resolve-engine.sh`, `resolve-skill.sh SKILL` and `resolve-role-capabilities.sh DOMAIN/ROLE` emit deterministic JSON. Incompatible skill selection emits exclusion reasons and exits nonzero. Validate with `validate-engine-contract.sh` and `validate-engines.sh`.

## Explicit task overrides

Record before producing output: `resolve-engine.sh --override UNITY --task TASK --scope prototypes/unity-demo --record-override`. An existing task and absent/empty isolated output directory are required. Consumers use `--evidence .opencaw/.cache/tasks/TASK/engine-override.json --output prototypes/unity-demo/file`. Evidence binds project/effective engine, task and contract/definition/registry hashes; its adjacent SHA-256 digest detects accidental receipt edits. Changed inputs require a new reviewed task receipt. This is cooperative validation, not an OS sandbox or an unforgeable authorization token.

## Dependencies and licensing

The baseline adds no AI model, service or paid middleware. It installs nothing and accepts no licenses. Each host supplies its selected engine and platform dependencies. Physical haptic testing needs a supported controller/mobile device; API mocks cannot prove tactile output. Optional physics libraries, glTF decoders, netcode transport, matchmaking, STUN/TURN, editor bridges and test frameworks remain explicit dependency decisions.

## Independent authorship

The six source packs informed the requested capability inventory; no source code, prose, scripts or assets were imported. The custom-licensed design-theory package is excluded from reuse. Standard design methods are independently authored. Engine APIs are checked against official, host-version-specific documentation. Prior Three.js/Babylon/Phaser architecture guidance moved within OpenCaw, with legacy redirects retained.

## Migration

Move legacy browser-engine architecture selection into ENGINE.md and retain software-structure templates separately. Never silently reinterpret a conflicting existing engine. Old skill names build-threejs-code-models, build-threejs-code-characters and review-threejs-code-characters resolve through compatibility aliases to their threejs-prefixed names; commands and artifact schemas retain their names. CODE remains Three.js-specific. No legacy test asset is restored.


## Native packages for web engines

THREEJS, BABYLONJS and PHASERJS declare `runtimeKind: web` and automatically select .NET 10 MAUI HybridWebView packaging for Windows, macOS (Mac Catalyst), Android and iOS. Any future registered web engine uses that same metadata-derived capability. MAUI remains a packaging host, never another game engine or visual pipeline. Native engines retain their own exporters.

Use `commands/web-game-package.sh` and read `docs/WEB_GAME_PACKAGING.md` in this installation. Resolution only declares the capability with unverified native readiness; explicit initialization, web-build sync, compatible SDK/workloads, signing and actual target QA precede release. Linux and TV are excluded. Linux users may independently try the Windows package with Wine or Proton, without a compatibility guarantee.

## Default Three.js particles

THREEJS declares `particleBackend: THREE_QUARKS` and automatically selects the `three.quarks` integration and `threejs-build-particles` skill. Every other engine declares a null Quarks backend and retains its own particle owner. Resolution emits the effective selection with unverified readiness, including default and valid isolated overrides; it loads or installs nothing. MAUI packaging remains independent.

Use `docs/THREEJS_PARTICLES.md` and `commands/threejs-particles.sh` for host inspection and an explicit fresh helper scaffold. Initial real-package acceptance uses `three.quarks`/`quarks.core` 0.17.1 with Three.js 0.182.0; lockfiles and actual API/renderer checks govern host readiness. No automatic version upgrade, WebGPU experiment or primitive fallback is implied.

## Default Three.js postprocessing

THREEJS derives `postprocessingBackend: PMNDRS_POSTPROCESSING`; other engines require null. Use `threejs-build-postprocessing`, `commands/threejs-postprocessing.sh` and `docs/THREEJS_POSTPROCESSING.md`. Selection loads/installs nothing. Existing WebGLRenderer/Quarks share one host clock; guarded LDR/FXAA starter requires actual WebGL2. Path tracing is separate and excluded from this default. MAUI device rendering remains unverified until actual target checks.
