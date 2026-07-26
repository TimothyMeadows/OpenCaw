#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"

opencaw_resolve_paths

status=0

validate_flat_system_file() {
  local line_number=0 line
  [[ -f "$OPENCAW_SYSTEM_MEMORY_FILE" ]] || { echo "Missing system memory: $OPENCAW_SYSTEM_MEMORY_FILE" >&2; status=1; return; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    [[ $line_number -eq 1 && "$line" == '# System Memory' ]] && continue
    [[ -z "$line" ]] && continue
    if [[ "$line" != '- '* ]]; then
      echo "Invalid system-memory line $line_number: $line" >&2
      status=1
      continue
    fi
    if ! opencaw_validate_single_line "${line#- }" 'System memory entry' \
      || ! opencaw_reject_sensitive_text "${line#- }" system; then
      echo "Invalid system-memory line $line_number." >&2
      status=1
    fi
  done < "$OPENCAW_SYSTEM_MEMORY_FILE"

  while IFS= read -r line; do
    if ! awk -v expected="$line" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$OPENCAW_SYSTEM_MEMORY_FILE"; then
      echo "Missing protected system-memory entry: $line" >&2
      status=1
    fi
  done < <(opencaw_system_defaults)
}

validate_tagged_file() {
  local file="$1"
  local label="$2"
  local line_number=0 line normalized duplicate_count

  [[ -f "$file" ]] || { echo "Missing $label: $file" >&2; status=1; return; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == '# '* || "$line" == '<!-- '* ]] && continue
    if ! opencaw_validate_tagged_line "$line"; then
      echo "Invalid $label line $line_number." >&2
      status=1
    fi
  done < "$file"

  duplicate_count="$(awk '
    /^-[[:space:]]+\[/ {
      normalized = tolower($0)
      sub(/\r$/, "", normalized)
      gsub(/[[:space:]]+/, " ", normalized)
      count[normalized]++
    }
    END { for (line in count) if (count[line] > 1) duplicates += count[line] - 1; print duplicates + 0 }
  ' "$file")"
  if [[ "$duplicate_count" -gt 0 ]]; then
    echo "$label contains $duplicate_count duplicate tagged entries." >&2
    status=1
  fi
}

validate_flat_system_file
validate_tagged_file "$OPENCAW_PROJECT_MEMORY_FILE" 'project memory'
validate_tagged_file "$OPENCAW_REPO_MAP_FILE" 'repository map'

if ! grep -Eq '^<!-- OPENCAW_REPO_MAP_FINGERPRINT: (pending|[a-f0-9]{64}) -->$' "$OPENCAW_REPO_MAP_FILE"; then
  echo 'Repository map is missing a valid fingerprint marker.' >&2
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo 'Memory validation passed.'
fi

exit $status
