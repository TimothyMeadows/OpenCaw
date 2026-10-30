# Independent media production pipelines

These production domains load independently of the visual primary selected by STYLE.md and independently of each other:

- `AUDIO` — [game sound effects and ambience](audio/PIPELINE.md).
- `MUSIC` — [instrumental and supplied-lyric music](music/PIPELINE.md).
- `VOICE` — [preset speech and consented local-reference cloning](voice/PIPELINE.md).

`registry.json` and `registry.schema.json` define domain names, explicit modality aliases, optional host contracts and implementation readiness. Domain declarations and templates are present from the foundation stage; a declaration does not imply its production command is implemented or a model is installed. `resolve-media-pipeline.sh` reports these distinctions without creating contracts, loading a model or selecting a provider.

AUDIO, MUSIC and VOICE have implemented `audio-pipeline.sh`, `music-pipeline.sh` and `voice-pipeline.sh` workflows with matching `build-audio-assets`, `build-music-assets` and `build-voice-assets` skills. Shared orchestration/evidence/ownership utilities are domain-neutral; one production domain never imports another.

Configure one requested domain with `generate-media-pipeline-contract.sh AUDIO`, `MUSIC` or `VOICE`. This creates only its optional host contract, AUDIO.md, MUSIC.md or VOICE.md. Use `--inline` for embedded instructions; default read directives point to the installed shared declaration. An existing changed contract is preserved rather than overwritten. Validate with `validate-media-pipeline-contract.sh DOMAIN`.

Use `resolve-media-pipeline.sh --domain DOMAIN` or `--modality MODALITY` for explicit routing, and `--all --visual` for separate named contexts. Mixed requests become domain-owned work items, not a new global selection. Contradictory explicit domain/modality pairs fail. AUDIO owns SFX/ambience only, MUSIC owns music and VOICE owns speech. No text classifier, visual fallback or implicit speech cloning is involved.

MEDIA.md remains the shared CLOUD/LOCAL authority. Domain selection does not select a provider, accept a license, authorize setup/generation, reset an allowance or grant promotion. LOCAL execution remains behind the verified pinned Bubo adapter; Bubo owns native process/GPU controls and shared claim accounting. Independent contexts do not imply simultaneous GPU inference.

Read [the shared lifecycle](LIFECYCLE.md) and [host-facing guide](../../docs/MEDIA_PIPELINES.md). Existing visual contracts, shared provenance, historical receipts and downstream model workflows retain their owners.
