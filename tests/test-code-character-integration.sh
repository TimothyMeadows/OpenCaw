#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo 'Node.js is required for code-character integration tests.' >&2; exit 1; }

fail() { echo "FAIL: $*" >&2; exit 1; }
require_text() {
  local file="$1" text="$2"
  grep -Fq -- "$text" "$file" || fail "$file omits required integration text: $text"
}

echo '[1/4] checking public documentation and catalog ownership'
for file in \
  .styles/.pipelines/code/code-character-profile.schema.json \
  .styles/.pipelines/code/code-character-observation.schema.json \
  .styles/.pipelines/code/code-character-evidence-report.schema.json \
  commands/measure-code-character-evidence.sh \
  commands/record-code-character-calibration.sh \
  skills/build-threejs-code-characters/SKILL.md \
  skills/review-threejs-code-characters/SKILL.md; do
  [[ -f "$file" && ! -L "$file" ]] || fail "missing public character capability: $file"
done
require_text README.md 'measure-code-character-evidence.sh analyze'
require_text README.md 'measure-code-character-evidence.sh capture'
require_text README.md 'Machine results never approve identity, silhouette, form, materials, style, or appeal.'
require_text skills/INDEX.md 'linked profiles, six ordered gates, calibrated machine evidence'
require_text .styles/.pipelines/INDEX.md 'linked character profiles, isolated visual review, and calibrated runtime evidence'
require_text .styles/.pipelines/code/PIPELINE.md 'Fixture reports remain untrusted'

echo '[2/4] checking builder, reviewer, and command role separation'
"$node_bin" <<'NODE'
const fs = require('fs');
const map = JSON.parse(fs.readFileSync('.roles/ROLE_SKILL_MAP.json', 'utf8'));
const builders = ['arts/technical-3d-artist', 'computer-science/frontend-developer', 'computer-science/gameplay-engineer'];
const reviewers = ['arts/technical-3d-artist', 'computer-science/qa-engineer', 'computer-science/game-designer'];
for (const role of builders) {
  if (!map[role].skills.includes('build-threejs-code-characters')) throw new Error(`Builder skill missing from ${role}.`);
  if (!map[role].commands.includes('commands/measure-code-character-evidence.sh')) throw new Error(`Evidence command missing from ${role}.`);
  if (!map[role].commands.includes('commands/record-code-character-calibration.sh')) throw new Error(`Calibration command missing from ${role}.`);
}
for (const role of reviewers) if (!map[role].skills.includes('review-threejs-code-characters')) throw new Error(`Reviewer skill missing from ${role}.`);
for (const role of ['computer-science/frontend-developer', 'computer-science/gameplay-engineer']) {
  if (map[role].skills.includes('review-threejs-code-characters')) throw new Error(`Builder-only role also owns reviewer skill: ${role}.`);
}
for (const role of ['computer-science/qa-engineer', 'computer-science/game-designer']) {
  if (map[role].skills.includes('build-threejs-code-characters')) throw new Error(`Reviewer-only role also owns builder skill: ${role}.`);
}
NODE

echo '[3/4] checking independently owned capability dispositions'
for id in CA-036 CA-037 CA-038 CA-039 CA-040; do require_text skills/EXTERNAL_SOURCES.md "| $id |"; done
require_text skills/EXTERNAL_SOURCES.md '`prepare-rigged-runtime-actors` remains the owner for GLB/FBX packages'
if sed -n '/| CA-036 |/,/| CA-040 |/p' skills/EXTERNAL_SOURCES.md | grep -Eqi 'https?://|github|download|install'; then
  fail 'character capability ownership rows contain a source, publication, download, or installer reference'
fi

echo '[4/4] checking integrated validators and generated surfaces'
require_text commands/validate-opencaw.sh './tests/test-code-character-contract.sh'
require_text commands/validate-opencaw.sh './tests/test-code-character-skills.sh'
require_text commands/validate-opencaw.sh './tests/test-code-character-evidence.sh'
require_text commands/validate-opencaw.sh './tests/test-code-character-integration.sh'
bash commands/validate-readme.sh >/dev/null
bash commands/validate-art-pipelines.sh >/dev/null
bash commands/validate-role-skill-map.sh >/dev/null
bash commands/validate-role-language-alignment.sh >/dev/null
bash commands/generate-role-skill-map.sh --check >/dev/null
echo 'Code-character integration tests passed.'
