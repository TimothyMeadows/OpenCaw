# Repository Map

<!-- OPENCAW_REPO_MAP_FINGERPRINT: f6e040c8749612cd6eb10917ea696353e0762ecc8dcea195b4bbd3f081f4f868 -->

- [kind:component] [scope:core] `AGENTS.md` is the authoritative OpenCaw baseline contract for startup, memory, task, verification, and delivery behavior.
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
