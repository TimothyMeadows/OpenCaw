#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/generate-role-skill-map.sh [--check]

Generates .roles/ROLE_SKILL_MAP.md deterministically from the canonical JSON map.
With --check, exits nonzero instead of writing when the generated file has drifted.
EOF
}

mode="write"
if [[ $# -gt 1 ]]; then usage >&2; exit 1; fi
case "${1:-}" in
  "") ;;
  --check) mode="check" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
esac

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to generate the role capability map." >&2; exit 1; }

"$node_bin" - "$mode" <<'NODE'
const fs = require('fs');
const path = require('path');

const mode = process.argv[2];
const source = path.resolve('.roles/ROLE_SKILL_MAP.json');
const target = path.resolve('.roles/ROLE_SKILL_MAP.md');
let map;
try { map = JSON.parse(fs.readFileSync(source, 'utf8')); }
catch (error) { console.error(`Unable to parse ${source}: ${error.message}`); process.exit(1); }

function list(values) {
  if (!values.length) return ['- _(none)_'];
  return values.map(value => `- \`${value}\``);
}

const lines = [
  '# Role Capability Map', '',
  'This file is generated from `.roles/ROLE_SKILL_MAP.json`. Edit the canonical JSON and regenerate this file.', '',
  'Role mappings use domain-qualified identifiers. Shared capabilities apply after each role-specific mapping.', '',
  '## Shared Capabilities', '',
  '### Skills', '',
  ...list(map.__shared__?.skills || []), '',
  '### Commands', '',
  ...list(map.__shared__?.commands || []), '',
  '## Role Mappings', ''
];
for (const role of Object.keys(map).filter(key => key !== '__shared__').sort()) {
  lines.push(`### ${role}`, '', 'Skills:', '', ...list(map[role].skills), '', 'Commands:', '', ...list(map[role].commands), '');
}
const generated = `${lines.join('\n').trimEnd()}\n`;
if (mode === 'check') {
  if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8').replace(/\r\n/g, '\n') !== generated) {
    console.error('Role capability Markdown has drifted from canonical JSON. Run ./commands/generate-role-skill-map.sh.');
    process.exit(1);
  }
  console.log('Generated role capability map is current.');
} else {
  fs.writeFileSync(target, generated, 'utf8');
  console.log(`Generated ${target}`);
}
NODE
