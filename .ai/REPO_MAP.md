# Repository Map

<!-- OPENCAW_REPO_MAP_FINGERPRINT: aafc0043278d3bc753c78ebfb7d60449a6d082026e79a18421c636647caaa04b -->

- [kind:component] [scope:core] `AGENTS.md` is the authoritative OpenCaw baseline contract for startup, memory, task, verification, and delivery behavior.
- [kind:component] [area:commands] [tech:bash] `commands/` contains deterministic executable workflows; `commands/lib/memory-common.sh` centralizes Memory v2 path, schema, safety, archive, and fingerprint behavior.
- [kind:component] [area:skills] `skills/` contains reusable reasoning workflows and UI metadata; `skills/INDEX.md` is the human-facing catalog.
- [kind:config] [area:roles] `.roles/ROLE_SKILL_MAP.json` is the authoritative role capability mapping and generates `.roles/ROLE_SKILL_MAP.md`.
- [kind:test] [area:memory] [tech:bash] `tests/test-memory-system.sh` verifies root isolation, system and tagged memory, migration, retrieval, purge, replacement, cleanup, and repository-map freshness.
- [kind:test] [scope:core] [tech:bash] `commands/validate-opencaw.sh` is the integrated structural validation entry point.
- [kind:command] [area:memory] [tech:bash] `commands/query-project-context.sh` lists tags and retrieves ranked memory and repository-map entries before raw searches.
