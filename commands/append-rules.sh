#!/usr/bin/env bash
set -euo pipefail

target="../.ai/RULES.md"
mkdir -p "../.ai"
if [[ ! -f "$target" ]]; then
  printf "# Rules\n\n" > "$target"
fi

entry="${1:-}"
if [[ -z "$entry" ]]; then
  echo "Usage: ./commands/append-rules.sh \"text\""
  exit 1
fi

printf "- %s\n" "$entry" >> "$target"
