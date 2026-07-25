---
name: build-interactive-web-effects
description: Build bounded CSS, SVG, canvas, or DOM interaction effects with semantic fallbacks, input parity, lifecycle cleanup, and performance limits. Use for masks, reveals, glows, gradients, pointer effects, particles, framed details, and other focused enhancements that must not destabilize the page.
---

# Build Interactive Web Effects

## When to use

- Adding one focused visual interaction to an existing surface.
- Choosing the lowest-complexity rendering technique for an effect.
- Hardening an effect for keyboard, touch, reduced motion, and cleanup.

## Workflow

1. State the communication or feedback purpose and the exact surface the effect may change.
2. Choose CSS first, then SVG or canvas only when the visual requirement justifies it.
3. Define idle, hover, focus, active, touch, disabled, loading, error, and reduced-motion states as applicable.
4. Keep decorative layers out of the accessibility tree and preserve the semantic control.
5. Bound pointer work, animation frames, particles, texture sizes, and observers.
6. Test cleanup, resize, input parity, contrast, clipping, and long-session stability.

## Output

- An effect contract with technology choice and state model.
- Performance and accessibility budgets.
- Integration and regression scenarios.

## Guardrails

- Do not rewrite unrelated layout or branding to add one effect.
- Do not require pointer input for essential functionality.
- Do not load remote runtime code or add a dependency without repository approval.
