---
name: comment-issue-test-results
description: Post QA and Playwright verification evidence to the linked task issue, including result summary and screenshot references.
---

## When to use
Use after running QA checks, especially Playwright/browser tests tied to a task issue.

## Output
- issue comment with timestamped test summary
- screenshot/artifact references attached to the issue thread

## Notes
- Include pass/fail outcome, scope tested, and key evidence.
- Prefer screenshot links when available; include local artifact paths when links are not available yet.
- For post-PR QA, prefer `post-pr-qa` and `comment-pr-qa-results.sh` so the PR receives the primary GitHub comment.
- If screenshots must render inline on GitHub, provide HTTP(S) screenshot URLs; local file paths cannot render inline in remote comments.

## Command
../commands/comment-issue-test-results.sh "<issue_url_or_number>" "<results_summary_file>" [screenshot_or_artifact ...]
