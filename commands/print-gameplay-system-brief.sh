#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: ./commands/print-gameplay-system-brief.sh [--focus design|ui|feedback]'
}
focus=""
focus_seen=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --focus)
      [[ $# -ge 2 && $focus_seen -eq 0 ]] || { usage >&2; exit 1; }
      focus="$2"; focus_seen=1; shift 2 ;;
    --focus=*)
      [[ $focus_seen -eq 0 ]] || { usage >&2; exit 1; }
      focus="${1#*=}"; focus_seen=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
case "$focus" in
  ""|design|ui|feedback) ;;
  *) echo "Unknown gameplay brief focus: $focus" >&2; exit 1 ;;
esac

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
- Effective ENGINE.md selection and compatible engine feature skills:
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

if [[ -n "$focus" ]]; then
  cat <<'EOF'

## Environment And Scope
- Engine and version:
- Build/revision and runtime surface (native, browser, or device):
- Platform, devices, and input methods:
- Feature/output scope and excluded surfaces:
- Dependencies, budgets, and unavailable prerequisites:
EOF
fi

case "$focus" in
  design)
    cat <<'EOF'

## Player Decisions And Loops
- Intended player experience, audience, and session constraints:
- Meaningful choices, information, risk, and learning:
- Core loop, progression loop, stopping points, failure, and recovery:

## Rules And Balance
- Resources, sources, sinks, costs, caps, and persistence:
- Rules versus tunable ranges; randomness and authority:
- Representative progression paths, exploits, and dominant strategies:

## Design Hypotheses And Playtests
- Hypothesis, target players, scenario, expected behavior, and revision threshold:
- Observation method and competing explanations:
- Observed decisions, player reports, revisions, and untested questions:
EOF
    ;;
  ui)
    cat <<'EOF'

## Layout And Readability
- Persistent/contextual information, hierarchy, and non-color cues:
- Aspect ratios, safe areas, text scale, localization, and touch targets:
- Representative layouts and readability in actual play:

## Navigation And Screen Flow
- Screen/modal lifecycle, exclusive input owner, and pause policy:
- Initial focus, disabled/removed controls, back action, and return focus:
- Device changes, remapping, binding prompts, and text-entry protection:

## HUD And Input Synchronization
- Authoritative snapshot, ordered events/revisions, and race prevention:
- Subscribe/unsubscribe, repeated reopen, player/scene changes, and stale responses:
- Loading, empty, error, disconnected, and reduced-motion states:
EOF
    ;;
  feedback)
    cat <<'EOF'

## Event And Channel Map
- Authoritative event, audience/local player, identity, magnitude, and expiration:
- Animation, VFX, sound, camera, HUD, and actual tactile haptic channels:
- Per-channel priority, intensity/concurrency caps, overlap policy, and equivalents:

## Timing And Cancellation
- Simulation/presentation/audio/device clock and pause/focus behavior:
- Scoped hit-stop ownership and preservation of pause/slow-motion requests:
- Interruption, repeated activation, cancellation handles, scene teardown, and stale callbacks:

## Haptic Capabilities And Results
- Per-player device ownership, capability, enable/intensity settings, and unsupported cases:
- API failures, bounded patterns, stop/cancel, disconnect/reconnect, and no stale replay:
- Adapter-test evidence versus physically observed output on a supported device:
- Missing hardware and blocked/not-run cases with reasons:
EOF
    ;;
esac

if [[ -n "$focus" ]]; then
  cat <<EOF

## Review Evidence Format
For the matching review profile, retain the general review sections and use this
Evidence table. Each row records actual observations; do not mark unrun scenarios
as passed. Missing physical hardware cannot establish tactile output.

| Scenario | Expected | Observed | Status | Evidence | Reason |
| --- | --- | --- | --- | --- | --- |

Validate the completed review structure with:
./commands/validate-gameplay-review.sh --profile ${focus} <report>
Structure validation does not establish gameplay correctness or physical output.
EOF
fi
