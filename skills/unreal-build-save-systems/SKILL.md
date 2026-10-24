---
name: unreal-build-save-systems
description: Build Unreal mutable-state persistence with versioned identities, validated migrations, owned asynchronous work and transactional restoration.
engines: [UNREAL]
---

# Unreal Build Save Systems

## When to use

Implement per-player/world mutable state, checkpointing, save migration and restore workflows in an Unreal project. Authored DataAssets/tables and Asset Manager loading remain definition/content concerns; a save references definitions rather than modifying shared packages.

## Activation and inputs

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-save-systems`; require effective `UNREAL` and `compatible: true` before edits or launches. Respect validated task-only output scope. Keep observed project context under `.opencaw/.cache`; game saves use the project's supported platform storage, not OpenCaw task storage.

Inspect Unreal version, platform/user identity, slot/storage policy, authority, data sizes, supported older versions, migration rules and privacy requirements. Select local/platform/cloud storage explicitly; no account setup, third-party service or implicit license acceptance is part of this skill.

## Workflow

1. Read [serialization, migration and restore](references/serialization-and-restore.md). Define versioned value data and stable world/instance/definition identities; do not persist raw UObject pointers, editor labels or transient object paths.
2. Capture consistent state on its owning thread. Separate immutable authored data from mutable values and avoid serializing live actors from a worker. Give every save/load request an owner, user/slot identity and generation.
3. Decode into temporary state, validate type/version/size/ranges/references and migrate supported versions before changing the live world. Reject corrupt, incompatible or future-version data without silently overwriting the user's last valid save.
4. Restore in a defined readiness order and commit validated state at one application boundary. A failed validation, missing required streamed content or cancelled request must preserve the prior live state. Define rollback/compensation for unavoidable side effects.
5. Serialize writes per user/slot, use the chosen platform's supported durability strategy, verify completion and retain recovery policy. Do not claim an engine slot API alone guarantees atomic disk replacement or durable cloud synchronization.

## Verification and output

Deliver reflected value schemas, migration and storage/restore code, sample native round-trip fixtures and explicit recovery behavior. Test supported legacy versions, renamed/missing identities, duplicate entities, invalid ranges, future schemas, malformed/truncated bytes, write failures, slot/user isolation and world travel during an async load. Cancellation may invalidate application even when the underlying platform I/O cannot be cancelled.

Record expected/observed results, native environment and evidence; native serialization tests do not prove platform durability or a complete gameplay restore. Missing matching tools or target storage remain blocked/not-run. Do not fabricate save success or accept a stale callback into a different user/world.
