---
name: build-proof-to-model-assets
description: Produce reviewed 3D assets from approved 2D proofs using the native PROOF_TO_MODEL pipeline, direct pinned Pixal3D reconstruction and audited Blender finishing. Use for proof preprocessing, reconstruction, retopology, UV/baking, LOD/collision, export, recovery and promotion evidence.
engines: [AGNOSTIC]
---

# Build Proof to Model Assets

## When to use

Use when PROOF_TO_MODEL is resolved for 2D-to-3D asset production or when resuming its staged native workflow. Do not invoke reconstruction for ordinary CSS/SVG interfaces or silently change a selected pipeline.

## Workflow

1. Read architecture, STYLE.md, `.styles/.pipelines/proof-to-model/PIPELINE.md` and its recipe/toolchain/schema. Resolve selection with `select-art-pipeline`, recording prompt evidence when applicable.
2. Inspect configured libraries with `use-external-asset-library`; preserve repository-local copy receipts and ancestry. Record scale, interfaces, rights, geometry/texture/collision budgets and rigging/animation applicability.
3. Use an authorized existing proof. New proof generation requires explicit CLOUD/LOCAL capability selection, MEDIA.md and applicable spending/rights authorization; it is never implicit.
4. Consult `./commands/proof-to-model.sh --help` and subcommand help. Initialize state with `init`; use `doctor` and dry-run `setup` to inspect prerequisites. Execute setup only when explicitly authorized and license evidence is supplied. Never accept licenses or install drivers.
5. Record exact proof-selection evidence before `preprocess` and `reconstruct`; preserve actual alpha or explicit BiRefNet preprocessing, masks, transforms and immutable originals. Missing approvals remain pending.
6. Run `finish` for measured QuadriFlow retopology, UV/bake, LOD/collision and editable blend/GLB outputs. Use only fixed, audited, hash-bound Blender 4.5 LTS scripts on working copies; this exception never permits arbitrary batch scripts or relaxes standalone BLENDER rules.
7. Run `review` and `validate`; inspect independent re-import findings and proof comparisons. Route required rig/animation work through subject-specific skills with evidence before declaring readiness.
8. Use `record` for current independent reviewer and separate human acceptance/rejection receipts. Check `status`; changed inputs require rerunning invalidated stages and reviews. Use `promote` only after explicit current human acceptance and task authorization.

## Guardrails

- No Docker, AssetForge, AssetFurnace, Bubo checkout, or sibling application dependency. Native process guards are not an OS sandbox.
- No threshold matte fallback, placeholder stages, automatic human approval, hidden downloads, silent pipeline changes or unreviewed promotion.
- Keep stage state under `.opencaw/.cache/tasks/<task>/`, candidates under `.art-staging/proof-to-model/`, tools under ignored `.local/tools/proof-to-model/`, and reviewed runtime packages under `assets/models/`.
- Preserve failed attempts and immutable originals, hashes, model/tool/script/recipe identity and logs. Distinguish simulated-process tests from live engine and Blender acceptance.
