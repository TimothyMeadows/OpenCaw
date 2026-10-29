#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/lib/memory-common.sh"
OPENCAW_PROJECT_ROOT="${OPENCAW_HOST_ROOT:-${OPENCAW_PROJECT_ROOT:-}}"
opencaw_resolve_paths
host_root="$OPENCAW_PROJECT_ROOT_RESOLVED"
scan_root="${1:-.}"
output_dir="${2:-.opencaw/.cache/reports}"

cd "$host_root"
mkdir -p "$output_dir"

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for Playwright reports; nothing was installed.' >&2; exit 1; }
node_scan="$scan_root"
node_output="$output_dir"
node_host="$host_root"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  [[ "$scan_root" == . ]] || node_scan="$(wslpath -w "$(realpath -m "$scan_root")")"
  node_output="$(wslpath -w "$(cd "$output_dir" && pwd -P)")"
  node_host="$(wslpath -w "$host_root")"
fi
"$node_bin" - "$node_scan" "$node_output" "$node_host" <<'NODE'
const fs = require('fs');
const path = require('path');

const [scanRootInput, outputDir, hostRoot] = process.argv.slice(2);
const scanRoot = path.resolve(hostRoot, scanRootInput);
const maxFiles = Number(process.env.PLAYWRIGHT_ARTIFACT_INDEX_MAX || 5000);
const preferredRoots = [
  'test-results',
  'playwright-report',
  'blob-report',
  '.playwright-cli',
].map(p => path.resolve(hostRoot, p));

const categories = {
  screenshots: [],
  videos: [],
  traces: [],
  reports: [],
  logs: [],
  snapshots: [],
};

function rel(p) {
  return path.relative(hostRoot, p).replace(/\\/g, '/');
}

function shouldSkipDir(name) {
  return ['node_modules', '.git', 'dist'].includes(name);
}

function addFile(file) {
  const ext = path.extname(file).toLowerCase();
  const base = path.basename(file).toLowerCase();
  if (['.png', '.jpg', '.jpeg'].includes(ext)) categories.screenshots.push(file);
  else if (['.webm', '.mp4'].includes(ext)) categories.videos.push(file);
  else if (['.zip', '.trace'].includes(ext) || base.includes('trace')) categories.traces.push(file);
  else if (['.html', '.json', '.xml'].includes(ext)) categories.reports.push(file);
  else if (['.log', '.txt'].includes(ext)) categories.logs.push(file);
  else if (['.yml', '.yaml'].includes(ext)) categories.snapshots.push(file);
}

function walk(dir, seen) {
  if (!fs.existsSync(dir) || seen.count >= maxFiles) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (seen.count >= maxFiles) break;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!shouldSkipDir(entry.name)) walk(full, seen);
    } else if (entry.isFile()) {
      seen.count++;
      addFile(full);
    }
  }
}

const roots = fs.existsSync(scanRoot) && scanRootInput !== '.'
  ? [scanRoot]
  : preferredRoots.filter(fs.existsSync);
if (roots.length === 0 && fs.existsSync(scanRoot)) roots.push(scanRoot);

const seen = { count: 0 };
for (const root of roots) walk(root, seen);

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
const reportPath = path.join(outputDir, `playwright-artifact-index-${stamp}.md`);

function section(lines, title, files) {
  lines.push(`### ${title}`, '');
  if (files.length === 0) {
    lines.push('None found.', '');
    return;
  }
  for (const file of files.slice(0, 200)) lines.push(`- \`${rel(file)}\``);
  if (files.length > 200) lines.push(`- ${files.length - 200} additional files omitted`);
  lines.push('');
}

const lines = [];
lines.push('# Playwright Artifact Index', '');
lines.push('## Summary', '');
lines.push(`- Generated: ${new Date().toISOString()}`);
lines.push(`- Host root: \`${hostRoot}\``);
lines.push(`- Indexed paths: ${roots.map(r => `\`${rel(r) || '.'}\``).join(', ') || 'none'}`);
lines.push(`- Screenshots: ${categories.screenshots.length}`);
lines.push(`- Videos: ${categories.videos.length}`);
lines.push(`- Traces: ${categories.traces.length}`);
lines.push(`- HTML/JSON/XML reports: ${categories.reports.length}`);
lines.push(`- Logs/text: ${categories.logs.length}`);
lines.push(`- Snapshots: ${categories.snapshots.length}`);
lines.push('');
lines.push('## Artifact Groups', '');
section(lines, 'Screenshots', categories.screenshots);
section(lines, 'Videos', categories.videos);
section(lines, 'Traces', categories.traces);
section(lines, 'Reports', categories.reports);
section(lines, 'Logs And Text', categories.logs);
section(lines, 'Discovery Snapshots', categories.snapshots);
lines.push('## Notes', '');
lines.push('- This report is a non-interactive substitute for browsing Playwright report and artifact folders.');
lines.push('- Use local paths from this report when posting verification evidence or diagnosing failures.');

fs.writeFileSync(reportPath, lines.join('\n'), 'utf8');
console.log(`REPORT_FILE=${reportPath}`);
console.log(`SUMMARY screenshots=${categories.screenshots.length} videos=${categories.videos.length} traces=${categories.traces.length} reports=${categories.reports.length}`);
NODE
