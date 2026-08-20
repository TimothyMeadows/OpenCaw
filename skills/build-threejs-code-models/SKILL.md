---
name: build-threejs-code-models
description: Author procedural Three.js TypeScript or JavaScript models from a text brief and optional authorized references using deterministic ordered review passes. Use when the selected art pipeline is CODE and the runtime model should be source code rather than a downloaded or generated mesh.
---

# Build Three.js Code Models

## When to use

- The resolved art pipeline is `CODE`.
- A web, frontend, game, or technical-3D task needs a procedural Three.js model authored in source.
- Optional reference images are authorized for review evidence but must not become runtime dependencies.
- Route characters, creatures, animated actors, enemies, NPCs, avatars, mounts, and other embodied subjects to `build-threejs-code-characters`; keep props, environments, and generic procedural models in this skill.

## Workflow

1. Read `STYLE.md`, resolve `CODE` with `select-art-pipeline`, and read `.styles/.pipelines/code/PIPELINE.md`.
2. If `STYLE.md` configures external asset libraries, inspect them first with `use-external-asset-library`. Copy any authorized template into the repository, but keep it as reference evidence rather than a primary runtime mesh.
3. Inspect the host's existing Three.js version and documented model interface. Do not add or install Three.js. Use the interface recorded by the code-model manifest when the host has no interface.
4. Scaffold a manifest below `.ai/tasks/` with the text brief, semantic parts, pivots or anchors, deterministic seed, explicit budgets, cleanup ownership, and any authorized reference-image hashes.
5. Validate the manifest before authoring. Treat references as review inputs only.
6. Work in order: `blockout`, `structure`, `form`, `materials`, `interaction`, then `optimization`. Query the next unlocked pass before each change.
7. For each pass, author source, build or typecheck with the host toolchain, and capture deterministic browser evidence. Non-planar models require front, orbit-left, and orbit-right views.
8. Record exactly one review decision: `pass`, `revise-spec`, `revise-code`, `request-input`, or `stop`. Keep evidence hashed and project-confined.
9. Stop after three attempts on one pass or twelve attempts overall. After all passes, run complete validation and representative browser verification, including budgets and disposal.

## Output

- Host-native Three.js TypeScript or JavaScript source and its factory export.
- A validated code-model manifest with semantic parts, anchors, budgets, and cleanup ownership.
- Hashed review evidence for every ordered pass.
- Typecheck/build and browser evidence for deterministic output, views, budgets, and disposal.

## Guardrails

- Do not download, generate, or load a mesh/model-library asset as the primary implementation.
- Do not add Three.js to OpenCaw or silently install it in a host repository.
- Do not use a reference image without a recorded rights basis and applicable consent.
- Do not skip or reorder passes, exceed correction limits, or fabricate evidence.
- Do not silently switch from `CODE` when implementation fails.

## Commands

- `./commands/create-code-model-manifest.sh MODEL_ID --brief TEXT --prompt-override [options]`
- `./commands/validate-code-model-manifest.sh [--strict|--complete] MANIFEST.json`
- `./commands/next-code-model-pass.sh [--json] MANIFEST.json`
- `./commands/record-code-model-review.sh MANIFEST.json --pass PASS --decision DECISION --summary TEXT [--evidence VIEW=FILE ...]`
