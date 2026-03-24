---
name: install-database-cli-tools
description: Install or preview installation commands for database CLI tooling across MSSQL, MySQL, Cosmos DB, Azure Storage Tables, SQLite, PostgreSQL, and Databricks.
---

## When to use
Use when a task requires local CLI tooling for database administration, connectivity checks, or query execution and the environment does not yet have required clients installed.

## Output
- selected target engine(s)
- install mode (`dry-run` or `execute`)
- package manager path used
- any unsupported platform or package-manager constraints

## Workflow
1. Identify which engine CLI clients are required for the task.
2. Prefer dry-run output first to confirm exact install commands.
3. Execute installation only when requested and safe for the environment.
4. Verify core binaries are available in `PATH` after install.

## Command
- `./commands/install-database-cli-tools.sh --engine <name|all>`
- `./commands/install-database-cli-tools.sh --engine <name|all> --execute`

