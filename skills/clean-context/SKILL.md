---
name: clean-context
description: Clean and compress host-repository context by compacting completed task files, deduplicating memory/rules/debug notes, and refreshing a high-signal context summary. Use after finishing tasks, before handoff, or when context artifacts become noisy.
---

## When to use
Use when active context has grown noisy and you need to keep only high-signal artifacts for the next session.

## Workflow
1. Verify task changes first.
2. Compact a specific completed task note when needed:
   - `../commands/archive-task-context.sh "<task-name>"`
3. Run full cleanup and summary refresh:
   - `../commands/clean-context.sh`

## Output
- task files compacted
- memory entries merged
- duplicate rules removed
- debug notes compressed
- recommended context summary refreshed

## Safety rules
- Never delete durable knowledge without archiving first.
- Prefer summarization over destruction.
- Keep `../.ai/MEMORY.md` short and high-value.
- Preserve traceability via `../.ai/archive/tasks/` snapshots and `../.ai/reports/` report files.
