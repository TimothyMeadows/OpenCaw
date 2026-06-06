# COLYSEUS.md

This repository follows a **Colyseus authoritative multiplayer architecture** for real-time game servers, rooms, matchmaking, state synchronization, reconnection, and multiplayer runtime operations.

The architecture is optimized for:

- Colyseus as an authoritative Node.js multiplayer server framework
- TypeScript-first room, state, and message contracts
- server-owned simulation and state mutation
- schema-based state synchronization
- explicit matchmaking and room lifecycle boundaries
- reconnect-safe browser and game-engine clients
- horizontal scaling with shared presence and room drivers
- load testing, monitoring, graceful shutdown, and operational visibility

The goal is to keep the system:

- clear about what runs on the server and what runs on clients
- resistant to cheating and invalid client messages
- efficient with bandwidth and state patching
- stable under disconnects, reconnects, process restarts, and scale-out
- testable through room-level unit tests and load tests
- compatible with browser clients, Phaser, Three.js, Unity, Godot, and other Colyseus SDK clients

---

# Core Architecture Rule

**Colyseus rooms are authoritative server sessions. Clients request actions; the server validates, simulates, mutates state, and synchronizes results.**

Prefer:

```text
Client Input -> Validated Room Message -> Server Simulation -> Schema State Patch -> Client Presentation
```

Avoid:

```text
Client mutates game state -> server mirrors it -> other clients trust it
```

Clients may predict, interpolate, animate, and render, but durable gameplay facts must be owned by the room or by trusted backend services. The synchronized schema state is a network contract, not a dumping ground for every server variable.

---

# Recommended Structure

```text
src/
  app.config.ts
  index.ts
  rooms/
    LobbyRoom.ts
    MatchRoom.ts
    RelayRoom.ts
    states/
      MatchState.ts
      PlayerState.ts
      SharedTypes.ts
    commands/
    systems/
    validators/
  matchmaking/
    filters.ts
    reservations.ts
    roomMetadata.ts
  auth/
    onAuth.ts
    tokens.ts
  persistence/
    repositories/
    saveSnapshots.ts
  realtime/
    transport.ts
    presence.ts
    driver.ts
  telemetry/
    metrics.ts
    logging.ts
  tests/
    rooms/
    loadtest/
```

Client repositories should keep Colyseus SDK integration behind a multiplayer service boundary, then adapt state callbacks into engine-specific systems for Phaser, Three.js, React, Unity, or other clients.

---

# Room Architecture

Rooms are the primary Colyseus runtime boundary.

Rules:

- define one room class per session type, such as `LobbyRoom`, `MatchRoom`, `PartyRoom`, `WorldRoom`, or `RelayRoom`
- treat every room instance as isolated session state with its own clients, lifecycle, and schema state
- keep room creation options typed and sanitized before use
- initialize state in `onCreate`
- authenticate and authorize in `onAuth` before `onJoin`
- allocate player state in `onJoin`
- handle temporary disconnection in `onDrop` and successful return in `onReconnect`
- perform final cleanup in `onLeave` and `onDispose`
- use `onBeforeShutdown` for graceful shutdown behavior when active rooms need player notification or save handling
- lock or dispose rooms deliberately when gameplay enters a non-joinable state

Do not put all multiplayer behavior in one giant room. Move combat, movement, matchmaking filters, persistence, replay, and scoring into focused systems or command handlers.

---

# State Synchronization

Colyseus synchronized state must be designed as a compact network model.

Rules:

- define synchronized state with `@colyseus/schema`
- mutate synchronized state only on the server
- expose the minimum state clients need to render and play
- keep secrets, anti-cheat signals, hidden cards, private matchmaking data, and server-only calculations out of shared schema state
- use nested `Schema` structures when models approach field limits or need ownership boundaries
- keep server and client schema definitions in matching field order when concrete schema classes are shared across SDKs
- use `MapSchema`, arrays, and child schemas intentionally; avoid large frequently changing structures that create unnecessary bandwidth
- tune `patchRate` based on game genre, perceived latency, and bandwidth budget
- use state views or filtered state when clients should see only part of the room state
- treat full state on join and patch updates as separate performance concerns

Recommended schema categories:

- public player state: position, facing, animation state, health, connected flag
- public match state: phase, timer, score, objectives, round index
- replicated entities: projectiles, pickups, hazards, NPCs, interactables
- private or filtered views: hand contents, fog-of-war, team-only data, hidden objectives

---

# Messages and Commands

Client messages are requests, not trusted facts.

Rules:

- use a small, versioned message vocabulary
- validate every client payload, preferably with schema validation such as Zod through Colyseus validation helpers
- bind messages to command handlers or systems instead of embedding every rule in inline callbacks
- rate-limit or reject spammy actions
- enforce authorization from `client.auth`, room state, and gameplay phase
- reject impossible movement, invalid targets, stale sequence numbers, and actions outside turn/phase rules
- use unreliable messages only for data that can safely be dropped
- keep important state changes represented in server state, not only in transient broadcasts

Message contracts should document:

- message name
- payload schema
- allowed room phase
- sender requirements
- server validation
- resulting state changes or errors
- whether it is reliable, unreliable, idempotent, or replay-sensitive

---

# Simulation, Tickrate, and Latency

Choose a timing model based on genre.

Rules:

- use fixed tick simulation for real-time movement, physics-like resolution, combat timing, or deterministic replays
- keep room clocks, timers, and delayed actions under room lifecycle ownership
- separate server simulation ticks from state patch rate when needed
- use client-side interpolation for remote entities and optional prediction/reconciliation for local movement-heavy games
- keep server timestamps, input sequence numbers, and authoritative corrections explicit when prediction is used
- define lag compensation only if the game design needs it and the exploit surface is understood
- clamp delta values and guard against event-loop stalls
- keep turn-based and async games event-driven where a fixed tick would add needless cost

Do not make gameplay correctness depend on client frame rate.

---

# Matchmaking and Rooms

Colyseus matchmaker APIs should be wrapped by product-specific matchmaking services.

Rules:

- expose only the matchmaker operations the client is allowed to call
- prefer explicit matchmaking endpoints or services for ranked queues, parties, password rooms, invites, private rooms, and rematches
- use room metadata for searchable room traits such as mode, map, region, rating band, team size, locked state, and visibility
- lock rooms when joining should stop
- validate seat reservations and join options in `onAuth` and `onJoin`
- document when to use `join`, `joinOrCreate`, `create`, `joinById`, `reserveSeatFor`, or custom room IDs
- keep lobby/queue/relay built-in rooms separate from gameplay rooms when behavior differs
- avoid trusting client-provided matchmaking filters for rank, entitlement, inventory, or private access

For cross-process deployments, remember that room data and seat reservations may involve shared driver and presence coordination.

---

# Reconnection and Lifecycle

Temporary disconnection is normal in browser and mobile multiplayer.

Rules:

- implement `onDrop` when the game supports reconnection
- call `allowReconnection` with a timeout appropriate to the game type
- mark players disconnected in synchronized state so other clients can show UI
- do not delete player state on drop if reconnection is allowed
- perform final cleanup only in `onLeave` after reconnection fails or the client leaves intentionally
- handle `onReconnect` by restoring connected state and resending any required client context
- show reconnecting, failed-to-reconnect, and return-to-lobby UI on clients
- define how buffered messages should be handled after reconnection
- reject reconnection when the match ended, the user was kicked, or session ownership changed

Fast action games usually need short reconnection windows. Turn-based or async rooms can tolerate longer windows when save/persistence supports it.

---

# Authentication and Security

Every production room should have an explicit authentication posture.

Rules:

- implement static `onAuth` when the room instance is not needed for authentication
- validate tokens, user identity, entitlement, ban status, matchmaking permission, region, and party membership before allowing join
- treat a missing `onAuth` as development-only because it allows any client to connect
- validate every message payload and authorization again inside room behavior
- never trust client position, inventory, currency, score, damage, or cooldown claims
- avoid leaking secrets, hidden state, admin controls, or private matchmaking data in schema state
- rate-limit joins, messages, room creation, and reconnect attempts
- keep admin/monitoring tools protected behind authentication and network controls
- treat IP, device, telemetry, and session identifiers as privacy-sensitive

Use HTTPS/WSS in production and keep CORS, reverse-proxy headers, and token handling explicit.

---

# Persistence and Databases

Separate real-time room state from durable data.

Rules:

- keep authoritative room state in memory during the match
- persist only durable facts such as results, progression, inventory, ratings, purchases, and long-lived world changes
- snapshot long-lived rooms intentionally; do not rely on in-memory room state for durability
- use repositories/services for database access instead of direct database calls scattered through room handlers
- avoid blocking the room tick on slow persistence operations
- make persistence idempotent for match results and reconnect-sensitive flows
- write audit trails for ranked, economy, or moderation-sensitive outcomes
- define recovery behavior after process crash or room disposal

Driver and presence choices for Colyseus scaling are separate from product databases used for accounts, inventory, progression, or analytics.

---

# Scaling and Deployment

Colyseus can scale horizontally, but room ownership matters.

Rules:

- start with a single process only for development or small deployments
- use shared presence and driver, commonly Redis-backed, for multi-process or distributed deployments
- understand that each room belongs to one Colyseus process and clients connect to the process that owns their room
- configure public addresses so clients can establish WebSocket connections to the correct process
- place a load balancer at the initial entry point while preserving the direct room connection flow required by Colyseus scaling
- define region strategy, process count, max clients per room, max rooms per process, and autoscaling signals
- use graceful shutdown to stop matchmaking, lock rooms, notify players, save state, and dispose rooms
- keep environment variables, secrets, Redis/database URLs, TLS, ports, and public addresses externalized
- validate local, staging, and production topology separately

Colyseus Cloud may remove some self-hosting configuration responsibilities, but the game still needs room, state, auth, persistence, testing, and client behavior contracts.

---

# Transports and Clients

Transport choice must match browser, native, and deployment needs.

Rules:

- default to WebSocket unless the project has a documented reason to choose uWebSockets.js, WebTransport, Bun WebSockets, or another transport
- document client SDKs and supported engines: browser TypeScript, Phaser, Three.js, Unity, Godot, Defold, GameMaker, native, or others
- keep client connection code behind a multiplayer service boundary
- normalize room lifecycle events into engine-facing states: connecting, joined, reconnecting, left, failed, kicked
- keep rendering state updates separate from raw Colyseus callback handlers
- handle endpoint configuration, protocol selection, auth token refresh, region selection, and reconnection UI in client code
- test client behavior on slow networks, tab backgrounding, mobile sleep, and browser refresh

---

# Observability and Operations

Real-time multiplayer needs operational feedback loops.

Required signals:

- process uptime and memory
- global and local CCU
- room count by room type
- room creation, join, leave, drop, reconnect, and dispose rates
- matchmaking latency and failures
- message rates and rejected messages
- patch size, patch rate, and bandwidth estimates
- tick duration, event-loop lag, and slow command handlers
- persistence latency and failures
- Redis/presence/driver connectivity
- disconnect close codes and reconnect outcomes

Use Colyseus monitoring and load testing tools during development and staging. Production monitoring should protect admin endpoints and export metrics/logs into the hosting platform's observability stack.

---

# Testing and Verification

Use tests that exercise room logic without needing a full game client, then add client and load tests.

Test categories:

- unit tests for commands, validators, state transitions, match phases, scoring, and persistence adapters
- Colyseus room tests for `onCreate`, `onAuth`, `onJoin`, messages, state patches, reconnects, leaves, and disposal
- schema compatibility tests when clients share generated or mirrored schema definitions
- matchmaking tests for joins, full rooms, locked rooms, private rooms, ratings, regions, and denied clients
- security tests for invalid payloads, unauthorized joins, spammy messages, and impossible actions
- load tests with scripted bots using `@colyseus/loadtest`
- browser or engine integration tests for join, state callback handling, reconnect UI, and rendering of remote entities
- deployment smoke tests for public address, WSS, reverse proxy, Redis presence/driver, and graceful shutdown

Do not call multiplayer work complete without at least one automated room test and one runtime connection smoke test.

---

# Anti-Patterns

Never introduce:

- client-authoritative health, damage, movement, score, inventory, or currency
- mutable schema state reassigned wholesale after room startup
- hidden gameplay rules inside unvalidated message callbacks
- every room type sharing one giant state schema
- private state placed in shared room state by default
- missing `onAuth` in production rooms
- Redis or database calls directly inside hot message paths without timeout and error handling
- scaling assumptions that ignore room ownership by process
- room cleanup that deletes players before reconnection can succeed
- monitoring/admin endpoints exposed without protection
- load-testing conclusions based on local loopback only

---

# Reference Sources

- Colyseus documentation: https://docs.colyseus.io/
- Rooms: https://docs.colyseus.io/room
- State synchronization: https://docs.colyseus.io/state
- Match-maker API: https://docs.colyseus.io/server/matchmaker
- Reconnection: https://docs.colyseus.io/room/reconnection
- Room authentication: https://docs.colyseus.io/auth/room
- Presence: https://docs.colyseus.io/server/presence
- Driver: https://docs.colyseus.io/server/driver
- Scalability: https://docs.colyseus.io/scalability
- Monitoring panel: https://docs.colyseus.io/tools/monitoring
- Load testing: https://docs.colyseus.io/tools/loadtest

---

# Code Generation Rules for Agents

When generating Colyseus multiplayer code:

1. Start with room boundaries, state schema, message contracts, auth policy, and matchmaking flow.
2. Keep server simulation authoritative and validate every client payload.
3. Design synchronized schema state for bandwidth and visibility, not convenience.
4. Implement reconnect behavior before calling a room production-ready.
5. Keep client SDK callbacks behind a multiplayer service layer.
6. Add unit tests for room lifecycle and message handling.
7. Add load-test scripts before scaling claims.
8. Document Redis/presence/driver/public-address requirements for multi-process deployment.

When in doubt:

**Let Colyseus own real-time rooms; let your game own explicit authoritative rules.**
