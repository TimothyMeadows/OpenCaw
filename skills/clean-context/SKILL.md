---
name: clean-context
description: Clean and compress host-repository context by archiving completed task detail, deduplicating memory/rules/debug notes, and refreshing a high-signal context summary. Use after finishing tasks, before handoff, or when context artifacts become noisy.
---

## When to use
Use when active context has grown noisy and you need to keep only high-signal artifacts for the next session.

## Workflow
1. Verify task changes first.
2. Archive a specific completed task note when needed:
   - `../commands/archive-task-context.sh "<task-name>"`
3. Run full cleanup and summary refresh:
   - `../commands/clean-context.sh`
4. Optionally archive stale active notes:
   - `../commands/clean-context.sh --archive-stale-active --stale-days 30`

## Output
- active items retained
- completed items archived
- memory entries merged
- duplicate rules removed
- debug notes compressed
- recommended context summary refreshed

## Safety rules
- Never delete durable knowledge without archiving first.
- Prefer summarization over destruction.
- Keep `../.ai/MEMORY.md` short and high-value.
- Preserve traceability via `../.ai/TASKS/completed/` snapshot and report files.
