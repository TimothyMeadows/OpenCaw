---
name: framework-migration-plan
description: Build a staged migration plan from legacy frameworks/runtimes to modern supported versions with explicit risk controls.
---

## When to use
Use when upgrading a codebase from an older runtime or framework version (for example, .NET Core to .NET 8) and you need a safe, testable migration path.

## Output
- current-state baseline (runtime, framework, package constraints)
- target-state definition and compatibility assumptions
- phased migration plan with checkpoints
- breaking-change and dependency risk matrix
- rollback and verification strategy per phase

## Notes
- Prefer incremental migration over one-shot rewrites.
- Require validation evidence after each phase before continuing.
