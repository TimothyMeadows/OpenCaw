#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
HEPHAERA_PROJECT_ROOT="${HEPHAERA_HOST_ROOT:-${HEPHAERA_PROJECT_ROOT:-}}"
hephaera_resolve_paths
host_root="$HEPHAERA_PROJECT_ROOT_RESOLVED"
results_json="${1:-test-results/results.json}"
output_dir="${2:-.hephaera/.cache/reports}"

cd "$host_root"
mkdir -p "$output_dir"

if [[ ! -f "$results_json" ]]; then
  echo "Playwright JSON results not found: $host_root/$results_json" >&2
  echo "Run Playwright with the JSON reporter enabled, for example: [['json', { outputFile: 'test-results/results.json' }]]." >&2
  exit 1
fi

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for Playwright reports; nothing was installed.' >&2; exit 1; }
node_results="$results_json"
node_output="$output_dir"
node_host="$host_root"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_results="$(wslpath -w "$(realpath "$results_json")")"
  node_output="$(wslpath -w "$(cd "$output_dir" && pwd -P)")"
  node_host="$(wslpath -w "$host_root")"
fi
"$node_bin" - "$node_results" "$node_output" "$node_host" <<'NODE'
const fs = require('fs');
const path = require('path');

const [resultsPath, outputDir, hostRoot] = process.argv.slice(2);
const raw = JSON.parse(fs.readFileSync(resultsPath, 'utf8'));

const tests = [];
function walkSuite(suite, titles = []) {
  const nextTitles = suite.title ? [...titles, suite.title] : titles;
  for (const spec of suite.specs || []) {
    const specTitle = [...nextTitles, spec.title].filter(Boolean).join(' > ');
    for (const test of spec.tests || []) {
      const project = test.projectName || test.projectId || '';
      const results = test.results || [];
      const final = results[results.length - 1] || {};
      const status = test.outcome || final.status || 'unknown';
      const expected = test.expectedStatus || 'passed';
      const location = spec.file ? `${spec.file}:${spec.line || 1}` : '';
      const errors = results.flatMap(r => r.errors || []);
      const attachments = results.flatMap(r => r.attachments || []);
      tests.push({ title: specTitle, project, status, expected, location, errors, attachments });
    }
  }
  for (const child of suite.suites || []) walkSuite(child, nextTitles);
}
for (const suite of raw.suites || []) walkSuite(suite);

const counts = {
  total: tests.length,
  passed: tests.filter(t => t.status === 'expected' || t.status === 'passed').length,
  failed: tests.filter(t => ['failed', 'unexpected', 'timedOut', 'interrupted'].includes(t.status)).length,
  skipped: tests.filter(t => ['skipped'].includes(t.status)).length,
  flaky: tests.filter(t => t.status === 'flaky').length,
};

const interesting = tests.filter(t => !['expected', 'passed'].includes(t.status));
const attachmentRows = [];
for (const t of tests) {
  for (const a of t.attachments) {
    if (a.path) attachmentRows.push({ test: t.title, name: a.name || a.contentType || 'attachment', path: a.path });
  }
}

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const reportPath = path.join(outputDir, `playwright-test-run-${stamp}.md`);

function tableEscape(value) {
  return String(value ?? '').replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
}

const lines = [];
lines.push('# Playwright Test Run Report', '');
lines.push('## Summary', '');
lines.push(`- Generated: ${new Date().toISOString()}`);
lines.push(`- Host root: \`${hostRoot}\``);
lines.push(`- Results JSON: \`${resultsPath}\``);
lines.push(`- Total: ${counts.total}`);
lines.push(`- Passed: ${counts.passed}`);
lines.push(`- Failed: ${counts.failed}`);
lines.push(`- Skipped: ${counts.skipped}`);
lines.push(`- Flaky/Unexpected: ${counts.flaky + interesting.filter(t => t.status === 'unexpected').length}`);
lines.push('');
lines.push('## Failed Or Unexpected Tests', '');
if (interesting.length === 0) {
  lines.push('No failed, skipped, flaky, or unexpected tests were reported.', '');
} else {
  lines.push('| Project | Test | Status | Location | First Error |');
  lines.push('| --- | --- | --- | --- | --- |');
  for (const t of interesting) {
    const firstError = t.errors[0]?.message || '';
    lines.push(`| ${tableEscape(t.project)} | ${tableEscape(t.title)} | ${tableEscape(t.status)} | ${tableEscape(t.location)} | ${tableEscape(firstError.slice(0, 500))} |`);
  }
  lines.push('');
}
lines.push('## Attachments And Evidence', '');
if (attachmentRows.length === 0) {
  lines.push('No result attachments were listed in the JSON report.', '');
} else {
  lines.push('| Test | Attachment | Path |');
  lines.push('| --- | --- | --- |');
  for (const row of attachmentRows.slice(0, 300)) {
    lines.push(`| ${tableEscape(row.test)} | ${tableEscape(row.name)} | \`${tableEscape(row.path)}\` |`);
  }
  if (attachmentRows.length > 300) lines.push(`| | | ${attachmentRows.length - 300} additional attachments omitted |`);
  lines.push('');
}
lines.push('## Notes', '');
lines.push('- This report is a non-interactive substitute for the Playwright HTML report UI.');
lines.push('- Pair it with `playwright-artifact-index.sh` for screenshots, traces, videos, logs, and raw report files.');

fs.writeFileSync(reportPath, lines.join('\n'), 'utf8');
console.log(`REPORT_FILE=${reportPath}`);
console.log(`SUMMARY total=${counts.total} passed=${counts.passed} failed=${counts.failed} skipped=${counts.skipped} flaky=${counts.flaky}`);
NODE
