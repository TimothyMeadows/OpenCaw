---
name: produce-generative-audio
description: Produce reviewed generative music, sound effects, or voice candidates with rights, consent, loudness, duration, looping, provenance, and runtime constraints. Use when planning or generating audio media.
engines: [AGNOSTIC]
---

# Produce Generative Audio

## When to use

- Generating or evaluating music, sound effects, ambience, or voice candidates.
- Building a deterministic audio batch and listen-through review.
- Preparing accepted audio for a conventional runtime handoff.

## Workflow

1. Confirm the selected backend and audio capability in `MEDIA.md`. For LOCAL, use `use-bubo-local-generation` through `bubo-media.sh`; read Bubo's media API for exact formats/settings and intrinsic decoder behavior. Setup, zero-sample diagnostics and generation are separate operations.
2. Define purpose, duration/bounds, structure, loop intent, variants, sample rate, channels, loudness, peaks, file size and runtime target. Direct Bubo LOCAL distinguishes SFX, instrumental/supplied-lyric music, preset speech and consented cloning. Voice uses explicit autoregressive token/time/byte ceilings rather than a fixed requested duration or diffusion controls; unsupported settings must fail.
3. Record source rights and obtain explicit identity or voice consent where applicable. Cloning requires exact local reference audio/transcript identities and reference-bound rights/consent; reject remote reference URLs. Keep transcripts/conditioning private and separate local-use consent from public audio disclosure.
4. Generate a deterministic batch where supported and record explicit unavailable markers where a provider withholds parameters or seeds. Preserve the approval's shared media-state path and existing candidate/revision allowance across tasks and workspace changes.
5. Stage candidates and create a listen-through sheet with waveform, duration, loudness, clipping, silence, loop, artifact and semantic checks. Keep native amplitudes and disclose clipping/silence rather than hiding them with normalization.
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
- Listen to the complete candidate for content and declared preset/reference match. A settings manifest, waveform measurement or fixture is not a listening verdict; generated music never implies a reviewed loop.
