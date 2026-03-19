#!/usr/bin/env bash
set -euo pipefail

fragment="${1:-}"
entry="${2:-}"

if [[ -z "$fragment" || -z "$entry" ]]; then
  echo 'Usage: ./commands/append-fragment.sh "<repo-map|conventions|gotchas|workflows|bugs>" "<text>"'
  exit 1
fi

case "$fragment" in
  repo-map) target="../.ai/FRAGMENTS/repo-map.md" ;;
  conventions) target="../.ai/FRAGMENTS/conventions.md" ;;
  gotchas) target="../.ai/FRAGMENTS/gotchas.md" ;;
  workflows) target="../.ai/LEARNINGS/workflows.md" ;;
  bugs) target="../.ai/LEARNINGS/bugs.md" ;;
  *)
    echo "Unknown fragment type: $fragment"
    exit 1
    ;;
esac

mkdir -p "$(dirname "$target")"
if [[ ! -f "$target" ]]; then
  printf "# %s\n\n" "$fragment" > "$target"
fi

printf "- %s\n" "$entry" >> "$target"
