# Repository Map

<!-- OPENCAW_REPO_MAP_FINGERPRINT: 1e0c23425a7c8bf77fdc247d6fc7bc1b28695159389b8caf23b239c7b7b8e113 -->

- [kind:component] [scope:core] `AGENTS.md` is the authoritative OpenCaw baseline contract for startup, memory, task, verification, and delivery behavior.
- [kind:architecture] [scope:core] OpenCaw's hierarchy is optional explicit persistent Brainstorm discovery, planning, then one sibling delivery mode: default task, explicit Goal, or explicit Gauntlet.
- [kind:component] [area:brainstorm] Repository-root `BRAINSTORM.md` stores active session state, stable branch definitions, and full researched idea elements; `BRAINSTORM_SUMMARY.md` is the generated hash-bound exit index.
- [kind:command] [area:brainstorm] [tech:bash] `commands/brainstorm-mode.sh`, `validate-brainstorm.sh`, and `show-brainstorm.sh` implement persistent lifecycle state, schema and summary validation, Mermaid mindmap rendering, and verbatim Markdown display through `commands/lib/brainstorm-common.sh`.
- [kind:test] [area:brainstorm] [tech:bash] `tests/test-brainstorm-flow.sh` verifies dry runs, sticky sessions, branches/elements, plan readiness, summary hashes, reactivation, visualization, path isolation, and Task/Goal/Gauntlet creation guards.
- [kind:component] [area:gauntlet] `.ai/gauntlets/<name>/GAUNTLET.md` is a Gauntlet's live contract; `rounds/`, `pr-events/`, `completion-events/`, and `promotion-events/` store one-to-one hashed critic, progress-PR, successful-completion, and promotion-QA evidence, while `GAUNTLET_REPORT.md` records complete, stopped, or blocked delivery state.
- [kind:command] [area:gauntlet] [tech:bash] `commands/create-gauntlet-file.sh`, `validate-gauntlet.sh`, `record-gauntlet-round.sh`, `record-gauntlet-pr-event.sh`, `record-gauntlet-promotion-qa.sh`, and `create-gauntlet-completion-report.sh` implement the root-confined, Git/GitHub-bound, transactionally locked Gauntlet lifecycle; `pr-readiness-check.sh --gauntlet-progress` authorizes approved progress publication while `--gauntlet` retains human promotion approval.
- [kind:test] [area:gauntlet] [tech:bash] `tests/test-gauntlet-flow.sh` covers real refs, frozen execution/bar/scope contracts, fetch/push and same-repo identity, semantic live QA comments, terminal GitHub replay, gapless merge topology, transitive causal remediation, supersession authorization, report-bound immutable completion, concurrency safety, promotion transitions, and task/goal compatibility.
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
