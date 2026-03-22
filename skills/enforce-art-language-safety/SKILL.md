---
name: enforce-art-language-safety
description: Enforce text language and safety policy for generated images with explicit user-language override handling.
---

## When to use
Use when generated images contain text or when content-safety constraints must be explicitly validated.

## Output
- required language decision (English default or user override)
- safety compliance verdict
- regeneration directives for any failing safety or language checks

## Notes
- Language policy:
  - default to English text
  - if the user specifies another spoken language, generated text must match it
- Safety policy:
  - no nudity
  - no graphic violence
- Combine with iterative sanity checking until compliant.
