---
name: memory-candidate-review
description: Evaluate whether a discovered fact is durable enough to promote into host repository memory.
---

## When to use
Use before writing new durable memory.

## Decision criteria
Promote only if the fact is:
- likely useful in future work
- architectural, procedural, or recurring
- not just raw task chatter

## Output
- promote or reject
- target file if promoted
- concise normalized memory entry
