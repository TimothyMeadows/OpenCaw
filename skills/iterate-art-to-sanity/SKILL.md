---
name: iterate-art-to-sanity
description: Iterate generated images until they pass mandatory sanity rules for anatomy, text quality, language alignment, and safety.
---

## When to use
Use when generated images need quality gating before acceptance or delivery.

## Output
- sanity checklist outcome per image candidate
- failed checks with targeted prompt corrections
- final accepted image reference after all checks pass

## Notes
- Required fail conditions:
  - extra hands or anatomy artifacts
  - duplicated/malformed letters in rendered text
  - text language mismatch vs required language
  - nudity
  - graphic violence
- Continue iterating until all sanity checks pass.
