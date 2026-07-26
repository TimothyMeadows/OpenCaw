#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/append-project-memory.sh --tags "kind:<kind>,area:<area>" --entry "fact" [--replace "old fact"]
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

tags=''
entry=''
replace=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags)
      tags="${2:-}"
      shift 2
      ;;
    --entry)
      entry="${2:-}"
      shift 2
      ;;
    --replace)
      replace="${2:-}"
      shift 2
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

if [[ -z "$tags" || -z "$entry" ]]; then
  echo 'Untagged project-memory writes are not supported.' >&2
  usage >&2
  exit 1
fi

opencaw_resolve_paths
opencaw_ensure_project_files

if [[ -n "$replace" ]]; then
  replacement_count="$(awk -v fact="$replace" '
    function lower(value) { return tolower(value) }
    {
      line = $0
      if (line !~ /^-[[:space:]]+\[/) next
      sub(/^-[[:space:]]+/, "", line)
      while (line ~ /^\[[^]]+\][[:space:]]+/) sub(/^\[[^]]+\][[:space:]]+/, "", line)
      if (lower(line) == lower(fact)) count++
    }
    END { print count + 0 }
  ' "$OPENCAW_PROJECT_MEMORY_FILE")"

  if [[ "$replacement_count" -ne 1 ]]; then
    echo "Replacement requires exactly one matching old fact; found $replacement_count." >&2
    exit 1
  fi

  opencaw_archive_file "$OPENCAW_PROJECT_MEMORY_FILE" replace "$OPENCAW_PROJECT_AI_DIR/archive/memory"
  awk -v fact="$replace" '
    {
      original = $0
      line = $0
      if (line ~ /^-[[:space:]]+\[/) {
        sub(/^-[[:space:]]+/, "", line)
        while (line ~ /^\[[^]]+\][[:space:]]+/) sub(/^\[[^]]+\][[:space:]]+/, "", line)
        if (tolower(line) == tolower(fact)) next
      }
      print original
    }
  ' "$OPENCAW_PROJECT_MEMORY_FILE" > "$OPENCAW_PROJECT_MEMORY_FILE.tmp"
  mv "$OPENCAW_PROJECT_MEMORY_FILE.tmp" "$OPENCAW_PROJECT_MEMORY_FILE"
fi

opencaw_append_tagged_entry "$OPENCAW_PROJECT_MEMORY_FILE" "$tags" "$entry"
echo "MEMORY_FILE=$OPENCAW_PROJECT_MEMORY_FILE"
