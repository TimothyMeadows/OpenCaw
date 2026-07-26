---
name: create-host-ai-scaffold
description: Create the repository-local Memory v2 scaffold, seed protected system memory under the project `.ai` directory, and ensure host AGENTS bootstrap points to OpenCaw when missing. Use at first startup or when required memory, map, task, or bootstrap artifacts are absent.
---

## When to use
Use when the host repo does not yet have the expected `.ai` structure or when OpenCaw bootstrap wiring is missing from the host root `AGENTS.md`.

## Output
- Resolved project `.ai/SYSTEM_MEMORY.md` exists with protected defaults.
- The project `.ai` directory contains all system memory, tagged memory, semantic map, rules, debug, archive, migration, report, and task files.
- Host root `AGENTS.md` includes a managed OpenCaw bootstrap block.
- Existing host `AGENTS.md` content is preserved; bootstrap block is appended only if missing.
- Legacy untagged memory is reported for AI-classified migration and is never silently rewritten.

## Command
../commands/create-host-ai-scaffold.sh
