#!/usr/bin/env bash

# Shared helpers for Gauntlet lifecycle commands. Calling commands must enable
# strict mode before sourcing this file.

gauntlet_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$gauntlet_lib_dir/memory-common.sh"
opencaw_resolve_paths

OPENCAW_GAUNTLETS_DIR="$OPENCAW_PROJECT_AI_DIR/gauntlets"

gauntlet_fail() {
  echo "$*" >&2
  return 1
}

gauntlet_validate_name() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    gauntlet_fail "$label must be lowercase kebab-case: $value"
    return 1
  fi
}

gauntlet_validate_identifier() {
  local value="$1"
  local label="$2"

  opencaw_validate_single_line "$value" "$label" || return 1
  if [[ ! "$value" =~ ^/?[A-Za-z0-9][A-Za-z0-9._:@/-]*$ ]] \
    || [[ "$value" == *'..'* || "$value" == *'//'* || "$value" == */ ]]; then
    gauntlet_fail "$label contains unsupported characters: $value"
    return 1
  fi
}

gauntlet_latest_round_file() {
  local round_dir="$1"

  [[ -d "$round_dir" ]] || return 0
  find "$round_dir" -maxdepth 1 -type f -name 'round-*.md' -print \
    | awk '
        {
          name = $0
          sub(/^.*\/round-/, "", name)
          sub(/\.md$/, "", name)
          if (name ~ /^[0-9]+$/) print name "\t" $0
        }
      ' \
    | LC_ALL=C sort -n -k1,1 \
    | tail -n 1 \
    | cut -f2-
}

gauntlet_trim() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

gauntlet_hash_file() {
  local file="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    gauntlet_fail 'A SHA-256 implementation is required (sha256sum, shasum, or openssl).'
    return 1
  fi
}

gauntlet_hash_text() {
  local value="$1"
  local temporary digest

  temporary="$(mktemp "${TMPDIR:-/tmp}/opencaw-gauntlet-hash.XXXXXX")"
  printf '%s\n' "$value" > "$temporary"
  if ! digest="$(gauntlet_hash_file "$temporary")"; then
    rm -f "$temporary"
    return 1
  fi
  rm -f "$temporary"
  printf '%s\n' "$digest"
}

gauntlet_extract_section() {
  local file="$1"
  local heading="$2"

  awk -v heading="$heading" '
    { sub(/\r$/, "") }
    $0 == "## " heading { in_section = 1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

gauntlet_extract_subsection() {
  local file="$1"
  local section="$2"
  local subsection="$3"

  awk -v section="$section" -v subsection="$subsection" '
    { sub(/\r$/, "") }
    $0 == "## " section { in_section = 1; next }
    /^## / && in_section { exit }
    in_section && $0 == "### " subsection { in_subsection = 1; next }
    in_section && in_subsection && /^### / { exit }
    in_section && in_subsection { print }
  ' "$file"
}

gauntlet_section_field() {
  local file="$1"
  local heading="$2"
  local key="$3"

  gauntlet_extract_section "$file" "$heading" \
    | awk -v prefix="- $key:" '
        index($0, prefix) == 1 {
          value = substr($0, length(prefix) + 1)
          sub(/^[[:space:]]+/, "", value)
          sub(/[[:space:]]+$/, "", value)
          print value
          exit
        }
      '
}

gauntlet_heading_count() {
  local file="$1"
  local heading="$2"
  awk -v target="## $heading" '{ sub(/\r$/, "") } $0 == target { count++ } END { print count + 0 }' "$file"
}

gauntlet_has_placeholder() {
  local value="$1"
  printf '%s\n' "$value" | grep -Eqi -- '(^|[^[:alnum:]])(todo|tbd|placeholder)([^[:alnum:]]|$)|<[^>]+>|describe an independently|define inspectable|define constraints|define allowed'
}

gauntlet_has_substance() {
  local value="$1"
  local stripped

  stripped="$(printf '%s\n' "$value" \
    | sed -E '/^[[:space:]]*$/d; /^<!--.*-->$/d; /^###[[:space:]]/d; s/^[[:space:]]*[-*][[:space:]]*//')"
  [[ -n "${stripped//[[:space:]]/}" ]] || return 1
  ! gauntlet_has_placeholder "$stripped"
}

gauntlet_quality_bar_fingerprint() {
  local gauntlet_file="$1"
  local content

  content="$(gauntlet_extract_section "$gauntlet_file" 'Approved Quality Bar')"
  gauntlet_hash_text "$content"
}

gauntlet_assert_safe_ai_path() {
  local path="$1"
  local label="$2"
  local project_root parent_canonical

  project_root="$(cd "$OPENCAW_PROJECT_ROOT_RESOLVED" && pwd -P)"
  [[ ! -L "$OPENCAW_PROJECT_AI_DIR" ]] || {
    gauntlet_fail "The project .ai directory must not be a symbolic link."
    return 1
  }
  [[ "$path" == "$OPENCAW_PROJECT_AI_DIR" || "$path" == "$OPENCAW_PROJECT_AI_DIR"/* ]] || {
    gauntlet_fail "$label is outside the resolved project .ai directory: $path"
    return 1
  }
  if [[ -L "$path" ]]; then
    gauntlet_fail "$label must not be a symbolic link: $path"
    return 1
  fi
  parent_canonical="$(cd "$(dirname "$path")" && pwd -P)"
  if [[ "$parent_canonical" != "$project_root/.ai" && "$parent_canonical" != "$project_root/.ai"/* ]]; then
    gauntlet_fail "$label resolves outside the project .ai directory: $path"
    return 1
  fi
}

gauntlet_resolve_file() {
  local ref="$1"
  local candidate gauntlets_root candidate_dir candidate_canonical project_root unit_dir_name

  [[ -d "$OPENCAW_GAUNTLETS_DIR" ]] || {
    gauntlet_fail "Gauntlet directory does not exist: $OPENCAW_GAUNTLETS_DIR"
    return 1
  }

  gauntlet_assert_safe_ai_path "$OPENCAW_GAUNTLETS_DIR" 'Gauntlet root' || return 1
  if [[ "$ref" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    candidate="$OPENCAW_GAUNTLETS_DIR/$ref/GAUNTLET.md"
  elif [[ -d "$ref" ]]; then
    candidate="$ref/GAUNTLET.md"
  else
    candidate="$ref"
  fi

  [[ -f "$candidate" ]] || {
    gauntlet_fail "Gauntlet file not found for: $ref"
    return 1
  }
  [[ ! -L "$candidate" ]] || {
    gauntlet_fail "Gauntlet file must not be a symbolic link: $candidate"
    return 1
  }

  [[ ! -L "$(dirname "$candidate")" ]] || {
    gauntlet_fail "Gauntlet directory must not be a symbolic link: $(dirname "$candidate")"
    return 1
  }

  project_root="$(cd "$OPENCAW_PROJECT_ROOT_RESOLVED" && pwd -P)"
  gauntlets_root="$(cd "$OPENCAW_GAUNTLETS_DIR" && pwd -P)"
  [[ "$gauntlets_root" == "$project_root/.ai/gauntlets" ]] || {
    gauntlet_fail "Gauntlet root resolves outside the canonical project path: $OPENCAW_GAUNTLETS_DIR"
    return 1
  }
  candidate_dir="$(cd "$(dirname "$candidate")" && pwd -P)"
  candidate_canonical="$candidate_dir/$(basename "$candidate")"
  unit_dir_name="$(basename "$candidate_dir")"

  if [[ "$(dirname "$candidate_dir")" != "$gauntlets_root" ]] \
    || ! gauntlet_validate_name "$unit_dir_name" 'Gauntlet directory name' \
    || [[ "$candidate_canonical" != "$candidate_dir/GAUNTLET.md" ]]; then
    gauntlet_fail "Gauntlet references must resolve under $OPENCAW_GAUNTLETS_DIR: $ref"
    return 1
  fi

  printf '%s\n' "$candidate_canonical"
}

gauntlet_project_relative_artifact() {
  local value="$1"
  local project_root candidate_dir canonical

  value="${value#\`}"
  value="${value%\`}"
  if [[ -z "$value" || "$value" == /* || "$value" == .. || "$value" == ../* || "$value" == */../* || "$value" == */.. ]]; then
    gauntlet_fail "Artifact paths must be project-relative and must not traverse parents: $value"
    return 1
  fi

  project_root="$(cd "$OPENCAW_PROJECT_ROOT_RESOLVED" && pwd -P)"
  [[ -f "$project_root/$value" ]] || {
    gauntlet_fail "Inspected artifact does not exist as a regular file: $value"
    return 1
  }
  [[ ! -L "$project_root/$value" ]] || {
    gauntlet_fail "Inspected artifacts must not be symbolic links: $value"
    return 1
  }

  candidate_dir="$(cd "$(dirname "$project_root/$value")" && pwd -P)"
  canonical="$candidate_dir/$(basename "$value")"
  if [[ "$canonical" != "$project_root"/* ]]; then
    gauntlet_fail "Inspected artifact resolves outside the project root: $value"
    return 1
  fi

  printf '%s\n' "${canonical#"$project_root"/}"
}

gauntlet_validate_critic_report() {
  local report_file="$1"
  local expected_verdict="$2"
  local -a headings=(
    'Artifact Inspected'
    'Bar Comparison'
    'Guardrail Results'
    'Verdict'
    'Largest Remaining Gap'
    'Next Strategy'
  )
  local heading content artifact artifact_count=0 verdict_section verdict_count=0 verdict='' line
  local largest_gap normalized_gap next_strategy normalized_strategy
  local previous_line=0 current_line

  [[ -f "$report_file" && ! -L "$report_file" ]] || {
    gauntlet_fail "Critic report not found as a regular non-symlink file: $report_file"
    return 1
  }

  for heading in "${headings[@]}"; do
    if [[ "$(gauntlet_heading_count "$report_file" "$heading")" -ne 1 ]]; then
      gauntlet_fail "Critic report requires exactly one '## $heading' heading."
      return 1
    fi
    current_line="$(grep -nF -m 1 -- "## $heading" "$report_file" | cut -d: -f1)"
    if [[ $current_line -le $previous_line ]]; then
      gauntlet_fail "Critic report headings are out of order at: ## $heading"
      return 1
    fi
    previous_line="$current_line"
  done

  content="$(gauntlet_extract_section "$report_file" 'Artifact Inspected')"
  while IFS= read -r artifact; do
    artifact="${artifact#- Artifact:}"
    artifact="$(gauntlet_trim "$artifact")"
    gauntlet_project_relative_artifact "$artifact" >/dev/null || return 1
    artifact_count=$((artifact_count + 1))
  done < <(printf '%s\n' "$content" | grep -E '^- Artifact:[[:space:]]*[^[:space:]]' || true)
  if [[ $artifact_count -lt 1 ]]; then
    gauntlet_fail "Artifact Inspected must include at least one '- Artifact: <project-relative-file>' entry."
    return 1
  fi

  content="$(gauntlet_extract_section "$report_file" 'Bar Comparison')"
  gauntlet_has_substance "$content" || {
    gauntlet_fail 'Bar Comparison must contain substantive evidence.'
    return 1
  }
  content="$(gauntlet_extract_section "$report_file" 'Guardrail Results')"
  gauntlet_has_substance "$content" || {
    gauntlet_fail 'Guardrail Results must contain substantive evidence.'
    return 1
  }

  verdict_section="$(gauntlet_extract_section "$report_file" 'Verdict')"
  while IFS= read -r line; do
    line="$(gauntlet_trim "$line")"
    if [[ "$line" =~ ^-[[:space:]]+Verdict:[[:space:]]*(pass|fail|blocked)$ ]]; then
      verdict="${BASH_REMATCH[1]}"
      verdict_count=$((verdict_count + 1))
    elif [[ "$line" =~ ^(pass|fail|blocked)$ ]]; then
      verdict="${BASH_REMATCH[1]}"
      verdict_count=$((verdict_count + 1))
    fi
  done <<< "$verdict_section"
  if [[ $verdict_count -ne 1 ]]; then
    gauntlet_fail "Verdict must contain exactly one verdict: pass, fail, or blocked."
    return 1
  fi
  if [[ "$verdict" != "$expected_verdict" ]]; then
    gauntlet_fail "Critic report verdict '$verdict' does not match CLI verdict '$expected_verdict'."
    return 1
  fi

  largest_gap="$(gauntlet_extract_section "$report_file" 'Largest Remaining Gap')"
  gauntlet_has_substance "$largest_gap" || {
    gauntlet_fail 'Largest Remaining Gap must contain a substantive finding.'
    return 1
  }
  next_strategy="$(gauntlet_extract_section "$report_file" 'Next Strategy')"
  gauntlet_has_substance "$next_strategy" || {
    gauntlet_fail 'Next Strategy must contain substantive guidance.'
    return 1
  }

  if [[ "$expected_verdict" != 'pass' ]]; then
    normalized_gap="$(printf '%s\n' "$largest_gap" \
      | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^(Largest[[:space:]]+Remaining[[:space:]]+)?Gap:[[:space:]]*//I; /^[[:space:]]*$/d' \
      | tr '[:upper:]' '[:lower:]')"
    normalized_strategy="$(printf '%s\n' "$next_strategy" \
      | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^(Next[[:space:]]+)?Strategy:[[:space:]]*//I; /^[[:space:]]*$/d' \
      | tr '[:upper:]' '[:lower:]')"
    if printf '%s\n' "$normalized_gap" | grep -Eqi -- '^[[:space:]]*(none|n/?a|not applicable)[.!]?[[:space:]]*$'; then
      gauntlet_fail 'A failed or blocked verdict requires a concrete largest remaining gap.'
      return 1
    fi
    if printf '%s\n' "$normalized_strategy" | grep -Eqi -- '^[[:space:]]*(none|n/?a|not applicable|retry|try again)[.!]?[[:space:]]*$'; then
      gauntlet_fail 'A failed or blocked verdict requires a concrete changed strategy.'
      return 1
    fi
  fi

  normalized_strategy="$(printf '%s\n' "$next_strategy" \
    | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/^(Next[[:space:]]+)?Strategy:[[:space:]]*//I; /^[[:space:]]*$/d; s/[[:space:]]+/ /g' \
    | tr '[:upper:]' '[:lower:]')"
  # Consumed by record-gauntlet-round.sh after this validator returns.
  # shellcheck disable=SC2034
  GAUNTLET_CRITIC_STRATEGY_FINGERPRINT="$(gauntlet_hash_text "$normalized_strategy")"
}

gauntlet_work_unit_lines() {
  local file="$1"
  gauntlet_extract_section "$file" 'Work Units' | grep -E '^- \[[ xX]\] ' || true
}

gauntlet_set_section_field() {
  local file="$1"
  local heading="$2"
  local key="$3"
  local value="$4"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-field.XXXXXX")"
  if ! awk -v heading="$heading" -v prefix="- $key:" -v replacement="- $key: $value" '
      { sub(/\r$/, "") }
      $0 == "## " heading { in_section = 1 }
      /^## / && $0 != "## " heading && in_section { in_section = 0 }
      in_section && index($0, prefix) == 1 {
        print replacement
        replaced++
        next
      }
      { print }
      END { if (replaced != 1) exit 42 }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Expected exactly one '$key' field in '$heading'."
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_set_work_unit_status() {
  local file="$1"
  local item_id="$2"
  local status="$3"
  local checkbox=' '
  local temporary

  if [[ "$status" == 'passed' || "$status" == 'superseded' ]]; then
    checkbox='x'
  fi

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-unit.XXXXXX")"
  if ! awk -v item="$item_id" -v status="$status" -v checkbox="$checkbox" '
      { sub(/\r$/, "") }
      $0 == "## Work Units" { in_section = 1 }
      /^## / && $0 != "## Work Units" && in_section { in_section = 0 }
      in_section && $0 ~ "^- \\[[ xX]\\] " item " \\| status: " {
        split($0, parts, " \\| title: ")
        if (length(parts[2]) == 0) exit 43
        print "- [" checkbox "] " item " | status: " status " | title: " parts[2]
        replaced++
        next
      }
      { print }
      END { if (replaced != 1) exit 42 }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Expected exactly one work unit named: $item_id"
    return 1
  fi
  mv "$temporary" "$file"
}

gauntlet_reopen_active_units() {
  local file="$1"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-reopen.XXXXXX")"
  awk '
    { sub(/\r$/, "") }
    $0 == "## Work Units" { in_section = 1 }
    /^## / && $0 != "## Work Units" && in_section { in_section = 0 }
    in_section && $0 ~ /^- \[[ xX]\] [a-z0-9-]+ \| status: (pending|building|critic-failed|passed|blocked) \| title: / {
      line = $0
      sub(/^- \[[ xX]\]/, "- [ ]", line)
      sub(/\| status: (pending|building|critic-failed|passed|blocked) \|/, "| status: critic-failed |", line)
      print line
      next
    }
    { print }
  ' "$file" > "$temporary"
  mv "$temporary" "$file"
}

gauntlet_append_round_ledger() {
  local file="$1"
  local entry="$2"
  local temporary

  temporary="$(mktemp "$(dirname "$file")/.gauntlet-ledger.XXXXXX")"
  if ! awk -v entry="$entry" '
      { sub(/\r$/, "") }
      $0 == "## Round Ledger" { in_section = 1; found = 1; print; next }
      /^## / && in_section {
        if (!inserted) print entry
        in_section = 0
        inserted = 1
      }
      in_section && $0 == "- No rounds recorded." { next }
      { print }
      END {
        if (in_section && !inserted) print entry
        if (!found) exit 42
      }
    ' "$file" > "$temporary"; then
    rm -f "$temporary"
    gauntlet_fail "Missing Round Ledger section."
    return 1
  fi
  mv "$temporary" "$file"
}
