#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
hephaera_resolve_paths

src="${1:-}"
name="${2:-}"

if [[ -z "$src" ]]; then
  echo 'Usage: ./commands/archive-task-note.sh "<source-file>" ["archive-name.md"]'
  exit 1
fi

if [[ -z "$name" ]]; then
  name="$(basename "$src")"
fi
if [[ "$name" == */* || "$name" == *\\* || "$name" == . || "$name" == .. ]]; then
  echo 'Archive name must be one filename within .hephaera/.cache/archive/tasks.' >&2
  exit 1
fi
archive_dir="$HEPHAERA_PROJECT_CACHE_DIR/archive/tasks"
for path in "$HEPHAERA_PROJECT_CACHE_DIR/archive" "$archive_dir" "$archive_dir/$name"; do
  [[ ! -L "$path" ]] || { echo "Archive path must not be a symbolic link: $path" >&2; exit 1; }
done
mkdir -p "$archive_dir"

cp "$src" "$archive_dir/$name"
