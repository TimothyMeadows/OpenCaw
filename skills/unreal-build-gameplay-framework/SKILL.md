---
name: unreal-build-gameplay-framework
description: Build Unreal reflected gameplay classes, Blueprint interfaces and actor lifetimes with explicit server and object ownership.
engines: [UNREAL]
---

# Unreal Build Gameplay Framework

## When to use

Build Unreal reflected gameplay classes, Blueprint interfaces and actor lifetimes with explicit server and object ownership. Use this feature for Unreal-owned game code and content.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-gameplay-framework` before edits or tool launches. Continue only when the effective engine is `UNREAL` and `compatible: true`. Skill selection never selects the engine. Revalidate any task override and its permitted isolated output scope before writes. Record observed context and evidence only in the resolved `.hephaera/.cache/tasks/<task>/`; `ENGINE.md` remains the selector.

Read the .uproject engine association, module and plugin list, target configurations, gameplay design and replication model. Bind APIs to the matching Unreal release and compiler toolchain. Distinguish gameplay C++/Blueprints from C# .Build.cs and .Target.cs build rules.

## Workflow

1. Map responsibilities across GameMode, GameState, PlayerState, PlayerController, Pawn/Character and components. GameMode is server-side, while replicated shared state belongs in appropriate replicated objects; do not put required client state only in GameMode.
2. Choose UObject, ActorComponent, Actor or a subsystem by lifetime and world/player scope. Define reflection, module export macros and generated headers deliberately. Keep constructors/default subobjects separate from world-dependent initialization. Use reflected strong references where reachability is intended; Outer alone does not replace a reachable reflected owner. Revalidate weak observers and soft references at use.
3. Define bounded C++/Blueprint interfaces and validated data surfaces. Distinguish BlueprintNativeEvent from BlueprintImplementableEvent, dispatch Blueprint-capable interfaces through generated Execute_ entry points and keep authoritative permission checks in their trusted owner. Construction Script and Editor rebuilds must be safe to repeat.
4. Implement construction, initialization, BeginPlay, possession, EndPlay and teardown deliberately. Remove delegates, timers and latent work when the owner leaves the world; do not assume destruction is the only ending path.
5. Use registered GameplayTags with deliberate exact/hierarchical queries. Tags are semantic state, not an authorization proof or event bus. Select a messaging implementation explicitly; document listener handles, payload lifetime and dispatch thread. Avoid assuming sample-specific messaging plugins exist.
6. Integrate asset loading, mutable save state, AI decisions and locomotion through their dedicated feature owners. Framework owns the interfaces and teardown order; do not duplicate their implementations or persist transient object addresses.
7. Bound ticking and event subscriptions. Group update work by actual need, profile representative actor counts and preserve standalone service architecture independently of Unreal modules.

## Verification

- Compile the intended target and Blueprint assets in real Unreal; test spawn, possession changes, world travel and teardown.
- Test native and Blueprint interface implementations, repeated initialization, two simultaneous worlds and streamed actor removal during pending work.
- Check delegate/timer cleanup, invalid soft references and target actor budgets in an actual player or representative Editor session.

## Output

Framework ownership diagram, native/Blueprint interfaces and assets, lifecycle and integration contracts, compile evidence and representative gameplay fixtures. Record environment, scope, expected and observed results, evidence paths, and blocked or not-run checks separately from passes.

## Boundaries

A generated C++ file or Blueprint description is not a playable native asset. Preserve package identities and use real engine tooling for asset authoring. Independent tools and services retain their own architecture contracts.

## References

Read [framework lifetimes](references/framework-lifetimes.md) when implementing reflection, ownership or designer seams.

- [Unreal gameplay framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-framework-in-unreal-engine). Match the documentation version to the project.
- [Unreal subsystems](https://dev.epicgames.com/documentation/en-us/unreal-engine/programming-subsystems-in-unreal-engine). Match the documentation version to the project.

