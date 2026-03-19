# EVENT_DRIVEN.md

This repository follows an **event-driven architecture** focused on explicit event contracts, clear ownership, and resilient asynchronous workflows.

The goal is to keep the system:

- explicit about publishers and consumers
- resilient to asynchronous behavior
- clear about idempotency and retries
- maintainable across message-driven workflows

---

# Core Architecture Rule

**Events are contracts, not internal implementation accidents.**

Prefer:

```text
Publisher -> explicit event contract -> broker -> consumer
```

Avoid:

```text
arbitrary payloads -> hidden coupling -> fragile consumers
```

---

# Event Rules

Each event should define:
- event name
- purpose
- ownership
- payload contract
- ordering assumptions if any
- idempotency expectations if any

Rules:
- version events intentionally
- keep payloads explicit
- document ownership clearly
- avoid leaking internal object graphs as event payloads

---

# Publisher Rules

Publishers should:
- emit events after meaningful business state transitions
- avoid duplicate uncontrolled publication
- make failure and retry behavior explicit

---

# Consumer Rules

Consumers should:
- treat input as untrusted
- validate payloads
- handle duplicates when needed
- define retry and poison/failure behavior
- isolate transport concerns from application logic

---

# Ordering and Consistency

Rules:
- do not assume ordering unless explicitly guaranteed
- document ordering requirements where they exist
- be explicit about eventual consistency expectations
- avoid hiding consistency-sensitive rules in transport code

---

# Observability

Event-driven systems should emphasize:
- traceability
- correlation identifiers
- dead-letter visibility
- replay or recovery understanding where applicable

---

# Testing Strategy

- unit test handlers
- integration test publisher and consumer boundaries
- contract test event schemas
- test retry, duplicate, and poison scenarios

---

# Anti-Patterns

Never introduce:

- undocumented event schemas
- consumers tightly coupled to publisher internals
- hidden ordering assumptions
- no strategy for duplicate processing or poison handling

When in doubt:

**Make ownership, contracts, and failure behavior explicit.**
