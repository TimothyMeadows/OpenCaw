---
name: create-game-vfx
description: Design and implement readable, performant game visual effects with semantic timing, bounded layers, pooling, cleanup, accessibility, and gameplay validation. Use for hit, cast, summon, movement, status, environment, UI-world, and transition effects.
---

# Create Game Vfx

## When to use

- Adding feedback for a gameplay event or state.
- Building sprite, particle, shader, mesh, trail, or screen-space effects.
- Reviewing VFX for readability, timing, accessibility, or runtime cost.

## Workflow

1. Define the gameplay event, audience, visibility distance, camera, duration, priority, and success signal.
2. Break the effect into anticipation, activation, impact, sustain, and release as applicable.
3. Assign shape, color, motion, scale, depth, audio, camera, and UI layers without duplicating feedback.
4. Choose the active architecture's implementation path and define pool, allocation, overdraw, light, particle, and texture budgets.
5. Provide reduced-flash, reduced-motion, contrast, and color-independent cues.
6. Validate timing against authoritative gameplay events and test cleanup under repeated activation.

When a staged effect is authored or simulated in Blender, use `simulate-blender-effects` for deterministic solver and cache ownership before this skill defines runtime timing, pooling, and gameplay validation.

## Output

- A VFX timing and layer brief.
- Runtime asset, budget, pooling, accessibility, and fallback requirements.
- Representative gameplay and stress-test acceptance criteria.

## Guardrails

- Do not let VFX timing decide authoritative hits or state.
- Do not obscure hazards, targets, UI, or player silhouettes.
- Do not create unbounded particles, lights, allocations, or screen flashes.
