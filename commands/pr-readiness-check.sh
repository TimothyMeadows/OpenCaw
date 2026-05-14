#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/pr-readiness-check.sh [task_or_issue_ref] [validation_summary_file]

Creates a non-destructive PR readiness report and prints the required user
confirmation prompt. This command never commits, pushes, or opens a PR.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

task_ref="${1:-Unspecified task}"
validation_summary_file="${2:-}"
invocation_dir="$(pwd)"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
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

## Working Tree

\`\`\`
$status_short
\`\`\`

## Validation Supplied

\`\`\`
$validation_summary
\`\`\`

## Required Human Checkpoint

Before any PR-related push or PR creation, ask the user:

> The implementation is complete enough for your validation. Are you ready for me to push this branch and open a pull request?

Do not run \`git push\`, \`gh pr create\`, \`github\` CLI PR creation, GitHub MCP/connector PR creation tools, auto-merge, or PR update automation until the user explicitly confirms.

## GitHub Tool Priority

When choosing a tool for GitHub PR work, use:

1. \`gh\` from the local shell
2. an available \`github\` CLI executable or repository-provided GitHub CLI wrapper
3. GitHub MCP/app connector tools only when both CLI options are unavailable or unsuitable

## After Confirmation

1. Push/open the PR only after the user confirms readiness.
2. Confirm the PR is available using the GitHub tool priority above.
3. Start task QA immediately.
4. Post QA pass/fail evidence to the PR using GitHub comments.
5. Include inline screenshot URLs when screenshots are part of the evidence.
6. Notify the user when QA is complete and the PR is ready for review.
EOF

popd >/dev/null

echo "REPORT_FILE=$report_file"
echo "USER_CONFIRMATION_REQUIRED=YES"
echo "PROMPT=The implementation is complete enough for your validation. Are you ready for me to push this branch and open a pull request?"
