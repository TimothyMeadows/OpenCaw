---
name: use-bubo-local-generation
description: Inspect, explicitly provision or register, and run direct Bubo LOCAL image, SFX, music, preset speech, or consented local-reference cloning with pinned runtime verification, shared budgets, staged provenance and separate human review. Use after LOCAL is selected.
engines: [AGNOSTIC]
---

# Use Bubo Local Generation

## When to use

- The user has selected `LOCAL` for an image or supported audio request.
- Inspecting host/runtime readiness without loading models or installing software.
- Preparing explicit setup or registration, or executing a bounded task-bound media request.

## Workflow

1. Read `MEDIA.md`. For images, also validate `STYLE.md` and resolve `LOCAL`, recording task-local evidence for a prompt override. Audio uses actual MEDIA policy without selecting an engine or inventing a visual style.
2. Inspect with `inspect-local-media-host.sh`. Distinguish a missing/uninitialized/build-unverified runtime, declared capability, receipt presence and fully verified installed content. Discovery never installs, downloads or loads models.
3. Initialize and build the pinned `runtime/bubo` explicitly when required. Use Bubo's media API/catalog as the authority for supported settings, model/tool pins, licenses and platform locks. Do not maintain another model catalog or infer readiness from an advertised backend.
4. Prepare the appropriate setup manifest: provision a fresh declared installation, or verify/register an existing one. New registration receipts belong directly under the selected workspace's `installations/` directory with a `.json` extension, where discovery reads them. Preview through `install-bubo-media.sh` or `bubo-media.sh setup`; use `--execute` only with explicit setup authorization and matching license evidence. Setup does not accept terms or authorize generation/promotion.
5. Prepare a typed generation request with exact installation/rights identities, finite output/time/byte budgets and explicit supported settings. Seeds must be nonnegative JavaScript safe integers (at most `9007199254740991`) so exported provenance stays exact; Bubo's backend-specific limits still apply. Preset speech requires an available preset and language; cloning requires admitted local audio, its exact transcript, source rights and reference-bound consent. Reject remote reference URLs and unsupported/ignored controls.
6. Keep state under the canonical task cache and retain one shared media-state root per approval identity across tasks and workspace changes. Preserve the existing candidate/revision allowance and all started claims; registration and migration never create a fresh budget. Use ordinary `inspect` for no-load verification. Select `inspect --load true` separately for a zero-sample load/unload diagnostic.
7. Generate only the explicitly authorized finite batch through `bubo-media.sh generate`. Bubo owns the verified offline workers, shared GPU lease, cancellation, measured cleanup and actual output checks; production never installs or downloads.
8. Preserve native dispatch/results/settings/build identities and per-output provider-neutral manifests. Keep candidates staged with pending review. Complete image review or full audio listening, then record acceptance/rejection and obtain separate runtime-promotion authorization.

## Output

- Read-only capability/readiness evidence distinguishing declaration, receipt presence and verified installed content.
- An explicit dry-run setup plan or authorized provision/registration receipt, when setup is requested.
- Staged outputs with native settings, installation/build/host-policy ancestry, hashes and per-output provider-neutral manifests.
- Retained shared budget/claim evidence and a pending or recorded human review verdict; runtime promotion remains separate.

## Capabilities

| Capability | Fixed Bubo backend | Required distinction |
| --- | --- | --- |
| Images | `flux-schnell` | Actual STYLE and LOCAL selection evidence |
| Sound effects | `stable-audio-open` | Explicit duration and reviewed loop intent |
| Music | `ace-step-turbo` | Instrumental or supplied-lyric mode; no planning LM |
| Preset speech | `qwen3-tts-customvoice` | Explicit supported language, preset and expression |
| Consented cloning | `qwen3-tts-base` | Exact local reference/transcript/rights/consent; no preset or expression |

Exact versions, dependencies, supported settings and native formats belong to `runtime/bubo/docs/MEDIA.md` and Bubo's audited catalog. Native platform acceptance must be reported separately; a dependency lock or fixture does not establish native inference or human media quality.

## Commands

Examples are relative to the Hephaera installation. Replace paths and manifests with the host's reviewed inputs:

```bash
./commands/inspect-local-media-host.sh --root /absolute/project --json
./commands/install-bubo-media.sh --root /absolute/project --task media-task \
  --manifest .hephaera/.cache/tasks/media-task/setup.json
./commands/bubo-media.sh inspect --root /absolute/project --task media-task \
  --manifest .hephaera/.cache/tasks/media-task/request.json \
  --media-state .hephaera/.cache/shared-media
./commands/bubo-media.sh generate --root /absolute/project --task media-task \
  --manifest .hephaera/.cache/tasks/media-task/request.json \
  --media-state .hephaera/.cache/shared-media
```

`setup` defaults to dry-run. `--execute` applies only to that explicit setup. `--load true` applies only to a selected zero-sample inspection. A retained acceptance approval must always use its already-bound shared media-state path.

Acceptance-bearing requests require that same explicit `--media-state` for inspection and generation. For an image task overriding a different STYLE primary, add `--selection` with the task's current hash-bound LOCAL selection JSON; audio rejects visual selection options.

## Guardrails

- Never install drivers, accept licenses, create accounts, persist credentials or change an external installation implicitly.
- Never switch backend, provider, device, precision or destination silently.
- Never run source, substitute another checkout or build/provision as a production fallback.
- Do not copy, reset, refund or relabel historical claims, approvals, receipts or accepted outputs.
- Do not normalize, repair or replace rejected media without a separately approved operation.
- Keep reference transcripts and conditioning tensors private. Consent to local cloning does not authorize public audio disclosure.
- Technical success, hashes and manifests do not establish human quality review or runtime acceptance. Generation grants no promotion authority.
