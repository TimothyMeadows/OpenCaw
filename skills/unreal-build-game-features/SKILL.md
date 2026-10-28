---
name: unreal-build-game-features
description: Build Unreal modular Game Features with scoped activation, reversible resource registration and bounded unload behavior.
engines: [UNREAL]
---

# Unreal Build Game Features

## When to use

Implement modular feature activation, actor extension and teardown through Unreal GameFeatures. Ordinary module organization belongs to tooling; a content load alone is not feature activation.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-game-features` before edits or tool launches. Require effective engine `UNREAL` and `compatible: true`; revalidate task override and output scope. A skill never selects its engine.

Read host version, selected GameFeatures/ModularGameplay plugins, project policy, feature dependencies and applicable worlds. Sample-specific interfaces are not universal APIs. Record evidence only in resolved `.opencaw/.cache/tasks/<task>/`; preserve `ENGINE.md`.

## Workflow

1. Define assets, modules, dependencies, activation prerequisites and world/authority scope. Use native-authored GameFeatureData/actions and selected policy; do not invent binary assets or enable plugins implicitly.
2. Separate registering, loading, activating, deactivating and unloading work. Loaded content must not mutate every active world, especially across multiple PIE contexts.
3. Track owned component requests, delegates/listeners, input contexts, ability grants, timers and async loads by activation/context. Make repeated activation/deactivation safe.
4. Integrate existing and newly spawned actors through the project's explicit extension/initialization protocol. Late registration cannot duplicate work or assume sample-specific initialization states exist.
5. On deactivation stop new work, cancel active behavior and remove owned resources. Use supported context/pauser APIs for bounded async teardown; older-generation callbacks cannot reinstall behavior.
6. Unload only under an explicit live-instance/reference policy. Logical shutdown and content release do not prove native binary code can be hot-unloaded safely.
7. Record transition failures. Missing dependencies, interrupted load, travel and failed activation must unwind without clearing another feature's resources.

Read [feature activation and unload](references/feature-activation-unload.md) when implementing lifecycle actions.

## Verification

Test activate/deactivate/reactivate, actors present before/after activation, two worlds, travel, missing dependencies and unload during work. Observe actual engine resources installed and removed by a native GameFeatureData/plugin fixture; a local active flag is insufficient.

## Output

Feature state/lifetime contract, native descriptors/assets/actions, ownership ledger and transition evidence. Record environment, expected/observed results and blocked/not-run checks; distinguish feature state from physical module/package unloading.

## Boundaries

No implicit installation or plugin enablement. Match project version/policy and native asset tools. Preserve budgets, provenance, review and publication gates.
