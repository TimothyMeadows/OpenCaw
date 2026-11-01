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

hephaera_validate_single_line "$entry" 'System memory entry'
hephaera_reject_sensitive_text "$entry" system
hephaera_resolve_paths
hephaera_ensure_system_memory

line="- $entry"
if grep -Fxiq -- "$line" "$HEPHAERA_SYSTEM_MEMORY_FILE"; then
  echo 'ALREADY_PRESENT=true'
else
  printf '%s\n' "$line" >> "$HEPHAERA_SYSTEM_MEMORY_FILE"
  echo 'ALREADY_PRESENT=false'
fi

echo "SYSTEM_MEMORY_FILE=$HEPHAERA_SYSTEM_MEMORY_FILE"
