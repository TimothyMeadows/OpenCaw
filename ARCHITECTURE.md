# ARCHITECTURE.md

This file is the canonical architecture contract for this repository.

Generated from OpenCaw architecture templates:
- MARKDOWN
- DOTNET

---

This document intentionally stays concise by referencing selected templates.

## Read Template Instructions

Read `./.architecture/MARKDOWN.md` instructions
Read `./.architecture/DOTNET.md` instructions

Add repository-specific architecture instructions below these read directives.


## Native asset orchestration

The standalone .NET 10 execution runtime is the exact Git submodule at `runtime/bubo`, pinned by its parent gitlink and `runtime/bubo.lock.json`. Read Bubo's own `ARCHITECTURE.md` for its inward domain/application/infrastructure layering. Bubo owns execution algorithms, fixed audited scripts, resources and native process ownership. Native subprocesses are bounded, cancellable and logged; cooperative file guards are not an OS sandbox.

OpenCaw owns host policy, engine/style/media selection, source rights and consent, task/publication controls and separate asset acceptance. Thin Node adapters in `commands/lib/bubo-*.cjs` supply explicit hash-bound host context to an explicitly built Bubo CLI. Verify the dependency revision, API, build receipt and audited resources on each invocation. Production never runs source, substitutes a sibling checkout, builds or installs dependencies implicitly. Scaffold/memory/policy startup remains usable without the runtime initialized.

Proof reconstruction, animation and action composition use this single execution boundary. Read-only Blender inspection uses an explicit inspection policy receipt without selecting an engine or art style. Motion data, authoring and selected-engine presentation remain separate; action sequencing and effects never own authoritative combat, targeting, movement or projectile outcomes. Historical manifests/approvals retain their bytes; a changed execution or host-policy identity needs a new asset version with retained ancestry and refreshed affected reviews.

LOCAL generated media uses `commands/lib/bubo-media-adapter.cjs` through the same verified runtime and bounded asynchronous execution boundary. The adapter supplies explicit MEDIA policy, typed rights/license/consent references, project-confined roots, finite budgets and immutable dispatch receipts. Image work additionally supplies actual STYLE/selection evidence; audio requires no fabricated visual style or engine. Bubo owns image, SFX, music, preset-speech and consented-cloning algorithms, dependency catalogs, setup/registration verification, GPU serialization and claim accounting. OpenCaw maintains no parallel model pins or inference implementation.

Read-only discovery remains available without an initialized or built runtime and distinguishes advertised capability from installation verification. Setup is dry-run unless explicitly authorized; generation never provisions. Each approval identity remains bound to one shared project-local media-state root across tasks and workspace changes. Provider-neutral manifests retain native output/settings/build ancestry with pending human review. CLOUD contracts and historical evidence remain compatible; runtime promotion and private-media disclosure require separate authorization.

## Independent media production domains

`.media/pipelines/registry.json` defines AUDIO (SFX/ambience), MUSIC and VOICE independently of STYLE's visual primary. `commands/lib/media-pipeline-contract.cjs` owns optional domain contracts, deterministic modality routing and named contexts. Its selected-domain fingerprint includes that declaration/template/host contract and shared MEDIA identity, excluding unrelated domains. Loading contexts creates no contracts, selects no provider and performs no native discovery or inference. Domain execution readiness and native installation readiness are distinct.

`commands/lib/media-pipeline-state.cjs` supplies shared host lifecycle primitives: immutable task/domain/asset/version records, bounded chained events, exclusive writes, exact input/provenance/output identities, stale-review checks and separate handoff/promotion admission plans. Domain executors extend these primitives; foundation admission never copies runtime assets. Native IDs bind domain, task, asset and version within Bubo's existing bounds, while original human names remain separate. Native output paths include Bubo's appended request ID. This namespacing never creates a separate native approval/attempt ledger or replaces Bubo's process/GPU guards. Read `.media/pipelines/LIFECYCLE.md` and `docs/MEDIA_PIPELINES.md` for the host interfaces and review/privacy boundaries.
