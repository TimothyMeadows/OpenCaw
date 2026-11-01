---
name: threejs-build-postprocessing
description: Build Three.js screen effects with its default pmndrs postprocessing backend and verified WebGL2, MAUI and resource constraints.
engines: [THREEJS]
---

# Three.js Postprocessing

## When to use

Implement or review antialiasing, bloom, grading, outline, depth or other fullscreen effects for a Three.js host. THREEJS automatically selects pmndrs `postprocessing`; selection grants no installation, renderer change or target acceptance.

## Workflow

Resolve ENGINE and this skill. Read `docs/THREEJS_POSTPROCESSING.md`, the shared runtime README, host locks and real target requirements.

1. Inspect with `commands/threejs-postprocessing.sh inspect --renderer WebGLRenderer`. Verify one actual locked Three resolution shared with Quarks and compatible postprocessing APIs. Metadata-only discovery cannot establish installed bytes, context or shader readiness. Missing/unsupported dependencies require direction; do not install, upgrade or switch renderer silently.
2. Explicitly scaffold a fresh host module if useful. Own one composer after scene/Quarks updates on the existing presentation clock. The bounded starter uses WebGL2, byte targets and FXAA, with no MSAA/HDR. Do not render the scene a second time after composer output.
3. Validate real context and supported settings, physical resolution, DPR, frame time, effect/pass/texture budgets, alpha and color output. HDR/bloom/depth/MSAA profiles require separately reviewed capability probes, real framebuffer checks and target evidence; do not copy desktop defaults into mobile WebViews.
4. Connect resize, pause, MAUI `hephaera:lifecycle`, context loss/restoration and disposal. Preserve caller-owned renderer/scene/Quarks/assets and one clock. Release owned targets/passes/effects and listeners, and restore temporarily owned renderer state. Context restoration requires fresh validation.
5. Review actual packaged scenes on Windows WebView2, Android WebView and iOS/MacCatalyst WKWebView. Verify Quarks composition, readable UI, reduced motion/flash controls, suspend/resume, context restoration, memory and sustained frame times. Source/CPU/packaging checks do not establish GPU/device acceptance.

## Boundaries

Path tracing is a separate renderer. Do not install/select three-gpu-pathtracer, WebGPU or deprecated WebGL tracing as this postprocessing default. Keep STYLE/MAUI/engine selection and gameplay authority independent. Different versions, renderers or broader upstream effects require reviewed host integration, never a silent fallback.
