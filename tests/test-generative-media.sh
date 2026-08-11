#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.pipeline-media-runtime-XXXXXX")"
export OPENCAW_TEST_MODE=1
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

echo "[1/8] validating styles, roles, skills, and bindings"
for style in LAYERED_PAPERCRAFT PAPER_DIORAMA POPUP_STORYBOOK; do
  [[ -f ".styles/$style.md" ]] || fail "missing style $style"
  contains_exact_line "- $style" .styles/INDEX.md || fail "$style is not indexed"
done
for asset in \
  .styles/.pipelines/INDEX.md \
  .styles/.pipelines/cloud/PIPELINE.md \
  .styles/.pipelines/local/PIPELINE.md \
  .styles/.pipelines/_shared/media-generation-manifest.schema.json \
  .styles/.pipelines/local/toolchain.json \
  .styles/.pipelines/local/model-packs.json; do
  [[ -f "$asset" ]] || fail "missing pipeline-owned media asset: $asset"
done
[[ ! -e ".styles/.gpu" ]] || fail "legacy pipeline tree still exists"
[[ ! -e ".media" ]] || fail "legacy .media directory still exists"
for role in arts/papercraft-art-director arts/sound-designer computer-science/generative-media-pipeline-engineer; do
  [[ -f ".roles/$role/ROLE.md" ]] || fail "missing role $role"
  bash commands/resolve-role.sh "${role#*/}" >/dev/null
done
bash commands/resolve-role.sh paper-art-director >/dev/null
bash commands/resolve-role.sh audio-designer >/dev/null
bash commands/resolve-role.sh media-pipeline-engineer >/dev/null
for skill in plan-generative-media-pipeline use-comfyui-local-generation produce-generative-audio validate-generated-media; do
  [[ -f "skills/$skill/SKILL.md" ]] || fail "missing skill $skill"
  grep -Fq "\$$skill" "skills/$skill/agents/openai.yaml" || fail "$skill metadata lacks its invocation"
  for section in "When to use" "Workflow" "Output" "Guardrails"; do contains_exact_line "## $section" "skills/$skill/SKILL.md" || fail "$skill is missing $section"; done
done
bash commands/validate-role-skill-map.sh

echo "[2/8] generating cloud-only and hybrid contracts"
bash commands/generate-media-contract.sh --output "$runtime_dir/cloud/MEDIA.md" CLOUD
bash commands/validate-media-contract.sh "$runtime_dir/cloud/MEDIA.md"
! grep -q '^- LOCAL' "$runtime_dir/cloud/MEDIA.md" || fail "cloud-only contract configured local"
bash commands/generate-media-contract.sh --output "$runtime_dir/hybrid/MEDIA.md" CLOUD LOCAL
bash commands/validate-media-contract.sh "$runtime_dir/hybrid/MEDIA.md"
grep -Fq '.styles/.pipelines/cloud/PIPELINE.md' "$runtime_dir/hybrid/MEDIA.md" || fail "hybrid contract omitted the cloud pipeline path"
grep -Fq '.styles/.pipelines/local/PIPELINE.md' "$runtime_dir/hybrid/MEDIA.md" || fail "hybrid contract omitted the local pipeline path"
! grep -Fq '.media/' "$runtime_dir/hybrid/MEDIA.md" || fail "hybrid contract retained a stale .media path"
grep -Eiq 'ask the user to choose' "$runtime_dir/hybrid/MEDIA.md" || fail "hybrid contract omitted user choice"
grep -Eiq 'never switch or fall back.*silently' "$runtime_dir/hybrid/MEDIA.md" || fail "hybrid contract omitted fallback boundary"
expect_failure "$runtime_dir/backend-order.log" bash commands/generate-media-contract.sh --output "$runtime_dir/bad.md" LOCAL CLOUD
expect_failure "$runtime_dir/blender-media.log" bash commands/generate-media-contract.sh --output "$runtime_dir/blender-media.md" BLENDER
cp "$runtime_dir/hybrid/MEDIA.md" "$runtime_dir/missing-choice.md"
sed -i '/ask the user to choose/d' "$runtime_dir/missing-choice.md"
expect_failure "$runtime_dir/missing-choice.log" bash commands/validate-media-contract.sh "$runtime_dir/missing-choice.md"

echo "[3/8] checking command help and dry-run behavior"
for command in generate-media-contract validate-media-contract install-comfyui-local install-comfyui-models inspect-local-media-host run-comfyui-workflow validate-media-generation-manifest; do
  bash "commands/$command.sh" --help >/dev/null || fail "$command --help failed"
done
for platform in windows linux macos; do
  OPENCAW_PLATFORM_OVERRIDE="$platform" bash commands/install-comfyui-local.sh --workspace "$runtime_dir/install-$platform" >"$runtime_dir/install-$platform.log"
  grep -q 'mode: dry-run' "$runtime_dir/install-$platform.log" || fail "$platform installer was not a dry-run"
done
bash commands/install-comfyui-models.sh --pack all --workspace "$runtime_dir/models" >"$runtime_dir/models-dry-run.log"
grep -q 'ead426278b49030e9da5df862994f25ce94ab2ee4df38b556ddddb3db093bf72' "$runtime_dir/models-dry-run.log" || fail "FLUX checksum missing"
grep -q 'stability-community-license' "$runtime_dir/models-dry-run.log" || fail "audio license missing"

echo "[4/8] enforcing hardware, disk, license, credential, and checksum gates"
large_disk=999999999999
large_vram=999999999999
expect_failure "$runtime_dir/disk.log" env OPENCAW_TEST_DISK_BYTES=1 OPENCAW_TEST_GPU_KIND=nvidia OPENCAW_TEST_VRAM_BYTES="$large_vram" bash commands/install-comfyui-models.sh --pack flux-schnell-fp8 --workspace "$runtime_dir/models" --execute
grep -q 'Insufficient disk space' "$runtime_dir/disk.log" || fail "disk gate was not reported"
expect_failure "$runtime_dir/vram.log" env OPENCAW_TEST_DISK_BYTES="$large_disk" OPENCAW_TEST_GPU_KIND=nvidia OPENCAW_TEST_VRAM_BYTES=1 bash commands/install-comfyui-models.sh --pack flux-schnell-fp8 --workspace "$runtime_dir/models" --execute
grep -q 'Insufficient VRAM' "$runtime_dir/vram.log" || fail "VRAM gate was not reported"
expect_failure "$runtime_dir/hardware.log" env OPENCAW_TEST_DISK_BYTES="$large_disk" OPENCAW_TEST_GPU_KIND=unsupported bash commands/install-comfyui-models.sh --pack flux-schnell-fp8 --workspace "$runtime_dir/models" --execute
grep -q 'Unsupported local generation hardware' "$runtime_dir/hardware.log" || fail "unsupported hardware was not reported"
expect_failure "$runtime_dir/license.log" env OPENCAW_TEST_DISK_BYTES="$large_disk" OPENCAW_TEST_GPU_KIND=nvidia OPENCAW_TEST_VRAM_BYTES="$large_vram" bash commands/install-comfyui-models.sh --pack flux-schnell-fp8 --workspace "$runtime_dir/models" --execute
grep -q 'License acceptance required' "$runtime_dir/license.log" || fail "license gate was not reported"
expect_failure "$runtime_dir/credential.log" env -u HF_API_TOKEN OPENCAW_COMFY_BIN=/bin/true OPENCAW_TEST_DISK_BYTES="$large_disk" OPENCAW_TEST_GPU_KIND=nvidia OPENCAW_TEST_VRAM_BYTES="$large_vram" bash commands/install-comfyui-models.sh --pack stable-audio-open --workspace "$runtime_dir/models" --accept-license stability-community-license --accept-license apache-2.0 --execute
grep -q 'HF_API_TOKEN is required' "$runtime_dir/credential.log" || fail "credential gate was not reported"
mkdir -p "$runtime_dir/bad-model/models/checkpoints"
printf 'wrong bytes\n' > "$runtime_dir/bad-model/models/checkpoints/flux1-schnell-fp8.safetensors"
expect_failure "$runtime_dir/checksum.log" env OPENCAW_TEST_DISK_BYTES="$large_disk" OPENCAW_TEST_GPU_KIND=nvidia OPENCAW_TEST_VRAM_BYTES="$large_vram" bash commands/install-comfyui-models.sh --pack flux-schnell-fp8 --workspace "$runtime_dir/bad-model" --accept-license apache-2.0 --execute
grep -q 'Checksum mismatch' "$runtime_dir/checksum.log" || fail "checksum gate was not reported"

echo "[5/8] exercising isolated package managers and idempotent tool installation"
fake_tools="$runtime_dir/fake-tools"
mkdir -p "$fake_tools"
cat > "$fake_tools/fake-comfy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then echo 'comfy-cli version 1.12.0'; exit 0; fi
workspace=''
while [[ $# -gt 0 ]]; do if [[ "$1" == "--workspace" ]]; then workspace="$2"; shift 2; else shift; fi; done
[[ -z "$workspace" ]] || { mkdir -p "$workspace"; touch "$workspace/main.py"; }
EOF
cat > "$fake_tools/fake-python" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "-c" ]]; then echo '3.13'; exit 0; fi
if [[ "\${1:-}" == "-m" && "\${2:-}" == "venv" ]]; then
  target="\$3"
  mkdir -p "\$target/bin" "\$target/Scripts"
  cp "$fake_tools/fake-python" "\$target/bin/python"
  cp "$fake_tools/fake-python" "\$target/Scripts/python.exe"
  cp "$fake_tools/fake-comfy" "\$target/bin/comfy"
  cp "$fake_tools/fake-comfy" "\$target/Scripts/comfy.exe"
  chmod +x "\$target/bin/python" "\$target/Scripts/python.exe" "\$target/bin/comfy" "\$target/Scripts/comfy.exe"
  exit 0
fi
exit 0
EOF
chmod +x "$fake_tools/fake-python" "$fake_tools/fake-comfy"
cat > "$fake_tools/winget" <<'EOF'
#!/usr/bin/env bash
printf 'winget %s\n' "$*" >> "${OPENCAW_PACKAGE_LOG:?}"
EOF
cat > "$fake_tools/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >> "${OPENCAW_PACKAGE_LOG:?}"
EOF
cat > "$fake_tools/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "${OPENCAW_PACKAGE_LOG:?}"
EOF
cat > "$fake_tools/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
chmod +x "$fake_tools/winget" "$fake_tools/brew" "$fake_tools/apt-get" "$fake_tools/sudo"
package_log="$runtime_dir/package-managers.log"
for platform in windows macos linux; do
  env PATH="$fake_tools:$PATH" OPENCAW_PLATFORM_OVERRIDE="$platform" OPENCAW_PYTHON_BIN="$fake_tools/fake-python" OPENCAW_TEST_MISSING_FFMPEG=1 OPENCAW_PACKAGE_LOG="$package_log" bash commands/install-comfyui-local.sh --workspace "$runtime_dir/package-$platform" --execute >"$runtime_dir/package-$platform.log"
done
grep -Fq 'winget install --id Gyan.FFmpeg' "$package_log" || fail "Windows package-manager fixture was not exercised"
grep -Fq 'brew install ffmpeg' "$package_log" || fail "macOS package-manager fixture was not exercised"
grep -Fq 'apt-get install -y ffmpeg' "$package_log" || fail "Linux package-manager fixture was not exercised"
OPENCAW_PLATFORM_OVERRIDE=linux OPENCAW_PYTHON_BIN="$fake_tools/fake-python" bash commands/install-comfyui-local.sh --workspace "$runtime_dir/isolated" --execute >"$runtime_dir/install-first.log"
OPENCAW_PLATFORM_OVERRIDE=linux OPENCAW_PYTHON_BIN="$fake_tools/fake-python" bash commands/install-comfyui-local.sh --workspace "$runtime_dir/isolated" --execute >"$runtime_dir/install-second.log"
[[ -x "$runtime_dir/isolated/.opencaw/bin/comfy" && -f "$runtime_dir/isolated/main.py" ]] || fail "isolated install fixture was incomplete"
grep -q 'already exists' "$runtime_dir/install-second.log" || fail "second install was not idempotent"
mkdir -p "$runtime_dir/isolated/models/checkpoints" "$runtime_dir/isolated/models/text_encoders"
touch "$runtime_dir/isolated/models/checkpoints/flux1-schnell-fp8.safetensors"
touch "$runtime_dir/isolated/models/checkpoints/stable-audio-open-1.0.safetensors"
touch "$runtime_dir/isolated/models/text_encoders/t5-base.safetensors"
OPENCAW_PLATFORM_OVERRIDE=linux bash commands/inspect-local-media-host.sh --workspace "$runtime_dir/isolated" --json > "$runtime_dir/inspect.json"
[[ "$(grep -c '"ready": true' "$runtime_dir/inspect.json")" -eq 2 ]] || fail "host inspection drifted from model-pack destinations"

echo "[6/8] running workflows through a fake structured comfy-cli"
fake_comfy="$repo_root/tests/fixtures/media/fake-comfy.cjs"
mkdir -p "$runtime_dir/workflows"
for name in success malformed failed node-error timeout missing-output malformed-download; do printf '{}\n' > "$runtime_dir/workflows/$name.json"; done
OPENCAW_ASSUME_SERVER_RUNNING=1 OPENCAW_TEST_COMFY_SCRIPT="$fake_comfy" bash commands/run-comfyui-workflow.sh --workflow "$runtime_dir/workflows/success.json" --output-dir "$runtime_dir/staging-success" --workspace "$runtime_dir/comfy" --timeout 10
[[ -f "$runtime_dir/staging-success/candidate.bin" && -f "$runtime_dir/staging-success/opencaw-run-receipt.json" ]] || fail "successful workflow lacks staged output or receipt"
grep -q 'pending-human-review' "$runtime_dir/staging-success/opencaw-run-receipt.json" || fail "receipt promoted output automatically"
expected_hash="$(sha256sum "$runtime_dir/staging-success/candidate.bin" | awk '{print $1}')"
grep -q "$expected_hash" "$runtime_dir/staging-success/opencaw-run-receipt.json" || fail "receipt hash mismatch"
for name in malformed failed node-error missing-output malformed-download; do
  expect_failure "$runtime_dir/$name.log" env OPENCAW_ASSUME_SERVER_RUNNING=1 OPENCAW_TEST_COMFY_SCRIPT="$fake_comfy" bash commands/run-comfyui-workflow.sh --workflow "$runtime_dir/workflows/$name.json" --output-dir "$runtime_dir/staging-$name" --workspace "$runtime_dir/comfy" --timeout 10
done
expect_failure "$runtime_dir/timeout.log" env OPENCAW_ASSUME_SERVER_RUNNING=1 OPENCAW_TEST_COMFY_SCRIPT="$fake_comfy" bash commands/run-comfyui-workflow.sh --workflow "$runtime_dir/workflows/timeout.json" --output-dir "$runtime_dir/staging-timeout" --workspace "$runtime_dir/comfy" --timeout 1
grep -q 'timeout' "$runtime_dir/timeout.log" || fail "wall-clock timeout was not reported"
expect_failure "$runtime_dir/path.log" env OPENCAW_ASSUME_SERVER_RUNNING=1 OPENCAW_TEST_COMFY_SCRIPT="$fake_comfy" bash commands/run-comfyui-workflow.sh --workflow "$runtime_dir/workflows/success.json" --output-dir / --workspace "$runtime_dir/comfy"

echo "[7/8] validating image, music, SFX, and voice manifests"
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
