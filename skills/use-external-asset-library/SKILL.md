---
name: use-external-asset-library
description: Discover approved read-only 3D models, rigs, animations, and bundles from optional external libraries configured in STYLE.md, then copy a selected asset into the repository before loading or modifying it. Use before creating, generating, or downloading a 3D asset when STYLE.md contains external asset libraries.
---

# Use External Asset Library

## When to use

Use for 3D model, rig, animation, Blender, WebGL, or game-asset work when `STYLE.md` contains an `External Asset Libraries` section.

## Workflow

1. Read and validate `STYLE.md`. Do not ask about libraries during startup or setup when none are configured.
2. Run `./commands/list-external-asset-libraries.sh`. When at least one library exists, inspect appropriate libraries before creating, generating, or downloading another model, rig, or animation.
3. Inventory candidates with `./commands/inspect-external-asset-library.sh LIBRARY_ID`. Treat inventory as filenames and metadata only; do not load or import an external file to preview it.
4. Evaluate candidate fit, asset-level provenance, license, modification limits, selected art pipeline, architecture, format, rig, animation, and runtime budgets. A configured root is not proof of redistribution rights.
5. Copy the selected file or complete bundle with `./commands/copy-external-asset.sh`. Record task-local evidence when an active task exists.
6. Load, import, edit, execute, or use only the repository-local copy below `assets/models/<library-id>/`. Verify it in the intended authoring tool or runtime before handoff.

## Pipeline Fit

- With `BLENDER`, use copied `.blend` files or bundles as working templates or approved reusable assets; never open the external source directly.
- With `CODE`, use a copied mesh only as authorized reference/template evidence. Do not turn model-library loading into the primary runtime implementation.
- With `CSS3`, do not use 3D model assets.
- With any other workflow, proceed only when the active pipeline and repository architecture explicitly permit the copied format and intended runtime use.

## Output

- Selected library id and source-relative asset path.
- Repository-local destination below `assets/models/`.
- Copy receipt containing the active style hash and copied-file hashes when evidence is requested.
- Rights, compatibility, and use-as-is versus template decision.

## Guardrails

- Treat every configured external library and every file beneath it as read-only.
- Never edit, rename, delete, generate into, install into, or otherwise write beneath a library root.
- Never load, import, execute, or use an external-library path directly. Copy first.
- Never follow symbolic links, escape the configured root, overwrite a project asset, or copy outside `assets/models/`.
- Never create or download a replacement before checking configured libraries, unless the task explains why no compatible authorized candidate exists.

## Commands

- `./commands/list-external-asset-libraries.sh [--style STYLE.md] [--json]`
- `./commands/inspect-external-asset-library.sh LIBRARY_ID [--style STYLE.md] [--json]`
- `./commands/copy-external-asset.sh LIBRARY_ID RELATIVE_ASSET_PATH [--style STYLE.md] [--evidence .ai/tasks/<task>/FILE.json]`
