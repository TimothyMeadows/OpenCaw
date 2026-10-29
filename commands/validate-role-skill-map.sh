#!/usr/bin/env bash
set -euo pipefail

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate role mappings." >&2; exit 1; }

"$node_bin" <<'NODE'
const fs = require('fs');
const path = require('path');

const rolesRoot = path.resolve('.roles');
const skillsRoot = path.resolve('skills');
const commandsRoot = path.resolve('commands');
const mapPath = path.join(rolesRoot, 'ROLE_SKILL_MAP.json');
let map;
try { map = JSON.parse(fs.readFileSync(mapPath, 'utf8')); }
catch (error) { console.error(`Unable to parse ${mapPath}: ${error.message}`); process.exit(1); }

const roles = [];
for (const domain of fs.readdirSync(rolesRoot, { withFileTypes: true }).filter(entry => entry.isDirectory())) {
  for (const role of fs.readdirSync(path.join(rolesRoot, domain.name), { withFileTypes: true }).filter(entry => entry.isDirectory())) {
    if (fs.existsSync(path.join(rolesRoot, domain.name, role.name, 'ROLE.md'))) roles.push(`${domain.name}/${role.name}`);
  }
}
roles.sort();
const roleSet = new Set(roles);
const skillSet = new Set(fs.readdirSync(skillsRoot, { withFileTypes: true }).filter(entry => entry.isDirectory() && fs.existsSync(path.join(skillsRoot, entry.name, 'SKILL.md'))).map(entry => entry.name));
const commandSet = new Set(fs.readdirSync(commandsRoot, { withFileTypes: true }).filter(entry => entry.isFile() && /^[a-z0-9]+(?:-[a-z0-9]+)*\.(?:sh|ps1)$/.test(entry.name)).map(entry => `commands/${entry.name}`));
const errors = [];

const expectedKeyOrder = ['__shared__', ...roles];
const actualKeyOrder = Object.keys(map);
if (JSON.stringify(actualKeyOrder) !== JSON.stringify(expectedKeyOrder)) errors.push('Canonical role map keys must be ordered as __shared__ followed by domain-qualified role ids.');

if (!map || typeof map !== 'object' || Array.isArray(map)) errors.push('Canonical role map must be a JSON object.');
for (const role of roles) if (!(role in map)) errors.push(`Missing explicit role mapping: ${role}`);
for (const key of Object.keys(map)) {
  if (key !== '__shared__' && !key.includes('/')) errors.push(`Role mapping is not domain-qualified: ${key}`);
  if (key !== '__shared__' && !roleSet.has(key)) errors.push(`Unknown role mapping: ${key}`);
  const entry = map[key];
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) { errors.push(`${key} mapping must be an object.`); continue; }
  for (const field of ['skills', 'commands']) {
    if (!Array.isArray(entry[field])) { errors.push(`${key}.${field} must be an array.`); continue; }
    const seen = new Set();
    for (const value of entry[field]) {
      if (typeof value !== 'string' || !value) { errors.push(`${key}.${field} contains an invalid value.`); continue; }
      if (seen.has(value)) errors.push(`${key}.${field} contains a duplicate: ${value}`);
      seen.add(value);
      if (field === 'skills' && !skillSet.has(value)) errors.push(`${key} maps unknown skill: ${value}`);
      if (field === 'commands' && !commandSet.has(value)) errors.push(`${key} maps unknown command: ${value}`);
    }
  }
  for (const field of Object.keys(entry)) if (!['skills', 'commands'].includes(field)) errors.push(`${key} contains unknown field: ${field}`);
}
if (!('__shared__' in map)) errors.push('Missing __shared__ mapping.');
if (errors.length) {
  errors.sort().forEach(error => console.error(error));
  process.exit(1);
}
console.log(`Role capability references are valid for ${roles.length} role(s).`);
NODE

./commands/generate-role-skill-map.sh --check
echo "Role capability map validation passed."
