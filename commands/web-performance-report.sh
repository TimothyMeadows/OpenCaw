#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/web-performance-report.sh <metrics-json> [output-md]

Converts local measured metrics into a Markdown report. Optional budgets in the
JSON are used for pass/fail evaluation; no universal thresholds are assumed.
EOF
}

metrics="${1:-}"
output="${2:-}"
if [[ -z "$metrics" || "$metrics" == "-h" || "$metrics" == "--help" ]]; then
  usage
  [[ -z "$metrics" ]] && exit 1 || exit 0
fi
[[ -f "$metrics" ]] || { echo "Metrics JSON does not exist: $metrics" >&2; exit 1; }
[[ $# -le 2 ]] || { usage >&2; exit 1; }
if [[ -z "$output" ]]; then output="${metrics%.*}.md"; fi
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required for performance reporting." >&2; exit 1; }
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  metrics="$(wslpath -w "$metrics")"
  output="$(wslpath -w "$output")"
fi

"$node_bin" - "$metrics" "$output" <<'NODE'
const fs = require('fs');
const path = require('path');
const [metricsArg, outputArg] = process.argv.slice(2);
let data;
try { data = JSON.parse(fs.readFileSync(metricsArg, 'utf8')); }
catch (error) { console.error(`Malformed metrics JSON: ${error.message}`); process.exit(1); }
if (!data || typeof data !== 'object' || Array.isArray(data) || !data.metrics || typeof data.metrics !== 'object' || Array.isArray(data.metrics)) {
  console.error('Metrics JSON must contain a metrics object.'); process.exit(1);
}
const budgets = data.budgets && typeof data.budgets === 'object' && !Array.isArray(data.budgets) ? data.budgets : {};
const units = data.units && typeof data.units === 'object' && !Array.isArray(data.units) ? data.units : {};
const rows = [];
for (const key of Object.keys(data.metrics).sort()) {
  const value = data.metrics[key];
  if (!Number.isFinite(value)) { console.error(`Metric '${key}' must be numeric.`); process.exit(1); }
  const budget = budgets[key];
  if (budget !== undefined && !Number.isFinite(budget)) { console.error(`Budget '${key}' must be numeric.`); process.exit(1); }
  rows.push({ key, value, unit: typeof units[key] === 'string' ? units[key].replace(/[|\r\n]/g, '') : '', budget, status: budget === undefined ? 'not evaluated' : value <= budget ? 'pass' : 'fail' });
}
if (!rows.length) { console.error('Metrics JSON contains no metrics.'); process.exit(1); }
const output = path.resolve(outputArg);
if (!fs.existsSync(path.dirname(output))) { console.error(`Output parent does not exist: ${path.dirname(output)}`); process.exit(1); }
if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) { console.error(`Output file must not be a symbolic link: ${output}`); process.exit(1); }
const lines = ['# Web Performance Report', '', '## Context', '', `- Source: \`${path.resolve(metricsArg).replace(/`/g, '')}\``, `- Scenario: ${String(data.scenario || 'not specified').replace(/[\r\n]/g, ' ')}`, `- Device/profile: ${String(data.profile || 'not specified').replace(/[\r\n]/g, ' ')}`, '', '## Measurements', '', '| Metric | Value | Unit | Budget | Status |', '| --- | ---: | --- | ---: | --- |'];
for (const row of rows) lines.push(`| ${row.key.replace(/\|/g, '')} | ${row.value} | ${row.unit} | ${row.budget === undefined ? 'not set' : row.budget} | ${row.status} |`);
const failed = rows.filter(row => row.status === 'fail').length;
lines.push('', '## Result', '', budgets && Object.keys(budgets).length ? (failed ? `Fail: ${failed} configured budget(s) exceeded.` : 'Pass: all configured budgets were met.') : 'Not evaluated: no budgets were provided.', '', '## Limits', '', '- This report summarizes supplied measurements and does not collect metrics.', '- Results apply only to the stated scenario and device/profile.', '');
fs.writeFileSync(output, `${lines.join('\n')}\n`, 'utf8');
console.log(`Wrote performance report to ${output}`);
if (failed) process.exitCode = 2;
NODE
