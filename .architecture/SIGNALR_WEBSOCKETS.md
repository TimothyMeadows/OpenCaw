# SIGNALR_WEBSOCKETS.md

This repository follows a **SignalR/WebSockets architecture** focused on reliable real-time messaging, controlled connection lifecycle behavior, and explicit scalability boundaries.

The architecture is optimized for:

- server-to-client push updates
- bidirectional low-latency communication
- connection-state awareness
- scale-out friendly messaging patterns

The goal is to keep the system:

- resilient under connection churn
- explicit about delivery guarantees
- secure at connection and message boundaries
- operationally observable

---

# Core Architecture Rule

**Favor SignalR when available; use raw WebSockets only when protocol-level control is explicitly required.**

Prefer:

```text
Application events -> SignalR Hub contracts -> supported transports (WebSockets when available)
```

Use raw WebSockets only when:

- SignalR protocol/features are insufficient for the use case
- custom framing/subprotocol behavior is required
- there is a documented reason to bypass SignalR abstractions

---

# Transport and Protocol Rules

- treat WebSockets as a transport, not an architecture on its own
- allow transport fallback behavior when using SignalR unless strict WebSocket-only behavior is required
- define message contract versioning for client/server compatibility
- keep payload formats explicit and bounded

---

# Hub and Boundary Rules

- keep SignalR hubs thin and focused on real-time orchestration
- move business rules into application/domain layers
- define explicit hub method contracts per feature area
- avoid leaking persistence or infrastructure concerns directly into hubs

---

# Connection Lifecycle Rules

- define connect/disconnect/reconnect behavior explicitly
- do not rely on in-memory connection identity as durable state
- externalize user/session mapping when required beyond single-instance runtime
- implement timeout and heartbeat expectations for long-lived sessions

---

# Scaling and Delivery Rules

- plan for horizontal scale from the start (for example Azure SignalR Service or Redis backplane)
- define ordering expectations per message stream
- design idempotent client handlers for duplicate delivery scenarios
- avoid assuming exactly-once semantics over real-time channels

---

# Security Rules

- authenticate and authorize at connection and method boundaries
- validate group/channel membership server-side
- apply least privilege for publish/subscribe capabilities
- avoid sending sensitive data without explicit encryption and retention policy consideration

---

# Observability and Operations

- log connection counts, reconnect rates, and error categories
- monitor hub invocation latency and message throughput
- instrument dropped connection and backpressure scenarios
- document deployment impact for scale unit or backplane changes

---

# Testing Strategy

- unit test hub orchestration and contract validation paths
- integration test connect/reconnect and group membership behavior
- load test concurrent connection and fan-out scenarios
- validate client backward compatibility for contract evolution

---

# Anti-Patterns

Never introduce:

- business logic concentrated inside hubs or WebSocket handlers
- hard dependency on single-node in-memory connection state
- undocumented message schemas for critical client workflows
- assumption that WebSocket availability is guaranteed in every environment

When in doubt:

**Use SignalR abstractions first, and narrow down to raw WebSockets only with explicit technical justification.**

