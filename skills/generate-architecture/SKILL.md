---
name: generate-architecture
description: Generate the host repository ARCHITECTURE.md by composing one or more selected templates from ./.architecture/.
---

## When to use
Use when `../ARCHITECTURE.md` is missing or when the user wants to regenerate it after changing the repo architecture mix.

## Workflow
1. If `../ARCHITECTURE.md` is missing and `../.ai/` is also missing, ask the user which templates from `./.architecture/` apply.
2. Support multiple templates for mixed-stack repositories.
3. Save the selected template names to `../.ai/`.
4. Generate `../ARCHITECTURE.md` from the selected templates using concise read directives by default (for example `Read \`./<mount>/.architecture/DOTNET.md\` instructions`) to avoid oversized files.
5. Use inline mode only when the user explicitly asks for fully embedded template content.
6. Treat `../ARCHITECTURE.md` as the authoritative architecture contract afterward.

## Commands
- `./commands/generate-architecture.sh "<TEMPLATE1>" ["TEMPLATE2" ...]`
- `./commands/generate-architecture.sh --inline "<TEMPLATE1>" ["TEMPLATE2" ...]`
