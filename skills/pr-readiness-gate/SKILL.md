---
name: pr-readiness-gate
description: Stop before pushing or opening a pull request, summarize readiness, and ask the human to confirm they are ready for PR creation.
---

## When to use
Use when implementation and local verification for a task are complete and the next likely action is pushing a branch or opening/updating a pull request.

## Output
- readiness report path
- validation summary and current branch state
- explicit user prompt asking whether they are ready for the branch to be pushed and a PR opened

## Notes
- This is a hard gate: do not run `git push`, create a PR, open a draft PR, update a PR branch, or enable auto-merge until the user explicitly confirms readiness after implementation.
- A general implementation request is not PR approval. Ask again at completion so the human can validate locally.
- Use this gate before any `gh`, `github` CLI/wrapper, GitHub MCP/connector, or publishing skill that could create or update a PR.
- After the user confirms, choose GitHub PR tools in this order: local `gh` first, an available `github` CLI executable or repository-provided GitHub CLI wrapper second, and GitHub MCP/app connector tools only when both CLI options are unavailable or unsuitable.
- After the user confirms and the PR is available, immediately continue with post-PR QA.

## Command
../commands/pr-readiness-check.sh [task_or_issue_ref] [validation_summary_file]
