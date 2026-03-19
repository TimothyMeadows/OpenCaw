# SPA.md

This repository follows a **Single Page Application architecture** intended for modern browser applications regardless of framework.

This template is appropriate for:
- React SPAs
- Angular SPAs
- Vue SPAs
- framework-light browser applications

The goal is to keep the system:

- feature-oriented
- explicit about state and side effects
- easy to test
- easy to evolve
- maintainable at enterprise scale

---

# Core Architecture Rule

**Separate presentation, feature logic, state, and infrastructure concerns.**

Prefer:

```text
UI -> Feature Logic / State -> Services / API Clients -> Backend
```

Avoid:

```text
UI -> raw infrastructure calls everywhere
UI -> business rules
one global module -> entire app behavior
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
  state/
  routes/
  infrastructure/
  models/
```

---

# UI Rules

- keep components/pages focused on presentation and orchestration
- do not bury business rules inside click handlers and lifecycle hooks
- prefer explicit props/contracts and feature APIs

---

# State Rules

- keep local state local
- isolate workflow state by feature
- isolate server state handling
- avoid uncontrolled global mutation

---

# Service Rules

- keep network and integration concerns behind service boundaries
- map raw transport shapes at boundaries
- keep auth/retry/error conventions centralized where possible

---

# Routing Rules

- keep routing declarative
- keep route-level orchestration thin
- avoid putting domain logic inside routing setup

---

# Testing Strategy

- unit test feature logic and state
- component test rendering and interaction
- integration or end-to-end test critical flows

---

# Anti-Patterns

Never introduce:

- UI-driven business logic sprawl
- uncontrolled global state
- direct network access scattered across the codebase
- generic dumping-ground utility modules with unclear ownership

When in doubt:

**Move logic toward feature/state/service boundaries and away from UI surfaces.**
