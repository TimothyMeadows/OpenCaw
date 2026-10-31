# Vehicle speed and warp presentation

Consume measured speed, acceleration, turn rate, grounded/water context and explicit travel phases from the authoritative controller. Drive exhaust, trails, wheel spray/dust, wakes and emissive/material response through stable motion-package anchors. A particle callback or animation completion cannot decide travel, impact damage, death or warp arrival.

Ordinary movement uses bounded continuous intensity curves; warp has enter, sustain, exit and cancel phases. Declare local/world particle space, lifetime, emission/instance/overdraw limits, pool ownership, quality tiers and required cues under reduced motion/flash. Dust needs a suitable surface and a wake needs water context. Avoid permanently increasing camera FOV, shake or time scale after interruption.

Use event IDs plus actor generation and simulation revision to reject stale/duplicate events. Assign one presentation clock, pause behavior, expiration and cancellation owner. Despawn, pooling, focus/scene exit and prediction rejection clear owned listeners, effects and pending callbacks. A respawned actor cannot inherit the previous actor's warp or death effect.

Select actual engine primitives through compatible feature owners. Core GLB animation channels do not instantiate Niagara, Unity ParticleSystem or Godot GPUParticles3D. Three.js particle production uses the selected three.quarks owner and bounded host-locked integration; particle-free mesh/material effects remain available for their own purposes. Do not silently install middleware or assume bitwise deterministic GPU particle replay.

Verify actual target playback, bounded counts and costs under repeated acceleration, boost, warp enter/cancel/exit, pause and pooled reuse. Low-quality/reduced-motion settings retain essential gameplay cues. A sidecar or Blender preview cannot establish runtime effect appearance, motion comfort or performance.
