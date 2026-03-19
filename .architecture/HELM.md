# HELM.md

This repository follows a **Helm chart architecture** optimized for reusable deployment packaging, environment-specific values, and reviewable Kubernetes release workflows.

The architecture is optimized for:

- Helm
- chart reuse
- values-driven environment composition
- release-oriented deployment workflows
- predictable chart ownership
- maintainable operational packaging

The goal is to keep the system:

- reusable
- configurable without chaos
- environment-aware
- reviewable in pull requests
- maintainable at enterprise scale

---

# Core Architecture Rule

**Keep charts reusable and keep environment-specific behavior in values, not hidden template logic.**

Prefer:

```text
chart templates + explicit values -> release configuration
```

Avoid:

```text
templates full of complex hidden environment branching
```

---

# Chart Structure

Suggested layout:

```text
charts/
  my-service/
    Chart.yaml
    values.yaml
    templates/
```

Environment values example:

```text
deploy/
  values/
    dev.yaml
    test.yaml
    prod.yaml
```

---

# Template Rules

Templates should define:

- resource shape
- labels/annotations
- config references
- optional features with explicit values gates

Rules:

- keep templates readable
- avoid deep branching when simpler values structure will do
- prefer explicit value contracts
- keep naming and labels predictable

---

# Values Rules

Values should own:

- environment-specific settings
- image tags or release wiring
- replica counts
- ingress/host differences
- optional feature toggles

Rules:

- document values clearly
- avoid giant uncontrolled values bags
- make security-sensitive values explicit
- keep defaults safe and understandable

---

# Release Rules

Release workflows should emphasize:

- linting
- template rendering review
- environment-specific values review
- controlled upgrade and rollback awareness

Avoid:
- applying charts with unclear value provenance
- hidden environment-only manual overrides as standard process

---

# Security Rules

Prefer:
- explicit secret references
- least privilege defaults
- explicit service account behavior
- clear image and registry controls

Avoid:
- burying security posture in opaque values logic
- weak defaults for production-sensitive workloads

---

# Testing and Validation

Recommended checks:
- `helm lint`
- template rendering
- value-file review
- environment-specific dry runs where supported

---

# Anti-Patterns

Never introduce:

- giant templating logic that behaves like a programming language
- unclear ownership of values files
- environment behavior hidden across many scattered values files
- unsafe defaults for production-sensitive deployments

---

# Code Generation Rules for Agents

When generating Helm code:

1. Start with the chart ownership boundary.
2. Keep templates readable and values-driven.
3. Put environment-specific differences in values files.
4. Preserve predictable labels, names, and release behavior.
5. Keep security and rollout posture explicit.

When in doubt:

**Favor clear values contracts over clever template branching.**
