---
name: unity-integrate-multiplayer-services
description: Integrate explicitly selected Unity multiplayer sessions, discovery, matchmaking and Relay with owned cancellation and reconnect lifecycles.
engines: [UNITY]
---

# Unity Integrate Multiplayer Services

## When to use

Implement session membership, player grouping, matchmaking or selected connection services. Gameplay replication and NGO authority remain owned by `unity-integrate-netcode`; session ownership does not confer gameplay authority.

## Activation and inputs

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unity-integrate-multiplayer-services`; require effective `UNITY`, compatibility and permitted scope. Inspect installed `com.unity.services.multiplayer` and any existing Lobby/Relay/Matchmaker integration before choosing an API. Record identity, service environment, topology, hosting/transport selection, join visibility, reconnect deadlines and permitted operations. Do not migrate packages or start a paid allocation implicitly.

## Workflow

1. Model create/search/join/match/reconnect/leave as owned operations. Bind every result and subscription to an account and attempt generation. Cancel matchmaking tickets when supported; reconcile and clean up a late successful allocation or join.
2. Select Sessions APIs supported by the locked package. Keep service state, transport establishment and replicated-scene readiness distinct; a listed or joined session is not proof that gameplay is ready.
3. Configure Relay, networking handlers and host/dedicated-server capacity only when explicitly selected. Preserve an existing individual-SDK project unless migration is in scope. Never substitute Netcode for Entities or enable a hosting product automatically.
4. Implement reconnect within actual service retention limits. Preserve stable player identity; verify membership, transport recovery and authoritative snapshot before restoring controls. Session-owner election alone cannot recover a lost game simulation.
5. Own event handlers, heartbeats where required, tickets and session handles. Leave/shutdown is idempotent; shutdown while joining must not leak a late connection. Bound retries and expose full/closed/kicked/expired outcomes.

Read [sessions and networking](references/session-lifecycle.md) for service boundaries and adverse scenarios.

## Verification and output

Deliver a versioned session/transport/replication map, operation-state ownership and sanitized multi-client evidence. Exercise simultaneous joins, cancellation races, host loss, reconnect expiry, rejected authentication and scene changes during connect. Clearly separate local simulations, real SDK calls and deployed multiplayer results. Service environments, relay traffic and hosting spend need explicit authorization; missing prerequisites remain blocked/not-run. Keep observations under resolved `.hephaera/.cache`.
