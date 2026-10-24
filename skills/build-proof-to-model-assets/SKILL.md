---
name: build-proof-to-model-assets
description: Produce reviewed 3D assets through original-source classification, a human-approved six-angle proof set, native Pixal3D multi-view reconstruction and audited Blender finishing. Use for PROOF_TO_MODEL asset production, revisions, recovery and review evidence.
engines: [AGNOSTIC]
---

# Build Proof to Model Assets

## When to use

Use when PROOF_TO_MODEL is resolved for 2D-to-3D asset production or when resuming its staged native workflow. Do not invoke reconstruction for ordinary CSS/SVG interfaces or silently change a selected pipeline.

## Workflow

1. Read architecture, STYLE.md, `.styles/.pipelines/proof-to-model/PIPELINE.md` and its recipe/toolchain/schema. Resolve selection with `select-art-pipeline`, recording prompt evidence when applicable.
2. Inspect configured libraries with `use-external-asset-library`; preserve repository-local copy receipts and ancestry. Record scale, interfaces, rights, geometry/texture/collision budgets and rigging/animation applicability.
3. Consult command/subcommand help. Use `init` to preserve authorized originals; use `doctor` and dry-run `setup` to inspect prerequisites. Execute setup only with explicit authorization and license evidence. Never accept licenses or install drivers.
4. First inspect and research only the registered original images. Read [source-subject-classification.md](references/source-subject-classification.md) for entities, observed/inferred anatomy or structure, materials, occlusion and unresolved interpretations. Register the actual report with `classify`; native registration does not perform vision or research.
5. Read [multiview-proof-contract.md](references/multiview-proof-contract.md) to plan front, subject-right, back, subject-left, top and bottom with one pose, identity and camera convention. If the sole source genuinely covers one angle, generate five missing views; an oblique/cropped source remains an anchor and may require six. New images/revisions require explicit CLOUD/LOCAL selection, MEDIA.md, rights and bounded spending authorization. Use the available session media capability, then register actual artifacts with `prepare-proofs`; the native command is not an image generator.
6. Show originals and all six current proofs, resolve consequential inferred features, and obtain human approval bound to the complete set. Preserve rejected candidates and revise only selected views. Record `proof-set` approval before `preprocess` using the current `status` fingerprint named `proofSet`; preserve real alpha or explicit BiRefNet, every mask, common square padding and adjusted camera FOV. Inspect and approve preprocessing before `reconstruct`, which must consume all six separate images and the pinned MV model set.
7. Run `finish` for measured QuadriFlow retopology, UV/bake, LOD/collision and editable blend/GLB outputs. Use only fixed, audited, hash-bound Blender 4.5 LTS scripts on working copies; this exception never permits arbitrary batch scripts or relaxes standalone BLENDER rules.
8. Run `review` and `validate`; inspect independent re-import findings, original-source comparisons and six matching-camera proof/render pairs. Nominal camera alignment does not establish likeness or anatomical correctness. Route required rig/animation work through subject-specific skills with evidence before declaring readiness.
9. Use `record` for current independent reviewer and separate human acceptance/rejection receipts. Check `status`; changed inputs invalidate affected proofs, approvals and dependent results. Use `promote` only after explicit current human acceptance and task authorization.

## Guardrails

- No Docker, AssetForge, AssetFurnace, Bubo checkout, or sibling application dependency. Native process guards are not an OS sandbox.
- No threshold matte fallback, placeholder stages, automatic human approval, hidden downloads, silent pipeline changes or unreviewed promotion.
- Keep stage state under `.opencaw/.cache/tasks/<task>/`, candidates under `.art-staging/proof-to-model/`, tools under ignored `.local/tools/proof-to-model/`, and reviewed runtime packages under `assets/models/`.
- Preserve failed attempts and immutable originals, hashes, model/tool/script/recipe identity and logs. Distinguish simulated-process tests from live engine and Blender acceptance.
- Generated/revised proofs and reconstruction renders never become classification evidence. Hidden anatomy and unseen surfaces remain inferred design completions after approval.
- Single-view diagnostics require explicit `--mode single-view-diagnostic` and use the separate `proof` approval kind; that receipt cannot approve a v2 proof set. No SV fallback, four-image subset or contact sheet may stand in for the six inference frames.
