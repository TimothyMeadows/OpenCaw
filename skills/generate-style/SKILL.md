---
name: generate-style
description: Generate the host repository STYLE.md by composing one or more selected templates from ./.styles/.
---

## When to use
Use when `../STYLE.md` is missing or when the user wants to regenerate it after changing the repository art style mix.

## Workflow
1. If `../STYLE.md` is missing, ask the user which templates from `./.styles/` apply unless the user already named the desired style.
2. Support multiple templates for mixed art-direction repositories.
3. Generate `../STYLE.md` from the selected templates using concise read directives by default (for example `Read `./<mount>/.styles/ISOMETRIC_2_5D.md` instructions`) to avoid oversized files.
4. Use inline mode only when the user explicitly asks for fully embedded template content.
5. Treat `../STYLE.md` as the authoritative art style contract afterward.

## Commands
- `./commands/generate-style.sh "<STYLE1>" ["STYLE2" ...]`
- `./commands/generate-style.sh --inline "<STYLE1>" ["STYLE2" ...]`
