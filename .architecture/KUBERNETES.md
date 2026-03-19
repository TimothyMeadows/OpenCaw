# KUBERNETES.md

This repository follows a **Kubernetes deployment architecture** optimized for declarative deployments, environment separation, and operational clarity.

The architecture is optimized for:

- Kubernetes
- namespace and workload ownership boundaries
- declarative manifests or templated deployment composition
- environment-specific overlays
- secure runtime configuration
- observable production operations

The goal is to keep the system:

- declarative
- reviewable
- environment-aware
- secure by default
- maintainable at enterprise scale

---

# Core Architecture Rule

**Separate reusable workload definitions from environment-specific deployment overlays and operations policy.**

Prefer:

```text
base workload definitions -> environment overlays -> cluster deployment
```

Avoid:

```text
one giant manifest set -> every environment -> every cluster
```

---

# Structure

Suggested layout:

```text
k8s/
  base/
  overlays/
    dev/
    test/
    prod/
```

Alternative layout:

```text
deploy/
  kubernetes/
    base/
    env/
```

---

# Workload Rules

Workloads should define:

- deployment or stateful workload shape
- service exposure
- config and secret references
- probes
- resource requests/limits
- operational metadata

Rules:

- keep manifests focused by workload or bounded capability
- avoid mixing unrelated concerns into giant files
- make ownership explicit
- define health probes intentionally

---

# Environment Rules

Environment overlays should own:

- replica counts
- hostnames
- environment-specific config references
- scaling or policy differences
- cluster-specific routing or ingress decisions

Rules:

- keep environment-specific assumptions out of reusable base definitions
- make differences intentional and reviewable
- do not rely on hidden manual cluster drift

---

# Configuration and Secret Rules

Prefer:

- explicit config boundaries
- managed secret flows
- environment-specific secret references
- minimal direct secret exposure

Avoid:

- hardcoded secrets in manifests
- unclear ownership of config sources
- leaking environment assumptions across overlays

---

# Networking Rules

Networking definitions should be explicit about:

- ingress ownership
- internal vs external exposure
- service-to-service assumptions
- namespace or policy boundaries

Avoid:
- implicit exposure
- undocumented internal dependencies
- broad open ingress without clear justification

---

# Resource and Reliability Rules

All production-sensitive workloads should define:

- resource requests/limits
- readiness probes
- liveness probes where appropriate
- rollout strategy intentionally
- disruption considerations when relevant

---

# Security Rules

Prefer:

- least privilege service accounts
- explicit RBAC
- restricted pod/runtime permissions
- clear image provenance and pull strategy

Avoid:

- default-everything security posture
- unnecessary privileged workloads
- unclear namespace ownership

---

# Deployment Workflow Rules

Deployment workflows should emphasize:

- manifest validation
- dry-run or preview where possible
- controlled rollout
- rollback awareness
- environment-specific promotion discipline

---

# Observability Rules

Workloads should make room for:

- logs
- metrics
- traces where supported
- correlation identifiers
- meaningful labels/annotations

---

# Anti-Patterns

Never introduce:

- giant shared manifest sets with no ownership boundaries
- manual prod-only cluster drift as normal process
- hidden environment differences outside versioned config
- insecure default service account usage for sensitive workloads

---

# Code Generation Rules for Agents

When generating Kubernetes deployment code:

1. Start with the workload ownership boundary.
2. Define reusable base manifests or workload templates.
3. Keep environment-specific values in overlays.
4. Make probes, resources, and security posture explicit.
5. Preserve reviewability and operational clarity.

When in doubt:

**Keep deployments declarative, environment-aware, and explicit about ownership and runtime behavior.**
