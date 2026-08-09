# Blender production session contract

## Brief

Record asset kind, target, one profile, Blender 4.5 LTS, active style, target architecture, delivery formats, budgets, required views, acceptance tests, and working/backup/staging/runtime paths. Resolve omissions before authoring.

## Backend selection

Use one compatible connected Blender tool for live scene changes and prefer its typed operations. A reviewed `bpy` script is an exception: save it inside the repository, validate it, record its SHA-256, create a repository-confined backup checkpoint, and execute that exact unchanged content. CLI Blender is inspection-only. Absence or failure of a backend blocks authoring and never authorizes a silent switch.

## Files and checkpoints

- Treat source `.blend` files as immutable inputs.
- Name working copies and checkpoints by stable asset identity and stage.
- Keep backups, cache, staging, and runtime paths declared and repository-confined.
- Bind reviews to a source hash, scene report, output hash, and required views.
- Human review is required before a staged render or export is promoted.

## Handoffs

Each stage reports inputs, output identity, decisions, unresolved warnings, measurements, dependencies, next owner, and acceptance evidence. A downstream stage may reject an incomplete handoff without repairing the upstream source silently.
