#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for code-character skill tests.' >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
require_text() {
  local file="$1"
  local text="$2"
  grep -Fqi -- "$text" "$file" || fail "$file omits required text: $text"
}

builder='skills/build-threejs-code-characters'
reviewer='skills/review-threejs-code-characters'
parent='skills/build-threejs-code-models/SKILL.md'

echo '[1/4] checking specialized triggers and generic routing'
require_text "$builder/SKILL.md" 'characters, creatures, and runtime actors'
require_text "$builder/SKILL.md" 'Use `build-threejs-code-models` directly for props'
require_text "$reviewer/SKILL.md" 'reviewer gates'
require_text "$reviewer/SKILL.md" 'isolated from builder history'
require_text "$parent" 'Route characters, creatures, animated actors'
require_text "$parent" 'keep props, environments, and generic procedural models in this skill'

echo '[2/4] checking one-level references and independent-review boundaries'
for file in \
  "$builder/references/design-contract.md" \
  "$builder/references/build-gates.md" \
  "$builder/references/evidence-adapter.md" \
  "$builder/references/rig-animation.md" \
  "$builder/references/failure-recovery.md" \
  "$reviewer/references/reviewer-packet.md" \
  "$reviewer/references/failure-recovery.md"; do
  [[ -f "$file" && ! -L "$file" ]] || fail "missing safe skill reference: $file"
done
require_text "$builder/references/build-gates.md" 'blockout-readability'
require_text "$builder/references/build-gates.md" 'optimization-budget'
require_text "$builder/references/evidence-adapter.md" 'Only a successful browser capture is trusted machine evidence'
require_text "$reviewer/references/reviewer-packet.md" 'intended answers'
require_text "$reviewer/references/reviewer-packet.md" 'builder reasoning'
require_text "$reviewer/SKILL.md" 'Do not rewrite the model'
[[ "$(find "$builder" "$reviewer" -mindepth 1 -type f | wc -l | tr -d '[:space:]')" -eq 11 ]] \
  || fail 'character skills contain files outside the required skill, metadata, and reference set'
if find "$builder" "$reviewer" -type f \( -name 'README*' -o -name 'CHANGELOG*' \) | grep -q .; then
  fail 'character skills contain an auxiliary file'
fi

echo '[3/4] checking generated metadata, catalogs, and role routing'
require_text "$builder/agents/openai.yaml" 'Use $build-threejs-code-characters'
require_text "$reviewer/agents/openai.yaml" 'Use $review-threejs-code-characters'
require_text 'skills/INDEX.md' '`build-threejs-code-characters`'
require_text 'skills/INDEX.md' '`review-threejs-code-characters`'
"$node_bin" <<'NODE'
const fs = require('fs');
const map = JSON.parse(fs.readFileSync('.roles/ROLE_SKILL_MAP.json', 'utf8'));
const builders = [
  'arts/technical-3d-artist',
  'computer-science/gameplay-engineer',
  'computer-science/frontend-developer'
];
const reviewers = [
  'arts/technical-3d-artist',
  'computer-science/qa-engineer',
  'computer-science/game-designer'
];
for (const role of builders) {
  if (!map[role].skills.includes('build-threejs-code-characters')) throw new Error(`Missing builder routing: ${role}`);
  for (const command of ['commands/create-code-character-profile.sh', 'commands/validate-code-character-profile.sh', 'commands/record-code-character-gate.sh', 'commands/measure-code-character-evidence.sh']) {
    if (!map[role].commands.includes(command)) throw new Error(`Missing builder command ${command}: ${role}`);
  }
}
for (const role of reviewers) {
  if (!map[role].skills.includes('review-threejs-code-characters')) throw new Error(`Missing reviewer routing: ${role}`);
  for (const command of ['commands/validate-code-character-profile.sh', 'commands/record-code-character-gate.sh']) {
    if (!map[role].commands.includes(command)) throw new Error(`Missing reviewer command ${command}: ${role}`);
  }
}
for (const role of ['computer-science/gameplay-engineer', 'computer-science/frontend-developer']) {
  if (map[role].skills.includes('review-threejs-code-characters')) throw new Error(`Builder-only role unexpectedly owns reviewer skill: ${role}`);
}
for (const role of ['computer-science/qa-engineer', 'computer-science/game-designer']) {
  if (map[role].skills.includes('build-threejs-code-characters')) throw new Error(`Reviewer-only role unexpectedly owns builder skill: ${role}`);
}
NODE

echo '[4/4] running repository skill, safety, role, and generated-map validators'
bash commands/validate-skills.sh >/dev/null
bash commands/validate-role-skill-map.sh >/dev/null
bash commands/validate-role-language-alignment.sh >/dev/null
bash commands/generate-role-skill-map.sh --check >/dev/null
echo 'Code-character skill tests passed.'
