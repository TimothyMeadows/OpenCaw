# Gameplay and simulation native fixtures

These independently authored source fixtures target **Unreal 5.8 for research/test purposes**. Host skills still resolve the project's own engine release. No source here is a claim that Unreal compilation or runtime testing has occurred: both are **NOT-RUN** without matching Editor, UBT, compiler, selected plugins and native-authored bindings. Structural/parser simulations do not count as native results.

## Module and plugin prerequisites

GameplayFixtureTypes.h is reflected and needs UHT. Runtime/module dependencies: Core, CoreUObject, Engine, GameplayAbilities, GameplayTags, GameplayTasks, AIModule, NavigationSystem, MassEntity, GameFeatures and Projects. GameplayAbilities and GameFeatures must be explicitly enabled in the isolated fixture project; AI/navigation are engine modules. MassEntity is a runtime module in the 5.8 API baseline. No Mover, StateTree, SmartObjects, EQS, Lyra or ModularGameplay selection is implied by these tests.

Use a disposable project-local working copy. Do not point the unload test at a production feature. Native binary assets must be authored/saved in the matching Editor. The runner must report missing tools/bindings as blocked and must never create text-shaped .uasset replacements or count a skipped case as passed.

## Required native bindings

Set these keys in `[OpenCaw.UnrealFeatures]` of the fixture project's Game configuration (read through GGameIni):

| Key | Required setup |
| --- | --- |
| `BehaviorTree` | Object path to a native-authored BehaviorTree with a root Sequence whose only child is `UOpenCawFixtureAbortTask`. No services, decorators or looping behavior. No blackboard is required. |
| `GameFeaturePluginName` | Name of an isolated project-owned GameFeature plugin created with the Editor's Game Feature tooling. Its GameFeatureData must include exactly one `UOpenCawFixtureFeatureAction` action (displayed as OpenCaw Feature Frame Probe). Start inactive; permit explicit activation/unload through fixture project policy. |

The plugin descriptor, GameFeatureData and BehaviorTree must belong to the disposable fixture working copy. Preserve their paths/hashes in the test report. The feature plugin name is resolved to its actual project plugin URL; external/engine plugins and an already active feature are rejected. Project policy/Asset Manager must recognize the native GameFeatureData. Explicitly configure the selected release's discovery settings through Editor/project configuration; this source does not install or silently enable anything.

## Automation cases and assertions

Every case starts with the shared fresh-run evidence marker. Assertion failures, missing assets, failed transitions, empty discovery and missing completion entries are failures/blockers, never success.

| Case | Actual engine behavior and required observations |
| --- | --- |
| `OpenCaw.UnrealFeatures.AsyncTeardown` | Real thread-pool tasks compute immutable snapshots; a live recipient accepts a current result, EndPlay cancels a retired recipient, and result application remains on the game thread. Waits/deadlines are bounded; no worker dereferences UObject data. |
| `OpenCaw.UnrealFeatures.GASOwnership` | Native ASC grant handles remain stable across avatar replacement without duplicate grants; an instant effect changes the intended target attribute and leaves caster health intact; native activation/cancellation and owned removal preserve unrelated grants. Standalone authority only. |
| `OpenCaw.UnrealFeatures.Movement` | Native CharacterMovement owns the capsule, a swept move hits an actual blocking body, stopping clears velocity, disabling enters MOVE_None and owner teardown succeeds. This is standalone movement evidence. |
| `OpenCaw.UnrealFeatures.AICancellation` | Actual bound BehaviorTree enters a latent native task, forced stop invokes native AbortTask, its owned timer cannot complete afterward, and unpossession releases the pawn. Does not certify navigation, StateTree, EQS or SmartObjects. |
| `OpenCaw.UnrealFeatures.MassLifecycle` | Initialized real entity manager builds an archetype/entity, accesses fragment data, queues destruction without immediate mutation, invalidates the handle after flush and rejects the retired identity after replacement. Does not certify crowd/representation or processor scaling. |
| `OpenCaw.UnrealFeatures.GameFeatureUnload` | Actual subsystem activation installs an OnEndFrame delegate through the native asset's action; an engine frame invokes it; unload removes the resource and active GameFeatureData. Repeat activation/unload to catch lifecycle residue. Logical unload only, not proof of binary module/package-memory unload. |

## Required supplemental network correction acceptance

The standalone Movement/GAS cases cannot establish client/server correction, remote validation or prediction rejection. Do not call client-only prediction hooks in a standalone world or assign synthetic network roles to pretend this was tested.

For an actual locomotion implementation, author a separate **project-owned native functional map and test controller** with the project's Character subclass and selected movement configuration. This is a required supplemental acceptance procedure, not an included prebuilt map or a result of the source-only fixtures:

1. Launch a dedicated server and two separate packaged/development client processes on matching builds. Record executable/map/configuration hashes, process identities, engine version and selected replication/movement systems.
2. Have owning client A send a bounded, timestamped input sequence for forward movement, stop and a movement-mode transition. Client B observes the pawn. Report server/owner/observer position and mode per request sequence; use project-specific spatial/time tolerances declared before the run.
3. Through a server-only fixture hook, perform an authorized displacement or reject a bounded invalid movement request while the owner still holds predicted movement. Capture server authoritative transform, owner predicted transform, subsequent corrected transform, saved-move/replay evidence and the correction event/time. The hook must not be callable by arbitrary gameplay clients.
4. Assert that correction actually occurred, the owner converged to the server within declared tolerance/time, client B converged, modes agree, speed/displacement limits remain enforced and the authoritative mutation occurred once. Zero corrections, missing samples or a client-side-only transform change fail this scenario.
5. Repeat under explicitly configured latency/loss and while moving-base ownership changes; then unpossess/disconnect during queued input. Assert stale input cannot command the replacement pawn and outstanding movement/effect callbacks retire.
6. Save distinct process logs and a structured per-scenario report containing expected/observed results, budgets/tolerances, input sequence IDs, authoritative/owner/observer measurements, correction counts and failures. The report must bind this fresh run and actual artifacts. Missing processes, correction events, evidence or reports block acceptance.

Do not impose a universal correction distance, frame rate or packet-loss threshold on host projects. The test scenario's explicit declared tolerances and network settings are its acceptance contract. Visual smoothing, animation alignment, input feel and physical haptics additionally require target-runtime/player/device review.

## Other limits

This suite does not certify hostile-client target validation, GAS costs/cooldowns and prediction rejection, Smart Object claims, real pathfinding, StateTree, Mover, Mass processors/representation, cross-platform physics or target performance. Select those systems explicitly and supply project-owned native fixtures and evidence when applicable. Native compilation and execution remain not-run until all prerequisites are satisfied.

## Official API inspection references

- [World creation](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UWorld)
- [AbilitySystemComponent](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameplayAbilities/UAbilitySystemComponent)
- [CharacterMovement and correction context](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UCharacterMovementComponent)
- [BehaviorTreeComponent](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/AIModule/UBehaviorTreeComponent)
- [Mass entity manager](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/MassEntity/FMassEntityManager)
- [GameFeatures subsystem](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameFeatures/UGameFeaturesSubsystem)

API inspection is supporting authoring evidence, not compiler or runtime evidence.
