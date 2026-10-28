# Feature transitions and reversible ownership

GameFeatures manages plugin states; project policy decides what is permitted and when. Inspect descriptors, dependencies, native actions and GameFeatureData. A runtime module, content plugin and optional game feature have different loading behavior.

| Transition | Feature-owned work |
| --- | --- |
| Register | Publish metadata without starting gameplay. |
| Load | Resolve data and retain explicit handles. |
| Activate | Install behavior once for each applicable recipient/context. |
| Deactivate | Stop new work and unwind behavior, including async cleanup barriers. |
| Unload | Release content consistent with live-instance policy. |

Use host-version deactivation contexts/pausers for asynchronous teardown. Guarantee pauser release on failure and a bounded shutdown path; otherwise feature transitions can stall. Avoid deferred raw-pointer capture of actions or actors.

Maintain a ledger for component requests, grants/effects, input contexts, delegates, timers and pending operations. Revoke by source/handle rather than clearing shared subsystems. Handle actors existing before activation and actors appearing later through the chosen initialization protocol.

Multiple worlds/local players can coexist. Filter recipients by context and actual ownership. A sample's initialization interfaces are optional integrations, not guaranteed native APIs.

Deactivation prevents stale callbacks from restoring registrations. Report logical feature state, object references, component lifetime and native-module lifetime separately; a state transition does not prove all package/code memory was unloaded.

## Evidence

Observe an actual installed engine resource during activation and its removal after deactivation/unload, then reactivate. Also test dependency failure, activation cancellation, world removal and isolation from unrelated registrations. A local boolean changed by the test cannot establish resource cleanup.

## Official references

- [Game Features and Modular Gameplay](https://dev.epicgames.com/documentation/en-us/unreal-engine/game-features-and-modular-gameplay-in-unreal-engine)
- [GameFeatures subsystem](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameFeatures/UGameFeaturesSubsystem)
- [GameFeatureAction](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameFeatures/UGameFeatureAction)

Match APIs and project policy to the installed release; plugin and extension protocols remain explicit selections.
