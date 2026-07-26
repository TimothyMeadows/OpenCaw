---
name: maintain-repository-map
description: Create, query, validate, and refresh OpenCaw's tagged semantic repository map. Use at first project startup, when the Git-visible path fingerprint is missing or stale, after structural file changes, or when exploration discovers durable component responsibilities, entry points, configuration, tests, or commands.
---

## When to use

Use before broad repository searches and whenever structural changes or new architectural evidence may have made the map incomplete.

## Workflow

1. Resolve the active project and run `./commands/repo-map-status.sh`.
2. Query existing map tags before exploring files.
3. If missing, empty, or stale, inspect tracked manifests, top-level components, entry points, configuration, tests, and common commands.
4. Write concise tagged semantic entries to `REPO_MAP.md`; use repository-relative paths and describe responsibility rather than listing every file.
5. Validate the map, then run `./commands/repo-map-status.sh --stamp` only after semantic entries reflect the current structure.

## Output

- tagged component, entrypoint, config, test, and command entries
- current Git-visible project-path fingerprint
- explicit current, stale, empty, or missing status

## Guardrails

- Do not replace semantic responsibilities with a raw tree dump.
- Exclude `.ai` and the mounted OpenCaw baseline from the project fingerprint.
- Do not stamp an empty or unverified map.
- Refresh on versionable path additions, removals, or moves; content-only edits do not require a fingerprint change.
