---
name: profile-application-performance
description: Plan and execute evidence-driven performance profiling using tools supported by the host architecture. Use for slow startup, CPU spikes, memory growth, hangs, jank, high I/O, thermal cost, battery impact, or regressions that require measured diagnosis.
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

## Guardrails

- Do not optimize from intuition alone.
- Do not compare runs with materially different workloads or environments.
- Do not add production telemetry that captures secrets or personal data.
