#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.art-pipeline-runtime-XXXXXX")"
project="$runtime_dir/project"
mkdir -p "$project/.opencaw/.cache/tasks/pipeline-test" "$project/src/models" "$project/evidence"

cleanup() {
  local resolved
  resolved="$(cd "$(dirname "$runtime_dir")" && pwd -P)/$(basename "$runtime_dir")"
  case "$resolved" in "$repo_root"/tests/.art-pipeline-runtime-*) rm -rf -- "$resolved" ;; esac
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
contains_exact_line() {
  awk -v expected="$1" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$2"
}
project_command() { OPENCAW_PROJECT_ROOT="$project" "$@"; }

echo "[1/6] validating the pipeline catalog and PROOF_TO_MODEL constraints"
bash commands/validate-art-pipelines.sh
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail "Node.js is required for finishing-schema regression checks"
"$node_bin" <<'FINISH_SCHEMA_CASES'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const schemaPath = '.styles/.pipelines/proof-to-model/finishing-settings.schema.json';
const source = fs.readFileSync('commands/validate-art-pipelines.sh', 'utf8').replace(/\r\n/g, '\n');
const program = source.match(/"\$node_bin" <<'NODE'\n([\s\S]*?)\nNODE/);
assert(program, 'The actual art schema validator must be exercised.');
const original = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
function check(schema) {
  const fixtureFs = Object.create(fs);
  fixtureFs.readFileSync = (file, ...args) => file === schemaPath ? JSON.stringify(schema) : fs.readFileSync(file, ...args);
  vm.runInNewContext(program[1], { require: name => name === 'fs' ? fixtureFs : require(name) }, { timeout: 2000 });
}
check(original);
const reordered = structuredClone(original);
reordered.oneOf.reverse();
check(reordered);
// Mutate only in-memory schemas: never weaken or overwrite the shared schema.
const legacy = schema => schema.$defs.legacyQuadriFlow;
const rigid = schema => schema.$defs.rigidParts;
const parts = schema => rigid(schema).properties.rigidParts;
const negatives = [
  ['missing route selection', s => delete s.oneOf],
  ['unversioned fallback route', s => s.oneOf.push({ type: 'object' })],
  ['duplicate v1 route', s => s.oneOf[1].$ref = s.oneOf[0].$ref],
  ['route reference siblings', s => s.oneOf[0].default = {}],
  ['open v1 object', s => legacy(s).additionalProperties = true],
  ['open v2 object', s => rigid(s).additionalProperties = true],
  ['v1 missing collision requirement', s => legacy(s).required = legacy(s).required.filter(k => k !== 'collision')],
  ['v1 missing version', s => delete legacy(s).properties.schemaVersion.const],
  ['v2 wrong version', s => rigid(s).properties.schemaVersion.const = 1],
  ['v2 noninteger version', s => rigid(s).properties.schemaVersion.type = 'number'],
  ['v1 mixed rigid route', s => legacy(s).properties.rigidParts = parts(s)],
  ['v2 implicit method', s => rigid(s).required = rigid(s).required.filter(k => k !== 'method')],
  ['v2 wrong method', s => rigid(s).properties.method.const = 'quadri-flow'],
  ['v2 mixed solver route', s => rigid(s).properties.quadriFlow = legacy(s).properties.quadriFlow],
  ['v2 implicit voxel fallback', s => rigid(s).properties.topologyPreparation.properties.method.const = 'voxel-remesh'],
  ['v2 open preparation', s => rigid(s).properties.topologyPreparation.additionalProperties = true],
  ['v1 absent collision alternative', s => legacy(s).properties.collision.oneOf.pop()],
  ['v2 implicit collision fallback', s => rigid(s).properties.collision.oneOf.push({ type: 'object' })],
  ['v2 open collision alternative', s => rigid(s).properties.collision.oneOf[0].additionalProperties = true],
  ['v2 unbounded collision padding', s => delete rigid(s).properties.collision.oneOf[1].properties.padding.maximum],
  ['v2 missing handoff requirement', s => parts(s).required = parts(s).required.filter(k => k !== 'handoff')],
  ['v2 missing review requirement', s => parts(s).required = parts(s).required.filter(k => k !== 'reviewEvidence')],
  ['v2 open handoff', s => parts(s).additionalProperties = true],
  ['v2 empty handoff path', s => parts(s).properties.handoff.minLength = 0],
  ['v2 unbounded review path', s => delete parts(s).properties.reviewEvidence.maxLength],
  ['v2 loose handoff hash', s => parts(s).properties.handoffSha256.pattern = '.*'],
  ['v2 shortened review hash', s => parts(s).properties.reviewEvidenceSha256.minLength = 1],
  ['v2 unbounded triangle output', s => delete parts(s).properties.maxLod0Triangles.maximum],
  ['v2 fractional triangle output', s => parts(s).properties.maxLod0Triangles.type = 'number'],
  ['v2 unbounded GLB bytes', s => delete parts(s).properties.maxGlbBytes.maximum],
  ['v2 required UV override', s => parts(s).required.push('uvAtlas')],
  ['v2 missing UV override definition', s => delete parts(s).properties.uvAtlas],
  ['v2 open UV override', s => parts(s).properties.uvAtlas.additionalProperties = true],
  ['v2 implicit UV method', s => parts(s).properties.uvAtlas.required.pop()],
  ['v2 unsupported UV method', s => parts(s).properties.uvAtlas.properties.method.const = 'automatic'],
  ['v2 fractional pixel margin', s => parts(s).properties.uvAtlas.properties.islandMarginPixels.type = 'number'],
  ['v2 zero pixel margin', s => parts(s).properties.uvAtlas.properties.islandMarginPixels.minimum = 0],
  ['v2 unbounded pixel margin', s => delete parts(s).properties.uvAtlas.properties.islandMarginPixels.maximum],
  ['v1 mixed UV override', s => legacy(s).properties.uvAtlas = parts(s).properties.uvAtlas],
  ['v2 required UV repair', s => parts(s).properties.uvAtlas.required.push('triangleRepair')],
  ['v2 missing UV repair definition', s => delete parts(s).properties.uvAtlas.properties.triangleRepair],
  ['v2 open UV repair', s => parts(s).properties.uvAtlas.properties.triangleRepair.additionalProperties = true],
  ['v2 implicit UV repair budget', s => parts(s).properties.uvAtlas.properties.triangleRepair.required.pop()],
  ['v2 automatic UV repair method', s => parts(s).properties.uvAtlas.properties.triangleRepair.properties.method.const = 'automatic'],
  ['v2 default UV repair', s => parts(s).properties.uvAtlas.properties.triangleRepair.default = {}],
  ['v2 default UV repair method', s => parts(s).properties.uvAtlas.properties.triangleRepair.properties.method.default = 'density-preserving-isolated-cells-v1'],
  ['v2 fractional UV repair cell type', s => parts(s).properties.uvAtlas.properties.triangleRepair.properties.minCellPixels.type = 'number'],
  ['v2 unsupported UV repair cell size', s => parts(s).properties.uvAtlas.properties.triangleRepair.properties.minCellPixels.const = 8],
  ['v2 zero UV repair budget', s => parts(s).properties.uvAtlas.properties.triangleRepair.properties.maxTriangles.minimum = 0],
  ['v2 unbounded UV repair budget', s => delete parts(s).properties.uvAtlas.properties.triangleRepair.properties.maxTriangles.maximum],
  ['v2 fractional UV repair budget', s => parts(s).properties.uvAtlas.properties.triangleRepair.properties.maxTriangles.type = 'number'],
  ['v2 caller UV repair tolerance', s => parts(s).properties.uvAtlas.properties.triangleRepair.properties.epsilon = {type:'number'}],
  ['v2 required normal import', s => parts(s).required.push('importNormals')],
  ['v2 missing normal definition', s => delete parts(s).properties.importNormals],
  ['v2 open normal profile', s => parts(s).properties.importNormals.additionalProperties = true],
  ['v2 implicit normal method', s => parts(s).properties.importNormals.required = []],
  ['v2 automatic normal method', s => parts(s).properties.importNormals.properties.method.const = 'automatic'],
  ['v2 default normal profile', s => parts(s).properties.importNormals.default = {method:'stored-corner-fan-v1'}],
  ['v2 default normal method', s => parts(s).properties.importNormals.properties.method.default = 'stored-corner-fan-v1'],
  ['v2 caller normal tolerance', s => parts(s).properties.importNormals.properties.maxError = {type:'number'}],
  ['v1 mixed normal profile', s => legacy(s).properties.importNormals = parts(s).properties.importNormals],
  ['v2 required LOD profile', s => parts(s).required.push('lods')],
  ['v2 missing LOD definition', s => delete parts(s).properties.lods],
  ['v2 open LOD profile', s => parts(s).properties.lods.additionalProperties = true],
  ['v2 implicit LOD method', s => parts(s).properties.lods.required.pop()],
  ['v2 automatic LOD method', s => parts(s).properties.lods.properties.method.const = 'automatic'],
  ['v2 default LOD profile', s => parts(s).properties.lods.default = {}],
  ['v2 default LOD method', s => parts(s).properties.lods.properties.method.default = 'original-component-finite-collapse-v1'],
  ['v2 nonarray LOD errors', s => parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.type = 'object'],
  ['v2 empty LOD errors', s => parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.minItems = 0],
  ['v2 excessive LOD errors', s => parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.maxItems = 9],
  ['v2 missing positive LOD bound', s => delete parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.items.exclusiveMinimum],
  ['v2 loose LOD upper bound', s => parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.items.maximum = 2],
  ['v2 ambiguous LOD minimum', s => parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.items.minimum = 0],
  ['v2 default LOD error array', s => parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.default = [.003]],
  ['v2 default LOD error item', s => parts(s).properties.lods.properties.maxVertexSurfaceErrorMetres.items.default = .003],
  ['v2 missing contact policy definition', s => delete parts(s).properties.lods.properties.contactPolicy],
  ['v2 implicit required contact policy', s => parts(s).properties.lods.required.push('contactPolicy')],
  ['v2 nonstring contact policy', s => parts(s).properties.lods.properties.contactPolicy.type = 'number'],
  ['v2 unsupported contact policy', s => parts(s).properties.lods.properties.contactPolicy.const = 'automatic'],
  ['v2 default contact policy', s => parts(s).properties.lods.properties.contactPolicy.default = 'protected-contact-rings-v1'],
  ['v2 missing contact authority dependency', s => delete parts(s).allOf],
  ['v2 empty contact authority dependency', s => parts(s).allOf = []],
  ['v2 duplicate contact authority dependency', s => parts(s).allOf.push(structuredClone(parts(s).allOf[0]))],
  ['v2 unconditional contact dependency', s => delete parts(s).allOf[0].if],
  ['v2 omitted conditional LOD presence', s => parts(s).allOf[0].if.required = []],
  ['v2 omitted contact selector presence', s => parts(s).allOf[0].if.properties.lods.required = []],
  ['v2 missing contact topology requirement', s => parts(s).allOf[0].then.required = []],
  ['v2 bypassable contact dependency', s => parts(s).allOf[0].else = {}],
  ['v2 caller LOD ratios', s => parts(s).properties.lods.properties.requestedRatios = {type:'array'}],
  ['v1 mixed LOD profile', s => legacy(s).properties.lods = parts(s).properties.lods],
  ['v2 missing resource policy', s => rigid(s).required = rigid(s).required.filter(k => k !== 'resources')],
  ['v2 open resource policy', s => rigid(s).properties.resources.additionalProperties = true],
  ['v2 unbounded memory', s => delete rigid(s).properties.resources.properties.maxPrivateBytes.maximum],
  ['v1 open solver', s => legacy(s).properties.quadriFlow.additionalProperties = true],
  ['v1 unpinned solver scale', s => legacy(s).properties.quadriFlow.properties.coordinateScale.enum.push(3)],
  ['v1 open simplification', s => legacy(s).properties.quadriFlow.properties.simplification.additionalProperties = true],
  ['v1 missing protected regions', s => legacy(s).properties.quadriFlow.properties.simplification.required.pop()]
];
for (const [label, mutate] of negatives) {
  const candidate = structuredClone(original);
  mutate(candidate);
  let rejected = false;
  try { check(candidate); } catch { rejected = true; }
  assert(rejected, `The actual validator accepted ${label}.`);
}
console.log(`Finishing schema checks passed: 2 valid arrangements and ${negatives.length} malformed schemas rejected.`);
FINISH_SCHEMA_CASES
[[ ! -e .styles/.gpu ]] || fail "legacy pipeline tree exists"
[[ ! -e .media ]] || fail "legacy media tree exists"
[[ ! -e .styles/.pipelines/css3 ]] || fail "retired CSS3 directory exists"
[[ ! -e commands/print-css-art-token-template.sh ]] || fail "retired token command exists"
for retired in CSS CSS3 vector css-vector; do
  expect_failure "$runtime_dir/retired-$retired.log" bash commands/generate-style.sh --pipeline "$retired" CEL_SHADED_COMIC
  grep -Fq 'CSS3 is retired' "$runtime_dir/retired-$retired.log" || fail "missing migration guidance"
done
source commands/lib/art-pipeline-common.sh
[[ "$(art_pipeline_normalize 'proof to model')" == PROOF_TO_MODEL ]] || fail "spaced alias failed"
grep -Fq 'Blender 4.5 LTS' .styles/.pipelines/blender/PIPELINE.md || fail "BLENDER contract lacks its version boundary"
grep -Eiq 'immutable source|preserve every immutable source' .styles/.pipelines/blender/PIPELINE.md || fail "BLENDER contract lacks immutable-source protection"
grep -Eiq 'never installed|never install' .styles/.pipelines/blender/PIPELINE.md || fail "BLENDER contract lacks its no-install boundary"

echo "[2/6] generating default, explicit, aliased, allowed, and inline contracts"
project_command bash commands/generate-style.sh CEL_SHADED_COMIC
project_command bash commands/validate-style-contract.sh "$project/STYLE.md"
contains_exact_line '- PROOF_TO_MODEL' "$project/STYLE.md" || fail "default style contract did not select PROOF_TO_MODEL"
# A retired selection must never damage a valid host contract.
valid_style_hash="$(sha256sum "$project/STYLE.md")"
for retired in CSS CSS3 vector css-vector; do
  expect_failure "$runtime_dir/retired-valid-$retired.log" bash commands/generate-style.sh --pipeline "$retired" CEL_SHADED_COMIC
  [[ "$(sha256sum "$project/STYLE.md")" == "$valid_style_hash" ]] || fail "retired selection overwrote STYLE.md"
  expect_failure "$runtime_dir/override-retired-$retired.log" bash commands/resolve-art-pipeline.sh --override "$retired"
  grep -Fq 'CSS3 is retired' "$runtime_dir/override-retired-$retired.log" || fail "retired override omitted migration guidance"
done
sed 's/PROOF_TO_MODEL/CSS3/g' "$project/STYLE.md" > "$runtime_dir/legacy-style.md"
expect_failure "$runtime_dir/legacy-style.log" bash commands/validate-style-contract.sh "$runtime_dir/legacy-style.md"
grep -Fq 'CSS3 is retired' "$runtime_dir/legacy-style.log" || fail "legacy style omitted migration guidance"
project_command bash commands/generate-style.sh --pipeline 'proof to model' CEL_SHADED_COMIC >/dev/null
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null


for pair in 'imagegen CLOUD' 'comfyui LOCAL' 'proof-to-model PROOF_TO_MODEL' '2d-to-3d PROOF_TO_MODEL' 'threejs CODE' 'blender BLENDER' 'blend BLENDER' 'bpy BLENDER'; do
  read -r alias expected <<< "$pair"
  project_command bash commands/generate-style.sh --pipeline "$alias" CEL_SHADED_COMIC >/dev/null
  project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
  awk -v expected="$expected" '
    /^Primary OpenCaw art pipeline:/ { list=1; next }
    /^Allowed OpenCaw art pipelines:/ { list=0 }
    list && $0 == "- " expected { found=1 }
    END { exit !found }
  ' "$project/STYLE.md" || fail "$alias did not normalize to $expected"
done

project_command bash commands/generate-style.sh --pipeline PROOF_TO_MODEL --allow-pipeline imagegen --allow-pipeline comfyui --allow-pipeline threejs --allow-pipeline blender CEL_SHADED_COMIC >/dev/null
for pipeline in PROOF_TO_MODEL CLOUD LOCAL CODE BLENDER; do contains_exact_line "- $pipeline" "$project/STYLE.md" || fail "allowed list omits $pipeline"; done
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
project_command bash commands/generate-style.sh --inline --pipeline CODE --allow-pipeline PROOF_TO_MODEL CEL_SHADED_COMIC >/dev/null
grep -Fq '<!-- BEGIN ART PIPELINE: CODE -->' "$project/STYLE.md" || fail "inline contract omitted CODE"
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
project_command bash commands/generate-style.sh --inline --pipeline blender --allow-pipeline PROOF_TO_MODEL CEL_SHADED_COMIC >/dev/null
grep -Fq '<!-- BEGIN ART PIPELINE: BLENDER -->' "$project/STYLE.md" || fail "inline contract omitted BLENDER"
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$project/STYLE.md" > "$project/STYLE-crlf.md"
project_command bash commands/validate-style-contract.sh "$project/STYLE-crlf.md" >/dev/null
project_command bash commands/resolve-art-pipeline.sh --style "$project/STYLE-crlf.md" --json >/dev/null
expect_failure "$runtime_dir/invalid.log" bash commands/generate-style.sh --pipeline unknown CEL_SHADED_COMIC
expect_failure "$runtime_dir/duplicate.log" bash commands/generate-style.sh --pipeline PROOF_TO_MODEL --allow-pipeline proof-to-model CEL_SHADED_COMIC

project_command bash commands/generate-style.sh --pipeline PROOF_TO_MODEL --allow-pipeline CODE CEL_SHADED_COMIC >/dev/null
awk '!/\.styles\/\.pipelines\/code\/PIPELINE\.md/' "$project/STYLE.md" > "$runtime_dir/missing-directive.md"
expect_failure "$runtime_dir/missing-directive.log" bash commands/validate-style-contract.sh "$runtime_dir/missing-directive.md"

echo "[3/6] resolving task-only prompt overrides without changing STYLE.md"
style_before="$(sha256sum "$project/STYLE.md" | awk '{print $1}')"
for pair in 'imagegen CLOUD' 'comfyui LOCAL' 'proof-to-model PROOF_TO_MODEL' '2d-to-3d PROOF_TO_MODEL' 'threejs CODE' 'blender BLENDER' 'blend BLENDER' 'bpy BLENDER'; do
  read -r alias expected <<< "$pair"
  output="$(project_command bash commands/resolve-art-pipeline.sh --style "$project/STYLE.md" --override "$alias" --json)"
  grep -Fq "\"pipeline\": \"$expected\"" <<< "$output" || fail "override $alias did not resolve to $expected"
  grep -Fq '"selectionSource": "prompt"' <<< "$output" || fail "override did not record prompt source"
done
project_command bash commands/resolve-art-pipeline.sh --style "$project/STYLE.md" --override imagegen --evidence "$project/.opencaw/.cache/tasks/pipeline-test/selection.json" >/dev/null
grep -Fq '"selectionSource": "prompt"' "$project/.opencaw/.cache/tasks/pipeline-test/selection.json" || fail "selection evidence omitted prompt source"
style_after="$(sha256sum "$project/STYLE.md" | awk '{print $1}')"
[[ "$style_before" == "$style_after" ]] || fail "prompt override rewrote STYLE.md"
expect_failure "$runtime_dir/evidence-escape.log" bash commands/resolve-art-pipeline.sh --style "$project/STYLE.md" --override CODE --evidence "$runtime_dir/outside.json"

echo "[4/6] creating and validating a CODE manifest"
printf 'authorized reference bytes\n' > "$project/reference.png"
project_command bash commands/create-code-model-manifest.sh test-model \
  --brief 'A deterministic cel-shaded mechanical mascot with articulated ears' \
  --prompt-override --output .opencaw/.cache/tasks/pipeline-test/code-model.json --source src/models/test-model.ts \
  --part torso --part left-ear --part right-ear --anchor origin --anchor head-pivot \
  --reference reference.png --reference-rights 'user-owned' --reference-consent confirmed >/dev/null
manifest="$project/.opencaw/.cache/tasks/pipeline-test/code-model.json"
manifest_sha_before="$(sha256sum "$manifest" | awk '{print $1}')"
project_command bash commands/create-code-model-manifest.sh test-model \
  --brief 'A deterministic cel-shaded mechanical mascot with articulated ears' \
  --prompt-override --output .opencaw/.cache/tasks/pipeline-test/code-model.json --source src/models/test-model.ts \
  --part torso --part left-ear --part right-ear --anchor origin --anchor head-pivot \
  --reference reference.png --reference-rights 'user-owned' --reference-consent confirmed >/dev/null
manifest_sha_after="$(sha256sum "$manifest" | awk '{print $1}')"
[[ "$manifest_sha_before" == "$manifest_sha_after" ]] || fail "identical manifest inputs produced different output"
project_command bash commands/validate-code-model-manifest.sh --strict "$manifest"
next="$(project_command bash commands/next-code-model-pass.sh "$manifest")"
grep -Fq 'NEXT_PASS=blockout' <<< "$next" || fail "blockout was not first"
grep -Fq '"front"' "$manifest" || fail "front view requirement missing"
grep -Fq '"orbit-left"' "$manifest" || fail "orbit-left view requirement missing"
grep -Fq '"orbit-right"' "$manifest" || fail "orbit-right view requirement missing"
expect_failure "$runtime_dir/code-output-escape.log" bash commands/create-code-model-manifest.sh escaped --brief 'escape' --prompt-override --output "$runtime_dir/escaped.json"

echo "[5/6] enforcing pass order, evidence hashes, decisions, and retry limits"
for view in front orbit-left orbit-right; do printf '%s deterministic render\n' "$view" > "$project/evidence/$view.png"; done
expect_failure "$runtime_dir/order.log" bash commands/record-code-model-review.sh "$manifest" --pass structure --decision revise-code --summary 'out of order'
expect_failure "$runtime_dir/views.log" bash commands/record-code-model-review.sh "$manifest" --pass blockout --decision pass --summary 'missing views' --evidence front=evidence/front.png
for attempt in 1 2 3; do
  project_command bash commands/record-code-model-review.sh "$manifest" --pass blockout --decision revise-code --summary "revision $attempt" >/dev/null
done
grep -Fq 'STATE=STOP' < <(project_command bash commands/next-code-model-pass.sh "$manifest") || fail "per-pass retry limit did not stop"
expect_failure "$runtime_dir/retry.log" bash commands/record-code-model-review.sh "$manifest" --pass blockout --decision revise-code --summary 'fourth revision'

project_command bash commands/create-code-model-manifest.sh decision-model --brief 'Decision state fixture' --prompt-override \
  --output .opencaw/.cache/tasks/pipeline-test/decision.json --source src/models/decision-model.ts >/dev/null
decision_manifest="$project/.opencaw/.cache/tasks/pipeline-test/decision.json"
project_command bash commands/record-code-model-review.sh "$decision_manifest" --pass blockout --decision request-input --summary 'Need a product dimension' >/dev/null
grep -Fq 'STATE=REQUEST_INPUT' < <(project_command bash commands/next-code-model-pass.sh "$decision_manifest") || fail "request-input did not block"
project_command bash commands/record-code-model-review.sh "$decision_manifest" --pass blockout --decision revise-spec --summary 'Dimension supplied' >/dev/null
project_command bash commands/record-code-model-review.sh "$decision_manifest" --pass blockout --decision stop --summary 'Product cancelled' >/dev/null
grep -Fq 'STATE=STOP' < <(project_command bash commands/next-code-model-pass.sh "$decision_manifest") || fail "explicit stop did not persist"

mkdir -p "$project/node_modules/three"
printf '{"name":"three","version":"0.180.0"}\n' > "$project/node_modules/three/package.json"
project_command bash commands/create-code-model-manifest.sh completed-model \
  --brief 'A deterministic cel-shaded mechanical mascot' --prompt-override \
  --output .opencaw/.cache/tasks/pipeline-test/completed.json --source src/models/completed-model.ts \
  --part torso --part ears --anchor origin --anchor head-pivot >/dev/null
complete_manifest="$project/.opencaw/.cache/tasks/pipeline-test/completed.json"
for pass in blockout structure form materials interaction optimization; do
  project_command bash commands/record-code-model-review.sh "$complete_manifest" --pass "$pass" --decision pass --summary "$pass accepted" \
    --evidence front=evidence/front.png --evidence orbit-left=evidence/orbit-left.png --evidence orbit-right=evidence/orbit-right.png >/dev/null
done
grep -Fq 'STATE=COMPLETE' < <(project_command bash commands/next-code-model-pass.sh "$complete_manifest") || fail "completed manifest did not finish"

project_command bash commands/create-code-model-manifest.sh total-limit-model --brief 'Overall retry fixture' --prompt-override \
  --output .opencaw/.cache/tasks/pipeline-test/total-limit.json --source src/models/total-limit-model.ts >/dev/null
total_manifest="$project/.opencaw/.cache/tasks/pipeline-test/total-limit.json"
for pass in blockout structure form materials; do
  project_command bash commands/record-code-model-review.sh "$total_manifest" --pass "$pass" --decision revise-code --summary 'revision one' >/dev/null
  project_command bash commands/record-code-model-review.sh "$total_manifest" --pass "$pass" --decision revise-code --summary 'revision two' >/dev/null
  project_command bash commands/record-code-model-review.sh "$total_manifest" --pass "$pass" --decision pass --summary 'accepted' \
    --evidence front=evidence/front.png --evidence orbit-left=evidence/orbit-left.png --evidence orbit-right=evidence/orbit-right.png >/dev/null
done
total_state="$(project_command bash commands/next-code-model-pass.sh "$total_manifest")"
grep -Fq 'STATE=STOP' <<< "$total_state" || fail "overall retry limit did not stop"
grep -Fq 'overall attempt limit' <<< "$total_state" || fail "overall retry stop reason was not reported"

echo "[6/6] checking complete source ownership and loaded-model rejection"
printf '%s\n' \
  "import * as THREE from 'three';" \
  'export function createCompletedModel() {' \
  '  const root = new THREE.Group();' \
  "  const parts = new Map([['torso', root]]);" \
  "  const anchors = new Map([['origin', root]]);" \
  '  return { root, parts, anchors, dispose() { root.traverse((item) => item.geometry?.dispose?.()); } };' \
  '}' > "$project/src/models/completed-model.ts"
project_command bash commands/validate-code-model-manifest.sh --complete "$complete_manifest"
printf '%s\n' "import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';" 'export function createCompletedModel() { return { dispose() {} }; }' > "$project/src/models/completed-model.ts"
expect_failure "$runtime_dir/loaded-model.log" bash commands/validate-code-model-manifest.sh --complete "$complete_manifest"
grep -Fq 'loaded mesh/model asset' "$runtime_dir/loaded-model.log" || fail "loaded-model rejection was not reported"

echo "Art pipeline tests passed."
