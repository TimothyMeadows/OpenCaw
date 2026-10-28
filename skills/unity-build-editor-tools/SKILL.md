---
name: unity-build-editor-tools
description: Author Unity inspectors, Editor windows and selected graph tools with undo, serialization and runtime separation.
engines: [UNITY]
---

# Unity Build Editor Tools

## When to use

Build or repair Unity authoring tools: custom inspectors, property drawers, IMGUI/UI Toolkit windows or explicitly selected Graph Toolkit workflows. Use runtime UI guidance for player screens.

## Activation and inputs

Resolve the engine and `unity-build-editor-tools` skill through OpenCaw commands; require compatible `UNITY` before edits or tool launches. Revalidate override scope for every output. Inspect Editor/package versions, current assemblies, asset formats, multi-object requirements and the intended authoring action. Store project observations only under the resolved `.opencaw/.cache/`.

## Workflow

1. Define the tool's asset and scene ownership and preview the proposed changes. Keep `UnityEditor` and optional Editor packages in Editor-only assemblies; player code consumes runtime-safe data.
2. Use the project's existing inspector/window stack. Prefer serialized-property binding for normal edits, preserving prefab overrides, multi-object behavior and validation. Retain clear mixed-value and read-only states.
3. Make creation, modifications, parenting and deletion undoable through their applicable Undo APIs. Save changed assets/scenes deliberately; support cancel and rollback for multi-asset operations without deleting unrelated content.
4. Keep UI callbacks, update hooks, selection subscriptions and async requests owned by the live window/inspector. Detach on close, disable, assembly reload and play-mode transition. Keep expensive work outside repaint paths.
5. Use Graph Toolkit only when explicitly selected and supported by the installed Editor/package. A graph editor owns authoring, validation and conversion to runtime data; it does not supply a universal runtime executor. Preserve graph IDs and migration paths.
6. Run a destructive-operation preview against a copied fixture first. Verify undo/redo, save/reload, prefab instances, selection changes, interrupted work and non-Editor builds.

Read [authoring transactions and graph boundaries](references/editor-authoring.md) when implementing editor bindings, batch edits or graph tools.

## Output and verification

Deliver the scoped tool, runtime data boundary, undo/save/cancel behavior and version/package requirements. Record native evidence for a create→edit→undo→redo→save→reload round trip and for callback cleanup after repeated open/close. Explicitly record missing native prerequisites and any untested visual interactions.

Do not install packages, execute arbitrary project helpers during discovery or import external editor examples as trusted automation. Avoid whole-project rewrites, direct serialized YAML editing and API assumptions based solely on a newer manual.
