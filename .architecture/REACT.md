# REACT.md

This repository follows a **React frontend architecture** optimized for maintainability, testability, and clear separation of responsibilities.

The architecture is optimized for:

- React
- TypeScript
- Feature-based organization
- Explicit state management
- Boundary-based API integration
- Component composition over inheritance

The goal is to keep the system:

- Easy to reason about
- Easy to test
- Resistant to component sprawl
- Clear about side effects and state ownership
- Maintainable at enterprise scale

---

# Core Architecture Rule

**Move logic away from framework surfaces and toward explicit feature, state, and service boundaries.**

Prefer:

```
UI Components -> Feature Logic -> Services / API Clients
```

Avoid:

```
UI Components -> raw fetch calls
UI Components -> hidden business rules
Global mutable state -> everything
```

---

# Project Structure

Standard project layout:

```text
src/
  app/
  features/
  components/
  services/
  state/
  hooks/
  models/
  infrastructure/
  routes/
  utils/
```

Alternative feature-first layout:

```text
src/
  features/
    orders/
      components/
      hooks/
      services/
      state/
      models/
```

---

# Component Rules

Components should be **presentation-first** unless they are explicitly container or page components.

Allowed responsibilities:

- rendering UI
- receiving props
- raising events
- simple formatting for display
- composing child components

Avoid in general components:

- direct API calls
- hidden business rules
- large stateful workflows
- cross-feature coupling

Rules:

- prefer small, composable components
- prefer explicit props over implicit context dependencies
- avoid god components
- isolate reusable visual primitives from feature-specific components

---

# State Management

State should be **owned explicitly**.

Guidelines:

- keep local UI state local
- move reusable or cross-view state into feature/state modules
- keep side effects isolated
- avoid scattered mutation patterns
- normalize complex state when needed

Good examples:

- local component state for toggles and form input draft state
- feature store / reducer for workflow state
- query caching library for server state

Avoid:

- pushing all state into one global store
- duplicating the same server state in multiple places
- business rules embedded inside UI event handlers

---

# Hooks

Hooks should encapsulate:

- reusable UI behavior
- feature state wiring
- service orchestration
- controlled side effects

Rules:

- keep hooks focused
- avoid hooks that silently own too many concerns
- avoid hooks that mix rendering concerns with infrastructure details
- name hooks clearly based on purpose

Good:

```text
useOrderSearch
useCreateOrderForm
useCustomerLookup
```

Avoid:

```text
useHelpers
useCommonStuff
useAppLogic
```

---

# Service Layer

All HTTP and external integration concerns should live behind **services or API client modules**.

Rules:

- do not scatter raw fetch/axios logic across components
- normalize responses at service boundaries
- map transport models to app models when needed
- centralize auth/header/retry behavior

Example flow:

```text
Component -> feature hook -> service -> API client
```

---

# Routing

Routing belongs at the application boundary.

Rules:

- route definitions should not contain business logic
- route guards should be explicit
- page components should orchestrate features, not implement domain rules
- prefer colocating page composition near route definitions without bloating route files

---

# DTO / Model Rules

Model placement:

| Type | Location |
|---|---|
| API request/response models | services / infrastructure |
| app-facing models | models / features |
| UI-only view models | feature or component boundary |

Never expose raw backend payload shapes everywhere in the app.

Map at boundaries.

---

# Mapping

Mapping should happen at boundaries.

Boundaries:

```text
HTTP -> service model
service model -> feature/app model
feature/app model -> UI props
```

Prefer:

- explicit mapping functions
- small transformers
- feature-local mapping where appropriate

Avoid:

- leaking raw transport objects directly into UI everywhere
- giant shared “helper” mappers with unclear ownership

---

# Validation

Validation should happen close to user input boundaries and feature workflows.

Guidelines:

- validate form input explicitly
- keep schema or rule definitions reusable
- separate display errors from business/process rules when needed
- prefer deterministic validation over ad hoc inline conditionals

---

# Testing Strategy

Component tests:
- rendering behavior
- user interactions
- accessibility-critical states

Feature tests:
- workflow behavior
- state transitions
- integration with services through mocks or test doubles

Service tests:
- response mapping
- error handling
- retry or auth behavior if custom

End-to-end tests:
- critical user journeys
- route transitions
- backend integration touchpoints

---

# Naming Conventions

Good:

```text
OrderList
CreateOrderPage
useOrderSearch
orderService
OrderSummaryCard
```

Avoid:

```text
Helper
Manager
Processor
CommonComponent
Util
```

---

# Anti-Patterns

Never introduce:

- fat page components full of business logic
- direct HTTP calls in random components
- giant shared mutable stores without clear ownership
- transport DTO leakage across the entire app
- hook or component “kitchensink” modules

---

# Code Generation Rules for Agents

When generating code:

1. Start with the feature boundary.
2. Create or update models and service contracts.
3. Implement services or API clients.
4. Wire state and hooks.
5. Keep components thin and presentation-focused.

When in doubt:

**Move logic out of components and into explicit feature/state/service boundaries.**
