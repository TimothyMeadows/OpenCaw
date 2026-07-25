---
name: extract-interaction-patterns
description: Analyze HTML or a live interface and express its interactions as reusable, framework-neutral behavior contracts. Use when hover, focus, scroll, drag, reveal, navigation, canvas, or state transitions must be documented before implementation or testing.
---

# Extract Interaction Patterns

## When to use

- Turning an existing interface into interaction requirements.
- Discovering event, state, accessibility, and cleanup behavior.
- Creating a handoff for frontend development or browser QA.

## Workflow

1. Inspect semantic structure, interactive controls, stable states, and input modalities.
2. Map each trigger to preconditions, state changes, visuals, duration, interruption, reversal, and completion.
3. Document keyboard, touch, pointer, focus, reduced-motion, and failure behavior.
4. Identify timers, animation loops, observers, listeners, and resources that require cleanup.
5. Separate the essential interaction contract from the current library or framework.
6. Define deterministic test states and observable acceptance criteria.

## Output

- An interaction inventory and state-transition table.
- Framework-neutral implementation guidance.
- Accessibility, performance, cleanup, and browser test requirements.

## Guardrails

- Do not copy page copy, branding, asset URLs, or implementation code.
- Do not infer server behavior from client presentation alone.
- Do not describe pointer-only behavior without an equivalent accessible path.
