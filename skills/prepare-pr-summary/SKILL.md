---
name: prepare-pr-summary
description: Prepare a structured PR summary for the current host repository changes.
---

## When to use
Use when the user asks to prepare a pull request summary or review-ready description.

## Output
- Summary
- What changed
- Risks
- Validation
- Linked issue references (for example `Closes #123`)
- Deployment / rollback notes when relevant

## Notes
- Ensure each PR is associated with its task issue.
- Prefer closing keywords in the PR body (`Closes #<issue-number>`).
- Use `../commands/link-pr-to-task-issue.sh` when association is missing.
