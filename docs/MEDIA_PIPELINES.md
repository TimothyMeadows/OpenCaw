# Independent media pipelines

Load audio, music and voice workflows alongside any registered visual primary: CLOUD, LOCAL, PROOF_TO_MODEL, CODE or BLENDER. Their contexts are independent, so a task can plan an effect, a soundtrack and speech without changing STYLE.md or another media domain's selection. The visual workflow retains its own prerequisites; CODE still requires THREEJS.

| Work | Domain | Optional host contract |
| --- | --- | --- |
| Game sound effects and ambience | AUDIO | AUDIO.md |
| Instrumental and supplied-lyric music | MUSIC | MUSIC.md |
| Preset speech and consented local-reference cloning | VOICE | VOICE.md |
| Images and models | Existing visual pipeline | STYLE.md and the applicable visual workflow |

Ordinary audio/SFX/ambience work routes to AUDIO; music routes to MUSIC; spoken voice routes to VOICE. Mixed requests become separate domain-owned work items. Explicit contradictory domains or unsupported modalities are errors. This routing does not choose a provider: MEDIA.md remains the shared authority for CLOUD/LOCAL availability, rights, budgets, staging and promotion.

## Configure and inspect

The shared foundation supplies domain declarations, optional contract generation/validation and independent context resolution. AUDIO, MUSIC and VOICE supply their complete command workflows. Resolve configuration and readiness separately: a valid contract or model receipt does not certify an executable installation or successful generation.

Host contracts remain optional. Loading a project does not create all three contracts or require a Bubo build, MEDIA.md, STYLE.md or ENGINE.md for unrelated nonvisual planning. A requested domain can be configured explicitly. Missing unrelated domains leave other contexts usable. Generation requires current applicable domain and MEDIA/provider policy; an actual engine handoff also requires compatible engine ownership and target evidence.

Commands live under the host installation at `.opencaw/commands/`. Their `--help` output is the current interface reference. Shared declarations and templates live under [.media/pipelines](../.media/pipelines/INDEX.md); visual primary pipelines remain under [.styles/.pipelines](../.styles/.pipelines/INDEX.md). AUDIO, MUSIC and VOICE are not extra primary STYLE choices.

From the project root, configure only the domain requested for the task:

```bash
bash .opencaw/commands/generate-media-pipeline-contract.sh AUDIO
bash .opencaw/commands/validate-media-pipeline-contract.sh AUDIO
bash .opencaw/commands/resolve-media-pipeline.sh --modality ambience
```

Use `MUSIC` or `VOICE` in the first two commands to configure those domains. Contract generation defaults to concise read directives; `--inline` embeds the current shared declaration. `--output FILE` creates a different confined contract file, which can be selected explicitly with `--contract FILE` during validation or resolution. An exact existing generated contract is reused with `created: false`; differing existing bytes are preserved and reported as an error.

Load all independent contexts, including the existing visual selection, without changing their contracts:

```bash
bash .opencaw/commands/resolve-media-pipeline.sh --all --visual
```

Commands return JSON. Aggregate resolution returns `contexts.visual`, `contexts.audio`, `contexts.music` and `contexts.voice`; omit `--visual` to avoid loading visual policy. A single-domain resolution reports:

| Field | Meaning |
| --- | --- |
| `domain` and `modality` | Routed domain and canonical modality; selecting only a domain leaves modality unspecified |
| `configured` | This domain has a valid selected host contract |
| `contract` and `media` | Project-relative file identities, or null when an optional default file is absent |
| `policySha256` | Selected domain/contract/modality and shared media-policy fingerprint; unrelated domain changes are excluded |
| `executionAvailable` | Declared workflow entry point and required configuration are available; this does not certify native installation or output quality |
| `nativeReadiness` | Native readiness remains `unverified` by this configuration-only resolver |
| `unavailableReasons` | Missing configuration or domain implementation prerequisites |

The canonical modalities are `sfx`, `ambience`, `instrumental`, `supplied-lyrics`, `preset-speech` and `consented-cloning`. For example, `--domain AUDIO --modality supplied-lyrics` fails rather than changing the requested domain. Explicit `--root`, `--contract` or `--media` paths are checked; a missing explicitly selected file is an error, while absent optional defaults are reported without creating them.

## One task, three independent assets

For an existing `town-square` task, prepare three valid domain briefs with their actual rights, source references, explicit provider and finite budgets. The following initialization commands load no model and grant no generation allowance. They intentionally reuse the human asset name `arrival`; the domain remains part of each immutable identity:

```bash
bash .opencaw/commands/audio-pipeline.sh init --task town-square --asset arrival --version v1 --brief inputs/arrival-sfx.json --workspace .opencaw/.cache/media-production
bash .opencaw/commands/music-pipeline.sh init --task town-square --asset arrival --version v1 --brief inputs/arrival-music.json --workspace .opencaw/.cache/media-production
bash .opencaw/commands/voice-pipeline.sh init --task town-square --asset arrival --version v1 --brief inputs/arrival-speech.json --workspace .opencaw/.cache/media-production
```

Read each JSON result's `stateFile` into its own `AUDIO_STATE`, `MUSIC_STATE` or `VOICE_STATE` variable. Use those exact project-relative paths; do not guess the hashed folders. Each state belongs to its domain even though the task, asset name and staging workspace match. The visual selection is unchanged. Status, planning and reviews can proceed independently; model execution still follows shared native ownership.

Only after separate LOCAL generation authorization, set `APPROVED_MEDIA_STATE` to that approval's already bound shared media-state root. Use the same physical root for image, SFX, music and speech cases covered by that media approval; never allocate one per domain or revision. For example:

```bash
bash .opencaw/commands/audio-pipeline.sh generate --state "$AUDIO_STATE" --provider LOCAL --workspace .opencaw/.cache/media-production --media-state "$APPROVED_MEDIA_STATE"
```

The MUSIC and VOICE commands take their own state with the same approved media-state root. Their brief's explicit provider must match the command. Missing installation, license, rights, consent or remaining allowance stops the requested operation. CLOUD uses separately selected available session generation and actual provenance import; these commands do not replace an unavailable provider. Existing compatible outputs can be imported with their original run ancestry, without claiming new synthesis or a fresh listening verdict.

After generation or import, run each asset's `validate`, then record its actual full-content review and separate runtime review with `review`. For example, AUDIO uses `audio-pipeline.sh review --state "$AUDIO_STATE" --review inputs/arrival-sfx-content-review.json`; MUSIC and VOICE use their own review files and criteria. `handoff --state ...` returns a guarded plan, not a runtime copy. Only a separately authorized `promote --state ... --authorization ...` publishes exact accepted bytes into its fresh target directory.

Revise only the affected asset, retaining its previous state as ancestry:

```bash
bash .opencaw/commands/audio-pipeline.sh revise --state "$AUDIO_STATE" --version v2 --brief inputs/arrival-sfx-v2.json
```

Use the returned new state for subsequent work. A revision neither erases failed attempts nor replenishes an exhausted candidate/revision allowance. Domain-specific changes invalidate their dependent evidence; shared MEDIA policy or shared source changes invalidate every affected consumer. Another domain's unchanged review cannot approve this revision.

## Work with staged assets

The [shared lifecycle](../.media/pipelines/LIFECYCLE.md) defines planning, read-only status, setup planning, generation/provenance import, technical validation, exact-output human review, target handoff and separate promotion. Domain workflows add their own brief fields and supported controls to those boundaries.

The foundation's handoff and promotion admission APIs return guarded plans. The separate shared promotion executor performs only an explicitly authorized domain command: private staged copying, current domain-policy revalidation and publication into a fresh version directory. It retains exact ownership, source/target hashes and intent/completion/failure history; explicit recovery recognizes only the same authorized bytes and cannot adopt or overwrite foreign files. Existing ownership locks require inspection rather than automatic deletion.

### SFX and ambience

Use `build-audio-assets` and the [AUDIO contract](../.media/pipelines/audio/PIPELINE.md). The command supports `brief`, `init`, `revise`, `status`, `doctor`, `setup-plan`, `generate`, `import`, `validate`, `review`, `handoff`, `promote` and `recover`:

```bash
bash .opencaw/commands/audio-pipeline.sh --help
bash .opencaw/commands/audio-pipeline.sh brief --brief path/to/audio-brief.json
```

Examples and the strict brief schema live beside the AUDIO contract. LOCAL SFX and ambience use the same supported native SFX capability. Unsupported long ambience or controls fail; no implicit tiling, trimming, normalization or provider fallback occurs. CLOUD is an explicit provenance-import path when no unattended session generation capability is available. Missing authoritative technical analysis keeps imported work ineligible for handoff.

Complete exact-output listening, any claimed loop seam, current distribution rights and actual selected-engine playback/load/dispose evidence remain separate gates. `promote` requires an additional exact authorization and writes deterministic `000.<codec>`, `001.<codec>` files beneath its fresh authorized target directory. Private provenance stays in task state. `recover` preserves failed preparation and can finish the receipt for an already published exact directory without copying again. A corrupted event or uncertain ownership lock remains an explicit diagnostic; recovery never discards history automatically.

Read-only status exposes `promotionState`, `promotionNeedsRecovery` and `publicationObserved`. A failed completion receipt can leave an already published directory: status reports that observation while keeping `promotion: false` until exact owned recovery completes. Do not treat a failed command as proof that no runtime write occurred.

### Instrumental and supplied-lyric music

Use `build-music-assets`, `music-pipeline.sh --help` and the [MUSIC contract/examples](../.media/pipelines/music/PIPELINE.md). The same lifecycle commands apply. Choose `instrumental` or `supplied-lyrics` explicitly; exact supplied UTF8 lyrics and scoped lyric-rights evidence remain bound to each requested item. LOCAL ACE-Step Turbo supports whole-second10..600 tracks,1..8 steps, guidance1 and an explicit int32 seed, using cuda:0/bfloat16/none. Unsupported planning, invented lyrics, mastering/stems/editing and provider fallback are errors.

The shared evidence validator retains native48000Hz stereo frames and raw amplitudes. MUSIC additionally verifies exact native conditioning/settings, disabled planning and normalization, and measured cleanup. Metadata proves neither audible singing nor musical quality. Review the entire track, intended vocal content, every supplied line and any claimed loop seam. Current selected-engine playback/load/disposal and separate distribution rights must pass before separately authorized promotion. Historical tracks remain imports with their original source/runtime/attempt identities, current human review pending and no new allowance.

## Shared execution and state

State is task-owned under `.opencaw/.cache/tasks/<task>/media/<audio|music|voice>/`. Each asset version retains its original brief, input and policy references, and any resulting native execution identity and staged outputs. Changes create new versions; affected reviews become stale. Native request/output IDs are collision-safe across domains and versions even when human asset names match. All domains still use the approval's physically shared native attempt ledger.

LOCAL work uses the pinned, explicitly built Bubo runtime through the existing media adapter. Bubo owns exact model/tool pins, verified installation, synthesis, bounded workers and GPU ownership. Independent context loading does not grant simultaneous GPU inference: proof reconstruction and LOCAL image/audio generation share native GPU exclusion. The six-case media acceptance ledger covers LOCAL image, SFX, instrumental, supplied-lyric, preset-speech and cloning cases under their original media approval. Proof/model workflows retain their own existing approval and attempt records; those records are not moved into the media ledger. Status and ordinary discovery load no model and download nothing. Setup is dry-run unless separately authorized; generation cannot install dependencies or change provider silently.

Full listening review remains necessary for actual content. SFX/ambience, music and speech use different content checks; technical metrics cannot certify wanted effects, audible supplied lyrics, speaker resemblance or seamless looping. Keep generated originals intact and disclose clipping/silence rather than hiding them with normalization. Runtime promotion requires current technical, human and target acceptance plus explicit authorization.

## Voice and permissions

Use `build-voice-assets`, `voice-pipeline.sh --help` and the [VOICE contract/examples](../.media/pipelines/voice/PIPELINE.md). Choose preset speech or cloning explicitly. LOCAL uses the verified CustomVoice/Base profile, explicit supported language/preset and bounded autoregressive sampling; diffusion, fixed requested seconds, loops and editing controls are unsupported. Native24000Hz mono metrics retain the declared intrinsic decoder clamp and unmodified output bytes. Metadata does not establish spoken-text, pronunciation or speaker/preset quality; review the complete output.

Cloning additionally requires native task/reference-bound local consent and a separate host local-use record binding the actual purpose and complete reference set. A QA-only scope needs its matching existing bounded native acceptance case. Target promotion requires current distribution/public-use evidence; cloned outputs need a distinct exact-output/reference-bound disclosure grant. Setup and local QA acceptance never supply those grants. CLOUD preset provenance may be staged without authoritative technical acceptance; CLOUD cloning/upload is unavailable under these local-only records.

Voice cloning requires local audio, a matching transcript, rights and recording-bound consent for the requested use. Changed reference bytes, transcript or consent invalidate affected acceptance. Keep private recordings, conditioning, transcripts, generated QA audio and identifying hashes local; public tracking should use a nonidentifying summary. Consent to local QA does not authorize public disclosure or runtime distribution.

Host-only use/lyric permission records and sources travel into the native context as internal immutable policy references. Bubo's existing freshness checks reject changed registered bytes after a wait for ownership. The guard preserves native reference roles, process/GPU limits and shared attempt identity; no public option can replace expected hashes. Unrelated domain contracts remain independent.

Contract/task/Goal creation grants no installation, license acceptance, fresh generation budget, private disclosure or asset promotion. Preserve the existing approval identity, physical shared state root and started candidate/revision history across tasks and workspaces. Historical accepted outputs remain historical and do not become new synthesis or listening evidence when imported.

## Selected-engine handoff

Generation planning does not require a fabricated engine. Handoff and promotion do require the actual selected engine, current exact output set, distribution rights and target evidence. Resolve that host's engine and obtain the lifecycle's current review identity, which binds its engine contract, definition and registry:

```bash
bash .opencaw/commands/resolve-engine.sh
node -e "console.log(JSON.stringify(require('./.opencaw/commands/lib/media-pipeline-state.cjs').engineIdentity(process.cwd()), null, 2))"
```

Copy neither an example's zero hash nor an earlier engine identity into an accepted review. A changed engine identity requires refreshed runtime acceptance. The runtime review binds `assetSha256`, all ordered `outputs`, `engine`, `target`, and typed human, distribution and target-evidence sources. Applicable cloned-output disclosure remains an additional gate.

The following are example bounds for one unchanged LOCAL output, not decoder guarantees or generation authorizations. `maxOutputBytes` and `maxAudioSeconds` limit the aggregate candidate, so a multi-output version needs explicit totals. Spatialization must match the brief; VOICE never accepts loop intent.

| Candidate | Target format | Example aggregate limits | Intent |
| --- | --- | --- | --- |
| Four-second SFX | `codecs: ["wav"]`, `sampleRates: [44100]`, `channels: [2]` | `maxOutputBytes: 4194304`, `maxAudioSeconds: 4` | `spatialization: "2d"`, `loopIntent: false` |
| Twenty-second instrumental | `codecs: ["wav"]`, `sampleRates: [48000]`, `channels: [2]` | `maxOutputBytes: 33554432`, `maxAudioSeconds: 20` | `spatialization: "2d"`, `loopIntent: false` |
| Speech within a thirty-second target budget | `codecs: ["wav"]`, `sampleRates: [24000]`, `channels: [1]` | `maxOutputBytes: 16777216`, `maxAudioSeconds: 30` | `spatialization: "2d"`, `loopIntent: false` |

The host admits declared `wav`, `ogg`, `mp3`, `flac`, `opus`, `m4a`, `webm` or `aiff` targets only when actual technical measurements and the selected target evidence agree. This format list adds no encoder, transcoding stage or target-platform support. LOCAL native originals remain WAV. An unsupported import/decoder or spatialization profile stays blocked; do not silently convert, downmix or alter the original.

| Host's selected owner | Required actual target observations |
| --- | --- |
| [THREEJS audio service](../.engine/THREEJS.md#audio) | Browser/device identity, actual decode and complete playback, user-gesture unlock and suspend/resume, separate music/ambience/SFX/voice routing, and the declared 2D or positional-listener behavior. Exercise pause, cancellation/restart and scene teardown; verify owned sources/nodes/listeners are stopped or released without affecting another asset. |
| [UNITY audio owner](../skills/unity-build-audio/SKILL.md) in a UNITY host | Resolve the compatible owner in that host; preserve its locked Editor, package and player target. Record actual clip import, mixer/voice budgets, 2D/3D configuration and complete audible player playback. Exercise interruption, pooled reuse, scene unload, pause/resume and resource ownership on representative devices. Editor/headless success or a browser build alone cannot certify native playback. |

The UNITY example does not select UNITY in a THREEJS project or install an Editor, middleware or package. Other engines retain their compatible owners. These workflows produce staged assets and evidence contracts, not a portable engine player. Engine-owned audio scheduling, cleanup, accessibility cues and load/dispose behavior must be implemented and reviewed in the host. Playback callbacks never authorize damage, targeting, movement or other gameplay outcomes.

Record actual target source evidence in the domain's runtime form: `opencaw-audio-runtime-evidence/v1`, `opencaw-music-runtime-evidence/v1` or `opencaw-voice-runtime-evidence/v1`. It binds task, current engine identity, exact outputs, spatialization, loop intent, playback/load-dispose observations and a typed source. AUDIO/MUSIC loop intent additionally requires actual seam review. Synthetic forms, a waveform, a successful API call or the admission examples above cannot certify those observations. If the selected browser/player, importer or listening evidence is unavailable, retain an explicit blocked/not-run result and keep handoff/promotion blocked while planning and staged content review continue.

## Failure and unavailable states

| Observation | Next step |
| --- | --- |
| An unrelated domain contract is missing | Continue with configured domains; configure the missing domain only when requested |
| The selected domain reports unavailable execution | Use its reported prerequisite; do not infer readiness from its declaration |
| A requested provider, installation or native capability is unavailable | Stop that execution path and report the concrete gap; preserve existing work |
| Policy, source, output or reference bytes changed | Create retained-ancestry evidence and refresh affected reviews |
| A prior candidate/revision allowance is exhausted | Preserve the ledger and request an explicitly bounded authorization |
| Target codec/budget/engine evidence is missing | Keep assets staged and leave promotion blocked |

Never switch to another provider or pipeline automatically after a selected execution path fails.
