# Skills Schema

This document defines the structure for all skills in OpenCaw.

Skills represent **reusable reasoning patterns**, not tools or commands.

---

# Required Structure

Each skill must include:

```
skills/<skill-name>/SKILL.md
skills/<skill-name>/agents/openai.yaml
```

`agents/openai.yaml` must define `display_name`, `short_description`, and a `default_prompt` that explicitly references `$<skill-name>`.

---

# SKILL.md Format

```
---
name: <skill-name>
description: <short description>
engines: [AGNOSTIC]
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
- declare engine compatibility explicitly; shared workflows use AGNOSTIC and feature workflows use exactly one registered engine
- define clear inputs/outputs
- be composable with other skills

Skills that keep project context must resolve paths through OpenCaw and write it only under `<project-root>/.opencaw/.cache/`. This is durable host state ignored by baseline Git, even though it is nested inside the fixed `.opencaw/` installation. Shared configuration and reusable assets stay outside `.cache/`; project `ENGINE.md`, `ARCHITECTURE.md`, `STYLE.md`, optional `MEDIA.md`, and optional Brainstorm contracts remain at the host root. Project-root command examples use `./.opencaw/commands/`; alternate install folders and install-location migration are unsupported.

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
- `agents/openai.yaml` exists and identifies the same skill in its default prompt
- all relative Markdown resource links resolve within the skill folder
- the skill folder contains no executable helpers, symbolic links, embedded credentials, or personal absolute paths
- the skill does not conceal account mutations or automatic external publishing

---

# Anti-Patterns

Do NOT:

- embed executable helpers inside the skill directory
- include repo-specific logic
- duplicate other skills
- make skills too broad or too narrow
- reference resources outside the skill directory
- embed credentials, personal paths, account operations, automatic publishing, or an unapproved vendor requirement

---

# Composition Rules

Skills should be composable:

Example:

- plan-task + review-code + verify-changes

Rules:

- skills should not conflict
- prefer deterministic structure
- prioritize clarity over verbosity

## Engine classification

Every skill has exactly one inline `engines: [AGNOSTIC]` or `engines: [ENGINE]` frontmatter declaration. V1 registered engines are THREEJS, BABYLONJS, PHASERJS, UNITY, UNREAL and GODOT. Empty, mixed, duplicate and unknown declarations are invalid. Engine skills use their canonical lowercase engine prefix (for example `unity-build-ui`); AGNOSTIC skills cannot use engine prefixes. Feature names may place the engine prefix before the action.

Run `commands/resolve-skill.sh SKILL` before activation or delegation. An incompatible result excludes the skill; requesting it never selects its engine. AGNOSTIC means shared engine policy, not universal platform/tool availability. Browser QA still requires a browser surface; native UI requires native evidence. Legacy Three.js names are aliases in the OpenCaw resolver, not duplicate skill folders or a promise of host-native alias support.
