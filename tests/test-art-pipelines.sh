#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.art-pipeline-runtime-XXXXXX")"
project="$runtime_dir/project"
mkdir -p "$project/.ai/tasks/pipeline-test" "$project/src/models" "$project/evidence"

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

echo "[1/6] validating the pipeline catalog and CSS3 constraints"
bash commands/validate-art-pipelines.sh
[[ ! -e .styles/.gpu ]] || fail "legacy pipeline tree exists"
[[ ! -e .media ]] || fail "legacy media tree exists"
grep -Eiq 'no raster|without raster|do not use raster' .styles/.pipelines/css3/PIPELINE.md || fail "CSS3 contract lacks raster boundary"
! grep -Eiq 'canvas|webgl|generated.image' .styles/.pipelines/css3/art-tokens.css || fail "CSS3 tokens depend on a prohibited renderer"
grep -Fq 'Blender 4.5 LTS' .styles/.pipelines/blender/PIPELINE.md || fail "BLENDER contract lacks its version boundary"
grep -Eiq 'immutable source|preserve every immutable source' .styles/.pipelines/blender/PIPELINE.md || fail "BLENDER contract lacks immutable-source protection"
grep -Eiq 'never installed|never install' .styles/.pipelines/blender/PIPELINE.md || fail "BLENDER contract lacks its no-install boundary"

echo "[2/6] generating default, explicit, aliased, allowed, and inline contracts"
project_command bash commands/generate-style.sh CEL_SHADED_COMIC
project_command bash commands/validate-style-contract.sh "$project/STYLE.md"
contains_exact_line '- CSS3' "$project/STYLE.md" || fail "default style contract did not select CSS3"

for pair in 'imagegen CLOUD' 'comfyui LOCAL' 'vector CSS3' 'threejs CODE' 'blender BLENDER' 'blend BLENDER' 'bpy BLENDER'; do
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

project_command bash commands/generate-style.sh --pipeline CSS3 --allow-pipeline imagegen --allow-pipeline comfyui --allow-pipeline threejs --allow-pipeline blender CEL_SHADED_COMIC >/dev/null
for pipeline in CSS3 CLOUD LOCAL CODE BLENDER; do contains_exact_line "- $pipeline" "$project/STYLE.md" || fail "allowed list omits $pipeline"; done
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
project_command bash commands/generate-style.sh --inline --pipeline CODE --allow-pipeline CSS3 CEL_SHADED_COMIC >/dev/null
grep -Fq '<!-- BEGIN ART PIPELINE: CODE -->' "$project/STYLE.md" || fail "inline contract omitted CODE"
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
project_command bash commands/generate-style.sh --inline --pipeline blender --allow-pipeline CSS3 CEL_SHADED_COMIC >/dev/null
grep -Fq '<!-- BEGIN ART PIPELINE: BLENDER -->' "$project/STYLE.md" || fail "inline contract omitted BLENDER"
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
expect_failure "$runtime_dir/invalid.log" bash commands/generate-style.sh --pipeline unknown CEL_SHADED_COMIC
expect_failure "$runtime_dir/duplicate.log" bash commands/generate-style.sh --pipeline CSS3 --allow-pipeline vector CEL_SHADED_COMIC

project_command bash commands/generate-style.sh --pipeline CSS3 --allow-pipeline CODE CEL_SHADED_COMIC >/dev/null
awk '!/\.styles\/\.pipelines\/code\/PIPELINE\.md/' "$project/STYLE.md" > "$runtime_dir/missing-directive.md"
expect_failure "$runtime_dir/missing-directive.log" bash commands/validate-style-contract.sh "$runtime_dir/missing-directive.md"

echo "[3/6] resolving task-only prompt overrides without changing STYLE.md"
style_before="$(sha256sum "$project/STYLE.md" | awk '{print $1}')"
for pair in 'imagegen CLOUD' 'comfyui LOCAL' 'vector CSS3' 'threejs CODE' 'blender BLENDER' 'blend BLENDER' 'bpy BLENDER'; do
  read -r alias expected <<< "$pair"
  output="$(project_command bash commands/resolve-art-pipeline.sh --style "$project/STYLE.md" --override "$alias" --json)"
  grep -Fq "\"pipeline\": \"$expected\"" <<< "$output" || fail "override $alias did not resolve to $expected"
  grep -Fq '"selectionSource": "prompt"' <<< "$output" || fail "override did not record prompt source"
done
project_command bash commands/resolve-art-pipeline.sh --style "$project/STYLE.md" --override imagegen --evidence "$project/.ai/tasks/pipeline-test/selection.json" >/dev/null
grep -Fq '"selectionSource": "prompt"' "$project/.ai/tasks/pipeline-test/selection.json" || fail "selection evidence omitted prompt source"
style_after="$(sha256sum "$project/STYLE.md" | awk '{print $1}')"
[[ "$style_before" == "$style_after" ]] || fail "prompt override rewrote STYLE.md"
expect_failure "$runtime_dir/evidence-escape.log" bash commands/resolve-art-pipeline.sh --style "$project/STYLE.md" --override CODE --evidence "$runtime_dir/outside.json"

echo "[4/6] creating and validating a CODE manifest"
printf 'authorized reference bytes\n' > "$project/reference.png"
project_command bash commands/create-code-model-manifest.sh test-model \
  --brief 'A deterministic cel-shaded mechanical mascot with articulated ears' \
  --prompt-override --output .ai/tasks/pipeline-test/code-model.json --source src/models/test-model.ts \
  --part torso --part left-ear --part right-ear --anchor origin --anchor head-pivot \
  --reference reference.png --reference-rights 'user-owned' --reference-consent confirmed >/dev/null
manifest="$project/.ai/tasks/pipeline-test/code-model.json"
manifest_sha_before="$(sha256sum "$manifest" | awk '{print $1}')"
project_command bash commands/create-code-model-manifest.sh test-model \
  --brief 'A deterministic cel-shaded mechanical mascot with articulated ears' \
  --prompt-override --output .ai/tasks/pipeline-test/code-model.json --source src/models/test-model.ts \
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
  --output .ai/tasks/pipeline-test/decision.json --source src/models/decision-model.ts >/dev/null
decision_manifest="$project/.ai/tasks/pipeline-test/decision.json"
project_command bash commands/record-code-model-review.sh "$decision_manifest" --pass blockout --decision request-input --summary 'Need a product dimension' >/dev/null
grep -Fq 'STATE=REQUEST_INPUT' < <(project_command bash commands/next-code-model-pass.sh "$decision_manifest") || fail "request-input did not block"
project_command bash commands/record-code-model-review.sh "$decision_manifest" --pass blockout --decision revise-spec --summary 'Dimension supplied' >/dev/null
project_command bash commands/record-code-model-review.sh "$decision_manifest" --pass blockout --decision stop --summary 'Product cancelled' >/dev/null
grep -Fq 'STATE=STOP' < <(project_command bash commands/next-code-model-pass.sh "$decision_manifest") || fail "explicit stop did not persist"

mkdir -p "$project/node_modules/three"
printf '{"name":"three","version":"0.180.0"}\n' > "$project/node_modules/three/package.json"
project_command bash commands/create-code-model-manifest.sh completed-model \
  --brief 'A deterministic cel-shaded mechanical mascot' --prompt-override \
  --output .ai/tasks/pipeline-test/completed.json --source src/models/completed-model.ts \
  --part torso --part ears --anchor origin --anchor head-pivot >/dev/null
complete_manifest="$project/.ai/tasks/pipeline-test/completed.json"
for pass in blockout structure form materials interaction optimization; do
  project_command bash commands/record-code-model-review.sh "$complete_manifest" --pass "$pass" --decision pass --summary "$pass accepted" \
    --evidence front=evidence/front.png --evidence orbit-left=evidence/orbit-left.png --evidence orbit-right=evidence/orbit-right.png >/dev/null
done
grep -Fq 'STATE=COMPLETE' < <(project_command bash commands/next-code-model-pass.sh "$complete_manifest") || fail "completed manifest did not finish"

project_command bash commands/create-code-model-manifest.sh total-limit-model --brief 'Overall retry fixture' --prompt-override \
  --output .ai/tasks/pipeline-test/total-limit.json --source src/models/total-limit-model.ts >/dev/null
total_manifest="$project/.ai/tasks/pipeline-test/total-limit.json"
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
