# Three.js postprocessing

THREEJS automatically selects [pmndrs postprocessing](https://github.com/pmndrs/postprocessing) for new screen-effects work through `threejs-build-postprocessing`. Other engines retain their render pipelines. This capability is independent of STYLE, Quarks particles and MAUI packaging; it installs nothing and never switches the host renderer.

## Host setup and inspection

Use host-locked dependencies and one Three resolution shared with Quarks. The tested fixture is Three0.182.0, postprocessing6.39.5 and Quarks/core0.17.1. Postprocessing6.39.5 declares Three>=0.168.0 <0.187.0. Preserve Zlib and applicable dependency notices. Different versions/lock formats require fresh compatibility evidence; no automatic upgrade or install is performed.

```bash
bash .hephaera/commands/threejs-postprocessing.sh inspect --renderer WebGLRenderer
bash .hephaera/commands/threejs-postprocessing.sh scaffold --output src/engine/postprocessing --renderer WebGLRenderer
```

Inspection reads bounded npm manifest/lock/installed metadata without importing host code. An exact tested graph establishes metadata consistency only; installed bytes, real context, shader execution and target readiness remain unverified. Missing/inconsistent dependencies, duplicate/nested Three, links, unsupported package graphs and WebGPU are reported explicitly. Scaffold copies reviewed source into a fresh owned directory with source/engine/dependency receipts; it overwrites nothing and can be prepared before installation. Valid isolated engine overrides must supply `--engine-evidence` and stay inside their recorded prototype scope.

## Runtime ownership

Read the [runtime contract](../.engine/threejs/postprocessing/README.md) and copied `example.mjs`. Inject the actual host Three/postprocessing modules, renderer, scene, camera and current engine selection. Use the existing presentation loop: simulation, animation/Quarks update, then composer output once. The helper owns no animation-frame scheduler and never disposes borrowed scene, renderer, geometry, materials or particle runtime.

The starter is deliberately bounded: WebGL2, LDR byte framebuffer, zero MSAA, RenderPass and FXAA. Validate the actual existing context and the actual bounded framebuffers before work. Require explicit compatible color/tone settings, finite size/DPR/pixel/delta limits and fresh validation after context restoration. Suspend for visibility/MAUI lifecycle and context loss. Dispose the owned composer resources/listeners on scene teardown; release shared renderer resources only at their owner teardown.

Library selection does not turn on every effect. Bloom, HDR, depth/outline/SSAO, multisampling, LUTs and custom passes require a reviewed host extension with applicable input rights, target capability probes and measured effect/pass/texture/frame budgets. HDR requires a verified high-precision render-target profile and one final tone-mapping/output path. Byte targets lose HDR range and may show dark banding. Never silently lower a selected HDR profile or change renderer/color behavior. Respect reduced-motion/flash preferences and preserve essential UI cues.

## MAUI compatibility and release evidence

MAUI HybridWebView hosts [WebView2, Android WebView and WKWebView](https://learn.microsoft.com/en-us/dotnet/maui/user-interface/controls/hybridwebview?view=net-maui-10.0#browser-engines). WebGL2 is feasible in these hosts; [WebKit introduced it in Safari15](https://webkit.org/blog/11989/new-webkit-features-in-safari-15/), matching the existing Apple floor. Android uses an independently updated [Chromium WebView](https://developer.chrome.com/docs/webview), with hardware acceleration enabled by our template. OS or package build success does not establish the actual context or optional extensions on a device.

Use the real packaged static assets on all release targets: Windows, MacCatalyst, Android and iOS. Review shader compilation, real output/alpha/color, Quarks effects and readable UI, resize/orientation/DPR, suspend/resume, context loss/restoration, sustained frame times and memory. Keep unavailable target checks explicit. This baseline's source/CPU tests do not certify native GPU behavior. Do not bypass GPU blocklists or select software rendering to manufacture acceptance. See [MAUI packaging](WEB_GAME_PACKAGING.md).

## Rendering scope

Ray tracing and path tracing are deferred. The default Three.js integration uses the existing raster WebGLRenderer with pmndrs postprocessing. Prioritize device coverage with the bounded LDR/FXAA profile and explicit actual-target checks. This capability does not select or install a tracing library, require WebGPU, upgrade Three.js or replace Quarks.
