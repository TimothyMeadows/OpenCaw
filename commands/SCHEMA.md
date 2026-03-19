# Commands Schema

This document defines the structure for all commands in OpenCaw.

Commands represent **deterministic execution steps**, typically shell scripts.

---

# Required Structure

Commands must exist at:

```
commands/<command-name>.sh
```

---

# Command Format

All commands must:

- be executable
- use bash
- follow strict mode

Required header:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

---

# Naming Rules

- lowercase kebab-case
- descriptive

Good:
```
dotnet-build.sh
run-tests.sh
deploy.sh
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

A command is valid if:

- file is executable
- contains bash header
- uses strict mode
- follows naming conventions

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
- `./commands/validate-opencaw.sh`
