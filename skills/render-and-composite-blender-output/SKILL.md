---
name: render-and-composite-blender-output
description: Render and composite Blender 4.5 stills, animation, passes, alpha, and pre-rendered 2D or 2.5D output. Use for render-engine choice, color management, pass design, compositing, frame delivery, staged media, and renderer-specific verification.
---

# Render and Composite Blender Output

## When to use

Use for Blender stills, animation, render-engine choice, passes, alpha, compositing, frame sequences, or pre-rendered 2D and 2.5D output.

## Workflow

1. Confirm target resolution, frame range, alpha, color space, bit depth, format, duration, budget, and review destination.
2. Select Eevee or Cycles from required fidelity, effects, determinism, hardware, and render-time constraints.
3. Freeze color management, sampling, denoising, motion blur, transparency, and pass ownership.
4. Build a bounded compositor graph with named inputs, premultiplication policy, and missing-pass failure behavior.
5. Render representative frames before the full range; inspect edges, flicker, noise, color, alpha, continuity, and frame numbering.
6. Keep outputs staged under the media contract until human review; then hand off approved 2D, 2.5D, or cinematic artifacts.

Read [render-composite-contract.md](references/render-composite-contract.md) for pass, color, and delivery rules.

## Guardrails

- Do not silently change engines, color transforms, samples, or output formats between review and final render.
- Do not overwrite prior frames or call partial output complete.
- Do not promote generated or rendered media without human review.
