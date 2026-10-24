# Runtime audio

Read this for runtime sound integration, timing, mix control or audio lifecycle changes. Identify the engine version, output targets, sound assets and selected audio plugins. SoundWave/SoundCue, MetaSound, Quartz and optional middleware have different roles; availability does not authorize adopting them.

## Requests and components

Map gameplay event identities to sound requests with category, owner, position/attachment, local-player audience and cancellation policy. Confirm source rights, import compression, streaming and subtitle metadata. Importing a clip does not authorize generation or a hosted service; those follow the existing media workflow separately.

Choose fire-and-forget playback only for short sounds whose cancellation and parameter control are unnecessary. `UGameplayStatics::SpawnSoundAttached` or `SpawnSoundAtLocation` returns an `UAudioComponent` when successful; retain and validate the result for loops, dialogue or effects requiring control. Treat asset absence, voice rejection and shutdown as operational outcomes, not completed gameplay actions.

Set routing, attenuation, concurrency and initial parameters before playback where the selected API allows. Distinguish `bAutoDestroy` component lifetime from stop behavior. Bind completion once for that playback generation; `OnAudioFinished` may result from stopping as well as reaching the end. A replacement sound must not let an old callback release its new owner. Unbind on teardown; for reusable components explicitly reset parameters, sound, transform, delegates, routing and auto-destroy policy.

## Mix and timing

Sound Concurrency groups constrain voices according to the authored rule and owner limits. Test maximum-count and voice-stealing behavior with essential dialogue and cue priorities. Virtualization is not identical to stop/restart: verify whether a loop resumes, advances silently or restarts under the chosen sound configuration.

Game-thread events are not sample-accurate scheduling. If Quartz is selected, establish the clock's owner, time signature, quantization, transport and callback lifetime. Define pause, time dilation, suspend/resume, clock replacement and travel explicitly. Cancel owned queued commands on interruption using the installed version's supported API; do not represent a stopped game timer as cancelled audio-render work.

For MetaSounds, record exact input parameter names/types and trigger semantics. Validate the native graph and runtime input path against the asset; a misspelled parameter should produce a visible integration finding. Audio Modulation, SoundClasses, SoundMixes and Submix effects are alternative/combined project choices with distinct scopes. Maintain reversible owner contributions so closing a menu does not undo dialogue ducking still in force.

## Spatial and accessibility acceptance

Attenuation, occlusion, listener override and spatialization depend on target setup. Split-screen listener policy must be deliberate. Avoid attaching a long-lived loop to an actor that is about to unload without a stop/transfer policy. Provide subtitles and alternate channels for information essential to play; vibrations require separate supported-device ownership and testing.

Listen on target speakers/headphones for clipping, transitions, spatial cues and subtitle timing. Stress cancellation, output-device changes, virtualized loops, actor destruction and world travel. Measure native voice counts, audio CPU, streaming residency and clock timing with the selected settings. A component reporting playback, a mock audio device or NullRHI run does not prove audible output or artistic acceptance.

Official references, with version matching:

- [AudioComponent API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/UAudioComponent)
- [Quartz](https://dev.epicgames.com/documentation/en-us/unreal-engine/overview-of-quartz-in-unreal-engine)
- [MetaSound parameters](https://dev.epicgames.com/documentation/en-us/unreal-engine/metasounds-reference-guide-in-unreal-engine)
