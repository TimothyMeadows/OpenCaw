#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/record-gauntlet-round.sh "<gauntlet>" "<item-id>" "<verdict>" "<builder-id>" "<critic-id>" "<native-subagent|fresh-session>" "<critic-report.md>" --head-sha <sha> --builder-strategy <strategy> [--dry-run]

Records immutable critic evidence as rounds/<item-id>/round-NNN.md and updates
the Gauntlet work-unit state and round ledger only after all checks pass. Use the
reserved item id "integration" for the final independent integration review.
The critic report must inspect the supplied full commit SHA, and retries require
a changed concrete builder strategy.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"
invocation_dir="$(pwd)"

dry_run=0
head_sha=''
builder_strategy=''
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --head-sha)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      head_sha="$2"
      shift 2
      ;;
    --builder-strategy)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      builder_strategy="$2"
      shift 2
      ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) positional+=("$1"); shift ;;
  esac
done

[[ ${#positional[@]} -eq 7 ]] || { usage >&2; exit 1; }
[[ -n "$head_sha" && -n "$builder_strategy" ]] || { usage >&2; exit 1; }
gauntlet_ref="${positional[0]}"
item_id="${positional[1]}"
verdict="${positional[2]}"
builder_id="${positional[3]}"
critic_id="${positional[4]}"
isolation="${positional[5]}"
critic_report="${positional[6]}"

if [[ "$item_id" != 'integration' ]]; then
  gauntlet_validate_name "$item_id" 'item-id'
fi
case "$verdict" in pass|fail|blocked) ;; *) echo "verdict must be pass, fail, or blocked: $verdict" >&2; exit 1 ;; esac
gauntlet_validate_identifier "$builder_id" 'builder-id'
gauntlet_validate_identifier "$critic_id" 'critic-id'
builder_id_normalized="${builder_id,,}"
critic_id_normalized="${critic_id,,}"
[[ "$builder_id_normalized" != "$critic_id_normalized" ]] || { echo 'Builder and critic IDs must be distinct case-insensitively.' >&2; exit 1; }
case "$isolation" in native-subagent|fresh-session) ;; *) echo "Invalid critic isolation: $isolation" >&2; exit 1 ;; esac
gauntlet_validate_head_sha "$head_sha" 'head-sha'
head_sha="${head_sha,,}"
gauntlet_assert_commit_object "$head_sha" 'Reviewed head SHA'
gauntlet_validate_substantive_single_line "$builder_strategy" 'builder-strategy'
builder_strategy="$(gauntlet_trim "$builder_strategy")"
builder_strategy_fingerprint="$(gauntlet_strategy_fingerprint "$builder_strategy")"

if [[ "$critic_report" != /* ]]; then
  critic_report="$invocation_dir/$critic_report"
fi
[[ -f "$critic_report" ]] || { echo "Critic report not found: ${positional[6]}" >&2; exit 1; }

gauntlet_file="$(gauntlet_resolve_file "$gauntlet_ref")"
gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
gauntlet_name="$(basename "$gauntlet_dir")"
gauntlet_acquire_lock "$gauntlet_dir"
trap 'gauntlet_release_lock' EXIT
if [[ -e "$gauntlet_dir/rounds" || -L "$gauntlet_dir/rounds" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/rounds" 'Gauntlet rounds directory'
fi
gauntlet_status="$(gauntlet_section_field "$gauntlet_file" 'Flow and Status' 'Status')"
[[ "$gauntlet_status" != 'passed' ]] || {
  echo 'A passed Gauntlet is immutable; only a recorded failing promotion-QA event may reopen it.' >&2
  exit 1
}
bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready >/dev/null
gauntlet_capture_source_hash "$gauntlet_file"
execution_fingerprint="$(gauntlet_assert_frozen_execution_contract "$gauntlet_file")"
unit_manifest_fingerprint="$(gauntlet_assert_frozen_unit_manifest "$gauntlet_file")"
base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
gauntlet_validate_head_sha "$base_commit_sha" 'Gauntlet base commit SHA'
base_commit_sha="${base_commit_sha,,}"

if [[ -d "$gauntlet_dir/rounds" ]]; then
  while IFS= read -r prior_round; do
    prior_builder_id="$(gauntlet_section_field "$prior_round" 'Round Metadata' 'Builder ID')"
    prior_critic_id="$(gauntlet_section_field "$prior_round" 'Round Metadata' 'Critic ID')"
    if [[ "${prior_critic_id,,}" == "$critic_id_normalized" ]]; then
      echo "Critic invocation ID has already been used in this Gauntlet: $critic_id" >&2
      exit 1
    fi
    if [[ "${prior_builder_id,,}" == "$critic_id_normalized" \
      || "${prior_critic_id,,}" == "$builder_id_normalized" ]]; then
      echo 'Builder and critic identity sets must remain globally disjoint case-insensitively.' >&2
      exit 1
    fi
  done < <(find "$gauntlet_dir/rounds" -type f -name 'round-*.md' -print)
fi

gauntlet_validate_critic_report "$critic_report" "$verdict" "$head_sha"
quality_fingerprint="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
recorded_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Quality bar fingerprint')"
if [[ ! "$recorded_fingerprint" =~ ^[0-9a-f]{64}$ \
  || "${recorded_fingerprint,,}" != "${quality_fingerprint,,}" ]]; then
  echo 'A critic round requires the quality bar frozen by an accepted opened progress-PR event.' >&2
  exit 1
fi

if [[ "$item_id" == 'integration' ]]; then
  gauntlet_assert_commit_ancestor "$base_commit_sha" "$head_sha" 'Integration review approved base'
  scope_fingerprint="$(gauntlet_active_scope_fingerprint "$gauntlet_file")"
  progress_pr='none'
  progress_head="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  opened_event_relative='none'
  opened_event_hash='none'
  remediation_root='none'
  remediation_root_hash='none'
  if [[ "$verdict" == 'pass' ]]; then
    affected_units='none'
  else
    affected_units="$(gauntlet_work_unit_lines "$gauntlet_file" \
      | awk '$0 !~ /\|[[:space:]]status:[[:space:]]superseded[[:space:]]\|/' \
      | sed -nE 's/^- \[[ xX]\] ([a-z0-9]+(-[a-z0-9]+)*) \|.*$/\1/p' \
      | LC_ALL=C sort -u | paste -sd, -)"
    [[ -n "$affected_units" ]] || { echo 'Integration failure/block requires frozen affected-unit evidence.' >&2; exit 1; }
  fi
  while IFS= read -r unit_line; do
    if [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]]; then
      continue
    fi
    if [[ ! "$unit_line" =~ ^-[[:space:]]\[[xX]\].*\|[[:space:]]status:[[:space:]]passed[[:space:]]\| ]]; then
      echo "Integration review requires every active work unit to pass first: $unit_line" >&2
      exit 1
    fi
    integrated_item="$(printf '%s\n' "$unit_line" | sed -nE 's/^- \[[xX]\] ([a-z0-9-]+) \|.*$/\1/p')"
    gauntlet_assert_unit_progress_integrated \
      "$gauntlet_file" "$integrated_item" "$quality_fingerprint" "$head_sha" || exit 1
  done < <(gauntlet_work_unit_lines "$gauntlet_file")
  integration_chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")"
  [[ "$head_sha" == "$integration_chain_tip" ]] || {
    echo "Integration critic must inspect the exact reconstructed progress-PR merge-chain tip: expected $integration_chain_tip, observed $head_sha" >&2
    exit 1
  }
  gauntlet_assert_remote_integration_tip "$gauntlet_file" "$integration_chain_tip"
else
  unit_line="$(gauntlet_work_unit_lines "$gauntlet_file" | awk -v item="$item_id" '$0 ~ "^- \\[[ xX]\\] " item " \\|" { print; exit }')"
  [[ -n "$unit_line" ]] || { echo "Unknown work-unit id: $item_id" >&2; exit 1; }
  if [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]]; then
    echo "Cannot record a round for superseded work unit: $item_id" >&2
    exit 1
  fi
  gauntlet_load_latest_progress_pr "$gauntlet_dir" "$item_id"
  if [[ -z "$GAUNTLET_PROGRESS_EVENT_FILE" \
    || "$GAUNTLET_PROGRESS_EVENT" == 'merged' \
    || "$GAUNTLET_PROGRESS_EVENT" == 'closed' ]]; then
    echo "Work-unit rounds require a live progress PR: $item_id" >&2
    exit 1
  fi
  progress_pr="$GAUNTLET_PROGRESS_PR_URL"
  progress_head="$GAUNTLET_PROGRESS_HEAD_BRANCH"
  affected_units='none'
  opened_event_file="$(gauntlet_opened_event_for_pr "$gauntlet_dir" "$item_id" "$progress_pr")"
  opened_event_relative="${opened_event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
  opened_event_hash="$(gauntlet_hash_file "$opened_event_file")"
  remediation_root="$(gauntlet_resolve_remediation_root "$gauntlet_file" "$item_id" "$opened_event_file")"
  if [[ "$GAUNTLET_PROGRESS_EVENT" == 'qa-fail' ]]; then
    remediation_root="${GAUNTLET_PROGRESS_EVENT_FILE#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
  fi
  if [[ "$remediation_root" == 'none' ]]; then
    remediation_root_hash='none'
  else
    remediation_root_hash="$(gauntlet_hash_file "$OPENCAW_PROJECT_ROOT_RESOLVED/$remediation_root")"
  fi
  issue_url="$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Issue')"
  issue_repo="$(gauntlet_github_repo_from_url "$issue_url")"
  [[ -n "$issue_repo" ]] || { echo 'Parent task Issue must identify a GitHub repository.' >&2; exit 1; }
  gauntlet_assert_github_repository_identity "$issue_repo"
  integration_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  gauntlet_assert_live_pr "$progress_pr" "$issue_repo" "$progress_head" "$head_sha" "$integration_branch" open
  gauntlet_assert_progress_publication_body \
    "$GAUNTLET_GH_BODY" "$issue_url" "$opened_event_file"
  progress_chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")"
  [[ "$GAUNTLET_GH_BASE_SHA" == "$progress_chain_tip" ]] || {
    echo "Progress critic PR targets stale integration state: expected $progress_chain_tip, observed $GAUNTLET_GH_BASE_SHA" >&2
    exit 1
  }
  gauntlet_assert_local_branch_at_sha "$integration_branch" "$progress_chain_tip" 'Recorded Gauntlet integration chain tip'
  gauntlet_assert_local_branch_at_sha "$progress_head" "$head_sha" 'Progress PR head branch'
  scope_fingerprint="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$item_id")"
  [[ "$GAUNTLET_PROGRESS_SCOPE_FINGERPRINT" == "$scope_fingerprint" ]] || {
    echo "Live progress PR scope is stale for work unit: $item_id" >&2
    exit 1
  }
  [[ "$GAUNTLET_PROGRESS_EXECUTION_FINGERPRINT" == "$execution_fingerprint" ]] || {
    echo "Live progress PR execution contract is stale for work unit: $item_id" >&2
    exit 1
  }
  [[ "$GAUNTLET_PROGRESS_UNIT_MANIFEST_FINGERPRINT" == "$unit_manifest_fingerprint" ]] || {
    echo "Live progress PR unit manifest is stale for work unit: $item_id" >&2
    exit 1
  }
fi

item_round_dir="$gauntlet_dir/rounds/$item_id"
if [[ -e "$item_round_dir" || -L "$item_round_dir" ]]; then
  gauntlet_assert_safe_ai_path "$item_round_dir" 'Gauntlet item rounds directory'
fi
max_round=0
if [[ -d "$item_round_dir" ]]; then
  while IFS= read -r existing_round; do
    existing_name="$(basename "$existing_round")"
    if [[ "$existing_name" =~ ^round-([0-9]+)\.md$ ]]; then
      existing_number=$((10#${BASH_REMATCH[1]}))
      (( existing_number > max_round )) && max_round=$existing_number
    fi
  done < <(find "$item_round_dir" -maxdepth 1 -type f -name 'round-*.md' -print)
fi

latest_prior_round="$(gauntlet_latest_round_file "$item_round_dir")"
if [[ "$item_id" != 'integration' ]]; then
  if [[ -n "$latest_prior_round" ]]; then
    prior_round_relative="${latest_prior_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    prior_round_pr="$(gauntlet_section_field "$latest_prior_round" 'Round Metadata' 'Progress PR')"
    prior_round_head_sha="$(gauntlet_section_field "$latest_prior_round" 'Round Metadata' 'Head SHA')"
    if [[ "${prior_round_pr%/}" == "$progress_pr" ]]; then
      [[ "$GAUNTLET_PROGRESS_EVENT" == 'qa-fail' \
        && "$GAUNTLET_PROGRESS_CRITIC_ROUND" == "$prior_round_relative" ]] || {
        echo 'A live progress PR may record another round only after QA fails its latest round.' >&2
        exit 1
      }
      gauntlet_assert_commit_ancestor "$prior_round_head_sha" "$head_sha" 'Same-PR critic retry fast-forward lineage'
    else
      [[ "$GAUNTLET_PROGRESS_EVENT" == 'opened' ]] || {
        echo 'A remediation PR must begin with a new opened event before its first critic round.' >&2
        exit 1
      }
      [[ "${head_sha,,}" == "${GAUNTLET_PROGRESS_HEAD_SHA,,}" ]] || {
        echo 'The first remediation round Head SHA must match its opened PR event.' >&2
        exit 1
      }
    fi
    [[ "${head_sha,,}" != "${prior_round_head_sha,,}" ]] || {
      echo 'A repeated work-unit attempt must review a new head commit SHA.' >&2
      exit 1
    }
  else
    [[ "$GAUNTLET_PROGRESS_EVENT" == 'opened' \
      && "${head_sha,,}" == "${GAUNTLET_PROGRESS_HEAD_SHA,,}" ]] || {
      echo 'The first work-unit round Head SHA must match its opened PR event.' >&2
      exit 1
    }
  fi
else
  latest_prior_round="$(gauntlet_latest_round_file "$gauntlet_dir/rounds/integration")"
fi

if [[ -d "$item_round_dir" ]]; then
  while IFS= read -r prior_strategy_round; do
    [[ -n "$prior_strategy_round" ]] || continue
    gauntlet_round_has_retained_failure "$gauntlet_file" "$prior_strategy_round" || continue
    prior_builder_strategy_fingerprint="$(gauntlet_section_field "$prior_strategy_round" 'Round Metadata' 'Builder strategy fingerprint')"
    [[ "$builder_strategy_fingerprint" != "$prior_builder_strategy_fingerprint" ]] || {
      echo "A repeated attempt cannot reuse any retained failed, blocked, or QA-failed builder strategy; it matches ${prior_strategy_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}." >&2
      exit 1
    }
  done < <(find "$item_round_dir" -maxdepth 1 -type f -name 'round-*.md' -print | LC_ALL=C sort)
fi

next_round=$((max_round + 1))
printf -v round_label '%03d' "$next_round"
round_relative=".ai/gauntlets/$gauntlet_name/rounds/$item_id/round-$round_label.md"
round_target="$OPENCAW_PROJECT_ROOT_RESOLVED/$round_relative"
[[ ! -e "$round_target" ]] || { echo "Round evidence already exists: $round_relative" >&2; exit 1; }

recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [[ "$opened_event_relative" != 'none' ]]; then
  opened_recorded_at="$(gauntlet_section_field "$opened_event_file" 'PR Event Metadata' 'Recorded at')"
  [[ "$opened_recorded_at" < "$recorded_at" || "$opened_recorded_at" == "$recorded_at" ]] || {
    echo 'Critic round predates its hash-anchored opened progress-PR event.' >&2
    exit 1
  }
fi
round_stage="$(mktemp "$gauntlet_dir/.round-stage.XXXXXX")"
main_stage="$(mktemp "$gauntlet_dir/.main-stage.XXXXXX")"
backup_stage="$(mktemp "$gauntlet_dir/.backup-stage.XXXXXX")"
cp "$gauntlet_file" "$backup_stage"
round_root_created=0
round_dir_created=0
cleanup_round_stage() {
  rm -f "$round_stage" "$main_stage" "$backup_stage"
  if [[ $round_dir_created -eq 1 ]]; then
    rmdir "$item_round_dir" 2>/dev/null || true
  fi
  if [[ $round_root_created -eq 1 ]]; then
    rmdir "$gauntlet_dir/rounds" 2>/dev/null || true
  fi
  gauntlet_release_lock
}
trap cleanup_round_stage EXIT

cat > "$round_stage" <<EOF
# Gauntlet Round: $item_id / $round_label

## Round Metadata
- Item: $item_id
- Round: $round_label
- Verdict: $verdict
- Builder ID: $builder_id
- Critic ID: $critic_id
- Isolation: $isolation
- Progress PR: $progress_pr
- Head branch: $progress_head
- Head SHA: $head_sha
- Scope fingerprint: $scope_fingerprint
- Unit manifest fingerprint: $unit_manifest_fingerprint
- Quality bar fingerprint: $quality_fingerprint
- Execution contract fingerprint: $execution_fingerprint
- Base commit SHA: $base_commit_sha
- Opened event: $opened_event_relative
- Opened event sha256: $opened_event_hash
- Remediation root: $remediation_root
- Remediation root sha256: $remediation_root_hash
- Affected units: $affected_units
- Builder strategy: $builder_strategy
- Builder strategy fingerprint: $builder_strategy_fingerprint
- Critic next strategy fingerprint: $GAUNTLET_CRITIC_NEXT_STRATEGY_FINGERPRINT
- Recorded at: $recorded_at

EOF
sed 's/\r$//' "$critic_report" >> "$round_stage"
printf '\n' >> "$round_stage"
round_hash="$(gauntlet_hash_file "$round_stage")"

cp "$gauntlet_file" "$main_stage"
gauntlet_set_section_field "$main_stage" 'Current State' 'Quality bar fingerprint' "$quality_fingerprint"
gauntlet_set_section_field "$main_stage" 'Current State' 'Unit manifest fingerprint' "$unit_manifest_fingerprint"
gauntlet_set_section_field "$main_stage" 'Current State' 'Latest round' "$item_id/$round_label ($verdict)"
gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' "$item_id"
gauntlet_set_section_field "$main_stage" 'Delivery' 'PR eligible' 'no'

if [[ "$item_id" == 'integration' ]]; then
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Verdict' "$verdict"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Critic ID' "$critic_id"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Isolation' "$isolation"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Evidence' "\`$round_relative\`"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Head SHA' "$head_sha"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Scope fingerprint' "$scope_fingerprint"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Quality bar fingerprint' "$quality_fingerprint"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Unit manifest fingerprint' "$unit_manifest_fingerprint"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Execution contract fingerprint' "$execution_fingerprint"
  gauntlet_set_section_field "$main_stage" 'Integration Review' 'Base commit SHA' "$base_commit_sha"
  case "$verdict" in
    pass)
      gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' 'none'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Generate the Gauntlet completion report and pass the human PR readiness gate.'
      ;;
    fail)
      gauntlet_reopen_active_units "$main_stage"
      gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Rebuild every reopened active unit with changed strategies, then run a fresh integration critic.'
      ;;
    blocked)
      gauntlet_reopen_active_units "$main_stage"
      gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'blocked'
      gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Resolve the recorded integration blocker, resume the reopened units explicitly, or generate a blocked completion report.'
      ;;
  esac
else
  case "$verdict" in
    pass)
      unit_status='passed'
      next_action='Continue remaining work units or run the fresh integration critic when all active units pass.'
      ;;
    fail)
      unit_status='critic-failed'
      next_action='Rebuild this work unit with a changed actual builder strategy informed by the critic gap, then use a new critic invocation.'
      ;;
    blocked)
      unit_status='blocked'
      next_action='Resolve the recorded blocker or generate a blocked completion report.'
      ;;
  esac
  gauntlet_set_work_unit_status "$main_stage" "$item_id" "$unit_status"
  gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' "$([[ "$verdict" == 'blocked' ]] && printf blocked || printf running)"
  gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' "$next_action"

  # Any unit work after an integration review invalidates that integration pass.
  if [[ "$(gauntlet_section_field "$main_stage" 'Integration Review' 'Verdict')" != 'pending' ]]; then
    gauntlet_reset_integration_review "$main_stage"
  fi
fi

ledger_entry="- $item_id | round: $round_label | verdict: $verdict | head-sha: $head_sha | scope: $scope_fingerprint | manifest: $unit_manifest_fingerprint | contract: $execution_fingerprint | base-sha: $base_commit_sha | opened: $opened_event_relative | opened-sha256: $opened_event_hash | root: $remediation_root | root-sha256: $remediation_root_hash | affected-units: $affected_units | builder: $builder_id | critic: $critic_id | isolation: $isolation | evidence: $round_relative | sha256: $round_hash"
gauntlet_append_round_ledger "$main_stage" "$ledger_entry"
chmod 0644 "$main_stage" "$round_stage"

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $round_target"
  echo "GAUNTLET_FILE=$gauntlet_file"
  echo "ROUND_FILE=$round_target"
  echo "ROUND_NUMBER=$round_label"
  echo "VERDICT=$verdict"
  echo "HEAD_SHA=$head_sha"
  echo "SCOPE_FINGERPRINT=$scope_fingerprint"
  echo "QUALITY_BAR_FINGERPRINT=$quality_fingerprint"
  echo "EXECUTION_CONTRACT_FINGERPRINT=$execution_fingerprint"
  echo "BASE_COMMIT_SHA=$base_commit_sha"
  echo
  cat "$round_stage"
  exit 0
fi

gauntlet_assert_source_hash
[[ -d "$gauntlet_dir/rounds" ]] || round_root_created=1
[[ -d "$item_round_dir" ]] || round_dir_created=1
mkdir -p "$item_round_dir"
gauntlet_assert_safe_ai_path "$item_round_dir" 'Gauntlet item rounds directory'
gauntlet_install_no_clobber "$round_stage" "$round_target"
if ! gauntlet_assert_source_hash; then
  rm -f "$round_target"
  exit 1
fi
if ! mv "$main_stage" "$gauntlet_file"; then
  rm -f "$round_target"
  exit 1
fi
if ! bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase structure >/dev/null; then
  cp "$backup_stage" "$gauntlet_file"
  rm -f "$round_target"
  echo 'Gauntlet round transition failed replay validation; GAUNTLET.md was restored.' >&2
  exit 1
fi
rm -f "$backup_stage"
gauntlet_release_lock
trap - EXIT

echo "GAUNTLET_FILE=$gauntlet_file"
echo "ROUND_FILE=$round_target"
echo "ROUND_NUMBER=$round_label"
echo "VERDICT=$verdict"
echo "HEAD_SHA=$head_sha"
echo "SCOPE_FINGERPRINT=$scope_fingerprint"
echo "QUALITY_BAR_FINGERPRINT=$quality_fingerprint"
echo "EXECUTION_CONTRACT_FINGERPRINT=$execution_fingerprint"
echo "BASE_COMMIT_SHA=$base_commit_sha"
