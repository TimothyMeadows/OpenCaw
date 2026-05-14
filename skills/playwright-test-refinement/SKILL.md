---
name: playwright-test-refinement
description: Refine, rerun, and stabilize Playwright tests using prior failures, traces, screenshots, and source-controlled test code.
---

## When to use

Use when a Playwright test is failing, flaky, stale after UI changes, missing evidence, or needs a rerun with focused diagnostics.

Typical triggers:
- "rerun this Playwright test"
- "fix the flaky browser test"
- "analyze this Playwright report"
- "update selectors after UI changes"
- "compare screenshots or traces"

## Output

Produce a remediation package:
- failure synopsis from logs, traces, reports, or screenshots
- likely root cause grouped as test data, selector, timing, app bug, infrastructure, or environment
- changes made or recommended
- focused commands run and results
- remaining risk and artifact paths

## Notes

- Start by reading the existing spec, fixtures, page objects, and latest report artifacts before changing code.
- Prefer fixing root causes over adding broad sleeps or retries.
- If live DOM confirmation is required, use the host repo's existing spec or fixture path to reach the page, then inspect from there.
- Keep generated screenshots, traces, and reports in ignored host artifact folders.
- When a required field or validation error appears, determine whether the source data actually contains the value before adding fixture data.
- Use `commands/playwright-report-summary.sh` and `commands/playwright-artifact-index.sh` before relying on the Playwright HTML report UI.
