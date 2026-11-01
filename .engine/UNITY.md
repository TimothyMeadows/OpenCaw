# UNITY

## Ownership and prerequisites
Use the exact Editor version in ProjectSettings/ProjectVersion.txt, selected platform modules and applicable Unity licensing. Preserve Packages/manifest.json and package lock selections. Do not install the Editor, accept terms, add services or packages automatically. A browser/editor bridge is optional and must be explicitly configured.

## Language and runtime
Engine-owned scripts use the Editor-supported C# compiler, API compatibility level, Mono/IL2CPP and target restrictions. Unity's scripting environment is not the standalone Hephaera .NET 10 runtime; do not add unsupported runtime APIs or language features. Separate runtime assemblies, Editor assemblies, tests and native plugin boundaries. Backend services keep their own architecture/runtime contracts.

## Feature boundaries
Use scenes/prefabs, serialized components, ScriptableObjects and stable .meta GUIDs. Binary imported assets and scenes need actual Editor import/validation. Select the Input System or existing input stack, navigation implementation, render pipeline, uGUI or UI Toolkit explicitly. Netcode guidance targets explicitly selected Netcode for GameObjects; transport, relay and matchmaking are separate choices. Keep simulation authoritative and presentation/haptics cancellable.

## Verification and limitations
Run project-owned build entrypoints and the selected Test Framework through the matching Editor. Record target, Editor/package versions, build report, test XML, logs, exit code and player smoke evidence. Avoid concurrent Editor writes to one project. Batchmode or nographics cannot certify rendered UI; browser QA can inspect a Unity web build but cannot certify native UI. Profile actual target budgets rather than assuming universal 60 FPS.

## Project discovery and feature ownership

Resolve the effective engine and every selected skill before edits or tool launches. Inspect `ProjectSettings/ProjectVersion.txt`, `Packages/manifest.json` and its lock, assembly definitions, Graphics/Quality settings, scene/build configuration, target modules and installed tooling as data. Record requested versus actually resolved package versions and explicit unknowns; a package identifier in a manifest does not establish a usable SDK, license or supported API. Store project/task observations under the resolved `.hephaera/.cache/`; do not create another selector or project context authority.

Select the actual render pipeline and per-quality overrides, physics dimension/system, input stack, uGUI/UI Toolkit, navigation and content delivery. Classic Rigidbody2D, newer Physics Core APIs/components and 3D PhysX are distinct paths. New Graph Toolkit, reflected Shader Graph and 2D rendering APIs require their documented Editor/package versions; preview APIs require an explicit project decision. Do not upgrade, change render pipelines or add packages to make a recipe fit.

The focused Unity owners divide 2D import/atlas/Tilemap production, localization, rendering configuration, native Editor tools and web optimization. Scene ownership retains navigation; materials retain shader implementation; runtime UI retains input/focus/HUD ownership; Editor graph UI does not supply runtime execution. Preserve stable asset/sprite identifiers, prefab relationships and unrelated application listeners when adapting content. Render-pipeline migration and content/player build ordering require explicit scope and actual target evidence.

## Tooling and optional integrations

Native Editor batch methods remain supported. Unity CLI and the `com.unity.pipeline` bridge are optional configured tools, not startup requirements or implicit installation/update permission. Bind every live operation to the approved project and Editor instance, inspect the installed command schema, await terminal job results and detect Safe Mode, modal blocks and disconnected instances. Never borrow another project's Editor, launch competing writers, retry an ambiguous mutation blindly or upload diagnostics automatically. A local bridge executes with its process privileges; it is not an operating-system sandbox.

NGO remains the explicitly selected gameplay replication owner. Multiplayer session discovery, matchmaking, Relay and hosting are separate optional service choices; a session alone does not synchronize gameplay. Do not substitute Netcode for Entities or recommend retired hosting as a default. Live services, Vivox, purchases and LevelPlay require their own selected packages, accounts, environments, permissions and budgets. Skill activation never links accounts, deploys resources, accepts service terms, enables telemetry or authorizes payments/ad traffic. Server signing secrets and authoritative entitlement/reward validation stay outside the client.

Cloud-hosted modules follow the service-supported standalone runtime and backend architecture, not Unity's player scripting profile or Hephaera's .NET 10 CLI target. Preserve explicit credentials/environment handling, idempotence, cancellation, reconnect and source-owned cleanup across service callbacks.

## Conditional evidence

Keep native Editor/API results, player/render/device observations, offline protocol simulations and manual online acceptance procedures distinct. A missing Editor, SDK, package, real asset or approved development service blocks that family. Empty discovery, incomplete reports, stale run identities or unsuccessful native processes cannot establish success. Native batch/headless checks do not prove visual appearance, audible output, physical haptics, browser delivery or an online transaction. Retain failed evidence and record environment, versions, expected/observed behavior, output hashes and scoped limits.

## Official references
- [Unity compiler](https://docs.unity.com/en-us/engine/6000.3/manual/programming-environment/overview-of-dot-net-in-unity/csharp-compiler)
- [API compatibility](https://docs.unity.com/en-us/engine/6000.3/manual/programming-environment/overview-of-dot-net-in-unity/dotnet-profile-support)
- [Editor command line](https://docs.unity3d.com/6000.3/Documentation/Manual/EditorCommandLineArguments.html)
- [Licensing](https://unity.com/products/unity-personal)
