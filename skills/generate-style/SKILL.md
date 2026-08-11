---
name: generate-style
description: Generate the host repository STYLE.md with one or more art-style templates plus a primary art pipeline and allowed alternatives. Use when creating or replacing the project visual contract.
---

## When to use
Use when `../STYLE.md` is missing or when the user wants to regenerate it after changing the repository art style mix.

## Workflow
1. If `../STYLE.md` is missing, ask the user which templates from `./.styles/` apply unless the user already named the desired style. Default the art pipeline to `CSS3` unless the user names another one.
2. Support multiple templates for mixed art-direction repositories.
3. Normalize `imagegen` to `CLOUD`, `comfyui` to `LOCAL`, `vector` to `CSS3`, `threejs` to `CODE`, and `blender`, `blend`, or `bpy` to `BLENDER`. Record exactly one primary and repeatable allowed alternatives.
4. Add repeatable optional external library roots only when the user explicitly configures them. Preserve existing entries during regeneration unless the user replaces or clears them; never prompt for them during startup or initial setup.
5. Generate `../STYLE.md` from the selected style and pipeline templates using concise read directives by default.
6. Use inline mode only when the user explicitly asks for fully embedded template content.
7. Validate the generated contract and treat it as authoritative afterward.

## Output

- A `STYLE.md` containing at least one style, exactly one primary pipeline, allowed pipelines, prompt-override scope, no-silent-fallback policy, and optional read-only external library roots.
- Style-contract validation output.

## Guardrails

- Do not default new contracts to generated imagery; use `CSS3` unless explicitly directed otherwise.
- Do not silently select a different pipeline when the chosen one is unavailable.
- Do not use a task-local override to rewrite `STYLE.md`.
- Do not invent, require, or probe an external asset-library path when none is configured.

## Commands
- `./commands/generate-style.sh "<STYLE1>" ["STYLE2" ...]`
- `./commands/generate-style.sh --pipeline CLOUD --allow-pipeline CODE "<STYLE1>"`
- `./commands/generate-style.sh --pipeline BLENDER --allow-pipeline CSS3 "<STYLE1>"`
- `./commands/generate-style.sh --asset-library studio=/absolute/path/to/models "<STYLE1>"`
- `./commands/generate-style.sh --clear-asset-libraries "<STYLE1>"`
- `./commands/generate-style.sh --inline "<STYLE1>" ["STYLE2" ...]`
- `./commands/validate-style-contract.sh [STYLE.md]`
