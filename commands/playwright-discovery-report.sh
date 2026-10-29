#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
OPENCAW_PROJECT_ROOT="${OPENCAW_HOST_ROOT:-${OPENCAW_PROJECT_ROOT:-}}"
opencaw_resolve_paths
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
discovery_dir="${1:-.playwright-cli}"
output_dir="${2:-.opencaw/.cache/reports}"

cd "$host_root"
mkdir -p "$output_dir"

if [[ ! -d "$discovery_dir" ]]; then
  echo "Discovery directory not found: $host_root/$discovery_dir" >&2
  exit 1
fi

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for Playwright reports; nothing was installed.' >&2; exit 1; }
node_discovery="$discovery_dir"
node_output="$output_dir"
node_host="$host_root"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_discovery="$(wslpath -w "$(cd "$discovery_dir" && pwd -P)")"
  node_output="$(wslpath -w "$(cd "$output_dir" && pwd -P)")"
  node_host="$(wslpath -w "$host_root")"
fi
"$node_bin" - "$node_discovery" "$node_output" "$node_host" <<'NODE'
const fs = require('fs');
const path = require('path');

const [discoveryDirInput, outputDir, hostRoot] = process.argv.slice(2);
const discoveryDir = path.resolve(hostRoot, discoveryDirInput);

function rel(p) {
  return path.relative(hostRoot, p).replace(/\\/g, '/');
}

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else if (entry.isFile()) files.push(full);
  }
  return files;
}

function extract(patterns, text) {
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) return match[1].trim();
  }
  return '';
}

const files = walk(discoveryDir);
const snapshots = files.filter(f => ['.yml', '.yaml'].includes(path.extname(f).toLowerCase()));
const screenshots = files.filter(f => ['.png', '.jpg', '.jpeg'].includes(path.extname(f).toLowerCase()));
const tracesVideos = files.filter(f => ['.zip', '.trace', '.webm', '.mp4'].includes(path.extname(f).toLowerCase()));

const rows = snapshots.map(file => {
  const text = fs.readFileSync(file, 'utf8').slice(0, 20000);
  return {
    file,
    url: extract([/Page URL:\s*(.+)/i, /\burl:\s*['"]?([^'"\n]+)['"]?/i], text),
    title: extract([/Page Title:\s*(.+)/i, /\btitle:\s*['"]?([^'"\n]+)['"]?/i], text),
  };
});

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const reportPath = path.join(outputDir, `playwright-discovery-${stamp}.md`);

function tableEscape(value) {
  return String(value ?? '').replace(/\|/g, '\\|').replace(/\r?\n/g, '<br>');
}

const lines = [];
lines.push('# Playwright Browser Discovery Report', '');
lines.push('## Summary', '');
lines.push(`- Generated: ${new Date().toISOString()}`);
lines.push(`- Discovery directory: \`${rel(discoveryDir)}\``);
lines.push(`- Snapshot count: ${snapshots.length}`);
lines.push(`- Screenshot count: ${screenshots.length}`);
lines.push(`- Trace/video count: ${tracesVideos.length}`);
lines.push('');
lines.push('## Navigation Evidence', '');
if (rows.length === 0) {
  lines.push('No snapshot files were found.', '');
} else {
  lines.push('| File | Page URL | Page Title |');
  lines.push('| --- | --- | --- |');
  for (const row of rows.slice(0, 200)) {
    lines.push(`| \`${tableEscape(rel(row.file))}\` | ${tableEscape(row.url)} | ${tableEscape(row.title)} |`);
  }
  if (rows.length > 200) lines.push(`| | | ${rows.length - 200} additional snapshots omitted |`);
  lines.push('');
}
lines.push('## Discovered Artifacts', '');
lines.push('### Snapshots', '');
for (const file of snapshots.slice(0, 100)) lines.push(`- \`${rel(file)}\``);
if (snapshots.length === 0) lines.push('None found.');
lines.push('');
lines.push('### Screenshots', '');
for (const file of screenshots.slice(0, 100)) lines.push(`- \`${rel(file)}\``);
if (screenshots.length === 0) lines.push('None found.');
lines.push('');
lines.push('### Traces And Videos', '');
for (const file of tracesVideos.slice(0, 100)) lines.push(`- \`${rel(file)}\``);
if (tracesVideos.length === 0) lines.push('None found.');
lines.push('');
lines.push('## Implementation Notes', '');
lines.push('- Stable selectors:');
lines.push('- Conditional behavior:');
lines.push('- Data setup:');
lines.push('- Follow-up test/page-object changes:');
lines.push('');
lines.push('## Notes', '');
lines.push('- This report is a non-interactive substitute for inspecting live browser discovery artifacts through a UI.');

fs.writeFileSync(reportPath, lines.join('\n'), 'utf8');
console.log(`REPORT_FILE=${reportPath}`);
console.log(`SUMMARY snapshots=${snapshots.length} screenshots=${screenshots.length} tracesVideos=${tracesVideos.length}`);
NODE
