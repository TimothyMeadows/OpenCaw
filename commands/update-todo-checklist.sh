#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
hephaera_resolve_paths
target="$HEPHAERA_PROJECT_CACHE_DIR/tasks/TODO.md"
open_issues_target="$HEPHAERA_PROJECT_CACHE_DIR/tasks/OPEN_ISSUES.md"
mkdir -p "$HEPHAERA_PROJECT_CACHE_DIR/tasks"

if [[ ! -f "$target" ]]; then
  printf "# TODO\n\n" > "$target"
fi

touch "$open_issues_target"

if [[ -f "$script_dir/sync-task-issues.sh" ]]; then
  bash "$script_dir/sync-task-issues.sh" || echo "Warning: task issue sync failed; review OPEN_ISSUES.md manually." >&2
fi

echo "Edit $target manually as the ordered checklist."
echo "Track only open GitHub issue URLs in $open_issues_target."
