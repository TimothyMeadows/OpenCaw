#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/comment-issue-test-results.sh "<issue_url_or_number>" "<results_summary_file>" [screenshot_or_artifact ...]
EOF
}

issue_ref="${1:-}"
summary_file="${2:-}"
shift 2 || true
screenshot_refs=("$@")

if [[ -z "$issue_ref" || -z "$summary_file" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$summary_file" ]]; then
  echo "Results summary file not found: $summary_file" >&2
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

  echo "GitHub CLI (gh) is required to post issue comments." >&2
  exit 1
}

resolve_gh

timestamp_utc="$(date -u +"%Y-%m-%d %H:%M:%SZ")"
summary_text="$(cat "$summary_file")"

screenshots_block=""
if [[ ${#screenshot_refs[@]} -eq 0 ]]; then
  screenshots_block="- No screenshots supplied."
else
  for ref in "${screenshot_refs[@]}"; do
    if [[ "$ref" =~ ^https?:// ]]; then
      screenshots_block+="- ${ref}"$'\n'
      screenshots_block+="![](${ref})"$'\n'
    else
      screenshots_block+="- \`${ref}\`"$'\n'
    fi
  done
fi

comment_body="$(cat <<EOF
## QA Test Results

Timestamp (UTC): $timestamp_utc

### Summary
\`\`\`
$summary_text
\`\`\`

### Screenshots / Artifacts
$screenshots_block
EOF
)"

"$GH_BIN" issue comment "$issue_ref" --body "$comment_body" >/dev/null
echo "Posted QA results comment to issue: $issue_ref"
