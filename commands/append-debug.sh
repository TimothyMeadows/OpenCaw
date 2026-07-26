#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
opencaw_ensure_project_files
target="$OPENCAW_DEBUG_FILE"

entry="${1:-}"
if [[ -z "$entry" ]]; then
  echo "Usage: ./commands/append-debug.sh \"text\""
  exit 1
fi

printf -- "- %s\n" "$entry" >> "$target"
