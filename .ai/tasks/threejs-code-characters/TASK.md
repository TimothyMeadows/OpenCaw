# Add character-focused Three.js CODE production and verification

## Status

Goal Flow is active. This file is the umbrella specification; execution is tracked by `.ai/goals/threejs-code-characters/GOAL.md` and its four dependency-ordered task files.

## Flow

Goal Flow: enabled.

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/112

## Goal

Add an OpenCaw-native specialization for procedural Three.js characters and creatures while preserving the existing generic `CODE` model workflow. Character work must gain structured design intent, independent visual review, source-native motion verification, calibrated browser evidence, contextual budgets, and fail-closed completion checks.

## User Constraint

- Keep every issue, task, implementation artifact, test, document, and review note independently authored in OpenCaw terminology.
- Do not include third-party repository identities, links, code, prompts, assets, binaries, examples, service integrations, or publication workflows.

## Architecture Decisions

1. Preserve `build-threejs-code-models` as the generic parent skill for procedural props, environments, characters, and other source-native models.
2. Add `build-threejs-code-characters` for character-specific production and `review-threejs-code-characters` for isolated visual and behavioral acceptance.
3. Keep `code-model-manifest` schema version 1 and existing commands backward-compatible. Add a separate `opencaw-code-character/v1` profile linked by repository-relative manifest path and matching `modelId`.
4. Make the character profile the production-readiness authority for character work. Its complete validator must also require the linked generic code-model manifest to pass complete validation.
5. Map character gates onto the existing ordered passes instead of inventing a second pass state machine:
   - `blockout`: frozen identity and silhouette intent;
   - `structure`: body plan, transforms, grounding, joints, symmetry, and attachments;
   - `form`: whole-character and selected-part readability plus seam integrity;
   - `materials`: style, value hierarchy, semantic-part contrast, and material budgets;
   - `interaction`: articulated or skinned motion, animation roles, contacts, sockets, colliders, and teardown;
   - `optimization`: contextual render/runtime budgets, representative counts, determinism, and repeated lifecycle proof.
6. Keep measurements descriptive and calibrated. Do not encode universal aesthetic thresholds; every threshold must name its intended presentation context, rationale, and passing/failing fixtures.
7. Require reviewer separation for visual gates. The reviewer receives a frozen packet containing only the brief, declared question, and evidence; builder history and intended answers are excluded.
8. Add no dependency or installer. Browser verification may use only host-approved Three.js, Playwright, and browser binaries already present. Missing required tooling stops the selected workflow without fallback.

## Character Profile Contract

Create `.styles/.pipelines/code/code-character-profile.schema.json` with strict, closed objects covering:

- identity: schema version, character ID, title, and linked code-model manifest path/model ID;
- intent: character or creature kind, intended use, presentation distance/scale, representative actor count, temperament, identity statement, and signature parts;
- silhouette: primary view, configurable required views, target on-screen size tiers, negative-space intent, asymmetry policy, and whole-character questions;
- structure: coordinate system, pivot and grounding, semantic body plan, joint/part relationships, symmetry groups, attachment graph, sockets, and collider declarations;
- motion: `static`, `articulated`, or `skinned` mode; skeleton identity when applicable; influences; semantic animation roles; looping/root-motion/contact policy; and representative poses;
- budgets: inherited generic budgets plus bones, influences, clips, shader variants, texture bytes, expected simultaneous actors, and optional measured CPU/GPU targets;
- review policy: builder identifiers, independent-review requirement, configurable attempt limits, repeated-failure limit, and allowed gate decisions;
- ordered gates: stable IDs, owning parent pass, machine or reviewer type, explicit claim/configuration, calibration references, attempts, immutable results, and current status.

The profile must use repository-relative normalized paths, reject symlinks and escapes, hash all evidence, and bind complete state to the current linked manifest hash.

## Commands

Add thin Bash wrappers over one deterministic Node command library:

- `create-code-character-profile.sh CHARACTER_ID --manifest MANIFEST [options]`
- `validate-code-character-profile.sh [--strict|--complete] PROFILE`
- `record-code-character-calibration.sh PROFILE --gate GATE --passing REPORT --failing REPORT [options]`
- `record-code-character-gate.sh PROFILE --gate GATE --decision DECISION --summary TEXT [options]`
- `measure-code-character-evidence.sh analyze PROFILE --measurements FILE --output REPORT [--compare REPORT]`
- `measure-code-character-evidence.sh capture PROFILE --adapter ADAPTER.mjs --output-dir DIR [options]`

Extend `record-code-model-review.sh` with an optional `--character-profile PROFILE`. Existing calls remain unchanged. When present, a `pass` decision is accepted only after every required character gate owned by that pass is current and passing.

## Evidence and Review Model

- Define a test-only browser adapter that exposes the created model instance, semantic `parts` and `anchors`, motion metadata, pose/animation controls, render state, and lifecycle counters without changing the production factory interface.
- Capture profile-selected orthographic and contextual views at deterministic camera, lighting, viewport, seed, pose, and renderer settings.
- Produce full renders, semantic-part masks, low-resolution readability renders derived from intended on-screen size, isolated-part views where context remains meaningful, runtime captures, and machine-readable reports.
- Record configuration, adapter, source, linked manifest, evidence, and comparison hashes.
- Support hash-bound revision comparisons that record prior source and machine-gate decisions without revealing or manufacturing a subjective target. A numeric result cannot independently approve an aesthetic gate.
- Build reviewer packets with only the frozen intent/questions and relevant evidence. Record reviewer type, invocation or human decision identifier, verdict, observed answer, remaining gap, packet hash, and evidence hashes.
- Reject reviewer identity overlap with the active builder identity set for the same acceptance cycle.

## Machine Gates

Implement fail-closed checks for:

- semantic parts and anchors promised by the profile;
- finite transforms, stable coordinate system, pivot, grounding, and bounds;
- declared attachment, socket, and collider resolution;
- attachment proximity and disconnected or floating parts using scale-relative tolerances declared by the profile;
- mirrored-part volume or bound divergence beyond an explicitly calibrated tolerance;
- deterministic construction from the recorded seed;
- motion-mode consistency, finite normalized skin weights, maximum influences, skeleton identity, required semantic animation roles, representative pose availability, and sampled deformation bounds;
- configurable action/contact displacement relative to the acting part or actor, without hard-coding one combat vocabulary;
- generic and character-specific budgets at representative actor counts;
- repeated create, update, animation switch, attach/detach, dispose, and scene-transition behavior without stale listeners or unbounded resource growth.

## Failure and Retry Policy

- Every non-pass result records a stable `failureClass`, strategy summary, and strategy fingerprint.
- Reject an unchanged strategy after a failure.
- When the same failure class occurs twice on one gate, require a material spec/structure revision, `request-input`, or `stop`; do not permit another local tweak with the same approach.
- Preserve the generic maximum of three attempts per pass and twelve attempts overall unless a stricter character profile is selected.
- Do not allow a later passing gate to reuse evidence or reviewer packets from a different source, manifest, profile, strategy, or pass generation.

## Skill Design

### `build-threejs-code-characters`

- Keep `SKILL.md` concise and route shared CODE selection, manifest, source ownership, evidence hashing, budgets, and disposal rules to `build-threejs-code-models`.
- Put the detailed character production contract in one directly linked reference file.
- Trigger only for source-native procedural Three.js characters or creatures under the `CODE` pipeline.
- Require profile creation before authoring and required gate completion before passing each parent pass.
- Route visual decisions to `review-threejs-code-characters`; the builder never self-approves them.

### `review-threejs-code-characters`

- Trigger for isolated review of procedural CODE characters, character revisions, or character-profile evidence.
- Read only the frozen reviewer packet and referenced evidence needed for the current gate.
- Distinguish observed evidence, inference, uncertainty, and blocking gaps.
- Never inspect builder reasoning, prior intended answers, or unrelated task history before issuing the verdict.
- Emit the structured gate decision consumed by `record-code-character-gate.sh`.

Generate matching `agents/openai.yaml` metadata deterministically and do not add auxiliary skill README or installation files.

## Role and Routing Changes

- Route `build-threejs-code-characters` to `arts/technical-3d-artist`, `computer-science/gameplay-engineer`, and `computer-science/frontend-developer` where CODE is selected.
- Route `review-threejs-code-characters` to `computer-science/qa-engineer`, `computer-science/game-designer`, and `arts/technical-3d-artist`, while enforcing distinct builder/reviewer identities for a concrete cycle.
- Keep `computer-science/senior-developer` on the generic parent unless character-production ownership is explicitly needed.
- Update the generated Markdown/JSON role-skill maps, skill index, CODE pipeline and indexes, README, and role-language validation.

## Security and Dependency Boundaries

- Never install Three.js, Playwright, a browser, image tooling, or Python packages.
- Use an OS-assigned loopback port only; reject wildcard and non-loopback binding.
- Keep the browser sandbox enabled and use repository-approved browser resolution.
- Constrain served paths and outputs to the resolved project root; reject traversal, alternate drive roots, symlinks, unsupported extensions, and source/output overlap.
- Escape or avoid rendering user-provided text as HTML.
- Serialize concurrent writes to one profile and install gate evidence without clobbering.
- Store task evidence outside runtime asset directories.

## Implementation Order

1. **Contract foundation**
   - Add the profile schema, deterministic Node library, create/validate wrappers, fixtures, and base/strict validation.
   - Prove path confinement, linked-manifest identity, schema closure, and generic-v1 compatibility.
2. **Gate transaction model**
   - Add immutable gate recording, failure/strategy rules, evidence hashing, reviewer separation, locking, and optional profile enforcement in code-model review recording.
   - Prove ordering, stale/reused evidence rejection, retry transitions, and concurrent update safety.
3. **Builder and reviewer skills**
   - Initialize both skills with the repository-local skill layout, concise trigger metadata, one-level references, and deterministic UI metadata.
   - Update role mappings and validate trigger separation and ownership.
4. **Browser evidence harness**
   - Add the review-adapter contract, deterministic view capture, semantic masks, isolated-part support, revision comparison, machine reports, and security controls.
   - Use only already-installed host tooling and stop clearly when unavailable.
5. **Source-native runtime checks**
   - Add structure, attachment, motion-mode, skeleton/skinning, animation/contact, representative-count, determinism, and lifecycle gates.
   - Align reusable actor semantics with `prepare-rigged-runtime-actors` without treating a source factory as GLB/FBX or weakening either contract.
6. **Calibration and end-to-end fixtures**
   - Add independently authored positive fixtures and focused negative fixtures for unreadable silhouette, missing semantic part, floating attachment, broken grounding, invalid rig/weights, ineffective motion, budget failure, stale evidence, self-review, repeated strategy, and disposal leakage.
   - Require the calibration set to demonstrate separation before accepting machine gates.
7. **Documentation and repository context**
   - Update indexes, README, CODE contract, role maps, capability ownership, repository map, and durable memory only after behavior is verified.
   - Keep documentation focused on OpenCaw contracts, usage, boundaries, and verification.

## Verification Plan

- `bash -n` for every new or changed Bash command.
- `node --check` for every new or changed JavaScript command library or browser harness.
- Warning-level ShellCheck for changed shell files when available.
- Focused character-profile schema, state-machine, security, concurrency, and browser-adapter tests.
- Existing `tests/test-art-pipelines.sh` unchanged-behavior regression.
- Rigged-actor regression to prove the existing GLB/FBX contract is not weakened.
- `commands/validate-skills.sh` and skill-specific safety/language checks.
- `commands/generate-role-skill-map.sh --check` and role-language alignment validation.
- `commands/validate-commands.sh`, README validation, memory validation, and repository-map status.
- Full `commands/validate-opencaw.sh` in the supported environment.
- `git diff --check` and an explicit comparison showing generic CODE behavior is unchanged.

## Acceptance Criteria

- Generic code-model users can continue using the existing manifest and commands without character fields or behavior changes.
- Character work cannot reach complete state without current linked generic validation and all required character gates.
- A builder cannot self-approve a visual gate, and stale or cross-generation evidence cannot satisfy a gate.
- Every trusted machine check has deterministic positive and negative calibration evidence.
- Character profiles support static, articulated, and skinned source-native implementations without requiring a runtime mesh asset.
- Missing browser or host tooling stops the workflow and never triggers installation or pipeline fallback.
- Representative runtime and repeated lifecycle checks enforce the declared budgets and cleanup contract.
- All affected and integrated OpenCaw validation passes before PR readiness is requested.

## Dependencies and Parallelism

- Contract foundation is the critical-path prerequisite for every later step.
- After the schema and gate vocabulary freeze, skill/role work and browser-harness work may proceed independently with disjoint files.
- Runtime checks depend on the browser adapter and gate-recording format.
- Calibration fixtures depend on all machine gates being interface-stable.
- Documentation and memory updates occur after behavior and terminology are frozen.
- No subagent execution is authorized by this planning task; any later parallel plan must resolve roles, write sets, dependencies, and verification before delegation.

## PR Boundary

Each validated child task uses Goal Flow readiness, automatic PR publication, and immediate post-PR QA. No task or goal automation may merge, approve, or enable auto-merge. The final integration PR closes this parent issue after every queued task has passed post-PR QA.
