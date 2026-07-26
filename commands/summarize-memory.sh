#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
opencaw_ensure_system_memory
opencaw_ensure_project_files

ai_dir="$OPENCAW_PROJECT_AI_DIR"
archive_dir="$ai_dir/archive/context-snapshots"
summary_file="$ai_dir/CONTEXT_SUMMARY.md"
todo_file="$ai_dir/tasks/TODO.md"
architecture_file="$OPENCAW_PROJECT_ROOT_RESOLVED/ARCHITECTURE.md"
timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
fs_timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"

mkdir -p "$archive_dir"
cp "$OPENCAW_SYSTEM_MEMORY_FILE" "$archive_dir/SYSTEM_MEMORY-$fs_timestamp.md"
cp "$OPENCAW_PROJECT_MEMORY_FILE" "$archive_dir/MEMORY-$fs_timestamp.md"
cp "$OPENCAW_REPO_MAP_FILE" "$archive_dir/REPO_MAP-$fs_timestamp.md"
cp "$OPENCAW_RULES_FILE" "$archive_dir/RULES-$fs_timestamp.md"
cp "$OPENCAW_DEBUG_FILE" "$archive_dir/DEBUG-$fs_timestamp.md"

dedupe_bullets_in_place() {
  local file="$1"
  local before after
  before="$(grep -Ec '^[[:space:]]*-[[:space:]]+' "$file" || true)"

  awk '
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*-[[:space:]]+/) {
        key = tolower(line)
        gsub(/[[:space:]]+/, " ", key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        if (seen[key]++) next
      }
      print line
    }
  ' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"

  after="$(grep -Ec '^[[:space:]]*-[[:space:]]+' "$file" || true)"
  echo $((before - after))
}

system_merged="$(dedupe_bullets_in_place "$OPENCAW_SYSTEM_MEMORY_FILE")"
memory_merged="$(dedupe_bullets_in_place "$OPENCAW_PROJECT_MEMORY_FILE")"
map_merged="$(dedupe_bullets_in_place "$OPENCAW_REPO_MAP_FILE")"
rules_merged="$(dedupe_bullets_in_place "$OPENCAW_RULES_FILE")"
debug_merged="$(dedupe_bullets_in_place "$OPENCAW_DEBUG_FILE")"

count_bullets() {
  grep -Ec '^[[:space:]]*-[[:space:]]+' "$1" || true
}

list_pending_todo() {
  if [[ ! -f "$todo_file" ]]; then
    echo '- none'
    return
  fi
  local pending
  pending="$(grep -E '^[0-9]+\.[[:space:]]+\[[[:space:]]\]' "$todo_file" | sed -E 's/^[0-9]+\.[[:space:]]+\[[[:space:]]\][[:space:]]+/- /' | head -n 8 || true)"
  [[ -n "$pending" ]] && echo "$pending" || echo '- none'
}

tag_catalog="$($script_dir/query-project-context.sh --list-tags | head -n 30 || true)"
[[ -n "$tag_catalog" ]] || tag_catalog='none 0'

map_status='UNAVAILABLE'
if git -C "$OPENCAW_PROJECT_ROOT_RESOLVED" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  map_status="$($script_dir/repo-map-status.sh | awk -F= '/^REPO_MAP_STATUS=/{print $2; exit}')"
fi

architecture_status='ARCHITECTURE.md not found.'
[[ -f "$architecture_file" ]] && architecture_status='ARCHITECTURE.md is present and authoritative.'

cat > "$summary_file" <<EOF
# Context Summary

Generated: $timestamp

## Active Items

$(list_pending_todo)

## Memory Inventory

- System memory entries: $(count_bullets "$OPENCAW_SYSTEM_MEMORY_FILE")
- Tagged project memory entries: $(count_bullets "$OPENCAW_PROJECT_MEMORY_FILE")
- Semantic repository map entries: $(count_bullets "$OPENCAW_REPO_MAP_FILE")
- Repository map status: $map_status

## Tag Catalog

\`\`\`text
$tag_catalog
\`\`\`

## Current Constraints

- $architecture_status
- System memory must be loaded before project rules and selectively queried project context.
- Task index: $todo_file

## Traceability

- Project snapshots: $archive_dir
- Memory and context snapshots: $archive_dir
EOF

echo "SYSTEM_MEMORY_DUPLICATES_MERGED=$system_merged"
echo "MEMORY_DUPLICATES_MERGED=$memory_merged"
echo "REPO_MAP_DUPLICATES_MERGED=$map_merged"
echo "RULE_DUPLICATES_REMOVED=$rules_merged"
echo "DEBUG_NOTES_COMPRESSED=$debug_merged"
echo "SUMMARY_FILE=$summary_file"
echo "SNAPSHOT_DIR=$archive_dir"
