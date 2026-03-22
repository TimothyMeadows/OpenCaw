#!/usr/bin/env bash
set -euo pipefail

target="../.ai/tasks/TODO.md"
open_issues_target="../.ai/tasks/OPEN_ISSUES.md"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p ../.ai/tasks

if [[ ! -f "$target" ]]; then
  printf "# TODO\n\n" > "$target"
fi

touch "$open_issues_target"

if [[ -f "$script_dir/sync-task-issues.sh" ]]; then
  bash "$script_dir/sync-task-issues.sh" || echo "Warning: task issue sync failed; review OPEN_ISSUES.md manually." >&2
fi

echo "Edit $target manually as the ordered checklist."
echo "Track only open GitHub issue URLs in $open_issues_target."
