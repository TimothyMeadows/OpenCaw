# Generative Media Assets

OpenCaw keeps all generative-media templates, schemas, and pinned local GPU assets in this directory. These files support media production but are not selectable art-style templates.

Available backend templates:

- `CLOUD_SESSION` - image and audio generation exposed by the active assistant or IDE session.
- `COMFYUI_LOCAL` - loopback-only image and audio generation through the pinned local adapter.

Supporting contracts:

- `media-generation-manifest.schema.json` defines reproducibility, provenance, review, and promotion records.

Local GPU contracts:

- `toolchain.json` pins the supported local toolchain.
- `model-packs.json` describes reviewed starter models and workflows.

Generate a host `MEDIA.md` only when a repository configures generative media. `STYLE.md` remains the authority for visual language.
