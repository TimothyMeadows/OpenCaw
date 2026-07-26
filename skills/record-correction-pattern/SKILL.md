---
name: record-correction-pattern
description: Record a user correction as both a memory pattern and a preventive rule in the host repository.
---

## When to use
Use after a user correction reveals a reusable lesson.

## Commands
../commands/append-project-memory.sh --tags "kind:convention,topic:corrections,<relevant-area-or-tech-tag>" --entry "<pattern>"
../commands/append-rules.sh "<preventive-rule>"
