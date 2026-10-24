---
name: godot-build-multiplayer
description: Implement Godot MultiplayerAPI ownership, RPC validation, and scene replication with explicit transport and failure testing.
engines: [GODOT]
---

# Godot Build Multiplayer

## When to use

Implement Godot MultiplayerAPI ownership, RPC validation, and scene replication with explicit transport and failure testing. Apply this feature only to Godot-owned code and content.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh godot-build-multiplayer` before edits or tool launches. Continue only when the effective engine is `GODOT` and the skill is eligible. Skill selection never selects the engine. Honor validated task override evidence and its permitted isolated output scope.

Identify Godot version, project language, topology, transport, platform exports, player counts, authority and bandwidth budgets. Select ENet, WebSocket or WebRTC explicitly according to platform support; optional services are not implicit.

## Workflow

1. Configure MultiplayerAPI/SceneMultiplayer and the selected MultiplayerPeer lifetime. Separate connection establishment, authentication/session rules and in-game replication; define timeout, rejection and cleanup behavior.
2. Declare node authority and RPC permissions explicitly using the selected language's supported annotation/attribute APIs. Validate remote sender identity, authorization, payload bounds and gameplay preconditions before state mutation.
3. Keep matching network node paths and deterministic spawn identity where the API requires them. Use MultiplayerSpawner and MultiplayerSynchronizer only with approved spawn scenes/properties and validate their authority settings.
4. Separate persistent replicated state from transient events. Late join and reconnect must receive complete snapshots; event deduplication and tick ordering need explicit design rather than trusting packet arrival order.
5. Implement bounded serialization with stable content IDs and schema validation. Do not enable arbitrary remote object decoding, script execution or unconstrained resource paths.
6. Choose channel and transfer modes from event semantics and selected transport support. Prediction, interpolation and reconciliation belong to the authority design; replication nodes do not supply rollback automatically.
7. Clean up actors, signals and peer resources on disconnect or scene transitions. Expired network effects and haptic cues must not replay after reconnect, and presentation failures cannot alter authoritative rules.

## Verification

- Run a real server/host and two separate clients; test late join, unauthorized RPCs, missing spawn content and authority transfer.
- Exercise latency/loss/reordering where the transport supports controlled simulation, plus connection failure and reconnect cleanup.
- Measure bandwidth/server work and test actual export-platform transport support. Browser networking and native networking are separate acceptance surfaces.

## Output

Transport/authority map, bounded RPC and replication contracts, multiplayer scene assets, abuse/lifecycle fixtures and multi-process evidence. Record environment, scope, expected and observed results, evidence paths, and blocked or not-run checks separately from passes.

## Boundaries

Do not provision matchmaking/STUN/TURN or expose public ports implicitly. Godot C# web export is not supported by current Godot 4 documentation; verify the chosen release before promising a platform. Independent services and tools retain their architecture contracts.

## References

- [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html). Select the documentation matching the project release.
- [Godot C# platform support](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/index.html). Select the documentation matching the project release.

