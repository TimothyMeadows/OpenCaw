#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./commands/migrate-memory-v2.sh --prepare [--manifest <candidate-tsv>]
  ./commands/migrate-memory-v2.sh --apply <classification-tsv> [--manifest <candidate-tsv>]

Classification rows must contain: <id><TAB><system|memory|repo-map|archive><TAB><tags-or-reason>
Use '-' as system metadata. Memory and repo-map rows require canonical comma-separated tags.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

mode=''
classification_file=''
manifest_file=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare)
      mode='prepare'
      shift
      ;;
    --apply)
      mode='apply'
      classification_file="${2:-}"
      shift 2
      ;;
    --manifest)
      manifest_file="${2:-}"
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

[[ -n "$mode" ]] || { usage >&2; exit 1; }

opencaw_resolve_paths
opencaw_ensure_system_memory
opencaw_ensure_project_files

migrations_dir="$OPENCAW_PROJECT_AI_DIR/migrations"
mkdir -p "$migrations_dir"
if [[ -z "$manifest_file" ]]; then
  manifest_file="$migrations_dir/memory-v2-candidates.tsv"
fi

prepare_manifest() {
  local timestamp archive_dir source line source_label id=0
  local -a sources=()

  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  archive_dir="$OPENCAW_PROJECT_AI_DIR/archive/memory-v1/$timestamp"
  mkdir -p "$archive_dir" "$(dirname "$manifest_file")"

  sources+=("$OPENCAW_PROJECT_MEMORY_FILE")
  if [[ -d "$OPENCAW_PROJECT_AI_DIR/FRAGMENTS" ]]; then
    while IFS= read -r source; do sources+=("$source"); done < <(find "$OPENCAW_PROJECT_AI_DIR/FRAGMENTS" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
  fi
  if [[ -d "$OPENCAW_PROJECT_AI_DIR/LEARNINGS" ]]; then
    while IFS= read -r source; do sources+=("$source"); done < <(find "$OPENCAW_PROJECT_AI_DIR/LEARNINGS" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
  fi

  printf '# id\tsource\tentry\n' > "$manifest_file"
  printf '# archive=%s\n' "$archive_dir" >> "$manifest_file"

  for source in "${sources[@]}"; do
    [[ -f "$source" ]] || continue
    source_label="${source#"$OPENCAW_PROJECT_AI_DIR"/}"
    mkdir -p "$archive_dir/$(dirname "$source_label")"
    cp "$source" "$archive_dir/$source_label"

    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" == '- '* ]] || continue
      if [[ "$source" == "$OPENCAW_PROJECT_MEMORY_FILE" && "$line" == '- ['* ]]; then
        continue
      fi
      id=$((id + 1))
      line="${line#- }"
      line="${line//$'\t'/ }"
      if ! opencaw_reject_sensitive_text "$line" project >/dev/null 2>&1; then
        line="[REDACTED sensitive legacy entry; archive source: $source_label]"
      fi
      printf '%04d\t%s\t%s\n' "$id" "$source_label" "$line" >> "$manifest_file"
    done < "$source"
  done

  echo "MIGRATION_CANDIDATES=$id"
  echo "MIGRATION_MANIFEST=$manifest_file"
  echo "MIGRATION_ARCHIVE=$archive_dir"
}

apply_classification() {
  local temp_dir normalized_file candidate_count classification_count
  local id destination metadata extra entry source candidate_id
  local timestamp report_file retired_dir classification_archive
  local -A seen=()

  [[ -f "$manifest_file" ]] || { echo "Migration manifest not found: $manifest_file" >&2; exit 1; }
  [[ -f "$classification_file" ]] || { echo "Classification file not found: $classification_file" >&2; exit 1; }

  temp_dir="$(mktemp -d)"
  trap "rm -rf -- '$temp_dir'" EXIT
  normalized_file="$temp_dir/classification.tsv"
  : > "$normalized_file"

  while IFS=$'\t' read -r id destination metadata extra || [[ -n "$id" ]]; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    [[ "$id" =~ ^[0-9]{4}$ ]] || { echo "Invalid migration id: $id" >&2; exit 1; }
    [[ -z "${seen[$id]+x}" ]] || { echo "Duplicate migration classification: $id" >&2; exit 1; }
    [[ "$destination" =~ ^(system|memory|repo-map|archive)$ ]] || { echo "Invalid migration destination for $id: $destination" >&2; exit 1; }
    [[ -n "$metadata" && -z "$extra" ]] || { echo "Classification $id requires exactly three tab-separated fields." >&2; exit 1; }

    candidate_id="$(awk -F '\t' -v wanted="$id" '$1 == wanted { print $1; exit }' "$manifest_file")"
    [[ "$candidate_id" == "$id" ]] || { echo "Classification references unknown candidate: $id" >&2; exit 1; }
    entry="$(awk -F '\t' -v wanted="$id" '$1 == wanted { print $3; exit }' "$manifest_file")"

    if [[ "$entry" == '[REDACTED sensitive legacy entry;'* && "$destination" != 'archive' ]]; then
      echo "Sensitive legacy candidate $id must be archived with an explicit reason." >&2
      exit 1
    fi

    case "$destination" in
      system)
        [[ "$metadata" == '-' ]] || { echo "System classification $id must use '-' metadata." >&2; exit 1; }
        opencaw_validate_single_line "$entry" 'System migration entry'
        opencaw_reject_sensitive_text "$entry" system
        ;;
      memory|repo-map)
        opencaw_validate_single_line "$entry" 'Project migration entry'
        opencaw_reject_sensitive_text "$entry" project
        opencaw_normalize_tags "$metadata"
        ;;
      archive)
        [[ "$metadata" != '-' ]] || { echo "Archived classification $id requires a rejection reason." >&2; exit 1; }
        ;;
    esac

    printf '%s\t%s\t%s\n' "$id" "$destination" "$metadata" >> "$normalized_file"
    seen[$id]=1
  done < "$classification_file"

  candidate_count="$(grep -Ec '^[0-9]{4}[[:space:]]' "$manifest_file" || true)"
  classification_count="$(wc -l < "$normalized_file" | tr -d ' ')"
  [[ "$candidate_count" -eq "$classification_count" ]] || {
    echo "Incomplete migration classification: $classification_count of $candidate_count candidates classified." >&2
    exit 1
  }

  awk '
    /^-[[:space:]]+\[/ || $0 !~ /^-[[:space:]]+/ { print }
  ' "$OPENCAW_PROJECT_MEMORY_FILE" > "$OPENCAW_PROJECT_MEMORY_FILE.tmp"
  mv "$OPENCAW_PROJECT_MEMORY_FILE.tmp" "$OPENCAW_PROJECT_MEMORY_FILE"

  while IFS=$'\t' read -r id destination metadata; do
    entry="$(awk -F '\t' -v wanted="$id" '$1 == wanted { print $3; exit }' "$manifest_file")"
    case "$destination" in
      system)
        if ! grep -Fxiq -- "- $entry" "$OPENCAW_SYSTEM_MEMORY_FILE"; then printf '%s\n' "- $entry" >> "$OPENCAW_SYSTEM_MEMORY_FILE"; fi
        ;;
      memory)
        opencaw_append_tagged_entry "$OPENCAW_PROJECT_MEMORY_FILE" "$metadata" "$entry" >/dev/null
        ;;
      repo-map)
        opencaw_append_tagged_entry "$OPENCAW_REPO_MAP_FILE" "$metadata" "$entry" >/dev/null
        ;;
      archive)
        ;;
    esac
  done < "$normalized_file"

  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  retired_dir="$OPENCAW_PROJECT_AI_DIR/archive/memory-v1/retired-$timestamp"
  mkdir -p "$retired_dir"
  for source in FRAGMENTS LEARNINGS; do
    if [[ -d "$OPENCAW_PROJECT_AI_DIR/$source" ]]; then
      mv "$OPENCAW_PROJECT_AI_DIR/$source" "$retired_dir/$source"
    fi
  done

  classification_archive="$OPENCAW_PROJECT_AI_DIR/archive/memory-v1/classification-$timestamp.tsv"
  cp "$normalized_file" "$classification_archive"

  mkdir -p "$OPENCAW_PROJECT_AI_DIR/reports"
  report_file="$OPENCAW_PROJECT_AI_DIR/reports/memory-v2-migration-$timestamp.md"
  {
    echo '# Memory v2 Migration Report'
    echo
    echo "- Candidates classified: $classification_count"
    echo "- System entries: $(awk -F '\t' '$2 == "system" { count++ } END { print count + 0 }' "$normalized_file")"
    echo "- Project memory entries: $(awk -F '\t' '$2 == "memory" { count++ } END { print count + 0 }' "$normalized_file")"
    echo "- Repository map entries: $(awk -F '\t' '$2 == "repo-map" { count++ } END { print count + 0 }' "$normalized_file")"
    echo "- Archived rejections: $(awk -F '\t' '$2 == "archive" { count++ } END { print count + 0 }' "$normalized_file")"
    echo "- Candidate manifest: $manifest_file"
    echo "- Applied classification: $classification_archive"
    echo "- Retired legacy stores: $retired_dir"
  } > "$report_file"

  echo "MIGRATION_APPLIED=true"
  echo "MIGRATION_REPORT=$report_file"
}

case "$mode" in
  prepare) prepare_manifest ;;
  apply) apply_classification ;;
esac
