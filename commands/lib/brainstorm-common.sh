#!/usr/bin/env bash

# Shared Brainstorm lifecycle helpers. Commands sourcing this file must enable strict mode.

brainstorm_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$brainstorm_lib_dir/memory-common.sh"
opencaw_resolve_paths

OPENCAW_BRAINSTORM_FILE="$OPENCAW_PROJECT_ROOT_RESOLVED/BRAINSTORM.md"
OPENCAW_BRAINSTORM_SUMMARY_FILE="$OPENCAW_PROJECT_ROOT_RESOLVED/BRAINSTORM_SUMMARY.md"

brainstorm_detect_state() {
  local file="${1:-$OPENCAW_BRAINSTORM_FILE}"
  local status_count status

  if [[ -L "$file" ]]; then
    OPENCAW_BRAINSTORM_STATE='malformed'
    return 2
  fi

  if [[ ! -f "$file" ]]; then
    OPENCAW_BRAINSTORM_STATE='absent'
    return 0
  fi

  status_count="$(awk '
    { sub(/\r$/, "") }
    /^## Mode$/ { in_mode=1; next }
    /^## / { in_mode=0 }
    in_mode && /^- Status: / { count++ }
    END { print count + 0 }
  ' "$file")"
  status="$(awk '
    { sub(/\r$/, "") }
    /^## Mode$/ { in_mode=1; next }
    /^## / { in_mode=0 }
    in_mode && /^- Status: / { sub(/^- Status: /, ""); print }
  ' "$file")"

  if [[ "$status_count" != '1' || ( "$status" != 'active' && "$status" != 'inactive' ) ]]; then
    OPENCAW_BRAINSTORM_STATE='malformed'
    return 2
  fi

  OPENCAW_BRAINSTORM_STATE="$status"
}

brainstorm_require_delivery_creation_allowed() {
  local operation="${1:-Delivery-mode artifact creation}"

  if ! brainstorm_detect_state; then
    echo "$operation is blocked because BRAINSTORM.md has malformed mode state. Repair or explicitly close Brainstorm mode first." >&2
    return 1
  fi

  if [[ "$OPENCAW_BRAINSTORM_STATE" == 'active' ]]; then
    echo "$operation is blocked while Brainstorm mode is active. The user must explicitly exit Brainstorm mode and request a plan before creating task, Goal, or Gauntlet state." >&2
    return 1
  fi

  if [[ "$OPENCAW_BRAINSTORM_STATE" == 'inactive' ]]; then
    if ! brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" inactive; then
      echo "$operation is blocked because inactive Brainstorm state is malformed." >&2
      return 1
    fi
    if ! brainstorm_validate_summary "$OPENCAW_BRAINSTORM_FILE" "$OPENCAW_BRAINSTORM_SUMMARY_FILE"; then
      echo "$operation is blocked because inactive Brainstorm state lacks a current exit summary. Explicitly stop Brainstorm mode again to repair it." >&2
      return 1
    fi
  fi
}

brainstorm_sha256() {
  local file="$1"
  sha256sum "$file" | awk '{ print $1 }'
}

brainstorm_utc_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

brainstorm_validate_file() {
  local file="${1:-$OPENCAW_BRAINSTORM_FILE}"
  local required_state="${2:-any}"
  local status=0 line section='' current_idea='' current_subsection=''
  local citation_regex='https?://[^[:space:])}]+'
  local mode_status='' active_session='' activated_at='' deactivated_at=''
  local mode_status_count=0 active_session_count=0 activated_count=0 deactivated_count=0
  local branch_id parent title summary idea_id key value subsection_key
  local -A branch_parent=() branch_title=() branch_summary=()
  local -A idea_seen=() idea_title=() idea_branch=() idea_status=() idea_created=() idea_updated=() idea_readiness=() idea_summary=()
  local -A idea_field_count=() subsection_count=() subsection_has_content=() subsection_has_pending=() subsection_has_citation=()
  local -a branch_ids=() idea_ids=()
  local -a required_subsections=(
    'User Idea'
    'Base Understanding'
    'Research Findings and Citations'
    'Dependencies'
    'Risks'
    'Open Questions'
    'Start Conditions'
    'Definition of Complete'
  )

  if [[ -L "$file" ]]; then
    echo "Brainstorm file must not be a symbolic link: $file" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "Missing Brainstorm file: $file" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    case "$line" in
      '## Mode') section='mode'; current_idea=''; current_subsection=''; continue ;;
      '## Session History') section='sessions'; current_idea=''; current_subsection=''; continue ;;
      '## Branches') section='branches'; current_idea=''; current_subsection=''; continue ;;
      '## Elements') section='elements'; current_idea=''; current_subsection=''; continue ;;
    esac

    if [[ "$line" =~ ^##[[:space:]] ]]; then
      section='other'
      current_idea=''
      current_subsection=''
      continue
    fi

    if [[ "$section" == 'mode' ]]; then
      case "$line" in
        '- Status: '*) mode_status="${line#- Status: }"; mode_status_count=$((mode_status_count + 1)) ;;
        '- Active session: '*) active_session="${line#- Active session: }"; active_session_count=$((active_session_count + 1)) ;;
        '- Activated at: '*) activated_at="${line#- Activated at: }"; activated_count=$((activated_count + 1)) ;;
        '- Deactivated at: '*) deactivated_at="${line#- Deactivated at: }"; deactivated_count=$((deactivated_count + 1)) ;;
      esac
      continue
    fi

    if [[ "$section" == 'branches' ]]; then
      if [[ "$line" =~ ^-[[:space:]](BR-[0-9]{3,})[[:space:]]\|[[:space:]]parent:[[:space:]](ROOT|BR-[0-9]{3,})[[:space:]]\|[[:space:]]title:[[:space:]]([^\|]+)[[:space:]]\|[[:space:]]summary:[[:space:]](.+)$ ]]; then
        branch_id="${BASH_REMATCH[1]}"
        parent="${BASH_REMATCH[2]}"
        title="${BASH_REMATCH[3]}"
        summary="${BASH_REMATCH[4]}"
        title="${title%${title##*[![:space:]]}}"
        summary="${summary%${summary##*[![:space:]]}}"
        if [[ -n "${branch_parent[$branch_id]+x}" ]]; then
          echo "Duplicate Brainstorm branch id: $branch_id" >&2
          status=1
        else
          branch_ids+=("$branch_id")
          branch_parent["$branch_id"]="$parent"
          branch_title["$branch_id"]="$title"
          branch_summary["$branch_id"]="$summary"
        fi
      elif [[ "$line" == '- BR-'* ]]; then
        echo "Malformed Brainstorm branch line: $line" >&2
        status=1
      fi
      continue
    fi

    if [[ "$section" == 'elements' && "$line" =~ ^###[[:space:]](IDEA-[0-9]{3,})$ ]]; then
      idea_id="${BASH_REMATCH[1]}"
      if [[ -n "${idea_seen[$idea_id]+x}" ]]; then
        echo "Duplicate Brainstorm element id: $idea_id" >&2
        status=1
      else
        idea_seen["$idea_id"]=1
        idea_ids+=("$idea_id")
      fi
      current_idea="$idea_id"
      current_subsection=''
      continue
    fi

    if [[ "$section" == 'elements' && -n "$current_idea" && "$line" =~ ^####[[:space:]](.+)$ ]]; then
      current_subsection="${BASH_REMATCH[1]}"
      subsection_key="$current_idea|$current_subsection"
      subsection_count["$subsection_key"]=$(( ${subsection_count[$subsection_key]:-0} + 1 ))
      continue
    fi

    if [[ "$section" == 'elements' && -n "$current_idea" && -z "$current_subsection" && "$line" =~ ^-[[:space:]]([^:]+):[[:space:]](.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      idea_field_count["$current_idea|$key"]=$(( ${idea_field_count[$current_idea|$key]:-0} + 1 ))
      case "$key" in
        Title) idea_title["$current_idea"]="$value" ;;
        Branch) idea_branch["$current_idea"]="$value" ;;
        Status) idea_status["$current_idea"]="$value" ;;
        'Created at') idea_created["$current_idea"]="$value" ;;
        'Updated at') idea_updated["$current_idea"]="$value" ;;
        'Plan readiness') idea_readiness["$current_idea"]="$value" ;;
        Summary) idea_summary["$current_idea"]="$value" ;;
      esac
      continue
    fi

    if [[ "$section" == 'elements' && -n "$current_idea" && -n "$current_subsection" ]]; then
      subsection_key="$current_idea|$current_subsection"
      if [[ -n "${line//[[:space:]]/}" && "$line" != '<!--'* ]]; then
        subsection_has_content["$subsection_key"]=1
      fi
      if [[ "$line" == *'_Pending._'* ]]; then
        subsection_has_pending["$subsection_key"]=1
      fi
      if [[ "$line" =~ $citation_regex ]]; then
        subsection_has_citation["$subsection_key"]=1
      fi
    fi
  done < "$file"

  if [[ "$mode_status_count" -ne 1 || ( "$mode_status" != 'active' && "$mode_status" != 'inactive' ) ]]; then
    echo 'Brainstorm mode must contain exactly one Status field set to active or inactive.' >&2
    status=1
  fi
  if [[ "$active_session_count" -ne 1 || ! "$active_session" =~ ^BS-[0-9]{3,}$ ]]; then
    echo 'Brainstorm mode must contain exactly one valid Active session id.' >&2
    status=1
  fi
  if [[ "$activated_count" -ne 1 || ! "$activated_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo 'Brainstorm mode must contain exactly one canonical UTC Activated at value.' >&2
    status=1
  fi
  if [[ "$deactivated_count" -ne 1 ]]; then
    echo 'Brainstorm mode must contain exactly one Deactivated at field.' >&2
    status=1
  elif [[ "$mode_status" == 'active' && "$deactivated_at" != 'pending' ]]; then
    echo 'An active Brainstorm must set Deactivated at to pending.' >&2
    status=1
  elif [[ "$mode_status" == 'inactive' && ! "$deactivated_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo 'An inactive Brainstorm must contain a canonical UTC Deactivated at value.' >&2
    status=1
  fi
  if [[ "$required_state" != 'any' && "$mode_status" != "$required_state" ]]; then
    echo "Brainstorm state is $mode_status; expected $required_state." >&2
    status=1
  fi

  for branch_id in "${branch_ids[@]}"; do
    parent="${branch_parent[$branch_id]}"
    if [[ "$parent" != 'ROOT' && -z "${branch_parent[$parent]+x}" ]]; then
      echo "Brainstorm branch $branch_id references missing parent $parent." >&2
      status=1
    fi
    if [[ -z "${branch_title[$branch_id]}" || -z "${branch_summary[$branch_id]}" ]]; then
      echo "Brainstorm branch $branch_id requires a title and summary." >&2
      status=1
    fi

    local cursor="$branch_id"
    local -A path_seen=()
    while [[ "$cursor" != 'ROOT' ]]; do
      if [[ -n "${path_seen[$cursor]+x}" ]]; then
        echo "Brainstorm branch cycle detected at $cursor." >&2
        status=1
        break
      fi
      path_seen["$cursor"]=1
      cursor="${branch_parent[$cursor]:-MISSING}"
      if [[ "$cursor" == 'MISSING' ]]; then break; fi
    done
  done

  local field required_key readiness expected_readiness
  local -a required_fields=('Title' 'Branch' 'Status' 'Created at' 'Updated at' 'Plan readiness' 'Summary')
  for idea_id in "${idea_ids[@]}"; do
    for field in "${required_fields[@]}"; do
      required_key="$idea_id|$field"
      if [[ "${idea_field_count[$required_key]:-0}" -ne 1 ]]; then
        echo "Brainstorm element $idea_id requires exactly one $field field." >&2
        status=1
      fi
    done
    if [[ -z "${idea_title[$idea_id]:-}" || -z "${idea_summary[$idea_id]:-}" ]]; then
      echo "Brainstorm element $idea_id requires a non-empty title and summary." >&2
      status=1
    fi
    branch_id="${idea_branch[$idea_id]:-}"
    if [[ -z "$branch_id" || -z "${branch_parent[$branch_id]+x}" ]]; then
      echo "Brainstorm element $idea_id references missing branch ${branch_id:-<empty>}." >&2
      status=1
    fi
    case "${idea_status[$idea_id]:-}" in
      captured|clarifying|researching|plan-ready|parked) ;;
      *) echo "Brainstorm element $idea_id has invalid status: ${idea_status[$idea_id]:-<empty>}." >&2; status=1 ;;
    esac
    for value in "${idea_created[$idea_id]:-}" "${idea_updated[$idea_id]:-}"; do
      if [[ ! "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        echo "Brainstorm element $idea_id requires canonical UTC timestamps." >&2
        status=1
        break
      fi
    done
    readiness="${idea_readiness[$idea_id]:-}"
    expected_readiness='no'
    [[ "${idea_status[$idea_id]:-}" == 'plan-ready' ]] && expected_readiness='yes'
    if [[ "$readiness" != "$expected_readiness" ]]; then
      echo "Brainstorm element $idea_id plan readiness must be $expected_readiness for status ${idea_status[$idea_id]:-<empty>}." >&2
      status=1
    fi

    for current_subsection in "${required_subsections[@]}"; do
      subsection_key="$idea_id|$current_subsection"
      if [[ "${subsection_count[$subsection_key]:-0}" -ne 1 ]]; then
        echo "Brainstorm element $idea_id requires exactly one '$current_subsection' subsection." >&2
        status=1
      elif [[ "${subsection_has_content[$subsection_key]:-0}" -ne 1 ]]; then
        echo "Brainstorm element $idea_id subsection '$current_subsection' must contain content or _Pending._." >&2
        status=1
      fi
      if [[ "${idea_status[$idea_id]:-}" == 'plan-ready' && "${subsection_has_pending[$subsection_key]:-0}" -eq 1 ]]; then
        echo "Plan-ready Brainstorm element $idea_id cannot contain pending subsection content." >&2
        status=1
      fi
    done
    subsection_key="$idea_id|Research Findings and Citations"
    if [[ "${idea_status[$idea_id]:-}" == 'plan-ready' && "${subsection_has_citation[$subsection_key]:-0}" -ne 1 ]]; then
      echo "Plan-ready Brainstorm element $idea_id requires at least one HTTP(S) research citation." >&2
      status=1
    fi
  done

  OPENCAW_BRAINSTORM_MODE_STATUS="$mode_status"
  OPENCAW_BRAINSTORM_ACTIVE_SESSION="$active_session"
  OPENCAW_BRAINSTORM_DEACTIVATED_AT="$deactivated_at"
  OPENCAW_BRAINSTORM_BRANCH_COUNT="${#branch_ids[@]}"
  OPENCAW_BRAINSTORM_ELEMENT_COUNT="${#idea_ids[@]}"
  OPENCAW_BRAINSTORM_BRANCH_IDS=("${branch_ids[@]}")
  OPENCAW_BRAINSTORM_IDEA_IDS=("${idea_ids[@]}")
  declare -gA OPENCAW_BRAINSTORM_BRANCH_PARENT=()
  declare -gA OPENCAW_BRAINSTORM_BRANCH_TITLE=()
  declare -gA OPENCAW_BRAINSTORM_IDEA_BRANCH=()
  declare -gA OPENCAW_BRAINSTORM_IDEA_TITLE=()
  declare -gA OPENCAW_BRAINSTORM_IDEA_STATUS=()
  declare -gA OPENCAW_BRAINSTORM_IDEA_READINESS=()
  declare -gA OPENCAW_BRAINSTORM_IDEA_SUMMARY=()
  for branch_id in "${branch_ids[@]}"; do
    OPENCAW_BRAINSTORM_BRANCH_PARENT["$branch_id"]="${branch_parent[$branch_id]}"
    OPENCAW_BRAINSTORM_BRANCH_TITLE["$branch_id"]="${branch_title[$branch_id]}"
  done
  for idea_id in "${idea_ids[@]}"; do
    OPENCAW_BRAINSTORM_IDEA_BRANCH["$idea_id"]="${idea_branch[$idea_id]}"
    OPENCAW_BRAINSTORM_IDEA_TITLE["$idea_id"]="${idea_title[$idea_id]}"
    OPENCAW_BRAINSTORM_IDEA_STATUS["$idea_id"]="${idea_status[$idea_id]}"
    OPENCAW_BRAINSTORM_IDEA_READINESS["$idea_id"]="${idea_readiness[$idea_id]}"
    OPENCAW_BRAINSTORM_IDEA_SUMMARY["$idea_id"]="${idea_summary[$idea_id]}"
  done

  [[ $status -eq 0 ]]
}

brainstorm_branch_path() {
  local branch_id="$1"
  local cursor="$branch_id" path=''
  local -a parts=()

  while [[ "$cursor" != 'ROOT' ]]; do
    parts+=("${OPENCAW_BRAINSTORM_BRANCH_TITLE[$cursor]}")
    cursor="${OPENCAW_BRAINSTORM_BRANCH_PARENT[$cursor]}"
  done
  local index
  for (( index=${#parts[@]}-1; index>=0; index-- )); do
    if [[ -z "$path" ]]; then path="${parts[$index]}"; else path+=" / ${parts[$index]}"; fi
  done
  printf '%s' "$path"
}

brainstorm_write_summary() {
  local source_file="$1"
  local target_file="$2"
  local generated_at hash branch_id idea_id path
  local -a sorted_branches=() sorted_ideas=()

  brainstorm_validate_file "$source_file" inactive
  generated_at="$OPENCAW_BRAINSTORM_DEACTIVATED_AT"
  hash="$(brainstorm_sha256 "$source_file")"
  if [[ ${#OPENCAW_BRAINSTORM_BRANCH_IDS[@]} -gt 0 ]]; then
    mapfile -t sorted_branches < <(printf '%s\n' "${OPENCAW_BRAINSTORM_BRANCH_IDS[@]}" | sort)
  fi
  if [[ ${#OPENCAW_BRAINSTORM_IDEA_IDS[@]} -gt 0 ]]; then
    mapfile -t sorted_ideas < <(printf '%s\n' "${OPENCAW_BRAINSTORM_IDEA_IDS[@]}" | sort)
  fi

  {
    echo '# Brainstorm Summary'
    echo
    echo '- Source: [BRAINSTORM.md](BRAINSTORM.md)'
    echo "- Generated at: $generated_at"
    echo "- Source SHA-256: \`$hash\`"
    echo "- Branch count: ${#sorted_branches[@]}"
    echo "- Element count: ${#sorted_ideas[@]}"
    echo
    if [[ ${#sorted_ideas[@]} -eq 0 ]]; then
      echo '## No Brainstorm Elements'
      echo
      echo '_No brainstorm elements have been recorded._'
    else
      for branch_id in "${sorted_branches[@]}"; do
        local has_ideas=0
        for idea_id in "${sorted_ideas[@]}"; do
          if [[ "${OPENCAW_BRAINSTORM_IDEA_BRANCH[$idea_id]}" == "$branch_id" ]]; then has_ideas=1; break; fi
        done
        [[ $has_ideas -eq 1 ]] || continue
        path="$(brainstorm_branch_path "$branch_id")"
        echo "## $path (\`$branch_id\`)"
        echo
        for idea_id in "${sorted_ideas[@]}"; do
          [[ "${OPENCAW_BRAINSTORM_IDEA_BRANCH[$idea_id]}" == "$branch_id" ]] || continue
          echo "- [$idea_id](BRAINSTORM.md#${idea_id,,}) | status: ${OPENCAW_BRAINSTORM_IDEA_STATUS[$idea_id]} | plan-ready: ${OPENCAW_BRAINSTORM_IDEA_READINESS[$idea_id]} | ${OPENCAW_BRAINSTORM_IDEA_TITLE[$idea_id]} — ${OPENCAW_BRAINSTORM_IDEA_SUMMARY[$idea_id]}"
        done
        echo
      done
    fi
  } > "$target_file"
}

brainstorm_validate_summary() {
  local source_file="${1:-$OPENCAW_BRAINSTORM_FILE}"
  local summary_file="${2:-$OPENCAW_BRAINSTORM_SUMMARY_FILE}"
  local expected_hash actual_hash summary_hash idea_id count

  brainstorm_validate_file "$source_file" inactive || return 1
  if [[ -L "$summary_file" ]]; then
    echo "Brainstorm summary must not be a symbolic link: $summary_file" >&2
    return 1
  fi
  if [[ ! -f "$summary_file" ]]; then
    echo "Missing Brainstorm summary: $summary_file" >&2
    return 1
  fi
  expected_hash="$(brainstorm_sha256 "$source_file")"
  summary_hash="$(sed -n 's/^- Source SHA-256: `\([0-9a-f]\{64\}\)`$/\1/p' "$summary_file" | tr -d '\r')"
  if [[ "$summary_hash" != "$expected_hash" ]]; then
    echo 'Brainstorm summary source hash does not match BRAINSTORM.md.' >&2
    return 1
  fi
  for idea_id in "${OPENCAW_BRAINSTORM_IDEA_IDS[@]}"; do
    count="$(grep -Fc -- "- [$idea_id](BRAINSTORM.md#${idea_id,,}) |" "$summary_file" || true)"
    if [[ "$count" -ne 1 ]]; then
      echo "Brainstorm summary must index $idea_id exactly once." >&2
      return 1
    fi
  done
  actual_hash="$(grep -Ec '^- \[IDEA-[0-9]{3,}\]\(BRAINSTORM\.md#idea-[0-9]{3,}\) \|' "$summary_file" || true)"
  if [[ "$actual_hash" -ne "${#OPENCAW_BRAINSTORM_IDEA_IDS[@]}" ]]; then
    echo 'Brainstorm summary contains missing or unexpected element entries.' >&2
    return 1
  fi
}
