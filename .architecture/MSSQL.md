# MSSQL.md

This repository follows an **MSSQL architecture** focused on deterministic schema design, predictable performance, and safe operational behavior across SQL Server and Azure SQL deployments.

The architecture is optimized for:

- SQL Server / Azure SQL compatibility
- explicit schema ownership
- transactional consistency
- measurable performance tuning
- secure data access boundaries

The goal is to keep the system:

- relationally correct
- resilient under load
- easy to observe and optimize
- safe for schema evolution

---

# Core Architecture Rule

**Business invariants must be enforced in schema constraints and transaction boundaries, not only in application code.**

Prefer:

```text
Application intent -> parameterized SQL -> constrained schema + explicit transaction scope
```

Avoid:

```text
Implicit conversions + ad hoc SQL + missing constraints
```

---

# Data Modeling Rules

- use explicit schemas (for example `dbo`, `sales`, `identity`) with clear ownership
- define primary keys and foreign keys for all relationship-critical tables
- prefer narrow, stable clustered index keys
- avoid random GUID clustered keys for high-write tables unless fragmentation strategy is explicit
- use `rowversion` or equivalent optimistic concurrency where concurrent updates are expected

---

# Query and Indexing Rules

- use parameterized queries only
- verify plans with Query Store and execution plan analysis
- align nonclustered indexes with real filter/sort patterns
- avoid over-indexing write-heavy tables
- add filtered indexes only with a clear selectivity rationale

---

# Transaction and Concurrency Rules

- define transaction boundaries per use case
- set isolation expectations explicitly
- prefer `READ COMMITTED SNAPSHOT` for mixed read/write workloads when appropriate
- handle deadlocks with retry policy and ordering discipline

---

# Security Rules

- use least-privilege database roles
- separate read/write/service principals when possible
- keep secrets and connection strings externalized
- prefer managed identity or integrated auth paths where available
- audit privileged changes and schema modifications

---

# Operations and Reliability

- use versioned, idempotent migration scripts
- define backup/restore and point-in-time recovery expectations
- document HA/DR posture (for example failover groups, replicas, RPO/RTO)
- monitor wait stats, IO pressure, blocking, and long-running queries

---

# Testing Strategy

- validate migrations in isolated environments before production rollout
- run regression queries for critical reports and APIs
- load test write-heavy and high-fanout read paths
- verify rollback behavior for each migration release

---

# Anti-Patterns

Never introduce:

- dynamic SQL with string concatenation from untrusted inputs
- schema changes without backward-compatibility planning
- long-running transactions across external calls
- implicit dependency on default collation or timezone behavior

When in doubt:

**Favor explicit constraints, explicit transactions, and measured indexing decisions.**

