# MUSIC production pipeline

## Scope

MUSIC owns instrumental and supplied-lyric tracks. AUDIO owns effects/ambience; VOICE owns preset speech and consented cloning. Each domain loads independently alongside the selected visual pipeline. Music generation needs no fabricated STYLE or ENGINE; target handoff still requires the actual selected engine and compatible runtime evidence.

## Entry point and readiness

Use `commands/music-pipeline.sh --help` and `skills/build-music-assets/`. The command provides brief/init/revise/status/doctor, dry-run setup planning, explicit generation or provenance import, technical validation, human review, target handoff and separately authorized promotion/recovery. It uses the shared coordinator and immutable lifecycle without importing the AUDIO workflow. Bubo remains the only LOCAL installation and synthesis boundary.

Configure only requested MUSIC.md through `generate-media-pipeline-contract.sh MUSIC`; read shared MEDIA.md for provider/execution authority. A valid contract, command, capability or installation receipt does not establish executable readiness. Status/doctor loads no model and performs no generation or installation. Provider, device, precision, workflow and backend never change implicitly.

## Brief and native request

Use [brief.schema.json](brief.schema.json) and [examples/README.md](examples/README.md). A brief declares purpose, explicit provider, `instrumental` or `supplied-lyrics`, spatialization (`2d`/`3d`), loop intent and finite byte/duration budgets. Put mood, instrumentation and intended structure in the caption; they are descriptive intent rather than invented native knobs. Each item retains the exact supplied lyric text, supported language, nullable BPM, key/scale, time signature and shift. Song briefs require a typed `lyricsRights` reference to an `opencaw-music-lyrics-rights/v1` record with ordered item IDs and SHA-256 of each exact UTF-8 lyric string, task/purpose, confirmed rights, generation permission and a typed source identity. Whitespace and line endings are part of that identity. Instrumentals require empty supplied lyrics and `unknown` vocal language; they do not borrow a song's permission.

LOCAL dispatch uses Bubo `ace-step-turbo`, explicit `cuda:0`/`bfloat16`/`none`, native `budget.maximum*` fields and item `seconds`. A batch has 1..4 items. Captions are at most 512 characters, seeds are nonnegative int32, steps 1..8, guidance 1 and negative prompt empty. Durations are whole 10..600 seconds within the explicit budget. BPM is null or 30..300, key/scale empty or a supported major/minor key, time signature empty/2/3/4/6 and shift 1..5. Mode must match every item's music mode. Native approval attempts select the same instrumental/supplied-lyrics case, one candidate or revision and the existing typed approval. Backend selection, request IDs and version-owned output paths belong to the coordinator.

The optional ACE-Step planning LM, automatic lyrics, reference audio, audio codes, stems, mixing/mastering/editing controls and hidden variants are unsupported. Planning/thinking/chain-of-thought controls, normalization, fades and latent adjustments remain disabled. No automatic clipping, resampling, downmixing or amplitude correction occurs. A requested loop is only a candidate until actual seam review. A generated instrumental cannot satisfy a supplied-lyric song.

Native prompt rights and installation/license references remain separate from host lyric rights. Planning/import may retain original-task permission and `generationAllowed:false`; new LOCAL dispatch requires current-task permission for both prompt and supplied lyrics plus native installation admission. Historical approval or a changed workspace never replenishes the physically shared native allowance. CLOUD briefs retain mode/exact lyrics and rights but omit native execution controls. This command imports actual CLOUD provenance; it does not invent an unattended adapter or fall back to LOCAL.

## Immutable provenance and technical checks

State lives under `.opencaw/.cache/tasks/<task>/media/music/<asset-hash>/<version>/`; original asset names remain in the immutable record and original tracks stay in non-runtime staging. Preserve started/failed attempts, original run IDs, all rejected revisions, native context/request/result/manifest, actual build/catalogue/worker identities and output hashes. New versions retain ancestry. Changes to text, sources, policy, settings, output bytes or target invalidate dependent evidence.

Technical validation rehashes complete neutral/native ancestry and exact output coverage. Authoritative native measurements bind 48000Hz stereo raw FLOAT WAV, frames/duration, bytes, peak/RMS/clipping/silence and resolved music settings. Metadata must show exact supplied lyrics, actual seed/steps/guidance, caption/lyric conditioning without truncation, planning LM disabled, no CPU decode/normalization and disclosed cleanup counters. Preserve original amplitude, including threshold failures; a report does not fix audio. LUFS, stems, acoustic lyric accuracy and musical/loop quality are unavailable without actual compatible evidence. CLOUD/incomplete imported analysis remains technically ineligible.

Current production retains immutable verified runtime/build/catalogue evidence. Historical import may retain its exact original revision/root/context/request rather than substituting the current pin. An optional LOCAL `historicalRoot` is import-only: it must be an existing directory strictly beneath the current project, match the neutral wrapper and untouched original context.projectRoot, and only maps original-root-relative typed identities. New references remain canonical current-project-relative paths. This is confined same-project original-root support, not cross-machine migration or fresh generation permission.

## Listening, target review and promotion

Current content review binds the complete exact ordered output set and asset fingerprint to a human source, reviewer, reason and verdict. Acceptance requires `listenedEntireOutput`, `matchesBrief`, `intendedVocalContentReviewed`, `artifactsAcceptable` and `headTailAccepted`; songs additionally require `everySuppliedLineReviewed`. Verify audible vocal intent and every original supplied line rather than accepting a metadata match. Review supplied section markers as structure cues without assuming those marker names must be sung; preserve their exact source text. Intended loops also require `loopSeamReviewed`. Historical listening or a synthetic waveform is not new human acceptance.

Runtime acceptance additionally binds actual selected-engine playback/load/disposal, matching spatialization/loop intent, codec/rate/channel/duration/byte budgets and separate current `opencaw-music-distribution/v1` evidence for this task/purpose. `opencaw-music-runtime-evidence/v1` retains exact outputs/engine and nested source identities. Lyric permission does not imply distribution permission. Rehash both sources and all current evidence before handoff/promotion.

Handoff prepares an admission plan without copying. Explicit promotion/recovery uses the shared executor with current technical/content/runtime reviews, exact target/output authorization, no overwrite, serialized ownership and retained intent/failure/recovery records. Examples are non-authorizing templates. Source merges grant no music generation, listening acceptance, private disclosure or runtime asset promotion.

Follow the shared lifecycle and bounded native GPU/process ownership. MUSIC has no runtime dependency on AUDIO or VOICE; no provider fallback is automatic.
