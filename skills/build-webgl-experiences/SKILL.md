---
name: build-webgl-experiences
description: Design and implement purposeful WebGL features with clear ownership, bounded rendering cost, responsive lifecycle, accessible fallback, and deterministic validation. Use for interactive 3D, particles, data scenes, immersive backgrounds, or shader effects that materially improve a web experience.
---

# Build Webgl Experiences

## When to use

- A web feature genuinely requires real-time 3D or shader rendering.
- Integrating a WebGL scene into a semantic page or application.
- Diagnosing lifecycle, resize, fallback, or performance failures in a graphics feature.

## Workflow

1. Define the user value and confirm simpler CSS, SVG, image, or video approaches are insufficient.
2. Use the active architecture to choose the renderer and asset pipeline.
3. Separate scene content, simulation, rendering, input, presentation integration, and disposal.
4. Set pixel ratio, geometry, texture, draw-call, update-rate, and mobile budgets.
5. Implement resize, visibility pause, context loss, loading, error, reduced-motion, and non-WebGL fallbacks.
6. Validate visual correctness, interaction, cleanup, memory stability, and page conversion or task clarity.

## Output

- A WebGL architecture and ownership contract.
- Asset and performance budgets with fallback requirements.
- Integration, lifecycle, accessibility, and verification scenarios.

## Guardrails

- Do not create a second renderer when one shared renderer can own the scene.
- Do not use shader pixels as authoritative application or gameplay state.
- Do not obscure semantic content or controls behind the canvas.
