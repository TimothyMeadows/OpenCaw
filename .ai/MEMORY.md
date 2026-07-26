# Project Memory

- [kind:workflow] [area:dependencies] [topic:dependency-audit] Dependency installation is permitted for OpenCaw implementation and verification after a lightweight provenance, version, lifecycle-script, and vulnerability audit; reusable commands must remain non-self-installing.
- [kind:gotcha] [env:wsl] [env:windows] [topic:path-translation] OpenCaw validation can run under WSL while Node.js, Git, Playwright, and FFmpeg resolve as Windows executables; translate paths only at the runtime boundary and preserve already-native Windows paths.
- [kind:architecture] [area:memory] [tech:bash] Memory v2 keeps all memory artifacts under `<project-root>/.ai/`: always-loaded constraints in `SYSTEM_MEMORY.md`, tagged facts in `MEMORY.md`, and semantic structure in `REPO_MAP.md`.
- [kind:convention] [area:commands] [topic:path-boundaries] Commands that write project artifacts resolve the active project through `commands/lib/memory-common.sh` and fail closed when the repository boundary is ambiguous.
- [kind:workflow] [env:windows] [tech:powershell] Use `commands/install-windows-bash.ps1` to prefer existing native Git Bash, explicitly install Git Bash or WSL, and invoke the Bash scaffold; Linux and macOS do not use this bootstrap.
- [kind:architecture] [area:media] Keep provider-neutral generative-media guidance and schemas under .media/, and keep the local ComfyUI backend template, pinned toolchain, and reviewed model packs under .styles/.gpu/.
- [kind:bug] [area:media] [env:wsl] [env:windows] Under WSL on Windows, exact-line Bash checks of Git-managed Markdown may see a trailing CR from CRLF; normalize carriage returns before comparing headings or index entries.
- [kind:bug] [area:memory] [tech:bash] When a Bash printf format begins with a hyphen, pass -- before the format; commands/append-debug.sh requires this so debug entries can be appended reliably.
- [kind:decision] [area:repository] [topic:git-history] Published branches and tags exclude demo/ as of issue #80; README.md uses the GitHub-hosted attachment, and future demo binaries must not be re-added to repository history.
