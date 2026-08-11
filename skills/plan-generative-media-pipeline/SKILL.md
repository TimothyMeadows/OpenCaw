---
name: plan-generative-media-pipeline
description: Plan reproducible CLOUD or LOCAL media execution with explicit pipeline selection, budgets, provenance, staging, review, and promotion gates. Use when configuring image, music, sound-effect, or voice generation.
---

# Plan Generative Media Pipeline

## When to use

- Configuring image, music, sound-effect, or voice generation for a repository.
- Choosing between the `CLOUD` and `LOCAL` media pipelines.
- Defining reproducibility, rights, budget, staging, review, and promotion policy.

## Workflow

1. Read `MEDIA.md` when it exists and read `STYLE.md` for visual work.
2. For images, resolve `CLOUD` or `LOCAL` through `STYLE.md` or an explicit task prompt. For music, sound effects, and voice, use `MEDIA.md` independently of visual style.
3. Discover capabilities per modality. If both cloud/session and local are viable, require an explicit choice; do not infer a fallback.
4. Generate or update `MEDIA.md` with selected pipelines, versions, destinations, budgets, rights, consent, provenance, review, and promotion rules.
5. Define a deterministic batch plan, naming scheme, staging location, manifest location, comparison format, and rejection criteria.
6. Keep promotion separate from generation and require a recorded human review verdict.

## Output

- A validated `MEDIA.md` contract.
- A per-modality pipeline and capability matrix.
- A deterministic batch, staging, review, budget, and promotion plan.

## Guardrails

- Never persist API keys, access tokens, credential-bearing URLs, or vendor account data.
- Never switch between `CLOUD` and `LOCAL` silently.
- Do not require `MEDIA.md` for `CSS3`, `CODE`, or ordinary `BLENDER` work; use it for Blender only when cloud/local generated inputs are in scope.
- Do not treat generated candidates as approved runtime assets.
- Do not proceed when input rights or required identity and voice consent are unclear.
