# AZURE_DEVOPS.md

This repository follows an **Azure DevOps pipeline architecture** optimized for repeatable validation, controlled releases, and enterprise-ready CI/CD governance.

The architecture is optimized for:

- Azure DevOps YAML pipelines
- reusable templates
- staged validation and deployment
- environment approvals
- artifact-driven release flow
- explicit variable and service connection ownership

The goal is to keep the system:

- governable
- reviewable
- reusable
- secure by default
- maintainable at enterprise scale

---

# Core Architecture Rule

**Separate reusable pipeline templates from repository-specific pipeline composition and environment release controls.**

Prefer:

```text
templates -> repo pipeline composition -> staged environment promotion
```

Avoid:

```text
one giant pipeline file -> every build, test, deploy, and environment concern
```

---

# Pipeline Structure

Suggested layout:

```text
.azuredevops/
  templates/
pipelines/
```

Alternative:
- root pipeline YAML for composition
- template files for shared steps, jobs, or stages

---

# Template Rules

Templates should own:

- repeated task patterns
- common build logic
- common deploy logic
- parameterized stage behavior

Rules:

- keep parameters explicit
- avoid hidden behavior through excessive defaults
- keep templates readable and bounded
- separate job/stage ownership clearly

---

# Variable Rules

Variables and variable groups should be:

- explicitly named
- scoped intentionally
- separated by environment or ownership boundary
- documented where operationally significant

Avoid:
- giant unowned variable bags
- hidden production-sensitive defaults
- unclear service connection assumptions

---

# Stage Rules

Stages should reflect:

- validation
- packaging
- promotion
- deployment
- post-deploy verification where relevant

Rules:

- keep stage boundaries meaningful
- isolate production-sensitive behavior
- make approvals and release flow explicit
- avoid mixing unrelated concerns in one stage

---

# Artifact Rules

Artifacts should represent:

- reviewed build outputs
- deployment packages
- versioned release payloads

Rules:

- keep artifact generation deterministic
- avoid rebuilding different outputs per stage when artifact promotion is intended
- document what each stage consumes

---

# Service Connection and Security Rules

Prefer:

- least privilege service connections
- explicit environment/resource ownership
- secure secret handling
- clear approval and deployment paths

Avoid:

- broad service connection usage without clear need
- undocumented deployment identity assumptions
- hidden privileged tasks in generic templates

---

# Validation and Release Rules

Pipeline quality should emphasize:
- deterministic build and test steps
- explicit quality gates
- clear environment promotion
- rollback or mitigation awareness
- visible deployment history

---

# Anti-Patterns

Never introduce:

- monolithic pipelines with no template boundaries
- hidden variable behavior across environments
- production deployment logic mixed into generic validation flows
- unclear artifact provenance

---

# Code Generation Rules for Agents

When generating Azure DevOps pipelines:

1. Separate templates from repo-specific composition.
2. Keep stages explicit and meaningful.
3. Preserve artifact and promotion clarity.
4. Keep variables and service connection assumptions explicit.
5. Make release controls and approvals clear.

When in doubt:

**Favor reusable templates plus explicit staged promotion over giant all-in-one pipelines.**
