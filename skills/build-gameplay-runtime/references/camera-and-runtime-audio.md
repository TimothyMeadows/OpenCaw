# Camera and Runtime Audio

## Camera ownership

- Give one controller authority over the base camera pose. Feed follow, orbit, pitch, zoom, lock-on, recoil, shake, cutscene, and accessibility behavior into explicit modifiers rather than competing writers.
- Compute simulation targets first, then presentation smoothing. Keep authoritative aim, targeting, and visibility independent from the smoothed render pose.
- Smooth position, rotation, distance, and field of view independently using time-step-stable behavior.
- Define framing bounds, look-ahead, dead zones, pitch and zoom limits, and reset behavior from gameplay readability requirements.

## Occlusion and failure behavior

- Evaluate obstruction between the intended subject framing and camera, then shorten or reposition the camera through a bounded policy.
- Restore distance smoothly after the obstruction clears without clipping through new blockers.
- Preserve a readable fallback when collision queries, target anchors, or cinematic data are unavailable.
- Test teleport, respawn, target loss, rapid direction changes, small rooms, thin blockers, scene transitions, and teardown.

## Camera modifiers

- Give each modifier priority, weight, blend-in, sustain, blend-out, duration, and cancellation policy.
- Apply high-frequency shake and recoil after stable framing so they cannot corrupt long-lived controller state.
- Cap combined displacement, rotation, and field-of-view change.
- Provide reduced-motion behavior that replaces strong movement with restrained emphasis without changing gameplay outcomes.

## Runtime audio activation

- Create or resume browser audio only from an eligible user gesture. Until activation, queue only bounded semantic requests or use a silent honest fallback.
- Centralize listener ownership, buses, concurrency, priority, spatialization, ducking, and teardown.
- Treat sound requests as presentation events derived from authoritative state; audio completion must not govern gameplay truth.
- Degrade missing or failed audio visibly in diagnostics rather than retrying without limit.

## Voice and priority budgets

- Set global and per-category voice limits. Reserve capacity for critical player, threat, objective, and accessibility cues.
- Rank requests by semantic priority, distance, recency, and duplication policy. Steal or reject lower-priority voices deterministically.
- Coalesce repeated ambience, footsteps, impacts, and UI cues within bounded time windows.
- Dispose sources, buffers, worklets, subscriptions, and scene-scoped buses when ownership ends.

## Accessibility equivalents

- Pair critical audio with readable visual, haptic, caption, or text equivalents as the target platform permits.
- Pair camera shake, rapid zoom, and strong parallax with reduced-motion alternatives.
- Keep captions and visual cues driven by semantic events, not by sampling audio output.
- Test muted audio, denied activation, mono output, reduced motion, and missing haptics without changing authoritative outcomes.

## Verification

- Assert that only one base camera writer exists and modifiers cannot persist after cancellation or teardown.
- Test frame-rate variation, occlusion recovery, target switching, maximum modifier stacking, and reduced motion.
- Test activation denial, voice saturation, priority stealing, scene churn, repeated pause/resume, and resource disposal.
- Capture representative camera and feedback behavior at target aspect ratios, device input modes, and performance budgets.
