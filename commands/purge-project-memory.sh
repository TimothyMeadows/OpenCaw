#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: ./commands/purge-project-memory.sh --tag "area:<area>" [--target memory|repo-map|both] [--dry-run]'
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

tag=''
target='memory'
dry_run='false'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --target)
      target="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run='true'
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ "$tag" =~ ^(kind|area|tech|env|topic|scope):[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "Invalid exact tag: $tag" >&2; exit 1; }
[[ "$target" =~ ^(memory|repo-map|both)$ ]] || { echo "Invalid target: $target" >&2; exit 1; }

opencaw_resolve_paths

files=()
if [[ "$target" == 'memory' || "$target" == 'both' ]]; then files+=("$OPENCAW_PROJECT_MEMORY_FILE"); fi
if [[ "$target" == 'repo-map' || "$target" == 'both' ]]; then files+=("$OPENCAW_REPO_MAP_FILE"); fi

total=0
for file in "${files[@]}"; do
  [[ -f "$file" ]] || continue
  count="$(awk -v wanted="$tag" '
    /^-[[:space:]]+\[/ {
      line = $0
      sub(/^-[[:space:]]+/, "", line)
      while (match(line, /^\[[^]]+\][[:space:]]*/)) {
        tag = substr(line, 2, index(line, "]") - 2)
        if (tag == wanted) { count++; print $0 > "/dev/stderr"; next }
        line = substr(line, RLENGTH + 1)
      }
    }
    END { print count + 0 }
  ' "$file" 2> >(sed "s|^|MATCH $(basename "$file"): |" >&2))"
  total=$((total + count))

  if [[ "$dry_run" == 'false' && "$count" -gt 0 ]]; then
    opencaw_archive_file "$file" "purge-${tag//:/-}" "$OPENCAW_PROJECT_AI_DIR/archive/memory"
    awk -v wanted="$tag" '
      {
        original = $0
        line = $0
        remove = 0
        if (line ~ /^-[[:space:]]+\[/) {
          sub(/^-[[:space:]]+/, "", line)
          while (match(line, /^\[[^]]+\][[:space:]]*/)) {
            tag = substr(line, 2, index(line, "]") - 2)
            if (tag == wanted) remove = 1
            line = substr(line, RLENGTH + 1)
          }
        }
        if (!remove) print original
      }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
  fi
done

echo "DRY_RUN=$dry_run"
echo "MATCHED_ENTRIES=$total"
echo "PURGED_ENTRIES=$([[ "$dry_run" == 'true' ]] && echo 0 || echo "$total")"
