---
name: unreal-build-multiplayer
description: Build Unreal replication and multiplayer lifecycles with explicit server authority, ownership, and network failure evidence.
engines: [UNREAL]
---

# Unreal Build Multiplayer

## When to use

Build Unreal replication and multiplayer lifecycles with explicit server authority, ownership, and network failure evidence. Use this feature for Unreal-owned game code and content.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-multiplayer` before edits or tool launches. Continue only when the effective engine is `UNREAL` and `compatible: true`. Skill selection never selects the engine. Revalidate any task override and its permitted isolated output scope before writes. Record observed context and evidence only in the resolved `.hephaera/.cache/tasks/<task>/`; `ENGINE.md` remains the selector.

Read Unreal version, replication system selection, listen/dedicated topology, player counts, target transports/platforms, session identity and network budgets. Iris, Replication Graph and online service plugins are explicit decisions.

## Workflow

1. Map authority across server GameMode, replicated GameState/PlayerState, owned PlayerControllers and Pawns. Set replication and ownership intentionally; a local controller or replicated property alone does not establish permission.
2. Separate durable replicated state from transient RPCs. Use server/client/multicast RPCs only under supported ownership and relevancy rules; validate target identity, eligibility, range/visibility, sequence, resources, request rate and payload bounds server-side as applicable. Actor ownership routes RPCs but is not proof the request is trustworthy.
3. Define property replication conditions, RepNotify behavior, actor relevance, update frequency and dormancy. Waking dormant objects and late joiners must receive complete state rather than depend on an earlier multicast event.
4. Integrate movement through the selected engine movement/prediction path. Cosmetic interpolation cannot replace authority, and general rigid-body replication is not automatically equivalent to character prediction.
5. Handle spawn, possession, seamless or non-seamless travel, reconnect and disconnect cleanup. Keep account/session identifiers separate from ephemeral actor references and define any persistence transaction boundaries.
6. Bound network serialization and actor counts. Declare expected clients, relevant actors per client, average/peak bits per second and requests per second. Profile saturation, message sizes and server-frame cost on constrained connections; reliable per-frame RPCs can build an unbounded queue under loss.
7. Deduplicate predicted presentation effects using event identities while applying authoritative correction. Feedback failures, audio completion and haptic capabilities must not decide remote gameplay results.

## Verification

- Run distinct server and client processes, including at least two clients; distinguish these results from single-process PIE convenience tests.
- Exercise late join, malicious/invalid requests, ownership changes, loss/latency/jitter, dormancy changes and world travel.
- Measure bandwidth and server frame budget under representative player counts; record transport/session integrations not exercised.

## Output

Authority/ownership and replication contracts, native components/configuration, abuse/lifecycle fixtures and multi-process network evidence. Record environment, scope, expected and observed results, evidence paths, and blocked or not-run checks separately from passes.

## Boundaries

Replication does not provide matchmaking, authentication, hosting or online-service entitlement automatically. Do not create public endpoints, accounts or paid resources implicitly. Independent tools and services retain their own architecture contracts.

## References

Read [authority and recovery budgets](references/authority-recovery-budgets.md) when implementing requests, replication conditions or reconnect.

- [Unreal networking and multiplayer](https://dev.epicgames.com/documentation/en-us/unreal-engine/networking-and-multiplayer-in-unreal-engine). Match the documentation version to the project.
- [Unreal actor replication](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicating-actors-in-unreal-engine). Match the documentation version to the project.

