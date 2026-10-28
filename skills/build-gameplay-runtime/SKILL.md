---
name: build-gameplay-runtime
description: Implement deterministic gameplay systems with clear simulation, content, presentation, input, persistence, and lifecycle boundaries. Use for cameras, controls, inventory, enemies, monsters, audio feedback, targeting, progression, and integrated game-loop work.
engines: [AGNOSTIC]
---

# Build Gameplay Runtime

## When to use

- Building or refactoring reusable gameplay systems.
- Adding content without duplicating runtime logic.
- Fixing state, lifecycle, persistence, or presentation coupling.

## Workflow

1. Read the active game architecture and effective engine selection. Resolve compatible engine feature skills with `resolve-skill.sh` before implementing APIs; selecting this agnostic wrapper never selects an engine. Locate the authoritative loop, state, content, input, rendering, and persistence boundaries.
2. Define serializable content contracts separately from mutable runtime state.
3. Use explicit state machines or deterministic transitions for actors, abilities, inventory transfers, and progression.
4. Treat inventory and persistence changes as validated transactions with migration and no-loss tests.
5. Keep presentation adapters replaceable and provide honest fallbacks for unavailable assets.
6. Dispose render resources, events, audio nodes, timers, workers, and observers on teardown.
7. Define bounded gameplay-feedback events separately from simulation outcomes. Assign event identity, local-player audience, channel priorities, intensity, clock, interruption, cancellation, and overlap policies; review the feedback reference for haptic device ownership and teardown.

## References

- Read [inventory-transactions.md](references/inventory-transactions.md) for conservation invariants, atomic transfers, serialization, migration, and no-loss testing.
- Read [camera-and-runtime-audio.md](references/camera-and-runtime-audio.md) for camera ownership, modifiers, occlusion, browser audio activation, voice budgets, priority, and accessibility equivalents.
- Read [gameplay-feedback-and-haptics.md](references/gameplay-feedback-and-haptics.md) when coordinating animation, camera, sound, VFX, UI, hit-stop, or tactile device output.
- Read [motion-package-integration.md](references/motion-package-integration.md) when connecting authored character/vehicle motion, root displacement or speed/warp presentation to authoritative movement.

## Output

- A runtime ownership and data-flow design.
- Typed content and state contracts with failure behavior.
- Targeted unit, integration, persistence, lifecycle, and playthrough tests.

## Guardrails

- Do not store authoritative game state only in render objects or component visibility.
- Do not allocate unbounded work in the frame loop.
- Do not couple one content item to bespoke runtime code when a shared contract is viable.
- Feedback failure must not alter damage, movement authority, rewards, or other simulation outcomes. Physical knockback belongs to the gameplay rules when it changes an actor's state.
