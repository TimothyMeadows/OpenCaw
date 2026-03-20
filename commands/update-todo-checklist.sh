#!/usr/bin/env bash
set -euo pipefail

target="../.ai/tasks/TODO.md"
mkdir -p ../.ai/tasks

if [[ ! -f "$target" ]]; then
  printf "# TODO\n\n" > "$target"
fi

echo "Edit $target manually as the ordered checklist. This helper only ensures the file exists."
