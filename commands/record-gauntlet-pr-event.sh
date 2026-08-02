#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/record-gauntlet-pr-event.sh "<gauntlet>" "<item-id>" "<opened|qa-pass|qa-fail|merged|closed>" "<pr-url>" "<head-branch>" "<evidence-url|none>" --head-sha <sha> [--merge-commit <sha>] [--dry-run]

Records an immutable progress-PR lifecycle event under
pr-events/<item-id>/event-NNN.md. Progress PRs target the Gauntlet integration
branch, require per-PR QA, and may be merged only by a human. Recording rejects
any retained auto-merge, auto-rebase, auto-squash, or merge-queue timeline event,
even if that automation was later disabled. Progress and remediation PRs must
use `Refs #<issue>` as the exact first body line; every closing-keyword alias is
reserved for the final promotion PR.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"

dry_run=0
merge_commit='none'
head_sha=''
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --head-sha)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      head_sha="$2"
      shift 2
      ;;
    --merge-commit)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      merge_commit="$2"
      shift 2
      ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) positional+=("$1"); shift ;;
  esac
done

[[ ${#positional[@]} -eq 6 ]] || { usage >&2; exit 1; }
[[ -n "$head_sha" ]] || { usage >&2; exit 1; }
gauntlet_ref="${positional[0]}"
item_id="${positional[1]}"
event="${positional[2]}"
pr_url="${positional[3]%/}"
head_branch="${positional[4]}"
evidence_url="${positional[5]}"

gauntlet_validate_name "$item_id" 'item-id'
[[ "$item_id" != 'integration' ]] || { echo 'Integration is not a progress-PR work unit.' >&2; exit 1; }
case "$event" in opened|qa-pass|qa-fail|merged|closed) ;; *) echo "Invalid PR event: $event" >&2; exit 1 ;; esac
gauntlet_validate_github_pr_url "$pr_url" 'PR URL'
gauntlet_validate_branch "$head_branch" 'Head branch'
gauntlet_validate_evidence_url "$evidence_url" 'Evidence URL'
gauntlet_validate_head_sha "$head_sha" 'head-sha'
head_sha="${head_sha,,}"
gauntlet_assert_commit_object "$head_sha" 'Progress PR head SHA'
case "$event" in
  opened)
    [[ "$evidence_url" == 'none' ]] || { echo 'An opened event must use evidence URL none.' >&2; exit 1; }
    [[ "$merge_commit" == 'none' ]] || { echo 'Only a merged event may include --merge-commit.' >&2; exit 1; }
    ;;
  qa-pass|qa-fail|closed)
    [[ "$evidence_url" != 'none' ]] || { echo "$event requires an HTTPS evidence URL." >&2; exit 1; }
    [[ "$merge_commit" == 'none' ]] || { echo 'Only a merged event may include --merge-commit.' >&2; exit 1; }
    ;;
  merged)
    [[ "$evidence_url" != 'none' ]] || { echo 'A merged event requires an HTTPS human-merge evidence URL.' >&2; exit 1; }
    [[ "$merge_commit" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]] || {
      echo 'A merged event requires --merge-commit with a full 40- or 64-character hexadecimal SHA.' >&2
      exit 1
    }
    merge_commit="${merge_commit,,}"
    gauntlet_assert_commit_object "$merge_commit" 'Progress PR merge commit'
    ;;
esac
case "$event" in
  qa-pass|qa-fail)
    gauntlet_validate_pr_evidence_url "$evidence_url" "$pr_url" no
    ;;
  merged|closed)
    gauntlet_validate_pr_evidence_url "$evidence_url" "$pr_url" yes
    ;;
esac

gauntlet_file="$(gauntlet_resolve_file "$gauntlet_ref")"
gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
gauntlet_name="$(basename "$gauntlet_dir")"
gauntlet_acquire_lock "$gauntlet_dir"
trap 'gauntlet_release_lock' EXIT
event_root="$gauntlet_dir/pr-events"
event_dir="$event_root/$item_id"
if [[ -e "$event_root" || -L "$event_root" ]]; then
  gauntlet_assert_safe_ai_path "$event_root" 'Gauntlet PR events directory'
fi
if [[ -e "$event_dir" || -L "$event_dir" ]]; then
  gauntlet_assert_safe_ai_path "$event_dir" 'Gauntlet item PR events directory'
fi

gauntlet_capture_source_hash "$gauntlet_file"
gauntlet_status="$(gauntlet_section_field "$gauntlet_file" 'Flow and Status' 'Status')"
[[ "$gauntlet_status" != 'passed' ]] || {
  echo 'A passed Gauntlet is immutable; only a recorded failing promotion-QA event may reopen it.' >&2
  exit 1
}
if [[ "$event" == 'merged' || "$event" == 'closed' ]]; then
  [[ "$gauntlet_status" == 'ready' || "$gauntlet_status" == 'running' ]] || {
    echo "Terminal progress-PR events require a ready or running Gauntlet, not $gauntlet_status." >&2
    exit 1
  }
  # A legitimate terminal transition changes live GitHub state before its
  # immutable event can be recorded. Replay durable structure first, then prove
  # the exact close or human-merge observation explicitly below.
  bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase structure >/dev/null
else
  bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready >/dev/null
fi
gauntlet_assert_source_hash
execution_fingerprint="$(gauntlet_execution_contract_fingerprint "$gauntlet_file")"
recorded_execution_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Execution contract fingerprint')"
quality_fingerprint="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
recorded_quality_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Quality bar fingerprint')"
unit_manifest_fingerprint="$(gauntlet_unit_manifest_fingerprint "$gauntlet_file")"
recorded_unit_manifest_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Unit manifest fingerprint')"
if [[ "$recorded_execution_fingerprint" == 'pending' ]]; then
  [[ "$event" == 'opened' && "$recorded_quality_fingerprint" == 'pending' \
    && "$recorded_unit_manifest_fingerprint" == 'pending' ]] || {
    echo 'The first immutable Gauntlet evidence must be an opened progress-PR event that atomically freezes the quality bar, unit manifest, and execution contract.' >&2
    exit 1
  }
else
  [[ "$recorded_execution_fingerprint" =~ ^[0-9a-fA-F]{64}$ \
    && "${recorded_execution_fingerprint,,}" == "$execution_fingerprint" ]] || {
    echo 'Gauntlet execution contract changed after progress-PR publication was authorized.' >&2
    exit 1
  }
  if [[ "$recorded_quality_fingerprint" == 'pending' ]]; then
    [[ "$event" == 'opened' ]] || {
      echo 'Only an accepted opened remediation PR may refreeze a canonically revised quality bar.' >&2
      exit 1
    }
  else
    [[ "${recorded_quality_fingerprint,,}" == "$quality_fingerprint" ]] || {
      echo 'Approved Quality Bar changed after it was frozen.' >&2
      exit 1
    }
  fi
  if [[ "$recorded_unit_manifest_fingerprint" == 'pending' ]]; then
    [[ "$event" == 'opened' ]] || {
      echo 'Only an accepted affected-unit opened PR may refreeze a canonically revised unit manifest.' >&2
      exit 1
    }
  else
    [[ "${recorded_unit_manifest_fingerprint,,}" == "$unit_manifest_fingerprint" ]] || {
      echo 'Work-unit manifest changed after it was frozen.' >&2
      exit 1
    }
  fi
fi
base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
gauntlet_validate_head_sha "$base_commit_sha" 'Gauntlet base commit SHA'
base_commit_sha="${base_commit_sha,,}"
unit_line="$(gauntlet_work_unit_lines "$gauntlet_file" | awk -v item="$item_id" '$0 ~ "^- \\[[ xX]\\] " item " \\|" { print; exit }')"
[[ -n "$unit_line" ]] || { echo "Unknown work-unit id: $item_id" >&2; exit 1; }
[[ ! "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]] || {
  echo "Cannot record a progress-PR event for superseded work unit: $item_id" >&2
  exit 1
}

integration_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
[[ "$integration_branch" == "gauntlet/$gauntlet_name" ]] || {
  echo "Integration branch must be gauntlet/$gauntlet_name." >&2
  exit 1
}
progress_branch_prefix="gauntlet-work/$gauntlet_name/"
[[ "$head_branch" == "$progress_branch_prefix"* ]] || {
  echo "Progress PR head branch must be under $progress_branch_prefix: $head_branch" >&2
  exit 1
}

issue_url="$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Issue')"
issue_repo="$(gauntlet_github_repo_from_url "$issue_url")"
pr_repo="$(gauntlet_github_repo_from_url "$pr_url")"
[[ -n "$issue_repo" && "${pr_repo,,}" == "${issue_repo,,}" ]] || {
  echo 'Progress PR must belong to the same GitHub repository as the parent issue.' >&2
  exit 1
}
gauntlet_assert_github_repository_identity "$issue_repo"

case "$event" in
  opened|qa-pass|qa-fail)
    expected_live_state='open'
    ;;
  merged)
    expected_live_state='merged'
    ;;
  closed)
    expected_live_state='closed'
    ;;
esac
gauntlet_assert_live_pr "$pr_url" "$issue_repo" "$head_branch" "$head_sha" "$integration_branch" "$expected_live_state"
gauntlet_assert_progress_issue_link "$GAUNTLET_GH_BODY" "$issue_url"
gauntlet_parse_publication_checkpoint_marker "$GAUNTLET_GH_BODY"
publication_checkpoint="$GAUNTLET_PUBLICATION_CHECKPOINT"
publication_checkpoint_hash="$GAUNTLET_PUBLICATION_CHECKPOINT_SHA256"
publication_checkpoint_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$publication_checkpoint"
[[ "$publication_checkpoint" =~ ^\.ai/gauntlets/${gauntlet_name}/publication-checkpoints/${item_id}/checkpoint-[0-9]{3,}\.md$ \
  && -f "$publication_checkpoint_file" && ! -L "$publication_checkpoint_file" \
  && "$publication_checkpoint_hash" == "$(gauntlet_hash_file "$publication_checkpoint_file")" ]] || {
  echo 'Progress PR publication marker does not bind canonical immutable checkpoint evidence.' >&2
  exit 1
}
if [[ "$event" == 'qa-pass' || "$event" == 'qa-fail' ]]; then
  gauntlet_assert_unique_qa_comment "$gauntlet_dir" "$evidence_url"
fi
observed_state="$GAUNTLET_GH_STATE"
observed_draft="$GAUNTLET_GH_IS_DRAFT"
observed_created_at="$GAUNTLET_GH_CREATED_AT"
observed_closed_at="${GAUNTLET_GH_CLOSED_AT:-none}"
observed_merged_at="${GAUNTLET_GH_MERGED_AT:-none}"
observed_merged_by="${GAUNTLET_GH_MERGED_BY:-none}"
observed_merged_by_type="${GAUNTLET_GH_MERGED_BY_TYPE:-none}"
observed_merged_by_bot="${GAUNTLET_GH_MERGED_BY_BOT:-none}"
observed_target_base_sha="${GAUNTLET_GH_BASE_SHA,,}"
observed_cross_repository="$GAUNTLET_GH_IS_CROSS_REPOSITORY"
observed_head_repository="$GAUNTLET_GH_HEAD_REPOSITORY"
prior_chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")"
if [[ "$event" == 'merged' ]]; then
  [[ "$GAUNTLET_GH_MERGE_COMMIT" == "$merge_commit" ]] || {
    echo "Recorded merge commit does not match live GitHub mergeCommit: $merge_commit" >&2
    exit 1
  }
  [[ "$observed_target_base_sha" == "$prior_chain_tip" ]] || {
    echo "Merged progress PR does not continue the recorded integration chain: expected target base $prior_chain_tip, observed $observed_target_base_sha" >&2
    exit 1
  }
  gauntlet_assert_local_branch_at_sha "$integration_branch" "$merge_commit" 'Just-merged Gauntlet integration branch'
else
  [[ "$observed_target_base_sha" == "$prior_chain_tip" ]] || {
    echo "Progress PR observation targets stale or unrecorded integration state: expected $prior_chain_tip, observed $observed_target_base_sha" >&2
    exit 1
  }
  gauntlet_assert_local_branch_at_sha "$integration_branch" "$prior_chain_tip" 'Recorded Gauntlet integration chain tip'
fi

# A PR URL belongs to exactly one retained work unit, including closed and
# merged history. A remediation cycle must receive a new PR URL.
if [[ -d "$event_root" ]]; then
  while IFS= read -r owner_event; do
    owner_item="$(gauntlet_section_field "$owner_event" 'PR Event Metadata' 'Item')"
    owner_pr="$(gauntlet_section_field "$owner_event" 'PR Event Metadata' 'PR URL')"
    owner_pr="${owner_pr%/}"
    if [[ "$owner_pr" == "$pr_url" && "$owner_item" != "$item_id" ]]; then
      echo "Progress PR is already owned by another work unit: $owner_item" >&2
      exit 1
    fi
  done < <(find "$event_root" -type f -name 'event-*.md' -print)
fi

gauntlet_load_latest_progress_pr "$gauntlet_dir" "$item_id"
previous_event_file="$GAUNTLET_PROGRESS_EVENT_FILE"
previous_event="$GAUNTLET_PROGRESS_EVENT"
previous_pr="$GAUNTLET_PROGRESS_PR_URL"
previous_head="$GAUNTLET_PROGRESS_HEAD_BRANCH"
previous_head_sha="$GAUNTLET_PROGRESS_HEAD_SHA"
previous_scope_fingerprint="$GAUNTLET_PROGRESS_SCOPE_FINGERPRINT"
previous_execution_fingerprint="$GAUNTLET_PROGRESS_EXECUTION_FINGERPRINT"
previous_round="$GAUNTLET_PROGRESS_CRITIC_ROUND"
remediation_trigger='none'
if [[ -n "$previous_event_file" && "$event" != 'opened' ]]; then
  [[ "$publication_checkpoint" == "$(gauntlet_section_field "$previous_event_file" 'PR Event Metadata' 'Publication checkpoint')" \
    && "$publication_checkpoint_hash" == "$(gauntlet_section_field "$previous_event_file" 'PR Event Metadata' 'Publication checkpoint sha256')" ]] || {
    echo 'Live progress PR body changed its immutable publication checkpoint marker.' >&2
    exit 1
  }
fi

case "$event" in
  opened)
    if [[ -n "$previous_event" && "$previous_event" != 'merged' && "$previous_event" != 'closed' ]]; then
      echo "Work unit already has a live progress PR: $previous_pr" >&2
      exit 1
    fi
    if [[ -n "$previous_event" ]]; then
      [[ "$pr_url" != "$previous_pr" ]] || {
        echo 'A remediation cycle requires a new progress PR URL.' >&2
        exit 1
      }
      remediation_trigger="$(gauntlet_remediation_trigger "$gauntlet_file" "$item_id" "$previous_event_file")" || {
        echo 'A merged progress PR may reopen only after a later integration failure/block, a promotion-QA failure naming this unit, or an approved quality-bar revision reset.' >&2
        exit 1
      }
      while IFS= read -r prior_event_file; do
        if grep -Fqx -- "- Remediation trigger: $remediation_trigger" "$prior_event_file"; then
          echo "Remediation trigger was already consumed for this work unit: $remediation_trigger" >&2
          exit 1
        fi
      done < <(find "$event_dir" -maxdepth 1 -type f -name 'event-*.md' -print 2>/dev/null || true)
    elif inherited_trigger="$(gauntlet_remediation_trigger "$gauntlet_file" "$item_id" '')"; then
      remediation_trigger="$inherited_trigger"
    fi
    opened_count=0
    if [[ -d "$event_dir" ]]; then
      while IFS= read -r prior_event_file; do
        [[ "$(gauntlet_section_field "$prior_event_file" 'PR Event Metadata' 'Event')" == 'opened' ]] \
          && opened_count=$((opened_count + 1))
      done < <(find "$event_dir" -maxdepth 1 -type f -name 'event-*.md' -print)
    fi
    if [[ $opened_count -eq 0 ]]; then
      expected_head_branch="${progress_branch_prefix}${item_id}"
    else
      expected_head_branch="${progress_branch_prefix}${item_id}-remediation-$opened_count"
    fi
    [[ "$head_branch" == "$expected_head_branch" ]] || {
      echo "Progress PR head branch must use the deterministic Gauntlet branch: $expected_head_branch" >&2
      exit 1
    }
    gauntlet_assert_local_branch_at_sha "$head_branch" "$head_sha" 'Progress PR head branch'
    gauntlet_assert_commit_ancestor "$prior_chain_tip" "$head_sha" 'Progress PR head from current integration chain tip'
    ;;
  qa-pass|qa-fail|merged|closed)
    [[ -n "$previous_event" && "$previous_event" != 'merged' && "$previous_event" != 'closed' ]] || {
      echo "$event requires a live opened progress PR." >&2
      exit 1
    }
    [[ "$pr_url" == "$previous_pr" && "$head_branch" == "$previous_head" ]] || {
      echo "PR URL and head branch must match the live progress PR for $item_id." >&2
      exit 1
    }
    if [[ "$event" == 'qa-pass' || "$event" == 'qa-fail' || "$event" == 'closed' ]]; then
      gauntlet_assert_local_branch_at_sha "$head_branch" "$head_sha" 'Progress PR head branch'
    fi
    gauntlet_assert_commit_ancestor "$previous_head_sha" "$head_sha" 'Progress PR no-force fast-forward lineage'
    ;;
esac

scope_fingerprint="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$item_id")"
if [[ "$event" == 'opened' ]]; then
  latest_issued_checkpoint=''
  checkpoint_item_dir="$gauntlet_dir/publication-checkpoints/$item_id"
  while IFS=$'\t' read -r _checkpoint_number issued_checkpoint_file; do
    [[ -n "$issued_checkpoint_file" ]] || continue
    issued_checkpoint_relative="${issued_checkpoint_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    issued_checkpoint_consumed=0
    if [[ -d "$event_root" ]]; then
      while IFS= read -r prior_checkpoint_event; do
        [[ "$(gauntlet_section_field "$prior_checkpoint_event" 'PR Event Metadata' 'Event')" == 'opened' \
          && "$(gauntlet_section_field "$prior_checkpoint_event" 'PR Event Metadata' 'Publication checkpoint')" == "$issued_checkpoint_relative" ]] \
          && issued_checkpoint_consumed=1
      done < <(find "$event_root" -type f -name 'event-*.md' -print)
    fi
    [[ "$issued_checkpoint_consumed" -eq 1 ]] || latest_issued_checkpoint="$issued_checkpoint_relative"
  done < <(find "$checkpoint_item_dir" -maxdepth 1 -type f -name 'checkpoint-*.md' -print \
    | awk '{ name=$0; sub(/^.*\/checkpoint-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
    | LC_ALL=C sort -n -k1,1)
  [[ -n "$latest_issued_checkpoint" && "$publication_checkpoint" == "$latest_issued_checkpoint" ]] || {
    echo "Opened progress PR must consume the latest numerically issued, unconsumed publication checkpoint: ${latest_issued_checkpoint:-none}" >&2
    exit 1
  }

  for checkpoint_key in 'Item' 'Sequence' 'Head branch' 'Head SHA' 'Target branch' 'Chain tip' \
    'Remediation trigger' 'Remediation trigger sha256' 'Remediation root' 'Remediation root sha256' \
    'Quality bar fingerprint' 'Quality bar approved at' 'Unit scope fingerprint' 'Unit manifest fingerprint' \
    'Unit manifest approved at' \
    'Execution contract fingerprint' 'Remote integration state' 'Remote integration SHA' \
    'Remote work state' 'Remote work SHA' 'Recorded at'; do
    [[ "$(gauntlet_section_field_count "$publication_checkpoint_file" 'Publication Checkpoint Metadata' "$checkpoint_key")" -eq 1 ]] || {
      echo "Publication checkpoint requires exactly one '$checkpoint_key' field: $publication_checkpoint" >&2
      exit 1
    }
  done
  checkpoint_trigger="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation trigger')"
  checkpoint_trigger_hash="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation trigger sha256')"
  checkpoint_root="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root')"
  checkpoint_root_hash="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root sha256')"
  checkpoint_quality_approved_at="$(gauntlet_section_field \
    "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar approved at')"
  checkpoint_manifest_approved_at="$(gauntlet_section_field \
    "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Unit manifest approved at')"
  checkpoint_recorded_at="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Recorded at')"
  quality_approved_at="$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Approved at')"
  manifest_approved_at="$(gauntlet_unit_manifest_approved_at \
    "$gauntlet_file" "$unit_manifest_fingerprint")"
  expected_trigger_hash="$(gauntlet_remediation_trigger_hash "$gauntlet_file" "$remediation_trigger")"
  expected_root="$(gauntlet_remediation_root_for_trigger \
    "$gauntlet_file" "$item_id" "$remediation_trigger" "$checkpoint_recorded_at")"
  if [[ "$expected_root" == 'none' ]]; then
    expected_root_hash='none'
  else
    expected_root_hash="$(gauntlet_hash_file "$OPENCAW_PROJECT_ROOT_RESOLVED/$expected_root")"
  fi
  checkpoint_remote_integration_state="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remote integration state')"
  checkpoint_remote_integration_sha="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remote integration SHA' | tr '[:upper:]' '[:lower:]')"
  checkpoint_remote_work_state="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remote work state')"
  checkpoint_remote_work_sha="$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Remote work SHA' | tr '[:upper:]' '[:lower:]')"
  checkpoint_remote_integration_valid=0
  if [[ "$checkpoint_remote_integration_state" == 'exact' \
    && "$checkpoint_remote_integration_sha" == "$prior_chain_tip" ]]; then
    checkpoint_remote_integration_valid=1
  elif [[ "$checkpoint_remote_integration_state" == 'absent-create-only' \
    && "$checkpoint_remote_integration_sha" == 'absent' \
    && "$(gauntlet_immutable_evidence_count "$gauntlet_dir")" -eq 0 ]]; then
    gauntlet_fetch_origin
    gauntlet_observe_remote_branch "$integration_branch" 'Gauntlet integration branch'
    [[ "$GAUNTLET_REMOTE_BRANCH_SHA" == "$prior_chain_tip" ]] \
      && checkpoint_remote_integration_valid=1
  fi
  [[ "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Item')" == "$item_id" \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Head branch')" == "$head_branch" \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" == "$head_sha" \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Target branch')" == "$integration_branch" \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Chain tip' | tr '[:upper:]' '[:lower:]')" == "$prior_chain_tip" \
    && "$checkpoint_trigger" == "$remediation_trigger" \
    && "$checkpoint_trigger_hash" == "$expected_trigger_hash" \
    && "$checkpoint_root" == "$expected_root" \
    && "$checkpoint_root_hash" == "$expected_root_hash" \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar fingerprint')" == "$quality_fingerprint" \
    && "$checkpoint_quality_approved_at" == "$quality_approved_at" \
    && "$checkpoint_quality_approved_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
    && ( "$checkpoint_quality_approved_at" < "$checkpoint_recorded_at" \
      || "$checkpoint_quality_approved_at" == "$checkpoint_recorded_at" ) \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Unit scope fingerprint')" == "$scope_fingerprint" \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Unit manifest fingerprint')" == "$unit_manifest_fingerprint" \
    && "$checkpoint_manifest_approved_at" == "$manifest_approved_at" \
    && "$checkpoint_manifest_approved_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
    && ( "$checkpoint_manifest_approved_at" < "$checkpoint_recorded_at" \
      || "$checkpoint_manifest_approved_at" == "$checkpoint_recorded_at" ) \
    && "$(gauntlet_section_field "$publication_checkpoint_file" 'Publication Checkpoint Metadata' 'Execution contract fingerprint')" == "$execution_fingerprint" \
    && "$checkpoint_remote_integration_valid" -eq 1 \
    && ( ( "$checkpoint_remote_work_state" == 'exact' && "$checkpoint_remote_work_sha" == "$head_sha" ) \
      || ( "$checkpoint_remote_work_state" == 'absent-create-only' && "$checkpoint_remote_work_sha" == 'absent' ) ) \
    && ( "$checkpoint_recorded_at" < "$observed_created_at" || "$checkpoint_recorded_at" == "$observed_created_at" ) ]] || {
    echo 'Opened progress PR does not match its current publication checkpoint contract and external creation time.' >&2
    exit 1
  }
  if [[ -d "$event_root" ]]; then
    while IFS= read -r prior_checkpoint_event; do
      [[ "$(gauntlet_section_field "$prior_checkpoint_event" 'PR Event Metadata' 'Event')" == 'opened' ]] || continue
      [[ "$(gauntlet_section_field "$prior_checkpoint_event" 'PR Event Metadata' 'Publication checkpoint')" != "$publication_checkpoint" ]] || {
        echo "Publication checkpoint has already been consumed by an opened event: $publication_checkpoint" >&2
        exit 1
      }
    done < <(find "$event_root" -type f -name 'event-*.md' -print)
  fi
fi
critic_round='none'
critic_verdict='none'
qa_comment_author='none'
qa_comment_author_type='none'
qa_comment_author_association='none'
qa_comment_created_at='none'
qa_comment_updated_at='none'
qa_comment_body_sha256='none'
latest_round=''
latest_round_relative='none'
if [[ "$event" != 'opened' ]]; then
  latest_round="$(gauntlet_latest_round_file "$gauntlet_dir/rounds/$item_id")"
fi

case "$event" in
  qa-pass|qa-fail)
    [[ -n "$latest_round" ]] || { echo "$event requires a recorded critic round." >&2; exit 1; }
    latest_round_relative="${latest_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    critic_round="$latest_round_relative"
    critic_verdict="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Verdict')"
    round_pr="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Progress PR')"
    round_head="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Head branch')"
    round_head_sha="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Head SHA')"
    round_scope="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Scope fingerprint')"
    round_bar="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Quality bar fingerprint')"
    round_execution="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Execution contract fingerprint')"
    [[ "$round_pr" == "$pr_url" && "$round_head" == "$head_branch" ]] || {
      echo "$event must evaluate the latest critic round owned by this live progress PR." >&2
      exit 1
    }
    [[ "$round_bar" == "$quality_fingerprint" ]] || { echo "$event cannot use a stale quality-bar round." >&2; exit 1; }
    [[ "$round_execution" == "$execution_fingerprint" ]] || { echo "$event cannot use a stale execution-contract round." >&2; exit 1; }
    [[ "${round_head_sha,,}" == "$head_sha" && "$round_scope" == "$scope_fingerprint" ]] || {
      echo "$event Head SHA and scope must match the latest critic round." >&2
      exit 1
    }
    round_recorded_at="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Recorded at')"
    gauntlet_assert_live_pr_comment \
      "$evidence_url" "$pr_url" "$issue_repo" "${event#qa-}" "$head_sha" \
      "$latest_round_relative" "$round_recorded_at"
    qa_comment_author="$GAUNTLET_COMMENT_AUTHOR"
    qa_comment_author_type="$GAUNTLET_COMMENT_AUTHOR_TYPE"
    qa_comment_author_association="$GAUNTLET_COMMENT_AUTHOR_ASSOCIATION"
    qa_comment_created_at="$GAUNTLET_COMMENT_CREATED_AT"
    qa_comment_updated_at="$GAUNTLET_COMMENT_UPDATED_AT"
    qa_comment_body_sha256="$GAUNTLET_COMMENT_BODY_SHA256"
    if [[ "$event" == 'qa-pass' && "$critic_verdict" != 'pass' ]]; then
      echo 'qa-pass requires the latest critic round to pass.' >&2
      exit 1
    fi
    # A QA result consumes one critic round. After qa-fail, a new round is
    # mandatory even when the critic had passed independently.
    if [[ "$previous_round" == "$critic_round" ]]; then
      echo "The latest critic round already has a recorded progress-PR QA event: $critic_round" >&2
      exit 1
    fi
    ;;
  merged)
    [[ "$previous_event" == 'qa-pass' ]] || { echo 'merged requires the latest event to be qa-pass.' >&2; exit 1; }
    [[ -n "$latest_round" ]] || { echo 'merged requires a latest passing critic round.' >&2; exit 1; }
    latest_round_relative="${latest_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    critic_round="$latest_round_relative"
    critic_verdict="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Verdict')"
    round_head_sha="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Head SHA')"
    round_scope="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Scope fingerprint')"
    round_execution="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Execution contract fingerprint')"
    [[ "$critic_verdict" == 'pass' && "$previous_round" == "$critic_round" \
      && "${round_head_sha,,}" == "$head_sha" \
      && "$round_scope" == "$scope_fingerprint" \
      && "${previous_head_sha,,}" == "$head_sha" \
      && "$previous_scope_fingerprint" == "$scope_fingerprint" \
      && "$GAUNTLET_PROGRESS_QUALITY_FINGERPRINT" == "$quality_fingerprint" \
      && "$round_execution" == "$execution_fingerprint" \
      && "$previous_execution_fingerprint" == "$execution_fingerprint" ]] || {
      echo 'merged requires QA pass evidence for the latest passing critic round.' >&2
      exit 1
    }
    ;;
  closed)
    if [[ -n "$latest_round" ]]; then
      round_pr="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Progress PR')"
      round_pr="${round_pr%/}"
      if [[ "$round_pr" == "$pr_url" ]]; then
        critic_round="${latest_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
        critic_verdict="$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Verdict')"
        [[ ( "$previous_event" == 'qa-pass' || "$previous_event" == 'qa-fail' ) \
          && "$previous_round" == "$critic_round" \
          && "${previous_head_sha,,}" == "$head_sha" ]] || {
          echo 'closed may not discard an unconsumed critic round; record qa-pass or qa-fail first.' >&2
          exit 1
        }
      fi
    fi
    ;;
esac

max_event=0
if [[ -d "$event_dir" ]]; then
  while IFS= read -r existing_event; do
    existing_name="$(basename "$existing_event")"
    if [[ "$existing_name" =~ ^event-([0-9]+)\.md$ ]]; then
      existing_number=$((10#${BASH_REMATCH[1]}))
      (( existing_number > max_event )) && max_event=$existing_number
    fi
  done < <(find "$event_dir" -maxdepth 1 -type f -name 'event-*.md' -print)
fi
next_event=$((max_event + 1))
printf -v event_label '%03d' "$next_event"
event_relative=".ai/gauntlets/$gauntlet_name/pr-events/$item_id/event-$event_label.md"
event_target="$OPENCAW_PROJECT_ROOT_RESOLVED/$event_relative"
[[ ! -e "$event_target" && ! -L "$event_target" ]] || { echo "PR event evidence already exists: $event_relative" >&2; exit 1; }

recorded_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
[[ "$observed_created_at" < "$recorded_at" || "$observed_created_at" == "$recorded_at" ]] || {
  echo 'Live progress PR creation time postdates the immutable event timestamp.' >&2
  exit 1
}
if [[ "$event" == 'merged' || "$event" == 'closed' ]]; then
  [[ "$observed_closed_at" < "$recorded_at" || "$observed_closed_at" == "$recorded_at" ]] || {
    echo 'Live progress PR closure time postdates the immutable terminal event.' >&2
    exit 1
  }
fi
event_stage="$(mktemp "$gauntlet_dir/.pr-event-stage.XXXXXX")"
main_stage="$(mktemp "$gauntlet_dir/.main-stage.XXXXXX")"
backup_stage="$(mktemp "$gauntlet_dir/.backup-stage.XXXXXX")"
cp "$gauntlet_file" "$backup_stage"
event_root_created=0
event_dir_created=0
cleanup_pr_event_stage() {
  rm -f "$event_stage" "$main_stage" "$backup_stage"
  if [[ $event_dir_created -eq 1 ]]; then
    rmdir "$event_dir" 2>/dev/null || true
  fi
  if [[ $event_root_created -eq 1 ]]; then
    rmdir "$event_root" 2>/dev/null || true
  fi
  gauntlet_release_lock
}
trap cleanup_pr_event_stage EXIT

cat > "$event_stage" <<EOF
# Gauntlet Progress PR Event: $item_id / $event_label

## PR Event Metadata
- Item: $item_id
- Sequence: $event_label
- Event: $event
- PR URL: $pr_url
- Head branch: $head_branch
- Target branch: $integration_branch
- Head SHA: $head_sha
- Scope fingerprint: $scope_fingerprint
- Unit manifest fingerprint: $unit_manifest_fingerprint
- Execution contract fingerprint: $execution_fingerprint
- Base commit SHA: $base_commit_sha
- Target base SHA: $observed_target_base_sha
- Cross repository: $observed_cross_repository
- Head repository: $observed_head_repository
- Publication checkpoint: $publication_checkpoint
- Publication checkpoint sha256: $publication_checkpoint_hash
- Evidence URL: $evidence_url
- QA comment author: $qa_comment_author
- QA comment author type: $qa_comment_author_type
- QA comment author association: $qa_comment_author_association
- QA comment created at: $qa_comment_created_at
- QA comment updated at: $qa_comment_updated_at
- QA comment body sha256: $qa_comment_body_sha256
- Merge commit: $merge_commit
- Critic round: $critic_round
- Critic verdict: $critic_verdict
- Quality bar fingerprint: $quality_fingerprint
- Observed state: $observed_state
- Draft: $observed_draft
- Created at: $observed_created_at
- Closed at: $observed_closed_at
- Merged at: $observed_merged_at
- Merged by: $observed_merged_by
- Merged by type: $observed_merged_by_type
- Merged by bot: $observed_merged_by_bot
- Remediation trigger: $remediation_trigger
- Recorded at: $recorded_at
EOF
event_hash="$(gauntlet_hash_file "$event_stage")"

cp "$gauntlet_file" "$main_stage"
gauntlet_set_section_field "$main_stage" 'Delivery' 'PR eligible' 'no'
case "$event" in
  opened)
    gauntlet_set_section_field "$main_stage" 'Current State' 'Execution contract fingerprint' "$execution_fingerprint"
    gauntlet_set_section_field "$main_stage" 'Current State' 'Quality bar fingerprint' "$quality_fingerprint"
    gauntlet_set_section_field "$main_stage" 'Current State' 'Unit manifest fingerprint' "$unit_manifest_fingerprint"
    gauntlet_set_work_unit_status "$main_stage" "$item_id" 'building'
    gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
    gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' "$item_id"
    gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Build and verify this progress PR, then request a fresh critic round against its real artifact.'
    gauntlet_reset_integration_review "$main_stage"
    ;;
  qa-pass)
    gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Await human merge of the QA-passed progress PR into the Gauntlet integration branch.'
    ;;
  qa-fail)
    gauntlet_set_work_unit_status "$main_stage" "$item_id" 'critic-failed'
    gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
    gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' "$item_id"
    gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Remediate the progress PR and record a new fresh-critic round before repeating PR QA.'
    gauntlet_reset_integration_review "$main_stage"
    ;;
  merged)
    gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' 'none'
    gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Continue remaining progress PRs or run the fresh integration critic after every active unit is merged.'
    ;;
  closed)
    gauntlet_set_work_unit_status "$main_stage" "$item_id" 'critic-failed'
    gauntlet_set_section_field "$main_stage" 'Flow and Status' 'Status' 'running'
    gauntlet_set_section_field "$main_stage" 'Current State' 'Active work unit' "$item_id"
    gauntlet_set_section_field "$main_stage" 'Current State' 'Next action' 'Publish a new remediation PR for this reopened unit before recording another critic round.'
    gauntlet_reset_integration_review "$main_stage"
    ;;
esac

ledger_entry="- $item_id | event: $event_label | action: $event | pr: $pr_url | head: $head_branch | head-sha: $head_sha | scope: $scope_fingerprint | manifest: $unit_manifest_fingerprint | contract: $execution_fingerprint | base-sha: $base_commit_sha | target: $integration_branch | target-base-sha: $observed_target_base_sha | pr-created: $observed_created_at | pr-closed: $observed_closed_at | checkpoint: $publication_checkpoint | checkpoint-sha256: $publication_checkpoint_hash | evidence: $evidence_url | qa-author: $qa_comment_author | qa-created: $qa_comment_created_at | merged-by: $observed_merged_by | merged-by-type: $observed_merged_by_type | merged-by-bot: $observed_merged_by_bot | merge-commit: $merge_commit | trigger: $remediation_trigger | record: $event_relative | sha256: $event_hash"
gauntlet_append_progress_pr_ledger "$main_stage" "$ledger_entry"
chmod 0644 "$event_stage" "$main_stage"

gauntlet_assert_source_hash
if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $event_target"
  echo "GAUNTLET_FILE=$gauntlet_file"
  echo "PR_EVENT_FILE=$event_target"
  echo "PR_EVENT_NUMBER=$event_label"
  echo "PR_EVENT=$event"
  echo "PR_URL=$pr_url"
  echo "HEAD_BRANCH=$head_branch"
  echo "HEAD_SHA=$head_sha"
  echo "SCOPE_FINGERPRINT=$scope_fingerprint"
  echo "EXECUTION_CONTRACT_FINGERPRINT=$execution_fingerprint"
  echo "BASE_COMMIT_SHA=$base_commit_sha"
  echo "TARGET_BRANCH=$integration_branch"
  echo
  cat "$event_stage"
  exit 0
fi

[[ -d "$event_root" ]] || event_root_created=1
if [[ ! -d "$event_dir" ]]; then
  mkdir -p "$event_dir"
  event_dir_created=1
fi
gauntlet_assert_safe_ai_path "$event_dir" 'Gauntlet item PR events directory'
gauntlet_install_no_clobber "$event_stage" "$event_target"
if ! gauntlet_assert_source_hash; then
  rm -f "$event_target"
  exit 1
fi
if ! mv "$main_stage" "$gauntlet_file"; then
  rm -f "$event_target"
  exit 1
fi
if ! bash "$script_dir/validate-gauntlet.sh" "$gauntlet_file" --phase ready >/dev/null; then
  cp "$backup_stage" "$gauntlet_file"
  rm -f "$event_target"
  echo 'Gauntlet PR event transition failed replay validation; GAUNTLET.md was restored.' >&2
  exit 1
fi
rm -f "$backup_stage"
gauntlet_release_lock
trap - EXIT

echo "GAUNTLET_FILE=$gauntlet_file"
echo "PR_EVENT_FILE=$event_target"
echo "PR_EVENT_NUMBER=$event_label"
echo "PR_EVENT=$event"
echo "PR_URL=$pr_url"
echo "HEAD_BRANCH=$head_branch"
echo "HEAD_SHA=$head_sha"
echo "SCOPE_FINGERPRINT=$scope_fingerprint"
echo "EXECUTION_CONTRACT_FINGERPRINT=$execution_fingerprint"
echo "BASE_COMMIT_SHA=$base_commit_sha"
echo "TARGET_BRANCH=$integration_branch"
