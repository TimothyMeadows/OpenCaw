#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/comment-pr-qa-results.sh "<pr_number_or_url>" "<results_summary_file>" [screenshot_or_artifact ...]

Posts a GitHub PR comment with QA pass/fail evidence. Screenshot references must
be HTTP(S) URLs so GitHub can render them inline. Local screenshot paths fail by
default because they cannot render inline in GitHub comments.
EOF
}

pr_ref="${1:-}"
summary_file="${2:-}"
if [[ $# -ge 2 ]]; then
  shift 2
else
  shift $# || true
fi
artifact_refs=("$@")

if [[ -z "$pr_ref" || -z "$summary_file" ]]; then
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

  echo "GitHub CLI (gh) is required by this script to post PR QA comments." >&2
  echo "If gh is unavailable, follow the PR process fallback: use an available github CLI/wrapper, then GitHub MCP/app connector tools." >&2
  exit 1
}

is_image_ref() {
  local ref_lower
  ref_lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ "$ref_lower" =~ \.(png|jpg|jpeg|gif|webp)(\?.*)?$ ]]
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opencaw_root="$(cd "$script_dir/.." && pwd)"
host_root="$(cd "$opencaw_root/.." && pwd)"
summary_text="$(cat "$summary_file")"

repo_root="$host_root"
if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$opencaw_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo_root="$opencaw_root"
  else
    echo "Unable to detect a git repository root for PR QA comments." >&2
    exit 1
  fi
fi

resolve_gh

inline_or_artifact_block=""
local_screenshot_errors=()
inline_screenshot_count=0

if [[ ${#artifact_refs[@]} -eq 0 ]]; then
  inline_or_artifact_block="- No screenshots or artifacts supplied."
else
  for ref in "${artifact_refs[@]}"; do
    label="$(basename "$ref")"
    if [[ "$ref" =~ ^https?:// ]]; then
      if is_image_ref "$ref"; then
        inline_or_artifact_block+="- Inline screenshot: ${ref}"$'\n'
        inline_or_artifact_block+="![${label}](${ref})"$'\n'
        inline_screenshot_count=$((inline_screenshot_count + 1))
      else
        inline_or_artifact_block+="- ${ref}"$'\n'
      fi
    elif is_image_ref "$ref"; then
      local_screenshot_errors+=("$ref")
      inline_or_artifact_block+="- Local screenshot path: \`${ref}\`"$'\n'
    else
      inline_or_artifact_block+="- \`${ref}\`"$'\n'
    fi
  done
fi

if [[ ${#local_screenshot_errors[@]} -gt 0 && "${OPENCAW_ALLOW_LOCAL_SCREENSHOT_REFERENCES:-}" != "1" ]]; then
  {
    echo "Local screenshot paths cannot render inline in GitHub PR comments."
    echo "Provide HTTP(S) screenshot URLs, or set OPENCAW_ALLOW_LOCAL_SCREENSHOT_REFERENCES=1 to post local paths as a temporary exception."
    printf 'Local screenshot: %s\n' "${local_screenshot_errors[@]}"
  } >&2
  exit 1
fi

pushd "$repo_root" >/dev/null
pr_url="$("$GH_BIN" pr view "$pr_ref" --json url -q .url)"
timestamp_utc="$(date -u +"%Y-%m-%d %H:%M:%SZ")"
comment_file="$(mktemp)"
trap 'rm -f "$comment_file"' EXIT

cat >"$comment_file" <<EOF
## PR QA Results

Timestamp (UTC): $timestamp_utc

PR: $pr_url

### Summary

\`\`\`
$summary_text
\`\`\`

### Screenshots / Artifacts

$inline_or_artifact_block
EOF

"$GH_BIN" pr comment "$pr_ref" --body-file "$comment_file" >/dev/null

popd >/dev/null

echo "Posted PR QA results comment to: $pr_url"
echo "INLINE_SCREENSHOTS=$inline_screenshot_count"
