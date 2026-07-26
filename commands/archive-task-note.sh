#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths

src="${1:-}"
name="${2:-}"

if [[ -z "$src" ]]; then
  echo 'Usage: ./commands/archive-task-note.sh "<source-file>" ["archive-name.md"]'
  exit 1
fi

mkdir -p "$OPENCAW_PROJECT_AI_DIR/archive/tasks"
if [[ -z "$name" ]]; then
  name="$(basename "$src")"
fi

cp "$src" "$OPENCAW_PROJECT_AI_DIR/archive/tasks/$name"
