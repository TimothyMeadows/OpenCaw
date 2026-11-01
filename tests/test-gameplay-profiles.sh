#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/hephaera-gameplay.XXXXXX")"
cleanup() {
  case "$temp_root" in "${TMPDIR:-/tmp}"/hephaera-gameplay.*) rm -rf -- "$temp_root" ;; esac
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  if "$@" >"$temp_root/rejection.log" 2>&1; then fail "unexpected success: $*"; fi
}

# These are synthetic review documents exercising validation and reporting. They
# do not execute a game, drive native UI, or establish physical haptic output.
general_report() {
  cat <<'EOF'
# Gameplay Review
## Summary
Synthetic fixture demonstrates the reporting boundary; no engine was executed.
## Controls And Accessibility
Fixture covers review records for keyboard, controller, and equivalent cues.
## Gameplay Systems
Expected state ownership is declared; gameplay acceptance remains separate.
## Performance
Runtime measurements were not run because this fixture validates documents.
## Evidence
Fixture documents are available to the test process as local text.
## Risks And Recommendation
Do not infer player experience or device output from this parser regression.
EOF
}

general_report >"$temp_root/general.md"
bash commands/validate-gameplay-review.sh "$temp_root/general.md" >"$temp_root/general.log"
grep -q 'profile=general' "$temp_root/general.log" || fail "legacy invocation lost its general default"
bash commands/print-gameplay-system-brief.sh >"$temp_root/brief.md"
grep -q '^## Player Contract$' "$temp_root/brief.md" || fail "legacy brief lost its player contract"
grep -q '^## Verification$' "$temp_root/brief.md" || fail "legacy brief lost verification"

for profile in design ui feedback; do
  bash commands/print-gameplay-system-brief.sh --focus "$profile" >"$temp_root/brief-$profile.md"
  grep -q '^## Environment And Scope$' "$temp_root/brief-$profile.md" || fail "focused brief omits environment"
  report="$temp_root/$profile.md"
  # Replace legacy narrative Evidence; specialized reports require scenario data.
  awk '$0 == "## Evidence" { skipping=1; next } skipping && /^## / { skipping=0 } !skipping { print }' "$temp_root/general.md" >"$report"
  cat >>"$report" <<'EOF'
## Environment And Scope
Synthetic report, no running engine; text fixtures only, all platforms unverified.
EOF
  case "$profile" in
    design)
      cat >>"$report" <<'EOF'
## Player Decisions And Loops
Fixture hypothesis: a visible resource cost creates a recoverable choice.
## Rules And Balance
Cost and recovery rules are separate from tunable values and simulated outcomes.
## Design Hypotheses And Playtests
Target players would explain their choice; no actual participants are available.
## Evidence
| Scenario | Expected | Observed | Status | Evidence | Reason |
| --- | --- | --- | --- | --- | --- |
| Core-loop decision interview | Player explains the opportunity cost | No players recruited | not-run | unavailable | This regression has no playtest participants |
EOF
      ;;
    ui)
      cat >>"$report" <<'EOF'
## Layout And Readability
Safe areas, long labels, and text scaling need an actual target layout review.
## Navigation And Screen Flow
Nested modal must own input and restore valid focus after removing an item.
## HUD And Input Synchronization
State update during creation must appear once; reopened HUD must unsubscribe.
## Evidence
| Scenario | Expected | Observed | Status | Evidence | Reason |
| --- | --- | --- | --- | --- | --- |
| Nested modal and removed focus target | Single input owner and fallback focus | No runtime attached | blocked | unavailable | Native UI build is unavailable in this fixture |
| HUD snapshot racing an update | Latest revision shown once after reopen | Synthetic record reports a duplicated event | fail | fixture-hud.log | Recorded defect intentionally remains visible |
| Safe area and localization variation | Critical information remains readable | No rendered layouts | not-run | unavailable | Document validation does not render game UI |
EOF
      ;;
    feedback)
      cat >>"$report" <<'EOF'
## Event And Channel Map
Event delivery must isolate each local player and bound channel overlap.
## Timing And Cancellation
Interruption must preserve pause ownership and reject expired queued effects.
## Haptic Capabilities And Results
Mocked calls concern adapter contracts; no tactile device is attached or tested.
## Evidence
| Scenario | Expected | Observed | Status | Evidence | Reason |
| --- | --- | --- | --- | --- | --- |
| Adapter API failure | Simulation continues after rejection | Synthetic failure record captured | pass | fixture-adapter.log | Parser fixture only; not a device result |
| Disconnect and late callback | No stale replay or cross-player cancellation | No native adapter executed | blocked | unavailable | Device integration is outside the text fixture |
| Physical haptic strength | Person observes bounded tactile output | No supported device attached | not-run | unavailable | Physical output cannot be proved with API mocks |
EOF
      ;;
  esac
  bash commands/validate-gameplay-review.sh --profile "$profile" "$report" >"$temp_root/$profile.log"
  grep -q 'structure only' "$temp_root/$profile.log" || fail "validator overstates evidence"
  grep -q 'not-run=1' "$temp_root/$profile.log" || fail "unrun evidence was lost"
  # The option also works after the legacy positional report and with CRLF.
  sed 's/$/\r/' "$report" >"$temp_root/$profile-crlf.md"
  bash commands/validate-gameplay-review.sh "$temp_root/$profile-crlf.md" --profile "$profile" >"$temp_root/$profile-crlf.log"
  diff <(tail -n 2 "$temp_root/$profile.log") <(tail -n 2 "$temp_root/$profile-crlf.log") || fail "LF/CRLF changed scenario verdicts"
done

grep -q 'fail=1' "$temp_root/ui.log" || fail "a failed scenario became a gameplay pass"
grep -q 'blocked=1' "$temp_root/feedback.log" || fail "blocked haptic integration disappeared"
grep -q 'pass=1' "$temp_root/feedback.log" || fail "adapter scenario count is incorrect"

expect_failure bash commands/validate-gameplay-review.sh --profile ui "$temp_root/general.md"
grep -q 'Environment And Scope' "$temp_root/rejection.log" || fail "missing specialized context was accepted"
sed '/^## Navigation And Screen Flow$/,+1d' "$temp_root/ui.md" >"$temp_root/missing-ui.md"
expect_failure bash commands/validate-gameplay-review.sh --profile ui "$temp_root/missing-ui.md"
grep -q 'Navigation And Screen Flow' "$temp_root/rejection.log" || fail "missing UI section was accepted"

sed 's/| not-run | unavailable | Physical output cannot be proved with API mocks |/| not-run | unavailable | - |/' "$temp_root/feedback.md" >"$temp_root/no-reason.md"
expect_failure bash commands/validate-gameplay-review.sh --profile feedback "$temp_root/no-reason.md"
grep -q 'needs a reason' "$temp_root/rejection.log" || fail "unrun scenario without reason was accepted"
sed 's/| pass | fixture-adapter.log |/| success | fixture-adapter.log |/' "$temp_root/feedback.md" >"$temp_root/bad-status.md"
expect_failure bash commands/validate-gameplay-review.sh --profile feedback "$temp_root/bad-status.md"
grep -q 'Unknown evidence status' "$temp_root/rejection.log" || fail "unknown scenario verdict was accepted"
sed 's/| pass | fixture-adapter.log |/| pass | unavailable |/' "$temp_root/feedback.md" >"$temp_root/no-artifact.md"
expect_failure bash commands/validate-gameplay-review.sh --profile feedback "$temp_root/no-artifact.md"
grep -q 'artifact reference' "$temp_root/rejection.log" || fail "passed scenario without evidence was accepted"
printf '\n## Summary\nTBD\n' >>"$temp_root/general.md"
expect_failure bash commands/validate-gameplay-review.sh "$temp_root/general.md"
grep -q 'Duplicate section' "$temp_root/rejection.log" || fail "ambiguous repeated heading was accepted"

expect_failure bash commands/print-gameplay-system-brief.sh --focus unknown
expect_failure bash commands/print-gameplay-system-brief.sh --focus
expect_failure bash commands/print-gameplay-system-brief.sh --focus ui --focus feedback
expect_failure bash commands/validate-gameplay-review.sh --profile unknown "$temp_root/ui.md"
expect_failure bash commands/validate-gameplay-review.sh --profile
expect_failure bash commands/validate-gameplay-review.sh --profile ui --profile feedback "$temp_root/ui.md"
expect_failure bash commands/validate-gameplay-review.sh "$temp_root/missing.md"
bash commands/print-gameplay-system-brief.sh --help >/dev/null
bash commands/validate-gameplay-review.sh --help >/dev/null
echo "Gameplay profile regressions passed (synthetic report fixtures; no game/device execution)."
