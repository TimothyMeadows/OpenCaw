# Repository Map

<!-- OPENCAW_REPO_MAP_FINGERPRINT: 059ca8bb27d02b35e97aca1facbe9e3afaffa4b467e10ce586df6850793cd5ea -->

- [kind:component] [scope:core] `AGENTS.md` is the authoritative OpenCaw baseline contract for startup, memory, task, verification, and delivery behavior.
- [kind:component] [area:commands] [tech:bash] `commands/` contains deterministic executable workflows; `commands/lib/memory-common.sh` centralizes Memory v2 path, schema, safety, archive, and fingerprint behavior.
- [kind:component] [area:skills] `skills/` contains reusable reasoning workflows and UI metadata; `skills/INDEX.md` is the human-facing catalog.
- [kind:config] [area:roles] `.roles/ROLE_SKILL_MAP.json` is the authoritative role capability mapping and generates `.roles/ROLE_SKILL_MAP.md`.
- [kind:test] [area:memory] [tech:bash] `tests/test-memory-system.sh` verifies root isolation, system and tagged memory, migration, retrieval, purge, replacement, cleanup, and repository-map freshness.
- [kind:test] [scope:core] [tech:bash] `commands/validate-opencaw.sh` is the integrated structural validation entry point.
- [kind:command] [area:memory] [tech:bash] `commands/query-project-context.sh` lists tags and retrieves ranked memory and repository-map entries before raw searches.
- [kind:command] [area:scaffold] [env:windows] [tech:powershell] `commands/install-windows-bash.ps1` discovers native Git Bash or WSL, performs only explicitly requested installation, and can invoke `create-host-ai-scaffold.sh` through the selected provider.
- [kind:component] [area:media] `.media/` owns provider-neutral generative-media guidance and schemas, while `.styles/.gpu/` owns the local ComfyUI backend template, pinned toolchain, and reviewed model packs.
- [kind:command] [area:media] [tech:bash] `commands/generate-media-contract.sh` composes cloud and optional local backend instructions; local install, model, and inspection commands resolve pinned assets from `.styles/.gpu/`.
- [kind:test] [area:media] [tech:bash] `tests/test-generative-media.sh` verifies backend path ownership, contract composition, local safety gates, staged workflows, manifests, and integrated validation.
