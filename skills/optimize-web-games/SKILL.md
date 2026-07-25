---
name: optimize-web-games
description: Measure and improve web-game CPU, GPU, memory, loading, input, rendering, and mobile behavior using repeatable scenes and explicit budgets. Use for frame drops, thermal cost, long-session degradation, oversized assets, touch issues, or release performance gates.
---

# Optimize Web Games

## When to use

- A browser game misses frame or input-latency targets.
- A scene performs differently across desktop and mobile.
- A regression requires a stable performance fixture.

## Workflow

1. Choose a deterministic scene, content seed, camera path, input sequence, device class, and measurement duration.
2. Measure frame timing, long tasks, draw calls, triangles, texture memory, allocations, garbage collection, loading, and input delay as supported.
3. Diagnose whether the limit is simulation, main-thread integration, rendering, assets, memory, or device input.
4. Apply low-risk changes first: visibility culling, pooled objects, bounded updates, asset budgets, shared resources, and reduced pixel cost.
5. Verify touch controls, safe areas, responsive HUD, background pause, context loss, and long-session cleanup.
6. Repeat the fixture and record regression thresholds.

## Output

- A repeatable performance fixture and budget table.
- Before-and-after measurements with the limiting subsystem.
- Remediation, device tradeoffs, and regression protection.

## Guardrails

- Do not reduce gameplay readability to meet a frame target without design review.
- Do not compare different scenes or device states as if they were equivalent.
- Do not hide leaks behind periodic scene reloads.
