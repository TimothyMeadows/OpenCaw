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
