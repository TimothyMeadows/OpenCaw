# MYSQL.md

This repository follows a **MySQL architecture** focused on durable InnoDB data models, predictable query behavior, and safe evolution under production load.

The architecture is optimized for:

- InnoDB transactional workloads
- clear relational modeling
- operationally safe replication and backup
- efficient query patterns

The goal is to keep the system:

- reliable
- performant
- migration-friendly
- secure by default

---

# Core Architecture Rule

**Use InnoDB with explicit constraints and transaction boundaries as the default persistence contract.**

Prefer:

```text
Use case -> parameterized SQL -> constrained InnoDB tables
```

Avoid:

```text
Mixed storage engines + implicit constraints + ad hoc transaction behavior
```

---

# Data Modeling Rules

- default to `utf8mb4` character set and explicit collation
- define primary keys for all tables
- model foreign keys unless there is a documented scalability exception
- avoid nullable columns for required domain facts
- keep row shape lean for hot tables

---

# Query and Indexing Rules

- use parameterized queries only
- index for real filter and join patterns, not hypothetical access paths
- validate plans with `EXPLAIN` and runtime metrics
- avoid functions on indexed columns in critical predicates
- review slow query log and performance schema regularly

---

# Transaction and Consistency Rules

- keep transactions short and explicit
- define isolation assumptions per workflow
- use idempotent write patterns for retried operations
- avoid hidden autocommit side effects in multi-step operations

---

# Replication and Operations

- document replication topology and failover policy
- define binlog retention and recovery expectations
- test backup/restore workflows regularly
- keep schema migration scripts versioned and repeatable

---

# Security Rules

- use least-privilege database users by workload
- rotate credentials and avoid embedding secrets in code
- restrict direct production access paths
- audit privileged grants and schema-change permissions

---

# Testing Strategy

- validate DDL and migrations in pre-production
- execute regression query suites for critical APIs/reports
- test replication lag tolerance for read-scaling scenarios
- verify rollback plans for high-risk migrations

---

# Anti-Patterns

Never introduce:

- non-deterministic ordering assumptions without `ORDER BY`
- broad `SELECT *` on large tables in service hot paths
- long transactions that hold locks across external calls
- schema changes applied directly in production without rehearsal

When in doubt:

**Keep transactions explicit, schemas constrained, and query plans observable.**

