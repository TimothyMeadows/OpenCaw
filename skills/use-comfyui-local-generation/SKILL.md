---
name: use-comfyui-local-generation
description: Provision and run pinned ComfyUI image or audio workflows through official tooling with license checks, loopback isolation, staged outputs, and receipts. Use when the user selects local GPU generation.
---

# Use ComfyUI Local Generation

## When to use

- The user has selected the `LOCAL` pipeline for a supported image or audio modality.
- Inspecting or provisioning a host for reviewed ComfyUI core-node workflows.
- Running a versioned workflow into a non-runtime staging directory.

## Workflow

1. For images, resolve `LOCAL` through `STYLE.md` or the current prompt. Read `MEDIA.md` and confirm local execution is configured for the requested modality.
2. Inspect the host before installing. Report GPU, VRAM, disk, Python, FFmpeg, CLI, server, workflow, and model-pack readiness.
3. On first local use, require the pinned toolchain before continuing. Preview installation, then use `--execute` only with explicit user authorization; later runs must pass the same idempotent readiness check.
4. Present each model source, revision, size, checksum, destination, and license; require matching license acceptance before download.
5. Launch on loopback with online API nodes disabled and no unreviewed custom nodes.
6. Run the workflow through structured CLI output, confine results to staging, hash outputs, and retain the run receipt.
7. Stop for human review; do not promote results as part of the run.

## Output

- A host capability report and idempotent installation record.
- Verified model and workflow files from pinned manifests.
- Staged generated files, hashes, structured execution evidence, and a run receipt.

## Guardrails

- Do not install GPU drivers, create accounts, accept licenses, or persist credentials for the user.
- Do not expose ComfyUI beyond loopback or enable online API nodes by default.
- Do not install unreviewed custom nodes automatically.
- Do not fall back to a cloud provider when local execution fails.
