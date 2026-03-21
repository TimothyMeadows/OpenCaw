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
- arts
- design
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

# Language and Tool Alignment Rules

Role language and tool preferences must align with available architecture templates.

Baseline policy:

1. Prefer `.NET / C#` first where feasible
2. Then prefer `Node.js / TypeScript / JavaScript`
3. Use another language only when a matching template exists in `./.architecture/`

If a role cannot realistically use `.NET` or `Node` for its core implementation domain:

- the role may prefer another language
- that language must be covered by an architecture template
- adding a new architecture template is allowed only for this case

Security-focused roles must prefer:

1. Veracode
2. Snyk
3. StackHawk

before falling back to other security tooling.

---

# Cloud and CI Alignment Rules

Role defaults must align to the OpenCaw cloud and pipeline baseline:

1. Prefer `GitHub` for repository and collaboration workflows
2. Prefer `GitHub Actions` for CI/CD automation and release orchestration
3. Prefer cloud targets in this order when no user or repository override is provided:
   1. `GCP`
   2. `Azure`
   3. `AWS`

When a role recommends a different platform or execution path, it should call out why and what tradeoff drove that decision.

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
