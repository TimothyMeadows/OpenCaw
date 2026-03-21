---
name: playwright-e2e-tests
description: Design, implement, and validate Playwright end-to-end coverage for critical user workflows.
---

## When to use
Use this skill when a task requires browser-driven verification, UI regression protection, or release confidence for user-critical web flows.

Typical triggers:
- New feature touches authentication, onboarding, checkout, billing, or data mutation paths.
- A bug escaped due to UI workflow drift.
- A release needs smoke coverage for core paths.
- A flaky browser test needs stabilization and deterministic selectors/data setup.

## Output

Produce a concise QA package that includes:
- Scope: targeted workflows and risk rationale.
- Coverage plan: smoke vs regression intent, browser matrix, and environment assumptions.
- Test implementation notes: selectors, fixtures, stubs/mocks, and data setup strategy.
- Verification evidence: commands run, pass/fail summary, and artifact references (trace/video/screenshot) when available.
- Follow-ups: gaps, flaky-risk notes, and prioritized next actions.

## Notes
- Align the work with the active `AGENTS.md`, `ARCHITECTURE.md`, and any active roles.
- Prefer existing commands in `./commands/` when a deterministic workflow exists.
- Keep Playwright suites deterministic:
  - Prefer role/name and stable test-id selectors over CSS/XPath-only selectors.
  - Isolate test data so tests can run in parallel safely.
  - Avoid fixed sleeps; prefer explicit waits on stable UI/network states.
- Treat flaky tests as defects:
  - Capture traces and retries for diagnosis.
  - Record likely root cause and ownership for stabilization.
