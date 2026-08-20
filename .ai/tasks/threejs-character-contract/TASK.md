# Build the Three.js code-character contract and gate state

## Status

Completed in Goal Flow; PR open and post-PR QA passed.

## Flow

Goal Flow: enabled.

## Goal

`.ai/goals/threejs-code-characters/GOAL.md`

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/113

## Scope

- Add the strict `opencaw-code-character/v1` sidecar schema linked to an existing generic code-model manifest.
- Add deterministic create, validate, and gate-recording commands using thin Bash wrappers over one Node command library.
- Add optional `--character-profile` enforcement to generic code-model review recording without changing existing callers.
- Enforce repository-relative paths, real-file hashes, manifest identity, immutable evidence, reviewer separation, strategy change, retry limits, lock serialization, and stale-generation rejection.
- Cover base, strict, complete, security, concurrency, and generic-v1 compatibility behavior.

## Deliverables

- `.styles/.pipelines/code/code-character-profile.schema.json`
- `commands/lib/code-character-cli.cjs`
- `commands/create-code-character-profile.sh`
- `commands/validate-code-character-profile.sh`
- `commands/record-code-character-gate.sh`
- compatible update to `commands/lib/code-model-cli.cjs` and `commands/record-code-model-review.sh`
- focused deterministic contract/state tests

## Acceptance Criteria

- Generic code-model creation, review, validation, and retry behavior remains unchanged without `--character-profile`.
- Complete character validation requires a current linked generic manifest and all required current character gates.
- Self-review, path escapes, symlinks, wrong hashes, stale evidence, unchanged failed strategies, exhausted retries, duplicate result paths, and concurrent lost updates fail closed.
- No dependency, installer, mesh runtime, service integration, or browser requirement is introduced by this task.

## Validation

- Bash syntax and warning-level ShellCheck when available.
- Node syntax and focused contract/state/security/concurrency tests.
- Existing `tests/test-art-pipelines.sh` compatibility regression.
- Command, schema, skill-safety surface, and `git diff --check` validation.

## Branch

- Base: `main`
- Head: `feature/threejs-character-contract`
- Depends on: none

## Review Notes

- This task freezes the schema and gate vocabulary consumed by all later goal tasks.
- Implemented the sidecar profile, six ordered character gates, immutable result hashes, retry/escalation controls, independent reviewer packets, and optional generic-pass enforcement.
- Froze the v1 gate vocabulary as exactly six required pass-bound gates so callers cannot bypass acceptance by renaming, appending, or making a core gate optional.
- Kept profile creation source-independent so the frozen character contract can precede model authoring; any recorded result requires the real source and complete validation rejects stale source, manifest, or profile generations.
- Hardened issue synchronization against subprocess stdin consumption and aligned README validation with the current repository opening so the normal task stack remains reliable.
- Kept unrelated delivery-mode behavior outside this character-contract task.
- Published as https://github.com/TimothyMeadows/OpenCaw/pull/117 with post-PR QA evidence at https://github.com/TimothyMeadows/OpenCaw/pull/117#issuecomment-5351851600.
