---
name: profile-application-performance
description: Plan and execute evidence-driven performance profiling using tools supported by the host architecture. Use for slow startup, CPU spikes, memory growth, hangs, jank, high I/O, thermal cost, battery impact, or regressions that require measured diagnosis.
engines: [AGNOSTIC]
---

# Profile Application Performance

## When to use

- A performance problem is reproducible but its limiting resource is unknown.
- A change needs before-and-after performance evidence.
- A release requires explicit budgets and residual-risk reporting.

## Workflow

1. Define the user-visible symptom, workload, environment, warmup, duration, and success threshold.
2. Choose profilers supported by the active architecture; prefer built-in diagnostics before adding dependencies.
3. Capture a baseline across CPU, allocation or memory, I/O, network, startup, and frame timing as relevant.
4. Form one hypothesis from the dominant evidence and change one ownership boundary or hot path at a time.
5. Repeat the same workload and compare distributions rather than one sample.
6. Record measurement limitations, regressions, and monitoring recommendations.

## Output

- A reproducible profiling protocol.
- Baseline and comparison evidence with units and environment.
- Root-cause confidence, remediation, residual risk, and regression thresholds.

## References

- Read `skills/build-gameplay-runtime/references/bounded-world-work.md` in the resolved Hephaera baseline (`.hephaera/skills/build-gameplay-runtime/references/bounded-world-work.md` from an installed host's root) when profiling identifies world-query, queue, navigation, allocation, or residency costs. Use comparable workloads and distinguish fixture correctness from actual engine/device performance before selecting a custom technique.

## Guardrails

- Do not optimize from intuition alone.
- Do not compare runs with materially different workloads or environments.
- Do not add production telemetry that captures secrets or personal data.

## Engine and feedback budgets

Resolve ENGINE.md and compatible feature skills before engine APIs. Declare target device, build, frame/CPU/GPU/memory/loading budgets and measurement windows; do not impose universal 60 FPS. Measure representative UI layout, HUD lifecycle, overlapping effects and shader/audio/haptic requests, including disabled accessibility settings and interruption. Browser profiling requires a browser build; native engines need native tooling. Feedback cannot determine authoritative outcomes and physical haptics require hardware evidence.
