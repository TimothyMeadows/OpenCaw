# Review complete motions and deliver current evidence

Review the real rig/hierarchy before motion authoring. Inspect fit, weighted joints, separate parts, attachment ownership and extreme poses. Record current human rig approval; automated inventories cannot manufacture it.

Every required clip needs actual meaningful channels, finite samples, intended timing/FPS, loop/root-motion policy and compatible exported bindings. Inspect contact/foot sliding, penetrations, equipment continuity, proportions and loop seams. Swimming animation does not establish buoyancy; a death clip does not supply a ragdoll or authoritative death rule.

Use full-range sampled frame playback plus relevant transition proofs and representative cameras. Record sampling, renderer and coverage. A still, midpoint render or passing manifest is insufficient for motion selection. Fast motion may need denser samples and actual target playback. Retargeted motion needs the same review as authored motion.

For targeted revisions, retain unaffected clips and their `motionSha256` identities and preserve prior attempts. Bind revision to the source motion/rig/recipe identities; changed rig/source interpretation can require a new version. Re-bake/export/review affected outputs and stale prior set acceptance rather than reusing it automatically.

The native `author --revision JSON` record is `{ "schemaVersion": 1, "clip": "existing-ID", "replacement": { /* complete clip specification with the same ID */ }, "reason": "specific defect and intended correction" }`. Supply strict JSON, without the illustrative comment. It requires a complete prior motion stage and current rig approval. Only that existing clip is replaced in the effective recipe and actual previous motion source; profile, rig, budgets and state graph are not revision fields. Fresh motion/bake/export/review attempts replace downstream acceptance while preserving unchanged motion identities and the still-current rig approval. A motion hash records sampled output, not only a clip's label.

The runtime handoff must exercise real import/bindings, transitions, controller/root-motion ownership, pause/frame-rate variation, interruption, copies/pooling, stale callbacks, teardown and target resource budgets. Mechanical fixtures also need actual pivots/wheel response/anchors; ships need real phase-driven effects and cancellation. Simulated process/API fixtures remain labeled and cannot certify these visuals.

Separate motion selection, independent review and human runtime acceptance. Runtime acceptance binds effective engine, model/package hashes and hashed `runtime-test`, `runtime-capture` and `performance-profile` artifacts. CPU submission timings and renderer counters are not GPU timings or target hardware certification. CLI receipts record caller assertions and cannot authenticate a person's identity.

Use `status` for current fingerprints and `validate` before explicit promotion. Preserve failed or interrupted attempts, source/clip provenance and rejection reasons. Any source, rig, clip, mapping, tool, recipe or engine change invalidates the dependent evidence. Missing prerequisites and coverage remain pending/blocked; no fallback, automatic approval or unreviewed runtime promotion is allowed.
