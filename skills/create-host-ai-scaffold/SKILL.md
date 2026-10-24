---
name: create-host-ai-scaffold
description: Initialize durable project context at .opencaw/.cache, seed protected system memory, add Windows Bash guidance when applicable, and maintain the host AGENTS bootstrap for the fixed .opencaw installation. Use at first startup or when required memory, map, task, or bootstrap artifacts are absent.
engines: [AGNOSTIC]
---

## When to use
Use when the host repo does not yet have the expected `.opencaw/.cache` structure or when OpenCaw bootstrap wiring is missing from the host root `AGENTS.md`.

## Output
- Resolved project `.opencaw/.cache/SYSTEM_MEMORY.md` exists with protected defaults.
- The project `.opencaw/.cache` directory contains durable system memory, tagged memory, semantic map, rules, debug, archives, reports, and task files. It is ignored by the baseline's Git repository and must be preserved during ordinary updates.
- Host root `AGENTS.md` includes a managed bootstrap block that reads only `./.opencaw/AGENTS.md`.
- Existing host `AGENTS.md` content outside the managed block is preserved.
- Installs use only `<project-root>/.opencaw/`; alternate directory names and previous installations are unsupported. Scaffolding does not probe or copy previous install or memory locations.
- Root `ENGINE.md`, `ARCHITECTURE.md`, `STYLE.md`, optional `MEDIA.md`, and optional Brainstorm state remain at the project root.
- Windows hosts receive `.opencaw/.cache/WINDOWS_BASH.md` with safe Git Bash and WSL setup commands; Linux and macOS do not need the Windows bootstrap.
- Scaffold creation never installs Bash automatically.

## Commands

- From the project root: `bash ./.opencaw/commands/create-host-ai-scaffold.sh`
- Windows before Bash is available: `powershell -NoProfile -ExecutionPolicy Bypass -File "./.opencaw/commands/install-windows-bash.ps1" -RunScaffold -ProjectRoot .`
