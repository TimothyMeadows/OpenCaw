---
name: adapt-external-agent-skills
description: Redesign an external agent capability as a concise OpenCaw-native role, skill, command, or rejection decision. Use after a security review when useful behavior must be integrated without copying source text, code, assets, identities, vendor assumptions, or unsafe side effects.
---

# Adapt External Agent Skills

## When to use

- Turning an audited capability into OpenCaw behavior.
- Consolidating overlapping public skills into a smaller native workflow.
- Deciding whether to enhance an existing role or skill instead of adding one.

## Workflow

1. Read `AGENTS.md`, the role and skill schemas, catalog indexes, and current mappings.
2. Define the reusable user outcome without retaining source wording or structure.
3. Choose exactly one primary disposition: enhance, create, consolidate, or reject.
4. Write a native contract covering triggers, inputs, outputs, failure modes, safety, and verification.
5. Place deterministic execution under `commands/`; keep reasoning in `SKILL.md`.
6. Bind the capability to the narrowest relevant roles and validate the entire catalog.

## Output

- A disposition with rationale and affected OpenCaw surfaces.
- A decision-complete native specification.
- Validation evidence showing no placeholders, broken mappings, or unsafe behavior.

## Guardrails

- Do not copy examples, code, prose, assets, metadata, or distinctive organization.
- Do not preserve account names, personal paths, project names, or automatic publication behavior.
- Prefer strengthening an existing capability when a new trigger would overlap.
