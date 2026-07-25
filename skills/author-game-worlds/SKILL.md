---
name: author-game-worlds
description: Design or revise readable, testable game spaces with explicit routes, landmarks, collision, navigation, encounter zones, objectives, lighting, and content data. Use for levels, maps, arenas, hubs, traversal spaces, or world expansions across supported game architectures.
---

# Author Game Worlds

## When to use

- Creating a new level or revising an unreadable space.
- Defining level data and ownership before runtime implementation.
- Preparing deterministic traversal and encounter verification.

## Workflow

1. Define player verbs, camera, gameplay plane, scale, movement limits, and the level's learning or challenge goal.
2. Separate authored content, collision, navigation, encounters, objectives, lighting, decoration, and runtime state.
3. Lay out primary and recovery routes with landmarks, pacing, readable boundaries, and safe restart points.
4. Represent content with stable identifiers and validated data rather than hidden scene state.
5. Use motivated lighting and visual hierarchy to support navigation and gameplay.
6. Verify traversal, collision, objectives, encounter entry and exit, camera behavior, and representative failure paths.

## Output

- A level brief and system ownership map.
- Validated content schema or placement specification.
- Desktop and supported-device playthrough scenarios with acceptance criteria.

## Guardrails

- Do not use decoration to hide broken navigation or collision.
- Do not make map-editor drafts authoritative without reviewed integration.
- Do not add content density that prevents players from reading threats and objectives.
