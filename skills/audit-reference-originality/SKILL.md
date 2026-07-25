---
name: audit-reference-originality
description: Compare a design or digital experience with supplied references and identify evidence-backed originality risk across copy, branding, assets, layout, motion, and implementation. Use when work was inspired by references and must preserve common design grammar without retaining distinctive expression.
---

# Audit Reference Originality

## When to use

- Reviewing a website, UI, campaign, or interactive prototype against references.
- Checking whether revisions are sufficiently differentiated.
- Preparing concrete remediation for potentially copied elements.

## Workflow

1. Create a registry of the references, allowed uses, capture dates, and evidence available.
2. Inventory the subject and compare copy, names, numbers, assets, composition, hierarchy, interactions, motion, and code separately.
3. Distinguish common functional patterns from distinctive combinations and signature elements.
4. Use `commands/build-originality-evidence.sh` when local subject and reference trees are available.
5. Triangulate each material finding with more than one evidence type when practical.
6. Propose the smallest changes that establish a distinct identity and recheck them.

## Output

- A category-by-category originality assessment.
- Specific evidence and a risk level for each finding.
- A remediation plan that changes protected or distinctive expression while preserving the functional goal.

## Guardrails

- Do not make legal conclusions or promise non-infringement.
- Do not treat similarity in a common component as proof of copying.
- Do not reproduce reference assets while documenting the audit.
