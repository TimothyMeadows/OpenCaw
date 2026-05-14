---
name: post-pr-qa
description: Run task QA immediately after a confirmed PR is available, then post pass/fail evidence to the PR with inline screenshot references.
---

## When to use
Use after the human has approved PR creation and the PR number or URL has been confirmed as available.

## Output
- QA commands run and pass/fail outcome
- generated report paths
- GitHub PR comment with QA evidence
- inline screenshot URLs in the PR comment when screenshots are part of the evidence
- final user notification that the PR is ready and the agent can move to the next task

## Notes
- Confirm the PR exists first using this GitHub tool priority: `gh pr view`, then an available `github` CLI/wrapper, then GitHub MCP/app connector metadata only when both CLI options are unavailable or unsuitable.
- Start QA immediately after PR availability is confirmed; do not wait for another user prompt.
- Choose the narrowest meaningful QA first, then broaden when risk or repository conventions require it.
- For browser/UI work, generate non-interactive evidence reports and include screenshot URLs in the PR comment.
- Local screenshot file paths do not render inline on GitHub. Upload screenshots or use CI/repository-hosted URLs before posting inline evidence.
- Mirror or link QA evidence to the task issue when a linked issue exists, but the PR comment is the primary post-PR signal.
- Post the PR QA comment through the same GitHub tool priority: `gh` first, `github` CLI/wrapper second, GitHub MCP/app connector last.
- After QA is complete, tell the user whether QA passed or failed, that the PR is ready for review, and that you can continue to the next task if any remain.

## Command
../commands/comment-pr-qa-results.sh "<pr_number_or_url>" "<results_summary_file>" [screenshot_or_artifact ...]
