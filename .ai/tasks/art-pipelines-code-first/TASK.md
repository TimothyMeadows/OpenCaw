# Add art pipelines and code-first Three.js models

## Status
BLENDER follow-up published to draft PR #108 and post-PR QA passed.

## Archive
- /mnt/c/Repository/OpenCaw/.ai/archive/tasks/art-pipelines-code-first-20260810T233132Z.md

## Durable Summary
- Goal: Add first-class CLOUD, LOCAL, CSS3, CODE, and BLENDER art pipelines, make CSS3 the default for generated style contracts, and provide quality-gated Three.js code-model and Blender production workflows.
- Review: The original four-pipeline implementation was locally verified, published to draft PR #107, and reopened to add the omitted Blender production path.

## Blender Follow-up

- Add a first-class `BLENDER` contract without conflating authored `.blend` production with the Three.js `CODE` pipeline.
- Reuse the existing Blender 4.5 LTS production skills, scene inspection, Python validation, staging, and review controls.
- Register `blender`, `blend`, and `bpy` as prompt and contract aliases.
- Keep `CSS3` as the default and add `BLENDER` to this repository's allowed alternatives.
- Update role routing, documentation, memory, repository mapping, and focused art/Blender tests.
- Preserve the no-install, immutable-source, explicit-review, and no-silent-fallback boundaries.

## Follow-up Review

- Added `BLENDER` contract selection and `blender`, `blend`, and `bpy` aliases while preserving `CSS3` as the default.
- Added Blender to this repository's allowed pipelines and routed the Blender production role through `select-art-pipeline`.
- Reused the established Blender 4.5 LTS skill/command suite; no new Blender installer or duplicate production skill was introduced.
- Updated README, AGENTS, style/pipeline indexes, memory, rules, repository map, and focused regressions.
- All directly affected art, Blender, media, style, role, command, skill, README, memory, and repository-map checks passed.
- The repository-wide `validate-opencaw.sh` supplemental run timed out after 604 seconds without a verdict; affected suites pass independently.
- ShellCheck is unavailable on this host; Bash syntax validation and `git diff --check` passed.

## Pull Request

https://github.com/TimothyMeadows/OpenCaw/pull/108

Post-PR QA passed on feature commit `c217820b1c02def85037b9e75df1b4b7b2c2bae8` for art-pipeline, Blender, cloud/local media, skill, command, role, README, memory, and repository-map coverage.

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/106
