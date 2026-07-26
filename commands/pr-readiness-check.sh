#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/pr-readiness-check.sh [task_or_issue_ref] [validation_summary_file]
       ./commands/pr-readiness-check.sh --goal [task_or_issue_ref] [validation_summary_file]

Creates a non-destructive PR readiness report and prints the required user
confirmation prompt unless --goal is supplied. This command never commits,
pushes, or opens a PR.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

goal_flow=0
invocation_dir="$(pwd)"

args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal)
      goal_flow=1
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

task_ref="${args[0]:-Unspecified task}"
validation_summary_file="${args[1]:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
opencaw_resolve_paths
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
output_dir="${OPENCAW_REPORT_DIR:-$host_root/.ai/reports}"

detect_repo_root() {
  if git -C "$host_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$host_root"
    return
  fi

  if git -C "$opencaw_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$opencaw_root"
    return
  fi

  echo "Unable to detect a git repository root for PR readiness." >&2
  exit 1
}

repo_root="$(detect_repo_root)"
mkdir -p "$output_dir"

pushd "$repo_root" >/dev/null

repo_name="$(basename "$repo_root")"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown')"
last_commit="$(git log -1 --oneline 2>/dev/null || printf 'No commits found')"
status_short="$(git status --short 2>/dev/null || true)"
if [[ -z "$status_short" ]]; then
  status_short="Working tree clean"
fi

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
ahead_behind="No upstream configured"
if [[ -n "$upstream" ]]; then
  ahead_behind="$(git rev-list --left-right --count "$upstream...HEAD" 2>/dev/null | awk '{print "behind="$1" ahead="$2}' || printf 'Unable to calculate ahead/behind')"
fi

validation_summary="No validation summary file supplied. Include commands run, pass/fail status, and any residual risk before asking for PR approval."
if [[ -n "$validation_summary_file" ]]; then
  validation_summary_path="$validation_summary_file"
  if [[ "$validation_summary_path" != /* ]]; then
    validation_summary_path="$invocation_dir/$validation_summary_path"
  fi

  if [[ ! -f "$validation_summary_path" ]]; then
    echo "Validation summary file not found: $validation_summary_file" >&2
    exit 1
  fi
  validation_summary="$(cat "$validation_summary_path")"
fi

stamp="$(date -u +"%Y%m%d-%H%M%S")"
report_file="$output_dir/pr-readiness-$stamp.md"

if [[ $goal_flow -eq 1 ]]; then
  checkpoint_heading="## Goal Flow Automation Checkpoint"
  checkpoint_body="Goal flow is active for this task. This is the only OpenCaw exception to the human PR readiness approval prompt.

Because the user explicitly selected goal flow, the agent may automatically push/open a PR for this completed task after local validation is complete. Goal flow must not merge PRs, approve PRs, or enable auto-merge.

The agent must still:

1. Confirm the PR is available using the GitHub tool priority below.
2. Start post-PR QA immediately.
3. Post QA pass/fail evidence to the PR.
4. Record branch dependency when a later goal task should be based on this task branch or PR head.
5. Stop goal automation if PR creation or post-PR QA fails.
6. Move to the next goal task only after post-PR QA completes."
  next_steps_heading="## Automated Goal-Flow Next Steps"
  next_steps_body="1. Push/open the PR after local validation is complete.
2. Confirm the PR is available using the GitHub tool priority above.
3. Start task QA immediately.
4. Post QA pass/fail evidence to the PR using GitHub comments.
5. Include inline screenshot URLs when screenshots are part of the evidence.
6. If the next goal task depends on this unmerged work or risks conflicts later, branch it from this task branch or PR head.
7. Move to the next goal task only after QA is complete.
8. Never merge, approve, or enable auto-merge from goal flow."
else
  checkpoint_heading="## Required Human Checkpoint"
  checkpoint_body="Before any PR-related push or PR creation, ask the user:

> The implementation is complete enough for your validation. Are you ready for me to push this branch and open a pull request?

Do not run \`git push\`, \`gh pr create\`, \`github\` CLI PR creation, GitHub MCP/connector PR creation tools, auto-merge, or PR update automation until the user explicitly confirms."
  next_steps_heading="## After Confirmation"
  next_steps_body="1. Push/open the PR only after the user confirms readiness.
2. Confirm the PR is available using the GitHub tool priority above.
3. Start task QA immediately.
4. Post QA pass/fail evidence to the PR using GitHub comments.
5. Include inline screenshot URLs when screenshots are part of the evidence.
6. Notify the user when QA is complete and the PR is ready for review."
fi

cat >"$report_file" <<EOF
# PR Readiness Gate

## Summary

- Generated: $(date -u +"%Y-%m-%d %H:%M:%SZ")
- Repository: \`$repo_name\`
- Repository root: \`$repo_root\`
- Task or issue: \`$task_ref\`
- Branch: \`$branch\`
- Upstream: \`${upstream:-none}\`
- Ahead/behind: \`$ahead_behind\`
- Last commit: \`$last_commit\`
- Goal flow: \`$([[ $goal_flow -eq 1 ]] && printf 'enabled' || printf 'disabled')\`

## Working Tree

\`\`\`
$status_short
\`\`\`

## Validation Supplied

\`\`\`
$validation_summary
\`\`\`

$checkpoint_heading

$checkpoint_body

## GitHub Tool Priority

When choosing a tool for GitHub PR work, use:

1. \`gh\` from the local shell
2. an available \`github\` CLI executable or repository-provided GitHub CLI wrapper
3. GitHub MCP/app connector tools only when both CLI options are unavailable or unsuitable

$next_steps_heading

$next_steps_body
EOF

popd >/dev/null

echo "REPORT_FILE=$report_file"
if [[ $goal_flow -eq 1 ]]; then
  echo "USER_CONFIRMATION_REQUIRED=NO"
  echo "GOAL_FLOW_AUTOMATION=YES"
  echo "PROMPT=Goal flow is active. Automatically push/open the PR for this completed task, run post-PR QA, then continue to the next goal task only after QA completes."
else
  echo "USER_CONFIRMATION_REQUIRED=YES"
  echo "GOAL_FLOW_AUTOMATION=NO"
  echo "PROMPT=The implementation is complete enough for your validation. Are you ready for me to push this branch and open a pull request?"
fi
