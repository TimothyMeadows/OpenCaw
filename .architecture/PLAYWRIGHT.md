# PLAYWRIGHT.md

This repository uses a **Playwright browser automation architecture** for end-to-end testing, UI regression protection, browser-driven discovery, or production-like workflow validation.

The architecture is optimized for:

- deterministic user-flow tests
- stable selectors and page objects
- environment-driven configuration
- trace, screenshot, video, and report artifacts
- CI-friendly browser project definitions
- clear separation between test data, fixtures, page objects, and specs

## Core Architecture Rule

**Keep browser workflow intent in specs and browser interaction details in page objects or focused helpers.**

Prefer:

```text
test data -> fixtures -> page objects -> specs -> reports
```

Avoid:

```text
spec files with raw selectors, hidden data setup, and unowned waits
```

## Recommended Structure

```text
tests/
fixtures/
pageobjects/
artifacts/
playwright.config.ts
```

## Selector Rules

- Prefer accessible roles, labels, stable `data-testid` attributes, and durable app-owned IDs.
- Avoid brittle CSS/XPath selectors unless the app exposes no stable alternative.
- Keep selectors near page objects or local helper APIs instead of scattering them across specs.
- When discovering a live UI, record exact selectors, control types, conditional behavior, and field ownership before implementing tests.

## Data Rules

- Keep scenario data outside test logic in JSON, builders, fixtures, or explicit setup APIs.
- Do not hardcode credentials in tests or shared OpenCaw assets.
- Use environment variables or host-owned secret stores for credentials and environment selection.
- Preserve generated test artifacts outside source-controlled durable assets unless they are deliberate documentation evidence.

## Fixture Rules

- Use Playwright fixtures as the construction and dependency-injection boundary.
- Keep fixture setup deterministic and scoped.
- Avoid hidden global mutation that changes later tests.

## Stability Rules

- Prefer explicit waits on durable UI, URL, network, or app state.
- Treat flaky tests as product or test defects.
- Capture traces, screenshots, videos, and logs for diagnosis.
- Isolate test data so parallel runs cannot collide unless the suite intentionally runs serially.

## CI Rules

- Define at least one local/debug project and one CI/headless project when browser behavior differs.
- Publish machine-readable test results and Playwright reports.
- Make environment, browser project, grep/tag filters, and credentials explicit in CI.

## OpenCaw Report Rules

- Assume interactive Playwright UI mode and report servers may not be available.
- Prefer Markdown evidence reports generated under the host `.ai/reports/` directory.
- Use JSON, JUnit, screenshots, traces, videos, and discovery snapshots as source artifacts.
- Use `playwright-report-summary.sh`, `playwright-artifact-index.sh`, `playwright-discovery-report.sh`, and `playwright-evidence-report.sh` as non-interactive substitutes for browsing the Playwright UI.

## OpenCaw Usage

Use the generic Playwright skills for cross-repo browser testing. Keep product-specific workflows in host repositories or explicitly scoped extension packs, not in the generic OpenCaw Playwright layer.
