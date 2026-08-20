#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.code-character-evidence-runtime-XXXXXX")"
project="$runtime_dir/project"
mkdir -p "$project/.ai/tasks/evidence-test" "$project/src/models" "$project/node_modules/three/build" "$project/fixtures" "$project/evidence"

cleanup() {
  local resolved
  resolved="$(cd "$(dirname "$runtime_dir")" && pwd -P)/$(basename "$runtime_dir")"
  case "$resolved" in "$repo_root"/tests/.code-character-evidence-runtime-*) rm -rf -- "$resolved" ;; esac
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

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail "Node.js is required for code-character evidence tests"

echo "[1/6] creating a contextual machine-evidence contract"
printf '{"name":"three","version":"0.180.0","main":"build/three.module.js"}\n' > "$project/node_modules/three/package.json"
printf 'export const REVISION = "180";\n' > "$project/node_modules/three/build/three.module.js"
project_command bash commands/generate-style.sh --pipeline CSS3 --allow-pipeline CODE CEL_SHADED_COMIC >/dev/null
project_command bash commands/create-code-model-manifest.sh evidence-character \
  --brief 'A deterministic evidence calibration actor' --intended-use 'machine gate calibration' \
  --prompt-override --output .ai/tasks/evidence-test/code-model.json --source src/models/evidence-character.js \
  --part torso --anchor origin --seed 1337 >/dev/null
printf '%s\n' \
  "import * as THREE from 'three';" \
  'export function createEvidenceCharacter() { return { root: new THREE.Group(), parts: new Map(), anchors: new Map(), dispose() {} }; }' \
  > "$project/src/models/evidence-character.js"
profile="$project/.ai/tasks/evidence-test/code-character.json"
project_command bash commands/create-code-character-profile.sh evidence-character \
  --manifest .ai/tasks/evidence-test/code-model.json --brief 'A deterministic evidence calibration actor' \
  --intended-use 'machine gate calibration' --output .ai/tasks/evidence-test/code-character.json \
  --signature-part torso --view front --pixel-height 32 --grounding-tolerance-ratio 0.01 \
  --contact-tolerance-ratio 0.02 --construction-runs 3 --lifecycle-cycles 3 >/dev/null
project_command bash commands/validate-code-character-profile.sh --strict "$profile" >/dev/null
cp tests/fixtures/code-character-evidence/*.json "$project/fixtures/"

echo "[2/6] calibrating every trusted machine gate with independent pass and focused fail fixtures"
for gate in structure interaction optimization; do
  for outcome in pass fail; do
    output="evidence/$gate-$outcome-report.json"
    project_command bash commands/measure-code-character-evidence.sh analyze "$profile" \
      --measurements "fixtures/$gate-$outcome.json" --output "$output" >/dev/null
  done
done
node_profile="$profile"
node_project="$project"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_profile="$(wslpath -w "$profile")"
  node_project="$(wslpath -w "$project")"
fi
"$node_bin" - "$node_project" <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.argv[2];
for (const gate of ['structure', 'interaction', 'optimization']) {
  const passing = JSON.parse(fs.readFileSync(path.join(root, 'evidence', `${gate}-pass-report.json`), 'utf8'));
  const failing = JSON.parse(fs.readFileSync(path.join(root, 'evidence', `${gate}-fail-report.json`), 'utf8'));
  const id = `${gate}${gate === 'structure' ? '-integrity' : gate === 'interaction' ? '-runtime' : '-budget'}`;
  if (passing.gateResults.find((item) => item.id === id)?.decision !== 'pass') throw new Error(`${id} pass fixture did not pass.`);
  if (failing.gateResults.find((item) => item.id === id)?.decision !== 'fail') throw new Error(`${id} fail fixture did not fail.`);
  if (passing.trustedMachineEvidence !== false || passing.captureMode !== 'fixture') throw new Error('Calibration fixture was incorrectly trusted.');
  if (passing.gateResults.some((item) => /readability|materials|style/.test(item.id))) throw new Error('Analyzer emitted an aesthetic verdict.');
}
NODE

echo "[3/6] checking structural, motion-mode, lifecycle, budget, capture, and comparison regressions"
node_analyzer="$repo_root/commands/lib/code-character-evidence-analyzer.cjs"
node_manifest="$project/.ai/tasks/evidence-test/code-model.json"
node_fixture="$project/fixtures/structure-pass.json"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_analyzer="$(wslpath -w "$node_analyzer")"
  node_manifest="$(wslpath -w "$node_manifest")"
  node_fixture="$(wslpath -w "$node_fixture")"
fi
"$node_bin" - "$node_analyzer" "$node_profile" "$node_manifest" "$node_fixture" <<'NODE'
const fs = require('fs');
const { analyze } = require(process.argv[2]);
const baseProfile = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const manifest = JSON.parse(fs.readFileSync(process.argv[4], 'utf8'));
const baseObservation = JSON.parse(fs.readFileSync(process.argv[5], 'utf8'));
const clone = (value) => JSON.parse(JSON.stringify(value));
const run = (profile, observation) => analyze(profile, manifest, observation, { captureMode: 'fixture', contracts: {} });
const gate = (report, id) => report.gateResults.find((item) => item.id === id);
const item = (report, gateId, checkId) => gate(report, gateId).checks.find((entry) => entry.id === checkId);

let profile = clone(baseProfile);
let observation = clone(baseObservation);
profile.structure.parts.push({ id: 'left-arm', parent: 'torso', role: 'secondary', required: true }, { id: 'right-arm', parent: 'torso', role: 'secondary', required: true });
profile.structure.attachments = [{ part: 'left-arm', host: 'torso', toleranceRatio: 0.02 }];
profile.structure.symmetryGroups = [{ id: 'arms', members: ['left-arm', 'right-arm'], toleranceRatio: 0.03 }];
observation.structure.parts.push({ id: 'left-arm', parent: 'torso' }, { id: 'right-arm', parent: 'torso' });
observation.structure.attachmentGaps = [{ part: 'left-arm', host: 'torso', gapRatio: 0.2 }];
observation.structure.symmetry = [{ id: 'arms', deviationRatio: 0.2 }];
let report = run(profile, observation);
if (item(report, 'structure-integrity', 'attachments').status !== 'fail' || item(report, 'structure-integrity', 'symmetry').status !== 'fail') throw new Error('Attachment or symmetry focused failure was missed.');

profile = clone(baseProfile);
observation = clone(baseObservation);
profile.motion = { mode: 'articulated', skeletonId: null, maxInfluencesPerVertex: 0, requiredRoles: ['idle'], clips: [{ id: 'idle', role: 'idle', loop: true, rootMotion: 'none', contacts: [] }], representativePoses: ['rest'] };
profile.budgets.clips = 1;
observation.motion = { mode: 'articulated', skeletonId: null, maxInfluencesPerVertex: 0, roles: ['idle'], contacts: [], movingPartCount: 1 };
observation.runtime.metrics.clips = 1;
report = run(profile, observation);
if (item(report, 'interaction-runtime', 'declared-motion-mode').status !== 'pass' || item(report, 'interaction-runtime', 'animation-roles').status !== 'pass') throw new Error('Articulated applicability failed.');

profile = clone(baseProfile);
observation = clone(baseObservation);
profile.motion = { mode: 'skinned', skeletonId: 'actor-skeleton', maxInfluencesPerVertex: 4, requiredRoles: ['idle'], clips: [{ id: 'idle', role: 'idle', loop: true, rootMotion: 'none', contacts: [] }], representativePoses: ['rest'] };
profile.budgets.bones = 16; profile.budgets.clips = 1;
observation.motion = { mode: 'skinned', skeletonId: 'actor-skeleton', maxInfluencesPerVertex: 4, roles: ['idle'], contacts: [], movingPartCount: 4 };
observation.runtime.metrics.bones = 8; observation.runtime.metrics.clips = 1;
report = run(profile, observation);
if (item(report, 'interaction-runtime', 'declared-motion-mode').status !== 'pass') throw new Error('Skinned applicability failed.');
observation.motion.maxInfluencesPerVertex = 8;
if (item(run(profile, observation), 'interaction-runtime', 'declared-motion-mode').status !== 'fail') throw new Error('Skinned influence bypass was accepted.');

profile = clone(baseProfile);
observation = clone(baseObservation);
observation.runtime.lifecycle[1].staleCallbacks = 1;
report = run(profile, observation);
if (item(report, 'interaction-runtime', 'interaction-lifecycle').status !== 'fail' || item(report, 'optimization-budget', 'resource-lifecycle').status !== 'fail') throw new Error('Lifecycle growth was not reported to both applicable gates.');
observation = clone(baseObservation);
observation.runtime.metrics.triangles = manifest.budgets.triangles + 1;
if (item(run(profile, observation), 'optimization-budget', 'budget-triangles').status !== 'fail') throw new Error('Contextual triangle budget failure was missed.');
observation = clone(baseObservation);
observation.capture.views = observation.capture.views.filter((entry) => !entry.key.includes('semantic-mask'));
if (item(run(profile, observation), 'structure-integrity', 'capture-coverage').status !== 'fail') throw new Error('Missing semantic mask was accepted.');
observation = clone(baseObservation);
observation.capture.externalRequests = ['https://example.invalid/blocked'];
if (item(run(profile, observation), 'structure-integrity', 'capture-coverage').status !== 'fail') throw new Error('External request attempt was accepted.');
NODE
project_command bash commands/measure-code-character-evidence.sh analyze "$profile" \
  --measurements fixtures/structure-pass.json --output evidence/comparison-report.json \
  --compare evidence/structure-pass-report.json >/dev/null
"$node_bin" - "$node_project/evidence/comparison-report.json" <<'NODE'
const fs = require('fs');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!report.comparison || report.comparison.changedSource !== false || report.comparison.previousOverallDecision !== 'pass') throw new Error('Revision comparison was not recorded deterministically.');
NODE

echo "[4/6] enforcing repository paths, output concurrency, and no-overwrite behavior"
expect_failure "$runtime_dir/overwrite.log" bash commands/measure-code-character-evidence.sh analyze "$profile" \
  --measurements fixtures/structure-pass.json --output evidence/structure-pass-report.json
expect_failure "$runtime_dir/escape-input.log" bash commands/measure-code-character-evidence.sh analyze "$profile" \
  --measurements "$repo_root/tests/fixtures/code-character-evidence/structure-pass.json" --output evidence/escape.json
expect_failure "$runtime_dir/escape-output.log" bash commands/measure-code-character-evidence.sh analyze "$profile" \
  --measurements fixtures/structure-pass.json --output "$runtime_dir/outside.json"
printf 'export async function createCodeCharacterEvidenceAdapter() {}\n' > "$project/evidence/adapter.mjs"
mkdir "$project/evidence/concurrent.lock"
expect_failure "$runtime_dir/concurrent.log" bash commands/measure-code-character-evidence.sh capture "$profile" \
  --adapter evidence/adapter.mjs --output-dir evidence/concurrent
grep -Fq 'locked by another capture' "$runtime_dir/concurrent.log" || fail "concurrent output lock was not enforced"
rmdir "$project/evidence/concurrent.lock"

echo "[5/6] stopping clearly when host browser dependencies are unavailable"
mv "$project/node_modules/three" "$project/node_modules/three.saved"
expect_failure "$runtime_dir/missing-three.log" bash commands/measure-code-character-evidence.sh capture "$profile" \
  --adapter evidence/adapter.mjs --output-dir evidence/missing-three
grep -Fq 'Three.js is unavailable in the host project' "$runtime_dir/missing-three.log" || fail "missing Three.js was not reported clearly"
grep -Fq 'installed nothing' "$runtime_dir/missing-three.log" || fail "missing dependency report omitted the no-install boundary"
mv "$project/node_modules/three.saved" "$project/node_modules/three"
expect_failure "$runtime_dir/missing-playwright.log" bash commands/measure-code-character-evidence.sh capture "$profile" \
  --adapter evidence/adapter.mjs --output-dir evidence/missing-playwright
grep -Fq 'Playwright is unavailable in the host project' "$runtime_dir/missing-playwright.log" || fail "missing Playwright was not reported clearly"
mkdir -p "$project/node_modules/playwright"
printf '{"name":"playwright","version":"1.0.0","main":"index.cjs"}\n' > "$project/node_modules/playwright/package.json"
printf "module.exports={chromium:{launch:async()=>{throw new Error('browser executable missing')}}};\n" > "$project/node_modules/playwright/index.cjs"
expect_failure "$runtime_dir/missing-browser.log" bash commands/measure-code-character-evidence.sh capture "$profile" \
  --adapter evidence/adapter.mjs --output-dir evidence/missing-browser
grep -Fq 'Playwright Chromium browser is unavailable or failed its sandboxed launch' "$runtime_dir/missing-browser.log" || fail "missing browser executable was not reported clearly"
grep -Fq 'did not disable the sandbox' "$runtime_dir/missing-browser.log" || fail "browser failure omitted the sandbox boundary"
[[ ! -e "$project/evidence/missing-three" && ! -e "$project/evidence/missing-playwright" && ! -e "$project/evidence/missing-browser" ]] || fail "failed capture left partial output"

echo "[6/6] validating browser confinement surfaces, schemas, and command integration"
node_cli="$repo_root/commands/lib/code-character-evidence-cli.cjs"
node_three_root="$project/node_modules/three"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_cli="$(wslpath -w "$node_cli")"
  node_three_root="$(wslpath -w "$node_three_root")"
fi
"$node_bin" - "$node_cli" "$node_project" "$node_three_root" <<'NODE'
const { startServer } = require(process.argv[2]);
(async () => {
  const root = process.argv[3];
  const threeRoot = process.argv[4];
  const running = await startServer(root, threeRoot, { relative: 'evidence/adapter.mjs' });
  try {
    const address = running.server.address();
    if (address.address !== '127.0.0.1' || !Number.isInteger(address.port) || address.port < 1) throw new Error('server is not bound to an OS-assigned loopback port');
    const expectations = [
      ['/project/evidence/adapter.mjs', 200],
      ['/three/three.module.js', 200],
      ['/project/STYLE.md', 415],
      ['/project/%E0%A4%A', 400],
      ['/project/%2e%2e/STYLE.md', 404]
    ];
    for (const [target, status] of expectations) {
      const response = await fetch(`${running.origin}${target}`);
      if (response.status !== status) throw new Error(`${target} returned ${response.status}; expected ${status}`);
    }
  } finally {
    await new Promise((resolve) => running.server.close(resolve));
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
NODE
cp tests/fixtures/code-character-evidence/playwright-stub.cjs "$project/node_modules/playwright/index.cjs"
project_command bash commands/measure-code-character-evidence.sh capture "$profile" \
  --adapter evidence/adapter.mjs --output-dir evidence/browser-capture >/dev/null
"$node_bin" - "$node_project/evidence/browser-capture/report.json" <<'NODE'
const fs = require('fs');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (!report.trustedMachineEvidence || report.captureMode !== 'browser' || report.overallDecision !== 'pass') throw new Error('Sandboxed capture did not emit trusted passing machine evidence.');
if (report.browserSecurity?.chromiumSandbox !== true || report.browserSecurity?.serviceWorkers !== 'blocked' || report.browserSecurity?.osAssignedPort !== true) throw new Error('Browser security evidence is incomplete.');
if (!/^http:\/\/127\.0\.0\.1:\d+$/.test(report.browserSecurity.origin)) throw new Error('Evidence server did not use loopback and an OS-assigned port.');
NODE
"$node_bin" - "$node_cli" <<'NODE'
const { pageSource } = require(process.argv[2]);
const source = pageSource('/project/evidence/adapter.mjs');
for (const required of ['createCodeCharacterEvidenceAdapter', 'sampleStructure', 'sampleMotion', 'sampleRuntime', 'constructionHash', 'lifecycleCycle', 'dispose']) {
  if (!source.includes(required)) throw new Error(`Browser adapter contract omits ${required}.`);
}
if (/https?:\/\//.test(source)) throw new Error('Browser page contains an external URL.');
NODE
"$node_bin" -e "for (const file of process.argv.slice(1)) JSON.parse(require('fs').readFileSync(file, 'utf8'))" \
  .styles/.pipelines/code/code-character-profile.schema.json \
  .styles/.pipelines/code/code-character-observation.schema.json \
  .styles/.pipelines/code/code-character-evidence-report.schema.json \
  tests/fixtures/code-character-evidence/*.json
node_analyzer_source="$repo_root/commands/lib/code-character-evidence-analyzer.cjs"
node_cli_source="$repo_root/commands/lib/code-character-evidence-cli.cjs"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  node_analyzer_source="$(wslpath -w "$node_analyzer_source")"
  node_cli_source="$(wslpath -w "$node_cli_source")"
fi
"$node_bin" --check "$node_analyzer_source"
"$node_bin" --check "$node_cli_source"
bash -n commands/measure-code-character-evidence.sh
bash commands/validate-art-pipelines.sh >/dev/null
bash tests/test-code-character-contract.sh >/dev/null
bash tests/test-code-character-skills.sh >/dev/null
echo "Code-character evidence tests passed."
