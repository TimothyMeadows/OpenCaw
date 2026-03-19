#!/usr/bin/env bash
set -euo pipefail

target="../.ai/DEBUG.md"
mkdir -p "../.ai"
if [[ ! -f "$target" ]]; then
  printf "# Debug History\n\n" > "$target"
fi

entry="${1:-}"
if [[ -z "$entry" ]]; then
  echo "Usage: ./commands/append-debug.sh \"text\""
  exit 1
fi

printf "- %s\n" "$entry" >> "$target"
