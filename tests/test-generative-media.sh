#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.pipeline-media-runtime-XXXXXX")"
cleanup() { case "$runtime_dir" in "$repo_root"/tests/.pipeline-media-runtime-*) rm -rf -- "$runtime_dir" ;; esac; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
contains_exact_line() {
  awk -v expected="$1" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$2"
}
expect_failure() {
  local log="$1"; shift
  set +e; "$@" >"$log" 2>&1; local status=$?; set -e
  [[ $status -ne 0 ]] || fail "command unexpectedly succeeded: $*"
}
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail 'Node.js is required for owned media contract fixtures'

echo "[1/8] validating styles, roles, skills, and Bubo bindings"
for style in LAYERED_PAPERCRAFT PAPER_DIORAMA POPUP_STORYBOOK; do
  [[ -f ".styles/$style.md" ]] || fail "missing style $style"
  contains_exact_line "- $style" .styles/INDEX.md || fail "$style is not indexed"
done
for asset in .styles/.pipelines/INDEX.md .styles/.pipelines/cloud/PIPELINE.md .styles/.pipelines/local/PIPELINE.md .styles/.pipelines/_shared/media-generation-manifest.schema.json runtime/bubo.lock.json; do
  [[ -f "$asset" ]] || fail "missing media integration asset: $asset"
done
[[ ! -e .styles/.gpu ]] || fail 'retired alternate GPU tree still exists'
[[ -f .media/pipelines/registry.json ]] || fail 'independent media domain registry is missing'
for legacy in CLOUD_SESSION.md COMFYUI_LOCAL.md INDEX.md media-generation-manifest.schema.json model-packs.json toolchain.json; do
  [[ ! -e ".media/$legacy" ]] || fail "retired alternate media asset still exists: $legacy"
done
for role in arts/papercraft-art-director arts/sound-designer computer-science/generative-media-pipeline-engineer; do
  [[ -f ".roles/$role/ROLE.md" ]] || fail "missing role $role"
  bash commands/resolve-role.sh "${role#*/}" >/dev/null
done
for alias in paper-art-director audio-designer media-pipeline-engineer; do bash commands/resolve-role.sh "$alias" >/dev/null; done
for skill in plan-generative-media-pipeline use-bubo-local-generation produce-generative-audio validate-generated-media; do
  [[ -f "skills/$skill/SKILL.md" ]] || fail "missing skill $skill"
  grep -Fq "\$$skill" "skills/$skill/agents/openai.yaml" || fail "$skill metadata lacks its invocation"
  for section in 'When to use' Workflow Output Guardrails; do contains_exact_line "## $section" "skills/$skill/SKILL.md" || fail "$skill is missing $section"; done
done
bash commands/validate-role-skill-map.sh

echo "[2/8] preserving CLOUD and explicit hybrid policy"
bash commands/generate-media-contract.sh --output "$runtime_dir/cloud/MEDIA.md" CLOUD
bash commands/validate-media-contract.sh "$runtime_dir/cloud/MEDIA.md"
! grep -q '^- LOCAL' "$runtime_dir/cloud/MEDIA.md" || fail 'cloud-only contract configured local'
bash commands/generate-media-contract.sh --output "$runtime_dir/hybrid/MEDIA.md" CLOUD LOCAL
bash commands/validate-media-contract.sh "$runtime_dir/hybrid/MEDIA.md"
bash commands/generate-media-contract.sh --inline --output "$runtime_dir/inline/MEDIA.md" CLOUD LOCAL
awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$runtime_dir/inline/MEDIA.md" > "$runtime_dir/inline/MEDIA-crlf.md"
bash commands/validate-media-contract.sh "$runtime_dir/inline/MEDIA-crlf.md"
grep -Fq '.styles/.pipelines/cloud/PIPELINE.md' "$runtime_dir/hybrid/MEDIA.md" || fail 'hybrid contract omitted CLOUD'
grep -Fq '.styles/.pipelines/local/PIPELINE.md' "$runtime_dir/hybrid/MEDIA.md" || fail 'hybrid contract omitted LOCAL'
! grep -Fq '.media/' "$runtime_dir/hybrid/MEDIA.md" || fail 'hybrid contract retained stale path'
grep -Eiq 'ask the user to choose|require the user to choose' "$runtime_dir/hybrid/MEDIA.md" || fail 'hybrid omitted explicit choice'
grep -Eiq 'never (switch or )?fall back.*silently|never.*silently.*fall back' "$runtime_dir/hybrid/MEDIA.md" || fail 'hybrid omitted fallback boundary'
expect_failure "$runtime_dir/backend-order.log" bash commands/generate-media-contract.sh --output "$runtime_dir/bad.md" LOCAL CLOUD
expect_failure "$runtime_dir/blender-media.log" bash commands/generate-media-contract.sh --output "$runtime_dir/blender-media.md" BLENDER
cp "$runtime_dir/hybrid/MEDIA.md" "$runtime_dir/missing-choice.md"
sed -i '/ask the user to choose\|require the user to choose/d' "$runtime_dir/missing-choice.md"
expect_failure "$runtime_dir/missing-choice.log" bash commands/validate-media-contract.sh "$runtime_dir/missing-choice.md"

echo "[3/8] keeping public command help independent of setup and generation"
for command in generate-media-contract validate-media-contract bubo-media install-bubo-media inspect-local-media-host validate-media-generation-manifest; do
  bash "commands/$command.sh" --help >/dev/null || fail "$command --help failed"
done
for operation in setup inspect generate; do bash commands/bubo-media.sh "$operation" --help >/dev/null; done

echo "[4/8] asserting active implementation retirement without touching external installations"
# These are explicit retirement assertions, not compatibility command aliases.
for retired in commands/install-comfyui-local.sh commands/install-comfyui-models.sh commands/run-comfyui-workflow.sh skills/use-comfyui-local-generation .styles/.pipelines/local/toolchain.json .styles/.pipelines/local/model-packs.json tests/fixtures/media/fake-comfy.cjs; do
  [[ ! -e "$retired" ]] || fail "active retired integration remains: $retired"
done

echo "[5/8] exercising owned pure host-context, shared-budget and provenance fixtures"
"$node_bin" tests/test-bubo-media-context.cjs

echo "[6/8] inspecting readiness without loading models or mutating the host"
mkdir -p "$runtime_dir/discovery"
bash commands/inspect-local-media-host.sh --root "$runtime_dir/discovery" --workspace .opencaw/.cache/bubo-media --json > "$runtime_dir/discovery.json"
discovery_for_node="$runtime_dir/discovery.json"
project_for_node="$runtime_dir/discovery"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  discovery_for_node="$(wslpath -w "$discovery_for_node")"; project_for_node="$(wslpath -w "$project_for_node")"
fi
"$node_bin" - "$discovery_for_node" "$project_for_node" <<'NODE'
const fs=require('fs'),assert=require('assert/strict');
const doc=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
assert.equal(doc.schemaVersion,'opencaw-local-media-host/v1');assert.equal(doc.pipeline,'LOCAL');
for(const field of ['generation','modelLoading','installation','externalInstallationsInspected'])assert.equal(doc[field],false,field+' must not occur in discovery');
for(const modality of ['image','sfx','music','voice']){
  assert.equal(doc.modalities[modality].ready,false,'advertisement/receipt presence cannot establish native readiness');
  assert(Array.isArray(doc.modalities[modality].backends),'separate backend identities remain available');
}
assert(!Object.hasOwn(doc,'comfyUI')&&!doc.tools?.comfyCli,'retired external execution must not be probed');
assert.deepEqual(fs.readdirSync(process.argv[3]),[],'read-only discovery creates no host/cache/install state');
console.log('PASS: four-modality readiness remains separate from installed/native verification.');
NODE
for operation in setup inspect generate; do
  expect_failure "$runtime_dir/missing-$operation.log" bash commands/bubo-media.sh "$operation" --root "$runtime_dir/discovery" --task owned --manifest missing.json
  [[ ! -e "$runtime_dir/discovery/.opencaw" ]] || fail 'rejected media dispatch created durable state'
done

echo "[7/8] validating image, music, SFX, and voice manifests"
# Schema-only synthetic fixtures retain historical provider names and review
# states. They execute no provider and establish no media quality or approval.
for modality in image music sfx voice; do
  dir="$runtime_dir/manifests/$modality"; mkdir -p "$dir"; printf '%s candidate\n' "$modality" > "$dir/candidate.bin"; hash="$(sha256sum "$dir/candidate.bin" | awk '{print $1}')"
  status=staged; review=pending; reviewer='{"unavailable":true,"reason":"review pending"}'; reviewed='{"unavailable":true,"reason":"review pending"}'; rejection=''
  backend_kind=cloud-session; provider=session-capability; tool_version='{"unavailable":true,"reason":"provider did not disclose"}'
  if [[ "$modality" == image ]]; then backend_kind=local; provider=comfy-cli; tool_version='"1.12.0"'; fi
  if [[ "$modality" == music ]]; then status=accepted; review=accepted; reviewer='"reviewer@example"'; reviewed='"2026-07-25T12:00:00Z"'; fi
  if [[ "$modality" == sfx ]]; then status=rejected; review=rejected; reviewer='"reviewer@example"'; reviewed='"2026-07-25T12:00:00Z"'; rejection=',"rejectionReason":"audible artifact"'; fi
  if [[ "$modality" == voice ]]; then status=promoted; review=accepted; reviewer='"reviewer@example"'; reviewed='"2026-07-25T12:00:00Z"'; fi
  cat > "$dir/manifest.json" <<EOF
{"schemaVersion":1,"runId":"$modality-fixture","createdAt":"2026-07-25T12:00:00Z","backend":{"kind":"$backend_kind","provider":"$provider","capability":"$modality","toolVersion":$tool_version},"modality":"$modality","model":{"name":{"unavailable":true,"reason":"not disclosed"},"revision":{"unavailable":true,"reason":"not disclosed"},"digest":{"unavailable":true,"reason":"not disclosed"},"license":"provider terms reviewed"},"workflow":{"name":{"unavailable":true,"reason":"not disclosed"},"revision":{"unavailable":true,"reason":"not disclosed"},"digest":{"unavailable":true,"reason":"not disclosed"}},"generation":{"prompt":"generic fixture","negativePrompt":{"unavailable":true,"reason":"unsupported"},"parameters":{"unavailable":true,"reason":"unsupported"},"seed":{"unavailable":true,"reason":"unsupported"}},"inputs":[{"description":"text brief","source":"authorized fixture","rights":"owned fixture","consent":"confirmed"}],"outputs":[{"stagedPath":"candidate.bin","sha256":"$hash","status":"$status","runtimeTarget":"runtime/media"$rejection}],"runtime":{"destination":"runtime/media","budgets":{"sizeBytes":1000000}},"review":{"status":"$review","reviewer":$reviewer,"reviewedAt":$reviewed,"notes":"fixture review"}}
EOF
  bash commands/validate-media-generation-manifest.sh "$dir/manifest.json"
done
echo "Checking native project-relative receipts and retained legacy resolution"
native_project="$runtime_dir/project-relative"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail 'Node.js is required for receipt fixtures'
native_project_for_node="$native_project"
template_for_node="$runtime_dir/manifests/image/manifest.json"
if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  native_project_for_node="$(wslpath -w "$native_project_for_node")"
  template_for_node="$(wslpath -w "$template_for_node")"
fi
"$node_bin" - "$native_project_for_node" "$template_for_node" <<'NODE'
const fs=require('fs'),path=require('path');
const root=process.argv[2],template=process.argv[3];
const receipts=path.join(root,'.opencaw/.cache/tasks/native');
const staged=path.join(root,'.art-staging/proofs');
const outside=path.join(path.dirname(root),'project-relative-sibling');
for(const directory of [receipts,staged,outside]) fs.mkdirSync(directory,{recursive:true});
for(const directory of [staged,outside]) fs.copyFileSync(path.join(path.dirname(template),'candidate.bin'),path.join(directory,'candidate.bin'));
const base=JSON.parse(fs.readFileSync(template,'utf8'));
function write(name,output) {
  const data=structuredClone(base);data.outputs[0].stagedPath=output;
  fs.writeFileSync(path.join(receipts,name+'.json'),JSON.stringify(data));return data;
}
const valid=write('valid','.art-staging/proofs/candidate.bin');
write('escape','../project-relative-sibling/candidate.bin');
write('absolute',path.join(staged,'candidate.bin'));
write('missing','.art-staging/proofs/missing.bin');
const stale=write('changed-hash','.art-staging/proofs/candidate.bin');stale.outputs[0].sha256='0'.repeat(64);fs.writeFileSync(path.join(receipts,'changed-hash.json'),JSON.stringify(stale));
fs.writeFileSync(path.join(outside,'manifest.json'),JSON.stringify(valid));
fs.symlinkSync(staged,path.join(root,'inside-link'),'junction');
fs.symlinkSync(outside,path.join(root,'outside-link'),'junction');
fs.symlinkSync(receipts,path.join(root,'manifest-link'),'junction');
fs.symlinkSync(root,path.join(path.dirname(root),'project-alias'),'junction');
write('inside-link','inside-link/candidate.bin');
write('outside-link','outside-link/candidate.bin');
NODE
native_receipts="$native_project/.opencaw/.cache/tasks/native"
bash commands/validate-media-generation-manifest.sh --project-root "$native_project" "$native_receipts/valid.json"
expect_failure "$runtime_dir/project-legacy.log" bash commands/validate-media-generation-manifest.sh "$native_receipts/valid.json"
for adverse in escape absolute missing changed-hash inside-link outside-link; do
  expect_failure "$runtime_dir/project-$adverse.log" bash commands/validate-media-generation-manifest.sh --project-root "$native_project" "$native_receipts/$adverse.json"
done
expect_failure "$runtime_dir/project-manifest-escape.log" bash commands/validate-media-generation-manifest.sh --project-root "$native_project" "$runtime_dir/project-relative-sibling/manifest.json"
expect_failure "$runtime_dir/project-manifest-link.log" bash commands/validate-media-generation-manifest.sh --project-root "$native_project" "$native_project/manifest-link/valid.json"
expect_failure "$runtime_dir/project-root-link.log" bash commands/validate-media-generation-manifest.sh --project-root "$runtime_dir/project-alias" "$runtime_dir/project-alias/.opencaw/.cache/tasks/native/valid.json"
expect_failure "$runtime_dir/project-duplicate.log" bash commands/validate-media-generation-manifest.sh --project-root "$native_project" --project-root "$native_project" "$native_receipts/valid.json"
expect_failure "$runtime_dir/project-missing-option.log" bash commands/validate-media-generation-manifest.sh --project-root
grep -Fq 'hash mismatch' "$runtime_dir/project-changed-hash.log" || fail 'changed project output did not fail its hash'
grep -Fq 'symbolic link or junction' "$runtime_dir/project-inside-link.log" || fail 'project output alias was not rejected'
grep -Fq 'escapes the project root' "$runtime_dir/project-manifest-escape.log" || fail 'outside manifest was not rejected before reading'
cp "$runtime_dir/manifests/image/manifest.json" "$runtime_dir/invalid-hash.json"; cp "$runtime_dir/manifests/image/candidate.bin" "$runtime_dir/candidate.bin"; sed -i 's/[a-f0-9]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' "$runtime_dir/invalid-hash.json"
expect_failure "$runtime_dir/hash.log" bash commands/validate-media-generation-manifest.sh "$runtime_dir/invalid-hash.json"
cp "$runtime_dir/manifests/voice/manifest.json" "$runtime_dir/unreviewed.json"; cp "$runtime_dir/manifests/voice/candidate.bin" "$runtime_dir/candidate.bin"; sed -i 's/"status":"accepted"/"status":"pending"/' "$runtime_dir/unreviewed.json"
expect_failure "$runtime_dir/promotion.log" bash commands/validate-media-generation-manifest.sh "$runtime_dir/unreviewed.json"
cp "$runtime_dir/manifests/image/manifest.json" "$runtime_dir/no-budget.json"; cp "$runtime_dir/manifests/image/candidate.bin" "$runtime_dir/candidate.bin"; sed -i 's/"budgets":{"sizeBytes":1000000}/"budgets":{}/' "$runtime_dir/no-budget.json"
expect_failure "$runtime_dir/budget.log" bash commands/validate-media-generation-manifest.sh "$runtime_dir/no-budget.json"
cp "$runtime_dir/manifests/voice/manifest.json" "$runtime_dir/no-consent.json"; cp "$runtime_dir/manifests/voice/candidate.bin" "$runtime_dir/candidate.bin"; sed -i 's/"consent":"confirmed"/"consent":"not-confirmed"/' "$runtime_dir/no-consent.json"
expect_failure "$runtime_dir/consent.log" bash commands/validate-media-generation-manifest.sh "$runtime_dir/no-consent.json"
cp "$runtime_dir/manifests/image/manifest.json" "$runtime_dir/no-seed.json"; cp "$runtime_dir/manifests/image/candidate.bin" "$runtime_dir/candidate.bin"; sed -i 's/,"seed":{"unavailable":true,"reason":"unsupported"}//' "$runtime_dir/no-seed.json"
expect_failure "$runtime_dir/reproducibility.log" bash commands/validate-media-generation-manifest.sh "$runtime_dir/no-seed.json"
cp "$runtime_dir/manifests/image/manifest.json" "$runtime_dir/no-rights.json"; cp "$runtime_dir/manifests/image/candidate.bin" "$runtime_dir/candidate.bin"; sed -i 's/,"rights":"owned fixture"//' "$runtime_dir/no-rights.json"
expect_failure "$runtime_dir/rights.log" bash commands/validate-media-generation-manifest.sh "$runtime_dir/no-rights.json"

echo "[8/8] validating pipeline structure and integrated hooks"
bash commands/validate-media-templates.sh
bash commands/validate-art-pipelines.sh
grep -Fq './commands/validate-art-pipelines.sh' commands/validate-opencaw.sh || fail "integrated validation omits art pipelines"
grep -Fq './commands/validate-media-templates.sh' commands/validate-opencaw.sh || fail "integrated validation omits media templates"
git_check_bin="$(command -v git.exe 2>/dev/null || command -v git)"
"$git_check_bin" diff --check
echo "Generative media tests passed."
