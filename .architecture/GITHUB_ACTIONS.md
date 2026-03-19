# GITHUB_ACTIONS.md

This repository follows a **GitHub Actions workflow architecture** optimized for reliable CI/CD, reviewable automation, and safe promotion through environments.

The architecture is optimized for:

- GitHub Actions
- reusable workflows
- step and job isolation
- artifact-driven promotion
- environment protection
- explicit secret and permission control
- cloud deployment support including GCP workflows

The goal is to keep the system:

- reviewable
- secure by default
- easy to troubleshoot
- reusable across repositories
- maintainable at enterprise scale

---

# Core Architecture Rule

**Separate reusable workflow logic from repository-specific pipeline composition and environment approvals.**

Prefer:

```text
reusable workflows -> repo workflow composition -> protected environments
```

Avoid:

```text
one giant workflow file -> every scenario -> every environment
```

---

# Workflow Structure

Suggested layout:

```text
.github/
  workflows/
```

Potential organization:
- CI validation workflow
- deployment workflow
- reusable shared workflow
- release workflow

---

# Job Rules

Jobs should be:

- focused
- explicitly permissioned
- explicit about dependencies
- artifact-aware when passing outputs across stages

Rules:

- keep job purposes narrow
- use `needs` intentionally
- avoid long unstructured mega-jobs
- separate validation, packaging, and deployment concerns where practical

---

# Reusable Workflow Rules

Reusable workflows should own:

- repeated validation patterns
- repeated deployment steps
- shared packaging or release behavior

Rules:

- keep inputs explicit
- keep secrets and permissions explicit
- avoid hidden behavior through weak defaults
- document expected callers and artifacts

---

# Permission and Secret Rules

Prefer:

- minimum required permissions
- explicit permissions blocks
- environment-protected secrets
- secret use isolated to the jobs that actually need them

Avoid:

- broad default write permissions without clear need
- secret sprawl across unrelated jobs
- unclear environment approval paths

---

# Artifact and Promotion Rules

Use artifacts intentionally for:
- build outputs
- test or scan results
- deployment packages

Rules:

- keep promotion paths explicit
- avoid rebuilding different artifacts in every stage when artifact promotion is intended
- document what is promoted and why

---

# Environment Rules

Protected environments should define:
- approval rules
- environment-specific secrets
- promotion expectations
- deployment boundaries
- cloud-specific deployment identity boundaries such as GCP project, workload identity, and service account scope

Avoid:
- mixing production deployment logic directly into unprotected validation flows
- hidden environment assumptions buried in shell commands

---

# Testing and Validation

Workflow quality should emphasize:
- linting or validation where practical
- deterministic step behavior
- artifact reviewability
- clear failure surfaces
- reproducible build/deploy paths

---

# Anti-Patterns

Never introduce:

- giant monolithic workflows with unclear stage boundaries
- implicit permissions or secret assumptions
- deployment logic mixed into every validation job
- environment promotions with unclear approval controls

---

# Code Generation Rules for Agents

When generating GitHub Actions workflows:

1. Separate validation, packaging, and deployment concerns.
2. Reuse workflows where patterns repeat.
3. Keep permissions, secrets, and cloud identity assumptions explicit.
4. Preserve artifact and promotion clarity.
5. Make environment boundaries reviewable.
6. When targeting GCP, make project, region, and workload identity boundaries explicit.

When in doubt:

**Prefer smaller, explicit workflows with clear permissions and promotion boundaries.**
