# Authored data, identity and loading

Use the project's actual Unreal version, Asset Manager configuration and package mount points. The links below select 5.8 as a reviewed reference baseline; verify signatures in the matching installed headers before implementation.

## Definitions and stable identity

Choose `UDataAsset` for authored object definitions, `UPrimaryDataAsset` when they need primary-asset discovery/loading policy, and `UDataTable` with a reflected `FTableRowBase` structure for a deliberately tabular schema. A CSV/JSON import can change a native table; inspect row-type compatibility, key uniqueness, localization and source ancestry before reimport. Never store per-player inventory, damage or quest progress by modifying a shared definition asset or class default object.

Use `FPrimaryAssetId` or an explicit project identity for durable references. An object pointer, row-array index, editor label and PIE-generated object name are unsuitable persistent identities. Primary IDs derived from names still need redirect/migration policy when names change. Validate duplicate IDs, missing rows and retired definitions; do not silently substitute a different gameplay definition.

## Dependency and lifetime decisions

- Inspect hard references for transitive memory loads; use `TSoftObjectPtr`/`TSoftClassPtr` when deferred resolution fits the consumer. Soft references are references, not proof that a package will be cooked.
- Configure the chosen primary asset types, scan roots, bundles and cook/chunk rules in project settings. Enumerate the resolved `FPrimaryAssetId` list and load paths before attributing a missing asset to async execution.
- Keep the `FStreamableHandle` or Asset Manager load owner alive for the documented use interval. Record which owner releases handles or calls `UnloadPrimaryAsset`; unrelated consumers may retain strong references afterward, so unloading is not immediate proof of memory release.
- Capture an owner weak pointer and request generation in completion work. On cancellation/world teardown, invalidate the generation and cancel only the owned pending handle. Validate owner, world and generation before assigning loaded objects; never resurrect a departed screen/actor or publish an obsolete request.
- Treat a missing handle, invalid primary ID, failed cast and absent dependency as distinct failures. Do not assume a completion callback guarantees the requested type exists. Keep temporary fallback presentation separate from authoritative gameplay selection.

Retain task-local observed context and receipts under `.hephaera/.cache`. `ENGINE.md` remains the engine authority; do not create another engine selector while recording discovered plugins and packages.

## Verification

Resolve a definition by its stable identity in a cooked player, including bundle dependencies and the smallest relevant streaming scenario. Reimport a controlled table, then test missing/duplicate keys, a renamed definition with an explicit redirect, cancelled request, consumer destruction, world travel and unloading with another consumer retaining ownership. Report headless package loading separately from visual/material/skeletal acceptance.

## Official API references

- [Asset Manager configuration and bundles](https://dev.epicgames.com/documentation/en-us/unreal-engine/asset-management-in-unreal-engine?application_version=5.8)
- [UAssetManager APIs](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UAssetManager?application_version=5.8)
- [FStreamableHandle ownership and cancellation](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/FStreamableHandle?application_version=5.8)
- [Data-driven gameplay and DataTables](https://dev.epicgames.com/documentation/en-us/unreal-engine/data-driven-gameplay-elements-in-unreal-engine?application_version=5.8)
