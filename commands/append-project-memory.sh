#!/usr/bin/env bash
set -euo pipefail

target="../.ai/MEMORY.md"
mkdir -p "../.ai"
if [[ ! -f "$target" ]]; then
  printf "# Project Memory\n\n" > "$target"
fi

entry="${1:-}"
if [[ -z "$entry" ]]; then
  echo "Usage: ./commands/append-project-memory.sh \"text\""
  exit 1
fi

printf "- %s\n" "$entry" >> "$target"
