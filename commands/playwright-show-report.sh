#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
OPENCAW_PROJECT_ROOT="${OPENCAW_HOST_ROOT:-${OPENCAW_PROJECT_ROOT:-}}"
opencaw_resolve_paths
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
report_dir="${1:-playwright-report}"
output_dir="${2:-.opencaw/.cache/reports}"

cd "$host_root"
mkdir -p "$output_dir"

echo "Generating non-interactive Playwright report summaries."

if [[ -f "test-results/results.json" ]]; then
  "$script_dir/playwright-report-summary.sh" "test-results/results.json" "$output_dir"
else
  echo "No test-results/results.json found; skipping JSON summary." >&2
fi

if [[ -d "$report_dir" ]]; then
  "$script_dir/playwright-artifact-index.sh" "$report_dir" "$output_dir"
else
  echo "Playwright HTML report directory not found: $host_root/$report_dir" >&2
fi

"$script_dir/playwright-evidence-report.sh" "$output_dir"
