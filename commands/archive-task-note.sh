#!/usr/bin/env bash
set -euo pipefail

src="${1:-}"
name="${2:-}"

if [[ -z "$src" ]]; then
  echo 'Usage: ./commands/archive-task-note.sh "<source-file>" ["archive-name.md"]'
  exit 1
fi

mkdir -p ../.ai/archive/tasks
if [[ -z "$name" ]]; then
  name="$(basename "$src")"
fi

cp "$src" "../.ai/archive/tasks/$name"
