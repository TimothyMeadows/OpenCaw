---
name: simulate-blender-effects
description: Author deterministic Blender 4.5 cloth, hair, rigid-body, particle, fluid, smoke, and volume effects with controlled caches. Use for simulation setup, collision ownership, bake policy, reproducibility, cache verification, and rendered or game-VFX handoff.
---

# Simulate Blender Effects

## When to use

Use for Blender cloth, hair, rigid-body, particle, fluid, smoke, volume, collision, deterministic bake, or cache-delivery work.

## Workflow

1. Define the effect purpose, scale, frame range, solver, collision layers, quality target, and deterministic inputs.
2. Separate control geometry, simulation geometry, render geometry, and collision proxies.
3. Declare cache path, version, seed, bake owner, invalidation rules, storage budget, and portability.
4. Run low-cost diagnostic bakes before final quality and inspect starts, contacts, tunneling, instability, and loop seams.
5. Bind accepted cache evidence to source identity and settings.
6. Route runtime effects through `create-game-vfx`; route pre-rendered output through `render-and-composite-blender-output`.

Read [simulation-bake-contract.md](references/simulation-bake-contract.md) for cache and acceptance requirements.

## Guardrails

- Do not rely on an unbaked viewport result as delivery evidence.
- Do not store caches outside the repository or leave required caches unresolved.
- Do not let a rendered simulation determine authoritative gameplay timing.
