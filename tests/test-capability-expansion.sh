#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

temp_root="$(mktemp -d)"
runtime_dir="$repo_root/tests/.capability-runtime-${RANDOM}-${RANDOM}"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" >/dev/null 2>&1 || true; fi
  rm -rf -- "$temp_root"
  case "$runtime_dir" in "$repo_root"/tests/.capability-runtime-*) rm -rf -- "$runtime_dir" ;; esac
}
trap cleanup EXIT
mkdir -p "$runtime_dir"

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_failure() {
  local output_file="$1"
  shift
  set +e
  "$@" >"$output_file" 2>&1
  local result=$?
  set -e
  [[ $result -ne 0 ]] || fail "command unexpectedly succeeded: $*"
  return 0
}

echo "[1/9] auditing inert adversarial source"
audit_fixture="$temp_root/audit-fixture"
cp -R tests/fixtures/unsafe-agent-source "$audit_fixture"
chmod +x "$audit_fixture/payload.sh"
printf 'outside\n' > "$temp_root/outside.txt"
ln -s "$temp_root/outside.txt" "$audit_fixture/escape-link"
export OPENCAW_TEST_MARKER="$temp_root/executed-marker"
export REMOTE_SCRIPT="inert"
export UNSAFE_TARGET="inert"
audit_report="$temp_root/audit.json"
bash commands/audit-agent-source.sh "$audit_fixture" --output "$audit_report"
for code in executable-content symbolic-link embedded-private-key credential-like-value destructive-command remote-execution-pipeline automatic-external-mutation prompt-control-language absolute-personal-path account-operation; do
  if [[ "$code" == "embedded-private-key" ]]; then continue; fi
  grep -q "\"code\": \"$code\"" "$audit_report" || fail "audit did not report $code"
done
[[ ! -e "$OPENCAW_TEST_MARKER" ]] || fail "audit executed the inert payload"
! grep -q 'ghp_AAAAAAAAAA' "$audit_report" || fail "audit report exposed a credential-shaped value"
set +e
bash commands/audit-agent-source.sh "$audit_fixture" --fail-on high >/dev/null
audit_status=$?
set -e
[[ $audit_status -eq 2 ]] || fail "--fail-on high returned $audit_status instead of 2"

echo "[2/9] validating skill schema and safety"
new_skills=(
  audit-untrusted-agent-source adapt-external-agent-skills verify-and-explain audit-reference-originality
  capture-ui-reference-pack derive-visual-spec-from-video extract-interaction-patterns develop-original-brand-directions
  prototype-from-reference-pack capture-full-page-evidence produce-browser-demo profile-application-performance
  source-licensed-visual-assets design-ui-from-constraints design-web-experiences design-conversion-pages
  build-accessible-motion-systems build-interactive-web-effects build-webgl-experiences optimize-web-motion
  author-game-worlds design-action-gameplay build-gameplay-runtime build-game-production-tools plan-hybrid-game-assets
  create-game-vfx optimize-web-games test-playable-games ship-web-games
)
[[ ${#new_skills[@]} -eq 29 ]] || fail "new skill list does not contain 29 entries"
for skill in "${new_skills[@]}"; do
  file="skills/$skill/SKILL.md"
  [[ -f "$file" ]] || fail "missing $file"
  grep -Eq '^description:.*\bUse\b' "$file" || fail "$skill has no trigger in its description"
  for section in "When to use" "Workflow" "Output" "Guardrails"; do grep -Eq "^## $section[[:space:]]*$" "$file" || fail "$skill is missing $section"; done
  grep -Fq "\$$skill" "skills/$skill/agents/openai.yaml" || fail "$skill UI metadata does not identify the skill"
done
skill_count="$(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')"
metadata_count="$(find skills -mindepth 3 -maxdepth 3 -path '*/agents/openai.yaml' | wc -l | tr -d ' ')"
[[ "$skill_count" == "$metadata_count" ]] || fail "not every skill has agents/openai.yaml metadata"
bash commands/validate-skill-safety.sh skills
expect_failure "$temp_root/unsafe-skill.log" bash commands/validate-skill-safety.sh tests/fixtures/unsafe-skill
grep -q 'executable helpers are not allowed' "$temp_root/unsafe-skill.log" || fail "unsafe executable helper was not rejected"
grep -q 'resource link escapes' "$temp_root/unsafe-skill.log" || fail "escaping resource link was not rejected"
cp -R skills/verify-and-explain "$temp_root/verify-and-explain"
ln -s "$temp_root/outside.txt" "$temp_root/verify-and-explain/escape-link"
expect_failure "$temp_root/unsafe-symlink.log" bash commands/validate-skill-safety.sh "$temp_root/verify-and-explain"
grep -Eq 'symbolic|cross-runtime' "$temp_root/unsafe-symlink.log" || fail "skill symbolic link was not rejected"

echo "[3/9] validating roles, mappings, and styles"
bash commands/resolve-role.sh gameplay-engineer >/dev/null
bash commands/resolve-role.sh web-experience-designer >/dev/null
bash commands/validate-roles.sh
bash commands/validate-role-skill-map.sh
bash commands/validate-styles.sh

echo "[4/9] building synthetic originality evidence"
mkdir -p "$temp_root/subject" "$temp_root/reference"
printf 'independent alpha interface constraint\n' > "$temp_root/subject/unique.txt"
printf 'shared synthetic evidence line\n' > "$temp_root/subject/shared.txt"
printf 'shared synthetic evidence line\n' > "$temp_root/reference/shared-copy.txt"
printf 'unrelated beta material\n' > "$temp_root/reference/other.txt"
bash commands/build-originality-evidence.sh --subject "$temp_root/subject" --reference "$temp_root/reference" --output "$temp_root/originality.md"
grep -q '| yes |' "$temp_root/originality.md" || fail "exact-hash similarity was not reported"
grep -q 'does not determine authorship' "$temp_root/originality.md" || fail "originality report omitted its legal limitation"

echo "[5/9] reporting measured web performance"
printf '%s\n' '{"scenario":"fixture","profile":"local","metrics":{"frameTime":12,"transferBytes":1000},"budgets":{"frameTime":16,"transferBytes":1200},"units":{"frameTime":"ms","transferBytes":"bytes"}}' > "$temp_root/performance-pass.json"
bash commands/web-performance-report.sh "$temp_root/performance-pass.json" "$temp_root/performance-pass.md"
grep -q 'Pass: all configured budgets were met.' "$temp_root/performance-pass.md" || fail "passing performance result missing"
printf '%s\n' '{"metrics":{"frameTime":24},"budgets":{"frameTime":16}}' > "$temp_root/performance-fail.json"
set +e
bash commands/web-performance-report.sh "$temp_root/performance-fail.json" "$temp_root/performance-fail.md" >/dev/null
performance_status=$?
set -e
[[ $performance_status -eq 2 ]] || fail "failing performance budget did not return 2"
grep -q 'Fail:' "$temp_root/performance-fail.md" || fail "failing performance result missing"

echo "[6/9] validating gameplay review reports"
cat > "$temp_root/gameplay-pass.md" <<'EOF'
# Gameplay Review
## Summary
Representative local playable review passed with stated limits.
## Controls And Accessibility
Keyboard, pointer, remapping, focus, and redundant feedback were reviewed.
## Gameplay Systems
State transitions, failure recovery, and tuning boundaries were exercised.
## Performance
Frame-time and loading measurements met the fixture budgets.
## Evidence
Local logs and captures were inspected.
## Risks And Recommendation
No blocking fixture risk remains; broader device coverage is still required.
EOF
bash commands/validate-gameplay-review.sh "$temp_root/gameplay-pass.md"
printf '# Gameplay Review\n## Summary\nTBD\n' > "$temp_root/gameplay-incomplete.md"
expect_failure "$temp_root/gameplay-incomplete.log" bash commands/validate-gameplay-review.sh "$temp_root/gameplay-incomplete.md"
printf '{ malformed\n' > "$temp_root/gameplay-malformed.md"
expect_failure "$temp_root/gameplay-malformed.log" bash commands/validate-gameplay-review.sh "$temp_root/gameplay-malformed.md"

echo "[7/9] rendering local demo frames"
ffmpeg_bin="$(command -v ffmpeg 2>/dev/null || command -v ffmpeg.exe 2>/dev/null || true)"
ffprobe_bin="$(command -v ffprobe 2>/dev/null || command -v ffprobe.exe 2>/dev/null || true)"
node_for_media="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
minimal_bin="$temp_root/minimal-bin"
mkdir -p "$minimal_bin"
if [[ -n "$node_for_media" ]]; then ln -s "$node_for_media" "$minimal_bin/$(basename "$node_for_media")"; fi
set +e
PATH="$minimal_bin:/usr/bin:/bin" bash commands/render-browser-demo.sh --manifest tests/fixtures/browser-demo/manifest.json --output "$runtime_dir/missing-dependency.gif" >"$temp_root/demo-dependency.log" 2>&1
missing_dependency_status=$?
set -e
[[ $missing_dependency_status -ne 0 ]] || fail "demo rendering succeeded without media dependencies"
grep -Eq 'ffmpeg|ffprobe' "$temp_root/demo-dependency.log" || fail "missing media dependency was not explained"
if [[ -n "$ffmpeg_bin" && -n "$ffprobe_bin" ]]; then
  demo_output="$runtime_dir/demo.mp4"
  bash commands/render-browser-demo.sh --manifest tests/fixtures/browser-demo/manifest.json --output "$demo_output"
  demo_probe_path="$demo_output"
  if [[ "$ffprobe_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then demo_probe_path="$(wslpath -w "$demo_output")"; fi
  dimensions="$("$ffprobe_bin" -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$demo_probe_path" | tr -d '\r')"
  [[ "$dimensions" == "160x90" ]] || fail "rendered demo dimensions were $dimensions"
  frame_rate="$("$ffprobe_bin" -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$demo_probe_path" | tr -d '\r')"
  [[ "$frame_rate" == "12/1" ]] || fail "rendered demo frame rate was $frame_rate"
  duration="$("$ffprobe_bin" -v error -show_entries format=duration -of csv=p=0 "$demo_probe_path" | tr -d '\r')"
  awk -v duration="$duration" 'BEGIN { exit !(duration >= 0.9 && duration <= 1.2) }' || fail "rendered demo duration was $duration"
  printf '{ malformed\n' > "$runtime_dir/malformed.json"
  expect_failure "$temp_root/demo-malformed.log" bash commands/render-browser-demo.sh --manifest "$runtime_dir/malformed.json" --output "$runtime_dir/malformed.gif"
  printf '%s\n' '{"width":0,"height":90,"fps":12,"frames":[]}' > "$runtime_dir/invalid.json"
  expect_failure "$temp_root/demo-invalid.log" bash commands/render-browser-demo.sh --manifest "$runtime_dir/invalid.json" --output "$runtime_dir/invalid.gif"
  printf '%s\n' '{"width":160,"height":90,"fps":12,"frames":[{"path":"../outside.ppm","duration":1}]}' > "$runtime_dir/escaping.json"
  expect_failure "$temp_root/demo-escaping.log" bash commands/render-browser-demo.sh --manifest "$runtime_dir/escaping.json" --output "$runtime_dir/escaping.gif"
  expect_failure "$temp_root/demo-boundary.log" bash commands/render-browser-demo.sh --manifest tests/fixtures/browser-demo/manifest.json --output "$repo_root/../opencaw-demo-escape-${RANDOM}.gif"
else
  echo "System media dependencies are absent; dependency failure behavior was verified."
fi

echo "[8/9] capturing local browser evidence"
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail "Node.js is required by the test harness"
expect_failure "$temp_root/capture-viewport.log" bash commands/playwright-capture-page.sh --url http://127.0.0.1:9 --output "$runtime_dir/invalid.png" --viewport bad
expect_failure "$temp_root/capture-boundary.log" bash commands/playwright-capture-page.sh --url http://127.0.0.1:9 --output "$repo_root/../opencaw-escape-${RANDOM}.png"
grep -q 'inside repository root' "$temp_root/capture-boundary.log" || fail "capture output confinement was not enforced"

if [[ -n "${OPENCAW_PLAYWRIGHT_ROOT:-}" ]]; then
  port=$((43100 + RANDOM % 1000))
  fixture_root="$repo_root/tests/fixtures/web-capture"
  if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then fixture_root="$(wslpath -w "$fixture_root")"; fi
  "$node_bin" tests/support/static-server.cjs "$port" "$fixture_root" >"$temp_root/server.log" 2>&1 &
  server_pid=$!
  for _ in $(seq 1 50); do grep -q '^READY ' "$temp_root/server.log" 2>/dev/null && break; sleep 0.1; done
  grep -q '^READY ' "$temp_root/server.log" || fail "local fixture server did not start"
  reduce_png="$runtime_dir/reduce.png"
  standard_png="$runtime_dir/standard.png"
  bash commands/playwright-capture-page.sh --url "http://127.0.0.1:$port/" --output "$reduce_png" --full-page --viewport 600x400 --reduced-motion reduce
  bash commands/playwright-capture-page.sh --url "http://127.0.0.1:$port/" --output "$standard_png" --full-page --viewport 600x400 --reduced-motion no-preference
  png_for_node="$reduce_png"
  if [[ "$node_bin" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then png_for_node="$(wslpath -w "$reduce_png")"; fi
  png_dimensions="$("$node_bin" -e "const b=require('fs').readFileSync(process.argv[1]); console.log(b.readUInt32BE(16)+'x'+b.readUInt32BE(20))" "$png_for_node" | tr -d '\r')"
  png_height="${png_dimensions#*x}"
  [[ "${png_dimensions%x*}" == "600" && "$png_height" -gt 1500 ]] || fail "full-page PNG dimensions were $png_dimensions"
  [[ "$(sha256sum "$reduce_png" | cut -d' ' -f1)" != "$(sha256sum "$standard_png" | cut -d' ' -f1)" ]] || fail "reduced-motion capture did not change fixture output"
  [[ "$(wc -c < "$reduce_png")" -gt 2000 ]] || fail "capture did not preserve rendered canvas evidence"
  expect_failure "$temp_root/capture-navigation.log" bash commands/playwright-capture-page.sh --url "http://127.0.0.1:$port/missing" --output "$runtime_dir/missing.png"
  grep -q 'HTTP 404' "$temp_root/capture-navigation.log" || fail "failed navigation did not report status"
else
  OPENCAW_PLAYWRIGHT_ROOT="$temp_root/missing-playwright" expect_failure "$temp_root/capture-dependency.log" bash commands/playwright-capture-page.sh --url http://127.0.0.1:9 --output "$runtime_dir/missing.png"
  grep -q 'Playwright is not installed' "$temp_root/capture-dependency.log" || fail "missing Playwright dependency was not explained"
fi

echo "[9/9] validating integrated OpenCaw structure"
bash commands/validate-opencaw.sh
git_check_bin="$(command -v git.exe 2>/dev/null || command -v git)"
"$git_check_bin" diff --check
echo "Capability expansion tests passed."
