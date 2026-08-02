# Rules

- Before installing a dependency for OpenCaw work, record a lightweight audit of its source, selected version, lifecycle scripts, and known vulnerability result; keep reusable commands non-self-installing.
- Keep every OpenCaw memory and context artifact under `<project-root>/.ai/`; never redirect memory storage to a user-home, machine-global, or workspace-parent directory.
- Windows bootstrap commands must never install Bash implicitly; require the explicit `-Install` switch and support `-WhatIf` previews.
- Keep every generative-media asset under .styles/.gpu/; never recreate the legacy .media/ directory.
- User-facing OpenCaw documentation must introduce natural-language collaboration and planning before optional role, skill, or command syntax.
- Do not delete or clear host-global caches, temporary data, or other files outside the resolved repository to make space for OpenCaw work without the user’s explicit approval; stop and report the storage blocker instead.
- Stop autonomous Gauntlet execution after 45 minutes or two failed full-validation epochs, persist resumable evidence, and require explicit user reauthorization before starting another execution window.
