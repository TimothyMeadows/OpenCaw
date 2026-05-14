---
name: playwright-browser-discovery
description: Discover live web UI structure with Playwright or playwright-cli before authoring browser tests or page objects.
---

## When to use

Use when the user needs to inspect a live web page, discover selectors, identify field types, record conditional UI behavior, capture screenshots, or confirm a browser workflow before writing Playwright tests.

Typical triggers:
- creating a new page object
- diagnosing a stale selector
- enumerating dropdown/multiselect options
- checking conditional fields after a radio, checkbox, or dropdown change
- producing UI evidence for a test plan

## Output

Produce a concise discovery record:
- target environment and entry URL
- navigation path used to reach the screen
- stable selectors or IDs discovered
- control type for each relevant field
- conditional behavior and how it is triggered
- screenshots, snapshots, traces, or eval output paths when available
- implementation recommendations for page objects and test data

## Notes

- Prefer host-owned login helpers, fixtures, and existing specs over rebuilding authentication manually.
- Use browser snapshots for orientation and `page.evaluate`/DOM enumeration for large or dynamic pages.
- Record exact option labels for dropdowns and multiselects; tests should use visible labels only when the application contract supports that.
- Treat snapshot element refs as temporary. Re-snapshot after navigation or dynamic UI changes.
- On Windows, do not invent unsupported CLI flags. Use the locally installed `playwright-cli` or `npx playwright-cli` with the flags supported by that version.
- Store generated discovery artifacts in host scratch locations such as `.playwright-cli/`; do not promote them into OpenCaw unless they are reusable templates or references.
- Reference docs bundled with OpenCaw live under `assets/playwright-cli/references/`.
- When the user needs a non-interactive handoff, run `commands/playwright-discovery-report.sh` to summarize snapshots, screenshots, traces, and videos into `.ai/reports/`.
