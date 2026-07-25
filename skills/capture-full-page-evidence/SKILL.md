---
name: capture-full-page-evidence
description: Capture reliable full-page browser evidence for lazy-loaded, animated, canvas, WebGL, and reveal-heavy pages. Use when ordinary screenshots are blank, incomplete, inconsistent with live behavior, or insufficient for QA and reference analysis.
---

# Capture Full Page Evidence

## When to use

- A full-page screenshot misses content or shows unloaded states.
- QA needs section crops tied to a trustworthy complete capture.
- Animated or virtualized content requires deliberate scrolling before capture.

## Workflow

1. Confirm the URL, authority, viewport, output path, and whether authentication is involved.
2. Use the repository-approved browser or `commands/playwright-capture-page.sh`; never install tooling implicitly.
3. Load the page, wait for the documented ready condition, and scroll deliberately to trigger deferred content.
4. Stabilize animations only when doing so does not change the evidence question.
5. Capture the full page and requested focused states with metadata.
6. Verify dimensions, non-blank content, section continuity, console state, and correspondence with the live page.

## Output

- Capture paths with URL, time, viewport, state, and method.
- Validation notes for completeness and known limitations.
- Section coordinates or crops when required by the handoff.

## Guardrails

- Do not bypass access controls or capture private data without authority.
- Do not submit forms or mutate server state during a capture-only workflow.
- Treat a stitched image as evidence only after continuity checks pass.
