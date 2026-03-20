#!/usr/bin/env bash
set -euo pipefail

task_ref="${1:-}"

if [[ -z "$task_ref" ]]; then
  echo 'Usage: ./commands/archive-task-context.sh "<task-name|../.ai/tasks/<task-name>/TASK.md>"' >&2
  exit 1
fi

if [[ "$task_ref" == */TASK.md ]]; then
  task_file="$task_ref"
elif [[ "$task_ref" == *.md ]]; then
  task_file="$task_ref"
else
  task_file="../.ai/tasks/$task_ref/TASK.md"
fi

if [[ "$task_file" != ../.ai/tasks/*/TASK.md && "$task_file" != ./.ai/tasks/*/TASK.md && "$task_file" != .ai/tasks/*/TASK.md && "$task_file" != */.ai/tasks/*/TASK.md ]]; then
  echo "Task file must be under .ai/tasks: $task_file" >&2
  exit 1
fi

if [[ ! -f "$task_file" ]]; then
  echo "Task file not found: $task_file" >&2
  exit 1
fi

task_name="$(basename "$(dirname "$task_file")")"

if grep -Eq '^Archived on [0-9]{8}T[0-9]{6}Z\.$' "$task_file"; then
  echo "ARCHIVED_TASK=$task_name"
  echo 'ALREADY_ARCHIVED=true'
  echo "TASK_FILE_COMPRESSED=$task_file"
  exit 0
fi

archive_dir="../.ai/archive/tasks"
mkdir -p "$archive_dir"

timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
archive_file="$archive_dir/${task_name}-${timestamp}.md"
cp "$task_file" "$archive_file"

extract_first_line_in_section() {
  local file="$1"
  local section="$2"

  awk -v section="$section" '
    BEGIN { in_section = 0 }
    {
      line = $0
      sub(/\r$/, "", line)

      if (line ~ "^##[[:space:]]+" section "[[:space:]]*$") {
        in_section = 1
        next
      }

      if (in_section && line ~ "^##[[:space:]]+") {
        exit
      }

      if (in_section) {
        candidate = line
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", candidate)
        sub(/^-+[[:space:]]*/, "", candidate)

        if (candidate != "") {
          print candidate
          exit
        }
      }
    }
  ' "$file"
}

extract_title() {
  local file="$1"

  awk '
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^#[[:space:]]+/) {
        sub(/^#[[:space:]]+/, "", line)
        print line
        exit
      }
    }
  ' "$file"
}

title="$(extract_title "$archive_file")"
if [[ -z "$title" ]]; then
  title="$task_name"
fi

goal_line="$(extract_first_line_in_section "$archive_file" 'Goal')"
if [[ -z "$goal_line" ]]; then
  goal_line='See archived task details.'
fi

review_line="$(extract_first_line_in_section "$archive_file" 'Review')"
if [[ -z "$review_line" ]]; then
  review_line='No explicit review summary found in source note.'
fi

cat > "$task_file" <<EOF
# $title

## Status
Archived on $timestamp.

## Archive
- $archive_file

## Durable Summary
- Goal: $goal_line
- Review: $review_line
EOF

echo "ARCHIVED_TASK=$task_name"
echo "ARCHIVE_FILE=$archive_file"
echo "TASK_FILE_COMPRESSED=$task_file"
