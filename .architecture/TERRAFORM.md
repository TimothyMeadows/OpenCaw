# TERRAFORM.md

This repository follows a **Terraform infrastructure architecture** optimized for repeatable, reviewable, and enterprise-ready infrastructure provisioning.

The architecture is optimized for:

- Terraform
- modular infrastructure design
- environment-specific composition
- remote state
- least-privilege deployment workflows
- predictable plan/apply behavior

The goal is to keep the system:

- safe to change
- easy to review
- modular and reusable
- explicit about environment boundaries
- maintainable at enterprise scale

---

# Core Architecture Rule

**Separate reusable modules from environment composition and deployment orchestration.**

Prefer:

```text
root composition -> reusable modules -> provider resources
```

Avoid:

```text
one giant root file -> every environment -> every resource
```

---

# Project Structure

Suggested layout:

```text
terraform/
  modules/
    networking/
    storage/
    app_service/
    service_bus/
  environments/
    dev/
    test/
    prod/
```

Alternative layout:

```text
infra/
  modules/
  stacks/
    shared/
    dev/
    prod/
```

---

# Module Rules

Modules should own:

- reusable resource composition
- clear input/output contracts
- minimal assumptions about calling environments
- narrowly scoped infrastructure responsibilities

Rules:

- keep modules focused
- define explicit variables and outputs
- avoid hidden environment assumptions
- avoid stuffing unrelated resources into one module
- prefer composition over giant multipurpose modules

---

# Environment Composition Rules

Environment roots should own:

- provider configuration
- backend configuration
- environment-specific variable wiring
- module composition
- environment-specific resource decisions

Rules:

- keep environment-specific logic at the environment boundary
- avoid hardcoding prod assumptions into reusable modules
- make naming, tagging, and subscription/account choices explicit

---

# State Rules

State must be handled intentionally.

Prefer:

- remote backends
- state locking where supported
- explicit separation of state by environment and ownership boundary

Rules:

- never rely on ad hoc local state for shared enterprise environments
- do not share one state file across unrelated bounded areas without clear ownership
- keep state boundaries aligned with deployment ownership and blast radius

---

# Provider and Version Rules

Rules:

- pin Terraform and provider versions intentionally
- avoid uncontrolled provider drift
- document upgrade considerations
- keep provider configuration explicit at composition boundaries

---

# Variable Rules

Variables should be:

- explicitly typed
- documented
- bounded to meaningful ownership
- validated where useful

Avoid:

- giant generic variable bags
- hidden defaults with operational risk
- unclear environment-specific assumptions

---

# Output Rules

Outputs should expose:

- meaningful integration points
- values needed by other stacks or deployment workflows
- only what is necessary

Avoid:

- exposing large internal details without need
- using outputs as a substitute for clear ownership boundaries

---

# Resource Design Rules

Resources should be:

- tagged consistently
- named predictably
- grouped by responsibility
- protected by explicit lifecycle choices when required

Rules:

- keep naming conventions explicit
- keep tags and metadata standardized
- define destructive behavior intentionally
- document drift-sensitive resources

---

# Security Rules

Prefer:

- least privilege
- managed identity / role-based access patterns where supported
- explicit secret handling boundaries
- separation of privileged and standard deployment paths

Avoid:

- embedding secrets in code or variables files carelessly
- broad wildcard permissions without clear need
- undocumented privilege assumptions

---

# Deployment Workflow Rules

Deployment workflows should emphasize:

- `fmt`
- `validate`
- `plan`
- reviewed `apply`

Rules:

- do not skip plan review for shared or production environments
- keep plan artifacts reviewable where your platform supports it
- separate validation and apply concerns in automation
- document rollback or mitigation expectations, even when rollback is not a simple inverse apply

---

# Testing and Validation Strategy

Recommended checks:

- `terraform fmt`
- `terraform validate`
- linting or policy checks where available
- reviewed `terraform plan`
- controlled `terraform apply`

Optional advanced checks:
- policy-as-code
- module tests
- drift detection workflows

---

# Naming Conventions

Good:

```text
module.networking
module.app_service
var.environment
output.service_bus_namespace_id
```

Avoid:

```text
module.common
module.helper
var.misc
output.stuff
```

---

# Anti-Patterns

Never introduce:

- one giant root module for all environments
- local state for shared enterprise deployment paths
- implicit environment behavior hidden inside modules
- unreviewed apply workflows for sensitive environments
- broad secret sprawl in code or plaintext vars

---

# Code Generation Rules for Agents

When generating Terraform:

1. Start with the ownership boundary.
2. Decide whether the change belongs in a reusable module or environment composition.
3. Define explicit variables and outputs.
4. Keep provider/backend/environment concerns at the composition boundary.
5. Preserve reviewability and safe deployment flow.

When in doubt:

**Move reusable logic into focused modules and keep environment-specific decisions at the environment root.**
