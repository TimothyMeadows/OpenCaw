#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/record-gauntlet-promotion-qa.sh <gauntlet> <pass|fail> <promotion-pr-url> <evidence-url> --head-sha <sha> [--affected-unit <id>]... [--dry-run]

Records immutable post-promotion-PR QA evidence. A failing event requires one or
more affected work units, archives the current completion report, reopens only
those units, and invalidates integration evidence. A passing event records the
QA evidence without reopening the passed Gauntlet. Promotion evidence is refused
if the PR timeline ever enabled auto-merge, auto-rebase, auto-squash, or entry into
a merge queue, including automation that was later disabled.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"

dry_run=0
head_sha=''
affected_units=()
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --head-sha)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      head_sha="$2"
      shift 2
      ;;
    --affected-unit)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      affected_units+=("$2")
      shift 2
      ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) positional+=("$1"); shift ;;
  esac
done

[[ ${#positional[@]} -eq 4 && -n "$head_sha" ]] || { usage >&2; exit 1; }
gauntlet_ref="${positional[0]}"
verdict="${positional[1]}"
promotion_pr_url="${positional[2]%/}"
evidence_url="${positional[3]}"

case "$verdict" in pass|fail) ;; *) echo "verdict must be pass or fail: $verdict" >&2; exit 1 ;; esac
gauntlet_validate_github_pr_url "$promotion_pr_url" 'Promotion PR URL'
gauntlet_validate_evidence_url "$evidence_url" 'Evidence URL'
[[ "$evidence_url" != 'none' ]] || { echo 'Promotion QA requires an HTTPS evidence URL.' >&2; exit 1; }
gauntlet_validate_pr_evidence_url "$evidence_url" "$promotion_pr_url" no
gauntlet_validate_head_sha "$head_sha" 'head-sha'
head_sha="${head_sha,,}"
gauntlet_assert_commit_object "$head_sha" 'Promotion PR head SHA'

if [[ "$verdict" == 'pass' && ${#affected_units[@]} -ne 0 ]]; then
  echo 'A passing promotion-QA event must not name affected units.' >&2
  exit 1
fi
if [[ "$verdict" == 'fail' && ${#affected_units[@]} -eq 0 ]]; then
  echo 'A failing promotion-QA event requires at least one --affected-unit.' >&2
  exit 1
fi

normalized_units=()
for affected_unit in "${affected_units[@]}"; do
  gauntlet_validate_name "$affected_unit" 'affected-unit'
  for existing_unit in "${normalized_units[@]}"; do
    [[ "$affected_unit" != "$existing_unit" ]] || {
      echo "Affected unit was supplied more than once: $affected_unit" >&2
      exit 1
    }
  done
  normalized_units+=("$affected_unit")
done
if [[ ${#normalized_units[@]} -gt 0 ]]; then
  sorted_units=()
  while IFS= read -r affected_unit; do
    sorted_units+=("$affected_unit")
  done < <(printf '%s\n' "${normalized_units[@]}" | LC_ALL=C sort)
  normalized_units=("${sorted_units[@]}")
  affected_csv="$(IFS=','; printf '%s' "${normalized_units[*]}")"
else
  affected_csv='none'
fi

gauntlet_file="$(gauntlet_resolve_file "$gauntlet_ref")"
gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
gauntlet_name="$(basename "$gauntlet_dir")"
promotion_dir="$gauntlet_dir/promotion-events"
if [[ -e "$promotion_dir" || -L "$promotion_dir" ]]; then
  gauntlet_assert_safe_ai_path "$promotion_dir" 'Gauntlet promotion events directory'
fi

gauntlet_acquire_lock "$gauntlet_dir"
trap 'gauntlet_release_lock' EXIT
bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase complete >/dev/null
gauntlet_capture_source_hash "$gauntlet_file"

[[ "$(gauntlet_section_field "$gauntlet_file" 'Flow and Status' 'Status')" == 'passed' ]] || {
  echo 'Promotion QA can be recorded only for a passed Gauntlet.' >&2
  exit 1
}
[[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'PR eligible')" == 'yes' ]] || {
  echo 'Promotion QA requires a promotion-eligible passed Gauntlet.' >&2
  exit 1
}

source_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
target_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base branch')"
base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
base_commit_sha="${base_commit_sha,,}"
execution_fingerprint="$(gauntlet_assert_frozen_execution_contract "$gauntlet_file")"
unit_manifest_fingerprint="$(gauntlet_assert_frozen_unit_manifest "$gauntlet_file")"
reviewed_head="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')"
[[ "${reviewed_head,,}" == "$head_sha" ]] || {
  echo "Promotion QA Head SHA must match the latest passing integration review: $reviewed_head" >&2
  exit 1
}
gauntlet_assert_local_branch_at_sha "$source_branch" "$head_sha" 'Gauntlet integration branch'

issue_url="$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Issue')"
issue_repo="$(gauntlet_github_repo_from_url "$issue_url")"
promotion_repo="$(gauntlet_github_repo_from_url "$promotion_pr_url")"
[[ -n "$issue_repo" && "${promotion_repo,,}" == "${issue_repo,,}" ]] || {
  echo 'Promotion PR must belong to the same GitHub repository as the parent issue.' >&2
  exit 1
}
gauntlet_assert_github_repository_identity "$issue_repo"
gauntlet_assert_github_default_branch "$issue_repo" "$target_branch"
gauntlet_assert_live_pr "$promotion_pr_url" "$issue_repo" "$source_branch" "$head_sha" "$target_branch" open
gauntlet_assert_promotion_issue_link "$GAUNTLET_GH_BODY" "$issue_url"
promotion_target_base_sha="${GAUNTLET_GH_BASE_SHA,,}"
promotion_cross_repository="$GAUNTLET_GH_IS_CROSS_REPOSITORY"
promotion_head_repository="$GAUNTLET_GH_HEAD_REPOSITORY"
promotion_observed_state="$GAUNTLET_GH_STATE"
promotion_draft="$GAUNTLET_GH_IS_DRAFT"
promotion_created_at="$GAUNTLET_GH_CREATED_AT"
promotion_closed_at="${GAUNTLET_GH_CLOSED_AT:-none}"
promotion_merged_at="${GAUNTLET_GH_MERGED_AT:-none}"
gauntlet_assert_commit_ancestor "$base_commit_sha" "$promotion_target_base_sha" 'Promotion PR target lineage'
gauntlet_assert_unique_qa_comment "$gauntlet_dir" "$evidence_url"

recorded_promotion_url="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Promotion PR URL')"
[[ -z "$recorded_promotion_url" || "${recorded_promotion_url%/}" == "$promotion_pr_url" ]] || {
  echo "Promotion PR URL conflicts with the existing Gauntlet delivery record: $recorded_promotion_url" >&2
  exit 1
}

quality_fingerprint="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
scope_fingerprint="$(gauntlet_active_scope_fingerprint "$gauntlet_file")"
[[ "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pass' \
  && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint')" == "$scope_fingerprint" \
  && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Quality bar fingerprint')" == "$quality_fingerprint" \
  && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Unit manifest fingerprint')" == "$unit_manifest_fingerprint" \
  && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Execution contract fingerprint')" == "$execution_fingerprint" \
  && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$base_commit_sha" ]] || {
  echo 'Promotion QA requires current passing integration evidence.' >&2
  exit 1
}

for affected_unit in "${normalized_units[@]}"; do
  unit_line="$(gauntlet_work_unit_lines "$gauntlet_file" | awk -v item="$affected_unit" '$0 ~ "^- \\[[ xX]\\] " item " \\|" { print; exit }')"
  [[ -n "$unit_line" ]] || { echo "Unknown affected work-unit id: $affected_unit" >&2; exit 1; }
  [[ "$unit_line" =~ ^-[[:space:]]\[[xX]\].*\|[[:space:]]status:[[:space:]]passed[[:space:]]\| ]] || {
    echo "Promotion-QA failure may reopen only an active passed work unit: $affected_unit" >&2
    exit 1
  }
done

report_file="$gauntlet_dir/GAUNTLET_REPORT.md"
[[ -f "$report_file" && ! -L "$report_file" ]] || {
  echo "Promotion QA requires the current Gauntlet completion report: $report_file" >&2
  exit 1
}
if ! grep -Fqx -- '- Completion outcome: complete' "$report_file" \
  || ! grep -Fqx -- '- Gauntlet status: passed' "$report_file" \
  || ! grep -Fqx -- '- PR eligible: yes' "$report_file" \
  || ! grep -Fqx -- "- Unit manifest fingerprint: $unit_manifest_fingerprint" "$report_file" \
  || ! grep -Fqx -- "- Execution contract fingerprint: $execution_fingerprint" "$report_file" \
  || ! grep -Fqx -- "- Base commit SHA: $base_commit_sha" "$report_file"; then
  echo "Promotion QA requires a complete, passed, PR-eligible report: $report_file" >&2
  exit 1
fi
completion_event_file="$(gauntlet_latest_completion_event_file "$gauntlet_dir/completion-events")"
[[ -n "$completion_event_file" && -f "$completion_event_file" && ! -L "$completion_event_file" ]] || {
  echo 'Promotion QA requires an active immutable completion event.' >&2
  exit 1
}
completion_event_relative="${completion_event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
completion_recorded_at="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Recorded at')"
gauntlet_assert_live_pr_comment \
  "$evidence_url" "$promotion_pr_url" "$issue_repo" "$verdict" "$head_sha" \
  "$completion_event_relative" "$completion_recorded_at" "$affected_csv"
qa_comment_author="$GAUNTLET_COMMENT_AUTHOR"
qa_comment_id="$GAUNTLET_COMMENT_ID"
qa_comment_author_type="$GAUNTLET_COMMENT_AUTHOR_TYPE"
qa_comment_author_association="$GAUNTLET_COMMENT_AUTHOR_ASSOCIATION"
qa_comment_created_at="$GAUNTLET_COMMENT_CREATED_AT"
qa_comment_updated_at="$GAUNTLET_COMMENT_UPDATED_AT"
qa_comment_body_sha256="$GAUNTLET_COMMENT_BODY_SHA256"

# Promotion QA state is keyed by the immutable completion event. One passing
# attestation may be followed by exactly one failing attestation of that same
# PR/completion/head boundary. The failure consumes the completion. Recovery
# therefore requires both a new reviewed head and a new completion event.
completion_transition_count=0
prior_completion_verdict=''
prior_completion_pr=''
prior_completion_head=''
prior_completion_evidence=''
prior_completion_comment_created=''
prior_completion_comment_id=''
prior_completion_target_base=''
prior_completion_pr_created=''
if [[ -d "$promotion_dir" ]]; then
  while IFS= read -r prior_promotion_event; do
    prior_verdict="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'Verdict')"
    prior_head="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
    prior_completion="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'Completion event')"
    if [[ "$prior_verdict" == 'fail' && "$prior_head" == "$head_sha" \
      && "$prior_completion" != "$completion_event_relative" ]]; then
      echo "Promotion-QA recovery requires a new reviewed head as well as a new completion event: $head_sha" >&2
      exit 1
    fi
    [[ "$prior_completion" == "$completion_event_relative" ]] || continue
    completion_transition_count=$((completion_transition_count + 1))
    prior_completion_verdict="$prior_verdict"
    prior_completion_pr="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'Promotion PR URL')"
    prior_completion_pr="${prior_completion_pr%/}"
    prior_completion_head="$prior_head"
    prior_completion_evidence="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'Evidence URL')"
    prior_completion_comment_id="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'QA comment ID')"
    prior_completion_comment_created="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'QA comment created at')"
    prior_completion_target_base="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'Target base SHA' | tr '[:upper:]' '[:lower:]')"
    prior_completion_pr_created="$(gauntlet_section_field "$prior_promotion_event" 'Promotion QA Event Metadata' 'Created at')"
  done < <(find "$promotion_dir" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
fi
case "$completion_transition_count" in
  0) ;;
  1)
    [[ "$prior_completion_verdict" == 'pass' && "$verdict" == 'fail' \
      && "$prior_completion_pr" == "$promotion_pr_url" \
      && "$prior_completion_head" == "$head_sha" \
      && "$prior_completion_target_base" == "$promotion_target_base_sha" \
      && "$prior_completion_pr_created" == "$promotion_created_at" \
      && "$prior_completion_evidence" != "$evidence_url" \
      && ( "$prior_completion_comment_created" < "$qa_comment_created_at" \
        || ( "$prior_completion_comment_created" == "$qa_comment_created_at" \
          && "$qa_comment_id" -gt "$prior_completion_comment_id" ) ) ]] || {
      echo 'A completion event permits only one pass followed by one later, distinct failing semantic QA comment on the same promotion PR and reviewed head.' >&2
      exit 1
    }
    ;;
  *)
    echo "Promotion QA completion event is already terminally consumed: $completion_event_relative" >&2
    exit 1
    ;;
esac

max_event=0
if [[ -d "$promotion_dir" ]]; then
  while IFS= read -r existing_event; do
    existing_name="$(basename "$existing_event")"
    if [[ "$existing_name" =~ ^event-([0-9]+)\.md$ ]]; then
      existing_number=$((10#${BASH_REMATCH[1]}))
      (( existing_number > max_event )) && max_event=$existing_number
    fi
  done < <(find "$promotion_dir" -maxdepth 1 -type f -name 'event-*.md' -print)
fi
next_event=$((max_event + 1))
printf -v event_label '%03d' "$next_event"
event_relative=".ai/gauntlets/$gauntlet_name/promotion-events/event-$event_label.md"
event_target="$OPENCAW_PROJECT_ROOT_RESOLVED/$event_relative"
archive_relative='none'
archive_target=''
archive_hash='none'
archive_stage=''
if [[ "$verdict" == 'fail' ]]; then
  archive_relative=".ai/gauntlets/$gauntlet_name/promotion-events/GAUNTLET_REPORT-before-event-$event_label.md"
  archive_target="$OPENCAW_PROJECT_ROOT_RESOLVED/$archive_relative"
  [[ ! -e "$archive_target" && ! -L "$archive_target" ]] || {
    echo "Archived completion report evidence already exists: $archive_relative" >&2
    exit 1
  }
fi
[[ ! -e "$event_target" && ! -L "$event_target" ]] || {
  echo "Promotion QA event evidence already exists: $event_relative" >&2
  exit 1
}

event_stage="$(mktemp "$gauntlet_dir/.promotion-event-stage.XXXXXX")"
main_stage="$(mktemp "$gauntlet_dir/.main-stage.XXXXXX")"
backup_stage="$(mktemp "$gauntlet_dir/.backup-stage.XXXXXX")"
cp "$gauntlet_file" "$backup_stage"
promotion_dir_created=0
cleanup_promotion_stage() {
  rm -f "$event_stage" "$main_stage" "$backup_stage" "${archive_stage:-}"
  if [[ $promotion_dir_created -eq 1 ]]; then
    rmdir "$promotion_dir" 2>/dev/null || true
  fi
  gauntlet_release_lock
}
trap cleanup_promotion_stage EXIT
if [[ "$verdict" == 'fail' ]]; then
  archive_stage="$(mktemp "$gauntlet_dir/.promotion-report-stage.XXXXXX")"
  cp "$report_file" "$archive_stage"
  chmod 0644 "$archive_stage"
  archive_hash="$(gauntlet_hash_file "$archive_stage")"
fi

recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
[[ "$promotion_created_at" < "$recorded_at" || "$promotion_created_at" == "$recorded_at" ]] || {
  echo 'Promotion PR creation time postdates the immutable QA event.' >&2
  exit 1
}
cat > "$event_stage" <<EOF
# Gauntlet Promotion QA Event: $event_label

## Promotion QA Event Metadata
- Sequence: $event_label
- Verdict: $verdict
- Promotion PR URL: $promotion_pr_url
- Source branch: $source_branch
- Target branch: $target_branch
- Target base SHA: $promotion_target_base_sha
- Cross repository: $promotion_cross_repository
- Head repository: $promotion_head_repository
- Head SHA: $head_sha
- Scope fingerprint: $scope_fingerprint
- Unit manifest fingerprint: $unit_manifest_fingerprint
- Quality bar fingerprint: $quality_fingerprint
- Execution contract fingerprint: $execution_fingerprint
- Base commit SHA: $base_commit_sha
- Completion event: $completion_event_relative
- Affected units: $affected_csv
- Evidence URL: $evidence_url
- QA comment ID: $qa_comment_id
- QA comment author: $qa_comment_author
- QA comment author type: $qa_comment_author_type
- QA comment author association: $qa_comment_author_association
- QA comment created at: $qa_comment_created_at
- QA comment updated at: $qa_comment_updated_at
- QA comment body sha256: $qa_comment_body_sha256
- Observed state: $promotion_observed_state
- Draft: $promotion_draft
- Created at: $promotion_created_at
- Closed at: $promotion_closed_at
- Merged at: $promotion_merged_at
- Archived report: $archive_relative
- Archived report sha256: $archive_hash
- Recorded at: $recorded_at
EOF
chmod 0644 "$event_stage"
event_hash="$(gauntlet_hash_file "$event_stage")"

cp "$gauntlet_file" "$main_stage"
gauntlet_set_section_field "$main_stage" 'Delivery' 'Promotion PR URL' "$promotion_pr_url"
if [[ "$verdict" == 'fail' ]]; then
  gauntlet_reopen_selected_units "$main_stage" "${normalized_units[@]}"
  gauntlet_reset_integration_review "$main_stage"
  gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
  gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' "${normalized_units[0]}"
  gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Publish remediation PRs for the affected units, then repeat integration criticism and promotion QA.'
  gauntlet_set_section_field "$main_stage" 'Delivery' 'PR eligible' 'no'
fi
ledger_entry="- event: $event_label | verdict: $verdict | pr: $promotion_pr_url | head-sha: $head_sha | source: $source_branch | target: $target_branch | target-base-sha: $promotion_target_base_sha | pr-created: $promotion_created_at | pr-closed: $promotion_closed_at | scope: $scope_fingerprint | manifest: $unit_manifest_fingerprint | contract: $execution_fingerprint | base-sha: $base_commit_sha | completion: $completion_event_relative | affected-units: $affected_csv | evidence: $evidence_url | qa-comment-id: $qa_comment_id | qa-author: $qa_comment_author | qa-created: $qa_comment_created_at | archived-report: $archive_relative | record: $event_relative | sha256: $event_hash"
gauntlet_append_promotion_qa_ledger "$main_stage" "$ledger_entry"
chmod 0644 "$main_stage"

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $event_target"
  [[ "$archive_relative" == 'none' ]] || echo "Dry run: would archive $report_file as $archive_target"
  echo "GAUNTLET_FILE=$gauntlet_file"
  echo "PROMOTION_EVENT_FILE=$event_target"
  echo "PROMOTION_EVENT_NUMBER=$event_label"
  echo "VERDICT=$verdict"
  echo "PROMOTION_PR_URL=$promotion_pr_url"
  echo "HEAD_SHA=$head_sha"
  echo "EXECUTION_CONTRACT_FINGERPRINT=$execution_fingerprint"
  echo "BASE_COMMIT_SHA=$base_commit_sha"
  echo "TARGET_BASE_SHA=$promotion_target_base_sha"
  echo "COMPLETION_EVENT=$completion_event_relative"
  echo "AFFECTED_UNITS=$affected_csv"
  echo
  cat "$event_stage"
  exit 0
fi

gauntlet_assert_source_hash
[[ -d "$promotion_dir" ]] || promotion_dir_created=1
mkdir -p "$promotion_dir"
gauntlet_assert_safe_ai_path "$promotion_dir" 'Gauntlet promotion events directory'
if [[ "$verdict" == 'fail' ]]; then
  gauntlet_install_no_clobber "$archive_stage" "$archive_target"
fi
if ! gauntlet_install_no_clobber "$event_stage" "$event_target"; then
  [[ -z "$archive_target" ]] || rm -f "$archive_target"
  exit 1
fi
if ! gauntlet_assert_source_hash; then
  rm -f "$event_target"
  [[ -z "$archive_target" ]] || rm -f "$archive_target"
  exit 1
fi
if ! mv "$main_stage" "$gauntlet_file"; then
  rm -f "$event_target"
  [[ -z "$archive_target" ]] || rm -f "$archive_target"
  exit 1
fi
if ! bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready >/dev/null; then
  cp "$backup_stage" "$gauntlet_file"
  rm -f "$event_target"
  [[ -z "$archive_target" ]] || rm -f "$archive_target"
  echo 'Promotion QA transition failed Gauntlet validation; GAUNTLET.md was restored.' >&2
  exit 1
fi
if [[ "$verdict" == 'fail' ]]; then
  rm -f "$report_file"
fi
rm -f "$backup_stage"
gauntlet_release_lock
trap - EXIT

echo "GAUNTLET_FILE=$gauntlet_file"
echo "PROMOTION_EVENT_FILE=$event_target"
echo "PROMOTION_EVENT_NUMBER=$event_label"
echo "VERDICT=$verdict"
echo "PROMOTION_PR_URL=$promotion_pr_url"
echo "HEAD_SHA=$head_sha"
echo "EXECUTION_CONTRACT_FINGERPRINT=$execution_fingerprint"
echo "BASE_COMMIT_SHA=$base_commit_sha"
echo "TARGET_BASE_SHA=$promotion_target_base_sha"
echo "COMPLETION_EVENT=$completion_event_relative"
echo "AFFECTED_UNITS=$affected_csv"
echo "ARCHIVED_REPORT=$archive_relative"
