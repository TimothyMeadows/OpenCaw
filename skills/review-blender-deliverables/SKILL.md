---
name: review-blender-deliverables
description: Review Blender 4.5 scenes, reports, required views, and staged outputs for production readiness. Use for severity-ranked defect review, reference-safe comparison, profile completeness, dependency audits, visual evidence, and explicit ship or block verdicts.
---

# Review Blender Deliverables

## When to use

Use when a Blender scene or staged output needs a machine report, required-view audit, severity-ranked defects, or a ship/block verdict.

## Workflow

1. Identify the exact source hash, profile, brief, style, budget, and target artifact under review.
2. Run `inspect-blender-scene.sh`, then `validate-blender-scene-report.sh`; use `--require-clean` for delivery candidates.
3. Review required orthographic, perspective, deformation, material, lighting, render, and runtime views appropriate to the profile.
4. Compare against functional and style constraints without reproducing distinctive third-party expression.
5. Rank defects as error, warning, or information; assign a subject, evidence, owner, and retest condition.
6. Issue one explicit verdict: ship, ship with recorded warnings, or block.

Read [scene-report-contract.md](references/scene-report-contract.md) for report semantics and [visual-review-contract.md](references/visual-review-contract.md) for review views and verdicts.

## Guardrails

- Do not infer clean topology, dependencies, or caches from beauty renders.
- Do not use an unbound screenshot as proof of the inspected source.
- Do not approve a blocked or unreviewed deliverable for runtime promotion.
