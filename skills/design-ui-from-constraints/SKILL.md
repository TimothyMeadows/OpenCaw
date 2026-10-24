---
name: design-ui-from-constraints
description: Turn product goals and explicit constraints into a coherent UI direction and variant plan. Use when a user needs layout, hierarchy, typography, color, interaction, responsive, and accessibility decisions before implementation or visual generation.
engines: [AGNOSTIC]
---

# Design Ui From Constraints

## When to use

- A UI request is underspecified or driven only by vague aesthetic language.
- Several controlled variants are needed without random rerolls.
- A frontend handoff needs measurable visual acceptance criteria.

## Workflow

1. Define the user goal, audience, primary task, platform, content density, brand constraints, and implementation limits.
2. Specify format, layout hierarchy, typography roles, color roles, imagery, interaction, motion, and accessibility.
3. Create a constraints card listing what must remain fixed and what may vary.
4. Produce controlled variants that change one or two major dimensions at a time.
5. Select a direction using task clarity, originality, feasibility, responsive behavior, and accessibility.
6. Translate the choice into implementation and validation criteria.

For game interfaces, compose `build-game-ui` to specify safe areas, localization and text-scale variations, screen/modal input ownership, focus restoration, binding-aware prompts, and HUD lifecycle. Resolve the selected engine's UI skill with `resolve-skill.sh` before implementation. Browser examples apply only to an actual browser surface; a native game interface requires its own runtime evidence.

## Output

- A design brief and constraints card.
- A small variant matrix with meaningful tradeoffs.
- A selected direction with component, responsive, motion, and acceptance guidance.

## Guardrails

- Do not use random variation as a substitute for a design decision.
- Do not rely on generated typography for final readable text.
- Do not choose visual novelty over task clarity or accessibility.
