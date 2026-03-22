#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-task-issue.sh "<task_name>" ["Issue Title"] [issue_body_file]
EOF
}

task_name="${1:-}"
issue_title="${2:-}"
issue_body_file="${3:-}"

if [[ -z "$task_name" ]]; then
  usage >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
host_tasks_dir="$host_root/.ai/tasks"
task_file="$host_tasks_dir/$task_name/TASK.md"
open_issues_file="$host_tasks_dir/OPEN_ISSUES.md"

resolve_gh() {
  if command -v gh >/dev/null 2>&1; then
    GH_BIN="$(command -v gh)"
    return
  fi

  if command -v gh.exe >/dev/null 2>&1; then
    GH_BIN="$(command -v gh.exe)"
    return
  fi

  echo "GitHub CLI (gh) is required to create task issues." >&2
  exit 1
}

detect_repo_root() {
  if git -C "$host_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$host_root"
    return
  fi

  if git -C "$opencaw_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$opencaw_root"
    return
  fi

  echo "Unable to detect a git repository root for issue creation." >&2
  exit 1
}

extract_issue_url() {
  local source_file="$1"
  if [[ ! -f "$source_file" ]]; then
    return 0
  fi

  grep -Eo 'https://github\.com/[^[:space:]]+/[^[:space:]]+/issues/[0-9]+' "$source_file" | head -n1 || true
}

add_open_issue_url() {
  local issue_url="$1"
  mkdir -p "$host_tasks_dir"
  touch "$open_issues_file"

  if ! grep -Fxq "$issue_url" "$open_issues_file"; then
    printf '%s\n' "$issue_url" >> "$open_issues_file"
  fi
}

upsert_issue_section() {
  local issue_url="$1"

  if [[ ! -f "$task_file" ]]; then
    return 0
  fi

  if grep -Fq "$issue_url" "$task_file"; then
    return 0
  fi

  if ! grep -q '^## Issue$' "$task_file"; then
    printf '\n## Issue\n\n%s\n' "$issue_url" >> "$task_file"
    return 0
  fi

  printf '%s\n' "$issue_url" >> "$task_file"
}

if [[ -z "$issue_title" ]]; then
  issue_title="Task: $task_name"
fi

existing_issue_url="$(extract_issue_url "$task_file")"
if [[ -n "$existing_issue_url" ]]; then
  add_open_issue_url "$existing_issue_url"
  echo "$existing_issue_url"
  exit 0
fi

resolve_gh
repo_root="$(detect_repo_root)"

if [[ -n "$issue_body_file" ]]; then
  if [[ ! -f "$issue_body_file" ]]; then
    echo "Issue body file not found: $issue_body_file" >&2
    exit 1
  fi
  issue_body="$(cat "$issue_body_file")"
else
  issue_body="$(cat <<EOF
OpenCaw task issue for \`$task_name\`.

Task file:
\`$task_file\`

Use this issue as the canonical tracker for planning, implementation updates, QA evidence, and closure.
EOF
)"
fi

pushd "$repo_root" >/dev/null
issue_url="$("$GH_BIN" issue create --title "$issue_title" --body "$issue_body")"
popd >/dev/null

add_open_issue_url "$issue_url"
upsert_issue_section "$issue_url"

echo "$issue_url"
