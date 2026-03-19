# NEXTJS.md

This repository follows a **Next.js application architecture** optimized for maintainability, clear boundary ownership, and explicit handling of server/client concerns.

The architecture is optimized for:

- Next.js
- TypeScript
- App Router or Pages Router
- server/client component separation
- API/service boundaries
- feature-based organization

The goal is to keep the system:

- explicit about rendering boundaries
- easy to test
- clear about side effects and data ownership
- maintainable at enterprise scale

---

# Core Architecture Rule

**Keep server concerns, client concerns, feature logic, and infrastructure concerns explicit and separate.**

Prefer:

```text
Routes / Pages -> Feature Logic -> Services / API Clients -> External Systems
```

And for UI:

```text
Server Components -> data composition
Client Components -> interaction and local UI state
```

Avoid:

```text
Client Components -> raw infrastructure calls everywhere
Pages/Routes -> hidden business rules
Shared utilities -> entire application behavior
```

---

# Project Structure

Suggested layout:

```text
src/
  app/
  features/
  components/
  services/
  lib/
  infrastructure/
  models/
  hooks/
```

Feature layout example:

```text
src/
  features/
    orders/
      components/
      services/
      models/
      hooks/
      actions/
```

---

# Server vs Client Rules

Be explicit about whether code runs on the server or client.

Rules:

- default to server-side composition when interaction is not needed
- use client components only where interaction, browser APIs, or local UI state are required
- avoid moving large workflow logic into client components without need
- keep server-only concerns out of client bundles

---

# Route / Page Rules

Routes, pages, and layout entry points should:

- compose features
- coordinate data loading
- define page-level structure
- stay thin about business rules

Avoid:

- hiding application rules directly in route modules
- scattering data-fetching conventions inconsistently
- letting route files become god modules

---

# Component Rules

Components should be presentation-first unless they are explicitly page/container components.

Allowed:
- rendering
- composition
- local UI interactions
- simple display formatting

Avoid:
- direct raw API calls in random components
- hidden business logic
- unbounded cross-feature coupling

---

# Service and API Rules

All external access should live behind explicit services or API client modules.

Rules:

- centralize transport details
- normalize responses at boundaries
- keep auth/header/retry behavior explicit
- do not scatter fetch logic through the UI tree

Possible boundaries:
- server actions
- service modules
- API route handlers
- backend clients

---

# Data Fetching Rules

Choose data-fetching patterns intentionally.

Guidelines:

- prefer server-side fetching for server-rendered composition
- keep client-side fetching focused on interaction-driven updates
- centralize fetch behavior where practical
- map transport models into app-facing models when useful

Avoid:
- inconsistent fetching patterns across similar features
- transport shape leakage throughout the app

---

# State Rules

State should be explicit and owned.

Guidelines:
- keep local UI state local
- keep workflow or feature state near the feature boundary
- separate server data concerns from local interaction state
- avoid over-centralizing all state without clear need

---

# DTO / Model Rules

Placement:

| Type | Location |
|---|---|
| external/API DTO | services / infrastructure |
| app-facing model | models / features |
| UI-only view model | page/component boundary |

Map at boundaries instead of leaking raw transport shapes everywhere.

---

# API Route / Server Action Rules

If using API routes or server actions:

- keep them thin
- validate inputs
- delegate business workflows to feature/service modules
- isolate infrastructure coupling

Avoid:
- embedding the entire workflow in route handlers or server actions
- re-implementing the same business rules in multiple boundaries

---

# Testing Strategy

Component tests:
- rendering behavior
- interactions
- client-only state behavior

Feature/service tests:
- workflow behavior
- mapping
- service orchestration

Integration tests:
- route or server action behavior
- auth-sensitive or data-sensitive boundaries

End-to-end tests:
- critical user journeys
- route transitions
- server/client integration flows

---

# Naming Conventions

Good:

```text
OrderList.tsx
CreateOrderPage.tsx
orderService.ts
useOrderSearch.ts
orders.actions.ts
```

Avoid:

```text
helper.ts
utils.ts
manager.ts
commonService.ts
processor.ts
```

---

# Anti-Patterns

Never introduce:

- client components with hidden infrastructure logic
- route files that absorb all application behavior
- raw transport DTO leakage across the UI
- uncontrolled shared state with unclear ownership
- server/client boundary confusion

---

# Code Generation Rules for Agents

When generating code:

1. Start at the feature boundary.
2. Decide what belongs on the server vs client.
3. Define models and service contracts.
4. Implement services or actions.
5. Keep pages/routes/components thin and explicit.

When in doubt:

**Push business and integration logic toward explicit feature/service boundaries and keep server/client responsibilities clear.**
