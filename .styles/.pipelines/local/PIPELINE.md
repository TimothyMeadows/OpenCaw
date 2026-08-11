# LOCAL Art Pipeline

## Intent

Run reviewed image and audio workflows locally through pinned ComfyUI tooling and the host GPU.

## Inputs

- A selected image or audio modality and active `MEDIA.md` contract.
- A compatible host inspection result, reviewed model pack, workflow, and explicit license acceptance.
- The active `STYLE.md` for image work.

## Production Rules

- Inspect operating system, GPU and VRAM, disk, Python, FFmpeg, `comfy-cli`, ComfyUI, and required model files before offering this pipeline.
- Keep installation dry-run by default and require explicit execution authorization.
- Pin tools, models, workflows, revisions, sizes, destinations, and checksums through the local manifests in this directory.
- Bind the server to loopback, disable online API nodes, and reject unreviewed custom nodes.
- Confine downloaded results to staging, hash outputs, and retain a structured run receipt.
- Stop when local execution fails. Never fall back to the cloud pipeline silently.

## Output Contract

- Verified local tools and model packs remain outside the repository runtime tree.
- Generated candidates remain staged with hashes, workflow evidence, and pending human review.
- Promotion is separate from provisioning and generation.

## Acceptance Checks

- Verify hardware viability, disk, license acceptance, credentials, checksums, workflow structure, output paths, and runtime budgets.
- Review image and audio candidates before promotion.

## Role Fit

Use with `generative-media-pipeline-engineer`, `generative-art-designer`, `sound-designer`, and `ai-engineer`.
