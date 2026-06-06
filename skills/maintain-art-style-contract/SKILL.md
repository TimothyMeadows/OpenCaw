---
name: maintain-art-style-contract
description: Maintain, generate, or validate the host repository STYLE.md art contract from OpenCaw .styles templates. Use when visual work must preserve a project art direction, when a user asks to choose or change art styles, or when art roles need to verify that STYLE.md still references valid style templates.
---

## When to use
Use when `../STYLE.md` is missing, stale, newly generated, or relevant to any visual, game-art, generated-image, UI-art, sprite, tileset, VFX, or art-handoff task.

## Workflow
1. Read `../STYLE.md` first when it exists; treat it as the authoritative project art contract.
2. If `../STYLE.md` is missing or the user asks to change the style mix, inspect `./.styles/INDEX.md` and select the smallest useful template set.
3. Generate or regenerate with `./commands/generate-style.sh "<STYLE1>" ["STYLE2" ...]`; use `--inline` only when the user explicitly asks for embedded template text.
4. Validate the generated contract with `./commands/validate-style-contract.sh`.
5. During art production, check outputs against both the active `STYLE.md` and the relevant role constraints.
6. When a style conflict affects gameplay readability, asset metadata, engine loading, or UI contrast, call out the impacted owner role before proceeding.

## Output
- selected style template names
- any missing or conflicting style instructions
- whether `STYLE.md` was generated, left unchanged, or needs user confirmation
- validation command output summary
- role handoff notes when style decisions affect game design, engineering, QA, or documentation

## Commands
- `./commands/generate-style.sh "<STYLE1>" ["STYLE2" ...]`
- `./commands/generate-style.sh --inline "<STYLE1>" ["STYLE2" ...]`
- `./commands/validate-style-contract.sh [STYLE.md]`
