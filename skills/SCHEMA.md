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
