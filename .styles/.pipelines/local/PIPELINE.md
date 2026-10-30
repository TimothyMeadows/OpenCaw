# LOCAL Art Pipeline

## Intent

Produce images, sound effects, music, preset speech and consented local-reference cloning through the pinned standalone Bubo runtime and local GPU. OpenCaw supplies host policy and acceptance; Bubo owns direct offline execution, model/tool catalogs, platform locks, setup/registration verification and shared GPU ownership.

## Inputs

- A selected supported capability and active `MEDIA.md` contract.
- For images, validated `STYLE.md` and actual LOCAL selection evidence. Audio needs no invented style or engine.
- Explicit task, project-local workspace/state/staging/tool/input roots, finite budgets, exact installation identity and applicable rights/license evidence.
- For cloning, exact local reference audio/transcript hashes and reference-bound rights/consent.

## Production Rules

- Use `use-bubo-local-generation`, `inspect-local-media-host.sh` and `bubo-media.sh`; initialize/build the exact `runtime/bubo` dependency explicitly before production.
- Discovery is read-only and startup-safe when the runtime is unavailable. Distinguish declared capability, receipt presence and full installed-content verification. Never load a model during discovery.
- Keep setup dry-run unless explicitly authorized with `--execute`. Preserve Bubo's distinct provision and existing-installation registration schemas. Setup accepts no terms and grants no generation or promotion authority.
- Keep exact model/tool pins and dependency locks in Bubo's audited catalog. Do not duplicate inference logic or model manifests in OpenCaw.
- Use only verified offline workers, explicit supported settings and bounded sequential batches. Generation never installs/downloads, uses remote reference URLs, or silently changes provider/device/precision.
- Retain one shared media-state root per approval identity across tasks and workspace changes. Preserve candidate/revision limits and all started attempts; a one-candidate-plus-one-revision allowance does not reset during migration or registration.
- Keep immutable dispatch/results/settings/build evidence and per-output provider-neutral manifests. Stage and hash outputs before human review; technical checks do not certify visual quality, spoken content, speaker match or music quality.
- Preserve historical receipts, rejected/failed attempts and accepted outputs. Do not inspect, alter or uninstall external installations as part of this migration.
- Stop when selected local execution fails. Do not fall back to CLOUD or another backend silently.

## Output Contract

- Staged generated files with exact output, native settings, installation, build and host-policy ancestry.
- Pending human image review or complete audio listening, with explicit acceptance/rejection reasons.
- Private reference/clone evidence limited to the authorized scope; local cloning consent never implies public disclosure.
- Separate runtime acceptance and explicit promotion. This execution path has no promotion operation.

## Acceptance Checks

Verify current runtime/build and installation identities, rights/licenses/consent, paths, finite budgets, imported settings, actual output format and measured lifecycle cleanup. `inspect --load true` is an explicitly selected zero-sample load/unload diagnostic, not ordinary discovery. Native platform execution and human review remain separate from synthetic fixtures and dependency availability.

Read [Bubo's media API](../../../runtime/bubo/docs/MEDIA.md) for supported backends, settings and setup/request schemas. CLOUD and the shared provider-neutral provenance schema retain their own contracts.

## Role Fit

Use with `generative-media-pipeline-engineer`, `generative-art-designer`, `sound-designer` and `ai-engineer`.
