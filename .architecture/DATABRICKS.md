# DATABRICKS.md

This repository follows a **Databricks architecture** focused on governed lakehouse design, reproducible data pipelines, and cost-aware analytical processing.

The architecture is optimized for:

- Delta Lake reliability
- medallion-layered data refinement
- SQL and Spark workload separation
- governed multi-team data platforms

The goal is to keep the system:

- trustworthy
- observable
- reproducible
- efficient at scale

---

# Core Architecture Rule

**Treat data products as governed software artifacts: versioned logic, validated quality, and explicit ownership.**

Prefer:

```text
Bronze ingest -> Silver conformance -> Gold consumption contracts
```

Avoid:

```text
Ad hoc notebook-only transformations as production contracts
```

---

# Lakehouse Modeling Rules

- use Delta tables for managed ACID behavior
- define table ownership and lifecycle by data domain
- partition and cluster based on real query/access patterns
- preserve raw source fidelity in bronze before destructive transforms

---

# Governance and Catalog Rules

- use Unity Catalog for central governance where available
- define data classification and access policies explicitly
- keep schema evolution controlled with compatibility expectations
- tag and document critical datasets for discoverability

---

# Pipeline and Job Rules

- move production logic into versioned jobs/pipelines
- keep notebook code modular and reusable
- define idempotency and late-data handling behavior
- separate orchestration concerns from transform logic

---

# Performance and Cost Rules

- right-size clusters/jobs for workload class
- prefer autoscaling and policy-driven guardrails
- monitor query/runtime cost, shuffle pressure, and job reliability
- tune file sizes/compaction strategy for stable read performance

---

# Security Rules

- prefer managed identities/service principals over shared personal tokens
- enforce least privilege at catalog/schema/table levels
- externalize workspace, catalog, and secret references via environment configuration
- audit access and lineage for sensitive datasets

---

# Testing and Data Quality

- add pipeline validation checks for schema, nullability, and referential assumptions
- test transformations with representative datasets
- validate backward compatibility for downstream gold consumers
- gate production promotion on quality checks and run stability

---

# Anti-Patterns

Never introduce:

- one-off manual notebook edits as production-only logic
- unmanaged schema drift in shared tables
- hidden dependencies on personal workspace paths
- cost-intensive full rewrites without partition/pruning strategy

When in doubt:

**Favor governed Delta contracts, reproducible jobs, and explicit quality gates.**

