#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/link-pr-to-task-issue.sh "<issue_url_or_number>" [pr_number_or_url]
EOF
}

issue_ref="${1:-}"
pr_ref="${2:-}"

if [[ -z "$issue_ref" ]]; then
  usage >&2
  exit 1
fi

resolve_gh() {
  if command -v gh >/dev/null 2>&1; then
    GH_BIN="$(command -v gh)"
    return
  fi

  if command -v gh.exe >/dev/null 2>&1; then
    GH_BIN="$(command -v gh.exe)"
    return
  fi

  echo "GitHub CLI (gh) is required by this script to link PRs to issues." >&2
  echo "If gh is unavailable, follow the PR process fallback: use an available github CLI/wrapper, then GitHub MCP/app connector tools." >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"

detect_repo_root() {
  if git -C "$host_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$host_root"
    return
  fi

  if git -C "$opencaw_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$opencaw_root"
    return
  fi

  echo "Unable to detect a git repository root for PR linking." >&2
  exit 1
}

extract_issue_number() {
  local ref="$1"
  ref="${ref##*/issues/}"
  ref="${ref#\#}"
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$ref"
    return
  fi

  echo "Unable to parse issue number from: $1" >&2
  exit 1
}

issue_number="$(extract_issue_number "$issue_ref")"
closing_line="Closes #$issue_number"
resolve_gh
repo_root="$(detect_repo_root)"

pushd "$repo_root" >/dev/null

if [[ -z "$pr_ref" ]]; then
  pr_ref="$("$GH_BIN" pr view --json number -q .number)"
fi

pr_body="$("$GH_BIN" pr view "$pr_ref" --json body -q .body)"

if printf '%s\n' "$pr_body" | grep -Eiq "(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#${issue_number}\b"; then
  echo "PR already linked to issue #$issue_number."
  popd >/dev/null
  exit 0
fi

if [[ -n "$pr_body" ]]; then
  new_body="${pr_body}"$'\n\n'"${closing_line}"
else
  new_body="$closing_line"
fi

"$GH_BIN" pr edit "$pr_ref" --body "$new_body" >/dev/null

popd >/dev/null

echo "Linked PR $pr_ref to issue #$issue_number using '$closing_line'."
