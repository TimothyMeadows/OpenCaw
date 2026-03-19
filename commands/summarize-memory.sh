#!/usr/bin/env bash
set -euo pipefail

ai_dir="../.ai"
archive_dir="$ai_dir/TASKS/completed/context-snapshots"
memory_file="$ai_dir/MEMORY.md"
rules_file="$ai_dir/RULES.md"
debug_file="$ai_dir/DEBUG.md"
summary_file="$ai_dir/CONTEXT_SUMMARY.md"
todo_file="../tasks/TODO.md"
architecture_file="../ARCHITECTURE.md"

timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
fs_timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"

mkdir -p "$ai_dir" "$archive_dir"

ensure_file() {
  local file="$1"
  local header="$2"

  if [[ ! -f "$file" ]]; then
    printf "%s\n\n" "$header" > "$file"
  fi
}

ensure_file "$memory_file" '# Project Memory'
ensure_file "$rules_file" '# Rules'
ensure_file "$debug_file" '# Debug History'

cp "$memory_file" "$archive_dir/MEMORY-$fs_timestamp.md"
cp "$rules_file" "$archive_dir/RULES-$fs_timestamp.md"
cp "$debug_file" "$archive_dir/DEBUG-$fs_timestamp.md"

dedupe_bullets_in_place() {
  local file="$1"
  local before after

  before="$(grep -Ec '^[[:space:]]*-[[:space:]]+' "$file" || true)"

  awk '
    {
      line = $0
      sub(/\r$/, "", line)

      if (line ~ /^[[:space:]]*-[[:space:]]+/) {
        item = line
        sub(/^[[:space:]]*-[[:space:]]+/, "", item)

        key = tolower(item)
        gsub(/[[:space:]]+/, " ", key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)

        if (key == "" || seen[key]++) {
          next
        }

        print "- " item
        next
      }

      print line
    }
  ' "$file" > "$file.tmp"

  mv "$file.tmp" "$file"

  after="$(grep -Ec '^[[:space:]]*-[[:space:]]+' "$file" || true)"
  echo $((before - after))
}

memory_merged="$(dedupe_bullets_in_place "$memory_file")"
rules_merged="$(dedupe_bullets_in_place "$rules_file")"
debug_merged="$(dedupe_bullets_in_place "$debug_file")"

list_bullets() {
  local file="$1"
  local limit="$2"
  local content

  content="$(grep -E '^[[:space:]]*-[[:space:]]+' "$file" | sed -E 's/^[[:space:]]*-[[:space:]]+/- /' | head -n "$limit" || true)"

  if [[ -z "$content" ]]; then
    echo '- none'
    return
  fi

  echo "$content"
}

list_pending_todo() {
  local limit="$1"

  if [[ ! -f "$todo_file" ]]; then
    echo '- TODO file not found.'
    return
  fi

  local pending
  pending="$(grep -E '^[0-9]+\.[[:space:]]+\[[[:space:]]\]' "$todo_file" | sed -E 's/^[0-9]+\.[[:space:]]+\[[[:space:]]\][[:space:]]+/- /' | head -n "$limit" || true)"

  if [[ -z "$pending" ]]; then
    echo '- none'
    return
  fi

  echo "$pending"
}

active_note_count="0"
if [[ -d "$ai_dir/TASKS/active" ]]; then
  active_note_count="$(find "$ai_dir/TASKS/active" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
fi

completed_archive_count="0"
if [[ -d "$ai_dir/TASKS/completed" ]]; then
  completed_archive_count="$(find "$ai_dir/TASKS/completed" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')"
fi

architecture_status='ARCHITECTURE.md not found.'
if [[ -f "$architecture_file" ]]; then
  architecture_status='ARCHITECTURE.md is present and authoritative.'
fi

cat > "$summary_file" <<EOF
# Context Summary

Generated: $timestamp

## Active Items Retained
$(list_pending_todo 8)

## Current Constraints
- $architecture_status
- Active task notes: $active_note_count

## Archive Snapshot
- Completed archive files: $completed_archive_count
- Snapshot directory: $archive_dir

## Durable Memory
$(list_bullets "$memory_file" 8)

## Active Rules
$(list_bullets "$rules_file" 8)

## Debug Patterns
$(list_bullets "$debug_file" 8)
EOF

echo "MEMORY_DUPLICATES_MERGED=$memory_merged"
echo "RULE_DUPLICATES_REMOVED=$rules_merged"
echo "DEBUG_NOTES_COMPRESSED=$debug_merged"
echo "SUMMARY_FILE=$summary_file"
echo "SNAPSHOT_DIR=$archive_dir"
