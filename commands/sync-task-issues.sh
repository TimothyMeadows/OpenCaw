#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
host_tasks_dir="$host_root/.ai/tasks"
open_issues_file="$host_tasks_dir/OPEN_ISSUES.md"

if [[ ! -f "$open_issues_file" ]]; then
  echo "No open issue tracker file found at $open_issues_file"
  exit 0
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

  echo "GitHub CLI (gh) is required to sync task issues." >&2
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

  echo "Unable to detect a git repository root for issue sync." >&2
  exit 1
}

remove_url_from_task_files() {
  local issue_url="$1"
  local task_md tmp

  while IFS= read -r -d '' task_md; do
    if grep -Fq "$issue_url" "$task_md"; then
      tmp="$(mktemp)"
      awk -v url="$issue_url" '$0 != url { print }' "$task_md" > "$tmp"
      mv "$tmp" "$task_md"
      echo "Removed closed issue URL from $task_md"
    fi
  done < <(find "$host_tasks_dir" -mindepth 2 -maxdepth 2 -name TASK.md -print0)
}

resolve_gh
repo_root="$(detect_repo_root)"
tmp_keep="$(mktemp)"
total=0
open_count=0
closed_count=0
error_count=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  issue_url="$(printf '%s' "$raw_line" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [[ -n "$issue_url" ]] || continue
  total=$((total + 1))

  pushd "$repo_root" >/dev/null
  issue_state="$("$GH_BIN" issue view "$issue_url" --json state -q .state 2>/dev/null || true)"
  popd >/dev/null

  case "$issue_state" in
    OPEN)
      printf '%s\n' "$issue_url" >> "$tmp_keep"
      open_count=$((open_count + 1))
      ;;
    CLOSED)
      closed_count=$((closed_count + 1))
      remove_url_from_task_files "$issue_url"
      ;;
    *)
      echo "Could not resolve state for issue URL, keeping entry: $issue_url" >&2
      printf '%s\n' "$issue_url" >> "$tmp_keep"
      error_count=$((error_count + 1))
      ;;
  esac
done < "$open_issues_file"

mv "$tmp_keep" "$open_issues_file"

echo "Task issue sync complete."
echo "Total tracked URLs: $total"
echo "Open URLs kept: $open_count"
echo "Closed URLs removed: $closed_count"
echo "Unresolved URLs kept: $error_count"
