# AUDIO.md

<!-- opencaw-media-pipeline:v1 domain=AUDIO -->

## Pipeline Selection
- AUDIO

## Shared Media Authority
- MEDIA.md

## Provider And Execution Authority

Provider selection comes from MEDIA.md and explicit task authorization. AUDIO selects the SFX/ambience production domain only. Never switch or fall back between providers silently. The verified pinned Bubo runtime owns LOCAL synthesis, tools/model pins, native limits and shared GPU/claim ownership. Configuration grants no installation, license acceptance or generation allowance.

## Brief Requirements

Record effect/environment, duration, variation, explicit LOCAL/CLOUD provider, spatialization/loop intent and finite output/runtime budgets in an opencaw-audio-brief/v1 brief. Use supported SFX controls and native maximum* budget/seconds names; do not silently tile, trim, normalize or downmix long ambience. MUSIC and VOICE are separately loadable domains. CLOUD execution is import-only unless a compatible session capability is separately selected.

## State And Ancestry

Keep immutable task/domain/asset/version state and exact input/request/settings/output hashes in non-runtime staging. Preserve all started attempts and one shared approval-bound native media-state root across tasks and domains. No allowance resets or implicit editing.

## Review And Promotion

Require complete exact-output human listening and separate loop review when claimed. Native hash-bound measurements establish technical observations, not acoustic quality; unavailable LUFS/loop/memory measures remain explicit. Promotion requires current technical/content/target evidence, separately scoped distribution rights and explicit promotion authorization. Preserve rejected/superseded evidence; generation and source merges do not promote assets.

{{DEFINITION}}
