# Reflected framework and object lifetime

Use reflection where serialization, Editor exposure, networking or Blueprint dispatch needs it. Keep public headers narrow; forward declarations cannot replace includes required by reflection/inheritance. Generated includes stay last in reflected headers. Module export macros must match the owning module.

| Surface | Ownership decision |
| --- | --- |
| GameMode | Authoritative rules; required client state needs another replicated owner. |
| GameState/PlayerState | Match/player identity, replication and travel behavior. |
| Controller/Pawn | Intent/device owner versus replaceable embodiment. |
| Component | Owned capability with registration/activation boundaries. |
| Subsystem | Engine, GameInstance, World or LocalPlayer scope; multiple Editor worlds can coexist. |

## Designer seams

Expose the smallest useful validated API. BlueprintNativeEvent has a native implementation seam; BlueprintImplementableEvent needs Blueprint behavior. Blueprint-capable interfaces use generated reflection dispatch rather than assuming a native interface pointer exists.

Constructors establish defaults/subobjects, not world-dependent transactions. Construction Scripts and Editor property changes rerun; keep their work repeatable. A Blueprint-generated class identity differs from its package asset path. Do not make designer events responsible for trusted server permission checks.

## Reachability and teardown

Reflected strong references establish intended GC reachability. Raw pointers do not; Outer association alone is insufficient. Weak observers require use-time validation, including after callbacks. A soft reference does not promise content is loaded or cooked.

Own every timer, delegate, task and latent request. Unpossession/deactivation can require cleanup before EndPlay; EndPlay itself covers more than destruction. Remove feature-owned handles only. Request-generation checks prevent a valid respawned owner from receiving an old result.

GameplayTags need registered sources and tests for exact versus parent matching. Tags are semantic state, not an event bus or authority grant. Select messaging explicitly and document payload ownership, dispatch thread and listener removal. Transient messages cannot replace durable replicated state.

## Verification

Exercise native-only and Blueprint interface implementations, repeated possession, two worlds and streamed removal during a callback. UHT/compile validates declarations, not runtime authority or lifetime correctness. Profile actual actor/tick counts.

## Official references

- [Gameplay framework](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-framework-in-unreal-engine)
- [Object pointers](https://dev.epicgames.com/documentation/en-us/unreal-engine/object-pointers-in-unreal-engine)
- [Interfaces](https://dev.epicgames.com/documentation/en-us/unreal-engine/interfaces-in-unreal-engine)
- [GameplayTags](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-gameplay-tags-in-unreal-engine)

Resolve documentation and installed headers for the host release; these references are not compile evidence.
