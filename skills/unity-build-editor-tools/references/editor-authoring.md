# Authoring transactions and graph boundaries

## Assembly and serialization boundary

Place Editor code in an Editor-only assembly or the appropriate `Editor` folder. Assembly definitions explicitly declare Editor platforms and selected package references. Runtime assemblies must not depend on `UnityEditor`, an Editor UI namespace or a graph-authoring assembly. A successful Editor compile does not establish player stripping, AOT or platform compatibility.

For an inspector, `SerializedObject.Update` reads current state, serialized-property fields handle supported edits, and `ApplyModifiedProperties` commits them. UI Toolkit binding should use the target serialized object/property path; IMGUI should display mixed values for multi-selection. Do not repeatedly assign one target's value across every selected object during repaint. Use runtime validation for invariants needed in players; Editor-only validation does not enforce them in production.

For changes outside serialized properties, record the specific objects before mutation. Use dedicated Undo APIs for object/component creation, parenting and destruction. Record prefab instance modifications where required. Mark and save only changed assets/scenes; calling a global save cannot substitute for identifying ownership. Group a coherent operation while keeping cancellation and recovery boundaries explicit.

## Lifetime and long work

Window state may survive layout reload, but a live callback's owner may not. Register once and detach the same delegates in `OnDisable` or the supported lifecycle. Stop owned scheduled callbacks and invalidate late results on close, selection replacement or assembly reload. Snapshot data on the main thread before worker computation; asset and scene writes return to supported Editor-thread APIs.

For a multi-asset job, discover candidates first, validate paths and show a change summary. Capture the owned set and original values before writes. Use progress/cancel APIs and `try/finally` to remove UI/progress hooks and end asset-editing scopes. Avoid leaving `AssetDatabase.StartAssetEditing` active after exceptions. Cancellation reports completed and untouched items honestly, with a recoverable partial state.

## Graph Toolkit

Graph Toolkit's API and release channel vary with Editor/package versions. Check package availability and its exact compatibility before selecting it. In particular, do not translate examples written for Unity 6.6/6.7 into a Unity 6.0 project or assume older experimental GraphView APIs are equivalent.

Define serialized graph/node/port identities, connection rules and diagnostics. Compile or interpret a validated graph through an explicitly designed runtime-safe representation. Document ordering, cycles, deterministic output, data version and migration. Editor tooling cannot ship a reference to an Editor-only graph class in the player. Reopen, undo connection changes and regenerate data twice to verify identity and determinism. If the actual API is unavailable, block that authoring path rather than silently replacing the project's graph framework.

## Native checks

Exercise edits on a disposable project-owned asset or scene. Check undo and redo values, persist, unload/reload, and verify references and IDs. Check two inspected objects with different values, prefab overrides, invalid values, cancelled batches and repeated window closure. Require a target-player compile for the runtime boundary and graphics-enabled Editor evidence for interaction and layout; source inspection proves neither.

Official references:

- [SerializedObject](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/SerializedObject.html).
- [Undo](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Undo.html).
- [UI Toolkit custom inspectors](https://docs.unity3d.com/6000.0/Documentation/Manual/UIE-HowTo-CreateCustomInspector.html).
- [Graph Toolkit 0.4 documentation](https://docs.unity3d.com/Packages/com.unity.graphtoolkit@0.4/manual/index.html). This channel is experimental; select the installed package's exact documentation rather than updating to match it.
