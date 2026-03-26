# DOTNET_ASPIRE.md

This repository follows a **.NET Aspire architecture** for distributed .NET applications.

The architecture is optimized for:

- AppHost-based composition
- ServiceDefaults for shared runtime policies
- cloud-ready local orchestration
- explicit resource wiring
- OpenTelemetry-first observability

The goal is to keep the system:

- modular across services
- environment-driven
- resilient under partial failure
- observable by default
- easy to run locally and deploy to cloud targets

---

# Core Architecture Rule

**AppHost composes the system topology; services own business logic.**

Prefer:

```text
AppHost -> project/resource composition -> service runtime
Service -> application/domain logic -> infrastructure adapters
```

Avoid:

```text
AppHost -> business rules
Service -> hardcoded environment/resource assumptions
```

---

# Suggested Solution Structure

```text
src/
  MyApp.AppHost/
  MyApp.ServiceDefaults/
  MyApp.Api/
  MyApp.Worker/
  MyApp.Domain/
  MyApp.Application/
  MyApp.Infrastructure/

tests/
  MyApp.Api.Tests/
  MyApp.Worker.Tests/
  MyApp.Application.Tests/
```

---

# AppHost Rules

AppHost is responsible for:

- defining project and resource relationships
- wiring service references
- configuring distributed runtime composition

Rules:

- keep AppHost free of business logic
- keep AppHost free of domain/persistence behavior
- treat AppHost as composition root only
- keep resource naming and connection details environment-driven

---

# ServiceDefaults Rules

ServiceDefaults should centralize shared runtime behavior, including:

- telemetry setup
- health checks
- service discovery defaults
- resiliency defaults where appropriate

Rules:

- use ServiceDefaults for shared cross-cutting concerns only
- avoid service-specific business behavior in ServiceDefaults
- keep policies explicit and overridable by service when needed

---

# Service Project Rules

Service projects (API, workers, processors) should:

- contain service-specific use cases and orchestration
- depend on application/domain boundaries as appropriate
- remain runnable and testable independently of AppHost when practical

Avoid:

- direct coupling to AppHost APIs from business logic
- hidden dependencies on local-only Aspire behavior

---

# Resource and Configuration Rules

Resource integration should be:

- explicit in AppHost
- externalized by environment
- safe for local and cloud parity

Rules:

- do not hardcode secrets, endpoints, or cloud resource names in service code
- make required settings explicit in docs and deployment config
- define ownership boundaries for each external dependency

---

# Observability and Diagnostics

Aspire-enabled applications should provide:

- structured logs
- traces with correlation identifiers
- metrics for critical flows
- health/readiness checks per service

Rules:

- keep telemetry behavior consistent through ServiceDefaults
- do not disable tracing/health behavior silently between environments

---

# Resilience and Communication

Inter-service communication should:

- define timeouts and retry behavior explicitly
- avoid hidden synchronous coupling
- state idempotency expectations for retried operations

For message-driven flows:

- document duplicate handling and poison-message behavior
- keep transport concerns separate from business handlers

---

# Testing Strategy

- unit test domain and application logic independently of Aspire host composition
- integration test service adapters and resource interactions
- smoke test AppHost startup and service graph composition
- validate configuration contracts for local and cloud execution

---

# Anti-Patterns

Never introduce:

- business logic in AppHost
- duplicated shared runtime wiring across every service
- hidden environment assumptions in service startup
- direct secret values in source code
- service boundaries blurred by shared internal models

When in doubt:

**Keep AppHost focused on composition and keep business logic in service/application/domain layers.**
