#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-gauntlet.sh "<name|path>" [--phase ready|complete]

Validates the Gauntlet contract. The ready phase enforces an approved and frozen
quality bar; complete additionally requires every active unit and integration
review to have immutable passing evidence.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"

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
  if [[ ! "$unit_line" =~ ^-[[:space:]]\[([[:space:]xX])\][[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]status:[[:space:]](pending|building|critic-failed|passed|blocked|superseded)[[:space:]]\|[[:space:]]title:[[:space:]](.+)$ ]]; then
    echo "Invalid work-unit entry: $unit_line" >&2
    exit 1
  fi
  checkbox="${BASH_REMATCH[1]}"
  item_id="${BASH_REMATCH[2]}"
  unit_status="${BASH_REMATCH[4]}"
  unit_title="${BASH_REMATCH[5]}"
  if grep -Fqx -- "$item_id" "$seen_units"; then
    echo "Duplicate work-unit id: $item_id" >&2
    exit 1
  fi
  [[ "$item_id" != 'integration' ]] || { echo "Work-unit id is reserved: integration" >&2; exit 1; }
  printf '%s\n' "$item_id" >> "$seen_units"
  gauntlet_has_substance "$unit_title" || { echo "Work-unit title is a placeholder: $item_id" >&2; exit 1; }
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

current_fingerprint="$(gauntlet_section_field "$gauntlet_file" 'Current State' 'Quality bar fingerprint')"
quality_fingerprint="$(gauntlet_quality_bar_fingerprint "$gauntlet_file")"

round_count=0
critics_seen="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-critics.XXXXXX")"
historical_bars="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-bars.XXXXXX")"
trap 'rm -f "$seen_units" "$critics_seen" "$historical_bars"' EXIT
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
    round_number="${BASH_REMATCH[1]}"
    metadata_item="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Item')"
    metadata_round="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Round')"
    metadata_verdict="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Verdict')"
    builder_id="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Builder ID')"
    critic_id="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Critic ID')"
    isolation="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Isolation')"
    metadata_bar="$(gauntlet_section_field "$round_file" 'Round Metadata' 'Quality bar fingerprint')"
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
    [[ -n "$builder_id" && -n "$critic_id" && "$builder_id" != "$critic_id" ]] || {
      echo "Round builder and critic must be distinct: $relative_round" >&2
      exit 1
    }
    if grep -Fqx -- "$critic_id" "$critics_seen"; then
      echo "Critic invocation was reused: $critic_id" >&2
      exit 1
    fi
    printf '%s\n' "$critic_id" >> "$critics_seen"
    [[ "$metadata_bar" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "Round has an invalid quality bar fingerprint: $relative_round" >&2; exit 1; }
    printf '%s\n' "${metadata_bar,,}" >> "$historical_bars"
    gauntlet_validate_critic_report "$round_file" "$metadata_verdict" || exit 1
    evidence_hash="$(gauntlet_hash_file "$round_file")"
    if ! grep -Fq -- "evidence: $relative_round | sha256: $evidence_hash" "$gauntlet_file"; then
      echo "Round evidence hash is missing or stale in the ledger: $relative_round" >&2
      exit 1
    fi
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
while IFS= read -r ledger_line; do
  [[ -n "$ledger_line" ]] || continue
  ledger_count=$((ledger_count + 1))
  ledger_evidence="$(printf '%s\n' "$ledger_line" | sed -nE 's#^.* \| evidence: ([^|]+) \| sha256: [0-9a-fA-F]{64}[[:space:]]*$#\1#p' | sed -E 's/[[:space:]]+$//')"
  [[ -n "$ledger_evidence" ]] || { echo "Invalid Round Ledger entry: $ledger_line" >&2; exit 1; }
  [[ "$ledger_evidence" == .ai/gauntlets/"$gauntlet_name"/rounds/*/round-*.md ]] || {
    echo "Round Ledger evidence path is outside this Gauntlet: $ledger_evidence" >&2
    exit 1
  }
  [[ -f "$OPENCAW_PROJECT_ROOT_RESOLVED/$ledger_evidence" ]] || {
    echo "Round Ledger references missing evidence: $ledger_evidence" >&2
    exit 1
  }
done < <(gauntlet_extract_section "$gauntlet_file" 'Round Ledger' | grep -E '^- .* \| round: ' || true)
[[ $ledger_count -eq $round_count ]] || {
  echo "Round Ledger count ($ledger_count) does not match immutable round evidence count ($round_count)." >&2
  exit 1
}

if [[ $round_count -gt 0 && "$current_fingerprint" == 'pending' ]]; then
  case "$status" in ready|running) ;; *) echo 'A quality-bar revision reset requires ready or running status.' >&2; exit 1 ;; esac
  while IFS= read -r unit_line; do
    [[ "$unit_line" =~ \|[[:space:]]status:[[:space:]]superseded[[:space:]]\| ]] && continue
    [[ "$unit_line" =~ ^-[[:space:]]\[[[:space:]]\].*\|[[:space:]]status:[[:space:]](pending|critic-failed)[[:space:]]\| ]] || {
      echo "Quality-bar reapproval must reopen every active work unit: $unit_line" >&2
      exit 1
    }
  done < <(gauntlet_work_unit_lines "$gauntlet_file")
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')" == 'pending' \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Critic ID')" \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Isolation')" \
    && -z "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')" \
    && "$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Quality bar fingerprint')" == 'pending' ]] || {
      echo 'Quality-bar reapproval must clear the Integration Review.' >&2
      exit 1
    }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'PR eligible')" == 'no' ]] || {
    echo 'Quality-bar reapproval must reset PR eligible to no.' >&2
    exit 1
  }

  revision_line="$(gauntlet_extract_subsection "$gauntlet_file" 'Work Units' 'Unit History' \
    | grep -E '^- Quality bar revision:' | tail -n 1 || true)"
  if [[ ! "$revision_line" =~ ^-[[:space:]]Quality[[:space:]]bar[[:space:]]revision:[[:space:]]([a-z0-9]+(-[a-z0-9]+)*)[[:space:]]\|[[:space:]]approved[[:space:]]by:[[:space:]](.+)[[:space:]]\|[[:space:]]approved[[:space:]]at:[[:space:]]([^|]+)[[:space:]]\|[[:space:]]supersedes:[[:space:]]([0-9a-fA-F]{64})[[:space:]]\|[[:space:]]reason:[[:space:]](.+)$ ]]; then
    echo 'Quality-bar reapproval requires a Unit History marker: - Quality bar revision: <kebab-id> | approved by: <identity> | approved at: <timestamp> | supersedes: <old-fingerprint> | reason: <text>' >&2
    exit 1
  fi
  revision_approver="$(gauntlet_trim "${BASH_REMATCH[3]}")"
  revision_time="$(gauntlet_trim "${BASH_REMATCH[4]}")"
  revision_supersedes="${BASH_REMATCH[5],,}"
  revision_reason="$(gauntlet_trim "${BASH_REMATCH[6]}")"
  [[ "$revision_approver" == "$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Approved by')" \
    && "$revision_time" == "$(gauntlet_section_field "$gauntlet_file" 'Approved Quality Bar' 'Approved at')" ]] || {
      echo 'Quality-bar revision approver and timestamp must match the current approval fields.' >&2
      exit 1
    }
  grep -Fqx -- "$revision_supersedes" "$historical_bars" || {
    echo 'Quality-bar revision supersedes fingerprint does not match historical round evidence.' >&2
    exit 1
  }
  gauntlet_has_substance "$revision_reason" || { echo 'Quality-bar revision reason must be substantive.' >&2; exit 1; }
elif [[ $round_count -gt 0 ]]; then
  [[ "$current_fingerprint" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo 'Current State requires a SHA-256 quality bar fingerprint or a fully documented reapproval reset.' >&2
    exit 1
  }
  [[ "${current_fingerprint,,}" == "${quality_fingerprint,,}" ]] || {
    echo 'Approved Quality Bar changed after it was frozen. To reapprove it, reopen every active unit, clear Integration Review, reset PR eligibility, set the Current State fingerprint to pending, and add the required Unit History revision marker.' >&2
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

  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'PR readiness confirmation')" == 'human required' ]] || { echo 'Gauntlet PR readiness confirmation must be human required.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'One final PR')" == 'required' ]] || { echo 'Gauntlet delivery must require one final PR.' >&2; exit 1; }
  [[ "$(gauntlet_section_field "$gauntlet_file" 'Delivery' 'Post-PR QA')" == 'required' ]] || { echo 'Gauntlet delivery must require post-PR QA.' >&2; exit 1; }
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

if [[ "$phase" == 'complete' ]]; then
  [[ "$status" == 'passed' ]] || { echo "Completed Gauntlet status must be passed, found: $status" >&2; exit 1; }
  while IFS= read -r unit_line; do
    [[ "$unit_line" =~ ^-[[:space:]]\[[xX]\][[:space:]]([a-z0-9-]+)[[:space:]]\|[[:space:]]status:[[:space:]](passed|superseded)[[:space:]]\| ]] || {
      echo "Every active work unit must pass before completion: $unit_line" >&2
      exit 1
    }
    item_id="${BASH_REMATCH[1]}"
    unit_status="${BASH_REMATCH[2]}"
    [[ "$unit_status" == 'superseded' ]] && continue
    latest_round="$(gauntlet_latest_round_file "$gauntlet_dir/rounds/$item_id")"
    [[ -n "$latest_round" \
      && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Verdict')" == 'pass' \
      && "$(gauntlet_section_field "$latest_round" 'Round Metadata' 'Quality bar fingerprint')" == "$quality_fingerprint" ]] || {
      echo "Work unit lacks a latest passing critic round: $item_id" >&2
      exit 1
    }
  done < <(gauntlet_work_unit_lines "$gauntlet_file")

  integration_verdict="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Verdict')"
  integration_evidence="$(gauntlet_section_field "$gauntlet_file" 'Integration Review' 'Evidence')"
  [[ "$integration_verdict" == 'pass' ]] || { echo 'Integration Review verdict must be pass.' >&2; exit 1; }
  integration_evidence="${integration_evidence#\`}"
  integration_evidence="${integration_evidence%\`}"
  [[ "$integration_evidence" == .ai/gauntlets/"$gauntlet_name"/rounds/integration/round-*.md ]] || {
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
fi

rm -f "$seen_units" "$critics_seen" "$historical_bars"
trap - EXIT
echo "GAUNTLET_FILE=$gauntlet_file"
echo "GAUNTLET_NAME=$gauntlet_name"
echo "GAUNTLET_STATUS=$status"
echo "QUALITY_BAR_FINGERPRINT=$quality_fingerprint"
echo "VALIDATION_PHASE=$phase"
echo 'VALID=true'
