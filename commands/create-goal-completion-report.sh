#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/create-goal-completion-report.sh "<goal_name|goal_dir|goal_file>" [--dry-run]

Creates or previews a GOAL_REPORT.md file next to GOAL.md. The report is the
human approval packet for goal-completion PR review and merge ordering.
EOF
}

goal_ref=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$goal_ref" ]]; then
        goal_ref="$1"
      else
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$goal_ref" ]]; then
  usage >&2
  exit 1
fi

resolve_goal_file() {
  local ref="$1"

  if [[ -f "$ref" ]]; then
    printf '%s\n' "$ref"
    return
  fi

  if [[ -d "$ref" && -f "$ref/GOAL.md" ]]; then
    printf '%s\n' "$ref/GOAL.md"
    return
  fi

  if [[ -f "../.ai/goals/$ref/GOAL.md" ]]; then
    printf '%s\n' "../.ai/goals/$ref/GOAL.md"
    return
  fi

  echo "Goal file not found for: $ref" >&2
  exit 1
}

goal_file="$(resolve_goal_file "$goal_ref")"
goal_dir="$(cd "$(dirname "$goal_file")" && pwd)"
goal_name="$(basename "$goal_dir")"
report_file="$goal_dir/GOAL_REPORT.md"

extract_section() {
  local heading="$1"
  awk -v heading="$heading" '
    $0 == "## " heading { in_section = 1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$goal_file"
}

section_or_placeholder() {
  local content="$1"
  local placeholder="$2"

  if [[ -n "${content//[[:space:]]/}" ]]; then
    printf '%s\n' "$content"
  else
    printf '%s\n' "$placeholder"
  fi
}

task_queue="$(extract_section "Task Queue")"
branch_chain="$(extract_section "Branch Chain")"
prs="$(extract_section "PRs")"
qa_evidence="$(extract_section "QA Evidence")"
review_notes="$(extract_section "Review Notes")"

write_report() {
  cat <<EOF
# Goal Completion Report: $goal_name

## Purpose

This report is the human approval packet for completed goal flow work.
Goal flow may automatically raise and QA PRs, but it must never merge PRs or enable auto-merge.

## Human Approval Rules

1. Review PRs in the order listed in this report.
2. Merge dependency PRs before dependent PRs.
3. After each merge, confirm the next PR still targets the right base branch and checks remain valid.
4. If a later PR was stacked on an earlier task branch, update or rebase it only after the earlier PR is merged.
5. Stop and re-run validation or post-PR QA if GitHub reports conflicts, stale checks, or changed base branches.

## Task Queue

$(section_or_placeholder "$task_queue" "_No task queue recorded in GOAL.md._")

## Branch Chain

$(section_or_placeholder "$branch_chain" "_No branch-chain records found. Confirm each PR base/head manually before approval._")

## PR Approval Order

$(section_or_placeholder "$prs" "_No PR links recorded. Add task PR links to GOAL.md before requesting approval._")

## Post-PR QA Evidence

$(section_or_placeholder "$qa_evidence" "_No QA evidence recorded. Post-PR QA must be complete before approval._")

## Review Notes

$(section_or_placeholder "$review_notes" "_No review notes recorded._")

## Final Checklist

- [ ] Every task PR link is present and ordered by dependency.
- [ ] Every PR has posted post-PR QA evidence.
- [ ] No PR has been auto-merged or marked for auto-merge.
- [ ] Stacked branches are approved from base dependency to final dependent PR.
- [ ] Merge conflict risk has been reviewed before human approval.
EOF
}

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $report_file"
  echo
  write_report
  exit 0
fi

write_report > "$report_file"
echo "Created $report_file"
