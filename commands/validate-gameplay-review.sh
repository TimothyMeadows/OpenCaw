#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-gameplay-review.sh [--profile general|design|ui|feedback] <report>

Validates report structure, not gameplay correctness. The default general profile
preserves the original six required sections and accepts narrative evidence.
Specialized profiles also require Environment And Scope and their focus sections.

Specialized Evidence sections require a Markdown table with these columns:
| Scenario | Expected | Observed | Status | Evidence | Reason |
Status is pass, fail, blocked, or not-run. Pass/fail rows need an artifact reference;
blocked/not-run rows may use unavailable but must state a substantive reason.
Evidence references are recorded, not opened or fact-checked by this command.
EOF
}

profile="general"
profile_seen=0
report=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 && $profile_seen -eq 0 ]] || { usage >&2; exit 1; }
      profile="$2"; profile_seen=1; shift 2 ;;
    --profile=*)
      [[ $profile_seen -eq 0 ]] || { usage >&2; exit 1; }
      profile="${1#*=}"; profile_seen=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      [[ $# -eq 1 && -z "$report" ]] || { usage >&2; exit 1; }
      report="$1"; shift ;;
    -*) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    *)
      [[ -z "$report" ]] || { usage >&2; exit 1; }
      report="$1"; shift ;;
  esac
done
case "$profile" in
  general|design|ui|feedback) ;;
  *) echo "Unknown gameplay review profile: $profile" >&2; exit 1 ;;
esac
[[ -n "$report" ]] || { usage >&2; exit 1; }
[[ -f "$report" ]] || { echo "Gameplay review does not exist: $report" >&2; exit 1; }

# Normalize CRLF before matching either headings or content. One parser owns both,
# so headings accepted by the section check cannot disappear during extraction.
awk -v profile="$profile" -v report="$report" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function placeholder(s) {
  s=tolower(trim(s)); sub(/^[-*][ \t]+/, "", s)
  return s == "" || s == "-" || s ~ /^(todo|tbd|n\/?a|<[^>]+>)$/
}
function problem(message) { print message > "/dev/stderr"; failed=1 }
function required(name) {
  if (!(name in sections)) { problem("Missing required section: " name); return }
  if (!substantive[name]) problem("Section is empty or contains only placeholder content: " name)
}
function evidence_row(line, n, i, cells, status, value) {
  line=trim(line)
  if (line !~ /^\|/) return
  sub(/^\|/, "", line); sub(/\|[ \t]*$/, "", line)
  n=split(line, cells, /\|/)
  for (i=1; i<=n; i++) cells[i]=trim(cells[i])
  if (tolower(cells[1]) == "scenario") {
    if (n != 6 || tolower(cells[2]) != "expected" || tolower(cells[3]) != "observed" || tolower(cells[4]) != "status" || tolower(cells[5]) != "evidence" || tolower(cells[6]) != "reason") {
      problem("Evidence table must use Scenario | Expected | Observed | Status | Evidence | Reason")
    } else evidence_header=1
    return
  }
  if (line ~ /^[ :|\t-]+$/) return
  if (!evidence_header) { problem("Evidence row appears before its required table header"); return }
  if (n != 6) { problem("Evidence row must contain six cells: " cells[1]); return }
  evidence_count++
  for (i=1; i<=5; i++) if (placeholder(cells[i])) problem("Evidence row has an empty or placeholder cell: " cells[1])
  status=tolower(cells[4])
  if (status != "pass" && status != "fail" && status != "blocked" && status != "not-run") {
    problem("Unknown evidence status: " cells[4]); return
  }
  outcomes[status]++
  if (status == "blocked" || status == "not-run") {
    if (placeholder(cells[6]) || cells[6] == "-") problem("Blocked/not-run evidence needs a reason: " cells[1])
  } else {
    value=tolower(cells[5])
    if (value == "-" || value == "none" || value == "unavailable" || value == "not-run") problem("Pass/fail evidence needs an artifact reference: " cells[1])
  }
}
{
  sub(/\r$/, "")
  if ($0 ~ /^##[ \t]+/) {
    current=$0; sub(/^##[ \t]+/, "", current); current=trim(current)
    if (current in sections) problem("Duplicate section: " current)
    sections[current]=1
    next
  }
  if (current != "" && !placeholder($0) && $0 !~ /^[ \t]*#+[ \t]*/) substantive[current]=1
  if (profile != "general" && current == "Evidence") evidence_row($0)
}
END {
  required("Summary"); required("Controls And Accessibility"); required("Gameplay Systems")
  required("Performance"); required("Evidence"); required("Risks And Recommendation")
  if (profile != "general") required("Environment And Scope")
  if (profile == "design") {
    required("Player Decisions And Loops"); required("Rules And Balance"); required("Design Hypotheses And Playtests")
  } else if (profile == "ui") {
    required("Layout And Readability"); required("Navigation And Screen Flow"); required("HUD And Input Synchronization")
  } else if (profile == "feedback") {
    required("Event And Channel Map"); required("Timing And Cancellation"); required("Haptic Capabilities And Results")
  }
  if (profile != "general" && (!evidence_header || evidence_count == 0)) problem("Specialized review needs at least one structured evidence scenario")
  if (failed) exit 1
  print "Gameplay review structure validation passed: " report " (profile=" profile ")"
  if (profile != "general") printf "Recorded scenarios: pass=%d fail=%d blocked=%d not-run=%d\n", outcomes["pass"], outcomes["fail"], outcomes["blocked"], outcomes["not-run"]
  print "This validates report structure only; recorded verdicts and referenced artifacts require review."
}' "$report"
