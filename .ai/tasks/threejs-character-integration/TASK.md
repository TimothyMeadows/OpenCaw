# Integrate and document Three.js code-character production

## Status

Queued in Goal Flow.

## Flow

Goal Flow: enabled.

## Goal

`.ai/goals/threejs-code-characters/GOAL.md`

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/116

## Scope

- Integrate the character profile, commands, skills, reviewer isolation, evidence harness, runtime gates, and calibration workflow into the CODE pipeline contract.
- Update skill and pipeline indexes, role maps, README, capability ownership, repository map, and verified durable memory.
- Aggregate focused regressions and run the complete affected supported-environment validation set.
- Prove generic CODE and existing rigged-actor behavior remain compatible.
- Generate the Goal completion report with ordered PR and post-PR QA evidence.

## Acceptance Criteria

- All documented commands, paths, trigger descriptions, role mappings, schemas, and validation claims match actual behavior.
- Capability ownership contains only independently authored OpenCaw descriptions and no prohibited identities or artifacts.
- Focused suites and every affected `validate-opencaw.sh` component pass against the final stacked head; unrelated delivery-mode suites remain out of scope.
- Repository map is current, durable memory is deduplicated and tagged, and context cleanup preserves high-signal goal evidence.
- The final PR closes issues #116 and #112, remains unmerged, and receives same-PR post-publication QA.

## Validation

- CODE character, generic art-pipeline, rigged-actor, skill, role, command, README, memory, repository-map, and affected integration validation.
- Shell syntax, Node syntax, ShellCheck when available, and `git diff --check`.
- Live PR topology and same-PR QA verification after automatic Goal publication.

## Branch

- Base: `feature/threejs-character-evidence`
- Head: `feature/threejs-character-integration`
- Depends on: `threejs-character-evidence`
