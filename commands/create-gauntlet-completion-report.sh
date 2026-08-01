#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-gauntlet-completion-report.sh "<gauntlet>" [--status complete|stopped|blocked] [--dry-run]

Creates GAUNTLET_REPORT.md next to GAUNTLET.md. A complete report is generated
only after all work-unit and integration evidence passes and makes the Gauntlet
eligible for the normal human PR readiness gate. Stopped and blocked reports
remain explicitly incomplete and PR-ineligible.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"

gauntlet_ref=''
completion_status='complete'
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      completion_status="$2"
      shift 2
      ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)
      if [[ -z "$gauntlet_ref" ]]; then
        gauntlet_ref="$1"
      else
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

[[ -n "$gauntlet_ref" ]] || { usage >&2; exit 1; }
case "$completion_status" in complete|stopped|blocked) ;; *) echo "status must be complete, stopped, or blocked: $completion_status" >&2; exit 1 ;; esac

gauntlet_file="$(gauntlet_resolve_file "$gauntlet_ref")"
gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
gauntlet_name="$(basename "$gauntlet_dir")"
report_file="$gauntlet_dir/GAUNTLET_REPORT.md"
if [[ -e "$report_file" || -L "$report_file" ]]; then
  gauntlet_assert_safe_ai_path "$report_file" 'Gauntlet completion report'
  [[ ! -d "$report_file" ]] || { echo "Gauntlet completion report path is a directory: $report_file" >&2; exit 1; }
fi

case "$completion_status" in
  complete)
    bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready >/dev/null
    resulting_status='passed'
    pr_eligible='yes'
    next_action='Pass the human PR readiness gate, open one final PR after approval, and run post-PR QA.'
    ;;
  stopped)
    resulting_status='stopped'
    pr_eligible='no'
    next_action='Resume only with explicit user direction; this stopped Gauntlet is not PR eligible.'
    ;;
  blocked)
    resulting_status='blocked'
    pr_eligible='no'
    next_action='Resolve the recorded blocker before resuming; this blocked Gauntlet is not PR eligible.'
    ;;
esac

assert_completion_evidence() {
  local current_bar unit_line item_id latest_round integration_evidence latest_integration

  current_bar="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
  while IFS= read -r unit_line; do
    [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]] && continue
    if [[ ! "$unit_line" =~ ^-[[:space:]]\[[xX]\][[:space:]]([a-z0-9-]+)[[:space:]]\|[[:space:]]status:[[:space:]]passed[[:space:]]\| ]]; then
      echo "Every active work unit must pass before a complete report: $unit_line" >&2
      return 1
    fi
    item_id="${BASH_REMATCH[1]}"
    latest_round="$(gauntlet_latest_round_file "$gauntlet_dir/rounds/$item_id")"
    [[ -n "$latest_round" \
      && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Verdict')" == 'pass' \
      && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Quality bar fingerprint')" == "$current_bar" ]] || {
      echo "Work unit lacks a latest passing round on the current quality bar: $item_id" >&2
      return 1
    }
  done < <(gauntlet_work_unit_lines "$gauntlet_file")

  [[ "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pass' ]] || {
    echo 'Integration Review verdict must pass before a complete report.' >&2
    return 1
  }
  integration_evidence="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')"
  integration_evidence="${integration_evidence#\`}"
  integration_evidence="${integration_evidence%\`}"
  latest_integration="$(gauntlet_latest_round_file "$gauntlet_dir/rounds/integration")"
  [[ -n "$latest_integration" \
    && "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" == "$latest_integration" \
    && "$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Verdict')" == 'pass' \
    && "$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Quality bar fingerprint')" == "$current_bar" ]] || {
    echo 'Latest integration evidence must pass on the current quality bar before a complete report.' >&2
    return 1
  }
}

if [[ "$completion_status" == 'complete' ]]; then
  assert_completion_evidence
fi

main_stage="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-completion.XXXXXX")"
report_stage="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-report.XXXXXX")"
backup_file="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-backup.XXXXXX")"
trap 'rm -f "$main_stage" "$report_stage" "$backup_file"' EXIT
cp "$gauntlet_file" "$main_stage"
gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' "$resulting_status"
gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' 'none'
gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' "$next_action"
gauntlet_set_section_field "$main_stage" 'Delivery' 'PR eligible' "$pr_eligible"
chmod 0644 "$main_stage"

parent_task="$(gauntlet_extract_section "$main_stage" 'Parent Task')"
objective="$(gauntlet_extract_section "$main_stage" 'Objective')"
quality_bar="$(gauntlet_extract_section "$main_stage" 'Approved Quality Bar')"
constraints="$(gauntlet_extract_section "$main_stage" 'Constraints and Permissions')"
work_units="$(gauntlet_extract_section "$main_stage" 'Work Units')"
round_ledger="$(gauntlet_extract_section "$main_stage" 'Round Ledger')"
integration_review="$(gauntlet_extract_section "$main_stage" 'Integration Review')"
delivery="$(gauntlet_extract_section "$main_stage" 'Delivery')"
review_notes="$(gauntlet_extract_section "$main_stage" 'Review Notes')"

cat > "$report_stage" <<EOF
# Gauntlet Report: $gauntlet_name

## Outcome
- Completion outcome: $completion_status
- Gauntlet status: $resulting_status
- PR eligible: $pr_eligible
- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

## Parent Task
$parent_task

## Objective
$objective

## Frozen Quality Bar
$quality_bar

## Constraints and Permissions
$constraints

## Work Units
$work_units

## Immutable Round Evidence
$round_ledger

## Final Integration Review
$integration_review

## Delivery State
$delivery

## Review Notes
$review_notes

## PR Readiness
EOF

if [[ "$completion_status" == 'complete' ]]; then
  cat >> "$report_stage" <<EOF
This Gauntlet passed every active unit and the latest independent integration review.
It is eligible for the normal human PR readiness checkpoint. Run:

\`./commands/pr-readiness-check.sh --gauntlet "$gauntlet_name"\`

Do not push or open the one final PR until the user explicitly confirms readiness.
EOF
else
  cat >> "$report_stage" <<EOF
This Gauntlet ended as **$completion_status** and is not PR eligible. Do not push,
open, merge, approve, or enable auto-merge for a Gauntlet PR from this report.
EOF
fi
chmod 0644 "$report_stage"

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $report_file"
  echo "GAUNTLET_FILE=$gauntlet_file"
  echo "REPORT_FILE=$report_file"
  echo "GAUNTLET_STATUS=$resulting_status"
  echo "PR_ELIGIBLE=$pr_eligible"
  echo
  cat "$report_stage"
  exit 0
fi

cp "$gauntlet_file" "$backup_file"
mv "$main_stage" "$gauntlet_file"
if [[ "$completion_status" == 'complete' ]]; then
  if ! bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase complete >/dev/null; then
    cp "$backup_file" "$gauntlet_file"
    echo 'Complete Gauntlet validation failed; GAUNTLET.md was restored and no report was written.' >&2
    exit 1
  fi
fi
if ! mv "$report_stage" "$report_file"; then
  cp "$backup_file" "$gauntlet_file"
  exit 1
fi
trap - EXIT
rm -f "$backup_file"

echo "GAUNTLET_FILE=$gauntlet_file"
echo "REPORT_FILE=$report_file"
echo "GAUNTLET_STATUS=$resulting_status"
echo "PR_ELIGIBLE=$pr_eligible"
