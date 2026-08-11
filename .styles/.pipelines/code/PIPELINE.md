# CODE Art Pipeline

## Intent

Author procedural Three.js models as reviewable TypeScript or JavaScript instead of loading downloaded, generated, or library-provided model files.

## Inputs

- A text brief and optional authorized reference images.
- The active `STYLE.md`, intended runtime use, target Three.js version, coordinate system, interaction needs, and performance budgets.
- The host repository's established model interface, or the OpenCaw default model-instance contract when none exists.

## Production Rules

- Build geometry, materials, semantic parts, pivots, anchors, and optional animation behavior in source code.
- Keep procedural variation deterministic through explicit seeds.
- Work through `blockout`, `structure`, `form`, `materials`, `interaction`, and `optimization` passes in order.
- Preserve model state outside the Three.js scene graph and expose cleanup for every owned GPU resource.
- Treat references as review evidence rather than runtime dependencies.
- Do not use GLB, glTF, FBX, OBJ, downloaded model packs, or generated meshes as the primary implementation.
- Stop when the selected pipeline fails or the correction budget is exhausted. Never switch pipelines silently.

## Output Contract

- Produce a typed factory returning the host model interface or an instance containing `root`, semantic `parts`, `anchors`, optional `update`, and `dispose`.
- Bind implementation and review evidence to a validated code-model manifest.
- Store review renders and task state outside runtime asset directories.

## Acceptance Checks

- Typecheck and build against the host's installed Three.js version.
- Render front and at least two meaningful orbit views for non-planar models.
- Verify deterministic output, semantic part coverage, attachment integrity, budgets, runtime integration, and disposal.

## Role Fit

Use with `technical-3d-artist`, `frontend-developer`, `web-experience-designer`, `senior-developer`, and Three.js-capable game roles.
