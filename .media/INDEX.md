# Generative Media Backends

OpenCaw keeps provider-neutral media policy and schemas here while allowing concrete local adapters to live with their production assets.

Available backend templates:

- `CLOUD_SESSION` - image and audio generation exposed by the active assistant or IDE session.
- `COMFYUI_LOCAL` - loopback-only image and audio generation through the pinned adapter at `.styles/.gpu/COMFYUI_LOCAL.md`.

Supporting contracts:

- `media-generation-manifest.schema.json` defines reproducibility, provenance, review, and promotion records.

Local GPU contracts:

- `.styles/.gpu/toolchain.json` pins the supported local toolchain.
- `.styles/.gpu/model-packs.json` describes reviewed starter models and workflows.

Generate a host `MEDIA.md` only when a repository configures generative media. `STYLE.md` remains the authority for visual language.
