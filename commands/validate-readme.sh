#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate README.md." >&2; exit 1; }

readme_for_node="$repo_root/README.md"
repo_for_node="$repo_root"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  readme_for_node="$(wslpath -w "$readme_for_node")"
  repo_for_node="$(wslpath -w "$repo_for_node")"
fi

"$node_bin" - "$readme_for_node" "$repo_for_node" <<'NODE'
const fs = require('fs');
const path = require('path');

const readmePath = process.argv[2];
const repoRoot = process.argv[3];
const content = fs.readFileSync(readmePath, 'utf8').replace(/\r\n/g, '\n');
const lines = content.split('\n');
const errors = [];

const expectedOpening = [
  '',
  '# OpenCaw',
  '',
  '![](OpenCaw.png)',
  ''
];
if (JSON.stringify(lines.slice(0, expectedOpening.length)) !== JSON.stringify(expectedOpening)) {
  errors.push('The README logo/video opening changed.');
}

function slug(value) {
  return value.trim().toLowerCase()
    .replace(/[^\p{L}\p{N}\p{Pc}\- ]/gu, '')
    .replace(/ /g, '-');
}

const headings = [];
const headingCounts = new Map();
for (const line of lines) {
  const match = line.match(/^(#{1,6})\s+(.+?)\s*$/);
  if (!match) continue;
  const item = { level: match[1].length, title: match[2], anchor: slug(match[2]) };
  headings.push(item);
  headingCounts.set(item.anchor, (headingCounts.get(item.anchor) || 0) + 1);
}
for (const [anchor, count] of headingCounts) {
  if (count > 1) errors.push(`Duplicate heading anchor: ${anchor}`);
}

const tocAnchors = [...content.matchAll(/^\s*- \[[^\]]+\]\(#([^)]+)\)/gm)].map(match => match[1]);
const tocSet = new Set(tocAnchors);
if (tocSet.size !== tocAnchors.length) errors.push('The table of contents contains duplicate anchors.');

const expectedToc = headings
  .filter(item => item.level <= 2 && !['opencaw', 'table-of-contents'].includes(item.anchor))
  .map(item => item.anchor);
for (const anchor of expectedToc) {
  if (!tocSet.has(anchor)) errors.push(`TOC omits heading: ${anchor}`);
}
for (const anchor of tocSet) {
  if (!expectedToc.includes(anchor)) errors.push(`TOC points to an unknown or out-of-scope heading: ${anchor}`);
}

const fenceCount = lines.filter(line => line.startsWith('```')).length;
if (fenceCount % 2 !== 0) errors.push(`Unbalanced fenced code blocks: ${fenceCount} markers.`);

const codeTokens = [...content.matchAll(/`([^`\r\n]+)`/g)].map(match => match[1]);
const repositoryPaths = [...new Set(codeTokens
  .filter(value => !/[<*>]/.test(value))
  .filter(value => /^(?:\.\/)?(?:commands|skills|\.roles|\.styles|\.architecture|assets|tests)\//.test(value))
  .map(value => value.replace(/^\.\//, '')))];
for (const relativePath of repositoryPaths) {
  if (!fs.existsSync(path.join(repoRoot, relativePath))) errors.push(`Documented path does not exist: ${relativePath}`);
}

const commandNames = [...new Set(codeTokens.filter(value => /^[a-z0-9][a-z0-9-]+\.(?:sh|ps1)$/.test(value)))];
for (const command of commandNames) {
  if (!fs.existsSync(path.join(repoRoot, 'commands', command))) errors.push(`Documented command does not exist: ${command}`);
}

if (/\.media\/(?:CLOUD_SESSION\.md|COMFYUI_LOCAL\.md|INDEX\.md|media-generation-manifest\.schema\.json|model-packs\.json|toolchain\.json)/.test(content)) {
  errors.push('README contains a stale legacy .media asset path.');
}
if (/\.styles\/\.gpu(?:\/|`)/.test(content)) {
  errors.push('README contains a stale legacy .styles/.gpu path.');
}
for (const required of ['CLOUD', 'LOCAL', 'CSS3', 'CODE', 'BLENDER', 'resolve-art-pipeline.sh', 'create-code-model-manifest.sh', 'create-code-character-profile.sh', 'validate-code-character-profile.sh', 'record-code-character-calibration.sh', 'record-code-character-gate.sh', 'measure-code-character-evidence.sh', 'code-character-profile.schema.json', 'code-character-observation.schema.json', 'code-character-evidence-report.schema.json', 'list-external-asset-libraries.sh', 'inspect-external-asset-library.sh', 'copy-external-asset.sh', 'assets/models/']) {
  if (!content.includes(required)) errors.push(`README omits art-pipeline documentation: ${required}`);
}

if (errors.length) {
  for (const error of errors) console.error(`README validation: ${error}`);
  process.exit(1);
}

console.log(`README validation passed (${tocAnchors.length} TOC anchors, ${commandNames.length} commands, ${repositoryPaths.length} paths).`);
NODE
