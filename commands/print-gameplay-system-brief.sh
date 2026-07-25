#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
# Gameplay System Brief

## Player Contract
- Player fantasy and goal:
- Available verbs:
- Information available before commitment:
- Success, failure, and recovery:

## Rules And State
- Authoritative state:
- State transitions:
- Timing model:
- Randomness and seed policy:
- Persistence and migration:

## Controls And Feedback
- Input actions and remapping:
- Buffering, cancellation, and priority:
- Animation, VFX, audio, camera, and UI events:
- Accessibility alternatives:

## Tuning
- Exposed parameters and ranges:
- Default values and rationale:
- Dominant-strategy risks:
- Difficulty and progression interactions:

## Runtime And Tooling
- Host architecture:
- Content schema and validation:
- Preview, undo, and rollback behavior:
- Frame-time, memory, loading, and asset budgets:

## Verification
- Deterministic unit scenarios:
- Integration scenarios:
- Playtest questions:
- Performance scenes:
- Release evidence and unresolved risks:
EOF
