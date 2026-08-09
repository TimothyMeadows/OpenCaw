# Scroll Experience Contract

Write this contract before implementation and keep it aligned with the shipped experience.

## Story map

Define 5–7 stable beats. Give each beat a durable ID and record:

| Field | Requirement |
| --- | --- |
| Source | Link or repository reference supporting the claim, artifact, or product fact. Mark creative interpretation separately. |
| Intended understanding | What the audience should know, feel, compare, or decide after the beat. |
| Semantic counterpart | Heading, prose, figure, caption, data table, or control present in document order. |
| Scroll interval | A non-overlapping or explicitly composed normalized interval with entry, focus, and exit state. |
| Visual state | Deterministic camera, layer, media, typography, or scene values derived from scroll truth. |
| Responsive composition | Wide, narrow, and short-viewport treatment without changing the beat's meaning. |
| Reduced motion | Immediate or low-motion state that preserves orientation and content. |
| Evidence | Inspectable assertion, screenshot, trace, or measurement proving the beat works. |

Do not use scroll distance as the only content boundary. Map each beat to semantic content so search, assistive technology, no-script rendering, and direct navigation retain the narrative.

## Scroll-state authority

- Treat current native scroll position and measured document geometry as exact truth.
- Normalize exact progress within an explicitly owned scroll range and derive beat state as a pure function of that progress.
- Keep any damped or interpolated value presentation-only. Never use it for routing, content completion, analytics milestones, focus, or other durable decisions.
- Recompute geometry after documented layout changes. Preserve state across resize, orientation change, font load, media load, history restoration, and dynamic content without trapping or jumping the user.
- Make forward, reverse, scrollbar drag, keyboard scroll, touch fling, anchor jump, and restored position settle on the same visual state for the same exact progress.
- Use a single frame owner for visual updates. Bound observers and passive listeners, pause offscreen or hidden work, and remove every listener, observer, timer, frame, media request, and rendering resource on teardown.

## Access and resilience

- Keep headings, landmarks, links, controls, captions, and reading order in semantic DOM.
- Preserve focus visibility and keyboard access; never hijack native scrolling or require precision pointer input.
- Respect reduced motion from the first render. Avoid autoplaying or scrubbing intense motion on that path.
- Define loading, error, no-script, unsupported capability, media failure, and rendering-context-loss states.
- Keep essential content and actions usable while assets load and after enhancement failure.

## Numeric budgets

Set project-specific thresholds before choosing implementation details. Record the measurement workload and target device for:

- initial transfer and enhancement transfer by asset type;
- largest decoded media and peak retained media memory;
- frame-time percentile and dropped-frame allowance while scrolling;
- main-thread long-task allowance and per-frame update work;
- renderer resolution, pixel ratio, draw calls, geometry, and texture memory when applicable;
- time to semantic content, time to first usable beat, and fallback activation;
- idle resource use and memory growth after repeated forward/reverse traversals.

A budget is incomplete without a number, unit, workload, environment, measurement method, and pass condition.

## Acceptance scenarios

Verify at minimum:

- exact direct entry to each beat and deterministic forward and reverse traversal;
- wide, narrow, short, zoomed, touch, keyboard, and restored-scroll states;
- reduced motion enabled before load and toggled during the session;
- slow loading, missing media, script failure, unsupported renderer, and context loss;
- semantic reading order and complete task flow without the enhanced stage;
- cleanup after navigation and stable memory across repeated traversal;
- all recorded performance budgets on representative hardware.
