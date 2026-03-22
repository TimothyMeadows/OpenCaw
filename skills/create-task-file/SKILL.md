---
name: create-task-file
description: Create a detailed task folder and TASK.md, then create/link a matching GitHub issue and track its URL while open.
---

## When to use
Use when a substantial task needs a dedicated instruction file and issue-backed tracking.

## Output
- task file path
- linked GitHub issue URL

## Notes
- The default workflow creates or links a matching GitHub issue.
- Open issue URLs are tracked in `../.ai/tasks/OPEN_ISSUES.md`.
- Use `--no-issue` only for exceptional local-only work.

## Command
../commands/create-task-file.sh "<unique_task_name>" ["Task Title"] [--no-issue]
