---
name: validate-generated-media
description: Validate generated image and audio batches for manifest completeness, exact coverage, geometry, technical budgets, artifacts, rights, consent, and reviewed promotion. Use before runtime handoff.
---

# Validate Generated Media

## When to use

- Reviewing generated image or audio candidates before handoff or promotion.
- Verifying a generation manifest and staged file hashes.
- Comparing an exact asset or audio coverage plan against delivered outputs.

## Workflow

1. Validate the generation manifest structure, explicit unavailable markers, staged paths, and hashes.
2. Compare delivered files against the planned matrix for exact names, states, variants, dimensions, durations, and destinations.
3. Review images in contact sheets at full, thumbnail, grayscale, and representative runtime scale.
4. Review audio in a listen-through sheet for duration, loudness, peaks, silence, loop boundaries, artifacts, and semantic fit.
5. Check rights, consent, provenance, tool and model revisions, workflow digest, parameters, seed, and runtime budgets.
6. Record each candidate as accepted or rejected with reasons; promote only accepted, human-reviewed outputs in a separate action.

## Output

- A manifest validation result and hash report.
- Contact-sheet or listen-through evidence.
- Exact coverage, technical-budget, provenance, and promotion verdicts.

## Guardrails

- Never invent missing reproducibility, rights, consent, or review evidence.
- Do not silently repair or replace rejected artifacts.
- Do not accept a visually or aurally plausible file when coverage, geometry, budget, or provenance fails.
- Do not promote staged outputs without an explicit human review status.
