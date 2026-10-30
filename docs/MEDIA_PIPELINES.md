# Independent media pipelines

Load audio, music and voice workflows alongside the selected visual pipeline. Their contexts are independent, so a task can plan an effect, a soundtrack and speech without changing STYLE.md or another media domain's selection.

| Work | Domain | Optional host contract |
| --- | --- | --- |
| Game sound effects and ambience | AUDIO | AUDIO.md |
| Instrumental and supplied-lyric music | MUSIC | MUSIC.md |
| Preset speech and consented local-reference cloning | VOICE | VOICE.md |
| Images and models | Existing visual pipeline | STYLE.md and the applicable visual workflow |

Ordinary audio/SFX/ambience work routes to AUDIO; music routes to MUSIC; spoken voice routes to VOICE. Mixed requests become separate domain-owned work items. Explicit contradictory domains or unsupported modalities are errors. This routing does not choose a provider: MEDIA.md remains the shared authority for CLOUD/LOCAL availability, rights, budgets, staging and promotion.

## Configure and inspect

The shared foundation supplies domain declarations, optional contract generation/validation and independent context resolution. AUDIO and MUSIC supply their complete command workflows; VOICE remains declared until its domain implementation is delivered. Resolve configuration and readiness separately: a valid contract or model receipt does not certify an executable installation or successful generation.

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

LOCAL work uses the pinned, explicitly built Bubo runtime through the existing media adapter. Bubo owns exact model/tool pins, verified installation, synthesis, bounded workers and GPU ownership. Independent context loading does not grant simultaneous GPU inference. Status and ordinary discovery load no model and download nothing. Setup is dry-run unless separately authorized; generation cannot install dependencies or change provider silently.

Full listening review remains necessary for actual content. SFX/ambience, music and speech use different content checks; technical metrics cannot certify wanted effects, audible supplied lyrics, speaker resemblance or seamless looping. Keep generated originals intact and disclose clipping/silence rather than hiding them with normalization. Runtime promotion requires current technical, human and target acceptance plus explicit authorization.

## Voice and permissions

Voice cloning requires local audio, a matching transcript, rights and recording-bound consent for the requested use. Changed reference bytes, transcript or consent invalidate affected acceptance. Keep private recordings, conditioning, transcripts, generated QA audio and identifying hashes local; public tracking should use a nonidentifying summary. Consent to local QA does not authorize public disclosure or runtime distribution.

Contract/task/Goal creation grants no installation, license acceptance, fresh generation budget, private disclosure or asset promotion. Preserve the existing approval identity, physical shared state root and started candidate/revision history across tasks and workspaces. Historical accepted outputs remain historical and do not become new synthesis or listening evidence when imported.

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
