# COSMOSDB.md

This repository follows an **Azure Cosmos DB architecture** focused on partition-aware modeling, predictable RU consumption, and globally resilient behavior.

The architecture is optimized for:

- partitioned NoSQL workloads
- high-availability multi-region scenarios
- predictable request unit (RU) planning
- explicit consistency tradeoffs

The goal is to keep the system:

- scalable
- cost-aware
- latency-aware
- operationally transparent

---

# Core Architecture Rule

**Choose partition keys based on dominant access patterns first; everything else is downstream of that decision.**

Prefer:

```text
Access pattern -> partition key -> document model -> indexing policy
```

Avoid:

```text
Document model first -> accidental hot partitions -> expensive cross-partition queries
```

---

# Data Modeling Rules

- model documents around use-case boundaries
- keep document size controlled and predictable
- denormalize intentionally where read paths justify it
- include version fields for evolving document shapes
- define retention and TTL behavior explicitly

---

# Partitioning and Throughput Rules

- choose high-cardinality partition keys that distribute write load
- validate hot-partition risk with realistic traffic assumptions
- set RU/autoscale strategy per container workload
- isolate bursty workloads from steady-state workloads when needed

---

# Query and Indexing Rules

- avoid unbounded cross-partition queries in service hot paths
- tune indexing policy to reduce unnecessary write RU cost
- parameterize all queries
- use continuation tokens for large result sets

---

# Consistency and Transactions

- set consistency level intentionally per workload
- use transactional batch or stored procedures only within a single logical partition
- design idempotent retries for throttling (429) and transient failures

---

# Security and Governance

- prefer Azure AD / managed identity over shared keys where possible
- apply least-privilege RBAC and scoped access
- keep account, database, and container names externalized in configuration
- monitor diagnostic logs for throttling and auth anomalies

---

# Operations and Reliability

- define backup/restore and regional failover expectations
- monitor RU consumption, latency percentiles, and throttling rates
- validate failover behavior in non-production before relying on it
- document data residency and compliance constraints

---

# Testing Strategy

- replay representative query/write mixes against realistic partition keys
- test throttling behavior and retry policies
- verify schema evolution logic for backward compatibility
- load test high-cardinality and worst-case partitions

---

# Anti-Patterns

Never introduce:

- low-cardinality partition keys for high-throughput containers
- unrestricted cross-partition scans in latency-sensitive APIs
- over-indexing every property without RU/cost justification
- undocumented consistency assumptions

When in doubt:

**Protect partition health first, then optimize RU, latency, and indexing as a system.**

