# Add Three.js code-character builder and reviewer skills

## Status

Completed in Goal Flow; PR open and post-PR QA passed.

## Flow

Goal Flow: enabled.

## Goal

`.ai/goals/threejs-code-characters/GOAL.md`

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/114

## Scope

- Add concise `build-threejs-code-characters` and `review-threejs-code-characters` skills.
- Keep shared CODE behavior owned by `build-threejs-code-models` and move detailed character/reviewer contracts into one-level references.
- Generate matching `agents/openai.yaml` metadata deterministically.
- Route builders to technical-3D, gameplay, and frontend roles and reviewers to QA, game-design, and technical-3D roles.
- Enforce concrete-cycle builder/reviewer identity separation and reviewer-packet isolation.

## Deliverables

- two skill folders containing only required `SKILL.md`, `agents/openai.yaml`, and directly linked references
- parent-skill routing updates
- generated JSON and Markdown role-skill maps
- focused skill, role, trigger-language, safety, and catalog tests

## Acceptance Criteria

- Character prompts trigger the builder skill without stealing generic prop/environment CODE prompts.
- Review prompts trigger the reviewer skill without exposing builder history or intended answers.
- Skill bodies remain concise, imperative, and free of auxiliary README, installation, or history files.
- Role maps are generated and current; a concrete reviewer cannot share an active builder identity.

## Validation

- Skill quick validation and repository skill validators.
- Role map generation check and role-language alignment.
- Trigger separation, reference reachability, safety, and `git diff --check` tests.

## Branch

- Base: `feature/threejs-character-contract`
- Head: `feature/threejs-character-skills`
- Depends on: `threejs-character-contract`

## Review Notes

- Added separate builder and answer-neutral reviewer skills using the canonical skill initializer.
- Kept generic props and environments routed through `build-threejs-code-models` while specializing embodied actor prompts.
- Routed builder ownership to technical-3D, gameplay, and frontend roles; routed reviewer ownership to technical-3D, QA, and game-design roles.
- Froze one-level design, gate, rig/animation, reviewer-packet, and failure-recovery references without executable helpers or auxiliary files.
- Published as https://github.com/TimothyMeadows/OpenCaw/pull/118 with post-PR QA evidence at https://github.com/TimothyMeadows/OpenCaw/pull/118#issuecomment-5351973755.
