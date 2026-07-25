---
name: build-game-production-tools
description: Build reversible game-content tools that derive from authoritative source, isolate drafts, validate imports and exports, and require reviewed integration. Use for map editors, encounter editors, changelog tooling, review modes, content inspectors, and local production utilities.
---

# Build Game Production Tools

## When to use

- Creating a private or local editor for authored game data.
- Adding a versioned changelog or deterministic review state.
- Designing import, export, undo, redo, or source-integration workflows.

## Workflow

1. State the authority lifecycle: production source, derived document, isolated draft, validated export, reviewed integration.
2. Define versioned schemas, stable identifiers, bounds, size limits, and ownership for every editable field.
3. Reuse production render and content adapters without running progression, saves, or live simulation.
4. Implement bounded undo and redo, atomic gestures, local restore, reset confirmation, and explicit draft status.
5. Treat exports as proposals and validate them against the current source manifest before integration.
6. If remote access is required, fail closed with repository-approved authentication, authorization, session, and audit controls.

## Output

- A tooling authority and schema contract.
- Interaction, draft, import, export, access, and integration requirements.
- Tests for validation, reversibility, security, cleanup, and production isolation.

## Guardrails

- Do not make a private URL the only access control.
- Do not let tools mutate gameplay saves, accounts, or live production data by default.
- Do not copy a draft wholesale into authoritative source.
