#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths

usage() {
  cat <<'EOF'
Usage: ./commands/create-goal-file.sh "<goal_name>" ["Goal Title"] [--dry-run]

Creates <project-root>/.ai/goals/<goal_name>/GOAL.md when it does not already exist.
Use --dry-run to print the goal scaffold without writing files.
EOF
}

goal_name=""
title=""
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
      if [[ -z "$goal_name" ]]; then
        goal_name="$1"
      elif [[ -z "$title" ]]; then
        title="$1"
      else
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$goal_name" ]]; then
  usage >&2
  exit 1
fi

if [[ ! "$goal_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "goal_name must be lowercase kebab-case: $goal_name" >&2
  exit 1
fi

if [[ -z "$title" ]]; then
  title="$goal_name"
fi

goal_dir="$OPENCAW_PROJECT_AI_DIR/goals/$goal_name"
target="$goal_dir/GOAL.md"

write_goal() {
  cat <<EOF
# $title

## Flow
- Type: goal
- Automation: enabled
- PR readiness confirmation: automatic
- Post-PR QA: required before next task
- Auto-merge: disabled
- Merge approval: human only

## Outcome

## Success Criteria

## Constraints

## Task Queue
1. [ ] TODO task name (\`.ai/tasks/<task-name>/TASK.md\`)

## Current Task

## Branch Chain
- Record each task as: \`task-name | base: <branch> | head: <branch> | PR: <url> | depends on: <prior task or none>\`.
- If a later task requires unmerged work from a previous task, or would likely create merge conflicts when based on the original base branch, branch from the previous task branch or PR head.
- Keep stacked branches ordered so human approval can happen from earliest dependency to latest dependent PR.

## Automation Rules
- Complete one task at a time unless the project-manager lane plan explicitly marks safe parallel work.
- After each task completes local validation, generate PR readiness with \`./commands/pr-readiness-check.sh --goal\`.
- Automatically push/open a PR for the completed task without asking for human PR readiness confirmation.
- Run post-PR QA immediately after the PR is available.
- Do not advance to the next task until post-PR QA is complete.
- Never merge, auto-merge, approve, or enable auto-merge for goal PRs.
- If a future task depends on a previous task or has likely merge-conflict risk, base the future task branch on the previous task branch or PR head and record that dependency in \`Branch Chain\`.
- When all goal tasks have completed post-PR QA, generate \`GOAL_REPORT.md\` with \`./commands/create-goal-completion-report.sh "$goal_name"\` before asking for human PR approval.
- Stop goal automation on validation failure, PR creation failure, post-PR QA failure, merge conflict, unresolved role ambiguity, or any required product/security decision outside this goal plan.

## PRs

## QA Evidence

## Goal Completion Report
- Generate with \`./commands/create-goal-completion-report.sh "$goal_name"\`.
- Include PR links in dependency order, branch base/head notes, post-PR QA evidence, and merge-conflict risk notes.
- Use this report for human approval after goal completion; do not merge automatically.

## Review Notes
EOF
}

if [[ $dry_run -eq 1 ]]; then
  echo "Dry run: would create $target"
  echo
  write_goal
  exit 0
fi

mkdir -p "$goal_dir"

if [[ -f "$target" ]]; then
  echo "$target already exists"
  exit 0
fi

write_goal > "$target"
echo "Created $target"
