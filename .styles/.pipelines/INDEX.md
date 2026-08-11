# Art Pipelines

OpenCaw separates visual language from the method used to produce it. Every generated `STYLE.md` selects one or more art style templates and exactly one primary art pipeline.

Selectable pipelines:

- `CLOUD` - session-provided image generation with explicit cost, provenance, staging, and review controls.
- `LOCAL` - loopback-only ComfyUI image and audio generation using reviewed local GPU tooling.
- `CSS3` - CSS, mathematical geometry, and inline SVG/vector production without raster or WebGL dependencies.
- `CODE` - authored procedural Three.js models implemented as TypeScript or JavaScript.

Pipeline contracts:

- `cloud/PIPELINE.md`
- `local/PIPELINE.md`
- `css3/PIPELINE.md`
- `code/PIPELINE.md`

Shared generated-media provenance lives under `_shared/`. Pipeline-specific schemas, manifests, and reusable assets remain beside the pipeline that owns them.

`CSS3` is the default when style generation does not name a pipeline. A current user prompt may explicitly select any registered pipeline for one task without rewriting `STYLE.md`. Never switch pipelines silently after work begins.
