---
name: create-host-ai-scaffold
description: Create the recommended host repository .ai scaffold and ensure host AGENTS bootstrap points to OpenCaw when missing.
---

## When to use
Use when the host repo does not yet have the expected `.ai` structure or when OpenCaw bootstrap wiring is missing from the host root `AGENTS.md`.

## Output
- Host `.ai` directory structure exists with baseline memory/task files.
- Host root `AGENTS.md` includes a managed OpenCaw bootstrap block.
- Existing host `AGENTS.md` content is preserved; bootstrap block is appended only if missing.

## Command
../commands/create-host-ai-scaffold.sh
