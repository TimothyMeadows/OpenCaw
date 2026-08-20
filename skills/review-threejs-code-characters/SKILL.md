---
name: review-threejs-code-characters
description: Independently review source-native Three.js characters and creatures against frozen silhouette, form, material, presentation, and runtime questions. Use for a character profile's reviewer gates when the reviewer is isolated from builder history, strategies, intended answers, and prior subjective conclusions.
---

# Review Three.js Code Characters

## When to use

- A `CODE` character or creature reaches the `blockout-readability`, `form-readability`, or `materials-style` reviewer gate.
- A fresh human or agent reviewer can inspect a frozen, answer-neutral evidence packet without sharing an active builder identity.
- Do not use this skill for machine-only structure, runtime, or budget verdicts.

## Workflow

1. Confirm the concrete reviewer identity is not listed in the profile's active builder identities. Stop on overlap or missing identity evidence.
2. Accept only a packet that satisfies [reviewer-packet.md](references/reviewer-packet.md). Reject builder history, intended answers, hidden comparison labels, or unsupported conclusions.
3. Inspect every required view at the declared presentation sizes before isolated parts or implementation details.
4. Answer the packet's frozen questions from visible evidence. Separate observation from interpretation and record uncertainty.
5. Return exactly one decision: `pass`, `revise-spec`, `revise-code`, `request-input`, or `stop`.
6. State the observed answer, concise summary, remaining gaps, and a stable failure class for non-pass decisions. Use [failure-recovery.md](references/failure-recovery.md) for escalation boundaries.
7. Bind the review to the supplied profile, manifest, source, packet, and evidence hashes. Do not approve a different revision.

## Output

- Gate ID and one allowed decision.
- Direct observed answer to each frozen review question.
- Evidence-backed summary, remaining gaps, uncertainty, and non-pass failure class when applicable.
- Reviewer identity and isolation statement, plus exact packet and evidence references.

## Guardrails

- Do not inspect builder chain-of-thought, correction history, intended verdict, strategy rationale, or unpublished target answers.
- Do not rewrite the model, change the profile, choose the builder's next strategy, or record machine-gate approval.
- Do not infer a pass from source inspection alone when required visual or runtime evidence is missing.
- Do not treat personal taste as a defect; tie every judgment to the frozen identity, style, presentation, and question set.
