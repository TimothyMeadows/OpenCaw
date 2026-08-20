# Complete Three.js CODE character production and verification

## Flow
- Type: goal
- Automation: enabled
- PR readiness confirmation: automatic
- Post-PR QA: required before next task
- Auto-merge: disabled
- Merge approval: human only

## Outcome

Deliver a complete OpenCaw-native character and creature specialization for the Three.js `CODE` pipeline, including its profile contract, transactional gates, focused builder/reviewer skills, deterministic evidence harness, source-native runtime checks, calibration fixtures, repository integration, and verified stacked PR chain.

## Success Criteria

- All four queued tasks pass their focused and integrated validation.
- Generic `code-model-manifest` version 1 behavior remains backward-compatible.
- Character production cannot complete without current generic validation, required character gates, independent visual review, calibrated machine evidence, and lifecycle proof.
- Static, articulated, and skinned source-native characters are supported without requiring a runtime mesh asset.
- No dependency, installer, service integration, or silent pipeline fallback is introduced.
- Every task PR is automatically published through Goal Flow, receives a same-PR post-publication QA verdict, and remains unmerged with auto-merge disabled.
- The final report records the stacked branch chain, PR order, QA evidence, compatibility proof, and residual risks.

## Constraints

- Keep every issue, task, implementation artifact, commit, PR, test, document, and review note independently authored in OpenCaw terminology.
- Do not include third-party repository identities, links, code, prompts, assets, binaries, examples, service integrations, or publication workflows.
- Preserve the selected `CODE` pipeline, host-owned Three.js dependency, repository confinement, deterministic evidence, and explicit cleanup contracts.
- Use only host-approved tooling already installed by the repository; missing required tooling stops the task.
- Never merge, approve, enable auto-merge, force-push shared branches, or change the delivery base.
- Execute tasks sequentially because each later task depends on interfaces established by its predecessor.

## Task Queue
1. [x] Build the code-character contract and gate state (`.ai/tasks/threejs-character-contract/TASK.md`)
2. [x] Add code-character builder and reviewer skills (`.ai/tasks/threejs-character-skills/TASK.md`)
3. [ ] Add deterministic character evidence and runtime gates (`.ai/tasks/threejs-character-evidence/TASK.md`)
4. [ ] Integrate and document code-character production (`.ai/tasks/threejs-character-integration/TASK.md`)

## Current Task

- `threejs-character-evidence`

## Branch Chain
- Record each task as: `task-name | base: <branch> | head: <branch> | PR: <url> | depends on: <prior task or none>`.
- If a later task requires unmerged work from a previous task, or would likely create merge conflicts when based on the original base branch, branch from the previous task branch or PR head.
- Keep stacked branches ordered so human approval can happen from earliest dependency to latest dependent PR.
- `threejs-character-contract | base: main | head: feature/threejs-character-contract | PR: https://github.com/TimothyMeadows/OpenCaw/pull/117 | depends on: none`
- `threejs-character-skills | base: feature/threejs-character-contract | head: feature/threejs-character-skills | PR: https://github.com/TimothyMeadows/OpenCaw/pull/118 | depends on: threejs-character-contract`
- `threejs-character-evidence | base: feature/threejs-character-skills | head: feature/threejs-character-evidence | PR: pending | depends on: threejs-character-skills`
- `threejs-character-integration | base: feature/threejs-character-evidence | head: feature/threejs-character-integration | PR: pending | depends on: threejs-character-evidence`

## Automation Rules
- Complete one task at a time unless the project-manager lane plan explicitly marks safe parallel work.
- After each task completes local validation, generate PR readiness with `./commands/pr-readiness-check.sh --goal`.
- Automatically push/open a PR for the completed task without asking for human PR readiness confirmation.
- Run post-PR QA immediately after the PR is available.
- Do not advance to the next task until post-PR QA is complete.
- Never merge, auto-merge, approve, or enable auto-merge for goal PRs.
- If a future task depends on a previous task or has likely merge-conflict risk, base the future task branch on the previous task branch or PR head and record that dependency in `Branch Chain`.
- When all goal tasks have completed post-PR QA, generate `GOAL_REPORT.md` with `./commands/create-goal-completion-report.sh "threejs-code-characters"` before asking for human PR approval.
- Stop goal automation on validation failure, PR creation failure, post-PR QA failure, merge conflict, unresolved role ambiguity, or any required product/security decision outside this goal plan.

## PRs

- Task 1: https://github.com/TimothyMeadows/OpenCaw/pull/117
- Task 2: https://github.com/TimothyMeadows/OpenCaw/pull/118

## QA Evidence

- Task 1 PASS: https://github.com/TimothyMeadows/OpenCaw/pull/117#issuecomment-5351851600
- Task 2 PASS: https://github.com/TimothyMeadows/OpenCaw/pull/118#issuecomment-5351973755

## Goal Completion Report
- Generate with `./commands/create-goal-completion-report.sh "threejs-code-characters"`.
- Include PR links in dependency order, branch base/head notes, post-PR QA evidence, and merge-conflict risk notes.
- Use this report for human approval after goal completion; do not merge automatically.

## Review Notes

- Goal execution authorized by the user on 2026-08-19.
- Parent specification: `.ai/tasks/threejs-code-characters/TASK.md`.
- Parent issue: https://github.com/TimothyMeadows/OpenCaw/issues/112
