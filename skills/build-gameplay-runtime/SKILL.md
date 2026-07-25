---
name: build-gameplay-runtime
description: Implement deterministic gameplay systems with clear simulation, content, presentation, input, persistence, and lifecycle boundaries. Use for cameras, controls, inventory, enemies, monsters, audio feedback, targeting, progression, and integrated game-loop work.
---

# Build Gameplay Runtime

## When to use

- Building or refactoring reusable gameplay systems.
- Adding content without duplicating runtime logic.
- Fixing state, lifecycle, persistence, or presentation coupling.

## Workflow

1. Read the active game architecture and locate the authoritative loop, state, content, input, rendering, and persistence boundaries.
2. Define serializable content contracts separately from mutable runtime state.
3. Use explicit state machines or deterministic transitions for actors, abilities, inventory transfers, and progression.
4. Treat inventory and persistence changes as validated transactions with migration and no-loss tests.
5. Keep presentation adapters replaceable and provide honest fallbacks for unavailable assets.
6. Dispose render resources, events, audio nodes, timers, workers, and observers on teardown.

## Output

- A runtime ownership and data-flow design.
- Typed content and state contracts with failure behavior.
- Targeted unit, integration, persistence, lifecycle, and playthrough tests.

## Guardrails

- Do not store authoritative game state only in render objects or component visibility.
- Do not allocate unbounded work in the frame loop.
- Do not couple one content item to bespoke runtime code when a shared contract is viable.
