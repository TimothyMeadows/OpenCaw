---
name: create-game-vfx
description: Design and implement readable, performant game visual effects with semantic timing, bounded layers, pooling, cleanup, accessibility, and gameplay validation. Use for hit, cast, summon, movement, status, environment, UI-world, and transition effects.
engines: [AGNOSTIC]
---

# Create Game Vfx

## When to use

- Adding feedback for a gameplay event or state.
- Building sprite, particle, shader, mesh, trail, or screen-space effects.
- Reviewing VFX for readability, timing, accessibility, or runtime cost.

## Workflow

For effects timed across a dance, combination or charge/cast sequence, coordinate with `build-model-actions`. Bind cues to real reviewed step/clip markers and anchors, capture fixed target points explicitly, and keep cancellation/resource cleanup separate from gameplay hit and projectile decisions.

For THREEJS, particle production uses the engine-selected `threejs-build-particles` Quarks owner and host-locked compatible packages. Missing dependencies or an unsupported renderer require direction; do not silently substitute native point primitives or install another backend. Other engine owners remain unchanged.

1. Define the gameplay event, audience, visibility distance, camera, duration, priority, and success signal.
2. Break the effect into anticipation, activation, impact, sustain, and release as applicable.
3. Assign shape, color, motion, scale, depth, audio, camera, and UI layers without duplicating feedback.
4. Resolve the active engine and compatible material/animation feature skills through `resolve-skill.sh`; define pool, allocation, overdraw, light, particle, and texture budgets. This agnostic VFX workflow does not authorize another engine's APIs or select a different art pipeline.
5. Provide reduced-flash, reduced-motion, contrast, and color-independent cues.
6. Validate timing against authoritative gameplay events and test cleanup under repeated activation.
7. Define the effect's clock, cancellation owner, overlap/intensity cap, and expiration under pause, focus loss, scene exit, and prediction correction. Coordinate its layer with camera, sound, HUD, and optional haptics through the gameplay-feedback owner; a visual impact is not a tactile effect.

When a staged effect is authored or simulated in Blender, use `simulate-blender-effects` for deterministic solver and cache ownership before this skill defines runtime timing, pooling, and gameplay validation.

Read [vehicle-speed-and-warp.md](references/vehicle-speed-and-warp.md) for motion-package anchors, continuous travel effects, warp phases and cancellation. Use `build-model-animations` for the model/motion package; this skill owns the selected-engine effects and their runtime evidence.

## Output

- A VFX timing and layer brief.
- Runtime asset, budget, pooling, accessibility, and fallback requirements.
- Representative gameplay and stress-test acceptance criteria.

## Guardrails

- Do not let VFX timing decide authoritative hits or state.
- Do not obscure hazards, targets, UI, or player silhouettes.
- Do not create unbounded particles, lights, allocations, or screen flashes.
