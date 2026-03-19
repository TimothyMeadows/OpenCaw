# AZURE.md

This repository follows an **Azure cloud integration architecture** focused on configuration-driven services, clear boundary ownership, and safe operational behavior.

The architecture is optimized for:

- Azure Functions
- Azure Storage
- Azure Service Bus
- Azure API Management
- Managed Identity
- configuration-driven deployment

The goal is to keep the system:

- environment-aware
- secure by default
- explicit about infrastructure assumptions
- testable where possible
- maintainable in enterprise environments

---

# Core Architecture Rule

**Application logic should not be tightly coupled to Azure implementation details.**

Prefer:

```text
Application Logic -> Abstractions -> Azure Implementations
```

Avoid:

```text
Business Logic -> direct SDK calls everywhere
Controllers/Handlers -> direct environment-specific wiring
```

---

# Configuration Rules

All Azure-dependent configuration should be externalized.

Examples:
- storage account names
- queue/topic names
- connection settings
- endpoint URIs
- tenant or subscription-sensitive values

Rules:
- do not hardcode resource names unless explicitly required
- prefer environment-driven configuration
- document required settings clearly
- differentiate local development assumptions from deployed environment assumptions

---

# Identity and Security

Prefer:
- managed identity
- least privilege
- explicit RBAC assumptions
- secret minimization

Rules:
- avoid embedding secrets in code
- keep auth assumptions explicit
- document required roles and permissions
- keep local dev auth flows separate from production auth expectations

---

# Azure Functions

Functions should:
- keep trigger and binding behavior explicit
- isolate application logic from function host plumbing
- avoid large function classes full of mixed concerns
- push reusable logic into application/service layers

Avoid:
- business rules buried directly inside triggers
- hidden environment assumptions
- untestable static coupling

---

# Storage Rules

Storage-related logic should:
- isolate blob/container naming concerns
- centralize upload/download conventions
- validate content handling at boundaries
- make auth/SAS/identity behavior explicit

Avoid:
- scattered storage SDK usage across unrelated layers
- hardcoded blob paths without ownership rules

---

# Service Bus Rules

Service Bus-related logic should:
- make queue/topic/subscription assumptions explicit
- define concurrency and ordering expectations
- define retry / poison message behavior
- isolate transport concerns from application rules

Avoid:
- hidden message ordering assumptions
- business logic coupled tightly to message transport details

---

# API Management Rules

APIM-related changes should:
- document impacted APIs/products/policies
- keep routing and versioning behavior explicit
- define deployment and rollback considerations
- separate API contract design from gateway policy mechanics

---

# Testing Strategy

- unit test application logic separately from Azure implementations
- integration test Azure-specific adapters where practical
- validate configuration contracts
- test operationally sensitive flows with clear environment assumptions

---

# Anti-Patterns

Never introduce:

- hardcoded cloud resource assumptions spread through the codebase
- direct Azure SDK coupling throughout business logic
- environment-sensitive behavior hidden in unrelated modules
- undocumented RBAC or deployment dependencies

When in doubt:

**Move Azure-specific behavior behind explicit boundaries and configuration contracts.**
