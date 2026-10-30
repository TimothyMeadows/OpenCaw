# AUDIO production pipeline

## Scope

AUDIO owns game/effect sounds and ambience. MUSIC owns instrumental/supplied-lyric tracks; VOICE owns preset speech and consented cloning. This domain can load with both and with any selected visual pipeline without changing STYLE.md or requiring a visual style for sound generation.

## Entry point and readiness

Use `commands/audio-pipeline.sh --help` and `skills/build-audio-assets/`. The command supplies brief/init/revise/status/doctor, setup planning, generation or provenance import, technical validation, explicit review, target handoff and separately authorized promotion/recovery. It uses the shared host coordinator and immutable lifecycle; Bubo remains the only LOCAL synthesis and installation boundary. Command presence, a valid AUDIO.md or an installation receipt does not prove verified native readiness. Ordinary status/doctor performs no inference or model loading.

Configure only the requested optional AUDIO.md through `generate-media-pipeline-contract.sh AUDIO`; read shared MEDIA.md for provider and execution authority. Generation-only AUDIO requires no STYLE or ENGINE selection. Target handoff still binds the actual selected engine and compatible runtime evidence.

## Production requirements

- Record event/environment, one-shot versus ambience, supported duration, variation count, spatialization/loop intent and finite format/runtime budgets.
- Use MEDIA.md for explicit provider selection, rights, setup/generation limits and staging. LOCAL dispatch goes through the existing verified Bubo SFX capability; unsupported long ambience must fail rather than silently tile, trim or select music.
- Preserve immutable versions, exact request/settings/output ancestry and shared native approval/attempt roots. Technical metrics never establish human acoustic or loop acceptance.
- Listen to the complete exact output for intended texture/event, artifacts, unwanted speech/music and head/tail. Claim looping only after actual seam review.
- Require current technical/content/target evidence and separate explicit promotion authorization; do not implicitly normalize, edit, loop, overwrite or promote generated originals.

## Brief and native settings

Use [brief.schema.json](brief.schema.json) and [examples/brief.local.json](examples/brief.local.json). `kind` is `sfx` or `ambience`, with explicit purpose, provider, spatialization (`2d`/`3d`) and loop intent. LOCAL requests use native `settings`, `budget.maximum*` fields and item `seconds`, never host-test aliases. SFX supports duration0.25..47seconds,1..200steps,guidance1..12 and exact nonnegative safe-integer seeds. Negative prompts at guidance<=1, image/music/voice controls and hidden extra variants are rejected. No automatic long-ambience tiling, duration clipping, normalization or downmix occurs. Native FLOAT WAV remains44100Hz stereo; spatialization is a reviewed target intent, not a conversion command.

The brief's rights reference preserves original scoped prompt rights. Planning/import may retain an earlier task's rights and a `generationAllowed: false` assertion. Actual LOCAL dispatch independently requires current-task `generationAllowed: true`, exact installation/license identities, supported settings and native admission. Historical import never creates a fresh generation allowance or changes its source run ID. CLOUD is provenance-import only here; unattended generation requires a separately selected compatible session capability and does not fall back to LOCAL.

## Technical and human evidence

Technical validation rehashes current neutral manifest, native manifest/result/context/source request and exact output bytes. It uses native frames/sample rate/channels/peak/RMS/clipping/silence and actual sampling settings; requested settings alone cannot establish measurements. It checks complete variant coverage and exact original duration within the native one-frame tolerance. Explicit peak/clipping/silence thresholds can fail an output without altering its amplitude. LUFS, independent allocator/driver cleanup counters and loop quality remain explicitly unavailable when the SFX API does not expose them. CLOUD or incomplete imported measurement ancestry stays technically ineligible rather than receiving fabricated analysis.

Disclosed backend/workflow/runtime commit, actual build resource catalogue and worker digest must agree. Current production provenance retains an immutable verified build receipt; an original historical invocation may supply its exact recorded revision/root/request/context identity instead. A supplied immutable model-catalogue snapshot must match the actual native catalogue hash and selected model name/revision/digest/license. Missing source disclosures use explicit unavailable markers, never the current Bubo pin as a guess.

For a retained LOCAL run whose original root is still a directory beneath the current project, an import-only brief may explicitly set `historicalRoot`. Its neutral wrapper records the same value, while all new typed references use canonical current-project-relative paths. Technical validation binds the untouched original context.projectRoot, maps only original-root-relative input/output identities, preserves original source hashes and permits only historical/external import origins. This supports that exact confined same-project scope, not generic cross-machine path migration. New generation rejects historical-root briefs. Known optional native width/height/music/voice nulls are equivalent to omission; non-null incompatible controls remain rejected.

Content reviews bind the current full output set and brief with an actual human source identity. An accepted verdict requires `listenedEntireOutput`, `matchesBrief`, `unwantedSpeechMusicAbsent`, `artifactsAcceptable` and `headTailAccepted`; `loopSeamReviewed` is additionally required for intended loops. A waveform, metadata report or old listening verdict is not current human acceptance.

Accepted runtime reviews additionally bind current selected-engine playback/load/dispose evidence, matching spatialization/loop intent and separately supplied distribution-rights evidence for this task and purpose. Recheck nested source hashes before handoff/promotion; installation terms and generation permission alone grant no distribution permission. Shared promotion requires exact current target/output authorization, no overwrite and retained intent/recovery evidence. Examples are non-authorizing templates, not approvals.

Follow the shared lifecycle and preserve Bubo's bounded process/GPU ownership. No CLOUD/LOCAL fallback is automatic.
