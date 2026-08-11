---
name: select-art-pipeline
description: Resolve CLOUD, LOCAL, CSS3, CODE, or BLENDER for a visual task from a task-local prompt override or STYLE.md, record selection evidence, and stop on failure instead of switching pipelines. Use for visual implementation, generated imagery, CSS/SVG art, authored Three.js models, or Blender production.
---

# Select Art Pipeline

## When to use

- Starting any visual or art-production request governed by `STYLE.md`.
- A prompt explicitly requests image generation, local ComfyUI, CSS/vector art, code-first Three.js models, or Blender production.
- Explaining which pipeline is active without changing the repository contract.

## Workflow

1. Read and validate `STYLE.md` with `./commands/validate-style-contract.sh`.
2. Normalize explicit prompt language to `CLOUD`, `LOCAL`, `CSS3`, `CODE`, or `BLENDER`. A prompt override may select any registered pipeline, including one outside the contract's allowed alternatives.
3. Resolve the prompt override before the primary pipeline with `./commands/resolve-art-pipeline.sh`. If no override exists, use the primary pipeline in `STYLE.md`.
4. For an override, write the resolver evidence below the active `.ai/tasks/<task>/` folder. Preserve `selectionSource: prompt` and the active style-contract hash.
5. Read the resolved pipeline contract under `.styles/.pipelines/` and follow it together with the selected art-style template.
6. For `CLOUD` or `LOCAL` image generation, also read `MEDIA.md`. `CSS3`, `CODE`, and `BLENDER` do not require `MEDIA.md`; read it for Blender only when cloud/local generated inputs are also in scope.
7. If the selected capability is unavailable or fails, stop and report the failure.

## Output

- Canonical selected pipeline and whether it came from the prompt or `STYLE.md`.
- Active style-contract path and SHA-256.
- Task-local evidence path when a prompt override is used.
- A clear stop reason when the selected pipeline cannot proceed.

## Guardrails

- Do not rewrite `STYLE.md` for a task-local prompt override.
- Do not silently switch or fall back between pipelines.
- Do not require `MEDIA.md` for `CSS3`, `CODE`, or ordinary `BLENDER` work.
- Keep selection evidence below `.ai/tasks/` and never persist credentials.

## Commands

- `./commands/resolve-art-pipeline.sh [--style STYLE.md] [--override PIPELINE] [--json] [--evidence .ai/tasks/<task>/pipeline-selection.json]`
- `./commands/validate-style-contract.sh [STYLE.md]`
