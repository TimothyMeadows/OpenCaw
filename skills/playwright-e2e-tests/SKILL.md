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
- Prefer existing commands in `./commands/` when a deterministic workflow exists. For Playwright, prefer `commands/playwright-test.sh`, `commands/playwright-install.sh`, and `commands/playwright-evidence-report.sh`.
- Keep Playwright suites deterministic:
  - Prefer role/name and stable test-id selectors over CSS/XPath-only selectors.
  - Isolate test data so tests can run in parallel safely.
  - Avoid fixed sleeps; prefer explicit waits on stable UI/network states.
- Treat flaky tests as defects:
  - Capture traces and retries for diagnosis.
  - Record likely root cause and ownership for stabilization.
- During implementation, post QA evidence to the linked task issue when useful:
  - include pass/fail summary
  - include screenshot/artifact references (especially Playwright screenshots)
  - use `../commands/comment-issue-test-results.sh` to keep issue history complete
- After a PR is confirmed available, use the `post-pr-qa` workflow so the PR receives a GitHub comment with pass/fail evidence and inline screenshot URLs when screenshots are part of the proof.

## Implementation guidance

When adding or changing Playwright coverage:
- Read `ARCHITECTURE.md` first. If the host repository uses the `PLAYWRIGHT` template, follow it as the testing contract.
- Identify the workflow owner: smoke, regression, discovery, data-entry, visual/report comparison, or CI validation.
- Keep specs orchestration-focused. Put selectors and browser interactions in page objects or host-local helpers when the workflow is reusable.
- Keep credentials and environment selectors in host-owned env vars, CI secrets, or artifact files. Never add secrets to OpenCaw skills, commands, or assets.
- Prefer a narrow targeted run before a broad suite run. Capture the command, browser project, grep/tag filter, and artifact locations in the final verification notes.
- When interactive UI/report viewers are unavailable, generate evidence with `commands/playwright-evidence-report.sh` and cite the resulting Markdown report paths.
