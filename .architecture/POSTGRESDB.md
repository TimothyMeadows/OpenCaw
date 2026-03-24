# POSTGRESDB.md

This repository follows a **PostgreSQL architecture** focused on explicit schema contracts, strong relational integrity, and production-grade operational discipline.

The architecture is optimized for:

- transactional relational workloads
- advanced indexing and query planning
- safe schema evolution
- observable performance tuning

The goal is to keep the system:

- correct
- performant
- recoverable
- maintainable over time

---

# Core Architecture Rule

**Design schema, indexes, and transaction boundaries together based on real query patterns.**

Prefer:

```text
Use case -> schema + constraints -> indexes -> measured plans
```

Avoid:

```text
Schema-first without workload validation
```

---

# Data Modeling Rules

- organize tables into explicit schemas by domain
- enforce primary/foreign keys and check constraints
- use appropriate data types (`uuid`, `jsonb`, `timestamptz`, numeric types)
- avoid uncontrolled schema drift and implicit casts

---

# Query and Indexing Rules

- parameterize all application queries
- use index types intentionally (`btree`, `gin`, `gist`, `brin`)
- validate with `EXPLAIN (ANALYZE, BUFFERS)` for critical paths
- avoid index bloat by monitoring vacuum and maintenance behavior

---

# Transactions and Concurrency

- define transaction scopes per use case
- handle contention with optimistic or pessimistic locking intentionally
- keep long-running transactions out of request hot paths
- define idempotent retry behavior for transient conflicts

---

# Operations and Reliability

- use versioned migration tooling with rollback strategy
- define backup and point-in-time recovery expectations
- monitor autovacuum health, replication lag, and lock contention
- use connection pooling for high-concurrency applications

---

# Security Rules

- use least-privilege roles and grants
- isolate admin and app runtime identities
- externalize credentials and rotate secrets
- apply row-level security only with explicit policy design and testing

---

# Testing Strategy

- test migration up/down paths in isolated environments
- run query regression tests for critical joins and aggregations
- load test high-concurrency and write-heavy paths
- validate failover/recovery runbooks where replication is used

---

# Anti-Patterns

Never introduce:

- implicit schema coupling across unrelated bounded contexts
- unchecked `jsonb` usage where relational constraints are required
- long-lived idle transactions that block vacuum progress
- production migrations without dry runs and rollback planning

When in doubt:

**Keep constraints explicit, plans measurable, and operational hygiene non-optional.**

