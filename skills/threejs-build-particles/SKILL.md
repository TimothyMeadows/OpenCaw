---
name: threejs-build-particles
description: Build Three.js particle and VFX systems with its default three.quarks backend, bounded lifecycle ownership and verified host dependencies.
engines: [THREEJS]
---

# Three.js Particles

## When to use

Implement or review particles, emitters, bursts, trails or particle-based gameplay feedback in a Three.js project. THREEJS selects three.quarks automatically; that selection never installs or upgrades packages.

## Workflow

Resolve ENGINE and this skill before production. Read `docs/THREEJS_PARTICLES.md` and `.engine/threejs/particles/README.md` from the shared baseline, the host lockfile, actual renderer and target budgets.

1. Run `commands/threejs-particles.sh inspect` through the installed .hephaera path. Distinguish declared default, locked versions, installed content and actual renderer readiness. Missing/incompatible libraries block this backend; do not upgrade Three.js or substitute another particle system silently.
2. Use host-installed three.quarks and one scene-owned BatchedRenderer with the existing presentation clock. Keep particle, lifetime, emission, instance, material/texture and overdraw budgets finite. Follow the supplied bounded runtime helper or equivalent reviewed host-owned integration.
3. Bind effects to real anchors and explicit action/motion cues. Gameplay owns hits, projectiles, travel and state; particle events are presentation signals. Pause/resume, cancellation, reset, pooling and disposal must release owned effects and leave shared resources intact.
4. Provide quality and reduced-motion/flash controls; preserve essential cues. JSON effects/textures require provenance, rights, budget validation and current host compatibility before use. The hosted editor and optional R3F/nodes integrations are separate choices.
5. Verify actual library lifecycle and real target rendering/performance. Core WebGL support does not imply WebGPU, native/MAUI WebView acceptance, visual quality or deterministic replay.

## Output

Deliver the host dependency/renderer identities, bounded integration and teardown, effect/clock ownership and evidence. Historical pinned Bubo point-based motion/action samples remain historical; do not relabel or silently migrate their approvals.
