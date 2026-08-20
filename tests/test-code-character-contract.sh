#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.code-character-runtime-XXXXXX")"
project="$runtime_dir/project"
mkdir -p "$project/.ai/tasks/character-test" "$project/src/models" "$project/evidence" "$project/node_modules/three"

cleanup() {
  local resolved
  resolved="$(cd "$(dirname "$runtime_dir")" && pwd -P)/$(basename "$runtime_dir")"
  case "$resolved" in "$repo_root"/tests/.code-character-runtime-*) rm -rf -- "$resolved" ;; esac
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  local log="$1"; shift
  set +e
  OPENCAW_PROJECT_ROOT="$project" "$@" >"$log" 2>&1
  local status=$?
  set -e
  [[ $status -ne 0 ]] || fail "command unexpectedly succeeded: $*"
}
project_command() { OPENCAW_PROJECT_ROOT="$project" "$@"; }

echo "[1/5] creating a source-independent character profile"
printf '{"name":"three","version":"0.180.0"}\n' > "$project/node_modules/three/package.json"
project_command bash commands/generate-style.sh --pipeline CSS3 --allow-pipeline CODE CEL_SHADED_COMIC >/dev/null
project_command bash commands/create-code-model-manifest.sh test-character \
  --brief 'A deterministic mechanical mascot with readable ears' --intended-use 'runtime actor' \
  --prompt-override --output .ai/tasks/character-test/code-model.json --source src/models/test-character.ts \
  --part torso --part left-ear --part right-ear --anchor origin --anchor head-pivot >/dev/null
manifest="$project/.ai/tasks/character-test/code-model.json"
profile="$project/.ai/tasks/character-test/code-character.json"
project_command bash commands/create-code-character-profile.sh test-character --manifest "$manifest" \
  --brief 'A friendly mechanical mascot whose ears define its identity' --intended-use 'runtime actor' \
  --output .ai/tasks/character-test/code-character.json --identity 'Friendly mechanical mascot with paired expressive ears' \
  --signature-part left-ear --signature-part right-ear --builder primary-builder --max-gate-attempts 5 >/dev/null
[[ -f "$profile" ]] || fail "character profile was not created"
[[ ! -f "$project/src/models/test-character.ts" ]] || fail "profile creation unexpectedly authored source"
project_command bash commands/validate-code-character-profile.sh --strict "$profile" >/dev/null
expect_failure "$runtime_dir/profile-escape.log" bash commands/create-code-character-profile.sh escaped-character \
  --manifest "$manifest" --brief 'escape fixture' --intended-use 'test' --output "$runtime_dir/outside.json"

echo "[2/5] enforcing reviewer independence and changed strategies"
printf '%s\n' \
  "import * as THREE from 'three';" \
  'export function createTestCharacter() {' \
  '  const root = new THREE.Group();' \
  "  const parts = new Map([['torso', root], ['left-ear', root], ['right-ear', root]]);" \
  "  const anchors = new Map([['origin', root], ['head-pivot', root]]);" \
  '  return { root, parts, anchors, dispose() { root.traverse((item) => item.geometry?.dispose?.()); } };' \
  '}' > "$project/src/models/test-character.ts"
for state in passing failing; do printf '%s calibration\n' "$state" > "$project/evidence/calibration-$state.json"; done
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail "Node.js is required for the test fixture"
node_profile="$profile"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_profile="$(wslpath -w "$profile")"; fi
cycle_profile="$project/.ai/tasks/character-test/cyclic-character.json"
cp "$profile" "$cycle_profile"
node_cycle_profile="$cycle_profile"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_cycle_profile="$(wslpath -w "$cycle_profile")"; fi
"$node_bin" - "$node_cycle_profile" <<'NODE'
const fs = require('fs');
const profilePath = process.argv[2];
const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
profile.structure.parts.find((part) => part.id === 'torso').parent = 'left-ear';
fs.writeFileSync(profilePath, `${JSON.stringify(profile, null, 2)}\n`);
NODE
expect_failure "$runtime_dir/part-cycle.log" bash commands/validate-code-character-profile.sh --strict "$cycle_profile"
grep -Fq 'structure.parts contains a parent cycle' "$runtime_dir/part-cycle.log" \
  || fail "cyclic structure did not reach the parent-cycle gate"
gate_tamper_profile="$project/.ai/tasks/character-test/optional-gate-character.json"
cp "$profile" "$gate_tamper_profile"
node_gate_tamper_profile="$gate_tamper_profile"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then node_gate_tamper_profile="$(wslpath -w "$gate_tamper_profile")"; fi
"$node_bin" - "$node_gate_tamper_profile" <<'NODE'
const fs = require('fs');
const profilePath = process.argv[2];
const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
profile.gates[0].required = false;
fs.writeFileSync(profilePath, `${JSON.stringify(profile, null, 2)}\n`);
NODE
expect_failure "$runtime_dir/optional-gate.log" bash commands/validate-code-character-profile.sh --strict "$gate_tamper_profile"
grep -Fq 'must be required reviewer gate blockout-readability for blockout' "$runtime_dir/optional-gate.log" \
  || fail "optional character gate did not reach the immutable gate-contract check"
pass_sha="$(sha256sum "$project/evidence/calibration-passing.json" | awk '{print $1}')"
fail_sha="$(sha256sum "$project/evidence/calibration-failing.json" | awk '{print $1}')"
"$node_bin" - "$node_profile" "$pass_sha" "$fail_sha" <<'NODE'
const fs = require('fs');
const [profilePath, passingSha, failingSha] = process.argv.slice(2);
const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
for (const gate of profile.gates.filter((item) => item.type === 'machine')) {
  gate.calibration.passing = [{ path: 'evidence/calibration-passing.json', sha256: passingSha }];
  gate.calibration.failing = [{ path: 'evidence/calibration-failing.json', sha256: failingSha }];
}
fs.writeFileSync(profilePath, `${JSON.stringify(profile, null, 2)}\n`);
NODE
printf 'first reviewer packet\n' > "$project/evidence/blockout-packet-1.md"
printf 'first blockout evidence\n' > "$project/evidence/blockout-1.txt"
expect_failure "$runtime_dir/early-parent-pass.log" bash commands/record-code-model-review.sh "$manifest" \
  --pass blockout --decision pass --summary 'premature parent pass' --character-profile "$profile" \
  --evidence front=evidence/blockout-1.txt --evidence orbit-left=evidence/blockout-1.txt --evidence orbit-right=evidence/blockout-1.txt
expect_failure "$runtime_dir/self-review.log" bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision revise-code --summary 'self review' --failure-class silhouette-readability \
  --strategy 'initial silhouette layout' --reviewer-id primary-builder --reviewer-type agent \
  --reviewer-packet evidence/blockout-packet-1.md --observed-answer 'Ambiguous silhouette' \
  --evidence reviewer-packet=evidence/blockout-packet-1.md --evidence render=evidence/blockout-1.txt
expect_failure "$runtime_dir/noncanonical-reviewer.log" bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision revise-code --summary 'case-variant self review' --failure-class silhouette-readability \
  --strategy 'attempt a case-variant reviewer identity' --reviewer-id Primary-Builder --reviewer-type agent \
  --reviewer-packet evidence/blockout-packet-1.md --observed-answer 'Ambiguous silhouette' \
  --evidence reviewer-packet=evidence/blockout-packet-1.md --evidence render=evidence/blockout-1.txt
project_command bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision revise-code --summary 'Ears merge into the torso' --failure-class silhouette-readability \
  --strategy 'separate ear masses from the torso' --reviewer-id independent-reviewer --reviewer-type agent \
  --reviewer-packet evidence/blockout-packet-1.md --observed-answer 'Identity is present but the ears merge at target scale' \
  --evidence reviewer-packet=evidence/blockout-packet-1.md --evidence render=evidence/blockout-1.txt >/dev/null
printf 'repeat reviewer packet\n' > "$project/evidence/blockout-packet-repeat.md"
printf 'repeat blockout evidence\n' > "$project/evidence/blockout-repeat.txt"
expect_failure "$runtime_dir/repeated-strategy.log" bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision revise-code --summary 'unchanged attempt' --failure-class silhouette-readability \
  --strategy 'separate ear masses from the torso' --reviewer-id independent-reviewer --reviewer-type agent \
  --reviewer-packet evidence/blockout-packet-repeat.md --observed-answer 'Still ambiguous' \
  --evidence reviewer-packet=evidence/blockout-packet-repeat.md --evidence render=evidence/blockout-repeat.txt
expect_failure "$runtime_dir/repeated-class.log" bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision revise-code --summary 'same failure class' --failure-class silhouette-readability \
  --strategy 'widen the ear stance' --reviewer-id independent-reviewer --reviewer-type agent \
  --reviewer-packet evidence/blockout-packet-repeat.md --observed-answer 'Still ambiguous' \
  --evidence reviewer-packet=evidence/blockout-packet-repeat.md --evidence render=evidence/blockout-repeat.txt
ln -s "$project/evidence/calibration-passing.json" "$project/evidence/linked.txt"
expect_failure "$runtime_dir/symlink.log" bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision pass --summary 'linked evidence' --strategy 'inspect a linked artifact' \
  --reviewer-id independent-reviewer --reviewer-type agent --reviewer-packet evidence/blockout-packet-repeat.md \
  --observed-answer 'Linked artifact must be rejected' --evidence reviewer-packet=evidence/blockout-packet-repeat.md \
  --evidence render=evidence/linked.txt
if ! grep -Eq 'must not be a symbolic link|does not exist' "$runtime_dir/symlink.log"; then
  sed 's/^/symlink rejection: /' "$runtime_dir/symlink.log" >&2
  fail "symbolic-link rejection was not reported"
fi
printf 'input request packet\n' > "$project/evidence/blockout-input-packet.md"
printf 'input request evidence\n' > "$project/evidence/blockout-input.txt"
project_command bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision request-input --summary 'Presentation scale is unresolved' --failure-class missing-context \
  --strategy 'ask for the target presentation scale' --reviewer-id independent-reviewer --reviewer-type agent \
  --reviewer-packet evidence/blockout-input-packet.md --observed-answer 'A scale decision is required' \
  --evidence reviewer-packet=evidence/blockout-input-packet.md --evidence render=evidence/blockout-input.txt >/dev/null
printf 'resumed review packet\n' > "$project/evidence/blockout-resume-packet.md"
printf 'resumed review evidence\n' > "$project/evidence/blockout-resume.txt"
project_command bash commands/record-code-character-gate.sh "$profile" \
  --gate blockout-readability --decision revise-spec --summary 'Presentation scale is now frozen' --failure-class spec-updated \
  --strategy 'incorporate the supplied presentation scale' --reviewer-id independent-reviewer --reviewer-type agent \
  --reviewer-packet evidence/blockout-resume-packet.md --observed-answer 'The supplied scale resolves the review question' \
  --evidence reviewer-packet=evidence/blockout-resume-packet.md --evidence render=evidence/blockout-resume.txt >/dev/null

echo "[3/5] pairing all six character gates with the generic CODE passes"
for view in front orbit-left orbit-right; do printf '%s parent evidence\n' "$view" > "$project/evidence/parent-$view.txt"; done
reviewer_gates='blockout-readability form-readability materials-style'
declare -A gate_for_pass=(
  [blockout]=blockout-readability [structure]=structure-integrity [form]=form-readability
  [materials]=materials-style [interaction]=interaction-runtime [optimization]=optimization-budget
)
for pass in blockout structure form materials interaction optimization; do
  gate="${gate_for_pass[$pass]}"
  printf '%s gate evidence\n' "$gate" > "$project/evidence/$gate.txt"
  record_args=("$profile" --gate "$gate" --decision pass --summary "$gate accepted" --strategy "validated $gate with frozen contextual evidence" --evidence "metric=evidence/$gate.txt")
  if [[ " $reviewer_gates " == *" $gate "* ]]; then
    printf '%s independent packet\n' "$gate" > "$project/evidence/$gate-packet.md"
    record_args+=(--reviewer-id independent-reviewer --reviewer-type agent --reviewer-packet "evidence/$gate-packet.md"
      --observed-answer "$gate is readable against the frozen question" --evidence "reviewer-packet=evidence/$gate-packet.md")
  fi
  project_command bash commands/record-code-character-gate.sh "${record_args[@]}" >/dev/null
  project_command bash commands/record-code-model-review.sh "$manifest" --pass "$pass" --decision pass --summary "$pass accepted" \
    --character-profile "$profile" --evidence front=evidence/parent-front.txt \
    --evidence orbit-left=evidence/parent-orbit-left.txt --evidence orbit-right=evidence/parent-orbit-right.txt >/dev/null
done
project_command bash commands/validate-code-character-profile.sh --complete "$profile" >/dev/null

echo "[4/5] rejecting stale, escaped, symbolic-link, and locked evidence"
cp "$project/evidence/form-readability.txt" "$runtime_dir/form-readability.backup"
printf 'mutated evidence\n' > "$project/evidence/form-readability.txt"
expect_failure "$runtime_dir/stale-evidence.log" bash commands/validate-code-character-profile.sh --complete "$profile"
cp "$runtime_dir/form-readability.backup" "$project/evidence/form-readability.txt"
cp "$project/src/models/test-character.ts" "$runtime_dir/test-character.backup"
printf '\n// source mutation\n' >> "$project/src/models/test-character.ts"
expect_failure "$runtime_dir/stale-source.log" bash commands/validate-code-character-profile.sh --complete "$profile"
cp "$runtime_dir/test-character.backup" "$project/src/models/test-character.ts"
mkdir "$profile.lock"
expect_failure "$runtime_dir/lock.log" bash commands/record-code-character-gate.sh "$profile" \
  --gate optimization-budget --decision pass --summary 'locked result' --strategy 'locked result' --evidence metric=evidence/optimization-budget.txt
rmdir "$profile.lock"

echo "[5/5] validating schemas, command surfaces, and generic compatibility"
project_command bash commands/validate-code-character-profile.sh --complete "$profile" >/dev/null
node_character_schema="$repo_root/.styles/.pipelines/code/code-character-profile.schema.json"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_character_schema="$(wslpath -w "$node_character_schema")"
fi
"$node_bin" - "$node_character_schema" <<'NODE'
const fs = require('fs');
const schema = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const expected = [
  ['blockout-readability', 'blockout', 'reviewer'],
  ['structure-integrity', 'structure', 'machine'],
  ['form-readability', 'form', 'reviewer'],
  ['materials-style', 'materials', 'reviewer'],
  ['interaction-runtime', 'interaction', 'machine'],
  ['optimization-budget', 'optimization', 'machine']
];
if (schema.properties.gates.items !== false || schema.properties.gates.prefixItems.length !== expected.length) {
  throw new Error('Character schema does not freeze exactly six ordered gates.');
}
expected.forEach(([id, pass, type], index) => {
  const properties = schema.properties.gates.prefixItems[index].allOf[1].properties;
  if (properties.id.const !== id || properties.pass.const !== pass || properties.type.const !== type || properties.required.const !== true) {
    throw new Error(`Character schema gate ${index} is not immutable.`);
  }
});
NODE
bash commands/validate-art-pipelines.sh >/dev/null
bash commands/validate-commands.sh >/dev/null
bash tests/test-art-pipelines.sh >/dev/null
echo "Code-character contract tests passed."
