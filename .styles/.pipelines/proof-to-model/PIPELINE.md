# PROOF_TO_MODEL Art Pipeline

## Intent

Produce editable, measured 3D game assets from human-selected 2D proofs using native pinned Pixal3D reconstruction and Blender 4.5 LTS finishing. PROOF_TO_MODEL is the default; CLOUD, LOCAL, CODE, and BLENDER remain explicit alternatives. Never switch pipelines or engines silently. CSS3 is retired; ordinary CSS/SVG interface work remains supported outside this registry.

## Inputs

- Resolve STYLE.md and record its hash and any task-local prompt override. Read architecture and applicable rights, budgets, scale, interfaces, subject requirements, and runtime format constraints.
- Inspect configured external libraries first; copy selected assets with the existing library command before opening them. Preserve copy receipts, rights, original hashes, and source ancestry.
- Supply an authorized existing proof or independently authorize CLOUD/LOCAL proof generation. Read MEDIA.md only for generated media. Selecting this pipeline does not generate images, configure MEDIA.md, or authorize spending.
- Preserve the exact proof, prompt/references/provider metadata when available, human proof-selection evidence, and immutable original bytes.
- Supply an explicit recipe: geometry/texture budgets, cage extrusion and ray distance in metres, UV margin, LOD ratios, semantic parts, collision limits, and rigging/animation applicability. Missing applicable settings block execution.
- Use the checked-in toolchain pins and manifest schema beside this contract. Setup defaults to dry-run; explicit execution verifies platform, space, hashes, model revisions, and license evidence. Never install drivers, accept licenses, or download during ordinary production.

## Production Rules

1. Use `commands/proof-to-model.sh` and its native .NET 10 runner: `init`, `doctor`, `setup`, `preprocess`, `reconstruct`, `finish`, `review`, `record`, `validate`, `status`, `promote`. Consult command help for arguments. No Docker daemon, AssetForge, AssetFurnace, Bubo runtime checkout, or sibling project is required.
2. Keep state/manifests/receipts below `.opencaw/.cache/tasks/<task>/`, immutable originals and versioned attempts below `.art-staging/proof-to-model/<asset>/<version>/`, and audited dependencies below ignored `.local/tools/proof-to-model/`. Resolve all paths within the project; reject symbolic-link escapes and runtime staging overlap.
3. Inspect actual alpha. Preserve suitable mattes; otherwise explicitly run pinned BiRefNet preprocessing through Pixal3D. Retain masks, transforms, normalized input hashes and review evidence. Never substitute threshold matting or a placeholder backend.
4. Call pinned Pixal3D single-view native inference directly, preserving raw output, executable/model identities and receipts. Bound execution, stream logs, pass argument arrays, cancel process trees, and serialize reconstruction per GPU. Native execution is not an OS sandbox.
5. Finishing uses Blender 4.5 LTS and only the fixed audited, hash-bound `blender/finish.py` and `blender/review.py` batch scripts on declared repository-local working copies. Preserve every source and raw reconstruction. This explicit batch-authoring exception does not change standalone BLENDER connected-tool authoring policy or authorize arbitrary scripts.
6. Perform measured QuadriFlow retopology; preserve valid UVs or unwrap with declared margin; high-to-low bake using recorded cage/ray and tangent conventions. Record source/target material correspondence and packed textures.
7. Generate measured decimation LODs and convex collision hulls for declared semantic parts. Validate geometry, bounds, scale, hierarchy, collision limits and budgets. Applicable stages cannot be skipped or marked successful by placeholder output.
8. Save editable blend sources and GLB packages; independently re-import exports and inspect transforms, textures, materials, hierarchy, external dependencies and budgets. Generate representative views and proof-versus-export comparison evidence.
9. Persist stage inputs/outputs, hashes, tool/model/script/recipe identity, reviews and failure history. Changed inputs invalidate all dependent outputs and approvals. Recover interrupted work with new attempts while preserving failed evidence.
10. Require independent review and separate human runtime acceptance bound to current artifact hashes before promotion to `assets/models/`. Automated checks cannot fabricate human approvals. Rigging/animation require separate subject-specific skill work and current evidence when applicable.

## Output Contract

- Versioned manifests with asset identity, rights, proof/preprocessing ancestry, style/recipe/tool/model fingerprints, stage receipts, measured budgets, applicability, reviews, and promotion history.
- Immutable proof, masks/normalized inputs, raw reconstruction, original copied sources, and per-attempt logs; editable blend, GLB, packed textures, LOD/collider data and independent re-import findings.
- Representative rendered views, proof comparison, severity-ranked technical/visual defects, independent reviewer identity/evidence, and separate human acceptance or rejection reasons.
- No unreviewed runtime promotion. Missing dependencies or approvals remain blocked/pending with an actionable reason; never report simulated-process tests as live reconstruction evidence.

## Acceptance Checks

- Verify style selection, rights, external-library ancestry, approved proof and current hashes before expensive stages.
- Validate every applicable stage, GLB format and independent re-import, budgets, materials/UV/textures, transforms, collision and LOD lineage, and applicable rig/animation evidence.
- Verify cancellation, interrupted recovery, concurrent GPU exclusion, stale receipts, missing dependencies, corrupt outputs, and path confinement.
- Require actual Blender fixture execution for Blender acceptance and a bounded real Pixal3D run for live reconstruction acceptance. Unavailable tools/models/licenses block those live claims.
- Reject retired CSS3/CSS/vector/css-vector aliases with migration guidance. Never silently fall back to CLOUD, LOCAL, CODE, BLENDER, or another reconstruction backend.

## Role Fit

- `computer-science/generative-media-pipeline-engineer`: native orchestration, pins, audit, provenance, recovery and promotion gates.
- `arts/generative-art-designer`: proof art direction, authorized inputs and human selection evidence.
- `arts/blender-production-artist`: finishing, material fidelity, measured exports and subject-specific rigging/animation.
- `arts/art-director` and `computer-science/qa-engineer`: independent visual/technical review and runtime acceptance evidence.

Use `build-proof-to-model-assets`. Preserve imported Bubo attribution and the capability ledger in the native runtime; Bubo supplies adapted execution primitives, not a runtime dependency.
