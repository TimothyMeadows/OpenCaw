#!/usr/bin/env bash
set -euo pipefail

roles_dir="./.roles"
index_file="./.roles/INDEX.md"
query="${1:-}"

if [[ -z "$query" ]]; then
  cat <<USAGE >&2
Usage: ./commands/resolve-role.sh "<role-name|alias|domain/role-name>"
USAGE
  exit 1
fi

if [[ ! -d "$roles_dir" ]]; then
  echo "Missing roles directory: $roles_dir" >&2
  exit 1
fi

trim_line() {
  local value="$1"
  value="${value//$'\r'/}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_token() {
  local value="$1"
  value="$(trim_line "$value")"
  value="$(to_lower "$value")"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf '%s' "$value"
}

append_unique_pipe_value() {
  local value="$1"
  local existing="$2"

  if [[ -z "$existing" ]]; then
    printf '%s' "$value"
    return
  fi

  local part
  IFS='|' read -r -a parts <<< "$existing"
  for part in "${parts[@]}"; do
    if [[ "$part" == "$value" ]]; then
      printf '%s' "$existing"
      return
    fi
  done

  printf '%s|%s' "$existing" "$value"
}

pipe_list_count() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo "0"
    return
  fi

  local count=1
  local part
  IFS='|' read -r -a parts <<< "$value"
  for part in "${parts[@]}"; do
    :
  done
  count="${#parts[@]}"
  echo "$count"
}

print_candidates() {
  local value="$1"
  local part
  IFS='|' read -r -a parts <<< "$value"
  printf '%s\n' "${parts[@]}" | sed '/^$/d' | sort -u
}

declare -A role_file_by_id
declare -A role_ids_by_name
declare -A alias_role_ids
role_alias_line_regex='^[[:space:]]*-[[:space:]]+`([^`]+)`:[[:space:]]*(.*)$'

while IFS= read -r -d '' role_md; do
  domain="$(basename "$(dirname "$(dirname "$role_md")")")"
  role_name="$(basename "$(dirname "$role_md")")"
  role_id="${domain}/${role_name}"
  role_file_by_id["$role_id"]="$role_md"
  role_ids_by_name["$role_name"]="$(append_unique_pipe_value "$role_id" "${role_ids_by_name[$role_name]:-}")"
done < <(find "$roles_dir" -mindepth 3 -maxdepth 3 -name ROLE.md -print0)

if [[ ${#role_file_by_id[@]} -eq 0 ]]; then
  echo "RESOLUTION=not_found"
  echo "QUERY=$query"
  echo "PROMPT=No roles found under .roles/<domain>/<role>/ROLE.md."
  exit 1
fi

register_alias() {
  local alias_value="$1"
  local role_id="$2"
  local alias_trimmed alias_lower alias_normalized

  alias_trimmed="$(trim_line "$alias_value")"
  [[ -n "$alias_trimmed" ]] || return

  alias_lower="$(to_lower "$alias_trimmed")"
  alias_normalized="$(normalize_token "$alias_trimmed")"

  alias_role_ids["$alias_lower"]="$(append_unique_pipe_value "$role_id" "${alias_role_ids[$alias_lower]:-}")"
  if [[ "$alias_normalized" != "$alias_lower" && -n "$alias_normalized" ]]; then
    alias_role_ids["$alias_normalized"]="$(append_unique_pipe_value "$role_id" "${alias_role_ids[$alias_normalized]:-}")"
  fi
}

if [[ -f "$index_file" ]]; then
  while IFS= read -r raw_line; do
    line="${raw_line//$'\r'/}"
    if [[ "$line" =~ $role_alias_line_regex ]]; then
      role_key="$(trim_line "${BASH_REMATCH[1]}")"
      alias_blob="${BASH_REMATCH[2]}"

      role_candidates=''
      if [[ "$role_key" == */* ]]; then
        role_domain="$(normalize_token "${role_key%%/*}")"
        role_name="$(normalize_token "${role_key#*/}")"
        role_id="${role_domain}/${role_name}"
        if [[ -n "${role_file_by_id[$role_id]:-}" ]]; then
          role_candidates="$role_id"
        fi
      else
        normalized_role_key="$(normalize_token "$role_key")"
        role_candidates="${role_ids_by_name[$normalized_role_key]:-}"
      fi

      if [[ -z "$role_candidates" ]]; then
        continue
      fi

      while IFS= read -r alias_token; do
        alias_token="${alias_token#\`}"
        alias_token="${alias_token%\`}"
        while IFS= read -r role_id; do
          register_alias "$alias_token" "$role_id"
        done < <(print_candidates "$role_candidates")
      done < <(printf '%s\n' "$alias_blob" | grep -oE '`[^`]+`' || true)
    fi
  done < "$index_file"
fi

query_trimmed="$(trim_line "$query")"
query_lower="$(to_lower "$query_trimmed")"
query_normalized="$(normalize_token "$query_trimmed")"

emit_resolved() {
  local match_type="$1"
  local role_id="$2"
  echo "RESOLUTION=resolved"
  echo "MATCH_TYPE=$match_type"
  echo "ROLE_ID=$role_id"
  echo "ROLE_FILE=${role_file_by_id[$role_id]}"
}

emit_ambiguous() {
  local match_type="$1"
  local candidates="$2"
  local count
  count="$(pipe_list_count "$candidates")"

  echo "RESOLUTION=ambiguous"
  echo "MATCH_TYPE=$match_type"
  echo "QUERY=$query_trimmed"
  echo "CANDIDATE_COUNT=$count"
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    echo "CANDIDATE=$candidate"
  done < <(print_candidates "$candidates")
  echo "PROMPT=Role reference '$query_trimmed' is ambiguous. Choose one CANDIDATE and retry using domain-qualified form."
}

if [[ "$query_trimmed" == */* ]]; then
  query_domain="$(normalize_token "${query_trimmed%%/*}")"
  query_role="$(normalize_token "${query_trimmed#*/}")"
  query_role_id="${query_domain}/${query_role}"
  if [[ -n "${role_file_by_id[$query_role_id]:-}" ]]; then
    emit_resolved "qualified" "$query_role_id"
    exit 0
  fi

  echo "RESOLUTION=not_found"
  echo "QUERY=$query_trimmed"
  echo "PROMPT=No role matched '$query_trimmed'. Check .roles/INDEX.md for valid domain-qualified role ids."
  exit 1
fi

exact_candidates="${role_ids_by_name[$query_normalized]:-}"
if [[ -n "$exact_candidates" ]]; then
  exact_count="$(pipe_list_count "$exact_candidates")"
  if [[ "$exact_count" -eq 1 ]]; then
    resolved_role="$(print_candidates "$exact_candidates" | head -n1)"
    emit_resolved "exact-name" "$resolved_role"
    exit 0
  fi

  emit_ambiguous "exact-name" "$exact_candidates"
  exit 2
fi

alias_candidates=''
if [[ -n "${alias_role_ids[$query_lower]:-}" ]]; then
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    alias_candidates="$(append_unique_pipe_value "$candidate" "$alias_candidates")"
  done < <(print_candidates "${alias_role_ids[$query_lower]}")
fi
if [[ -n "${alias_role_ids[$query_normalized]:-}" ]]; then
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    alias_candidates="$(append_unique_pipe_value "$candidate" "$alias_candidates")"
  done < <(print_candidates "${alias_role_ids[$query_normalized]}")
fi

if [[ -n "$alias_candidates" ]]; then
  alias_count="$(pipe_list_count "$alias_candidates")"
  if [[ "$alias_count" -eq 1 ]]; then
    resolved_role="$(print_candidates "$alias_candidates" | head -n1)"
    emit_resolved "alias" "$resolved_role"
    exit 0
  fi

  emit_ambiguous "alias" "$alias_candidates"
  exit 2
fi

echo "RESOLUTION=not_found"
echo "QUERY=$query_trimmed"
echo "PROMPT=No role matched '$query_trimmed'. Check .roles/INDEX.md for valid role names and aliases."
exit 1
