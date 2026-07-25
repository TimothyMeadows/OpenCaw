---
name: derive-visual-spec-from-video
description: Convert a supplied video into an implementation-neutral visual and motion specification. Use when a product demo, interaction recording, animation study, or gameplay clip must be analyzed for layout, timing, state changes, assets, responsive behavior, and accessible fallbacks.
---

# Derive Visual Spec From Video

## When to use

- A user provides a video and needs a build specification.
- Motion must be reconstructed from observable states and timing.
- A reviewer needs a timeline of interaction and presentation behavior.

## Workflow

1. Confirm the target outcome, intended platform, video duration, dimensions, and available frames.
2. Divide the recording into scenes, state transitions, and stable visual states.
3. Record spatial hierarchy, camera or viewport movement, timing, easing character, layering, input cues, and asset roles.
4. Identify behavior that is uncertain because frames, inputs, or hidden state are unavailable.
5. Specify semantic fallback and reduced-motion behavior for every essential transition.
6. Translate observations into acceptance criteria rather than source-specific implementation.

## Output

- A scene and transition timeline.
- Layout, visual token, asset, state, and motion requirements.
- Implementation risks, unknowns, accessibility requirements, and verification scenarios.

## Guardrails

- Do not claim hidden implementation details are observed facts.
- Do not require exact reproduction of distinctive branding or creative expression.
- Do not extract or redistribute embedded media assets unless authorized.
