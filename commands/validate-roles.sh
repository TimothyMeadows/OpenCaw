#!/usr/bin/env bash
set -euo pipefail

roles_dir="./.roles"
schema_file="./.roles/SCHEMA.md"

if [[ ! -d "$roles_dir" ]]; then
  echo "Missing roles directory: $roles_dir" >&2
  exit 1
fi

if [[ ! -f "$schema_file" ]]; then
  echo "Missing roles schema: $schema_file" >&2
  exit 1
fi

status=0
declare -A alias_seen

trim_line() {
  local value="$1"
  value="${value//$'\r'/}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

normalize_role_name() {
  local value="$1"
  value="$(trim_line "$value")"
  value="$(printf '%s' "$value" | sed -E "s/^['\"]//; s/['\"]$//")"
  value="$(printf '%s' "$value" | sed -E 's/[[:space:]]*\([^)]*\)//g')"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf '%s' "$value"
}

is_legacy_role_format() {
  local role_file="$1"
  local h1_count h2_count
  h1_count="$(grep -Ec '^# ' "$role_file" || true)"
  h2_count="$(grep -Ec '^## ' "$role_file" || true)"
  [[ "$h1_count" -ge 1 && "$h2_count" -ge 3 ]]
}

while IFS= read -r -d '' role_md; do
  role_dir="$(basename "$(dirname "$role_md")")"

  if [[ ! "$role_dir" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "Invalid role folder name: $role_dir" >&2
    status=1
  fi

  if ! grep -q '^---' "$role_md"; then
    echo "Missing metadata block in $role_md" >&2
    status=1
  fi

  if ! grep -q '^name:[[:space:]]' "$role_md"; then
    echo "Missing name field in $role_md" >&2
    status=1
  else
    declared_name_raw="$(grep '^name:[[:space:]]' "$role_md" | head -n1 | sed 's/^name:[[:space:]]*//')"
    declared_name="$(trim_line "$declared_name_raw")"
    declared_name_normalized="$(normalize_role_name "$declared_name")"
    if [[ "$declared_name" != "$role_dir" && "$declared_name_normalized" != "$role_dir" ]]; then
      echo "Role name mismatch in $role_md (folder=$role_dir, name=$declared_name)" >&2
      status=1
    fi
  fi

  missing_sections=()
  for section in "^# Purpose" "^# Responsibilities" "^# Behavior" "^# Constraints" "^# Collaboration"; do
    if ! grep -q "$section" "$role_md"; then
      missing_sections+=("$section")
    fi
  done

  if [[ ${#missing_sections[@]} -gt 0 ]] && ! is_legacy_role_format "$role_md"; then
    for section in "${missing_sections[@]}"; do
      echo "Missing required section ($section) in $role_md" >&2
      status=1
    done
  fi

  in_aliases=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^aliases: ]]; then
      in_aliases=1
      continue
    fi
    if [[ $in_aliases -eq 1 ]]; then
      if [[ "$line" =~ ^[A-Za-z] || "$line" =~ ^category: || "$line" =~ ^--- ]]; then
        in_aliases=0
      elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.+)$ ]]; then
        alias="${BASH_REMATCH[1]}"
        alias="${alias//[$'\r']}"
        if [[ ! "$alias" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
          echo "Invalid alias '$alias' in $role_md" >&2
          status=1
        fi
        if [[ -n "${alias_seen[$alias]:-}" ]]; then
          echo "Duplicate alias '$alias' found in $role_md and ${alias_seen[$alias]}" >&2
          status=1
        else
          alias_seen[$alias]="$role_md"
        fi
      fi
    fi
  done < "$role_md"

done < <(find "$roles_dir" -mindepth 2 -maxdepth 2 -name ROLE.md -print0)

if [[ $status -eq 0 ]]; then
  echo "Roles validation passed."
fi

exit $status
