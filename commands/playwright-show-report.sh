#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
host_root="${OPENCAW_HOST_ROOT:-$(pwd)}"
report_dir="${1:-playwright-report}"
output_dir="${2:-.ai/reports}"

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
