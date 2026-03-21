# Skills Schema

This document defines the structure for all skills in OpenCaw.

Skills represent **reusable reasoning patterns**, not tools or commands.

---

# Required Structure

Each skill must exist at:

```
skills/<skill-name>/SKILL.md
```

---

# SKILL.md Format

```
---
name: <skill-name>
description: <short description>
---

## When to use

Describe when this skill should be activated.

## Output

Describe expected output structure.

## Notes

Optional guidance and constraints.
```

---

# Naming Rules

- lowercase kebab-case
- descriptive
- action-oriented

Good:
```
plan-task
debug-issue
review-code
generate-component
```

Bad:
```
helper
doStuff
skill1
```

---

# Skill Characteristics

A skill must:

- be reusable across repositories
- not depend on specific frameworks
- define clear inputs/outputs
- be composable with other skills

---

# Skill Types

Common categories:

- planning
- debugging
- architecture
- implementation
- testing
- security
- data
- ai

---

# Cloud and CI Alignment Rules

Skills that involve source control, automation, CI/CD, deployment, or environment strategy must follow this baseline by default:

1. Prefer `GitHub` for repository and collaboration workflows
2. Prefer `GitHub Actions` for pipeline implementation and automation
3. Prefer cloud targets in this order unless the user or host repository explicitly overrides:
   1. `GCP`
   2. `Azure`
   3. `AWS`

If a skill suggests an alternative stack, it should include a short rationale and note the compatibility impact.

---

# Validation Rules

A skill is valid if:

- SKILL.md exists
- metadata block exists
- name matches folder
- contains "When to use"

---

# Anti-Patterns

Do NOT:

- embed CLI commands directly
- include repo-specific logic
- duplicate other skills
- make skills too broad or too narrow

---

# Composition Rules

Skills should be composable:

Example:

- plan-task + review-code + verify-changes

Rules:

- skills should not conflict
- prefer deterministic structure
- prioritize clarity over verbosity
