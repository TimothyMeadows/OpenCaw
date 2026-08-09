---
name: build-scroll-authored-web-experiences
description: Design and implement accessible, reversible web narratives whose visual state is authored against native scroll position. Use for scrollytelling, editorial journeys, product stories, image or video sequences, and persistent WebGL scenes that need stable story beats, responsive composition, fallbacks, lifecycle cleanup, and measured performance.
---

# Build Scroll-Authored Web Experiences

## When to use

- A narrative page needs scroll position to reveal or transform a sequence of sourced ideas.
- A team must choose between semantic HTML/SVG, pre-rendered media, and persistent WebGL for one visual stage.
- An existing scroll-driven experience needs deterministic reversal, responsive composition, accessible fallback, cleanup, or performance hardening.

## Workflow

1. Define the audience, intended understanding, source material, and success evidence. Turn the narrative into 5–7 stable, source-backed beats before choosing effects.
2. Read [renderer selection](references/renderer-selection.md) and choose exactly one primary renderer for the visual stage: semantic HTML/SVG, a pre-rendered image/video sequence, or persistent WebGL.
3. Read the [scroll experience contract](references/scroll-experience-contract.md) and record the beat map, scroll-state ownership, responsive compositions, accessibility behavior, fallbacks, lifecycle, and numeric budgets.
4. Build the complete semantic document in reading order. Treat enhanced visuals as a progressive layer rather than the only source of essential content or actions.
5. Derive deterministic visual state from exact native scroll position. Allow smoothing only in presentation values, and make reverse scrolling, jumps, resize, restoration, and repeated traversal converge on the same state.
6. Implement mobile composition, reduced motion, loading and error behavior, fallback rendering, and complete disposal before polishing choreography.
7. Verify every beat in both directions across representative viewports and input methods. Measure the recorded budgets and capture evidence for the semantic, enhanced, reduced-motion, and fallback paths.

## Related OpenCaw skills

- Use `design-web-experiences` for the broader visual system and page hierarchy.
- Use `build-accessible-motion-systems` for motion tokens, interruption, and reduced-motion choreography.
- Use `build-webgl-experiences` when persistent WebGL is the selected renderer.
- Use `capture-full-page-evidence` for trustworthy browser evidence.
- Use `profile-application-performance` for reproducible runtime measurements.

## Output

- A cited story map with 5–7 stable beats and semantic counterparts.
- One documented renderer decision and fallback ladder.
- An implementation contract for exact scroll truth, responsive and accessible behavior, cleanup, and numeric budgets.
- Evidence that forward, reverse, mobile, reduced-motion, failure, and long-session paths satisfy the contract.

## Guardrails

- Do not run multiple primary renderers for the same visual stage.
- Do not let interpolation, animation completion, or renderer state become authoritative scroll state.
- Do not make essential meaning or actions depend on motion, canvas, WebGL, hover, or sound.
- Do not add a rendering dependency when the simpler renderer meets the story and budget.
- Do not copy a reference site's identity, composition, prose, assets, or interaction choreography.
