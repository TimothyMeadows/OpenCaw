#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-subagent-plan.sh "<task_name|path>"

Validates a SUBAGENTS.md lane plan.
EOF
}

input="${1:-}"
if [[ -z "$input" || "$input" == "-h" || "$input" == "--help" ]]; then
  usage
  [[ -z "$input" ]] && exit 1 || exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$input" ]]; then
  plan_path="$input"
else
  plan_path="../.ai/tasks/$input/SUBAGENTS.md"
fi

if [[ ! -f "$plan_path" ]]; then
  echo "Missing subagent plan: $plan_path" >&2
  exit 1
fi

trim() {
  local value="$1"
  value="${value//$'\r'/}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf '%s' "$value"
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_placeholder() {
  local value
  value="$(lower "$(trim "$1")")"
  [[ -z "$value" || "$value" == "todo" || "$value" == "tbd" || "$value" =~ ^\<.*\>$ ]]
}

field_value() {
  local block="$1"
  local field="$2"
  printf '%s\n' "$block" \
    | sed -nE "s/^[[:space:]]*-[[:space:]]*${field}:[[:space:]]*(.*)$/\\1/p" \
    | head -n1 \
    | sed -E 's/\r$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

normalize_path() {
  local value
  value="$(trim "$1")"
  value="${value#./}"
  value="${value%/}"
  printf '%s' "$value"
}

paths_overlap() {
  local left right
  left="$(normalize_path "$1")"
  right="$(normalize_path "$2")"
  [[ "$left" == "$right" || "$left" == "$right"/* || "$right" == "$left"/* ]]
}

status=0
current_lane=""
current_block=""
declare -A lane_seen
declare -A deps_by_lane
declare -A write_owner
lane_ids=()

process_lane() {
  local lane_id="$1"
  local block="$2"

  if [[ -z "$lane_id" ]]; then
    return 0
  fi

  if [[ -n "${lane_seen[$lane_id]:-}" ]]; then
    echo "Duplicate lane id: $lane_id" >&2
    status=1
    return
  fi

  lane_seen["$lane_id"]=1
  lane_ids+=("$lane_id")

  local role agent_type scope write_set dependencies expected_output verification
  role="$(field_value "$block" "Role")"
  agent_type="$(field_value "$block" "Agent type")"
  scope="$(field_value "$block" "Scope")"
  write_set="$(field_value "$block" "Write set")"
  dependencies="$(field_value "$block" "Dependencies")"
  expected_output="$(field_value "$block" "Expected output")"
  verification="$(field_value "$block" "Verification")"

  local field_name field_content
  for field_name in "Role" "Agent type" "Scope" "Write set" "Dependencies" "Expected output" "Verification"; do
    field_content="$(field_value "$block" "$field_name")"
    if is_placeholder "$field_content"; then
      echo "$lane_id has missing or placeholder field: $field_name" >&2
      status=1
    fi
  done

  if ! bash "$script_dir/resolve-role.sh" "$role" >/dev/null 2>&1; then
    echo "$lane_id has unresolved role: $role" >&2
    status=1
  fi

  local normalized_agent_type
  normalized_agent_type="$(lower "$(trim "$agent_type")")"
  case "$normalized_agent_type" in
    explorer|worker|default)
      ;;
    *)
      echo "$lane_id has invalid Agent type '$agent_type' (expected explorer, worker, or default)" >&2
      status=1
      ;;
  esac

  deps_by_lane["$lane_id"]="$dependencies"

  if [[ "$normalized_agent_type" == "worker" ]]; then
    if [[ "$(lower "$(trim "$write_set")")" == "none" ]]; then
      echo "$lane_id is a worker lane and must declare a non-empty write set" >&2
      status=1
      return
    fi

    local path existing_path
    IFS=',' read -r -a write_paths <<< "$write_set"
    for path in "${write_paths[@]}"; do
      path="$(normalize_path "$path")"
      if is_placeholder "$path" || [[ "$(lower "$path")" == "none" ]]; then
        echo "$lane_id has invalid worker write path: $path" >&2
        status=1
        continue
      fi

      for existing_path in "${!write_owner[@]}"; do
        if paths_overlap "$path" "$existing_path"; then
          echo "Worker write set overlap: $lane_id '$path' conflicts with ${write_owner[$existing_path]} '$existing_path'" >&2
          status=1
        fi
      done

      write_owner["$path"]="$lane_id"
    done
  fi

  return 0
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line//$'\r'/}"
  if [[ "$line" =~ ^###[[:space:]]+(lane-[a-z0-9][a-z0-9-]*)[[:space:]]*$ ]]; then
    matched_lane="${BASH_REMATCH[1]}"
    process_lane "$current_lane" "$current_block"
    current_lane="$matched_lane"
    current_block=""
  elif [[ -n "$current_lane" ]]; then
    current_block+="${line}"$'\n'
  fi
done < "$plan_path"
process_lane "$current_lane" "$current_block"

if [[ ${#lane_ids[@]} -eq 0 ]]; then
  echo "No lane sections found in $plan_path (expected headings like '### lane-1')" >&2
  status=1
fi

for lane_id in "${lane_ids[@]}"; do
  deps="${deps_by_lane[$lane_id]:-}"
  if [[ "$(lower "$(trim "$deps")")" == "none" ]]; then
    continue
  fi

  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    if [[ -z "${lane_seen[$dep]:-}" ]]; then
      echo "$lane_id depends on missing lane: $dep" >&2
      status=1
    fi
  done < <(printf '%s\n' "$deps" | grep -oE 'lane-[a-z0-9][a-z0-9-]*' || true)
done

if [[ $status -eq 0 ]]; then
  echo "Subagent plan validation passed: $plan_path"
fi

exit "$status"
