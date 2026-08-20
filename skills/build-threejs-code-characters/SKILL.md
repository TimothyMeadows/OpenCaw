---
name: build-threejs-code-characters
description: Author source-native Three.js characters, creatures, and runtime actors through the CODE pipeline's character profile, six ordered gates, independent review, and deterministic evidence. Use when an actor's silhouette, anatomy, articulation, skinning, animation, attachments, contacts, or lifecycle behavior needs character-specific production beyond a generic procedural model.
---

# Build Three.js Code Characters

## When to use

- The resolved art pipeline is `CODE` and the requested model is a character, creature, animated actor, enemy, NPC, avatar, mount, or other embodied runtime subject.
- The source must expose stable semantic parts, anchors, motion ownership, and disposal without a downloaded or generated runtime mesh.
- Use `build-threejs-code-models` directly for props, vehicles without actor behavior, environments, and other generic procedural models.

## Workflow

1. Read `STYLE.md`, resolve `CODE`, and follow `build-threejs-code-models` plus the CODE pipeline contract. Never install or bundle Three.js.
2. Freeze the character brief, presentation context, semantic graph, motion mode, and budgets using [design-contract.md](references/design-contract.md).
3. Create and validate the generic code-model manifest, then create the linked code-character profile. Keep profile creation source-independent.
4. Author the model in generic pass order. Apply the character-specific acceptance gate paired to each pass from [build-gates.md](references/build-gates.md).
5. For reviewer gates, prepare an answer-neutral packet and invoke `review-threejs-code-characters` with an identity outside the active builder set. For machine gates, follow [evidence-adapter.md](references/evidence-adapter.md), require calibrated passing and failing fixtures, and stop if the required measurement adapter is unavailable.
6. Record the character-gate result before recording a passing generic CODE review for that pass. Change strategy after failure and follow [failure-recovery.md](references/failure-recovery.md).
7. For articulated or skinned work, apply [rig-animation.md](references/rig-animation.md) before accepting interaction or optimization.
8. Run complete validation for both linked artifacts and representative host build/runtime checks, including repeated create, update, animation, attachment, and dispose cycles.

## Output

- Host-native Three.js TypeScript or JavaScript with a stable factory, semantic parts and anchors, deterministic inputs, and explicit cleanup.
- A complete generic code-model manifest and linked `opencaw-code-character/v1` profile.
- Immutable gate evidence, independent reviewer packets where required, calibrated machine results, and explicit residual risks.

## Guardrails

- Do not use an external mesh, model library, generated asset, or downloaded actor as the primary runtime implementation.
- Do not let a builder review the same concrete cycle, disclose intended answers to a reviewer, fabricate machine evidence, or mark aesthetic judgment as machine-approved.
- Do not skip, rename, append, make optional, or reorder the six character gates.
- Do not silently change the selected pipeline, motion mode, source contract, presentation scale, or budgets.

## Commands

- `./commands/create-code-character-profile.sh CHARACTER_ID --manifest MANIFEST --brief TEXT --intended-use TEXT [options]`
- `./commands/validate-code-character-profile.sh [--strict|--complete] PROFILE.json`
- `./commands/record-code-character-gate.sh PROFILE.json --gate GATE --decision DECISION --summary TEXT --strategy TEXT --evidence KIND=FILE [options]`
- `./commands/measure-code-character-evidence.sh analyze PROFILE.json --measurements FILE --output REPORT.json [--compare REPORT.json]`
- `./commands/measure-code-character-evidence.sh capture PROFILE.json --adapter ADAPTER.mjs --output-dir DIR [options]`
- `./commands/record-code-model-review.sh MANIFEST.json --pass PASS --decision pass --summary TEXT --character-profile PROFILE.json --evidence VIEW=FILE ...`
