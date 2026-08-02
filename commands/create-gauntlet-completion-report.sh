#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-gauntlet-completion-report.sh "<gauntlet>" [--status complete|stopped|blocked] [--dry-run]

Creates GAUNTLET_REPORT.md next to GAUNTLET.md. A complete report is generated
only after all work-unit and integration evidence passes and makes the Gauntlet
eligible for the human-gated final promotion PR. Stopped and blocked reports
remain explicitly incomplete and PR-ineligible. The approved promotion PR uses
`Closes #<issue>` as its exact first body line and targets the GitHub default
branch; progress and remediation PRs use non-closing `Refs #<issue>` first.
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
gauntlet_acquire_lock "$gauntlet_dir"
trap 'gauntlet_release_lock' EXIT
current_status="$(gauntlet_section_field "$gauntlet_file" 'Flow and Status' 'Status')"
if [[ "$current_status" == 'passed' && "$completion_status" != 'complete' ]]; then
  echo 'A passed Gauntlet cannot be demoted by report generation; only --status complete is valid.' >&2
  exit 1
fi
bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase structure >/dev/null
report_file="$gauntlet_dir/GAUNTLET_REPORT.md"
if [[ -e "$report_file" || -L "$report_file" ]]; then
  gauntlet_assert_safe_ai_path "$report_file" 'Gauntlet completion report'
  [[ ! -d "$report_file" ]] || { echo "Gauntlet completion report path is a directory: $report_file" >&2; exit 1; }
fi
completion_dir="$gauntlet_dir/completion-events"
if [[ -e "$completion_dir" || -L "$completion_dir" ]]; then
  gauntlet_assert_safe_ai_path "$completion_dir" 'Gauntlet completion events directory'
fi

if [[ "$current_status" == 'passed' && "$completion_status" == 'complete' ]]; then
  bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase complete >/dev/null
  active_completion_event="$(gauntlet_latest_completion_event_file "$completion_dir")"
  [[ -n "$active_completion_event" && -f "$report_file" ]] || {
    echo 'Passed Gauntlet lacks its active immutable completion event or report.' >&2
    exit 1
  }
  echo "GAUNTLET_FILE=$gauntlet_file"
  echo "REPORT_FILE=$report_file"
  echo "COMPLETION_EVENT_FILE=$active_completion_event"
  echo 'GAUNTLET_STATUS=passed'
  echo 'PR_ELIGIBLE=yes'
  echo "EXECUTION_CONTRACT_FINGERPRINT=$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Execution contract fingerprint')"
  echo "BASE_COMMIT_SHA=$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
  gauntlet_release_lock
  trap - EXIT
  exit 0
fi

existing_completion_temp="$(find "$gauntlet_dir" -maxdepth 1 -type f \
  \( -name '.completion-*' -o -name '.report-*' \) -print -quit)"
[[ -z "$existing_completion_temp" ]] || {
  echo "Stale Gauntlet completion/report transaction file blocks report generation: $existing_completion_temp" >&2
  exit 1
}

case "$completion_status" in
  complete)
    bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready >/dev/null
    resulting_status='passed'
    pr_eligible='yes'
    next_action='Pass the human promotion-PR readiness gate, promote the integration branch only after approval, and run post-promotion QA.'
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
gauntlet_capture_source_hash "$gauntlet_file"

assert_completion_evidence() {
  local current_bar current_manifest current_execution base_commit_sha unit_line item_id integration_evidence latest_integration reviewed_integration_head integration_head integration_scope current_scope chain_tip

  current_bar="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
  current_execution="$(gauntlet_assert_frozen_execution_contract "$gauntlet_file")" || return 1
  current_manifest="$(gauntlet_assert_frozen_unit_manifest "$gauntlet_file")" || return 1
  base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
  base_commit_sha="${base_commit_sha,,}"
  reviewed_integration_head="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')"
  gauntlet_validate_head_sha "$reviewed_integration_head" 'Gauntlet integration review Head SHA' || return 1
  gauntlet_assert_commit_ancestor "$base_commit_sha" "$reviewed_integration_head" 'Completed integration review approved base' || return 1
  chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")" || return 1
  [[ "$chain_tip" == "${reviewed_integration_head,,}" ]] || {
    echo 'Completed integration review is not the exact gapless progress-PR merge-chain tip.' >&2
    return 1
  }
  gauntlet_assert_remote_integration_tip "$gauntlet_file" "$chain_tip" || return 1
  while IFS= read -r unit_line; do
    [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]] && continue
    if [[ ! "$unit_line" =~ ^-[[:space:]]\[[xX]\][[:space:]]([a-z0-9-]+)[[:space:]]\|[[:space:]]status:[[:space:]]passed[[:space:]]\| ]]; then
      echo "Every active work unit must pass before a complete report: $unit_line" >&2
      return 1
    fi
    item_id="${BASH_REMATCH[1]}"
    gauntlet_assert_unit_progress_integrated \
      "$gauntlet_file" "$item_id" "$current_bar" "$reviewed_integration_head" || return 1
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
    && "$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Quality bar fingerprint')" == "$current_bar" \
    && "$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Unit manifest fingerprint')" == "$current_manifest" \
    && "$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Execution contract fingerprint')" == "$current_execution" \
    && "$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$base_commit_sha" ]] || {
    echo 'Latest integration evidence must pass on the current quality bar before a complete report.' >&2
    return 1
  }
  integration_head="$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Head SHA')"
  integration_scope="$(gauntlet_section_field "$latest_integration" 'Round Metadata' 'Scope fingerprint')"
  current_scope="$(gauntlet_active_scope_fingerprint "$gauntlet_file")"
  [[ "$reviewed_integration_head" == "$integration_head" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint')" == "$integration_scope" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Unit manifest fingerprint')" == "$current_manifest" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Execution contract fingerprint')" == "$current_execution" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$base_commit_sha" \
    && "$integration_scope" == "$current_scope" ]] || {
    echo 'Latest integration evidence does not match the current integration commit and active scope.' >&2
    return 1
  }
}

if [[ "$completion_status" == 'complete' ]]; then
  assert_completion_evidence
fi

main_stage="$(mktemp "$gauntlet_dir/.completion-stage.XXXXXX")"
report_stage="$(mktemp "$gauntlet_dir/.report-stage.XXXXXX")"
backup_file="$(mktemp "$gauntlet_dir/.backup-stage.XXXXXX")"
completion_event_stage=''
completion_event_target=''
completion_event_relative='none'
completion_ledger_stage=''
report_backup=''
completion_dir_created=0
cleanup_completion_stage() {
  rm -f "$main_stage" "$report_stage" "$backup_file" \
    "${completion_event_stage:-}" "${completion_ledger_stage:-}" "${report_backup:-}"
  if [[ $completion_dir_created -eq 1 ]]; then
    rmdir "$completion_dir" 2>/dev/null || true
  fi
  gauntlet_release_lock
}
trap cleanup_completion_stage EXIT
cp "$gauntlet_file" "$main_stage"
gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' "$resulting_status"
gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' 'none'
gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' "$next_action"
gauntlet_set_section_field "$main_stage" 'Delivery' 'PR eligible' "$pr_eligible"
chmod 0644 "$main_stage"

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [[ "$completion_status" == 'complete' ]]; then
  max_completion_event=0
  if [[ -d "$completion_dir" ]]; then
    while IFS= read -r existing_completion_event; do
      existing_name="$(basename "$existing_completion_event")"
      if [[ "$existing_name" =~ ^event-([0-9]+)\.md$ ]]; then
        existing_number=$((10#${BASH_REMATCH[1]}))
        (( existing_number > max_completion_event )) && max_completion_event=$existing_number
      fi
    done < <(find "$completion_dir" -maxdepth 1 -type f -name 'event-*.md' -print)
  fi
  next_completion_event=$((max_completion_event + 1))
  printf -v completion_event_label '%03d' "$next_completion_event"
  completion_event_relative=".ai/gauntlets/$gauntlet_name/completion-events/event-$completion_event_label.md"
  completion_event_target="$OPENCAW_PROJECT_ROOT_RESOLVED/$completion_event_relative"
  [[ ! -e "$completion_event_target" && ! -L "$completion_event_target" ]] || {
    echo "Completion event evidence already exists: $completion_event_relative" >&2
    exit 1
  }
  completing_integration_round="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')"
  completing_integration_round="${completing_integration_round#\`}"
  completing_integration_round="${completing_integration_round%\`}"
  completing_head_sha="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
  completing_scope="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')"
  completing_quality="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
  completing_manifest="$(gauntlet_assert_frozen_unit_manifest "$gauntlet_file")"
  completing_execution="$(gauntlet_assert_frozen_execution_contract "$gauntlet_file")"
  completing_base="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')"
fi

parent_task="$(gauntlet_extract_section "$main_stage" 'Parent Task')"
objective="$(gauntlet_extract_section "$main_stage" 'Objective')"
quality_bar="$(gauntlet_extract_section "$main_stage" 'Approved Quality Bar')"
constraints="$(gauntlet_extract_section "$main_stage" 'Constraints and Permissions')"
work_units="$(gauntlet_extract_section "$main_stage" 'Work Units')"
round_ledger="$(gauntlet_extract_section "$main_stage" 'Round Ledger')"
progress_pr_ledger="$(gauntlet_extract_section "$main_stage" 'Progress PR Ledger')"
promotion_qa_ledger="$(gauntlet_extract_section "$main_stage" 'Promotion QA Ledger')"
completion_ledger="$(gauntlet_extract_section "$main_stage" 'Completion Ledger')"
integration_review="$(gauntlet_extract_section "$main_stage" 'Integration Review')"
delivery="$(gauntlet_extract_section "$main_stage" 'Delivery')"
review_notes="$(gauntlet_extract_section "$main_stage" 'Review Notes')"
report_execution_fingerprint="$(gauntlet_section_field "$main_stage" 'Current State' 'Execution contract fingerprint')"
report_base_commit_sha="$(gauntlet_section_field "$main_stage" 'Delivery' 'Base commit SHA')"
report_unit_manifest_fingerprint="$(gauntlet_section_field "$main_stage" 'Current State' 'Unit manifest fingerprint')"

cat > "$report_stage" <<EOF
# Gauntlet Report: $gauntlet_name

## Outcome
- Completion outcome: $completion_status
- Gauntlet status: $resulting_status
- PR eligible: $pr_eligible
- Unit manifest fingerprint: $report_unit_manifest_fingerprint
- Execution contract fingerprint: $report_execution_fingerprint
- Base commit SHA: $report_base_commit_sha
- Generated: $generated_at

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

## Ordered Progress PR and QA Evidence
$progress_pr_ledger

## Promotion QA Evidence
$promotion_qa_ledger

## Immutable Completion Evidence
$completion_ledger

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
This Gauntlet passed every active unit, each unit's latest QA-passed human-merged
progress PR, and the latest independent integration review. It is eligible for
the human promotion-PR readiness checkpoint. Run:

\`bash ./commands/pr-readiness-check.sh --gauntlet "$gauntlet_name"\`

Do not push or open the final promotion PR from the integration branch to the
approved, currently verified GitHub default branch until the user explicitly
confirms readiness.
EOF
else
  cat >> "$report_stage" <<EOF
This Gauntlet ended as **$completion_status** and is not PR eligible. Do not push,
open, merge, approve, or enable auto-merge for a Gauntlet PR from this report.
EOF
fi
chmod 0644 "$report_stage"

if [[ "$completion_status" == 'complete' ]]; then
  # The event binds the full report projection while avoiding a circular hash:
  # the projection excludes only the Completion Ledger section that will name
  # and hash this event.
  report_projection_hash="$(gauntlet_report_projection_hash "$report_stage")"
  completion_event_stage="$(mktemp "$gauntlet_dir/.completion-event-stage.XXXXXX")"
  cat > "$completion_event_stage" <<EOF
# Gauntlet Completion Event: $completion_event_label

## Completion Event Metadata
- Sequence: $completion_event_label
- Outcome: complete
- Integration round: $completing_integration_round
- Head SHA: $completing_head_sha
- Scope fingerprint: $completing_scope
- Unit manifest fingerprint: $completing_manifest
- Quality bar fingerprint: $completing_quality
- Execution contract fingerprint: $completing_execution
- Base commit SHA: $completing_base
- Report: .ai/gauntlets/$gauntlet_name/GAUNTLET_REPORT.md
- Report projection sha256: $report_projection_hash
- Recorded at: $generated_at
EOF
  chmod 0644 "$completion_event_stage"
  completion_event_hash="$(gauntlet_hash_file "$completion_event_stage")"
  completion_ledger_entry="- event: $completion_event_label | outcome: complete | integration-round: $completing_integration_round | head-sha: $completing_head_sha | scope: $completing_scope | manifest: $completing_manifest | contract: $completing_execution | base-sha: $completing_base | quality: $completing_quality | report: .ai/gauntlets/$gauntlet_name/GAUNTLET_REPORT.md | report-projection: $report_projection_hash | record: $completion_event_relative | sha256: $completion_event_hash"
  gauntlet_append_completion_ledger "$main_stage" "$completion_ledger_entry"
  completion_ledger_stage="$(mktemp "$gauntlet_dir/.completion-ledger-stage.XXXXXX")"
  gauntlet_extract_section "$main_stage" 'Completion Ledger' > "$completion_ledger_stage"
  rewritten_report="$(mktemp "$gauntlet_dir/.report-rewrite-stage.XXXXXX")"
  awk -v ledger_file="$completion_ledger_stage" '
      { sub(/\r$/, "") }
      $0 == "## Immutable Completion Evidence" {
        print
        while ((getline ledger_line < ledger_file) > 0) print ledger_line
        close(ledger_file)
        skip = 1
        next
      }
      /^## / && skip { skip = 0 }
      !skip { print }
    ' "$report_stage" > "$rewritten_report"
  chmod 0644 "$rewritten_report"
  mv "$rewritten_report" "$report_stage"
  [[ "$(gauntlet_report_projection_hash "$report_stage")" == "$report_projection_hash" ]] || {
    echo 'Completion report projection changed while embedding immutable completion evidence.' >&2
    exit 1
  }
fi

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $report_file"
  echo "GAUNTLET_FILE=$gauntlet_file"
  echo "REPORT_FILE=$report_file"
  echo "GAUNTLET_STATUS=$resulting_status"
  echo "PR_ELIGIBLE=$pr_eligible"
  echo "UNIT_MANIFEST_FINGERPRINT=$report_unit_manifest_fingerprint"
  echo "EXECUTION_CONTRACT_FINGERPRINT=$report_execution_fingerprint"
  echo "BASE_COMMIT_SHA=$report_base_commit_sha"
  echo "COMPLETION_EVENT_FILE=${completion_event_target:-none}"
  echo
  cat "$report_stage"
  exit 0
fi

cp "$gauntlet_file" "$backup_file"
if [[ -f "$report_file" && ! -L "$report_file" ]]; then
  report_backup="$(mktemp "$gauntlet_dir/.report-backup.XXXXXX")"
  cp "$report_file" "$report_backup"
fi
gauntlet_assert_source_hash
if [[ "$completion_status" == 'complete' ]]; then
  [[ -d "$completion_dir" ]] || completion_dir_created=1
  mkdir -p "$completion_dir"
  gauntlet_assert_safe_ai_path "$completion_dir" 'Gauntlet completion events directory'
  gauntlet_install_no_clobber "$completion_event_stage" "$completion_event_target"
fi
if ! mv "$main_stage" "$gauntlet_file"; then
  [[ -z "$completion_event_target" ]] || rm -f "$completion_event_target"
  echo 'Could not install GAUNTLET.md completion state; immutable completion event was rolled back.' >&2
  exit 1
fi
if ! mv "$report_stage" "$report_file"; then
  cp "$backup_file" "$gauntlet_file"
  [[ -z "$completion_event_target" ]] || rm -f "$completion_event_target"
  exit 1
fi
if [[ "$completion_status" == 'complete' ]]; then
  if ! bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase complete >/dev/null; then
    cp "$backup_file" "$gauntlet_file"
    rm -f "$completion_event_target"
    if [[ -n "$report_backup" ]]; then
      mv "$report_backup" "$report_file"
    else
      rm -f "$report_file"
    fi
    echo 'Complete Gauntlet validation failed; GAUNTLET.md and report state were restored.' >&2
    exit 1
  fi
fi
rm -f "$backup_file" "${completion_ledger_stage:-}" "${report_backup:-}"
completion_temp_residue="$(find "$gauntlet_dir" -maxdepth 1 -type f \
  \( -name '.completion-*' -o -name '.report-*' \) -print -quit)"
[[ -z "$completion_temp_residue" ]] || {
  echo "Gauntlet completion transaction left a temporary file: $completion_temp_residue" >&2
  exit 1
}
gauntlet_release_lock
trap - EXIT

echo "GAUNTLET_FILE=$gauntlet_file"
echo "REPORT_FILE=$report_file"
echo "GAUNTLET_STATUS=$resulting_status"
echo "PR_ELIGIBLE=$pr_eligible"
echo "UNIT_MANIFEST_FINGERPRINT=$report_unit_manifest_fingerprint"
echo "EXECUTION_CONTRACT_FINGERPRINT=$report_execution_fingerprint"
echo "BASE_COMMIT_SHA=$report_base_commit_sha"
echo "COMPLETION_EVENT_FILE=${completion_event_target:-none}"
