# PYTHON.md

This repository follows a **Python application architecture** optimized for maintainability, testability, and explicit boundaries between domain logic, orchestration, and framework or infrastructure code.

The architecture is optimized for:

- Python
- FastAPI, Flask, Django, or service-oriented runtimes
- explicit service and domain boundaries
- typed interfaces where practical
- isolated infrastructure concerns
- maintainable module ownership

The goal is to keep the system:

- easy to reason about
- easy to test
- explicit about side effects
- framework-aware but not framework-dominated
- maintainable at enterprise scale

---

# Core Architecture Rule

**Keep domain and application logic separate from framework and infrastructure details.**

Prefer:

```text
Presentation / API -> Application / Services -> Domain
Infrastructure -> Application / Domain
```

Avoid:

```text
Domain -> framework imports
Business logic -> ORM or HTTP coupling everywhere
Routes/controllers -> core business rules
```

---

# Project Structure

Suggested service layout:

```text
src/
  app/
    api/
    services/
    domain/
    infrastructure/
    models/
    schemas/
    config/
tests/
```

Alternative feature layout:

```text
src/
  app/
    features/
      orders/
        api/
        services/
        domain/
        infrastructure/
        schemas/
```

---

# Domain Rules

Domain modules should contain:

- entities
- value-like domain objects
- business invariants
- domain-specific policies
- domain exceptions

Rules:

- avoid framework coupling
- avoid persistence-specific behavior leaking into core logic
- avoid HTTP/request knowledge in domain modules
- prefer explicit invariants and meaningful types

---

# Application / Service Rules

Application or service modules should own:

- use cases
- orchestration
- workflow sequencing
- coordination between domain and infrastructure abstractions

Rules:

- keep business workflows explicit
- depend on abstractions where practical
- do not bury workflow logic in route handlers
- avoid infrastructure implementation leakage into service logic

---

# Presentation Layer Rules

For API frameworks such as FastAPI or Flask:

- keep route handlers thin
- validate input at the boundary
- map request models into service/application calls
- map service results into response models

Avoid:

- route handlers full of business rules
- direct ORM or transport logic scattered everywhere
- hidden cross-cutting policy inside endpoints

---

# Persistence and Infrastructure

Infrastructure may include:

- database repositories
- external API clients
- cache adapters
- queue or event adapters
- file storage adapters
- environment/config readers

Rules:

- keep infrastructure replaceable where practical
- keep infrastructure-specific code out of domain modules
- map persistence and transport shapes at boundaries
- isolate third-party SDK details

---

# Typing and Contracts

Prefer:

- type hints on public APIs
- clear input/output contracts
- Pydantic/dataclass/schema objects where appropriate
- explicit boundaries between transport models and domain models

Avoid:

- “anything goes” dict-based contracts across the entire codebase
- opaque helper modules with unclear return shapes

---

# Validation

Validation should happen close to system boundaries.

Examples:
- request validation
- config validation
- workflow precondition validation

Rules:

- do not rely on ad hoc inline checks everywhere
- keep validation reusable and explicit
- separate transport validation from domain invariants where practical

---

# Framework Guidance

Framework-specific wiring belongs near the application boundary.

Examples:
- FastAPI routers and dependency wiring
- Flask blueprint registration
- Django view / serializer / settings integration

Rules:

- do not let framework conventions define all internal architecture
- keep core modules importable without requiring the runtime framework where practical
- isolate framework setup and DI-like wiring near startup boundaries

---

# Testing Strategy

Domain tests:
- pure unit tests
- minimal mocking

Application/service tests:
- mocks or test doubles for repositories/clients
- verify workflow behavior

Infrastructure tests:
- integration tests
- database or external adapter tests

Presentation tests:
- endpoint tests
- serialization and validation tests

---

# Naming Conventions

Good:

```text
create_order.py
order_service.py
order_repository.py
order_schema.py
customer_domain.py
```

Avoid:

```text
helpers.py
utils.py
manager.py
processor.py
common.py
```

---

# Anti-Patterns

Never introduce:

- business logic inside route handlers or views
- ORM models as the only domain model everywhere
- giant helper modules with unclear ownership
- uncontrolled global state
- infrastructure concerns bleeding through all layers

---

# Code Generation Rules for Agents

When generating code:

1. Start with the domain or feature boundary.
2. Define request/response or schema contracts at the edges.
3. Implement service/application orchestration.
4. Add infrastructure adapters only where needed.
5. Keep framework-specific code thin and boundary-focused.

When in doubt:

**Move logic away from framework entry points and toward explicit service and domain boundaries.**
