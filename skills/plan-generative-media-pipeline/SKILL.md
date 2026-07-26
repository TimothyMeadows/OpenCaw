---
name: plan-generative-media-pipeline
description: Plan a reproducible cloud or local media pipeline with explicit backend selection, budgets, provenance, staging, review, and promotion gates. Use when configuring image, music, sound-effect, or voice generation.
---

# Plan Generative Media Pipeline

## When to use

- Configuring image, music, sound-effect, or voice generation for a repository.
- Choosing between session/cloud capabilities and a compatible local backend.
- Defining reproducibility, rights, budget, staging, review, and promotion policy.

## Workflow

1. Read `MEDIA.md` when it exists and read `STYLE.md` for visual work.
2. Discover capabilities per modality. Treat the compatible session/cloud capability as default.
3. If a compatible local backend is viable, ask the user to choose cloud/session or local; do not infer the choice.
4. Generate or update `MEDIA.md` with selected backends, versions, destinations, budgets, rights, consent, provenance, review, and promotion rules.
5. Define a deterministic batch plan, naming scheme, staging location, manifest location, comparison format, and rejection criteria.
6. Keep promotion separate from generation and require a recorded human review verdict.

## Output

- A validated `MEDIA.md` contract.
- A per-modality backend and capability matrix.
- A deterministic batch, staging, review, budget, and promotion plan.

## Guardrails

- Never persist API keys, access tokens, credential-bearing URLs, or vendor account data.
- Never switch between cloud/session and local backends silently.
- Do not treat generated candidates as approved runtime assets.
- Do not proceed when input rights or required identity and voice consent are unclear.
