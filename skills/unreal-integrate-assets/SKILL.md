---
name: unreal-integrate-assets
description: Import and author Unreal native assets with audited dependencies, stable references, and verified cook inclusion.
engines: [UNREAL]
---

# Unreal Integrate Assets

## When to use

Import and author Unreal native assets with audited dependencies, stable references, and verified cook inclusion. Use this feature for Unreal-owned game code and content.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-integrate-assets` before edits or tool launches. Continue only when the effective engine is `UNREAL` and the skill is eligible. Skill selection never selects the engine. Honor any validated task override and its permitted isolated output scope.

Record Unreal version, target platforms, source asset rights/provenance, importer/plugin selection, content roots, scale/axes, budgets and desired native asset types. Inspect existing packages and project import conventions before changes.

## Workflow

1. Inspect source geometry, materials, textures, skeletons and animation dependencies. Record units, orientation, pivots, collision, naming and expected material slots; keep originals immutable and work on approved repository-local copies.
2. Use the actual Editor, supported commandlets or an explicitly selected Editor scripting interface to import and author .uasset/.umap content. Never fabricate binary package files from text, rename another format to .uasset or report an unexecuted import as complete.
3. Apply importer settings deliberately, including normals/tangents, texture color semantics, skeletal hierarchy and animation compatibility. Preserve import data for reproducible reimport and review semantic differences before replacing existing packages.
4. Create collision, LOD and platform settings from asset budgets. Nanite or other rendering features are version/platform decisions, not substitutes for measuring memory, visibility and collision behavior.
5. Use Asset Registry inspection to find dependencies, missing references and redirectors. Move or rename through supported content tools, inspect referencers and avoid bulk redirector cleanup that changes unrelated packages.
6. For DataAssets, tables, Asset Manager identities and asynchronous loading, read [authored data and loading](references/authored-data-and-loading.md). Keep authored definitions separate from mutable save state. Track stable primary IDs/row keys, owned streamable handles, cancellation and post-unload references.
7. Separate runtime modules from Editor-only asset-authoring code. Save only intended packages, retain source ancestry and generate a reviewable import/change manifest. Distinguish soft references from cook inclusion; validate maps, primary assets, rules and chunks so dynamically loaded dependencies exist in the packaged build.

## Verification

For Blender-authored content, read [Blender asset handoff](references/blender-asset-handoff.md) before native import, reimport or target material/LOD/collision acceptance.

- Reopen native assets in the selected Editor and inspect geometry, hierarchy, material assignments, collision and textures.
- Reimport a controlled fixture and verify intentional settings/references survive without duplicate packages or lost bindings.
- Cook/package and load the asset by the real runtime path, including soft-loaded dependencies; record size, LOD and memory evidence.
- Cancel an owned load while its consumer is destroyed; verify a late completion cannot repopulate stale state. Test missing IDs, renamed assets/row keys and the applicable migration/redirect policy.

## Output

Authentic native packages, source/import provenance, dependency and cook manifest, before/after inspections and packaged runtime evidence. Record environment, scope, expected and observed results, evidence paths, and blocked or not-run checks separately from passes.

## Boundaries

Missing Editor, importer or source rights block the affected operation. Do not acquire marketplace plugins, accept licenses or rewrite native package bytes speculatively. Independent tools and services retain their own architecture contracts.

## References

- [Authored data and loading](references/authored-data-and-loading.md): read for data definitions, identity, dependency policy and lifetime.
- [Unreal asset management](https://dev.epicgames.com/documentation/unreal-engine/asset-management-in-unreal-engine). Match the documentation version to the project.
- [Cooking and chunking](https://dev.epicgames.com/documentation/en-us/unreal-engine/cooking-content-and-creating-chunks-in-unreal-engine). Match the documentation version to the project.

