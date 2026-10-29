#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/brainstorm-common.sh"

usage() {
  cat <<'EOF'
Usage: ./commands/brainstorm-mode.sh <start|stop|status> [--dry-run]

start   Create or reactivate repository-root BRAINSTORM.md.
stop    Explicitly deactivate Brainstorm mode and regenerate BRAINSTORM_SUMMARY.md.
status  Print current state, counts, and summary currency.

--dry-run previews start or stop without writing files.
EOF
}

action="${1:-}"
dry_run=0
if [[ "$action" == '-h' || "$action" == '--help' || -z "$action" ]]; then usage; [[ -n "$action" ]] || exit 1; exit 0; fi
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done
if [[ "$action" == 'status' && $dry_run -eq 1 ]]; then
  echo '--dry-run is valid only with start or stop.' >&2
  exit 1
fi

write_new_brainstorm() {
  local timestamp="$1"
  cat <<EOF
# Brainstorm

## Mode
- Status: active
- Active session: BS-001
- Activated at: $timestamp
- Deactivated at: pending

## Session History
- BS-001 | started: $timestamp | ended: pending

## Branches

<!-- One line per branch: - BR-NNN | parent: ROOT or BR-NNN | title: title | summary: one-line summary -->

## Elements

<!--
Each element uses a stable heading and these required fields/subsections:

### IDEA-NNN
- Title: Single-line title
- Branch: BR-NNN
- Status: captured|clarifying|researching|plan-ready|parked
- Created at: canonical UTC timestamp
- Updated at: canonical UTC timestamp
- Plan readiness: yes only for plan-ready; otherwise no
- Summary: One-line index summary

#### User Idea
#### Base Understanding
#### Research Findings and Citations
#### Dependencies
#### Risks
#### Open Questions
#### Start Conditions
#### Definition of Complete
-->
EOF
}

next_session_id() {
  local max
  max="$(grep -Eo 'BS-[0-9]{3,}' "$OPENCAW_BRAINSTORM_FILE" | sed 's/^BS-//' | sort -n | tail -n1 || true)"
  [[ -n "$max" ]] || max=0
  printf 'BS-%03d' "$((10#$max + 1))"
}

stage_active_copy() {
  local source="$1" target="$2" session_id="$3" timestamp="$4"
  awk -v session="$session_id" -v now="$timestamp" '
    { sub(/\r$/, "") }
    /^## Mode$/ { in_mode=1 }
    /^## / && $0 != "## Mode" { in_mode=0 }
    in_mode && /^- Status: / { print "- Status: active"; next }
    in_mode && /^- Active session: / { print "- Active session: " session; next }
    in_mode && /^- Activated at: / { print "- Activated at: " now; next }
    in_mode && /^- Deactivated at: / { print "- Deactivated at: pending"; next }
    /^## Session History$/ { print; print "- " session " | started: " now " | ended: pending"; next }
    { print }
  ' "$source" > "$target"
}

stage_inactive_copy() {
  local source="$1" target="$2" session_id="$3" timestamp="$4"
  awk -v session="$session_id" -v now="$timestamp" '
    { sub(/\r$/, "") }
    /^## Mode$/ { in_mode=1 }
    /^## / && $0 != "## Mode" { in_mode=0 }
    in_mode && /^- Status: / { print "- Status: inactive"; next }
    in_mode && /^- Deactivated at: / { print "- Deactivated at: " now; next }
    $0 == "- " session " | started: " {
      print
      next
    }
    index($0, "- " session " | started: ") == 1 && $0 ~ / \| ended: pending$/ {
      sub(/ \| ended: pending$/, " | ended: " now)
    }
    { print }
  ' "$source" > "$target"
}

case "$action" in
  start)
    timestamp="$(brainstorm_utc_now)"
    if ! brainstorm_detect_state; then
      echo 'Cannot start Brainstorm mode because the existing BRAINSTORM.md state is malformed.' >&2
      exit 1
    fi
    if [[ "$OPENCAW_BRAINSTORM_STATE" == 'active' ]]; then
      brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" active
      echo "Brainstorm mode is already active: $OPENCAW_BRAINSTORM_FILE"
      exit 0
    fi
    tmp="$(mktemp "$OPENCAW_PROJECT_ROOT_RESOLVED/.brainstorm-start.XXXXXX")"
    trap 'rm -f -- "${tmp:-}"' EXIT
    if [[ "$OPENCAW_BRAINSTORM_STATE" == 'absent' ]]; then
      write_new_brainstorm "$timestamp" > "$tmp"
    else
      brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" inactive
      session_id="$(next_session_id)"
      stage_active_copy "$OPENCAW_BRAINSTORM_FILE" "$tmp" "$session_id" "$timestamp"
    fi
    brainstorm_validate_file "$tmp" active
    if [[ $dry_run -eq 1 ]]; then
      echo "Dry run: would activate $OPENCAW_BRAINSTORM_FILE"
      cat "$tmp"
      exit 0
    fi
    mv "$tmp" "$OPENCAW_BRAINSTORM_FILE"
    trap - EXIT
    echo "Brainstorm mode activated: $OPENCAW_BRAINSTORM_FILE"
    ;;
  stop)
    if ! brainstorm_detect_state; then
      echo 'Cannot stop Brainstorm mode because BRAINSTORM.md state is malformed.' >&2
      exit 1
    fi
    if [[ "$OPENCAW_BRAINSTORM_STATE" == 'absent' ]]; then
      echo 'Brainstorm mode has not been started.' >&2
      exit 1
    fi
    if [[ -L "$OPENCAW_BRAINSTORM_SUMMARY_FILE" ]]; then
      echo "Cannot stop Brainstorm mode because the summary path is a symbolic link: $OPENCAW_BRAINSTORM_SUMMARY_FILE" >&2
      exit 1
    fi
    timestamp="$(brainstorm_utc_now)"
    if [[ "$OPENCAW_BRAINSTORM_STATE" == 'inactive' ]]; then
      brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" inactive
      if brainstorm_validate_summary "$OPENCAW_BRAINSTORM_FILE" "$OPENCAW_BRAINSTORM_SUMMARY_FILE" >/dev/null 2>&1; then
        echo "Brainstorm mode is already inactive and its summary is current: $OPENCAW_BRAINSTORM_SUMMARY_FILE"
        exit 0
      fi
      staged_brainstorm="$OPENCAW_BRAINSTORM_FILE"
    else
      brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" active
      staged_brainstorm="$(mktemp "$OPENCAW_PROJECT_ROOT_RESOLVED/.brainstorm-stop.XXXXXX")"
      stage_inactive_copy "$OPENCAW_BRAINSTORM_FILE" "$staged_brainstorm" "$OPENCAW_BRAINSTORM_ACTIVE_SESSION" "$timestamp"
      brainstorm_validate_file "$staged_brainstorm" inactive
    fi
    staged_summary="$(mktemp "$OPENCAW_PROJECT_ROOT_RESOLVED/.brainstorm-summary.XXXXXX")"
    trap '[[ "${staged_brainstorm:-}" == "$OPENCAW_BRAINSTORM_FILE" ]] || rm -f -- "${staged_brainstorm:-}"; rm -f -- "${staged_summary:-}" "${backup_brainstorm:-}" "${backup_summary:-}"' EXIT
    brainstorm_write_summary "$staged_brainstorm" "$staged_summary"
    brainstorm_validate_summary "$staged_brainstorm" "$staged_summary"
    if [[ $dry_run -eq 1 ]]; then
      echo "Dry run: would deactivate $OPENCAW_BRAINSTORM_FILE"
      echo "Dry run: would regenerate $OPENCAW_BRAINSTORM_SUMMARY_FILE"
      cat "$staged_summary"
      exit 0
    fi
    backup_brainstorm="$(mktemp "$OPENCAW_PROJECT_ROOT_RESOLVED/.brainstorm-backup.XXXXXX")"
    cp "$OPENCAW_BRAINSTORM_FILE" "$backup_brainstorm"
    backup_summary=''
    if [[ -f "$OPENCAW_BRAINSTORM_SUMMARY_FILE" ]]; then
      backup_summary="$(mktemp "$OPENCAW_PROJECT_ROOT_RESOLVED/.brainstorm-summary-backup.XXXXXX")"
      cp "$OPENCAW_BRAINSTORM_SUMMARY_FILE" "$backup_summary"
    fi
    rollback=0
    if [[ "$staged_brainstorm" != "$OPENCAW_BRAINSTORM_FILE" ]]; then
      mv "$staged_brainstorm" "$OPENCAW_BRAINSTORM_FILE" || rollback=1
    fi
    if [[ $rollback -eq 0 ]]; then
      mv "$staged_summary" "$OPENCAW_BRAINSTORM_SUMMARY_FILE" || rollback=1
    fi
    if [[ $rollback -ne 0 ]]; then
      cp "$backup_brainstorm" "$OPENCAW_BRAINSTORM_FILE"
      if [[ -n "$backup_summary" ]]; then cp "$backup_summary" "$OPENCAW_BRAINSTORM_SUMMARY_FILE"; else rm -f "$OPENCAW_BRAINSTORM_SUMMARY_FILE"; fi
      echo 'Brainstorm deactivation failed; prior artifacts were restored.' >&2
      exit 1
    fi
    brainstorm_validate_summary "$OPENCAW_BRAINSTORM_FILE" "$OPENCAW_BRAINSTORM_SUMMARY_FILE"
    rm -f -- "$backup_brainstorm" ${backup_summary:+"$backup_summary"}
    trap - EXIT
    echo "Brainstorm mode deactivated: $OPENCAW_BRAINSTORM_FILE"
    echo "Brainstorm summary generated: $OPENCAW_BRAINSTORM_SUMMARY_FILE"
    ;;
  status)
    if ! brainstorm_detect_state; then
      echo 'BRAINSTORM_STATUS=malformed'
      echo "BRAINSTORM_FILE=$OPENCAW_BRAINSTORM_FILE"
      exit 2
    fi
    echo "BRAINSTORM_STATUS=$OPENCAW_BRAINSTORM_STATE"
    echo "BRAINSTORM_FILE=$OPENCAW_BRAINSTORM_FILE"
    echo "BRAINSTORM_SUMMARY_FILE=$OPENCAW_BRAINSTORM_SUMMARY_FILE"
    if [[ "$OPENCAW_BRAINSTORM_STATE" == 'absent' ]]; then
      echo 'BRAINSTORM_BRANCHES=0'
      echo 'BRAINSTORM_ELEMENTS=0'
      echo 'BRAINSTORM_SUMMARY_CURRENT=no'
      exit 0
    fi
    brainstorm_validate_file "$OPENCAW_BRAINSTORM_FILE" "$OPENCAW_BRAINSTORM_STATE"
    echo "BRAINSTORM_SESSION=$OPENCAW_BRAINSTORM_ACTIVE_SESSION"
    echo "BRAINSTORM_BRANCHES=$OPENCAW_BRAINSTORM_BRANCH_COUNT"
    echo "BRAINSTORM_ELEMENTS=$OPENCAW_BRAINSTORM_ELEMENT_COUNT"
    if [[ "$OPENCAW_BRAINSTORM_STATE" == 'inactive' ]] && brainstorm_validate_summary "$OPENCAW_BRAINSTORM_FILE" "$OPENCAW_BRAINSTORM_SUMMARY_FILE" >/dev/null 2>&1; then
      echo 'BRAINSTORM_SUMMARY_CURRENT=yes'
    else
      echo 'BRAINSTORM_SUMMARY_CURRENT=no'
    fi
    ;;
  *) echo "Unknown action: $action" >&2; usage >&2; exit 1 ;;
esac
