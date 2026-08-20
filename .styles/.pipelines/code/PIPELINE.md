# CODE Art Pipeline

## Intent

Author procedural Three.js models as reviewable TypeScript or JavaScript instead of loading downloaded, generated, or library-provided model files.

## Inputs

- A text brief and optional authorized reference images.
- The active `STYLE.md`, intended runtime use, target Three.js version, coordinate system, interaction needs, and performance budgets.
- The host repository's established model interface, or the OpenCaw default model-instance contract when none exists.
- For characters and creatures, a linked `opencaw-code-character/v1` profile that freezes identity, presentation sizes, body plan, motion mode, contextual thresholds, reviewer policy, and machine-gate calibration.

## Production Rules

- Build geometry, materials, semantic parts, pivots, anchors, and optional animation behavior in source code.
- Keep procedural variation deterministic through explicit seeds.
- Work through `blockout`, `structure`, `form`, `materials`, `interaction`, and `optimization` passes in order.
- Route embodied characters, creatures, and runtime actors through `build-threejs-code-characters`; keep props and environments in the generic `build-threejs-code-models` workflow.
- Pass each linked character gate before its generic CODE pass. Keep blockout, form, and material/style acceptance with an independent reviewer; machine evidence owns only structure, interaction/runtime, and optimization/budget facts.
- Preserve model state outside the Three.js scene graph and expose cleanup for every owned GPU resource.
- Treat references as review evidence rather than runtime dependencies.
- When `STYLE.md` configures external asset libraries, inspect them before authoring and copy an authorized candidate into `assets/models/` only as template/reference evidence.
- Do not use GLB, glTF, FBX, OBJ, downloaded model packs, or generated meshes as the primary implementation.
- Stop when the selected pipeline fails or the correction budget is exhausted. Never switch pipelines silently.

## Output Contract

- Produce a typed factory returning the host model interface or an instance containing `root`, semantic `parts`, `anchors`, optional `update`, and `dispose`.
- Bind implementation and review evidence to a validated code-model manifest.
- For characters and creatures, bind deterministic observations to the linked character profile and preserve the machine-versus-reviewer boundary in the evidence report.
- Store character contracts and reports against `code-character-profile.schema.json`, `code-character-observation.schema.json`, and `code-character-evidence-report.schema.json`.
- Store review renders and task state outside runtime asset directories.

## Acceptance Checks

- Typecheck and build against the host's installed Three.js version.
- Render front and at least two meaningful orbit views for non-planar models.
- Verify deterministic output, semantic part coverage, attachment integrity, budgets, runtime integration, and disposal.
- For characters, capture required views and presentation sizes plus semantic masks, isolated signature parts, and a runtime view. Check only applicable static, articulated, or skinned behavior.
- Require passing and focused failing calibration for every machine gate. Fixture reports remain untrusted; trusted machine evidence requires the loopback-only sandboxed browser harness with host-installed Three.js, Playwright, and Chromium.
- Require exactly one current trusted browser report as `machine-report` evidence before recording a passing machine gate.
- Stop without installation or fallback when the selected host browser tooling is unavailable.

## Role Fit

Use generic model production with `technical-3d-artist`, `frontend-developer`, `web-experience-designer`, `senior-developer`, and Three.js-capable game roles. Character building belongs to technical-3D, frontend, and gameplay roles; concrete-cycle visual review belongs to a distinct technical-3D, QA, or game-design identity.
