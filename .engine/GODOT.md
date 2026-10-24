# GODOT

## Ownership and prerequisites
Use the project-selected Godot version and renderer, matching export templates and explicit platform SDKs. Preserve the project's GDScript/C# choice. C# requires the .NET-enabled Editor and compatible SDK; a standalone .NET installation does not substitute for that Editor. Godot is MIT-licensed; dependencies and asset licenses remain separate.

## Languages and platform limits
Use version-compatible GDScript, Godot shader language or engine-compatible C#. Engine-owned Node/Resource lifecycles and signals take precedence over generic service patterns. Confirm the selected version's export support: current stable Godot 4 documentation excludes C# web export; mobile C# support has additional restrictions. Do not silently translate C# to GDScript or change engines. Standalone services retain their own architecture.

## Feature boundaries
Compose scenes/nodes/resources with stable UIDs and import metadata. Bound autoload ownership, signal subscriptions and deferred deletion. Select 2D/3D physics bodies, navigation and avoidance ownership, multiplayer peer/transport, animation tree, Control UI and audio buses explicitly. Preserve runtime vs imported source separation and exported resource inclusion.

## Verification and limitations
Record Editor/SDK/template versions. Run imports and project-owned test scenes or SceneTree harnesses with explicit nonzero failure codes. --check-only parses a selected script; it does not test the whole project. --test runs engine tests only in appropriately built engines and is not a project test runner. Export and launch a tiny target build, capture runtime errors and rendered/input evidence separately from headless checks. The built-in script profiler does not measure C# scripts.

## Official references
- [Command line](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
- [C# and platform support](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/index.html)
- [Input and vibration](https://docs.godotengine.org/en/stable/classes/class_input.html)
- [License](https://godotengine.org/license/)
