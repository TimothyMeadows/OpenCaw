# Shared media asset lifecycle

AUDIO, MUSIC and VOICE share host lifecycle rules while keeping their contracts, asset versions and reviews independent. Their domain declarations are indexed in [INDEX.md](INDEX.md). Visual production keeps its existing STYLE.md selection and workflow state.

This contract defines the shared foundation. Domain declarations can be loaded before their full production commands are available. A declaration, valid host contract or registered model does not establish executable workflow readiness; inspect the resolved context's `executionAvailable` and `unavailableReasons` fields. The initial foundation declarations report execution unavailable.

The foundation's handoff and promotion primitives produce guarded admission plans. They do not copy files into runtime assets. A domain executor must perform a separately authorized write only after that admission; do not describe an admission plan as a completed promotion.

## Ownership

OpenCaw owns domain routing, host policy, task state, input rights and consent, staged-asset ancestry, review and runtime promotion. LOCAL execution stays behind the verified [Bubo media adapter](../../commands/bubo-media.sh). The pinned Bubo dependency owns model and tool identities, installation verification, synthesis, native process limits, cancellation, GPU ownership and atomic generation-attempt accounting. This layer creates no separate inference implementation or attempt allocator.

Loading visual, AUDIO, MUSIC and VOICE contexts together does not permit simultaneous GPU inference. A domain-local state directory must never become a separate native approval ledger. Keep the same physical shared media-state root for an approval identity across tasks, domains, revisions, restarts and workspace changes.

## Identity and storage

Each asset version binds the task, domain, original asset name, version, modality and brief to its policy and input identities. Each dispatched run additionally retains the actual provider, native request, runtime/build/settings and staged output identities. Keep host state below:

```text
.opencaw/.cache/tasks/<task>/media/<audio|music|voice>/
```

Keep generated media in the workflow's versioned non-runtime staging location. Domain state and native execution state remain separate. Native request IDs and resulting native output paths must include a collision-safe identity for domain, asset and version; a plain human name such as `candidate` is insufficient. Current native IDs are limited to 80 characters matching `[A-Za-z0-9][A-Za-z0-9._-]*`. Preserve the original human names separately and allocate a fresh version/request identity for a revision.

Do not overwrite originals, used request identities, generation receipts, failed attempts or prior reviews. A source or policy change creates new versioned evidence and invalidates affected downstream acceptance. Concurrent writes to the same asset version must serialize or fail without partially replacing its state.

## Policy and freshness

The selected domain context binds its declaration and host contract, applicable shared MEDIA.md policy and supported modality. A domain's identity must not depend on another domain's declaration or contract. A VOICE-only change therefore does not invalidate an unrelated AUDIO review. Changes to shared MEDIA/provider policy invalidate all affected consumers.

Retain explicit file references and hashes for the brief, rights, supplied lyrics, local voice reference/transcript/consent and other applicable inputs. Revalidate current bytes and policy before downstream operations. A hash proves identity, not the truth of a rights assertion, speaker consent or acoustic judgment. Never rewrite historical approvals to make them current.

## Stage boundaries

| Stage | Required result | Authority it does not grant |
| --- | --- | --- |
| Initialize and plan | Task-owned domain/asset/version, supported brief, source references and finite bounds | Model loading, installation, generation or human acceptance |
| Status and doctor | Current configuration, evidence freshness and concrete unavailable prerequisites | Setup, inference or a successful installation claim from receipt presence |
| Setup plan | Explicit pinned dependency/installation plan and applicable license prerequisites | Downloads, license acceptance or execution without separate authorization |
| Generate or import | Explicit provider selection and authorization, current inputs, bounded execution or actual provider provenance, immutable staged outputs | Automatic listening acceptance, public disclosure or runtime promotion |
| Technical validation | Supported measured format/duration/sample rate/channels/size/peaks/clipping/silence and truthful unavailable markers | Content quality, speaker match, audible lyrics or a seamless loop |
| Human review | Supplied human reviewer, verdict, reason and source evidence bound to the complete exact candidate and brief | Review of changed output, target-engine acceptance or promotion |
| Runtime handoff | Target codec and budgets, loop/spatialization intent, load/dispose ownership and actual target evidence | Gameplay authority or automatic installation into runtime assets |
| Promote | Current technical/content/target evidence and explicit promotion authorization for exact bytes and destination | Overwriting another asset, exposing private media or accepting future revisions |

These boundaries are common requirements. An unavailable domain stage must report its missing prerequisite rather than advertise a successful executable operation.

LOCAL dispatch must use the current verified Bubo runtime and existing host admission. Preserve its explicit supported settings, offline execution, shared GPU ownership, claim history and cancellation controls. Generation never provisions tools or models. CLOUD requires an explicitly available selected capability and real provenance; unsupported unattended execution must stop instead of changing provider.

## Foundation implementation interface

The host-only [media-pipeline-state.cjs](../../commands/lib/media-pipeline-state.cjs) module supplies these shared APIs. All file arguments are confined to the explicit project root. File identities use `{path, sha256}` with project-relative paths; the module rechecks current bytes. Records are bounded JSON, asset versions are immutable, and event writes use an exclusive per-version lock and a hash-linked sequence.

Domain validators remain responsible for applicable rights/consent, supported settings and actual technical analysis before using these generic primitives. Importing a report records its explicit evidence; the shared state module does not listen to audio, measure a waveform or establish consent from a file hash.

| API | Inputs and result |
| --- | --- |
| `init` | Takes `root`, existing `task`, `domain`, explicit `modality`, original `asset` name, safe `version` and a project-relative JSON `brief` path; optional `references` and `parent` are file identities. Returns `stateFile` and the asset record. The domain contract must already be configured. |
| `status` | Takes `root` and `stateFile`; returns domain/version/request identity, current `assetSha256` fingerprint, stale reasons, execution readiness, stage and review status. It creates no files. |
| `nativeRequest` | Takes the state plus a native request object, explicit `provider: 'LOCAL'`, cache-local `workspace` and physically shared `mediaState`; returns the owned native request and final state/output paths without dispatching. Shared MEDIA policy must exist. |
| `dispatch` | Uses the same inputs plus optional whitelisted `controls`, requires `executionAvailable`, saves the native request/start event and invokes the existing Bubo adapter. Retained starts prevent a fresh rerun of the same version even after failure. |
| `recordCandidate` | Takes a provider-neutral manifest path and explicit `LOCAL` or `CLOUD` provider. Reuses the existing manifest validator, binds every exact staged output and records pending review. Replacing that candidate requires a new version. |
| `recordTechnical` | Imports an `opencaw-media-technical/v1` report with the current asset fingerprint, exact ordered output identities, explicit check verdicts/reasons and any measured output properties. Unavailable or failed checks cannot produce a passed report. |
| `recordReview` | Imports an `opencaw-media-review/v1` content or runtime review with the current fingerprint/output set, accepted/rejected verdict, reviewer, reason and a distinct source-evidence file identity. Runtime review also binds the current engine identity. |
| `admitHandoff` | Requires current passed technical, accepted content and accepted runtime evidence. Validates target format/rate/channel/duration/byte budgets, measured outputs and a fresh scoped assets destination, then returns a plan with `promotion: false`. |
| `admitPromotion` | Requires handoff admission plus an `opencaw-media-promotion/v1` authorization binding the current fingerprint, exact outputs and target, authorizer, reason and source evidence. Returns an admitted plan; it performs no runtime copy. |

Use `status.assetSha256` for a technical report, review or promotion authorization's `assetSha256`: this is the current composite asset/policy/candidate fingerprint, not the hash of `asset.json` or an audio file. Evidence must bind all current outputs in the recorded order. A revision's parent must identify the same task, domain and asset with a different version.

`init` also binds a project-confined non-runtime `stagingRoot` (default `.art-staging/media/<domain>`), optional explicit `contract`/`media` selections and typed references nested in its brief. A LOCAL workflow supplies its workspace staging child explicitly. Candidate bytes must stay beneath that declared root. Typed brief, provenance, technical and review references are rehashed with the outputs; mutating a referenced file cannot preserve an old review merely by leaving its containing JSON unchanged.

`recordCandidate` accepts one `manifest` or the complete ordered `manifests` array emitted by a native batch. After this version starts LOCAL dispatch, only its exact successfully returned provenance, original source-request identity and native output subtree can become its candidate; another asset's output and a provider switch are rejected. LOCAL import without this version's dispatch requires explicit `origin: historical-import` or `external-import`. Status retains `executionOrigin`, original `sourceRunIds` and a distinct `nativeDispatchRequestId`, which is null for import-only history. The version-owned `nativeRequestId` is not a claim that an imported output was newly generated.

Promotion authorization requires an exact typed `{path, sha256}` `sourceEvidence`, which is returned in the admitted plan. A plain source path is insufficient: the assertion's current bytes must remain bound before a later executor performs any runtime write.

Shared `dispatch` accepts only its documented top-level inputs plus a `controls` object. Supported control keys are `timeout`, `max-log-bytes`, `max-private-bytes` and `platform-modules`; they retain the existing adapter's finite bounds and exact flag values. Selected platform-module manifest bytes are retained with dispatch evidence. Protected setup/API/provider-state switches and unknown controls are rejected, rather than ignored or passed through. Bubo still owns native process and module verification.

The native output base is `<workspace>/staging/<domain>`; native admission appends the version's owned request ID. Domain-specific output ownership must not change `mediaState` into a new per-domain budget root. The foundation APIs enforce host workflow admission; they do not claim an OS sandbox or independently verify a listener's judgment.

## Review and promotion

Listen to the complete candidate. AUDIO review covers the intended event or ambience, unwanted speech/music, artifacts and head/tail. MUSIC review covers the entire track, instrumental versus vocal intent and every supplied lyric line when applicable. VOICE review covers exact spoken content, pronunciation, artifacts and the declared preset/reference match. A waveform, technical report, fixture or historical verdict is not a new listening review. A loop needs an actual seam review before it is accepted as a loop.

Technical reports preserve native amplitudes and disclose clipping, silence and unsupported measurements. Do not silently normalize, trim, splice, tile, repair or loop generated originals. Any authorized derivative retains its source ancestry and requires the reviews affected by that change.

Promotion must recheck current hashes, rights/consent, policy, reviews, target limits and explicit authorization. Reject path traversal, aliases, symlinks/junctions, changed bytes, stale evidence and unauthorized overwrite. Missing engine-specific evidence leaves promotion blocked while planning or staged review remains usable. Audio playback never owns authoritative gameplay damage, targeting, collision or action outcomes.

## Voice privacy

Cloning requires local reference audio, a matching transcript, rights and consent bound to that recording's content hash and the intended use before native dispatch. Reject remote references and stale or mismatched evidence. Keep conditioning, recordings, transcripts, private QA outputs and identifying hashes out of public issues, PR bodies and shared memory. Local cloning QA consent does not grant public disclosure, redistribution, runtime use or a different purpose.

Creating a domain contract, task or Goal grants none of installation, terms acceptance, new synthesis allowance, private disclosure or asset promotion. Historical outputs retain their original execution and review identities; replaying compatible evidence creates no new generation or review claim.
