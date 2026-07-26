---
name: record-debug-resolution
description: Record a reusable bug diagnosis or resolution in detailed debug history and tagged project memory. Use after a verified root cause or fix is likely to help future debugging.
---

## When to use
Use after diagnosing or fixing a bug with lessons likely to recur.

## Command
../commands/append-debug.sh "<debug-resolution>"
../commands/append-project-memory.sh --tags "kind:bug,<relevant-area-tech-or-env-tags>" --entry "<concise-reusable-root-cause>"
