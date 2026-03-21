---
name: define-logo-size-depth-standards
description: Define logo and vector-art standards for size tiers, spacing, and depth so artwork remains consistent across UI surfaces.
---

## When to use
Use when creating or revising logo systems, brand marks, and vector art standards that need explicit minimum sizes, clear-space rules, and depth/elevation consistency.

## Output
- size tier specification (minimum, preferred, and large-format tiers)
- clear-space and lockup rules
- depth/elevation scale with token names and usage constraints
- prohibited transformations and distortion rules

## Notes
- Prefer tiered standards that map cleanly to interface sizes (`16`, `20`, `24`, `32`, `48`, `64`, `128`).
- Keep depth subtle and intentional; every shadow/highlight treatment should map to a named level.
- Align the work with the active `AGENTS.md`, `ARCHITECTURE.md`, and any active roles.
- Prefer existing commands in `./commands/` when a deterministic workflow exists.
