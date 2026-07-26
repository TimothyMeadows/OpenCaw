#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths

todo_file="$OPENCAW_PROJECT_AI_DIR/tasks/TODO.md"
report_dir="$OPENCAW_PROJECT_AI_DIR/reports"
dry_run='false'

usage() {
  cat <<USAGE
Usage: ./commands/clean-context.sh [--dry-run]

Options:
  --dry-run  Print what would change without writing files.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run='true'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$report_dir"

archived_task_count=0
archived_task_names=''

if [[ -f "$todo_file" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^[0-9]+\.[[:space:]]+\[x\][[:space:]].*\`(\.\./)?\.ai/tasks/([^/]+)/TASK\.md\` ]]; then
      task_name="${BASH_REMATCH[2]}"
      task_file="$OPENCAW_PROJECT_AI_DIR/tasks/$task_name/TASK.md"

      if [[ -f "$task_file" ]]; then
        if grep -Eq '^Archived on [0-9]{8}T[0-9]{6}Z\.$' "$task_file"; then
          continue
        fi

        if [[ "$dry_run" == 'true' ]]; then
          echo "DRY_RUN archive task context: $task_name"
          archived_task_count=$((archived_task_count + 1))
          archived_task_names+="- $task_name\n"
        else
          archive_output="$(OPENCAW_PROJECT_ROOT="$OPENCAW_PROJECT_ROOT_RESOLVED" "${script_dir}/archive-task-context.sh" "$task_name")"
          if ! printf '%s\n' "$archive_output" | grep -q '^ALREADY_ARCHIVED=true$'; then
            archived_task_count=$((archived_task_count + 1))
            archived_task_names+="- $task_name\n"
          fi
        fi
      fi
    fi
  done < "$todo_file"
fi

memory_merged=0
system_memory_merged=0
repo_map_merged=0
rules_removed=0
debug_compressed=0
summary_file='(dry-run)'
snapshot_dir='(dry-run)'

if [[ "$dry_run" == 'false' ]]; then
  summarize_output="$("${script_dir}/summarize-memory.sh")"
  system_memory_merged="$(printf '%s\n' "$summarize_output" | awk -F= '/^SYSTEM_MEMORY_DUPLICATES_MERGED=/{print $2; exit}')"
  memory_merged="$(printf '%s\n' "$summarize_output" | awk -F= '/^MEMORY_DUPLICATES_MERGED=/{print $2; exit}')"
  repo_map_merged="$(printf '%s\n' "$summarize_output" | awk -F= '/^REPO_MAP_DUPLICATES_MERGED=/{print $2; exit}')"
  rules_removed="$(printf '%s\n' "$summarize_output" | awk -F= '/^RULE_DUPLICATES_REMOVED=/{print $2; exit}')"
  debug_compressed="$(printf '%s\n' "$summarize_output" | awk -F= '/^DEBUG_NOTES_COMPRESSED=/{print $2; exit}')"
  summary_file="$(printf '%s\n' "$summarize_output" | awk -F= '/^SUMMARY_FILE=/{print $2; exit}')"
  snapshot_dir="$(printf '%s\n' "$summarize_output" | awk -F= '/^SNAPSHOT_DIR=/{print $2; exit}')"
fi

report_file="$report_dir/clean-context-report-$(date -u '+%Y%m%dT%H%M%SZ').md"

if [[ "$dry_run" == 'false' ]]; then
  cat > "$report_file" <<EOF
# Clean Context Report

Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

## Task Files Compacted
- Task files compacted: $archived_task_count

### Compacted Tasks
${archived_task_names:-- none}

## Memory Cleanup
- System-memory entries merged: $system_memory_merged
- Memory entries merged: $memory_merged
- Repository-map entries merged: $repo_map_merged
- Duplicate rules removed: $rules_removed
- Debug notes compressed: $debug_compressed

## Refreshed Summary
- $summary_file

## Traceability
- Snapshot directory: $snapshot_dir
EOF
fi

echo "TASK_FILES_COMPACTED=$archived_task_count"
echo "SYSTEM_MEMORY_ENTRIES_MERGED=$system_memory_merged"
echo "MEMORY_ENTRIES_MERGED=$memory_merged"
echo "REPO_MAP_ENTRIES_MERGED=$repo_map_merged"
echo "DUPLICATE_RULES_REMOVED=$rules_removed"
echo "DEBUG_NOTES_COMPRESSED=$debug_compressed"
echo "CONTEXT_SUMMARY_REFRESHED=$summary_file"
echo "REPORT_FILE=$report_file"
