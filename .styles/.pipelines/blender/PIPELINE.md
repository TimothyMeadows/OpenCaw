# BLENDER Art Pipeline

## Intent

Author inspectable Blender 4.5 LTS scenes, assets, renders, and runtime exports through the repository's staged Blender production workflow.

## Inputs

- The active `STYLE.md`, production brief, target camera or viewing conditions, Blender production profile, renderer or export target, and explicit geometry, texture, render, and runtime budgets.
- Declared immutable source, working, backup, cache, staging, and runtime destinations confined to the repository.
- An existing compatible Blender installation and connected authoring capability; Blender, addons, packages, and providers are never installed automatically.
- Authorized reference or generated-media inputs with their provenance when those inputs are part of the brief.

## Production Rules

- Support Blender 4.5 LTS only and route work through `direct-blender-production` plus the applicable modeling, material, procedural, rigging, simulation, lighting, rendering, optimization, and review skills.
- Preserve every immutable source `.blend`; author only in the declared working copy and create checkpoints before destructive or high-risk operations.
- When `STYLE.md` configures external asset libraries, inspect them before new modeling or downloads and open only a copied project asset below `assets/models/`, never the library source.
- Prefer typed connected Blender operations. Use exact-content validated `bpy` only when typed operations are insufficient, and use the CLI only for read-only inspection and validation.
- Keep authored Blender work distinct from the `CODE` pipeline: `.blend` scenes and exported assets are expected deliverables here, while Three.js source remains owned by `CODE`.
- Keep generation, staging, human review, and promotion separate. Read `MEDIA.md` only when `CLOUD` or `LOCAL` generated inputs are also in scope.
- Stop when the selected Blender capability is unavailable or fails. Never switch pipelines or authoring backends silently.

## Output Contract

- Produce repository-confined working `.blend` files, backups, inspection reports, staged review renders, and requested runtime exports.
- Record the Blender version, production profile, source and dependency hashes, budgets, checkpoints, validation results, and human review state.
- Promote only reviewed outputs to runtime destinations; scene reports and staged renders are evidence, not automatic approval.

## Acceptance Checks

- Verify Blender 4.5 LTS, immutable-source preservation, repository path confinement, dependency resolution, and the applicable scene-report profile.
- Validate topology, naming, transforms, materials, cameras, rigs, actions, procedural realization, simulation caches, render settings, and export budgets as applicable.
- Review representative camera or orbit views and test exported assets in their intended renderer or runtime before promotion.

## Role Fit

Use with `blender-production-artist`, `technical-3d-artist`, `art-director`, `pre-rendered-2-5d-artist`, `game-vfx-artist`, and Blender-capable game-art roles.
