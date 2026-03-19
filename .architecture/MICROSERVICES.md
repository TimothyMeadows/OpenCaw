# MICROSERVICES.md

This repository follows a **microservices architecture** focused on service autonomy, explicit contracts, and independently evolvable bounded contexts.

The goal is to keep the system:

- bounded by clear service responsibilities
- explicit about inter-service communication
- resilient to change
- deployable independently where possible
- maintainable at enterprise scale

---

# Core Architecture Rule

**Each service owns its own domain, contracts, data, and operational concerns.**

Prefer:

```text
Service A -> explicit contract -> Service B
```

Avoid:

```text
Service A -> direct database dependency on Service B
Shared internal models -> every service
```

---

# Service Boundaries

Each service should own:
- its domain model
- its persistence
- its API or messaging contracts
- its operational configuration

Rules:
- do not couple services through shared internal databases
- do not leak one service’s internal model across all others
- keep contracts explicit and version-aware

---

# Communication Rules

Supported communication may include:
- synchronous HTTP/gRPC
- asynchronous messaging
- event-driven integration

Rules:
- be explicit about ownership and direction
- define timeouts, retries, and failure behavior
- prefer loose coupling where appropriate
- document idempotency expectations for message-driven flows

---

# Data Rules

- each service owns its own data store
- cross-service reporting or views should be explicit
- avoid shared-database coupling
- keep consistency models explicit

---

# API / Event Contract Rules

- version contracts intentionally
- keep schemas explicit
- do not expose internal implementation details as public contracts
- map internal models to contract models at boundaries

---

# Operational Rules

- define health, readiness, and configuration expectations
- keep deployment assumptions explicit
- isolate service-specific infrastructure concerns
- document rollout and rollback considerations

---

# Testing Strategy

- unit test service domain/application logic
- integration test adapters and persistence
- contract test APIs/events
- system test critical cross-service flows

---

# Anti-Patterns

Never introduce:

- shared database coupling between services
- shared giant model libraries that erase service boundaries
- hidden synchronous dependencies across many services
- distributed monolith patterns disguised as microservices

When in doubt:

**Strengthen service boundaries and make contracts more explicit.**
