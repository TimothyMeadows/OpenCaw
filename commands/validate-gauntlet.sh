#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-gauntlet.sh "<name|path>" [--phase ready|complete]

Validates the Gauntlet contract. The ready phase validates the approved execution
contract needed for work. The complete phase validates terminal state materialized
by create-gauntlet-completion-report.sh: passed and PR-eligible status, a current
immutable completion event and canonical report projection, plus passing active-unit
and integration evidence. Run the completion-report command after ready validation;
it creates the report and event before invoking complete validation transactionally.
Ready and complete replay reject any retained progress or promotion PR timeline
history that enabled auto-merge, auto-rebase, auto-squash, or a merge queue.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"

gauntlet_validate_replay_timestamp() {
  local value="$1"
  local label="$2"

  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
    echo "$label must use canonical UTC form YYYY-MM-DDTHH:MM:SSZ: $value" >&2
    return 1
  }
}

gauntlet_validate_same_pr_comment_url() {
  local evidence_url="$1"
  local pr_url="${2%/}"
  local label="$3"
  local prefix comment_id

  prefix="$pr_url#issuecomment-"
  [[ "$evidence_url" == "$prefix"* ]] || {
    echo "$label must be an exact comment URL on $pr_url: $evidence_url" >&2
    return 1
  }
  comment_id="${evidence_url#"$prefix"}"
  [[ "$comment_id" =~ ^[1-9][0-9]*$ ]] || {
    echo "$label has a noncanonical issue-comment id: $evidence_url" >&2
    return 1
  }
}

gauntlet_preflight_evidence_tree() {
  local tree_path="$1"
  local label="$2"
  local linked_path

  if [[ ! -e "$tree_path" && ! -L "$tree_path" ]]; then
    return 0
  fi
  [[ -d "$tree_path" && ! -L "$tree_path" ]] || {
    echo "$label must be a real directory, not a file or symbolic link: $tree_path" >&2
    return 1
  }
  gauntlet_assert_safe_ai_path "$tree_path" "$label"
  linked_path="$(find "$tree_path" -type l -print -quit)"
  [[ -z "$linked_path" ]] || {
    echo "$label must not contain symbolic links: $linked_path" >&2
    return 1
  }
}

gauntlet_ref=''
phase='structure'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      phase="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
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
case "$phase" in
  structure|ready|complete) ;;
  *) echo "phase must be ready or complete: $phase" >&2; exit 1 ;;
esac

gauntlet_file="$(gauntlet_resolve_file "$gauntlet_ref")"
gauntlet_dir="$(cd "$(dirname "$gauntlet_file")" && pwd -P)"
gauntlet_name="$(basename "$gauntlet_dir")"

required_headings=(
  'Flow and Status'
  'Parent Task'
  'Objective'
  'Approved Quality Bar'
  'Constraints and Permissions'
  'Work Units'
  'Current State'
  'Round Ledger'
  'Progress PR Ledger'
  'Promotion QA Ledger'
  'Completion Ledger'
  'Integration Review'
  'Delivery'
  'Review Notes'
)
previous_line=0
for heading in "${required_headings[@]}"; do
  if [[ "$(gauntlet_heading_count "$gauntlet_file" "$heading")" -ne 1 ]]; then
    echo "GAUNTLET.md requires exactly one '## $heading' heading." >&2
    exit 1
  fi
  current_line="$(grep -nF -m 1 -- "## $heading" "$gauntlet_file" | cut -d: -f1)"
  if [[ $current_line -le $previous_line ]]; then
    echo "GAUNTLET.md headings are out of order at: ## $heading" >&2
    exit 1
  fi
  previous_line="$current_line"
done

flow_type="$(gauntlet_section_field "$gauntlet_file" 'Flow and Status' 'Type')"
status="$(gauntlet_section_field "$gauntlet_file" 'Flow and Status' 'Status')"
[[ "$flow_type" == 'gauntlet' ]] || { echo "Flow Type must be gauntlet." >&2; exit 1; }
case "$status" in
  planning|ready|running|passed|stopped|blocked) ;;
  *) echo "Invalid Gauntlet status: $status" >&2; exit 1 ;;
esac

task_name="$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Task name')"
task_path="$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Task file')"
issue_url="$(gauntlet_section_field "$gauntlet_file" 'Parent Task' 'Issue')"
for parent_task_field in 'Task name' 'Task file' 'Issue'; do
  [[ "$(gauntlet_section_field_count "$gauntlet_file" 'Parent Task' "$parent_task_field")" -eq 1 ]] || {
    echo "Parent Task requires exactly one '$parent_task_field' field." >&2
    exit 1
  }
done
gauntlet_validate_name "$task_name" 'Parent task name'
task_path="${task_path#\`}"
task_path="${task_path%\`}"
expected_task_path=".ai/tasks/$task_name/TASK.md"
[[ "$task_path" == "$expected_task_path" ]] || {
  echo "Parent Task file must be \`$expected_task_path\`." >&2
  exit 1
}
task_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$task_path"
gauntlet_assert_safe_ai_path "$OPENCAW_PROJECT_AI_DIR/tasks" 'Task root'
gauntlet_assert_safe_ai_path "$OPENCAW_PROJECT_AI_DIR/tasks/$task_name" 'Parent task directory'
[[ -f "$task_file" && ! -L "$task_file" ]] || {
  echo "Parent task file does not exist: $task_path" >&2
  exit 1
}
[[ "$(sed 's/\r$//' "$gauntlet_file" | grep -Fxc -- '### Unit History')" -eq 1 ]] || {
  echo "Work Units requires exactly one '### Unit History' subsection." >&2
  exit 1
}

unit_count=0
active_unit_count=0
seen_units="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-units.XXXXXX")"
trap 'rm -f "$seen_units"' EXIT
while IFS= read -r unit_line; do
  if [[ ! "$unit_line" =~ ^-[[:space:]]\[([[:space:]xX])\][[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]status:[[:space:]](pending|building|critic-failed|passed|blocked|superseded)[[:space:]]\|[[:space:]]title:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]scope:[[:space:]]([^|]+)$ ]]; then
    echo "Invalid work-unit entry: $unit_line" >&2
    exit 1
  fi
  checkbox="${BASH_REMATCH[1]}"
  item_id="${BASH_REMATCH[2]}"
  unit_status="${BASH_REMATCH[4]}"
  unit_title="$(gauntlet_trim "${BASH_REMATCH[5]}")"
  unit_scope="$(gauntlet_trim "${BASH_REMATCH[6]}")"
  if grep -Fqx -- "$item_id" "$seen_units"; then
    echo "Duplicate work-unit id: $item_id" >&2
    exit 1
  fi
  case "$item_id" in
    integration|none)
      echo "Work-unit id is reserved: $item_id" >&2
      exit 1
      ;;
  esac
  printf '%s\n' "$item_id" >> "$seen_units"
  gauntlet_validate_substantive_single_line "$unit_title" "Work-unit title for $item_id"
  gauntlet_validate_substantive_single_line "$unit_scope" "Work-unit scope for $item_id"
  if [[ "$unit_status" == 'passed' || "$unit_status" == 'superseded' ]]; then
    [[ "$checkbox" =~ [xX] ]] || { echo "Completed work unit must be checked: $item_id" >&2; exit 1; }
  else
    [[ "$checkbox" == ' ' ]] || { echo "Incomplete work unit must not be checked: $item_id" >&2; exit 1; }
  fi
  unit_count=$((unit_count + 1))
  [[ "$unit_status" == 'superseded' ]] || active_unit_count=$((active_unit_count + 1))
done < <(gauntlet_work_unit_lines "$gauntlet_file")
[[ $unit_count -gt 0 && $active_unit_count -gt 0 ]] || {
  echo 'Gauntlet requires at least one active work unit.' >&2
  exit 1
}

for current_state_field in 'Quality bar fingerprint' 'Unit manifest fingerprint' 'Execution contract fingerprint'; do
  [[ "$(gauntlet_section_field_count "$gauntlet_file" 'Current State' "$current_state_field")" -eq 1 ]] || {
    echo "Current State requires exactly one '$current_state_field' field." >&2
    exit 1
  }
done
current_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Quality bar fingerprint')"
quality_fingerprint="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"
current_manifest_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Unit manifest fingerprint')"
unit_manifest_fingerprint="$(gauntlet_unit_manifest_fingerprint "$gauntlet_file")"
if [[ "$current_manifest_fingerprint" != 'pending' ]]; then
  [[ "$current_manifest_fingerprint" =~ ^[0-9a-f]{64}$ ]] || {
    echo 'Current State Unit manifest fingerprint must be pending or a lowercase SHA-256 value.' >&2
    exit 1
  }
  [[ "$current_manifest_fingerprint" == "$unit_manifest_fingerprint" ]] || {
    echo 'Retained work-unit IDs, titles, or scopes changed without a pending approved unit-manifest revision.' >&2
    exit 1
  }
fi
current_execution_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Execution contract fingerprint')"
execution_fingerprint="$(gauntlet_execution_contract_fingerprint "$gauntlet_file")"
if [[ "$current_execution_fingerprint" != 'pending' ]]; then
  [[ "$current_execution_fingerprint" =~ ^[0-9a-f]{64}$ ]] || {
    echo 'Current State Execution contract fingerprint must be pending or a lowercase SHA-256 value.' >&2
    exit 1
  }
  [[ "$current_execution_fingerprint" == "$execution_fingerprint" ]] || {
    echo 'Parent task, objective, constraints, permissions, or static delivery contract changed after progress-PR publication.' >&2
    exit 1
  }
fi
base_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base branch')"
base_commit_sha="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base commit SHA')"
integration_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
for delivery_contract_field in 'Base branch' 'Base commit SHA' 'Integration branch' \
  'Progress PR publication' 'Progress PR QA' 'Progress PR merge' \
  'Promotion PR readiness confirmation' 'Promotion PR' 'Post-promotion QA' \
  'Auto-merge' 'Merge approval'; do
  [[ "$(gauntlet_section_field_count "$gauntlet_file" 'Delivery' "$delivery_contract_field")" -eq 1 ]] || {
    echo "Delivery requires exactly one '$delivery_contract_field' field." >&2
    exit 1
  }
done
[[ "$integration_branch" == "gauntlet/$gauntlet_name" ]] || {
  echo "Gauntlet integration branch must be gauntlet/$gauntlet_name." >&2
  exit 1
}
gauntlet_validate_branch "$integration_branch" 'Gauntlet integration branch'
if [[ "$base_branch" != 'pending' ]]; then
  gauntlet_validate_branch "$base_branch" 'Gauntlet delivery base branch'
fi
if [[ "$base_commit_sha" != 'pending' ]]; then
  [[ "$base_commit_sha" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || {
    echo 'Gauntlet Base commit SHA must be pending or a lowercase full commit SHA.' >&2
    exit 1
  }
fi

# Cross-ledger replay reads evidence before some tree-specific validators run.
# Preflight every durable evidence tree once so no cross-reference can traverse
# an intermediate symlink or leave the resolved project .ai boundary.
for evidence_tree in publication-checkpoints rounds pr-events promotion-events completion-events; do
  gauntlet_preflight_evidence_tree \
    "$gauntlet_dir/$evidence_tree" "Gauntlet $evidence_tree evidence tree"
done

# Publication checkpoints are append-only authorization records. Validate the
# entire tree, including unused/aborted checkpoints, before replaying any PR
# event that may consume one.
publication_checkpoint_root="$gauntlet_dir/publication-checkpoints"
[[ ! -L "$publication_checkpoint_root" ]] || {
  echo "Gauntlet publication-checkpoints root must not be a symbolic link: $publication_checkpoint_root" >&2
  exit 1
}
if [[ -d "$publication_checkpoint_root" ]]; then
  gauntlet_assert_safe_ai_path "$publication_checkpoint_root" 'Gauntlet publication-checkpoints root'
  unexpected_checkpoint_root_entry="$(find "$publication_checkpoint_root" -mindepth 1 -maxdepth 1 ! -type d -print -quit)"
  [[ -z "$unexpected_checkpoint_root_entry" ]] || {
    echo "Publication-checkpoints root may contain only canonical work-unit directories: $unexpected_checkpoint_root_entry" >&2
    exit 1
  }
  while IFS= read -r checkpoint_item_dir; do
    [[ -n "$checkpoint_item_dir" ]] || continue
    [[ ! -L "$checkpoint_item_dir" ]] || {
      echo "Publication checkpoint item directory must not be a symbolic link: $checkpoint_item_dir" >&2
      exit 1
    }
    gauntlet_assert_safe_ai_path "$checkpoint_item_dir" 'Gauntlet publication checkpoint item directory'
    checkpoint_item="$(basename "$checkpoint_item_dir")"
    gauntlet_validate_name "$checkpoint_item" 'Publication checkpoint item id'
    grep -Fqx -- "$checkpoint_item" "$seen_units" || {
      echo "Publication checkpoint directory references an unretained unit: $checkpoint_item" >&2
      exit 1
    }
    expected_checkpoint_number=1
    checkpoint_file_count=0
    while IFS= read -r checkpoint_entry; do
      [[ -n "$checkpoint_entry" ]] || continue
      checkpoint_entry_name="$(basename "$checkpoint_entry")"
      [[ -f "$checkpoint_entry" && ! -L "$checkpoint_entry" \
        && "$checkpoint_entry_name" =~ ^checkpoint-[0-9]{3,}\.md$ ]] || {
        echo "Publication checkpoint directory contains noncanonical or unsafe evidence: $checkpoint_entry" >&2
        exit 1
      }
    done < <(find "$checkpoint_item_dir" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)
    while IFS=$'\t' read -r checkpoint_numeric checkpoint_file; do
      [[ -n "$checkpoint_file" ]] || continue
      checkpoint_file_count=$((checkpoint_file_count + 1))
      printf -v expected_checkpoint_label '%03d' "$expected_checkpoint_number"
      checkpoint_actual_label="$(basename "$checkpoint_file")"
      checkpoint_actual_label="${checkpoint_actual_label#checkpoint-}"
      checkpoint_actual_label="${checkpoint_actual_label%.md}"
      [[ "$checkpoint_numeric" -eq "$expected_checkpoint_number" \
        && "$checkpoint_actual_label" == "$expected_checkpoint_label" ]] || {
        echo "Publication checkpoint sequence must be contiguous and canonically padded; expected checkpoint-$expected_checkpoint_label.md for $checkpoint_item." >&2
        exit 1
      }
      checkpoint_relative="${checkpoint_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      [[ "$(awk -v target="# Gauntlet Publication Checkpoint: $checkpoint_item / $expected_checkpoint_label" \
          '{ sub(/\r$/, "") } $0 == target { count++ } END { print count + 0 }' "$checkpoint_file")" -eq 1 \
        && "$(gauntlet_heading_count "$checkpoint_file" 'Publication Checkpoint Metadata')" -eq 1 ]] || {
        echo "Publication checkpoint headings are noncanonical: $checkpoint_relative" >&2
        exit 1
      }
      for checkpoint_key in 'Item' 'Sequence' 'Head branch' 'Head SHA' 'Target branch' 'Chain tip' \
        'Remediation trigger' 'Remediation trigger sha256' 'Remediation root' 'Remediation root sha256' \
        'Quality bar fingerprint' 'Quality bar approved at' 'Unit scope fingerprint' 'Unit manifest fingerprint' \
        'Unit manifest approved at' \
        'Execution contract fingerprint' 'Remote integration state' 'Remote integration SHA' \
        'Remote work state' 'Remote work SHA' 'Recorded at'; do
        [[ "$(gauntlet_section_field_count "$checkpoint_file" 'Publication Checkpoint Metadata' "$checkpoint_key")" -eq 1 ]] || {
          echo "Publication checkpoint requires exactly one '$checkpoint_key' field: $checkpoint_relative" >&2
          exit 1
        }
      done
      checkpoint_head_branch="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Head branch')"
      checkpoint_head_sha="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
      checkpoint_chain_tip="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Chain tip' | tr '[:upper:]' '[:lower:]')"
      checkpoint_trigger="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation trigger')"
      checkpoint_trigger_hash="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation trigger sha256')"
      checkpoint_root="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root')"
      checkpoint_root_hash="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root sha256')"
      checkpoint_quality_approved_at="$(gauntlet_section_field \
        "$checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar approved at')"
      checkpoint_manifest_approved_at="$(gauntlet_section_field \
        "$checkpoint_file" 'Publication Checkpoint Metadata' 'Unit manifest approved at')"
      checkpoint_remote_integration_state="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote integration state')"
      checkpoint_remote_integration_sha="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote integration SHA' | tr '[:upper:]' '[:lower:]')"
      checkpoint_remote_work_state="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote work state')"
      checkpoint_remote_work_sha="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote work SHA' | tr '[:upper:]' '[:lower:]')"
      checkpoint_recorded_at="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Recorded at')"
      gauntlet_validate_replay_timestamp "$checkpoint_recorded_at" "Publication checkpoint Recorded at ($checkpoint_relative)"
      gauntlet_validate_replay_timestamp \
        "$checkpoint_quality_approved_at" "Publication checkpoint quality approval ($checkpoint_relative)"
      gauntlet_validate_replay_timestamp \
        "$checkpoint_manifest_approved_at" "Publication checkpoint manifest approval ($checkpoint_relative)"
      gauntlet_validate_branch "$checkpoint_head_branch" "Publication checkpoint head branch ($checkpoint_relative)"
      gauntlet_validate_head_sha "$checkpoint_head_sha" "Publication checkpoint Head SHA ($checkpoint_relative)"
      gauntlet_validate_head_sha "$checkpoint_chain_tip" "Publication checkpoint chain tip ($checkpoint_relative)"
      [[ "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Item')" == "$checkpoint_item" \
        && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Sequence')" == "$expected_checkpoint_label" \
        && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Target branch')" == "$integration_branch" \
        && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar fingerprint')" =~ ^[0-9a-f]{64}$ \
        && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Unit scope fingerprint')" =~ ^[0-9a-f]{64}$ \
        && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Unit manifest fingerprint')" =~ ^[0-9a-f]{64}$ \
        && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Execution contract fingerprint')" =~ ^[0-9a-f]{64}$ \
        && "$checkpoint_trigger_hash" == "$(gauntlet_remediation_trigger_hash "$gauntlet_file" "$checkpoint_trigger")" \
        && "$checkpoint_root" == "$(gauntlet_remediation_root_for_trigger \
          "$gauntlet_file" "$checkpoint_item" "$checkpoint_trigger" "$checkpoint_recorded_at")" \
        && ( "$checkpoint_remote_integration_state" == 'exact' \
          || "$checkpoint_remote_integration_state" == 'absent-create-only' ) \
        && ( "$checkpoint_remote_work_state" == 'exact' \
          || "$checkpoint_remote_work_state" == 'absent-create-only' ) ]] || {
        echo "Publication checkpoint metadata is noncanonical or stale: $checkpoint_relative" >&2
        exit 1
      }
      if [[ "$checkpoint_remote_integration_state" == 'exact' ]]; then
        [[ "$checkpoint_remote_integration_sha" == "$checkpoint_chain_tip" ]] || {
          echo "Publication checkpoint exact remote integration SHA differs from its chain tip: $checkpoint_relative" >&2
          exit 1
        }
      else
        [[ "$checkpoint_remote_integration_sha" == 'absent' ]] || {
          echo "Publication checkpoint absent integration state requires absent SHA: $checkpoint_relative" >&2
          exit 1
        }
      fi
      if [[ "$checkpoint_remote_work_state" == 'exact' ]]; then
        [[ "$checkpoint_remote_work_sha" == "$checkpoint_head_sha" ]] || {
          echo "Publication checkpoint exact remote work SHA differs from its reviewed head: $checkpoint_relative" >&2
          exit 1
        }
      else
        [[ "$checkpoint_remote_work_sha" == 'absent' ]] || {
          echo "Publication checkpoint absent work state requires absent SHA: $checkpoint_relative" >&2
          exit 1
        }
      fi
      checkpoint_expected_head="gauntlet-work/$gauntlet_name/$checkpoint_item"
      [[ "$checkpoint_head_branch" == "$checkpoint_expected_head" \
        || "$checkpoint_head_branch" =~ ^${checkpoint_expected_head}-remediation-[1-9][0-9]*$ ]] || {
        echo "Publication checkpoint uses a noncanonical work branch: $checkpoint_relative" >&2
        exit 1
      }
      gauntlet_assert_commit_ancestor "$checkpoint_chain_tip" "$checkpoint_head_sha" \
        "Publication checkpoint work-head ancestry ($checkpoint_relative)"
      if [[ "$checkpoint_root" == 'none' ]]; then
        [[ "$checkpoint_root_hash" == 'none' ]] || { echo "Publication checkpoint none root must have none hash: $checkpoint_relative" >&2; exit 1; }
      else
        [[ -f "$OPENCAW_PROJECT_ROOT_RESOLVED/$checkpoint_root" && ! -L "$OPENCAW_PROJECT_ROOT_RESOLVED/$checkpoint_root" \
          && "$checkpoint_root_hash" == "$(gauntlet_hash_file "$OPENCAW_PROJECT_ROOT_RESOLVED/$checkpoint_root")" ]] || {
          echo "Publication checkpoint remediation-root hash is stale: $checkpoint_relative" >&2
          exit 1
        }
      fi
      expected_checkpoint_number=$((expected_checkpoint_number + 1))
    done < <(find "$checkpoint_item_dir" -maxdepth 1 -type f -name 'checkpoint-*.md' -print \
      | awk '{ name=$0; sub(/^.*\/checkpoint-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
      | LC_ALL=C sort -n -k1,1)
    [[ "$checkpoint_file_count" -gt 0 ]] || {
      echo "Publication checkpoint item directory is empty: $checkpoint_item_dir" >&2
      exit 1
    }
  done < <(find "$publication_checkpoint_root" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
fi

round_count=0
critics_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-critics.XXXXXX")"
builders_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-builders.XXXXXX")"
historical_bars="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-bars.XXXXXX")"
historical_manifests="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-manifests.XXXXXX")"
round_ledger_paths="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-round-ledger-paths.XXXXXX")"
trap 'rm -f "$seen_units" "$critics_seen" "$builders_seen" "$historical_bars" "$historical_manifests" "$round_ledger_paths"' EXIT
[[ ! -L "$gauntlet_dir/rounds" ]] || {
  echo "Gauntlet rounds directory must not be a symbolic link: $gauntlet_dir/rounds" >&2
  exit 1
}
if [[ -d "$gauntlet_dir/rounds" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/rounds" 'Gauntlet rounds directory'
  linked_round_path="$(find "$gauntlet_dir/rounds" -type l -print -quit)"
  [[ -z "$linked_round_path" ]] || {
    echo "Gauntlet round history must not contain symbolic links: $linked_round_path" >&2
    exit 1
  }
  while IFS= read -r round_file; do
    [[ -n "$round_file" ]] || continue
    round_count=$((round_count + 1))
    relative_round="${round_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    item_dir="$(basename "$(dirname "$round_file")")"
    filename="$(basename "$round_file")"
    [[ "$filename" =~ ^round-([0-9]{3,})\.md$ ]] || { echo "Invalid round filename: $relative_round" >&2; exit 1; }
    [[ "$(gauntlet_heading_count "$round_file" 'Round Metadata')" -eq 1 ]] || {
      echo "Round requires exactly one metadata heading: $relative_round" >&2
      exit 1
    }
    for round_metadata_key in 'Item' 'Round' 'Verdict' 'Builder ID' 'Critic ID' \
      'Isolation' 'Progress PR' 'Head branch' 'Head SHA' 'Scope fingerprint' \
      'Unit manifest fingerprint' 'Quality bar fingerprint' \
      'Execution contract fingerprint' 'Base commit SHA' 'Opened event' 'Opened event sha256' \
      'Remediation root' 'Remediation root sha256' 'Affected units' 'Builder strategy' \
      'Builder strategy fingerprint' 'Critic next strategy fingerprint' 'Recorded at'; do
      [[ "$(gauntlet_section_field_count "$round_file" 'Round Metadata' "$round_metadata_key")" -eq 1 ]] || {
        echo "Round requires exactly one '$round_metadata_key' field: $relative_round" >&2
        exit 1
      }
    done
    round_number="${BASH_REMATCH[1]}"
    metadata_item="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Item')"
    metadata_round="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Round')"
    metadata_verdict="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Verdict')"
    builder_id="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Builder ID')"
    critic_id="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Critic ID')"
    isolation="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Isolation')"
    metadata_pr="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Progress PR')"
    metadata_pr="${metadata_pr%/}"
    metadata_head="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Head branch')"
    metadata_head_sha="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Head SHA')"
    metadata_head_sha="${metadata_head_sha,,}"
    metadata_scope="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Scope fingerprint')"
    metadata_manifest="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')"
    metadata_bar="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Quality bar fingerprint')"
    metadata_execution="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')"
    metadata_base_sha="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')"
    metadata_opened_event="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Opened event')"
    metadata_opened_hash="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Opened event sha256')"
    metadata_remediation_root="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Remediation root')"
    metadata_remediation_root_hash="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Remediation root sha256')"
    metadata_affected_units="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Affected units')"
    builder_strategy="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Builder strategy')"
    builder_strategy_fingerprint="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Builder strategy fingerprint')"
    critic_strategy_fingerprint="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Critic next strategy fingerprint')"
    round_recorded_at="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Recorded at')"
    [[ "$metadata_item" == "$item_dir" && "$metadata_round" == "$round_number" ]] || {
      echo "Round metadata does not match its path: $relative_round" >&2
      exit 1
    }
    if [[ "$item_dir" != 'integration' ]] && ! grep -Fqx -- "$item_dir" "$seen_units"; then
      echo "Round references unknown work unit: $relative_round" >&2
      exit 1
    fi
    case "$metadata_verdict" in pass|fail|blocked) ;; *) echo "Invalid round verdict: $relative_round" >&2; exit 1 ;; esac
    case "$isolation" in native-subagent|fresh-session) ;; *) echo "Invalid critic isolation: $relative_round" >&2; exit 1 ;; esac
    gauntlet_validate_head_sha "$metadata_head_sha" 'Round Head SHA'
    [[ "$metadata_scope" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Round has an invalid scope fingerprint: $relative_round" >&2; exit 1; }
    [[ "$metadata_manifest" =~ ^[0-9a-f]{64}$ ]] || { echo "Round has an invalid unit-manifest fingerprint: $relative_round" >&2; exit 1; }
    gauntlet_validate_substantive_single_line "$builder_strategy" 'Round builder strategy'
    [[ "$builder_strategy_fingerprint" == "$(gauntlet_strategy_fingerprint "$builder_strategy")" ]] || {
      echo "Round builder strategy fingerprint is stale: $relative_round" >&2
      exit 1
    }
    if [[ "$item_dir" == 'integration' ]]; then
      [[ "$metadata_pr" == 'none' && "$metadata_head" == "$integration_branch" ]] || {
        echo "Integration round must inspect the durable integration branch: $relative_round" >&2
        exit 1
      }
      [[ "$metadata_opened_event" == 'none' && "$metadata_opened_hash" == 'none' \
        && "$metadata_remediation_root" == 'none' && "$metadata_remediation_root_hash" == 'none' ]] || {
        echo "Integration round cannot claim a progress-PR opened event or remediation root: $relative_round" >&2
        exit 1
      }
      if [[ "$metadata_verdict" == 'pass' ]]; then
        [[ "$metadata_affected_units" == 'none' ]] || { echo "Passing integration round must not claim affected units: $relative_round" >&2; exit 1; }
      else
        [[ "$metadata_affected_units" != 'none' \
          && "$metadata_affected_units" =~ ^[a-z0-9]+(-[a-z0-9]+)*(,[a-z0-9]+(-[a-z0-9]+)*)*$ \
          && "$metadata_affected_units" == "$(printf '%s' "$metadata_affected_units" | tr ',' '\n' | LC_ALL=C sort -u | paste -sd, -)" ]] || {
          echo "Integration failure/block requires canonical frozen affected-unit IDs: $relative_round" >&2
          exit 1
        }
        IFS=',' read -r -a metadata_affected_ids <<< "$metadata_affected_units"
        for metadata_affected_item in "${metadata_affected_ids[@]}"; do
          grep -Fqx -- "$metadata_affected_item" "$seen_units" || {
            echo "Integration round affected-unit set references an unretained item: $metadata_affected_item" >&2
            exit 1
          }
        done
      fi
    else
      gauntlet_validate_github_pr_url "$metadata_pr" 'Round progress PR URL'
      gauntlet_validate_branch "$metadata_head" 'Round progress PR head branch'
      expected_progress_head="gauntlet-work/$gauntlet_name/$item_dir"
      [[ "$metadata_head" == "$expected_progress_head" \
        || "$metadata_head" =~ ^${expected_progress_head}-remediation-[1-9][0-9]*$ ]] || {
        echo "Round progress PR head must use the canonical work-unit branch for $item_dir: $relative_round" >&2
        exit 1
      }
      [[ "$(gauntlet_github_repo_from_url "$metadata_pr")" == "$(gauntlet_github_repo_from_url "$issue_url")" ]] || {
        echo "Round progress PR repository does not match the parent issue: $relative_round" >&2
        exit 1
      }
      [[ "$metadata_opened_event" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/${item_dir}/event-[0-9]{3,}\.md$ ]] || {
        echo "Work-unit round lacks its exact hash-anchored opened event: $relative_round" >&2
        exit 1
      }
      opened_round_event_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$metadata_opened_event"
      gauntlet_assert_safe_ai_path "$opened_round_event_file" \
        'Round opened-event evidence'
      [[ -f "$opened_round_event_file" && ! -L "$opened_round_event_file" \
        && "$metadata_opened_hash" == "$(gauntlet_hash_file "$opened_round_event_file")" ]] || {
        echo "Work-unit round lacks its exact hash-anchored opened event: $relative_round" >&2
        exit 1
      }
      [[ "$(gauntlet_section_field "$opened_round_event_file" 'PR Event Metadata' 'Event')" == 'opened' \
        && "$(gauntlet_section_field "$opened_round_event_file" 'PR Event Metadata' 'Item')" == "$item_dir" \
        && "${metadata_pr%/}" == "$(gauntlet_section_field "$opened_round_event_file" 'PR Event Metadata' 'PR URL' | sed 's#/$##')" \
        && "$metadata_head" == "$(gauntlet_section_field "$opened_round_event_file" 'PR Event Metadata' 'Head branch')" ]] || {
        echo "Work-unit round opened-event anchor does not own its progress PR: $relative_round" >&2
        exit 1
      }
      expected_round_root="$(gauntlet_resolve_remediation_root "$gauntlet_file" "$item_dir" "$opened_round_event_file")"
      latest_same_pr_qa_failure=''
      latest_same_pr_qa_time=''
      while IFS= read -r round_qa_candidate; do
        [[ "$(gauntlet_section_field "$round_qa_candidate" 'PR Event Metadata' 'Event')" == 'qa-fail' \
          && "$(gauntlet_section_field "$round_qa_candidate" 'PR Event Metadata' 'PR URL' | sed 's#/$##')" == "$metadata_pr" ]] || continue
        round_qa_time="$(gauntlet_section_field "$round_qa_candidate" 'PR Event Metadata' 'Recorded at')"
        round_qa_relative="${round_qa_candidate#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
        round_qa_precedes=0
        if [[ "$round_qa_time" < "$round_recorded_at" ]]; then
          round_qa_precedes=1
        elif [[ "$round_qa_time" == "$round_recorded_at" \
          && "$metadata_remediation_root" == "$round_qa_relative" ]]; then
          round_qa_critic_round="$(gauntlet_section_field "$round_qa_candidate" 'PR Event Metadata' 'Critic round')"
          if [[ "$round_qa_critic_round" == .ai/gauntlets/*/rounds/*/round-*.md ]] \
            && gauntlet_round_event_precedes \
              "$gauntlet_file" "$round_qa_critic_round" "$relative_round"; then
            round_qa_precedes=1
          fi
        fi
        [[ "$round_qa_precedes" -eq 1 ]] || continue

        if [[ -z "$latest_same_pr_qa_time" || "$latest_same_pr_qa_time" < "$round_qa_time" ]]; then
          latest_same_pr_qa_time="$round_qa_time"
          latest_same_pr_qa_failure="$round_qa_relative"
        elif [[ "$latest_same_pr_qa_time" == "$round_qa_time" ]] \
          && gauntlet_progress_pr_event_precedes \
            "$gauntlet_file" "$latest_same_pr_qa_failure" "$round_qa_relative"; then
          latest_same_pr_qa_failure="$round_qa_relative"
        fi
      done < <(find "$gauntlet_dir/pr-events/$item_dir" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
      [[ -z "$latest_same_pr_qa_failure" ]] || expected_round_root="$latest_same_pr_qa_failure"
      if [[ "$expected_round_root" == 'none' ]]; then
        expected_round_root_hash='none'
      else
        expected_round_root_hash="$(gauntlet_hash_file "$OPENCAW_PROJECT_ROOT_RESOLVED/$expected_round_root")"
      fi
      [[ "$metadata_remediation_root" == "$expected_round_root" \
        && "$metadata_remediation_root_hash" == "$expected_round_root_hash" \
        && "$metadata_affected_units" == 'none' ]] || {
        echo "Work-unit round has stale remediation-root or affected-unit evidence: $relative_round" >&2
        exit 1
      }
      opened_round_recorded_at="$(gauntlet_section_field "$opened_round_event_file" 'PR Event Metadata' 'Recorded at')"
      [[ "$opened_round_recorded_at" < "$round_recorded_at" || "$opened_round_recorded_at" == "$round_recorded_at" ]] || {
        echo "Work-unit round predates its opened-event anchor: $relative_round" >&2
        exit 1
      }
    fi
    [[ -n "$builder_id" && -n "$critic_id" && "${builder_id,,}" != "${critic_id,,}" ]] || {
      echo "Round builder and critic must be distinct: $relative_round" >&2
      exit 1
    }
    if grep -Fqxi -- "$critic_id" "$critics_seen"; then
      echo "Critic invocation was reused: $critic_id" >&2
      exit 1
    fi
    if grep -Fqxi -- "$critic_id" "$builders_seen" || grep -Fqxi -- "$builder_id" "$critics_seen"; then
      echo "Builder and critic identity sets overlap case-insensitively: $relative_round" >&2
      exit 1
    fi
    printf '%s\n' "${critic_id,,}" >> "$critics_seen"
    printf '%s\n' "${builder_id,,}" >> "$builders_seen"
    [[ "$metadata_bar" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Round has an invalid quality bar fingerprint: $relative_round" >&2; exit 1; }
    [[ "$metadata_execution" =~ ^[0-9a-f]{64}$ \
      && "$metadata_execution" == "$current_execution_fingerprint" ]] || {
      echo "Round has a stale or invalid execution-contract fingerprint: $relative_round" >&2
      exit 1
    }
    [[ "$metadata_base_sha" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ \
      && "$metadata_base_sha" == "${base_commit_sha,,}" ]] || {
      echo "Round has a stale or invalid approved base commit SHA: $relative_round" >&2
      exit 1
    }
    if [[ "$item_dir" == 'integration' ]]; then
      gauntlet_assert_commit_ancestor "$metadata_base_sha" "$metadata_head_sha" "Integration round approved base ($relative_round)"
    fi
    printf '%s\n' "${metadata_bar,,}" >> "$historical_bars"
    printf '%s\n' "$metadata_manifest" >> "$historical_manifests"
    gauntlet_validate_critic_report "$round_file" "$metadata_verdict" "$metadata_head_sha" || exit 1
    [[ "$critic_strategy_fingerprint" == "$GAUNTLET_CRITIC_NEXT_STRATEGY_FINGERPRINT" ]] || {
      echo "Round critic next-strategy fingerprint is stale: $relative_round" >&2
      exit 1
    }
    gauntlet_validate_replay_timestamp "$round_recorded_at" "Round Recorded at ($relative_round)"
  done < <(find "$gauntlet_dir/rounds" -type f -name 'round-*.md' -print | LC_ALL=C sort)

  while IFS= read -r item_round_dir; do
    [[ -n "$item_round_dir" ]] || continue
    gauntlet_assert_safe_ai_path "$item_round_dir" 'Gauntlet item rounds directory'
    round_item="$(basename "$item_round_dir")"
    if [[ "$round_item" != 'integration' ]]; then
      gauntlet_validate_name "$round_item" 'Round work-unit id'
      grep -Fqx -- "$round_item" "$seen_units" || {
        echo "Orphan round directory has no retained work-unit entry: $round_item" >&2
        exit 1
      }
    fi
    expected_number=1
    item_file_count=0
    while IFS=$'\t' read -r numeric_value item_round_file; do
      [[ -n "$item_round_file" ]] || continue
      item_file_count=$((item_file_count + 1))
      printf -v expected_label '%03d' "$expected_number"
      actual_label="$(basename "$item_round_file")"
      actual_label="${actual_label#round-}"
      actual_label="${actual_label%.md}"
      [[ "$numeric_value" -eq "$expected_number" && "$actual_label" == "$expected_label" ]] || {
        echo "Round sequence must be contiguous and canonically padded; expected round-$expected_label.md in $round_item." >&2
        exit 1
      }
      expected_number=$((expected_number + 1))
    done < <(find "$item_round_dir" -maxdepth 1 -type f -name 'round-*.md' -print \
      | awk '{ name=$0; sub(/^.*\/round-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
      | LC_ALL=C sort -n -k1,1)
    [[ $item_file_count -gt 0 ]] || {
      echo "Orphan or empty round directory: $item_round_dir" >&2
      exit 1
    }
  done < <(find "$gauntlet_dir/rounds" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
fi

ledger_count=0
round_placeholder_count=0
round_ledger_pattern='^- ([^|[:space:]]+) \| round: ([0-9]{3,}) \| verdict: (pass|fail|blocked) \| head-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| scope: ([0-9a-f]{64}) \| manifest: ([0-9a-f]{64}) \| contract: ([0-9a-f]{64}) \| base-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| opened: ([^|[:space:]]+) \| opened-sha256: (none|[0-9a-f]{64}) \| root: ([^|[:space:]]+) \| root-sha256: (none|[0-9a-f]{64}) \| affected-units: ([^|[:space:]]+) \| builder: ([^|]+) \| critic: ([^|]+) \| isolation: (native-subagent|fresh-session) \| evidence: ([^|[:space:]]+) \| sha256: ([0-9a-f]{64})$'
while IFS= read -r ledger_line; do
  [[ "$ledger_line" =~ ^[[:space:]]*$ ]] && continue
  if [[ "$ledger_line" == '- No rounds recorded.' ]]; then
    round_placeholder_count=$((round_placeholder_count + 1))
    continue
  fi
  if [[ ! "$ledger_line" =~ $round_ledger_pattern ]]; then
    echo "Invalid or noncanonical Round Ledger content: $ledger_line" >&2
    exit 1
  fi

  ledger_item="${BASH_REMATCH[1]}"
  ledger_round="${BASH_REMATCH[2]}"
  ledger_verdict="${BASH_REMATCH[3]}"
  ledger_head_sha="${BASH_REMATCH[4]}"
  ledger_scope="${BASH_REMATCH[5]}"
  ledger_manifest="${BASH_REMATCH[6]}"
  ledger_execution="${BASH_REMATCH[7]}"
  ledger_base_sha="${BASH_REMATCH[8]}"
  ledger_opened="${BASH_REMATCH[9]}"
  ledger_opened_hash="${BASH_REMATCH[10]}"
  ledger_root="${BASH_REMATCH[11]}"
  ledger_root_hash="${BASH_REMATCH[12]}"
  ledger_affected="${BASH_REMATCH[13]}"
  ledger_builder="${BASH_REMATCH[14]}"
  ledger_critic="${BASH_REMATCH[15]}"
  ledger_isolation="${BASH_REMATCH[16]}"
  ledger_evidence="${BASH_REMATCH[17]}"
  ledger_hash="${BASH_REMATCH[18]}"
  ledger_count=$((ledger_count + 1))

  if [[ "$ledger_item" != 'integration' ]]; then
    gauntlet_validate_name "$ledger_item" 'Round Ledger work-unit id'
    grep -Fqx -- "$ledger_item" "$seen_units" || {
      echo "Round Ledger references an unknown work unit: $ledger_item" >&2
      exit 1
    }
  fi
  expected_ledger_evidence=".ai/gauntlets/$gauntlet_name/rounds/$ledger_item/round-$ledger_round.md"
  [[ "$ledger_evidence" == "$expected_ledger_evidence" ]] || {
    echo "Round Ledger path does not match its item and round: $ledger_evidence" >&2
    exit 1
  }
  if grep -Fqx -- "$ledger_evidence" "$round_ledger_paths"; then
    echo "Round Ledger evidence path is duplicated: $ledger_evidence" >&2
    exit 1
  fi
  printf '%s\n' "$ledger_evidence" >> "$round_ledger_paths"
  ledger_round_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$ledger_evidence"
  [[ -f "$ledger_round_file" && ! -L "$ledger_round_file" ]] || {
    echo "Round Ledger references missing or unsafe evidence: $ledger_evidence" >&2
    exit 1
  }
  [[ "$ledger_item" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Item')" \
    && "$ledger_round" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Round')" \
    && "$ledger_verdict" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Verdict')" \
    && "$ledger_head_sha" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$ledger_scope" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$ledger_manifest" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$ledger_execution" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$ledger_base_sha" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$ledger_opened" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Opened event')" \
    && "$ledger_opened_hash" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Opened event sha256')" \
    && "$ledger_root" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Remediation root')" \
    && "$ledger_root_hash" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Remediation root sha256')" \
    && "$ledger_affected" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Affected units')" \
    && "$ledger_builder" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Builder ID')" \
    && "$ledger_critic" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Critic ID')" \
    && "$ledger_isolation" == "$(gauntlet_section_field "$ledger_round_file" 'Round Metadata' 'Isolation')" ]] || {
    echo "Round Ledger fields do not match their exact evidence file: $ledger_evidence" >&2
    exit 1
  }
  [[ "$ledger_hash" == "$(gauntlet_hash_file "$ledger_round_file")" ]] || {
    echo "Round Ledger hash is stale for its exact evidence file: $ledger_evidence" >&2
    exit 1
  }
done < <(gauntlet_extract_section "$gauntlet_file" 'Round Ledger')
if [[ $round_count -eq 0 ]]; then
  [[ $ledger_count -eq 0 && $round_placeholder_count -eq 1 ]] || {
    echo 'An empty Round Ledger requires exactly one canonical placeholder.' >&2
    exit 1
  }
else
  [[ $round_placeholder_count -eq 0 && $ledger_count -eq $round_count ]] || {
    echo "Round Ledger count ($ledger_count) does not match immutable round evidence count ($round_count)." >&2
    exit 1
  }
fi

pr_event_count=0
live_pr_count=0
pr_urls_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-pr-urls.XXXXXX")"
qa_rounds_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-pr-qa-rounds.XXXXXX")"
qa_comment_evidence_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-qa-comments.XXXXXX")"
pr_ledger_paths="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-pr-ledger-paths.XXXXXX")"
remediation_trigger_records="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-remediation-triggers.XXXXXX")"
remediation_triggers_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-remediation-triggers-seen.XXXXXX")"
publication_checkpoints_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-publication-checkpoints.XXXXXX")"
trap 'rm -f "$seen_units" "$critics_seen" "$builders_seen" "$historical_bars" "$historical_manifests" "$round_ledger_paths" "$pr_urls_seen" "$qa_rounds_seen" "$qa_comment_evidence_seen" "$pr_ledger_paths" "$remediation_trigger_records" "$remediation_triggers_seen" "$publication_checkpoints_seen"' EXIT
[[ ! -L "$gauntlet_dir/pr-events" ]] || {
  echo "Gauntlet PR events directory must not be a symbolic link: $gauntlet_dir/pr-events" >&2
  exit 1
}
if [[ -d "$gauntlet_dir/pr-events" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/pr-events" 'Gauntlet PR events directory'
  linked_pr_event_path="$(find "$gauntlet_dir/pr-events" -type l -print -quit)"
  [[ -z "$linked_pr_event_path" ]] || {
    echo "Gauntlet PR event history must not contain symbolic links: $linked_pr_event_path" >&2
    exit 1
  }
  unexpected_pr_event_root_entry="$(find "$gauntlet_dir/pr-events" -mindepth 1 -maxdepth 1 ! -type d -print -quit)"
  [[ -z "$unexpected_pr_event_root_entry" ]] || {
    echo "Gauntlet PR event root may contain only work-unit directories: $unexpected_pr_event_root_entry" >&2
    exit 1
  }

  while IFS= read -r item_event_dir; do
    [[ -n "$item_event_dir" ]] || continue
    gauntlet_assert_safe_ai_path "$item_event_dir" 'Gauntlet item PR events directory'
    event_item="$(basename "$item_event_dir")"
    gauntlet_validate_name "$event_item" 'PR event work-unit id'
    grep -Fqx -- "$event_item" "$seen_units" || {
      echo "Orphan PR event directory has no retained work-unit entry: $event_item" >&2
      exit 1
    }

    expected_event_number=1
    item_event_file_count=0
    opened_event_count=0
    live_pr=0
    live_pr_url=''
    live_head=''
    previous_event=''
    previous_event_record=''
    previous_recorded_at=''
    previous_critic_round='none'
    previous_critic_verdict='none'
    previous_head_sha=''
    previous_scope=''
    previous_manifest=''
    previous_quality_bar=''
    previous_execution=''
    previous_base_sha=''
    previous_publication_checkpoint=''
    previous_publication_checkpoint_hash=''
    previous_created_at=''
    : > "$qa_rounds_seen"

    while IFS= read -r item_event_entry; do
      [[ -n "$item_event_entry" ]] || continue
      event_entry_name="$(basename "$item_event_entry")"
      [[ -f "$item_event_entry" && ! -L "$item_event_entry" \
        && "$event_entry_name" =~ ^event-[0-9]{3,}\.md$ ]] || {
        echo "PR event item directory contains noncanonical evidence: $item_event_entry" >&2
        exit 1
      }
    done < <(find "$item_event_dir" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)

    while IFS=$'\t' read -r numeric_value pr_event_file; do
      [[ -n "$pr_event_file" ]] || continue
      item_event_file_count=$((item_event_file_count + 1))
      pr_event_count=$((pr_event_count + 1))
      printf -v expected_event_label '%03d' "$expected_event_number"
      actual_event_label="$(basename "$pr_event_file")"
      actual_event_label="${actual_event_label#event-}"
      actual_event_label="${actual_event_label%.md}"
      [[ "$numeric_value" -eq "$expected_event_number" && "$actual_event_label" == "$expected_event_label" ]] || {
        echo "PR event sequence must be contiguous and canonically padded; expected event-$expected_event_label.md in $event_item." >&2
        exit 1
      }
      relative_event="${pr_event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      [[ "$(gauntlet_heading_count "$pr_event_file" 'PR Event Metadata')" -eq 1 ]] || {
        echo "PR event requires exactly one metadata heading: $relative_event" >&2
        exit 1
      }
      for pr_metadata_key in 'Item' 'Sequence' 'Event' 'PR URL' 'Head branch' 'Target branch' 'Head SHA' \
        'Scope fingerprint' 'Unit manifest fingerprint' 'Execution contract fingerprint' 'Base commit SHA' 'Target base SHA' \
        'Cross repository' 'Head repository' \
        'Publication checkpoint' 'Publication checkpoint sha256' \
        'Evidence URL' 'QA comment author' 'QA comment author type' 'QA comment author association' \
        'QA comment created at' 'QA comment updated at' 'QA comment body sha256' 'Merge commit' 'Critic round' 'Critic verdict' \
        'Quality bar fingerprint' 'Observed state' 'Draft' 'Created at' 'Closed at' 'Merged at' 'Merged by' 'Merged by bot' \
        'Merged by type' \
        'Remediation trigger' 'Recorded at'; do
        [[ "$(gauntlet_section_field_count "$pr_event_file" 'PR Event Metadata' "$pr_metadata_key")" -eq 1 ]] || {
          echo "PR event requires exactly one '$pr_metadata_key' field: $relative_event" >&2
          exit 1
        }
      done
      metadata_item="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Item')"
      metadata_sequence="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Sequence')"
      metadata_event="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Event')"
      metadata_pr_url="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'PR URL')"
      metadata_pr_url="${metadata_pr_url%/}"
      metadata_head_branch="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Head branch')"
      metadata_target_branch="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Target branch')"
      metadata_head_sha="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Head SHA')"
      metadata_head_sha="${metadata_head_sha,,}"
      metadata_scope="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Scope fingerprint')"
      metadata_manifest="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')"
      metadata_execution="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')"
      metadata_base_sha="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')"
      metadata_target_base_sha="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Target base SHA' | tr '[:upper:]' '[:lower:]')"
      metadata_cross_repository="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Cross repository')"
      metadata_head_repository="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Head repository')"
      metadata_publication_checkpoint="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Publication checkpoint')"
      metadata_publication_checkpoint_hash="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Publication checkpoint sha256')"
      metadata_evidence_url="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Evidence URL')"
      metadata_qa_author="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'QA comment author')"
      metadata_qa_author_type="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'QA comment author type')"
      metadata_qa_author_association="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'QA comment author association')"
      metadata_qa_created_at="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'QA comment created at')"
      metadata_qa_updated_at="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'QA comment updated at')"
      metadata_qa_body_hash="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'QA comment body sha256')"
      metadata_merge_commit="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Merge commit')"
      metadata_critic_round="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Critic round')"
      metadata_critic_verdict="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Critic verdict')"
      metadata_quality_bar="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Quality bar fingerprint')"
      metadata_observed_state="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Observed state')"
      metadata_draft="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Draft')"
      metadata_created_at="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Created at')"
      metadata_closed_at="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Closed at')"
      metadata_merged_at="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Merged at')"
      metadata_merged_by="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Merged by')"
      metadata_merged_by_type="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Merged by type')"
      metadata_merged_by_bot="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Merged by bot')"
      metadata_remediation_trigger="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Remediation trigger')"
      recorded_at="$(gauntlet_section_field "$pr_event_file" 'PR Event Metadata' 'Recorded at')"

      [[ "$metadata_item" == "$event_item" && "$metadata_sequence" == "$expected_event_label" ]] || {
        echo "PR event metadata does not match its path: $relative_event" >&2
        exit 1
      }
      case "$metadata_event" in opened|qa-pass|qa-fail|merged|closed) ;; *) echo "Invalid PR event action: $relative_event" >&2; exit 1 ;; esac
      gauntlet_validate_github_pr_url "$metadata_pr_url" 'PR event URL'
      gauntlet_validate_branch "$metadata_head_branch" 'PR event head branch'
      gauntlet_validate_evidence_url "$metadata_evidence_url" 'PR event evidence URL'
      gauntlet_validate_head_sha "$metadata_head_sha" 'PR event Head SHA'
      [[ "$metadata_scope" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "PR event has an invalid scope fingerprint: $relative_event" >&2; exit 1; }
      [[ "$metadata_manifest" =~ ^[0-9a-f]{64}$ ]] || { echo "PR event has an invalid unit-manifest fingerprint: $relative_event" >&2; exit 1; }
      [[ "$metadata_execution" =~ ^[0-9a-f]{64}$ \
        && "$metadata_execution" == "$current_execution_fingerprint" ]] || {
        echo "PR event has a stale or invalid execution-contract fingerprint: $relative_event" >&2
        exit 1
      }
      [[ "$metadata_base_sha" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ \
        && "$metadata_base_sha" == "${base_commit_sha,,}" ]] || {
        echo "PR event has a stale or invalid approved base commit SHA: $relative_event" >&2
        exit 1
      }
      gauntlet_validate_head_sha "$metadata_target_base_sha" 'PR event Target base SHA'
      expected_progress_head="gauntlet-work/$gauntlet_name/$event_item"
      [[ "$metadata_target_branch" == "$integration_branch" \
        && ( "$metadata_head_branch" == "$expected_progress_head" \
          || "$metadata_head_branch" =~ ^${expected_progress_head}-remediation-[1-9][0-9]*$ ) ]] || {
        echo "Progress PR event must target $integration_branch from the canonical work-unit branch: $relative_event" >&2
        exit 1
      }
      [[ "$(gauntlet_github_repo_from_url "$metadata_pr_url")" == "$(gauntlet_github_repo_from_url "$issue_url")" ]] || {
        echo "Progress PR event repository does not match the parent issue: $relative_event" >&2
        exit 1
      }
      [[ "$metadata_cross_repository" == 'false' \
        && "${metadata_head_repository,,}" == "$(gauntlet_github_repo_from_url "$issue_url" | tr '[:upper:]' '[:lower:]')" ]] || {
        echo "Progress PR event does not prove an approved same-repository head: $relative_event" >&2
        exit 1
      }
      [[ "$metadata_quality_bar" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "PR event has an invalid quality-bar fingerprint: $relative_event" >&2; exit 1; }
      printf '%s\n' "${metadata_quality_bar,,}" >> "$historical_bars"
      printf '%s\n' "$metadata_manifest" >> "$historical_manifests"
      gauntlet_validate_replay_timestamp "$recorded_at" "PR event Recorded at ($relative_event)"
      gauntlet_validate_replay_timestamp "$metadata_created_at" "PR Created at ($relative_event)"
      [[ "$metadata_created_at" < "$recorded_at" || "$metadata_created_at" == "$recorded_at" ]] || {
        echo "PR event predates external PR creation: $relative_event" >&2
        exit 1
      }
      [[ "$metadata_publication_checkpoint" =~ ^\.ai/gauntlets/${gauntlet_name}/publication-checkpoints/${event_item}/checkpoint-[0-9]{3,}\.md$ \
        && -f "$OPENCAW_PROJECT_ROOT_RESOLVED/$metadata_publication_checkpoint" \
        && ! -L "$OPENCAW_PROJECT_ROOT_RESOLVED/$metadata_publication_checkpoint" \
        && "$metadata_publication_checkpoint_hash" == "$(gauntlet_hash_file "$OPENCAW_PROJECT_ROOT_RESOLVED/$metadata_publication_checkpoint")" ]] || {
        echo "PR event has missing or stale publication checkpoint evidence: $relative_event" >&2
        exit 1
      }
      metadata_checkpoint_cutoff="$(gauntlet_section_field \
        "$OPENCAW_PROJECT_ROOT_RESOLVED/$metadata_publication_checkpoint" \
        'Publication Checkpoint Metadata' 'Recorded at')"
      case "$metadata_event" in
        qa-pass|qa-fail)
          gauntlet_validate_same_pr_comment_url "$metadata_evidence_url" "$metadata_pr_url" 'Progress PR QA evidence'
          if grep -Fqx -- "$metadata_evidence_url" "$qa_comment_evidence_seen"; then
            echo "QA comment evidence was reused across immutable verdict events: $metadata_evidence_url" >&2
            exit 1
          fi
          printf '%s\n' "$metadata_evidence_url" >> "$qa_comment_evidence_seen"
          [[ "$metadata_critic_round" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/${event_item}/round-[0-9]{3,}\.md$ ]] || {
            echo "QA event references invalid critic evidence: $relative_event" >&2
            exit 1
          }
          qa_round_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$metadata_critic_round"
          gauntlet_assert_safe_ai_path "$qa_round_file" 'Progress QA critic-round evidence'
          [[ -f "$qa_round_file" && ! -L "$qa_round_file" ]] || {
            echo "QA event references invalid critic evidence: $relative_event" >&2
            exit 1
          }
          gauntlet_assert_live_pr_comment \
            "$metadata_evidence_url" \
            "$metadata_pr_url" \
            "$(gauntlet_github_repo_from_url "$issue_url")" \
            "${metadata_event#qa-}" \
            "$metadata_head_sha" \
            "$metadata_critic_round" \
            "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Recorded at')" \
            none \
            replay
          [[ "$metadata_qa_author" == "$GAUNTLET_COMMENT_AUTHOR" \
            && "$metadata_qa_author_type" == "$GAUNTLET_COMMENT_AUTHOR_TYPE" \
            && "$metadata_qa_author_association" == "$GAUNTLET_COMMENT_AUTHOR_ASSOCIATION" \
            && "$metadata_qa_created_at" == "$GAUNTLET_COMMENT_CREATED_AT" \
            && "$metadata_qa_updated_at" == "$GAUNTLET_COMMENT_UPDATED_AT" \
            && "$metadata_qa_body_hash" == "$GAUNTLET_COMMENT_BODY_SHA256" \
            && ( "$metadata_created_at" < "$metadata_qa_created_at" \
              || "$metadata_created_at" == "$metadata_qa_created_at" ) \
            && ( "$metadata_qa_created_at" < "$recorded_at" || "$metadata_qa_created_at" == "$recorded_at" ) ]] || {
            echo "Progress QA comment metadata is stale or postdates its immutable event: $relative_event" >&2
            exit 1
          }
          ;;
        merged|closed)
          if [[ "$metadata_evidence_url" != "$metadata_pr_url" ]]; then
            gauntlet_validate_same_pr_comment_url "$metadata_evidence_url" "$metadata_pr_url" 'Progress PR terminal evidence'
          fi
          [[ "$metadata_qa_author" == 'none' && "$metadata_qa_author_type" == 'none' \
            && "$metadata_qa_author_association" == 'none' && "$metadata_qa_created_at" == 'none' \
            && "$metadata_qa_updated_at" == 'none' \
            && "$metadata_qa_body_hash" == 'none' ]] || {
            echo "Non-QA terminal event must not claim QA comment metadata: $relative_event" >&2
            exit 1
          }
          ;;
        opened)
          [[ "$metadata_qa_author" == 'none' && "$metadata_qa_author_type" == 'none' \
            && "$metadata_qa_author_association" == 'none' && "$metadata_qa_created_at" == 'none' \
            && "$metadata_qa_updated_at" == 'none' \
            && "$metadata_qa_body_hash" == 'none' ]] || {
            echo "Opened event must not claim QA comment metadata: $relative_event" >&2
            exit 1
          }
          ;;
      esac
      [[ "$metadata_draft" == 'false' ]] || {
        echo "Progress PR event must prove a non-draft PR: $relative_event" >&2
        exit 1
      }
      case "$metadata_event" in
        opened|qa-pass|qa-fail)
          [[ "$metadata_observed_state" == 'OPEN' && "$metadata_merged_at" == 'none' \
            && "$metadata_closed_at" == 'none' \
            && "$metadata_merged_by" == 'none' && "$metadata_merged_by_type" == 'none' \
            && "$metadata_merged_by_bot" == 'none' ]] || {
            echo "Open progress PR event has inconsistent live observation fields: $relative_event" >&2
            exit 1
          }
          ;;
        merged)
          [[ "$metadata_observed_state" == 'MERGED' \
            && "$metadata_closed_at" != 'none' && "$metadata_merged_at" != 'none' && "$metadata_merged_by" != 'none' \
            && "$metadata_merged_by_type" == 'User' \
            && "$metadata_merged_by_bot" == 'false' ]] || {
            echo "Merged progress PR event lacks exact human-merge observations: $relative_event" >&2
            exit 1
          }
          gauntlet_validate_replay_timestamp "$metadata_merged_at" "PR event Merged at ($relative_event)"
          gauntlet_validate_replay_timestamp "$metadata_closed_at" "PR event Closed at ($relative_event)"
          [[ ( "$metadata_created_at" < "$metadata_closed_at" || "$metadata_created_at" == "$metadata_closed_at" ) \
            && ( "$metadata_closed_at" < "$recorded_at" || "$metadata_closed_at" == "$recorded_at" ) \
            && ( "$previous_recorded_at" < "$metadata_merged_at" || "$previous_recorded_at" == "$metadata_merged_at" ) \
            && ( "$metadata_merged_at" < "$recorded_at" || "$metadata_merged_at" == "$recorded_at" ) ]] || {
            echo "Merged PR external times do not bracket local QA and terminal evidence: $relative_event" >&2
            exit 1
          }
          ;;
        closed)
          [[ "$metadata_observed_state" == 'CLOSED' && "$metadata_merged_at" == 'none' \
            && "$metadata_closed_at" != 'none' \
            && "$metadata_merged_by" == 'none' && "$metadata_merged_by_type" == 'none' \
            && "$metadata_merged_by_bot" == 'none' ]] || {
            echo "Closed progress PR event has inconsistent live observation fields: $relative_event" >&2
            exit 1
          }
          gauntlet_validate_replay_timestamp "$metadata_closed_at" "PR event Closed at ($relative_event)"
          [[ ( "$metadata_created_at" < "$metadata_closed_at" || "$metadata_created_at" == "$metadata_closed_at" ) \
            && ( "$previous_recorded_at" < "$metadata_closed_at" || "$previous_recorded_at" == "$metadata_closed_at" ) \
            && ( "$metadata_closed_at" < "$recorded_at" || "$metadata_closed_at" == "$recorded_at" ) ]] || {
            echo "Closed PR external time does not bracket local cycle evidence: $relative_event" >&2
            exit 1
          }
          ;;
      esac
      if [[ "$metadata_event" != 'opened' ]]; then
        [[ "$metadata_remediation_trigger" == 'none' ]] || {
          echo "Only an opened remediation PR may carry a remediation trigger: $relative_event" >&2
          exit 1
        }
      elif [[ -z "$previous_event" ]]; then
        if [[ "$metadata_remediation_trigger" == quality-revision:* ]]; then
          initial_revision_id="${metadata_remediation_trigger#quality-revision:}"
          earlier_revision_consumers=0
          while IFS= read -r revision_consumer_file; do
            [[ "$revision_consumer_file" != "$pr_event_file" \
              && "$(gauntlet_section_field "$revision_consumer_file" 'PR Event Metadata' 'Event')" == 'opened' \
              && "$(gauntlet_section_field "$revision_consumer_file" 'PR Event Metadata' 'Remediation trigger')" == "$metadata_remediation_trigger" ]] || continue
            revision_consumer_time="$(gauntlet_section_field "$revision_consumer_file" 'PR Event Metadata' 'Recorded at')"
            revision_consumer_precedes=0
            if [[ "$revision_consumer_time" < "$recorded_at" ]]; then
              revision_consumer_precedes=1
            elif [[ "$revision_consumer_time" == "$recorded_at" ]] \
              && gauntlet_progress_pr_event_precedes \
                "$gauntlet_file" \
                "${revision_consumer_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}" \
                "$relative_event"; then
              revision_consumer_precedes=1
            fi
            if [[ "$revision_consumer_precedes" -eq 1 ]]; then
              earlier_revision_consumers=$((earlier_revision_consumers + 1))
            fi
          done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' -print | LC_ALL=C sort)
          [[ -n "$initial_revision_id" && "$earlier_revision_consumers" -eq 0 ]] || {
            echo "Initial unit consumed a stale or already-consumed quality revision: $relative_event" >&2
            exit 1
          }
        else
          latest_inherited_trigger='none'
          latest_inherited_time=''
          while IFS=$'\t' read -r inherited_time inherited_path; do
            [[ -n "$inherited_path" ]] || continue
            inherited_precedes=0
            if [[ "$inherited_time" < "$recorded_at" ]]; then
              inherited_precedes=1
            elif [[ "$inherited_time" == "$recorded_at" ]]; then
              if [[ "$inherited_path" == .ai/gauntlets/*/pr-events/*/event-*.md ]]; then
                gauntlet_progress_pr_event_precedes \
                  "$gauntlet_file" "$inherited_path" "$relative_event" \
                  && inherited_precedes=1
              elif [[ "$metadata_remediation_trigger" == "$inherited_path" ]]; then
                # Equal-second evidence in another ledger has no implicit global
                # order. Its exact immutable trigger is the required causal edge.
                inherited_precedes=1
              fi
            fi
            [[ "$inherited_precedes" -eq 1 ]] || continue

            if [[ -z "$latest_inherited_time" || "$latest_inherited_time" < "$inherited_time" ]]; then
              latest_inherited_time="$inherited_time"
              latest_inherited_trigger="$inherited_path"
            elif [[ "$latest_inherited_time" == "$inherited_time" ]]; then
              if [[ "$latest_inherited_trigger" == .ai/gauntlets/*/pr-events/*/event-*.md \
                && "$inherited_path" == .ai/gauntlets/*/pr-events/*/event-*.md ]]; then
                if gauntlet_progress_pr_event_precedes \
                  "$gauntlet_file" "$latest_inherited_trigger" "$inherited_path"; then
                  latest_inherited_trigger="$inherited_path"
                fi
              elif [[ "$metadata_remediation_trigger" == "$inherited_path" ]]; then
                latest_inherited_trigger="$inherited_path"
              fi
            fi
          done < <(gauntlet_applicable_failures \
            "$gauntlet_file" "$event_item" "$metadata_checkpoint_cutoff" \
            | LC_ALL=C sort -k1,1 -k2,2)
          [[ "$metadata_remediation_trigger" == "$latest_inherited_trigger" ]] || {
            echo "Initial replacement unit must bind the latest inherited ancestor failure, while ordinary initial units use none: $relative_event" >&2
            exit 1
          }
        fi
        if [[ "$metadata_remediation_trigger" != 'none' ]]; then
          trigger_use="$event_item|$metadata_remediation_trigger"
          printf '%s\n' "$trigger_use" >> "$remediation_triggers_seen"
        fi
      elif [[ "$previous_event" == 'closed' ]]; then
        if [[ "$metadata_remediation_trigger" == "$previous_event_record" ]]; then
          :
        elif [[ "$metadata_remediation_trigger" == quality-revision:* ]]; then
          closed_revision_root="$(gauntlet_remediation_root_for_trigger \
            "$gauntlet_file" "$event_item" \
            "$metadata_remediation_trigger" "$metadata_checkpoint_cutoff")" || {
              echo "Replacement after a closed PR has an invalid quality-revision remediation root: $relative_event" >&2
              exit 1
            }
          [[ "$closed_revision_root" == "$previous_event_record" ]] || {
            echo "Replacement after a closed PR must retain that exact terminal event as its quality-revision remediation root: $relative_event" >&2
            exit 1
          }
          trigger_use="$event_item|$metadata_remediation_trigger"
          if grep -Fqx -- "$trigger_use" "$remediation_triggers_seen"; then
            echo "A remediation trigger cannot reopen the same unit more than once: $metadata_remediation_trigger" >&2
            exit 1
          fi
          printf '%s\n' "$trigger_use" >> "$remediation_triggers_seen"
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$event_item" "$previous_event_record" "$previous_recorded_at" \
            "$relative_event" "$recorded_at" "$metadata_remediation_trigger" >> "$remediation_trigger_records"
        else
          echo "Replacement after a closed PR must cite that exact terminal event: $relative_event" >&2
          exit 1
        fi
      elif [[ "$previous_event" == 'merged' ]]; then
        [[ "$metadata_remediation_trigger" != 'none' ]] || {
          echo "Remediation after a merged PR requires an immutable reopening trigger: $relative_event" >&2
          exit 1
        }
        trigger_use="$event_item|$metadata_remediation_trigger"
        if grep -Fqx -- "$trigger_use" "$remediation_triggers_seen"; then
          echo "A remediation trigger cannot reopen the same unit more than once: $metadata_remediation_trigger" >&2
          exit 1
        fi
        printf '%s\n' "$trigger_use" >> "$remediation_triggers_seen"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$event_item" "$previous_event_record" "$previous_recorded_at" \
          "$relative_event" "$recorded_at" "$metadata_remediation_trigger" >> "$remediation_trigger_records"
      fi

      if [[ "$metadata_event" == 'opened' ]]; then
        gauntlet_assert_commit_ancestor "$metadata_target_base_sha" "$metadata_head_sha" \
          "Opened progress PR lineage ($relative_event)"
        latest_eligible_checkpoint=''
        while IFS=$'\t' read -r _candidate_number candidate_checkpoint; do
          [[ -n "$candidate_checkpoint" ]] || continue
          candidate_checkpoint_relative="${candidate_checkpoint#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
          grep -Fqx -- "$candidate_checkpoint_relative" "$publication_checkpoints_seen" && continue
          candidate_checkpoint_time="$(gauntlet_section_field "$candidate_checkpoint" 'Publication Checkpoint Metadata' 'Recorded at')"
          if [[ "$candidate_checkpoint_time" < "$metadata_created_at" \
            || ( "$candidate_checkpoint_time" == "$metadata_created_at" \
              && "$candidate_checkpoint_relative" == "$metadata_publication_checkpoint" ) ]]; then
            latest_eligible_checkpoint="$candidate_checkpoint_relative"
          fi
        done < <(find "$publication_checkpoint_root/$event_item" -maxdepth 1 -type f -name 'checkpoint-*.md' -print \
          | awk '{ name=$0; sub(/^.*\/checkpoint-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
          | LC_ALL=C sort -n -k1,1)
        [[ -n "$latest_eligible_checkpoint" \
          && "$metadata_publication_checkpoint" == "$latest_eligible_checkpoint" ]] || {
          echo "Opened PR did not consume the latest issued, unconsumed checkpoint available before PR creation: $relative_event" >&2
          exit 1
        }
        if grep -Fqx -- "$metadata_publication_checkpoint" "$publication_checkpoints_seen"; then
          echo "Publication checkpoint was consumed by more than one opened PR event: $metadata_publication_checkpoint" >&2
          exit 1
        fi
        printf '%s\n' "$metadata_publication_checkpoint" >> "$publication_checkpoints_seen"
        checkpoint_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$metadata_publication_checkpoint"
        for checkpoint_key in 'Item' 'Sequence' 'Head branch' 'Head SHA' 'Target branch' 'Chain tip' \
          'Remediation trigger' 'Remediation trigger sha256' 'Remediation root' 'Remediation root sha256' \
          'Quality bar fingerprint' 'Quality bar approved at' 'Unit scope fingerprint' 'Unit manifest fingerprint' \
          'Unit manifest approved at' \
          'Execution contract fingerprint' 'Remote integration state' 'Remote integration SHA' \
          'Remote work state' 'Remote work SHA' 'Recorded at'; do
          [[ "$(gauntlet_section_field_count "$checkpoint_file" 'Publication Checkpoint Metadata' "$checkpoint_key")" -eq 1 ]] || {
            echo "Publication checkpoint requires exactly one '$checkpoint_key' field: $metadata_publication_checkpoint" >&2
            exit 1
          }
        done
        checkpoint_recorded_at="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Recorded at')"
        checkpoint_trigger="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation trigger')"
        checkpoint_root="$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root')"
        expected_checkpoint_trigger_hash="$(gauntlet_remediation_trigger_hash "$gauntlet_file" "$metadata_remediation_trigger")"
        expected_checkpoint_root="$(gauntlet_remediation_root_for_trigger \
          "$gauntlet_file" "$event_item" "$metadata_remediation_trigger" "$checkpoint_recorded_at")"
        if [[ "$expected_checkpoint_root" == 'none' ]]; then
          expected_checkpoint_root_hash='none'
        else
          expected_checkpoint_root_hash="$(gauntlet_hash_file "$OPENCAW_PROJECT_ROOT_RESOLVED/$expected_checkpoint_root")"
        fi
        checkpoint_label="$(basename "$metadata_publication_checkpoint")"
        checkpoint_label="${checkpoint_label#checkpoint-}"
        checkpoint_label="${checkpoint_label%.md}"
        [[ "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Item')" == "$event_item" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Sequence')" == "$checkpoint_label" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Head branch')" == "$metadata_head_branch" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" == "$metadata_head_sha" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Target branch')" == "$metadata_target_branch" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Chain tip' | tr '[:upper:]' '[:lower:]')" == "$metadata_target_base_sha" \
          && "$checkpoint_trigger" == "$metadata_remediation_trigger" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation trigger sha256')" == "$expected_checkpoint_trigger_hash" \
          && "$checkpoint_root" == "$expected_checkpoint_root" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remediation root sha256')" == "$expected_checkpoint_root_hash" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar fingerprint')" == "$metadata_quality_bar" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Unit scope fingerprint')" == "$metadata_scope" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Unit manifest fingerprint')" == "$metadata_manifest" \
          && "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Execution contract fingerprint')" == "$metadata_execution" \
          && ( "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote integration state')" == 'exact' \
            || "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote integration state')" == 'absent-create-only' ) \
          && ( "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote work state')" == 'exact' \
            || "$(gauntlet_section_field "$checkpoint_file" 'Publication Checkpoint Metadata' 'Remote work state')" == 'absent-create-only' ) \
          && ( "$checkpoint_recorded_at" < "$metadata_created_at" || "$checkpoint_recorded_at" == "$metadata_created_at" ) ]] || {
          echo "Opened PR event does not replay its immutable publication checkpoint: $relative_event" >&2
          exit 1
        }
      else
        gauntlet_assert_commit_ancestor "$previous_head_sha" "$metadata_head_sha" \
          "Progress PR no-force lineage ($relative_event)"
        [[ "$metadata_publication_checkpoint" == "$previous_publication_checkpoint" \
          && "$metadata_publication_checkpoint_hash" == "$previous_publication_checkpoint_hash" \
          && "$metadata_created_at" == "$previous_created_at" ]] || {
          echo "Progress PR cycle changed its checkpoint or creation evidence after opening: $relative_event" >&2
          exit 1
        }
      fi

      case "$metadata_event" in
        opened)
          [[ $live_pr -eq 0 ]] || { echo "A work unit may have only one live progress PR: $relative_event" >&2; exit 1; }
          [[ "$metadata_evidence_url" == 'none' && "$metadata_merge_commit" == 'none' \
            && "$metadata_critic_round" == 'none' && "$metadata_critic_verdict" == 'none' ]] || {
            echo "Opened PR event has invalid evidence fields: $relative_event" >&2
            exit 1
          }
          if grep -Fqx -- "$metadata_pr_url" "$pr_urls_seen"; then
            echo "A remediation cycle must use a new PR URL: $metadata_pr_url" >&2
            exit 1
          fi
          opened_event_count=$((opened_event_count + 1))
          if [[ $opened_event_count -eq 1 ]]; then
            canonical_open_head="gauntlet-work/$gauntlet_name/$event_item"
          else
            canonical_open_head="gauntlet-work/$gauntlet_name/$event_item-remediation-$((opened_event_count - 1))"
          fi
          [[ "$metadata_head_branch" == "$canonical_open_head" ]] || {
            echo "Opened progress PR head is not the canonical iteration branch: $relative_event" >&2
            exit 1
          }
          printf '%s\n' "$metadata_pr_url" >> "$pr_urls_seen"
          live_pr=1
          live_pr_url="$metadata_pr_url"
          live_head="$metadata_head_branch"
          ;;
        qa-pass|qa-fail)
          [[ $live_pr -eq 1 && "$metadata_pr_url" == "$live_pr_url" && "$metadata_head_branch" == "$live_head" \
            && "$metadata_manifest" == "$previous_manifest" ]] || {
            echo "QA event does not belong to the live progress PR: $relative_event" >&2
            exit 1
          }
          [[ "$metadata_evidence_url" != 'none' && "$metadata_merge_commit" == 'none' ]] || {
            echo "QA event requires URL evidence and no merge commit: $relative_event" >&2
            exit 1
          }
          round_verdict="$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Verdict')"
          [[ "$metadata_critic_verdict" == "$round_verdict" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Progress PR')" == "$metadata_pr_url" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Head branch')" == "$metadata_head_branch" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Head SHA')" == "$metadata_head_sha" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Scope fingerprint')" == "$metadata_scope" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Unit manifest fingerprint')" == "$metadata_manifest" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Quality bar fingerprint')" == "$metadata_quality_bar" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Execution contract fingerprint')" == "$metadata_execution" \
            && "$(gauntlet_section_field "$qa_round_file" 'Round Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$metadata_base_sha" ]] || {
            echo "QA event does not match its critic round: $relative_event" >&2
            exit 1
          }
          [[ "$metadata_event" != 'qa-pass' || "$metadata_critic_verdict" == 'pass' ]] || {
            echo "qa-pass requires passing critic evidence: $relative_event" >&2
            exit 1
          }
          if grep -Fqx -- "$metadata_critic_round" "$qa_rounds_seen"; then
            echo "Critic round has more than one progress-PR QA event: $metadata_critic_round" >&2
            exit 1
          fi
          printf '%s\n' "$metadata_critic_round" >> "$qa_rounds_seen"
          ;;
        merged)
          [[ $live_pr -eq 1 && "$metadata_pr_url" == "$live_pr_url" && "$metadata_head_branch" == "$live_head" \
            && "$previous_event" == 'qa-pass' \
            && "$metadata_critic_round" == "$previous_critic_round" \
            && "$metadata_critic_verdict" == 'pass' \
            && "$metadata_head_sha" == "$previous_head_sha" \
            && "$metadata_scope" == "$previous_scope" \
            && "$metadata_manifest" == "$previous_manifest" \
            && "$metadata_quality_bar" == "$previous_quality_bar" \
            && "$metadata_execution" == "$previous_execution" \
            && "$metadata_base_sha" == "$previous_base_sha" \
            && "$metadata_evidence_url" != 'none' \
            && "$metadata_merge_commit" =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]] || {
            echo "Merged event requires the live PR's latest QA pass and full human merge SHA: $relative_event" >&2
            exit 1
          }
          live_pr=0
          ;;
        closed)
          [[ $live_pr -eq 1 && "$metadata_pr_url" == "$live_pr_url" && "$metadata_head_branch" == "$live_head" \
            && "$metadata_evidence_url" != 'none' && "$metadata_merge_commit" == 'none' ]] || {
            echo "Closed event does not match the live progress PR: $relative_event" >&2
            exit 1
          }
          latest_live_round=''
          if [[ -d "$gauntlet_dir/rounds/$event_item" ]]; then
            latest_live_round="$(gauntlet_latest_round_file_for_pr \
              "$gauntlet_dir/rounds/$event_item" "$metadata_pr_url")"
          fi
          if [[ -n "$latest_live_round" ]]; then
            latest_live_round_relative="${latest_live_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
            latest_live_round_verdict="$(gauntlet_section_field "$latest_live_round" 'Round Metadata' 'Verdict')"
            [[ "$previous_event" == 'qa-pass' || "$previous_event" == 'qa-fail' ]] || {
              echo "Closed event cannot discard an unconsumed latest critic round: $relative_event" >&2
              exit 1
            }
            [[ "$metadata_critic_round" == "$latest_live_round_relative" \
              && "$metadata_critic_verdict" == "$latest_live_round_verdict" \
              && "$previous_critic_round" == "$latest_live_round_relative" \
              && "$previous_critic_verdict" == "$latest_live_round_verdict" \
              && "$metadata_head_sha" == "$previous_head_sha" \
              && "$metadata_scope" == "$previous_scope" \
              && "$metadata_manifest" == "$previous_manifest" \
              && "$metadata_quality_bar" == "$previous_quality_bar" \
              && "$metadata_execution" == "$previous_execution" \
              && "$metadata_base_sha" == "$previous_base_sha" ]] || {
              echo "Closed event does not follow QA consumption of the live PR's latest critic round: $relative_event" >&2
              exit 1
            }
          else
            [[ "$metadata_critic_round" == 'none' && "$metadata_critic_verdict" == 'none' ]] || {
              echo "Closed event without a critic round must retain canonical none evidence: $relative_event" >&2
              exit 1
            }
          fi
          live_pr=0
          ;;
      esac

      previous_event="$metadata_event"
      previous_event_record="$relative_event"
      previous_recorded_at="$recorded_at"
      previous_critic_round="$metadata_critic_round"
      previous_critic_verdict="$metadata_critic_verdict"
      previous_head_sha="$metadata_head_sha"
      previous_scope="$metadata_scope"
      previous_manifest="$metadata_manifest"
      previous_quality_bar="$metadata_quality_bar"
      previous_execution="$metadata_execution"
      previous_base_sha="$metadata_base_sha"
      previous_publication_checkpoint="$metadata_publication_checkpoint"
      previous_publication_checkpoint_hash="$metadata_publication_checkpoint_hash"
      previous_created_at="$metadata_created_at"
      expected_event_number=$((expected_event_number + 1))
    done < <(find "$item_event_dir" -maxdepth 1 -type f -name 'event-*.md' -print \
      | awk '{ name=$0; sub(/^.*\/event-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
      | LC_ALL=C sort -n -k1,1)
    [[ $item_event_file_count -gt 0 ]] || { echo "Orphan or empty PR event directory: $item_event_dir" >&2; exit 1; }
    if [[ $live_pr -eq 1 ]]; then
      live_pr_count=$((live_pr_count + 1))
      current_event_scope="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$event_item")"
      [[ "$previous_scope" == "$current_event_scope" ]] || {
        echo "Live progress PR uses a stale work-unit scope: $event_item" >&2
        exit 1
      }
    elif [[ "$previous_event" == 'merged' ]]; then
      current_event_scope="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$event_item")"
      current_event_unit="$(gauntlet_work_unit_lines "$gauntlet_file" | awk -v item="$event_item" '$0 ~ "^- \\[[ xX]\\] " item " \\|" { print; exit }')"
      if [[ "$current_event_unit" =~ \|[[:space:]]status:[[:space:]]passed[[:space:]]\| \
        && "$previous_scope" != "$current_event_scope" ]]; then
        echo "Passed work unit changed scope without being reopened: $event_item" >&2
        exit 1
      fi
    fi
  done < <(find "$gauntlet_dir/pr-events" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
fi

[[ "$status" != 'passed' || $live_pr_count -eq 0 ]] || {
  echo 'A passed Gauntlet cannot retain a live progress PR.' >&2
  exit 1
}

pr_ledger_count=0
pr_placeholder_count=0
pr_ledger_pattern='^- ([^|[:space:]]+) \| event: ([0-9]{3,}) \| action: (opened|qa-pass|qa-fail|merged|closed) \| pr: ([^|[:space:]]+) \| head: ([^|[:space:]]+) \| head-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| scope: ([0-9a-f]{64}) \| manifest: ([0-9a-f]{64}) \| contract: ([0-9a-f]{64}) \| base-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| target: ([^|[:space:]]+) \| target-base-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| pr-created: ([^|[:space:]]+) \| pr-closed: ([^|[:space:]]+) \| checkpoint: ([^|[:space:]]+) \| checkpoint-sha256: ([0-9a-f]{64}) \| evidence: ([^|[:space:]]+) \| qa-author: ([^|[:space:]]+) \| qa-created: ([^|[:space:]]+) \| merged-by: ([^|[:space:]]+) \| merged-by-type: (none|User) \| merged-by-bot: (none|false) \| merge-commit: (none|[0-9a-f]{40}|[0-9a-f]{64}) \| trigger: ([^|[:space:]]+) \| record: ([^|[:space:]]+) \| sha256: ([0-9a-f]{64})$'
while IFS= read -r pr_ledger_line; do
  [[ "$pr_ledger_line" =~ ^[[:space:]]*$ ]] && continue
  if [[ "$pr_ledger_line" == '- No progress PR events recorded.' ]]; then
    pr_placeholder_count=$((pr_placeholder_count + 1))
    continue
  fi
  if [[ ! "$pr_ledger_line" =~ $pr_ledger_pattern ]]; then
    echo "Invalid or noncanonical Progress PR Ledger content: $pr_ledger_line" >&2
    exit 1
  fi

  pr_ledger_item="${BASH_REMATCH[1]}"
  pr_ledger_sequence="${BASH_REMATCH[2]}"
  pr_ledger_action="${BASH_REMATCH[3]}"
  pr_ledger_url="${BASH_REMATCH[4]}"
  pr_ledger_head="${BASH_REMATCH[5]}"
  pr_ledger_head_sha="${BASH_REMATCH[6]}"
  pr_ledger_scope="${BASH_REMATCH[7]}"
  pr_ledger_manifest="${BASH_REMATCH[8]}"
  pr_ledger_execution="${BASH_REMATCH[9]}"
  pr_ledger_base_sha="${BASH_REMATCH[10]}"
  pr_ledger_target="${BASH_REMATCH[11]}"
  pr_ledger_target_base_sha="${BASH_REMATCH[12]}"
  pr_ledger_created_at="${BASH_REMATCH[13]}"
  pr_ledger_closed_at="${BASH_REMATCH[14]}"
  pr_ledger_checkpoint="${BASH_REMATCH[15]}"
  pr_ledger_checkpoint_hash="${BASH_REMATCH[16]}"
  pr_ledger_evidence="${BASH_REMATCH[17]}"
  pr_ledger_qa_author="${BASH_REMATCH[18]}"
  pr_ledger_qa_created="${BASH_REMATCH[19]}"
  pr_ledger_merged_by="${BASH_REMATCH[20]}"
  pr_ledger_merged_by_type="${BASH_REMATCH[21]}"
  pr_ledger_merged_by_bot="${BASH_REMATCH[22]}"
  pr_ledger_merge_commit="${BASH_REMATCH[23]}"
  pr_ledger_trigger="${BASH_REMATCH[24]}"
  pr_ledger_record="${BASH_REMATCH[25]}"
  pr_ledger_hash="${BASH_REMATCH[26]}"
  pr_ledger_count=$((pr_ledger_count + 1))

  gauntlet_validate_name "$pr_ledger_item" 'Progress PR Ledger work-unit id'
  grep -Fqx -- "$pr_ledger_item" "$seen_units" || {
    echo "Progress PR Ledger references an unknown work unit: $pr_ledger_item" >&2
    exit 1
  }
  expected_pr_ledger_record=".ai/gauntlets/$gauntlet_name/pr-events/$pr_ledger_item/event-$pr_ledger_sequence.md"
  [[ "$pr_ledger_record" == "$expected_pr_ledger_record" ]] || {
    echo "Progress PR Ledger path does not match its item and event: $pr_ledger_record" >&2
    exit 1
  }
  if grep -Fqx -- "$pr_ledger_record" "$pr_ledger_paths"; then
    echo "Progress PR Ledger evidence path is duplicated: $pr_ledger_record" >&2
    exit 1
  fi
  printf '%s\n' "$pr_ledger_record" >> "$pr_ledger_paths"
  pr_ledger_event_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$pr_ledger_record"
  [[ -f "$pr_ledger_event_file" && ! -L "$pr_ledger_event_file" ]] || {
    echo "Progress PR Ledger references missing or unsafe evidence: $pr_ledger_record" >&2
    exit 1
  }
  event_file_pr_url="$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'PR URL')"
  event_file_pr_url="${event_file_pr_url%/}"
  [[ "$pr_ledger_item" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Item')" \
    && "$pr_ledger_sequence" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Sequence')" \
    && "$pr_ledger_action" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Event')" \
    && "$pr_ledger_url" == "$event_file_pr_url" \
    && "$pr_ledger_head" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Head branch')" \
    && "$pr_ledger_head_sha" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$pr_ledger_scope" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$pr_ledger_manifest" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$pr_ledger_execution" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$pr_ledger_base_sha" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$pr_ledger_target" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Target branch')" \
    && "$pr_ledger_target_base_sha" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Target base SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$pr_ledger_created_at" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Created at')" \
    && "$pr_ledger_closed_at" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Closed at')" \
    && "$pr_ledger_checkpoint" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Publication checkpoint')" \
    && "$pr_ledger_checkpoint_hash" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Publication checkpoint sha256')" \
    && "$pr_ledger_evidence" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Evidence URL')" \
    && "$pr_ledger_qa_author" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'QA comment author')" \
    && "$pr_ledger_qa_created" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'QA comment created at')" \
    && "$pr_ledger_merged_by" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Merged by')" \
    && "$pr_ledger_merged_by_type" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Merged by type')" \
    && "$pr_ledger_merged_by_bot" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Merged by bot')" \
    && "$pr_ledger_merge_commit" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Merge commit' | tr '[:upper:]' '[:lower:]')" \
    && "$pr_ledger_trigger" == "$(gauntlet_section_field "$pr_ledger_event_file" 'PR Event Metadata' 'Remediation trigger')" ]] || {
    echo "Progress PR Ledger fields do not match their exact evidence file: $pr_ledger_record" >&2
    exit 1
  }
  [[ "$pr_ledger_hash" == "$(gauntlet_hash_file "$pr_ledger_event_file")" ]] || {
    echo "Progress PR Ledger hash is stale for its exact evidence file: $pr_ledger_record" >&2
    exit 1
  }
done < <(gauntlet_extract_section "$gauntlet_file" 'Progress PR Ledger')
if [[ $pr_event_count -eq 0 ]]; then
  [[ $pr_ledger_count -eq 0 && $pr_placeholder_count -eq 1 ]] || {
    echo 'An empty Progress PR Ledger requires exactly one canonical placeholder.' >&2
    exit 1
  }
else
  [[ $pr_placeholder_count -eq 0 && $pr_ledger_count -eq $pr_event_count ]] || {
    echo "Progress PR Ledger count ($pr_ledger_count) does not match immutable event evidence count ($pr_event_count)." >&2
    exit 1
  }
fi

promotion_event_count=0
promotion_archive_count=0
promotion_ledger_paths="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-promotion-ledger-paths.XXXXXX")"
promotion_archive_paths="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-promotion-archive-paths.XXXXXX")"
promotion_completion_states="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-promotion-completion-states.XXXXXX")"
promotion_affected_values="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-promotion-affected.XXXXXX")"
trap 'rm -f "$seen_units" "$critics_seen" "$builders_seen" "$historical_bars" "$historical_manifests" "$round_ledger_paths" "$pr_urls_seen" "$qa_rounds_seen" "$qa_comment_evidence_seen" "$pr_ledger_paths" "$remediation_trigger_records" "$remediation_triggers_seen" "$promotion_ledger_paths" "$promotion_archive_paths" "$promotion_completion_states" "$promotion_affected_values"' EXIT

promotion_event_dir="$gauntlet_dir/promotion-events"
[[ ! -L "$promotion_event_dir" ]] || {
  echo "Gauntlet promotion events directory must not be a symbolic link: $promotion_event_dir" >&2
  exit 1
}
latest_promotion_verdict=''
latest_promotion_head_sha=''
latest_promotion_scope=''
latest_promotion_quality_bar=''
latest_promotion_execution=''
latest_promotion_base_sha=''
latest_promotion_completion=''
latest_promotion_recorded_at=''
latest_promotion_event_file=''
promotion_series_pr_url=''
promotion_series_created_at=''
previous_promotion_head_sha=''
previous_promotion_target_base_sha=''
previous_promotion_qa_created_at=''
previous_promotion_qa_comment_id='0'
previous_promotion_recorded_at=''
current_integration_review_head="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
promotion_live_chain_tip=''
if [[ -d "$promotion_event_dir" ]]; then
  gauntlet_assert_safe_ai_path "$promotion_event_dir" 'Gauntlet promotion events directory'
  linked_promotion_path="$(find "$promotion_event_dir" -type l -print -quit)"
  [[ -z "$linked_promotion_path" ]] || {
    echo "Gauntlet promotion history must not contain symbolic links: $linked_promotion_path" >&2
    exit 1
  }
  while IFS= read -r promotion_entry; do
    [[ -n "$promotion_entry" ]] || continue
    promotion_entry_name="$(basename "$promotion_entry")"
    [[ -f "$promotion_entry" && ! -L "$promotion_entry" \
      && ( "$promotion_entry_name" =~ ^event-[0-9]{3,}\.md$ \
        || "$promotion_entry_name" =~ ^GAUNTLET_REPORT-before-event-[0-9]{3,}\.md$ ) ]] || {
      echo "Promotion event directory contains noncanonical evidence: $promotion_entry" >&2
      exit 1
    }
  done < <(find "$promotion_event_dir" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort)

  latest_promotion_event_file="$(gauntlet_latest_promotion_event_file "$promotion_event_dir")"
  if [[ -n "$latest_promotion_event_file" \
    && ( "$phase" == 'ready' || "$phase" == 'complete' ) ]]; then
    gauntlet_assert_github_default_branch \
      "$(gauntlet_github_repo_from_url "$issue_url")" "$base_branch"
    promotion_live_chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")"
    promotion_live_local_tip="$(gauntlet_local_branch_sha "$integration_branch" 'Gauntlet promotion source branch')"
    [[ "$promotion_live_local_tip" == "$promotion_live_chain_tip" ]] || {
      echo 'Gauntlet promotion source branch differs from the reconstructed progress-PR merge chain.' >&2
      exit 1
    }
    gauntlet_assert_remote_integration_tip "$gauntlet_file" "$promotion_live_chain_tip"
  fi
  expected_promotion_number=1
  while IFS=$'\t' read -r numeric_value promotion_event_file; do
    [[ -n "$promotion_event_file" ]] || continue
    promotion_event_count=$((promotion_event_count + 1))
    printf -v expected_promotion_label '%03d' "$expected_promotion_number"
    promotion_filename="$(basename "$promotion_event_file")"
    actual_promotion_label="${promotion_filename#event-}"
    actual_promotion_label="${actual_promotion_label%.md}"
    [[ "$numeric_value" -eq "$expected_promotion_number" \
      && "$actual_promotion_label" == "$expected_promotion_label" ]] || {
      echo "Promotion event sequence must be contiguous and canonically padded; expected event-$expected_promotion_label.md." >&2
      exit 1
    }
    relative_promotion_event="${promotion_event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    promotion_title="# Gauntlet Promotion QA Event: $expected_promotion_label"
    [[ "$(awk -v target="$promotion_title" '{ sub(/\r$/, "") } $0 == target { count++ } END { print count + 0 }' "$promotion_event_file")" -eq 1 \
      && "$(gauntlet_heading_count "$promotion_event_file" 'Promotion QA Event Metadata')" -eq 1 ]] || {
      echo "Promotion QA event headings are noncanonical: $relative_promotion_event" >&2
      exit 1
    }
    for promotion_metadata_key in 'Sequence' 'Verdict' 'Promotion PR URL' 'Source branch' 'Target branch' \
      'Target base SHA' 'Cross repository' 'Head repository' 'Head SHA' 'Scope fingerprint' 'Quality bar fingerprint' 'Execution contract fingerprint' \
      'Unit manifest fingerprint' 'Base commit SHA' 'Completion event' 'Affected units' 'Evidence URL' \
      'QA comment ID' \
      'QA comment author' 'QA comment author type' 'QA comment author association' \
      'QA comment created at' 'QA comment updated at' 'QA comment body sha256' \
      'Observed state' 'Draft' 'Created at' 'Closed at' 'Merged at' \
      'Archived report' 'Archived report sha256' 'Recorded at'; do
      [[ "$(gauntlet_section_field_count "$promotion_event_file" 'Promotion QA Event Metadata' "$promotion_metadata_key")" -eq 1 ]] || {
        echo "Promotion QA event requires exactly one '$promotion_metadata_key' field: $relative_promotion_event" >&2
        exit 1
      }
    done

    promotion_sequence="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Sequence')"
    promotion_verdict="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Verdict')"
    promotion_pr_url="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Promotion PR URL')"
    promotion_pr_url="${promotion_pr_url%/}"
    promotion_source="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Source branch')"
    promotion_target="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Target branch')"
    promotion_target_base_sha="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Target base SHA' | tr '[:upper:]' '[:lower:]')"
    promotion_cross_repository="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Cross repository')"
    promotion_head_repository="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Head repository')"
    promotion_head_sha="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
    promotion_scope="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')"
    promotion_quality_bar="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')"
    promotion_manifest="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')"
    promotion_execution="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')"
    promotion_base_sha="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')"
    promotion_completion="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Completion event')"
    promotion_affected="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Affected units')"
    promotion_evidence_url="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Evidence URL')"
    promotion_qa_comment_id="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'QA comment ID')"
    promotion_qa_author="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'QA comment author')"
    promotion_qa_author_type="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'QA comment author type')"
    promotion_qa_author_association="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'QA comment author association')"
    promotion_qa_created_at="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'QA comment created at')"
    promotion_qa_updated_at="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'QA comment updated at')"
    promotion_qa_body_hash="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'QA comment body sha256')"
    promotion_observed_state="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Observed state')"
    promotion_draft="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Draft')"
    promotion_created_at="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Created at')"
    promotion_closed_at="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Closed at')"
    promotion_merged_at="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Merged at')"
    promotion_archived_report="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Archived report')"
    promotion_archived_hash="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Archived report sha256')"
    promotion_recorded_at="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Recorded at')"

    [[ "$promotion_sequence" == "$expected_promotion_label" ]] || {
      echo "Promotion QA event sequence does not match its path: $relative_promotion_event" >&2
      exit 1
    }
    case "$promotion_verdict" in pass|fail) ;; *) echo "Invalid Promotion QA verdict: $relative_promotion_event" >&2; exit 1 ;; esac
    gauntlet_validate_github_pr_url "$promotion_pr_url" 'Promotion QA PR URL'
    [[ "$(gauntlet_github_repo_from_url "$promotion_pr_url")" == "$(gauntlet_github_repo_from_url "$issue_url")" ]] || {
      echo "Promotion QA PR repository does not match the parent issue: $relative_promotion_event" >&2
      exit 1
    }
    [[ "$promotion_cross_repository" == 'false' \
      && "${promotion_head_repository,,}" == "$(gauntlet_github_repo_from_url "$issue_url" | tr '[:upper:]' '[:lower:]')" ]] || {
      echo "Promotion QA event does not prove an approved same-repository head: $relative_promotion_event" >&2
      exit 1
    }
    [[ "$promotion_source" == "$integration_branch" && "$promotion_target" == "$base_branch" ]] || {
      echo "Promotion QA event must bind the integration branch to the approved delivery base: $relative_promotion_event" >&2
      exit 1
    }
    gauntlet_validate_head_sha "$promotion_target_base_sha" 'Promotion QA Target base SHA'
    gauntlet_assert_commit_ancestor "$base_commit_sha" "$promotion_target_base_sha" "Promotion QA target lineage ($relative_promotion_event)"
    gauntlet_validate_head_sha "$promotion_head_sha" 'Promotion QA Head SHA'
    [[ "$promotion_scope" =~ ^[0-9a-f]{64}$ && "$promotion_quality_bar" =~ ^[0-9a-f]{64}$ \
      && "$promotion_manifest" =~ ^[0-9a-f]{64}$ ]] || {
      echo "Promotion QA event has an invalid scope, manifest, or quality-bar fingerprint: $relative_promotion_event" >&2
      exit 1
    }
    [[ "$promotion_execution" =~ ^[0-9a-f]{64}$ \
      && "$promotion_execution" == "$current_execution_fingerprint" \
      && "$promotion_base_sha" == "${base_commit_sha,,}" ]] || {
      echo "Promotion QA event has a stale execution contract or base SHA: $relative_promotion_event" >&2
      exit 1
    }
    [[ "$promotion_completion" =~ ^\.ai/gauntlets/${gauntlet_name}/completion-events/event-[0-9]{3,}\.md$ ]] || {
      echo "Promotion QA event references invalid completion evidence: $relative_promotion_event" >&2
      exit 1
    }
    promotion_completion_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$promotion_completion"
    gauntlet_assert_safe_ai_path "$promotion_completion_file" \
      'Promotion completion evidence'
    [[ -f "$promotion_completion_file" && ! -L "$promotion_completion_file" ]] || {
      echo "Promotion QA event references invalid completion evidence: $relative_promotion_event" >&2
      exit 1
    }
    [[ "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Outcome')" == 'complete' \
      && "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" == "$promotion_head_sha" \
      && "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_scope" \
      && "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_quality_bar" \
      && "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_manifest" \
      && "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_execution" \
      && "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$promotion_base_sha" ]] || {
      echo "Promotion QA event does not bind its exact completion evidence: $relative_promotion_event" >&2
      exit 1
    }
    [[ "$promotion_evidence_url" != 'none' ]] || {
      echo "Promotion QA event requires durable URL evidence: $relative_promotion_event" >&2
      exit 1
    }
    gauntlet_validate_evidence_url "$promotion_evidence_url" 'Promotion QA evidence URL'
    gauntlet_validate_same_pr_comment_url "$promotion_evidence_url" "$promotion_pr_url" 'Promotion QA evidence'
    if grep -Fqx -- "$promotion_evidence_url" "$qa_comment_evidence_seen"; then
      echo "QA comment evidence was reused across immutable verdict events: $promotion_evidence_url" >&2
      exit 1
    fi
    printf '%s\n' "$promotion_evidence_url" >> "$qa_comment_evidence_seen"
    completion_recorded_at="$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Recorded at')"
    gauntlet_assert_live_pr_comment \
      "$promotion_evidence_url" \
      "$promotion_pr_url" \
      "$(gauntlet_github_repo_from_url "$issue_url")" \
      "$promotion_verdict" \
      "$promotion_head_sha" \
      "$promotion_completion" \
      "$completion_recorded_at" \
      "$promotion_affected" \
      replay
    gauntlet_validate_replay_timestamp "$promotion_recorded_at" "Promotion QA Recorded at ($relative_promotion_event)"
    gauntlet_validate_replay_timestamp "$promotion_created_at" "Promotion PR Created at ($relative_promotion_event)"
    [[ "$promotion_observed_state" == 'OPEN' && "$promotion_draft" == 'false' \
      && "$promotion_closed_at" == 'none' && "$promotion_merged_at" == 'none' \
      && ( "$promotion_created_at" < "$promotion_qa_created_at" || "$promotion_created_at" == "$promotion_qa_created_at" ) ]] || {
      echo "Promotion QA event lacks canonical live open-PR creation evidence: $relative_promotion_event" >&2
      exit 1
    }
    if [[ "$phase" == 'ready' || "$phase" == 'complete' ]]; then
      # A promotion PR remains the same public review surface while remediation
      # advances its source branch. Historical QA events therefore bind their
      # original heads through immutable comments and require the current live
      # head to be their fast-forward descendant. Only the latest event is an
      # exact snapshot of mutable live PR state.
      gauntlet_observe_github_pr \
        "$promotion_pr_url" "$(gauntlet_github_repo_from_url "$issue_url")"
      gauntlet_assert_promotion_issue_link "$GAUNTLET_GH_BODY" "$issue_url"
      gauntlet_validate_head_sha "$GAUNTLET_GH_HEAD_SHA" 'Live promotion PR Head SHA'
      [[ "$GAUNTLET_GH_HEAD_SHA" == "$promotion_live_chain_tip" ]] || {
        echo "Live promotion PR head contains unrecorded work beyond the reconstructed integration chain: $GAUNTLET_GH_HEAD_SHA" >&2
        exit 1
      }
      gauntlet_validate_head_sha "$GAUNTLET_GH_BASE_SHA" 'Live promotion PR Target base SHA'
      gauntlet_assert_commit_ancestor \
        "$base_commit_sha" "$GAUNTLET_GH_BASE_SHA" \
        "Live promotion PR target-base lineage ($relative_promotion_event)"
      gauntlet_assert_commit_ancestor \
        "$promotion_head_sha" "$GAUNTLET_GH_HEAD_SHA" \
        "Promotion PR no-force history ($relative_promotion_event)"
      [[ "$GAUNTLET_GH_URL" == "$promotion_pr_url" \
        && "$GAUNTLET_GH_HEAD_BRANCH" == "$promotion_source" \
        && "$GAUNTLET_GH_BASE_BRANCH" == "$promotion_target" \
        && "$GAUNTLET_GH_IS_CROSS_REPOSITORY" == "$promotion_cross_repository" \
        && "$GAUNTLET_GH_HEAD_REPOSITORY" == "$promotion_head_repository" \
        && "$GAUNTLET_GH_CREATED_AT" == "$promotion_created_at" \
        && "$GAUNTLET_GH_STATE" == 'OPEN' \
        && "$GAUNTLET_GH_IS_DRAFT" == 'false' \
        && "$GAUNTLET_GH_CLOSED_AT" == 'none' \
        && "$GAUNTLET_GH_MERGED_AT" == 'none' \
        && "$GAUNTLET_GH_MERGED_BY" == 'none' \
        && "$GAUNTLET_GH_MERGED_BY_TYPE" == 'none' \
        && "$GAUNTLET_GH_MERGED_BY_BOT" == 'none' \
        && "$GAUNTLET_GH_MERGE_COMMIT" == 'none' ]] || {
        echo "Live promotion PR identity differs from immutable QA history: $relative_promotion_event" >&2
        exit 1
      }
      # A failed promotion event resets Integration Review before remediation.
      # Until the replacement integration head receives its own QA event, the
      # newest persisted promotion event is historical too. Exact mutable-state
      # replay applies once the latest event represents the currently reviewed
      # integration head; every older generation remains ancestry-anchored.
      if [[ "$promotion_event_file" == "$latest_promotion_event_file" \
        && "$promotion_head_sha" == "$current_integration_review_head" ]]; then
        [[ "$GAUNTLET_GH_HEAD_SHA" == "$promotion_head_sha" \
          && "$GAUNTLET_GH_BASE_SHA" == "$promotion_target_base_sha" \
          && "$GAUNTLET_GH_STATE" == "$promotion_observed_state" \
          && "$GAUNTLET_GH_IS_DRAFT" == "$promotion_draft" \
          && "$GAUNTLET_GH_CLOSED_AT" == "$promotion_closed_at" \
          && "$GAUNTLET_GH_MERGED_AT" == "$promotion_merged_at" ]] || {
          echo "Latest live promotion PR replay differs from immutable QA evidence: $relative_promotion_event" >&2
          exit 1
        }
      fi
    fi
    [[ "$promotion_qa_author" == "$GAUNTLET_COMMENT_AUTHOR" \
      && "$promotion_qa_comment_id" == "$GAUNTLET_COMMENT_ID" \
      && "$promotion_qa_author_type" == "$GAUNTLET_COMMENT_AUTHOR_TYPE" \
      && "$promotion_qa_author_association" == "$GAUNTLET_COMMENT_AUTHOR_ASSOCIATION" \
      && "$promotion_qa_created_at" == "$GAUNTLET_COMMENT_CREATED_AT" \
      && "$promotion_qa_updated_at" == "$GAUNTLET_COMMENT_UPDATED_AT" \
      && "$promotion_qa_body_hash" == "$GAUNTLET_COMMENT_BODY_SHA256" \
      && ( "$completion_recorded_at" < "$promotion_qa_created_at" \
        || "$completion_recorded_at" == "$promotion_qa_created_at" ) \
      && ( "$promotion_qa_created_at" < "$promotion_recorded_at" \
        || "$promotion_qa_created_at" == "$promotion_recorded_at" ) ]] || {
      echo "Promotion semantic QA comment metadata is stale or postdates its event: $relative_promotion_event" >&2
      exit 1
    }
    [[ "$completion_recorded_at" < "$promotion_recorded_at" || "$completion_recorded_at" == "$promotion_recorded_at" ]] || {
      echo "Promotion QA event predates its completion evidence: $relative_promotion_event" >&2
      exit 1
    }
    if [[ -z "$promotion_series_pr_url" ]]; then
      promotion_series_pr_url="$promotion_pr_url"
      promotion_series_created_at="$promotion_created_at"
    else
      [[ "$promotion_pr_url" == "$promotion_series_pr_url" \
        && "$promotion_created_at" == "$promotion_series_created_at" ]] || {
        echo 'Promotion remediation must continue on the same PR URL and immutable creation time.' >&2
        exit 1
      }
      gauntlet_assert_commit_ancestor \
        "$previous_promotion_head_sha" "$promotion_head_sha" \
        "Ordered promotion-event head lineage ($relative_promotion_event)"
      gauntlet_assert_commit_ancestor \
        "$previous_promotion_target_base_sha" "$promotion_target_base_sha" \
        "Ordered promotion-event target-base lineage ($relative_promotion_event)"
      [[ "$previous_promotion_recorded_at" < "$promotion_recorded_at" \
        || "$previous_promotion_recorded_at" == "$promotion_recorded_at" ]] || {
        echo "Promotion QA event timestamps are out of sequence: $relative_promotion_event" >&2
        exit 1
      }
      [[ "$previous_promotion_qa_created_at" < "$promotion_qa_created_at" \
        || ( "$previous_promotion_qa_created_at" == "$promotion_qa_created_at" \
          && "$previous_promotion_qa_comment_id" -lt "$promotion_qa_comment_id" ) ]] || {
        echo "Promotion QA comments do not form a strict chronological sequence: $relative_promotion_event" >&2
        exit 1
      }
    fi
    while IFS=$'\t' read -r prior_state_completion prior_state_verdict prior_state_pr prior_state_head prior_state_evidence prior_state_created prior_state_comment_id prior_state_target_base prior_state_pr_created; do
      [[ -n "$prior_state_completion" ]] || continue
      if [[ "$prior_state_verdict" == 'fail' && "$prior_state_head" == "$promotion_head_sha" \
        && "$prior_state_completion" != "$promotion_completion" ]]; then
        echo "Promotion-QA recovery reused a failed reviewed head without a new head: $promotion_head_sha" >&2
        exit 1
      fi
    done < "$promotion_completion_states"
    prior_completion_state="$(awk -F '\t' -v completion="$promotion_completion" '$1 == completion { print }' "$promotion_completion_states")"
    prior_completion_state_count="$(printf '%s\n' "$prior_completion_state" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    case "$prior_completion_state_count" in
      0) ;;
      1)
        IFS=$'\t' read -r _ prior_state_verdict prior_state_pr prior_state_head prior_state_evidence prior_state_created prior_state_comment_id prior_state_target_base prior_state_pr_created <<< "$prior_completion_state"
        [[ "$prior_state_verdict" == 'pass' && "$promotion_verdict" == 'fail' \
          && "${prior_state_pr%/}" == "$promotion_pr_url" \
          && "$prior_state_head" == "$promotion_head_sha" \
          && "$prior_state_target_base" == "$promotion_target_base_sha" \
          && "$prior_state_pr_created" == "$promotion_created_at" \
          && "$prior_state_evidence" != "$promotion_evidence_url" \
          && ( "$prior_state_created" < "$promotion_qa_created_at" \
            || ( "$prior_state_created" == "$promotion_qa_created_at" \
              && "$prior_state_comment_id" -lt "$promotion_qa_comment_id" ) ) ]] || {
          echo "Invalid Promotion QA transition for completion event: $promotion_completion" >&2
          exit 1
        }
        ;;
      *)
        echo "Promotion completion event has more than its permitted pass-to-fail transition: $promotion_completion" >&2
        exit 1
        ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$promotion_completion" "$promotion_verdict" "$promotion_pr_url" "$promotion_head_sha" \
      "$promotion_evidence_url" "$promotion_qa_created_at" "$promotion_qa_comment_id" \
      "$promotion_target_base_sha" "$promotion_created_at" >> "$promotion_completion_states"

    promotion_integration_relative="$(gauntlet_section_field \
      "$promotion_completion_file" 'Completion Event Metadata' 'Integration round')"
    [[ "$promotion_integration_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/integration/round-[0-9]{3,}\.md$ ]] || {
      echo "Promotion QA completion references invalid integration evidence: $relative_promotion_event" >&2
      exit 1
    }
    promotion_integration_round="$OPENCAW_PROJECT_ROOT_RESOLVED/$promotion_integration_relative"
    gauntlet_assert_safe_ai_path "$promotion_integration_round" \
      'Promotion integration-round evidence'
    [[ -f "$promotion_integration_round" && ! -L "$promotion_integration_round" \
      && "$(gauntlet_section_field "$promotion_integration_round" 'Round Metadata' 'Verdict')" == 'pass' \
      && "$(gauntlet_section_field "$promotion_integration_round" 'Round Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" == "$promotion_head_sha" \
      && "$(gauntlet_section_field "$promotion_integration_round" 'Round Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_scope" \
      && "$(gauntlet_section_field "$promotion_integration_round" 'Round Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_quality_bar" \
      && "$(gauntlet_section_field "$promotion_integration_round" 'Round Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_manifest" \
      && "$(gauntlet_section_field "$promotion_integration_round" 'Round Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" == "$promotion_execution" \
      && "$(gauntlet_section_field "$promotion_integration_round" 'Round Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$promotion_base_sha" ]] || {
      echo "Promotion QA event does not bind its completion's exact passing integration round: $relative_promotion_event" >&2
      exit 1
    }
    integration_round_recorded_at="$(gauntlet_section_field \
      "$promotion_integration_round" 'Round Metadata' 'Recorded at')"
    [[ "$integration_round_recorded_at" < "$promotion_recorded_at" \
      || "$integration_round_recorded_at" == "$promotion_recorded_at" ]] || {
      echo "Promotion QA event predates its integration review: $relative_promotion_event" >&2
      exit 1
    }

    : > "$promotion_affected_values"
    if [[ "$promotion_verdict" == 'pass' ]]; then
      [[ "$promotion_affected" == 'none' \
        && "$promotion_archived_report" == 'none' \
        && "$promotion_archived_hash" == 'none' ]] || {
        echo "Passing Promotion QA event cannot reopen units or archive a failure report: $relative_promotion_event" >&2
        exit 1
      }
    else
      [[ "$promotion_affected" != 'none' ]] || {
        echo "Failing Promotion QA event must identify affected retained units: $relative_promotion_event" >&2
        exit 1
      }
      IFS=',' read -r -a promotion_affected_ids <<< "$promotion_affected"
      [[ ${#promotion_affected_ids[@]} -gt 0 ]] || {
        echo "Failing Promotion QA event has no affected units: $relative_promotion_event" >&2
        exit 1
      }
      for affected_item in "${promotion_affected_ids[@]}"; do
        gauntlet_validate_name "$affected_item" 'Promotion QA affected unit'
        grep -Fqx -- "$affected_item" "$seen_units" || {
          echo "Promotion QA event references an unretained work unit: $affected_item" >&2
          exit 1
        }
        printf '%s\n' "$affected_item" >> "$promotion_affected_values"
      done
      canonical_affected="$(LC_ALL=C sort -u "$promotion_affected_values" | paste -sd, -)"
      [[ "$promotion_affected" == "$canonical_affected" \
        && "$(wc -l < "$promotion_affected_values" | tr -d '[:space:]')" -eq "$(LC_ALL=C sort -u "$promotion_affected_values" | wc -l | tr -d '[:space:]')" ]] || {
        echo "Promotion QA affected units must be unique and comma-sorted: $relative_promotion_event" >&2
        exit 1
      }
      expected_archived_report=".ai/gauntlets/$gauntlet_name/promotion-events/GAUNTLET_REPORT-before-event-$expected_promotion_label.md"
      [[ "$promotion_archived_report" == "$expected_archived_report" \
        && "$promotion_archived_hash" =~ ^[0-9a-f]{64}$ ]] || {
        echo "Failing Promotion QA event has noncanonical archived-report metadata: $relative_promotion_event" >&2
        exit 1
      }
      if grep -Fqx -- "$promotion_archived_report" "$promotion_archive_paths"; then
        echo "Promotion QA archived report path is duplicated: $promotion_archived_report" >&2
        exit 1
      fi
      printf '%s\n' "$promotion_archived_report" >> "$promotion_archive_paths"
      promotion_archive_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$promotion_archived_report"
      [[ -f "$promotion_archive_file" && ! -L "$promotion_archive_file" \
        && "$promotion_archived_hash" == "$(gauntlet_hash_file "$promotion_archive_file")" \
        && "$(gauntlet_report_projection_hash "$promotion_archive_file")" == \
          "$(gauntlet_section_field "$promotion_completion_file" 'Completion Event Metadata' 'Report projection sha256' | tr '[:upper:]' '[:lower:]')" ]] || {
        echo "Promotion QA archived report is missing, unsafe, or stale: $promotion_archived_report" >&2
        exit 1
      }
      promotion_archive_count=$((promotion_archive_count + 1))
    fi

    latest_promotion_verdict="$promotion_verdict"
    latest_promotion_head_sha="$promotion_head_sha"
    latest_promotion_scope="$promotion_scope"
    latest_promotion_quality_bar="$promotion_quality_bar"
    latest_promotion_execution="$promotion_execution"
    latest_promotion_base_sha="$promotion_base_sha"
    latest_promotion_completion="$promotion_completion"
    latest_promotion_recorded_at="$promotion_recorded_at"
    previous_promotion_head_sha="$promotion_head_sha"
    previous_promotion_target_base_sha="$promotion_target_base_sha"
    previous_promotion_qa_created_at="$promotion_qa_created_at"
    previous_promotion_qa_comment_id="$promotion_qa_comment_id"
    previous_promotion_recorded_at="$promotion_recorded_at"
    expected_promotion_number=$((expected_promotion_number + 1))
  done < <(find "$promotion_event_dir" -maxdepth 1 -type f -name 'event-*.md' -print \
    | awk '{ name=$0; sub(/^.*\/event-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
    | LC_ALL=C sort -n -k1,1)

  actual_promotion_archive_count="$(find "$promotion_event_dir" -maxdepth 1 -type f -name 'GAUNTLET_REPORT-before-event-*.md' -print | wc -l | tr -d '[:space:]')"
  [[ "$actual_promotion_archive_count" -eq "$promotion_archive_count" ]] || {
    echo "Promotion QA archive count ($actual_promotion_archive_count) does not match failing event evidence ($promotion_archive_count)." >&2
    exit 1
  }
fi

promotion_ledger_count=0
promotion_placeholder_count=0
promotion_ledger_pattern='^- event: ([0-9]{3,}) \| verdict: (pass|fail) \| pr: ([^|[:space:]]+) \| head-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| source: ([^|[:space:]]+) \| target: ([^|[:space:]]+) \| target-base-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| pr-created: ([^|[:space:]]+) \| pr-closed: ([^|[:space:]]+) \| scope: ([0-9a-f]{64}) \| manifest: ([0-9a-f]{64}) \| contract: ([0-9a-f]{64}) \| base-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| completion: ([^|[:space:]]+) \| affected-units: ([^|[:space:]]+) \| evidence: ([^|[:space:]]+) \| qa-comment-id: ([1-9][0-9]*) \| qa-author: ([^|[:space:]]+) \| qa-created: ([^|[:space:]]+) \| archived-report: ([^|[:space:]]+) \| record: ([^|[:space:]]+) \| sha256: ([0-9a-f]{64})$'
while IFS= read -r promotion_ledger_line; do
  [[ "$promotion_ledger_line" =~ ^[[:space:]]*$ ]] && continue
  if [[ "$promotion_ledger_line" == '- No promotion QA events recorded.' ]]; then
    promotion_placeholder_count=$((promotion_placeholder_count + 1))
    continue
  fi
  if [[ ! "$promotion_ledger_line" =~ $promotion_ledger_pattern ]]; then
    echo "Invalid or noncanonical Promotion QA Ledger content: $promotion_ledger_line" >&2
    exit 1
  fi
  promotion_ledger_sequence="${BASH_REMATCH[1]}"
  promotion_ledger_verdict="${BASH_REMATCH[2]}"
  promotion_ledger_pr="${BASH_REMATCH[3]}"
  promotion_ledger_head_sha="${BASH_REMATCH[4]}"
  promotion_ledger_source="${BASH_REMATCH[5]}"
  promotion_ledger_target="${BASH_REMATCH[6]}"
  promotion_ledger_target_base_sha="${BASH_REMATCH[7]}"
  promotion_ledger_created_at="${BASH_REMATCH[8]}"
  promotion_ledger_closed_at="${BASH_REMATCH[9]}"
  promotion_ledger_scope="${BASH_REMATCH[10]}"
  promotion_ledger_manifest="${BASH_REMATCH[11]}"
  promotion_ledger_execution="${BASH_REMATCH[12]}"
  promotion_ledger_base_sha="${BASH_REMATCH[13]}"
  promotion_ledger_completion="${BASH_REMATCH[14]}"
  promotion_ledger_affected="${BASH_REMATCH[15]}"
  promotion_ledger_evidence="${BASH_REMATCH[16]}"
  promotion_ledger_qa_comment_id="${BASH_REMATCH[17]}"
  promotion_ledger_qa_author="${BASH_REMATCH[18]}"
  promotion_ledger_qa_created="${BASH_REMATCH[19]}"
  promotion_ledger_archive="${BASH_REMATCH[20]}"
  promotion_ledger_record="${BASH_REMATCH[21]}"
  promotion_ledger_hash="${BASH_REMATCH[22]}"
  promotion_ledger_count=$((promotion_ledger_count + 1))

  expected_promotion_record=".ai/gauntlets/$gauntlet_name/promotion-events/event-$promotion_ledger_sequence.md"
  [[ "$promotion_ledger_record" == "$expected_promotion_record" ]] || {
    echo "Promotion QA Ledger path does not match its event: $promotion_ledger_record" >&2
    exit 1
  }
  if grep -Fqx -- "$promotion_ledger_record" "$promotion_ledger_paths"; then
    echo "Promotion QA Ledger evidence path is duplicated: $promotion_ledger_record" >&2
    exit 1
  fi
  printf '%s\n' "$promotion_ledger_record" >> "$promotion_ledger_paths"
  promotion_ledger_event_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$promotion_ledger_record"
  [[ -f "$promotion_ledger_event_file" && ! -L "$promotion_ledger_event_file" ]] || {
    echo "Promotion QA Ledger references missing or unsafe evidence: $promotion_ledger_record" >&2
    exit 1
  }
  event_promotion_pr="$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Promotion PR URL')"
  event_promotion_pr="${event_promotion_pr%/}"
  [[ "$promotion_ledger_sequence" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Sequence')" \
    && "$promotion_ledger_verdict" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Verdict')" \
    && "$promotion_ledger_pr" == "$event_promotion_pr" \
    && "$promotion_ledger_head_sha" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$promotion_ledger_source" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Source branch')" \
    && "$promotion_ledger_target" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Target branch')" \
    && "$promotion_ledger_target_base_sha" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Target base SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$promotion_ledger_created_at" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Created at')" \
    && "$promotion_ledger_closed_at" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Closed at')" \
    && "$promotion_ledger_scope" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$promotion_ledger_manifest" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$promotion_ledger_execution" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$promotion_ledger_base_sha" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$promotion_ledger_completion" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Completion event')" \
    && "$promotion_ledger_affected" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Affected units')" \
    && "$promotion_ledger_evidence" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Evidence URL')" \
    && "$promotion_ledger_qa_comment_id" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'QA comment ID')" \
    && "$promotion_ledger_qa_author" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'QA comment author')" \
    && "$promotion_ledger_qa_created" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'QA comment created at')" \
    && "$promotion_ledger_archive" == "$(gauntlet_section_field "$promotion_ledger_event_file" 'Promotion QA Event Metadata' 'Archived report')" ]] || {
    echo "Promotion QA Ledger fields do not match their exact evidence file: $promotion_ledger_record" >&2
    exit 1
  }
  [[ "$promotion_ledger_hash" == "$(gauntlet_hash_file "$promotion_ledger_event_file")" ]] || {
    echo "Promotion QA Ledger hash is stale for its exact evidence file: $promotion_ledger_record" >&2
    exit 1
  }
done < <(gauntlet_extract_section "$gauntlet_file" 'Promotion QA Ledger')
if [[ $promotion_event_count -eq 0 ]]; then
  [[ $promotion_ledger_count -eq 0 && $promotion_placeholder_count -eq 1 ]] || {
    echo 'An empty Promotion QA Ledger requires exactly one canonical placeholder.' >&2
    exit 1
  }
else
  [[ "$base_branch" != 'pending' ]] || {
    echo 'Promotion QA evidence cannot target a pending delivery base.' >&2
    exit 1
  }
  [[ $promotion_placeholder_count -eq 0 && $promotion_ledger_count -eq $promotion_event_count ]] || {
    echo "Promotion QA Ledger count ($promotion_ledger_count) does not match immutable event evidence count ($promotion_event_count)." >&2
    exit 1
  }
  delivery_promotion_pr="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Promotion PR URL')"
  delivery_promotion_pr="${delivery_promotion_pr%/}"
  [[ -n "$delivery_promotion_pr" ]] || {
    echo 'Promotion QA evidence requires Delivery / Promotion PR URL.' >&2
    exit 1
  }
  while IFS= read -r promotion_event_file; do
    event_promotion_pr="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Promotion PR URL')"
    [[ "${event_promotion_pr%/}" == "$delivery_promotion_pr" ]] || {
      echo 'Every Promotion QA event must belong to the recorded promotion PR.' >&2
      exit 1
    }
  done < <(find "$promotion_event_dir" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
fi

completion_event_count=0
completion_ledger_count=0
completion_placeholder_count=0
completion_ledger_paths="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-completion-ledger-paths.XXXXXX")"
completion_consumed_paths="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-completion-consumed.XXXXXX")"
completion_event_dir="$gauntlet_dir/completion-events"
active_completion_event=''
active_completion_relative=''
[[ ! -L "$completion_event_dir" ]] || {
  echo "Gauntlet completion events directory must not be a symbolic link: $completion_event_dir" >&2
  exit 1
}
if [[ -d "$completion_event_dir" ]]; then
  gauntlet_assert_safe_ai_path "$completion_event_dir" 'Gauntlet completion events directory'
  linked_completion_path="$(find "$completion_event_dir" -type l -print -quit)"
  [[ -z "$linked_completion_path" ]] || {
    echo "Gauntlet completion history must not contain symbolic links: $linked_completion_path" >&2
    exit 1
  }
  expected_completion_number=1
  while IFS=$'\t' read -r numeric_value completion_event_file; do
    [[ -n "$completion_event_file" ]] || continue
    completion_event_count=$((completion_event_count + 1))
    printf -v expected_completion_label '%03d' "$expected_completion_number"
    actual_completion_label="$(basename "$completion_event_file")"
    actual_completion_label="${actual_completion_label#event-}"
    actual_completion_label="${actual_completion_label%.md}"
    [[ "$numeric_value" -eq "$expected_completion_number" \
      && "$actual_completion_label" == "$expected_completion_label" ]] || {
      echo "Completion event sequence must be contiguous; expected event-$expected_completion_label.md." >&2
      exit 1
    }
    relative_completion_event="${completion_event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    [[ "$(gauntlet_heading_count "$completion_event_file" 'Completion Event Metadata')" -eq 1 ]] || {
      echo "Completion event requires exactly one metadata heading: $relative_completion_event" >&2
      exit 1
    }
    for completion_metadata_key in 'Sequence' 'Outcome' 'Integration round' 'Head SHA' \
      'Scope fingerprint' 'Unit manifest fingerprint' 'Quality bar fingerprint' 'Execution contract fingerprint' \
      'Base commit SHA' 'Report' 'Report projection sha256' 'Recorded at'; do
      [[ "$(gauntlet_section_field_count "$completion_event_file" 'Completion Event Metadata' "$completion_metadata_key")" -eq 1 ]] || {
        echo "Completion event requires exactly one '$completion_metadata_key' field: $relative_completion_event" >&2
        exit 1
      }
    done
    completion_sequence="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Sequence')"
    completion_outcome="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Outcome')"
    completion_integration_round="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Integration round')"
    completion_head_sha="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
    completion_scope="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')"
    completion_manifest="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')"
    completion_quality="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')"
    completion_execution="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')"
    completion_base_sha="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')"
    completion_report="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Report')"
    completion_report_projection="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Report projection sha256' | tr '[:upper:]' '[:lower:]')"
    completion_recorded_at="$(gauntlet_section_field "$completion_event_file" 'Completion Event Metadata' 'Recorded at')"
    [[ "$completion_sequence" == "$expected_completion_label" && "$completion_outcome" == 'complete' ]] || {
      echo "Completion event sequence or outcome is noncanonical: $relative_completion_event" >&2
      exit 1
    }
    expected_completion_report=".ai/gauntlets/$gauntlet_name/GAUNTLET_REPORT.md"
    [[ "$completion_report" == "$expected_completion_report" \
      && "$completion_integration_round" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/integration/round-[0-9]{3,}\.md$ ]] || {
      echo "Completion event has a noncanonical report or integration-round path: $relative_completion_event" >&2
      exit 1
    }
    completion_round_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$completion_integration_round"
    [[ -f "$completion_round_file" && ! -L "$completion_round_file" \
      && "$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Verdict')" == 'pass' \
      && "$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" == "$completion_head_sha" \
      && "$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" == "$completion_scope" \
      && "$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" == "$completion_manifest" \
      && "$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" == "$completion_quality" \
      && "$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" == "$completion_execution" \
      && "$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$completion_base_sha" ]] || {
      echo "Completion event does not bind one passing integration round: $relative_completion_event" >&2
      exit 1
    }
    [[ "$completion_execution" == "$current_execution_fingerprint" \
      && "$completion_base_sha" == "${base_commit_sha,,}" \
      && "$completion_report_projection" =~ ^[0-9a-f]{64}$ ]] || {
      echo "Completion event has a stale execution contract or approved base: $relative_completion_event" >&2
      exit 1
    }
    gauntlet_validate_replay_timestamp "$completion_recorded_at" "Completion Recorded at ($relative_completion_event)"
    round_recorded_at="$(gauntlet_section_field "$completion_round_file" 'Round Metadata' 'Recorded at')"
    [[ "$round_recorded_at" < "$completion_recorded_at" || "$round_recorded_at" == "$completion_recorded_at" ]] || {
      echo "Completion event predates its integration round: $relative_completion_event" >&2
      exit 1
    }
    active_completion_event="$completion_event_file"
    active_completion_relative="$relative_completion_event"
    expected_completion_number=$((expected_completion_number + 1))
  done < <(find "$completion_event_dir" -maxdepth 1 -type f -name 'event-*.md' -print \
    | awk '{ name=$0; sub(/^.*\/event-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
    | LC_ALL=C sort -n -k1,1)
fi

completion_ledger_pattern='^- event: ([0-9]{3,}) \| outcome: (complete) \| integration-round: ([^|[:space:]]+) \| head-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| scope: ([0-9a-f]{64}) \| manifest: ([0-9a-f]{64}) \| contract: ([0-9a-f]{64}) \| base-sha: ([0-9a-f]{40}|[0-9a-f]{64}) \| quality: ([0-9a-f]{64}) \| report: ([^|[:space:]]+) \| report-projection: ([0-9a-f]{64}) \| record: ([^|[:space:]]+) \| sha256: ([0-9a-f]{64})$'
while IFS= read -r completion_ledger_line; do
  [[ "$completion_ledger_line" =~ ^[[:space:]]*$ ]] && continue
  if [[ "$completion_ledger_line" == '- No completion events recorded.' ]]; then
    completion_placeholder_count=$((completion_placeholder_count + 1))
    continue
  fi
  [[ "$completion_ledger_line" =~ $completion_ledger_pattern ]] || {
    echo "Invalid or noncanonical Completion Ledger content: $completion_ledger_line" >&2
    exit 1
  }
  completion_ledger_sequence="${BASH_REMATCH[1]}"
  completion_ledger_outcome="${BASH_REMATCH[2]}"
  completion_ledger_round="${BASH_REMATCH[3]}"
  completion_ledger_head="${BASH_REMATCH[4]}"
  completion_ledger_scope="${BASH_REMATCH[5]}"
  completion_ledger_manifest="${BASH_REMATCH[6]}"
  completion_ledger_execution="${BASH_REMATCH[7]}"
  completion_ledger_base="${BASH_REMATCH[8]}"
  completion_ledger_quality="${BASH_REMATCH[9]}"
  completion_ledger_report="${BASH_REMATCH[10]}"
  completion_ledger_report_projection="${BASH_REMATCH[11]}"
  completion_ledger_record="${BASH_REMATCH[12]}"
  completion_ledger_hash="${BASH_REMATCH[13]}"
  completion_ledger_count=$((completion_ledger_count + 1))
  expected_completion_record=".ai/gauntlets/$gauntlet_name/completion-events/event-$completion_ledger_sequence.md"
  [[ "$completion_ledger_record" == "$expected_completion_record" ]] || {
    echo "Completion Ledger path does not match its sequence: $completion_ledger_record" >&2
    exit 1
  }
  if grep -Fqx -- "$completion_ledger_record" "$completion_ledger_paths"; then
    echo "Completion Ledger evidence path is duplicated: $completion_ledger_record" >&2
    exit 1
  fi
  printf '%s\n' "$completion_ledger_record" >> "$completion_ledger_paths"
  completion_ledger_event="$OPENCAW_PROJECT_ROOT_RESOLVED/$completion_ledger_record"
  [[ -f "$completion_ledger_event" && ! -L "$completion_ledger_event" \
    && "$completion_ledger_outcome" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Outcome')" \
    && "$completion_ledger_round" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Integration round')" \
    && "$completion_ledger_head" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$completion_ledger_scope" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$completion_ledger_manifest" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$completion_ledger_execution" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$completion_ledger_base" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" \
    && "$completion_ledger_quality" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" \
    && "$completion_ledger_report" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Report')" \
    && "$completion_ledger_report_projection" == "$(gauntlet_section_field "$completion_ledger_event" 'Completion Event Metadata' 'Report projection sha256' | tr '[:upper:]' '[:lower:]')" \
    && "$completion_ledger_hash" == "$(gauntlet_hash_file "$completion_ledger_event")" ]] || {
    echo "Completion Ledger fields or hash do not match exact evidence: $completion_ledger_record" >&2
    exit 1
  }
done < <(gauntlet_extract_section "$gauntlet_file" 'Completion Ledger')
if [[ $completion_event_count -eq 0 ]]; then
  [[ $completion_ledger_count -eq 0 && $completion_placeholder_count -eq 1 ]] || {
    echo 'An empty Completion Ledger requires exactly one canonical placeholder.' >&2
    exit 1
  }
else
  [[ $completion_placeholder_count -eq 0 && $completion_ledger_count -eq $completion_event_count ]] || {
    echo "Completion Ledger count ($completion_ledger_count) does not match immutable events ($completion_event_count)." >&2
    exit 1
  }
fi

# Only a failing Promotion QA event consumes completion. Passing QA continues
# to attest the same active completion boundary.
if [[ -d "$promotion_event_dir" ]]; then
  while IFS= read -r promotion_event_file; do
    [[ "$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Verdict')" == 'fail' ]] || continue
    consumed_completion="$(gauntlet_section_field "$promotion_event_file" 'Promotion QA Event Metadata' 'Completion event')"
    if grep -Fqx -- "$consumed_completion" "$completion_consumed_paths"; then
      echo "Completion event was consumed by more than one Promotion QA failure: $consumed_completion" >&2
      exit 1
    fi
    printf '%s\n' "$consumed_completion" >> "$completion_consumed_paths"
  done < <(find "$promotion_event_dir" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
fi
if [[ -d "$completion_event_dir" && $completion_event_count -gt 1 ]]; then
  latest_completion_history_file="$(gauntlet_latest_completion_event_file "$completion_event_dir")"
  while IFS= read -r completion_history_file; do
    [[ -n "$completion_history_file" ]] || continue
    [[ "$completion_history_file" == "$latest_completion_history_file" ]] && continue
    completion_history_relative="${completion_history_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    grep -Fqx -- "$completion_history_relative" "$completion_consumed_paths" || {
      echo "Every non-latest completion event must be consumed exactly once by a later failing Promotion QA event: $completion_history_relative" >&2
      exit 1
    }
  done < <(find "$completion_event_dir" -maxdepth 1 -type f -name 'event-*.md' -print | LC_ALL=C sort)
fi
if [[ -n "$active_completion_relative" ]] && grep -Fqx -- "$active_completion_relative" "$completion_consumed_paths"; then
  active_completion_event=''
  active_completion_relative=''
fi

if [[ -n "$active_completion_event" ]]; then
  active_round="$(gauntlet_section_field "$active_completion_event" 'Completion Event Metadata' 'Integration round')"
  active_head="$(gauntlet_section_field "$active_completion_event" 'Completion Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
  active_scope="$(gauntlet_section_field "$active_completion_event" 'Completion Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')"
  active_manifest="$(gauntlet_section_field "$active_completion_event" 'Completion Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')"
  active_quality="$(gauntlet_section_field "$active_completion_event" 'Completion Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')"
  active_report="$(gauntlet_section_field "$active_completion_event" 'Completion Event Metadata' 'Report')"
  active_report_projection="$(gauntlet_section_field "$active_completion_event" 'Completion Event Metadata' 'Report projection sha256' | tr '[:upper:]' '[:lower:]')"
  integration_evidence="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')"
  integration_evidence="${integration_evidence#\`}"
  integration_evidence="${integration_evidence%\`}"
  [[ "$status" == 'passed' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'PR eligible')" == 'yes' \
    && "$active_manifest" == "$current_manifest_fingerprint" \
    && "$active_quality" == "${quality_fingerprint,,}" \
    && "$integration_evidence" == "$active_round" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA' | tr '[:upper:]' '[:lower:]')" == "$active_head" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" == "$active_scope" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" == "$active_manifest" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" == "$active_quality" ]] || {
    echo 'Active completion evidence requires unchanged passed and PR-eligible integration state.' >&2
    exit 1
  }
  active_report_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$active_report"
  [[ -f "$active_report_file" && ! -L "$active_report_file" \
    && "$(gauntlet_heading_count "$active_report_file" 'Immutable Completion Evidence')" -eq 1 \
    && "$(gauntlet_extract_section "$active_report_file" 'Immutable Completion Evidence')" == "$(gauntlet_extract_section "$gauntlet_file" 'Completion Ledger')" \
    && "$(gauntlet_report_projection_hash "$active_report_file")" == "$active_report_projection" ]] || {
    echo 'Active completion report is missing or stale against the Completion Ledger.' >&2
    exit 1
  }
  for active_report_line in '- Completion outcome: complete' '- Gauntlet status: passed' '- PR eligible: yes' \
    "- Unit manifest fingerprint: $current_manifest_fingerprint" \
    "- Execution contract fingerprint: $current_execution_fingerprint" "- Base commit SHA: $base_commit_sha"; do
    grep -Fqx -- "$active_report_line" "$active_report_file" || {
      echo "Active completion report lacks current outcome evidence: $active_report_line" >&2
      exit 1
    }
  done
elif [[ "$status" == 'passed' ]]; then
  echo 'A passed Gauntlet requires an active unconsumed immutable completion event.' >&2
  exit 1
fi

immutable_evidence_count=$((round_count + pr_event_count + promotion_event_count + completion_event_count))

# Replay the approved unit-manifest and quality-bar generations as chronological
# chains. Immutable evidence remains valid against the generation active when
# it was recorded; only the active, unconsumed completion must match the current
# generation.
evidence_timeline="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-evidence-timeline.XXXXXX")"
approved_manifest_rows="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-approved-manifests.XXXXXX")"
approved_quality_rows="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-approved-quality.XXXXXX")"
manifest_revision_ids="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-manifest-revision-ids.XXXXXX")"
quality_revision_ids="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-quality-revision-ids.XXXXXX")"
: > "$evidence_timeline"
: > "$approved_manifest_rows"
: > "$approved_quality_rows"
: > "$manifest_revision_ids"
: > "$quality_revision_ids"
trap 'rm -f "$seen_units" "$critics_seen" "$builders_seen" "$historical_bars" "$historical_manifests" "$round_ledger_paths" "$pr_urls_seen" "$qa_rounds_seen" "$qa_comment_evidence_seen" "$pr_ledger_paths" "$remediation_trigger_records" "$remediation_triggers_seen" "$publication_checkpoints_seen" "$promotion_ledger_paths" "$promotion_archive_paths" "$promotion_completion_states" "$promotion_affected_values" "$completion_ledger_paths" "$completion_consumed_paths" "$evidence_timeline" "$approved_manifest_rows" "$approved_quality_rows" "$manifest_revision_ids" "$quality_revision_ids"' EXIT
while IFS= read -r timeline_file; do
  [[ -n "$timeline_file" ]] || continue
  case "$timeline_file" in
    "$gauntlet_dir"/rounds/*) timeline_heading='Round Metadata' ;;
    "$gauntlet_dir"/pr-events/*) timeline_heading='PR Event Metadata' ;;
    "$gauntlet_dir"/promotion-events/event-*.md) timeline_heading='Promotion QA Event Metadata' ;;
    "$gauntlet_dir"/completion-events/event-*.md) timeline_heading='Completion Event Metadata' ;;
    *) continue ;;
  esac
  timeline_recorded_at="$(gauntlet_section_field "$timeline_file" "$timeline_heading" 'Recorded at')"
  timeline_manifest="$(gauntlet_section_field "$timeline_file" "$timeline_heading" 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')"
  timeline_quality="$(gauntlet_section_field "$timeline_file" "$timeline_heading" 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')"
  [[ "$timeline_recorded_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ \
    && "$timeline_manifest" =~ ^[0-9a-f]{64}$ \
    && "$timeline_quality" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Immutable evidence lacks canonical generation metadata: ${timeline_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}" >&2
    exit 1
  }
  printf '%s\t%s\t%s\t%s\n' "$timeline_recorded_at" "$timeline_manifest" "$timeline_quality" \
    "${timeline_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}" >> "$evidence_timeline"
done < <(find "$gauntlet_dir/rounds" "$gauntlet_dir/pr-events" "$gauntlet_dir/promotion-events" "$gauntlet_dir/completion-events" \
  -type f \( -name 'round-*.md' -o -name 'event-*.md' \) -print 2>/dev/null | LC_ALL=C sort)

first_opened_row=''
if [[ -d "$gauntlet_dir/pr-events" ]]; then
  while IFS= read -r first_opened_candidate; do
    [[ "$(gauntlet_section_field "$first_opened_candidate" 'PR Event Metadata' 'Event')" == 'opened' ]] || continue
    printf '%s\t%s\t%s\t%s\n' \
      "$(gauntlet_section_field "$first_opened_candidate" 'PR Event Metadata' 'Recorded at')" \
      "$(gauntlet_section_field "$first_opened_candidate" 'PR Event Metadata' 'Unit manifest fingerprint' | tr '[:upper:]' '[:lower:]')" \
      "$(gauntlet_section_field "$first_opened_candidate" 'PR Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" \
      "${first_opened_candidate#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
  done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' -print | LC_ALL=C sort) \
    | LC_ALL=C sort -k1,1 -k4,4 > "$evidence_timeline.opened"
  first_opened_row="$(head -n 1 "$evidence_timeline.opened" || true)"
  rm -f "$evidence_timeline.opened"
fi
if [[ "$immutable_evidence_count" -gt 0 ]]; then
  [[ -n "$first_opened_row" ]] || {
    echo 'Immutable Gauntlet evidence requires an accepted opened progress-PR event that froze the initial generations.' >&2
    exit 1
  }
  first_evidence_time="$(LC_ALL=C sort -k1,1 -k4,4 "$evidence_timeline" | head -n 1 | cut -f1)"
  first_opened_time="$(printf '%s\n' "$first_opened_row" | cut -f1)"
  [[ "$first_opened_time" == "$first_evidence_time" ]] || {
    echo 'The first immutable Gauntlet evidence must be an opened progress-PR event.' >&2
    exit 1
  }
fi

unit_history="$(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History')"
manifest_approval_count=0
manifest_revision_count=0
manifest_chain=''
manifest_units=''
manifest_last_approval_time=''
while IFS= read -r history_line; do
  if [[ "$history_line" == '- Unit manifest approval:'* ]]; then
    [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]manifest[[:space:]]approval:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]units:[[:space:]]([a-z0-9,-]+)[[:space:]]\|[[:space:]]approved[[:space:]]by:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || {
      echo "Malformed Unit manifest approval marker: $history_line" >&2
      exit 1
    }
    manifest_approval_count=$((manifest_approval_count + 1))
    [[ "$manifest_approval_count" -eq 1 && "$manifest_revision_count" -eq 0 ]] || {
      echo 'Unit manifest history requires exactly one baseline approval before every revision.' >&2
      exit 1
    }
    manifest_chain="${BASH_REMATCH[1]}"
    manifest_units="${BASH_REMATCH[2]}"
    manifest_approver="$(gauntlet_trim "${BASH_REMATCH[3]}")"
    manifest_last_approval_time="$(gauntlet_trim "${BASH_REMATCH[4]}")"
    [[ "$manifest_units" == "$(printf '%s' "$manifest_units" | tr ',' '\n' | LC_ALL=C sort -u | paste -sd, -)" ]] || {
      echo 'Unit manifest baseline IDs must be unique and comma-sorted.' >&2
      exit 1
    }
    gauntlet_validate_substantive_single_line "$manifest_approver" 'Unit manifest approver'
    gauntlet_validate_replay_timestamp "$manifest_last_approval_time" 'Unit manifest approved at'
    printf '%s\t%s\t%s\t%s\n' "$manifest_last_approval_time" "$manifest_chain" "$manifest_units" "$manifest_approver" >> "$approved_manifest_rows"
  elif [[ "$history_line" == '- Unit manifest revision:'* ]]; then
    [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]manifest[[:space:]]revision:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]from:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]to:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]prior-units:[[:space:]]([a-z0-9,-]+)[[:space:]]\|[[:space:]]current-units:[[:space:]]([a-z0-9,-]+)[[:space:]]\|[[:space:]]reason:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]by:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || {
      echo "Malformed Unit manifest revision marker: $history_line" >&2
      exit 1
    }
    [[ "$manifest_approval_count" -eq 1 ]] || { echo 'Unit manifest revision requires a baseline approval.' >&2; exit 1; }
    manifest_revision_id="${BASH_REMATCH[1]}"
    manifest_revision_from="${BASH_REMATCH[3]}"
    manifest_revision_to="${BASH_REMATCH[4]}"
    manifest_revision_prior="${BASH_REMATCH[5]}"
    manifest_revision_current="${BASH_REMATCH[6]}"
    manifest_revision_reason="$(gauntlet_trim "${BASH_REMATCH[7]}")"
    manifest_revision_approver="$(gauntlet_trim "${BASH_REMATCH[8]}")"
    manifest_revision_time="$(gauntlet_trim "${BASH_REMATCH[9]}")"
    grep -Fqx -- "$manifest_revision_id" "$manifest_revision_ids" && {
      echo "Duplicate Unit manifest revision id: $manifest_revision_id" >&2
      exit 1
    }
    printf '%s\n' "$manifest_revision_id" >> "$manifest_revision_ids"
    [[ "$manifest_revision_from" == "$manifest_chain" \
      && "$manifest_revision_to" != "$manifest_revision_from" \
      && "$manifest_revision_prior" == "$manifest_units" \
      && "$manifest_revision_prior" == "$(printf '%s' "$manifest_revision_prior" | tr ',' '\n' | LC_ALL=C sort -u | paste -sd, -)" \
      && "$manifest_revision_current" == "$(printf '%s' "$manifest_revision_current" | tr ',' '\n' | LC_ALL=C sort -u | paste -sd, -)" ]] || {
      echo "Unit manifest revision does not extend the immediately prior approved generation: $manifest_revision_id" >&2
      exit 1
    }
    IFS=',' read -r -a manifest_prior_ids <<< "$manifest_revision_prior"
    for manifest_prior_id in "${manifest_prior_ids[@]}"; do
      gauntlet_comma_list_contains "$manifest_revision_current" "$manifest_prior_id" || {
        echo "Unit manifest revision silently removes retained unit $manifest_prior_id: $manifest_revision_id" >&2
        exit 1
      }
    done
    gauntlet_validate_substantive_single_line "$manifest_revision_reason" "Unit manifest revision reason ($manifest_revision_id)"
    gauntlet_validate_substantive_single_line "$manifest_revision_approver" "Unit manifest revision approver ($manifest_revision_id)"
    gauntlet_validate_replay_timestamp "$manifest_revision_time" "Unit manifest revision approved at ($manifest_revision_id)"
    [[ "$manifest_last_approval_time" < "$manifest_revision_time" ]] || {
      echo "Unit manifest revision approvals must be strictly chronological; same-time ties are rejected: $manifest_revision_id" >&2
      exit 1
    }
    manifest_chain="$manifest_revision_to"
    manifest_units="$manifest_revision_current"
    manifest_last_approval_time="$manifest_revision_time"
    manifest_revision_count=$((manifest_revision_count + 1))
    printf '%s\t%s\t%s\t%s\n' "$manifest_revision_time" "$manifest_chain" "$manifest_units" "$manifest_revision_approver" >> "$approved_manifest_rows"
  fi
done <<< "$unit_history"

if [[ "$phase" == 'ready' || "$phase" == 'complete' || "$immutable_evidence_count" -gt 0 ]]; then
  [[ "$manifest_approval_count" -eq 1 ]] || {
    echo 'Execution-ready Gauntlets require exactly one canonical Unit manifest approval marker.' >&2
    exit 1
  }
  retained_units_csv="$(gauntlet_unit_ids_csv "$gauntlet_file")"
  [[ "$manifest_chain" == "$unit_manifest_fingerprint" && "$manifest_units" == "$retained_units_csv" ]] || {
    echo 'Approved Unit manifest revision chain does not end at the current retained definitions and supersession topology.' >&2
    exit 1
  }
  if [[ -n "$first_opened_row" ]]; then
    first_opened_manifest="$(printf '%s\n' "$first_opened_row" | cut -f2)"
    first_approved_manifest="$(head -n 1 "$approved_manifest_rows" | cut -f2)"
    [[ "$first_opened_manifest" == "$first_approved_manifest" ]] || {
      echo 'The first accepted opened event does not freeze the baseline approved Unit manifest.' >&2
      exit 1
    }
  fi
  [[ "$current_manifest_fingerprint" == 'pending' || "$current_manifest_fingerprint" == "$manifest_chain" ]] || {
    echo 'Current State Unit manifest fingerprint is not the latest approved generation.' >&2
    exit 1
  }
fi

supersession_markers_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-supersessions.XXXXXX")"
scope_revision_markers_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-scope-revisions.XXXXXX")"
: > "$supersession_markers_seen"
: > "$scope_revision_markers_seen"
trap 'rm -f "$seen_units" "$critics_seen" "$builders_seen" "$historical_bars" "$historical_manifests" "$round_ledger_paths" "$pr_urls_seen" "$qa_rounds_seen" "$qa_comment_evidence_seen" "$pr_ledger_paths" "$remediation_trigger_records" "$remediation_triggers_seen" "$publication_checkpoints_seen" "$promotion_ledger_paths" "$promotion_archive_paths" "$promotion_completion_states" "$promotion_affected_values" "$completion_ledger_paths" "$completion_consumed_paths" "$evidence_timeline" "$approved_manifest_rows" "$approved_quality_rows" "$manifest_revision_ids" "$quality_revision_ids" "$supersession_markers_seen" "$scope_revision_markers_seen"' EXIT
gauntlet_scope_revision_reaches() {
  local revision_item="$1"
  local revision_from="$2"
  local revision_to="$3"
  local revision_seen="${4:-|}"
  local revision_row revision_next

  [[ "$revision_from" == "$revision_to" ]] && return 0
  [[ "$revision_seen" != *"|$revision_from|"* ]] || return 1
  revision_seen+="$revision_from|"
  while IFS= read -r revision_row; do
    [[ "$revision_row" == "$revision_item|$revision_from|"* ]] || continue
    revision_next="${revision_row##*|}"
    [[ "$revision_next" == "$revision_to" ]] && return 0
    gauntlet_scope_revision_reaches "$revision_item" "$revision_next" "$revision_to" "$revision_seen" && return 0
  done < "$scope_revision_markers_seen"
  return 1
}
while IFS= read -r history_line; do
  [[ "$history_line" == '- Unit scope-title revision:'* ]] || continue
  [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]scope-title[[:space:]]revision:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]from:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]to:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]reason:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]by:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || {
    echo "Malformed Unit scope-title revision marker: $history_line" >&2
    exit 1
  }
  scope_revision_item="${BASH_REMATCH[1]}"
  scope_revision_from="${BASH_REMATCH[3]}"
  scope_revision_to="${BASH_REMATCH[4]}"
  scope_revision_reason="$(gauntlet_trim "${BASH_REMATCH[5]}")"
  scope_revision_approver="$(gauntlet_trim "${BASH_REMATCH[6]}")"
  scope_revision_at="$(gauntlet_trim "${BASH_REMATCH[7]}")"
  scope_revision_key="$scope_revision_item|$scope_revision_from|$scope_revision_to"
  grep -Fqx -- "$scope_revision_key" "$scope_revision_markers_seen" && {
    echo "Duplicate Unit scope-title revision marker: $scope_revision_key" >&2
    exit 1
  }
  printf '%s\n' "$scope_revision_key" >> "$scope_revision_markers_seen"
  grep -Fqx -- "$scope_revision_item" "$seen_units" || { echo "Scope-title revision references unretained unit: $scope_revision_item" >&2; exit 1; }
  [[ "$scope_revision_from" != "$scope_revision_to" ]] || { echo "Scope-title revision must change its fingerprint: $scope_revision_item" >&2; exit 1; }
  gauntlet_validate_substantive_single_line "$scope_revision_reason" "Unit scope-title revision reason ($scope_revision_item)"
  gauntlet_validate_substantive_single_line "$scope_revision_approver" "Unit scope-title revision approver ($scope_revision_item)"
  gauntlet_validate_replay_timestamp "$scope_revision_at" "Unit scope-title revision approved at ($scope_revision_item)"
  scope_revision_approval_rows="$(awk -F '\t' \
    -v at="$scope_revision_at" -v actor="$scope_revision_approver" \
    '$1 == at && $4 == actor { print }' "$approved_manifest_rows")"
  [[ "$(printf '%s\n' "$scope_revision_approval_rows" | sed '/^$/d' | wc -l | tr -d '[:space:]')" -eq 1 ]] || {
    echo "Scope-title revision is not bound to exactly one approved Unit manifest generation: $scope_revision_item" >&2
    exit 1
  }
  scope_revision_approval_units="$(printf '%s\n' "$scope_revision_approval_rows" | cut -f3)"
  gauntlet_comma_list_contains "$scope_revision_approval_units" "$scope_revision_item" || {
    echo "Scope-title revision unit is absent from its exact approved Unit manifest generation: $scope_revision_item" >&2
    exit 1
  }
  current_scope_revision_fp="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$scope_revision_item")"
  scope_from_seen=0
  scope_to_seen=0
  while IFS= read -r scope_evidence; do
    [[ -n "$scope_evidence" ]] || continue
    case "$scope_evidence" in
      "$gauntlet_dir"/rounds/"$scope_revision_item"/*)
        scope_evidence_fp="$(gauntlet_section_field "$scope_evidence" 'Round Metadata' 'Scope fingerprint')" ;;
      "$gauntlet_dir"/pr-events/"$scope_revision_item"/*)
        scope_evidence_fp="$(gauntlet_section_field "$scope_evidence" 'PR Event Metadata' 'Scope fingerprint')" ;;
      *) continue ;;
    esac
    [[ "$scope_evidence_fp" == "$scope_revision_from" ]] && scope_from_seen=1
    [[ "$scope_evidence_fp" == "$scope_revision_to" ]] && scope_to_seen=1
  done < <(find "$gauntlet_dir/rounds/$scope_revision_item" "$gauntlet_dir/pr-events/$scope_revision_item" -type f \
    \( -name 'round-*.md' -o -name 'event-*.md' \) -print 2>/dev/null | LC_ALL=C sort)
  [[ "$scope_from_seen" -eq 1 \
    && ( "$scope_to_seen" -eq 1 || "$current_scope_revision_fp" == "$scope_revision_to" ) ]] || {
    echo "Scope-title revision does not bind a retained old scope to the approved current/new scope: $scope_revision_item" >&2
    exit 1
  }
done <<< "$unit_history"

while IFS= read -r history_line; do
  [[ "$history_line" == '- Unit supersession:'* ]] || continue
  [[ "$history_line" =~ ^-[[:space:]]Unit[[:space:]]supersession:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]scope:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]replacements:[[:space:]]([a-z0-9,-]+)[[:space:]]\|[[:space:]]reason:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]by:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || {
    echo "Malformed Unit supersession marker: $history_line" >&2
    exit 1
  }
  superseded_item="${BASH_REMATCH[1]}"
  superseded_scope="${BASH_REMATCH[3]}"
  superseded_replacements="${BASH_REMATCH[4]}"
  superseded_reason="$(gauntlet_trim "${BASH_REMATCH[5]}")"
  superseded_approver="$(gauntlet_trim "${BASH_REMATCH[6]}")"
  superseded_at="$(gauntlet_trim "${BASH_REMATCH[7]}")"
  grep -Fqx -- "$superseded_item" "$supersession_markers_seen" && {
    echo "Superseded unit has more than one topology marker: $superseded_item" >&2
    exit 1
  }
  printf '%s\n' "$superseded_item" >> "$supersession_markers_seen"
  grep -Fqx -- "$superseded_item" "$seen_units" || { echo "Supersession marker references unretained unit: $superseded_item" >&2; exit 1; }
  [[ "$(gauntlet_unit_status "$gauntlet_file" "$superseded_item")" == 'superseded' \
    && "$superseded_scope" == "$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$superseded_item")" \
    && "$superseded_replacements" == "$(printf '%s' "$superseded_replacements" | tr ',' '\n' | LC_ALL=C sort -u | paste -sd, -)" ]] || {
    echo "Supersession marker status, old-scope hash, or replacement ordering is stale: $superseded_item" >&2
    exit 1
  }
  gauntlet_validate_substantive_single_line "$superseded_reason" "Unit supersession reason ($superseded_item)"
  gauntlet_validate_substantive_single_line "$superseded_approver" "Unit supersession approver ($superseded_item)"
  gauntlet_validate_replay_timestamp "$superseded_at" "Unit supersession approved at ($superseded_item)"
  supersession_approval_rows="$(awk -F '\t' \
    -v at="$superseded_at" -v actor="$superseded_approver" \
    '$1 == at && $4 == actor { print }' "$approved_manifest_rows")"
  [[ "$(printf '%s\n' "$supersession_approval_rows" | sed '/^$/d' | wc -l | tr -d '[:space:]')" -eq 1 ]] || {
    echo "Supersession edge is not bound to exactly one approved Unit manifest generation: $superseded_item" >&2
    exit 1
  }
  supersession_approval_units="$(printf '%s\n' "$supersession_approval_rows" | cut -f3)"
  gauntlet_comma_list_contains "$supersession_approval_units" "$superseded_item" || {
    echo "Superseded unit is absent from its exact approved Unit manifest generation: $superseded_item" >&2
    exit 1
  }
  [[ "$superseded_scope" == "$(gauntlet_unit_scope_fingerprint_at \
    "$gauntlet_file" "$superseded_item" "$superseded_at")" ]] || {
    echo "Supersession edge uses a scope not active in its exact approved Unit manifest generation: $superseded_item" >&2
    exit 1
  }
  IFS=',' read -r -a supersession_replacement_ids <<< "$superseded_replacements"
  for supersession_replacement in "${supersession_replacement_ids[@]}"; do
    [[ "$supersession_replacement" != "$superseded_item" ]] || { echo "Unit cannot supersede itself: $superseded_item" >&2; exit 1; }
    grep -Fqx -- "$supersession_replacement" "$seen_units" || {
      echo "Supersession replacement is not retained: $superseded_item -> $supersession_replacement" >&2
      exit 1
    }
    gauntlet_comma_list_contains "$supersession_approval_units" "$supersession_replacement" || {
      echo "Supersession replacement is absent from its exact approved Unit manifest generation: $superseded_item -> $supersession_replacement" >&2
      exit 1
    }
  done
  while IFS= read -r superseded_evidence; do
    [[ -n "$superseded_evidence" ]] || continue
    case "$superseded_evidence" in
      "$gauntlet_dir"/rounds/"$superseded_item"/*)
        superseded_evidence_time="$(gauntlet_section_field "$superseded_evidence" 'Round Metadata' 'Recorded at')" ;;
      "$gauntlet_dir"/pr-events/"$superseded_item"/*)
        superseded_evidence_time="$(gauntlet_section_field "$superseded_evidence" 'PR Event Metadata' 'Recorded at')" ;;
      *) continue ;;
    esac
    [[ "$superseded_evidence_time" < "$superseded_at" || "$superseded_evidence_time" == "$superseded_at" ]] || {
      echo "Superseded unit retains evidence recorded after its approved transition: ${superseded_evidence#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}" >&2
      exit 1
    }
  done < <(find "$gauntlet_dir/rounds/$superseded_item" "$gauntlet_dir/pr-events/$superseded_item" -type f \
    \( -name 'round-*.md' -o -name 'event-*.md' \) -print 2>/dev/null | LC_ALL=C sort)
done <<< "$unit_history"

while IFS= read -r retained_item; do
  [[ -n "$retained_item" ]] || continue
  retained_status="$(gauntlet_unit_status "$gauntlet_file" "$retained_item")"
  if [[ "$retained_status" == 'superseded' ]]; then
    grep -Fqx -- "$retained_item" "$supersession_markers_seen" || {
      echo "Superseded unit requires exactly one canonical topology marker: $retained_item" >&2
      exit 1
    }
    retained_replacements="$(gauntlet_supersession_replacements "$gauntlet_file" "$retained_item")" || {
      echo "Cannot resolve supersession replacements for $retained_item" >&2
      exit 1
    }
    IFS=',' read -r -a retained_replacement_ids <<< "$retained_replacements"
    for retained_replacement in "${retained_replacement_ids[@]}"; do
      gauntlet_supersession_reaches "$gauntlet_file" "$retained_replacement" "$retained_item" && {
        echo "Unit supersession graph contains a cycle through $retained_item and $retained_replacement" >&2
        exit 1
      }
    done
  elif grep -Fqx -- "$retained_item" "$supersession_markers_seen"; then
    echo "Only a unit with status superseded may own a supersession marker: $retained_item" >&2
    exit 1
  fi
  retained_current_scope="$(gauntlet_unit_scope_fingerprint "$gauntlet_file" "$retained_item")"
  retained_historical_scopes="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-unit-scopes.XXXXXX")"
  printf '%s\n' "$retained_current_scope" > "$retained_historical_scopes"
  while IFS= read -r retained_scope_evidence; do
    [[ -n "$retained_scope_evidence" ]] || continue
    case "$retained_scope_evidence" in
      "$gauntlet_dir"/rounds/"$retained_item"/*)
        gauntlet_section_field "$retained_scope_evidence" 'Round Metadata' 'Scope fingerprint' >> "$retained_historical_scopes" ;;
      "$gauntlet_dir"/pr-events/"$retained_item"/*)
        gauntlet_section_field "$retained_scope_evidence" 'PR Event Metadata' 'Scope fingerprint' >> "$retained_historical_scopes" ;;
    esac
  done < <(find "$gauntlet_dir/rounds/$retained_item" "$gauntlet_dir/pr-events/$retained_item" -type f \
    \( -name 'round-*.md' -o -name 'event-*.md' \) -print 2>/dev/null | LC_ALL=C sort)
  while IFS= read -r retained_old_scope; do
    [[ -n "$retained_old_scope" && "$retained_old_scope" != "$retained_current_scope" ]] || continue
    gauntlet_scope_revision_reaches "$retained_item" "$retained_old_scope" "$retained_current_scope" || {
      rm -f "$retained_historical_scopes"
      echo "Changed retained unit lacks a complete approved scope-title revision chain: $retained_item" >&2
      exit 1
    }
  done < <(LC_ALL=C sort -u "$retained_historical_scopes")
  rm -f "$retained_historical_scopes"
done < <(printf '%s' "$(gauntlet_unit_ids_csv "$gauntlet_file")" | tr ',' '\n')

# Reconstruct every approved manifest generation from its exact members, the
# scope definition active for each member, and topology edges active at that
# approval second. This turns otherwise opaque historical fingerprints into a
# replayable chain and prevents later scope/topology changes from being
# backdated into an earlier generation.
while IFS=$'\t' read -r manifest_generation_at manifest_generation_fingerprint \
  manifest_generation_units _manifest_generation_approver; do
  [[ -n "$manifest_generation_fingerprint" ]] || continue
  reconstructed_manifest_fingerprint="$(gauntlet_unit_manifest_fingerprint_at \
    "$gauntlet_file" "$manifest_generation_units" "$manifest_generation_at")" || {
    echo "Approved Unit manifest generation has an invalid scope/topology chain at $manifest_generation_at." >&2
    exit 1
  }
  [[ "$reconstructed_manifest_fingerprint" == "$manifest_generation_fingerprint" ]] || {
    echo "Approved Unit manifest generation cannot be reconstructed from its approved unit, scope, and topology state: $manifest_generation_at" >&2
    exit 1
  }
done < "$approved_manifest_rows"

# Every retained unit has one deterministic scope lineage. A unit's first
# scope revision must follow (not coincide with) the generation that introduced
# it, every revision is a strictly chronological immediate-parent edge, and the
# chain must end at the current retained definition.
while IFS= read -r scope_chain_item; do
  [[ -n "$scope_chain_item" ]] || continue
  scope_chain_introduced_at=''
  while IFS=$'\t' read -r manifest_generation_at _manifest_generation_fingerprint \
    manifest_generation_units _manifest_generation_approver; do
    if gauntlet_comma_list_contains "$manifest_generation_units" "$scope_chain_item"; then
      scope_chain_introduced_at="$manifest_generation_at"
      break
    fi
  done < "$approved_manifest_rows"
  [[ -n "$scope_chain_introduced_at" ]] || {
    echo "Retained work unit is absent from every approved Unit manifest generation: $scope_chain_item" >&2
    exit 1
  }
  scope_chain_first_revision=''
  while IFS= read -r scope_chain_history_line; do
    [[ "$scope_chain_history_line" =~ ^-[[:space:]]Unit[[:space:]]scope-title[[:space:]]revision:[[:space:]]${scope_chain_item}[[:space:]]\|.*\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)$ ]] || continue
    scope_chain_revision_at="$(gauntlet_trim "${BASH_REMATCH[1]}")"
    if [[ -z "$scope_chain_first_revision" \
      || "$scope_chain_revision_at" < "$scope_chain_first_revision" ]]; then
      scope_chain_first_revision="$scope_chain_revision_at"
    fi
  done <<< "$unit_history"
  [[ -z "$scope_chain_first_revision" \
    || "$scope_chain_introduced_at" < "$scope_chain_first_revision" ]] || {
    echo "Unit scope revision does not follow the manifest generation that introduced its unit: $scope_chain_item" >&2
    exit 1
  }
  scope_chain_latest="$(gauntlet_unit_scope_fingerprint_at \
    "$gauntlet_file" "$scope_chain_item" '9999-12-31T23:59:59Z')" || exit 1
  [[ "$scope_chain_latest" == "$(gauntlet_unit_scope_fingerprint \
    "$gauntlet_file" "$scope_chain_item")" ]] || {
    echo "Unit scope revision chain does not end at the current retained definition: $scope_chain_item" >&2
    exit 1
  }
done < <(printf '%s' "$(gauntlet_unit_ids_csv "$gauntlet_file")" | tr ',' '\n')

# Each evidence record must use the generation active at its timestamp. An
# approval becomes effective at its exact UTC second; equal-time old-generation
# evidence is therefore rejected deterministically.
while IFS=$'\t' read -r timeline_time timeline_manifest timeline_quality timeline_path; do
  [[ -n "$timeline_path" ]] || continue
  expected_timeline_manifest=''
  expected_timeline_manifest_at=''
  expected_timeline_units=''
  while IFS=$'\t' read -r approval_time approval_manifest approval_units _approval_actor; do
    [[ -n "$approval_manifest" ]] || continue
    if [[ "$approval_time" < "$timeline_time" || "$approval_time" == "$timeline_time" ]]; then
      expected_timeline_manifest="$approval_manifest"
      expected_timeline_manifest_at="$approval_time"
      expected_timeline_units="$approval_units"
    fi
  done < "$approved_manifest_rows"
  [[ -n "$expected_timeline_manifest" && "$timeline_manifest" == "$expected_timeline_manifest" ]] || {
    echo "Immutable evidence uses a Unit manifest not active at its Recorded at timestamp: $timeline_path" >&2
    exit 1
  }
  timeline_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$timeline_path"
  timeline_item='aggregate'
  timeline_scope='aggregate'
  case "$timeline_path" in
    .ai/gauntlets/"$gauntlet_name"/rounds/*/round-*.md)
      timeline_item="$(gauntlet_section_field "$timeline_file" 'Round Metadata' 'Item')"
      timeline_scope="$(gauntlet_section_field \
        "$timeline_file" 'Round Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')"
      ;;
    .ai/gauntlets/"$gauntlet_name"/pr-events/*/event-*.md)
      timeline_item="$(gauntlet_section_field "$timeline_file" 'PR Event Metadata' 'Item')"
      timeline_scope="$(gauntlet_section_field \
        "$timeline_file" 'PR Event Metadata' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')"
      ;;
  esac
  if [[ "$timeline_item" != 'aggregate' && "$timeline_item" != 'integration' ]]; then
    gauntlet_comma_list_contains "$expected_timeline_units" "$timeline_item" || {
      echo "Immutable evidence item was not part of the active Unit manifest at its Recorded at timestamp: $timeline_path" >&2
      exit 1
    }
    expected_timeline_scope="$(gauntlet_unit_scope_fingerprint_at \
      "$gauntlet_file" "$timeline_item" "$expected_timeline_manifest_at")" || exit 1
    [[ "$timeline_scope" == "$expected_timeline_scope" ]] || {
      echo "Immutable evidence scope was not part of the active Unit manifest at its Recorded at timestamp: $timeline_path" >&2
      exit 1
    }
  fi
done < <(LC_ALL=C sort -k1,1 -k4,4 "$evidence_timeline")

# Quality revisions form the same immediate-parent chain. The first opened
# event's exact publication checkpoint durably freezes the baseline approval
# time. Every later revision is consumed exactly once by the first opened event
# using that generation; timestamp orders distinct seconds and immutable
# Progress PR Ledger order breaks same-second ties.
quality_revision_count=0
if [[ "$immutable_evidence_count" -gt 0 || "$phase" == 'ready' || "$phase" == 'complete' ]]; then
if [[ -n "$first_opened_row" ]]; then
  quality_chain="$(printf '%s\n' "$first_opened_row" | cut -f3)"
  first_opened_relative="$(printf '%s\n' "$first_opened_row" | cut -f4)"
  first_opened_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$first_opened_relative"
  first_quality_checkpoint="$(gauntlet_section_field \
    "$first_opened_file" 'PR Event Metadata' 'Publication checkpoint')"
  first_quality_checkpoint_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$first_quality_checkpoint"
  [[ "$first_quality_checkpoint" =~ ^\.ai/gauntlets/${gauntlet_name}/publication-checkpoints/[a-z0-9]+(-[a-z0-9]+)*/checkpoint-[0-9]{3,}\.md$ \
    && -f "$first_quality_checkpoint_file" && ! -L "$first_quality_checkpoint_file" \
    && "$(gauntlet_section_field "$first_quality_checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar fingerprint')" == "$quality_chain" ]] || {
    echo 'The first opened event lacks a safe publication checkpoint for its baseline quality generation.' >&2
    exit 1
  }
  quality_activation_time="$(gauntlet_section_field \
    "$first_quality_checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar approved at')"
else
  quality_chain="$quality_fingerprint"
  quality_activation_time="$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Approved at')"
fi
gauntlet_validate_replay_timestamp "$quality_activation_time" 'Initial quality generation activation time'
printf '%s\t%s\n' "$quality_activation_time" "$quality_chain" >> "$approved_quality_rows"
quality_last_approval_time="$quality_activation_time"
while IFS= read -r history_line; do
  [[ "$history_line" == '- Quality bar revision:'* ]] || continue
  [[ "$history_line" =~ ^-[[:space:]]Quality[[:space:]]bar[[:space:]]revision:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]approved[[:space:]]by:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]supersedes:[[:space:]]([0-9a-f]{64})[[:space:]]\|[[:space:]]reason:[[:space:]]([^|]+)$ ]] || {
    echo "Malformed Quality bar revision marker: $history_line" >&2
    exit 1
  }
  quality_revision_id="${BASH_REMATCH[1]}"
  quality_revision_approver="$(gauntlet_trim "${BASH_REMATCH[3]}")"
  quality_revision_time="$(gauntlet_trim "${BASH_REMATCH[4]}")"
  quality_revision_parent="${BASH_REMATCH[5]}"
  quality_revision_reason="$(gauntlet_trim "${BASH_REMATCH[6]}")"
  grep -Fqx -- "$quality_revision_id" "$quality_revision_ids" && {
    echo "Duplicate Quality bar revision id: $quality_revision_id" >&2
    exit 1
  }
  printf '%s\n' "$quality_revision_id" >> "$quality_revision_ids"
  gauntlet_validate_substantive_single_line "$quality_revision_approver" "Quality revision approver ($quality_revision_id)"
  gauntlet_validate_substantive_single_line "$quality_revision_reason" "Quality revision reason ($quality_revision_id)"
  gauntlet_validate_replay_timestamp "$quality_revision_time" "Quality revision approved at ($quality_revision_id)"
  [[ "$quality_revision_parent" == "$quality_chain" \
    && "$quality_last_approval_time" < "$quality_revision_time" ]] || {
    echo "Quality revision must supersede the immediately prior generation with a strictly later approval: $quality_revision_id" >&2
    exit 1
  }
  revision_opened_qualities="$(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' -print 2>/dev/null \
    | while IFS= read -r revision_opened_file; do
        [[ "$(gauntlet_section_field "$revision_opened_file" 'PR Event Metadata' 'Event')" == 'opened' \
          && "$(gauntlet_section_field "$revision_opened_file" 'PR Event Metadata' 'Remediation trigger')" == "quality-revision:$quality_revision_id" ]] || continue
        printf '%s\t%s\t%s\n' \
          "$(gauntlet_section_field "$revision_opened_file" 'PR Event Metadata' 'Recorded at')" \
          "$(gauntlet_section_field "$revision_opened_file" 'PR Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" \
          "${revision_opened_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      done | LC_ALL=C sort -k1,1 -k3,3)"
  if [[ -n "$revision_opened_qualities" ]]; then
    quality_revision_consumer_count="$(printf '%s\n' "$revision_opened_qualities" \
      | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    [[ "$quality_revision_consumer_count" -eq 1 ]] || {
      echo "Quality revision must have exactly one global opened-event consumer: $quality_revision_id" >&2
      exit 1
    }
    quality_revision_next="$(printf '%s\n' "$revision_opened_qualities" | cut -f2)"
    quality_revision_consumer_path="$(printf '%s\n' "$revision_opened_qualities" | cut -f3)"
    while IFS=$'\t' read -r revision_opened_time revision_opened_quality _revision_opened_path; do
      # The exact publication checkpoint and revision trigger provide the
      # causal edge when approval and event recording share one UTC second.
      [[ ( "$quality_revision_time" < "$revision_opened_time" \
          || "$quality_revision_time" == "$revision_opened_time" ) \
        && "$revision_opened_quality" == "$quality_revision_next" ]] || {
        echo "Quality revision opened evidence is misordered or freezes inconsistent generations: $quality_revision_id" >&2
        exit 1
      }
    done <<< "$revision_opened_qualities"

    quality_revision_first_path=''
    quality_revision_first_time=''
    while IFS= read -r revision_generation_file; do
      [[ "$(gauntlet_section_field "$revision_generation_file" 'PR Event Metadata' 'Event')" == 'opened' \
        && "$(gauntlet_section_field "$revision_generation_file" 'PR Event Metadata' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" == "$quality_revision_next" ]] || continue
      revision_generation_time="$(gauntlet_section_field \
        "$revision_generation_file" 'PR Event Metadata' 'Recorded at')"
      revision_generation_path="${revision_generation_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      if [[ -z "$quality_revision_first_path" \
        || "$revision_generation_time" < "$quality_revision_first_time" ]] \
        || { [[ "$revision_generation_time" == "$quality_revision_first_time" ]] \
          && gauntlet_progress_pr_event_precedes "$gauntlet_file" \
            "$revision_generation_path" "$quality_revision_first_path"; }; then
        quality_revision_first_time="$revision_generation_time"
        quality_revision_first_path="$revision_generation_path"
      fi
    done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' \
      -print 2>/dev/null | LC_ALL=C sort)
    [[ "$quality_revision_first_path" == "$quality_revision_consumer_path" ]] || {
      echo "The first opened event using a revised quality generation must carry its exact revision trigger: $quality_revision_id" >&2
      exit 1
    }
  else
    [[ "$current_fingerprint" == 'pending' ]] || {
      echo "Quality revision lacks an exact consuming opened checkpoint/event: $quality_revision_id" >&2
      exit 1
    }
    quality_revision_next="$quality_fingerprint"
  fi
  [[ "$quality_revision_next" != "$quality_chain" ]] || {
    echo "Quality revision did not change the approved quality fingerprint: $quality_revision_id" >&2
    exit 1
  }
  quality_chain="$quality_revision_next"
  quality_last_approval_time="$quality_revision_time"
  quality_revision_count=$((quality_revision_count + 1))
  printf '%s\t%s\n' "$quality_revision_time" "$quality_chain" >> "$approved_quality_rows"
done <<< "$unit_history"
if [[ "$quality_revision_count" -eq 0 ]]; then
  [[ "$quality_activation_time" == "$(gauntlet_section_field \
    "$gauntlet_file" 'Approved Quality Bar' 'Approved at')" ]] || {
    echo "Publication checkpoint uses a quality generation not active at its Recorded at timestamp: $first_quality_checkpoint" >&2
    exit 1
  }
fi
[[ "$quality_chain" == "$quality_fingerprint" ]] || {
  echo 'Approved Quality Bar does not match the latest chronological quality-revision generation.' >&2
  exit 1
}
while IFS=$'\t' read -r timeline_time _timeline_manifest timeline_quality timeline_path; do
  [[ -n "$timeline_path" ]] || continue
  expected_timeline_quality=''
  while IFS=$'\t' read -r approval_time approval_quality; do
    if [[ "$approval_time" < "$timeline_time" || "$approval_time" == "$timeline_time" ]]; then
      expected_timeline_quality="$approval_quality"
    fi
  done < "$approved_quality_rows"
  [[ -n "$expected_timeline_quality" && "$timeline_quality" == "$expected_timeline_quality" ]] || {
    echo "Immutable evidence uses a quality generation not active at its Recorded at timestamp: $timeline_path" >&2
    exit 1
  }
done < <(LC_ALL=C sort -k1,1 -k4,4 "$evidence_timeline")

# Publication checkpoints are authorization evidence rather than completed
# work evidence, so they do not participate in the "first evidence is opened"
# rule above. They must still freeze the manifest and quality generations that
# were active when publication was authorized.
if [[ -d "$publication_checkpoint_root" ]]; then
  while IFS= read -r generation_checkpoint_file; do
    [[ -n "$generation_checkpoint_file" ]] || continue
    generation_checkpoint_relative="${generation_checkpoint_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
    generation_checkpoint_time="$(gauntlet_section_field \
      "$generation_checkpoint_file" 'Publication Checkpoint Metadata' 'Recorded at')"
    generation_checkpoint_manifest="$(gauntlet_section_field \
      "$generation_checkpoint_file" 'Publication Checkpoint Metadata' 'Unit manifest fingerprint' \
      | tr '[:upper:]' '[:lower:]')"
    generation_checkpoint_manifest_approved_at="$(gauntlet_section_field \
      "$generation_checkpoint_file" 'Publication Checkpoint Metadata' 'Unit manifest approved at')"
    generation_checkpoint_item="$(gauntlet_section_field \
      "$generation_checkpoint_file" 'Publication Checkpoint Metadata' 'Item')"
    generation_checkpoint_scope="$(gauntlet_section_field \
      "$generation_checkpoint_file" 'Publication Checkpoint Metadata' 'Unit scope fingerprint' \
      | tr '[:upper:]' '[:lower:]')"
    generation_checkpoint_quality="$(gauntlet_section_field \
      "$generation_checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar fingerprint' \
      | tr '[:upper:]' '[:lower:]')"
    generation_checkpoint_quality_approved_at="$(gauntlet_section_field \
      "$generation_checkpoint_file" 'Publication Checkpoint Metadata' 'Quality bar approved at')"

    expected_checkpoint_manifest=''
    expected_checkpoint_manifest_approved_at=''
    expected_checkpoint_manifest_units=''
    while IFS=$'\t' read -r approval_time approval_manifest approval_units _approval_actor; do
      [[ -n "$approval_manifest" ]] || continue
      if [[ "$approval_time" < "$generation_checkpoint_time" \
        || "$approval_time" == "$generation_checkpoint_time" ]]; then
        expected_checkpoint_manifest="$approval_manifest"
        expected_checkpoint_manifest_approved_at="$approval_time"
        expected_checkpoint_manifest_units="$approval_units"
      fi
    done < "$approved_manifest_rows"
    [[ -n "$expected_checkpoint_manifest" \
      && "$generation_checkpoint_manifest" == "$expected_checkpoint_manifest" \
      && "$generation_checkpoint_manifest_approved_at" == "$expected_checkpoint_manifest_approved_at" ]] || {
      echo "Publication checkpoint uses a Unit manifest not active at its Recorded at timestamp: $generation_checkpoint_relative" >&2
      exit 1
    }
    gauntlet_comma_list_contains \
      "$expected_checkpoint_manifest_units" "$generation_checkpoint_item" || {
      echo "Publication checkpoint item was not part of the active Unit manifest at its Recorded at timestamp: $generation_checkpoint_relative" >&2
      exit 1
    }
    expected_checkpoint_scope="$(gauntlet_unit_scope_fingerprint_at \
      "$gauntlet_file" "$generation_checkpoint_item" \
      "$expected_checkpoint_manifest_approved_at")" || exit 1
    [[ "$generation_checkpoint_scope" == "$expected_checkpoint_scope" ]] || {
      echo "Publication checkpoint scope was not part of the active Unit manifest at its Recorded at timestamp: $generation_checkpoint_relative" >&2
      exit 1
    }

    expected_checkpoint_quality=''
    expected_checkpoint_quality_approved_at=''
    while IFS=$'\t' read -r approval_time approval_quality; do
      [[ -n "$approval_quality" ]] || continue
      if [[ "$approval_time" < "$generation_checkpoint_time" \
        || "$approval_time" == "$generation_checkpoint_time" ]]; then
        expected_checkpoint_quality="$approval_quality"
        expected_checkpoint_quality_approved_at="$approval_time"
      fi
    done < "$approved_quality_rows"
    [[ -n "$expected_checkpoint_quality" \
      && "$generation_checkpoint_quality" == "$expected_checkpoint_quality" \
      && "$generation_checkpoint_quality_approved_at" == "$expected_checkpoint_quality_approved_at" ]] || {
      echo "Publication checkpoint uses a quality generation not active at its Recorded at timestamp: $generation_checkpoint_relative" >&2
      exit 1
    }
  done < <(find "$publication_checkpoint_root" -type f -name 'checkpoint-*.md' -print | LC_ALL=C sort)
fi
fi

if [[ "$current_execution_fingerprint" == 'pending' ]]; then
  [[ $immutable_evidence_count -eq 0 \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Execution contract fingerprint')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Base commit SHA')" == 'pending' ]] || {
    echo 'Execution contract fingerprint may remain pending only before all immutable Gauntlet evidence.' >&2
    exit 1
  }
elif [[ $immutable_evidence_count -eq 0 ]]; then
  echo 'Only the first accepted opened progress-PR event may freeze the execution contract.' >&2
  exit 1
fi

# Reconstruct terminal remediation authorization only after every referenced
# immutable trigger has itself passed full evidence and ledger replay.
while IFS=$'\t' read -r trigger_item _terminal_event terminal_time opened_event opened_time remediation_trigger; do
  [[ -n "$trigger_item" ]] || continue
  [[ "$terminal_time" < "$opened_time" || "$terminal_time" == "$opened_time" ]] || {
    echo "Remediation PR predates its terminal progress-PR event: $opened_event" >&2
    exit 1
  }
  opened_trigger_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$opened_event"
  opened_trigger_checkpoint="$(gauntlet_section_field \
    "$opened_trigger_file" 'PR Event Metadata' 'Publication checkpoint')"
  opened_trigger_checkpoint_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$opened_trigger_checkpoint"
  [[ -f "$opened_trigger_file" && ! -L "$opened_trigger_file" \
    && "$opened_trigger_checkpoint" =~ ^\.ai/gauntlets/${gauntlet_name}/publication-checkpoints/${trigger_item}/checkpoint-[0-9]{3,}\.md$ \
    && -f "$opened_trigger_checkpoint_file" && ! -L "$opened_trigger_checkpoint_file" ]] || {
    echo "Remediation PR lacks its safe publication-checkpoint authorization cutoff: $opened_event" >&2
    exit 1
  }
  opened_trigger_cutoff="$(gauntlet_section_field \
    "$opened_trigger_checkpoint_file" 'Publication Checkpoint Metadata' 'Recorded at')"
  trigger_time=''
  if [[ "$remediation_trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/integration/round-[0-9]{3,}\.md$ ]]; then
    trigger_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$remediation_trigger"
    [[ -f "$trigger_file" && ! -L "$trigger_file" ]] || {
      echo "Remediation references missing or unsafe integration evidence: $remediation_trigger" >&2
      exit 1
    }
    trigger_verdict="$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Verdict')"
    [[ "$trigger_verdict" == 'fail' || "$trigger_verdict" == 'blocked' ]] || {
      echo "Terminal remediation requires a failing or blocked integration trigger: $remediation_trigger" >&2
      exit 1
    }
    trigger_time="$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Recorded at')"
    gauntlet_failure_applies_to_unit_at "$gauntlet_file" \
      "$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Affected units')" \
      "$trigger_item" "$opened_trigger_cutoff" || {
      echo "Integration remediation trigger does not affect $trigger_item: $remediation_trigger" >&2
      exit 1
    }
  elif [[ "$remediation_trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/([a-z0-9]+(-[a-z0-9]+)*)/round-[0-9]{3,}\.md$ ]]; then
    trigger_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$remediation_trigger"
    trigger_source_item="${BASH_REMATCH[1]}"
    trigger_verdict="$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Verdict')"
    trigger_applies=0
    if [[ "$trigger_source_item" == "$trigger_item" ]] \
      || gauntlet_supersession_reaches_at \
        "$gauntlet_file" "$trigger_source_item" "$trigger_item" "$opened_trigger_cutoff"; then
      trigger_applies=1
    fi
    [[ -f "$trigger_file" && ! -L "$trigger_file" \
      && ( "$trigger_verdict" == 'fail' || "$trigger_verdict" == 'blocked' ) \
      && "$trigger_applies" -eq 1 ]] || {
      echo "Work-unit remediation trigger is not an applicable failed/blocked round: $remediation_trigger" >&2
      exit 1
    }
    trigger_time="$(gauntlet_section_field "$trigger_file" 'Round Metadata' 'Recorded at')"
  elif [[ "$remediation_trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/promotion-events/event-[0-9]{3,}\.md$ ]]; then
    trigger_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$remediation_trigger"
    [[ -f "$trigger_file" && ! -L "$trigger_file" \
      && "$(gauntlet_section_field "$trigger_file" 'Promotion QA Event Metadata' 'Verdict')" == 'fail' ]] || {
      echo "Terminal remediation requires a failing Promotion QA trigger: $remediation_trigger" >&2
      exit 1
    }
    trigger_affected="$(gauntlet_section_field "$trigger_file" 'Promotion QA Event Metadata' 'Affected units')"
    gauntlet_failure_applies_to_unit_at \
      "$gauntlet_file" "$trigger_affected" "$trigger_item" "$opened_trigger_cutoff" || {
      echo "Promotion QA trigger does not authorize remediation for $trigger_item: $remediation_trigger" >&2
      exit 1
    }
    trigger_time="$(gauntlet_section_field "$trigger_file" 'Promotion QA Event Metadata' 'Recorded at')"
  elif [[ "$remediation_trigger" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/([a-z0-9]+(-[a-z0-9]+)*)/event-[0-9]{3,}\.md$ ]]; then
    trigger_file="$OPENCAW_PROJECT_ROOT_RESOLVED/$remediation_trigger"
    trigger_source_item="${BASH_REMATCH[1]}"
    trigger_event="$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'Event')"
    trigger_applies=0
    if [[ "$trigger_source_item" == "$trigger_item" ]] \
      || gauntlet_supersession_reaches_at \
        "$gauntlet_file" "$trigger_source_item" "$trigger_item" "$opened_trigger_cutoff"; then
      trigger_applies=1
    fi
    [[ -f "$trigger_file" && ! -L "$trigger_file" \
      && ( "$trigger_event" == 'qa-fail' || "$trigger_event" == 'closed' ) \
      && "$trigger_applies" -eq 1 ]] || {
      echo "PR-event remediation trigger is not an applicable failed cycle: $remediation_trigger" >&2
      exit 1
    }
    trigger_time="$(gauntlet_section_field "$trigger_file" 'PR Event Metadata' 'Recorded at')"
  elif [[ "$remediation_trigger" =~ ^quality-revision:([a-z0-9]+(-[a-z0-9]+)*)$ ]]; then
    trigger_revision_id="${BASH_REMATCH[1]}"
    trigger_revision_count=0
    latest_revision_before_open=''
    while IFS= read -r revision_candidate; do
      [[ "$revision_candidate" =~ ^-[[:space:]]Quality[[:space:]]bar[[:space:]]revision:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]approved[[:space:]]by:[[:space:]](.+)[[:space:]]\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]supersedes:[[:space:]]([0-9a-fA-F]{64})[[:space:]]\|[[:space:]]reason:[[:space:]](.+)$ ]] || continue
      candidate_revision_id="${BASH_REMATCH[1]}"
      candidate_revision_time="$(gauntlet_trim "${BASH_REMATCH[4]}")"
      candidate_revision_supersedes="${BASH_REMATCH[5],,}"
      candidate_revision_reason="$(gauntlet_trim "${BASH_REMATCH[6]}")"
      gauntlet_validate_replay_timestamp "$candidate_revision_time" "Quality revision approved at ($candidate_revision_id)"
      if [[ "$candidate_revision_time" < "$opened_time" || "$candidate_revision_time" == "$opened_time" ]]; then
        latest_revision_before_open="$candidate_revision_id"
      fi
      [[ "$candidate_revision_id" == "$trigger_revision_id" ]] || continue
      trigger_revision_count=$((trigger_revision_count + 1))
      trigger_time="$candidate_revision_time"
      trigger_supersedes="$candidate_revision_supersedes"
      trigger_reason="$candidate_revision_reason"
      grep -Fqx -- "$trigger_supersedes" "$historical_bars" || {
        echo "Quality revision trigger does not supersede retained evidence: $trigger_revision_id" >&2
        exit 1
      }
      gauntlet_has_substance "$trigger_reason" || {
        echo "Quality revision trigger reason must be substantive: $trigger_revision_id" >&2
        exit 1
      }
    done < <(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History')
    [[ $trigger_revision_count -eq 1 ]] || {
      echo "Quality revision remediation trigger must resolve exactly once: $remediation_trigger" >&2
      exit 1
    }
    [[ "$latest_revision_before_open" == "$trigger_revision_id" ]] || {
      echo "Quality revision remediation trigger was stale when the replacement PR opened: $remediation_trigger" >&2
      exit 1
    }
  else
    echo "Unsupported terminal remediation trigger: $remediation_trigger" >&2
    exit 1
  fi
  gauntlet_validate_replay_timestamp "$trigger_time" "Remediation trigger Recorded at ($remediation_trigger)"
  [[ "$trigger_time" < "$opened_trigger_cutoff" \
    || "$trigger_time" == "$opened_trigger_cutoff" ]] || {
    echo "Publication checkpoint remediation trigger was not active at its Recorded at timestamp: $opened_event" >&2
    exit 1
  }
  [[ ( "$terminal_time" < "$trigger_time" || "$terminal_time" == "$trigger_time" ) \
    && ( "$trigger_time" < "$opened_time" || "$trigger_time" == "$opened_time" ) ]] || {
    echo "Remediation trigger does not occur between terminal merge and replacement PR: $opened_event" >&2
    exit 1
  }
done < "$remediation_trigger_records"

if [[ "$latest_promotion_verdict" == 'pass' ]]; then
  [[ "$status" == 'passed' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pass' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA' | tr '[:upper:]' '[:lower:]')" == "$latest_promotion_head_sha" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint' | tr '[:upper:]' '[:lower:]')" == "$latest_promotion_scope" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Quality bar fingerprint' | tr '[:upper:]' '[:lower:]')" == "$latest_promotion_quality_bar" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Execution contract fingerprint' | tr '[:upper:]' '[:lower:]')" == "$latest_promotion_execution" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Base commit SHA' | tr '[:upper:]' '[:lower:]')" == "$latest_promotion_base_sha" \
    && "$active_completion_relative" == "$latest_promotion_completion" ]] || {
    echo 'Latest passing Promotion QA event does not match the current passed integration state.' >&2
    exit 1
  }
elif [[ "$latest_promotion_verdict" == 'fail' && "$status" == 'passed' ]]; then
  current_integration_evidence="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')"
  current_integration_evidence="${current_integration_evidence#\`}"
  current_integration_evidence="${current_integration_evidence%\`}"
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pass' \
    && "$current_integration_evidence" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/integration/round-[0-9]{3,}\.md$ \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA' | tr '[:upper:]' '[:lower:]')" != "$latest_promotion_head_sha" \
    && ( "$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$current_integration_evidence" 'Round Metadata' 'Recorded at')" > "$latest_promotion_recorded_at" \
      || "$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$current_integration_evidence" 'Round Metadata' 'Recorded at')" == "$latest_promotion_recorded_at" ) ]] || {
    echo 'A passed Gauntlet after Promotion QA failure requires a newer remediated integration pass.' >&2
    exit 1
  }
fi

# Reconstruct attempt sequencing from immutable evidence. Historical scope
# fingerprints may become stale after an explicit decomposition change, but
# each new PR cycle must open at its reviewed SHA/scope and every repeated
# attempt must consume the prior round through qa-fail (same PR) or a new PR.
if [[ -d "$gauntlet_dir/rounds" ]]; then
  while IFS= read -r sequence_round_dir; do
    [[ -n "$sequence_round_dir" ]] || continue
    sequence_item="$(basename "$sequence_round_dir")"
    previous_sequence_round=''
    failed_strategy_history="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-failed-strategies.XXXXXX")"
    : > "$failed_strategy_history"
    while IFS=$'\t' read -r _ sequence_round; do
      [[ -n "$sequence_round" ]] || continue
      sequence_pr="$(gauntlet_section_field "$sequence_round" 'Round Metadata' 'Progress PR')"
      sequence_sha="$(gauntlet_section_field "$sequence_round" 'Round Metadata' 'Head SHA')"
      sequence_scope="$(gauntlet_section_field "$sequence_round" 'Round Metadata' 'Scope fingerprint')"
      sequence_strategy="$(gauntlet_section_field "$sequence_round" 'Round Metadata' 'Builder strategy fingerprint')"
      sequence_relative="${sequence_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
      if grep -Fqx -- "$sequence_strategy" "$failed_strategy_history"; then
        rm -f "$failed_strategy_history"
        echo "Attempt reused a builder strategy retained by any earlier fail, block, or QA failure for $sequence_item: $sequence_relative" >&2
        exit 1
      fi
      if [[ -n "$previous_sequence_round" ]]; then
        previous_pr="$(gauntlet_section_field "$previous_sequence_round" 'Round Metadata' 'Progress PR')"
        previous_sha="$(gauntlet_section_field "$previous_sequence_round" 'Round Metadata' 'Head SHA')"
        previous_scope_fingerprint="$(gauntlet_section_field "$previous_sequence_round" 'Round Metadata' 'Scope fingerprint')"
        previous_strategy_fingerprint="$(gauntlet_section_field "$previous_sequence_round" 'Round Metadata' 'Builder strategy fingerprint')"
        previous_relative="${previous_sequence_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}"
        [[ "$sequence_strategy" != "$previous_strategy_fingerprint" \
          && ( "$sequence_item" == 'integration' || "${sequence_sha,,}" != "${previous_sha,,}" ) ]] || {
          echo "Repeated attempt reused its prior builder strategy or a work-unit Head SHA: $sequence_relative" >&2
          exit 1
        }
        if [[ "$sequence_item" != 'integration' ]]; then
          if [[ "${sequence_pr%/}" == "${previous_pr%/}" ]]; then
            gauntlet_has_progress_pr_event "$gauntlet_dir" "$sequence_item" 'qa-fail' \
              "$previous_pr" "$previous_relative" "$previous_sha" "$previous_scope_fingerprint" || {
              echo "Same-PR retry lacks qa-fail consumption of its prior round: $sequence_relative" >&2
              exit 1
            }
          else
            gauntlet_has_progress_pr_event "$gauntlet_dir" "$sequence_item" 'opened' \
              "$sequence_pr" 'none' "$sequence_sha" "$sequence_scope" || {
              echo "Remediation round lacks a matching opened PR event: $sequence_relative" >&2
              exit 1
            }
          fi
        fi
      elif [[ "$sequence_item" != 'integration' ]]; then
        gauntlet_has_progress_pr_event "$gauntlet_dir" "$sequence_item" 'opened' \
          "$sequence_pr" 'none' "$sequence_sha" "$sequence_scope" || {
          echo "Initial work-unit round lacks a matching opened PR event: $sequence_relative" >&2
          exit 1
        }
      fi
      if gauntlet_round_has_retained_failure "$gauntlet_file" "$sequence_round"; then
        printf '%s\n' "$sequence_strategy" >> "$failed_strategy_history"
      fi
      previous_sequence_round="$sequence_round"
    done < <(find "$sequence_round_dir" -maxdepth 1 -type f -name 'round-*.md' -print \
      | awk '{ name=$0; sub(/^.*\/round-/, "", name); sub(/\.md$/, "", name); if (name ~ /^[0-9]+$/) print (name + 0) "\t" $0 }' \
      | LC_ALL=C sort -n -k1,1)
    rm -f "$failed_strategy_history"
  done < <(find "$gauntlet_dir/rounds" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
fi

if [[ $immutable_evidence_count -gt 0 && "$current_fingerprint" == 'pending' ]]; then
  case "$status" in ready|running) ;; *) echo 'A quality-bar revision reset requires ready or running status.' >&2; exit 1 ;; esac
  while IFS= read -r unit_line; do
    [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]] && continue
    [[ "$unit_line" =~ ^-[[:space:]]\[[[:space:]]\].*\|[[:space:]]status:[[:space:]](pending|building|critic-failed)[[:space:]]\| ]] || {
      echo "Quality-bar reapproval must reopen every active work unit: $unit_line" >&2
      exit 1
    }
  done < <(gauntlet_work_unit_lines "$gauntlet_file")
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pending' \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Critic ID')" \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Isolation')" \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')" \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Quality bar fingerprint')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Unit manifest fingerprint')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Execution contract fingerprint')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Base commit SHA')" == 'pending' ]] || {
      echo 'Quality-bar reapproval must clear the Integration Review.' >&2
      exit 1
    }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'PR eligible')" == 'no' ]] || {
    echo 'Quality-bar reapproval must reset PR eligible to no.' >&2
    exit 1
  }

  [[ "$quality_revision_count" -gt 0 \
    && "$quality_revision_approver" == "$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Approved by')" \
    && "$quality_revision_time" == "$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Approved at')" ]] || {
      echo 'Quality-bar revision approver and timestamp must match the current approval fields.' >&2
      exit 1
    }
  [[ "$live_pr_count" -eq 0 ]] || {
    echo 'Quality-bar reapproval must close every live progress-PR cycle before the new bar can be frozen.' >&2
    exit 1
  }
elif [[ $immutable_evidence_count -gt 0 ]]; then
  [[ "$current_fingerprint" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo 'Current State requires a SHA-256 quality bar fingerprint or a fully documented reapproval reset.' >&2
    exit 1
  }
  [[ "${current_fingerprint,,}" == "${quality_fingerprint,,}" ]] || {
    echo 'Approved Quality Bar changed after it was frozen. To reapprove it, reopen every active unit, clear Integration Review, reset PR eligibility, set the Current State fingerprint to pending, and add the required Unit History revision marker.' >&2
    exit 1
  }
fi

if [[ $immutable_evidence_count -gt 0 && "$current_manifest_fingerprint" == 'pending' ]]; then
  case "$status" in ready|running) ;; *) echo 'A Unit manifest revision reset requires ready or running status.' >&2; exit 1 ;; esac
  [[ "$manifest_revision_count" -gt 0 && "$live_pr_count" -eq 0 \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pending' \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')" \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Unit manifest fingerprint')" == 'pending' \
    && "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'PR eligible')" == 'no' ]] || {
    echo 'Unit manifest revision must close live cycles, clear integration evidence, and reset PR eligibility before refreezing.' >&2
    exit 1
  }
fi

if [[ "$phase" == 'ready' || "$phase" == 'complete' ]]; then
  case "$status" in ready|running|passed) ;; *) echo "Gauntlet status is not execution-ready: $status" >&2; exit 1 ;; esac

  [[ "$issue_url" =~ ^https://github\.com/[^/[:space:]]+/[^/[:space:]]+/issues/[0-9]+/?$ ]] || {
    echo 'Parent Task requires a GitHub issue URL.' >&2
    exit 1
  }
  task_issue="$(gauntlet_extract_section "$task_file" 'Issue' \
    | sed -nE 's#.*(https://github\.com/[^[:space:]]+/[^[:space:]]+/issues/[0-9]+).*#\1#p' \
    | head -n 1 || true)"
  [[ "${issue_url%/}" == "${task_issue%/}" ]] || {
    echo 'Gauntlet issue must match the parent task Issue section.' >&2
    exit 1
  }
  issue_repo="$(gauntlet_github_repo_from_url "$issue_url")"
  gauntlet_assert_github_repository_identity "$issue_repo"
  if [[ "$phase" == 'complete' && "$status" == 'passed' ]]; then
    gauntlet_assert_github_default_branch "$issue_repo" "$base_branch"
  fi
  gauntlet_assert_commit_object "$base_commit_sha" 'Gauntlet frozen base commit SHA'
  base_branch_tip="$(gauntlet_local_branch_sha "$base_branch" 'Gauntlet delivery base branch')"
  integration_branch_tip="$(gauntlet_local_branch_sha "$integration_branch" 'Gauntlet integration branch')"
  gauntlet_assert_commit_ancestor "$base_commit_sha" "$base_branch_tip" 'Frozen base in delivery branch'
  gauntlet_assert_commit_ancestor "$base_commit_sha" "$integration_branch_tip" 'Frozen base in integration branch'
  progress_chain_tip="$(gauntlet_progress_merge_chain_tip "$gauntlet_file")"
  [[ "$integration_branch_tip" == "$progress_chain_tip" ]] || {
    echo "Integration branch contains direct or unrecorded writes beyond the gapless progress-PR merge chain: $integration_branch_tip" >&2
    exit 1
  }
  if [[ "$phase" == 'complete' ]]; then
    gauntlet_assert_remote_integration_tip "$gauntlet_file" "$progress_chain_tip"
  fi
  if [[ "$pr_event_count" -eq 0 ]]; then
    [[ "$progress_chain_tip" == "${base_commit_sha,,}" ]] || {
      echo 'Before first progress evidence, the integration branch must equal the frozen base commit.' >&2
      exit 1
    }
  fi

  # Terminal progress events are re-observed live. This anchors all earlier
  # opened/round/QA evidence to the same immutable GitHub PR identity.
  if [[ -d "$gauntlet_dir/pr-events" ]]; then
    while IFS= read -r terminal_event_file; do
      terminal_action="$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Event')"
      [[ "$terminal_action" == 'merged' || "$terminal_action" == 'closed' ]] || continue
      terminal_pr="$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'PR URL')"
      terminal_head="$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Head branch')"
      terminal_head_sha="$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Head SHA' | tr '[:upper:]' '[:lower:]')"
      terminal_target="$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Target branch')"
      gauntlet_assert_live_pr "$terminal_pr" "$issue_repo" "$terminal_head" "$terminal_head_sha" "$terminal_target" "$terminal_action"
      gauntlet_assert_progress_issue_link "$GAUNTLET_GH_BODY" "$issue_url"
      gauntlet_parse_publication_checkpoint_marker "$GAUNTLET_GH_BODY"
      [[ "$GAUNTLET_GH_BASE_SHA" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Target base SHA' | tr '[:upper:]' '[:lower:]')" \
        && "$GAUNTLET_GH_IS_CROSS_REPOSITORY" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Cross repository')" \
        && "$GAUNTLET_GH_HEAD_REPOSITORY" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Head repository')" \
        && "$GAUNTLET_GH_STATE" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Observed state')" \
        && "$GAUNTLET_GH_IS_DRAFT" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Draft')" \
        && "$GAUNTLET_GH_CREATED_AT" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Created at')" \
        && "$GAUNTLET_GH_CLOSED_AT" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Closed at')" \
        && "$GAUNTLET_GH_MERGED_AT" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Merged at')" \
        && "$GAUNTLET_GH_MERGED_BY" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Merged by')" \
        && "$GAUNTLET_GH_MERGED_BY_TYPE" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Merged by type')" \
        && "$GAUNTLET_GH_MERGED_BY_BOT" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Merged by bot')" \
        && "$GAUNTLET_GH_MERGE_COMMIT" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Merge commit' | tr '[:upper:]' '[:lower:]')" \
        && "$GAUNTLET_PUBLICATION_CHECKPOINT" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Publication checkpoint')" \
        && "$GAUNTLET_PUBLICATION_CHECKPOINT_SHA256" == "$(gauntlet_section_field "$terminal_event_file" 'PR Event Metadata' 'Publication checkpoint sha256')" ]] || {
        echo "Live terminal PR replay differs from immutable evidence: ${terminal_event_file#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}" >&2
        exit 1
      }
    done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' -print | LC_ALL=C sort)
  fi

  # A live progress PR remains mutable on GitHub. Re-observe each active cycle
  # so body edits cannot remove its issue link or swap its frozen checkpoint
  # between immutable events or critic rounds.
  while IFS= read -r live_unit_line; do
    live_item_id="$(printf '%s\n' "$live_unit_line" \
      | sed -nE 's/^- \[[ xX]\] ([a-z0-9]+(-[a-z0-9]+)*) \|.*$/\1/p')"
    [[ -n "$live_item_id" ]] || continue
    gauntlet_load_latest_progress_pr "$gauntlet_dir" "$live_item_id"
    [[ -n "$GAUNTLET_PROGRESS_EVENT_FILE" \
      && "$GAUNTLET_PROGRESS_EVENT" != 'merged' \
      && "$GAUNTLET_PROGRESS_EVENT" != 'closed' ]] || continue
    live_opened_event="$(gauntlet_opened_event_for_pr \
      "$gauntlet_dir" "$live_item_id" "$GAUNTLET_PROGRESS_PR_URL")"
    gauntlet_observe_github_pr "$GAUNTLET_PROGRESS_PR_URL" "$issue_repo"
    [[ "$GAUNTLET_GH_URL" == "$GAUNTLET_PROGRESS_PR_URL" \
      && "$GAUNTLET_GH_HEAD_BRANCH" == "$GAUNTLET_PROGRESS_HEAD_BRANCH" \
      && "$GAUNTLET_GH_BASE_BRANCH" == "$integration_branch" \
      && "$GAUNTLET_GH_STATE" == 'OPEN' \
      && "$GAUNTLET_GH_IS_DRAFT" == 'false' \
      && "$GAUNTLET_GH_CLOSED_AT" == 'none' \
      && "$GAUNTLET_GH_MERGED_AT" == 'none' \
      && "$GAUNTLET_GH_MERGED_BY" == 'none' \
      && "$GAUNTLET_GH_MERGED_BY_TYPE" == 'none' \
      && "$GAUNTLET_GH_MERGED_BY_BOT" == 'none' \
      && "$GAUNTLET_GH_MERGE_COMMIT" == 'none' \
      && "$GAUNTLET_GH_CREATED_AT" == "$(gauntlet_section_field \
        "$live_opened_event" 'PR Event Metadata' 'Created at')" ]] || {
      echo "Live open PR replay differs from immutable cycle identity: $GAUNTLET_PROGRESS_PR_URL" >&2
      exit 1
    }
    gauntlet_assert_progress_publication_body \
      "$GAUNTLET_GH_BODY" "$issue_url" "$live_opened_event"
  done < <(gauntlet_work_unit_lines "$gauntlet_file")

  objective="$(gauntlet_extract_section "$gauntlet_file" 'Objective')"
  gauntlet_has_substance "$objective" || { echo 'Objective must be substantive and contain no placeholders.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Approval')" == 'approved' ]] || { echo 'Quality bar Approval must be approved.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Frozen')" == 'yes' ]] || { echo 'Quality bar Frozen must be yes.' >&2; exit 1; }
  for bar_field in 'Approved by' 'Approved at' 'Benchmark'; do
    field_value="$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' "$bar_field")"
    gauntlet_has_substance "$field_value" || { echo "Quality bar '$bar_field' must be substantive." >&2; exit 1; }
  done
  criteria="$(gauntlet_extract_subsection "$gauntlet_file" 'Approved Quality Bar' 'Criteria')"
  gauntlet_has_substance "$criteria" || { echo 'Approved Quality Bar Criteria must be substantive.' >&2; exit 1; }
  constraints="$(gauntlet_extract_subsection "$gauntlet_file" 'Constraints and Permissions' 'Constraints')"
  permissions="$(gauntlet_extract_subsection "$gauntlet_file" 'Constraints and Permissions' 'Permissions')"
  gauntlet_has_substance "$constraints" || { echo 'Constraints must be substantive.' >&2; exit 1; }
  gauntlet_has_substance "$permissions" || { echo 'Permissions must be substantive.' >&2; exit 1; }

  integration_state_verdict="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')"
  for integration_field in 'Head SHA' 'Scope fingerprint' 'Quality bar fingerprint' \
    'Unit manifest fingerprint' 'Execution contract fingerprint' 'Base commit SHA'; do
    [[ "$(gauntlet_section_field_count "$gauntlet_file" 'Integration Review' "$integration_field")" -eq 1 ]] || {
      echo "Integration Review requires exactly one '$integration_field' field." >&2
      exit 1
    }
  done
  integration_state_head_sha="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')"
  integration_state_scope="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint')"
  integration_state_quality="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Quality bar fingerprint')"
  integration_state_manifest="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Unit manifest fingerprint')"
  integration_state_execution="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Execution contract fingerprint')"
  integration_state_base_sha="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Base commit SHA')"
  if [[ "$integration_state_verdict" == 'pending' ]]; then
    [[ -z "$integration_state_head_sha" && "$integration_state_scope" == 'pending' \
      && "$integration_state_quality" == 'pending' && "$integration_state_manifest" == 'pending' \
      && "$integration_state_execution" == 'pending' && "$integration_state_base_sha" == 'pending' ]] || {
      echo 'Pending Integration Review must clear Head SHA and reset scope, execution-contract, and base fingerprints.' >&2
      exit 1
    }
  else
    gauntlet_validate_head_sha "$integration_state_head_sha" 'Integration Review Head SHA'
    [[ "$integration_state_scope" =~ ^[0-9a-fA-F]{64}$ ]] || {
      echo 'Integration Review requires a valid scope fingerprint.' >&2
      exit 1
    }
    [[ "$integration_state_execution" == "$current_execution_fingerprint" \
      && "$integration_state_quality" =~ ^[0-9a-f]{64}$ \
      && "$integration_state_manifest" =~ ^[0-9a-f]{64}$ \
      && "${integration_state_base_sha,,}" == "${base_commit_sha,,}" ]] || {
      echo 'Integration Review used a stale execution contract or approved base commit.' >&2
      exit 1
    }
  fi

  base_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Base branch')"
  integration_branch="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Integration branch')"
  gauntlet_validate_branch "$base_branch" 'Gauntlet delivery base branch'
  [[ "$base_branch" != 'pending' ]] || { echo 'Gauntlet delivery base branch requires explicit approval before execution.' >&2; exit 1; }
  [[ "$integration_branch" == "gauntlet/$gauntlet_name" ]] || { echo "Gauntlet integration branch must be gauntlet/$gauntlet_name." >&2; exit 1; }
  gauntlet_validate_branch "$integration_branch" 'Gauntlet integration branch'
  [[ "$base_branch" != "$integration_branch" ]] || { echo 'Gauntlet base and integration branches must be distinct.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Progress PR publication')" == 'automatic after approval' ]] || { echo 'Gauntlet progress PR publication must be automatic after approval.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Progress PR QA')" == 'required' ]] || { echo 'Every Gauntlet progress PR must require QA.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Progress PR merge')" == 'human only' ]] || { echo 'Gauntlet progress PR merges must be human only.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Promotion PR readiness confirmation')" == 'human required' ]] || { echo 'Gauntlet promotion PR readiness confirmation must be human required.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Promotion PR')" == 'required' ]] || { echo 'Gauntlet delivery must require a final promotion PR.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Post-promotion QA')" == 'required' ]] || { echo 'Gauntlet delivery must require post-promotion QA.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Auto-merge')" == 'disabled' ]] || { echo 'Gauntlet auto-merge must be disabled.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Merge approval')" == 'human only' ]] || { echo 'Gauntlet merge approval must be human only.' >&2; exit 1; }
  pr_eligible="$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'PR eligible')"
  case "$status" in
    ready|running) [[ "$pr_eligible" == 'no' ]] || { echo 'Ready or running Gauntlets must not be PR eligible.' >&2; exit 1; } ;;
    passed)
      if [[ "$phase" == 'complete' ]]; then
        [[ "$pr_eligible" == 'yes' ]] || { echo 'A completed passed Gauntlet must be PR eligible.' >&2; exit 1; }
      else
        [[ "$pr_eligible" == 'no' || "$pr_eligible" == 'yes' ]] || { echo 'PR eligible must be yes or no.' >&2; exit 1; }
      fi
      ;;
  esac
fi

if [[ "$status" == 'passed' ]]; then
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Latest round')" =~ ^integration/[0-9]{3,}[[:space:]]\(pass\)$ \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pass' ]] || {
    echo 'A passed Gauntlet is immutable outside promotion-QA failure and must end at its passing integration round.' >&2
    exit 1
  }
fi

if [[ "$phase" == 'complete' ]]; then
  [[ "$status" == 'passed' ]] || { echo "Completed Gauntlet status must be passed, found: $status" >&2; exit 1; }
  completion_integration_head="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')"
  gauntlet_validate_head_sha "$completion_integration_head" 'Completed Gauntlet integration Head SHA'
  while IFS= read -r unit_line; do
    [[ "$unit_line" =~ ^-[[:space:]]\[[xX]\][[:space:]]([a-z0-9-]+)[[:space:]]\|[[:space:]]status:[[:space:]](passed|superseded)[[:space:]]\| ]] || {
      echo "Every active work unit must pass before completion: $unit_line" >&2
      exit 1
    }
    item_id="${BASH_REMATCH[1]}"
    unit_status="${BASH_REMATCH[2]}"
    [[ "$unit_status" == 'superseded' ]] && continue
    gauntlet_assert_unit_progress_integrated \
      "$gauntlet_file" "$item_id" "$quality_fingerprint" "$completion_integration_head" || exit 1
  done < <(gauntlet_work_unit_lines "$gauntlet_file")

  integration_verdict="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')"
  integration_evidence="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')"
  [[ "$integration_verdict" == 'pass' ]] || { echo 'Integration Review verdict must be pass.' >&2; exit 1; }
  integration_evidence="${integration_evidence#\`}"
  integration_evidence="${integration_evidence%\`}"
  [[ "$integration_evidence" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/integration/round-[0-9]{3,}\.md$ ]] || {
    echo 'Integration Review evidence path is invalid.' >&2
    exit 1
  }
  [[ -f "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" ]] || { echo 'Integration Review evidence file is missing.' >&2; exit 1; }
  latest_integration_round="$(gauntlet_latest_round_file "$gauntlet_dir/rounds/integration")"
  [[ -n "$latest_integration_round" && "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" == "$latest_integration_round" ]] || {
    echo 'Integration Review must point to the latest integration round.' >&2
    exit 1
  }
  [[ "$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" 'Round Metadata' 'Verdict')" == 'pass' ]] || {
    echo 'Latest Integration Review evidence must pass.' >&2
    exit 1
  }
  [[ "$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" 'Round Metadata' 'Quality bar fingerprint')" == "$quality_fingerprint" ]] || {
    echo 'Latest Integration Review evidence belongs to an older quality-bar revision.' >&2
    exit 1
  }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Quality bar fingerprint')" == "$quality_fingerprint" ]] || {
    echo 'Integration Review used a stale quality bar.' >&2
    exit 1
  }
  integration_head_sha="$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" 'Round Metadata' 'Head SHA')"
  integration_scope_fingerprint="$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" 'Round Metadata' 'Scope fingerprint')"
  current_active_scope="$(gauntlet_active_scope_fingerprint "$gauntlet_file")"
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Head SHA')" == "$integration_head_sha" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Scope fingerprint')" == "$integration_scope_fingerprint" \
    && "$integration_scope_fingerprint" == "$current_active_scope" ]] || {
    echo 'Integration Review used a stale commit or active-unit scope.' >&2
    exit 1
  }
  integration_round_label="$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" 'Round Metadata' 'Round')"
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Latest round')" == "integration/$integration_round_label (pass)" ]] || {
    echo 'A passed Gauntlet cannot retain a work-unit or integration round after its completing integration pass.' >&2
    exit 1
  }
  last_round_ledger_line="$(gauntlet_extract_section "$gauntlet_file" 'Round Ledger' \
    | grep -E '^- .* \| round: ' \
    | tail -n 1)"
  [[ "$last_round_ledger_line" == "- integration | round: $integration_round_label |"* \
    && "$last_round_ledger_line" == *" | evidence: $integration_evidence |"* ]] || {
    echo 'The completing integration pass must be the final immutable Round Ledger entry for a passed Gauntlet.' >&2
    exit 1
  }
  integration_recorded_at="$(gauntlet_section_field "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" 'Round Metadata' 'Recorded at')"
  while IFS= read -r retained_round; do
    [[ "$retained_round" == "$OPENCAW_PROJECT_ROOT_RESOLVED/$integration_evidence" ]] && continue
    retained_round_time="$(gauntlet_section_field "$retained_round" 'Round Metadata' 'Recorded at')"
    [[ "$retained_round_time" < "$integration_recorded_at" || "$retained_round_time" == "$integration_recorded_at" ]] || {
      echo "A passed Gauntlet contains a round recorded after its completing integration pass: ${retained_round#"$OPENCAW_PROJECT_ROOT_RESOLVED"/}" >&2
      exit 1
    }
  done < <(find "$gauntlet_dir/rounds" -type f -name 'round-*.md' -print | LC_ALL=C sort)
fi

rm -f "$seen_units" "$critics_seen" "$builders_seen" "$historical_bars" \
  "$historical_manifests" "$round_ledger_paths" \
  "$pr_urls_seen" "$qa_rounds_seen" "$qa_comment_evidence_seen" "$pr_ledger_paths" \
  "$remediation_trigger_records" "$remediation_triggers_seen" \
  "$publication_checkpoints_seen" \
  "$promotion_ledger_paths" "$promotion_archive_paths" \
  "$promotion_completion_states" "$promotion_affected_values" \
  "$completion_ledger_paths" "$completion_consumed_paths" \
  "$evidence_timeline" "$approved_manifest_rows" "$approved_quality_rows" \
  "$manifest_revision_ids" "$quality_revision_ids" "$supersession_markers_seen" \
  "$scope_revision_markers_seen"
trap - EXIT
echo "GAUNTLET_FILE=$gauntlet_file"
echo "GAUNTLET_NAME=$gauntlet_name"
echo "GAUNTLET_STATUS=$status"
echo "QUALITY_BAR_FINGERPRINT=$quality_fingerprint"
echo "VALIDATION_PHASE=$phase"
echo 'VALID=true'
