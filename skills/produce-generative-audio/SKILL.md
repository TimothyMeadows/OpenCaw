---
name: produce-generative-audio
description: Produce reviewed generative music, sound effects, or voice candidates with rights, consent, loudness, duration, looping, provenance, and runtime constraints. Use when planning or generating audio media.
---

# Produce Generative Audio

## When to use

- Generating or evaluating music, sound effects, ambience, or voice candidates.
- Building a deterministic audio batch and listen-through review.
- Preparing accepted audio for a conventional runtime handoff.

## Workflow

1. Confirm the selected backend and audio capability in `MEDIA.md`.
2. Define purpose, duration, structure, loop points, variants, sample rate, channels, loudness, peaks, file size, and runtime target.
3. Record source rights and obtain explicit identity or voice consent where applicable.
4. Generate a deterministic batch where supported and record explicit unavailable markers where a provider withholds parameters or seeds.
5. Stage candidates and create a listen-through sheet with waveform, duration, loudness, clipping, silence, loop, artifact, and semantic checks.
6. Reject unsuitable candidates explicitly. Promote only accepted files after human review and runtime validation.

## Output

- An audio brief, batch plan, and runtime budget.
- Staged candidates with provenance and generation manifests.
- A listen-through review with acceptance or rejection reasons.

## Guardrails

- Never clone or imply a person's voice without documented authorization and consent.
- Do not assume generated music, samples, or model outputs are redistributable.
- Do not normalize, trim, splice, loop, or repair a rejected artifact destructively without approval.
- Do not publish or promote audio automatically.
