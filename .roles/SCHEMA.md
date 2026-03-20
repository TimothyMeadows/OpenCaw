# Roles Schema

This document defines the **standard structure, expectations, and validation rules** for all roles in OpenCaw.

All roles must follow this schema to ensure:

- consistency across repositories
- compatibility with AGENTS.md role casting
- predictable behavior when composing multiple roles

---

# Required Structure

Each role must exist at:

```
.roles/<domain>/<role-name>/ROLE.md
```

---

# ROLE.md Format

Each ROLE.md must follow this structure:

```
---
name: <role-name>
description: <short description>
aliases:
  - <alias1>
  - <alias2>
category: <category>
---

# Purpose

Describe what this role is responsible for.

# Responsibilities

- List of responsibilities
- What this role owns

# Behavior

- How the agent should think when this role is active
- Biases and priorities

# Constraints

- What this role should NOT do
- Guardrails

# Collaboration

- How this role interacts with other roles
```

---

# Naming Rules

- Must be lowercase kebab-case
- Must be unique
- Must be descriptive
- Domain folders must also be lowercase kebab-case

Good:
```
backend-architect
security-engineer
frontend-developer
```

Bad:
```
dev
helper
engineer1
```

---

# Categories

Recommended categories:

- architecture
- backend
- frontend
- security
- qa
- devops
- sre
- platform
- ai
- data
- fullstack

---

# Alias Rules

Aliases allow flexible role invocation.

Example:

```
aliases:
  - api-engineer
  - backend
```

Rules:

- Aliases must be lowercase
- No spaces (use hyphen)
- Alias conflicts across domains are allowed, but they must be resolvable through explicit domain-qualified disambiguation at activation time

Role-name conflicts across domains are also allowed and must be handled through explicit domain-qualified disambiguation when ambiguous.

---

# Validation Rules

A role is valid if:

- ROLE.md exists
- domain folder exists
- required sections are present
- metadata block exists
- name matches folder
- aliases are unique across all roles

---

# Anti-Patterns

Do NOT:

- duplicate roles with minor differences
- include tool-specific behavior
- include repository-specific logic
- create vague or generic roles

---

# Composition Rules

Roles must support composition:

Example:

```
use role backend-architect + security-engineer
```

Rules:

- roles must not conflict in constraints
- stricter rule wins if conflict exists
- first role = primary bias
