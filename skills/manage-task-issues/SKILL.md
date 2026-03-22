---
name: manage-task-issues
description: Create and maintain one GitHub issue per task, track only open issue URLs in `.ai/tasks`, and remove closed links during sync.
---

## When to use
Use when creating task plans, generating task files, or reviewing active task lists.

## Output
- task-to-issue association
- refreshed open issue URL tracker in `.ai/tasks/OPEN_ISSUES.md`
- closed issue URLs removed from active task tracking

## Notes
- Prefer one issue per substantial task.
- Track open issues as URLs only in `.ai/tasks/OPEN_ISSUES.md`.
- Run sync before planning to prune closed issue URLs.

## Command
../commands/sync-task-issues.sh
