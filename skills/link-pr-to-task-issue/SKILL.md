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

## Command
../commands/link-pr-to-task-issue.sh "<issue_url_or_number>" [pr_number_or_url]
