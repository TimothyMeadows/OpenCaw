# Project Memory

- [kind:workflow] [area:dependencies] [topic:dependency-audit] Dependency installation is permitted for OpenCaw implementation and verification after a lightweight provenance, version, lifecycle-script, and vulnerability audit; reusable commands must remain non-self-installing.
- [kind:gotcha] [env:wsl] [env:windows] [topic:path-translation] OpenCaw validation can run under WSL while Node.js, Git, Playwright, and FFmpeg resolve as Windows executables; translate paths only at the runtime boundary and preserve already-native Windows paths.
- [kind:architecture] [area:memory] [tech:bash] Memory v2 keeps all memory artifacts under `<project-root>/.ai/`: always-loaded constraints in `SYSTEM_MEMORY.md`, tagged facts in `MEMORY.md`, and semantic structure in `REPO_MAP.md`.
- [kind:convention] [area:commands] [topic:path-boundaries] Commands that write project artifacts resolve the active project through `commands/lib/memory-common.sh` and fail closed when the repository boundary is ambiguous.
