# Web build measurement and delivery

## Comparable evidence

Record Editor/package lock identities, code revision, build target, scene list, scripting backend, stripping/debugging options and compression settings. Keep release and development results separate. Run comparable workloads on named browser/device classes with cold and warm caches; report variability, sample count and failure cases. Project budgets, not universal frame-rate or file-size rules, define acceptance.

BuildReport attributes included files and build duration/size. HTTP traces establish actual encoded transfer, response headers, retries and download timing. Player instrumentation establishes first usable interaction and representative gameplay, with a clear start/end event. A loader disappearing is not proof that controls and content are ready.

## Compression and hosting

Unity's Brotli/gzip outputs need matching server encoding and MIME types for the emitted files. Avoid double compression and mismatched encoded files. Configure cache policy from file identity: immutable hashed resources can be long-lived while entry points must refresh deliberately. Verify headers from actual responses, including CDN behavior and error pages. Document service workers and stale-cache recovery if the project uses them.

Decompression fallback shifts work and can increase startup/memory cost. Choose it explicitly when hosting restrictions require it; measure rather than treat it as a free optimization. Never change production hosting or publish a build while performing a local optimization task unless that action is separately authorized.

## Memory and platform limits

Distinguish Unity/WebAssembly heap allocation from browser memory, decoded images/audio, downloads and GPU resources. Texture compression availability depends on the target browser/device; don't assume a desktop format is mobile-safe. Dispose owned resources and bound in-flight work before increasing memory settings. Compare peak startup and steady gameplay after warmup and a long session, not just one Editor snapshot.

Threads, shared memory, cross-origin isolation, browser support and mobile restrictions depend on the installed Unity release and selected packages. Inspect that release's platform documentation and the actual headers before claiming support. Do not infer that a native .NET thread or socket API works in a web build. Localized content and remote asset loading must use asynchronous paths compatible with the target.

## Browser acceptance

Serve the generated player through the intended HTTP path. Check network errors, decoding, console exceptions, focus/navigation, text input, resizing, fullscreen exit, user-gesture audio, reconnect and recovery after a failed resource. A successful build or simulated HTTP header test cannot prove those behaviors. Browser QA may verify Unity web UI while native UI, device audio and physically felt haptics remain separate acceptance cases.

Official starting points, use the matching installed release:

- [Web deployment](https://docs.unity3d.com/6000.0/Documentation/Manual/webgl-deploying.html).
- [Web memory](https://docs.unity3d.com/6000.0/Documentation/Manual/webgl-memory.html).
- [BuildReport](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Build.Reporting.BuildReport.html).
