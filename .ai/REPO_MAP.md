# Repository Map

<!-- OPENCAW_REPO_MAP_FINGERPRINT: a5cbbab82d4205a0855b683af40172b551eeb664e76007c4639c450982fc1062 -->

- [kind:component] [scope:core] `AGENTS.md` is the authoritative OpenCaw baseline contract for startup, memory, task, verification, and delivery behavior.
- [kind:architecture] [scope:core] OpenCaw work selection has three sibling modes: task is the default one-assignment flow, goal is an explicit ordered multi-task delivery flow, and Gauntlet is an explicit adversarial single-deliverable flow.
- [kind:component] [area:gauntlet] `.ai/gauntlets/<name>/GAUNTLET.md` is a Gauntlet's live contract; its `rounds/<item-id>/round-NNN.md` files are immutable critic evidence and `GAUNTLET_REPORT.md` records complete, stopped, or blocked delivery state.
- [kind:command] [area:gauntlet] [tech:bash] `commands/create-gauntlet-file.sh`, `validate-gauntlet.sh`, `record-gauntlet-round.sh`, and `create-gauntlet-completion-report.sh` implement the root-confined Gauntlet lifecycle; `pr-readiness-check.sh --gauntlet` retains human PR approval.
- [kind:test] [area:gauntlet] [tech:bash] `tests/test-gauntlet-flow.sh` is the isolated regression suite for scaffold boundaries, frozen and revised bars, critic isolation, immutable rounds, integration reopening, reports, and task/goal/Gauntlet PR compatibility.
- [kind:component] [area:commands] [tech:bash] `commands/` contains deterministic executable workflows; `commands/lib/memory-common.sh` centralizes Memory v2 path, schema, safety, archive, and fingerprint behavior.
- [kind:component] [area:skills] `skills/` contains reusable reasoning workflows and UI metadata; `skills/INDEX.md` is the human-facing catalog.
- [kind:config] [area:roles] `.roles/ROLE_SKILL_MAP.json` is the authoritative role capability mapping and generates `.roles/ROLE_SKILL_MAP.md`.
- [kind:test] [area:memory] [tech:bash] `tests/test-memory-system.sh` verifies root isolation, system and tagged memory, migration, retrieval, purge, replacement, cleanup, and repository-map freshness.
- [kind:test] [scope:core] [tech:bash] `commands/validate-opencaw.sh` is the integrated structural validation entry point.
- [kind:command] [area:memory] [tech:bash] `commands/query-project-context.sh` lists tags and retrieves ranked memory and repository-map entries before raw searches.
- [kind:command] [area:scaffold] [env:windows] [tech:powershell] `commands/install-windows-bash.ps1` discovers native Git Bash or WSL, performs only explicitly requested installation, and can invoke `create-host-ai-scaffold.sh` through the selected provider.
- [kind:component] [area:media] `.styles/.gpu/` owns all generative-media backend templates, indexes, schemas, pinned toolchains, and reviewed model packs; `.media/` is prohibited.
- [kind:command] [area:media] [tech:bash] `commands/generate-media-contract.sh` composes cloud and optional local backend instructions; local install, model, and inspection commands resolve pinned assets from `.styles/.gpu/`.
- [kind:test] [area:media] [tech:bash] `tests/test-generative-media.sh` verifies backend path ownership, contract composition, local safety gates, staged workflows, manifests, and integrated validation.
