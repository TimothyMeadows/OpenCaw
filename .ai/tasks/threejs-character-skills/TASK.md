# Add Three.js code-character builder and reviewer skills

## Status

Queued in Goal Flow.

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
