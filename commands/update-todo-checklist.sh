#!/usr/bin/env bash
set -euo pipefail

target="../tasks/TODO.md"
mkdir -p ../tasks

if [[ ! -f "$target" ]]; then
  printf "# TODO\n\n" > "$target"
fi

echo "Edit $target manually as the ordered checklist. This helper only ensures the file exists."
