# Art Pipelines

OpenCaw separates visual language from the method used to produce it. Every generated `STYLE.md` selects one or more art style templates and exactly one primary art pipeline.

Primary art pipelines selectable in `STYLE.md`:

- `CLOUD` - session-provided image generation with explicit cost, provenance, staging, and review controls.
- `LOCAL` - loopback-only ComfyUI image and audio generation using reviewed local GPU tooling.
- `PROOF_TO_MODEL` - original-only anatomy/structure classification, reviewed six-view proofs, pinned native multi-view reconstruction, Blender finishing and reviewed runtime packages.
- `CODE` - authored procedural Three.js models, with linked character profiles, isolated visual review, and calibrated runtime evidence for characters and creatures.
- `BLENDER` - authored Blender 4.5 LTS scenes, assets, renders, and exports with immutable-source and review controls.

Pipeline contracts:

- `cloud/PIPELINE.md`
- `local/PIPELINE.md`
- `proof-to-model/PIPELINE.md`
- `code/PIPELINE.md`
- `blender/PIPELINE.md`

Shared generated-media provenance lives under `_shared/`. Pipeline-specific schemas, manifests, and reusable assets remain beside the pipeline that owns them.

`PROOF_TO_MODEL` is the default when style generation does not name a pipeline. A current user prompt may explicitly select any registered pipeline for one task without rewriting `STYLE.md`. Never switch pipelines silently after work begins.

## Downstream production pipelines

- [`MODEL_TO_ANIMATION`](../.workflows/model-to-animation/WORKFLOW.md) - turn a reviewed model into a skinned, articulated or rigid motion package: prepare its rig/hierarchy, author or retarget clips, bake/export, review full motions and verify selected-engine playback and effects before separate human runtime acceptance.
- [`MODEL_TO_ACTION`](../.workflows/model-to-action/WORKFLOW.md) - compose reviewed clips into ordered dance patterns, combinations or charge/cast actions, with explicit trims, rates, blends, timed model-attached effects and fixed-target presentation.

`MODEL_TO_ANIMATION` follows model production through `PROOF_TO_MODEL`, `BLENDER`, a copied asset library or an explicitly compatible `CODE` handoff. It composes with the selected primary art pipeline and preserves `STYLE.md` and `ENGINE.md`; it is not a primary choice for `generate-style.sh` or `resolve-art-pipeline.sh`.

Use [`build-model-animations`](../../skills/build-model-animations/SKILL.md) and [`model-to-animation.sh`](../../commands/model-to-animation.sh). The contract, schemas, recipes, audited Blender scripts and engine adapter live under `.styles/.workflows/model-to-animation/`.

Use [`build-model-actions`](../../skills/build-model-actions/SKILL.md) and [`model-to-action.sh`](../../commands/model-to-action.sh) for composed sequences. Its owned contract and assets live under `.styles/.workflows/model-to-action/`. Individual clip creation stays with MODEL_TO_ANIMATION; gameplay retains movement, targeting, collision, damage and projectile-outcome authority. Neither downstream pipeline replaces the primary STYLE selection or grants runtime acceptance.
