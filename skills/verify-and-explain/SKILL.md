---
name: verify-and-explain
description: Audit a claim or implementation, prove what can be proven with concrete evidence, and explain the result in clear audience-appropriate language. Use for reviews, validation summaries, change explanations, test reports, and technical findings that must distinguish fact from inference.
---

# Verify And Explain

## When to use

- A user asks whether work is correct, complete, safe, or functioning.
- A technical result must be explained to a non-specialist.
- Review evidence is spread across tests, logs, code, screenshots, or configuration.

## Workflow

1. Restate the claim and define what evidence would prove or disprove it.
2. Inspect authoritative code, tests, logs, artifacts, and runtime behavior.
3. Label each conclusion as verified, contradicted, inferred, or unknown.
4. Resolve contradictions before summarizing; do not average conflicting evidence.
5. Explain the outcome from impact to cause to proof to next action.
6. Match vocabulary and depth to the named audience without removing material risk.

## Output

- A direct result and confidence level.
- A compact evidence list with commands or artifacts.
- Unknowns, residual risk, and the smallest useful next action.

## Guardrails

- Do not present successful command execution as proof of unrelated behavior.
- Do not invent measurements, test results, or causal explanations.
- Use plain language without becoming vague or patronizing.
