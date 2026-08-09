# Renderer Selection

Choose one primary renderer for the experience's visual stage. Keep the semantic document as the content and navigation truth regardless of renderer.

## Decision inputs

Record:

- the communication job of the visual stage;
- required depth, lighting, camera, simulation, and user input;
- asset availability and provenance;
- target browsers, devices, and network conditions;
- authoring and maintenance capacity;
- accessibility, fallback, and numeric performance requirements.

## Options

| Primary renderer | Choose when | Avoid when |
| --- | --- | --- |
| Semantic HTML/SVG | Layout, typography, diagrams, paths, masks, and lightweight transforms can express the story while preserving crisp, inspectable content. | The experience requires continuous real-time depth, lighting, or simulation that cannot be represented honestly in two dimensions. |
| Pre-rendered image/video sequence | Art direction must be exact, runtime behavior is mostly playback, and the asset budget can support responsive variants and controlled decoding. | Content changes often, interaction must alter the world, frames cannot fit network or memory budgets, or an equivalent semantic treatment is sufficient. |
| Persistent WebGL | A continuous 3D world, camera, lighting, shader, or simulation is essential to the story and simpler media cannot preserve the intended relationship. | The effect is decorative, target devices cannot sustain the measured budget, or fallback content would lose the experience's essential meaning. |

## Ownership rule

Assign one system to own the visual stage and its lifecycle. Supporting DOM labels, captions, controls, and accessibility content do not count as another primary renderer. Do not build parallel full-fidelity stages and switch between them at runtime.

For WebGL, keep one persistent renderer and scene unless the host architecture documents a stronger ownership boundary. For sequences, keep one media pipeline and define preload, decode, eviction, cancellation, and missing-frame behavior. For HTML/SVG, prefer native layout and compositing before adding canvas.

## Fallback ladder

Define fallbacks before implementation:

1. Keep the semantic narrative and actions available without enhancement.
2. Replace unsupported or over-budget real-time rendering with a representative still, short media treatment, or simplified HTML/SVG state.
3. Preserve beat identity and essential meaning across primary and fallback paths.
4. Trigger fallback deterministically for unsupported capabilities, loading failure, context loss, or a documented budget breach; never fail into an empty stage.

Document the chosen renderer, rejected alternatives, evidence, primary budgets, fallback trigger, and fallback asset or structure.
