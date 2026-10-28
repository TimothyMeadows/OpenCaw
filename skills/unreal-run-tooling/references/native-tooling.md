# Native build, editor and test ownership

Record the actual engine association/build ID, source/binary distribution, `.uproject`, target, configuration, platform SDK and plugin/module graph before launching tools. Reviewed documentation links select 5.8; they do not force a project upgrade. Native compilation remains not-run when the matching Unreal installation or compiler is unavailable.

## Module and extension boundaries

`ModuleRules` in `.Build.cs` declares module visibility/dependencies; `TargetRules` selects build behavior. Add only dependencies used by the feature. Export public C++ interfaces with the owning module's API macro; reflected public headers must be processed by UHT. Do not fix a missing include by exposing Editor dependencies to a runtime module.

Keep `UnrealEd`, asset factories, details customizations and editor asset tooling in an Editor module/target. Package the game target as well as compiling the Editor target to detect accidental `WITH_EDITOR` leaks. `WITH_EDITORONLY_DATA` protects data layout where appropriate; it is not a substitute for correct module separation.

For an editor tool, register commands/menus/customizations in module startup and release every handle, tab spawner and delegate during shutdown. Do not capture a raw editor object across hot reload, map closure or an asynchronous callback. Operate on the selected scope; opening an extension does not authorize checkout, package resaves, source-control submission or publication.

For undoable edits, use `FScopedTransaction`, call `Modify()` on each affected transactional object before changes, and send the appropriate property/edit notifications. Distinguish transient preview state from saved package changes. Verify undo and redo restore references and child objects; a transaction does not by itself save a package. Save only intended packages using supported Editor APIs, with explicit handling of read-only files or cancelled dialogs.

## Tests and diagnostic evidence

Use Unreal Automation tests for engine-level assertions and selected Functional tests for world/actor behavior. CQTest is an optional bundled test module: inspect availability and add it explicitly only when chosen. It is not a required external framework. Do not assume sample-specific Lyra helpers exist in another project.

Give each run a new output directory. Bind the report to project/source fixture hashes, engine identity, exact test filter, configuration and run start/end. Require discovery of the expected cases and a terminal success result for each, consistent with process exit. An empty test list, a stale `index.json`, a timed-out process or a missing test is a failed evidence contract; do not convert it into a pass. Retain failing logs and distinguish unsupported/missing prerequisites from tested failures.

Select diagnostics from the problem: log categories and scoped traces for lifecycle, Unreal Insights for scheduling/CPU/allocation, GPU profiling for rendering, and memory/reference tools for retention. State capture overhead and target configuration. A NullRHI run can validate some CPU/asset logic, not final materials, audio output, physical haptics or camera comfort.

Validate build, Blueprint compile, cook, stage, package and launched-player behavior separately. A successful Editor build does not establish that dynamically loaded assets were cooked or an exported player starts on the target device. Keep tools bounded and terminate only their owned process tree.

## Official references

- [Unreal modules](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-modules?application_version=5.8)
- [Module build rules](https://dev.epicgames.com/documentation/en-us/unreal-engine/module-properties-in-unreal-engine?application_version=5.8)
- [FScopedTransaction](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Editor/UnrealEd/FScopedTransaction?application_version=5.8)
- [UObject::Modify](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/CoreUObject/UObject/Modify?application_version=5.8)
- [Automation test framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/automation-test-framework-in-unreal-engine?application_version=5.8)
- [CQTest](https://dev.epicgames.com/documentation/en-us/unreal-engine/cqtest-test-framework-for-unreal-engine?application_version=5.8)
- [Unreal Insights](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-insights-in-unreal-engine?application_version=5.8)
