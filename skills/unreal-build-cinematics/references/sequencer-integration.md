# Sequencer integration

Use this for native sequence authoring or runtime playback. Match the project version and selected plugins; neither a matching filename nor a playable empty sequence proves binding correctness.

## Asset and binding contract

Author `ULevelSequence` and map assets with actual Editor tools. Record display rate, tick resolution, playback/section ranges, subsequences, tracks and completion policy. Inspect possessables, spawnables, binding GUIDs/tags and resolution context. Runtime binding overrides need an explicit owner and reset on replacement; actor labels and enumeration order are not persistent identities.

Possessables control existing world objects; spawnables have sequence-owned lifetime rules. Test both against world streaming, restored saves and packaged content. A binding can resolve in the Editor and fail in a cooked map because its dependency or instance context differs. Declare failure when a required binding is absent instead of playing a silent partial shot.

## Player lifecycle and restoration

`ULevelSequencePlayer::CreateLevelSequencePlayer` returns a player and output actor; retain both through the request's lifetime and check startup success. Establish settings before playback. In current versions, `FMovieSceneSequencePlaybackSettings::FinishCompletionStateOverride` distinguishes default section behavior, forced keep and forced restore. Since 5.4 this supersedes the older `bRestoreState` setting; inspect the installed headers rather than copying deprecated fields.

`Play`, `Pause`, `Stop`, `StopAtCurrentTime` and natural finish have different semantics. `OnStop` is not `OnFinished`. Track why a request ended and remove owned delegates. Replace/cancel paths must clean input/HUD/camera claims even if no natural completion callback occurs. A stale callback must not release a newer request's claims. Keep versus restore must be deliberate for every affected property; an explicit restore call cannot undo authoritative changes outside the sequence's captured state.

Avoid overlapping players writing the same property without a defined blending/priority policy. Before a replacement starts, stop and restore the retired owner in the chosen order. Exercise repeated cancellation and verify idempotence. Capture a property's initial state, prove sequence evaluation changed it, then prove the chosen stop policy; checking only a stopped flag misses broken bindings.

## Time, events and camera handoff

Use the selected sequence time controller and clock source. Distinguish display frames, tick-resolution frames and seconds in `FMovieSceneSequencePlaybackParams`. Jump, scrub and play-through positions can evaluate event tracks differently. Audio/timecode synchronization and render warmup are separate from game-time playback; record pause and dilation behavior.

A skipped or replayed shot must not duplicate rewards or miss an authoritative state transition. Route important decisions through server-validated, idempotent gameplay logic; event tracks can request presentation. Coordinate camera cuts with the local-player camera owner and declare whether the shot restores, transfers or replaces that claim. Restoring the view from the start of a shot is unsafe if the player has since died or changed possession.

## Rendering and acceptance

Movie Render Queue is an explicitly selected rendering plugin/workflow. Record output format, temporal/spatial sampling, warmup, exposure, shot range, resolution and version; render into non-runtime staging with provenance. Validate rendered frames and audio with a native viewing/listening pass. Compile/UHT, property automation and NullRHI establish no final cinematic quality.

Official references, with version matching:

- [LevelSequencePlayer API](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/LevelSequence/ULevelSequencePlayer)
- [MovieSceneSequencePlayer API](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/MovieScene/UMovieSceneSequencePlayer)
- [Playback settings API](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/MovieScene/FMovieSceneSequencePlaybackSetti-)
- [Sequencer changes in 5.4](https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5.4-release-notes?application_version=5.4)
