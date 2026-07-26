#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: ./commands/append-system-memory.sh --entry "verified repository system-memory fact"'
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

entry=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --entry)
      entry="${2:-}"
      shift 2
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

[[ -n "$entry" ]] || { usage >&2; exit 1; }

opencaw_validate_single_line "$entry" 'System memory entry'
opencaw_reject_sensitive_text "$entry" system
opencaw_resolve_paths
opencaw_ensure_system_memory

line="- $entry"
if grep -Fxiq -- "$line" "$OPENCAW_SYSTEM_MEMORY_FILE"; then
  echo 'ALREADY_PRESENT=true'
else
  printf '%s\n' "$line" >> "$OPENCAW_SYSTEM_MEMORY_FILE"
  echo 'ALREADY_PRESENT=false'
fi

echo "SYSTEM_MEMORY_FILE=$OPENCAW_SYSTEM_MEMORY_FILE"
