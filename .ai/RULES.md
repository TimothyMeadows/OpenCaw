# Rules

- Before installing a dependency for OpenCaw work, record a lightweight audit of its source, selected version, lifecycle scripts, and known vulnerability result; keep reusable commands non-self-installing.
- Keep every OpenCaw memory and context artifact under `<project-root>/.ai/`; never redirect memory storage to a user-home, machine-global, or workspace-parent directory.
- Windows bootstrap commands must never install Bash implicitly; require the explicit `-Install` switch and support `-WhatIf` previews.
- Keep art-pipeline contracts and their assets under `.styles/.pipelines/<owner>/`; never recreate legacy media-configuration directories or silently fall back between pipelines.
- User-facing OpenCaw documentation must introduce natural-language collaboration and planning before optional role, skill, or command syntax.
- Do not delete or clear host-global caches, temporary data, or other files outside the resolved repository to make space for OpenCaw work without the user’s explicit approval; stop and report the storage blocker instead.
- Stop autonomous Gauntlet execution after 45 minutes or two failed full-validation epochs, persist resumable evidence, and require explicit user reauthorization before starting another execution window.
- Do not use the monolithic Gauntlet regression as an incidental gate for unrelated work; run it only when Gauntlet behavior changes or the user explicitly requests full delivery-mode validation, and track performance or test-architecture repairs as separate work.
- When changing the art-pipeline registry, inventory every established production path, including Blender, and update selection, contracts, roles, skills, documentation, memory, and tests as one coherent change.
- Treat configured external asset libraries as read-only source locations: inspect them before creating or downloading replacement 3D assets, and copy selected files or bundles into repository-root `assets/models/` before any load, import, edit, or use.
