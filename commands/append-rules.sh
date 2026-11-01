#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
hephaera_resolve_paths
hephaera_ensure_project_files
target="$HEPHAERA_RULES_FILE"

entry="${1:-}"
if [[ -z "$entry" ]]; then
  echo "Usage: ./commands/append-rules.sh \"text\""
  exit 1
fi

printf -- "- %s\n" "$entry" >> "$target"
