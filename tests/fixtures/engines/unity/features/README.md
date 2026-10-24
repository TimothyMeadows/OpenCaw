# Conditional Unity feature fixtures

This source fixture covers Unity content, rendering, UI, localization, audio and Editor tooling. It contains **16 native case methods: 15 eligible for automated execution and one prepared-Editor-only Package Manager case**, plus **10 supplemental native/online procedures**. The inventory and claim limits are defined in `fixture.json`.

No matching Unity Editor has been configured or executed while authoring this fixture. Compilation, player behavior and real SDK integration remain **blocked/not run**. Static checks and deterministic process/service simulations are separate evidence and cannot establish native acceptance.

## Prepare an offline fixture

Use the exact already installed Editor version and its applicable license/platform modules. The runner does not install, update, log in, accept terms, resolve packages or activate services. Preparation must be a deliberate, separately authorized action in this fixture project; ordinary validation never enables restoration to repair missing prerequisites.

1. Prepare the source project in this directory through the matching native Editor. Preserve its case scripts and author required assets through real Unity import/authoring tools. Keep prerequisite files beneath `Assets/` with their actual `.meta` identities; do not fabricate serialized YAML or binary assets.
2. Select only the needed packages at project-compatible exact versions. The prepared `Packages/manifest.json` and `packages-lock.json` must agree. Every non-builtin locked dependency must already exist in this project's `Library/PackageCache` with a matching package identity/version. Linked caches, unresolved dependencies and unsupported package sources fail or block preflight. No registry request or download is used to fill gaps.
3. Copy `fixture-config.example.json` to a JSON file in this fixture directory or the active task's resolved `.opencaw/.cache/tasks/<task>/` directory. Keep `schemaVersion: 1`, provide `settings` as nonempty string values and `packages` as selected package IDs mapped to exact versions. The example contains only builtin package inventory settings; it does not configure optional assets/packages automatically.
4. Add the selected cases' settings from [content configuration](ContentFixtures.md), [presentation configuration](PresentationFixtures.md) and [tooling/service prerequisites](ToolingServiceFixtures.md). File/asset values must be existing forward-slash `Assets/...` paths inside this fixture project. Traversal, symbolic links and external project injection are rejected. Text values identify expected behavior; they do not select or rewrite host engine/render contracts.

Package selection is explicit even when the prepared manifest already contains a dependency. The configuration's chosen package/version must match the manifest and lock. Conditional compilation symbols are enabled only after these checks; availability and API compatibility still require actual native compilation. TMP may be in an older TextMesh Pro package or the compatible Unity 6 uGUI package, so verify the real assembly/types rather than assuming one package layout.

## Run and interpret results

From the OpenCaw baseline root, set `OPENCAW_UNITY_EDITOR` to the already installed native executable, `OPENCAW_UNITY_VERSION` to its exact version and `OPENCAW_UNITY_FEATURE_CONFIG` to the prepared repository-local JSON path. Run `bash tests/test-native-engine-fixtures.sh`. Executable selections contain no embedded arguments. The standard runner also evaluates the other engines' independently configured fixtures.

`--structure-only` validates source structure and explicitly labeled process/report simulations without native launches. Default execution prints separate pass/fail/blocked/not-run verdicts. Missing Editor, configuration, package cache, authored input, graphics or platform support blocks the affected native checks. A default command can exit successfully with blocked prerequisites; inspect the verdicts and final JSON before making acceptance claims. `--require-native` requires all three base engine smoke cases, twelve Unreal features and fifteen automated Unity features to pass. It does not certify the manual Package Manager case, supplemental procedures, online services, visuals, audio or devices.

Each automated case runs in a fresh copied project beneath the test runner's owned temporary directory. The runner copies already prepared package caches, selects UNITY through the engine resolver and uses `-noUpm` to keep Package Manager disabled. It supplies fresh invocation/input identities, exact Editor version, bounded execution and separate report/log destinations. Nonzero processes, empty or incomplete assertions, mode mismatches and stale reports cannot establish success. Native execution is not an operating-system sandbox.

`OPENCAW_NATIVE_TIMEOUT_SECONDS` bounds a native invocation from 1 to 600 seconds, default 180. Timeout/cancellation terminates owned process trees. Temporary projects, logs and outputs are removed after summarization; capture the command's output and required evidence into the task record before relying on it for a handoff.

## What the automatic cases establish

| Family | Cases | Evidence boundary |
|---|---|---|
| Content and rendering | SpriteIdentity, RuleTileTopology, AtlasLifecycle, Physics3D, Physics2D, NavigationCancellation, ShaderCompilation, RenderingConfiguration | Real import, native callback, physics/path or graphics effects within the declared case. Does not certify all topology, platform variants, Physics Core, Render Graph features or artistic quality. |
| UI and localization | UIFocus, UGUIFocus, UIFontCoverage, LocalizationLifecycle | Editor-panel focus, Play Mode EventSystem/listener ownership, primary TMP character lookup and actual configured Localization SDK results. Device input, runtime UIDocument, shaping, translated layout and cold network races require further evidence. |
| Audio and Editor transactions | AudioLifecycle, EditorTransactions | Real DSP/sample progress, mixer assignment, cancellation/reuse, Undo/Redo and scene save/reload. Audibility, profiling budgets, prefab authoring and graphs remain separate. |
| Web build | WebBuild | Actual successful WebGL BuildReport and nonempty emitted player files. HTTP headers, startup, browser memory and gameplay are not tested by the build. |

`UGUIFocus`, `LocalizationLifecycle` and `AudioLifecycle` require Play Mode. In the isolated copied fixture process, the driver temporarily disables domain reload so it can own its coroutine/report state, then exits Play Mode and restores its Editor options. This does not certify the host game's normal reload settings or static initialization. No live user Editor is selected or closed.

Graphics-required cases launch without `-nographics` and require an actual supported graphics device; a null device cannot pass them. WebBuild requires the matching installed web support module and launches the copied Editor with startup target `WebGL`. It does not switch target in the middle of a batch build. A usable DSP clock/audio output remains a separate audio prerequisite, even for cases that do not require graphics.

## Prepared-Editor and supplemental acceptance

`PackageInventory` is implemented with real offline UPM listing/completion checks, but ordinary automated runs deliberately block it because `-noUpm` disables the API it needs. Use only the separately prepared, authorized Editor procedure in [ToolingServiceFixtures.md](ToolingServiceFixtures.md). Do not remove the runner's no-restoration boundary to manufacture a pass.

The ten named supplemental families are LiveServices, MultiplayerServices, VoiceChat, Purchases, Ads, ToolingCli, GraphToolkit, PhysicsCore, RenderGraphAndMigration and PlayerPresentationAndWeb. They require actual selected packages, project adapters, APIs, players and/or devices. The optional CLI/Pipeline procedure needs Unity 6.0+, the already configured CLI and project package, and explicit project/Editor-instance targeting; it is not a mandatory bridge.

Online families need a separately authorized development environment. Purchases use store sandbox/test accounts; ads use provider test mode without real ad clicks; voice uses consenting users and devices. Missing SDKs, authorization, accounts or real implementations remain blocked/not run. Deterministic synthetic service failures prove only the application-owned protocol being simulated, not Unity SDK or online acceptance.

Read the three linked family documents for exact expected/observed scenarios and artifact requirements. Preserve per-family limits when reporting success: compile/headless results cannot certify visuals, listening, accessibility, physically felt feedback or packaged gameplay.
