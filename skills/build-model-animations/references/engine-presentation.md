# Motion, movement and effects ownership

The motion package describes actual clips/bindings, hierarchy/anchors, continuous parameters and explicit presentation states/transitions. The selected engine owns their implementation. A portable GLB is not an engine particle system or state graph.

Use one controller for authoritative travel, collision, jumping/water state, death and arrival. In-place motion follows measured speed. Extracted root motion supplies validated controller intent and is removed locally so it is not applied twice. Three.js playback supplies neither collision response nor a physics controller; native engine integrations use their selected movement owner.

Ordinary vehicle movement uses speed, acceleration and turn parameters. Wheel rotation needs a declared radius/axis calibration; steering and suspension need distinct pivot/channel ownership. Special phases such as warp enter/sustain/exit/cancel require explicit gameplay requests, travel/streaming/collision rules and cancellation behavior. A completed visual clip cannot decide arrival.

Effects consume stable anchors and semantic state. Exhaust, trails, dust, spray and wakes depend on environment/context. Declare local/world space, lifetime, emission/overdraw/light budgets, quality tiers and reduced-motion/flash controls. Coordinate optional camera/audio/haptic layers through existing feedback ownership; do not create them implicitly.

The executable Three.js adapter accepts host-owned locked APIs, actual animations, a canonical effective-engine receipt and a visual child beneath a separate movement root. It supports bounded native point/material effects and parameter articulation. Read `.styles/.workflows/model-to-animation/engines/README.md` for exact supported fields and limitations, including translation extraction and explicit specialized handling for rotating extracted roots.

Use compatible Babylon.js, Unity, Unreal or Godot animation/material/VFX owners for their actual native artifacts. Do not install plugins or switch ENGINE.md to satisfy a requested feature. Phaser's2D selection requires an explicitly chosen sprite/pre-rendered handoff. Browser proof can cover a web target; it cannot certify native UI, gameplay feel, physical haptics or an unavailable engine.

Capture the actor generation when scheduling external callbacks. Pause, destruction, pooling, respawn, scene exit and prediction rejection must expire old work. Reset/teardown clears owned particles, listeners, local pose overrides and mixer resources while preserving shared host assets.
