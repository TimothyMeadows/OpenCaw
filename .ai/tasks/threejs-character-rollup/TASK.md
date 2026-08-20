# Land the completed Three.js character stack on main

## Status

Implementation and exact-head validation are complete. The corrective PR is ready for review and human-controlled merge.

## Goal

Land the already reviewed final character integration head on `main` after the preceding stacked PRs were merged into intermediate branches.

## Scope

- Preserve the implementation at reviewed integration SHA `5322365871b3125fb6d06aa753b33e09ab73a6e3`.
- Target the corrective roll-up PR directly at `main`.
- Add only this task's tracking and validation evidence beyond the reviewed implementation.
- Close the parent and remaining task issues when the corrective PR is human-merged.

## Root Cause

The dependent PRs retained their intermediate base branches. GitHub marked them merged, but their heads did not become ancestors of `main`.

## Verification

- Prove the reviewed heads of PRs #118–#120 are absent from current `main` before correction.
- Prove a conflict-free merge tree between current `main` and the corrective branch.
- Run the focused character contract, skills, evidence, and integration suites.
- Validate README, skills, roles, art pipelines, memory, repository-map freshness, and `git diff --check`.
- Confirm the PR targets `main` and contains the expected cumulative delta.

## Issue

https://github.com/TimothyMeadows/OpenCaw/issues/121
