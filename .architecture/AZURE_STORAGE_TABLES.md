# AZURE_STORAGE_TABLES.md

This repository follows an **Azure Storage Tables architecture** focused on key-driven access patterns, predictable partition behavior, and low-operational-overhead persistence.

The architecture is optimized for:

- key-value/table-style lookup workloads
- cost-effective large-scale entity storage
- partition-aware query design
- simple operational footprint

The goal is to keep the system:

- efficient
- predictable
- easy to scale
- safe at integration boundaries

---

# Core Architecture Rule

**Model `PartitionKey` and `RowKey` from first-class access patterns before defining entities.**

Prefer:

```text
Access pattern -> PartitionKey/RowKey strategy -> entity shape
```

Avoid:

```text
Entity shape first -> expensive scans + hot partitions
```

---

# Data Modeling Rules

- design entities around key-based retrieval
- treat non-key filtering as an exception, not the default
- keep entities narrow and stable for hot paths
- include explicit version or timestamp fields where update ordering matters
- define retention and archival behavior up front

---

# Partitioning and Query Rules

- distribute write load across partitions to avoid hotspots
- batch operations only within the same partition key
- avoid table scans in performance-critical workflows
- model alternate lookup needs with duplicate/derived entities when justified

---

# Consistency and Concurrency

- use ETag-based optimistic concurrency for updates and deletes
- define retry strategy for transient storage errors
- document eventual-consistency expectations for downstream consumers

---

# Security Rules

- prefer managed identity/RBAC over connection-string sprawl
- keep account names and table names in configuration
- scope permissions to minimum required operations
- avoid broad shared keys for app-level access when scoped credentials are available

---

# Operations and Reliability

- define naming conventions for accounts/tables/partitions
- monitor latency, throttling, and partition distribution
- test backup/export and recovery approaches for business-critical data
- document regional and failover assumptions

---

# Testing Strategy

- test key-path lookups and update concurrency behavior
- validate batch semantics for same-partition operations
- benchmark read/write behavior with representative partition distributions
- verify retry handling under transient failures

---

# Anti-Patterns

Never introduce:

- random or low-cardinality partition keys in high-write paths
- query patterns that rely on full scans for routine operations
- hidden coupling to storage account names in code
- updates that ignore ETag concurrency in contested records

When in doubt:

**Design around keys and partitions first, then optimize entity shape and retries.**

