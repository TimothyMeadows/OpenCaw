#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/import-task-from-issue.sh "<issue_url_or_number_or_#number>" [task_name]

Examples:
  ./commands/import-task-from-issue.sh "#123"
  ./commands/import-task-from-issue.sh "123"
  ./commands/import-task-from-issue.sh "https://github.com/org/repo/issues/123"
  ./commands/import-task-from-issue.sh "#123" "implement-auth-timeout"
EOF
}

issue_ref="${1:-}"
task_name_input="${2:-}"

if [[ "$issue_ref" == "-h" || "$issue_ref" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$issue_ref" ]]; then
  usage >&2
  exit 1
fi

resolve_gh() {
  if command -v gh >/dev/null 2>&1; then
    GH_BIN="$(command -v gh)"
    return
  fi

  if command -v gh.exe >/dev/null 2>&1; then
    GH_BIN="$(command -v gh.exe)"
    return
  fi

  echo "GitHub CLI (gh) is required to import issue tasks." >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
host_tasks_dir="$host_root/.ai/tasks"
open_issues_file="$host_tasks_dir/OPEN_ISSUES.md"

detect_repo_root() {
  if git -C "$host_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$host_root"
    return
  fi

  if git -C "$opencaw_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$opencaw_root"
    return
  fi

  echo "Unable to detect a git repository root for issue import." >&2
  exit 1
}

normalize_task_name() {
  local value="$1"
  value="${value//$'\r'/}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf '%s' "$value"
}

add_open_issue_url() {
  local issue_url="$1"

  mkdir -p "$host_tasks_dir"
  touch "$open_issues_file"

  if ! grep -Fxq "$issue_url" "$open_issues_file"; then
    printf '%s\n' "$issue_url" >> "$open_issues_file"
  fi
}

remove_open_issue_url() {
  local issue_url="$1"
  local tmp

  [[ -f "$open_issues_file" ]] || return 0

  tmp="$(mktemp)"
  awk -v url="$issue_url" '$0 != url { print }' "$open_issues_file" > "$tmp"
  mv "$tmp" "$open_issues_file"
}

find_task_for_issue_url() {
  local issue_url="$1"
  local task_md

  [[ -d "$host_tasks_dir" ]] || return 1

  while IFS= read -r -d '' task_md; do
    if grep -Fq "$issue_url" "$task_md"; then
      printf '%s\n' "$task_md"
      return 0
    fi
  done < <(find "$host_tasks_dir" -mindepth 2 -maxdepth 2 -name TASK.md -print0)

  return 1
}

upsert_issue_section() {
  local task_file="$1"
  local issue_url="$2"

  [[ -f "$task_file" ]] || return 0

  if grep -Fq "$issue_url" "$task_file"; then
    return 0
  fi

  if ! grep -q '^## Issue$' "$task_file"; then
    printf '\n## Issue\n\n%s\n' "$issue_url" >> "$task_file"
    return 0
  fi

  printf '%s\n' "$issue_url" >> "$task_file"
}

resolve_gh
repo_root="$(detect_repo_root)"

pushd "$repo_root" >/dev/null
issue_number="$($GH_BIN issue view "$issue_ref" --json number --jq .number 2>/dev/null || true)"
if [[ -z "$issue_number" ]]; then
  popd >/dev/null
  echo "Unable to resolve GitHub issue from: $issue_ref" >&2
  exit 1
fi

issue_title="$($GH_BIN issue view "$issue_ref" --json title --jq .title)"
issue_body="$($GH_BIN issue view "$issue_ref" --json body --jq .body)"
issue_url="$($GH_BIN issue view "$issue_ref" --json url --jq .url)"
issue_state="$($GH_BIN issue view "$issue_ref" --json state --jq .state)"
popd >/dev/null

existing_task_file="$(find_task_for_issue_url "$issue_url" || true)"
if [[ -n "$existing_task_file" ]]; then
  if [[ "$issue_state" == "OPEN" ]]; then
    add_open_issue_url "$issue_url"
  else
    remove_open_issue_url "$issue_url"
  fi

  echo "Issue already linked: $existing_task_file"
  echo "$existing_task_file"
  exit 0
fi

if [[ -n "$task_name_input" ]]; then
  task_name="$(normalize_task_name "$task_name_input")"
else
  title_slug="$(normalize_task_name "$issue_title")"
  if [[ -n "$title_slug" ]]; then
    task_name="issue-${issue_number}-${title_slug}"
  else
    task_name="issue-${issue_number}"
  fi
fi

if [[ -z "$task_name" ]]; then
  echo "Could not derive a valid task name from input/issue title." >&2
  exit 1
fi

task_dir="$host_tasks_dir/$task_name"
task_file="$task_dir/TASK.md"
created=0

mkdir -p "$task_dir"

trimmed_issue_body="$(printf '%s' "$issue_body" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
if [[ -z "$trimmed_issue_body" ]]; then
  issue_body="_No issue body provided in GitHub issue._"
fi

if [[ ! -f "$task_file" ]]; then
  cat > "$task_file" <<EOF
# $issue_title

## Goal
Implement GitHub issue #$issue_number.

## Scope
- Imported from GitHub issue #$issue_number
- Issue URL: $issue_url
- Issue state at import: $issue_state

## Assumptions

## Work Instructions
$issue_body

## Verification

## Review

## Issue
$issue_url
EOF
  created=1
else
  upsert_issue_section "$task_file" "$issue_url"
fi

if [[ "$issue_state" == "OPEN" ]]; then
  add_open_issue_url "$issue_url"
else
  remove_open_issue_url "$issue_url"
fi

if [[ $created -eq 1 ]]; then
  echo "Imported issue #$issue_number into $task_file"
else
  echo "Linked issue #$issue_number to existing task file: $task_file"
fi

echo "$task_file"
