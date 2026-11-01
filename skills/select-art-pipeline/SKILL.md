---
name: select-art-pipeline
description: Resolve CLOUD, LOCAL, PROOF_TO_MODEL, CODE, or BLENDER for a visual task from a task-local prompt override or STYLE.md, record selection evidence, and stop on failure instead of switching pipelines. Use for 2D-to-3D assets, generated imagery, authored Three.js models, or Blender production. CSS/SVG interface work uses the style contract without selecting a retired pipeline.
engines: [AGNOSTIC]
---

# Select Art Pipeline

## When to use

- Starting any visual or art-production request governed by `STYLE.md`.
- A prompt explicitly requests proof-to-model assets, image generation, direct Bubo LOCAL generation, code-first Three.js models, or Blender production.
- CSS/SVG interface-only work follows style guidance independently; do not start reconstruction or resolve a retired vector pipeline.
- Explaining which pipeline is active without changing the repository contract.

## Workflow

1. Read and validate `STYLE.md` with `./commands/validate-style-contract.sh`.
2. Normalize explicit prompt language to `CLOUD`, `LOCAL`, `PROOF_TO_MODEL`, `CODE`, or `BLENDER`. A prompt override may select any registered pipeline, including one outside the contract's allowed alternatives.
3. Resolve the prompt override before the primary pipeline with `./commands/resolve-art-pipeline.sh`. If no override exists, use the primary pipeline in `STYLE.md`.
4. For an override, write the resolver evidence below the active `.hephaera/.cache/tasks/<task>/` folder. Preserve `selectionSource: prompt` and the active style-contract hash.
5. Read the resolved pipeline contract under `.styles/.pipelines/` and follow it together with the selected art-style template.
6. For `CLOUD` or `LOCAL` image generation, also read `MEDIA.md`. Existing-proof `PROOF_TO_MODEL`, `CODE`, and `BLENDER` do not require `MEDIA.md`; read it whenever cloud/local generated inputs are in scope. Route PROOF_TO_MODEL to `build-proof-to-model-assets`; never implicitly invoke a generator.
7. If the selected capability is unavailable or fails, stop and report the failure.
8. Route LOCAL generation to `use-bubo-local-generation` through the pinned Bubo runtime. Selection alone never authorizes setup, model loading, generation, an additional candidate/revision allowance or runtime promotion. Audio uses MEDIA policy independently of this visual selection workflow.

## Output

- Canonical selected pipeline and whether it came from the prompt or `STYLE.md`.
- Active style-contract path and SHA-256.
- Task-local evidence path when a prompt override is used.
- A clear stop reason when the selected pipeline cannot proceed.

## Guardrails

- Do not rewrite `STYLE.md` for a task-local prompt override.
- Do not silently switch or fall back between pipelines.
- Do not require `MEDIA.md` for existing-proof `PROOF_TO_MODEL`, `CODE`, or ordinary `BLENDER` work. Reject retired CSS3/CSS/vector/css-vector pipeline aliases and explain migration.
- Keep selection evidence below `.hephaera/.cache/tasks/` and never persist credentials.

## Commands

- `./commands/resolve-art-pipeline.sh [--style STYLE.md] [--override PIPELINE] [--json] [--evidence .hephaera/.cache/tasks/<task>/pipeline-selection.json]`
- `./commands/validate-style-contract.sh [STYLE.md]`
