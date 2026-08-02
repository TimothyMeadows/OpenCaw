#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/comment-pr-qa-results.sh "<pr_number_or_url>" "<results_summary_file>" [--gauntlet-verdict pass|fail --head-sha <sha> --gauntlet-source <project-relative-evidence> [--gauntlet-affected-units <none|comma-sorted-ids>]] [screenshot_or_artifact ...]

Posts a GitHub PR comment with QA pass/fail evidence. Screenshot references must
be HTTP(S) URLs so GitHub can render them inline. Local screenshot paths fail by
default because they cannot render inline in GitHub comments. On success, emits
the exact COMMENT_URL returned by GitHub for durable QA evidence.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

pr_ref="${1:-}"
summary_file="${2:-}"
if [[ $# -ge 2 ]]; then
  shift 2
else
  shift $# || true
fi
gauntlet_verdict=''
gauntlet_head_sha=''
gauntlet_source=''
gauntlet_affected_units='none'
gauntlet_affected_units_supplied=0
artifact_refs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gauntlet-verdict)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      gauntlet_verdict="$2"
      shift 2
      ;;
    --head-sha)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      gauntlet_head_sha="$2"
      shift 2
      ;;
    --gauntlet-source)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      gauntlet_source="$2"
      shift 2
      ;;
    --gauntlet-affected-units)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      gauntlet_affected_units="$2"
      gauntlet_affected_units_supplied=1
      shift 2
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *) artifact_refs+=("$1"); shift ;;
  esac
done

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
source "$script_dir/lib/gauntlet-common.sh"
opencaw_root="$OPENCAW_ROOT"
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
summary_text="$(cat "$summary_file")"
gauntlet_marker=''
if [[ -n "$gauntlet_verdict" || -n "$gauntlet_head_sha" || -n "$gauntlet_source" \
  || $gauntlet_affected_units_supplied -eq 1 ]]; then
  [[ "$gauntlet_verdict" == 'pass' || "$gauntlet_verdict" == 'fail' ]] || {
    echo '--gauntlet-verdict must be pass or fail when Gauntlet QA metadata is supplied.' >&2
    exit 1
  }
  gauntlet_validate_head_sha "$gauntlet_head_sha" 'Gauntlet QA head SHA'
  gauntlet_head_sha="${gauntlet_head_sha,,}"
  [[ "$gauntlet_source" =~ ^\.ai/gauntlets/[a-z0-9]+(-[a-z0-9]+)*/(rounds/[a-z0-9-]+/round-[0-9]{3,}|completion-events/event-[0-9]{3,})\.md$ ]] || {
    echo 'Gauntlet QA source must be a project-relative immutable round or completion event.' >&2
    exit 1
  }
  gauntlet_source_file="$host_root/$gauntlet_source"
  gauntlet_assert_safe_ai_path "$gauntlet_source_file" \
    'Gauntlet QA source evidence'
  [[ -f "$gauntlet_source_file" && ! -L "$gauntlet_source_file" ]] || {
    echo "Gauntlet QA source evidence is missing or unsafe: $gauntlet_source" >&2
    exit 1
  }
  gauntlet_source_hash="$(gauntlet_hash_file "$gauntlet_source_file")"
  if [[ "$gauntlet_affected_units" != 'none' ]]; then
    [[ "$gauntlet_affected_units" =~ ^[a-z0-9]+(-[a-z0-9]+)*(,[a-z0-9]+(-[a-z0-9]+)*)*$ \
      && "$gauntlet_affected_units" == "$(printf '%s' "$gauntlet_affected_units" | tr ',' '\n' | LC_ALL=C sort -u | paste -sd, -)" ]] || {
      echo '--gauntlet-affected-units must be none or unique comma-sorted kebab-case IDs.' >&2
      exit 1
    }
  fi
  gauntlet_marker="<!-- opencaw-gauntlet-qa:v1 verdict=$gauntlet_verdict head-sha=$gauntlet_head_sha source=$gauntlet_source source-sha256=$gauntlet_source_hash affected-units=$gauntlet_affected_units -->"
fi

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

$gauntlet_marker

### Summary

\`\`\`
$summary_text
\`\`\`

### Screenshots / Artifacts

$inline_or_artifact_block
EOF

gh_comment_file="$comment_file"
if [[ "${GH_BIN,,}" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  gh_comment_file="$(wslpath -w "$comment_file")"
fi

comment_output="$("$GH_BIN" pr comment "$pr_ref" --body-file "$gh_comment_file")"
comment_url="$(printf '%s\n' "$comment_output" \
  | grep -Eo 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/(pull|issues)/[0-9]+#issuecomment-[0-9]+' \
  | tail -n 1 || true)"
if [[ -z "$comment_url" ]]; then
  {
    echo 'GitHub accepted the PR comment but did not return its durable comment URL.'
    echo "PR_URL=$pr_url"
    echo 'Recover the created comment URL from the PR before recording Gauntlet QA evidence.'
  } >&2
  exit 1
fi

popd >/dev/null

echo "Posted PR QA results comment to: $pr_url"
echo "COMMENT_URL=$comment_url"
echo "INLINE_SCREENSHOTS=$inline_screenshot_count"
if [[ -n "$gauntlet_marker" ]]; then
  echo "GAUNTLET_VERDICT=$gauntlet_verdict"
  echo "HEAD_SHA=$gauntlet_head_sha"
  echo "GAUNTLET_SOURCE=$gauntlet_source"
  echo "GAUNTLET_SOURCE_SHA256=$gauntlet_source_hash"
  echo "GAUNTLET_AFFECTED_UNITS=$gauntlet_affected_units"
fi
