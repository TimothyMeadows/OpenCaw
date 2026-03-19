# ANGULAR.md

This repository follows an **Angular application architecture** optimized for maintainability, modularity, and clear layering.

The architecture is optimized for:

- Angular
- TypeScript
- Feature modules or standalone feature boundaries
- RxJS-based reactive flows
- Service isolation
- Clear presentation/application separation

The goal is to keep the system:

- modular
- testable
- explicit about side effects
- scalable across large teams
- maintainable at enterprise scale

---

# Core Architecture Rule

**Components present, services orchestrate, models define contracts.**

Prefer:

```text
Components -> Facades / Services -> API Clients / Infrastructure
```

Avoid:

```text
Components -> raw HttpClient everywhere
Components -> business rules
Shared dumping-ground services -> entire app
```

---

# Project Structure

Standard layout:

```text
src/app/
  core/
  shared/
  features/
  infrastructure/
```

Feature layout:

```text
features/
  orders/
    components/
    pages/
    services/
    models/
    state/
```

---

# Core Module Rules

Use `core/` for:

- application-wide singletons
- interceptors
- auth shell concerns
- app initialization concerns

Use `shared/` for:

- reusable UI primitives
- pipes
- common presentational directives
- narrowly reusable utilities

Do not turn `shared/` into an unowned dumping ground.

---

# Component Rules

Components should stay **thin**.

Allowed:

- template orchestration
- input/output handling
- view composition
- simple display-only formatting

Avoid:

- direct business workflow logic
- raw API calls
- persistence logic
- hidden cross-feature coupling

Prefer:

- smart page/container components at the feature boundary
- dumb/presentational child components below them

---

# Service Rules

Services should own:

- orchestration
- API access
- transformation
- workflow coordination
- state coordination where appropriate

Rules:

- keep services focused by feature
- avoid giant cross-app “manager” services
- keep HttpClient usage near infrastructure/service boundaries
- centralize shared interceptors and cross-cutting request policy

---

# RxJS Rules

Reactive flows should be explicit and readable.

Guidelines:

- name streams clearly
- avoid deeply nested operator chains when they reduce readability
- isolate side effects
- complete or clean up subscriptions correctly
- prefer async pipe when possible for template subscriptions

Avoid:

- hidden subscription leaks
- side effects buried in unclear chains
- pushing all logic into components

---

# State Management

State should be explicit and owned.

Options may include:

- feature-local RxJS state
- facades
- NgRx or similar libraries where justified

Rules:

- do not introduce global state without clear need
- keep state ownership close to the feature
- separate server state, view state, and workflow state where practical

---

# DTO / Model Rules

Placement:

| Type | Location |
|---|---|
| API DTO | service / infrastructure boundary |
| app model | feature or domain model layer |
| view model | page/component boundary |

Map at boundaries rather than leaking transport models everywhere.

---

# Routing

Routing should reflect application structure, not contain business logic.

Rules:

- keep guards explicit
- keep lazy-loading boundaries intentional
- page components may orchestrate but should not absorb business rules

---

# Testing Strategy

Component tests:
- rendering
- binding
- event handling

Service tests:
- orchestration
- transformations
- error handling

Feature tests:
- route or page workflows
- facade/state interactions

End-to-end tests:
- critical user journeys
- authentication-sensitive routes
- cross-feature flows

---

# Naming Conventions

Good:

```text
OrdersPageComponent
OrderCardComponent
OrdersFacade
OrdersService
CreateOrderRequest
```

Avoid:

```text
HelperService
CommonManager
UtilService
Processor
```

---

# Anti-Patterns

Never introduce:

- fat components with orchestration and infrastructure mixed together
- app-wide mega services
- DTO leakage across the UI
- implicit shared mutable state
- unbounded shared modules

---

# Code Generation Rules for Agents

When generating code:

1. Start with the feature boundary.
2. Define models and contracts.
3. Create focused services or facades.
4. Implement thin components and pages.
5. Keep infrastructure concerns near service boundaries.

When in doubt:

**Move logic out of components and toward explicit feature services or facades.**
