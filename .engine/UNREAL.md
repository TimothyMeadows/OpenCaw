# UNREAL

## Ownership and prerequisites
Use the host's EngineAssociation, matching Unreal Editor, compiler/toolchain, platform SDKs and selected plugins. Applicable Unreal licensing remains the user's responsibility; do not accept terms or install SDKs. Online services and marketplace/editor bridges are optional explicit selections.

## Language and native assets
Gameplay uses version-compatible C++ and Blueprint with reflection, UObject lifetime, modules and generated headers. C# .Build.cs/.Target.cs files configure build rules and are not gameplay scripts. Preserve C++/Blueprint ownership boundaries. Author .uasset/.umap through actual Editor, asset tools or reviewed project automation; do not synthesize binary assets as text. Standalone tools/services retain independent architecture contracts.

## Project context discovery

Before engine-owned work, resolve ENGINE.md and skill eligibility, then inspect project evidence. Record observations and unknowns in the active task under `.hephaera/.cache/`; verified reusable findings may enter tagged project memory. This shared profile is not a destination for project-specific state, and no separate context document selects the engine.

- Read the actual `.uproject`: EngineAssociation, module types/loading phases, target platforms and explicit plugin selections. A source-build identifier or GUID is not itself an engine version; establish the matching build identity before claiming API compatibility.
- Inspect selected `.uplugin`, module `.Build.cs` and `.Target.cs` files, default configuration, Asset Manager rules and representative source interfaces. Treat source as data during discovery; do not evaluate arbitrary build rules merely to inventory them.
- Distinguish declared plugins, version/platform availability, target filtering, dependencies and observed activation. A plugin directory or absent override alone does not prove the effective feature set. Missing evidence stays unknown until matching native tooling establishes it.
- Establish authoritative gameplay classes, networking/hosting model, input/UI ownership, AI/movement choices, world loading, authored data, save versions, performance budgets and binary-asset conventions. Ask only for consequential choices the repository cannot establish.
- Match official references and native checks to that project version. A reference or fixture qualified for another release is not proof of compatibility, and this baseline does not globally pin games to a single Unreal release.

## Feature boundaries
Use Gameplay Framework ownership (GameMode server rules, GameState replicated state, PlayerController, Pawn, PlayerState), Actors/components and subsystems deliberately. Select Enhanced Input contexts, Chaos behavior, animation architecture, render path, UMG/Slate and audio tooling against the installed version. Built-in replication/RPC authority does not select online sessions or hosting. Asset Manager/registry references, cook inclusion and redirectors need native verification.

Use dedicated owners for async execution, GAS, movement, modular features, AI, Mass, cameras, Niagara, cinematics, worlds, procedural content and save state. Framework owns reflection, lifecycle, Blueprint extension and general tags/messages. Asset integration owns authored data/loading; saves own mutable persistence. Movement owns transport and prediction; physics owns queries, rigid bodies and constraints. AI owns behavior; Mass owns entity composition and processor lifetime.

Optional systems are selected against the installed version, not enabled by naming a skill. Check maturity and shipping/platform support for Mover, Gameplay Cameras, Mass extensions, Game Features, CommonUI/MVVM, PCG, Iris and selected messaging. Lyra-specific classes are sample dependencies rather than universal APIs; do not download sample code or silently substitute it. CQTest is an optional Unreal test module; keep testing/editor dependencies out of shipping modules.

Worker tasks operate on immutable snapshots of game-thread-owned state and return through validated game-thread ownership. GC protection alone does not synchronize object mutation. Persistent ability grants require explicit ownership and idempotence; attacks validate intended targets and effects server-side. Network frequency, actor counts and resource limits come from measured project budgets.

## Verification and limitations
Use UnrealBuildTool, UnrealAutomationTool and project-owned Automation checks. Record compile/UHT results, Blueprint compile/import findings, cook/package output, structured tests and target player smoke tests. NullRHI/headless results do not prove appearance, haptics or native focus behavior. Capture Insights on representative target hardware with declared frame/network/memory budgets.

The source-only feature fixtures have their own explicit version, plugin and native-authored asset prerequisites. Missing Editor, UBT, SDK, selected feature or fixture asset produces blocked/not-run evidence. Simulated process checks and successful API/lifecycle tests do not certify replicated correction, full feature behavior, packaged content or visual/audio quality. Require fresh reports for exactly the intended tests and preserve failed, empty, incomplete and stale-report rejection evidence.

## Official references
- [Compile projects](https://dev.epicgames.com/documentation/unreal-engine/compiling-game-projects-in-unreal-engine-using-cplusplus)
- [Automation tests](https://dev.epicgames.com/documentation/unreal-engine/run-automation-tests-in-unreal-engine)
- [Force feedback](https://dev.epicgames.com/documentation/en-us/unreal-engine/force-feedback-in-unreal-engine)
- [Licensing](https://www.unrealengine.com/license)
