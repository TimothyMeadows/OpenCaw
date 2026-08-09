#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing required file: $1"
}

require_text() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "$file is missing required text: $text"
}

scan_ci() {
  local pattern="$1"
  shift
  if command -v rg >/dev/null 2>&1; then
    rg -n -i "$pattern" "$@"
  else
    grep -R -E -n -i -- "$pattern" "$@"
  fi
}

count_skill_name() {
  local skill_name="$1"
  local count=0
  local file
  for file in skills/*/SKILL.md; do
    if tr -d '\r' <"$file" | grep -Fxq "name: ${skill_name}"; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

expect_validation_failure() {
  local name="$1"
  shift
  local log_file="$temp_root/${name}.log"
  if "$@" >"$log_file" 2>&1; then
    fail "validator accepted invalid fixture: $name"
  fi
}

echo "[1/7] checking adaptation boundaries and dispositions"
ledger="skills/EXTERNAL_SOURCES.md"
require_file "$ledger"
require_text "$ledger" '## Review boundary'
require_text "$ledger" 'Do not retain a source repository, commit, author identity, personal material, or audit payload.'
for disposition in create enhance defer reject; do
  grep -Eq "\| CA-[0-9]{3} \| ${disposition} \|" "$ledger" || fail "ledger has no $disposition disposition"
done
require_text "$ledger" '| CA-001 | create | Rigged runtime actor preparation | `prepare-rigged-runtime-actors` and `arts/technical-3d-artist` |'
require_text "$ledger" '| CA-002 | create | Scroll-authored web experiences | `build-scroll-authored-web-experiences` |'
require_text "$ledger" '| CA-008 | enhance | Production release history | `build-game-production-tools` reference |'
require_text "$ledger" '| CA-009 | enhance | Acceptance-to-evidence verification | `verify-and-explain` reference |'
require_text "$ledger" '| CA-010 | defer | Platform-specific native performance profiling |'
require_text "$ledger" '| CA-011 | reject | Repository publication automation |'
record_count="$(grep -Ec '^\| CA-[0-9]{3} \|' "$ledger")"
[[ "$record_count" -ge 18 ]] || fail "ledger must retain all 18 reviewed disposition records"
duplicate_ids="$(awk -F '|' '/^\| CA-[0-9][0-9][0-9] \|/ { id=$2; gsub(/[[:space:]]/, "", id); print id }' "$ledger" | sort | uniq -d)"
[[ -z "$duplicate_ids" ]] || fail "ledger contains duplicate disposition IDs: $duplicate_ids"
if grep -E '^\| CA-[0-9]{3} \|' "$ledger" | grep -Ev '^\| CA-[0-9]{3} \| (create|enhance|defer|reject) \|'; then
  fail "ledger contains an unsupported disposition"
fi
grep -Fq 'No external code, script, executable, binary, model, image, video, audio, demo, generated output, runtime bundle, dependency, endpoint, credential, identity, personal path, or project-specific artifact is imported.' "$ledger" || fail "ledger does not state the no-payload boundary"

echo "[2/7] checking reference routing"
release_ref="skills/build-game-production-tools/references/release-ledger.md"
evidence_ref="skills/verify-and-explain/references/acceptance-evidence-matrix.md"
require_file "$release_ref"
require_file "$evidence_ref"
require_text 'skills/build-game-production-tools/SKILL.md' '[production release ledger](references/release-ledger.md)'
require_text 'skills/verify-and-explain/SKILL.md' '[acceptance and evidence matrix](references/acceptance-evidence-matrix.md)'
require_text "$release_ref" '## Live-version verification'
require_text "$release_ref" 'return focus to the control that opened the view'
require_text "$release_ref" 'A ledger operation must not publish, deploy, mutate an account, or rewrite release history.'
require_text "$evidence_ref" 'automated, runtime, visual, performance, or external-state'
require_text "$evidence_ref" 'An overall pass requires every required row to be verified.'

echo "[3/7] checking selected capability surfaces"
for skill in prepare-rigged-runtime-actors build-scroll-authored-web-experiences; do
  require_file "skills/$skill/SKILL.md"
  require_file "skills/$skill/agents/openai.yaml"
  require_text "skills/$skill/agents/openai.yaml" "\$$skill"
done
role_file='.roles/arts/technical-3d-artist/ROLE.md'
require_file "$role_file"
for alias in 3d-technical-artist rigging-artist technical-animator; do
  require_text "$role_file" "  - $alias"
done
require_file 'commands/validate-rigged-actor-manifest.sh'
bash -n commands/validate-rigged-actor-manifest.sh
[[ -x commands/validate-rigged-actor-manifest.sh ]] || fail "rigged actor manifest validator is not executable"

echo "[4/7] exercising rigged actor manifest validation"
temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT
fixture_root="$temp_root/project"
mkdir -p "$fixture_root/assets" "$fixture_root/evidence" "$temp_root/variants"
printf 'source actor\n' > "$fixture_root/assets/source.fbx"
printf 'runtime actor\n' > "$fixture_root/assets/runtime.glb"
printf 'equipment actor\n' > "$fixture_root/assets/sword.glb"
for evidence in automated-test runtime-capture gameplay-review performance-profile; do
  printf '%s evidence\n' "$evidence" > "$fixture_root/evidence/$evidence.txt"
done

hash_file() { sha256sum "$1" | awk '{print $1}'; }
source_hash="$(hash_file "$fixture_root/assets/source.fbx")"
runtime_hash="$(hash_file "$fixture_root/assets/runtime.glb")"
equipment_hash="$(hash_file "$fixture_root/assets/sword.glb")"
automated_hash="$(hash_file "$fixture_root/evidence/automated-test.txt")"
capture_hash="$(hash_file "$fixture_root/evidence/runtime-capture.txt")"
review_hash="$(hash_file "$fixture_root/evidence/gameplay-review.txt")"
profile_hash="$(hash_file "$fixture_root/evidence/performance-profile.txt")"
valid_character="$temp_root/valid-character.json"

cat > "$valid_character" <<EOF
{
  "schemaVersion": "opencaw-rigged-actor/v1",
  "actor": {"id": "sentinel", "displayName": "Sentinel", "kind": "character", "deliveryStage": "shipped"},
  "files": {
    "source": {"path": "assets/source.fbx", "sha256": "$source_hash"},
    "runtime": {"path": "assets/runtime.glb", "sha256": "$runtime_hash"}
  },
  "coordinateSystem": {"unitsPerMeter": 1, "upAxis": "+Y", "forwardAxis": "+Z", "handedness": "right", "pivot": "feet", "grounding": "sole-plane"},
  "skeleton": {"id": "humanoid-v1", "rootBone": "root", "bindPose": "bind-v1", "bones": ["root", "hand"], "maxInfluencesPerVertex": 4},
  "sockets": [{"id": "main-hand", "parentBone": "hand", "purpose": "primary equipment"}],
  "clips": [
    {"id": "idle", "role": "idle", "skeletonId": "humanoid-v1", "loop": true, "rootMotion": "none", "events": []},
    {"id": "walk", "role": "locomotion", "skeletonId": "humanoid-v1", "loop": true, "rootMotion": "extract", "events": []},
    {"id": "strike", "role": "attack", "skeletonId": "humanoid-v1", "loop": false, "rootMotion": "none", "events": [{"id": "contact", "type": "contact", "timeSeconds": 0.4}]},
    {"id": "hurt", "role": "hit-react", "skeletonId": "humanoid-v1", "loop": false, "rootMotion": "none", "events": []},
    {"id": "death", "role": "death", "skeletonId": "humanoid-v1", "loop": false, "rootMotion": "none", "events": []}
  ],
  "equipment": [{"id": "sword", "socketId": "main-hand", "path": "assets/sword.glb", "sha256": "$equipment_hash"}],
  "colliders": [
    {"id": "navigation", "role": "navigation", "parentRef": "bone:root", "shape": "capsule"},
    {"id": "hurt", "role": "hurt", "parentRef": "bone:root", "shape": "capsule"},
    {"id": "attack", "role": "attack", "parentRef": "socket:main-hand", "shape": "box"},
    {"id": "targeting", "role": "targeting", "parentRef": "bone:root", "shape": "sphere"}
  ],
  "budgets": {"triangles": 50000, "bones": 64, "materials": 8, "textureBytes": 8388608, "runtimeBytes": 1048576},
  "provenance": {"sourceUri": "repository:assets/source.fbx", "author": "fixture", "license": "test-only", "rights": "owned", "capturedAt": "2026-08-08T00:00:00Z"},
  "verification": {
    "status": "verified", "verifier": "fixture-reviewer", "verifiedAt": "2026-08-08T00:00:00Z",
    "evidence": [
      {"id": "automated", "type": "automated-test", "path": "evidence/automated-test.txt", "sha256": "$automated_hash", "notes": "Schema and lifecycle checks passed."},
      {"id": "capture", "type": "runtime-capture", "path": "evidence/runtime-capture.txt", "sha256": "$capture_hash", "notes": "Animation and attachments were observed."},
      {"id": "review", "type": "gameplay-review", "path": "evidence/gameplay-review.txt", "sha256": "$review_hash", "notes": "Representative gameplay readability was reviewed."},
      {"id": "profile", "type": "performance-profile", "path": "evidence/performance-profile.txt", "sha256": "$profile_hash", "notes": "Runtime budgets were measured."}
    ]
  }
}
EOF

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail "Node.js is required for the rigged actor validator test"
node_path() {
  local value
  value="$(realpath "$1")"
  if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$value"
  else
    printf '%s\n' "$value"
  fi
}

valid_for_node="$(node_path "$valid_character")"
variants_for_node="$(node_path "$temp_root/variants")"
"$node_bin" - "$valid_for_node" "$variants_for_node" <<'NODE'
const fs = require('fs');
const path = require('path');
const source = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const output = process.argv[3];
const write = (name, mutate) => {
  const value = structuredClone(source);
  mutate(value);
  fs.writeFileSync(path.join(output, `${name}.json`), JSON.stringify(value, null, 2));
};

write('valid-monster', value => {
  value.actor = {...value.actor, id: 'warden', displayName: 'Warden', kind: 'monster'};
  value.detachableParts = [{...value.equipment[0], id: 'horn'}];
  delete value.equipment;
});
write('wrong-schema', value => { value.schemaVersion = 'opencaw-rigged-actor/v2'; });
write('invalid-kind', value => { value.actor.kind = 'vehicle'; });
write('duplicate-clip', value => { value.clips.push(structuredClone(value.clips[0])); });
write('duplicate-socket', value => { value.sockets.push(structuredClone(value.sockets[0])); });
write('duplicate-equipment', value => { value.equipment.push(structuredClone(value.equipment[0])); });
write('missing-action', value => { value.clips = value.clips.filter(clip => clip.role !== 'death'); });
write('unknown-socket', value => { value.equipment[0].socketId = 'missing-socket'; });
write('unknown-collider-parent', value => { value.colliders[0].parentRef = 'bone:missing-bone'; });
write('path-escape', value => { value.files.runtime.path = '../runtime.glb'; });
write('absolute-path', value => { value.files.runtime.path = 'C:/runtime.glb'; });
write('skeleton-mismatch', value => { value.clips[0].skeletonId = 'other-skeleton'; });
write('missing-file', value => { value.files.runtime.path = 'assets/missing.glb'; });
write('hash-mismatch', value => { value.files.runtime.sha256 = '0'.repeat(64); });
write('incomplete-evidence', value => { value.verification.evidence = value.verification.evidence.slice(0, 1); });
NODE

validator='./commands/validate-rigged-actor-manifest.sh'
bash "$validator" "$valid_character" --root "$fixture_root" --require-verified >/dev/null
bash "$validator" "$temp_root/variants/valid-monster.json" --root "$fixture_root" --require-verified >/dev/null
for invalid in wrong-schema invalid-kind duplicate-clip duplicate-socket duplicate-equipment missing-action unknown-socket unknown-collider-parent path-escape absolute-path skeleton-mismatch missing-file hash-mismatch; do
  expect_validation_failure "$invalid" bash "$validator" "$temp_root/variants/$invalid.json" --root "$fixture_root"
done
expect_validation_failure incomplete-evidence bash "$validator" "$temp_root/variants/incomplete-evidence.json" --root "$fixture_root" --require-verified
expect_validation_failure shipped-without-root bash "$validator" "$valid_character"

echo "[5/7] checking the no-copy and no-payload boundary"
selected_surfaces=(
  skills/prepare-rigged-runtime-actors
  skills/build-scroll-authored-web-experiences
  skills/build-game-production-tools
  skills/verify-and-explain
  .roles/arts/technical-3d-artist
  commands/validate-rigged-actor-manifest.sh
)

if find "${selected_surfaces[@]:0:5}" -type f \
  ! -name '*.md' ! -name '*.yaml' -print -quit | grep -q .; then
  fail "selected skill and role surfaces contain an executable, binary, or unsupported payload"
fi

if scan_ci '(/Users/[^/[:space:]]+|/home/[^/[:space:]]+|[A-Za-z]:\\Users\\[^\\[:space:]]+)' "${selected_surfaces[@]}"; then
  fail "selected import surfaces contain a personal absolute path"
fi
if scan_ci '(gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY)' "${selected_surfaces[@]}"; then
  fail "selected import surfaces contain credential-shaped material"
fi
if scan_ci '(Vesperfall|ElevenLabs|Unsplash|Aura Build|GSAP|Lenis)' "${selected_surfaces[@]}"; then
  fail "selected implementation surfaces contain an upstream project, author, or vendor identity"
fi
if scan_ci 'https?://' "${selected_surfaces[@]}"; then
  fail "selected implementation surfaces contain a remote or vendor endpoint"
fi
if scan_ci '(gh pr create|git push|publish-project-to-github|automatically.{0,80}(publish|deploy|release|post|push))' "${selected_surfaces[@]}"; then
  fail "selected import surfaces contain publication automation"
fi

echo "[6/7] validating changed skill safety and links"
for skill in \
  skills/build-game-production-tools \
  skills/verify-and-explain \
  skills/prepare-rigged-runtime-actors \
  skills/build-scroll-authored-web-experiences; do
  bash commands/validate-skill-safety.sh "$skill"
done

echo "[7/7] checking stable capability ownership"
[[ "$(count_skill_name prepare-rigged-runtime-actors)" -eq 1 ]] || fail "rigged runtime actor skill ownership is missing or duplicated"
[[ "$(count_skill_name build-scroll-authored-web-experiences)" -eq 1 ]] || fail "scroll-authored web skill ownership is missing or duplicated"
[[ "$(find .roles -mindepth 3 -maxdepth 3 -name ROLE.md -path '*/technical-3d-artist/ROLE.md' | wc -l | tr -d ' ')" -eq 1 ]] || fail "technical 3D artist role ownership is missing or duplicated"

echo "Selected capability import tests passed."
