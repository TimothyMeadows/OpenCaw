# COMFYUI_LOCAL.md

## Intent

Run reviewed image and audio workflows locally through the official `comfy-cli` and a pinned ComfyUI installation.

## Capability Discovery

- Inspect operating system, GPU and VRAM, disk, Python, FFmpeg, `comfy-cli`, ComfyUI, and required model files before offering this backend.
- On first local use, keep the backend unavailable until the pinned toolchain and the selected modality's licensed model pack are installed and verified.
- Treat unsupported hardware or an incomplete model pack as unavailable for that modality.
- When this backend and the cloud/session backend are both viable, require the user to choose one.

## Production Rules

- Install only after explicit `--execute`; keep dry-run as the default.
- Require every model-pack license identifier before downloading and use environment-provided Hugging Face credentials for gated sources.
- Pin ComfyUI, `comfy-cli`, model revisions, workflow revisions, sizes, and checksums through `.styles/.gpu` manifests.
- Bind the server to loopback, disable online API nodes, and do not install unreviewed custom nodes.
- Submit workflows through structured `comfy --json` output and confine downloaded results to a staging directory.
- Hash staged outputs and write a run receipt. Promotion is a separate human-reviewed action.

## Boundaries

- Do not install or update GPU drivers, create vendor accounts, persist credentials, or accept licenses for the user.
- Do not silently fall back to a cloud provider when local execution fails.
- Do not automatically repair corrupt, malformed, or policy-rejected outputs.
