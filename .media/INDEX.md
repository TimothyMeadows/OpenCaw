# Generative Media Backends

OpenCaw keeps media policy provider-neutral while allowing concrete local adapters.

Available backend templates:

- `CLOUD_SESSION` - image and audio generation exposed by the active assistant or IDE session.
- `COMFYUI_LOCAL` - loopback-only image and audio generation through pinned ComfyUI tooling.

Supporting contracts:

- `toolchain.json` pins the supported local toolchain.
- `model-packs.json` describes reviewed starter models and workflows.
- `media-generation-manifest.schema.json` defines reproducibility, provenance, review, and promotion records.

Generate a host `MEDIA.md` only when a repository configures generative media. `STYLE.md` remains the authority for visual language.
