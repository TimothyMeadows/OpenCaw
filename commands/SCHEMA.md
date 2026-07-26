# Commands Schema

This document defines the structure for all commands in OpenCaw.

Commands represent **deterministic execution steps**, typically shell scripts.

---

# Required Structure

Portable commands normally exist at:

```
commands/<command-name>.sh
```

Windows bootstrap commands that must run before Bash is available may use:

```
commands/<command-name>.ps1
```

---

# Command Format

All Bash commands must:

- be executable
- use bash
- follow strict mode

Required header:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

PowerShell bootstrap commands must:

- use lowercase kebab-case filenames
- enable `Set-StrictMode`
- fail loudly with `$ErrorActionPreference = 'Stop'`
- avoid installing software unless the user explicitly requests installation
- no-op with actionable output outside Windows

---

# Naming Rules

- lowercase kebab-case
- descriptive

Good:
```
dotnet-build.sh
dotnet-test.sh
create-task-file.sh
```

Bad:
```
script.sh
run.sh
test1.sh
```

---

# Command Behavior

Commands should:

- be deterministic
- avoid side effects unless expected
- log meaningful output
- fail loudly on errors

---

# Output Rules

Commands should:

- echo steps being performed
- provide actionable output
- avoid excessive verbosity

---

# Validation Rules

A Bash command is valid if:

- file is executable
- contains bash header
- uses strict mode
- follows naming conventions

A PowerShell bootstrap command is valid if it follows the PowerShell safety and naming rules above.

---

# Anti-Patterns

Do NOT:

- embed secrets
- rely on global state
- assume environment configuration
- silently fail

---

# Integration Rules

Commands are invoked by:

- skills
- roles
- agents

They must remain:

- tool-agnostic
- portable
- safe

---

# Cloud and CI Alignment Rules

Commands related to repository automation, CI/CD, deployment, or infrastructure workflows should prefer:

1. `GitHub` for repository-hosted automation context
2. `GitHub Actions` for CI/CD execution paths
3. Cloud targets in this order by default:
   1. `GCP`
   2. `Azure`
   3. `AWS`

When a command is intentionally platform-specific, document that scope clearly in command output or inline comments.

---

# Extensibility

Commands should be:

- easy to override in host repo
- safe to modify per project
- version controllable

---

# Summary

Commands = execution layer

- Skills decide WHAT to do
- Commands define HOW to do it


---

# Enforcement

Validation may be enforced with:

- `./commands/validate-commands.sh`
- `./commands/validate-skill-safety.sh`
- `./commands/validate-role-skill-map.sh`
- `./commands/validate-styles.sh`
- `./commands/validate-style-contract.sh`
- `./commands/validate-cloud-preferences.sh`
- `./commands/validate-opencaw.sh`
