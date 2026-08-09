#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-gauntlet-file.sh "<name>" ["Title"] --task "<task-name>" [--dry-run]

Creates <project-root>/.ai/gauntlets/<name>/GAUNTLET.md linked to an existing
parent task. The command copies the task's GitHub issue URL when one is present.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/gauntlet-common.sh"
source "$script_dir/lib/brainstorm-common.sh"

gauntlet_name=''
title=''
task_name=''
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      task_name="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
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
      if [[ -z "$gauntlet_name" ]]; then
        gauntlet_name="$1"
      elif [[ -z "$title" ]]; then
        title="$1"
      else
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

[[ -n "$gauntlet_name" && -n "$task_name" ]] || {
  usage >&2
  exit 1
}
gauntlet_validate_name "$gauntlet_name" 'name'
gauntlet_validate_name "$task_name" 'task-name'

if [[ -z "$title" ]]; then
  title="$gauntlet_name"
fi
opencaw_validate_single_line "$title" 'Title'

if [[ $dry_run -eq 0 ]]; then
  brainstorm_require_delivery_creation_allowed 'Gauntlet creation'
fi

task_file="$OPENCAW_PROJECT_AI_DIR/tasks/$task_name/TASK.md"
gauntlet_assert_safe_ai_path "$OPENCAW_PROJECT_AI_DIR/tasks" 'Task root'
gauntlet_assert_safe_ai_path "$OPENCAW_PROJECT_AI_DIR/tasks/$task_name" 'Parent task directory'
[[ -f "$task_file" && ! -L "$task_file" ]] || {
  echo "Parent task file not found: $task_file" >&2
  exit 1
}

issue_url="$(gauntlet_extract_section "$task_file" 'Issue' \
  | sed -nE 's#.*(https://github\.com/[^[:space:]]+/[^[:space:]]+/issues/[0-9]+).*#\1#p' \
  | head -n 1 || true)"

gauntlet_dir="$OPENCAW_GAUNTLETS_DIR/$gauntlet_name"
target="$gauntlet_dir/GAUNTLET.md"
if [[ -e "$OPENCAW_GAUNTLETS_DIR" ]]; then
  gauntlet_assert_safe_ai_path "$OPENCAW_GAUNTLETS_DIR" 'Gauntlet root'
fi
if [[ -e "$gauntlet_dir" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir" 'Gauntlet directory'
fi
if [[ -e "$gauntlet_dir/rounds" || -L "$gauntlet_dir/rounds" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/rounds" 'Gauntlet rounds directory'
fi
if [[ -e "$gauntlet_dir/pr-events" || -L "$gauntlet_dir/pr-events" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/pr-events" 'Gauntlet PR events directory'
fi
if [[ -e "$gauntlet_dir/promotion-events" || -L "$gauntlet_dir/promotion-events" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/promotion-events" 'Gauntlet promotion events directory'
fi
if [[ -e "$gauntlet_dir/completion-events" || -L "$gauntlet_dir/completion-events" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/completion-events" 'Gauntlet completion events directory'
fi
if [[ -e "$gauntlet_dir/publication-checkpoints" || -L "$gauntlet_dir/publication-checkpoints" ]]; then
  gauntlet_assert_safe_ai_path "$gauntlet_dir/publication-checkpoints" 'Gauntlet publication checkpoints directory'
fi

write_gauntlet() {
  cat <<EOF
# $title

## Flow and Status
- Type: gauntlet
- Status: planning

## Parent Task
- Task name: $task_name
- Task file: \`.ai/tasks/$task_name/TASK.md\`
- Issue: $issue_url

## Objective

## Approved Quality Bar
- Approval: pending
- Approved by:
- Approved at:
- Frozen: no
- Benchmark:

### Criteria
- TODO: Define inspectable pass criteria.

## Constraints and Permissions

### Constraints
- TODO: Define constraints and guardrails.

### Permissions
- TODO: Define allowed tools, writes, and external actions.

## Work Units
- [ ] unit-1 | status: pending | title: Describe an independently judgeable unit | scope: Define inspectable artifact and acceptance boundary

### Unit History
- No unit changes recorded.

## Current State
- Active work unit: none
- Latest round: none
- Quality bar fingerprint: pending
- Unit manifest fingerprint: pending
- Execution contract fingerprint: pending
- Next action: Approve and freeze the quality bar before building.

## Round Ledger
- No rounds recorded.

## Progress PR Ledger
- No progress PR events recorded.

## Promotion QA Ledger
- No promotion QA events recorded.

## Completion Ledger
- No completion events recorded.

## Integration Review
- Verdict: pending
- Critic ID:
- Isolation:
- Evidence:
- Head SHA:
- Scope fingerprint: pending
- Quality bar fingerprint: pending
- Unit manifest fingerprint: pending
- Execution contract fingerprint: pending
- Base commit SHA: pending

## Delivery
- Base branch: pending
- Base commit SHA: pending
- Integration branch: gauntlet/$gauntlet_name
- Progress PR publication: automatic after approval
- Progress PR QA: required
- Progress PR merge: human only
- Promotion PR readiness confirmation: human required
- Promotion PR: required
- Post-promotion QA: required
- Auto-merge: disabled
- Merge approval: human only
- PR eligible: no
- Promotion PR URL:

## Review Notes
EOF
}

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $target"
  echo
  write_gauntlet
  exit 0
fi

mkdir -p "$OPENCAW_GAUNTLETS_DIR"
if [[ ! -d "$gauntlet_dir" ]]; then
  mkdir "$gauntlet_dir" 2>/dev/null || true
fi
[[ ! -L "$target" ]] || {
  echo "Gauntlet file must not be a symbolic link: $target" >&2
  exit 1
}
if [[ -f "$target" ]]; then
  echo "$target already exists"
  exit 0
fi

gauntlet_acquire_lock "$gauntlet_dir"
trap 'gauntlet_release_lock' EXIT
[[ ! -e "$target" && ! -L "$target" ]] || {
  echo "$target already exists"
  exit 0
}
mkdir -p "$gauntlet_dir/rounds" "$gauntlet_dir/pr-events" "$gauntlet_dir/promotion-events" \
  "$gauntlet_dir/completion-events" "$gauntlet_dir/publication-checkpoints"
gauntlet_assert_safe_ai_path "$gauntlet_dir/rounds" 'Gauntlet rounds directory'
gauntlet_assert_safe_ai_path "$gauntlet_dir/pr-events" 'Gauntlet PR events directory'
gauntlet_assert_safe_ai_path "$gauntlet_dir/promotion-events" 'Gauntlet promotion events directory'
gauntlet_assert_safe_ai_path "$gauntlet_dir/completion-events" 'Gauntlet completion events directory'
gauntlet_assert_safe_ai_path "$gauntlet_dir/publication-checkpoints" 'Gauntlet publication checkpoints directory'

temporary="$(mktemp "$gauntlet_dir/.GAUNTLET.md.XXXXXX")"
trap 'rm -f "$temporary"; gauntlet_release_lock' EXIT
write_gauntlet > "$temporary"
chmod 0644 "$temporary"
gauntlet_install_no_clobber "$temporary" "$target"
gauntlet_release_lock
trap - EXIT
echo "Created $target"
