# VUE.md

This repository follows a **Vue application architecture** optimized for composability, feature boundaries, and maintainable state and service flows.

The architecture is optimized for:

- Vue
- TypeScript
- Composition API
- feature-based organization
- explicit service boundaries
- clear separation between UI, state, and infrastructure

The goal is to keep the system:

- composable
- testable
- explicit about state and side effects
- easy to evolve
- maintainable at enterprise scale

---

# Core Architecture Rule

**Composables coordinate behavior, services own external access, components present UI.**

Prefer:

```text
Components -> Composables / Feature State -> Services / API Clients
```

Avoid:

```text
Components -> direct fetch calls
Components -> hidden business workflows
Global stores -> everything
```

---

# Project Structure

Standard layout:

```text
src/
  app/
  features/
  components/
  composables/
  services/
  stores/
  models/
  infrastructure/
  routes/
```

Feature layout:

```text
features/
  orders/
    components/
    composables/
    services/
    stores/
    models/
```

---

# Component Rules

Components should be primarily concerned with:

- rendering
- props
- emitted events
- view composition

Avoid in components:

- direct infrastructure access
- scattered business rules
- hidden side-effect orchestration

Prefer:
- smart page/container components near route boundaries
- focused child components below them

---

# Composable Rules

Composables should encapsulate:

- reusable feature logic
- workflow coordination
- state transitions
- controlled side effects

Rules:

- keep composables focused
- avoid giant multi-purpose composables
- do not hide infrastructure complexity without clear ownership
- use clear naming based on feature intent

Good:

```text
useOrderSearch
useCreateOrder
useCustomerLookup
```

Avoid:

```text
useHelpers
useAppStuff
useEverything
```

---

# Service Rules

Services should own:

- HTTP access
- response normalization
- retry/auth mechanics where needed
- infrastructure boundary concerns

Rules:

- do not scatter fetch/axios usage across components
- map raw transport shapes at boundaries
- keep services explicit and feature-oriented where possible

---

# State Rules

State should be explicit.

Possible tools:
- local reactive state
- Pinia stores
- feature-local composable state

Rules:

- keep local state local when possible
- do not force everything into one global store
- separate server state, view state, and workflow state when useful
- keep mutations understandable and traceable

---

# Routing

Routing should define navigation structure, not domain rules.

Rules:

- keep route guards explicit
- page-level composition may orchestrate features
- avoid deeply coupling route files to infrastructure logic

---

# DTO / Model Rules

Placement:

| Type | Location |
|---|---|
| API DTO | services / infrastructure |
| app model | features / models |
| view model | component or page boundary |

Map at boundaries instead of leaking transport shapes throughout the app.

---

# Testing Strategy

Component tests:
- rendering
- emitted events
- interaction behavior

Composable tests:
- logic
- state transitions
- side effects using mocks or doubles

Service tests:
- response mapping
- error handling
- auth/retry behavior when custom

End-to-end tests:
- critical user journeys
- route transitions
- integration-heavy flows

---

# Naming Conventions

Good:

```text
OrderList.vue
CreateOrderPage.vue
useOrderSearch.ts
orderService.ts
ordersStore.ts
```

Avoid:

```text
helper.ts
manager.ts
util.ts
commonService.ts
```

---

# Anti-Patterns

Never introduce:

- giant all-purpose composables
- direct API calls in random components
- transport DTO leakage everywhere
- over-centralized global stores without ownership
- hidden side-effect chains

---

# Code Generation Rules for Agents

When generating code:

1. Start at the feature boundary.
2. Define feature models and service contracts.
3. Implement services and composables.
4. Keep components focused on rendering and interaction.
5. Keep side effects explicit and testable.

When in doubt:

**Move logic out of components and into composables or service boundaries.**
