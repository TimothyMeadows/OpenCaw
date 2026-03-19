# NODE.md

This repository follows a **Node.js / SPA application architecture** for frontend or service runtimes.

Goals:
- clear separation between UI, state, services, and infrastructure concerns
- maintainable component boundaries
- testable business and state logic
- environment-driven configuration
- framework-aware but framework-contained implementation

## Core rules

- Keep framework bootstrapping and runtime wiring near the application boundary
- Keep API clients, browser storage, and network concerns out of pure domain/state logic
- Prefer feature-based organization over large type-based dumping grounds
- Keep UI components focused on presentation and orchestration, not hidden business rules

## Suggested structure

```text
src/
  app/
  features/
  components/
  services/
  state/
  models/
  infrastructure/
```

## State rules

- Prefer explicit state transitions
- Keep side effects isolated
- Avoid hidden global mutation
- Keep domain-like logic independent from UI framework internals

## API rules

- Keep HTTP clients and request concerns in service/infrastructure layers
- Do not spread raw fetch/axios calls across components
- Normalize responses at boundaries

## UI rules

- Keep components thin where possible
- Move reusable business decisions into feature/state/service modules
- Prefer clear props/contracts over implicit coupling

## Testing

- unit test state and feature logic
- component test key UI behavior
- integration test critical flows
- verify environment/config behavior separately when needed

When in doubt:

**Move logic away from framework surfaces and toward explicit feature/state modules.**
