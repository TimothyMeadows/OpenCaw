#!/usr/bin/env bash
set -euo pipefail

fragment="${1:-}"
entry="${2:-}"

if [[ -z "$fragment" || -z "$entry" ]]; then
  echo 'Usage: ./commands/append-fragment.sh "<repo-map|conventions|gotchas|workflows|bugs>" "<text>"'
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
hephaera_resolve_paths
hephaera_ensure_project_files

case "$fragment" in
  repo-map)
    target="$HEPHAERA_REPO_MAP_FILE"
    tags='kind:component,area:general,topic:legacy-fragment'
    ;;
  conventions)
    target="$HEPHAERA_PROJECT_MEMORY_FILE"
    tags='kind:convention,topic:conventions'
    ;;
  gotchas)
    target="$HEPHAERA_PROJECT_MEMORY_FILE"
    tags='kind:gotcha,topic:gotchas'
    ;;
  workflows)
    target="$HEPHAERA_PROJECT_MEMORY_FILE"
    tags='kind:workflow,topic:workflows'
    ;;
  bugs)
    target="$HEPHAERA_PROJECT_MEMORY_FILE"
    tags='kind:bug,topic:bugs'
    ;;
  *)
    echo "Unknown fragment type: $fragment"
    exit 1
    ;;
esac

echo 'Warning: append-fragment.sh is deprecated; use tagged memory or the repository map directly.' >&2
hephaera_append_tagged_entry "$target" "$tags" "$entry"
echo "TARGET_FILE=$target"
