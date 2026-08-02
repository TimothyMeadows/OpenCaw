#!/usr/bin/env bash
# shellcheck disable=SC2016 # Markdown backticks are intentional literal fixture content.
set -Eeuo pipefail
export LC_ALL=C
export LANG=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

temp_root="$(mktemp -d "${TMPDIR:-/tmp}/opencaw-gauntlet.XXXXXX")"
network_marker="$temp_root/network-command-used"
cleanup() {
  if [[ "${OPENCAW_TEST_PRESERVE_TMP:-0}" == 1 ]]; then
    printf 'Preserved Gauntlet test fixture: %s\n' "$temp_root" >&2
    return
  fi
  case "$temp_root" in
    */opencaw-gauntlet.*) rm -rf -- "$temp_root" ;;
  esac
}
trap cleanup EXIT

report_unhandled_error() {
  local exit_code="$1"
  local source_line="$2"
  local failed_command="$3"
  if [[ $- == *e* ]]; then
    printf 'FAIL: unhandled command exited %s at %s:%s: %s\n' \
      "$exit_code" "${BASH_SOURCE[1]}" "$source_line" "$failed_command" >&2
  fi
  return "$exit_code"
}
trap 'report_unhandled_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  local output_file="$1"
  local result
  shift
  set +e
  ( "$@" ) >"$output_file" 2>&1
  result=$?
  set -e
  if [[ $result -eq 125 ]] || grep -Fq 'HARNESS_SETUP_FAILURE' "$output_file"; then
    sed -n '1,200p' "$output_file" >&2
    fail "test harness setup failed before the expected command rejection: $*"
  fi
  [[ $result -ne 0 ]] || fail "command unexpectedly succeeded: $*"
}

expect_file() {
  [[ -f "$1" ]] || fail "expected file was not created: $1"
}

expect_line() {
  local expected="$1"
  local file="$2"
  awk -v expected="$expected" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$file" \
    || fail "expected line was not found in $file: $expected"
}

wait_for_path() {
  local path="$1"
  local attempts=0
  while [[ ! -e "$path" && $attempts -lt 200 ]]; do
    sleep 0.01
    attempts=$((attempts + 1))
  done
  [[ -e "$path" ]] || fail "timed out waiting for concurrent fixture path: $path"
}

replace_line() {
  local file="$1"
  local before="$2"
  local after="$3"
  local temporary="$file.replace"
  awk -v before="$before" -v after="$after" '
    { sub(/\r$/, "") }
    $0 == before { print after; replaced=1; next }
    { print }
    END { if (!replaced) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "fixture line was not found in $file: $before"
  }
  mv "$temporary" "$file"
}

replace_section_line() {
  local file="$1"
  local section="$2"
  local before="$3"
  local after="$4"
  local temporary="$file.section-replace"
  awk -v heading="## $section" -v before="$before" -v after="$after" '
    { sub(/\r$/, "") }
    $0 == heading { in_section=1 }
    /^## / && $0 != heading && in_section { in_section=0 }
    in_section && $0 == before { print after; replaced++; next }
    { print }
    END { if (replaced != 1) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "expected exactly one line in section '$section' of $file: $before"
  }
  mv "$temporary" "$file"
}

insert_after_section_line() {
  local file="$1"
  local section="$2"
  local before="$3"
  local inserted_line="$4"
  local temporary="$file.section-insert"
  awk -v heading="## $section" -v before="$before" -v inserted="$inserted_line" '
    { sub(/\r$/, "") }
    $0 == heading { in_section=1 }
    /^## / && $0 != heading && in_section { in_section=0 }
    in_section && $0 == before {
      print
      print inserted
      inserted_count++
      next
    }
    { print }
    END { if (inserted_count != 1) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "expected exactly one insertion point in section '$section' of $file: $before"
  }
  mv "$temporary" "$file"
}

replace_matching_line() {
  local file="$1"
  local pattern="$2"
  local after="$3"
  local temporary="$file.replace"
  awk -v pattern="$pattern" -v after="$after" '
    { sub(/\r$/, "") }
    $0 ~ pattern { print after; replaced=1; next }
    { print }
    END { if (!replaced) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "fixture pattern was not found in $file: $pattern"
  }
  mv "$temporary" "$file"
}

insert_after_matching_line() {
  local file="$1"
  local pattern="$2"
  local inserted_line="$3"
  local temporary="$file.insert"
  awk -v pattern="$pattern" -v inserted="$inserted_line" '
    { print }
    $0 ~ pattern { print inserted; matched=1 }
    END { if (!matched) exit 42 }
  ' "$file" >"$temporary" || {
    rm -f -- "$temporary"
    fail "fixture insertion pattern was not found in $file: $pattern"
  }
  mv "$temporary" "$file"
}

replace_all_literal() {
  local file="$1"
  local before="$2"
  local after="$3"
  local temporary="$file.replace"
  local line
  : >"$temporary"
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "${line//$before/$after}" >>"$temporary"
  done <"$file"
  mv "$temporary" "$file"
}

round_file_count() {
  local gauntlet="$1"
  if [[ ! -d "$gauntlet/rounds" ]]; then
    echo 0
    return
  fi
  find "$gauntlet/rounds" -type f -name 'round-*.md' | wc -l | tr -d ' '
}

pr_event_file_count() {
  local gauntlet="$1"
  if [[ ! -d "$gauntlet/pr-events" ]]; then
    echo 0
    return
  fi
  find "$gauntlet/pr-events" -type f -name 'event-*.md' | wc -l | tr -d ' '
}

completion_event_file_count() {
  local gauntlet="$1"
  if [[ ! -d "$gauntlet/completion-events" ]]; then
    echo 0
    return
  fi
  find "$gauntlet/completion-events" -maxdepth 1 -type f -name 'event-*.md' \
    | wc -l | tr -d ' '
}

assert_no_completion_staging() {
  local gauntlet="$1"
  local staged
  staged="$(find "$gauntlet" -maxdepth 1 -type f \
    \( -name '.completion-stage.*' -o -name '.report-stage.*' \
      -o -name '.backup-stage.*' -o -name '.completion-event-stage.*' \
      -o -name '.completion-ledger-stage.*' -o -name '.report-rewrite-stage.*' \
      -o -name '.report-backup.*' \) -print -quit)"
  [[ -z "$staged" ]] || fail "completion transaction left staging evidence: $staged"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{ print $1 }'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{ print $1 }'
  fi
}

gauntlet_helper_value() {
  local project="$1"
  local helper="$2"
  shift 2
  OPENCAW_PROJECT_ROOT="$project" bash -c '
    set -euo pipefail
    source commands/lib/gauntlet-common.sh
    "$@"
  ' _ "$helper" "$@"
}

select_ledger_line() {
  local project="$1"
  local file="$2"
  local section="$3"
  local field="$4"
  local evidence_path="$5"
  local selected
  local selected_count

  selected="$(gauntlet_helper_value "$project" gauntlet_extract_section \
    "$file" "$section" | awk -v marker="| $field: $evidence_path |" '
      index($0, marker) { print }
    ')"
  selected_count="$(printf '%s\n' "$selected" \
    | awk 'NF { count++ } END { print count + 0 }')"
  [[ "$selected_count" == 1 ]] \
    || fail "expected exactly one $section row with $field: $evidence_path in $file"
  printf '%s\n' "$selected"
}

unit_manifest_fingerprint() {
  gauntlet_helper_value "$1" gauntlet_unit_manifest_fingerprint "$2"
}

active_scope_fingerprint() {
  gauntlet_helper_value "$1" gauntlet_active_scope_fingerprint "$2"
}

unit_scope_fingerprint() {
  gauntlet_helper_value "$1" gauntlet_unit_scope_fingerprint "$2" "$3"
}

set_gauntlet_field() {
  gauntlet_helper_value "$1" gauntlet_set_section_field \
    "$2" "$3" "$4" "$5" >/dev/null
}

reset_integration_review() {
  gauntlet_helper_value "$1" gauntlet_reset_integration_review "$2" >/dev/null
}

refresh_copied_evidence_hashes() {
  local gauntlet_dir="$1"
  local gauntlet_name
  local evidence_file
  local relative_path
  local ledger_line
  local ledger_match
  local ledger_matches
  local ledger_match_count
  local ledger_section
  local primary_ledger_section
  local report_ledger_section
  local ledger_required
  local ledger_target
  local updated_line
  local evidence_hash
  local opened_hash
  local root_hash
  local checkpoint_hash
  local report_projection
  gauntlet_name="$(basename "$gauntlet_dir")"
  while IFS= read -r evidence_file; do
    [[ -n "$evidence_file" ]] || continue
    relative_path=".ai/gauntlets/$gauntlet_name/${evidence_file#"$gauntlet_dir"/}"
    evidence_hash="$(sha256_file "$evidence_file")"
    case "$relative_path" in
      */rounds/*/round-*.md)
        ledger_match="| evidence: $relative_path | sha256:"
        primary_ledger_section='Round Ledger'
        report_ledger_section='Immutable Round Evidence'
        opened_hash="$(sed -nE 's/^- Opened event sha256: (.*)$/\1/p' \
          "$evidence_file" | head -n 1)"
        root_hash="$(sed -nE 's/^- Remediation root sha256: (.*)$/\1/p' \
          "$evidence_file" | head -n 1)"
        [[ "$opened_hash" == none || "$opened_hash" =~ ^[0-9a-f]{64}$ ]] \
          || fail "copied round omitted a canonical opened-event hash: $evidence_file"
        [[ "$root_hash" == none || "$root_hash" =~ ^[0-9a-f]{64}$ ]] \
          || fail "copied round omitted a canonical remediation-root hash: $evidence_file"
        checkpoint_hash=''
        report_projection=''
        ;;
      */pr-events/*/event-*.md)
        ledger_match="| record: $relative_path | sha256:"
        primary_ledger_section='Progress PR Ledger'
        report_ledger_section='Ordered Progress PR and QA Evidence'
        checkpoint_hash="$(sed -nE \
          's/^- Publication checkpoint sha256: (.*)$/\1/p' \
          "$evidence_file" | head -n 1)"
        [[ "$checkpoint_hash" =~ ^[0-9a-f]{64}$ ]] \
          || fail "copied PR event omitted a canonical checkpoint hash: $evidence_file"
        opened_hash=''
        root_hash=''
        report_projection=''
        ;;
      */completion-events/event-*.md)
        ledger_match="| record: $relative_path | sha256:"
        primary_ledger_section='Completion Ledger'
        report_ledger_section='Immutable Completion Evidence'
        report_projection="$(sed -nE \
          's/^- Report projection sha256: (.*)$/\1/p' \
          "$evidence_file" | head -n 1)"
        [[ "$report_projection" =~ ^[0-9a-f]{64}$ ]] \
          || fail "copied completion event omitted a canonical report projection: $evidence_file"
        opened_hash=''
        root_hash=''
        checkpoint_hash=''
        ;;
      *)
        ledger_match="| record: $relative_path | sha256:"
        primary_ledger_section='Promotion QA Ledger'
        report_ledger_section='Promotion QA Evidence'
        opened_hash=''
        root_hash=''
        checkpoint_hash=''
        report_projection=''
        ;;
    esac
    while IFS= read -r ledger_target; do
      [[ -f "$ledger_target" ]] || continue
      if [[ "$(basename "$ledger_target")" == GAUNTLET.md ]]; then
        ledger_section="$primary_ledger_section"
        ledger_required=1
      else
        ledger_section="$report_ledger_section"
        ledger_required=0
      fi
      ledger_matches="$(awk -v heading="## $ledger_section" \
        -v needle="$ledger_match" '
          { sub(/\r$/, "") }
          $0 == heading { in_section=1; next }
          /^## / && in_section { exit }
          in_section && index($0, needle) { print }
        ' "$ledger_target")"
      ledger_match_count="$(printf '%s\n' "$ledger_matches" \
        | awk 'NF { count++ } END { print count + 0 }')"
      if [[ $ledger_required -eq 1 ]]; then
        [[ "$ledger_match_count" -eq 1 ]] \
          || fail "copied $ledger_section requires one exact row for $relative_path"
      else
        [[ "$ledger_match_count" -le 1 ]] \
          || fail "copied $ledger_section duplicates the row for $relative_path"
        [[ "$ledger_match_count" -eq 1 ]] || continue
      fi
      ledger_line="$ledger_matches"
      updated_line="$ledger_line"
      if [[ -n "$opened_hash" ]]; then
        updated_line="$(printf '%s\n' "$updated_line" | awk \
          -v opened="$opened_hash" -v root="$root_hash" '
          {
            opened_count = sub(/\| opened-sha256: [^ |]+ \|/,
              "| opened-sha256: " opened " |")
            root_count = sub(/\| root-sha256: [^ |]+ \|/,
              "| root-sha256: " root " |")
            if (opened_count != 1 || root_count != 1) exit 42
            print
          }
        ')" || fail "copied Round Ledger row is noncanonical: $relative_path"
      fi
      if [[ -n "$checkpoint_hash" ]]; then
        updated_line="$(printf '%s\n' "$updated_line" | awk \
          -v checkpoint="$checkpoint_hash" '
          {
            count = sub(/\| checkpoint-sha256: [^ |]+ \|/,
              "| checkpoint-sha256: " checkpoint " |")
            if (count != 1) exit 42
            print
          }
        ')" || fail "copied Progress PR Ledger row is noncanonical: $relative_path"
      fi
      if [[ -n "$report_projection" ]]; then
        updated_line="$(printf '%s\n' "$updated_line" | awk \
          -v projection="$report_projection" '
          {
            count = sub(/\| report-projection: [^ |]+ \|/,
              "| report-projection: " projection " |")
            if (count != 1) exit 42
            print
          }
        ')" || fail "copied Completion Ledger row is noncanonical: $relative_path"
      fi
      updated_line="${updated_line%sha256:*}sha256: $evidence_hash"
      replace_section_line "$ledger_target" "$ledger_section" \
        "$ledger_line" "$updated_line"
    done < <(find "$gauntlet_dir" -type f \
      \( -name 'GAUNTLET.md' -o -name 'GAUNTLET_REPORT*.md' \) \
      -print 2>/dev/null | LC_ALL=C sort)
  done < <(find "$gauntlet_dir/rounds" "$gauntlet_dir/pr-events" \
    "$gauntlet_dir/promotion-events" "$gauntlet_dir/completion-events" -type f \
    \( -name 'round-*.md' -o -name 'event-*.md' \) -print 2>/dev/null | LC_ALL=C sort)
}

assert_safe_copied_reference() {
  local project_root="$1"
  local gauntlet_name="$2"
  local referenced="$3"
  local kind="$4"
  local referenced_file="$project_root/$referenced"
  case "$kind" in
    opened)
      [[ "$referenced" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/[a-z0-9]+(-[a-z0-9]+)*/event-[0-9]{3,}\.md$ ]] \
        || fail "copied round has a noncanonical opened-event reference: $referenced"
      ;;
    root|trigger)
      [[ "$referenced" =~ ^\.ai/gauntlets/${gauntlet_name}/(rounds/[a-z0-9]+(-[a-z0-9]+)*/round-[0-9]{3,}|pr-events/[a-z0-9]+(-[a-z0-9]+)*/event-[0-9]{3,}|promotion-events/event-[0-9]{3,})\.md$ ]] \
        || fail "copied evidence has a noncanonical remediation reference: $referenced"
      ;;
    archive)
      [[ "$referenced" =~ ^\.ai/gauntlets/${gauntlet_name}/promotion-events/GAUNTLET_REPORT-before-event-[0-9]{3,}\.md$ ]] \
        || fail "copied promotion event has a noncanonical report archive: $referenced"
      ;;
    *) fail "unknown copied-reference kind: $kind" ;;
  esac
  [[ -f "$referenced_file" && ! -L "$referenced_file" ]] \
    || fail "copied evidence reference is missing or unsafe: $referenced"
  gauntlet_helper_value "$project_root" gauntlet_assert_safe_ai_path \
    "$referenced_file" "Copied $kind evidence" >/dev/null \
    || fail "copied evidence reference escaped the project root: $referenced"
}

refresh_copied_checkpoint_hashes() {
  local gauntlet_dir="$1"
  local gauntlet_name project_root gauntlet_file checkpoint checkpoint_relative checkpoint_hash
  local remediation_trigger remediation_trigger_hash recorded_trigger_hash
  local remediation_root remediation_root_file remediation_root_hash recorded_root_hash
  local event_file
  gauntlet_name="$(basename "$gauntlet_dir")"
  project_root="$(cd "$gauntlet_dir/../../.." && pwd -P)"
  gauntlet_file="$gauntlet_dir/GAUNTLET.md"
  while IFS= read -r checkpoint; do
    [[ -n "$checkpoint" ]] || continue
    checkpoint_relative=".ai/gauntlets/$gauntlet_name/${checkpoint#"$gauntlet_dir"/}"
    remediation_trigger="$(sed -nE \
      's/^- Remediation trigger: (.*)$/\1/p' "$checkpoint" | head -n 1)"
    if [[ "$remediation_trigger" != none \
      && "$remediation_trigger" != quality-revision:* ]]; then
      assert_safe_copied_reference "$project_root" "$gauntlet_name" \
        "$remediation_trigger" trigger
    fi
    recorded_trigger_hash="$(sed -nE \
      's/^- Remediation trigger sha256: (.*)$/\1/p' "$checkpoint" | head -n 1)"
    if remediation_trigger_hash="$(gauntlet_helper_value "$project_root" \
      gauntlet_remediation_trigger_hash "$gauntlet_file" \
      "$remediation_trigger" 2>/dev/null)" \
      && [[ -n "$recorded_trigger_hash" \
        && "$recorded_trigger_hash" != "$remediation_trigger_hash" ]]; then
      set_gauntlet_field "$project_root" "$checkpoint" \
        'Publication Checkpoint Metadata' 'Remediation trigger sha256' \
        "$remediation_trigger_hash"
    fi
    remediation_root="$(sed -nE \
      's/^- Remediation root: (.*)$/\1/p' "$checkpoint" | head -n 1)"
    if [[ "$remediation_root" != none \
      && ( "$remediation_root" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/[a-z0-9]+(-[a-z0-9]+)*/round-[0-9]{3,}\.md$ \
        || "$remediation_root" =~ ^\.ai/gauntlets/${gauntlet_name}/pr-events/[a-z0-9]+(-[a-z0-9]+)*/event-[0-9]{3,}\.md$ \
        || "$remediation_root" =~ ^\.ai/gauntlets/${gauntlet_name}/promotion-events/event-[0-9]{3,}\.md$ ) ]]; then
      remediation_root_file="$project_root/$remediation_root"
      if [[ -f "$remediation_root_file" && ! -L "$remediation_root_file" ]] \
        && gauntlet_helper_value "$project_root" gauntlet_assert_safe_ai_path \
          "$remediation_root_file" 'Copied checkpoint remediation root' \
          >/dev/null 2>&1; then
        remediation_root_hash="$(sha256_file "$remediation_root_file")"
        recorded_root_hash="$(sed -nE \
          's/^- Remediation root sha256: (.*)$/\1/p' "$checkpoint" | head -n 1)"
        if [[ -n "$recorded_root_hash" \
          && "$recorded_root_hash" != "$remediation_root_hash" ]]; then
          set_gauntlet_field "$project_root" "$checkpoint" \
            'Publication Checkpoint Metadata' 'Remediation root sha256' \
            "$remediation_root_hash"
        fi
      fi
    fi
    checkpoint_hash="$(sha256_file "$checkpoint")"
    while IFS= read -r event_file; do
      [[ -n "$event_file" ]] || continue
      grep -Fqx -- "- Publication checkpoint: $checkpoint_relative" "$event_file" \
        || continue
      set_gauntlet_field "$project_root" "$event_file" 'PR Event Metadata' \
        'Publication checkpoint sha256' "$checkpoint_hash"
    done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' \
      -print 2>/dev/null | LC_ALL=C sort)
  done < <(find "$gauntlet_dir/publication-checkpoints" -type f \
    -name 'checkpoint-*.md' -print 2>/dev/null | LC_ALL=C sort)
}

refresh_copied_cross_evidence_hashes() {
  local gauntlet_dir="$1"
  local gauntlet_name project_root round referenced hash promotion archive
  gauntlet_name="$(basename "$gauntlet_dir")"
  project_root="$(cd "$gauntlet_dir/../../.." && pwd -P)"
  while IFS= read -r round; do
    [[ -n "$round" ]] || continue
    referenced="$(sed -nE 's/^- Opened event: (.*)$/\1/p' "$round" | head -n 1)"
    if [[ -n "$referenced" && "$referenced" != none ]]; then
      assert_safe_copied_reference "$project_root" "$gauntlet_name" \
        "$referenced" opened
      hash="$(sha256_file "$project_root/$referenced")"
      set_gauntlet_field "$project_root" "$round" 'Round Metadata' \
        'Opened event sha256' "$hash"
    fi
    referenced="$(sed -nE 's/^- Remediation root: (.*)$/\1/p' "$round" | head -n 1)"
    if [[ -n "$referenced" && "$referenced" != none ]]; then
      assert_safe_copied_reference "$project_root" "$gauntlet_name" \
        "$referenced" root
      hash="$(sha256_file "$project_root/$referenced")"
      set_gauntlet_field "$project_root" "$round" 'Round Metadata' \
        'Remediation root sha256' "$hash"
    fi
  done < <(find "$gauntlet_dir/rounds" -type f -name 'round-*.md' \
    -print 2>/dev/null | LC_ALL=C sort)

  while IFS= read -r promotion; do
    [[ -n "$promotion" ]] || continue
    archive="$(sed -nE 's/^- Archived report: (.*)$/\1/p' "$promotion" | head -n 1)"
    if [[ -n "$archive" && "$archive" != none ]]; then
      assert_safe_copied_reference "$project_root" "$gauntlet_name" \
        "$archive" archive
      hash="$(sha256_file "$project_root/$archive")"
      set_gauntlet_field "$project_root" "$promotion" \
        'Promotion QA Event Metadata' 'Archived report sha256' "$hash"
    fi
  done < <(find "$gauntlet_dir/promotion-events" -maxdepth 1 -type f \
    -name 'event-*.md' -print 2>/dev/null | LC_ALL=C sort)
}

refresh_copied_report_projections() {
  local gauntlet_dir="$1"
  local gauntlet_name project_root completion completion_relative
  local promotion consumed_completion report_relative report_file projection
  local archive_count
  gauntlet_name="$(basename "$gauntlet_dir")"
  project_root="$(cd "$gauntlet_dir/../../.." && pwd -P)"

  while IFS= read -r completion; do
    [[ -n "$completion" ]] || continue
    completion_relative=".ai/gauntlets/$gauntlet_name/${completion#"$gauntlet_dir"/}"
    report_relative=''
    archive_count=0
    while IFS= read -r promotion; do
      [[ -n "$promotion" ]] || continue
      [[ "$(gauntlet_helper_value "$project_root" gauntlet_section_field \
        "$promotion" 'Promotion QA Event Metadata' 'Verdict')" == fail ]] || continue
      consumed_completion="$(gauntlet_helper_value "$project_root" \
        gauntlet_section_field "$promotion" 'Promotion QA Event Metadata' \
        'Completion event')"
      [[ "$consumed_completion" == "$completion_relative" ]] || continue
      report_relative="$(gauntlet_helper_value "$project_root" \
        gauntlet_section_field "$promotion" 'Promotion QA Event Metadata' \
        'Archived report')"
      archive_count=$((archive_count + 1))
    done < <(find "$gauntlet_dir/promotion-events" -maxdepth 1 -type f \
      -name 'event-*.md' -print 2>/dev/null | LC_ALL=C sort)

    [[ $archive_count -le 1 ]] \
      || fail "copied completion has multiple archived reports: $completion_relative"
    if [[ $archive_count -eq 0 ]]; then
      report_relative="$(gauntlet_helper_value "$project_root" \
        gauntlet_section_field "$completion" 'Completion Event Metadata' 'Report')"
    fi
    [[ "$report_relative" == ".ai/gauntlets/$gauntlet_name/GAUNTLET_REPORT.md" \
      || "$report_relative" =~ ^\.ai/gauntlets/${gauntlet_name}/promotion-events/GAUNTLET_REPORT-before-event-[0-9]{3,}\.md$ ]] \
      || fail "copied completion resolved a noncanonical report: $report_relative"
    report_file="$project_root/$report_relative"
    [[ -f "$report_file" && ! -L "$report_file" ]] \
      || fail "copied completion report is missing or unsafe: $report_relative"
    gauntlet_helper_value "$project_root" gauntlet_assert_safe_ai_path \
      "$report_file" 'Copied completion report' >/dev/null \
      || fail "copied completion report escaped the project root: $report_relative"
    projection="$(gauntlet_helper_value "$project_root" \
      gauntlet_report_projection_hash "$report_file")"
    set_gauntlet_field "$project_root" "$completion" \
      'Completion Event Metadata' 'Report projection sha256' "$projection"
  done < <(find "$gauntlet_dir/completion-events" -maxdepth 1 -type f \
    -name 'event-*.md' -print 2>/dev/null | LC_ALL=C sort)
}

refresh_copied_qa_body_hashes() {
  local gauntlet_dir="$1"
  local gauntlet_name project_root event action head_sha referenced affected
  local body body_hash
  gauntlet_name="$(basename "$gauntlet_dir")"
  project_root="$(cd "$gauntlet_dir/../../.." && pwd -P)"

  while IFS= read -r event; do
    [[ -n "$event" ]] || continue
    action="$(gauntlet_helper_value "$project_root" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Event')"
    [[ "$action" == qa-pass || "$action" == qa-fail ]] || continue
    head_sha="$(gauntlet_helper_value "$project_root" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Head SHA')"
    referenced="$(gauntlet_helper_value "$project_root" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Critic round')"
    [[ "$referenced" =~ ^\.ai/gauntlets/${gauntlet_name}/rounds/[a-z0-9]+(-[a-z0-9]+)*/round-[0-9]{3,}\.md$ \
      && -f "$project_root/$referenced" && ! -L "$project_root/$referenced" ]] \
      || fail "copied PR QA event references unsafe critic evidence: $referenced"
    gauntlet_helper_value "$project_root" gauntlet_assert_safe_ai_path \
      "$project_root/$referenced" 'Copied PR QA source' >/dev/null \
      || fail "copied PR QA source escaped the project root: $referenced"
    body="$(semantic_comment_body "$project_root" "${action#qa-}" \
      "$head_sha" "$referenced" none)"
    body_hash="$(gauntlet_helper_value "$project_root" gauntlet_hash_text "$body")"
    set_gauntlet_field "$project_root" "$event" 'PR Event Metadata' \
      'QA comment body sha256' "$body_hash"
  done < <(find "$gauntlet_dir/pr-events" -type f -name 'event-*.md' \
    -print 2>/dev/null | LC_ALL=C sort)

  while IFS= read -r event; do
    [[ -n "$event" ]] || continue
    action="$(gauntlet_helper_value "$project_root" gauntlet_section_field \
      "$event" 'Promotion QA Event Metadata' 'Verdict')"
    head_sha="$(gauntlet_helper_value "$project_root" gauntlet_section_field \
      "$event" 'Promotion QA Event Metadata' 'Head SHA')"
    referenced="$(gauntlet_helper_value "$project_root" gauntlet_section_field \
      "$event" 'Promotion QA Event Metadata' 'Completion event')"
    affected="$(gauntlet_helper_value "$project_root" gauntlet_section_field \
      "$event" 'Promotion QA Event Metadata' 'Affected units')"
    [[ "$action" == pass || "$action" == fail ]] \
      || fail "copied promotion event has an invalid verdict: $event"
    [[ "$referenced" =~ ^\.ai/gauntlets/${gauntlet_name}/completion-events/event-[0-9]{3,}\.md$ \
      && -f "$project_root/$referenced" && ! -L "$project_root/$referenced" ]] \
      || fail "copied promotion QA event references unsafe completion evidence: $referenced"
    gauntlet_helper_value "$project_root" gauntlet_assert_safe_ai_path \
      "$project_root/$referenced" 'Copied promotion QA source' >/dev/null \
      || fail "copied promotion QA source escaped the project root: $referenced"
    body="$(semantic_comment_body "$project_root" "$action" "$head_sha" \
      "$referenced" "$affected")"
    body_hash="$(gauntlet_helper_value "$project_root" gauntlet_hash_text "$body")"
    set_gauntlet_field "$project_root" "$event" \
      'Promotion QA Event Metadata' 'QA comment body sha256' "$body_hash"
  done < <(find "$gauntlet_dir/promotion-events" -maxdepth 1 -type f \
    -name 'event-*.md' -print 2>/dev/null | LC_ALL=C sort)
}

copied_markdown_digest() {
  local gauntlet_dir="$1"
  local project_root markdown_file material=''
  project_root="$(cd "$gauntlet_dir/../../.." && pwd -P)"
  while IFS= read -r markdown_file; do
    [[ -n "$markdown_file" ]] || continue
    material+="${markdown_file#"$project_root"/}"$'\t'
    material+="$(sha256_file "$markdown_file")"$'\n'
  done < <(find "$gauntlet_dir" -type f -name '*.md' \
    -print 2>/dev/null | LC_ALL=C sort)
  sha256_text "$material"
}

stabilize_copied_evidence_hashes() {
  local gauntlet_dir="$1"
  local markdown_count max_passes pass=0 before_digest after_digest
  markdown_count="$(find "$gauntlet_dir" -type f -name '*.md' \
    -print 2>/dev/null | wc -l | tr -d '[:space:]')"
  max_passes=$((markdown_count + 2))
  before_digest="$(copied_markdown_digest "$gauntlet_dir")"
  while (( pass < max_passes )); do
    refresh_copied_cross_evidence_hashes "$gauntlet_dir"
    refresh_copied_checkpoint_hashes "$gauntlet_dir"
    refresh_copied_evidence_hashes "$gauntlet_dir"
    refresh_copied_report_projections "$gauntlet_dir"
    refresh_copied_qa_body_hashes "$gauntlet_dir"
    refresh_copied_evidence_hashes "$gauntlet_dir"
    after_digest="$(copied_markdown_digest "$gauntlet_dir")"
    if [[ "$after_digest" == "$before_digest" ]]; then
      return 0
    fi
    before_digest="$after_digest"
    pass=$((pass + 1))
  done
  fail "copied Gauntlet evidence hashes did not converge after $max_passes passes: $gauntlet_dir"
}

convert_to_crlf() {
  local file="$1"
  local temporary="$file.crlf"
  awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$file" >"$temporary"
  mv "$temporary" "$file"
}

new_project() {
  local name="$1"
  local project="$temp_root/$name"
  mkdir -p "$project"
  git -C "$project" init -q -b main
  git -C "$project" config user.name 'OpenCaw Gauntlet Test'
  git -C "$project" config user.email 'opencaw-gauntlet@example.invalid'
  git -C "$project" remote add origin https://github.com/example/opencaw-fixture.git
  printf 'inspectable fixture artifact\n' >"$project/artifact.txt"
  git -C "$project" add artifact.txt
  git -C "$project" commit -qm 'test: initialize fixture'
  printf '%s\n' "$project"
}

create_fixture_commit() {
  local project="$1"
  local ordinal="$2"
  local parent="$3"
  local tree="$4"
  local timestamp=$((946684800 + ordinal))
  local commit_sha

  commit_sha="$(printf 'fixture commit %02d\n' "$ordinal" \
    | GIT_AUTHOR_NAME='OpenCaw Gauntlet Test' \
      GIT_AUTHOR_EMAIL='opencaw-gauntlet@example.invalid' \
      GIT_AUTHOR_DATE="@$timestamp +0000" \
      GIT_COMMITTER_NAME='OpenCaw Gauntlet Test' \
      GIT_COMMITTER_EMAIL='opencaw-gauntlet@example.invalid' \
      GIT_COMMITTER_DATE="@$timestamp +0000" \
      git -C "$project" commit-tree "$tree" -p "$parent")"
  git -C "$project" update-ref "refs/heads/fixture/review-$ordinal" "$commit_sha"
  printf '%s\n' "$commit_sha"
}

initialize_fixture_commits() {
  local project="$1"
  local parent tree ordinal commit_sha empty_tree timestamp root_commit orphan_timestamp

  parent="$(git -C "$project" rev-parse HEAD)"
  tree="$(git -C "$project" rev-parse 'HEAD^{tree}')"
  for ordinal in 1 2 3 4 5 6 7 8 9; do
    commit_sha="$(create_fixture_commit "$project" "$ordinal" "$parent" "$tree")"
    printf -v "head_sha_$ordinal" '%s' "$commit_sha"
    parent="$commit_sha"
  done

  empty_tree="$(git -C "$project" mktree </dev/null)"
  timestamp=946684899
  artifact_absent_sha="$(printf 'fixture commit without artifact\n' \
    | GIT_AUTHOR_NAME='OpenCaw Gauntlet Test' \
      GIT_AUTHOR_EMAIL='opencaw-gauntlet@example.invalid' \
      GIT_AUTHOR_DATE="@$timestamp +0000" \
      GIT_COMMITTER_NAME='OpenCaw Gauntlet Test' \
      GIT_COMMITTER_EMAIL='opencaw-gauntlet@example.invalid' \
      GIT_COMMITTER_DATE="@$timestamp +0000" \
      git -C "$project" commit-tree "$empty_tree" -p "$parent")"
  git -C "$project" update-ref refs/heads/fixture/artifact-absent "$artifact_absent_sha"

  root_commit="$(git -C "$project" rev-list --max-parents=0 HEAD)"
  divergent_sha="$(create_fixture_commit "$project" 50 "$root_commit" "$tree")"

  orphan_timestamp=946684900
  orphan_sha="$(printf 'fixture orphan commit\n' \
    | GIT_AUTHOR_NAME='OpenCaw Gauntlet Test' \
      GIT_AUTHOR_EMAIL='opencaw-gauntlet@example.invalid' \
      GIT_AUTHOR_DATE="@$orphan_timestamp +0000" \
      GIT_COMMITTER_NAME='OpenCaw Gauntlet Test' \
      GIT_COMMITTER_EMAIL='opencaw-gauntlet@example.invalid' \
      GIT_COMMITTER_DATE="@$orphan_timestamp +0000" \
      git -C "$project" commit-tree "$tree")"
  git -C "$project" update-ref refs/heads/fixture/orphan "$orphan_sha"
}

set_local_ref() {
  local project="$1"
  local branch="$2"
  local commit_sha="$3"
  if git -C "$project" cat-file -e "$commit_sha^{commit}" 2>/dev/null; then
    git -C "$project" update-ref "refs/heads/$branch" "$commit_sha"
  fi
}

set_remote_ref() {
  local project="$1"
  local branch="$2"
  local commit_sha="$3"
  local canonical_project temporary
  canonical_project="$(cd "$project" && pwd -P)"
  temporary="$fake_git_remote_state.next"
  awk -F '\t' -v root="$canonical_project" -v ref="refs/heads/$branch" \
    '!($1 == root && $2 == ref)' "$fake_git_remote_state" >"$temporary"
  if [[ "$commit_sha" != absent ]]; then
    printf '%s\t%s\t%s\n' "$canonical_project" "refs/heads/$branch" "$commit_sha" \
      >>"$temporary"
  fi
  mv "$temporary" "$fake_git_remote_state"
}

fixture_issue_link() {
  local project="$1"
  local head_branch="$2"
  local base_branch="$3"
  local gauntlet_name='' link_keyword='' candidate=''
  local issue_url issue_number candidate_integration candidate_base

  # Promotion is identified from its exact integration head first. This keeps
  # a configured delivery base such as gauntlet/release from being mistaken
  # for a progress target without scanning every generated fixture contract.
  if [[ "$head_branch" == gauntlet/* ]]; then
    gauntlet_name="${head_branch#gauntlet/}"
    candidate="$project/.ai/gauntlets/$gauntlet_name/GAUNTLET.md"
    if [[ -f "$candidate" ]]; then
      candidate_integration="$(sed -nE \
        's/\r$//; s/^- Integration branch: (.+)$/\1/p' "$candidate" | head -n 1)"
      candidate_base="$(sed -nE \
        's/\r$//; s/^- Base branch: (.+)$/\1/p' "$candidate" | head -n 1)"
      if [[ "$head_branch" == "$candidate_integration" \
        && "$base_branch" == "$candidate_base" ]]; then
        link_keyword='Closes'
      fi
    fi
  fi
  if [[ -z "$link_keyword" && "$base_branch" == gauntlet/* ]]; then
    gauntlet_name="${base_branch#gauntlet/}"
    candidate="$project/.ai/gauntlets/$gauntlet_name/GAUNTLET.md"
    if [[ -f "$candidate" ]]; then
      candidate_integration="$(sed -nE \
        's/\r$//; s/^- Integration branch: (.+)$/\1/p' "$candidate" | head -n 1)"
      if [[ "$base_branch" == "$candidate_integration" \
        && "$head_branch" == gauntlet-work/"$gauntlet_name"/* ]]; then
        link_keyword='Refs'
      fi
    fi
  fi
  [[ -n "$link_keyword" ]] || return 1
  issue_url="$(gauntlet_helper_value "$project" gauntlet_section_field \
    "$project/.ai/gauntlets/$gauntlet_name/GAUNTLET.md" \
    'Parent Task' 'Issue')"
  issue_number="$(gauntlet_helper_value "$project" \
    gauntlet_github_issue_number "$issue_url")"
  printf '%s #%s\n' "$link_keyword" "$issue_number"
}

set_pr_observation() {
  local argument_count=$#
  local pr_url="$1"
  local head_branch="$2"
  local head_sha="$3"
  local base_branch="$4"
  local state="$5"
  local is_draft="$6"
  local merged_at="$7"
  local merged_by="$8"
  local merge_commit="$9"
  local merged_by_bot="${10:-}"
  local base_ref_oid="${11:-}"
  local is_cross_repository="${12:-false}"
  local head_repository="${13:-example/opencaw-fixture}"
  local created_at="${14:-${FAKE_DATE_ISO:-2026-08-01T12:00:00Z}}"
  local closed_at="${15:-}"
  local pr_body="${16:-}"
  local merged_by_type="${17:-}"
  local actor_login="${18:-}"
  local merge_automation_event="${19:-none}"
  local canonical_issue_link
  local pr_body_base64
  local observation_exists=0
  local temporary="$fake_gh_state.next"

  if [[ -z "$merged_by_bot" ]]; then
    if [[ "$merged_by" == none ]]; then
      merged_by_bot=none
    else
      merged_by_bot=false
    fi
  fi

  if [[ $argument_count -lt 16 ]]; then
    observation_exists="$(awk -F '\t' -v url="$pr_url" \
      '$1 == url { found=1 } END { print found + 0 }' "$fake_gh_state")"
    pr_body_base64="$(awk -F '\t' -v url="$pr_url" \
      '$1 == url { body=$18 } END { print body }' "$fake_gh_state")"
    if [[ "$observation_exists" -eq 0 \
      && -z "$pr_body_base64" \
      && "${OPENCAW_TEST_RAW_PR_BODY:-0}" != 1 ]]; then
      canonical_issue_link="$(fixture_issue_link \
        "$project" "$head_branch" "$base_branch" 2>/dev/null || true)"
      if [[ -n "$canonical_issue_link" ]]; then
        pr_body_base64="$(printf '%s' "$canonical_issue_link" \
          | base64 | tr -d '\r\n')"
      fi
    fi
  else
    if [[ "${OPENCAW_TEST_RAW_PR_BODY:-0}" != 1 ]]; then
      canonical_issue_link="$(fixture_issue_link \
        "$project" "$head_branch" "$base_branch" 2>/dev/null || true)"
      if [[ -n "$canonical_issue_link" ]]; then
        pr_body="$canonical_issue_link"$'\n'"$pr_body"
      fi
    fi
    pr_body_base64="$(printf '%s' "$pr_body" | base64 | tr -d '\r\n')"
  fi

  if [[ -z "$base_ref_oid" ]]; then
    base_ref_oid="$(git -C "$project" rev-parse --verify \
      "refs/heads/$base_branch" 2>/dev/null || true)"
    [[ -n "$base_ref_oid" ]] || base_ref_oid=none
  fi

  if [[ -z "$merged_by_type" ]]; then
    case "$merged_by_bot:$merged_by" in
      true:*) merged_by_type=Bot ;;
      false:none|none:none) merged_by_type=none ;;
      *) merged_by_type=User ;;
    esac
  fi
  [[ -n "$actor_login" ]] || actor_login="$merged_by"

  if [[ -z "$closed_at" ]]; then
    case "$state" in
      OPEN) closed_at=none ;;
      MERGED) closed_at="$merged_at" ;;
      CLOSED) closed_at="${FAKE_DATE_ISO:-2026-08-01T12:00:00Z}" ;;
      *) closed_at=none ;;
    esac
  fi

  awk -F '\t' -v url="$pr_url" '$1 != url' "$fake_gh_state" > "$temporary"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$pr_url" "$head_branch" "$head_sha" "$base_branch" "$base_ref_oid" \
    "$is_cross_repository" "$head_repository" "$state" "$is_draft" \
    "$created_at" "$closed_at" "$merged_at" "$merged_by" "$merged_by_bot" \
    "$merge_commit" "$merged_by_type" "$actor_login" "$pr_body_base64" \
    "$merge_automation_event" \
    >> "$temporary"
  mv "$temporary" "$fake_gh_state"
}

set_pr_actor_observation() {
  local pr_url="$1"
  local actor_type="$2"
  local actor_login="$3"
  local temporary="$fake_gh_state.next"
  awk -F '\t' -v OFS='\t' -v url="$pr_url" -v type="$actor_type" \
    -v login="$actor_login" '
      $1 == url { $16=type; $17=login; found=1 }
      { print }
      END { if (!found) exit 42 }
    ' "$fake_gh_state" >"$temporary" || {
      rm -f -- "$temporary"
      fail "PR actor fixture was not found: $pr_url"
    }
  mv "$temporary" "$fake_gh_state"
}

set_pr_merge_automation_observation() {
  local pr_url="$1"
  local automation_event="$2"
  local temporary="$fake_gh_state.next"
  awk -F '\t' -v OFS='\t' -v url="$pr_url" -v event="$automation_event" '
      $1 == url { $19=event; found=1 }
      { print }
      END { if (!found) exit 42 }
    ' "$fake_gh_state" >"$temporary" || {
      rm -f -- "$temporary"
      fail "PR merge-automation fixture was not found: $pr_url"
    }
  mv "$temporary" "$fake_gh_state"
}

set_pr_body_observation() {
  local pr_url="$1"
  local pr_body="$2"
  local record
  local observed_url head_branch head_sha base_branch base_ref_oid
  local is_cross_repository head_repository state is_draft created_at closed_at
  local merged_at merged_by merged_by_bot merge_commit _pr_body_base64
  local merged_by_type actor_login merge_automation_event

  record="$(awk -F '\t' -v url="${pr_url%/}" \
    '$1 == url { found=$0 } END { if (found == "") exit 1; print found }' \
    "$fake_gh_state")" || return 1
  IFS=$'\t' read -r observed_url head_branch head_sha base_branch base_ref_oid \
    is_cross_repository head_repository state is_draft created_at closed_at merged_at \
    merged_by merged_by_bot merge_commit merged_by_type actor_login \
    <<<"$(printf '%s\n' "$record" | cut -f1-17)"
  _pr_body_base64="$(awk -F '\t' '{ print $18 }' <<<"$record")"
  merge_automation_event="$(awk -F '\t' '{ print $19 }' <<<"$record")"
  set_pr_observation "$observed_url" "$head_branch" "$head_sha" "$base_branch" \
    "$state" "$is_draft" "$merged_at" "$merged_by" "$merge_commit" \
    "$merged_by_bot" "$base_ref_oid" "$is_cross_repository" "$head_repository" \
    "$created_at" "$closed_at" "$pr_body" "$merged_by_type" "$actor_login" \
    "$merge_automation_event"
}

set_comment_observation() {
  local evidence_url="$1"
  local observed_pr_url="${2:-${evidence_url%%#issuecomment-*}}"
  local body="${3:-Unrelated fixture comment without a Gauntlet QA marker.}"
  local author_login="${4:-fixture-user}"
  local author_type="${5:-User}"
  local author_association="${6:-MEMBER}"
  local created_at="${7:-2026-08-02T00:00:00Z}"
  local updated_at="${8:-$created_at}"
  local expected_pr_url="${evidence_url%%#issuecomment-*}"
  local comment_id="${evidence_url#*#issuecomment-}"
  local expected_owner expected_repo observed_owner observed_repo observed_pr_number
  local endpoint observed_html_url observed_issue_url temporary body_base64

  [[ "$expected_pr_url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/[1-9][0-9]*$ ]] \
    || return 0
  expected_owner="${BASH_REMATCH[1]}"
  expected_repo="${BASH_REMATCH[2]}"
  [[ "$comment_id" =~ ^[1-9][0-9]*$ ]] || return 0
  [[ "$observed_pr_url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([1-9][0-9]*)$ ]] \
    || fail "invalid observed PR URL for comment fixture: $observed_pr_url"
  observed_owner="${BASH_REMATCH[1]}"
  observed_repo="${BASH_REMATCH[2]}"
  observed_pr_number="${BASH_REMATCH[3]}"
  endpoint="repos/$expected_owner/$expected_repo/issues/comments/$comment_id"
  observed_html_url="$observed_pr_url#issuecomment-$comment_id"
  observed_issue_url="https://api.github.com/repos/$observed_owner/$observed_repo/issues/$observed_pr_number"
  body_base64="$(printf '%s' "$body" | base64 | tr -d '\r\n')"
  temporary="$fake_gh_comments.next"

  awk -F '\t' -v endpoint="$endpoint" '$1 != endpoint' "$fake_gh_comments" >"$temporary"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$endpoint" "$observed_html_url" "$observed_issue_url" "$comment_id" \
    "$body_base64" "$author_login" "$author_type" "$author_association" \
    "$created_at" "$updated_at" \
    >>"$temporary"
  mv "$temporary" "$fake_gh_comments"
}

semantic_comment_body() {
  local project="$1"
  local verdict="$2"
  local head_sha="$3"
  local source_relative="$4"
  local affected_units="${5:-none}"
  local source_hash
  source_hash="$(sha256_file "$project/$source_relative")"
  printf '<!-- opencaw-gauntlet-qa:v1 verdict=%s head-sha=%s source=%s source-sha256=%s affected-units=%s -->\n' \
    "$verdict" "$head_sha" "$source_relative" "$source_hash" "$affected_units"
}

set_semantic_comment_observation() {
  local project="$1"
  local evidence_url="$2"
  local observed_pr_url="$3"
  local verdict="$4"
  local head_sha="$5"
  local source_relative="$6"
  local affected_units="${7:-none}"
  local body source_recorded_at
  body="$(semantic_comment_body "$project" "$verdict" "$head_sha" \
    "$source_relative" "$affected_units")"
  source_recorded_at="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
    "$project/$source_relative" | head -n 1)"
  [[ -n "$source_recorded_at" ]] \
    || fail "semantic QA source omitted Recorded at: $source_relative"
  set_comment_observation "$evidence_url" "$observed_pr_url" "$body" \
    fixture-user User MEMBER "$source_recorded_at" "$source_recorded_at"
}

latest_event_field() {
  local project="$1"
  local gauntlet="$2"
  local item="$3"
  local field="$4"
  local event_file
  event_file="$(gauntlet_helper_value "$project" gauntlet_latest_pr_event_file \
    "$project/.ai/gauntlets/$gauntlet/pr-events/$item")"
  [[ -n "$event_file" ]] || return 1
  sed -nE "s/^- $field: (.*)$/\\1/p" "$event_file" | head -n 1
}

checkpoint_consumed() {
  local project="$1"
  local gauntlet="$2"
  local checkpoint_relative="$3"
  grep -R -Fq -- "- Publication checkpoint: $checkpoint_relative" \
    "$project/.ai/gauntlets/$gauntlet/pr-events" 2>/dev/null
}

latest_unused_publication_checkpoint() {
  local project="$1"
  local gauntlet="$2"
  local item="$3"
  local checkpoint checkpoint_relative
  while IFS= read -r checkpoint; do
    [[ -n "$checkpoint" ]] || continue
    checkpoint_relative="${checkpoint#"$project"/}"
    if ! checkpoint_consumed "$project" "$gauntlet" "$checkpoint_relative"; then
      printf '%s\n' "$checkpoint"
      return 0
    fi
  done < <(find "$project/.ai/gauntlets/$gauntlet/publication-checkpoints/$item" \
    -maxdepth 1 -type f -name 'checkpoint-*.md' -print 2>/dev/null \
    | LC_ALL=C sort -r)
  return 1
}

ensure_publication_marker() {
  local project="$1"
  local gauntlet="$2"
  local item="$3"
  local checkpoint checkpoint_relative checkpoint_hash readiness_output

  checkpoint="$(latest_unused_publication_checkpoint \
    "$project" "$gauntlet" "$item" 2>/dev/null || true)"
  if [[ -z "$checkpoint" ]]; then
    readiness_output="$(mktemp "$temp_root/publication-readiness.XXXXXX")"
    OPENCAW_PROJECT_ROOT="$project" \
      OPENCAW_REPORT_DIR="$project/.ai/reports/publication-checkpoint-$gauntlet-$item" \
      bash commands/pr-readiness-check.sh --gauntlet-progress \
        "$gauntlet" "$item" "$project/progress-validation.md" >"$readiness_output"
    checkpoint_relative="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
      "$readiness_output" | tail -n 1)"
    checkpoint_hash="$(sed -nE 's/^PUBLICATION_CHECKPOINT_SHA256=([0-9a-f]{64})$/\1/p' \
      "$readiness_output" | tail -n 1)"
    [[ -n "$checkpoint_relative" && -n "$checkpoint_hash" ]] \
      || fail "progress readiness omitted publication checkpoint evidence: $gauntlet/$item"
    checkpoint="$project/$checkpoint_relative"
  else
    checkpoint_relative="${checkpoint#"$project"/}"
    checkpoint_hash="$(sha256_file "$checkpoint")"
  fi
  expect_file "$checkpoint"
  printf '<!-- opencaw-gauntlet-publication:v1 checkpoint=%s checkpoint-sha256=%s -->\n' \
    "$checkpoint_relative" "$checkpoint_hash"
}

opened_publication_marker() {
  local project="$1"
  local gauntlet="$2"
  local item="$3"
  local opened_event checkpoint_relative checkpoint_hash
  opened_event="$(find "$project/.ai/gauntlets/$gauntlet/pr-events/$item" -maxdepth 1 \
    -type f -name 'event-*.md' -print 2>/dev/null | LC_ALL=C sort -r \
    | while IFS= read -r candidate; do
        [[ "$(sed -nE 's/^- Event: (.*)$/\1/p' "$candidate" | head -n 1)" == opened ]] \
          && { printf '%s\n' "$candidate"; break; }
      done)"
  [[ -n "$opened_event" ]] || return 1
  checkpoint_relative="$(sed -nE 's/^- Publication checkpoint: (.*)$/\1/p' \
    "$opened_event" | head -n 1)"
  checkpoint_hash="$(sed -nE 's/^- Publication checkpoint sha256: (.*)$/\1/p' \
    "$opened_event" | head -n 1)"
  [[ -n "$checkpoint_relative" && -n "$checkpoint_hash" ]] || return 1
  printf '<!-- opencaw-gauntlet-publication:v1 checkpoint=%s checkpoint-sha256=%s -->\n' \
    "$checkpoint_relative" "$checkpoint_hash"
}

publish_checkpoint_refs() {
  local project="$1"
  local marker="$2"
  local checkpoint_relative checkpoint head_branch head_sha target_branch chain_tip
  checkpoint_relative="$(printf '%s\n' "$marker" \
    | sed -nE 's/^.* checkpoint=([^ ]+) checkpoint-sha256=.*$/\1/p')"
  [[ -n "$checkpoint_relative" ]] || return 1
  checkpoint="$project/$checkpoint_relative"
  expect_file "$checkpoint"
  head_branch="$(sed -nE 's/^- Head branch: (.*)$/\1/p' "$checkpoint" | head -n 1)"
  head_sha="$(sed -nE 's/^- Head SHA: (.*)$/\1/p' "$checkpoint" | head -n 1)"
  target_branch="$(sed -nE 's/^- Target branch: (.*)$/\1/p' "$checkpoint" | head -n 1)"
  chain_tip="$(sed -nE 's/^- Chain tip: (.*)$/\1/p' "$checkpoint" | head -n 1)"
  set_remote_ref "$project" "$target_branch" "$chain_tip"
  set_remote_ref "$project" "$head_branch" "$head_sha"
}

prepare_observation_for_command() {
  local project="$1"
  shift
  [[ "${1:-}" == bash ]] || return 0
  local command_path="${2:-}"
  shift 2
  local gauntlet item action pr_url head_branch head_sha='' merge_commit='' base_branch gauntlet_name
  local base_ref_oid publication_marker='' pr_created_at recorded_pr_created_at
  local fixture_now="${FAKE_DATE_ISO:-2026-08-01T12:00:00Z}"
  local promotion_url evidence_url qa_verdict source_file source_relative qa_affected_units
  local observation_index
  local -a positional_observation=()
  local -a observed_affected_units=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --head-sha) head_sha="$2"; shift 2 ;;
      --merge-commit) merge_commit="$2"; shift 2 ;;
      *) positional_observation+=("$1"); shift ;;
    esac
  done

  case "$command_path" in
    commands/record-gauntlet-pr-event.sh)
      gauntlet="${positional_observation[0]}"
      item="${positional_observation[1]}"
      action="${positional_observation[2]}"
      pr_url="${positional_observation[3]%/}"
      head_branch="${positional_observation[4]}"
      evidence_url="${positional_observation[5]}"
      gauntlet_name="$(basename "$gauntlet")"
      base_branch="gauntlet/$gauntlet_name"
      if ! git -C "$project" show-ref --verify --quiet "refs/heads/$base_branch"; then
        set_local_ref "$project" "$base_branch" "$(git -C "$project" rev-parse HEAD)"
      fi
      base_ref_oid="$(git -C "$project" rev-parse "refs/heads/$base_branch")"
      set_local_ref "$project" "$head_branch" "$head_sha"
      pr_created_at="$fixture_now"
      if [[ "$action" != opened ]]; then
        recorded_pr_created_at="$(latest_event_field \
          "$project" "$gauntlet_name" "$item" 'Created at' 2>/dev/null || true)"
        [[ -z "$recorded_pr_created_at" ]] \
          || pr_created_at="$recorded_pr_created_at"
      fi
      if [[ "$action" == opened ]]; then
        publication_marker="$(ensure_publication_marker \
          "$project" "$gauntlet_name" "$item")"
        if [[ "${OPENCAW_TEST_SKIP_REMOTE_PUBLICATION:-0}" != 1 ]]; then
          publish_checkpoint_refs "$project" "$publication_marker"
        fi
      else
        publication_marker="$(opened_publication_marker \
          "$project" "$gauntlet_name" "$item" 2>/dev/null || true)"
      fi
      case "$action" in
        opened|qa-pass|qa-fail)
          if [[ "${OPENCAW_TEST_SKIP_OBSERVATION:-0}" != 1 ]]; then
            set_pr_observation "$pr_url" "$head_branch" "$head_sha" "$base_branch" \
              OPEN false none none none none "$base_ref_oid" false \
              example/opencaw-fixture "$pr_created_at" none "$publication_marker"
          elif [[ "${OPENCAW_TEST_SKIP_PUBLICATION_BODY:-0}" != 1 \
            && -n "$publication_marker" ]]; then
            set_pr_body_observation "$pr_url" "$publication_marker"
          fi
          if [[ "$action" == qa-* && "${OPENCAW_TEST_SKIP_COMMENT_OBSERVATION:-0}" != 1 \
            && "$evidence_url" == "$pr_url#issuecomment-"* ]]; then
            qa_verdict="${action#qa-}"
            source_file="$(gauntlet_helper_value "$project" gauntlet_latest_round_file \
              "$project/.ai/gauntlets/$gauntlet_name/rounds/$item")"
            [[ -n "$source_file" ]] || fail "QA fixture cannot find its critic source: $item"
            source_relative="${source_file#"$project"/}"
            set_semantic_comment_observation "$project" "$evidence_url" "$pr_url" \
              "$qa_verdict" "$head_sha" "$source_relative"
          fi
          ;;
        merged)
          if [[ "${OPENCAW_TEST_SKIP_OBSERVATION:-0}" != 1 ]]; then
            set_pr_observation "$pr_url" "$head_branch" "$head_sha" "$base_branch" MERGED false \
              "$fixture_now" human-reviewer "$merge_commit" false "$base_ref_oid" \
              false example/opencaw-fixture "$pr_created_at" \
              "$fixture_now" "$publication_marker"
          elif [[ "${OPENCAW_TEST_SKIP_PUBLICATION_BODY:-0}" != 1 \
            && -n "$publication_marker" ]]; then
            set_pr_body_observation "$pr_url" "$publication_marker"
          fi
          set_local_ref "$project" "$base_branch" "$merge_commit"
          set_remote_ref "$project" "$base_branch" "$merge_commit"
          ;;
        closed)
          if [[ "${OPENCAW_TEST_SKIP_OBSERVATION:-0}" != 1 ]]; then
            set_pr_observation "$pr_url" "$head_branch" "$head_sha" "$base_branch" \
              CLOSED false none none none none "$base_ref_oid" false \
              example/opencaw-fixture "$pr_created_at" \
              "$fixture_now" "$publication_marker"
          elif [[ "${OPENCAW_TEST_SKIP_PUBLICATION_BODY:-0}" != 1 \
            && -n "$publication_marker" ]]; then
            set_pr_body_observation "$pr_url" "$publication_marker"
          fi
          ;;
      esac
      ;;
    commands/record-gauntlet-round.sh)
      gauntlet="${positional_observation[0]}"
      item="${positional_observation[1]}"
      gauntlet_name="$(basename "$gauntlet")"
      if [[ "$item" == integration ]]; then
        set_local_ref "$project" "gauntlet/$gauntlet_name" "$head_sha"
      else
        pr_url="$(latest_event_field "$project" "$gauntlet_name" "$item" 'PR URL')"
        head_branch="$(latest_event_field "$project" "$gauntlet_name" "$item" 'Head branch')"
        set_local_ref "$project" "$head_branch" "$head_sha"
        base_ref_oid="$(git -C "$project" rev-parse "refs/heads/gauntlet/$gauntlet_name")"
        publication_marker="$(opened_publication_marker \
          "$project" "$gauntlet_name" "$item" 2>/dev/null || true)"
        pr_created_at="$(latest_event_field \
          "$project" "$gauntlet_name" "$item" 'Created at' 2>/dev/null || true)"
        [[ -n "$pr_created_at" ]] || pr_created_at="$fixture_now"
        set_pr_observation "$pr_url" "$head_branch" "$head_sha" "gauntlet/$gauntlet_name" \
          OPEN false none none none none "$base_ref_oid" false \
          example/opencaw-fixture "$pr_created_at" none "$publication_marker"
      fi
      ;;
    commands/record-gauntlet-promotion-qa.sh)
      gauntlet="${positional_observation[0]}"
      promotion_url="${positional_observation[2]}"
      evidence_url="${positional_observation[3]}"
      gauntlet_name="$(basename "$gauntlet")"
      set_local_ref "$project" "gauntlet/$gauntlet_name" "$head_sha"
      base_ref_oid="$(git -C "$project" rev-parse refs/heads/main)"
      pr_created_at="$(awk -F '\t' -v url="${promotion_url%/}" \
        '$1 == url { value=$10 } END { print value }' "$fake_gh_state")"
      [[ -n "$pr_created_at" ]] || pr_created_at="$fixture_now"
      if [[ "${OPENCAW_TEST_SKIP_OBSERVATION:-0}" != 1 ]]; then
        set_pr_observation "$promotion_url" "gauntlet/$gauntlet_name" "$head_sha" main \
          OPEN false none none none none "$base_ref_oid" false \
          example/opencaw-fixture "$pr_created_at"
      fi
      if [[ "${OPENCAW_TEST_SKIP_COMMENT_OBSERVATION:-0}" != 1 \
        && "$evidence_url" == "$promotion_url#issuecomment-"* ]]; then
        qa_verdict="${positional_observation[1]}"
        source_file="$(gauntlet_helper_value "$project" \
          gauntlet_latest_completion_event_file \
          "$project/.ai/gauntlets/$gauntlet_name/completion-events")"
        [[ -n "$source_file" ]] || fail 'Promotion QA fixture cannot find its completion source.'
        source_relative="${source_file#"$project"/}"
        qa_affected_units=none
        observation_index=4
        while [[ $observation_index -lt ${#positional_observation[@]} ]]; do
          if [[ "${positional_observation[$observation_index]}" == --affected-unit \
            && $((observation_index + 1)) -lt ${#positional_observation[@]} ]]; then
            observed_affected_units+=("${positional_observation[$((observation_index + 1))]}")
            observation_index=$((observation_index + 2))
          else
            observation_index=$((observation_index + 1))
          fi
        done
        if [[ ${#observed_affected_units[@]} -gt 0 ]]; then
          qa_affected_units="$(printf '%s\n' "${observed_affected_units[@]}" \
            | LC_ALL=C sort -u | paste -sd, -)"
        fi
        set_semantic_comment_observation "$project" "$evidence_url" "$promotion_url" \
          "$qa_verdict" "$head_sha" "$source_relative" "$qa_affected_units"
      fi
      ;;
  esac
}

run_for() {
  local project="$1"
  local setup_result command_result argument
  shift
  set +e
  ( set -Eeuo pipefail; prepare_observation_for_command "$project" "$@" )
  setup_result=$?
  set -e
  if [[ $setup_result -ne 0 ]]; then
    printf '%s\n' \
      'HARNESS_SETUP_FAILURE: observation setup failed before command execution.' >&2
    return 125
  fi
  if OPENCAW_PROJECT_ROOT="$project" "$@"; then
    return 0
  else
    command_result=$?
  fi
  printf 'HARNESS_COMMAND_FAILURE:' >&2
  for argument in "$@"; do
    printf ' %q' "$argument" >&2
  done
  printf '\n' >&2
  return "$command_result"
}

run_for_without_observation() {
  local project="$1"
  shift
  OPENCAW_PROJECT_ROOT="$project" "$@"
}

write_parent_task() {
  local project="$1"
  local task_name="$2"
  local issue_number="$3"
  mkdir -p "$project/.ai/tasks/$task_name"
  cat >"$project/.ai/tasks/$task_name/TASK.md" <<EOF
# Gauntlet parent fixture

## Goal

Exercise the Gauntlet lifecycle against local fixture evidence.

## Scope

Local fixture files only.

## Assumptions

No external services are available.

## Work Instructions

Build and inspect the fixture artifact.

## Verification

Run deterministic local checks.

## Review

Use a separate critic identity.

## Issue
https://github.com/example/opencaw-fixture/issues/$issue_number
EOF
}

copy_gauntlet() {
  local source_dir="$1"
  local destination_dir="$2"
  local destination_name
  local source_integration_branch
  local source_integration_sha
  local source_name
  local source_contract_fingerprint
  local destination_contract_fingerprint
  local copied_file
  mkdir -p "$(dirname "$destination_dir")"
  cp -R "$source_dir" "$destination_dir"
  if [[ -f "$destination_dir/GAUNTLET.md" ]]; then
    destination_name="$(basename "$destination_dir")"
    source_integration_branch="$(sed -nE 's/^- Integration branch: (.+)$/\1/p' "$destination_dir/GAUNTLET.md" | head -n 1)"
    source_contract_fingerprint="$(sed -nE \
      's/^- Execution contract fingerprint: ([0-9a-f]{64})$/\1/p' \
      "$destination_dir/GAUNTLET.md" | head -n 1)"
    if [[ "$source_integration_branch" == gauntlet/* ]]; then
      source_name="${source_integration_branch#gauntlet/}"
      source_integration_sha="$(git -C "$project" rev-parse --verify \
        "refs/heads/$source_integration_branch" 2>/dev/null || true)"
      replace_all_literal "$destination_dir/GAUNTLET.md" \
        ".ai/gauntlets/$source_name/" ".ai/gauntlets/$destination_name/"
      replace_all_literal "$destination_dir/GAUNTLET.md" \
        "gauntlet/$source_name/" "gauntlet/$destination_name/"
      replace_all_literal "$destination_dir/GAUNTLET.md" \
        "gauntlet-work/$source_name/" "gauntlet-work/$destination_name/"
      replace_line "$destination_dir/GAUNTLET.md" \
        "- Integration branch: $source_integration_branch" \
        "- Integration branch: gauntlet/$destination_name"
      replace_all_literal "$destination_dir/GAUNTLET.md" \
        "gauntlet/$source_name" "gauntlet/$destination_name"
      while IFS= read -r copied_file; do
        [[ -n "$copied_file" ]] || continue
        replace_all_literal "$copied_file" \
          ".ai/gauntlets/$source_name/" ".ai/gauntlets/$destination_name/"
        replace_all_literal "$copied_file" \
          "gauntlet/$source_name" "gauntlet/$destination_name"
        replace_all_literal "$copied_file" \
          "gauntlet-work/$source_name" "gauntlet-work/$destination_name"
      done < <(find "$destination_dir" -type f -name '*.md' \
        -print 2>/dev/null | LC_ALL=C sort)
      if [[ -n "$source_integration_sha" ]]; then
        set_local_ref "$project" "gauntlet/$destination_name" "$source_integration_sha"
        set_remote_ref "$project" "gauntlet/$destination_name" "$source_integration_sha"
      fi
      if [[ -n "$source_contract_fingerprint" ]]; then
        destination_contract_fingerprint="$(OPENCAW_PROJECT_ROOT="$project" bash -c '
          set -euo pipefail
          source commands/lib/gauntlet-common.sh
          gauntlet_execution_contract_fingerprint "$1"
        ' _ "$destination_dir/GAUNTLET.md")"
        while IFS= read -r copied_file; do
          replace_all_literal "$copied_file" "$source_contract_fingerprint" \
            "$destination_contract_fingerprint"
        done < <(find "$destination_dir" -type f -name '*.md' -print | LC_ALL=C sort)
      fi
      stabilize_copied_evidence_hashes "$destination_dir"
      sync_gauntlet_live_observations "$project" "$destination_dir"
    fi
  fi
}

ordered_event_files() {
  local event_root="$1"

  [[ -d "$event_root" ]] || return 0
  find "$event_root" -type f -name 'event-*.md' -print 2>/dev/null \
    | awk '
        {
          name = $0
          sub(/^.*\/event-/, "", name)
          sub(/\.md$/, "", name)
          if (name ~ /^[0-9]+$/) print name "\t" $0
        }
      ' \
    | LC_ALL=C sort -n -k1,1 -k2,2 \
    | cut -f2-
}

sync_gauntlet_live_observations() {
  local project="$1"
  local gauntlet_dir="$2"
  local event action pr_url head_branch head_sha target_branch target_base
  local state draft created closed merged_at merged_by merged_by_type merged_by_bot
  local merge_commit
  local cross_repository head_repository checkpoint checkpoint_hash publication_body
  local promotion referenced evidence_url affected_units verdict

  while IFS= read -r event; do
    [[ -n "$event" ]] || continue
    action="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Event')"
    case "$action" in
      opened|qa-pass|qa-fail|merged|closed) ;;
      *) fail "copied progress event has an unsupported action: $event" ;;
    esac
    pr_url="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'PR URL')"
    head_branch="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Head branch')"
    head_sha="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Head SHA')"
    target_branch="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Target branch')"
    target_base="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Target base SHA')"
    cross_repository="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Cross repository')"
    head_repository="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Head repository')"
    state="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Observed state')"
    draft="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Draft')"
    created="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Created at')"
    closed="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Closed at')"
    merged_at="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Merged at')"
    merged_by="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Merged by')"
    merged_by_type="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Merged by type')"
    merged_by_bot="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Merged by bot')"
    merge_commit="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Merge commit')"
    checkpoint="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Publication checkpoint')"
    checkpoint_hash="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Publication checkpoint sha256')"
    publication_body="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint checkpoint-sha256=$checkpoint_hash -->"
    set_pr_observation "$pr_url" "$head_branch" "$head_sha" "$target_branch" \
      "$state" "$draft" "$merged_at" "$merged_by" "$merge_commit" \
      "$merged_by_bot" "$target_base" "$cross_repository" "$head_repository" \
      "$created" "$closed" "$publication_body" "$merged_by_type" "$merged_by"
  done < <(ordered_event_files "$gauntlet_dir/pr-events")

  while IFS= read -r event; do
    [[ -n "$event" ]] || continue
    action="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Event')"
    [[ "$action" == qa-pass || "$action" == qa-fail ]] || continue
    pr_url="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'PR URL')"
    head_sha="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Head SHA')"
    referenced="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Critic round')"
    evidence_url="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$event" 'PR Event Metadata' 'Evidence URL')"
    set_semantic_comment_observation "$project" "$evidence_url" "$pr_url" \
      "${action#qa-}" "$head_sha" "$referenced" none
  done < <(ordered_event_files "$gauntlet_dir/pr-events")

  while IFS= read -r promotion; do
    [[ -n "$promotion" ]] || continue
    pr_url="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Promotion PR URL')"
    head_branch="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Source branch')"
    head_sha="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Head SHA')"
    target_branch="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Target branch')"
    target_base="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Target base SHA')"
    cross_repository="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Cross repository')"
    head_repository="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Head repository')"
    state="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Observed state')"
    draft="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Draft')"
    created="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Created at')"
    closed="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Closed at')"
    merged_at="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Merged at')"
    set_pr_observation "$pr_url" "$head_branch" "$head_sha" "$target_branch" \
      "$state" "$draft" "$merged_at" none none none "$target_base" \
      "$cross_repository" "$head_repository" "$created" "$closed" ''
    evidence_url="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Evidence URL')"
    referenced="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Completion event')"
    affected_units="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Affected units')"
    verdict="$(gauntlet_helper_value "$project" gauntlet_section_field \
      "$promotion" 'Promotion QA Event Metadata' 'Verdict')"
    set_semantic_comment_observation "$project" "$evidence_url" "$pr_url" \
      "$verdict" "$head_sha" "$referenced" "$affected_units"
  done < <(ordered_event_files "$gauntlet_dir/promotion-events")
}

write_ready_gauntlet() {
  local target="$1"
  cat >"$target" <<'EOF'
# Fixture Gauntlet

## Flow and Status
- Type: gauntlet
- Status: ready

## Parent Task
- Task name: gauntlet-parent
- Task file: `.ai/tasks/gauntlet-parent/TASK.md`
- Issue: https://github.com/example/opencaw-fixture/issues/101

## Objective

Produce an inspectable local artifact that satisfies the approved fixture benchmark.

## Approved Quality Bar
- Approval: approved
- Approved by: fixture-user
- Approved at: 2026-08-01T12:00:00Z
- Frozen: yes
- Benchmark: Local artifact quality contract version 1.

### Criteria
- The artifact exists and contains the expected verified behavior.
- The focused local verifier passes without network access.

## Constraints and Permissions

### Constraints
- Keep all writes inside the explicit fixture project root.
- Do not use network services or credentials.

### Permissions
- Read and edit the local fixture artifact.
- Run deterministic local shell verification.

## Work Units
- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier

### Unit History
- No unit changes recorded.

## Current State
- Active work unit: unit-1
- Latest round: none
- Quality bar fingerprint: pending
- Unit manifest fingerprint: pending
- Execution contract fingerprint: pending
- Next action: Build unit-1 and request a fresh isolated critic.

## Round Ledger
- No rounds recorded.

## Progress PR Ledger
- No progress PR events recorded.

## Promotion QA Ledger
- No promotion QA events recorded.

## Completion Ledger
- No completion events recorded.

## Integration Review
- Verdict: pending
- Critic ID:
- Isolation:
- Evidence:
- Head SHA:
- Quality bar fingerprint: pending
- Unit manifest fingerprint: pending
- Execution contract fingerprint: pending
- Base commit SHA: pending
- Scope fingerprint: pending

## Delivery
- Base branch: main
- Base commit SHA: BASE_COMMIT_SHA_PLACEHOLDER
- Integration branch: gauntlet/fixture-gauntlet
- Progress PR publication: automatic after approval
- Progress PR QA: required
- Progress PR merge: human only
- Promotion PR readiness confirmation: human required
- Promotion PR: required
- Post-promotion QA: required
- Auto-merge: disabled
- Merge approval: human only
- PR eligible: no
- Promotion PR URL:

## Review Notes

Fixture lifecycle evidence only.
EOF
  replace_line "$target" '- Base commit SHA: BASE_COMMIT_SHA_PLACEHOLDER' \
    "- Base commit SHA: $base_commit_sha"
  local approved_manifest
  approved_manifest="$(unit_manifest_fingerprint "$project" "$target")"
  replace_line "$target" '- No unit changes recorded.' \
    "- Unit manifest approval: $approved_manifest | units: unit-1 | approved by: fixture-user | approved at: 2026-08-01T12:00:00Z"
}

write_critic_report() {
  local target="$1"
  local verdict="$2"
  local artifact="$3"
  local head_sha="$4"
  local gap="$5"
  local strategy="$6"
  cat >"$target" <<EOF
# Critic Report

## Artifact Inspected
- Artifact: $artifact
- Head SHA: $head_sha
- Evidence: The critic inspected the concrete local artifact and its focused verifier output.

## Bar Comparison
- Comparison: The artifact was compared directly with every approved fixture criterion.

## Guardrail Results
- Result: Root confinement, offline operation, and fixture integrity were checked.

## Verdict
- Verdict: $verdict

## Largest Remaining Gap
- Gap: $gap

## Next Strategy
- Strategy: $strategy
EOF
}

fake_network_bin="$temp_root/fake-network-bin"
mkdir -p "$fake_network_bin"
fake_gh_state="$temp_root/fake-gh-state.tsv"
fake_gh_marker="$temp_root/fake-gh-invocations.log"
fake_gh_comments="$temp_root/fake-gh-comments.tsv"
fake_gh_api_marker="$temp_root/fake-gh-api-invocations.log"
fake_gh_comment_bodies="$temp_root/fake-gh-comment-bodies.log"
fake_git_remote_state="$temp_root/fake-git-remote-refs.tsv"
fake_git_marker="$temp_root/fake-git-invocations.log"
: >"$fake_gh_state"
: >"$fake_gh_marker"
: >"$fake_gh_comments"
: >"$fake_gh_api_marker"
: >"$fake_gh_comment_bodies"
: >"$fake_git_remote_state"
: >"$fake_git_marker"
export FAKE_GH_STATE="$fake_gh_state"
export FAKE_GH_MARKER="$fake_gh_marker"
export FAKE_GH_COMMENTS="$fake_gh_comments"
export FAKE_GH_API_MARKER="$fake_gh_api_marker"
export FAKE_GH_COMMENT_BODIES="$fake_gh_comment_bodies"
export FAKE_GIT_REMOTE_STATE="$fake_git_remote_state"
export FAKE_GIT_MARKER="$fake_git_marker"
real_git_path="$(command -v git)"
export REAL_GIT="$real_git_path"
export FAKE_GH_AUTH_LOGIN='fixture-user'
export FAKE_GH_AUTH_TYPE='User'
export FAKE_GH_DEFAULT_BRANCH='main'

cat >"$fake_network_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 5 && "$1" == -C && "$3" == fetch \
  && "$4" == --no-tags && "$5" == origin ]]; then
  printf 'fetch\t%s\torigin\n' "$(cd "$2" && pwd -P)" >>"$FAKE_GIT_MARKER"
  exit 0
fi

if [[ "$#" -eq 6 && "$1" == -C && "$3" == ls-remote \
  && "$4" == --heads && "$5" == origin && "$6" == refs/heads/* ]]; then
  canonical_root="$(cd "$2" && pwd -P)"
  expected_ref="$6"
  printf 'ls-remote\t%s\t%s\n' "$canonical_root" "$expected_ref" >>"$FAKE_GIT_MARKER"
  if [[ -n "${FAKE_GIT_PAUSE_READY:-}" && ! -e "$FAKE_GIT_PAUSE_READY" ]]; then
    : >"$FAKE_GIT_PAUSE_READY"
    pause_attempt=0
    while [[ ! -e "${FAKE_GIT_PAUSE_RELEASE:-}" && $pause_attempt -lt 200 ]]; do
      sleep 0.01
      pause_attempt=$((pause_attempt + 1))
    done
    [[ -e "${FAKE_GIT_PAUSE_RELEASE:-}" ]] || exit 98
  fi
  awk -F '\t' -v root="$canonical_root" -v ref="$expected_ref" \
    '$1 == root && $2 == ref { print $3 "\t" $2 }' "$FAKE_GIT_REMOTE_STATE"
  exit 0
fi

if [[ "$#" -ge 3 && "$1" == -C \
  && ( "$3" == fetch || "$3" == ls-remote ) ]]; then
  exit 97
fi

exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_network_bin/git"

cat >"$fake_network_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ge 1 && "$1" == api ]]; then
  shift
  [[ "$#" -ge 2 && "$1" == --hostname && "$2" == github.com ]] || exit 76
  shift 2
  if [[ "${1:-}" == graphql ]]; then
    [[ "$#" -eq 11 ]] || exit 80
    actor_query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){mergedBy{__typename login} timelineItems(last:1,itemTypes:[AUTO_MERGE_ENABLED_EVENT,AUTO_REBASE_ENABLED_EVENT,AUTO_SQUASH_ENABLED_EVENT,ADDED_TO_MERGE_QUEUE_EVENT]){nodes{__typename}}}}}'
    actor_filter='[.data.repository.pullRequest.mergedBy.__typename // "none", .data.repository.pullRequest.mergedBy.login // "none", (if (.data.repository.pullRequest.timelineItems.nodes|length)==0 then "none" else .data.repository.pullRequest.timelineItems.nodes[0].__typename end)] | @tsv'
    [[ "$2" == -f && "$3" == "query=$actor_query" \
      && "$4" == -f && "$5" == owner=* \
      && "$6" == -f && "$7" == name=* \
      && "$8" == -F && "$9" == number=* \
      && "${10}" == --jq && "${11}" == "$actor_filter" ]] || exit 79
    actor_owner="${5#owner=}"
    actor_repo="${7#name=}"
    actor_number="${9#number=}"
    [[ "$actor_number" =~ ^[1-9][0-9]*$ ]] || exit 78
    actor_url="https://github.com/$actor_owner/$actor_repo/pull/$actor_number"
    printf '%s\t%s\n' graphql "$actor_filter" >>"$FAKE_GH_API_MARKER"
    actor_record="$(awk -F '\t' -v url="$actor_url" \
      '$1 == url { found=$0 } END { if (found == "") exit 1; print found }' \
      "$FAKE_GH_STATE")" || exit 77
    actor_type="$(awk -F '\t' '{ print $16 }' <<<"$actor_record")"
    actor_login="$(awk -F '\t' '{ print $17 }' <<<"$actor_record")"
    merge_automation_event="$(awk -F '\t' '{ print $19 }' <<<"$actor_record")"
    printf '%s\t%s\t%s\n' "$actor_type" "$actor_login" \
      "$merge_automation_event"
    exit 0
  fi
  [[ "$#" -eq 3 ]] || exit 81
  endpoint="$1"
  shift
  [[ "$1" == --jq ]] || exit 82
  jq_filter="$2"
  if [[ "$endpoint" == user ]]; then
    expected_filter='[.login, .type] | @tsv'
    [[ "$jq_filter" == "$expected_filter" ]] || exit 83
    printf '%s\t%s\n' "$endpoint" "$jq_filter" >>"$FAKE_GH_API_MARKER"
    printf '%s\t%s\n' "$FAKE_GH_AUTH_LOGIN" "$FAKE_GH_AUTH_TYPE"
    exit 0
  fi
  expected_filter='[.html_url, .issue_url, (.id | tostring), (.body // "" | @base64), (.user.login // "none"), (.user.type // "none"), (.author_association // "none"), (.created_at // "none"), (.updated_at // "none")] | @tsv'
  [[ "$jq_filter" == "$expected_filter" ]] || exit 83
  printf '%s\t%s\n' "$endpoint" "$jq_filter" >>"$FAKE_GH_API_MARKER"
  record="$(awk -F '\t' -v endpoint="$endpoint" \
    '$1 == endpoint { found=$0 } END { if (found == "") exit 1; print found }' \
    "$FAKE_GH_COMMENTS")" || exit 84
  IFS=$'\t' read -r observed_endpoint html_url issue_url comment_id body_base64 \
    author_login author_type author_association created_at updated_at <<<"$record"
  [[ "$observed_endpoint" == "$endpoint" ]] || exit 85
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$html_url" "$issue_url" "$comment_id" "$body_base64" "$author_login" \
    "$author_type" "$author_association" "$created_at" "$updated_at"
  exit 0
fi

if [[ "${1:-}" == pr && "${2:-}" == view && " $* " == *' --repo '* ]]; then
  [[ "${GH_HOST:-}" == github.com ]] || exit 75
fi

if [[ "$#" -eq 7 && "$1" == repo && "$2" == view \
  && "$4" == --json && "$5" == defaultBranchRef \
  && "$6" == --jq && "$7" == .defaultBranchRef.name ]]; then
  [[ "${GH_HOST:-}" == github.com ]] || exit 75
  printf '%s\n' "${FAKE_GH_DEFAULT_BRANCH:-main}"
  exit 0
fi

if [[ "$#" -eq 7 && "$1" == pr && "$2" == view \
  && "$4" == --json && "$5" == url && "$6" == -q && "$7" == .url ]]; then
  printf '%s\n' "${3%/}"
  exit 0
fi

if [[ "$#" -eq 5 && "$1" == pr && "$2" == comment && "$4" == --body-file ]]; then
  printf '%s\n' '--- COMMENT BODY ---' >>"$FAKE_GH_COMMENT_BODIES"
  cat "$5" >>"$FAKE_GH_COMMENT_BODIES"
  printf '\n' >>"$FAKE_GH_COMMENT_BODIES"
  printf '%s#issuecomment-9900\n' "${3%/}"
  exit 0
fi

[[ "$#" -ge 3 && "$1" == pr && "$2" == view ]] || exit 91
shift 2
pr_url="$1"
shift
repo=''
json_fields=''
jq_filter=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --json) json_fields="$2"; shift 2 ;;
    --jq) jq_filter="$2"; shift 2 ;;
    *) exit 92 ;;
  esac
done

expected_fields='url,headRefName,headRefOid,baseRefName,baseRefOid,isCrossRepository,headRepository,state,isDraft,createdAt,closedAt,mergedAt,mergedBy,mergeCommit,body'
expected_pr_filter='[.url, .headRefName, .headRefOid, .baseRefName, .baseRefOid, (.isCrossRepository | tostring), (.headRepository.nameWithOwner // "none"), .state, (.isDraft | tostring), (.createdAt // "none"), (.closedAt // "none"), (.mergedAt // "none"), (.mergedBy.login // "none"), (if .mergedBy == null then "none" elif .mergedBy.is_bot == null then "none" else (.mergedBy.is_bot | tostring) end), (.mergeCommit.oid // "none"), (.body // "" | @base64)] | @tsv'
[[ "$json_fields" == "$expected_fields" ]] || exit 93
[[ -n "$repo" && "$jq_filter" == "$expected_pr_filter" ]] || exit 94
printf '%s\t%s\t%s\t%s\n' \
  "$pr_url" "$repo" "$json_fields" "$jq_filter" >>"$FAKE_GH_MARKER"

record="$(awk -F '\t' -v url="${pr_url%/}" '$1 == url { found=$0 } END { if (found == "") exit 1; print found }' "$FAKE_GH_STATE")" \
  || exit 95
IFS=$'\t' read -r observed_url head_branch head_sha base_branch base_ref_oid \
  is_cross_repository head_repository state is_draft created_at closed_at merged_at \
  merged_by merged_by_bot merge_commit _actor_type _actor_login \
  <<<"$(printf '%s\n' "$record" | cut -f1-17)"
pr_body_base64="$(awk -F '\t' '{ print $18 }' <<<"$record")"
_merge_automation_event="$(awk -F '\t' '{ print $19 }' <<<"$record")"
[[ "$observed_url" == "${pr_url%/}" ]] || exit 96

if [[ -n "${FAKE_GH_MUTATE_BODY_URL:-}" \
  && "${pr_url%/}" == "${FAKE_GH_MUTATE_BODY_URL%/}" \
  && -n "${FAKE_GH_MUTATE_BODY_TRIGGER:-}" \
  && -n "${FAKE_GH_MUTATE_BODY_BASE64:-}" ]]; then
  if [[ -e "$FAKE_GH_MUTATE_BODY_TRIGGER" ]]; then
    pr_body_base64="$FAKE_GH_MUTATE_BODY_BASE64"
  else
    : >"$FAKE_GH_MUTATE_BODY_TRIGGER"
  fi
fi

if [[ -n "${FAKE_GH_DELAY_SECONDS:-}" ]]; then
  sleep "$FAKE_GH_DELAY_SECONDS"
fi
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$observed_url" "$head_branch" "$head_sha" "$base_branch" "$base_ref_oid" \
  "$is_cross_repository" "$head_repository" "$state" "$is_draft" \
  "$created_at" "$closed_at" "$merged_at" "$merged_by" "$merged_by_bot" \
  "$merge_commit" "$pr_body_base64"
EOF
chmod +x "$fake_network_bin/gh"

cat >"$fake_network_bin/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == -u && $# -eq 2 ]] || exit 86
case "$2" in
  '+%Y-%m-%dT%H:%M:%SZ') printf '%s\n' "${FAKE_DATE_ISO:-2026-08-01T12:00:00Z}" ;;
  '+%Y%m%d-%H%M%S') printf '20260801-120000\n' ;;
  '+%Y-%m-%d %H:%M:%SZ') printf '2026-08-01 12:00:00Z\n' ;;
  *) exit 87 ;;
esac
EOF
chmod +x "$fake_network_bin/date"

for command_name in github curl wget; do
  cat >"$fake_network_bin/$command_name" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$command_name' >>'$network_marker'
exit 97
EOF
  chmod +x "$fake_network_bin/$command_name"
done
export PATH="$fake_network_bin:$PATH"
unset GH_TOKEN GITHUB_TOKEN 2>/dev/null || true
export GH_HOST='attacker.example'

head_sha_1=''
head_sha_2=''
head_sha_3=''
head_sha_4=''
head_sha_5=''
head_sha_6=''
head_sha_7=''
head_sha_8=''
head_sha_9=''
divergent_sha=''
orphan_sha=''
base_commit_sha=''
builder_strategy_1='Implement the initial scoped artifact behavior with focused boundary verification.'
builder_strategy_2='Replace the boundary adapter and add deterministic recovery assertions.'
builder_strategy_3='Complete the scoped behavior and verify every approved unit criterion.'
builder_strategy_4='Repair the QA regression with a new implementation path and focused checks.'
builder_strategy_5='Rebuild the reopened scope against the revised quality bar and rerun verification.'
builder_strategy_6='Correct the integrated recovery path through a newly isolated remediation change.'
builder_strategy_7='Repair the promotion regression on a fresh remediation branch and rerun checks.'
integration_strategy_1='Assemble and inspect the integration branch against every active unit contract.'
integration_strategy_2='Diagnose the cross-unit failure and compare the full integrated artifact again.'
integration_strategy_3='Reinspect the corrected integration branch and all final guardrails.'
integration_strategy_4='Repeat the independent final integration review from a fresh evidence strategy without changing the verified head.'

harness_setup_probe_log="$temp_root/harness-setup-probe.log"
harness_setup_guard_log="$temp_root/harness-setup-guard.log"
set +e
(
  expect_failure "$harness_setup_probe_log" bash -c \
    'printf "%s\n" "HARNESS_SETUP_FAILURE: synthetic setup failure" >&2; exit 125'
) >"$harness_setup_guard_log" 2>&1
harness_setup_guard_status=$?
set -e
[[ $harness_setup_guard_status -ne 0 ]] \
  || fail 'expect_failure accepted a harness setup failure as a production rejection'
grep -Fq 'HARNESS_SETUP_FAILURE: synthetic setup failure' "$harness_setup_guard_log" \
  || fail 'expect_failure did not surface the captured harness setup failure'
expect_failure "$temp_root/direct-production-rejection.log" bash -c 'exit 23'

echo '[1/8] checking command interfaces and isolated scaffold behavior'
for budget_contract in AGENTS.md README.md skills/gauntlet-flow/SKILL.md \
  .roles/computer-science/project-manager/ROLE.md; do
  grep -Fq '45 minutes or two failed full-validation epochs' "$budget_contract" \
    || fail "Gauntlet autonomous-window checkpoint is missing from $budget_contract"
done
! rg -q 'Do not impose an automatic attempt, time, cost, or diminishing-return limit|There is no automatic round, time, cost, or diminishing-return limit' \
  AGENTS.md README.md skills/gauntlet-flow/SKILL.md \
  .roles/computer-science/project-manager/ROLE.md \
  || fail 'obsolete unlimited Gauntlet continuation language remains in a behavioral contract'
for command_name in create-gauntlet-file validate-gauntlet record-gauntlet-round \
  record-gauntlet-pr-event record-gauntlet-promotion-qa; do
  command_file="commands/$command_name.sh"
  [[ -x "$command_file" ]] || fail "Gauntlet command is missing or not executable: $command_file"
  bash "$command_file" --help >/dev/null || fail "$command_name --help failed"
done

pr_readiness_help="$(bash commands/pr-readiness-check.sh --help)"
[[ "$pr_readiness_help" == *'non-closing `Refs #<issue>`'* \
  && "$pr_readiness_help" == *'`Closes #<issue>`'* ]] \
  || fail 'Gauntlet readiness help omitted progressive versus promotion issue-link semantics'
pr_event_help="$(bash commands/record-gauntlet-pr-event.sh --help)"
[[ "$pr_event_help" == *'`Refs #<issue>`'* \
  && "$pr_event_help" == *'reserved for the final promotion PR'* ]] \
  || fail 'progress-PR event help omitted its non-closing parent-issue contract'
completion_help="$(bash commands/create-gauntlet-completion-report.sh --help)"
[[ "$completion_help" == *'`Closes #<issue>`'* \
  && "$completion_help" == *'non-closing `Refs #<issue>`'* ]] \
  || fail 'completion help omitted its promotion-only closing issue contract'
link_issue_help="$(bash commands/link-pr-to-task-issue.sh --help)"
[[ "$link_issue_help" == *'Do not use this command for Gauntlet'* \
  && "$link_issue_help" == *'`Refs #<issue>`'* ]] \
  || fail 'task issue-link command help did not exclude Gauntlet progress PRs'

project="$(new_project gauntlet-project)"
initialize_fixture_commits "$project"
base_commit_sha="$(git -C "$project" rev-parse refs/heads/main)"
closing_reference_count="$(gauntlet_helper_value "$project" \
  gauntlet_github_closing_reference_count \
  $'Refs #101\nResolves #7, closes: example/opencaw-fixture#101' \
  'https://github.com/example/opencaw-fixture/issues/101')"
[[ "$closing_reference_count" == 1 ]] \
  || fail 'GitHub closing-keyword parser missed colon, qualified, or comma-separated syntax'
zero_padded_closing_count="$(gauntlet_helper_value "$project" \
  gauntlet_github_closing_reference_count \
  $'Closes #0101\nFixes: example/opencaw-fixture#000101\nResolved GH-000101\nClosed https://github.com/example/opencaw-fixture/issues/000101?source=pr\nClose [the parent](https://github.com/example/opencaw-fixture/issues/000101)' \
  'https://github.com/example/opencaw-fixture/issues/101')"
[[ "$zero_padded_closing_count" == 5 ]] \
  || fail 'GitHub closing-keyword parser missed zero-padded, GH-, URL, or Markdown-link aliases'
expect_failure "$temp_root/noncanonical-progress-directive.log" \
  gauntlet_helper_value "$project" gauntlet_assert_progress_issue_link \
  $'refs #101\n<!-- checkpoint follows -->' \
  'https://github.com/example/opencaw-fixture/issues/101'
expect_failure "$temp_root/buried-promotion-directive.log" \
  gauntlet_helper_value "$project" gauntlet_assert_promotion_issue_link \
  $'Promotion review\nCloses #101' \
  'https://github.com/example/opencaw-fixture/issues/101'
expect_failure "$temp_root/markdown-closing-progress-link.log" \
  gauntlet_helper_value "$project" gauntlet_assert_progress_issue_link \
  $'Refs #101\nCloses [#101](https://github.com/example/opencaw-fixture/issues/101)' \
  'https://github.com/example/opencaw-fixture/issues/101'

numeric_round_dir="$temp_root/numeric-round-selection"
mkdir -p "$numeric_round_dir"
cat >"$numeric_round_dir/round-999.md" <<'EOF'
# Numeric round fixture 999

## Round Metadata
- Progress PR: https://github.com/example/opencaw-fixture/pull/900
EOF
cat >"$numeric_round_dir/round-1000.md" <<'EOF'
# Numeric round fixture 1000

## Round Metadata
- Progress PR: https://github.com/example/opencaw-fixture/pull/900
EOF
cat >"$numeric_round_dir/round-1001.md" <<'EOF'
# Numeric round fixture 1001

## Round Metadata
- Progress PR: https://github.com/example/opencaw-fixture/pull/901
EOF
numeric_latest_for_pr="$(gauntlet_helper_value "$project" \
  gauntlet_latest_round_file_for_pr "$numeric_round_dir" \
  'https://github.com/example/opencaw-fixture/pull/900')"
[[ "$numeric_latest_for_pr" == "$numeric_round_dir/round-1000.md" ]] \
  || fail 'PR-filtered close replay selected round-999 lexically instead of round-1000 numerically'
numeric_latest_overall="$(gauntlet_helper_value "$project" \
  gauntlet_latest_round_file "$numeric_round_dir")"
[[ "$numeric_latest_overall" == "$numeric_round_dir/round-1001.md" ]] \
  || fail 'latest-round replay did not preserve numeric ordering above 999'

numeric_completion_dir="$temp_root/numeric-completion-selection"
mkdir -p "$numeric_completion_dir"
printf '%s\n' '# Numeric completion fixture 999' \
  >"$numeric_completion_dir/event-999.md"
printf '%s\n' '# Numeric completion fixture 1000' \
  >"$numeric_completion_dir/event-1000.md"
numeric_latest_completion="$(gauntlet_helper_value "$project" \
  gauntlet_latest_completion_event_file "$numeric_completion_dir")"
[[ "$numeric_latest_completion" == "$numeric_completion_dir/event-1000.md" ]] \
  || fail 'latest completion replay selected event-999 lexically instead of event-1000 numerically'

numeric_event_dir="$temp_root/numeric-event-selection/unit-1"
mkdir -p "$numeric_event_dir"
: >"$numeric_event_dir/event-999.md"
: >"$numeric_event_dir/event-1000.md"
numeric_event_order="$(ordered_event_files "$temp_root/numeric-event-selection")"
[[ "$numeric_event_order" == "$numeric_event_dir/event-999.md"$'\n'"$numeric_event_dir/event-1000.md" ]] \
  || fail 'copied-event replay selected event-1000 lexically before event-999'

for ordinal in 1 2 3 4 5 6 7 8 9; do
  sha_variable="head_sha_$ordinal"
  fixture_sha="${!sha_variable}"
  git -C "$project" cat-file -e "$fixture_sha^{commit}" 2>/dev/null \
    || fail "fixture Head SHA is not a real commit object: $fixture_sha"
  git -C "$project" show-ref --verify --quiet "refs/heads/fixture/review-$ordinal" \
    || fail "fixture Head SHA is not retained by a deterministic local ref: $fixture_sha"
done
git -C "$project" cat-file -e "$artifact_absent_sha^{commit}" 2>/dev/null \
  || fail 'artifact-absent fixture is not a real commit object'
if git -C "$project" cat-file -e "$artifact_absent_sha:artifact.txt" 2>/dev/null; then
  fail 'artifact-absent fixture unexpectedly contains artifact.txt'
fi
git -C "$project" cat-file -e "$divergent_sha:artifact.txt" 2>/dev/null \
  || fail 'divergent integration fixture does not retain the inspectable artifact'
if git -C "$project" merge-base --is-ancestor "$head_sha_4" "$divergent_sha"; then
  fail 'divergent integration fixture unexpectedly contains the latest unit merge ancestry'
fi
git -C "$project" cat-file -e "$orphan_sha:artifact.txt" 2>/dev/null \
  || fail 'orphan integration fixture does not retain the inspectable artifact'
if git -C "$project" merge-base --is-ancestor "$base_commit_sha" "$orphan_sha"; then
  fail 'orphan integration fixture unexpectedly descends from the frozen base commit'
fi
gh_probe_url='https://github.com/example/opencaw-fixture/pull/199'
gh_pr_jq_filter='[.url, .headRefName, .headRefOid, .baseRefName, .baseRefOid, (.isCrossRepository | tostring), (.headRepository.nameWithOwner // "none"), .state, (.isDraft | tostring), (.createdAt // "none"), (.closedAt // "none"), (.mergedAt // "none"), (.mergedBy.login // "none"), (if .mergedBy == null then "none" elif .mergedBy.is_bot == null then "none" else (.mergedBy.is_bot | tostring) end), (.mergeCommit.oid // "none"), (.body // "" | @base64)] | @tsv'
set_pr_observation "$gh_probe_url" gauntlet-work/probe/unit-1 "$head_sha_1" gauntlet/probe \
  OPEN false none none none none "$base_commit_sha"
gh_probe_output="$(env GH_HOST=github.com gh pr view "$gh_probe_url" \
  --repo example/opencaw-fixture \
  --json url,headRefName,headRefOid,baseRefName,baseRefOid,isCrossRepository,headRepository,state,isDraft,createdAt,closedAt,mergedAt,mergedBy,mergeCommit,body \
  --jq "$gh_pr_jq_filter")"
[[ "$gh_probe_output" == "$gh_probe_url"$'\t'gauntlet-work/probe/unit-1$'\t'"$head_sha_1"$'\t'gauntlet/probe$'\t'"$base_commit_sha"$'\t'false$'\t'example/opencaw-fixture$'\t'OPEN$'\t'false$'\t'2026-08-01T12:00:00Z$'\t'none$'\t'none$'\t'none$'\t'none$'\t'none$'\t' ]] \
  || fail 'offline gh fixture did not return its exact deterministic PR observation'
expect_failure "$temp_root/gh-wrong-fields.log" env GH_HOST=github.com \
  gh pr view "$gh_probe_url" --repo example/opencaw-fixture \
  --json url,state --jq fixture-filter
run_for "$project" bash commands/create-host-ai-scaffold.sh >/dev/null
run_for "$project" bash commands/create-host-ai-scaffold.sh >/dev/null
[[ -d "$project/.ai/gauntlets" ]] || fail 'scaffold omitted .ai/gauntlets'
[[ -d "$project/.ai/archive/gauntlets" ]] || fail 'scaffold omitted .ai/archive/gauntlets'
[[ ! -e "$temp_root/.ai" ]] || fail 'scaffold escaped the explicit project root'

write_parent_task "$project" gauntlet-parent 101
dry_run_output="$temp_root/create-dry-run.log"
run_for "$project" bash commands/create-gauntlet-file.sh dry-run-gauntlet 'Dry-run Gauntlet' --task gauntlet-parent --dry-run >"$dry_run_output"
grep -q 'Dry run:' "$dry_run_output" || fail 'create dry-run did not identify itself'
grep -q -- '- Type: gauntlet' "$dry_run_output" || fail 'create dry-run omitted the Gauntlet flow marker'
grep -q '^## Progress PR Ledger$' "$dry_run_output" || fail 'create dry-run omitted the Progress PR Ledger'
grep -q '^## Promotion QA Ledger$' "$dry_run_output" || fail 'create dry-run omitted the Promotion QA Ledger'
grep -q '^## Completion Ledger$' "$dry_run_output" || fail 'create dry-run omitted the Completion Ledger'
grep -q -- '- No completion events recorded.' "$dry_run_output" \
  || fail 'create dry-run omitted the empty Completion Ledger placeholder'
grep -q -- '- Base branch: pending' "$dry_run_output" || fail 'create dry-run omitted the pending delivery base'
grep -q -- '- Base commit SHA: pending' "$dry_run_output" \
  || fail 'create dry-run omitted the pending delivery base commit'
grep -q -- '- Integration branch: gauntlet/dry-run-gauntlet' "$dry_run_output" \
  || fail 'create dry-run omitted the durable integration branch'
grep -Eq '^-[[:space:]]\[[[:space:]]\] unit-1 .*\| scope: ' "$dry_run_output" \
  || fail 'create dry-run omitted the required work-unit scope field'
grep -q -- '- Unit manifest fingerprint: pending' "$dry_run_output" \
  || fail 'create dry-run omitted the pending retained-unit manifest fingerprint'
[[ ! -e "$project/.ai/gauntlets/dry-run-gauntlet" ]] || fail 'create dry-run changed project state'

expect_failure "$temp_root/invalid-name.log" run_for "$project" bash commands/create-gauntlet-file.sh 'Invalid_Name' --task gauntlet-parent
expect_failure "$temp_root/escaping-name.log" run_for "$project" bash commands/create-gauntlet-file.sh '../../escape' --task gauntlet-parent
expect_failure "$temp_root/missing-task.log" run_for "$project" bash commands/create-gauntlet-file.sh missing-task-gauntlet --task absent-task

create_output="$temp_root/create.log"
run_for "$project" bash commands/create-gauntlet-file.sh fixture-gauntlet 'Fixture Gauntlet' --task gauntlet-parent >"$create_output"
gauntlet_dir="$project/.ai/gauntlets/fixture-gauntlet"
gauntlet_file="$gauntlet_dir/GAUNTLET.md"
expect_file "$gauntlet_file"
grep -Fq '.ai/tasks/gauntlet-parent/TASK.md' "$gauntlet_file" || fail 'Gauntlet did not link its parent task'
grep -Fq 'https://github.com/example/opencaw-fixture/issues/101' "$gauntlet_file" || fail 'Gauntlet did not link its parent issue'
expect_line '## Progress PR Ledger' "$gauntlet_file"
expect_line '## Completion Ledger' "$gauntlet_file"
expect_line '- No completion events recorded.' "$gauntlet_file"
[[ -d "$gauntlet_dir/completion-events" ]] || fail 'Gauntlet template omitted completion-events/'
[[ -d "$gauntlet_dir/publication-checkpoints" ]] \
  || fail 'Gauntlet template omitted publication-checkpoints/'
expect_line '- Base branch: pending' "$gauntlet_file"
expect_line '- Base commit SHA: pending' "$gauntlet_file"
expect_line '- Integration branch: gauntlet/fixture-gauntlet' "$gauntlet_file"
grep -Eq '^-[[:space:]]\[[[:space:]]\] unit-1 .*\| scope: ' "$gauntlet_file" \
  || fail 'Gauntlet template omitted the required work-unit scope field'
expect_line '- Unit manifest fingerprint: pending' "$gauntlet_file"
[[ ! -e "$temp_root/escape" ]] || fail 'invalid Gauntlet name escaped the project root'

before_hash="$(git hash-object "$gauntlet_file")"
run_for "$project" bash commands/create-gauntlet-file.sh fixture-gauntlet 'Replacement title' --task gauntlet-parent >/dev/null
after_hash="$(git hash-object "$gauntlet_file")"
[[ "$before_hash" == "$after_hash" ]] || fail 'idempotent create overwrote an existing Gauntlet'

echo '[2/8] enforcing ready-state quality, linkage, and delivery gates'
write_ready_gauntlet "$gauntlet_file"
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh "$gauntlet_dir" --phase ready >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh "$gauntlet_file" --phase ready >/dev/null

linked_root_project="$(new_project linked-gauntlet-root-project)"
mkdir -p "$linked_root_project/.ai" "$temp_root/outside-gauntlet-root"
write_parent_task "$linked_root_project" gauntlet-parent 101
ln -s "$temp_root/outside-gauntlet-root" "$linked_root_project/.ai/gauntlets"
expect_failure "$temp_root/linked-gauntlet-root.log" run_for "$linked_root_project" \
  bash commands/create-gauntlet-file.sh escaped-root-gauntlet --task gauntlet-parent

outside_gauntlet_dir="$temp_root/outside-direct-gauntlet"
copy_gauntlet "$gauntlet_dir" "$outside_gauntlet_dir"
ln -s "$outside_gauntlet_dir" "$project/.ai/gauntlets/linked-gauntlet"
expect_failure "$temp_root/linked-gauntlet-dir.log" run_for "$project" \
  bash commands/validate-gauntlet.sh linked-gauntlet --phase ready
expect_failure "$temp_root/outside-gauntlet-ref.log" run_for "$project" \
  bash commands/validate-gauntlet.sh "$outside_gauntlet_dir/GAUNTLET.md" --phase ready

nested_gauntlet_dir="$project/.ai/gauntlets/nested-container/child"
mkdir -p "$nested_gauntlet_dir"
cp "$gauntlet_file" "$nested_gauntlet_dir/GAUNTLET.md"
expect_failure "$temp_root/nested-gauntlet-ref.log" run_for "$project" \
  bash commands/validate-gauntlet.sh "$nested_gauntlet_dir/GAUNTLET.md" --phase ready

outside_task_dir="$temp_root/outside-parent-task"
mkdir -p "$outside_task_dir"
cp "$project/.ai/tasks/gauntlet-parent/TASK.md" "$outside_task_dir/TASK.md"
ln -s "$outside_task_dir" "$project/.ai/tasks/symlink-task-dir"
case_dir="$project/.ai/gauntlets/symlink-task-directory"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: symlink-task-dir'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/symlink-task-dir/TASK.md`'
expect_failure "$temp_root/symlink-task-directory.log" run_for "$project" \
  bash commands/validate-gauntlet.sh symlink-task-directory --phase ready

mkdir -p "$project/.ai/tasks/symlink-task-file"
ln -s ../gauntlet-parent/TASK.md "$project/.ai/tasks/symlink-task-file/TASK.md"
case_dir="$project/.ai/gauntlets/symlink-task-file"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: symlink-task-file'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/symlink-task-file/TASK.md`'
expect_failure "$temp_root/symlink-task-file.log" run_for "$project" \
  bash commands/validate-gauntlet.sh symlink-task-file --phase ready

mkdir -p "$project/.ai/tasks/crlf-task"
cp "$project/.ai/tasks/gauntlet-parent/TASK.md" "$project/.ai/tasks/crlf-task/TASK.md"
convert_to_crlf "$project/.ai/tasks/crlf-task/TASK.md"
case_dir="$project/.ai/gauntlets/crlf-gauntlet"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: crlf-task'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/crlf-task/TASK.md`'
convert_to_crlf "$case_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh crlf-gauntlet --phase ready >/dev/null

case_dir="$project/.ai/gauntlets/missing-objective"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" 'Produce an inspectable local artifact that satisfies the approved fixture benchmark.' ''
expect_failure "$temp_root/missing-objective.log" run_for "$project" bash commands/validate-gauntlet.sh missing-objective --phase ready

case_dir="$project/.ai/gauntlets/missing-progress-pr-ledger"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '## Progress PR Ledger' '## Missing Progress PR Ledger'
expect_failure "$temp_root/missing-progress-pr-ledger.log" run_for "$project" \
  bash commands/validate-gauntlet.sh missing-progress-pr-ledger --phase ready

case_dir="$project/.ai/gauntlets/unapproved-bar"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Approval: approved' '- Approval: pending'
expect_failure "$temp_root/unapproved-bar.log" run_for "$project" bash commands/validate-gauntlet.sh unapproved-bar --phase ready

case_dir="$project/.ai/gauntlets/placeholder-bar"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- The artifact exists and contains the expected verified behavior.' '- TODO: Define inspectable pass criteria.'
expect_failure "$temp_root/placeholder-bar.log" run_for "$project" bash commands/validate-gauntlet.sh placeholder-bar --phase ready

write_parent_task "$project" task-without-issue 102
awk '$0 !~ /^https:\/\/github\.com\/example\/opencaw-fixture\/issues\/102$/' \
  "$project/.ai/tasks/task-without-issue/TASK.md" >"$project/.ai/tasks/task-without-issue/TASK.md.tmp"
mv "$project/.ai/tasks/task-without-issue/TASK.md.tmp" "$project/.ai/tasks/task-without-issue/TASK.md"
case_dir="$project/.ai/gauntlets/missing-issue"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Task name: gauntlet-parent' '- Task name: task-without-issue'
replace_line "$case_dir/GAUNTLET.md" '- Task file: `.ai/tasks/gauntlet-parent/TASK.md`' '- Task file: `.ai/tasks/task-without-issue/TASK.md`'
replace_line "$case_dir/GAUNTLET.md" '- Issue: https://github.com/example/opencaw-fixture/issues/101' '- Issue:'
expect_failure "$temp_root/missing-issue.log" run_for "$project" bash commands/validate-gauntlet.sh missing-issue --phase ready

case_dir="$project/.ai/gauntlets/invalid-unit"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier' \
  '- [ ] unit-1 | status: invented | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
expect_failure "$temp_root/invalid-unit.log" run_for "$project" bash commands/validate-gauntlet.sh invalid-unit --phase ready

case_dir="$project/.ai/gauntlets/missing-unit-scope"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier' \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact'
expect_failure "$temp_root/missing-unit-scope.log" run_for "$project" \
  bash commands/validate-gauntlet.sh missing-unit-scope --phase ready

case_dir="$project/.ai/gauntlets/placeholder-unit-scope"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier' \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: TODO define scope'
expect_failure "$temp_root/placeholder-unit-scope.log" run_for "$project" \
  bash commands/validate-gauntlet.sh placeholder-unit-scope --phase ready

case_dir="$project/.ai/gauntlets/pipe-ambiguous-unit-scope"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier' \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt | verifier output'
expect_failure "$temp_root/pipe-ambiguous-unit-scope.log" run_for "$project" \
  bash commands/validate-gauntlet.sh pipe-ambiguous-unit-scope --phase ready

case_dir="$project/.ai/gauntlets/reserved-integration-unit"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier' \
  '- [ ] integration | status: pending | title: Reserved IDs cannot be normal work units | scope: complete integrated artifact'
expect_failure "$temp_root/reserved-integration-unit.log" run_for "$project" \
  bash commands/validate-gauntlet.sh reserved-integration-unit --phase ready

case_dir="$project/.ai/gauntlets/reserved-none-unit"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier' \
  '- [ ] none | status: pending | title: Sentinel IDs cannot be normal work units | scope: complete inspectable artifact'
expect_failure "$temp_root/reserved-none-unit.log" run_for "$project" \
  bash commands/validate-gauntlet.sh reserved-none-unit --phase ready
grep -Fq 'Work-unit id is reserved: none' "$temp_root/reserved-none-unit.log" \
  || fail 'validator accepted the affected-unit sentinel as a work-unit id'

manifest_normalization_fixture="$temp_root/manifest-normalization.md"
cat >"$manifest_normalization_fixture" <<'EOF'
## Work Units
- [x] zeta-unit | status: passed | title: Zeta retained title | scope: zeta retained scope
- [ ] alpha-unit | status: pending | title: Alpha retained title | scope: alpha retained scope

### Unit History
- No unit changes recorded.
EOF
manifest_alpha_scope="$(unit_scope_fingerprint \
  "$project" "$manifest_normalization_fixture" alpha-unit)"
manifest_zeta_scope="$(unit_scope_fingerprint \
  "$project" "$manifest_normalization_fixture" zeta-unit)"
manifest_expected_material="id=alpha-unit
scope-fingerprint=$manifest_alpha_scope
id=zeta-unit
scope-fingerprint=$manifest_zeta_scope
"
manifest_normalized_hash="$(unit_manifest_fingerprint \
  "$project" "$manifest_normalization_fixture")"
[[ "$manifest_normalized_hash" == "$(sha256_text "$manifest_expected_material")" ]] \
  || fail 'retained-unit manifest did not normalize scope fingerprints by unit ID with one final newline'
manifest_active_scope="$(active_scope_fingerprint \
  "$project" "$manifest_normalization_fixture")"
replace_line "$manifest_normalization_fixture" \
  '- [x] zeta-unit | status: passed | title: Zeta retained title | scope: zeta retained scope' \
  '- [ ] zeta-unit | status: building | title: Zeta retained title | scope: zeta retained scope'
replace_line "$manifest_normalization_fixture" \
  '- [ ] alpha-unit | status: pending | title: Alpha retained title | scope: alpha retained scope' \
  '- [x] alpha-unit | status: passed | title: Alpha retained title | scope: alpha retained scope'
[[ "$manifest_normalized_hash" == "$(unit_manifest_fingerprint \
    "$project" "$manifest_normalization_fixture")" \
  && "$manifest_active_scope" == "$(active_scope_fingerprint \
    "$project" "$manifest_normalization_fixture")" ]] \
  || fail 'checkbox or non-superseded status changes altered normalized manifest or active scope'
replace_line "$manifest_normalization_fixture" \
  '- [x] alpha-unit | status: passed | title: Alpha retained title | scope: alpha retained scope' \
  '- [x] alpha-unit | status: superseded | title: Alpha retained title | scope: alpha retained scope'
[[ "$manifest_normalized_hash" == "$(unit_manifest_fingerprint \
    "$project" "$manifest_normalization_fixture")" \
  && "$manifest_active_scope" != "$(active_scope_fingerprint \
    "$project" "$manifest_normalization_fixture")" ]] \
  || fail 'superseded membership failed to change only active scope while retaining manifest identity'

case_dir="$project/.ai/gauntlets/forbidden-pr-setting"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Auto-merge: disabled' '- Auto-merge: enabled'
expect_failure "$temp_root/forbidden-pr.log" run_for "$project" bash commands/validate-gauntlet.sh forbidden-pr-setting --phase ready

case_dir="$project/.ai/gauntlets/missing-base-branch"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Base branch: main' '- Base branch:'
expect_failure "$temp_root/missing-base-branch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh missing-base-branch --phase ready

case_dir="$project/.ai/gauntlets/pending-base-branch"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Base branch: main' '- Base branch: pending'
expect_failure "$temp_root/pending-base-branch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh pending-base-branch --phase ready

case_dir="$project/.ai/gauntlets/pending-base-commit"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" "- Base commit SHA: $base_commit_sha" \
  '- Base commit SHA: pending'
expect_failure "$temp_root/pending-base-commit.log" run_for "$project" \
  bash commands/validate-gauntlet.sh pending-base-commit --phase ready

case_dir="$project/.ai/gauntlets/nonexistent-base-commit"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" "- Base commit SHA: $base_commit_sha" \
  '- Base commit SHA: 0000000000000000000000000000000000000000'
expect_failure "$temp_root/nonexistent-base-commit.log" run_for "$project" \
  bash commands/validate-gauntlet.sh nonexistent-base-commit --phase ready

case_dir="$project/.ai/gauntlets/base-branch-before-creation-point"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" "- Base commit SHA: $base_commit_sha" \
  "- Base commit SHA: $head_sha_1"
expect_failure "$temp_root/base-branch-before-creation-point.log" run_for "$project" \
  bash commands/validate-gauntlet.sh base-branch-before-creation-point --phase ready

case_dir="$project/.ai/gauntlets/prefreeze-integration-ahead"
copy_gauntlet "$gauntlet_dir" "$case_dir"
set_local_ref "$project" gauntlet/prefreeze-integration-ahead "$head_sha_1"
expect_failure "$temp_root/prefreeze-integration-ahead.log" run_for "$project" \
  bash commands/validate-gauntlet.sh prefreeze-integration-ahead --phase ready

case_dir="$project/.ai/gauntlets/integration-unrelated-to-base"
copy_gauntlet "$gauntlet_dir" "$case_dir"
set_local_ref "$project" main "$head_sha_1"
replace_line "$case_dir/GAUNTLET.md" "- Base commit SHA: $base_commit_sha" \
  "- Base commit SHA: $head_sha_1"
set_local_ref "$project" gauntlet/integration-unrelated-to-base "$divergent_sha"
expect_failure "$temp_root/integration-unrelated-to-base.log" run_for "$project" \
  bash commands/validate-gauntlet.sh integration-unrelated-to-base --phase ready
set_local_ref "$project" main "$base_commit_sha"

case_dir="$project/.ai/gauntlets/wrong-integration-branch"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- Integration branch: gauntlet/wrong-integration-branch' \
  '- Integration branch: feature/unrelated'
expect_failure "$temp_root/wrong-integration-branch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh wrong-integration-branch --phase ready

case_dir="$project/.ai/gauntlets/forbidden-progress-merge"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- Progress PR merge: human only' '- Progress PR merge: automatic'
expect_failure "$temp_root/forbidden-progress-merge.log" run_for "$project" \
  bash commands/validate-gauntlet.sh forbidden-progress-merge --phase ready

case_dir="$project/.ai/gauntlets/forbidden-promotion-gate"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" \
  '- Promotion PR readiness confirmation: human required' \
  '- Promotion PR readiness confirmation: automatic'
expect_failure "$temp_root/forbidden-promotion-gate.log" run_for "$project" \
  bash commands/validate-gauntlet.sh forbidden-promotion-gate --phase ready

case_dir="$project/.ai/gauntlets/premature-pr-eligibility"
copy_gauntlet "$gauntlet_dir" "$case_dir"
replace_line "$case_dir/GAUNTLET.md" '- PR eligible: no' '- PR eligible: yes'
expect_failure "$temp_root/premature-pr-eligibility.log" run_for "$project" \
  bash commands/validate-gauntlet.sh premature-pr-eligibility --phase ready

echo '[3/8] enforcing progressive PR publication, ownership, ordering, and path safety'
ready_snapshot="$temp_root/ready-snapshot"
copy_gauntlet "$gauntlet_dir" "$ready_snapshot"
nested_base_fixture_dir="$project/.ai/gauntlets/nested-base-fixture"
copy_gauntlet "$ready_snapshot" "$nested_base_fixture_dir"
replace_line "$nested_base_fixture_dir/GAUNTLET.md" \
  '- Base branch: main' '- Base branch: gauntlet/release'
[[ "$(fixture_issue_link "$project" \
    gauntlet/nested-base-fixture gauntlet/release)" == 'Closes #101' ]] \
  || fail 'promotion fixture misclassified a delivery base whose name begins with gauntlet/'
critic_dir="$project/critic-reports"
mkdir -p "$critic_dir"
valid_fail_report="$critic_dir/fail-round.md"
write_critic_report "$valid_fail_report" fail artifact.txt "$head_sha_1" \
  'The fixture still lacks the required verified behavior.' \
  'Rework the parsing boundary and rerun the focused verifier.'

printf '# Progress validation\n\nThe unit branch is locally verified and ready for publication.\n' \
  >"$project/progress-validation.md"
expect_line '- Execution contract fingerprint: pending' "$gauntlet_file"
set_local_ref "$project" gauntlet/fixture-gauntlet "$(git -C "$project" rev-parse HEAD)"
set_local_ref "$project" gauntlet-work/fixture-gauntlet/unit-1 "$head_sha_1"
progress_readiness_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/progress" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress fixture-gauntlet unit-1 "$project/progress-validation.md")"
grep -q '^USER_CONFIRMATION_REQUIRED=NO$' <<<"$progress_readiness_output" \
  || fail 'approved Gauntlet progress publication unexpectedly required another confirmation'
grep -q '^GAUNTLET_FLOW=YES$' <<<"$progress_readiness_output" \
  || fail 'progress readiness did not identify Gauntlet mode'
grep -q '^GAUNTLET_PROGRESS_AUTOMATION=YES$' <<<"$progress_readiness_output" \
  || fail 'progress readiness did not authorize automatic publication'
grep -q '^TARGET_BRANCH=gauntlet/fixture-gauntlet$' <<<"$progress_readiness_output" \
  || fail 'progress readiness did not target the durable integration branch'
grep -q '^ISSUE_LINK=Refs #101$' <<<"$progress_readiness_output" \
  || fail 'progress readiness did not emit a non-closing parent-issue reference'
grep -q "^HEAD_SHA=$head_sha_1$" <<<"$progress_readiness_output" \
  || fail 'progress readiness did not bind publication to the exact local work-branch commit'
progress_execution_contract="$(sed -nE \
  's/^EXECUTION_CONTRACT_FINGERPRINT=([0-9a-f]{64})$/\1/p' \
  <<<"$progress_readiness_output")"
[[ -n "$progress_execution_contract" ]] \
  || fail 'progress readiness omitted the computed execution-contract fingerprint'
grep -q "^BASE_COMMIT_SHA=$base_commit_sha$" <<<"$progress_readiness_output" \
  || fail 'progress readiness omitted the frozen Base commit SHA'
progress_checkpoint_relative="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$progress_readiness_output")"
progress_checkpoint_sha256="$(sed -nE \
  's/^PUBLICATION_CHECKPOINT_SHA256=([0-9a-f]{64})$/\1/p' \
  <<<"$progress_readiness_output")"
progress_publication_marker="$(sed -nE 's/^PUBLICATION_MARKER=(.+)$/\1/p' \
  <<<"$progress_readiness_output")"
[[ "$progress_checkpoint_relative" \
    == '.ai/gauntlets/fixture-gauntlet/publication-checkpoints/unit-1/checkpoint-001.md' \
  && -n "$progress_checkpoint_sha256" \
  && "$progress_publication_marker" \
    == "<!-- opencaw-gauntlet-publication:v1 checkpoint=$progress_checkpoint_relative checkpoint-sha256=$progress_checkpoint_sha256 -->" ]] \
  || fail 'progress readiness omitted its exact append-only publication checkpoint marker'
progress_checkpoint="$project/$progress_checkpoint_relative"
expect_file "$progress_checkpoint"
[[ "$progress_checkpoint_sha256" == "$(sha256_file "$progress_checkpoint")" ]] \
  || fail 'progress readiness emitted the wrong publication checkpoint hash'
expect_line '# Gauntlet Publication Checkpoint: unit-1 / 001' "$progress_checkpoint"
expect_line '- Item: unit-1' "$progress_checkpoint"
expect_line '- Sequence: 001' "$progress_checkpoint"
expect_line '- Head branch: gauntlet-work/fixture-gauntlet/unit-1' "$progress_checkpoint"
expect_line "- Head SHA: $head_sha_1" "$progress_checkpoint"
expect_line '- Target branch: gauntlet/fixture-gauntlet' "$progress_checkpoint"
expect_line "- Chain tip: $base_commit_sha" "$progress_checkpoint"
expect_line '- Remediation trigger: none' "$progress_checkpoint"
expect_line '- Remediation trigger sha256: none' "$progress_checkpoint"
expect_line '- Remediation root: none' "$progress_checkpoint"
expect_line '- Remediation root sha256: none' "$progress_checkpoint"
expect_line '- Quality bar approved at: 2026-08-01T12:00:00Z' "$progress_checkpoint"
expect_line '- Unit manifest approved at: 2026-08-01T12:00:00Z' "$progress_checkpoint"
expect_line '- Remote integration state: absent-create-only' "$progress_checkpoint"
expect_line '- Remote integration SHA: absent' "$progress_checkpoint"
expect_line '- Remote work state: absent-create-only' "$progress_checkpoint"
expect_line '- Remote work SHA: absent' "$progress_checkpoint"

prepare_checkpoint_fixture() {
  local fixture_name="$1"
  checkpoint_case_dir="$project/.ai/gauntlets/$fixture_name"
  checkpoint_case_head="gauntlet-work/$fixture_name/unit-1"
  checkpoint_case_url="https://github.com/example/opencaw-fixture/pull/$2"
  copy_gauntlet "$ready_snapshot" "$checkpoint_case_dir"
  set_local_ref "$project" "$checkpoint_case_head" "$head_sha_1"
  set_remote_ref "$project" "$checkpoint_case_head" absent
  checkpoint_case_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/$fixture_name" \
    run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
      "$fixture_name" unit-1 "$project/progress-validation.md")"
  checkpoint_case_relative="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
    <<<"$checkpoint_case_output")"
  checkpoint_case_hash="$(sed -nE \
    's/^PUBLICATION_CHECKPOINT_SHA256=([0-9a-f]{64})$/\1/p' \
    <<<"$checkpoint_case_output")"
  checkpoint_case_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_case_relative checkpoint-sha256=$checkpoint_case_hash -->"
  expect_file "$project/$checkpoint_case_relative"
}

prepare_checkpoint_fixture remediation-trigger-path-escape 303
printf 'project-boundary sentinel\n' >"$temp_root/outside-remediation-trigger.md"
remediation_escape_checkpoint="$project/$checkpoint_case_relative"
remediation_escape_hash="$(sha256_file "$temp_root/outside-remediation-trigger.md")"
replace_line "$remediation_escape_checkpoint" \
  '- Remediation trigger: none' \
  '- Remediation trigger: ../outside-remediation-trigger.md'
replace_line "$remediation_escape_checkpoint" \
  '- Remediation trigger sha256: none' \
  "- Remediation trigger sha256: $remediation_escape_hash"
expect_failure "$temp_root/remediation-trigger-path-escape.log" run_for "$project" \
  bash commands/validate-gauntlet.sh remediation-trigger-path-escape --phase ready
grep -Fq \
  'Remediation trigger is not canonical immutable evidence for remediation-trigger-path-escape' \
  "$temp_root/remediation-trigger-path-escape.log" \
  || fail 'checkpoint validation did not reject remediation traversal before hashing its target'

baseline_quality_control_dir="$project/.ai/gauntlets/baseline-quality-checkpoint-control"
copy_gauntlet "$ready_snapshot" "$baseline_quality_control_dir"
baseline_quality_head='gauntlet-work/baseline-quality-checkpoint-control/unit-1'
baseline_quality_url='https://github.com/example/opencaw-fixture/pull/302'
export FAKE_DATE_ISO='2026-08-01T12:00:02Z'
set_local_ref "$project" "$baseline_quality_head" "$head_sha_1"
set_remote_ref "$project" "$baseline_quality_head" absent
baseline_quality_readiness="$(run_for "$project" bash commands/pr-readiness-check.sh \
  --gauntlet-progress baseline-quality-checkpoint-control unit-1 \
  "$project/progress-validation.md")"
baseline_quality_checkpoint_relative="$(sed -nE \
  's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' <<<"$baseline_quality_readiness")"
expect_file "$project/$baseline_quality_checkpoint_relative"
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  baseline-quality-checkpoint-control unit-1 opened "$baseline_quality_url" \
  "$baseline_quality_head" none --head-sha "$head_sha_1" >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh \
  baseline-quality-checkpoint-control --phase ready >/dev/null
baseline_quality_marker="$(opened_publication_marker \
  "$project" baseline-quality-checkpoint-control unit-1)"
OPENCAW_TEST_RAW_PR_BODY=1 set_pr_observation \
  "$baseline_quality_url" "$baseline_quality_head" "$head_sha_1" \
  gauntlet/baseline-quality-checkpoint-control OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture \
  2026-08-01T12:00:02Z none "$baseline_quality_marker"
expect_failure "$temp_root/live-open-issue-link-removed.log" run_for "$project" \
  bash commands/validate-gauntlet.sh baseline-quality-checkpoint-control --phase ready
grep -Fq 'Progress PR body requires this exact canonical first line exactly once: Refs #101' \
  "$temp_root/live-open-issue-link-removed.log" \
  || fail 'ready validation accepted mutable live progress-PR body drift'
set_pr_observation "$baseline_quality_url" "$baseline_quality_head" "$head_sha_1" \
  gauntlet/baseline-quality-checkpoint-control OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture \
  2026-08-01T12:00:02Z none "$baseline_quality_marker"

toctou_report="$temp_root/live-round-body-toctou-critic.md"
write_critic_report "$toctou_report" fail artifact.txt "$head_sha_1" \
  'The fixture still needs one measurable correction.' \
  'Change the artifact implementation before the next isolated review.'
export FAKE_GH_MUTATE_BODY_URL="$baseline_quality_url"
export FAKE_GH_MUTATE_BODY_TRIGGER="$temp_root/live-round-body-toctou.trigger"
FAKE_GH_MUTATE_BODY_BASE64="$(printf '%s' "$baseline_quality_marker" \
  | base64 | tr -d '\r\n')"
export FAKE_GH_MUTATE_BODY_BASE64
expect_failure "$temp_root/live-round-body-toctou.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh baseline-quality-checkpoint-control \
  unit-1 fail fixture-builder-live-body fixture-critic-live-body native-subagent \
  "$toctou_report" --head-sha "$head_sha_1" \
  --builder-strategy 'Verify that the second live observation retains publication evidence.'
grep -Fq 'Progress PR body requires this exact canonical first line exactly once: Refs #101' \
  "$temp_root/live-round-body-toctou.log" \
  || fail 'round recording accepted body drift between ready validation and critic binding'
unset FAKE_GH_MUTATE_BODY_URL FAKE_GH_MUTATE_BODY_TRIGGER \
  FAKE_GH_MUTATE_BODY_BASE64
set_pr_observation "$baseline_quality_url" "$baseline_quality_head" "$head_sha_1" \
  gauntlet/baseline-quality-checkpoint-control OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture \
  2026-08-01T12:00:02Z none "$baseline_quality_marker"
unset FAKE_DATE_ISO

future_baseline_quality_dir="$project/.ai/gauntlets/future-baseline-quality-checkpoint"
copy_gauntlet "$baseline_quality_control_dir" "$future_baseline_quality_dir"
future_baseline_quality_approval='2026-08-01T12:00:03Z'
future_baseline_quality_event_time='2026-08-01T12:00:04Z'
future_baseline_quality_old_fingerprint="$(gauntlet_helper_value "$project" \
  gauntlet_quality_bar_fingerprint "$future_baseline_quality_dir/GAUNTLET.md")"
replace_line "$future_baseline_quality_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:00Z' \
  "- Approved at: $future_baseline_quality_approval"
future_baseline_quality_new_fingerprint="$(gauntlet_helper_value "$project" \
  gauntlet_quality_bar_fingerprint "$future_baseline_quality_dir/GAUNTLET.md")"
while IFS= read -r future_baseline_quality_file; do
  replace_all_literal "$future_baseline_quality_file" \
    "$future_baseline_quality_old_fingerprint" \
    "$future_baseline_quality_new_fingerprint"
done < <(find "$future_baseline_quality_dir" -type f -name '*.md' \
  -print 2>/dev/null | LC_ALL=C sort)
future_baseline_quality_event="$future_baseline_quality_dir/pr-events/unit-1/event-001.md"
future_baseline_quality_checkpoint_relative="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$future_baseline_quality_event" 'PR Event Metadata' \
  'Publication checkpoint')"
future_baseline_quality_checkpoint="$project/$future_baseline_quality_checkpoint_relative"
replace_matching_line "$future_baseline_quality_checkpoint" \
  '^- Quality bar approved at:' \
  "- Quality bar approved at: $future_baseline_quality_approval"
refresh_copied_checkpoint_hashes "$future_baseline_quality_dir"
replace_matching_line "$future_baseline_quality_event" '^- Created at:' \
  "- Created at: $future_baseline_quality_event_time"
replace_matching_line "$future_baseline_quality_event" '^- Recorded at:' \
  "- Recorded at: $future_baseline_quality_event_time"
future_baseline_quality_ledger="$(select_ledger_line "$project" \
  "$future_baseline_quality_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/future-baseline-quality-checkpoint/pr-events/unit-1/event-001.md')"
replace_line "$future_baseline_quality_dir/GAUNTLET.md" \
  "$future_baseline_quality_ledger" \
  "${future_baseline_quality_ledger//pr-created: 2026-08-01T12:00:02Z/pr-created: $future_baseline_quality_event_time}"
refresh_copied_evidence_hashes "$future_baseline_quality_dir"
future_baseline_quality_head='gauntlet-work/future-baseline-quality-checkpoint/unit-1'
future_baseline_quality_marker="$(opened_publication_marker \
  "$project" future-baseline-quality-checkpoint unit-1)"
set_local_ref "$project" "$future_baseline_quality_head" "$head_sha_1"
set_remote_ref "$project" "$future_baseline_quality_head" "$head_sha_1"
set_pr_observation "$baseline_quality_url" "$future_baseline_quality_head" "$head_sha_1" \
  gauntlet/future-baseline-quality-checkpoint OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture \
  "$future_baseline_quality_event_time" none "$future_baseline_quality_marker"
expect_line '- Recorded at: 2026-08-01T12:00:02Z' \
  "$future_baseline_quality_checkpoint"
expect_line "- Quality bar approved at: $future_baseline_quality_approval" \
  "$future_baseline_quality_checkpoint"
expect_failure "$temp_root/future-baseline-quality-checkpoint.log" run_for "$project" \
  bash commands/validate-gauntlet.sh future-baseline-quality-checkpoint --phase ready
grep -Fq 'Publication checkpoint uses a quality generation not active at its Recorded at timestamp' \
  "$temp_root/future-baseline-quality-checkpoint.log" \
  || fail 'future baseline quality checkpoint did not reach the generation-authorization gate'

backdated_baseline_quality_dir="$project/.ai/gauntlets/backdated-baseline-quality-checkpoint"
copy_gauntlet "$baseline_quality_control_dir" "$backdated_baseline_quality_dir"
backdated_baseline_quality_approval='2026-08-01T12:00:01Z'
backdated_baseline_quality_event_time='2026-08-01T12:00:04Z'
replace_line "$backdated_baseline_quality_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:00Z' \
  "- Approved at: $backdated_baseline_quality_approval"
backdated_baseline_quality_event="$backdated_baseline_quality_dir/pr-events/unit-1/event-001.md"
backdated_baseline_quality_checkpoint_relative="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$backdated_baseline_quality_event" 'PR Event Metadata' \
  'Publication checkpoint')"
backdated_baseline_quality_checkpoint="$project/$backdated_baseline_quality_checkpoint_relative"
replace_matching_line "$backdated_baseline_quality_event" '^- Created at:' \
  "- Created at: $backdated_baseline_quality_event_time"
replace_matching_line "$backdated_baseline_quality_event" '^- Recorded at:' \
  "- Recorded at: $backdated_baseline_quality_event_time"
backdated_baseline_quality_ledger="$(select_ledger_line "$project" \
  "$backdated_baseline_quality_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/backdated-baseline-quality-checkpoint/pr-events/unit-1/event-001.md')"
replace_line "$backdated_baseline_quality_dir/GAUNTLET.md" \
  "$backdated_baseline_quality_ledger" \
  "${backdated_baseline_quality_ledger//pr-created: 2026-08-01T12:00:02Z/pr-created: $backdated_baseline_quality_event_time}"
refresh_copied_evidence_hashes "$backdated_baseline_quality_dir"
backdated_baseline_quality_head='gauntlet-work/backdated-baseline-quality-checkpoint/unit-1'
backdated_baseline_quality_marker="$(opened_publication_marker \
  "$project" backdated-baseline-quality-checkpoint unit-1)"
set_local_ref "$project" "$backdated_baseline_quality_head" "$head_sha_1"
set_remote_ref "$project" "$backdated_baseline_quality_head" "$head_sha_1"
set_pr_observation "$baseline_quality_url" "$backdated_baseline_quality_head" "$head_sha_1" \
  gauntlet/backdated-baseline-quality-checkpoint OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture \
  "$backdated_baseline_quality_event_time" none "$backdated_baseline_quality_marker"
expect_line '- Quality bar approved at: 2026-08-01T12:00:00Z' \
  "$backdated_baseline_quality_checkpoint"
expect_line "- Approved at: $backdated_baseline_quality_approval" \
  "$backdated_baseline_quality_dir/GAUNTLET.md"
expect_failure "$temp_root/backdated-baseline-quality-checkpoint.log" \
  run_for "$project" bash commands/validate-gauntlet.sh \
  backdated-baseline-quality-checkpoint --phase ready
grep -Fq 'Publication checkpoint uses a quality generation not active at its Recorded at timestamp' \
  "$temp_root/backdated-baseline-quality-checkpoint.log" \
  || fail 'backdated baseline quality checkpoint did not reach the generation-authorization gate'

prepare_checkpoint_fixture checkpoint-objective-drift 270
replace_line "$checkpoint_case_dir/GAUNTLET.md" \
  'Produce an inspectable local artifact that satisfies the approved fixture benchmark.' \
  'Produce an unapproved objective changed after the publication checkpoint.'
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-objective-drift OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none "$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-objective-drift.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-objective-drift unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-quality-drift 271
replace_line "$checkpoint_case_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Quality changed after the publication checkpoint.'
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-quality-drift OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none "$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-quality-drift.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-quality-drift unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-scope-drift 272
replace_line "$checkpoint_case_dir/GAUNTLET.md" \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier' \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and a changed verifier boundary'
checkpoint_scope_manifest="$(unit_manifest_fingerprint \
  "$project" "$checkpoint_case_dir/GAUNTLET.md")"
replace_matching_line "$checkpoint_case_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' \
  "- Unit manifest approval: $checkpoint_scope_manifest | units: unit-1 | approved by: fixture-user | approved at: 2026-08-01T12:00:00Z"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-scope-drift OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none "$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-scope-drift.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-scope-drift unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-manifest-drift 273
insert_after_matching_line "$checkpoint_case_dir/GAUNTLET.md" \
  '^- \[ \] unit-1 \| status: pending' \
  '- [ ] unit-2 | status: pending | title: Added after checkpoint | scope: second inspectable artifact boundary'
checkpoint_added_manifest="$(unit_manifest_fingerprint \
  "$project" "$checkpoint_case_dir/GAUNTLET.md")"
replace_matching_line "$checkpoint_case_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' \
  "- Unit manifest approval: $checkpoint_added_manifest | units: unit-1,unit-2 | approved by: fixture-user | approved at: 2026-08-01T12:00:00Z"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-manifest-drift OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none "$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-manifest-drift.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-manifest-drift unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-missing-marker 274
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-missing-marker OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none ''
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-missing-marker.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-missing-marker unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-missing-issue-reference 305
OPENCAW_TEST_RAW_PR_BODY=1 set_pr_observation \
  "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-missing-issue-reference OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-missing-issue-reference.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-missing-issue-reference \
    unit-1 opened "$checkpoint_case_url" "$checkpoint_case_head" none \
    --head-sha "$head_sha_1"
grep -Fq 'Progress PR body requires this exact canonical first line exactly once: Refs #101' \
  "$temp_root/checkpoint-missing-issue-reference.log" \
  || fail 'progress event accepted a PR body without its parent-issue reference'

prepare_checkpoint_fixture checkpoint-forbidden-closing-link 306
checkpoint_forbidden_closing_body="Refs #101
Closes: example/opencaw-fixture#101

$checkpoint_case_marker"
OPENCAW_TEST_RAW_PR_BODY=1 set_pr_observation \
  "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-forbidden-closing-link OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_forbidden_closing_body"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-forbidden-closing-link.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-forbidden-closing-link \
    unit-1 opened "$checkpoint_case_url" "$checkpoint_case_head" none \
    --head-sha "$head_sha_1"
grep -Fq 'Progress PR body must not close the parent issue; reserve Closes #101 for promotion.' \
  "$temp_root/checkpoint-forbidden-closing-link.log" \
  || fail 'progress event accepted a parent-issue closing keyword'

prepare_checkpoint_fixture checkpoint-wrong-marker 275
checkpoint_wrong_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_case_relative checkpoint-sha256=0000000000000000000000000000000000000000000000000000000000000000 -->"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-wrong-marker OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none "$checkpoint_wrong_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-wrong-marker.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-wrong-marker unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-duplicate-marker 276
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-duplicate-marker OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_case_marker
$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-duplicate-marker.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-duplicate-marker unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-late 277
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-late OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T11:59:59Z none "$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-late.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-late unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-unrelated-head 280
replace_line "$project/$checkpoint_case_relative" "- Head SHA: $head_sha_1" \
  "- Head SHA: $orphan_sha"
checkpoint_unrelated_hash="$(sha256_file "$project/$checkpoint_case_relative")"
checkpoint_unrelated_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_case_relative checkpoint-sha256=$checkpoint_unrelated_hash -->"
set_local_ref "$project" "$checkpoint_case_head" "$orphan_sha"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$orphan_sha" \
  gauntlet/checkpoint-unrelated-head OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_unrelated_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-unrelated-head.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-unrelated-head unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$orphan_sha"

prepare_checkpoint_fixture checkpoint-forged-integration-ref 281
replace_line "$project/$checkpoint_case_relative" \
  "- Remote integration SHA: $base_commit_sha" \
  "- Remote integration SHA: $head_sha_1"
checkpoint_forged_integration_hash="$(sha256_file "$project/$checkpoint_case_relative")"
checkpoint_forged_integration_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_case_relative checkpoint-sha256=$checkpoint_forged_integration_hash -->"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-forged-integration-ref OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_forged_integration_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-forged-integration-ref.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-forged-integration-ref unit-1 \
    opened "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-forged-work-ref 282
replace_line "$project/$checkpoint_case_relative" '- Remote work state: absent-create-only' \
  '- Remote work state: exact'
replace_line "$project/$checkpoint_case_relative" '- Remote work SHA: absent' \
  "- Remote work SHA: $head_sha_2"
checkpoint_forged_work_hash="$(sha256_file "$project/$checkpoint_case_relative")"
checkpoint_forged_work_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_case_relative checkpoint-sha256=$checkpoint_forged_work_hash -->"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-forged-work-ref OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_forged_work_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-forged-work-ref.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-forged-work-ref unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

checkpoint_cas_dir="$project/.ai/gauntlets/checkpoint-cas"
copy_gauntlet "$ready_snapshot" "$checkpoint_cas_dir"
set_local_ref "$project" gauntlet-work/checkpoint-cas/unit-1 "$head_sha_1"
set_remote_ref "$project" gauntlet-work/checkpoint-cas/unit-1 absent
checkpoint_cas_ready="$temp_root/checkpoint-cas-ready"
checkpoint_cas_release="$temp_root/checkpoint-cas-release"
checkpoint_cas_output="$temp_root/checkpoint-cas-output.log"
set +e
FAKE_GIT_PAUSE_READY="$checkpoint_cas_ready" \
  FAKE_GIT_PAUSE_RELEASE="$checkpoint_cas_release" \
  OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/checkpoint-cas" \
  bash commands/pr-readiness-check.sh --gauntlet-progress checkpoint-cas unit-1 \
    "$project/progress-validation.md" >"$checkpoint_cas_output" 2>&1 &
checkpoint_cas_pid=$!
set -e
wait_for_path "$checkpoint_cas_ready"
replace_line "$checkpoint_cas_dir/GAUNTLET.md" \
  'Produce an inspectable local artifact that satisfies the approved fixture benchmark.' \
  'Produce a concurrently mutated artifact objective during remote observation.'
: >"$checkpoint_cas_release"
set +e
wait "$checkpoint_cas_pid"
checkpoint_cas_result=$?
set -e
[[ $checkpoint_cas_result -ne 0 ]] || fail 'publication readiness ignored concurrent GAUNTLET.md mutation'
[[ "$(find "$checkpoint_cas_dir/publication-checkpoints" -type f -name 'checkpoint-*.md' \
  | wc -l | tr -d ' ')" == 0 ]] \
  || fail 'publication readiness CAS failure installed an orphan checkpoint'

checkpoint_symlink_root_dir="$project/.ai/gauntlets/checkpoint-symlink-root"
copy_gauntlet "$ready_snapshot" "$checkpoint_symlink_root_dir"
mkdir -p "$temp_root/outside-publication-checkpoints"
rmdir "$checkpoint_symlink_root_dir/publication-checkpoints"
ln -s "$temp_root/outside-publication-checkpoints" \
  "$checkpoint_symlink_root_dir/publication-checkpoints"
set_local_ref "$project" gauntlet-work/checkpoint-symlink-root/unit-1 "$head_sha_1"
expect_failure "$temp_root/checkpoint-symlink-root.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress checkpoint-symlink-root unit-1 \
  "$project/progress-validation.md"

checkpoint_symlink_item_dir="$project/.ai/gauntlets/checkpoint-symlink-item"
copy_gauntlet "$ready_snapshot" "$checkpoint_symlink_item_dir"
mkdir -p "$temp_root/outside-publication-checkpoint-item"
ln -s "$temp_root/outside-publication-checkpoint-item" \
  "$checkpoint_symlink_item_dir/publication-checkpoints/unit-1"
set_local_ref "$project" gauntlet-work/checkpoint-symlink-item/unit-1 "$head_sha_1"
expect_failure "$temp_root/checkpoint-symlink-item.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress checkpoint-symlink-item unit-1 \
  "$project/progress-validation.md"

prepare_checkpoint_fixture checkpoint-malformed-time 283
replace_line "$project/$checkpoint_case_relative" \
  '- Recorded at: 2026-08-01T12:00:00Z' '- Recorded at: not-a-canonical-time'
checkpoint_malformed_time_hash="$(sha256_file "$project/$checkpoint_case_relative")"
checkpoint_malformed_time_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_case_relative checkpoint-sha256=$checkpoint_malformed_time_hash -->"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-malformed-time OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_malformed_time_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-malformed-time.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-malformed-time unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-sequence-gap 284
checkpoint_gap_original="$project/$checkpoint_case_relative"
checkpoint_gap_relative='.ai/gauntlets/checkpoint-sequence-gap/publication-checkpoints/unit-1/checkpoint-003.md'
mv "$checkpoint_gap_original" "$project/$checkpoint_gap_relative"
replace_line "$project/$checkpoint_gap_relative" \
  '# Gauntlet Publication Checkpoint: unit-1 / 001' \
  '# Gauntlet Publication Checkpoint: unit-1 / 003'
replace_line "$project/$checkpoint_gap_relative" '- Sequence: 001' '- Sequence: 003'
checkpoint_gap_hash="$(sha256_file "$project/$checkpoint_gap_relative")"
checkpoint_gap_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_gap_relative checkpoint-sha256=$checkpoint_gap_hash -->"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-sequence-gap OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none "$checkpoint_gap_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-sequence-gap.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-sequence-gap unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

prepare_checkpoint_fixture checkpoint-noncanonical-extra 285
cp "$project/$checkpoint_case_relative" \
  "$checkpoint_case_dir/publication-checkpoints/unit-1/checkpoint-extra.md"
set_pr_observation "$checkpoint_case_url" "$checkpoint_case_head" "$head_sha_1" \
  gauntlet/checkpoint-noncanonical-extra OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_case_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-noncanonical-extra.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-noncanonical-extra unit-1 opened \
    "$checkpoint_case_url" "$checkpoint_case_head" none --head-sha "$head_sha_1"

checkpoint_stale_dir="$project/.ai/gauntlets/checkpoint-stale-replay"
copy_gauntlet "$ready_snapshot" "$checkpoint_stale_dir"
checkpoint_stale_head='gauntlet-work/checkpoint-stale-replay/unit-1'
set_local_ref "$project" "$checkpoint_stale_head" "$head_sha_1"
set_remote_ref "$project" "$checkpoint_stale_head" absent
checkpoint_stale_output_1="$(OPENCAW_REPORT_DIR="$project/.ai/reports/checkpoint-stale-1" \
  run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  checkpoint-stale-replay unit-1 "$project/progress-validation.md")"
checkpoint_stale_relative_1="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$checkpoint_stale_output_1")"
checkpoint_stale_hash_1="$(sha256_file "$project/$checkpoint_stale_relative_1")"
checkpoint_stale_marker_1="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_stale_relative_1 checkpoint-sha256=$checkpoint_stale_hash_1 -->"
set_local_ref "$project" "$checkpoint_stale_head" "$head_sha_2"
checkpoint_stale_output_2="$(OPENCAW_REPORT_DIR="$project/.ai/reports/checkpoint-stale-2" \
  run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  checkpoint-stale-replay unit-1 "$project/progress-validation.md")"
checkpoint_stale_relative_2="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$checkpoint_stale_output_2")"
[[ "$checkpoint_stale_relative_1" == *'/checkpoint-001.md' \
  && "$checkpoint_stale_relative_2" == *'/checkpoint-002.md' ]] \
  || fail 'successive changed-head checkpoints were not issued contiguously'
set_local_ref "$project" "$checkpoint_stale_head" "$head_sha_1"
set_remote_ref "$project" "$checkpoint_stale_head" "$head_sha_1"
checkpoint_stale_url='https://github.com/example/opencaw-fixture/pull/286'
set_pr_observation "$checkpoint_stale_url" "$checkpoint_stale_head" "$head_sha_1" \
  gauntlet/checkpoint-stale-replay OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_stale_marker_1"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  OPENCAW_TEST_SKIP_REMOTE_PUBLICATION=1 \
  expect_failure "$temp_root/checkpoint-stale-replay.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-stale-replay unit-1 opened \
    "$checkpoint_stale_url" "$checkpoint_stale_head" none --head-sha "$head_sha_1"
set_local_ref "$project" "$checkpoint_stale_head" "$head_sha_3"
set_remote_ref "$project" "$checkpoint_stale_head" absent
checkpoint_stale_output_3="$(OPENCAW_REPORT_DIR="$project/.ai/reports/checkpoint-stale-3" \
  run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  checkpoint-stale-replay unit-1 "$project/progress-validation.md")"
checkpoint_stale_relative_3="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$checkpoint_stale_output_3")"
[[ "$checkpoint_stale_relative_3" == *'/checkpoint-003.md' \
  && -f "$project/$checkpoint_stale_relative_2" ]] \
  || fail 'aborted newest checkpoint was not retained before contiguous next issuance'

checkpoint_parallel_dir="$project/.ai/gauntlets/checkpoint-parallel"
copy_gauntlet "$ready_snapshot" "$checkpoint_parallel_dir"
set_local_ref "$project" gauntlet-work/checkpoint-parallel/unit-1 "$head_sha_1"
set_remote_ref "$project" gauntlet-work/checkpoint-parallel/unit-1 absent
checkpoint_parallel_output_1="$temp_root/checkpoint-parallel-1.log"
checkpoint_parallel_output_2="$temp_root/checkpoint-parallel-2.log"
checkpoint_parallel_pause_ready="$temp_root/checkpoint-parallel-pause-ready"
checkpoint_parallel_pause_release="$temp_root/checkpoint-parallel-pause-release"
OPENCAW_PROJECT_ROOT="$project" \
  OPENCAW_REPORT_DIR="$project/.ai/reports/checkpoint-parallel-1" \
  FAKE_GIT_PAUSE_READY="$checkpoint_parallel_pause_ready" \
  FAKE_GIT_PAUSE_RELEASE="$checkpoint_parallel_pause_release" \
  bash commands/pr-readiness-check.sh --gauntlet-progress checkpoint-parallel unit-1 \
    "$project/progress-validation.md" >"$checkpoint_parallel_output_1" 2>&1 &
checkpoint_parallel_pid_1=$!
wait_for_path "$checkpoint_parallel_pause_ready"
set +e
OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/checkpoint-parallel-2" \
  bash commands/pr-readiness-check.sh --gauntlet-progress checkpoint-parallel unit-1 \
    "$project/progress-validation.md" >"$checkpoint_parallel_output_2" 2>&1
checkpoint_parallel_status_2=$?
set -e
: >"$checkpoint_parallel_pause_release"
wait "$checkpoint_parallel_pid_1"
[[ "$checkpoint_parallel_status_2" -ne 0 \
  && "$(find "$checkpoint_parallel_dir/publication-checkpoints/unit-1" -maxdepth 1 \
    -type f -name 'checkpoint-*.md' | wc -l | tr -d ' ')" == 1 \
  && ! -e "$checkpoint_parallel_dir/.opencaw-gauntlet.lock" ]] \
  || fail 'parallel readiness did not fail fast without residue while one writer held the lock'
grep -Fq 'Gauntlet is locked' "$checkpoint_parallel_output_2" \
  || fail 'parallel readiness loser did not report the durable lock blocker'
checkpoint_parallel_relative_1="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  "$checkpoint_parallel_output_1")"
OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/checkpoint-parallel-retry" \
  bash commands/pr-readiness-check.sh --gauntlet-progress checkpoint-parallel unit-1 \
    "$project/progress-validation.md" >"$checkpoint_parallel_output_2" 2>&1
checkpoint_parallel_relative_2="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  "$checkpoint_parallel_output_2")"
[[ -n "$checkpoint_parallel_relative_1" && -n "$checkpoint_parallel_relative_2" \
  && "$checkpoint_parallel_relative_1" != "$checkpoint_parallel_relative_2" \
  && "$checkpoint_parallel_relative_1" == *'/checkpoint-001.md' \
  && "$checkpoint_parallel_relative_2" == *'/checkpoint-002.md' \
  && "$(find "$checkpoint_parallel_dir/publication-checkpoints/unit-1" -maxdepth 1 \
    -type f -name 'checkpoint-*.md' | wc -l | tr -d ' ')" == 2 ]] \
  || fail 'explicit readiness retry did not append a contiguous second checkpoint'
checkpoint_parallel_hash_1="$(sha256_file "$project/$checkpoint_parallel_relative_1")"
checkpoint_parallel_marker_1="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_parallel_relative_1 checkpoint-sha256=$checkpoint_parallel_hash_1 -->"
checkpoint_parallel_hash_2="$(sha256_file "$project/$checkpoint_parallel_relative_2")"
checkpoint_parallel_marker_2="<!-- opencaw-gauntlet-publication:v1 checkpoint=$checkpoint_parallel_relative_2 checkpoint-sha256=$checkpoint_parallel_hash_2 -->"
checkpoint_parallel_url='https://github.com/example/opencaw-fixture/pull/278'
set_pr_observation "$checkpoint_parallel_url" gauntlet-work/checkpoint-parallel/unit-1 \
  "$head_sha_1" gauntlet/checkpoint-parallel OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_parallel_marker_1"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-parallel-stale-first.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-parallel unit-1 \
    opened "$checkpoint_parallel_url" gauntlet-work/checkpoint-parallel/unit-1 none \
    --head-sha "$head_sha_1"
[[ "$(pr_event_file_count "$checkpoint_parallel_dir")" == 0 ]] \
  || fail 'stale checkpoint-001 rejection created immutable PR evidence'
set_pr_observation "$checkpoint_parallel_url" gauntlet-work/checkpoint-parallel/unit-1 \
  "$head_sha_1" gauntlet/checkpoint-parallel OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_parallel_marker_2"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh checkpoint-parallel unit-1 \
    opened "$checkpoint_parallel_url" gauntlet-work/checkpoint-parallel/unit-1 none \
    --head-sha "$head_sha_1" >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh checkpoint-parallel \
  --phase ready >/dev/null
[[ "$(find "$checkpoint_parallel_dir/publication-checkpoints/unit-1" -maxdepth 1 \
  -type f -name 'checkpoint-*.md' | wc -l | tr -d ' ')" == 2 ]] \
  || fail 'validation removed the harmless unused publication checkpoint'
set_pr_observation 'https://github.com/example/opencaw-fixture/pull/279' \
  gauntlet-work/checkpoint-parallel/unit-1 "$head_sha_1" \
  gauntlet/checkpoint-parallel OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$checkpoint_parallel_marker_2"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  expect_failure "$temp_root/checkpoint-reused.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh checkpoint-parallel unit-1 opened \
    'https://github.com/example/opencaw-fixture/pull/279' \
    gauntlet-work/checkpoint-parallel/unit-1 none --head-sha "$head_sha_1"
expect_failure "$temp_root/progress-readiness-unknown-unit.log" env \
  OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/unknown-progress" \
  bash commands/pr-readiness-check.sh --gauntlet-progress \
  fixture-gauntlet absent-unit "$project/progress-validation.md"

fixture_pr_url='https://github.com/example/opencaw-fixture/pull/201'
fixture_head='gauntlet-work/fixture-gauntlet/unit-1'
gauntlet_before_pr_dry_run="$(git hash-object "$gauntlet_file")"
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  "$fixture_pr_url" "$fixture_head" none --head-sha "$head_sha_1" --dry-run >"$temp_root/pr-event-dry-run.log"
[[ "$(pr_event_file_count "$gauntlet_dir")" == 0 ]] || fail 'PR-event dry-run created immutable evidence'
[[ "$gauntlet_before_pr_dry_run" == "$(git hash-object "$gauntlet_file")" ]] \
  || fail 'PR-event dry-run changed GAUNTLET.md'

expect_failure "$temp_root/pr-event-missing-head-sha.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  "$fixture_pr_url" "$fixture_head" none
expect_failure "$temp_root/pr-event-malformed-head-sha.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  "$fixture_pr_url" "$fixture_head" none --head-sha deadbeef

nonexistent_sha='0000000000000000000000000000000000000000'
nonexistent_sha_dir="$project/.ai/gauntlets/nonexistent-sha"
copy_gauntlet "$ready_snapshot" "$nonexistent_sha_dir"
expect_failure "$temp_root/pr-event-nonexistent-sha.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh nonexistent-sha unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/212' \
  'gauntlet-work/nonexistent-sha/unit-1' none --head-sha "$nonexistent_sha"
[[ "$(pr_event_file_count "$nonexistent_sha_dir")" == 0 ]] \
  || fail 'a nonexistent commit object produced progress-PR evidence'

origin_binding_dir="$project/.ai/gauntlets/origin-binding"
copy_gauntlet "$ready_snapshot" "$origin_binding_dir"
git -C "$project" remote remove origin
expect_failure "$temp_root/pr-event-missing-origin.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh origin-binding unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/223' \
  gauntlet-work/origin-binding/unit-1 none --head-sha "$head_sha_1"
git -C "$project" remote add origin https://github.com/different/repository.git
expect_failure "$temp_root/pr-event-wrong-origin.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh origin-binding unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/223' \
  gauntlet-work/origin-binding/unit-1 none --head-sha "$head_sha_1"
git -C "$project" remote set-url origin \
  http://github.com/example/opencaw-fixture.git
expect_failure "$temp_root/pr-event-plaintext-http-origin.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh origin-binding unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/223' \
  gauntlet-work/origin-binding/unit-1 none --head-sha "$head_sha_1"
grep -Fq 'Local Git origin does not match the parent task GitHub repository' \
  "$temp_root/pr-event-plaintext-http-origin.log" \
  || fail 'plaintext HTTP origin was not rejected at the repository trust boundary'
git -C "$project" remote set-url origin git@github.com:example/opencaw-fixture.git
[[ "$(pr_event_file_count "$origin_binding_dir")" == 0 ]] \
  || fail 'a missing, mismatched, or plaintext origin produced progress-PR evidence'

push_target_dir="$project/.ai/gauntlets/push-target-binding"
copy_gauntlet "$ready_snapshot" "$push_target_dir"
push_target_head='gauntlet-work/push-target-binding/unit-1'
push_target_url='https://github.com/example/opencaw-fixture/pull/226'
set_local_ref "$project" "$push_target_head" "$head_sha_1"
git -C "$project" remote set-url --add --push origin \
  https://github.com/different/repository.git
push_target_gauntlet_hash="$(git hash-object "$push_target_dir/GAUNTLET.md")"
expect_failure "$temp_root/progress-readiness-wrong-push-target.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress \
  push-target-binding unit-1 "$project/progress-validation.md"
expect_failure "$temp_root/progress-record-wrong-push-target.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh push-target-binding unit-1 opened \
  "$push_target_url" "$push_target_head" none --head-sha "$head_sha_1"
[[ "$push_target_gauntlet_hash" == "$(git hash-object "$push_target_dir/GAUNTLET.md")" \
  && "$(pr_event_file_count "$push_target_dir")" == 0 ]] \
  || fail 'mismatched effective push target mutated progress evidence'
git -C "$project" config --unset-all remote.origin.pushurl
git -C "$project" remote set-url --add --push origin \
  http://github.com/example/opencaw-fixture.git
expect_failure "$temp_root/progress-readiness-plaintext-http-push-target.log" \
  run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  push-target-binding unit-1 "$project/progress-validation.md"
grep -Fq 'Git origin push URL does not match the parent task GitHub repository' \
  "$temp_root/progress-readiness-plaintext-http-push-target.log" \
  || fail 'plaintext HTTP push URL was not rejected at the repository trust boundary'
git -C "$project" config --unset-all remote.origin.pushurl
git -C "$project" remote set-url --add --push origin \
  git@github.com:example/opencaw-fixture.git
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  push-target-binding unit-1 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh push-target-binding unit-1 opened \
  "$push_target_url" "$push_target_head" none --head-sha "$head_sha_1" >/dev/null
expect_file "$push_target_dir/pr-events/unit-1/event-001.md"
git -C "$project" config --unset-all remote.origin.pushurl

stale_ref_dir="$project/.ai/gauntlets/stale-local-ref"
copy_gauntlet "$ready_snapshot" "$stale_ref_dir"
set_local_ref "$project" gauntlet/stale-local-ref "$head_sha_1"
set_local_ref "$project" gauntlet-work/stale-local-ref/unit-1 "$head_sha_1"
set_pr_observation 'https://github.com/example/opencaw-fixture/pull/213' \
  gauntlet-work/stale-local-ref/unit-1 "$head_sha_2" gauntlet/stale-local-ref \
  OPEN false none none none
expect_failure "$temp_root/pr-event-stale-local-ref.log" env OPENCAW_TEST_SKIP_OBSERVATION=1 \
  OPENCAW_PROJECT_ROOT="$project" bash commands/record-gauntlet-pr-event.sh \
  stale-local-ref unit-1 opened 'https://github.com/example/opencaw-fixture/pull/213' \
  gauntlet-work/stale-local-ref/unit-1 none --head-sha "$head_sha_2"
[[ "$(pr_event_file_count "$stale_ref_dir")" == 0 ]] \
  || fail 'a stale local progress ref produced progress-PR evidence'

first_target_drift_dir="$project/.ai/gauntlets/first-target-drift"
copy_gauntlet "$ready_snapshot" "$first_target_drift_dir"
first_target_url='https://github.com/example/opencaw-fixture/pull/227'
first_target_head='gauntlet-work/first-target-drift/unit-1'
set_local_ref "$project" "$first_target_head" "$head_sha_1"
set_local_ref "$project" gauntlet/first-target-drift "$base_commit_sha"
set_pr_observation "$first_target_url" "$first_target_head" "$head_sha_1" \
  gauntlet/first-target-drift OPEN false none none none none "$base_commit_sha" \
  true example/opencaw-fixture
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/first-open-cross-repository.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh first-target-drift unit-1 opened \
  "$first_target_url" "$first_target_head" none --head-sha "$head_sha_1"
set_pr_observation "$first_target_url" "$first_target_head" "$head_sha_1" \
  gauntlet/first-target-drift OPEN false none none none none "$base_commit_sha" \
  false different/repository
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/first-open-head-repository-mismatch.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh first-target-drift unit-1 opened \
  "$first_target_url" "$first_target_head" none --head-sha "$head_sha_1"
set_pr_observation "$first_target_url" "$first_target_head" "$head_sha_1" \
  gauntlet/first-target-drift OPEN false none none none none "$orphan_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/first-open-unrelated-live-target.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh first-target-drift unit-1 opened \
  "$first_target_url" "$first_target_head" none --head-sha "$head_sha_1"
set_local_ref "$project" gauntlet/first-target-drift "$orphan_sha"
set_pr_observation "$first_target_url" "$first_target_head" "$head_sha_1" \
  gauntlet/first-target-drift OPEN false none none none none "$base_commit_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/first-open-unrelated-local-target.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh first-target-drift unit-1 opened \
  "$first_target_url" "$first_target_head" none --head-sha "$head_sha_1"
[[ "$(pr_event_file_count "$first_target_drift_dir")" == 0 ]] \
  || fail 'first-open integration-target drift produced progress evidence'
set_local_ref "$project" gauntlet/first-target-drift "$base_commit_sha"
run_for "$project" bash commands/record-gauntlet-pr-event.sh first-target-drift unit-1 opened \
  "$first_target_url" "$first_target_head" none --head-sha "$head_sha_1" >/dev/null
expect_file "$first_target_drift_dir/pr-events/unit-1/event-001.md"

absent_artifact_dir="$project/.ai/gauntlets/artifact-absent-at-commit"
copy_gauntlet "$ready_snapshot" "$absent_artifact_dir"
absent_artifact_url='https://github.com/example/opencaw-fixture/pull/214'
absent_artifact_head='gauntlet-work/artifact-absent-at-commit/unit-1'
run_for "$project" bash commands/record-gauntlet-pr-event.sh artifact-absent-at-commit unit-1 opened \
  "$absent_artifact_url" "$absent_artifact_head" none --head-sha "$artifact_absent_sha" >/dev/null
absent_commit_report="$critic_dir/artifact-absent-at-reviewed-commit.md"
write_critic_report "$absent_commit_report" fail artifact.txt "$artifact_absent_sha" \
  'The working tree path exists, but the reviewed commit does not contain it.' \
  'Commit the concrete artifact before requesting a fresh isolated critic.'
expect_failure "$temp_root/artifact-absent-at-reviewed-commit.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh artifact-absent-at-commit unit-1 fail \
  absent-artifact-builder absent-artifact-critic fresh-session "$absent_commit_report" \
  --head-sha "$artifact_absent_sha" --builder-strategy "$builder_strategy_1"
[[ "$(round_file_count "$absent_artifact_dir")" == 0 ]] \
  || fail 'an artifact absent from the reviewed commit produced critic evidence'
expect_failure "$temp_root/pr-event-unknown-unit.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet absent-unit opened \
  "$fixture_pr_url" 'gauntlet-work/fixture-gauntlet/absent-unit' none --head-sha "$head_sha_1"
expect_failure "$temp_root/pr-event-invalid-url.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  'https://example.com/pull/201' "$fixture_head" none --head-sha "$head_sha_1"
expect_failure "$temp_root/pr-event-invalid-head.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  "$fixture_pr_url" 'feature/unrelated-unit' none --head-sha "$head_sha_1"
expect_failure "$temp_root/pr-event-outside-ref.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh "$outside_gauntlet_dir/GAUNTLET.md" unit-1 opened \
  "$fixture_pr_url" "$fixture_head" none --head-sha "$head_sha_1"
expect_failure "$temp_root/round-without-progress-pr.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-no-pr critic-no-pr native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"
expect_failure "$temp_root/qa-before-open.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-1' \
  --head-sha "$head_sha_1"

linked_pr_events_dir="$project/.ai/gauntlets/linked-pr-events"
copy_gauntlet "$ready_snapshot" "$linked_pr_events_dir"
mkdir -p "$temp_root/outside-pr-events"
rmdir "$linked_pr_events_dir/pr-events"
ln -s "$temp_root/outside-pr-events" "$linked_pr_events_dir/pr-events"
expect_failure "$temp_root/linked-pr-events.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh linked-pr-events unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/202' \
  'gauntlet-work/linked-pr-events/unit-1' none --head-sha "$head_sha_1"

set_remote_ref "$project" gauntlet/fixture-gauntlet absent
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_1" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$progress_publication_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
  OPENCAW_TEST_SKIP_REMOTE_PUBLICATION=1 \
  expect_failure "$temp_root/first-open-remote-integration-still-absent.log" \
    run_for "$project" bash commands/record-gauntlet-pr-event.sh \
    fixture-gauntlet unit-1 opened "$fixture_pr_url" "$fixture_head" none \
    --head-sha "$head_sha_1"
[[ "$(pr_event_file_count "$gauntlet_dir")" == 0 ]] \
  || fail 'first opened event accepted an integration ref that publication never created'

set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_1" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$progress_publication_marker"
set_pr_merge_automation_observation "$fixture_pr_url" AutoMergeEnabledEvent
OPENCAW_TEST_SKIP_OBSERVATION=1 \
  expect_failure "$temp_root/open-progress-auto-merge-history.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
    "$fixture_pr_url" "$fixture_head" none --head-sha "$head_sha_1"
grep -Fq 'Gauntlet PR must never enable auto-merge or enter a merge queue' \
  "$temp_root/open-progress-auto-merge-history.log" \
  || fail 'open progress PR did not reject retained auto-merge history'
[[ "$(pr_event_file_count "$gauntlet_dir")" == 0 ]] \
  || fail 'open progress PR auto-merge history created immutable evidence'
set_pr_merge_automation_observation "$fixture_pr_url" none

run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  "$fixture_pr_url" "$fixture_head" none --head-sha "$head_sha_1" >/dev/null
event_one="$gauntlet_dir/pr-events/unit-1/event-001.md"
expect_file "$event_one"
expect_line '- Event: opened' "$event_one"
expect_line "- PR URL: $fixture_pr_url" "$event_one"
expect_line "- Head branch: $fixture_head" "$event_one"
expect_line "- Head SHA: $head_sha_1" "$event_one"
expect_line '- Target branch: gauntlet/fixture-gauntlet' "$event_one"
expect_line "- Target base SHA: $base_commit_sha" "$event_one"
expect_line '- Cross repository: false' "$event_one"
expect_line '- Head repository: example/opencaw-fixture' "$event_one"
expect_line '- Created at: 2026-08-01T12:00:00Z' "$event_one"
expect_line '- Closed at: none' "$event_one"
expect_line "- Publication checkpoint: $progress_checkpoint_relative" "$event_one"
expect_line "- Publication checkpoint sha256: $progress_checkpoint_sha256" "$event_one"
execution_contract_v1="$(sed -nE \
  's/^- Execution contract fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$gauntlet_file" | head -n 1)"
[[ -n "$execution_contract_v1" && "$execution_contract_v1" == "$progress_execution_contract" ]] \
  || fail 'first opened event did not atomically freeze the readiness execution contract'
quality_bar_opened="$(sed -nE \
  's/^- Quality bar fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$gauntlet_file" | head -n 1)"
[[ -n "$quality_bar_opened" ]] \
  || fail 'first opened event did not freeze the approved quality-bar fingerprint'
unit_manifest_opened="$(sed -nE \
  's/^- Unit manifest fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$gauntlet_file" | head -n 1)"
[[ -n "$unit_manifest_opened" \
  && "$unit_manifest_opened" == "$(unit_manifest_fingerprint "$project" "$gauntlet_file")" ]] \
  || fail 'first opened event did not freeze the approved retained-unit manifest'
expect_line "- Execution contract fingerprint: $execution_contract_v1" "$event_one"
expect_line "- Quality bar fingerprint: $quality_bar_opened" "$event_one"
expect_line "- Unit manifest fingerprint: $unit_manifest_opened" "$event_one"
expect_line "- Base commit SHA: $base_commit_sha" "$event_one"
expect_line '- QA comment author: none' "$event_one"
expect_line '- QA comment author type: none' "$event_one"
expect_line '- QA comment author association: none' "$event_one"
expect_line '- QA comment created at: none' "$event_one"
expect_line '- QA comment updated at: none' "$event_one"
expect_line '- QA comment body sha256: none' "$event_one"
grep -Eq '^- Scope fingerprint: [0-9a-f]{64}$' "$event_one" \
  || fail 'opened progress PR omitted the frozen unit-scope fingerprint'
event_one_hash="$(git hash-object "$event_one")"
event_one_sha256="$(sha256_file "$event_one")"
grep -Fq '.ai/gauntlets/fixture-gauntlet/pr-events/unit-1/event-001.md' "$gauntlet_file" \
  || fail 'opened progress PR was not linked from the durable ledger'
progress_open_ledger="$(select_ledger_line "$project" "$gauntlet_file" \
  'Progress PR Ledger' record \
  '.ai/gauntlets/fixture-gauntlet/pr-events/unit-1/event-001.md')"
[[ "$progress_open_ledger" == *"| checkpoint: $progress_checkpoint_relative | checkpoint-sha256: $progress_checkpoint_sha256 |"* ]] \
  || fail 'opened progress ledger omitted its publication checkpoint binding'

replace_line "$gauntlet_file" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Unapproved quality edit after first progress publication.'
expect_failure "$temp_root/quality-edit-after-first-open.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
expect_failure "$temp_root/quality-edit-after-first-open-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-unapproved-quality-edit critic-unapproved-quality-edit fresh-session \
  "$valid_fail_report" --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"
replace_line "$gauntlet_file" \
  '- Benchmark: Unapproved quality edit after first progress publication.' \
  '- Benchmark: Local artifact quality contract version 1.'
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready >/dev/null

first_open_quality_reset_dir="$project/.ai/gauntlets/first-open-quality-reset"
copy_gauntlet "$gauntlet_dir" "$first_open_quality_reset_dir"
replace_line "$first_open_quality_reset_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Illegitimate pending reset before any critic round.'
set_gauntlet_field "$project" "$first_open_quality_reset_dir/GAUNTLET.md" \
  'Current State' 'Quality bar fingerprint' pending
expect_failure "$temp_root/first-open-quality-reset-validation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh first-open-quality-reset --phase ready
expect_failure "$temp_root/first-open-quality-reset-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh first-open-quality-reset unit-1 fail \
  first-open-reset-builder first-open-reset-critic fresh-session "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

deleted_frozen_unit_dir="$project/.ai/gauntlets/deleted-frozen-unit"
copy_gauntlet "$gauntlet_dir" "$deleted_frozen_unit_dir"
replace_matching_line "$deleted_frozen_unit_dir/GAUNTLET.md" \
  '^- \[[ xX]\] unit-1 \| status:' ''
expect_failure "$temp_root/deleted-frozen-unit.log" run_for "$project" \
  bash commands/validate-gauntlet.sh deleted-frozen-unit --phase ready

renamed_frozen_unit_dir="$project/.ai/gauntlets/renamed-frozen-unit"
copy_gauntlet "$gauntlet_dir" "$renamed_frozen_unit_dir"
replace_matching_line "$renamed_frozen_unit_dir/GAUNTLET.md" \
  '^- \[[ xX]\] unit-1 \| status:' \
  '- [ ] renamed-unit | status: building | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
set_gauntlet_field "$project" "$renamed_frozen_unit_dir/GAUNTLET.md" \
  'Current State' 'Active work unit' renamed-unit
expect_failure "$temp_root/renamed-frozen-unit.log" run_for "$project" \
  bash commands/validate-gauntlet.sh renamed-frozen-unit --phase ready

first_open_revision_dir="$project/.ai/gauntlets/first-open-quality-revision"
copy_gauntlet "$gauntlet_dir" "$first_open_revision_dir"
first_open_revision_old_url='https://github.com/example/opencaw-fixture/pull/201'
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  first-open-quality-revision unit-1 closed "$first_open_revision_old_url" \
  gauntlet-work/first-open-quality-revision/unit-1 "$first_open_revision_old_url" \
  --head-sha "$head_sha_1" >/dev/null
expect_file "$first_open_revision_dir/pr-events/unit-1/event-002.md"
export FAKE_DATE_ISO='2026-08-01T12:00:02Z'
replace_line "$first_open_revision_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Local artifact quality contract version 2 after pre-critic closure.'
replace_line "$first_open_revision_dir/GAUNTLET.md" \
  '- Approved by: fixture-user' '- Approved by: fixture-user-v2'
replace_line "$first_open_revision_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:00Z' \
  '- Approved at: 2026-08-01T12:00:01Z'
set_gauntlet_field "$project" "$first_open_revision_dir/GAUNTLET.md" \
  'Current State' 'Quality bar fingerprint' pending
set_gauntlet_field "$project" "$first_open_revision_dir/GAUNTLET.md" \
  'Current State' 'Active work unit' unit-1
replace_matching_line "$first_open_revision_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
first_open_revision_marker="- Quality bar revision: precritic-v2 | approved by: fixture-user-v2 | approved at: 2026-08-01T12:00:01Z | supersedes: $quality_bar_opened | reason: Close the originally published PR before criticism and approve the replacement benchmark explicitly."
insert_after_matching_line "$first_open_revision_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$first_open_revision_marker"
run_for "$project" bash commands/validate-gauntlet.sh \
  first-open-quality-revision --phase ready >/dev/null
first_open_revision_head='gauntlet-work/first-open-quality-revision/unit-1-remediation-1'
first_open_revision_url='https://github.com/example/opencaw-fixture/pull/288'
set_local_ref "$project" "$first_open_revision_head" "$head_sha_2"
set_remote_ref "$project" "$first_open_revision_head" absent
first_open_revision_readiness="$(run_for "$project" bash commands/pr-readiness-check.sh \
  --gauntlet-progress first-open-quality-revision unit-1 \
  "$project/progress-validation.md")"
first_open_revision_checkpoint="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$first_open_revision_readiness")"
first_open_revision_trigger='quality-revision:precritic-v2'
first_open_revision_root='.ai/gauntlets/first-open-quality-revision/pr-events/unit-1/event-002.md'
first_open_revision_trigger_sha256="$(sha256_text "$first_open_revision_marker"$'\n')"
first_open_revision_root_sha256="$(sha256_file "$project/$first_open_revision_root")"
expect_line "- Remediation trigger: $first_open_revision_trigger" \
  "$project/$first_open_revision_checkpoint"
expect_line "- Remediation trigger sha256: $first_open_revision_trigger_sha256" \
  "$project/$first_open_revision_checkpoint"
expect_line "- Remediation root: $first_open_revision_root" \
  "$project/$first_open_revision_checkpoint"
expect_line "- Remediation root sha256: $first_open_revision_root_sha256" \
  "$project/$first_open_revision_checkpoint"
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  first-open-quality-revision unit-1 opened "$first_open_revision_url" \
  "$first_open_revision_head" none --head-sha "$head_sha_2" >/dev/null
first_open_quality_v2="$(sed -nE \
  's/^- Quality bar fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$first_open_revision_dir/GAUNTLET.md" | head -n 1)"
[[ -n "$first_open_quality_v2" && "$first_open_quality_v2" != "$quality_bar_opened" ]] \
  || fail 'new checkpoint/opened cycle did not freeze the explicitly revised quality bar'
expect_line "- Quality bar fingerprint: $first_open_quality_v2" \
  "$first_open_revision_dir/pr-events/unit-1/event-003.md"
unset FAKE_DATE_ISO

post_revision_close_dir="$project/.ai/gauntlets/post-revision-close"
copy_gauntlet "$first_open_revision_dir" "$post_revision_close_dir"
post_revision_close_url="$first_open_revision_url"
post_revision_close_head='gauntlet-work/post-revision-close/unit-1-remediation-1'
post_revision_close_marker="$(opened_publication_marker \
  "$project" post-revision-close unit-1)"
export FAKE_DATE_ISO='2026-08-01T12:00:04Z'
set_local_ref "$project" "$post_revision_close_head" "$head_sha_2"
set_pr_observation "$post_revision_close_url" "$post_revision_close_head" \
  "$head_sha_2" gauntlet/post-revision-close CLOSED false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:02Z \
  "$FAKE_DATE_ISO" "$post_revision_close_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh post-revision-close unit-1 closed \
  "$post_revision_close_url" "$post_revision_close_head" \
  'https://github.com/example/opencaw-fixture/pull/288#issuecomment-2880' \
  --head-sha "$head_sha_2" >/dev/null
post_revision_close_event="$post_revision_close_dir/pr-events/unit-1/event-004.md"
expect_file "$post_revision_close_event"
expect_line '- Recorded at: 2026-08-01T12:00:04Z' "$post_revision_close_event"
unset FAKE_DATE_ISO

for revision_timing_case in pre equal; do
  case "$revision_timing_case" in
    pre) revision_timing_close='2026-08-01T12:00:02Z' ;;
    equal) revision_timing_close='2026-08-01T12:00:01Z' ;;
  esac
  revision_timing_baseline='2026-08-01T12:00:00Z'
  revision_timing_approval='2026-08-01T12:00:01Z'
  revision_timing_open='2026-08-01T12:00:03Z'
  revision_timing_name="$revision_timing_case-close-quality-revision"
  revision_timing_dir="$project/.ai/gauntlets/$revision_timing_name"
  copy_gauntlet "$first_open_revision_dir" "$revision_timing_dir"
  revision_timing_event="$revision_timing_dir/pr-events/unit-1/event-003.md"
  revision_timing_close_event="$revision_timing_dir/pr-events/unit-1/event-002.md"
  replace_matching_line "$revision_timing_close_event" '^- Closed at:' \
    "- Closed at: $revision_timing_close"
  replace_matching_line "$revision_timing_close_event" '^- Recorded at:' \
    "- Recorded at: $revision_timing_close"
  revision_timing_close_ledger="$(select_ledger_line "$project" \
    "$revision_timing_dir/GAUNTLET.md" 'Progress PR Ledger' record \
    ".ai/gauntlets/$revision_timing_name/pr-events/unit-1/event-002.md")"
  replace_line "$revision_timing_dir/GAUNTLET.md" \
    "$revision_timing_close_ledger" \
    "${revision_timing_close_ledger//pr-closed: 2026-08-01T12:00:00Z/pr-closed: $revision_timing_close}"
  replace_matching_line "$revision_timing_event" '^- Created at:' \
    "- Created at: $revision_timing_open"
  replace_matching_line "$revision_timing_event" '^- Recorded at:' \
    "- Recorded at: $revision_timing_open"
  revision_timing_open_ledger="$(select_ledger_line "$project" \
    "$revision_timing_dir/GAUNTLET.md" 'Progress PR Ledger' record \
    ".ai/gauntlets/$revision_timing_name/pr-events/unit-1/event-003.md")"
  replace_line "$revision_timing_dir/GAUNTLET.md" \
    "$revision_timing_open_ledger" \
    "${revision_timing_open_ledger//pr-created: 2026-08-01T12:00:02Z/pr-created: $revision_timing_open}"
  revision_timing_checkpoint_relative="$(gauntlet_helper_value "$project" \
    gauntlet_section_field "$revision_timing_event" 'PR Event Metadata' \
    'Publication checkpoint')"
  revision_timing_checkpoint="$project/$revision_timing_checkpoint_relative"
  replace_matching_line "$revision_timing_checkpoint" \
    '^- Remediation root:' '- Remediation root: none'
  replace_matching_line "$revision_timing_checkpoint" \
    '^- Remediation root sha256:' '- Remediation root sha256: none'
  replace_matching_line "$revision_timing_checkpoint" '^- Recorded at:' \
    "- Recorded at: $revision_timing_open"
  refresh_copied_checkpoint_hashes "$revision_timing_dir"
  refresh_copied_evidence_hashes "$revision_timing_dir"
  sync_gauntlet_live_observations "$project" "$revision_timing_dir"
  revision_timing_head="gauntlet-work/$revision_timing_name/unit-1-remediation-1"
  revision_timing_publication_marker="$(opened_publication_marker \
    "$project" "$revision_timing_name" unit-1)"
  set_local_ref "$project" "$revision_timing_head" "$head_sha_2"
  set_remote_ref "$project" "$revision_timing_head" "$head_sha_2"
  set_pr_observation "$first_open_revision_url" "$revision_timing_head" \
    "$head_sha_2" "gauntlet/$revision_timing_name" OPEN false none none none none \
    "$base_commit_sha" false example/opencaw-fixture "$revision_timing_open" \
    none "$revision_timing_publication_marker"
  [[ "$revision_timing_baseline" < "$revision_timing_approval" \
    && ( "$revision_timing_approval" < "$revision_timing_close" \
      || "$revision_timing_approval" == "$revision_timing_close" ) \
    && "$revision_timing_close" < "$revision_timing_open" ]] \
    || fail "$revision_timing_case-close fixture did not isolate revision <= close ordering"
  expect_line "- Closed at: $revision_timing_close" "$revision_timing_close_event"
  expect_line "- Recorded at: $revision_timing_open" "$revision_timing_checkpoint"
  expect_line '- Remediation root: none' "$revision_timing_checkpoint"
  expect_line '- Remediation root sha256: none' "$revision_timing_checkpoint"
  revision_timing_root="$(gauntlet_helper_value "$project" \
    gauntlet_remediation_root_for_trigger "$revision_timing_dir/GAUNTLET.md" \
    unit-1 'quality-revision:precritic-v2' "$revision_timing_open")"
  [[ "$revision_timing_root" == none ]] \
    || fail "$revision_timing_case-close quality revision unexpectedly resolved to the immediately previous close"
  expect_failure "$temp_root/$revision_timing_name.log" run_for "$project" \
    bash commands/validate-gauntlet.sh "$revision_timing_name" --phase ready
  grep -Fq 'Replacement after a closed PR must retain that exact terminal event as its quality-revision remediation root:' \
    "$temp_root/$revision_timing_name.log" \
    || fail "$revision_timing_case-close quality revision did not reach the closed-root authorization gate"
done

same_unit_quality_reuse_dir="$project/.ai/gauntlets/same-unit-quality-reuse"
copy_gauntlet "$post_revision_close_dir" "$same_unit_quality_reuse_dir"
set_gauntlet_field "$project" "$same_unit_quality_reuse_dir/GAUNTLET.md" \
  'Current State' 'Quality bar fingerprint' pending
same_unit_quality_reuse_head='gauntlet-work/same-unit-quality-reuse/unit-1-remediation-2'
set_local_ref "$project" "$same_unit_quality_reuse_head" "$head_sha_3"
same_unit_quality_reuse_checkpoint_count="$(find \
  "$same_unit_quality_reuse_dir/publication-checkpoints/unit-1" -type f \
  -name 'checkpoint-*.md' | wc -l | tr -d ' ')"
export FAKE_DATE_ISO='2026-08-01T12:00:05Z'
expect_failure "$temp_root/same-unit-quality-reuse.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress \
  same-unit-quality-reuse unit-1 "$project/progress-validation.md"
grep -Fq \
  'Remediation trigger was already consumed for this work unit: quality-revision:precritic-v2' \
  "$temp_root/same-unit-quality-reuse.log" \
  || fail 'same-unit quality revision reuse after a second close was not rejected'
[[ "$same_unit_quality_reuse_checkpoint_count" == "$(find \
  "$same_unit_quality_reuse_dir/publication-checkpoints/unit-1" -type f \
  -name 'checkpoint-*.md' | wc -l | tr -d ' ')" ]] \
  || fail 'rejected same-unit quality revision reuse created a publication checkpoint'
unset FAKE_DATE_ISO

future_quality_dir="$project/.ai/gauntlets/future-quality-checkpoint"
copy_gauntlet "$first_open_revision_dir" "$future_quality_dir"
future_quality_approval_time='2026-08-01T12:00:03Z'
future_quality_event_time='2026-08-01T12:00:04Z'
future_quality_old_fingerprint="$(gauntlet_helper_value "$project" \
  gauntlet_quality_bar_fingerprint "$future_quality_dir/GAUNTLET.md")"
future_quality_revision_marker="${first_open_revision_marker/approved at: 2026-08-01T12:00:01Z/approved at: $future_quality_approval_time}"
replace_line "$future_quality_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:01Z' \
  "- Approved at: $future_quality_approval_time"
replace_line "$future_quality_dir/GAUNTLET.md" \
  "$first_open_revision_marker" "$future_quality_revision_marker"
future_quality_new_fingerprint="$(gauntlet_helper_value "$project" \
  gauntlet_quality_bar_fingerprint "$future_quality_dir/GAUNTLET.md")"
[[ "$future_quality_new_fingerprint" != "$future_quality_old_fingerprint" ]] \
  || fail 'future quality fixture did not derive a distinct revised fingerprint'
while IFS= read -r future_quality_file; do
  replace_all_literal "$future_quality_file" "$future_quality_old_fingerprint" \
    "$future_quality_new_fingerprint"
done < <(find "$future_quality_dir" -type f -name '*.md' \
  -print 2>/dev/null | LC_ALL=C sort)
future_quality_event="$future_quality_dir/pr-events/unit-1/event-003.md"
future_quality_checkpoint_relative="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$future_quality_event" 'PR Event Metadata' \
  'Publication checkpoint')"
future_quality_checkpoint="$project/$future_quality_checkpoint_relative"
future_quality_trigger_sha256="$(sha256_text "$future_quality_revision_marker"$'\n')"
expect_line '- Recorded at: 2026-08-01T12:00:02Z' "$future_quality_checkpoint"
expect_line "- Quality bar fingerprint: $future_quality_new_fingerprint" \
  "$future_quality_checkpoint"
replace_matching_line "$future_quality_checkpoint" '^- Quality bar approved at:' \
  "- Quality bar approved at: $future_quality_approval_time"
refresh_copied_checkpoint_hashes "$future_quality_dir"
expect_line "- Remediation trigger sha256: $future_quality_trigger_sha256" \
  "$future_quality_checkpoint"
replace_matching_line "$future_quality_event" '^- Created at:' \
  "- Created at: $future_quality_event_time"
replace_matching_line "$future_quality_event" '^- Recorded at:' \
  "- Recorded at: $future_quality_event_time"
future_quality_event_ledger="$(select_ledger_line "$project" \
  "$future_quality_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/future-quality-checkpoint/pr-events/unit-1/event-003.md')"
replace_line "$future_quality_dir/GAUNTLET.md" "$future_quality_event_ledger" \
  "${future_quality_event_ledger//pr-created: 2026-08-01T12:00:02Z/pr-created: $future_quality_event_time}"
refresh_copied_evidence_hashes "$future_quality_dir"
future_quality_head='gauntlet-work/future-quality-checkpoint/unit-1-remediation-1'
future_quality_marker="$(opened_publication_marker \
  "$project" future-quality-checkpoint unit-1)"
set_local_ref "$project" "$future_quality_head" "$head_sha_2"
set_remote_ref "$project" "$future_quality_head" "$head_sha_2"
set_pr_observation "$first_open_revision_url" "$future_quality_head" "$head_sha_2" \
  gauntlet/future-quality-checkpoint OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture "$future_quality_event_time" \
  none "$future_quality_marker"
expect_failure "$temp_root/future-quality-checkpoint.log" run_for "$project" \
  bash commands/validate-gauntlet.sh future-quality-checkpoint --phase ready
grep -Fq 'Publication checkpoint remediation trigger was not active at its Recorded at timestamp: quality-revision:precritic-v2' \
  "$temp_root/future-quality-checkpoint.log" \
  || fail 'future quality checkpoint did not reach the trigger-authorization gate'

equal_quality_dir="$project/.ai/gauntlets/equal-quality-checkpoint"
copy_gauntlet "$future_quality_dir" "$equal_quality_dir"
equal_quality_revision_marker="${future_quality_revision_marker/approved at: $future_quality_approval_time/approved at: 2026-08-01T12:00:02Z}"
replace_line "$equal_quality_dir/GAUNTLET.md" \
  "- Approved at: $future_quality_approval_time" \
  '- Approved at: 2026-08-01T12:00:02Z'
replace_line "$equal_quality_dir/GAUNTLET.md" \
  "$future_quality_revision_marker" "$equal_quality_revision_marker"
equal_quality_old_fingerprint="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$equal_quality_dir/pr-events/unit-1/event-003.md" \
  'PR Event Metadata' 'Quality bar fingerprint')"
equal_quality_new_fingerprint="$(gauntlet_helper_value "$project" \
  gauntlet_quality_bar_fingerprint "$equal_quality_dir/GAUNTLET.md")"
[[ "$equal_quality_new_fingerprint" != "$equal_quality_old_fingerprint" ]] \
  || fail 'equal-time quality fixture did not derive a distinct revised fingerprint'
while IFS= read -r equal_quality_file; do
  replace_all_literal "$equal_quality_file" "$equal_quality_old_fingerprint" \
    "$equal_quality_new_fingerprint"
done < <(find "$equal_quality_dir" -type f -name '*.md' \
  -print 2>/dev/null | LC_ALL=C sort)
equal_quality_event="$equal_quality_dir/pr-events/unit-1/event-003.md"
equal_quality_checkpoint_relative="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$equal_quality_event" 'PR Event Metadata' \
  'Publication checkpoint')"
equal_quality_checkpoint="$project/$equal_quality_checkpoint_relative"
equal_quality_trigger_sha256="$(sha256_text "$equal_quality_revision_marker"$'\n')"
expect_line '- Recorded at: 2026-08-01T12:00:02Z' "$equal_quality_checkpoint"
expect_line "- Quality bar fingerprint: $equal_quality_new_fingerprint" \
  "$equal_quality_checkpoint"
replace_matching_line "$equal_quality_checkpoint" '^- Quality bar approved at:' \
  '- Quality bar approved at: 2026-08-01T12:00:02Z'
refresh_copied_checkpoint_hashes "$equal_quality_dir"
expect_line "- Remediation trigger sha256: $equal_quality_trigger_sha256" \
  "$equal_quality_checkpoint"
replace_matching_line "$equal_quality_event" '^- Created at:' \
  '- Created at: 2026-08-01T12:00:02Z'
replace_matching_line "$equal_quality_event" '^- Recorded at:' \
  '- Recorded at: 2026-08-01T12:00:02Z'
equal_quality_event_ledger="$(select_ledger_line "$project" \
  "$equal_quality_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/equal-quality-checkpoint/pr-events/unit-1/event-003.md')"
replace_line "$equal_quality_dir/GAUNTLET.md" "$equal_quality_event_ledger" \
  "${equal_quality_event_ledger//pr-created: $future_quality_event_time/pr-created: 2026-08-01T12:00:02Z}"
refresh_copied_evidence_hashes "$equal_quality_dir"
equal_quality_head='gauntlet-work/equal-quality-checkpoint/unit-1-remediation-1'
equal_quality_marker="$(opened_publication_marker \
  "$project" equal-quality-checkpoint unit-1)"
set_local_ref "$project" "$equal_quality_head" "$head_sha_2"
set_remote_ref "$project" "$equal_quality_head" "$head_sha_2"
set_pr_observation "$first_open_revision_url" "$equal_quality_head" "$head_sha_2" \
  gauntlet/equal-quality-checkpoint OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:02Z \
  none "$equal_quality_marker"
expect_line '- Created at: 2026-08-01T12:00:02Z' "$equal_quality_event"
expect_line '- Recorded at: 2026-08-01T12:00:02Z' "$equal_quality_event"
run_for "$project" bash commands/validate-gauntlet.sh \
  equal-quality-checkpoint --phase ready >/dev/null

reverse_revision_dir="$project/.ai/gauntlets/reverse-lexical-quality-consumer"
copy_gauntlet "$gauntlet_dir" "$reverse_revision_dir"
reverse_baseline_event="$reverse_revision_dir/pr-events/unit-1/event-001.md"
reverse_baseline_checkpoint_relative="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$reverse_baseline_event" 'PR Event Metadata' \
  'Publication checkpoint')"
expect_line "- Quality bar fingerprint: $quality_bar_opened" \
  "$reverse_baseline_event"
expect_line "- Quality bar fingerprint: $quality_bar_opened" \
  "$project/$reverse_baseline_checkpoint_relative"
reverse_baseline_url="$(gauntlet_helper_value "$project" gauntlet_section_field \
  "$reverse_baseline_event" 'PR Event Metadata' 'PR URL')"
reverse_baseline_head="$(gauntlet_helper_value "$project" gauntlet_section_field \
  "$reverse_baseline_event" 'PR Event Metadata' 'Head branch')"
reverse_baseline_head_sha="$(gauntlet_helper_value "$project" gauntlet_section_field \
  "$reverse_baseline_event" 'PR Event Metadata' 'Head SHA')"
export FAKE_DATE_ISO=2026-08-01T12:00:00Z
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  reverse-lexical-quality-consumer unit-1 closed "$reverse_baseline_url" \
  "$reverse_baseline_head" "$reverse_baseline_url" \
  --head-sha "$reverse_baseline_head_sha" >/dev/null
expect_line '- Event: closed' \
  "$reverse_revision_dir/pr-events/unit-1/event-002.md"
insert_after_matching_line "$reverse_revision_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [ ] unit-a | status: pending | title: Lexically earlier parallel unit | scope: independent unit-a artifact boundary'
insert_after_matching_line "$reverse_revision_dir/GAUNTLET.md" \
  '^- .*unit-a .*status:' \
  '- [ ] unit-z | status: pending | title: First revision-consuming parallel unit | scope: independent unit-z artifact boundary'
reverse_manifest_fingerprint="$(unit_manifest_fingerprint \
  "$project" "$reverse_revision_dir/GAUNTLET.md")"
reverse_manifest_revision="- Unit manifest revision: add-reverse-lexical-units | from: $unit_manifest_opened | to: $reverse_manifest_fingerprint | prior-units: unit-1 | current-units: unit-1,unit-a,unit-z | reason: Add two disjoint units to prove append order rather than lexical path order. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$reverse_revision_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$reverse_manifest_revision"
replace_line "$reverse_revision_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Local artifact quality contract version 2 for reverse lexical consumers.'
replace_line "$reverse_revision_dir/GAUNTLET.md" \
  '- Approved by: fixture-user' '- Approved by: reverse-fixture-user'
replace_line "$reverse_revision_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:00Z' \
  '- Approved at: 2026-08-02T00:00:01Z'
reverse_quality_revision="- Quality bar revision: reverse-v2 | approved by: reverse-fixture-user | approved at: 2026-08-02T00:00:01Z | supersedes: $quality_bar_opened | reason: Prove that the first append-ordered consumer wins when lexical unit order is reversed."
insert_after_matching_line "$reverse_revision_dir/GAUNTLET.md" \
  '^- Unit manifest revision: add-reverse-lexical-units ' "$reverse_quality_revision"
set_gauntlet_field "$project" "$reverse_revision_dir/GAUNTLET.md" \
  'Current State' 'Quality bar fingerprint' pending
set_gauntlet_field "$project" "$reverse_revision_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
set_gauntlet_field "$project" "$reverse_revision_dir/GAUNTLET.md" \
  'Current State' 'Active work unit' unit-z
reset_integration_review "$project" "$reverse_revision_dir/GAUNTLET.md"
set_local_ref "$project" gauntlet/reverse-lexical-quality-consumer "$base_commit_sha"
run_for "$project" bash commands/validate-gauntlet.sh \
  reverse-lexical-quality-consumer --phase ready >/dev/null

export FAKE_DATE_ISO=2026-08-02T00:00:02Z
reverse_z_head='gauntlet-work/reverse-lexical-quality-consumer/unit-z'
reverse_a_head='gauntlet-work/reverse-lexical-quality-consumer/unit-a'
reverse_z_url='https://github.com/example/opencaw-fixture/pull/297'
reverse_a_url='https://github.com/example/opencaw-fixture/pull/298'
set_local_ref "$project" "$reverse_z_head" "$head_sha_1"
set_local_ref "$project" "$reverse_a_head" "$head_sha_2"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  reverse-lexical-quality-consumer unit-z "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  reverse-lexical-quality-consumer unit-z opened "$reverse_z_url" \
  "$reverse_z_head" none --head-sha "$head_sha_1" >/dev/null
reverse_z_event="$reverse_revision_dir/pr-events/unit-z/event-001.md"
expect_line '- Remediation trigger: quality-revision:reverse-v2' "$reverse_z_event"
set_gauntlet_field "$project" "$reverse_revision_dir/GAUNTLET.md" \
  'Current State' 'Active work unit' unit-a
reverse_a_readiness="$(run_for "$project" bash commands/pr-readiness-check.sh \
  --gauntlet-progress reverse-lexical-quality-consumer unit-a \
  "$project/progress-validation.md")"
reverse_a_checkpoint_relative="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$reverse_a_readiness")"
reverse_a_checkpoint="$project/$reverse_a_checkpoint_relative"
expect_line '- Remediation trigger: none' "$reverse_a_checkpoint"
cp "$reverse_a_checkpoint" "$temp_root/reverse-a-checkpoint-original.md"
reverse_quality_trigger_hash="$(gauntlet_helper_value "$project" \
  gauntlet_remediation_trigger_hash "$reverse_revision_dir/GAUNTLET.md" \
  quality-revision:reverse-v2)"
replace_line "$reverse_a_checkpoint" '- Remediation trigger: none' \
  '- Remediation trigger: quality-revision:reverse-v2'
replace_line "$reverse_a_checkpoint" '- Remediation trigger sha256: none' \
  "- Remediation trigger sha256: $reverse_quality_trigger_hash"
expect_failure "$temp_root/reverse-lexical-quality-reuse.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh reverse-lexical-quality-consumer \
  unit-a opened "$reverse_a_url" "$reverse_a_head" none --head-sha "$head_sha_2"
[[ ! -d "$reverse_revision_dir/pr-events/unit-a" ]] \
  || fail 'later reverse-lexical unit reused the already-consumed quality revision'
cp "$temp_root/reverse-a-checkpoint-original.md" "$reverse_a_checkpoint"
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  reverse-lexical-quality-consumer unit-a opened "$reverse_a_url" \
  "$reverse_a_head" none --head-sha "$head_sha_2" >/dev/null
reverse_a_event="$reverse_revision_dir/pr-events/unit-a/event-001.md"
expect_line '- Remediation trigger: none' "$reverse_a_event"
run_for "$project" bash commands/validate-gauntlet.sh \
  reverse-lexical-quality-consumer --phase ready >/dev/null
reverse_z_ledger="$(select_ledger_line "$project" \
  "$reverse_revision_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/reverse-lexical-quality-consumer/pr-events/unit-z/event-001.md')"
reverse_a_ledger="$(select_ledger_line "$project" \
  "$reverse_revision_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/reverse-lexical-quality-consumer/pr-events/unit-a/event-001.md')"
replace_line "$reverse_revision_dir/GAUNTLET.md" "$reverse_z_ledger" \
  '__REVERSE_Z_LEDGER__'
replace_line "$reverse_revision_dir/GAUNTLET.md" "$reverse_a_ledger" \
  "$reverse_z_ledger"
replace_line "$reverse_revision_dir/GAUNTLET.md" '__REVERSE_Z_LEDGER__' \
  "$reverse_a_ledger"
expect_failure "$temp_root/reverse-lexical-ledger-reorder.log" run_for "$project" \
  bash commands/validate-gauntlet.sh reverse-lexical-quality-consumer --phase ready
replace_line "$reverse_revision_dir/GAUNTLET.md" "$reverse_a_ledger" \
  '__REVERSE_A_LEDGER__'
replace_line "$reverse_revision_dir/GAUNTLET.md" "$reverse_z_ledger" \
  "$reverse_a_ledger"
replace_line "$reverse_revision_dir/GAUNTLET.md" '__REVERSE_A_LEDGER__' \
  "$reverse_z_ledger"
run_for "$project" bash commands/validate-gauntlet.sh \
  reverse-lexical-quality-consumer --phase ready >/dev/null
unset FAKE_DATE_ISO

objective_drift_dir="$project/.ai/gauntlets/execution-objective-drift"
copy_gauntlet "$gauntlet_dir" "$objective_drift_dir"
replace_line "$objective_drift_dir/GAUNTLET.md" \
  'Produce an inspectable local artifact that satisfies the approved fixture benchmark.' \
  'Produce a retargeted artifact under an unapproved execution objective.'
expect_failure "$temp_root/execution-objective-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh execution-objective-drift --phase ready

constraints_drift_dir="$project/.ai/gauntlets/execution-constraints-drift"
copy_gauntlet "$gauntlet_dir" "$constraints_drift_dir"
replace_line "$constraints_drift_dir/GAUNTLET.md" \
  '- Do not use network services or credentials.' \
  '- Permit an unapproved network service during execution.'
expect_failure "$temp_root/execution-constraints-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh execution-constraints-drift --phase ready

policy_drift_dir="$project/.ai/gauntlets/execution-policy-drift"
copy_gauntlet "$gauntlet_dir" "$policy_drift_dir"
replace_line "$policy_drift_dir/GAUNTLET.md" \
  '- Post-promotion QA: required' '- Post-promotion QA: optional'
expect_failure "$temp_root/execution-policy-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh execution-policy-drift --phase ready

base_drift_dir="$project/.ai/gauntlets/execution-base-drift"
copy_gauntlet "$gauntlet_dir" "$base_drift_dir"
set_local_ref "$project" release "$base_commit_sha"
replace_line "$base_drift_dir/GAUNTLET.md" '- Base branch: main' '- Base branch: release'
base_drift_gauntlet_hash="$(git hash-object "$base_drift_dir/GAUNTLET.md")"
base_drift_event_hash="$(git hash-object "$base_drift_dir/pr-events/unit-1/event-001.md")"
expect_failure "$temp_root/execution-base-drift-validation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh execution-base-drift --phase ready
expect_failure "$temp_root/execution-base-drift-readiness.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress \
  execution-base-drift unit-1 "$project/progress-validation.md"
expect_failure "$temp_root/execution-base-drift-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh execution-base-drift unit-1 fail \
  base-drift-builder base-drift-critic fresh-session "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"
expect_failure "$temp_root/execution-base-drift-pr-event.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh execution-base-drift unit-1 closed \
  "$fixture_pr_url" gauntlet-work/execution-base-drift/unit-1 "$fixture_pr_url" \
  --head-sha "$head_sha_1"
[[ "$base_drift_gauntlet_hash" == "$(git hash-object "$base_drift_dir/GAUNTLET.md")" \
  && "$base_drift_event_hash" == "$(git hash-object "$base_drift_dir/pr-events/unit-1/event-001.md")" \
  && "$(pr_event_file_count "$base_drift_dir")" == 1 \
  && "$(round_file_count "$base_drift_dir")" == 0 ]] \
  || fail 'execution-contract drift recorder/readiness probes mutated durable evidence'

base_sha_drift_dir="$project/.ai/gauntlets/execution-base-sha-drift"
copy_gauntlet "$gauntlet_dir" "$base_sha_drift_dir"
set_local_ref "$project" main "$head_sha_1"
set_local_ref "$project" gauntlet/execution-base-sha-drift "$head_sha_1"
replace_line "$base_sha_drift_dir/GAUNTLET.md" "- Base commit SHA: $base_commit_sha" \
  "- Base commit SHA: $head_sha_1"
expect_failure "$temp_root/execution-base-sha-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh execution-base-sha-drift --phase ready
set_local_ref "$project" main "$base_commit_sha"

contract_evidence_tamper_dir="$project/.ai/gauntlets/contract-evidence-tamper"
copy_gauntlet "$gauntlet_dir" "$contract_evidence_tamper_dir"
replace_matching_line "$contract_evidence_tamper_dir/pr-events/unit-1/event-001.md" \
  '^- Execution contract fingerprint:' \
  '- Execution contract fingerprint: 0000000000000000000000000000000000000000000000000000000000000000'
refresh_copied_evidence_hashes "$contract_evidence_tamper_dir"
expect_failure "$temp_root/contract-evidence-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh contract-evidence-tamper --phase ready

contract_ledger_tamper_dir="$project/.ai/gauntlets/contract-ledger-tamper"
copy_gauntlet "$gauntlet_dir" "$contract_ledger_tamper_dir"
contract_ledger_line="$(select_ledger_line "$project" \
  "$contract_ledger_tamper_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/contract-ledger-tamper/pr-events/unit-1/event-001.md')"
contract_ledger_fingerprint="$(sed -nE \
  's/^- Execution contract fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$contract_ledger_tamper_dir/GAUNTLET.md" | head -n 1)"
replace_line "$contract_ledger_tamper_dir/GAUNTLET.md" "$contract_ledger_line" \
  "${contract_ledger_line/contract: $contract_ledger_fingerprint/contract: 0000000000000000000000000000000000000000000000000000000000000000}"
expect_failure "$temp_root/contract-ledger-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh contract-ledger-tamper --phase ready

tampered_event_dir="$project/.ai/gauntlets/tampered-pr-event"
copy_gauntlet "$gauntlet_dir" "$tampered_event_dir"
run_for "$project" bash commands/validate-gauntlet.sh tampered-pr-event --phase ready >/dev/null
replace_line "$tampered_event_dir/pr-events/unit-1/event-001.md" '- Event: opened' '- Event: qa-pass'
expect_failure "$temp_root/tampered-pr-event.log" run_for "$project" \
  bash commands/validate-gauntlet.sh tampered-pr-event --phase ready

noncontiguous_event_dir="$project/.ai/gauntlets/noncontiguous-pr-event"
copy_gauntlet "$gauntlet_dir" "$noncontiguous_event_dir"
cp "$noncontiguous_event_dir/pr-events/unit-1/event-001.md" \
  "$noncontiguous_event_dir/pr-events/unit-1/event-003.md"
expect_failure "$temp_root/noncontiguous-pr-event.log" run_for "$project" \
  bash commands/validate-gauntlet.sh noncontiguous-pr-event --phase ready

stray_event_root_dir="$project/.ai/gauntlets/stray-pr-event-root"
copy_gauntlet "$gauntlet_dir" "$stray_event_root_dir"
printf 'unexpected top-level event artifact\n' >"$stray_event_root_dir/pr-events/stray.md"
expect_failure "$temp_root/stray-pr-event-root.log" run_for "$project" \
  bash commands/validate-gauntlet.sh stray-pr-event-root --phase ready

unexpected_event_file_dir="$project/.ai/gauntlets/unexpected-pr-event-file"
copy_gauntlet "$gauntlet_dir" "$unexpected_event_file_dir"
printf 'unexpected item event artifact\n' \
  >"$unexpected_event_file_dir/pr-events/unit-1/notes.md"
expect_failure "$temp_root/unexpected-pr-event-file.log" run_for "$project" \
  bash commands/validate-gauntlet.sh unexpected-pr-event-file --phase ready

noncanonical_event_file_dir="$project/.ai/gauntlets/noncanonical-pr-event-file"
copy_gauntlet "$gauntlet_dir" "$noncanonical_event_file_dir"
cp "$noncanonical_event_file_dir/pr-events/unit-1/event-001.md" \
  "$noncanonical_event_file_dir/pr-events/unit-1/event-1.md"
expect_failure "$temp_root/noncanonical-pr-event-file.log" run_for "$project" \
  bash commands/validate-gauntlet.sh noncanonical-pr-event-file --phase ready

expect_failure "$temp_root/second-live-pr.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/203' \
  'gauntlet-work/fixture-gauntlet/unit-1-replacement' none --head-sha "$head_sha_2"
expect_failure "$temp_root/qa-before-round.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-2' \
  --head-sha "$head_sha_1"

ownership_dir="$project/.ai/gauntlets/pr-ownership"
copy_gauntlet "$ready_snapshot" "$ownership_dir"
insert_after_matching_line "$ownership_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Independently owned fixture unit | scope: independent ownership fixture'
ownership_manifest_fingerprint="$(unit_manifest_fingerprint \
  "$project" "$ownership_dir/GAUNTLET.md")"
ownership_manifest_approval="$(grep -F -- '- Unit manifest approval:' \
  "$ownership_dir/GAUNTLET.md")"
replace_line "$ownership_dir/GAUNTLET.md" "$ownership_manifest_approval" \
  "- Unit manifest approval: $ownership_manifest_fingerprint | units: unit-1,unit-2 | approved by: fixture-user | approved at: 2026-08-01T12:00:00Z"
run_for "$project" bash commands/record-gauntlet-pr-event.sh pr-ownership unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/204' \
  'gauntlet-work/pr-ownership/unit-1' none --head-sha "$head_sha_1" >/dev/null
expect_failure "$temp_root/cross-unit-pr-ownership.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh pr-ownership unit-2 opened \
  'https://github.com/example/opencaw-fixture/pull/204' \
  'gauntlet-work/pr-ownership/unit-2' none --head-sha "$head_sha_1"

alias_dir="$project/.ai/gauntlets/pr-url-alias"
copy_gauntlet "$ready_snapshot" "$alias_dir"
alias_pr_url='https://github.com/example/opencaw-fixture/pull/211'
alias_head='gauntlet-work/pr-url-alias/unit-1'
run_for "$project" bash commands/record-gauntlet-pr-event.sh pr-url-alias unit-1 opened \
  "$alias_pr_url" "$alias_head" none --head-sha "$head_sha_1" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh pr-url-alias unit-1 closed \
  "$alias_pr_url" "$alias_head" \
  'https://github.com/example/opencaw-fixture/pull/211#issuecomment-30' --head-sha "$head_sha_1" >/dev/null
expect_failure "$temp_root/trailing-slash-pr-alias.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh pr-url-alias unit-1 opened \
  "$alias_pr_url/" 'gauntlet-work/pr-url-alias/unit-1-remediation-1' none --head-sha "$head_sha_2"
alias_original_marker="$(opened_publication_marker \
  "$project" pr-url-alias unit-1)"
set_pr_observation "$alias_pr_url" "$alias_head" "$head_sha_1" \
  gauntlet/pr-url-alias CLOSED false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z \
  2026-08-01T12:00:00Z "$alias_original_marker"
alias_checkpoint_one="$alias_dir/publication-checkpoints/unit-1/checkpoint-001.md"
alias_checkpoint_two="$alias_dir/publication-checkpoints/unit-1/checkpoint-002.md"
expect_file "$alias_checkpoint_one"
expect_file "$alias_checkpoint_two"
alias_checkpoint_one_time="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$alias_checkpoint_one" | head -n 1)"
alias_checkpoint_two_time="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$alias_checkpoint_two" | head -n 1)"
alias_event_one_created="$(sed -nE 's/^- Created at: (.*)$/\1/p' \
  "$alias_dir/pr-events/unit-1/event-001.md" | head -n 1)"
[[ "$alias_checkpoint_one_time" == "$alias_checkpoint_two_time" \
  && "$alias_checkpoint_two_time" == "$alias_event_one_created" ]] \
  || fail 'future-checkpoint replay fixture did not retain its same-second tie'
alias_replacement_url='https://github.com/example/opencaw-fixture/pull/299'
alias_replacement_head='gauntlet-work/pr-url-alias/unit-1-remediation-1'
run_for "$project" bash commands/record-gauntlet-pr-event.sh pr-url-alias unit-1 opened \
  "$alias_replacement_url" "$alias_replacement_head" none --head-sha "$head_sha_2" >/dev/null
expect_file "$alias_dir/pr-events/unit-1/event-003.md"
expect_line '- Publication checkpoint: .ai/gauntlets/pr-url-alias/publication-checkpoints/unit-1/checkpoint-001.md' \
  "$alias_dir/pr-events/unit-1/event-001.md"
expect_line '- Publication checkpoint: .ai/gauntlets/pr-url-alias/publication-checkpoints/unit-1/checkpoint-002.md' \
  "$alias_dir/pr-events/unit-1/event-003.md"
run_for "$project" bash commands/validate-gauntlet.sh pr-url-alias --phase ready >/dev/null

concurrent_dir="$project/.ai/gauntlets/concurrent-recorders"
copy_gauntlet "$ready_snapshot" "$concurrent_dir"
insert_after_matching_line "$concurrent_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Independently recordable fixture unit | scope: independent second fixture artifact'
concurrent_manifest_fingerprint="$(unit_manifest_fingerprint \
  "$project" "$concurrent_dir/GAUNTLET.md")"
concurrent_manifest_approval="$(grep -F -- '- Unit manifest approval:' \
  "$concurrent_dir/GAUNTLET.md")"
replace_line "$concurrent_dir/GAUNTLET.md" "$concurrent_manifest_approval" \
  "- Unit manifest approval: $concurrent_manifest_fingerprint | units: unit-1,unit-2 | approved by: fixture-user | approved at: 2026-08-01T12:00:00Z"
set_local_ref "$project" gauntlet/concurrent-recorders "$base_commit_sha"
set_local_ref "$project" gauntlet-work/concurrent-recorders/unit-1 "$head_sha_1"
set_local_ref "$project" gauntlet-work/concurrent-recorders/unit-2 "$head_sha_2"
concurrent_marker_1="$(ensure_publication_marker \
  "$project" concurrent-recorders unit-1)"
publish_checkpoint_refs "$project" "$concurrent_marker_1"
concurrent_marker_2="$(ensure_publication_marker \
  "$project" concurrent-recorders unit-2)"
publish_checkpoint_refs "$project" "$concurrent_marker_2"
concurrent_url_1='https://github.com/example/opencaw-fixture/pull/216'
concurrent_url_2='https://github.com/example/opencaw-fixture/pull/217'
set_pr_observation "$concurrent_url_1" gauntlet-work/concurrent-recorders/unit-1 \
  "$head_sha_1" gauntlet/concurrent-recorders OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$concurrent_marker_1"
set_pr_observation "$concurrent_url_2" gauntlet-work/concurrent-recorders/unit-2 \
  "$head_sha_2" gauntlet/concurrent-recorders OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$concurrent_marker_2"
set +e
FAKE_GH_DELAY_SECONDS=1 OPENCAW_PROJECT_ROOT="$project" \
  bash commands/record-gauntlet-pr-event.sh concurrent-recorders unit-1 opened \
  "$concurrent_url_1" gauntlet-work/concurrent-recorders/unit-1 none \
  --head-sha "$head_sha_1" >"$temp_root/concurrent-first.log" 2>&1 &
concurrent_first_pid=$!
set -e
wait_for_path "$concurrent_dir/.opencaw-gauntlet.lock"
set +e
OPENCAW_PROJECT_ROOT="$project" bash commands/record-gauntlet-pr-event.sh \
  concurrent-recorders unit-2 opened "$concurrent_url_2" \
  gauntlet-work/concurrent-recorders/unit-2 none --head-sha "$head_sha_2" \
  >"$temp_root/concurrent-disjoint-contended.log" 2>&1
concurrent_contended_status=$?
wait "$concurrent_first_pid"
concurrent_first_status=$?
set -e
[[ $concurrent_first_status -eq 0 ]] || fail 'the lock-owning concurrent recorder did not complete'
[[ $concurrent_contended_status -ne 0 ]] || fail 'a disjoint concurrent recorder bypassed the Gauntlet lock'
grep -Fq 'Gauntlet is locked' "$temp_root/concurrent-disjoint-contended.log" \
  || fail 'lock contention did not return the deterministic retry diagnosis'
run_for "$project" bash commands/record-gauntlet-pr-event.sh concurrent-recorders unit-2 opened \
  "$concurrent_url_2" gauntlet-work/concurrent-recorders/unit-2 none \
  --head-sha "$head_sha_2" >/dev/null
expect_file "$concurrent_dir/pr-events/unit-1/event-001.md"
expect_file "$concurrent_dir/pr-events/unit-2/event-001.md"
run_for "$project" bash commands/validate-gauntlet.sh concurrent-recorders --phase ready >/dev/null

same_unit_concurrent_dir="$project/.ai/gauntlets/same-unit-concurrent"
copy_gauntlet "$ready_snapshot" "$same_unit_concurrent_dir"
set_local_ref "$project" gauntlet/same-unit-concurrent "$base_commit_sha"
set_local_ref "$project" gauntlet-work/same-unit-concurrent/unit-1 "$head_sha_1"
same_unit_concurrent_marker="$(ensure_publication_marker \
  "$project" same-unit-concurrent unit-1)"
publish_checkpoint_refs "$project" "$same_unit_concurrent_marker"
same_unit_url_1='https://github.com/example/opencaw-fixture/pull/218'
same_unit_url_2='https://github.com/example/opencaw-fixture/pull/219'
set_pr_observation "$same_unit_url_1" gauntlet-work/same-unit-concurrent/unit-1 \
  "$head_sha_1" gauntlet/same-unit-concurrent OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$same_unit_concurrent_marker"
set_pr_observation "$same_unit_url_2" gauntlet-work/same-unit-concurrent/unit-1 \
  "$head_sha_1" gauntlet/same-unit-concurrent OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$same_unit_concurrent_marker"
set +e
FAKE_GH_DELAY_SECONDS=1 OPENCAW_PROJECT_ROOT="$project" \
  bash commands/record-gauntlet-pr-event.sh same-unit-concurrent unit-1 opened \
  "$same_unit_url_1" gauntlet-work/same-unit-concurrent/unit-1 none \
  --head-sha "$head_sha_1" >"$temp_root/same-unit-concurrent-first.log" 2>&1 &
same_unit_first_pid=$!
set -e
wait_for_path "$same_unit_concurrent_dir/.opencaw-gauntlet.lock"
set +e
OPENCAW_PROJECT_ROOT="$project" bash commands/record-gauntlet-pr-event.sh \
  same-unit-concurrent unit-1 opened "$same_unit_url_2" \
  gauntlet-work/same-unit-concurrent/unit-1 none --head-sha "$head_sha_1" \
  >"$temp_root/same-unit-concurrent-contended.log" 2>&1
same_unit_contended_status=$?
wait "$same_unit_first_pid"
same_unit_first_status=$?
set -e
[[ $same_unit_first_status -eq 0 && $same_unit_contended_status -ne 0 ]] \
  || fail 'same-unit concurrency did not preserve exactly one lock-owning recorder'
expect_failure "$temp_root/same-unit-retry-live-pr.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh same-unit-concurrent unit-1 opened \
  "$same_unit_url_2" gauntlet-work/same-unit-concurrent/unit-1 none --head-sha "$head_sha_1"
[[ "$(pr_event_file_count "$same_unit_concurrent_dir")" == 1 ]] \
  || fail 'same-unit concurrent recording duplicated immutable PR evidence'
expect_line "- PR URL: $same_unit_url_1" \
  "$same_unit_concurrent_dir/pr-events/unit-1/event-001.md"

run_for "$project" bash commands/record-gauntlet-pr-event.sh crlf-gauntlet unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/205' \
  'gauntlet-work/crlf-gauntlet/unit-1' none --head-sha "$head_sha_1" >/dev/null

echo '[4/8] rejecting invalid critic evidence without mutating round history'

crlf_report="$critic_dir/crlf-report.md"
cp "$valid_fail_report" "$crlf_report"
convert_to_crlf "$crlf_report"
run_for "$project" bash commands/record-gauntlet-round.sh crlf-gauntlet unit-1 fail \
  crlf-builder crlf-critic fresh-session "$crlf_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1" --dry-run >/dev/null
[[ "$(round_file_count "$project/.ai/gauntlets/crlf-gauntlet")" == 0 ]] \
  || fail 'CRLF record dry-run created evidence'

expect_failure "$temp_root/unknown-unit.log" run_for_without_observation "$project" \
  bash commands/record-gauntlet-round.sh \
  fixture-gauntlet absent-unit fail builder-1 critic-unknown native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"
expect_failure "$temp_root/self-critique.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail same-identity same-identity native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

expect_failure "$temp_root/round-missing-head-sha.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-missing-sha critic-missing-sha native-subagent "$valid_fail_report" \
  --builder-strategy "$builder_strategy_1"
expect_failure "$temp_root/round-malformed-head-sha.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-malformed-sha critic-malformed-sha native-subagent "$valid_fail_report" \
  --head-sha deadbeef --builder-strategy "$builder_strategy_1"
expect_failure "$temp_root/round-missing-builder-strategy.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-missing-strategy critic-missing-strategy native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1"
expect_failure "$temp_root/round-placeholder-builder-strategy.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-placeholder-strategy critic-placeholder-strategy native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy TODO
expect_failure "$temp_root/round-multiline-builder-strategy.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-multiline-strategy critic-multiline-strategy native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy $'First implementation step.\nSecond hidden step.'

missing_head_report="$critic_dir/missing-head-sha.md"
cp "$valid_fail_report" "$missing_head_report"
replace_line "$missing_head_report" "- Head SHA: $head_sha_1" ''
expect_failure "$temp_root/report-missing-head-sha.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-report-missing-sha critic-report-missing-sha fresh-session "$missing_head_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

mismatched_head_report="$critic_dir/mismatched-head-sha.md"
cp "$valid_fail_report" "$mismatched_head_report"
replace_line "$mismatched_head_report" "- Head SHA: $head_sha_1" "- Head SHA: $head_sha_2"
expect_failure "$temp_root/report-mismatched-head-sha.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-report-sha-drift critic-report-sha-drift fresh-session "$mismatched_head_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

malformed_head_report="$critic_dir/malformed-head-sha.md"
cp "$valid_fail_report" "$malformed_head_report"
replace_line "$malformed_head_report" "- Head SHA: $head_sha_1" '- Head SHA: deadbeef'
expect_failure "$temp_root/report-malformed-head-sha.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-report-malformed-sha critic-report-malformed-sha fresh-session "$malformed_head_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

malformed_report="$critic_dir/malformed.md"
cp "$valid_fail_report" "$malformed_report"
awk '
  $0 == "## Guardrail Results" { skip=1; next }
  /^## / && skip { skip=0 }
  !skip { print }
' "$malformed_report" >"$malformed_report.tmp"
mv "$malformed_report.tmp" "$malformed_report"
expect_failure "$temp_root/malformed-report.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-malformed native-subagent "$malformed_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

missing_artifact_report="$critic_dir/missing-artifact.md"
write_critic_report "$missing_artifact_report" fail missing-artifact.txt "$head_sha_1" \
  'No inspectable artifact was available.' \
  'Produce the real artifact before requesting another review.'
expect_failure "$temp_root/missing-artifact.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-missing native-subagent "$missing_artifact_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

escaping_artifact_report="$critic_dir/escaping-artifact.md"
write_critic_report "$escaping_artifact_report" fail ../outside.txt "$head_sha_1" \
  'The claimed evidence escaped the fixture root.' \
  'Inspect a project-root artifact in the next isolated review.'
expect_failure "$temp_root/escaping-artifact.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-escaping native-subagent "$escaping_artifact_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

ln -s artifact.txt "$project/artifact-link.txt"
symlink_artifact_report="$critic_dir/symlink-artifact.md"
write_critic_report "$symlink_artifact_report" fail artifact-link.txt "$head_sha_1" \
  'The claimed evidence was not a regular non-symlink artifact.' \
  'Inspect the real regular file in the next isolated review.'
expect_failure "$temp_root/symlink-artifact.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-symlink native-subagent "$symlink_artifact_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

mismatched_report="$critic_dir/mismatched-verdict.md"
write_critic_report "$mismatched_report" pass artifact.txt "$head_sha_1" \
  'No material gap remains in the inspected unit.' \
  'Advance to integration only after the recorded pass is accepted.'
expect_failure "$temp_root/mismatched-verdict.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-mismatch native-subagent "$mismatched_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

none_gap_report="$critic_dir/none-gap.md"
write_critic_report "$none_gap_report" fail artifact.txt "$head_sha_1" none \
  'Replace the incomplete boundary implementation with the verified design.'
expect_failure "$temp_root/none-gap.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-1 critic-none-gap native-subagent "$none_gap_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

retry_strategy_report="$critic_dir/retry-strategy.md"
write_critic_report "$retry_strategy_report" blocked artifact.txt "$head_sha_1" \
  'The required local verifier is unavailable in the current fixture state.' retry
expect_failure "$temp_root/retry-strategy.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 blocked builder-1 critic-retry-strategy fresh-session "$retry_strategy_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1"

[[ "$(round_file_count "$gauntlet_dir")" == 0 ]] || fail 'rejected critic evidence created round history'

echo '[5/8] preserving failed rounds, PR QA history, bar immutability, and fresh critics'
gauntlet_before_dry_run="$(git hash-object "$gauntlet_file")"
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-1 critic-dry-run native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1" --dry-run >"$temp_root/round-dry-run.log"
[[ "$(round_file_count "$gauntlet_dir")" == 0 ]] || fail 'record-round dry-run created evidence'
[[ "$gauntlet_before_dry_run" == "$(git hash-object "$gauntlet_file")" ]] || fail 'record-round dry-run changed GAUNTLET.md'

run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-1 critic-1 native-subagent "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1" >/dev/null
round_one="$gauntlet_dir/rounds/unit-1/round-001.md"
expect_file "$round_one"
grep -q 'critic-1' "$round_one" || fail 'round evidence omitted the critic identity'
expect_line "- Progress PR: $fixture_pr_url" "$round_one"
expect_line "- Head branch: $fixture_head" "$round_one"
expect_line "- Head SHA: $head_sha_1" "$round_one"
expect_line "- Builder strategy: $builder_strategy_1" "$round_one"
expect_line '- Opened event: .ai/gauntlets/fixture-gauntlet/pr-events/unit-1/event-001.md' \
  "$round_one"
expect_line "- Opened event sha256: $event_one_sha256" "$round_one"
expect_line '- Remediation root: none' "$round_one"
expect_line '- Remediation root sha256: none' "$round_one"
expect_line '- Affected units: none' "$round_one"
expect_line "- Unit manifest fingerprint: $unit_manifest_opened" "$round_one"
grep -Eq '^- Scope fingerprint: [0-9a-f]{64}$' "$round_one" \
  || fail 'round evidence omitted the frozen scope fingerprint'
grep -Eq '^- Builder strategy fingerprint: [0-9a-f]{64}$' "$round_one" \
  || fail 'round evidence omitted the builder strategy fingerprint'
grep -q 'critic-failed' "$gauntlet_file" || fail 'failed verdict did not update the work-unit state'
current_fingerprint_line="$(awk '
  $0 == "## Current State" { active=1; next }
  /^## / && active { exit }
  active && /Quality bar fingerprint:/ { print }
' "$gauntlet_file")"
[[ -n "$current_fingerprint_line" && "$current_fingerprint_line" != *pending* ]] \
  || fail 'first round did not freeze a quality-bar fingerprint'
quality_bar_v1="${current_fingerprint_line#- Quality bar fingerprint: }"
[[ "$quality_bar_v1" == "$quality_bar_opened" ]] \
  || fail 'first critic round changed the quality fingerprint frozen at PR publication'
round_one_hash="$(git hash-object "$round_one")"
round_one_recorded_at="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' "$round_one" | head -n 1)"
[[ -n "$round_one_recorded_at" ]] || fail 'round one omitted its canonical Recorded at value'

printf '# QA helper summary\n\nThe focused fixture checks completed.\n' \
  >"$project/qa-helper-summary.md"
: >"$fake_gh_comment_bodies"
run_for "$project" bash commands/comment-pr-qa-results.sh \
  'https://github.com/example/opencaw-fixture/pull/240' \
  "$project/qa-helper-summary.md" >"$temp_root/task-qa-helper.log"
grep -Fq 'The focused fixture checks completed.' "$fake_gh_comment_bodies" \
  || fail 'Task/Goal-compatible QA helper omitted the legacy summary body'
if grep -Fq 'opencaw-gauntlet-qa:' "$fake_gh_comment_bodies"; then
  fail 'Task/Goal-compatible QA helper emitted Gauntlet metadata without flags'
fi
: >"$fake_gh_comment_bodies"
run_for "$project" bash commands/comment-pr-qa-results.sh \
  'https://github.com/example/opencaw-fixture/pull/241' \
  "$project/qa-helper-summary.md" \
  --gauntlet-verdict fail --head-sha "$head_sha_1" \
  --gauntlet-source '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-001.md' \
  --gauntlet-affected-units none \
  >"$temp_root/gauntlet-qa-helper.log"
round_one_sha256="$(sha256_file "$round_one")"
expect_line "GAUNTLET_SOURCE_SHA256=$round_one_sha256" "$temp_root/gauntlet-qa-helper.log"
grep -Fq -- "<!-- opencaw-gauntlet-qa:v1 verdict=fail head-sha=$head_sha_1 source=.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-001.md source-sha256=$round_one_sha256 affected-units=none -->" \
  "$fake_gh_comment_bodies" \
  || fail 'Gauntlet QA helper omitted or changed the exact semantic marker'
expect_failure "$temp_root/incomplete-gauntlet-qa-helper-flags.log" run_for "$project" \
  bash commands/comment-pr-qa-results.sh \
  'https://github.com/example/opencaw-fixture/pull/242' \
  "$project/qa-helper-summary.md" --gauntlet-verdict fail --head-sha "$head_sha_1"

outside_qa_source_root="$temp_root/outside-qa-source"
mkdir -p "$outside_qa_source_root/unit-1" \
  "$project/.ai/gauntlets/qa-source-symlink"
cp "$round_one" "$outside_qa_source_root/unit-1/round-001.md"
ln -s "$outside_qa_source_root" \
  "$project/.ai/gauntlets/qa-source-symlink/rounds"
: >"$fake_gh_comment_bodies"
expect_failure "$temp_root/qa-helper-intermediate-symlink.log" run_for "$project" \
  bash commands/comment-pr-qa-results.sh \
  'https://github.com/example/opencaw-fixture/pull/243' \
  "$project/qa-helper-summary.md" \
  --gauntlet-verdict fail --head-sha "$head_sha_1" \
  --gauntlet-source \
    '.ai/gauntlets/qa-source-symlink/rounds/unit-1/round-001.md' \
  --gauntlet-affected-units none
grep -Fq 'Gauntlet QA source evidence resolves outside the project .ai directory' \
  "$temp_root/qa-helper-intermediate-symlink.log" \
  || fail 'Gauntlet QA helper did not reject an intermediate source-directory symlink'
[[ ! -s "$fake_gh_comment_bodies" ]] \
  || fail 'Gauntlet QA helper published a comment after source containment failed'

unconsumed_round_report="$critic_dir/unconsumed-round.md"
write_critic_report "$unconsumed_round_report" fail artifact.txt "$head_sha_2" \
  'The first failed critic round has not yet received progress PR QA.' \
  'Wait for QA evidence before beginning the next changed implementation strategy.'
expect_failure "$temp_root/new-round-before-prior-qa.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-unconsumed critic-unconsumed fresh-session "$unconsumed_round_report" \
  --head-sha "$head_sha_2" --builder-strategy "$builder_strategy_2"

expect_failure "$temp_root/qa-pass-for-failed-round.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-10' \
  --head-sha "$head_sha_1"
expect_failure "$temp_root/qa-invalid-evidence-url.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" 'http://example.com/insecure-evidence' --head-sha "$head_sha_1"
expect_failure "$temp_root/qa-arbitrary-https-evidence.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" 'https://example.com/unbound-evidence' --head-sha "$head_sha_1"
expect_failure "$temp_root/qa-different-pr-comment.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" \
  'https://github.com/example/opencaw-fixture/pull/999#issuecomment-10' --head-sha "$head_sha_1"
semantic_source='.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-001.md'
wrong_verdict_comment="$fixture_pr_url#issuecomment-9100"
wrong_verdict_body="$(semantic_comment_body "$project" pass "$head_sha_1" "$semantic_source")"
set_comment_observation "$wrong_verdict_comment" "$fixture_pr_url" "$wrong_verdict_body"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-wrong-verdict.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$wrong_verdict_comment" --head-sha "$head_sha_1"
wrong_head_comment="$fixture_pr_url#issuecomment-9101"
wrong_head_body="$(semantic_comment_body "$project" fail "$head_sha_2" "$semantic_source")"
set_comment_observation "$wrong_head_comment" "$fixture_pr_url" "$wrong_head_body"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-wrong-head.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$wrong_head_comment" --head-sha "$head_sha_1"
unrelated_comment_source='.ai/gauntlets/unrelated-comment-source/rounds/unit-1/round-001.md'
mkdir -p "$project/.ai/gauntlets/unrelated-comment-source/rounds/unit-1"
cp "$round_one" "$project/$unrelated_comment_source"
unrelated_source_comment="$fixture_pr_url#issuecomment-9102"
unrelated_source_body="$(semantic_comment_body "$project" fail "$head_sha_1" \
  "$unrelated_comment_source")"
set_comment_observation "$unrelated_source_comment" "$fixture_pr_url" "$unrelated_source_body"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-unrelated-source.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$unrelated_source_comment" --head-sha "$head_sha_1"
stale_comment="$fixture_pr_url#issuecomment-9103"
stale_comment_body="$(semantic_comment_body "$project" fail "$head_sha_1" "$semantic_source")"
set_comment_observation "$stale_comment" "$fixture_pr_url" "$stale_comment_body" \
  fixture-user User MEMBER 2000-01-01T00:00:00Z
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-stale-created-at.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$stale_comment" --head-sha "$head_sha_1"
edited_comment="$fixture_pr_url#issuecomment-9107"
set_comment_observation "$edited_comment" "$fixture_pr_url" "$stale_comment_body" \
  fixture-user User MEMBER "$round_one_recorded_at" 2099-01-01T00:00:00Z
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-edited-before-record.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$edited_comment" --head-sha "$head_sha_1"
untrusted_author_comment="$fixture_pr_url#issuecomment-9104"
set_comment_observation "$untrusted_author_comment" "$fixture_pr_url" "$stale_comment_body" \
  other-user User MEMBER "$round_one_recorded_at" "$round_one_recorded_at"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-untrusted-author.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$untrusted_author_comment" --head-sha "$head_sha_1"
bot_author_comment="$fixture_pr_url#issuecomment-9105"
set_comment_observation "$bot_author_comment" "$fixture_pr_url" "$stale_comment_body" \
  fixture-user Bot MEMBER "$round_one_recorded_at" "$round_one_recorded_at"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-bot-author.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$bot_author_comment" --head-sha "$head_sha_1"
outsider_comment="$fixture_pr_url#issuecomment-9106"
set_comment_observation "$outsider_comment" "$fixture_pr_url" "$stale_comment_body" \
  fixture-user User NONE "$round_one_recorded_at" "$round_one_recorded_at"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 \
  expect_failure "$temp_root/qa-comment-outsider.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$outsider_comment" --head-sha "$head_sha_1"
qa_fail_missing_comment="$fixture_pr_url#issuecomment-9001"
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/qa-fail-missing-live-comment.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$qa_fail_missing_comment" --head-sha "$head_sha_1"
qa_fail_wrong_pr_comment="$fixture_pr_url#issuecomment-9002"
set_semantic_comment_observation "$project" "$qa_fail_wrong_pr_comment" \
  'https://github.com/example/opencaw-fixture/pull/999' fail "$head_sha_1" \
  '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-001.md'
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/qa-fail-wrong-live-comment-pr.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" "$qa_fail_wrong_pr_comment" --head-sha "$head_sha_1"
expect_failure "$temp_root/qa-head-sha-drift.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-10' \
  --head-sha "$head_sha_2"
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-11' \
  --head-sha "$head_sha_1" >/dev/null
expect_file "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line '- Critic round: .ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-001.md' \
  "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line '- Critic verdict: fail' "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line "- Head SHA: $head_sha_1" "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line '- QA comment author: fixture-user' "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line '- QA comment author type: User' "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line '- QA comment author association: MEMBER' "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line "- QA comment created at: $round_one_recorded_at" \
  "$gauntlet_dir/pr-events/unit-1/event-002.md"
expect_line "- QA comment updated at: $round_one_recorded_at" \
  "$gauntlet_dir/pr-events/unit-1/event-002.md"
grep -Eq '^- QA comment body sha256: [0-9a-f]{64}$' \
  "$gauntlet_dir/pr-events/unit-1/event-002.md" \
  || fail 'QA event omitted the exact live semantic comment-body hash'
qa_fail_evidence="$fixture_pr_url#issuecomment-11"
valid_qa_fail_body="$(semantic_comment_body "$project" fail "$head_sha_1" \
  '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-001.md')"
: >"$fake_gh_api_marker"
FAKE_GH_AUTH_LOGIN='different-current-user' run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready >/dev/null
if awk -F '\t' '$1 == "user" { found=1 } END { exit !found }' "$fake_gh_api_marker"; then
  fail 'QA replay incorrectly rebound durable evidence to the current authenticated user'
fi
set_comment_observation "$qa_fail_evidence" "$fixture_pr_url" \
  "$valid_qa_fail_body edited after recording" fixture-user User MEMBER \
  "$round_one_recorded_at" "$round_one_recorded_at"
expect_failure "$temp_root/qa-comment-body-edited-on-replay.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
set_comment_observation "$qa_fail_evidence" "$fixture_pr_url" "$valid_qa_fail_body" \
  fixture-user User MEMBER "$round_one_recorded_at" 2098-01-01T00:00:00Z
expect_failure "$temp_root/qa-comment-edit-restored-on-replay.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
set_comment_observation "$qa_fail_evidence" "$fixture_pr_url" "$valid_qa_fail_body" \
  fixture-user User MEMBER 2099-01-01T00:00:00Z 2099-01-01T00:00:00Z
expect_failure "$temp_root/qa-comment-postdates-event.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
set_comment_observation "$qa_fail_evidence" "$fixture_pr_url" "$valid_qa_fail_body" \
  fixture-user User MEMBER "$round_one_recorded_at" "$round_one_recorded_at"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready >/dev/null
round_scope_fingerprint="$(sed -nE 's/^- Scope fingerprint: ([0-9a-f]{64})$/\1/p' "$round_one")"
event_scope_fingerprint="$(sed -nE 's/^- Scope fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$gauntlet_dir/pr-events/unit-1/event-002.md")"
[[ -n "$round_scope_fingerprint" && "$round_scope_fingerprint" == "$event_scope_fingerprint" ]] \
  || fail 'round and QA evidence did not retain the same frozen scope fingerprint'

qa_critic_path_dir="$project/.ai/gauntlets/qa-critic-path-traversal"
copy_gauntlet "$gauntlet_dir" "$qa_critic_path_dir"
run_for "$project" bash commands/validate-gauntlet.sh qa-critic-path-traversal --phase ready >/dev/null
replace_line "$qa_critic_path_dir/pr-events/unit-1/event-002.md" \
  '- Critic round: .ai/gauntlets/qa-critic-path-traversal/rounds/unit-1/round-001.md' \
  '- Critic round: .ai/gauntlets/qa-critic-path-traversal/rounds/unit-1/../unit-1/round-001.md'
refresh_copied_evidence_hashes "$qa_critic_path_dir"
expect_failure "$temp_root/qa-critic-path-traversal.log" run_for "$project" \
  bash commands/validate-gauntlet.sh qa-critic-path-traversal --phase ready

round_opened_symlink_dir="$project/.ai/gauntlets/round-opened-symlink"
copy_gauntlet "$gauntlet_dir" "$round_opened_symlink_dir"
outside_round_opened_events="$temp_root/outside-round-opened-events"
mv "$round_opened_symlink_dir/pr-events" "$outside_round_opened_events"
ln -s "$outside_round_opened_events" "$round_opened_symlink_dir/pr-events"
expect_failure "$temp_root/round-opened-symlink.log" run_for "$project" \
  bash commands/validate-gauntlet.sh round-opened-symlink --phase ready
grep -Fq \
  'Gauntlet pr-events evidence tree must be a real directory, not a file or symbolic link' \
  "$temp_root/round-opened-symlink.log" \
  || fail 'round replay did not preflight its opened-event tree before cross-reading it'

round_ledger_path_dir="$project/.ai/gauntlets/round-ledger-path-traversal"
copy_gauntlet "$gauntlet_dir" "$round_ledger_path_dir"
replace_all_literal "$round_ledger_path_dir/GAUNTLET.md" \
  '.ai/gauntlets/round-ledger-path-traversal/rounds/unit-1/round-001.md' \
  '.ai/gauntlets/round-ledger-path-traversal/rounds/unit-1/../unit-1/round-001.md'
expect_failure "$temp_root/round-ledger-path-traversal.log" run_for "$project" \
  bash commands/validate-gauntlet.sh round-ledger-path-traversal --phase ready

progress_ledger_path_dir="$project/.ai/gauntlets/progress-ledger-path-traversal"
copy_gauntlet "$gauntlet_dir" "$progress_ledger_path_dir"
replace_all_literal "$progress_ledger_path_dir/GAUNTLET.md" \
  '.ai/gauntlets/progress-ledger-path-traversal/pr-events/unit-1/event-002.md' \
  '.ai/gauntlets/progress-ledger-path-traversal/pr-events/unit-1/../unit-1/event-002.md'
expect_failure "$temp_root/progress-ledger-path-traversal.log" run_for "$project" \
  bash commands/validate-gauntlet.sh progress-ledger-path-traversal --phase ready

wrong_section_hash_dir="$project/.ai/gauntlets/wrong-section-ledger-hash"
copy_gauntlet "$gauntlet_dir" "$wrong_section_hash_dir"
wrong_section_round_line="$(select_ledger_line "$project" \
  "$wrong_section_hash_dir/GAUNTLET.md" 'Round Ledger' evidence \
  '.ai/gauntlets/wrong-section-ledger-hash/rounds/unit-1/round-001.md')"
replace_line "$wrong_section_hash_dir/GAUNTLET.md" "$wrong_section_round_line" ''
insert_after_matching_line "$wrong_section_hash_dir/GAUNTLET.md" '^## Review Notes$' \
  "$wrong_section_round_line"
expect_failure "$temp_root/wrong-section-ledger-hash.log" run_for "$project" \
  bash commands/validate-gauntlet.sh wrong-section-ledger-hash --phase ready

stale_ledger_hash_dir="$project/.ai/gauntlets/stale-ledger-hash"
copy_gauntlet "$gauntlet_dir" "$stale_ledger_hash_dir"
stale_round_line="$(select_ledger_line "$project" \
  "$stale_ledger_hash_dir/GAUNTLET.md" 'Round Ledger' evidence \
  '.ai/gauntlets/stale-ledger-hash/rounds/unit-1/round-001.md')"
replace_line "$stale_ledger_hash_dir/GAUNTLET.md" "$stale_round_line" \
  "${stale_round_line%sha256:*}sha256: 0000000000000000000000000000000000000000000000000000000000000000"
expect_failure "$temp_root/stale-ledger-hash.log" run_for "$project" \
  bash commands/validate-gauntlet.sh stale-ledger-hash --phase ready

duplicate_round_metadata_dir="$project/.ai/gauntlets/duplicate-round-metadata"
copy_gauntlet "$gauntlet_dir" "$duplicate_round_metadata_dir"
duplicate_round_metadata_file="$duplicate_round_metadata_dir/rounds/unit-1/round-001.md"
insert_after_matching_line "$duplicate_round_metadata_file" '^- Item: unit-1$' \
  '- Item: unit-1'
refresh_copied_evidence_hashes "$duplicate_round_metadata_dir"
expect_failure "$temp_root/duplicate-round-metadata.log" run_for "$project" \
  bash commands/validate-gauntlet.sh duplicate-round-metadata --phase ready
grep -Fq "Round requires exactly one 'Item' field" \
  "$temp_root/duplicate-round-metadata.log" \
  || fail 'round replay accepted duplicate authoritative Item metadata'

duplicate_round_heading_dir="$project/.ai/gauntlets/duplicate-round-heading"
copy_gauntlet "$gauntlet_dir" "$duplicate_round_heading_dir"
duplicate_round_heading_file="$duplicate_round_heading_dir/rounds/unit-1/round-001.md"
printf '\n## Round Metadata\n' >>"$duplicate_round_heading_file"
refresh_copied_evidence_hashes "$duplicate_round_heading_dir"
expect_failure "$temp_root/duplicate-round-heading.log" run_for "$project" \
  bash commands/validate-gauntlet.sh duplicate-round-heading --phase ready
grep -Fq 'Round requires exactly one metadata heading' \
  "$temp_root/duplicate-round-heading.log" \
  || fail 'round replay accepted a duplicate metadata section'

duplicate_round_ledger_dir="$project/.ai/gauntlets/duplicate-round-ledger"
copy_gauntlet "$gauntlet_dir" "$duplicate_round_ledger_dir"
duplicate_round_line="$(select_ledger_line "$project" \
  "$duplicate_round_ledger_dir/GAUNTLET.md" 'Round Ledger' evidence \
  '.ai/gauntlets/duplicate-round-ledger/rounds/unit-1/round-001.md')"
insert_after_section_line "$duplicate_round_ledger_dir/GAUNTLET.md" \
  'Round Ledger' "$duplicate_round_line" "$duplicate_round_line"
expect_failure "$temp_root/duplicate-round-ledger.log" run_for "$project" \
  bash commands/validate-gauntlet.sh duplicate-round-ledger --phase ready

duplicate_progress_ledger_dir="$project/.ai/gauntlets/duplicate-progress-ledger"
copy_gauntlet "$gauntlet_dir" "$duplicate_progress_ledger_dir"
duplicate_progress_line="$(select_ledger_line "$project" \
  "$duplicate_progress_ledger_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/duplicate-progress-ledger/pr-events/unit-1/event-002.md')"
insert_after_section_line "$duplicate_progress_ledger_dir/GAUNTLET.md" \
  'Progress PR Ledger' "$duplicate_progress_line" "$duplicate_progress_line"
expect_failure "$temp_root/duplicate-progress-ledger.log" run_for "$project" \
  bash commands/validate-gauntlet.sh duplicate-progress-ledger --phase ready

unledgered_evidence_dir="$project/.ai/gauntlets/unledgered-round-evidence"
copy_gauntlet "$gauntlet_dir" "$unledgered_evidence_dir"
unledgered_round_line="$(select_ledger_line "$project" \
  "$unledgered_evidence_dir/GAUNTLET.md" 'Round Ledger' evidence \
  '.ai/gauntlets/unledgered-round-evidence/rounds/unit-1/round-001.md')"
replace_line "$unledgered_evidence_dir/GAUNTLET.md" "$unledgered_round_line" ''
expect_failure "$temp_root/unledgered-round-evidence.log" run_for "$project" \
  bash commands/validate-gauntlet.sh unledgered-round-evidence --phase ready

builder_fingerprint_dir="$project/.ai/gauntlets/builder-fingerprint-tamper"
copy_gauntlet "$gauntlet_dir" "$builder_fingerprint_dir"
replace_matching_line "$builder_fingerprint_dir/rounds/unit-1/round-001.md" \
  '^- Builder strategy fingerprint:' \
  '- Builder strategy fingerprint: 0000000000000000000000000000000000000000000000000000000000000000'
refresh_copied_evidence_hashes "$builder_fingerprint_dir"
expect_failure "$temp_root/builder-fingerprint-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh builder-fingerprint-tamper --phase ready

sync_gauntlet_live_observations "$project" "$gauntlet_dir"
expect_failure "$temp_root/merge-after-failed-round.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-12' \
  --head-sha "$head_sha_1" --merge-commit "$head_sha_1"
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
set_remote_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
fixture_open_marker="$(opened_publication_marker \
  "$project" fixture-gauntlet unit-1)"
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_1" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$base_commit_sha" \
  false example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$fixture_open_marker"

changed_fail_report="$critic_dir/changed-fail-round.md"
write_critic_report "$changed_fail_report" fail artifact.txt "$head_sha_2" \
  'The output contract is correct, but its boundary recovery remains incomplete.' \
  'Replace the boundary adapter with deterministic validation and add a recovery assertion.'

replace_line "$gauntlet_file" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Mutated quality contract that was not re-approved.'
expect_failure "$temp_root/changed-bar-validation.log" run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
expect_failure "$temp_root/changed-bar-record.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-2 critic-bar-drift fresh-session "$changed_fail_report" \
  --head-sha "$head_sha_2" --builder-strategy "$builder_strategy_2"
replace_line "$gauntlet_file" \
  '- Benchmark: Mutated quality contract that was not re-approved.' \
  '- Benchmark: Local artifact quality contract version 1.'

expect_failure "$temp_root/reused-critic.log" run_for "$project" bash commands/record-gauntlet-round.sh \
  fixture-gauntlet unit-1 fail builder-2 critic-1 fresh-session "$changed_fail_report" \
  --head-sha "$head_sha_2" --builder-strategy "$builder_strategy_2"
expect_failure "$temp_root/prior-critic-reused-as-builder.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  critic-1 globally-fresh-critic fresh-session "$changed_fail_report" \
  --head-sha "$head_sha_2" --builder-strategy "$builder_strategy_2"
expect_failure "$temp_root/missing-builder-strategy-after-critic-fail.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-missing-after-fail critic-missing-after-fail fresh-session "$changed_fail_report" \
  --head-sha "$head_sha_2"
expect_failure "$temp_root/repeated-builder-strategy-after-critic-fail.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-repeat-after-fail critic-repeat-after-fail fresh-session "$changed_fail_report" \
  --head-sha "$head_sha_2" --builder-strategy "$builder_strategy_1"

run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 fail \
  builder-2 critic-2 fresh-session "$changed_fail_report" \
  --head-sha "$head_sha_2" --builder-strategy "$builder_strategy_2" >/dev/null
round_two="$gauntlet_dir/rounds/unit-1/round-002.md"
expect_file "$round_two"
expect_line '- Remediation root: .ai/gauntlets/fixture-gauntlet/pr-events/unit-1/event-002.md' \
  "$round_two"
round_two_recorded_at="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$round_two" | head -n 1)"
qa_one_recorded_at="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$gauntlet_dir/pr-events/unit-1/event-002.md" | head -n 1)"
[[ "$round_one_recorded_at" == "$qa_one_recorded_at" \
  && "$qa_one_recorded_at" == "$round_two_recorded_at" ]] \
  || fail 'same-second round replay fixture did not retain its intended timestamp tie'
round_one_ledger="$(select_ledger_line "$project" "$gauntlet_file" \
  'Round Ledger' evidence \
  '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-001.md')"
round_two_ledger="$(select_ledger_line "$project" "$gauntlet_file" \
  'Round Ledger' evidence \
  '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-002.md')"
replace_line "$gauntlet_file" "$round_one_ledger" '__ROUND_ONE_LEDGER__'
replace_line "$gauntlet_file" "$round_two_ledger" "$round_one_ledger"
replace_line "$gauntlet_file" '__ROUND_ONE_LEDGER__' "$round_two_ledger"
expect_failure "$temp_root/same-second-round-ledger-reorder.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
replace_line "$gauntlet_file" "$round_one_ledger" '__ROUND_TWO_LEDGER__'
replace_line "$gauntlet_file" "$round_two_ledger" "$round_one_ledger"
replace_line "$gauntlet_file" '__ROUND_TWO_LEDGER__' "$round_two_ledger"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready >/dev/null

strict_quality_root_dir="$project/.ai/gauntlets/strict-quality-root-tie"
copy_gauntlet "$ready_snapshot" "$strict_quality_root_dir"
mkdir -p "$strict_quality_root_dir/rounds/unit-1"
cp "$round_two" "$strict_quality_root_dir/rounds/unit-1/round-002.md"
replace_all_literal "$strict_quality_root_dir/rounds/unit-1/round-002.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/strict-quality-root-tie/'
strict_quality_time='2026-08-02T00:00:01Z'
replace_matching_line "$strict_quality_root_dir/rounds/unit-1/round-002.md" \
  '^- Recorded at:' "- Recorded at: $strict_quality_time"
strict_quality_revision="- Quality bar revision: strict-tie-v2 | approved by: fixture-user-v2 | approved at: $strict_quality_time | supersedes: $quality_bar_opened | reason: Prove that an equal-second cross-ledger failure has no implicit order before approval."
insert_after_matching_line "$strict_quality_root_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$strict_quality_revision"
strict_quality_root="$(gauntlet_helper_value "$project" \
  gauntlet_remediation_root_for_trigger "$strict_quality_root_dir/GAUNTLET.md" \
  unit-1 quality-revision:strict-tie-v2)"
[[ "$strict_quality_root" == none ]] \
  || fail 'equal-second non-PR failure implicitly preceded a quality revision'
strict_quality_later_revision="${strict_quality_revision/approved at: $strict_quality_time/approved at: 2026-08-02T00:00:02Z}"
replace_line "$strict_quality_root_dir/GAUNTLET.md" "$strict_quality_revision" \
  "$strict_quality_later_revision"
strict_quality_root="$(gauntlet_helper_value "$project" \
  gauntlet_remediation_root_for_trigger "$strict_quality_root_dir/GAUNTLET.md" \
  unit-1 quality-revision:strict-tie-v2)"
[[ "$strict_quality_root" \
    == '.ai/gauntlets/strict-quality-root-tie/rounds/unit-1/round-002.md' ]] \
  || fail 'strictly earlier non-PR failure was not retained as a quality revision root'
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/reused-live-comment-for-later-round-qa.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" \
  'https://github.com/example/opencaw-fixture/pull/201#issuecomment-11' \
  --head-sha "$head_sha_2"
grep -Fq 'QA comment evidence has already been consumed by a progress event' \
  "$temp_root/reused-live-comment-for-later-round-qa.log" \
  || fail 'reused QA comment was not rejected by the uniqueness invariant'
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-13' \
  --head-sha "$head_sha_2" >/dev/null
expect_file "$gauntlet_dir/pr-events/unit-1/event-003.md"

pass_report="$critic_dir/pass-round.md"
write_critic_report "$pass_report" pass artifact.txt "$head_sha_3" \
  'No remaining unit-level gap was found against the approved bar.' \
  'Advance the passed unit to a fresh integration review.'
non_ff_round_report="$critic_dir/non-fast-forward-round.md"
write_critic_report "$non_ff_round_report" pass artifact.txt "$orphan_sha" \
  'The observed work branch was force-moved outside its prior reviewed ancestry.' \
  'Restore a strict fast-forward descendant and request another isolated critic.'
expect_failure "$temp_root/non-fast-forward-same-pr-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  non-ff-builder non-ff-critic native-subagent "$non_ff_round_report" \
  --head-sha "$orphan_sha" --builder-strategy "$builder_strategy_3"
expect_failure "$temp_root/nonadjacent-builder-strategy-reuse.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-nonadjacent-reuse critic-nonadjacent-reuse native-subagent "$pass_report" \
  --head-sha "$head_sha_3" --builder-strategy "$builder_strategy_1"
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-3 critic-3 native-subagent "$pass_report" \
  --head-sha "$head_sha_3" --builder-strategy "$builder_strategy_3" >/dev/null
round_three="$gauntlet_dir/rounds/unit-1/round-003.md"
expect_file "$round_three"
nonadjacent_strategy_replay_dir="$project/.ai/gauntlets/nonadjacent-strategy-replay"
copy_gauntlet "$gauntlet_dir" "$nonadjacent_strategy_replay_dir"
builder_strategy_1_fingerprint="$(gauntlet_helper_value "$project" \
  gauntlet_strategy_fingerprint "$builder_strategy_1")"
replace_line "$nonadjacent_strategy_replay_dir/rounds/unit-1/round-003.md" \
  "- Builder strategy: $builder_strategy_3" \
  "- Builder strategy: $builder_strategy_1"
replace_matching_line "$nonadjacent_strategy_replay_dir/rounds/unit-1/round-003.md" \
  '^- Builder strategy fingerprint:' \
  "- Builder strategy fingerprint: $builder_strategy_1_fingerprint"
refresh_copied_evidence_hashes "$nonadjacent_strategy_replay_dir"
expect_failure "$temp_root/nonadjacent-strategy-replay.log" run_for "$project" \
  bash commands/validate-gauntlet.sh nonadjacent-strategy-replay --phase ready
sync_gauntlet_live_observations "$project" "$gauntlet_dir"
qa_pass_missing_comment="$fixture_pr_url#issuecomment-9003"
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/qa-pass-missing-live-comment.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$fixture_pr_url" "$fixture_head" "$qa_pass_missing_comment" --head-sha "$head_sha_3"
qa_pass_wrong_pr_comment="$fixture_pr_url#issuecomment-9004"
set_semantic_comment_observation "$project" "$qa_pass_wrong_pr_comment" \
  'https://github.com/example/opencaw-fixture/pull/998' pass "$head_sha_3" \
  '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-003.md'
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/qa-pass-wrong-live-comment-pr.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$fixture_pr_url" "$fixture_head" "$qa_pass_wrong_pr_comment" --head-sha "$head_sha_3"
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-14' \
  --head-sha "$head_sha_3" >/dev/null
expect_file "$gauntlet_dir/pr-events/unit-1/event-004.md"
expect_line '- Critic round: .ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-003.md' \
  "$gauntlet_dir/pr-events/unit-1/event-004.md"
expect_line '- Critic verdict: pass' "$gauntlet_dir/pr-events/unit-1/event-004.md"
grep -Eq '^- \[[ x]\] unit-1 \| status: critic-failed \|' "$gauntlet_file" \
  || fail 'independent PR QA failure did not invalidate a critic pass'
expect_failure "$temp_root/qa-pass-without-new-critic.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-15' \
  --head-sha "$head_sha_3"
qa_remediation_report="$critic_dir/qa-remediation-pass.md"
write_critic_report "$qa_remediation_report" pass artifact.txt "$head_sha_4" \
  'The independently detected QA regression is corrected on the changed artifact commit.' \
  'Advance the newly verified artifact through PR QA before human merge.'
expect_failure "$temp_root/missing-builder-strategy-after-qa-fail.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-missing-after-qa critic-missing-after-qa fresh-session "$qa_remediation_report" \
  --head-sha "$head_sha_4"
expect_failure "$temp_root/repeated-builder-strategy-after-qa-fail.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-repeat-after-qa critic-repeat-after-qa fresh-session "$qa_remediation_report" \
  --head-sha "$head_sha_4" --builder-strategy "$builder_strategy_3"
expect_failure "$temp_root/repeated-head-sha-after-qa-fail.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-repeat-sha-after-qa critic-repeat-sha-after-qa fresh-session "$pass_report" \
  --head-sha "$head_sha_3" --builder-strategy "$builder_strategy_4"
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-qa-remediation critic-qa-remediation fresh-session "$qa_remediation_report" \
  --head-sha "$head_sha_4" --builder-strategy "$builder_strategy_4" >/dev/null
round_four="$gauntlet_dir/rounds/unit-1/round-004.md"
expect_file "$round_four"
expect_line "- Progress PR: $fixture_pr_url" "$round_four"
expect_line "- Head branch: $fixture_head" "$round_four"
expect_line "- Head SHA: $head_sha_4" "$round_four"
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-16' \
  --head-sha "$head_sha_4" >/dev/null
expect_file "$gauntlet_dir/pr-events/unit-1/event-005.md"
after_qa_pass_report="$critic_dir/after-qa-pass.md"
write_critic_report "$after_qa_pass_report" pass artifact.txt "$head_sha_5" \
  'The QA-passed unit is already terminal for this live progress PR.' \
  'Await human merge instead of recording an unreviewed additional round.'
expect_failure "$temp_root/new-round-after-qa-pass.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-after-qa-pass critic-after-qa-pass fresh-session "$after_qa_pass_report" \
  --head-sha "$head_sha_5" --builder-strategy "$builder_strategy_5"
expect_failure "$temp_root/merge-without-commit.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-17' \
  --head-sha "$head_sha_4"
expect_failure "$temp_root/merge-short-commit.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-18' \
  --head-sha "$head_sha_4" --merge-commit deadbeef
expect_failure "$temp_root/merge-head-sha-drift.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-18' \
  --head-sha "$head_sha_3" --merge-commit "$head_sha_4"
premerge_event_count="$(pr_event_file_count "$gauntlet_dir")"
premerge_gauntlet_hash="$(git hash-object "$gauntlet_file")"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_4"
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:28:00Z human-reviewer \
  "$head_sha_4" false "$head_sha_1"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure "$temp_root/unrecorded-target-before-merge.log" \
  run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" \
  'https://github.com/example/opencaw-fixture/pull/201#issuecomment-18' \
  --head-sha "$head_sha_4" --merge-commit "$head_sha_4"
[[ "$premerge_event_count" == "$(pr_event_file_count "$gauntlet_dir")" \
  && "$premerge_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" ]] \
  || fail 'unrecorded target-base commit before merge mutated progress evidence'
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_4"
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:29:00Z merge-bot \
  "$head_sha_4" true "$base_commit_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure "$temp_root/merge-by-bot.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" \
  'https://github.com/example/opencaw-fixture/pull/201#issuecomment-18' \
  --head-sha "$head_sha_4" --merge-commit "$head_sha_4"
for forbidden_actor_type in App Mannequin none; do
  forbidden_actor_login=human-reviewer
  [[ "$forbidden_actor_type" != none ]] || forbidden_actor_login=none
  set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
  set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
    gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:29:00Z human-reviewer \
    "$head_sha_4" false "$base_commit_sha"
  set_pr_actor_observation "$fixture_pr_url" "$forbidden_actor_type" \
    "$forbidden_actor_login"
  OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
    "$temp_root/merge-by-${forbidden_actor_type,,}.log" run_for "$project" \
    bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
    "$fixture_pr_url" "$fixture_head" \
    'https://github.com/example/opencaw-fixture/pull/201#issuecomment-18' \
    --head-sha "$head_sha_4" --merge-commit "$head_sha_4"
done
for forbidden_merge_automation_event in \
  AutoMergeEnabledEvent AutoRebaseEnabledEvent AutoSquashEnabledEvent \
  AddedToMergeQueueEvent; do
  set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
  set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
    gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:29:00Z human-reviewer \
    "$head_sha_4" false "$base_commit_sha"
  set_pr_merge_automation_observation "$fixture_pr_url" \
    "$forbidden_merge_automation_event"
  OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
    "$temp_root/merge-automation-${forbidden_merge_automation_event}.log" \
    run_for "$project" bash commands/record-gauntlet-pr-event.sh \
    fixture-gauntlet unit-1 merged "$fixture_pr_url" "$fixture_head" \
    'https://github.com/example/opencaw-fixture/pull/201#issuecomment-18' \
    --head-sha "$head_sha_4" --merge-commit "$head_sha_4"
  grep -Fq 'Gauntlet PR must never enable auto-merge or enter a merge queue' \
    "$temp_root/merge-automation-${forbidden_merge_automation_event}.log" \
    || fail "merged PR accepted forbidden automation history: $forbidden_merge_automation_event"
  [[ "$premerge_event_count" == "$(pr_event_file_count "$gauntlet_dir")" \
    && "$premerge_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" ]] \
    || fail "merge automation rejection mutated progress evidence: $forbidden_merge_automation_event"
done
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:29:00Z human-reviewer \
  "$head_sha_4" false "$base_commit_sha"
set_pr_actor_observation "$fixture_pr_url" User different-reviewer
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/merge-actor-login-mismatch.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" \
  'https://github.com/example/opencaw-fixture/pull/201#issuecomment-18' \
  --head-sha "$head_sha_4" --merge-commit "$head_sha_4"
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
premerge_integration_report="$critic_dir/premerge-integration.md"
write_critic_report "$premerge_integration_report" pass artifact.txt "$head_sha_5" \
  'The integration review cannot be accepted before the unit PR is human-merged.' \
  'Wait for the merge and inspect the resulting durable integration branch commit.'
expect_failure "$temp_root/integration-before-human-merge.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  premerge-builder premerge-critic fresh-session "$premerge_integration_report" \
  --head-sha "$head_sha_5" --builder-strategy "$integration_strategy_1"
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
set_remote_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$fixture_pr_url" "$fixture_head" 'https://github.com/example/opencaw-fixture/pull/201#issuecomment-19' \
  --head-sha "$head_sha_4" --merge-commit "$head_sha_4" >/dev/null
expect_file "$gauntlet_dir/pr-events/unit-1/event-006.md"
expect_line '- Event: merged' "$gauntlet_dir/pr-events/unit-1/event-006.md"
expect_line "- Head SHA: $head_sha_4" "$gauntlet_dir/pr-events/unit-1/event-006.md"
expect_line "- Target base SHA: $base_commit_sha" \
  "$gauntlet_dir/pr-events/unit-1/event-006.md"
expect_line "- Merge commit: $head_sha_4" \
  "$gauntlet_dir/pr-events/unit-1/event-006.md"
expect_line '- Merged by: human-reviewer' "$gauntlet_dir/pr-events/unit-1/event-006.md"
expect_line '- Merged by type: User' "$gauntlet_dir/pr-events/unit-1/event-006.md"
expect_line '- Merged by bot: false' "$gauntlet_dir/pr-events/unit-1/event-006.md"
[[ "$event_one_hash" == "$(git hash-object "$event_one")" ]] \
  || fail 'later PR events overwrote immutable event-001 evidence'
[[ "$(pr_event_file_count "$gauntlet_dir")" == 6 ]] \
  || fail 'valid PR lifecycle events were not auto-incremented immutably'
set_pr_merge_automation_observation "$fixture_pr_url" AutoMergeEnabledEvent
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/merged-auto-merge-history-replay.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready
grep -Fq 'Gauntlet PR must never enable auto-merge or enter a merge queue' \
  "$temp_root/merged-auto-merge-history-replay.log" \
  || fail 'validator replay accepted forbidden merge automation history'
set_pr_merge_automation_observation "$fixture_pr_url" none
[[ "$round_one_hash" == "$(git hash-object "$round_one")" ]] || fail 'later recording overwrote immutable round-001 evidence'
[[ "$(find "$gauntlet_dir/rounds/unit-1" -type f -name 'round-*.md' | wc -l | tr -d ' ')" == 4 ]] \
  || fail 'failed invocations consumed round numbers or valid rounds were lost'
grep -Eq '^- \[[ x]\] unit-1 \| status: passed \|' "$gauntlet_file" || fail 'passing verdict did not mark the work unit passed'

scope_mutation_dir="$project/.ai/gauntlets/scope-mutation"
copy_gauntlet "$gauntlet_dir" "$scope_mutation_dir"
replace_matching_line "$scope_mutation_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: passed | title: Complete the inspectable fixture artifact | scope: changed artifact boundary that was never re-reviewed'
expect_failure "$temp_root/scope-mutation-invalidates-evidence.log" run_for "$project" \
  bash commands/validate-gauntlet.sh scope-mutation --phase ready

bot_merge_tamper_dir="$project/.ai/gauntlets/bot-merge-tamper"
copy_gauntlet "$gauntlet_dir" "$bot_merge_tamper_dir"
replace_line "$bot_merge_tamper_dir/pr-events/unit-1/event-006.md" \
  '- Merged by bot: false' '- Merged by bot: true'
refresh_copied_evidence_hashes "$bot_merge_tamper_dir"
expect_failure "$temp_root/bot-merge-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh bot-merge-tamper --phase ready

actor_type_tamper_dir="$project/.ai/gauntlets/actor-type-tamper"
copy_gauntlet "$gauntlet_dir" "$actor_type_tamper_dir"
replace_line "$actor_type_tamper_dir/pr-events/unit-1/event-006.md" \
  '- Merged by type: User' '- Merged by type: App'
refresh_copied_evidence_hashes "$actor_type_tamper_dir"
expect_failure "$temp_root/actor-type-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh actor-type-tamper --phase ready

target_base_tamper_dir="$project/.ai/gauntlets/target-base-tamper"
copy_gauntlet "$gauntlet_dir" "$target_base_tamper_dir"
replace_line "$target_base_tamper_dir/pr-events/unit-1/event-006.md" \
  "- Target base SHA: $base_commit_sha" "- Target base SHA: $head_sha_1"
refresh_copied_evidence_hashes "$target_base_tamper_dir"
expect_failure "$temp_root/target-base-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh target-base-tamper --phase ready

reapproval_dir="$project/.ai/gauntlets/reapproved-bar"
copy_gauntlet "$gauntlet_dir" "$reapproval_dir"
reapproval_execution_contract="$(sed -nE \
  's/^- Execution contract fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$reapproval_dir/GAUNTLET.md" | head -n 1)"
export FAKE_DATE_ISO='2026-08-01T12:00:01Z'
revision_timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
replace_all_literal "$reapproval_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/reapproved-bar/'
replace_line "$reapproval_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Local artifact quality contract version 2 with explicit recovery behavior.'
replace_line "$reapproval_dir/GAUNTLET.md" '- Approved by: fixture-user' '- Approved by: fixture-user-v2'
replace_line "$reapproval_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:00Z' "- Approved at: $revision_timestamp"
replace_line "$reapproval_dir/GAUNTLET.md" \
  "- Quality bar fingerprint: $quality_bar_v1" '- Quality bar fingerprint: pending'
replace_matching_line "$reapproval_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: critic-failed | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
insert_after_matching_line "$reapproval_dir/GAUNTLET.md" '^- Unit manifest approval:' \
  "- Quality bar revision: recovery-v2 | approved by: fixture-user-v2 | approved at: $revision_timestamp | supersedes: $quality_bar_v1 | reason: Add explicit recovery behavior after reviewing retained round evidence."
run_for "$project" bash commands/validate-gauntlet.sh reapproved-bar --phase ready >/dev/null
[[ "$reapproval_execution_contract" == "$(sed -nE \
  's/^- Execution contract fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$reapproval_dir/GAUNTLET.md" | head -n 1)" ]] \
  || fail 'approved quality-bar revision changed the separately frozen execution contract'
expect_failure "$temp_root/reapproval-old-passes.log" run_for "$project" \
  bash commands/validate-gauntlet.sh reapproved-bar --phase complete

export FAKE_DATE_ISO='2026-08-01T12:00:02Z'

reapproval_old_round_hash="$(git hash-object "$reapproval_dir/rounds/unit-1/round-001.md")"
reapproval_unit_report="$critic_dir/reapproval-unit-pass.md"
write_critic_report "$reapproval_unit_report" pass artifact.txt "$head_sha_5" \
  'The artifact now satisfies every criterion in the explicitly reapproved quality bar.' \
  'Advance the revised artifact to a new independent integration review.'
reapproval_pr_url='https://github.com/example/opencaw-fixture/pull/206'
reapproval_head='gauntlet-work/reapproved-bar/unit-1-remediation-1'
set_local_ref "$project" "$reapproval_head" "$head_sha_5"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  reapproved-bar unit-1 "$project/progress-validation.md" >/dev/null
malformed_quality_trigger_dir="$project/.ai/gauntlets/malformed-quality-trigger"
copy_gauntlet "$reapproval_dir" "$malformed_quality_trigger_dir"
malformed_quality_checkpoint="$(find \
  "$malformed_quality_trigger_dir/publication-checkpoints/unit-1" \
  -maxdepth 1 -type f -name 'checkpoint-*.md' -print | LC_ALL=C sort | tail -n 1)"
expect_file "$malformed_quality_checkpoint"
replace_line "$malformed_quality_checkpoint" \
  '- Remediation trigger: quality-revision:recovery-v2' \
  '- Remediation trigger: quality-revision:recovery-v.*'
expect_failure "$temp_root/malformed-quality-trigger.log" run_for "$project" \
  bash commands/validate-gauntlet.sh malformed-quality-trigger --phase ready
grep -Fq 'Quality revision trigger is not canonical: quality-revision:recovery-v.*' \
  "$temp_root/malformed-quality-trigger.log" \
  || fail 'checkpoint remediation accepted a regex-aliased quality revision id'
# copy_gauntlet synchronizes the clone's fake GitHub observations so the clone
# can be replayed. Restore the source observations before resuming its lifecycle;
# both fixtures intentionally retain the same immutable external comment URLs.
sync_gauntlet_live_observations "$project" "$reapproval_dir"
run_for "$project" bash commands/record-gauntlet-pr-event.sh reapproved-bar unit-1 opened \
  "$reapproval_pr_url" "$reapproval_head" none --head-sha "$head_sha_5" >/dev/null
run_for "$project" bash commands/record-gauntlet-round.sh reapproved-bar unit-1 pass \
  reapproval-builder-1 reapproval-critic-1 fresh-session "$reapproval_unit_report" \
  --head-sha "$head_sha_5" --builder-strategy "$builder_strategy_5" >/dev/null
expect_file "$reapproval_dir/rounds/unit-1/round-005.md"
expect_line "- Execution contract fingerprint: $reapproval_execution_contract" \
  "$reapproval_dir/rounds/unit-1/round-005.md"
[[ "$reapproval_old_round_hash" == "$(git hash-object "$reapproval_dir/rounds/unit-1/round-001.md")" ]] \
  || fail 'quality-bar reapproval changed retained historical evidence'
run_for "$project" bash commands/record-gauntlet-pr-event.sh reapproved-bar unit-1 qa-pass \
  "$reapproval_pr_url" "$reapproval_head" \
  'https://github.com/example/opencaw-fixture/pull/206#issuecomment-20' --head-sha "$head_sha_5" >/dev/null
reapproval_premerge_count="$(pr_event_file_count "$reapproval_dir")"
reapproval_premerge_hash="$(git hash-object "$reapproval_dir/GAUNTLET.md")"
set_local_ref "$project" gauntlet/reapproved-bar "$head_sha_6"
set_pr_observation "$reapproval_pr_url" "$reapproval_head" "$head_sha_5" \
  gauntlet/reapproved-bar MERGED false 2026-08-01T12:29:30Z human-reviewer \
  "$head_sha_6" false "$head_sha_5"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/unrecorded-target-between-merges.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh reapproved-bar unit-1 merged \
  "$reapproval_pr_url" "$reapproval_head" \
  'https://github.com/example/opencaw-fixture/pull/206#issuecomment-21' \
  --head-sha "$head_sha_5" --merge-commit "$head_sha_6"
[[ "$reapproval_premerge_count" == "$(pr_event_file_count "$reapproval_dir")" \
  && "$reapproval_premerge_hash" == "$(git hash-object "$reapproval_dir/GAUNTLET.md")" ]] \
  || fail 'unrecorded target-base commit between merges mutated progress evidence'
set_local_ref "$project" gauntlet/reapproved-bar "$head_sha_4"
run_for "$project" bash commands/record-gauntlet-pr-event.sh reapproved-bar unit-1 merged \
  "$reapproval_pr_url" "$reapproval_head" \
  'https://github.com/example/opencaw-fixture/pull/206#issuecomment-21' \
  --head-sha "$head_sha_5" --merge-commit "$head_sha_5" >/dev/null
expect_line "- Target base SHA: $head_sha_4" \
  "$reapproval_dir/pr-events/unit-1/event-009.md"
expect_line '- Merged by bot: false' "$reapproval_dir/pr-events/unit-1/event-009.md"

reapproval_integration_report="$critic_dir/reapproval-integration-pass.md"
write_critic_report "$reapproval_integration_report" pass artifact.txt "$head_sha_5" \
  'The complete revised artifact passes the newly approved integration bar.' \
  'Generate the revised completion report and retain all earlier round history.'
run_for "$project" bash commands/record-gauntlet-round.sh reapproved-bar integration pass \
  reapproval-integration-builder reapproval-integration-critic native-subagent "$reapproval_integration_report" \
  --head-sha "$head_sha_5" --builder-strategy "$integration_strategy_1" >/dev/null
expect_file "$reapproval_dir/rounds/integration/round-001.md"
expect_line "- Execution contract fingerprint: $reapproval_execution_contract" \
  "$reapproval_dir/rounds/integration/round-001.md"

quality_bar_v2="$(sed -nE \
  's/^- Quality bar fingerprint: ([0-9a-f]{64})$/\1/p' \
  "$reapproval_dir/GAUNTLET.md" | head -n 1)"
quality_v3_dir="$project/.ai/gauntlets/quality-v3-chain"
copy_gauntlet "$reapproval_dir" "$quality_v3_dir"
export FAKE_DATE_ISO='2026-08-01T12:00:03Z'
replace_line "$quality_v3_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 2 with explicit recovery behavior.' \
  '- Benchmark: Local artifact quality contract version 3 with hardened recovery behavior.'
replace_line "$quality_v3_dir/GAUNTLET.md" '- Approved by: fixture-user-v2' \
  '- Approved by: fixture-user-v3'
replace_line "$quality_v3_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:01Z' \
  '- Approved at: 2026-08-01T12:00:03Z'
set_gauntlet_field "$project" "$quality_v3_dir/GAUNTLET.md" \
  'Current State' 'Quality bar fingerprint' pending
set_gauntlet_field "$project" "$quality_v3_dir/GAUNTLET.md" \
  'Current State' 'Active work unit' unit-1
set_gauntlet_field "$project" "$quality_v3_dir/GAUNTLET.md" \
  'Flow and Status' 'Status' running
set_gauntlet_field "$project" "$quality_v3_dir/GAUNTLET.md" \
  'Delivery' 'PR eligible' no
reset_integration_review "$project" "$quality_v3_dir/GAUNTLET.md"
replace_matching_line "$quality_v3_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: pending | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
quality_v3_revision="- Quality bar revision: recovery-v3 | approved by: fixture-user-v3 | approved at: 2026-08-01T12:00:03Z | supersedes: $quality_bar_v2 | reason: Harden the immediate prior recovery bar after retaining its full evidence chain."
insert_after_matching_line "$quality_v3_dir/GAUNTLET.md" \
  '^- Quality bar revision: recovery-v2 ' "$quality_v3_revision"
run_for "$project" bash commands/validate-gauntlet.sh quality-v3-chain --phase ready >/dev/null
expect_line '- Remediation trigger: quality-revision:recovery-v2' \
  "$quality_v3_dir/pr-events/unit-1/event-007.md"
quality_v2_consumer_time="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$quality_v3_dir/pr-events/unit-1/event-007.md" | head -n 1)"
[[ "$quality_v2_consumer_time" < '2026-08-01T12:00:03Z' ]] \
  || fail 'later quality revision was not strictly chronological after its prior consumer'

quality_v3_skipped_parent_dir="$project/.ai/gauntlets/quality-v3-skipped-parent"
copy_gauntlet "$quality_v3_dir" "$quality_v3_skipped_parent_dir"
replace_all_literal "$quality_v3_skipped_parent_dir/GAUNTLET.md" \
  "supersedes: $quality_bar_v2" "supersedes: $quality_bar_v1"
expect_failure "$temp_root/quality-v3-skipped-parent.log" run_for "$project" \
  bash commands/validate-gauntlet.sh quality-v3-skipped-parent --phase ready

quality_v3_equal_approval_dir="$project/.ai/gauntlets/quality-v3-equal-approval"
copy_gauntlet "$quality_v3_dir" "$quality_v3_equal_approval_dir"
replace_all_literal "$quality_v3_equal_approval_dir/GAUNTLET.md" \
  'approved at: 2026-08-01T12:00:03Z' \
  'approved at: 2026-08-01T12:00:01Z'
expect_failure "$temp_root/quality-v3-equal-approval.log" run_for "$project" \
  bash commands/validate-gauntlet.sh quality-v3-equal-approval --phase ready

quality_v3_misordered_dir="$project/.ai/gauntlets/quality-v3-misordered"
copy_gauntlet "$quality_v3_dir" "$quality_v3_misordered_dir"
quality_v2_revision_line="$(grep -F -- '- Quality bar revision: recovery-v2 ' \
  "$quality_v3_misordered_dir/GAUNTLET.md")"
quality_v3_revision_line="$(grep -F -- '- Quality bar revision: recovery-v3 ' \
  "$quality_v3_misordered_dir/GAUNTLET.md")"
replace_line "$quality_v3_misordered_dir/GAUNTLET.md" \
  "$quality_v2_revision_line" '__QUALITY_V2_REVISION__'
replace_line "$quality_v3_misordered_dir/GAUNTLET.md" \
  "$quality_v3_revision_line" "$quality_v2_revision_line"
replace_line "$quality_v3_misordered_dir/GAUNTLET.md" \
  '__QUALITY_V2_REVISION__' "$quality_v3_revision_line"
expect_failure "$temp_root/quality-v3-misordered.log" run_for "$project" \
  bash commands/validate-gauntlet.sh quality-v3-misordered --phase ready

sync_gauntlet_live_observations "$project" "$quality_v3_dir"
quality_v3_head='gauntlet-work/quality-v3-chain/unit-1-remediation-2'
set_local_ref "$project" "$quality_v3_head" "$head_sha_6"
set_remote_ref "$project" "$quality_v3_head" absent
quality_v3_readiness="$(run_for "$project" bash commands/pr-readiness-check.sh \
  --gauntlet-progress quality-v3-chain unit-1 "$project/progress-validation.md")"
quality_v3_checkpoint="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$quality_v3_readiness")"
expect_line '- Remediation trigger: quality-revision:recovery-v3' \
  "$project/$quality_v3_checkpoint"
grep -Eq '^- Remediation trigger sha256: [0-9a-f]{64}$' \
  "$project/$quality_v3_checkpoint" \
  || fail 'latest quality revision checkpoint omitted its hash-bound trigger'
unset FAKE_DATE_ISO

topology_order_dir="$project/.ai/gauntlets/topology-ledger-order"
copy_gauntlet "$reapproval_dir" "$topology_order_dir"
topology_first_merge_line="$(select_ledger_line "$project" \
  "$topology_order_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/topology-ledger-order/pr-events/unit-1/event-006.md')"
topology_second_merge_line="$(select_ledger_line "$project" \
  "$topology_order_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/topology-ledger-order/pr-events/unit-1/event-009.md')"
replace_line "$topology_order_dir/GAUNTLET.md" "$topology_first_merge_line" \
  '__TOPOLOGY_FIRST_MERGE__'
replace_line "$topology_order_dir/GAUNTLET.md" "$topology_second_merge_line" \
  "$topology_first_merge_line"
replace_line "$topology_order_dir/GAUNTLET.md" '__TOPOLOGY_FIRST_MERGE__' \
  "$topology_second_merge_line"
run_for "$project" bash commands/validate-gauntlet.sh topology-ledger-order --phase ready >/dev/null

unconsumed_close_dir="$project/.ai/gauntlets/unconsumed-close"
copy_gauntlet "$ready_snapshot" "$unconsumed_close_dir"
unconsumed_close_url='https://github.com/example/opencaw-fixture/pull/215'
unconsumed_close_head='gauntlet-work/unconsumed-close/unit-1'
run_for "$project" bash commands/record-gauntlet-pr-event.sh unconsumed-close unit-1 opened \
  "$unconsumed_close_url" "$unconsumed_close_head" none --head-sha "$head_sha_1" >/dev/null
run_for "$project" bash commands/record-gauntlet-round.sh unconsumed-close unit-1 fail \
  unconsumed-close-builder unconsumed-close-critic fresh-session "$valid_fail_report" \
  --head-sha "$head_sha_1" --builder-strategy "$builder_strategy_1" >/dev/null
expect_failure "$temp_root/close-with-unconsumed-critic-round.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh unconsumed-close unit-1 closed \
  "$unconsumed_close_url" "$unconsumed_close_head" \
  'https://github.com/example/opencaw-fixture/pull/215#issuecomment-31' --head-sha "$head_sha_1"
[[ "$(pr_event_file_count "$unconsumed_close_dir")" == 1 ]] \
  || fail 'closing with an unconsumed critic round mutated progress-PR evidence'
run_for "$project" bash commands/record-gauntlet-pr-event.sh unconsumed-close unit-1 qa-fail \
  "$unconsumed_close_url" "$unconsumed_close_head" \
  'https://github.com/example/opencaw-fixture/pull/215#issuecomment-32' --head-sha "$head_sha_1" >/dev/null
replace_line "$unconsumed_close_dir/GAUNTLET.md" '- Status: running' '- Status: stopped'
stopped_close_contract_hash="$(sha256_file "$unconsumed_close_dir/GAUNTLET.md")"
expect_failure "$temp_root/close-stopped-gauntlet.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh unconsumed-close unit-1 closed \
  "$unconsumed_close_url" "$unconsumed_close_head" \
  'https://github.com/example/opencaw-fixture/pull/215#issuecomment-33' --head-sha "$head_sha_1"
expect_line 'Terminal progress-PR events require a ready or running Gauntlet, not stopped.' \
  "$temp_root/close-stopped-gauntlet.log"
[[ "$(pr_event_file_count "$unconsumed_close_dir")" == 2 ]] \
  || fail 'closing a stopped Gauntlet mutated progress-PR evidence'
[[ "$(sha256_file "$unconsumed_close_dir/GAUNTLET.md")" == "$stopped_close_contract_hash" ]] \
  || fail 'closing a stopped Gauntlet mutated the Gauntlet contract'
replace_line "$unconsumed_close_dir/GAUNTLET.md" '- Status: stopped' '- Status: running'

terminal_validator_bin="$temp_root/terminal-validator-bin"
terminal_validator_ready="$temp_root/terminal-validator-ready"
terminal_validator_release="$temp_root/terminal-validator-release"
terminal_cas_output="$temp_root/terminal-status-cas.log"
terminal_real_bash="$(command -v bash)"
mkdir -p "$terminal_validator_bin"
cat >"$terminal_validator_bin/bash" <<'EOF'
#!/bin/sh
set -eu

if [ -n "${FAKE_VALIDATOR_PAUSE_READY:-}" ] \
  && [ -n "${FAKE_VALIDATOR_PAUSE_RELEASE:-}" ]; then
  case "${1:-}" in
    */validate-gauntlet.sh)
      : >"$FAKE_VALIDATOR_PAUSE_READY"
      pause_attempt=0
      while [ ! -e "$FAKE_VALIDATOR_PAUSE_RELEASE" ] && [ "$pause_attempt" -lt 200 ]; do
        sleep 0.01
        pause_attempt=$((pause_attempt + 1))
      done
      [ -e "$FAKE_VALIDATOR_PAUSE_RELEASE" ] || exit 98
      ;;
  esac
fi

exec "$REAL_BASH" "$@"
EOF
chmod +x "$terminal_validator_bin/bash"
set +e
PATH="$terminal_validator_bin:$PATH" REAL_BASH="$terminal_real_bash" \
  FAKE_VALIDATOR_PAUSE_READY="$terminal_validator_ready" \
  FAKE_VALIDATOR_PAUSE_RELEASE="$terminal_validator_release" \
  OPENCAW_PROJECT_ROOT="$project" "$terminal_real_bash" \
  commands/record-gauntlet-pr-event.sh unconsumed-close unit-1 closed \
  "$unconsumed_close_url" "$unconsumed_close_head" \
  'https://github.com/example/opencaw-fixture/pull/215#issuecomment-33' \
  --head-sha "$head_sha_1" >"$terminal_cas_output" 2>&1 &
terminal_cas_pid=$!
set -e
wait_for_path "$terminal_validator_ready"
replace_line "$unconsumed_close_dir/GAUNTLET.md" '- Status: running' '- Status: stopped'
terminal_concurrent_contract_hash="$(sha256_file "$unconsumed_close_dir/GAUNTLET.md")"
: >"$terminal_validator_release"
set +e
wait "$terminal_cas_pid"
terminal_cas_status=$?
set -e
[[ $terminal_cas_status -ne 0 ]] \
  || fail 'terminal progress-PR recording ignored a concurrent stopped-state transition'
expect_line "Gauntlet state changed during operation; no mutation was committed: $unconsumed_close_dir/GAUNTLET.md" \
  "$terminal_cas_output"
[[ "$(pr_event_file_count "$unconsumed_close_dir")" == 2 ]] \
  || fail 'terminal status CAS failure installed progress-PR evidence'
[[ "$(sha256_file "$unconsumed_close_dir/GAUNTLET.md")" == "$terminal_concurrent_contract_hash" ]] \
  || fail 'terminal status CAS failure overwrote the concurrent stopped-state transition'
[[ ! -e "$unconsumed_close_dir/.opencaw-gauntlet.lock" ]] \
  || fail 'terminal status CAS failure retained the Gauntlet lock'
replace_line "$unconsumed_close_dir/GAUNTLET.md" '- Status: stopped' '- Status: running'
run_for "$project" bash commands/record-gauntlet-pr-event.sh unconsumed-close unit-1 closed \
  "$unconsumed_close_url" "$unconsumed_close_head" \
  'https://github.com/example/opencaw-fixture/pull/215#issuecomment-33' --head-sha "$head_sha_1" >/dev/null
expect_file "$unconsumed_close_dir/pr-events/unit-1/event-003.md"

closed_dir="$project/.ai/gauntlets/closed-unmerged"
copy_gauntlet "$ready_snapshot" "$closed_dir"
closed_pr_url='https://github.com/example/opencaw-fixture/pull/207'
closed_head='gauntlet-work/closed-unmerged/unit-1'
run_for "$project" bash commands/record-gauntlet-pr-event.sh closed-unmerged unit-1 opened \
  "$closed_pr_url" "$closed_head" none --head-sha "$head_sha_3" >/dev/null
run_for "$project" bash commands/record-gauntlet-round.sh closed-unmerged unit-1 pass \
  closed-builder closed-critic fresh-session "$pass_report" \
  --head-sha "$head_sha_3" --builder-strategy "$builder_strategy_3" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh closed-unmerged unit-1 qa-pass \
  "$closed_pr_url" "$closed_head" \
  'https://github.com/example/opencaw-fixture/pull/207#issuecomment-22' --head-sha "$head_sha_3" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh closed-unmerged unit-1 closed \
  "$closed_pr_url" "$closed_head" \
  'https://github.com/example/opencaw-fixture/pull/207#issuecomment-23' --head-sha "$head_sha_3" >/dev/null
expect_failure "$temp_root/closed-unmerged-integration.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh closed-unmerged integration pass \
  closed-integration-builder closed-integration-critic fresh-session "$pass_report" \
  --head-sha "$head_sha_3" --builder-strategy "$integration_strategy_1"
set_local_ref "$project" gauntlet/closed-unmerged "$base_commit_sha"
set_remote_ref "$project" gauntlet/closed-unmerged "$base_commit_sha"
expect_failure "$temp_root/closed-unmerged-complete.log" run_for "$project" \
  bash commands/validate-gauntlet.sh closed-unmerged --phase complete
set_local_ref "$project" gauntlet-work/closed-unmerged/unit-1-remediation-1 "$head_sha_4"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  closed-unmerged unit-1 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh closed-unmerged unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/210' \
  'gauntlet-work/closed-unmerged/unit-1-remediation-1' none --head-sha "$head_sha_4" >/dev/null
expect_file "$closed_dir/pr-events/unit-1/event-004.md"
run_for "$project" bash commands/record-gauntlet-round.sh closed-unmerged unit-1 pass \
  closed-remediation-builder closed-remediation-critic fresh-session "$qa_remediation_report" \
  --head-sha "$head_sha_4" --builder-strategy "$builder_strategy_4" >/dev/null
expect_file "$closed_dir/rounds/unit-1/round-002.md"

echo '[6/8] gating integration, remediation, and completion reports'
[[ -x commands/create-gauntlet-completion-report.sh ]] \
  || fail 'Gauntlet completion command is missing or not executable'
bash commands/create-gauntlet-completion-report.sh --help >/dev/null \
  || fail 'create-gauntlet-completion-report --help failed'
sync_gauntlet_live_observations "$project" "$reapproval_dir"
run_for "$project" bash commands/create-gauntlet-completion-report.sh reapproved-bar --status complete --dry-run \
  >"$temp_root/reapproved-complete-dry-run.log"
[[ ! -f "$reapproval_dir/GAUNTLET_REPORT.md" ]] || fail 'reapproved completion dry-run wrote a report'
[[ "$(completion_event_file_count "$reapproval_dir")" == 0 ]] \
  || fail 'reapproved completion dry-run wrote a completion event'
sync_gauntlet_live_observations "$project" "$gauntlet_dir"
expect_failure "$temp_root/premature-complete.log" run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  fixture-gauntlet --status complete
grep -Fq 'Gauntlet integration review Head SHA must not be empty.' \
  "$temp_root/premature-complete.log" \
  || fail 'premature completion hit the wrong rejection guard'

stopped_dir="$project/.ai/gauntlets/stopped-gauntlet"
copy_gauntlet "$ready_snapshot" "$stopped_dir"
stopped_hash="$(git hash-object "$stopped_dir/GAUNTLET.md")"
run_for "$project" bash commands/create-gauntlet-completion-report.sh stopped-gauntlet --status stopped --dry-run \
  >"$temp_root/stopped-dry-run.log"
[[ ! -f "$stopped_dir/GAUNTLET_REPORT.md" ]] || fail 'completion dry-run created a report'
[[ "$stopped_hash" == "$(git hash-object "$stopped_dir/GAUNTLET.md")" ]] || fail 'completion dry-run changed Gauntlet state'
run_for "$project" bash commands/create-gauntlet-completion-report.sh stopped-gauntlet --status stopped >/dev/null
expect_file "$stopped_dir/GAUNTLET_REPORT.md"
[[ "$(completion_event_file_count "$stopped_dir")" == 0 ]] \
  || fail 'stopped report created a completion event'
grep -Eiq 'PR eligible[^[:alnum:]]+no|not PR[- ]eligible|PR-ineligible' "$stopped_dir/GAUNTLET_REPORT.md" \
  || fail 'stopped report was not explicitly PR-ineligible'
expect_failure "$temp_root/stopped-complete-validation.log" run_for "$project" bash commands/validate-gauntlet.sh stopped-gauntlet --phase complete

blocked_dir="$project/.ai/gauntlets/blocked-gauntlet"
copy_gauntlet "$ready_snapshot" "$blocked_dir"
run_for "$project" bash commands/create-gauntlet-completion-report.sh blocked-gauntlet --status blocked >/dev/null
expect_file "$blocked_dir/GAUNTLET_REPORT.md"
[[ "$(completion_event_file_count "$blocked_dir")" == 0 ]] \
  || fail 'blocked report created a completion event'
grep -Eiq 'PR eligible[^[:alnum:]]+no|not PR[- ]eligible|PR-ineligible' "$blocked_dir/GAUNTLET_REPORT.md" \
  || fail 'blocked report was not explicitly PR-ineligible'
expect_failure "$temp_root/blocked-complete-validation.log" run_for "$project" bash commands/validate-gauntlet.sh blocked-gauntlet --phase complete

direct_integration_report="$critic_dir/direct-unrecorded-integration-pass.md"
write_critic_report "$direct_integration_report" pass artifact.txt "$head_sha_5" \
  'The integration ref contains a direct commit that was never recorded as a merged progress PR.' \
  'Restore the exact progress-merge chain tip before requesting integration criticism.'
direct_pre_round_gauntlet_hash="$(git hash-object "$gauntlet_file")"
direct_pre_round_count="$(round_file_count "$gauntlet_dir")"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_5"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/direct-unrecorded-integration-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  direct-integration-builder direct-integration-critic fresh-session \
  "$direct_integration_report" --head-sha "$head_sha_5" \
  --builder-strategy 'Attempt to review a direct unrecorded integration-branch commit.'
[[ "$direct_pre_round_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$direct_pre_round_count" == "$(round_file_count "$gauntlet_dir")" ]] \
  || fail 'rejected direct integration commit mutated Gauntlet state or evidence'

orphan_integration_report="$critic_dir/orphan-integration-pass.md"
write_critic_report "$orphan_integration_report" pass artifact.txt "$orphan_sha" \
  'The reviewed integration head does not descend from the frozen base commit.' \
  'Reconstruct the branch from the frozen base and recorded human merge chain.'
set_local_ref "$project" gauntlet/fixture-gauntlet "$orphan_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/orphan-integration-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  orphan-integration-builder orphan-integration-critic fresh-session \
  "$orphan_integration_report" --head-sha "$orphan_sha" \
  --builder-strategy 'Attempt to review an integration head outside frozen-base ancestry.'
[[ "$direct_pre_round_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$direct_pre_round_count" == "$(round_file_count "$gauntlet_dir")" ]] \
  || fail 'rejected orphan integration head mutated Gauntlet state or evidence'

divergent_integration_report="$critic_dir/divergent-integration-pass.md"
write_critic_report "$divergent_integration_report" pass artifact.txt "$divergent_sha" \
  'The integration branch commit omits the latest human-merged unit progress.' \
  'Rebuild the integration head from every recorded unit merge before criticism.'
divergent_pre_round_gauntlet_hash="$(git hash-object "$gauntlet_file")"
divergent_pre_round_count="$(round_file_count "$gauntlet_dir")"
set_local_ref "$project" gauntlet/fixture-gauntlet "$divergent_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/divergent-integration-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  divergent-integration-builder divergent-integration-critic fresh-session \
  "$divergent_integration_report" --head-sha "$divergent_sha" \
  --builder-strategy 'Recheck a divergent integration head that omits the merged unit commit.'
[[ "$divergent_pre_round_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$divergent_pre_round_count" == "$(round_file_count "$gauntlet_dir")" \
  && ! -f "$gauntlet_dir/rounds/integration/round-001.md" ]] \
  || fail 'rejected divergent integration review mutated Gauntlet state or round evidence'
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_4"
sync_gauntlet_live_observations "$project" "$gauntlet_dir"

integration_report="$critic_dir/integration-pass.md"
write_critic_report "$integration_report" pass artifact.txt "$head_sha_4" \
  'No remaining integration gap was found across the complete fixture artifact.' \
  'Hold the passing artifact for final reporting and the human PR readiness checkpoint.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  integration-builder-1 integration-critic-1 fresh-session "$integration_report" \
  --head-sha "$head_sha_4" --builder-strategy "$integration_strategy_1" >/dev/null
expect_file "$gauntlet_dir/rounds/integration/round-001.md"
expect_line "- Head SHA: $head_sha_4" "$gauntlet_dir/rounds/integration/round-001.md"
expect_line "- Builder strategy: $integration_strategy_1" "$gauntlet_dir/rounds/integration/round-001.md"
expect_line '- Opened event: none' "$gauntlet_dir/rounds/integration/round-001.md"
expect_line '- Opened event sha256: none' "$gauntlet_dir/rounds/integration/round-001.md"
expect_line '- Remediation root: none' "$gauntlet_dir/rounds/integration/round-001.md"
expect_line '- Remediation root sha256: none' "$gauntlet_dir/rounds/integration/round-001.md"
expect_line '- Affected units: none' "$gauntlet_dir/rounds/integration/round-001.md"
grep -Eq '^- Scope fingerprint: [0-9a-f]{64}$' "$gauntlet_dir/rounds/integration/round-001.md" \
  || fail 'integration round omitted the aggregate active-unit scope fingerprint'
grep -q -- '- Verdict: pass' "$gauntlet_file" || fail 'integration pass was not recorded in GAUNTLET.md'
run_for "$project" bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete --dry-run \
  >"$temp_root/first-integration-complete-dry-run.log"
[[ ! -f "$gauntlet_dir/GAUNTLET_REPORT.md" ]] || fail 'complete dry-run wrote a report after the first integration pass'
[[ "$(completion_event_file_count "$gauntlet_dir")" == 0 ]] \
  || fail 'complete dry-run wrote a completion event after the first integration pass'

integration_fail_report="$critic_dir/integration-fail.md"
write_critic_report "$integration_fail_report" fail artifact.txt "$head_sha_4" \
  'The assembled artifact exposes a cross-unit recovery regression.' \
  'Reopen affected units, correct recovery as one coherent change, and rerun focused checks.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet integration fail \
  integration-builder-2 integration-critic-2 native-subagent "$integration_fail_report" \
  --head-sha "$head_sha_4" --builder-strategy "$integration_strategy_2" >/dev/null
expect_file "$gauntlet_dir/rounds/integration/round-002.md"
expect_line '- Opened event: none' "$gauntlet_dir/rounds/integration/round-002.md"
expect_line '- Remediation root: none' "$gauntlet_dir/rounds/integration/round-002.md"
expect_line '- Affected units: unit-1' "$gauntlet_dir/rounds/integration/round-002.md"
grep -q -- '- Verdict: fail' "$gauntlet_file" || fail 'later integration failure did not supersede the earlier pass'
! grep -Eq '^- \[[ x]\] unit-1 \| status: passed \|' "$gauntlet_file" \
  || fail 'integration failure left the active unit pass current'
expect_failure "$temp_root/stale-integration-pass.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete

forged_integration_reopen_dir="$project/.ai/gauntlets/integration-fail-forged-pass"
copy_gauntlet "$gauntlet_dir" "$forged_integration_reopen_dir"
replace_matching_line "$forged_integration_reopen_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: passed | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
forged_integration_gauntlet_hash="$(git hash-object "$forged_integration_reopen_dir/GAUNTLET.md")"
forged_integration_round_count="$(round_file_count "$forged_integration_reopen_dir")"
forged_integration_report="$critic_dir/integration-fail-forged-pass.md"
write_critic_report "$forged_integration_report" pass artifact.txt "$head_sha_4" \
  'A manual status flip cannot replace a progress PR triggered by the integration failure.' \
  'Open, review, QA, and merge a remediation PR that cites the failing integration round.'
expect_failure "$temp_root/integration-fail-forged-pass-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh integration-fail-forged-pass integration pass \
  forged-integration-builder forged-integration-critic fresh-session \
  "$forged_integration_report" --head-sha "$head_sha_4" \
  --builder-strategy 'Attempt integration after manually forging the reopened unit to passed.'
expect_failure "$temp_root/integration-fail-forged-pass-complete.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh integration-fail-forged-pass --status complete
[[ "$forged_integration_gauntlet_hash" == \
    "$(git hash-object "$forged_integration_reopen_dir/GAUNTLET.md")" \
  && "$forged_integration_round_count" == "$(round_file_count "$forged_integration_reopen_dir")" \
  && ! -f "$forged_integration_reopen_dir/GAUNTLET_REPORT.md" ]] \
  || fail 'manual post-integration-failure pass created mutable evidence or completion output'

integration_affected_tamper_dir="$project/.ai/gauntlets/integration-affected-tamper"
copy_gauntlet "$gauntlet_dir" "$integration_affected_tamper_dir"
replace_line "$integration_affected_tamper_dir/rounds/integration/round-002.md" \
  '- Affected units: unit-1' '- Affected units: none'
integration_affected_ledger="$(select_ledger_line "$project" \
  "$integration_affected_tamper_dir/GAUNTLET.md" 'Round Ledger' evidence \
  '.ai/gauntlets/integration-affected-tamper/rounds/integration/round-002.md')"
replace_line "$integration_affected_tamper_dir/GAUNTLET.md" \
  "$integration_affected_ledger" \
  "${integration_affected_ledger/affected-units: unit-1/affected-units: none}"
refresh_copied_evidence_hashes "$integration_affected_tamper_dir"
expect_failure "$temp_root/integration-affected-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh integration-affected-tamper --phase ready
grep -Fq 'Integration failure/block requires canonical frozen affected-unit IDs' \
  "$temp_root/integration-affected-tamper.log" || {
    sed -n '1,120p' "$temp_root/integration-affected-tamper.log" >&2
    fail 'integration affected-unit tamper hit the wrong rejection guard'
  }

pretip_work_dir="$project/.ai/gauntlets/work-head-before-chain-tip"
copy_gauntlet "$gauntlet_dir" "$pretip_work_dir"
pretip_work_head='gauntlet-work/work-head-before-chain-tip/unit-1-remediation-1'
set_local_ref "$project" "$pretip_work_head" "$head_sha_2"
set_remote_ref "$project" "$pretip_work_head" absent
pretip_checkpoint_count_before="$(find "$pretip_work_dir/publication-checkpoints" \
  -type f -name 'checkpoint-*.md' | wc -l | tr -d ' ')"
expect_failure "$temp_root/work-head-before-chain-tip-readiness.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress \
  work-head-before-chain-tip unit-1 "$project/progress-validation.md"
grep -Fq 'Gauntlet progress branch from current integration chain tip is not represented by the required local Git ancestry' \
  "$temp_root/work-head-before-chain-tip-readiness.log" \
  || fail 'work based before the chain tip hit the wrong readiness rejection guard'
[[ "$(find "$pretip_work_dir/publication-checkpoints" -type f -name 'checkpoint-*.md' \
  | wc -l | tr -d ' ')" == "$pretip_checkpoint_count_before" ]] \
  || fail 'readiness issued a checkpoint for work based before the chain tip'
set_local_ref "$project" "$pretip_work_head" "$head_sha_7"
set_remote_ref "$project" "$pretip_work_head" absent
pretip_readiness_output="$(run_for "$project" bash commands/pr-readiness-check.sh \
  --gauntlet-progress work-head-before-chain-tip unit-1 \
  "$project/progress-validation.md")"
pretip_checkpoint_relative="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$pretip_readiness_output")"
replace_line "$project/$pretip_checkpoint_relative" "- Head SHA: $head_sha_7" \
  "- Head SHA: $head_sha_2"
pretip_checkpoint_hash="$(sha256_file "$project/$pretip_checkpoint_relative")"
pretip_checkpoint_marker="<!-- opencaw-gauntlet-publication:v1 checkpoint=$pretip_checkpoint_relative checkpoint-sha256=$pretip_checkpoint_hash -->"
set_local_ref "$project" "$pretip_work_head" "$head_sha_2"
set_pr_observation 'https://github.com/example/opencaw-fixture/pull/287' \
  "$pretip_work_head" "$head_sha_2" gauntlet/work-head-before-chain-tip \
  OPEN false none none none none "$head_sha_4" false example/opencaw-fixture \
  2026-08-01T12:00:00Z none "$pretip_checkpoint_marker"
OPENCAW_TEST_SKIP_OBSERVATION=1 OPENCAW_TEST_SKIP_PUBLICATION_BODY=1 \
expect_failure "$temp_root/work-head-before-chain-tip.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh work-head-before-chain-tip unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/287' "$pretip_work_head" none \
  --head-sha "$head_sha_2"
[[ "$(pr_event_file_count "$pretip_work_dir")" \
    == "$(pr_event_file_count "$gauntlet_dir")" ]] \
  || fail 'work head based before the current chain tip created immutable PR evidence'

transitive_retry_dir="$project/.ai/gauntlets/transitive-retry"
copy_gauntlet "$gauntlet_dir" "$transitive_retry_dir"
transitive_first_url='https://github.com/example/opencaw-fixture/pull/224'
transitive_first_head='gauntlet-work/transitive-retry/unit-1-remediation-1'
set_local_ref "$project" "$transitive_first_head" "$head_sha_7"
run_for "$project" bash commands/record-gauntlet-pr-event.sh transitive-retry unit-1 opened \
  "$transitive_first_url" "$transitive_first_head" none --head-sha "$head_sha_7" >/dev/null
expect_line '- Remediation trigger: .ai/gauntlets/transitive-retry/rounds/integration/round-002.md' \
  "$transitive_retry_dir/pr-events/unit-1/event-007.md"
transitive_root_relative='.ai/gauntlets/transitive-retry/rounds/integration/round-002.md'
transitive_root_sha256="$(sha256_file "$project/$transitive_root_relative")"
transitive_first_open_relative='.ai/gauntlets/transitive-retry/pr-events/unit-1/event-007.md'
transitive_first_open_sha256="$(sha256_file "$project/$transitive_first_open_relative")"
transitive_fail_report="$critic_dir/transitive-remediation-fail.md"
write_critic_report "$transitive_fail_report" fail artifact.txt "$head_sha_7" \
  'The first remediation attempt still fails its recovery guardrail.' \
  'Close the QA-consumed failed PR and replace it with a distinct implementation.'
run_for "$project" bash commands/record-gauntlet-round.sh transitive-retry unit-1 fail \
  transitive-builder-1 transitive-critic-1 fresh-session "$transitive_fail_report" \
  --head-sha "$head_sha_7" \
  --builder-strategy 'Attempt the first isolated remediation of the integration failure.' >/dev/null
transitive_first_round="$(find "$transitive_retry_dir/rounds/unit-1" -maxdepth 1 \
  -type f -name 'round-*.md' -print | LC_ALL=C sort | tail -n 1)"
transitive_first_round_relative="${transitive_first_round#"$project"/}"
expect_line "- Opened event: $transitive_first_open_relative" "$transitive_first_round"
expect_line "- Opened event sha256: $transitive_first_open_sha256" "$transitive_first_round"
expect_line "- Remediation root: $transitive_root_relative" "$transitive_first_round"
expect_line "- Remediation root sha256: $transitive_root_sha256" "$transitive_first_round"
expect_line '- Affected units: none' "$transitive_first_round"
run_for "$project" bash commands/record-gauntlet-pr-event.sh transitive-retry unit-1 qa-fail \
  "$transitive_first_url" "$transitive_first_head" \
  'https://github.com/example/opencaw-fixture/pull/224#issuecomment-60' \
  --head-sha "$head_sha_7" >/dev/null
transitive_first_qa_relative='.ai/gauntlets/transitive-retry/pr-events/unit-1/event-008.md'
expect_file "$project/$transitive_first_qa_relative"
run_for "$project" bash commands/record-gauntlet-pr-event.sh transitive-retry unit-1 closed \
  "$transitive_first_url" "$transitive_first_head" \
  'https://github.com/example/opencaw-fixture/pull/224#issuecomment-61' \
  --head-sha "$head_sha_7" >/dev/null
expect_file "$transitive_retry_dir/pr-events/unit-1/event-009.md"
expect_line '- Event: closed' "$transitive_retry_dir/pr-events/unit-1/event-009.md"

transitive_quality_revision_marker="- Quality bar revision: transitive-v2 | approved by: transitive-quality-user | approved at: 2026-08-01T12:00:01Z | supersedes: $quality_bar_v1 | reason: Preserve the original integration failure through a closed remediation cycle while approving the next quality generation."
replace_line "$transitive_retry_dir/GAUNTLET.md" \
  '- Benchmark: Local artifact quality contract version 1.' \
  '- Benchmark: Local artifact quality contract version 2 with transitive remediation tracing.'
replace_line "$transitive_retry_dir/GAUNTLET.md" \
  '- Approved by: fixture-user' '- Approved by: transitive-quality-user'
replace_line "$transitive_retry_dir/GAUNTLET.md" \
  '- Approved at: 2026-08-01T12:00:00Z' \
  '- Approved at: 2026-08-01T12:00:01Z'
set_gauntlet_field "$project" "$transitive_retry_dir/GAUNTLET.md" \
  'Current State' 'Quality bar fingerprint' pending
reset_integration_review "$project" "$transitive_retry_dir/GAUNTLET.md"
insert_after_matching_line "$transitive_retry_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$transitive_quality_revision_marker"
run_for "$project" bash commands/validate-gauntlet.sh \
  transitive-retry --phase ready >/dev/null
transitive_quality_root="$(gauntlet_helper_value "$project" \
  gauntlet_remediation_root_for_trigger "$transitive_retry_dir/GAUNTLET.md" \
  unit-1 quality-revision:transitive-v2 '2026-08-01T12:00:02Z')"
[[ "$transitive_quality_root" \
    == '.ai/gauntlets/transitive-retry/pr-events/unit-1/event-009.md' ]] \
  || fail 'transitive quality revision did not resolve its immediately previous close'

export FAKE_DATE_ISO='2026-08-01T12:00:02Z'
transitive_second_url='https://github.com/example/opencaw-fixture/pull/225'
transitive_second_head='gauntlet-work/transitive-retry/unit-1-remediation-2'
set_local_ref "$project" "$transitive_second_head" "$head_sha_8"
run_for "$project" bash commands/record-gauntlet-pr-event.sh transitive-retry unit-1 opened \
  "$transitive_second_url" "$transitive_second_head" none --head-sha "$head_sha_8" >/dev/null
transitive_second_open_relative='.ai/gauntlets/transitive-retry/pr-events/unit-1/event-010.md'
transitive_second_open="$project/$transitive_second_open_relative"
expect_line '- Remediation trigger: quality-revision:transitive-v2' \
  "$transitive_second_open"
transitive_second_checkpoint_relative="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$transitive_second_open" 'PR Event Metadata' \
  'Publication checkpoint')"
transitive_second_checkpoint="$project/$transitive_second_checkpoint_relative"
transitive_quality_trigger_sha256="$(sha256_text "$transitive_quality_revision_marker"$'\n')"
transitive_close_sha256="$(sha256_file "$project/$transitive_quality_root")"
expect_line "- Remediation trigger sha256: $transitive_quality_trigger_sha256" \
  "$transitive_second_checkpoint"
expect_line "- Remediation root: $transitive_quality_root" \
  "$transitive_second_checkpoint"
expect_line "- Remediation root sha256: $transitive_close_sha256" \
  "$transitive_second_checkpoint"
gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$transitive_retry_dir/GAUNTLET.md" unit-1 "$transitive_second_open" \
  "$transitive_first_round_relative" >/dev/null \
  || fail 'transitive quality-revision close root did not retain its contained failed critic round'
gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$transitive_retry_dir/GAUNTLET.md" unit-1 "$transitive_second_open" \
  "$transitive_first_qa_relative" >/dev/null \
  || fail 'transitive quality-revision close root did not retain its contained QA failure'
gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$transitive_retry_dir/GAUNTLET.md" unit-1 "$transitive_second_open" \
  "$transitive_root_relative" >/dev/null \
  || fail 'transitive quality-revision close root did not trace to the original integration failure'

containment_tamper_dir="$project/.ai/gauntlets/closed-cycle-containment-tamper"
copy_gauntlet "$transitive_retry_dir" "$containment_tamper_dir"
containment_tamper_open="$containment_tamper_dir/pr-events/unit-1/event-010.md"
containment_tamper_qa="$containment_tamper_dir/pr-events/unit-1/event-008.md"
containment_tamper_round="$containment_tamper_dir/rounds/unit-1/$(basename "$transitive_first_round")"
containment_tamper_round_relative=".ai/gauntlets/closed-cycle-containment-tamper/rounds/unit-1/$(basename "$transitive_first_round")"
containment_tamper_qa_relative='.ai/gauntlets/closed-cycle-containment-tamper/pr-events/unit-1/event-008.md'
gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$containment_tamper_dir/GAUNTLET.md" unit-1 "$containment_tamper_open" \
  "$containment_tamper_round_relative" >/dev/null \
  || fail 'copied closed-cycle containment control lost its failed critic round'

replace_line "$containment_tamper_qa" '- Event: qa-fail' '- Event: qa-pass'
expect_failure "$temp_root/closed-cycle-qa-pass-consumer.log" \
  gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$containment_tamper_dir/GAUNTLET.md" unit-1 "$containment_tamper_open" \
  "$containment_tamper_qa_relative"
replace_line "$containment_tamper_qa" '- Event: qa-pass' '- Event: qa-fail'

containment_wrong_round="$(find "$containment_tamper_dir/rounds/unit-1" \
  -maxdepth 1 -type f -name 'round-*.md' ! -path "$containment_tamper_round" \
  -print | LC_ALL=C sort | head -n 1)"
[[ -n "$containment_wrong_round" ]] \
  || fail 'closed-cycle wrong-round fixture lacks a distinct retained unit round'
containment_wrong_round_relative="${containment_wrong_round#"$project"/}"
replace_line "$containment_tamper_qa" \
  "- Critic round: $containment_tamper_round_relative" \
  "- Critic round: $containment_wrong_round_relative"
expect_failure "$temp_root/closed-cycle-wrong-critic-round.log" \
  gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$containment_tamper_dir/GAUNTLET.md" unit-1 "$containment_tamper_open" \
  "$containment_tamper_round_relative"
replace_line "$containment_tamper_qa" \
  "- Critic round: $containment_wrong_round_relative" \
  "- Critic round: $containment_tamper_round_relative"

containment_opened_hash="$(sha256_file \
  "$containment_tamper_dir/pr-events/unit-1/event-007.md")"
replace_line "$containment_tamper_round" \
  "- Opened event sha256: $containment_opened_hash" \
  '- Opened event sha256: 0000000000000000000000000000000000000000000000000000000000000000'
expect_failure "$temp_root/closed-cycle-stale-opened-anchor.log" \
  gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$containment_tamper_dir/GAUNTLET.md" unit-1 "$containment_tamper_open" \
  "$containment_tamper_round_relative"
replace_line "$containment_tamper_round" \
  '- Opened event sha256: 0000000000000000000000000000000000000000000000000000000000000000' \
  "- Opened event sha256: $containment_opened_hash"

containment_qa_ledger="$(select_ledger_line "$project" \
  "$containment_tamper_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  "$containment_tamper_qa_relative")"
containment_close_relative='.ai/gauntlets/closed-cycle-containment-tamper/pr-events/unit-1/event-009.md'
containment_close_ledger="$(select_ledger_line "$project" \
  "$containment_tamper_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  "$containment_close_relative")"
replace_line "$containment_tamper_dir/GAUNTLET.md" \
  "$containment_qa_ledger" '__CONTAINMENT_QA_LEDGER__'
replace_line "$containment_tamper_dir/GAUNTLET.md" \
  "$containment_close_ledger" "$containment_qa_ledger"
replace_line "$containment_tamper_dir/GAUNTLET.md" \
  '__CONTAINMENT_QA_LEDGER__' "$containment_close_ledger"
expect_failure "$temp_root/closed-cycle-qa-after-close.log" \
  gauntlet_helper_value "$project" gauntlet_trace_remediation_trigger \
  "$containment_tamper_dir/GAUNTLET.md" unit-1 "$containment_tamper_open" \
  "$containment_tamper_qa_relative"

transitive_second_open_sha256="$(sha256_file "$project/$transitive_second_open_relative")"
transitive_pass_report="$critic_dir/transitive-remediation-pass.md"
write_critic_report "$transitive_pass_report" pass artifact.txt "$head_sha_8" \
  'The replacement remediation resolves the failure under the frozen unit bar.' \
  'Consume QA, merge it, and run a new integration critic on the chain tip.'
sync_gauntlet_live_observations "$project" "$transitive_retry_dir"
run_for "$project" bash commands/record-gauntlet-round.sh transitive-retry unit-1 pass \
  transitive-builder-2 transitive-critic-2 fresh-session "$transitive_pass_report" \
  --head-sha "$head_sha_8" \
  --builder-strategy 'Replace the closed remediation with a different verified implementation.' >/dev/null
transitive_second_round="$(find "$transitive_retry_dir/rounds/unit-1" -maxdepth 1 \
  -type f -name 'round-*.md' -print | LC_ALL=C sort | tail -n 1)"
expect_line "- Opened event: $transitive_second_open_relative" "$transitive_second_round"
expect_line "- Opened event sha256: $transitive_second_open_sha256" "$transitive_second_round"
expect_line "- Remediation root: $transitive_quality_root" "$transitive_second_round"
expect_line "- Remediation root sha256: $transitive_close_sha256" "$transitive_second_round"
expect_line '- Affected units: none' "$transitive_second_round"
run_for "$project" bash commands/record-gauntlet-pr-event.sh transitive-retry unit-1 qa-pass \
  "$transitive_second_url" "$transitive_second_head" \
  'https://github.com/example/opencaw-fixture/pull/225#issuecomment-62' \
  --head-sha "$head_sha_8" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh transitive-retry unit-1 merged \
  "$transitive_second_url" "$transitive_second_head" \
  'https://github.com/example/opencaw-fixture/pull/225#issuecomment-63' \
  --head-sha "$head_sha_8" --merge-commit "$head_sha_8" >/dev/null
expect_line "- Target base SHA: $head_sha_4" \
  "$transitive_retry_dir/pr-events/unit-1/event-012.md"
transitive_integration_report="$critic_dir/transitive-integration-pass.md"
write_critic_report "$transitive_integration_report" pass artifact.txt "$head_sha_8" \
  'The transitive replacement chain resolves the original integration failure.' \
  'The Gauntlet may now create a fresh completion event.'
run_for "$project" bash commands/record-gauntlet-round.sh transitive-retry integration pass \
  transitive-integration-builder transitive-integration-critic native-subagent \
  "$transitive_integration_report" --head-sha "$head_sha_8" \
  --builder-strategy 'Inspect the exact merge-chain tip after the transitive retry.' >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh transitive-retry --phase ready >/dev/null
unset FAKE_DATE_ISO

set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_6" \
  gauntlet/transitive-retry CLOSED false none none none none "$head_sha_4"
expect_failure "$temp_root/closed-requery-head-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  main CLOSED false none none none none "$head_sha_4"
expect_failure "$temp_root/closed-requery-base-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  gauntlet/transitive-retry CLOSED false none none none none "$base_commit_sha"
expect_failure "$temp_root/closed-requery-base-sha-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  gauntlet/transitive-retry OPEN false none none none none "$head_sha_4"
expect_failure "$temp_root/closed-requery-state-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  gauntlet/transitive-retry CLOSED false 2026-08-01T12:30:00Z none none none "$head_sha_4"
expect_failure "$temp_root/closed-requery-time-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  gauntlet/transitive-retry CLOSED false none forged-reviewer none none "$head_sha_4"
expect_failure "$temp_root/closed-requery-actor-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  gauntlet/transitive-retry CLOSED false none none none false "$head_sha_4"
expect_failure "$temp_root/closed-requery-bot-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  gauntlet/transitive-retry CLOSED false none none "$head_sha_7" none "$head_sha_4"
expect_failure "$temp_root/closed-requery-merge-commit-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-retry --phase ready
set_pr_observation "$transitive_first_url" "$transitive_first_head" "$head_sha_7" \
  gauntlet/transitive-retry CLOSED false none none none none "$head_sha_4"
run_for "$project" bash commands/validate-gauntlet.sh transitive-retry --phase ready >/dev/null

transitive_trigger_rewrite_dir="$project/.ai/gauntlets/transitive-trigger-rewrite"
copy_gauntlet "$transitive_retry_dir" "$transitive_trigger_rewrite_dir"
replace_line "$transitive_trigger_rewrite_dir/pr-events/unit-1/event-010.md" \
  '- Remediation trigger: quality-revision:transitive-v2' \
  '- Remediation trigger: .ai/gauntlets/transitive-trigger-rewrite/rounds/integration/round-002.md'
refresh_copied_cross_evidence_hashes "$transitive_trigger_rewrite_dir"
refresh_copied_evidence_hashes "$transitive_trigger_rewrite_dir"
expect_failure "$temp_root/transitive-trigger-rewrite.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-trigger-rewrite --phase ready

transitive_root_hash_tamper_dir="$project/.ai/gauntlets/transitive-root-hash-tamper"
copy_gauntlet "$transitive_retry_dir" "$transitive_root_hash_tamper_dir"
replace_matching_line \
  "$transitive_root_hash_tamper_dir/rounds/unit-1/round-006.md" \
  '^- Remediation root sha256:' \
  '- Remediation root sha256: 0000000000000000000000000000000000000000000000000000000000000000'
refresh_copied_evidence_hashes "$transitive_root_hash_tamper_dir"
expect_failure "$temp_root/transitive-root-hash-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh transitive-root-hash-tamper --phase ready

unrelated_close_dir="$project/.ai/gauntlets/unrelated-close-trigger"
copy_gauntlet "$transitive_retry_dir" "$unrelated_close_dir"
replace_line "$unrelated_close_dir/pr-events/unit-1/event-010.md" \
  '- Remediation trigger: quality-revision:transitive-v2' \
  '- Remediation trigger: .ai/gauntlets/closed-unmerged/pr-events/unit-1/event-004.md'
refresh_copied_evidence_hashes "$unrelated_close_dir"
expect_failure "$temp_root/unrelated-close-trigger.log" run_for "$project" \
  bash commands/validate-gauntlet.sh unrelated-close-trigger --phase ready

stale_reference_dir="$project/.ai/gauntlets/stale-integration-reference"
copy_gauntlet "$gauntlet_dir" "$stale_reference_dir"
replace_all_literal "$stale_reference_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/stale-integration-reference/'
replace_line "$stale_reference_dir/GAUNTLET.md" '- Status: running' '- Status: passed'
replace_matching_line "$stale_reference_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: passed | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
replace_line "$stale_reference_dir/GAUNTLET.md" '- Verdict: fail' '- Verdict: pass'
replace_line "$stale_reference_dir/GAUNTLET.md" '- Critic ID: integration-critic-2' '- Critic ID: integration-critic-1'
replace_line "$stale_reference_dir/GAUNTLET.md" \
  '- Evidence: `.ai/gauntlets/stale-integration-reference/rounds/integration/round-002.md`' \
  '- Evidence: `.ai/gauntlets/stale-integration-reference/rounds/integration/round-001.md`'
replace_line "$stale_reference_dir/GAUNTLET.md" '- PR eligible: no' '- PR eligible: yes'
expect_failure "$temp_root/stale-integration-reference.log" run_for "$project" \
  bash commands/validate-gauntlet.sh stale-integration-reference --phase complete

orphan_dir="$project/.ai/gauntlets/orphan-history"
copy_gauntlet "$gauntlet_dir" "$orphan_dir"
replace_all_literal "$orphan_dir/GAUNTLET.md" \
  '.ai/gauntlets/fixture-gauntlet/' '.ai/gauntlets/orphan-history/'
replace_matching_line "$orphan_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Replacement unit that erased prior history | scope: replacement artifact boundary'
replace_matching_line "$orphan_dir/GAUNTLET.md" '^- Active work unit:' '- Active work unit: unit-2'
expect_failure "$temp_root/orphan-history.log" run_for "$project" \
  bash commands/validate-gauntlet.sh orphan-history --phase ready

later_unrelated_dir="$project/.ai/gauntlets/later-unrelated-unit"
copy_gauntlet "$gauntlet_dir" "$later_unrelated_dir"
insert_after_matching_line "$later_unrelated_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Later unrelated unit | scope: independent artifact boundary added after the integration failure'
replace_matching_line "$later_unrelated_dir/GAUNTLET.md" \
  '^- Active work unit:' '- Active work unit: unit-2'
later_unrelated_manifest="$(unit_manifest_fingerprint \
  "$project" "$later_unrelated_dir/GAUNTLET.md")"
later_unrelated_revision="- Unit manifest revision: add-unrelated-unit-2 | from: $unit_manifest_opened | to: $later_unrelated_manifest | prior-units: unit-1 | current-units: unit-1,unit-2 | reason: Add a disjoint unit after the earlier integration failure without retroactively expanding that failure scope. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$later_unrelated_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$later_unrelated_revision"
set_gauntlet_field "$project" "$later_unrelated_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
reset_integration_review "$project" "$later_unrelated_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh later-unrelated-unit --phase ready >/dev/null
export FAKE_DATE_ISO=2026-08-02T00:00:02Z
later_unrelated_head='gauntlet-work/later-unrelated-unit/unit-2'
later_unrelated_pr='https://github.com/example/opencaw-fixture/pull/290'
set_local_ref "$project" "$later_unrelated_head" "$head_sha_7"
later_unrelated_readiness="$(OPENCAW_REPORT_DIR="$project/.ai/reports/later-unrelated" \
  run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  later-unrelated-unit unit-2 "$project/progress-validation.md")"
later_unrelated_checkpoint="$(sed -nE 's/^PUBLICATION_CHECKPOINT=(.+)$/\1/p' \
  <<<"$later_unrelated_readiness")"
expect_line '- Remediation trigger: none' "$project/$later_unrelated_checkpoint"
run_for "$project" bash commands/record-gauntlet-pr-event.sh later-unrelated-unit \
  unit-2 opened "$later_unrelated_pr" \
  "$later_unrelated_head" none --head-sha "$head_sha_7" >/dev/null
expect_line '- Remediation trigger: none' \
  "$later_unrelated_dir/pr-events/unit-2/event-001.md"
later_unrelated_report="$critic_dir/later-unrelated-unit-pass.md"
write_critic_report "$later_unrelated_report" pass artifact.txt "$head_sha_7" \
  'The independently added unit passes its approved isolated boundary.' \
  'Consume progressive QA and merge the disjoint unit into the integration branch.'
run_for "$project" bash commands/record-gauntlet-round.sh later-unrelated-unit \
  unit-2 pass later-unrelated-builder later-unrelated-critic fresh-session \
  "$later_unrelated_report" --head-sha "$head_sha_7" \
  --builder-strategy 'Implement and verify the independently approved second unit.' >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh later-unrelated-unit \
  unit-2 qa-pass "$later_unrelated_pr" "$later_unrelated_head" \
  "$later_unrelated_pr#issuecomment-82" --head-sha "$head_sha_7" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh later-unrelated-unit \
  unit-2 merged "$later_unrelated_pr" "$later_unrelated_head" \
  "$later_unrelated_pr#issuecomment-83" --head-sha "$head_sha_7" \
  --merge-commit "$head_sha_7" >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh \
  later-unrelated-unit --phase ready >/dev/null
unset FAKE_DATE_ISO

future_unit_membership_dir="$project/.ai/gauntlets/future-unit-membership"
copy_gauntlet "$later_unrelated_dir" "$future_unit_membership_dir"
future_unit_membership_revision="${later_unrelated_revision/approved at: 2026-08-02T00:00:01Z/approved at: 2026-08-02T00:00:03Z}"
replace_line "$future_unit_membership_dir/GAUNTLET.md" \
  "$later_unrelated_revision" "$future_unit_membership_revision"
future_unit_membership_checkpoint="$future_unit_membership_dir/publication-checkpoints/unit-2/checkpoint-001.md"
replace_matching_line "$future_unit_membership_checkpoint" \
  '^- Unit manifest fingerprint:' \
  "- Unit manifest fingerprint: $unit_manifest_opened"
replace_matching_line "$future_unit_membership_checkpoint" \
  '^- Unit manifest approved at:' \
  '- Unit manifest approved at: 2026-08-01T12:00:00Z'
refresh_copied_checkpoint_hashes "$future_unit_membership_dir"
for future_unit_membership_evidence in \
  "$future_unit_membership_dir/pr-events/unit-2/event-001.md" \
  "$future_unit_membership_dir/pr-events/unit-2/event-002.md" \
  "$future_unit_membership_dir/pr-events/unit-2/event-003.md" \
  "$future_unit_membership_dir/rounds/unit-2/round-001.md"; do
  replace_matching_line "$future_unit_membership_evidence" \
    '^- Unit manifest fingerprint:' \
    "- Unit manifest fingerprint: $unit_manifest_opened"
done
replace_all_literal "$future_unit_membership_dir/GAUNTLET.md" \
  "manifest: $later_unrelated_manifest" "manifest: $unit_manifest_opened"
refresh_copied_cross_evidence_hashes "$future_unit_membership_dir"
future_unit_membership_round_relative='.ai/gauntlets/future-unit-membership/rounds/unit-2/round-001.md'
future_unit_membership_comment_body="$(semantic_comment_body "$project" pass "$head_sha_7" \
  "$future_unit_membership_round_relative")"
replace_matching_line \
  "$future_unit_membership_dir/pr-events/unit-2/event-002.md" \
  '^- QA comment body sha256:' \
  "- QA comment body sha256: $(sha256_text "$future_unit_membership_comment_body")"
refresh_copied_evidence_hashes "$future_unit_membership_dir"
sync_gauntlet_live_observations "$project" "$future_unit_membership_dir"
expect_line '- Recorded at: 2026-08-02T00:00:02Z' \
  "$future_unit_membership_checkpoint"
expect_line "- Unit manifest fingerprint: $unit_manifest_opened" \
  "$future_unit_membership_dir/pr-events/unit-2/event-003.md"
expect_failure "$temp_root/future-unit-membership.log" run_for "$project" \
  bash commands/validate-gauntlet.sh future-unit-membership --phase ready
grep -Fq \
  'Publication checkpoint item was not part of the active Unit manifest at its Recorded at timestamp' \
  "$temp_root/future-unit-membership.log" \
  || fail 'future unit evidence did not reach the manifest-membership gate'

topology_binding_control_dir="$project/.ai/gauntlets/topology-binding-control"
copy_gauntlet "$ready_snapshot" "$topology_binding_control_dir"
insert_after_matching_line "$topology_binding_control_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Pre-existing independent topology peer | scope: independent peer boundary'
topology_binding_m2="$(unit_manifest_fingerprint \
  "$project" "$topology_binding_control_dir/GAUNTLET.md")"
topology_binding_m2_revision="- Unit manifest revision: add-topology-peer | from: $unit_manifest_opened | to: $topology_binding_m2 | prior-units: unit-1 | current-units: unit-1,unit-2 | reason: Approve both independent units before any replacement edge exists. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$topology_binding_control_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$topology_binding_m2_revision"
replace_matching_line "$topology_binding_control_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: superseded | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
topology_binding_old_scope="$(unit_scope_fingerprint \
  "$project" "$topology_binding_control_dir/GAUNTLET.md" unit-1)"
topology_binding_edge="- Unit supersession: unit-1 | scope: $topology_binding_old_scope | replacements: unit-2 | reason: Introduce the replacement edge only in the later topology generation. | approved by: fixture-user | approved at: 2026-08-02T00:00:03Z"
insert_after_matching_line "$topology_binding_control_dir/GAUNTLET.md" \
  '^- Unit manifest revision: add-topology-peer ' "$topology_binding_edge"
topology_binding_m3="$(unit_manifest_fingerprint \
  "$project" "$topology_binding_control_dir/GAUNTLET.md")"
topology_binding_m3_revision="- Unit manifest revision: add-topology-edge | from: $topology_binding_m2 | to: $topology_binding_m3 | prior-units: unit-1,unit-2 | current-units: unit-1,unit-2 | reason: Freeze the later replacement edge without changing retained membership. | approved by: fixture-user | approved at: 2026-08-02T00:00:03Z"
insert_after_matching_line "$topology_binding_control_dir/GAUNTLET.md" \
  '^- Unit supersession: unit-1 ' "$topology_binding_m3_revision"
set_gauntlet_field "$project" "$topology_binding_control_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
set_gauntlet_field "$project" "$topology_binding_control_dir/GAUNTLET.md" \
  'Current State' 'Active work unit' unit-2
reset_integration_review "$project" "$topology_binding_control_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh \
  topology-binding-control --phase ready >/dev/null

topology_binding_backdated_dir="$project/.ai/gauntlets/topology-binding-backdated"
copy_gauntlet "$topology_binding_control_dir" "$topology_binding_backdated_dir"
topology_binding_backdated_edge="${topology_binding_edge/approved at: 2026-08-02T00:00:03Z/approved at: 2026-08-02T00:00:01Z}"
replace_line "$topology_binding_backdated_dir/GAUNTLET.md" \
  "$topology_binding_edge" "$topology_binding_backdated_edge"
expect_failure "$temp_root/topology-binding-backdated.log" run_for "$project" \
  bash commands/validate-gauntlet.sh topology-binding-backdated --phase ready
grep -Fq \
  'Approved Unit manifest generation cannot be reconstructed from its approved unit, scope, and topology state' \
  "$temp_root/topology-binding-backdated.log" \
  || fail 'backdated topology edge did not reach the manifest-delta binding gate'

scope_activation_dir="$project/.ai/gauntlets/scope-activation-control"
copy_gauntlet "$gauntlet_dir" "$scope_activation_dir"
scope_activation_v1="$(unit_scope_fingerprint \
  "$project" "$scope_activation_dir/GAUNTLET.md" unit-1)"
replace_matching_line "$scope_activation_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: critic-failed | title: Complete the expanded fixture artifact | scope: artifact.txt and its expanded verifier boundary'
scope_activation_v2="$(unit_scope_fingerprint \
  "$project" "$scope_activation_dir/GAUNTLET.md" unit-1)"
scope_activation_manifest="$(unit_manifest_fingerprint \
  "$project" "$scope_activation_dir/GAUNTLET.md")"
scope_activation_manifest_revision="- Unit manifest revision: revise-unit-1-scope | from: $unit_manifest_opened | to: $scope_activation_manifest | prior-units: unit-1 | current-units: unit-1 | reason: Expand the retained unit boundary while preserving its prior evidence. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
scope_activation_scope_revision="- Unit scope-title revision: unit-1 | from: $scope_activation_v1 | to: $scope_activation_v2 | reason: Expand the retained unit boundary after reviewing the original failure evidence. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$scope_activation_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$scope_activation_manifest_revision"
insert_after_matching_line "$scope_activation_dir/GAUNTLET.md" \
  '^- Unit manifest revision: revise-unit-1-scope ' "$scope_activation_scope_revision"
set_gauntlet_field "$project" "$scope_activation_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
set_gauntlet_field "$project" "$scope_activation_dir/GAUNTLET.md" \
  'Current State' 'Active work unit' unit-1
reset_integration_review "$project" "$scope_activation_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh \
  scope-activation-control --phase ready >/dev/null
export FAKE_DATE_ISO=2026-08-02T00:00:02Z
scope_activation_head='gauntlet-work/scope-activation-control/unit-1-remediation-1'
scope_activation_pr='https://github.com/example/opencaw-fixture/pull/304'
set_local_ref "$project" "$scope_activation_head" "$head_sha_7"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  scope-activation-control unit-1 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  scope-activation-control unit-1 opened "$scope_activation_pr" \
  "$scope_activation_head" none --head-sha "$head_sha_7" >/dev/null
scope_activation_report="$critic_dir/scope-activation-unit-pass.md"
write_critic_report "$scope_activation_report" pass artifact.txt "$head_sha_7" \
  'The expanded unit scope passes its newly approved verifier boundary.' \
  'Consume progressive QA and merge the approved scope revision.'
run_for "$project" bash commands/record-gauntlet-round.sh scope-activation-control \
  unit-1 pass scope-activation-builder scope-activation-critic fresh-session \
  "$scope_activation_report" --head-sha "$head_sha_7" \
  --builder-strategy 'Implement the approved expanded scope and rerun its focused verifier.' \
  >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  scope-activation-control unit-1 qa-pass "$scope_activation_pr" \
  "$scope_activation_head" "$scope_activation_pr#issuecomment-84" \
  --head-sha "$head_sha_7" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  scope-activation-control unit-1 merged "$scope_activation_pr" \
  "$scope_activation_head" "$scope_activation_pr#issuecomment-85" \
  --head-sha "$head_sha_7" --merge-commit "$head_sha_7" >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh \
  scope-activation-control --phase ready >/dev/null
expect_line "- Scope fingerprint: $scope_activation_v1" \
  "$scope_activation_dir/pr-events/unit-1/event-001.md"
expect_line "- Scope fingerprint: $scope_activation_v2" \
  "$scope_activation_dir/pr-events/unit-1/event-007.md"
unset FAKE_DATE_ISO

future_scope_activation_dir="$project/.ai/gauntlets/future-scope-activation"
copy_gauntlet "$scope_activation_dir" "$future_scope_activation_dir"
future_scope_manifest_revision="${scope_activation_manifest_revision/approved at: 2026-08-02T00:00:01Z/approved at: 2026-08-02T00:00:03Z}"
future_scope_revision="${scope_activation_scope_revision/approved at: 2026-08-02T00:00:01Z/approved at: 2026-08-02T00:00:03Z}"
replace_line "$future_scope_activation_dir/GAUNTLET.md" \
  "$scope_activation_manifest_revision" "$future_scope_manifest_revision"
replace_line "$future_scope_activation_dir/GAUNTLET.md" \
  "$scope_activation_scope_revision" "$future_scope_revision"
future_scope_open="$future_scope_activation_dir/pr-events/unit-1/event-007.md"
future_scope_round="$future_scope_activation_dir/rounds/unit-1/round-005.md"
future_scope_qa="$future_scope_activation_dir/pr-events/unit-1/event-008.md"
future_scope_merge="$future_scope_activation_dir/pr-events/unit-1/event-009.md"
future_scope_checkpoint_relative="$(gauntlet_helper_value "$project" \
  gauntlet_section_field "$future_scope_open" 'PR Event Metadata' \
  'Publication checkpoint')"
future_scope_checkpoint="$project/$future_scope_checkpoint_relative"
replace_matching_line "$future_scope_checkpoint" \
  '^- Unit manifest fingerprint:' \
  "- Unit manifest fingerprint: $unit_manifest_opened"
replace_matching_line "$future_scope_checkpoint" \
  '^- Unit manifest approved at:' \
  '- Unit manifest approved at: 2026-08-01T12:00:00Z'
refresh_copied_checkpoint_hashes "$future_scope_activation_dir"
for future_scope_evidence in "$future_scope_open" "$future_scope_round" \
  "$future_scope_qa" "$future_scope_merge"; do
  replace_matching_line "$future_scope_evidence" \
    '^- Unit manifest fingerprint:' \
    "- Unit manifest fingerprint: $unit_manifest_opened"
done
replace_all_literal "$future_scope_activation_dir/GAUNTLET.md" \
  "manifest: $scope_activation_manifest" "manifest: $unit_manifest_opened"
refresh_copied_cross_evidence_hashes "$future_scope_activation_dir"
future_scope_round_relative='.ai/gauntlets/future-scope-activation/rounds/unit-1/round-005.md'
future_scope_comment_body="$(semantic_comment_body "$project" pass "$head_sha_7" \
  "$future_scope_round_relative")"
replace_matching_line "$future_scope_qa" '^- QA comment body sha256:' \
  "- QA comment body sha256: $(sha256_text "$future_scope_comment_body")"
refresh_copied_evidence_hashes "$future_scope_activation_dir"
sync_gauntlet_live_observations "$project" "$future_scope_activation_dir"
expect_line '- Recorded at: 2026-08-02T00:00:02Z' "$future_scope_checkpoint"
expect_line "- Scope fingerprint: $scope_activation_v2" "$future_scope_open"
expect_line "- Unit manifest fingerprint: $unit_manifest_opened" "$future_scope_round"
expect_failure "$temp_root/future-scope-activation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh future-scope-activation --phase ready
grep -Fq \
  'Publication checkpoint scope was not part of the active Unit manifest at its Recorded at timestamp' \
  "$temp_root/future-scope-activation.log" \
  || fail 'future scope evidence did not reach the manifest-scope gate'

scope_binding_backdated_dir="$project/.ai/gauntlets/scope-binding-backdated"
copy_gauntlet "$scope_activation_dir" "$scope_binding_backdated_dir"
scope_binding_backdated_revision="${scope_activation_scope_revision/approved at: 2026-08-02T00:00:01Z/approved at: 2026-08-01T12:00:00Z}"
replace_line "$scope_binding_backdated_dir/GAUNTLET.md" \
  "$scope_activation_scope_revision" "$scope_binding_backdated_revision"
expect_failure "$temp_root/scope-binding-backdated.log" run_for "$project" \
  bash commands/validate-gauntlet.sh scope-binding-backdated --phase ready
grep -Fq \
  'Approved Unit manifest generation cannot be reconstructed from its approved unit, scope, and topology state' \
  "$temp_root/scope-binding-backdated.log" \
  || fail 'backdated scope revision did not reach the manifest-delta binding gate'

superseded_dir="$project/.ai/gauntlets/superseded-history"
copy_gauntlet "$gauntlet_dir" "$superseded_dir"
replace_matching_line "$superseded_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: superseded | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
insert_after_matching_line "$superseded_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Replacement active unit | scope: replacement artifact boundary'
replace_matching_line "$superseded_dir/GAUNTLET.md" '^- Active work unit:' '- Active work unit: unit-2'
superseded_scope_fingerprint="$(OPENCAW_PROJECT_ROOT="$project" bash -c '
  set -euo pipefail
  source commands/lib/gauntlet-common.sh
  gauntlet_unit_scope_fingerprint "$1" unit-1
' _ "$superseded_dir/GAUNTLET.md")"
supersession_marker="- Unit supersession: unit-1 | scope: $superseded_scope_fingerprint | replacements: unit-2 | reason: Replace the failed recovery unit with a newly isolated active boundary. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$superseded_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$supersession_marker"
superseded_manifest_fingerprint="$(unit_manifest_fingerprint \
  "$project" "$superseded_dir/GAUNTLET.md")"
superseded_manifest_revision="- Unit manifest revision: supersede-unit-1 | from: $unit_manifest_opened | to: $superseded_manifest_fingerprint | prior-units: unit-1 | current-units: unit-1,unit-2 | reason: Preserve the failed original boundary while adding its independently judgeable replacement. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$superseded_dir/GAUNTLET.md" \
  '^- Unit supersession: unit-1 ' "$superseded_manifest_revision"
set_gauntlet_field "$project" "$superseded_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
reset_integration_review "$project" "$superseded_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh superseded-history --phase ready >/dev/null

supersession_authorization_control_dir="$project/.ai/gauntlets/supersession-authorization-control"
copy_gauntlet "$superseded_dir" "$supersession_authorization_control_dir"
supersession_authorization_pr='https://github.com/example/opencaw-fixture/pull/300'
supersession_authorization_head='gauntlet-work/supersession-authorization-control/unit-2-remediation-1'
supersession_authorization_time='2026-08-02T00:00:02Z'
export FAKE_DATE_ISO="$supersession_authorization_time"
set_local_ref "$project" "$supersession_authorization_head" "$head_sha_7"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  supersession-authorization-control unit-2 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  supersession-authorization-control unit-2 opened "$supersession_authorization_pr" \
  "$supersession_authorization_head" none --head-sha "$head_sha_7" >/dev/null
supersession_authorization_open="$supersession_authorization_control_dir/pr-events/unit-2/event-001.md"
expect_line '- Unit manifest approved at: 2026-08-02T00:00:01Z' \
  "$supersession_authorization_control_dir/publication-checkpoints/unit-2/checkpoint-001.md"
expect_line "- Created at: $supersession_authorization_time" \
  "$supersession_authorization_open"
expect_line "- Recorded at: $supersession_authorization_time" \
  "$supersession_authorization_open"
expect_line '- Remediation trigger: .ai/gauntlets/supersession-authorization-control/rounds/integration/round-002.md' \
  "$supersession_authorization_open"
supersession_authorization_report="$critic_dir/supersession-authorization-unit-pass.md"
write_critic_report "$supersession_authorization_report" pass artifact.txt "$head_sha_7" \
  'The authorized replacement resolves the retained failure under its frozen scope.' \
  'Consume progressive QA, merge the replacement, and repeat integration criticism.'
run_for "$project" bash commands/record-gauntlet-round.sh \
  supersession-authorization-control unit-2 pass supersession-authorization-builder \
  supersession-authorization-critic fresh-session "$supersession_authorization_report" \
  --head-sha "$head_sha_7" \
  --builder-strategy 'Implement the approved replacement after its supersession edge is active.' \
  >/dev/null
expect_line "- Recorded at: $supersession_authorization_time" \
  "$supersession_authorization_control_dir/rounds/unit-2/round-001.md"
expect_line '- Remediation root: .ai/gauntlets/supersession-authorization-control/rounds/integration/round-002.md' \
  "$supersession_authorization_control_dir/rounds/unit-2/round-001.md"
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  supersession-authorization-control unit-2 qa-pass "$supersession_authorization_pr" \
  "$supersession_authorization_head" \
  "$supersession_authorization_pr#issuecomment-80" --head-sha "$head_sha_7" >/dev/null
expect_line "- Recorded at: $supersession_authorization_time" \
  "$supersession_authorization_control_dir/pr-events/unit-2/event-002.md"
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  supersession-authorization-control unit-2 merged "$supersession_authorization_pr" \
  "$supersession_authorization_head" \
  "$supersession_authorization_pr#issuecomment-81" --head-sha "$head_sha_7" \
  --merge-commit "$head_sha_7" >/dev/null
expect_line "- Merged at: $supersession_authorization_time" \
  "$supersession_authorization_control_dir/pr-events/unit-2/event-003.md"
expect_line "- Recorded at: $supersession_authorization_time" \
  "$supersession_authorization_control_dir/pr-events/unit-2/event-003.md"
supersession_authorization_integration_report="$critic_dir/supersession-authorization-integration-pass.md"
write_critic_report "$supersession_authorization_integration_report" pass artifact.txt "$head_sha_7" \
  'The complete artifact passes after the authorized replacement merge.' \
  'The accepted evidence chain may proceed to completion reporting.'
run_for "$project" bash commands/record-gauntlet-round.sh \
  supersession-authorization-control integration pass \
  supersession-authorization-integration-builder \
  supersession-authorization-integration-critic native-subagent \
  "$supersession_authorization_integration_report" --head-sha "$head_sha_7" \
  --builder-strategy 'Inspect the complete merged replacement against every guardrail.' \
  >/dev/null
run_for "$project" bash commands/validate-gauntlet.sh \
  supersession-authorization-control --phase ready >/dev/null
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  supersession-authorization-control --status complete --dry-run >/dev/null
unset FAKE_DATE_ISO

backdated_manifest_dir="$project/.ai/gauntlets/backdated-manifest-checkpoint"
copy_gauntlet "$supersession_authorization_control_dir" "$backdated_manifest_dir"
backdated_manifest_approval='2026-08-01T12:00:01Z'
backdated_manifest_marker="${supersession_marker/approved at: 2026-08-02T00:00:01Z/approved at: $backdated_manifest_approval}"
backdated_manifest_revision="${superseded_manifest_revision/approved at: 2026-08-02T00:00:01Z/approved at: $backdated_manifest_approval}"
replace_line "$backdated_manifest_dir/GAUNTLET.md" \
  "$supersession_marker" "$backdated_manifest_marker"
replace_line "$backdated_manifest_dir/GAUNTLET.md" \
  "$superseded_manifest_revision" "$backdated_manifest_revision"
expect_line '- Unit manifest approved at: 2026-08-02T00:00:01Z' \
  "$backdated_manifest_dir/publication-checkpoints/unit-2/checkpoint-001.md"
expect_line "$backdated_manifest_revision" "$backdated_manifest_dir/GAUNTLET.md"
expect_failure "$temp_root/backdated-manifest-checkpoint.log" run_for "$project" \
  bash commands/validate-gauntlet.sh backdated-manifest-checkpoint --phase ready
grep -Fq 'Publication checkpoint uses a Unit manifest not active at its Recorded at timestamp' \
  "$temp_root/backdated-manifest-checkpoint.log" \
  || fail 'backdated manifest checkpoint did not reach the generation-authorization gate'

future_supersession_dir="$project/.ai/gauntlets/future-supersession-checkpoint"
copy_gauntlet "$supersession_authorization_control_dir" "$future_supersession_dir"
future_supersession_approval_time='2026-08-02T00:00:03Z'
future_supersession_evidence_time='2026-08-02T00:00:04Z'
future_supersession_marker="${supersession_marker/approved at: 2026-08-02T00:00:01Z/approved at: $future_supersession_approval_time}"
future_supersession_revision="${superseded_manifest_revision/approved at: 2026-08-02T00:00:01Z/approved at: $future_supersession_approval_time}"
replace_line "$future_supersession_dir/GAUNTLET.md" \
  "$supersession_marker" "$future_supersession_marker"
replace_line "$future_supersession_dir/GAUNTLET.md" \
  "$superseded_manifest_revision" "$future_supersession_revision"

future_supersession_checkpoint="$future_supersession_dir/publication-checkpoints/unit-2/checkpoint-001.md"
future_supersession_open="$future_supersession_dir/pr-events/unit-2/event-001.md"
future_supersession_round="$future_supersession_dir/rounds/unit-2/round-001.md"
future_supersession_qa="$future_supersession_dir/pr-events/unit-2/event-002.md"
future_supersession_merge="$future_supersession_dir/pr-events/unit-2/event-003.md"
future_supersession_integration="$future_supersession_dir/rounds/integration/round-003.md"
expect_line "- Recorded at: $supersession_authorization_time" \
  "$future_supersession_checkpoint"
expect_line "- Unit manifest fingerprint: $superseded_manifest_fingerprint" \
  "$future_supersession_checkpoint"
replace_matching_line "$future_supersession_checkpoint" \
  '^- Unit manifest approved at:' \
  "- Unit manifest approved at: $future_supersession_approval_time"
refresh_copied_checkpoint_hashes "$future_supersession_dir"
for future_supersession_evidence in "$future_supersession_open" \
  "$future_supersession_round" "$future_supersession_qa" \
  "$future_supersession_merge" "$future_supersession_integration"; do
  replace_matching_line "$future_supersession_evidence" '^- Recorded at:' \
    "- Recorded at: $future_supersession_evidence_time"
done
replace_matching_line "$future_supersession_open" '^- Created at:' \
  "- Created at: $future_supersession_evidence_time"
replace_matching_line "$future_supersession_qa" '^- Created at:' \
  "- Created at: $future_supersession_evidence_time"
replace_matching_line "$future_supersession_qa" '^- QA comment created at:' \
  "- QA comment created at: $future_supersession_evidence_time"
replace_matching_line "$future_supersession_qa" '^- QA comment updated at:' \
  "- QA comment updated at: $future_supersession_evidence_time"
replace_matching_line "$future_supersession_merge" '^- Created at:' \
  "- Created at: $future_supersession_evidence_time"
replace_matching_line "$future_supersession_merge" '^- Closed at:' \
  "- Closed at: $future_supersession_evidence_time"
replace_matching_line "$future_supersession_merge" '^- Merged at:' \
  "- Merged at: $future_supersession_evidence_time"
refresh_copied_cross_evidence_hashes "$future_supersession_dir"
future_supersession_round_relative='.ai/gauntlets/future-supersession-checkpoint/rounds/unit-2/round-001.md'
future_supersession_comment_body="$(semantic_comment_body "$project" pass "$head_sha_7" \
  "$future_supersession_round_relative")"
replace_matching_line "$future_supersession_qa" '^- QA comment body sha256:' \
  "- QA comment body sha256: $(sha256_text "$future_supersession_comment_body")"
future_supersession_qa_ledger="$(select_ledger_line "$project" \
  "$future_supersession_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/future-supersession-checkpoint/pr-events/unit-2/event-002.md')"
replace_line "$future_supersession_dir/GAUNTLET.md" "$future_supersession_qa_ledger" \
  "${future_supersession_qa_ledger//pr-created: $supersession_authorization_time/pr-created: $future_supersession_evidence_time}"
future_supersession_qa_ledger="$(select_ledger_line "$project" \
  "$future_supersession_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/future-supersession-checkpoint/pr-events/unit-2/event-002.md')"
replace_line "$future_supersession_dir/GAUNTLET.md" "$future_supersession_qa_ledger" \
  "${future_supersession_qa_ledger//qa-created: $supersession_authorization_time/qa-created: $future_supersession_evidence_time}"
future_supersession_open_ledger="$(select_ledger_line "$project" \
  "$future_supersession_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/future-supersession-checkpoint/pr-events/unit-2/event-001.md')"
replace_line "$future_supersession_dir/GAUNTLET.md" "$future_supersession_open_ledger" \
  "${future_supersession_open_ledger//pr-created: $supersession_authorization_time/pr-created: $future_supersession_evidence_time}"
future_supersession_merge_ledger="$(select_ledger_line "$project" \
  "$future_supersession_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  '.ai/gauntlets/future-supersession-checkpoint/pr-events/unit-2/event-003.md')"
future_supersession_merge_ledger_updated="${future_supersession_merge_ledger//pr-created: $supersession_authorization_time/pr-created: $future_supersession_evidence_time}"
future_supersession_merge_ledger_updated="${future_supersession_merge_ledger_updated//pr-closed: $supersession_authorization_time/pr-closed: $future_supersession_evidence_time}"
replace_line "$future_supersession_dir/GAUNTLET.md" \
  "$future_supersession_merge_ledger" "$future_supersession_merge_ledger_updated"
refresh_copied_evidence_hashes "$future_supersession_dir"
sync_gauntlet_live_observations "$project" "$future_supersession_dir"
expect_line "- Created at: $future_supersession_evidence_time" \
  "$future_supersession_open"
expect_line "$future_supersession_marker" "$future_supersession_dir/GAUNTLET.md"
expect_line "$future_supersession_revision" "$future_supersession_dir/GAUNTLET.md"
expect_failure "$temp_root/future-supersession-checkpoint-ready.log" run_for "$project" \
  bash commands/validate-gauntlet.sh future-supersession-checkpoint --phase ready
if ! grep -Fq \
    'Publication checkpoint Unit supersession path was not active at its Recorded at timestamp' \
    "$temp_root/future-supersession-checkpoint-ready.log" \
  && ! grep -Fq \
    'Publication checkpoint uses a Unit manifest not active at its Recorded at timestamp' \
    "$temp_root/future-supersession-checkpoint-ready.log"; then
  fail 'future supersession checkpoint did not reach a supersession authorization gate'
fi
expect_failure "$temp_root/future-supersession-checkpoint-complete.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh \
  future-supersession-checkpoint --status complete --dry-run
[[ ! -f "$future_supersession_dir/GAUNTLET_REPORT.md" ]] \
  || fail 'future supersession checkpoint created a completion report'

future_trigger_dir="$project/.ai/gauntlets/future-trigger-checkpoint"
copy_gauntlet "$future_supersession_dir" "$future_trigger_dir"
replace_line "$future_trigger_dir/GAUNTLET.md" \
  "$future_supersession_marker" "$supersession_marker"
replace_line "$future_trigger_dir/GAUNTLET.md" \
  "$future_supersession_revision" "$superseded_manifest_revision"
future_trigger_root="$future_trigger_dir/rounds/integration/round-002.md"
future_trigger_time='2026-08-02T00:00:03Z'
replace_matching_line "$future_trigger_root" '^- Recorded at:' \
  "- Recorded at: $future_trigger_time"
future_trigger_root_hash="$(sha256_file "$future_trigger_root")"
future_trigger_checkpoint="$future_trigger_dir/publication-checkpoints/unit-2/checkpoint-001.md"
replace_matching_line "$future_trigger_checkpoint" \
  '^- Unit manifest approved at:' \
  '- Unit manifest approved at: 2026-08-02T00:00:01Z'
replace_matching_line "$future_trigger_checkpoint" \
  '^- Remediation trigger sha256:' \
  "- Remediation trigger sha256: $future_trigger_root_hash"
replace_matching_line "$future_trigger_checkpoint" \
  '^- Remediation root sha256:' \
  "- Remediation root sha256: $future_trigger_root_hash"
refresh_copied_checkpoint_hashes "$future_trigger_dir"
refresh_copied_cross_evidence_hashes "$future_trigger_dir"
future_trigger_qa="$future_trigger_dir/pr-events/unit-2/event-002.md"
future_trigger_round_relative='.ai/gauntlets/future-trigger-checkpoint/rounds/unit-2/round-001.md'
future_trigger_comment_body="$(semantic_comment_body "$project" pass "$head_sha_7" \
  "$future_trigger_round_relative")"
replace_matching_line "$future_trigger_qa" '^- QA comment body sha256:' \
  "- QA comment body sha256: $(sha256_text "$future_trigger_comment_body")"
refresh_copied_evidence_hashes "$future_trigger_dir"
sync_gauntlet_live_observations "$project" "$future_trigger_dir"
expect_line "- Recorded at: $supersession_authorization_time" \
  "$future_trigger_checkpoint"
expect_line "- Recorded at: $future_trigger_time" "$future_trigger_root"
expect_line "- Created at: $future_supersession_evidence_time" \
  "$future_trigger_dir/pr-events/unit-2/event-001.md"
expect_failure "$temp_root/future-trigger-checkpoint-ready.log" run_for "$project" \
  bash commands/validate-gauntlet.sh future-trigger-checkpoint --phase ready
grep -Fq 'Publication checkpoint remediation trigger was not active at its Recorded at timestamp' \
  "$temp_root/future-trigger-checkpoint-ready.log" \
  || fail 'future trigger checkpoint did not reach the trigger-authorization gate'
expect_failure "$temp_root/future-trigger-checkpoint-complete.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh \
  future-trigger-checkpoint --status complete --dry-run
[[ ! -f "$future_trigger_dir/GAUNTLET_REPORT.md" ]] \
  || fail 'future trigger checkpoint created a completion report'

missing_supersession_dir="$project/.ai/gauntlets/missing-supersession-marker"
copy_gauntlet "$superseded_dir" "$missing_supersession_dir"
replace_line "$missing_supersession_dir/GAUNTLET.md" \
  "${supersession_marker/superseded-history/missing-supersession-marker}" \
  '- No unit changes recorded.'
expect_failure "$temp_root/missing-supersession-marker.log" run_for "$project" \
  bash commands/validate-gauntlet.sh missing-supersession-marker --phase ready

stale_supersession_scope_dir="$project/.ai/gauntlets/stale-supersession-scope"
copy_gauntlet "$superseded_dir" "$stale_supersession_scope_dir"
stale_supersession_marker="${supersession_marker/scope: $superseded_scope_fingerprint/scope: 0000000000000000000000000000000000000000000000000000000000000000}"
replace_line "$stale_supersession_scope_dir/GAUNTLET.md" \
  "$supersession_marker" "$stale_supersession_marker"
expect_failure "$temp_root/stale-supersession-scope.log" run_for "$project" \
  bash commands/validate-gauntlet.sh stale-supersession-scope --phase ready

missing_supersession_replacement_dir="$project/.ai/gauntlets/missing-supersession-replacement"
copy_gauntlet "$superseded_dir" "$missing_supersession_replacement_dir"
replace_all_literal "$missing_supersession_replacement_dir/GAUNTLET.md" \
  'replacements: unit-2' 'replacements: absent-unit'
expect_failure "$temp_root/missing-supersession-replacement.log" run_for "$project" \
  bash commands/validate-gauntlet.sh missing-supersession-replacement --phase ready

self_supersession_replacement_dir="$project/.ai/gauntlets/self-supersession-replacement"
copy_gauntlet "$superseded_dir" "$self_supersession_replacement_dir"
replace_all_literal "$self_supersession_replacement_dir/GAUNTLET.md" \
  'replacements: unit-2' 'replacements: unit-1'
expect_failure "$temp_root/self-supersession-replacement.log" run_for "$project" \
  bash commands/validate-gauntlet.sh self-supersession-replacement --phase ready

nonactive_supersession_dir="$project/.ai/gauntlets/nonactive-supersession-replacement"
copy_gauntlet "$superseded_dir" "$nonactive_supersession_dir"
insert_after_matching_line "$nonactive_supersession_dir/GAUNTLET.md" \
  '^- .*unit-2 .*status:' \
  '- [x] unit-3 | status: superseded | title: Retired intermediate replacement | scope: retired intermediate boundary'
unit_three_scope="$(OPENCAW_PROJECT_ROOT="$project" bash -c '
  set -euo pipefail
  source commands/lib/gauntlet-common.sh
  gauntlet_unit_scope_fingerprint "$1" unit-3
' _ "$nonactive_supersession_dir/GAUNTLET.md")"
replace_all_literal "$nonactive_supersession_dir/GAUNTLET.md" \
  'replacements: unit-2' 'replacements: unit-3'
insert_after_matching_line "$nonactive_supersession_dir/GAUNTLET.md" \
  '^- Unit supersession: unit-1 ' \
  "- Unit supersession: unit-3 | scope: $unit_three_scope | replacements: unit-2 | reason: Retire the intermediate boundary in favor of the active replacement. | approved by: fixture-user | approved at: 2026-08-02T00:00:00Z"
expect_failure "$temp_root/nonactive-supersession-replacement.log" run_for "$project" \
  bash commands/validate-gauntlet.sh nonactive-supersession-replacement --phase ready

duplicate_supersession_dir="$project/.ai/gauntlets/duplicate-supersession-marker"
copy_gauntlet "$superseded_dir" "$duplicate_supersession_dir"
duplicate_supersession_marker="$(grep -F -- '- Unit supersession: unit-1 ' \
  "$duplicate_supersession_dir/GAUNTLET.md")"
insert_after_matching_line "$duplicate_supersession_dir/GAUNTLET.md" \
  '^- Unit supersession: unit-1 ' "$duplicate_supersession_marker"
expect_failure "$temp_root/duplicate-supersession-marker.log" run_for "$project" \
  bash commands/validate-gauntlet.sh duplicate-supersession-marker --phase ready

early_supersession_dir="$project/.ai/gauntlets/early-supersession-marker"
copy_gauntlet "$superseded_dir" "$early_supersession_dir"
replace_all_literal "$early_supersession_dir/GAUNTLET.md" \
  'approved at: 2026-08-02T00:00:01Z' 'approved at: 2000-01-01T00:00:00Z'
expect_failure "$temp_root/early-supersession-marker.log" run_for "$project" \
  bash commands/validate-gauntlet.sh early-supersession-marker --phase ready

superseded_report_dir="$project/.ai/gauntlets/superseded-report-history"
copy_gauntlet "$superseded_dir" "$superseded_report_dir"
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  superseded-report-history --status stopped >/dev/null
expect_line "${supersession_marker/superseded-history/superseded-report-history}" \
  "$superseded_report_dir/GAUNTLET.md"
grep -Fq -- '- Unit supersession: unit-1 ' "$superseded_report_dir/GAUNTLET_REPORT.md" \
  || fail 'stopped report omitted the canonical retained supersession history'

supersession_chain_dir="$project/.ai/gauntlets/supersession-chain"
copy_gauntlet "$superseded_dir" "$supersession_chain_dir"
replace_matching_line "$supersession_chain_dir/GAUNTLET.md" \
  '^- .*unit-2 .*status:' \
  '- [x] unit-2 | status: superseded | title: Replacement active unit | scope: replacement artifact boundary'
insert_after_matching_line "$supersession_chain_dir/GAUNTLET.md" \
  '^- .*unit-2 .*status:' \
  '- [ ] unit-3 | status: pending | title: Final inherited recovery unit | scope: final isolated replacement artifact boundary'
replace_matching_line "$supersession_chain_dir/GAUNTLET.md" \
  '^- Active work unit:' '- Active work unit: unit-3'
supersession_chain_unit_two_scope="$(unit_scope_fingerprint \
  "$project" "$supersession_chain_dir/GAUNTLET.md" unit-2)"
supersession_chain_marker="- Unit supersession: unit-2 | scope: $supersession_chain_unit_two_scope | replacements: unit-3 | reason: Replace the intermediate recovery boundary while preserving its inherited failure obligation. | approved by: fixture-user | approved at: 2026-08-02T00:00:02Z"
insert_after_matching_line "$supersession_chain_dir/GAUNTLET.md" \
  '^- Unit manifest revision: supersede-unit-1 ' "$supersession_chain_marker"
supersession_chain_manifest="$(unit_manifest_fingerprint \
  "$project" "$supersession_chain_dir/GAUNTLET.md")"
supersession_chain_revision="- Unit manifest revision: supersede-unit-2 | from: $superseded_manifest_fingerprint | to: $supersession_chain_manifest | prior-units: unit-1,unit-2 | current-units: unit-1,unit-2,unit-3 | reason: Preserve both retired generations and freeze the final active recovery leaf. | approved by: fixture-user | approved at: 2026-08-02T00:00:02Z"
insert_after_matching_line "$supersession_chain_dir/GAUNTLET.md" \
  '^- Unit supersession: unit-2 ' "$supersession_chain_revision"
set_gauntlet_field "$project" "$supersession_chain_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
reset_integration_review "$project" "$supersession_chain_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh supersession-chain --phase ready >/dev/null

supersession_cycle_dir="$project/.ai/gauntlets/supersession-cycle"
copy_gauntlet "$supersession_chain_dir" "$supersession_cycle_dir"
replace_all_literal "$supersession_cycle_dir/GAUNTLET.md" \
  'replacements: unit-3' 'replacements: unit-1'
supersession_cycle_manifest="$(unit_manifest_fingerprint \
  "$project" "$supersession_cycle_dir/GAUNTLET.md")"
replace_all_literal "$supersession_cycle_dir/GAUNTLET.md" \
  "$supersession_chain_manifest" "$supersession_cycle_manifest"
expect_failure "$temp_root/supersession-cycle.log" run_for "$project" \
  bash commands/validate-gauntlet.sh supersession-cycle --phase ready

sync_gauntlet_live_observations "$project" "$supersession_chain_dir"
export FAKE_DATE_ISO=2026-08-02T00:00:02Z
supersession_chain_pr='https://github.com/example/opencaw-fixture/pull/291'
supersession_chain_head='gauntlet-work/supersession-chain/unit-3-remediation-1'
set_local_ref "$project" "$supersession_chain_head" "$head_sha_7"
supersession_chain_readiness="$(OPENCAW_REPORT_DIR="$project/.ai/reports/supersession-chain" \
  run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  supersession-chain unit-3 "$project/progress-validation.md")"
grep -q "^UNIT_MANIFEST_FINGERPRINT=$supersession_chain_manifest$" \
  <<<"$supersession_chain_readiness" \
  || fail 'supersession-chain readiness did not freeze manifest generation M3'
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-chain \
  unit-3 opened "$supersession_chain_pr" "$supersession_chain_head" none \
  --head-sha "$head_sha_7" >/dev/null
supersession_chain_open="$supersession_chain_dir/pr-events/unit-3/event-001.md"
supersession_chain_root='.ai/gauntlets/supersession-chain/rounds/integration/round-002.md'
expect_line "- Remediation trigger: $supersession_chain_root" \
  "$supersession_chain_open"
expect_line "- Unit manifest fingerprint: $supersession_chain_manifest" \
  "$supersession_chain_open"
supersession_chain_report="$critic_dir/supersession-chain-unit-pass.md"
write_critic_report "$supersession_chain_report" pass artifact.txt "$head_sha_7" \
  'The final descendant resolves the original integration failure across both retired boundaries.' \
  'Merge the final descendant and repeat complete-artifact integration criticism.'
run_for "$project" bash commands/record-gauntlet-round.sh supersession-chain unit-3 pass \
  supersession-chain-builder supersession-chain-critic fresh-session \
  "$supersession_chain_report" --head-sha "$head_sha_7" \
  --builder-strategy 'Replace both retired recovery boundaries with a final independently verified implementation.' \
  >/dev/null
supersession_chain_round="$supersession_chain_dir/rounds/unit-3/round-001.md"
expect_line "- Remediation root: $supersession_chain_root" \
  "$supersession_chain_round"
expect_line "- Remediation root sha256: $(sha256_file "$project/$supersession_chain_root")" \
  "$supersession_chain_round"
expect_line "- Unit manifest fingerprint: $supersession_chain_manifest" \
  "$supersession_chain_round"
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-chain \
  unit-3 qa-pass "$supersession_chain_pr" "$supersession_chain_head" \
  "$supersession_chain_pr#issuecomment-70" --head-sha "$head_sha_7" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-chain \
  unit-3 merged "$supersession_chain_pr" "$supersession_chain_head" \
  "$supersession_chain_pr#issuecomment-71" --head-sha "$head_sha_7" \
  --merge-commit "$head_sha_7" >/dev/null
supersession_chain_integration_report="$critic_dir/supersession-chain-integration-pass.md"
write_critic_report "$supersession_chain_integration_report" pass artifact.txt "$head_sha_7" \
  'The complete artifact passes after the full transitive supersession recovery.' \
  'Generate the completion event for the final retained manifest generation.'
run_for "$project" bash commands/record-gauntlet-round.sh supersession-chain \
  integration pass supersession-chain-integration-builder \
  supersession-chain-integration-critic native-subagent \
  "$supersession_chain_integration_report" --head-sha "$head_sha_7" \
  --builder-strategy 'Inspect the exact integrated descendant chain and every retained guardrail.' \
  >/dev/null
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  supersession-chain --status complete >/dev/null
expect_line '- Status: passed' "$supersession_chain_dir/GAUNTLET.md"
expect_line "- Unit manifest fingerprint: $supersession_chain_manifest" \
  "$supersession_chain_dir/completion-events/event-001.md"
run_for "$project" bash commands/validate-gauntlet.sh supersession-chain \
  --phase complete >/dev/null
unset FAKE_DATE_ISO

supersession_edge_rewrite_dir="$project/.ai/gauntlets/supersession-edge-rewrite"
copy_gauntlet "$supersession_chain_dir" "$supersession_edge_rewrite_dir"
replace_all_literal "$supersession_edge_rewrite_dir/GAUNTLET.md" \
  'replacements: unit-2' 'replacements: unit-3'
refresh_copied_evidence_hashes "$supersession_edge_rewrite_dir"
expect_failure "$temp_root/supersession-edge-rewrite.log" run_for "$project" \
  bash commands/validate-gauntlet.sh supersession-edge-rewrite --phase complete

supersession_split_dir="$project/.ai/gauntlets/supersession-split"
copy_gauntlet "$superseded_dir" "$supersession_split_dir"
insert_after_matching_line "$supersession_split_dir/GAUNTLET.md" \
  '^- .*unit-2 .*status:' \
  '- [ ] unit-3 | status: pending | title: Second split recovery leaf | scope: second independently judgeable replacement boundary'
replace_all_literal "$supersession_split_dir/GAUNTLET.md" \
  'replacements: unit-2' 'replacements: unit-2,unit-3'
supersession_split_manifest="$(unit_manifest_fingerprint \
  "$project" "$supersession_split_dir/GAUNTLET.md")"
supersession_split_revision="- Unit manifest revision: supersede-unit-1 | from: $unit_manifest_opened | to: $supersession_split_manifest | prior-units: unit-1 | current-units: unit-1,unit-2,unit-3 | reason: Preserve the failed original boundary and require both independently judgeable recovery leaves. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
replace_line "$supersession_split_dir/GAUNTLET.md" \
  "$superseded_manifest_revision" "$supersession_split_revision"
set_gauntlet_field "$project" "$supersession_split_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
reset_integration_review "$project" "$supersession_split_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh supersession-split --phase ready >/dev/null
export FAKE_DATE_ISO=2026-08-02T00:00:01Z
supersession_split_pr_two='https://github.com/example/opencaw-fixture/pull/292'
supersession_split_head_two='gauntlet-work/supersession-split/unit-2-remediation-1'
set_local_ref "$project" "$supersession_split_head_two" "$head_sha_7"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  supersession-split unit-2 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-split \
  unit-2 opened "$supersession_split_pr_two" "$supersession_split_head_two" none \
  --head-sha "$head_sha_7" >/dev/null
expect_line '- Remediation trigger: .ai/gauntlets/supersession-split/rounds/integration/round-002.md' \
  "$supersession_split_dir/pr-events/unit-2/event-001.md"
supersession_split_report_two="$critic_dir/supersession-split-unit-two.md"
write_critic_report "$supersession_split_report_two" pass artifact.txt "$head_sha_7" \
  'The first split leaf satisfies its isolated recovery scope.' \
  'Merge this leaf, then complete the still-pending second leaf.'
run_for "$project" bash commands/record-gauntlet-round.sh supersession-split unit-2 pass \
  supersession-split-builder-two supersession-split-critic-two fresh-session \
  "$supersession_split_report_two" --head-sha "$head_sha_7" \
  --builder-strategy 'Implement and verify the first disjoint split recovery leaf.' >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-split \
  unit-2 qa-pass "$supersession_split_pr_two" "$supersession_split_head_two" \
  "$supersession_split_pr_two#issuecomment-72" --head-sha "$head_sha_7" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-split \
  unit-2 merged "$supersession_split_pr_two" "$supersession_split_head_two" \
  "$supersession_split_pr_two#issuecomment-73" --head-sha "$head_sha_7" \
  --merge-commit "$head_sha_7" >/dev/null
supersession_split_premature_report="$critic_dir/supersession-split-premature-integration.md"
write_critic_report "$supersession_split_premature_report" pass artifact.txt "$head_sha_7" \
  'One split leaf remains pending, so the artifact is not integration-complete.' \
  'Complete the second active split leaf before integration review.'
expect_failure "$temp_root/supersession-split-one-leaf.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh supersession-split integration pass \
  supersession-split-premature-builder supersession-split-premature-critic \
  fresh-session "$supersession_split_premature_report" --head-sha "$head_sha_7" \
  --builder-strategy 'Attempt integration after only one of two required split leaves.'

supersession_split_pr_three='https://github.com/example/opencaw-fixture/pull/293'
supersession_split_head_three='gauntlet-work/supersession-split/unit-3-remediation-1'
set_local_ref "$project" "$supersession_split_head_three" "$head_sha_8"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  supersession-split unit-3 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-split \
  unit-3 opened "$supersession_split_pr_three" "$supersession_split_head_three" none \
  --head-sha "$head_sha_8" >/dev/null
expect_line '- Remediation trigger: .ai/gauntlets/supersession-split/rounds/integration/round-002.md' \
  "$supersession_split_dir/pr-events/unit-3/event-001.md"
supersession_split_report_three="$critic_dir/supersession-split-unit-three.md"
write_critic_report "$supersession_split_report_three" pass artifact.txt "$head_sha_8" \
  'The second split leaf now satisfies its independent recovery scope.' \
  'Merge the final leaf and run the integration critic over both leaves.'
run_for "$project" bash commands/record-gauntlet-round.sh supersession-split unit-3 pass \
  supersession-split-builder-three supersession-split-critic-three fresh-session \
  "$supersession_split_report_three" --head-sha "$head_sha_8" \
  --builder-strategy 'Implement the second disjoint split leaf after the first leaf merge.' >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-split \
  unit-3 qa-pass "$supersession_split_pr_three" "$supersession_split_head_three" \
  "$supersession_split_pr_three#issuecomment-74" --head-sha "$head_sha_8" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh supersession-split \
  unit-3 merged "$supersession_split_pr_three" "$supersession_split_head_three" \
  "$supersession_split_pr_three#issuecomment-75" --head-sha "$head_sha_8" \
  --merge-commit "$head_sha_8" >/dev/null
supersession_split_integration_report="$critic_dir/supersession-split-integration.md"
write_critic_report "$supersession_split_integration_report" pass artifact.txt "$head_sha_8" \
  'Both split recovery leaves pass together on the exact integration chain tip.' \
  'Generate completion evidence bound to the two-leaf manifest.'
run_for "$project" bash commands/record-gauntlet-round.sh supersession-split \
  integration pass supersession-split-integration-builder \
  supersession-split-integration-critic native-subagent \
  "$supersession_split_integration_report" --head-sha "$head_sha_8" \
  --builder-strategy 'Inspect the integrated two-leaf recovery and all frozen guardrails.' \
  >/dev/null
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  supersession-split --status complete >/dev/null
expect_line '- Status: passed' "$supersession_split_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh supersession-split \
  --phase complete >/dev/null
unset FAKE_DATE_ISO

critic_failure_supersession_dir="$project/.ai/gauntlets/critic-failure-supersession"
copy_gauntlet "$unconsumed_close_dir" "$critic_failure_supersession_dir"
replace_matching_line "$critic_failure_supersession_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: superseded | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
insert_after_matching_line "$critic_failure_supersession_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: Critic-failure descendant | scope: replacement for the critic-failed artifact boundary'
replace_matching_line "$critic_failure_supersession_dir/GAUNTLET.md" \
  '^- Active work unit:' '- Active work unit: unit-2'
critic_failure_old_scope="$(unit_scope_fingerprint \
  "$project" "$critic_failure_supersession_dir/GAUNTLET.md" unit-1)"
critic_failure_marker="- Unit supersession: unit-1 | scope: $critic_failure_old_scope | replacements: unit-2 | reason: Replace the closed critic-failed unit without losing its causal obligation. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$critic_failure_supersession_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$critic_failure_marker"
critic_failure_manifest="$(unit_manifest_fingerprint \
  "$project" "$critic_failure_supersession_dir/GAUNTLET.md")"
critic_failure_revision="- Unit manifest revision: critic-failure-descendant | from: $unit_manifest_opened | to: $critic_failure_manifest | prior-units: unit-1 | current-units: unit-1,unit-2 | reason: Freeze the retained critic-failure ancestry and its active descendant. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$critic_failure_supersession_dir/GAUNTLET.md" \
  '^- Unit supersession: unit-1 ' "$critic_failure_revision"
set_gauntlet_field "$project" "$critic_failure_supersession_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
reset_integration_review "$project" "$critic_failure_supersession_dir/GAUNTLET.md"
export FAKE_DATE_ISO=2026-08-02T00:00:01Z
critic_failure_descendant_pr='https://github.com/example/opencaw-fixture/pull/294'
critic_failure_descendant_head='gauntlet-work/critic-failure-supersession/unit-2-remediation-1'
set_local_ref "$project" "$critic_failure_descendant_head" "$head_sha_2"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  critic-failure-supersession unit-2 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  critic-failure-supersession unit-2 opened "$critic_failure_descendant_pr" \
  "$critic_failure_descendant_head" none --head-sha "$head_sha_2" >/dev/null
expect_line '- Remediation trigger: .ai/gauntlets/critic-failure-supersession/pr-events/unit-1/event-003.md' \
  "$critic_failure_supersession_dir/pr-events/unit-2/event-001.md"
critic_failure_descendant_report="$critic_dir/critic-failure-descendant.md"
write_critic_report "$critic_failure_descendant_report" pass artifact.txt "$head_sha_2" \
  'The descendant resolves the closed ancestor critic failure.' \
  'Preserve the original round as the remediation root for downstream replay.'
run_for "$project" bash commands/record-gauntlet-round.sh \
  critic-failure-supersession unit-2 pass critic-failure-descendant-builder \
  critic-failure-descendant-critic fresh-session "$critic_failure_descendant_report" \
  --head-sha "$head_sha_2" \
  --builder-strategy 'Replace the critic-failed ancestor with a distinct verified descendant.' \
  >/dev/null
expect_line '- Remediation root: .ai/gauntlets/critic-failure-supersession/rounds/unit-1/round-001.md' \
  "$critic_failure_supersession_dir/rounds/unit-2/round-001.md"
unset FAKE_DATE_ISO

qa_failure_supersession_dir="$project/.ai/gauntlets/qa-failure-supersession"
copy_gauntlet "$ready_snapshot" "$qa_failure_supersession_dir"
qa_failure_ancestor_pr='https://github.com/example/opencaw-fixture/pull/295'
qa_failure_ancestor_head='gauntlet-work/qa-failure-supersession/unit-1'
set_local_ref "$project" "$qa_failure_ancestor_head" "$head_sha_3"
run_for "$project" bash commands/record-gauntlet-pr-event.sh qa-failure-supersession \
  unit-1 opened "$qa_failure_ancestor_pr" "$qa_failure_ancestor_head" none \
  --head-sha "$head_sha_3" >/dev/null
run_for "$project" bash commands/record-gauntlet-round.sh qa-failure-supersession \
  unit-1 pass qa-failure-ancestor-builder qa-failure-ancestor-critic fresh-session \
  "$pass_report" --head-sha "$head_sha_3" \
  --builder-strategy 'Build the ancestor artifact that passes criticism before independent PR QA.' \
  >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh qa-failure-supersession \
  unit-1 qa-fail "$qa_failure_ancestor_pr" "$qa_failure_ancestor_head" \
  "$qa_failure_ancestor_pr#issuecomment-76" --head-sha "$head_sha_3" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh qa-failure-supersession \
  unit-1 closed "$qa_failure_ancestor_pr" "$qa_failure_ancestor_head" \
  "$qa_failure_ancestor_pr#issuecomment-77" --head-sha "$head_sha_3" >/dev/null
replace_matching_line "$qa_failure_supersession_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: superseded | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
insert_after_matching_line "$qa_failure_supersession_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [ ] unit-2 | status: pending | title: QA-failure descendant | scope: replacement for the QA-failed artifact boundary'
replace_matching_line "$qa_failure_supersession_dir/GAUNTLET.md" \
  '^- Active work unit:' '- Active work unit: unit-2'
qa_failure_old_scope="$(unit_scope_fingerprint \
  "$project" "$qa_failure_supersession_dir/GAUNTLET.md" unit-1)"
qa_failure_marker="- Unit supersession: unit-1 | scope: $qa_failure_old_scope | replacements: unit-2 | reason: Replace the closed QA-failed unit without erasing the independent QA failure. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$qa_failure_supersession_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$qa_failure_marker"
qa_failure_manifest="$(unit_manifest_fingerprint \
  "$project" "$qa_failure_supersession_dir/GAUNTLET.md")"
qa_failure_revision="- Unit manifest revision: qa-failure-descendant | from: $unit_manifest_opened | to: $qa_failure_manifest | prior-units: unit-1 | current-units: unit-1,unit-2 | reason: Freeze the retained QA-failure ancestry and its active descendant. | approved by: fixture-user | approved at: 2026-08-02T00:00:01Z"
insert_after_matching_line "$qa_failure_supersession_dir/GAUNTLET.md" \
  '^- Unit supersession: unit-1 ' "$qa_failure_revision"
set_gauntlet_field "$project" "$qa_failure_supersession_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
reset_integration_review "$project" "$qa_failure_supersession_dir/GAUNTLET.md"
export FAKE_DATE_ISO=2026-08-02T00:00:01Z
qa_failure_descendant_pr='https://github.com/example/opencaw-fixture/pull/296'
qa_failure_descendant_head='gauntlet-work/qa-failure-supersession/unit-2-remediation-1'
set_local_ref "$project" "$qa_failure_descendant_head" "$head_sha_4"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  qa-failure-supersession unit-2 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh \
  qa-failure-supersession unit-2 opened "$qa_failure_descendant_pr" \
  "$qa_failure_descendant_head" none --head-sha "$head_sha_4" >/dev/null
expect_line '- Remediation trigger: .ai/gauntlets/qa-failure-supersession/pr-events/unit-1/event-003.md' \
  "$qa_failure_supersession_dir/pr-events/unit-2/event-001.md"
qa_failure_descendant_report="$critic_dir/qa-failure-descendant.md"
write_critic_report "$qa_failure_descendant_report" pass artifact.txt "$head_sha_4" \
  'The descendant resolves the independently detected ancestor QA failure.' \
  'Preserve the QA-fail event as the durable remediation root.'
run_for "$project" bash commands/record-gauntlet-round.sh qa-failure-supersession \
  unit-2 pass qa-failure-descendant-builder qa-failure-descendant-critic \
  fresh-session "$qa_failure_descendant_report" --head-sha "$head_sha_4" \
  --builder-strategy 'Replace the QA-failed ancestor with an independently verified descendant.' \
  >/dev/null
expect_line '- Remediation root: .ai/gauntlets/qa-failure-supersession/pr-events/unit-1/event-002.md' \
  "$qa_failure_supersession_dir/rounds/unit-2/round-001.md"

later_ancestor_dir="$project/.ai/gauntlets/later-same-second-ancestor-failure"
copy_gauntlet "$qa_failure_supersession_dir" "$later_ancestor_dir"
later_ancestor_qa="$later_ancestor_dir/pr-events/unit-1/event-002.md"
later_ancestor_close="$later_ancestor_dir/pr-events/unit-1/event-003.md"
earlier_descendant_open="$later_ancestor_dir/pr-events/unit-2/event-001.md"
earlier_descendant_round="$later_ancestor_dir/rounds/unit-2/round-001.md"
later_ancestor_time='2026-08-02T00:00:01Z'
replace_matching_line "$later_ancestor_qa" '^- Recorded at:' \
  "- Recorded at: $later_ancestor_time"
replace_matching_line "$later_ancestor_close" '^- Closed at:' \
  "- Closed at: $later_ancestor_time"
replace_matching_line "$later_ancestor_close" '^- Recorded at:' \
  "- Recorded at: $later_ancestor_time"
later_ancestor_close_relative='.ai/gauntlets/later-same-second-ancestor-failure/pr-events/unit-1/event-003.md'
later_ancestor_qa_relative='.ai/gauntlets/later-same-second-ancestor-failure/pr-events/unit-1/event-002.md'
replace_line "$earlier_descendant_open" \
  "- Remediation trigger: $later_ancestor_close_relative" \
  '- Remediation trigger: none'
earlier_descendant_checkpoint_relative="$(sed -nE \
  's/^- Publication checkpoint: (.*)$/\1/p' "$earlier_descendant_open" | head -n 1)"
earlier_descendant_checkpoint="$project/$earlier_descendant_checkpoint_relative"
replace_line "$earlier_descendant_checkpoint" \
  "- Remediation trigger: $later_ancestor_close_relative" \
  '- Remediation trigger: none'
replace_matching_line "$earlier_descendant_checkpoint" \
  '^- Remediation trigger sha256:' '- Remediation trigger sha256: none'
replace_line "$earlier_descendant_checkpoint" \
  "- Remediation root: $later_ancestor_qa_relative" '- Remediation root: none'
replace_matching_line "$earlier_descendant_checkpoint" \
  '^- Remediation root sha256:' '- Remediation root sha256: none'
earlier_descendant_root_hash="$(sed -nE \
  's/^- Remediation root sha256: (.*)$/\1/p' "$earlier_descendant_round" | head -n 1)"
replace_line "$earlier_descendant_round" \
  "- Remediation root: $later_ancestor_qa_relative" '- Remediation root: none'
replace_line "$earlier_descendant_round" \
  "- Remediation root sha256: $earlier_descendant_root_hash" \
  '- Remediation root sha256: none'
replace_all_literal "$later_ancestor_dir/GAUNTLET.md" \
  "| trigger: $later_ancestor_close_relative |" '| trigger: none |'
replace_all_literal "$later_ancestor_dir/GAUNTLET.md" \
  "| root: $later_ancestor_qa_relative | root-sha256: $earlier_descendant_root_hash |" \
  '| root: none | root-sha256: none |'
replace_all_literal "$later_ancestor_dir/GAUNTLET.md" \
  'pr-closed: 2026-08-01T12:00:00Z | checkpoint:' \
  "pr-closed: $later_ancestor_time | checkpoint:"
refresh_copied_checkpoint_hashes "$later_ancestor_dir"
refresh_copied_cross_evidence_hashes "$later_ancestor_dir"
refresh_copied_evidence_hashes "$later_ancestor_dir"

later_ancestor_qa_ledger="$(select_ledger_line "$project" \
  "$later_ancestor_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  "$later_ancestor_qa_relative")"
later_ancestor_close_ledger="$(select_ledger_line "$project" \
  "$later_ancestor_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  "$later_ancestor_close_relative")"
earlier_descendant_relative='.ai/gauntlets/later-same-second-ancestor-failure/pr-events/unit-2/event-001.md'
earlier_descendant_ledger="$(select_ledger_line "$project" \
  "$later_ancestor_dir/GAUNTLET.md" 'Progress PR Ledger' record \
  "$earlier_descendant_relative")"
replace_line "$later_ancestor_dir/GAUNTLET.md" "$later_ancestor_qa_ledger" \
  '__LATER_ANCESTOR_QA__'
replace_line "$later_ancestor_dir/GAUNTLET.md" "$later_ancestor_close_ledger" \
  '__LATER_ANCESTOR_CLOSE__'
replace_line "$later_ancestor_dir/GAUNTLET.md" "$earlier_descendant_ledger" \
  '__EARLIER_DESCENDANT_OPEN__'
replace_line "$later_ancestor_dir/GAUNTLET.md" '__LATER_ANCESTOR_QA__' \
  "$earlier_descendant_ledger"
replace_line "$later_ancestor_dir/GAUNTLET.md" '__LATER_ANCESTOR_CLOSE__' \
  "$later_ancestor_qa_ledger"
replace_line "$later_ancestor_dir/GAUNTLET.md" '__EARLIER_DESCENDANT_OPEN__' \
  "$later_ancestor_close_ledger"

later_ancestor_name='later-same-second-ancestor-failure'
later_ancestor_integration="gauntlet/$later_ancestor_name"
later_ancestor_head="gauntlet-work/$later_ancestor_name/unit-1"
earlier_descendant_head="gauntlet-work/$later_ancestor_name/unit-2-remediation-1"
later_ancestor_url='https://github.com/example/opencaw-fixture/pull/295'
earlier_descendant_url='https://github.com/example/opencaw-fixture/pull/296'
set_local_ref "$project" "$later_ancestor_integration" "$base_commit_sha"
set_remote_ref "$project" "$later_ancestor_integration" "$base_commit_sha"
set_local_ref "$project" "$later_ancestor_head" "$head_sha_3"
set_remote_ref "$project" "$later_ancestor_head" "$head_sha_3"
set_local_ref "$project" "$earlier_descendant_head" "$head_sha_4"
set_remote_ref "$project" "$earlier_descendant_head" "$head_sha_4"
later_ancestor_marker="$(opened_publication_marker \
  "$project" "$later_ancestor_name" unit-1)"
earlier_descendant_marker="$(opened_publication_marker \
  "$project" "$later_ancestor_name" unit-2)"
set_pr_observation "$later_ancestor_url" "$later_ancestor_head" "$head_sha_3" \
  "$later_ancestor_integration" CLOSED false none none none none \
  "$base_commit_sha" false example/opencaw-fixture 2026-08-01T12:00:00Z \
  "$later_ancestor_time" "$later_ancestor_marker"
set_pr_observation "$earlier_descendant_url" "$earlier_descendant_head" \
  "$head_sha_4" "$later_ancestor_integration" OPEN false none none none none \
  "$base_commit_sha" false example/opencaw-fixture "$later_ancestor_time" none \
  "$earlier_descendant_marker"
expect_line '- Remediation trigger: none' "$earlier_descendant_open"
expect_line '- Remediation root: none' "$earlier_descendant_round"
run_for "$project" bash commands/validate-gauntlet.sh \
  "$later_ancestor_name" --phase ready >/dev/null
unset FAKE_DATE_ISO

post_integration_unit_report="$critic_dir/post-integration-unit-pass.md"
write_critic_report "$post_integration_unit_report" pass artifact.txt "$head_sha_7" \
  'The reopened recovery behavior now satisfies the frozen unit criteria.' \
  'Return the corrected complete artifact to a new integration critic.'
sync_gauntlet_live_observations "$project" "$gauntlet_dir"
expect_failure "$temp_root/integration-remediation-requires-new-pr.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-without-remediation-pr critic-without-remediation-pr fresh-session "$post_integration_unit_report" \
  --head-sha "$head_sha_7" --builder-strategy "$builder_strategy_6"
grep -Fq 'Work-unit rounds require a live progress PR: unit-1' \
  "$temp_root/integration-remediation-requires-new-pr.log" \
  || fail 'integration remediation without a new PR hit the wrong rejection guard'
remediation_pr_url='https://github.com/example/opencaw-fixture/pull/208'
remediation_head='gauntlet-work/fixture-gauntlet/unit-1-remediation-1'
set_local_ref "$project" "$remediation_head" "$head_sha_7"
remediation_readiness_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/remediation" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress \
  fixture-gauntlet unit-1 "$project/progress-validation.md")"
grep -q '^TARGET_BRANCH=gauntlet/fixture-gauntlet$' <<<"$remediation_readiness_output" \
  || fail 'remediation PR readiness changed the durable integration target'
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_4"
set_pr_observation "$remediation_pr_url" "$remediation_head" "$head_sha_7" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$base_commit_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/remediation-open-rewound-live-target.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  "$remediation_pr_url" "$remediation_head" none --head-sha "$head_sha_7"
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 opened \
  "$remediation_pr_url" "$remediation_head" none --head-sha "$head_sha_7" >/dev/null
expect_file "$gauntlet_dir/pr-events/unit-1/event-007.md"
expect_line '- Remediation trigger: .ai/gauntlets/fixture-gauntlet/rounds/integration/round-002.md' \
  "$gauntlet_dir/pr-events/unit-1/event-007.md"
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
set_pr_observation "$remediation_pr_url" "$remediation_head" "$head_sha_7" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$head_sha_4"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/remediation-round-rewound-local-target.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-stale-local-target critic-stale-local-target fresh-session \
  "$post_integration_unit_report" --head-sha "$head_sha_7" \
  --builder-strategy "$builder_strategy_6"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_4"
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  builder-4 critic-4 fresh-session "$post_integration_unit_report" \
  --head-sha "$head_sha_7" --builder-strategy "$builder_strategy_6" >/dev/null
expect_file "$gauntlet_dir/rounds/unit-1/round-005.md"
remediation_stale_pass_comment="$remediation_pr_url#issuecomment-9020"
set_semantic_comment_observation "$project" "$remediation_stale_pass_comment" \
  "$remediation_pr_url" pass "$head_sha_7" \
  '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-005.md'
set_pr_observation "$remediation_pr_url" "$remediation_head" "$head_sha_7" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$base_commit_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/remediation-qa-pass-rewound-live-target.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$remediation_pr_url" "$remediation_head" "$remediation_stale_pass_comment" \
  --head-sha "$head_sha_7"
remediation_stale_fail_comment="$remediation_pr_url#issuecomment-9021"
set_semantic_comment_observation "$project" "$remediation_stale_fail_comment" \
  "$remediation_pr_url" fail "$head_sha_7" \
  '.ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-005.md'
set_local_ref "$project" gauntlet/fixture-gauntlet "$base_commit_sha"
set_pr_observation "$remediation_pr_url" "$remediation_head" "$head_sha_7" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$head_sha_4"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/remediation-qa-fail-rewound-local-target.log" run_for "$project" \
  bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-fail \
  "$remediation_pr_url" "$remediation_head" "$remediation_stale_fail_comment" \
  --head-sha "$head_sha_7"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_4"
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 qa-pass \
  "$remediation_pr_url" "$remediation_head" \
  'https://github.com/example/opencaw-fixture/pull/208#issuecomment-24' --head-sha "$head_sha_7" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh fixture-gauntlet unit-1 merged \
  "$remediation_pr_url" "$remediation_head" \
  'https://github.com/example/opencaw-fixture/pull/208#issuecomment-25' \
  --head-sha "$head_sha_7" --merge-commit "$head_sha_7" >/dev/null
expect_file "$gauntlet_dir/pr-events/unit-1/event-009.md"
expect_line "- Target base SHA: $head_sha_4" "$gauntlet_dir/pr-events/unit-1/event-009.md"
expect_line '- Merged by bot: false' "$gauntlet_dir/pr-events/unit-1/event-009.md"
[[ "$(pr_event_file_count "$gauntlet_dir")" == 9 ]] \
  || fail 'integration remediation did not retain both progress PR histories'
same_second_chain_time="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$gauntlet_dir/rounds/integration/round-002.md" | head -n 1)"
for same_second_evidence in \
  "$gauntlet_dir/pr-events/unit-1/event-007.md" \
  "$gauntlet_dir/rounds/unit-1/round-005.md" \
  "$gauntlet_dir/pr-events/unit-1/event-008.md" \
  "$gauntlet_dir/pr-events/unit-1/event-009.md"; do
  [[ "$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
      "$same_second_evidence" | head -n 1)" == "$same_second_chain_time" ]] \
    || fail "explicit remediation chain lost its same-second replay tie: $same_second_evidence"
done
expect_line '- Remediation root: .ai/gauntlets/fixture-gauntlet/rounds/integration/round-002.md' \
  "$gauntlet_dir/rounds/unit-1/round-005.md"
expect_line '- Critic round: .ai/gauntlets/fixture-gauntlet/rounds/unit-1/round-005.md' \
  "$gauntlet_dir/pr-events/unit-1/event-008.md"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase ready >/dev/null

final_integration_report="$critic_dir/final-integration-pass.md"
write_critic_report "$final_integration_report" pass artifact.txt "$head_sha_7" \
  'No remaining integration gap exists after the reopened unit correction.' \
  'Generate the final report and proceed to the human PR readiness checkpoint.'
postmerge_direct_report="$critic_dir/postmerge-direct-integration-pass.md"
write_critic_report "$postmerge_direct_report" pass artifact.txt "$head_sha_8" \
  'A direct commit after the latest merge is not part of the immutable progress-merge chain.' \
  'Review the exact final merge-chain tip instead of an unrecorded integration commit.'
postmerge_gauntlet_hash="$(git hash-object "$gauntlet_file")"
postmerge_round_count="$(round_file_count "$gauntlet_dir")"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_8"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/direct-commit-after-merges-integration.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  postmerge-direct-builder postmerge-direct-critic fresh-session \
  "$postmerge_direct_report" --head-sha "$head_sha_8" \
  --builder-strategy 'Attempt integration review after a direct unrecorded branch commit.'
[[ "$postmerge_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$postmerge_round_count" == "$(round_file_count "$gauntlet_dir")" ]] \
  || fail 'direct commit after progress merges mutated integration evidence'
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_7"

git -C "$project" remote set-url origin https://github.com/different/repository.git
expect_failure "$temp_root/integration-origin-drift.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  origin-drift-integration-builder origin-drift-integration-critic fresh-session \
  "$final_integration_report" --head-sha "$head_sha_7" \
  --builder-strategy "$integration_strategy_3"
[[ "$postmerge_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$postmerge_round_count" == "$(round_file_count "$gauntlet_dir")" ]] \
  || fail 'origin-drift integration attempt mutated Gauntlet state or evidence'
git -C "$project" remote set-url origin git@github.com:example/opencaw-fixture.git
for remote_topology_case in ahead divergent rewound absent; do
  case "$remote_topology_case" in
    ahead) remote_topology_sha="$head_sha_8" ;;
    divergent) remote_topology_sha="$divergent_sha" ;;
    rewound) remote_topology_sha="$head_sha_4" ;;
    absent) remote_topology_sha=absent ;;
  esac
  set_remote_ref "$project" gauntlet/fixture-gauntlet "$remote_topology_sha"
  expect_failure "$temp_root/integration-remote-$remote_topology_case.log" \
    run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet \
    integration pass "remote-$remote_topology_case-builder" \
    "remote-$remote_topology_case-critic" fresh-session \
    "$final_integration_report" --head-sha "$head_sha_7" \
    --builder-strategy "$integration_strategy_3"
  [[ "$postmerge_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
    && "$postmerge_round_count" == "$(round_file_count "$gauntlet_dir")" ]] \
    || fail "remote $remote_topology_case integration topology probe mutated evidence"
done
set_remote_ref "$project" gauntlet/fixture-gauntlet "$head_sha_7"
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  integration-builder-3 integration-critic-3 fresh-session "$final_integration_report" \
  --head-sha "$head_sha_7" --builder-strategy "$integration_strategy_3" >/dev/null
expect_file "$gauntlet_dir/rounds/integration/round-003.md"
repeated_integration_report="$critic_dir/repeated-final-integration-pass.md"
write_critic_report "$repeated_integration_report" pass artifact.txt "$head_sha_7" \
  'A fresh integration critic independently confirmed the unchanged final merge-chain tip.' \
  'Bind completion to this exact latest integration review while retaining the prior pass.'
run_for "$project" bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  integration-builder-4 integration-critic-4 native-subagent \
  "$repeated_integration_report" --head-sha "$head_sha_7" \
  --builder-strategy "$integration_strategy_4" >/dev/null
expect_file "$gauntlet_dir/rounds/integration/round-004.md"
run_for "$project" bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete >/dev/null
expect_file "$gauntlet_dir/GAUNTLET_REPORT.md"
assert_no_completion_staging "$gauntlet_dir"
completion_event="$gauntlet_dir/completion-events/event-001.md"
completion_event_relative='.ai/gauntlets/fixture-gauntlet/completion-events/event-001.md'
expect_file "$completion_event"
expect_line '# Gauntlet Completion Event: 001' "$completion_event"
expect_line '- Sequence: 001' "$completion_event"
expect_line '- Outcome: complete' "$completion_event"
expect_line '- Integration round: .ai/gauntlets/fixture-gauntlet/rounds/integration/round-004.md' \
  "$completion_event"
expect_line "- Head SHA: $head_sha_7" "$completion_event"
expect_line "- Quality bar fingerprint: $quality_bar_v1" "$completion_event"
expect_line "- Unit manifest fingerprint: $unit_manifest_opened" "$completion_event"
expect_line "- Execution contract fingerprint: $execution_contract_v1" "$completion_event"
expect_line "- Base commit SHA: $base_commit_sha" "$completion_event"
expect_line '- Report: .ai/gauntlets/fixture-gauntlet/GAUNTLET_REPORT.md' "$completion_event"
completion_report_projection="$(OPENCAW_PROJECT_ROOT="$project" bash -c '
  set -euo pipefail
  source commands/lib/gauntlet-common.sh
  gauntlet_report_projection_hash "$1"
' _ "$gauntlet_dir/GAUNTLET_REPORT.md")"
expect_line "- Report projection sha256: $completion_report_projection" "$completion_event"
grep -Eq '^- Scope fingerprint: [0-9a-f]{64}$' "$completion_event" \
  || fail 'completion event omitted the integration scope fingerprint'
completion_event_hash="$(sha256_file "$completion_event")"
grep -Fq -- "record: $completion_event_relative | sha256: $completion_event_hash" "$gauntlet_file" \
  || fail 'Completion Ledger omitted the immutable completion event hash'
grep -Fq -- "report-projection: $completion_report_projection" "$gauntlet_file" \
  || fail 'Completion Ledger omitted the stable report projection hash'
grep -Fq -- "manifest: $unit_manifest_opened" "$gauntlet_file" \
  || fail 'Completion Ledger omitted the retained-unit manifest fingerprint'
grep -Fq -- "$completion_event_relative" "$gauntlet_dir/GAUNTLET_REPORT.md" \
  || fail 'completion report omitted its Completion Ledger event'
grep -Eiq 'PR eligible[^[:alnum:]]+yes' "$gauntlet_dir/GAUNTLET_REPORT.md" || fail 'passed report was not marked PR-eligible'
grep -Fq 'gauntlet/fixture-gauntlet' "$gauntlet_dir/GAUNTLET_REPORT.md" \
  || fail 'completion report omitted the durable integration branch'
grep -Fq "$fixture_pr_url" "$gauntlet_dir/GAUNTLET_REPORT.md" \
  || fail 'completion report omitted the ordered progress PR history'
grep -Fq "$remediation_pr_url" "$gauntlet_dir/GAUNTLET_REPORT.md" \
  || fail 'completion report omitted the remediation PR history'
expect_line "- Unit manifest fingerprint: $unit_manifest_opened" \
  "$gauntlet_dir/GAUNTLET_REPORT.md"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null

terminal_remote_gauntlet_hash="$(git hash-object "$gauntlet_file")"
terminal_remote_report_hash="$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")"
terminal_remote_event_hash="$(git hash-object "$completion_event")"
for remote_topology_case in ahead divergent rewound absent; do
  case "$remote_topology_case" in
    ahead) remote_topology_sha="$head_sha_8" ;;
    divergent) remote_topology_sha="$divergent_sha" ;;
    rewound) remote_topology_sha="$head_sha_4" ;;
    absent) remote_topology_sha=absent ;;
  esac
  set_remote_ref "$project" gauntlet/fixture-gauntlet "$remote_topology_sha"
  expect_failure "$temp_root/completion-report-remote-$remote_topology_case.log" \
    run_for "$project" bash commands/create-gauntlet-completion-report.sh \
    fixture-gauntlet --status complete
  assert_no_completion_staging "$gauntlet_dir"
  expect_failure "$temp_root/complete-validation-remote-$remote_topology_case.log" \
    run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
  expect_failure "$temp_root/final-readiness-remote-$remote_topology_case.log" env \
    OPENCAW_PROJECT_ROOT="$project" \
    OPENCAW_REPORT_DIR="$project/.ai/reports/final-remote-$remote_topology_case" \
    bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
    "$project/progress-validation.md"
  [[ "$terminal_remote_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
    && "$terminal_remote_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
    && "$terminal_remote_event_hash" == "$(git hash-object "$completion_event")" ]] \
    || fail "remote $remote_topology_case terminal probes mutated durable completion evidence"
done
set_remote_ref "$project" gauntlet/fixture-gauntlet "$head_sha_7"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null

idempotent_completion_gauntlet_hash="$(git hash-object "$gauntlet_file")"
idempotent_completion_report_hash="$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")"
idempotent_completion_event_hash="$(git hash-object "$completion_event")"
idempotent_completion_event_count="$(completion_event_file_count "$gauntlet_dir")"
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  fixture-gauntlet --status complete >"$temp_root/idempotent-completion.log"
assert_no_completion_staging "$gauntlet_dir"
[[ "$idempotent_completion_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$idempotent_completion_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
  && "$idempotent_completion_event_hash" == "$(git hash-object "$completion_event")" \
  && "$idempotent_completion_event_count" == "$(completion_event_file_count "$gauntlet_dir")" ]] \
  || fail 'repeated complete changed the active immutable completion or created another event'

report_backup="$temp_root/fixture-gauntlet-report.backup.md"
cp "$gauntlet_dir/GAUNTLET_REPORT.md" "$report_backup"
replace_matching_line "$gauntlet_dir/GAUNTLET_REPORT.md" '^# Gauntlet Report:' \
  '# Gauntlet Report: tampered narrative projection'
tampered_report_hash="$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")"
tampered_report_gauntlet_hash="$(git hash-object "$gauntlet_file")"
tampered_report_event_hash="$(git hash-object "$completion_event")"
expect_failure "$temp_root/tampered-report-validation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
expect_failure "$temp_root/tampered-report-regeneration.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete
assert_no_completion_staging "$gauntlet_dir"
expect_failure "$temp_root/tampered-report-readiness.log" env \
  OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/tampered-report" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md"
[[ "$tampered_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
  && "$tampered_report_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$tampered_report_event_hash" == "$(git hash-object "$completion_event")" ]] \
  || fail 'report-integrity rejection mutated terminal artifacts or hid the tamper'
cp "$report_backup" "$gauntlet_dir/GAUNTLET_REPORT.md"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null

restore_fixture_first_merge_observation() {
  set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
    gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:00:00Z \
    human-reviewer "$head_sha_4" false "$base_commit_sha" false \
    example/opencaw-fixture 2026-08-01T12:00:00Z 2026-08-01T12:00:00Z \
    "$(opened_publication_marker "$project" fixture-gauntlet unit-1)"
}
merged_requery_gauntlet_hash="$(git hash-object "$gauntlet_file")"
merged_requery_report_hash="$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")"
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_3" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:00:00Z \
  human-reviewer "$head_sha_4" false "$base_commit_sha"
expect_failure "$temp_root/merged-requery-head-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  main MERGED false 2026-08-01T12:00:00Z \
  human-reviewer "$head_sha_4" false "$base_commit_sha"
expect_failure "$temp_root/merged-requery-base-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:00:00Z \
  human-reviewer "$head_sha_4" false "$head_sha_1"
expect_failure "$temp_root/merged-requery-base-sha-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet OPEN false none none none none "$base_commit_sha"
expect_failure "$temp_root/merged-requery-state-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
expect_failure "$temp_root/merged-requery-state-readiness.log" env \
  OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/merged-state" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md"
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:31:00Z \
  human-reviewer "$head_sha_4" false "$base_commit_sha"
expect_failure "$temp_root/merged-requery-time-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:00:00Z \
  forged-reviewer "$head_sha_4" false "$base_commit_sha"
expect_failure "$temp_root/merged-requery-actor-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:00:00Z \
  human-reviewer "$head_sha_4" true "$base_commit_sha"
expect_failure "$temp_root/merged-requery-bot-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
set_pr_observation "$fixture_pr_url" "$fixture_head" "$head_sha_4" \
  gauntlet/fixture-gauntlet MERGED false 2026-08-01T12:00:00Z \
  human-reviewer "$head_sha_5" false "$base_commit_sha"
expect_failure "$temp_root/merged-requery-commit-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
restore_fixture_first_merge_observation
set_pr_body_observation "$fixture_pr_url" ''
expect_failure "$temp_root/merged-requery-publication-body-removed.log" \
  run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
expect_failure "$temp_root/merged-requery-publication-body-readiness.log" env \
  OPENCAW_PROJECT_ROOT="$project" \
  OPENCAW_REPORT_DIR="$project/.ai/reports/merged-publication-body" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md"
restore_fixture_first_merge_observation
fixture_first_marker="$(opened_publication_marker \
  "$project" fixture-gauntlet unit-1)"
OPENCAW_TEST_RAW_PR_BODY=1 set_pr_body_observation \
  "$fixture_pr_url" "$fixture_first_marker"
expect_failure "$temp_root/merged-requery-issue-reference-removed.log" \
  run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
grep -Fq 'Progress PR body requires this exact canonical first line exactly once: Refs #101' \
  "$temp_root/merged-requery-issue-reference-removed.log" \
  || fail 'terminal progress replay accepted removal of its parent-issue reference'
restore_fixture_first_merge_observation
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null
[[ "$merged_requery_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$merged_requery_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" ]] \
  || fail 'live merged-event requery probes mutated terminal evidence'

direct_complete_gauntlet_hash="$(git hash-object "$gauntlet_file")"
direct_complete_report_hash="$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")"
direct_complete_event_hash="$(git hash-object "$completion_event")"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_8"
expect_failure "$temp_root/direct-complete-validation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
expect_failure "$temp_root/direct-completion-report.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete
expect_failure "$temp_root/direct-final-readiness.log" env \
  OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/direct-final" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md"
[[ "$direct_complete_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$direct_complete_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
  && "$direct_complete_event_hash" == "$(git hash-object "$completion_event")" \
  && "$(completion_event_file_count "$gauntlet_dir")" == 1 ]] \
  || fail 'direct commit after completion mutated terminal evidence'
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_7"

git -C "$project" remote set-url origin https://github.com/different/repository.git
expect_failure "$temp_root/complete-origin-drift-validation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
expect_failure "$temp_root/complete-origin-drift-report.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete
expect_failure "$temp_root/complete-origin-drift-readiness.log" env \
  OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/origin-drift-final" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md"
[[ "$direct_complete_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$direct_complete_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
  && "$direct_complete_event_hash" == "$(git hash-object "$completion_event")" ]] \
  || fail 'origin-drift terminal probes mutated completion evidence'
git -C "$project" remote set-url origin git@github.com:example/opencaw-fixture.git
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  fixture-gauntlet --status complete >/dev/null
OPENCAW_REPORT_DIR="$project/.ai/reports/restored-origin-final" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md" >/dev/null

git -C "$project" remote set-url --add --push origin \
  https://github.com/different/repository.git
expect_failure "$temp_root/complete-push-target-validation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
expect_failure "$temp_root/complete-push-target-report.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete
expect_failure "$temp_root/complete-push-target-readiness.log" env \
  OPENCAW_PROJECT_ROOT="$project" OPENCAW_REPORT_DIR="$project/.ai/reports/push-target-final" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md"
[[ "$direct_complete_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$direct_complete_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
  && "$direct_complete_event_hash" == "$(git hash-object "$completion_event")" ]] \
  || fail 'mismatched effective push target mutated terminal completion evidence'
git -C "$project" config --unset-all remote.origin.pushurl
git -C "$project" remote set-url --add --push origin \
  git@github.com:example/opencaw-fixture.git
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  fixture-gauntlet --status complete >/dev/null
OPENCAW_REPORT_DIR="$project/.ai/reports/restored-push-target-final" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet \
  "$project/progress-validation.md" >/dev/null
git -C "$project" config --unset-all remote.origin.pushurl

divergent_complete_gauntlet_hash="$(git hash-object "$gauntlet_file")"
divergent_complete_report_hash="$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")"
divergent_complete_round_count="$(round_file_count "$gauntlet_dir")"
set_local_ref "$project" gauntlet/fixture-gauntlet "$divergent_sha"
expect_failure "$temp_root/divergent-complete-validation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete
expect_failure "$temp_root/divergent-completion-report.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status complete
[[ "$divergent_complete_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$divergent_complete_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
  && "$divergent_complete_round_count" == "$(round_file_count "$gauntlet_dir")" ]] \
  || fail 'divergent complete validation/report attempts mutated passed state or evidence'
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_7"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null

terminal_demotion_report="$critic_dir/terminal-demotion-integration.md"
write_critic_report "$terminal_demotion_report" pass artifact.txt "$head_sha_8" \
  'An unconsumed completion event makes manual terminal demotion invalid.' \
  'Consume the active completion through immutable promotion-failure evidence first.'
terminal_pr_number=230
for terminal_variant in terminal-demotion-with-report terminal-demotion-without-report; do
  terminal_variant_dir="$project/.ai/gauntlets/$terminal_variant"
  copy_gauntlet "$gauntlet_dir" "$terminal_variant_dir"
  run_for "$project" bash commands/validate-gauntlet.sh "$terminal_variant" --phase complete >/dev/null
  replace_line "$terminal_variant_dir/GAUNTLET.md" '- Status: passed' '- Status: running'
  replace_line "$terminal_variant_dir/GAUNTLET.md" '- PR eligible: yes' '- PR eligible: no'
  if [[ "$terminal_variant" == terminal-demotion-without-report ]]; then
    rm -f "$terminal_variant_dir/GAUNTLET_REPORT.md"
  fi
  terminal_variant_gauntlet_hash="$(git hash-object "$terminal_variant_dir/GAUNTLET.md")"
  terminal_variant_report_hash='missing'
  if [[ -f "$terminal_variant_dir/GAUNTLET_REPORT.md" ]]; then
    terminal_variant_report_hash="$(git hash-object "$terminal_variant_dir/GAUNTLET_REPORT.md")"
  fi
  terminal_variant_completion_hash="$(git hash-object \
    "$terminal_variant_dir/completion-events/event-001.md")"
  terminal_variant_round_count="$(round_file_count "$terminal_variant_dir")"
  terminal_variant_pr_count="$(pr_event_file_count "$terminal_variant_dir")"
  expect_failure "$temp_root/$terminal_variant-integration.log" run_for "$project" \
    bash commands/record-gauntlet-round.sh "$terminal_variant" integration pass \
    "$terminal_variant-builder" "$terminal_variant-critic" fresh-session \
    "$terminal_demotion_report" --head-sha "$head_sha_8" \
    --builder-strategy 'Attempt to advance after manually demoting an active completion.'
  set_local_ref "$project" "gauntlet/$terminal_variant" "$head_sha_7"
  expect_failure "$temp_root/$terminal_variant-progress.log" \
    run_for_without_observation "$project" \
    bash commands/record-gauntlet-pr-event.sh "$terminal_variant" unit-1 opened \
    "https://github.com/example/opencaw-fixture/pull/$terminal_pr_number" \
    "gauntlet-work/$terminal_variant/unit-1-remediation-2" none --head-sha "$head_sha_8"
  expect_failure "$temp_root/$terminal_variant-report.log" run_for "$project" \
    bash commands/create-gauntlet-completion-report.sh "$terminal_variant" --status complete
  [[ "$terminal_variant_gauntlet_hash" == \
      "$(git hash-object "$terminal_variant_dir/GAUNTLET.md")" \
    && "$terminal_variant_completion_hash" == \
      "$(git hash-object "$terminal_variant_dir/completion-events/event-001.md")" \
    && "$terminal_variant_round_count" == "$(round_file_count "$terminal_variant_dir")" \
    && "$terminal_variant_pr_count" == "$(pr_event_file_count "$terminal_variant_dir")" \
    && "$(completion_event_file_count "$terminal_variant_dir")" == 1 ]] \
    || fail "manual active-completion demotion mutated durable evidence: $terminal_variant"
  if [[ "$terminal_variant_report_hash" == missing ]]; then
    [[ ! -f "$terminal_variant_dir/GAUNTLET_REPORT.md" ]] \
      || fail "rejected terminal demotion recreated a deleted report: $terminal_variant"
  else
    [[ "$terminal_variant_report_hash" == \
      "$(git hash-object "$terminal_variant_dir/GAUNTLET_REPORT.md")" ]] \
      || fail "rejected terminal demotion changed report bytes: $terminal_variant"
  fi
  terminal_pr_number=$((terminal_pr_number + 1))
done

sync_gauntlet_live_observations "$project" "$gauntlet_dir"
terminal_gauntlet_hash="$(git hash-object "$gauntlet_file")"
terminal_report_hash="$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")"
terminal_round_count="$(round_file_count "$gauntlet_dir")"
expect_failure "$temp_root/passed-report-demotion-stopped.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status stopped
grep -Fq 'A passed Gauntlet cannot be demoted by report generation' \
  "$temp_root/passed-report-demotion-stopped.log" \
  || fail 'stopped report demotion did not use the passed-state guard'
[[ "$terminal_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$terminal_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" ]] \
  || fail 'rejected stopped report generation mutated passed Gauntlet state or report bytes'
expect_failure "$temp_root/passed-report-demotion-blocked.log" run_for "$project" \
  bash commands/create-gauntlet-completion-report.sh fixture-gauntlet --status blocked
grep -Fq 'A passed Gauntlet cannot be demoted by report generation' \
  "$temp_root/passed-report-demotion-blocked.log" \
  || fail 'blocked report demotion did not use the passed-state guard'
[[ "$terminal_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$terminal_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" ]] \
  || fail 'rejected blocked report generation mutated passed Gauntlet state or report bytes'
terminal_unit_report="$critic_dir/terminal-unit-pass.md"
write_critic_report "$terminal_unit_report" pass artifact.txt "$head_sha_9" \
  'A passed Gauntlet cannot accept another unit round without immutable promotion-failure evidence.' \
  'Keep the terminal state unchanged until promotion QA records a concrete failure.'
expect_failure "$temp_root/passed-gauntlet-unit-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet unit-1 pass \
  terminal-unit-builder terminal-unit-critic fresh-session "$terminal_unit_report" \
  --head-sha "$head_sha_9" \
  --builder-strategy 'Attempt a forbidden unit mutation after the completing integration pass.'
grep -Fq 'A passed Gauntlet is immutable' "$temp_root/passed-gauntlet-unit-round.log" \
  || fail 'terminal unit-round rejection did not use the passed-state guard'

terminal_integration_report="$critic_dir/terminal-integration-pass.md"
write_critic_report "$terminal_integration_report" pass artifact.txt "$head_sha_9" \
  'A passed Gauntlet cannot accept a later integration round outside promotion remediation.' \
  'Preserve the completing integration round as the immutable terminal round.'
expect_failure "$temp_root/passed-gauntlet-integration-round.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh fixture-gauntlet integration pass \
  terminal-integration-builder terminal-integration-critic fresh-session \
  "$terminal_integration_report" --head-sha "$head_sha_9" \
  --builder-strategy 'Attempt a forbidden integration mutation after completion.'
grep -Fq 'A passed Gauntlet is immutable' "$temp_root/passed-gauntlet-integration-round.log" \
  || fail 'terminal integration-round rejection did not use the passed-state guard'
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_7"
sync_gauntlet_live_observations "$project" "$gauntlet_dir"
[[ "$terminal_gauntlet_hash" == "$(git hash-object "$gauntlet_file")" \
  && "$terminal_report_hash" == "$(git hash-object "$gauntlet_dir/GAUNTLET_REPORT.md")" \
  && "$terminal_round_count" == "$(round_file_count "$gauntlet_dir")" ]] \
  || fail 'rejected terminal round recording mutated passed Gauntlet state or evidence'
expect_line '- Status: passed' "$gauntlet_file"
run_for "$project" bash commands/validate-gauntlet.sh fixture-gauntlet --phase complete >/dev/null

forged_later_round_dir="$project/.ai/gauntlets/forged-later-round"
copy_gauntlet "$gauntlet_dir" "$forged_later_round_dir"
forged_round="$forged_later_round_dir/rounds/integration/round-005.md"
cp "$forged_later_round_dir/rounds/integration/round-004.md" "$forged_round"
replace_line "$forged_round" '# Gauntlet Round: integration / 004' \
  '# Gauntlet Round: integration / 005'
replace_line "$forged_round" '- Round: 004' '- Round: 005'
forged_round_hash="$(sha256_file "$forged_round")"
final_round_ledger_line="$(select_ledger_line "$project" \
  "$forged_later_round_dir/GAUNTLET.md" 'Round Ledger' evidence \
  '.ai/gauntlets/forged-later-round/rounds/integration/round-004.md')"
forged_round_ledger_line="${final_round_ledger_line/round: 004/round: 005}"
forged_round_ledger_line="${forged_round_ledger_line/round-004.md/round-005.md}"
forged_round_ledger_line="${forged_round_ledger_line%sha256:*}sha256: $forged_round_hash"
insert_after_section_line "$forged_later_round_dir/GAUNTLET.md" \
  'Round Ledger' "$final_round_ledger_line" "$forged_round_ledger_line"
expect_failure "$temp_root/forged-later-round.log" run_for "$project" \
  bash commands/validate-gauntlet.sh forged-later-round --phase complete

completed_scope_mutation_dir="$project/.ai/gauntlets/completed-scope-mutation"
copy_gauntlet "$gauntlet_dir" "$completed_scope_mutation_dir"
replace_matching_line "$completed_scope_mutation_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: passed | title: Complete the inspectable fixture artifact | scope: expanded completion scope without new critic evidence'
expect_failure "$temp_root/completed-scope-mutation.log" run_for "$project" \
  bash commands/validate-gauntlet.sh completed-scope-mutation --phase complete

integration_path_dir="$project/.ai/gauntlets/integration-path-traversal"
copy_gauntlet "$gauntlet_dir" "$integration_path_dir"
replace_line "$integration_path_dir/GAUNTLET.md" \
  '- Evidence: `.ai/gauntlets/integration-path-traversal/rounds/integration/round-004.md`' \
  '- Evidence: `.ai/gauntlets/integration-path-traversal/rounds/integration/../integration/round-004.md`'
expect_failure "$temp_root/integration-path-traversal.log" run_for "$project" \
  bash commands/validate-gauntlet.sh integration-path-traversal --phase complete

post_pr_reopen_dir="$project/.ai/gauntlets/post-pr-reopen"
copy_gauntlet "$gauntlet_dir" "$post_pr_reopen_dir"
post_promotion_report="$critic_dir/post-promotion-remediation.md"
write_critic_report "$post_promotion_report" pass artifact.txt "$head_sha_9" \
  'The post-promotion regression is corrected on a new remediation PR commit.' \
  'Return the changed promotion artifact through PR QA and integration review.'
expect_failure "$temp_root/post-pr-round-without-remediation-pr.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh post-pr-reopen unit-1 pass \
  post-pr-builder-without-pr post-pr-critic-without-pr fresh-session "$post_promotion_report" \
  --head-sha "$head_sha_9" --builder-strategy "$builder_strategy_7"
expect_failure "$temp_root/passed-progress-readiness-without-promotion-failure.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet-progress \
  post-pr-reopen unit-1 "$project/progress-validation.md"
post_pr_remediation_url='https://github.com/example/opencaw-fixture/pull/209'
post_pr_remediation_head='gauntlet-work/post-pr-reopen/unit-1-remediation-2'
expect_failure "$temp_root/passed-open-without-promotion-failure.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh post-pr-reopen unit-1 opened \
  "$post_pr_remediation_url" "$post_pr_remediation_head" none --head-sha "$head_sha_9"

manual_reopen_dir="$project/.ai/gauntlets/manual-passed-state-reopen"
copy_gauntlet "$gauntlet_dir" "$manual_reopen_dir"
replace_line "$manual_reopen_dir/GAUNTLET.md" '- Status: passed' '- Status: running'
replace_matching_line "$manual_reopen_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: critic-failed | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
replace_line "$manual_reopen_dir/GAUNTLET.md" '- PR eligible: yes' '- PR eligible: no'
insert_after_matching_line "$manual_reopen_dir/GAUNTLET.md" '^### Unit History$' \
  '- manual-reopen | action: reopen | reason: Unverified prose must not authorize remediation.'
rm -f "$manual_reopen_dir/GAUNTLET_REPORT.md"
expect_failure "$temp_root/manual-passed-state-remediation.log" \
  run_for_without_observation "$project" \
  bash commands/record-gauntlet-pr-event.sh manual-passed-state-reopen unit-1 opened \
  'https://github.com/example/opencaw-fixture/pull/222' \
  gauntlet-work/manual-passed-state-reopen/unit-1-remediation-2 none --head-sha "$head_sha_9"

promotion_pass_dir="$project/.ai/gauntlets/promotion-qa-pass"
copy_gauntlet "$gauntlet_dir" "$promotion_pass_dir"
promotion_completion_recorded_at="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$promotion_pass_dir/completion-events/event-001.md" | head -n 1)"
set_local_ref "$project" main "$head_sha_1"
promotion_pass_url='https://github.com/example/opencaw-fixture/pull/220'
promotion_pass_evidence="$promotion_pass_url#issuecomment-40"
set_local_ref "$project" gauntlet/promotion-qa-pass "$head_sha_7"
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$orphan_sha"
set_semantic_comment_observation "$project" "$promotion_pass_evidence" \
  "$promotion_pass_url" pass "$head_sha_7" \
  '.ai/gauntlets/promotion-qa-pass/completion-events/event-001.md'
export FAKE_GH_DEFAULT_BRANCH='release'
expect_failure "$temp_root/promotion-pass-nondefault-target.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
grep -Fq 'Gauntlet promotion PR must target the current GitHub default branch' \
  "$temp_root/promotion-pass-nondefault-target.log" \
  || fail 'promotion QA accepted a non-default target that cannot close its parent issue'
export FAKE_GH_DEFAULT_BRANCH='main'
OPENCAW_TEST_RAW_PR_BODY=1 set_pr_observation \
  "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" false \
  example/opencaw-fixture 2026-08-01T12:00:00Z none 'Refs #101'
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-pass-missing-closing-link.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
grep -Fq 'Promotion PR body requires this exact canonical first line exactly once: Closes #101' \
  "$temp_root/promotion-pass-missing-closing-link.log" \
  || fail 'promotion QA accepted a PR body without its closing parent-issue link'
promotion_duplicate_closing_body="Closes #101
Fixes: example/opencaw-fixture#101"
OPENCAW_TEST_RAW_PR_BODY=1 set_pr_observation \
  "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" false \
  example/opencaw-fixture 2026-08-01T12:00:00Z none \
  "$promotion_duplicate_closing_body"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-pass-duplicate-closing-link.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
grep -Fq 'Promotion PR body must contain exactly one parent-issue closing reference; use only: Closes #101' \
  "$temp_root/promotion-pass-duplicate-closing-link.log" \
  || fail 'promotion QA accepted an additional parent-issue closing alias'
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$orphan_sha" false \
  example/opencaw-fixture 2026-08-01T12:00:00Z none ''
promotion_lineage_gauntlet_hash="$(git hash-object "$promotion_pass_dir/GAUNTLET.md")"
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" true example/opencaw-fixture
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-pass-cross-repository.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" false different/repository
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-pass-head-repository-mismatch.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$orphan_sha"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-pass-unrelated-target-base.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
[[ "$promotion_lineage_gauntlet_hash" == "$(git hash-object "$promotion_pass_dir/GAUNTLET.md")" \
  && "$(find "$promotion_pass_dir/promotion-events" -maxdepth 1 -type f -name 'event-*.md' \
    | wc -l | tr -d ' ')" == 0 ]] \
  || fail 'unrelated promotion target base created promotion-pass evidence'
expect_failure "$temp_root/promotion-pass-with-affected-unit.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7" \
  --affected-unit unit-1
expect_failure "$temp_root/promotion-pass-arbitrary-https-evidence.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" 'https://example.com/unbound-evidence' --head-sha "$head_sha_7"
expect_failure "$temp_root/promotion-pass-different-pr-comment.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" \
  'https://github.com/example/opencaw-fixture/pull/999#issuecomment-41' --head-sha "$head_sha_7"
promotion_pass_missing_comment="$promotion_pass_url#issuecomment-9010"
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-pass-missing-live-comment.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_missing_comment" --head-sha "$head_sha_7"
promotion_pass_wrong_pr_comment="$promotion_pass_url#issuecomment-9011"
set_semantic_comment_observation "$project" "$promotion_pass_wrong_pr_comment" \
  'https://github.com/example/opencaw-fixture/pull/997' pass "$head_sha_7" \
  '.ai/gauntlets/promotion-qa-pass/completion-events/event-001.md'
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-pass-wrong-live-comment-pr.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_wrong_pr_comment" --head-sha "$head_sha_7"
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1"
set_pr_merge_automation_observation "$promotion_pass_url" AutoMergeEnabledEvent
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/open-promotion-auto-merge-history.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
grep -Fq 'Gauntlet PR must never enable auto-merge or enter a merge queue' \
  "$temp_root/open-promotion-auto-merge-history.log" \
  || fail 'open promotion PR did not reject retained auto-merge history'
[[ "$(find "$promotion_pass_dir/promotion-events" -maxdepth 1 -type f \
    -name 'event-*.md' | wc -l | tr -d ' ')" == 0 ]] \
  || fail 'open promotion auto-merge history created immutable QA evidence'
set_pr_merge_automation_observation "$promotion_pass_url" none
run_for "$project" bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7" >/dev/null
expect_file "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- Verdict: pass' "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- Affected units: none' "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- QA comment ID: 40' "$promotion_pass_dir/promotion-events/event-001.md"
expect_line "- Target base SHA: $head_sha_1" \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- Cross repository: false' \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- Head repository: example/opencaw-fixture' \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- QA comment author: fixture-user' \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- QA comment author type: User' \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- QA comment author association: MEMBER' \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line "- QA comment created at: $promotion_completion_recorded_at" \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line "- QA comment updated at: $promotion_completion_recorded_at" \
  "$promotion_pass_dir/promotion-events/event-001.md"
grep -Eq '^- QA comment body sha256: [0-9a-f]{64}$' \
  "$promotion_pass_dir/promotion-events/event-001.md" \
  || fail 'promotion event omitted the exact semantic comment-body hash'
expect_line '- Completion event: .ai/gauntlets/promotion-qa-pass/completion-events/event-001.md' \
  "$promotion_pass_dir/promotion-events/event-001.md"
expect_line '- Status: passed' "$promotion_pass_dir/GAUNTLET.md"
expect_file "$promotion_pass_dir/GAUNTLET_REPORT.md"
[[ "$(completion_event_file_count "$promotion_pass_dir")" == 1 ]] \
  || fail 'passing promotion QA changed the active completion event count'
promotion_pass_event_hash="$(git hash-object "$promotion_pass_dir/promotion-events/event-001.md")"
run_for "$project" bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete >/dev/null
set_pr_merge_automation_observation "$promotion_pass_url" AddedToMergeQueueEvent
expect_failure "$temp_root/promotion-replay-merge-queue-history.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
grep -Fq 'Gauntlet PR must never enable auto-merge or enter a merge queue' \
  "$temp_root/promotion-replay-merge-queue-history.log" \
  || fail 'promotion validator replay did not reject retained merge-queue history'
[[ "$promotion_pass_event_hash" == \
  "$(git hash-object "$promotion_pass_dir/promotion-events/event-001.md")" ]] \
  || fail 'promotion validator replay rejection mutated immutable evidence'
set_pr_merge_automation_observation "$promotion_pass_url" none
promotion_completion_symlink_dir="$project/.ai/gauntlets/promotion-completion-symlink"
copy_gauntlet "$promotion_pass_dir" "$promotion_completion_symlink_dir"
outside_promotion_completion_events="$temp_root/outside-promotion-completion-events"
mv "$promotion_completion_symlink_dir/completion-events" \
  "$outside_promotion_completion_events"
ln -s "$outside_promotion_completion_events" \
  "$promotion_completion_symlink_dir/completion-events"
expect_failure "$temp_root/promotion-completion-symlink.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-completion-symlink --phase complete
grep -Fq \
  'Gauntlet completion-events evidence tree must be a real directory, not a file or symbolic link' \
  "$temp_root/promotion-completion-symlink.log" \
  || fail 'promotion replay did not preflight completion evidence before cross-reading it'
sync_gauntlet_live_observations "$project" "$promotion_pass_dir"
restore_promotion_pass_observation() {
  set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
    main OPEN false none none none none "$head_sha_1" false \
    example/opencaw-fixture 2026-08-01T12:00:00Z none ''
}
promotion_live_replay_gauntlet_hash="$(git hash-object "$promotion_pass_dir/GAUNTLET.md")"
promotion_live_replay_event_hash="$(git hash-object \
  "$promotion_pass_dir/promotion-events/event-001.md")"
OPENCAW_TEST_RAW_PR_BODY=1 set_pr_observation \
  "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" false \
  example/opencaw-fixture 2026-08-01T12:00:00Z none 'Refs #101'
expect_failure "$temp_root/promotion-live-closing-link-removed.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
grep -Fq 'Promotion PR body requires this exact canonical first line exactly once: Closes #101' \
  "$temp_root/promotion-live-closing-link-removed.log" \
  || fail 'promotion replay accepted removal of its closing parent-issue link'
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/unrelated "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1"
expect_failure "$temp_root/promotion-live-head-ref-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_6" \
  main OPEN false none none none none "$head_sha_1"
expect_failure "$temp_root/promotion-live-head-sha-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_local_ref "$project" release "$head_sha_1"
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  release OPEN false none none none none "$head_sha_1"
expect_failure "$temp_root/promotion-live-base-ref-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$orphan_sha"
expect_failure "$temp_root/promotion-live-base-sha-mismatch.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" true example/opencaw-fixture
expect_failure "$temp_root/promotion-live-cross-repository.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" false different/repository
expect_failure "$temp_root/promotion-live-head-repository.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN true none none none none "$head_sha_1"
expect_failure "$temp_root/promotion-live-draft.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main CLOSED false none none none none "$head_sha_1"
expect_failure "$temp_root/promotion-live-state.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
set_pr_observation "$promotion_pass_url" gauntlet/promotion-qa-pass "$head_sha_7" \
  main OPEN false none none none none "$head_sha_1" false \
  example/opencaw-fixture 2026-08-01T12:01:00Z none
expect_failure "$temp_root/promotion-live-chronology.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete
restore_promotion_pass_observation
run_for "$project" bash commands/validate-gauntlet.sh promotion-qa-pass --phase complete >/dev/null
[[ "$promotion_live_replay_gauntlet_hash" == "$(git hash-object "$promotion_pass_dir/GAUNTLET.md")" \
  && "$promotion_live_replay_event_hash" == "$(git hash-object \
    "$promotion_pass_dir/promotion-events/event-001.md")" ]] \
  || fail 'promotion live replay probes mutated immutable evidence'
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/reused-live-comment-for-later-promotion-qa.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_pass_evidence" --head-sha "$head_sha_7"
grep -Fq 'QA comment evidence has already been consumed by a promotion event' \
  "$temp_root/reused-live-comment-for-later-promotion-qa.log" \
  || fail 'reused promotion QA comment was not rejected by the uniqueness invariant'
[[ "$(find "$promotion_pass_dir/promotion-events" -maxdepth 1 -type f -name 'event-*.md' \
  | wc -l | tr -d ' ')" == 1 ]] \
  || fail 'reused promotion comment evidence created another immutable event'

promotion_duplicate_ledger_dir="$project/.ai/gauntlets/promotion-duplicate-ledger"
copy_gauntlet "$promotion_pass_dir" "$promotion_duplicate_ledger_dir"
promotion_duplicate_line="$(select_ledger_line "$project" \
  "$promotion_duplicate_ledger_dir/GAUNTLET.md" 'Promotion QA Ledger' record \
  '.ai/gauntlets/promotion-duplicate-ledger/promotion-events/event-001.md')"
insert_after_section_line "$promotion_duplicate_ledger_dir/GAUNTLET.md" \
  'Promotion QA Ledger' "$promotion_duplicate_line" "$promotion_duplicate_line"
expect_failure "$temp_root/promotion-duplicate-ledger.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-duplicate-ledger --phase complete
sync_gauntlet_live_observations "$project" "$promotion_pass_dir"

promotion_repeat_pass_evidence="$promotion_pass_url#issuecomment-42"
expect_failure "$temp_root/promotion-pass-repeat-same-completion.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_repeat_pass_evidence" --head-sha "$head_sha_7"
promotion_reversed_order_dir="$project/.ai/gauntlets/promotion-reversed-comment-order"
copy_gauntlet "$promotion_pass_dir" "$promotion_reversed_order_dir"
promotion_reversed_evidence="$promotion_pass_url#issuecomment-39"
expect_failure "$temp_root/promotion-pass-to-fail-reversed-comment-order.log" \
  run_for "$project" bash commands/record-gauntlet-promotion-qa.sh \
  promotion-reversed-comment-order fail "$promotion_pass_url" \
  "$promotion_reversed_evidence" --head-sha "$head_sha_7" --affected-unit unit-1
[[ "$(find "$promotion_reversed_order_dir/promotion-events" -maxdepth 1 \
  -type f -name 'event-*.md' | wc -l | tr -d ' ')" == 1 ]] \
  || fail 'reversed same-second comment ordering created promotion failure evidence'
promotion_followup_fail_evidence="$promotion_pass_url#issuecomment-43"
sync_gauntlet_live_observations "$project" "$promotion_pass_dir"
run_for "$project" bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass fail \
  "$promotion_pass_url" "$promotion_followup_fail_evidence" --head-sha "$head_sha_7" \
  --affected-unit unit-1 >/dev/null
expect_file "$promotion_pass_dir/promotion-events/event-002.md"
expect_line '- Verdict: fail' "$promotion_pass_dir/promotion-events/event-002.md"
expect_line '- QA comment ID: 43' "$promotion_pass_dir/promotion-events/event-002.md"
expect_line '- Completion event: .ai/gauntlets/promotion-qa-pass/completion-events/event-001.md' \
  "$promotion_pass_dir/promotion-events/event-002.md"
expect_line '- Status: running' "$promotion_pass_dir/GAUNTLET.md"
[[ ! -f "$promotion_pass_dir/GAUNTLET_REPORT.md" ]] \
  || fail 'allowed pass-to-fail promotion transition did not consume the completion report'
promotion_order_token_dir="$project/.ai/gauntlets/promotion-order-token-tamper"
copy_gauntlet "$promotion_pass_dir" "$promotion_order_token_dir"
replace_line "$promotion_order_token_dir/promotion-events/event-002.md" \
  '- QA comment ID: 43' '- QA comment ID: 39'
promotion_order_ledger_line="$(select_ledger_line "$project" \
  "$promotion_order_token_dir/GAUNTLET.md" 'Promotion QA Ledger' record \
  '.ai/gauntlets/promotion-order-token-tamper/promotion-events/event-002.md')"
replace_line "$promotion_order_token_dir/GAUNTLET.md" "$promotion_order_ledger_line" \
  "${promotion_order_ledger_line/qa-comment-id: 43/qa-comment-id: 39}"
refresh_copied_evidence_hashes "$promotion_order_token_dir"
expect_failure "$temp_root/promotion-order-token-tamper.log" run_for "$project" \
  bash commands/validate-gauntlet.sh promotion-order-token-tamper --phase ready
sync_gauntlet_live_observations "$project" "$promotion_pass_dir"
promotion_post_fail_evidence="$promotion_pass_url#issuecomment-44"
expect_failure "$temp_root/promotion-post-fail-reuse.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass fail \
  "$promotion_pass_url" "$promotion_post_fail_evidence" --head-sha "$head_sha_7" \
  --affected-unit unit-1
promotion_fail_to_pass_evidence="$promotion_pass_url#issuecomment-45"
expect_failure "$temp_root/promotion-fail-to-pass-same-completion.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh promotion-qa-pass pass \
  "$promotion_pass_url" "$promotion_fail_to_pass_evidence" --head-sha "$head_sha_7"

promotion_forged_pass_dir="$project/.ai/gauntlets/promotion-fail-forged-pass"
copy_gauntlet "$post_pr_reopen_dir" "$promotion_forged_pass_dir"
promotion_forged_url='https://github.com/example/opencaw-fixture/pull/243'
promotion_forged_evidence="$promotion_forged_url#issuecomment-46"
run_for "$project" bash commands/record-gauntlet-promotion-qa.sh \
  promotion-fail-forged-pass fail "$promotion_forged_url" \
  "$promotion_forged_evidence" --head-sha "$head_sha_7" --affected-unit unit-1 >/dev/null
expect_file "$promotion_forged_pass_dir/promotion-events/event-001.md"
replace_matching_line "$promotion_forged_pass_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [x] unit-1 | status: passed | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused local verifier'
promotion_forged_hash="$(git hash-object "$promotion_forged_pass_dir/GAUNTLET.md")"
promotion_forged_round_count="$(round_file_count "$promotion_forged_pass_dir")"
promotion_forged_report="$critic_dir/promotion-fail-forged-integration.md"
write_critic_report "$promotion_forged_report" pass artifact.txt "$head_sha_7" \
  'A manual unit status flip cannot satisfy the consumed promotion-failure remediation.' \
  'Complete the triggered remediation PR lifecycle before integration review.'
expect_failure "$temp_root/promotion-fail-forged-pass-integration.log" run_for "$project" \
  bash commands/record-gauntlet-round.sh promotion-fail-forged-pass integration pass \
  promotion-forged-builder promotion-forged-critic fresh-session \
  "$promotion_forged_report" --head-sha "$head_sha_7" \
  --builder-strategy 'Attempt integration after a manual post-promotion-failure status flip.'
[[ "$promotion_forged_hash" == "$(git hash-object "$promotion_forged_pass_dir/GAUNTLET.md")" \
  && "$promotion_forged_round_count" == "$(round_file_count "$promotion_forged_pass_dir")" ]] \
  || fail 'manual post-promotion-failure pass mutated integration evidence'

sync_gauntlet_live_observations "$project" "$post_pr_reopen_dir"
promotion_fail_url='https://github.com/example/opencaw-fixture/pull/221'
promotion_fail_evidence="$promotion_fail_url#issuecomment-50"
set_local_ref "$project" gauntlet/post-pr-reopen "$head_sha_7"
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_7" \
  main OPEN false none none none none "$orphan_sha"
set_semantic_comment_observation "$project" "$promotion_fail_evidence" \
  "$promotion_fail_url" fail "$head_sha_7" \
  '.ai/gauntlets/post-pr-reopen/completion-events/event-001.md' unit-1
promotion_fail_lineage_hash="$(git hash-object "$post_pr_reopen_dir/GAUNTLET.md")"
OPENCAW_TEST_SKIP_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-fail-unrelated-target-base.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_evidence" --head-sha "$head_sha_7" \
  --affected-unit unit-1
[[ "$promotion_fail_lineage_hash" == "$(git hash-object "$post_pr_reopen_dir/GAUNTLET.md")" \
  && "$(find "$post_pr_reopen_dir/promotion-events" -maxdepth 1 -type f -name 'event-*.md' \
    | wc -l | tr -d ' ')" == 0 ]] \
  || fail 'unrelated promotion target base created promotion-fail evidence'
promotion_fail_missing_comment="$promotion_fail_url#issuecomment-9012"
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-fail-missing-live-comment.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_missing_comment" --head-sha "$head_sha_7" \
  --affected-unit unit-1
promotion_fail_wrong_pr_comment="$promotion_fail_url#issuecomment-9013"
set_semantic_comment_observation "$project" "$promotion_fail_wrong_pr_comment" \
  'https://github.com/example/opencaw-fixture/pull/996' fail "$head_sha_7" \
  '.ai/gauntlets/post-pr-reopen/completion-events/event-001.md' unit-1
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-fail-wrong-live-comment-pr.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_wrong_pr_comment" --head-sha "$head_sha_7" \
  --affected-unit unit-1
promotion_fail_wrong_affected_comment="$promotion_fail_url#issuecomment-9014"
set_semantic_comment_observation "$project" "$promotion_fail_wrong_affected_comment" \
  "$promotion_fail_url" fail "$head_sha_7" \
  '.ai/gauntlets/post-pr-reopen/completion-events/event-001.md' none
OPENCAW_TEST_SKIP_COMMENT_OBSERVATION=1 expect_failure \
  "$temp_root/promotion-fail-wrong-comment-affected-units.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_wrong_affected_comment" \
  --head-sha "$head_sha_7" --affected-unit unit-1
expect_failure "$temp_root/promotion-fail-missing-affected-unit.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_evidence" --head-sha "$head_sha_7"
expect_failure "$temp_root/promotion-fail-unknown-affected-unit.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_evidence" --head-sha "$head_sha_7" \
  --affected-unit absent-unit
expect_failure "$temp_root/promotion-fail-duplicate-affected-unit.log" run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_evidence" --head-sha "$head_sha_7" \
  --affected-unit unit-1 --affected-unit unit-1
run_for "$project" bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen fail \
  "$promotion_fail_url" "$promotion_fail_evidence" --head-sha "$head_sha_7" \
  --affected-unit unit-1 >/dev/null
promotion_fail_event="$post_pr_reopen_dir/promotion-events/event-001.md"
promotion_fail_archive="$post_pr_reopen_dir/promotion-events/GAUNTLET_REPORT-before-event-001.md"
expect_file "$promotion_fail_event"
expect_file "$promotion_fail_archive"
[[ ! -f "$post_pr_reopen_dir/GAUNTLET_REPORT.md" ]] \
  || fail 'promotion-QA failure left the stale completion report current'
expect_line '- Verdict: fail' "$promotion_fail_event"
expect_line '- Affected units: unit-1' "$promotion_fail_event"
expect_line "- Target base SHA: $head_sha_1" "$promotion_fail_event"
expect_line '- Completion event: .ai/gauntlets/post-pr-reopen/completion-events/event-001.md' \
  "$promotion_fail_event"
expect_line '- Status: running' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- PR eligible: no' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- Verdict: pending' "$post_pr_reopen_dir/GAUNTLET.md"
grep -Eq '^- \[[ x]\] unit-1 \| status: critic-failed \|' "$post_pr_reopen_dir/GAUNTLET.md" \
  || fail 'promotion-QA failure did not reopen its affected unit'
integration_failure_recorded_at="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$post_pr_reopen_dir/rounds/integration/round-002.md" | head -n 1)"
promotion_failure_recorded_at="$(sed -nE 's/^- Recorded at: (.*)$/\1/p' \
  "$promotion_fail_event" | head -n 1)"
[[ -n "$integration_failure_recorded_at" && -n "$promotion_failure_recorded_at" ]] \
  || fail 'failure evidence omitted Recorded at timestamps needed for causality replay'
replace_line "$promotion_fail_event" "- Recorded at: $promotion_failure_recorded_at" \
  "- Recorded at: $integration_failure_recorded_at"
refresh_copied_evidence_hashes "$post_pr_reopen_dir"
post_pr_manifest_v1="$(gauntlet_helper_value "$project" gauntlet_section_field \
  "$post_pr_reopen_dir/completion-events/event-001.md" \
  'Completion Event Metadata' 'Unit manifest fingerprint')"
[[ "$post_pr_manifest_v1" == "$unit_manifest_opened" ]] \
  || fail 'consumed completion C1 did not retain its original M1 manifest generation'

post_pr_unapproved_scope_dir="$project/.ai/gauntlets/post-pr-unapproved-scope"
copy_gauntlet "$post_pr_reopen_dir" "$post_pr_unapproved_scope_dir"
replace_matching_line "$post_pr_unapproved_scope_dir/GAUNTLET.md" \
  '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: critic-failed | title: Complete the inspectable fixture artifact | scope: artifact.txt plus an unapproved promotion-recovery boundary'
expect_failure "$temp_root/post-pr-unapproved-scope.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-unapproved-scope --phase ready

post_pr_scope_v1="$(unit_scope_fingerprint \
  "$project" "$post_pr_reopen_dir/GAUNTLET.md" unit-1)"
replace_matching_line "$post_pr_reopen_dir/GAUNTLET.md" '^- .*unit-1 .*status:' \
  '- [ ] unit-1 | status: critic-failed | title: Complete the inspectable fixture artifact | scope: artifact.txt and its focused verifier plus the promotion-recovery contract'
post_pr_scope_v2="$(unit_scope_fingerprint \
  "$project" "$post_pr_reopen_dir/GAUNTLET.md" unit-1)"
post_pr_manifest_v2="$(unit_manifest_fingerprint \
  "$project" "$post_pr_reopen_dir/GAUNTLET.md")"
post_pr_scope_revision="- Unit scope-title revision: unit-1 | from: $post_pr_scope_v1 | to: $post_pr_scope_v2 | reason: Expand the retained unit boundary to cover the concrete promotion QA regression. | approved by: fixture-user-m2 | approved at: 2026-08-01T12:00:01Z"
post_pr_manifest_revision="- Unit manifest revision: post-promotion-scope-v2 | from: $post_pr_manifest_v1 | to: $post_pr_manifest_v2 | prior-units: unit-1 | current-units: unit-1 | reason: Freeze the approved promotion-recovery scope as manifest generation M2. | approved by: fixture-user-m2 | approved at: 2026-08-01T12:00:01Z"
insert_after_matching_line "$post_pr_reopen_dir/GAUNTLET.md" \
  '^- Unit manifest approval:' "$post_pr_scope_revision"
insert_after_matching_line "$post_pr_reopen_dir/GAUNTLET.md" \
  '^- Unit scope-title revision: unit-1 ' "$post_pr_manifest_revision"
set_gauntlet_field "$project" "$post_pr_reopen_dir/GAUNTLET.md" \
  'Current State' 'Unit manifest fingerprint' pending
reset_integration_review "$project" "$post_pr_reopen_dir/GAUNTLET.md"

post_pr_misordered_manifest_dir="$project/.ai/gauntlets/post-pr-misordered-manifest"
copy_gauntlet "$post_pr_reopen_dir" "$post_pr_misordered_manifest_dir"
replace_all_literal "$post_pr_misordered_manifest_dir/GAUNTLET.md" \
  'approved at: 2026-08-01T12:00:01Z' 'approved at: 2026-08-01T12:00:00Z'
expect_failure "$temp_root/post-pr-misordered-manifest.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-misordered-manifest --phase ready

sync_gauntlet_live_observations "$project" "$post_pr_reopen_dir"
export FAKE_DATE_ISO=2026-08-01T12:00:01Z
run_for "$project" bash commands/validate-gauntlet.sh post-pr-reopen --phase ready >/dev/null
set_local_ref "$project" main "$base_commit_sha"
promotion_fail_event_hash="$(git hash-object "$promotion_fail_event")"

set_local_ref "$project" "$post_pr_remediation_head" "$head_sha_9"
run_for "$project" bash commands/pr-readiness-check.sh --gauntlet-progress \
  post-pr-reopen unit-1 "$project/progress-validation.md" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh post-pr-reopen unit-1 opened \
  "$post_pr_remediation_url" "$post_pr_remediation_head" none --head-sha "$head_sha_9" >/dev/null
expect_file "$post_pr_reopen_dir/pr-events/unit-1/event-010.md"
expect_line '- Remediation trigger: .ai/gauntlets/post-pr-reopen/promotion-events/event-001.md' \
  "$post_pr_reopen_dir/pr-events/unit-1/event-010.md"
expect_line "- Unit manifest fingerprint: $post_pr_manifest_v2" \
  "$post_pr_reopen_dir/pr-events/unit-1/event-010.md"
expect_line '- Status: running' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- PR eligible: no' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- Verdict: pending' "$post_pr_reopen_dir/GAUNTLET.md"
run_for "$project" bash commands/record-gauntlet-round.sh post-pr-reopen unit-1 pass \
  post-pr-builder post-pr-critic fresh-session "$post_promotion_report" \
  --head-sha "$head_sha_9" --builder-strategy "$builder_strategy_7" >/dev/null
expect_file "$post_pr_reopen_dir/rounds/unit-1/round-006.md"
expect_line "- Unit manifest fingerprint: $post_pr_manifest_v2" \
  "$post_pr_reopen_dir/rounds/unit-1/round-006.md"
[[ "$promotion_fail_event_hash" == "$(git hash-object "$promotion_fail_event")" ]] \
  || fail 'remediation mutated immutable promotion-QA evidence'
[[ "$promotion_pass_event_hash" == "$(git hash-object "$promotion_pass_dir/promotion-events/event-001.md")" ]] \
  || fail 'unrelated remediation mutated passing promotion-QA evidence'
expect_line '- Status: running' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- PR eligible: no' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- Verdict: pending' "$post_pr_reopen_dir/GAUNTLET.md"
run_for "$project" bash commands/validate-gauntlet.sh post-pr-reopen --phase ready >/dev/null
expect_failure "$temp_root/post-pr-reopen-readiness.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet post-pr-reopen
consumed_completion="$post_pr_reopen_dir/completion-events/event-001.md"
consumed_completion_hash="$(git hash-object "$consumed_completion")"
run_for "$project" bash commands/record-gauntlet-pr-event.sh post-pr-reopen unit-1 qa-pass \
  "$post_pr_remediation_url" "$post_pr_remediation_head" \
  'https://github.com/example/opencaw-fixture/pull/209#issuecomment-52' \
  --head-sha "$head_sha_9" >/dev/null
run_for "$project" bash commands/record-gauntlet-pr-event.sh post-pr-reopen unit-1 merged \
  "$post_pr_remediation_url" "$post_pr_remediation_head" \
  'https://github.com/example/opencaw-fixture/pull/209#issuecomment-53' \
  --head-sha "$head_sha_9" --merge-commit "$head_sha_9" >/dev/null
expect_file "$post_pr_reopen_dir/pr-events/unit-1/event-012.md"
expect_line "- Target base SHA: $head_sha_7" \
  "$post_pr_reopen_dir/pr-events/unit-1/event-012.md"
expect_line "- Unit manifest fingerprint: $post_pr_manifest_v2" \
  "$post_pr_reopen_dir/pr-events/unit-1/event-012.md"
post_promotion_integration_report="$critic_dir/post-promotion-integration.md"
write_critic_report "$post_promotion_integration_report" pass artifact.txt "$head_sha_9" \
  'The promotion remediation is merged and the exact integration chain tip passes.' \
  'Create a new completion event before requesting promotion readiness again.'
run_for "$project" bash commands/record-gauntlet-round.sh post-pr-reopen integration pass \
  post-promotion-integration-builder post-promotion-integration-critic fresh-session \
  "$post_promotion_integration_report" --head-sha "$head_sha_9" \
  --builder-strategy 'Reintegrate the human-merged promotion remediation at the exact chain tip.' \
  >/dev/null
expect_file "$post_pr_reopen_dir/rounds/integration/round-005.md"
expect_line "- Unit manifest fingerprint: $post_pr_manifest_v2" \
  "$post_pr_reopen_dir/rounds/integration/round-005.md"
[[ "$(completion_event_file_count "$post_pr_reopen_dir")" == 1 ]] \
  || fail 'remediation or reintegration silently created a replacement completion event'
expect_failure "$temp_root/reintegration-needs-new-completion.log" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet post-pr-reopen \
  "$project/progress-validation.md"
run_for "$project" bash commands/create-gauntlet-completion-report.sh \
  post-pr-reopen --status complete >/dev/null
replacement_completion="$post_pr_reopen_dir/completion-events/event-002.md"
expect_file "$replacement_completion"
expect_line '# Gauntlet Completion Event: 002' "$replacement_completion"
expect_line '- Sequence: 002' "$replacement_completion"
expect_line '- Integration round: .ai/gauntlets/post-pr-reopen/rounds/integration/round-005.md' \
  "$replacement_completion"
expect_line "- Head SHA: $head_sha_9" "$replacement_completion"
expect_line "- Unit manifest fingerprint: $post_pr_manifest_v2" \
  "$replacement_completion"
expect_line "- Unit manifest fingerprint: $post_pr_manifest_v1" \
  "$consumed_completion"
[[ "$(completion_event_file_count "$post_pr_reopen_dir")" == 2 \
  && "$consumed_completion_hash" == "$(git hash-object "$consumed_completion")" ]] \
  || fail 'replacement completion did not preserve the consumed completion immutably'
expect_file "$post_pr_reopen_dir/GAUNTLET_REPORT.md"
expect_line "- Unit manifest fingerprint: $post_pr_manifest_v2" \
  "$post_pr_reopen_dir/GAUNTLET_REPORT.md"
[[ "$(grep -Ec '^- event: 00[12] \| outcome: complete ' \
  "$post_pr_reopen_dir/GAUNTLET.md")" == 2 ]] \
  || fail 'C1/M1 to C2/M2 recovery did not retain exactly two completion ledger entries'
expect_line '- Status: passed' "$post_pr_reopen_dir/GAUNTLET.md"
expect_line '- PR eligible: yes' "$post_pr_reopen_dir/GAUNTLET.md"
post_pr_promotion_created_at="$(gauntlet_helper_value "$project" gauntlet_section_field \
  "$promotion_fail_event" 'Promotion QA Event Metadata' 'Created at')"
post_pr_promotion_target_base="$(gauntlet_helper_value "$project" gauntlet_section_field \
  "$promotion_fail_event" 'Promotion QA Event Metadata' 'Target base SHA')"
restore_post_pr_promotion_h2_observation() {
  set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_9" \
    main OPEN false none none none none "$post_pr_promotion_target_base" false \
    example/opencaw-fixture "$post_pr_promotion_created_at" none
}
restore_post_pr_promotion_h2_observation
post_pr_unrecorded_h3="$artifact_absent_sha"
git -C "$project" merge-base --is-ancestor "$head_sha_9" "$post_pr_unrecorded_h3" \
  || fail 'promotion H3 fixture is not a strict fast-forward descendant of H2'
set_remote_ref "$project" gauntlet/post-pr-reopen "$post_pr_unrecorded_h3"
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen \
  "$post_pr_unrecorded_h3" main OPEN false none none none none \
  "$post_pr_promotion_target_base" false example/opencaw-fixture \
  "$post_pr_promotion_created_at" none
expect_failure "$temp_root/post-pr-promotion-live-and-origin-h3.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase ready
grep -Fq 'Origin integration ref must equal the exact reconstructed chain tip' \
  "$temp_root/post-pr-promotion-live-and-origin-h3.log" \
  || fail 'live/origin H3 drift did not fail at exact remote-chain replay'
set_remote_ref "$project" gauntlet/post-pr-reopen "$head_sha_9"
restore_post_pr_promotion_h2_observation
set_remote_ref "$project" gauntlet/post-pr-reopen "$post_pr_unrecorded_h3"
expect_failure "$temp_root/post-pr-promotion-origin-only-h3.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase ready
grep -Fq 'Origin integration ref must equal the exact reconstructed chain tip' \
  "$temp_root/post-pr-promotion-origin-only-h3.log" \
  || fail 'origin-only H3 drift did not fail at exact remote-chain replay'
set_remote_ref "$project" gauntlet/post-pr-reopen "$head_sha_9"
restore_post_pr_promotion_h2_observation
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_9" \
  main CLOSED false none none none none "$post_pr_promotion_target_base" false \
  example/opencaw-fixture "$post_pr_promotion_created_at" \
  2026-08-01T12:00:01Z
expect_failure "$temp_root/post-pr-promotion-current-h2-closed.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase ready
grep -Fq 'Live promotion PR identity differs from immutable QA history' \
  "$temp_root/post-pr-promotion-current-h2-closed.log" \
  || fail 'historical H1/current H2 CLOSED drift did not fail live identity replay'
restore_post_pr_promotion_h2_observation
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_9" \
  main OPEN true none none none none "$post_pr_promotion_target_base" false \
  example/opencaw-fixture "$post_pr_promotion_created_at" none
expect_failure "$temp_root/post-pr-promotion-current-h2-draft.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase ready
grep -Fq 'Live promotion PR identity differs from immutable QA history' \
  "$temp_root/post-pr-promotion-current-h2-draft.log" \
  || fail 'historical H1/current H2 draft drift did not fail live identity replay'
restore_post_pr_promotion_h2_observation
run_for "$project" bash commands/validate-gauntlet.sh post-pr-reopen --phase complete >/dev/null

set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_6" \
  main OPEN false none none none none "$post_pr_promotion_target_base" false \
  example/opencaw-fixture "$post_pr_promotion_created_at" none
expect_failure "$temp_root/post-pr-promotion-rewound-head.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase complete
restore_post_pr_promotion_h2_observation
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$orphan_sha" \
  main OPEN false none none none none "$post_pr_promotion_target_base" false \
  example/opencaw-fixture "$post_pr_promotion_created_at" none
expect_failure "$temp_root/post-pr-promotion-unrelated-head.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase complete
restore_post_pr_promotion_h2_observation
set_pr_observation "$promotion_fail_url" gauntlet/unrelated "$head_sha_9" \
  main OPEN false none none none none "$post_pr_promotion_target_base" false \
  example/opencaw-fixture "$post_pr_promotion_created_at" none
expect_failure "$temp_root/post-pr-promotion-source-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase complete
restore_post_pr_promotion_h2_observation
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_9" \
  release OPEN false none none none none "$post_pr_promotion_target_base" false \
  example/opencaw-fixture "$post_pr_promotion_created_at" none
expect_failure "$temp_root/post-pr-promotion-base-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase complete
restore_post_pr_promotion_h2_observation
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_9" \
  main OPEN false none none none none "$post_pr_promotion_target_base" false \
  different/repository "$post_pr_promotion_created_at" none
expect_failure "$temp_root/post-pr-promotion-repo-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase complete
restore_post_pr_promotion_h2_observation
set_pr_observation "$promotion_fail_url" gauntlet/post-pr-reopen "$head_sha_9" \
  main OPEN false none none none none "$post_pr_promotion_target_base" false \
  example/opencaw-fixture 2026-08-01T12:00:02Z none
expect_failure "$temp_root/post-pr-promotion-created-at-drift.log" run_for "$project" \
  bash commands/validate-gauntlet.sh post-pr-reopen --phase complete
restore_post_pr_promotion_h2_observation

post_pr_promotion_pass_evidence="$promotion_fail_url#issuecomment-78"
OPENCAW_TEST_SKIP_OBSERVATION=1 run_for "$project" \
  bash commands/record-gauntlet-promotion-qa.sh post-pr-reopen pass \
  "$promotion_fail_url" "$post_pr_promotion_pass_evidence" \
  --head-sha "$head_sha_9" >/dev/null
post_pr_promotion_pass_event="$post_pr_reopen_dir/promotion-events/event-002.md"
expect_file "$post_pr_promotion_pass_event"
expect_line '- Verdict: pass' "$post_pr_promotion_pass_event"
expect_line '- Completion event: .ai/gauntlets/post-pr-reopen/completion-events/event-002.md' \
  "$post_pr_promotion_pass_event"
expect_line "- Head SHA: $head_sha_9" "$post_pr_promotion_pass_event"
expect_line "- Created at: $post_pr_promotion_created_at" \
  "$post_pr_promotion_pass_event"
[[ "$promotion_fail_event_hash" == "$(git hash-object "$promotion_fail_event")" ]] \
  || fail 'same-PR H2 promotion validation mutated immutable H1 failure evidence'
run_for "$project" bash commands/validate-gauntlet.sh post-pr-reopen --phase complete >/dev/null
unset FAKE_DATE_ISO

numeric_round_dir="$temp_root/numeric-round-selection"
mkdir -p "$numeric_round_dir"
: >"$numeric_round_dir/round-999.md"
: >"$numeric_round_dir/round-1000.md"
numeric_latest="$(OPENCAW_PROJECT_ROOT="$project" bash -c \
  'source commands/lib/gauntlet-common.sh; gauntlet_latest_round_file "$1"' \
  _ "$numeric_round_dir")"
[[ "$numeric_latest" == "$numeric_round_dir/round-1000.md" ]] \
  || fail 'numeric latest-round selection imposed a three-digit ceiling or used lexicographic order'

echo '[7/8] preserving task, goal, progress, and promotion PR-readiness behavior'
printf '# Validation Summary\n\nAll local Gauntlet fixture checks passed.\n' >"$project/validation-summary.md"
task_pr_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/task" run_for "$project" \
  bash commands/pr-readiness-check.sh gauntlet-parent "$project/validation-summary.md")"
grep -q '^USER_CONFIRMATION_REQUIRED=YES$' <<<"$task_pr_output" || fail 'task readiness lost its human confirmation gate'
grep -q '^GOAL_FLOW_AUTOMATION=NO$' <<<"$task_pr_output" || fail 'task readiness enabled goal automation'

goal_pr_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/goal" run_for "$project" \
  bash commands/pr-readiness-check.sh --goal gauntlet-parent "$project/validation-summary.md")"
grep -q '^USER_CONFIRMATION_REQUIRED=NO$' <<<"$goal_pr_output" || fail 'goal readiness lost its automatic PR exception'
grep -q '^GOAL_FLOW_AUTOMATION=YES$' <<<"$goal_pr_output" || fail 'goal readiness did not identify goal automation'

sync_gauntlet_live_observations "$project" "$gauntlet_dir"
gauntlet_pr_output="$(OPENCAW_REPORT_DIR="$project/.ai/reports/gauntlet" run_for "$project" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet "$project/validation-summary.md")"
grep -q '^USER_CONFIRMATION_REQUIRED=YES$' <<<"$gauntlet_pr_output" || fail 'Gauntlet readiness bypassed human confirmation'
grep -q '^GOAL_FLOW_AUTOMATION=NO$' <<<"$gauntlet_pr_output" || fail 'Gauntlet readiness enabled goal automation'
grep -q '^GAUNTLET_FLOW=YES$' <<<"$gauntlet_pr_output" || fail 'Gauntlet readiness did not identify Gauntlet mode'
grep -q '^GAUNTLET_PROGRESS_AUTOMATION=NO$' <<<"$gauntlet_pr_output" \
  || fail 'final promotion readiness was confused with automatic progress publication'
grep -q '^ISSUE_LINK=Closes #101$' <<<"$gauntlet_pr_output" \
  || fail 'promotion readiness did not reserve the closing parent-issue link'
grep -q "^SOURCE_SHA=$head_sha_7$" <<<"$gauntlet_pr_output" \
  || fail 'Gauntlet readiness did not emit the exact passing integration Head SHA'
grep -q "^UNIT_MANIFEST_FINGERPRINT=$unit_manifest_opened$" \
  <<<"$gauntlet_pr_output" \
  || fail 'Gauntlet readiness did not emit the active completion manifest generation'

set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_6"
expect_failure "$temp_root/stale-promotion-source-ref.log" env OPENCAW_PROJECT_ROOT="$project" \
  OPENCAW_REPORT_DIR="$project/.ai/reports/stale-promotion-source" \
  bash commands/pr-readiness-check.sh --gauntlet fixture-gauntlet "$project/validation-summary.md"
set_local_ref "$project" gauntlet/fixture-gauntlet "$head_sha_7"

expect_failure "$temp_root/stopped-pr-readiness.log" env OPENCAW_PROJECT_ROOT="$project" \
  OPENCAW_REPORT_DIR="$project/.ai/reports/stopped" bash commands/pr-readiness-check.sh --gauntlet stopped-gauntlet "$project/validation-summary.md"
expect_failure "$temp_root/blocked-pr-readiness.log" env OPENCAW_PROJECT_ROOT="$project" \
  OPENCAW_REPORT_DIR="$project/.ai/reports/blocked" bash commands/pr-readiness-check.sh --gauntlet blocked-gauntlet "$project/validation-summary.md"

echo '[8/8] checking owned shell syntax and offline isolation'
bash -n tests/test-gauntlet-flow.sh commands/validate-opencaw.sh \
  commands/create-gauntlet-file.sh commands/validate-gauntlet.sh \
  commands/record-gauntlet-round.sh commands/record-gauntlet-pr-event.sh \
  commands/record-gauntlet-promotion-qa.sh \
  commands/create-gauntlet-completion-report.sh \
  commands/pr-readiness-check.sh commands/create-host-ai-scaffold.sh

[[ -s "$fake_gh_marker" ]] || fail 'Gauntlet tests never exercised the deterministic offline gh fixture'
awk -F '\t' '
  NF != 4 { bad=1 }
  $3 != "url,headRefName,headRefOid,baseRefName,baseRefOid,isCrossRepository,headRepository,state,isDraft,createdAt,closedAt,mergedAt,mergedBy,mergeCommit,body" { bad=1 }
  $4 != "[.url, .headRefName, .headRefOid, .baseRefName, .baseRefOid, (.isCrossRepository | tostring), (.headRepository.nameWithOwner // \"none\"), .state, (.isDraft | tostring), (.createdAt // \"none\"), (.closedAt // \"none\"), (.mergedAt // \"none\"), (.mergedBy.login // \"none\"), (if .mergedBy == null then \"none\" elif .mergedBy.is_bot == null then \"none\" else (.mergedBy.is_bot | tostring) end), (.mergeCommit.oid // \"none\"), (.body // \"\" | @base64)] | @tsv" { bad=1 }
  END { exit bad }
' "$fake_gh_marker" || fail 'a Gauntlet command requested an unexpected GitHub PR field set'
[[ -s "$fake_gh_api_marker" ]] \
  || fail 'Gauntlet tests never exercised the deterministic offline comment lookup fixture'
awk -F '\t' '
  NF != 2 { bad=1 }
  $1 == "user" && $2 != "[.login, .type] | @tsv" { bad=1 }
  $1 == "graphql" && $2 != "[.data.repository.pullRequest.mergedBy.__typename // \"none\", .data.repository.pullRequest.mergedBy.login // \"none\", (if (.data.repository.pullRequest.timelineItems.nodes|length)==0 then \"none\" else .data.repository.pullRequest.timelineItems.nodes[0].__typename end)] | @tsv" { bad=1 }
  $1 != "user" && $1 != "graphql" && $1 !~ /^repos\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/comments\/[1-9][0-9]*$/ { bad=1 }
  $1 != "user" && $1 != "graphql" && $2 != "[.html_url, .issue_url, (.id | tostring), (.body // \"\" | @base64), (.user.login // \"none\"), (.user.type // \"none\"), (.author_association // \"none\"), (.created_at // \"none\"), (.updated_at // \"none\")] | @tsv" { bad=1 }
  END { exit bad }
' "$fake_gh_api_marker" || fail 'a Gauntlet command used a noncanonical live comment lookup'
[[ ! -e "$network_marker" ]] || fail 'Gauntlet tests invoked a network-capable command'
echo 'Gauntlet flow tests passed.'
