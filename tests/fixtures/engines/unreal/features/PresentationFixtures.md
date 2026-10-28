# Native presentation fixtures

These source fixtures target Unreal 5.8 for test compilation, not as a host-engine policy. They have not been compiled or run without a matching Unreal Editor/toolchain. Their synchronous assertions exercise native ownership and evaluation, not visual, audio or physical-device acceptance.

The fixture module needs Core, CoreUObject, Engine, UnrealEd, Niagara, LevelSequence and MovieScene. Keep UnrealEd/testing code in this Editor fixture, never in a shipped game module. Niagara is an explicitly selected dependency of this test project; skill use does not enable it in host games.

## Required real assets

Author the following using the matching native Editor in an isolated disposable copy of this fixture project. No `.uasset`/`.umap` bytes or fake success receipts are supplied. All three tests register even when assets are absent; missing prerequisites are blocked by the runner and an accidental direct run fails with an actionable error.

`Config/DefaultGame.ini` contributes these keys to `GGameIni`:

```ini
[OpenCaw.UnrealFeatures]
PresentationMap=/Game/OpenCawFixtures/Presentation
NiagaraSystem=/Game/OpenCawFixtures/NS_OpenCawPool.NS_OpenCawPool
LevelSequence=/Game/OpenCawFixtures/LS_OpenCawInterrupt.LS_OpenCawInterrupt
```

These are examples for assets to author, not installed bindings. Store the actual asset paths and hashes with native run evidence. The map is a long package name without an object suffix; system/sequence values are object paths. The runner must ensure these files exist in the fixture content before launching the corresponding cases. Tests load these native assets and validate class, parameter, binding and actual behavior; an arbitrary file at the path cannot pass.

### Presentation map and bound sequence

1. Build the Editor fixture so `AOpenCawPresentationProbe` exists. Create a fresh non-partitioned empty map and place exactly one instance; give it Actor Tag `OpenCawSequenceProbe` and leave `AnimatedValue` at 17. Save as the configured PresentationMap. Keep the map free of runtime scripts or auto-playing sequences.
2. Create a Level Sequence in the configured path, 30 fps, playback range 0–2 seconds. Add that placed probe as a **possessable**, not a replacement spawnable. Add a float-property track for `AnimatedValue` with linear keys 0 seconds = 0 and 1 second = 100; extend the section through 2 seconds. Keep it active at 0.5 and 1.0 seconds.
3. Use the native property track. Do not substitute an event track that assigns a value from custom code; the test checks real Sequencer evaluation and preanimated restoration. Save the sequence and map with their binding intact. No camera, audio or event tracks are needed for this narrow state fixture.
4. Compile/save assets and close the authoring session. The automation process loads the saved map without saving it. Run it in an isolated fixture workspace, not a human's unsaved editing session.

### Niagara pool system

1. Create one real Niagara System with one enabled stateful **CPU** emitter, a finite 0.5-second single loop, a spawn burst at time zero and 0.25-second particle lifetime. A native sprite renderer is sufficient; no GPU data interfaces, collision or outside assets are needed.
2. Expose float `User.OpenCawIntensity` and connect it to a visible parameter such as particle scale through an appropriate typed conversion. Compile and verify this graph in the Editor; setting an unconsumed override is not proof of visual control.
3. Set **Max Pool Size ≥ 1** and Pool Prime Size = 0. Keep engine Niagara component pooling enabled. Save/compile a valid ready-to-run system. The test deliberately fails if the engine declines ManualRelease pooling or returns a fresh component instead of reusing the one returned.
4. The test disables scalability on its acquired components and uses forced-solo `AdvanceSimulation` for bounded CPU advancement. It checks initial live lifetime, immediate cancellation, native completion delegates, actual pool reuse, new transform/value and removal of the old delegate. These fixture settings do not prescribe production scalability policy.

## Native test cases and claims

| Automation name | Actual observation | Additional prerequisites |
| --- | --- | --- |
| `OpenCaw.UnrealFeatures.CameraOwnership` | Real controllers/managers/CameraActors; per-controller target isolation, generation-fenced stale release, repeated cancellation and destroyed-target restoration | Core native fixture build; no binary asset |
| `OpenCaw.UnrealFeatures.VFXPooling` | Real Niagara component activation/cancellation/delegates, manual pool reacquisition identity, new parameter/transform and detached old callback | PresentationMap + NiagaraSystem above |
| `OpenCaw.UnrealFeatures.SequenceInterruption` | Real sequence changes a bound reflected property, pauses/stops, restores preanimated state and distinguishes stopped/finished callbacks across restart | PresentationMap + LevelSequence above |

The tiny camera claim coordinator is fixture-owned application code around actual engine APIs. It illustrates a generation boundary; Unreal itself does not arbitrate arbitrary competing callers. Distinct controllers prove API owner isolation here, not full split-screen local-player input routing. Camera framing/comfort, Niagara GPU output/readability/flashing, native focus/HUD, soundtrack synchronization and packaged behavior require separate target playtests/captures. NullRHI success cannot certify them.

Official signature references inspected during authoring:

- [PlayerController](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/APlayerController): SetViewTarget, GetViewTarget, SpawnPlayerCameraManager.
- [NiagaraFunctionLibrary](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/Niagara/UNiagaraFunctionLibrary): explicit SpawnSystemAtLocation pool/activation arguments.
- [NiagaraComponent](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/Niagara/UNiagaraComponent): PoolingMethod, typed variable access, Activate, AdvanceSimulation, DeactivateImmediate, ReleaseToPool and OnSystemFinished.
- [LevelSequencePlayer](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/LevelSequence/ULevelSequencePlayer), [MovieSceneSequencePlayer](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/MovieScene/UMovieSceneSequencePlayer), [playback settings](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/MovieScene/FMovieSceneSequencePlaybackSetti-): native creation, evaluation/delegates and ForceRestoreState settings.
- [EditorLoadingAndSavingUtils](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Editor/UnrealEd/UEditorLoadingAndSavingUtils): LoadMap returns the loaded world.
