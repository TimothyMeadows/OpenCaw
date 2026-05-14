#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
host_root="${OPENCAW_HOST_ROOT:-$(pwd)}"
output_dir="${1:-.ai/reports}"

cd "$host_root"
mkdir -p "$output_dir"

summary_output=""
artifact_output=""
discovery_output=""

if [[ -f "test-results/results.json" ]]; then
  summary_output="$("$script_dir/playwright-report-summary.sh" "test-results/results.json" "$output_dir" || true)"
fi

artifact_output="$("$script_dir/playwright-artifact-index.sh" "." "$output_dir" || true)"

if [[ -d ".playwright-cli" ]]; then
  discovery_output="$("$script_dir/playwright-discovery-report.sh" ".playwright-cli" "$output_dir" || true)"
fi

stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
bundle="$output_dir/playwright-evidence-${stamp}.md"

{
  echo "# Playwright Evidence Report"
  echo
  echo "## Summary"
  echo
  echo "- Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- Host root: \`$host_root\`"
  echo
  echo "## Generated Reports"
  echo
  for output in "$summary_output" "$artifact_output" "$discovery_output"; do
    if [[ -n "$output" ]]; then
      while IFS= read -r line; do
        if [[ "$line" == REPORT_FILE=* ]]; then
          echo "- \`${line#REPORT_FILE=}\`"
        fi
      done <<< "$output"
    fi
  done
  echo
  echo "## Command Output"
  echo
  echo '```text'
  [[ -n "$summary_output" ]] && printf '%s\n' "$summary_output"
  [[ -n "$artifact_output" ]] && printf '%s\n' "$artifact_output"
  [[ -n "$discovery_output" ]] && printf '%s\n' "$discovery_output"
  echo '```'
  echo
  echo "## Notes"
  echo
  echo "- This bundle is intended for OpenCaw sessions where interactive Playwright UI and HTML report viewers are unavailable."
} > "$bundle"

echo "REPORT_FILE=$bundle"
