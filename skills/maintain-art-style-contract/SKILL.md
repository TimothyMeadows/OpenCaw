---
name: maintain-art-style-contract
description: Maintain, generate, or validate the host STYLE.md contract from OpenCaw art-style and art-pipeline templates. Use when visual work must preserve project art direction and its CLOUD, LOCAL, CSS3, CODE, or BLENDER production path.
---

## When to use
Use when `../STYLE.md` is missing, stale, newly generated, or relevant to any visual, game-art, generated-image, UI-art, sprite, tileset, VFX, or art-handoff task.

## Workflow
1. Read `../STYLE.md` first when it exists; treat it as the authoritative project art contract.
2. If `../STYLE.md` is missing or the user asks to change it, inspect `./.styles/INDEX.md` and `./.styles/.pipelines/INDEX.md`. Choose the smallest useful style set and default the primary pipeline to `CSS3` unless the user names another.
3. Generate or regenerate with `./commands/generate-style.sh [--pipeline PIPELINE] [--allow-pipeline PIPELINE ...] [--asset-library ID=ABSOLUTE_PATH ...] "<STYLE1>" ["STYLE2" ...]`; use `--inline` only when explicitly requested. Preserve configured libraries by default and clear them only on explicit request.
4. Validate the generated contract with `./commands/validate-style-contract.sh`.
5. During art production, check outputs against the active art style, resolved pipeline, and relevant role constraints.
6. When a style conflict affects gameplay readability, asset metadata, engine loading, or UI contrast, call out the impacted owner role before proceeding.

For Blender work, resolve the `BLENDER` pipeline, keep the selected templates authoritative, and route their application through `author-blender-materials-and-lookdev`, `light-and-frame-blender-scenes`, and `render-and-composite-blender-output`; do not create a Blender-specific style template.

## Output
- selected style template names
- primary and allowed art pipelines
- optional external asset-library ids and roots, without probing them during unrelated startup
- any missing or conflicting style instructions
- whether `STYLE.md` was generated, left unchanged, or needs user confirmation
- validation command output summary
- role handoff notes when style decisions affect game design, engineering, QA, or documentation

## Commands
- `./commands/generate-style.sh "<STYLE1>" ["STYLE2" ...]`
- `./commands/generate-style.sh --pipeline CODE --allow-pipeline CSS3 "<STYLE1>"`
- `./commands/generate-style.sh --pipeline BLENDER --allow-pipeline CSS3 "<STYLE1>"`
- `./commands/generate-style.sh --asset-library studio=/absolute/path/to/models "<STYLE1>"`
- `./commands/generate-style.sh --inline "<STYLE1>" ["STYLE2" ...]`
- `./commands/validate-style-contract.sh [STYLE.md]`
- `./commands/resolve-art-pipeline.sh [--override PIPELINE]`
