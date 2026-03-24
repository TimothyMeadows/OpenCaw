# SQLITE.md

This repository follows a **SQLite architecture** focused on deterministic local persistence, simple deployment, and safe concurrency for embedded or lightweight workloads.

The architecture is optimized for:

- local-first or edge workloads
- low-overhead relational storage
- deterministic file-based deployment
- high read, moderate write scenarios

The goal is to keep the system:

- simple
- reliable
- testable
- easy to migrate

---

# Core Architecture Rule

**Treat SQLite as an embedded relational engine with explicit concurrency and migration constraints.**

Prefer:

```text
Bounded local workload -> explicit schema + migrations -> controlled write concurrency
```

Avoid:

```text
Server-grade multi-writer assumptions without coordination
```

---

# Data Modeling Rules

- enforce primary/foreign key constraints
- enable `PRAGMA foreign_keys = ON` in all runtime paths
- keep schema explicit and versioned
- avoid oversized rows and unbounded text/blob fields in hot tables

---

# Concurrency and Durability Rules

- use WAL mode for mixed read/write workloads when appropriate
- keep write transactions short
- coordinate concurrent writers at application level
- define timeout/retry behavior for database locks

---

# Query and Indexing Rules

- parameterize all queries
- add indexes only for validated filter/sort paths
- inspect query plans for hot-path operations
- avoid N+1 query behavior in embedded loops

---

# Operations and Lifecycle

- manage schema with versioned migrations
- define file location, backup, and retention policies
- validate startup migration behavior in upgrade scenarios
- treat database files as sensitive data for access control and encryption

---

# Security Rules

- protect file permissions and storage location
- externalize encryption key handling when encryption is used
- avoid exposing raw SQLite files in logs, artifacts, or debug dumps

---

# Testing Strategy

- run migration tests against real SQLite files
- test lock contention and retry behavior
- verify durability assumptions across process restarts
- exercise backup/restore workflows for user-critical data

---

# Anti-Patterns

Never introduce:

- assumptions of unlimited concurrent writers
- schema changes without migration/version control
- unbounded full-table scans in user-visible hot paths
- hidden reliance on SQLite defaults that differ by environment

When in doubt:

**Favor explicit pragmas, explicit migrations, and explicit write-concurrency control.**

