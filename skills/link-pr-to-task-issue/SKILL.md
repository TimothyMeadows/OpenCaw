---
name: link-pr-to-task-issue
description: Ensure pull requests are explicitly associated with the task issue using GitHub closing keywords.
---

## When to use
Use when preparing, updating, or reviewing a pull request for task-backed work.

## Output
- PR body updated with issue closing reference
- explicit traceability from issue to implementation PR

## Notes
- Prefer `Closes #<issue-number>` in the PR body.
- If the link is missing, add it before final review.
- This skill runs after the PR readiness gate and user approval. Do not use it as permission to push or create a PR.
- For PR body reads/updates, prefer `gh` first, then an available `github` CLI executable or repository-provided GitHub CLI wrapper, then GitHub MCP/app connector tools only when both CLI options are unavailable or unsuitable.

## Command
../commands/link-pr-to-task-issue.sh "<issue_url_or_number>" [pr_number_or_url]
