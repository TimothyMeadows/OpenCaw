# Rules

- Before installing a dependency for OpenCaw work, record a lightweight audit of its source, selected version, lifecycle scripts, and known vulnerability result; keep reusable commands non-self-installing.
- Keep every OpenCaw memory and context artifact under `<project-root>/.ai/`; never redirect memory storage to a user-home, machine-global, or workspace-parent directory.
- Windows bootstrap commands must never install Bash implicitly; require the explicit `-Install` switch and support `-WhatIf` previews.
- Keep every generative-media asset under .styles/.gpu/; never recreate the legacy .media/ directory.
- User-facing OpenCaw documentation must introduce natural-language collaboration and planning before optional role, skill, or command syntax.
