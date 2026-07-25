---
name: build-accessible-motion-systems
description: Design and implement a reusable motion system with purposeful tokens, choreography, interruption, cleanup, and reduced-motion behavior. Use when a product needs entrance, navigation, feedback, scroll, hover, focus, or state-transition animation that remains accessible and performant.
---

# Build Accessible Motion Systems

## When to use

- Adding a consistent motion language to a site or application.
- Replacing scattered animation values with governed tokens.
- Reviewing motion for accessibility, lifecycle, or performance defects.

## Workflow

1. Define the user purpose for each motion category: orientation, hierarchy, continuity, feedback, or emphasis.
2. Create bounded duration, easing, distance, delay, and stagger tokens.
3. Implement a small primitive set before composing sequences.
4. Specify interruption, reversal, repeated activation, focus, visibility, and route-change behavior.
5. Provide reduced-motion behavior that preserves state comprehension without decorative movement.
6. Measure animation cost and dispose timers, observers, listeners, frames, and rendering resources.

## Output

- A motion token table and primitive inventory.
- Choreography rules with responsive and reduced-motion behavior.
- Implementation, cleanup, performance, and test acceptance criteria.

## Guardrails

- Do not animate layout when transform or opacity can express the same result.
- Do not make essential content depend on an animation completing.
- Do not add continuous movement without a user benefit and pause strategy.
