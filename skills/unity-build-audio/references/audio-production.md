# Import, mixer and measurement decisions

## Clip and load decisions

Inspect duration, channels, source sample rate, usage and target import overrides before changing clips. Preserve originals and rights. `Decompress On Load` trades decoded memory for reduced playback decoding; `Compressed In Memory` retains compressed data while decoding during playback; `Streaming` uses streaming resources and buffers. Concurrent short effects and long music have different costs; choose from measured target workloads, not a universal load type.

Preload and background-loading flags are separate from load type. Inspect `AudioClip.loadState` before a request needs the clip, handle failed loads and bound prefetch concurrency. Account for compressed and decoded memory, streaming buffers and temporary decode peaks. `LoadAudioData`/`UnloadAudioData` must respect live consumers and the selected load type; unloading a borrowed clip is not a cancellation mechanism for one voice.

Stereo is not automatically appropriate for a positional point source. Check channel count, Force To Mono, normalization, spatialBlend and selected spatializer behavior. Do not force mono for music or authored stereo beds without listening review. `spatialBlend = 1` does not prove a multichannel source has the intended localized image on every backend. Test distance, attenuation, spread, occlusion design and listener position on the actual device configuration.

## Mixer and voice ownership

Route owned sources into explicit AudioMixerGroups. Map user volumes and snapshots to project-defined parameter ranges, with a deliberate silence floor and persistence policy. Snapshot transitions, ducking and pause/focus policies need an owner; cancelling one request must not restore another system's settings.

A pool resets clip, loop, pitch, priority, volume, spatial parameters, mixer group, time state and completion subscriptions. Handle voice stealing and callbacks as state transitions tied to an owned request ID. A late end callback from the previous lease cannot release the current source. Stop/release loops on scene teardown unless ownership was explicitly transferred.

Use audio DSP time for scheduled transitions and record how it relates to simulation/unscaled clocks. Don't interpret `AudioSource.isPlaying == false` alone as natural completion: pause, disable, stop, virtualization and load failure need their own ownership state. Audio callbacks have real-time/thread restrictions; don't perform Unity scene access, blocking work or allocations there.

## Measurement and verification

Record real/virtual voice counts, Audio Profiler DSP/streaming CPU and memory under a representative scene, including saturation and concurrent loads. `AudioSettings.GetConfiguration` and DSP buffer information describe configuration, not measured CPU cost. A buffer duration derived from samples/sample-rate is only one part of end-to-end latency. Don't change global buffer size simply to make a test pass.

Native smoke checks may create a known PCM clip, verify DSP time advances, check playback sample progress, stop/reuse the source and confirm routing assignment to a real mixer asset. Such checks do not prove audibility, mixer gain, spatial quality, loudness, platform interruption or profiler budgets. Capture listening and profiling evidence on representative devices, with unavailable outputs explicitly blocked.

Official references, qualify to the installed release:

- [Audio clip import settings](https://docs.unity3d.com/6000.0/Documentation/Manual/class-AudioClip.html).
- [Audio mixer](https://docs.unity3d.com/6000.0/Documentation/Manual/AudioMixer.html).
- [Audio Profiler](https://docs.unity3d.com/6000.0/Documentation/Manual/ProfilerAudio.html).
- [AudioSettings](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/AudioSettings.html).
