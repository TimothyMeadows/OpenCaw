#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() { echo "FAIL: $*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || fail "missing required file: $1"; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 is missing required text: $2"; }
expect_failure() { local name="$1"; shift; if "$@" >"$temp_root/$name.log" 2>&1; then fail "accepted invalid fixture: $name"; fi; }

skills=(
  direct-blender-production model-blender-assets prepare-blender-uvs-and-textures
  author-blender-materials-and-lookdev build-procedural-blender-scenes
  rig-and-animate-blender-actors simulate-blender-effects light-and-frame-blender-scenes
  render-and-composite-blender-output optimize-and-export-blender-assets review-blender-deliverables
)
commands=(
  commands/print-blender-production-brief.sh commands/inspect-blender-scene.sh
  commands/validate-blender-scene-report.sh commands/validate-blender-python.sh
)

temp_root="$(mktemp -d "$repo_root/.test-blender-art.XXXXXX")"
trap 'rm -rf -- "$temp_root"' EXIT
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || fail "Node.js is required for Blender capability fixtures"
node_path() { if [[ "$node_bin" == *.exe ]]; then wslpath -w "$1"; else printf '%s\n' "$1"; fi; }

echo "[1/8] checking skills, references, role, and mappings"
require_file '.styles/.pipelines/blender/PIPELINE.md'
require_text '.styles/.pipelines/INDEX.md' '`BLENDER`'
require_text '.styles/.pipelines/blender/PIPELINE.md' 'Blender 4.5 LTS'
require_text '.styles/.pipelines/blender/PIPELINE.md' '`direct-blender-production`'
for skill in "${skills[@]}"; do
  require_file "skills/$skill/SKILL.md"
  require_file "skills/$skill/agents/openai.yaml"
  require_text "skills/$skill/agents/openai.yaml" "\$$skill"
  grep -Eq '\]\(references/[^/)]+\.md\)' "skills/$skill/SKILL.md" || fail "$skill has no one-level reference"
done
role='.roles/arts/blender-production-artist/ROLE.md'
require_file "$role"
for alias in blender-artist blender-modeler blender-technical-artist 3d-production-artist; do require_text "$role" "  - $alias"; done
require_text '.roles/ROLE_SKILL_MAP.json' '"arts/blender-production-artist"'
require_text '.roles/ROLE_SKILL_MAP.json' '"select-art-pipeline"'
require_text '.roles/ROLE_SKILL_MAP.json' '"commands/resolve-art-pipeline.sh"'
for skill in "${skills[@]}"; do require_text '.roles/ROLE_SKILL_MAP.json' "\"$skill\""; done
for command in "${commands[@]}"; do require_file "$command"; [[ -x "$command" ]] || fail "$command is not executable"; bash -n "$command"; done
style_project="$temp_root/style-project"
mkdir -p "$style_project/.opencaw/.cache/tasks/blender-pipeline-test"
OPENCAW_PROJECT_ROOT="$style_project" bash commands/generate-style.sh --pipeline blender --allow-pipeline PROOF_TO_MODEL CEL_SHADED_COMIC >/dev/null
OPENCAW_PROJECT_ROOT="$style_project" bash commands/validate-style-contract.sh "$style_project/STYLE.md" >/dev/null
grep -A1 '^Primary OpenCaw art pipeline:' "$style_project/STYLE.md" | grep -Fxq -- '- BLENDER' || fail "blender alias did not select BLENDER"
selection="$(OPENCAW_PROJECT_ROOT="$style_project" bash commands/resolve-art-pipeline.sh --style "$style_project/STYLE.md" --override bpy --json)"
grep -Fq '"pipeline": "BLENDER"' <<<"$selection" || fail "bpy override did not resolve to BLENDER"

echo "[2/8] checking deterministic production brief"
brief_one="$(commands/print-blender-production-brief.sh prop engine --profile static-asset)"
brief_two="$(commands/print-blender-production-brief.sh prop engine --profile static-asset)"
[[ "$brief_one" == "$brief_two" ]] || fail "production brief is not deterministic"
grep -Fq -- '- Supported Blender: 4.5 LTS' <<<"$brief_one" || fail "brief does not pin Blender 4.5 LTS"
expect_failure bad-brief commands/print-blender-production-brief.sh prop engine --profile unsupported
for profile in static-asset rigged-actor procedural-scene render-scene simulation; do
  first="$(commands/print-blender-production-brief.sh 'subject with spaces' 'selected engine' --profile "$profile")"
  second="$(commands/print-blender-production-brief.sh 'subject with spaces' 'selected engine' --profile "$profile")"
  [[ "$first" == "$second" ]] || fail "$profile brief is not deterministic"
  grep -Fq -- '- Asset kind: subject with spaces' <<<"$first" || fail "brief lost the requested subject"
  grep -Fq -- "- Profile: $profile" <<<"$first" || fail "brief lost the selected profile"
  grep -Fq -- '- Applicability: mark unused fields not applicable with a reason; required unavailable work stays blocked/not-run' <<<"$first" || fail "brief treats every discovery field as mandatory"
  grep -Fq -- '- Selected ENGINE.md and importer/shader versions:' <<<"$first" || fail "brief omitted engine discovery"
  grep -Fq -- '- Observed features, inferred hidden structure and uncertainties:' <<<"$first" || fail "brief conflates observation and inference"
  grep -Fq -- '- Blocked/not-run checks and remaining defects:' <<<"$first" || fail "brief omitted incomplete verification"
  case "$profile" in
    static-asset) expected='Mechanism pivots, contact/clearance and concealed surfaces:' ;;
    rigged-actor) expected='Skinned/articulated/rigid profile and actual model readiness:' ;;
    procedural-scene) expected='Module dimensions, grid, pivots and corner/junction coverage:' ;;
    render-scene) expected='Required passes, alpha interpretation and compositor ownership:' ;;
    simulation) expected='Cloth density, pin gradients, collision separation and settling:' ;;
  esac
  grep -Fq -- "$expected" <<<"$first" || fail "$profile omitted its production discovery fields"
  if [[ "$profile" != simulation ]]; then
    ! grep -Fq -- '- Cloth density, pin gradients, collision separation and settling:' <<<"$first" || fail "cloth-specific discovery leaked into $profile"
  fi
done
expect_failure missing-brief-profile commands/print-blender-production-brief.sh prop engine
expect_failure duplicate-brief-profile commands/print-blender-production-brief.sh prop engine --profile static-asset --profile simulation
expect_failure multiline-brief-subject commands/print-blender-production-brief.sh $'prop\nforged field' engine --profile static-asset
expect_failure cr-brief-target commands/print-blender-production-brief.sh prop $'engine\rforged field' --profile static-asset

echo "[3/8] building scene-report fixtures"
fixture_root="$temp_root/project"
mkdir -p "$fixture_root/assets" "$fixture_root/.blender-cache"
printf 'fixture blend\n' >"$fixture_root/scene.blend"
printf 'texture\n' >"$fixture_root/assets/texture.bin"
printf 'cache\n' >"$fixture_root/.blender-cache/sim"
hash_file() { sha256sum "$1" | awk '{print $1}'; }
scene_hash="$(hash_file "$fixture_root/scene.blend")"
texture_hash="$(hash_file "$fixture_root/assets/texture.bin")"
valid_report="$temp_root/valid.json"
cat >"$valid_report" <<EOF
{
  "schemaVersion": "opencaw-blender-scene/v1",
  "profile": "static-asset",
  "blenderVersion": "4.5.3",
  "source": {"path": "scene.blend", "sha256": "$scene_hash"},
  "units": {"system": "METRIC", "scaleLength": 1},
  "render": {"engine": "BLENDER_EEVEE_NEXT", "resolutionX": 1920, "resolutionY": 1080, "fps": 24, "activeCamera": "object-camera"},
  "totals": {"collections": 1, "objects": 3, "meshes": 1, "materials": 1, "images": 1, "armatures": 1, "actions": 1, "nodeGroups": 1, "modifiers": 1, "simulations": 1, "dependencies": 1, "cameras": 1},
  "collections": [{"id": "collection-main", "name": "Main", "parentId": null}],
  "objects": [
    {"id": "object-mesh", "name": "Mesh", "type": "MESH", "parentId": null, "collectionIds": ["collection-main"], "meshId": "mesh-main", "materialIds": ["material-main"], "armatureId": null, "actionIds": [], "nodeGroupIds": ["node-main"], "modifierIds": ["modifier-main"], "transform": {"location": [0,0,0], "rotation": [0,0,0], "scale": [1,1,1]}},
    {"id": "object-rig", "name": "Rig", "type": "ARMATURE", "parentId": null, "collectionIds": ["collection-main"], "meshId": null, "materialIds": [], "armatureId": "armature-main", "actionIds": ["action-main"], "nodeGroupIds": [], "modifierIds": [], "transform": {"location": [0,0,0], "rotation": [0,0,0], "scale": [1,1,1]}},
    {"id": "object-camera", "name": "Camera", "type": "CAMERA", "parentId": null, "collectionIds": ["collection-main"], "meshId": null, "materialIds": [], "armatureId": null, "actionIds": [], "nodeGroupIds": [], "modifierIds": [], "transform": {"location": [0,-5,2], "rotation": [1.2,0,0], "scale": [1,1,1]}}
  ],
  "meshes": [{"id": "mesh-main", "name": "MeshData", "objectId": "object-mesh", "vertices": 8, "edges": 12, "faces": 6, "triangles": 12, "materialIds": ["material-main"], "uvLayers": ["UVMap"], "invalidTopology": {"nonManifoldEdges": 0, "looseVertices": 0, "zeroAreaFaces": 0}}],
  "materials": [{"id": "material-main", "name": "Material", "imageIds": ["image-main"], "nodeGroupIds": ["node-main"]}],
  "images": [{"id": "image-main", "name": "Texture", "path": "assets/texture.bin", "packed": false, "exists": true, "sha256": "$texture_hash"}],
  "armatures": [{"id": "armature-main", "name": "RigData", "objectId": "object-rig", "skeletonId": "skeleton-v1"}],
  "actions": [{"id": "action-main", "name": "Idle", "armatureId": "armature-main", "frameStart": 1, "frameEnd": 24}],
  "nodeGroups": [{"id": "node-main", "name": "Assembly", "type": "GeometryNodeTree", "realizationPolicy": "realize-for-export"}],
  "modifiers": [{"id": "modifier-main", "name": "Geometry", "objectId": "object-mesh", "type": "NODES", "nodeGroupId": "node-main"}],
  "simulations": [{"id": "simulation-main", "name": "Cloth", "type": "CLOTH", "objectId": "object-mesh", "cache": {"required": true, "path": ".blender-cache/sim", "baked": true, "resolved": true}}],
  "dependencies": [{"id": "dependency-texture", "kind": "image", "path": "assets/texture.bin", "packed": false, "exists": true, "insideRoot": true, "sha256": "$texture_hash"}],
  "findings": [{"severity": "warning", "code": "fixture-warning", "subject": "object-mesh", "message": "Reviewed fixture warning."}]
}
EOF

make_variant() {
  local kind="$1" destination="$2"
  "$node_bin" - "$(node_path "$valid_report")" "$(node_path "$destination")" "$kind" <<'NODE'
const fs=require('fs'); const [source,destination,kind]=process.argv.slice(2); const d=JSON.parse(fs.readFileSync(source,'utf8'));
switch(kind) {
  case 'schema': d.schemaVersion='opencaw-blender-scene/v2'; break;
  case 'version': d.blenderVersion='4.4.9'; break;
  case 'duplicate-id': d.objects[1].id=d.objects[0].id; break;
  case 'duplicate-name': d.objects[1].name=d.objects[0].name; break;
  case 'parent': d.objects[0].parentId='object-missing'; break;
  case 'collection': d.objects[0].collectionIds=['collection-missing']; break;
  case 'material': d.objects[0].materialIds=['material-missing']; break;
  case 'action': d.objects[1].actionIds=['action-missing']; break;
  case 'node': d.modifiers[0].nodeGroupId='node-missing'; break;
  case 'totals': d.totals.objects=99; break;
  case 'nonfinite': d.objects[0].transform.scale[0]='NaN'; break;
  case 'absolute': d.source.path='/outside.blend'; break;
  case 'escape': d.dependencies[0].path='../outside.bin'; break;
  case 'hash': d.source.sha256='bad'; break;
  case 'missing-dependency': d.dependencies[0].path='assets/missing.bin'; d.dependencies[0].exists=false; d.dependencies[0].sha256=null; break;
  case 'render-camera': d.profile='render-scene'; d.render.activeCamera=null; break;
  case 'rig': d.profile='rigged-actor'; d.armatures=[]; d.actions=[]; d.totals.armatures=0; d.totals.actions=0; d.objects[1].armatureId=null; d.objects[1].actionIds=[]; break;
  case 'procedural': d.profile='procedural-scene'; d.nodeGroups[0].realizationPolicy=null; break;
  case 'simulation-cache': d.profile='simulation'; d.simulations[0].cache.baked=false; d.simulations[0].cache.resolved=false; break;
  case 'topology': d.meshes[0].invalidTopology.nonManifoldEdges=1; break;
  case 'error-finding': d.findings.push({severity:'error',code:'blocked',subject:'object-mesh',message:'Blocked fixture.'}); break;
  default: throw new Error(`unknown fixture ${kind}`);
}
fs.writeFileSync(destination, JSON.stringify(d,null,2)+'\n');
NODE
}

echo "[4/8] validating all profiles and rejecting malformed reports"
for profile in static-asset rigged-actor procedural-scene render-scene simulation; do
  profile_report="$temp_root/$profile.json"
  "$node_bin" - "$(node_path "$valid_report")" "$(node_path "$profile_report")" "$profile" <<'NODE'
const fs=require('fs'); const [source,destination,profile]=process.argv.slice(2); const d=JSON.parse(fs.readFileSync(source)); d.profile=profile; fs.writeFileSync(destination,JSON.stringify(d,null,2)+'\n');
NODE
  commands/validate-blender-scene-report.sh "$profile_report" --root "$fixture_root" --require-clean >/dev/null
done
for kind in schema version duplicate-id duplicate-name parent collection material action node totals nonfinite absolute escape hash missing-dependency render-camera rig procedural; do
  variant="$temp_root/$kind.json"; make_variant "$kind" "$variant"; expect_failure "$kind" commands/validate-blender-scene-report.sh "$variant" --root "$fixture_root"
done
for kind in simulation-cache topology error-finding; do
  variant="$temp_root/$kind.json"; make_variant "$kind" "$variant"; expect_failure "$kind-clean" commands/validate-blender-scene-report.sh "$variant" --root "$fixture_root" --require-clean
done

echo "[5/8] exercising safe fake-Blender inspection"
fake_blender="$temp_root/fake-blender"
args_log="$temp_root/blender-args.log"
cat >"$fake_blender" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then echo "Blender ${FAKE_BLENDER_VERSION:-4.5.3}"; exit 0; fi
printf '%s\n' "$@" >"$FAKE_BLENDER_ARGS"
output=''
while [[ $# -gt 0 ]]; do if [[ "$1" == '--output' ]]; then output="$2"; break; fi; shift; done
[[ -n "$output" ]]
cp "$FAKE_BLENDER_REPORT" "$output"
EOF
chmod +x "$fake_blender"
export FAKE_BLENDER_ARGS="$args_log" FAKE_BLENDER_REPORT="$valid_report"
if [[ "${OS:-}" == Windows_NT ]]; then
  # The standalone native runner executes native Windows programs. Build an
  # owned test apphost instead of treating a Bash script as a Win32 executable.
  fake_project="$temp_root/fake-native"
  mkdir -p "$fake_project"
  cat >"$fake_project/Fixture.csproj" <<'XML'
<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>
XML
  cat >"$fake_project/Program.cs" <<'CS'
if (args.SequenceEqual(new[]{"--version"})) { Console.WriteLine("Blender " + (Environment.GetEnvironmentVariable("FAKE_BLENDER_VERSION") ?? "4.5.3")); return; }
File.WriteAllLines(Environment.GetEnvironmentVariable("FAKE_BLENDER_ARGS")!, args);
var index = Array.IndexOf(args,"--output");
if (index < 0) throw new Exception("Fixture requires --output");
File.Copy(Environment.GetEnvironmentVariable("FAKE_BLENDER_REPORT")!,args[index+1],true);
CS
  dotnet build "$fake_project/Fixture.csproj" -o "$fake_project/out" --nologo >/dev/null
  fake_blender="$fake_project/out/Fixture.exe"
  export FAKE_BLENDER_ARGS="$(node_path "$args_log")" FAKE_BLENDER_REPORT="$(node_path "$valid_report")"
fi
dry_output="$fixture_root/dry.json"
commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$dry_output" --dry-run >/dev/null
[[ ! -e "$dry_output" ]] || fail "inspector dry run mutated output"
report_output="$fixture_root/scene-report.json"
commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$report_output" >/dev/null
require_file "$report_output"
for flag in --background --factory-startup --disable-autoexec --offline-mode --python-exit-code; do grep -Fxq -- "$flag" "$args_log" || fail "inspector omitted $flag"; done
grep -Fxq -- '1' "$args_log" || fail "inspector omitted the pinned Bubo Python exit code"
expect_failure overwrite commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$report_output"
commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$report_output" --replace >/dev/null
expect_failure missing-binary commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$temp_root/missing"
export FAKE_BLENDER_VERSION='4.4.9'
expect_failure wrong-version commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender"
unset FAKE_BLENDER_VERSION
if ln -s "$fixture_root/scene.blend" "$fixture_root/linked.blend" && [[ -L "$fixture_root/linked.blend" ]]; then
  expect_failure scene-symlink commands/inspect-blender-scene.sh "$fixture_root/linked.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender"
else
  echo 'NOT RUN: file-symlink privilege unavailable; native host boundary suites cover actual Windows junctions.'
fi
expect_failure output-escape commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$temp_root/outside.json"

echo "[6/8] exercising restricted Blender Python validation"
allowed="$fixture_root/allowed.py"
cat >"$allowed" <<'PY'
import bpy
import json
import math
bpy.context.scene["review_state"] = json.dumps({"angle": math.pi})
PY
first_hash="$(commands/validate-blender-python.sh "$allowed" --root "$fixture_root")"
[[ "$first_hash" =~ ^[a-f0-9]{64}$ ]] || fail "Python validator did not emit a SHA-256"
render_script="$fixture_root/render.py"
cat >"$render_script" <<'PY'
import bpy
bpy.context.scene.render.filepath = "renders/frame.png"
bpy.ops.render.render(write_still=True)
PY
commands/validate-blender-python.sh "$render_script" --root "$fixture_root" --allow-output renders/frame.png >/dev/null
expect_failure undeclared-output commands/validate-blender-python.sh "$render_script" --root "$fixture_root"
declare -A prohibited
prohibited[import]='import subprocess'
prohibited[network]='import socket'
prohibited[dynamic]='exec("pass")'
prohibited[addon]='import bpy; bpy.ops.preferences.addon_install(filepath="addon.py")'
prohibited[preference]='import bpy; bpy.context.preferences.active_section = "ADDONS"'
prohibited[delete]='from pathlib import Path; Path("assets/texture.bin").unlink()'
prohibited[escape]='from pathlib import Path; Path("../outside").write_text("x")'
prohibited[nonliteral]='from pathlib import Path; target="renders/x"; Path(target).write_text("x")'
prohibited[library]='import bpy; bpy.data.libraries.load("missing.blend")'
for name in "${!prohibited[@]}"; do printf '%s\n' "${prohibited[$name]}" >"$fixture_root/$name.py"; expect_failure "python-$name" commands/validate-blender-python.sh "$fixture_root/$name.py" --root "$fixture_root" --allow-output renders/x; done
printf '\n# exact content changed\n' >>"$allowed"
second_hash="$(commands/validate-blender-python.sh "$allowed" --root "$fixture_root")"
[[ "$first_hash" != "$second_hash" ]] || fail "script hash did not change after content mutation"

echo "[7/8] checking routing, catalogs, and safe content"
require_text skills/plan-hybrid-game-assets/SKILL.md '`direct-blender-production`'
require_text skills/prepare-game-art-handoff/SKILL.md '`optimize-and-export-blender-assets`'
require_text skills/prepare-rigged-runtime-actors/SKILL.md '`rig-and-animate-blender-actors`'
require_text skills/create-game-vfx/SKILL.md '`simulate-blender-effects`'
require_text skills/maintain-art-style-contract/SKILL.md '`author-blender-materials-and-lookdev`'
for skill in "${skills[@]}"; do require_text skills/INDEX.md "\`$skill\`"; done
if command -v rg >/dev/null 2>&1; then
  scan_command=(rg -n -i '[A-Za-z]:\\Users\\|api[_ -]?key|automatic publication')
else
  scan_command=(grep -R -E -n -i '[A-Za-z]:\\Users\\|api[_ -]?key|automatic publication')
fi
if "${scan_command[@]}" "${skills[@]/#/skills/}" .roles/arts/blender-production-artist runtime/bubo/resources/blender/inspect-blender-scene.py; then fail "Blender capability files contain an external identity, personal path, credential, or publication automation"; fi

# Versioned primary documentation is useful research, not an imported identity
# or permission to install/execute content. Keep all other URLs rejected here.
"$node_bin" - "${skills[@]/#/skills/}" .roles/arts/blender-production-artist runtime/bubo/resources/blender/inspect-blender-scene.py <<'NODE'
const fs = require('fs');
const path = require('path');
function allowedDocumentation(value) {
  let url;
  try { url = new URL(value); } catch { return false; }
  if (url.protocol !== 'https:' || url.username || url.password || url.port) return false;
  if (url.hostname === 'docs.blender.org') return /^\/(?:manual\/en\/4\.5|api\/4\.5)\//.test(url.pathname);
  if (url.hostname === 'developer.blender.org') return url.pathname.startsWith('/docs/release_notes/4.1/');
  return url.hostname === 'registry.khronos.org' && url.pathname.startsWith('/glTF/specs/2.0/');
}
const controls = [
  ['https://docs.blender.org/manual/en/4.5/physics/cloth/index.html', true],
  ['https://docs.blender.org/api/4.5/bpy.types.BevelModifier.html', true],
  ['https://developer.blender.org/docs/release_notes/4.1/modeling/', true],
  ['https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials', true],
  ['http://docs.blender.org/manual/en/4.5/physics/cloth/index.html', false],
  ['https://docs.blender.org.example.invalid/manual/en/4.5/', false],
  ['HTTPS://example.invalid/payload', false],
  ['https://docs.blender.org@example.invalid/manual/en/4.5/', false],
  ['https://user:pass@docs.blender.org/manual/en/4.5/', false],
  ['https://docs.blender.org:9876/manual/en/4.5/', false],
  ['https://docs.blender.org/download/addon.py', false],
  ['https://docs.blender.org/manual/en/4.5/../../download/addon.py', false],
  ['https://registry.khronos.org/downloads/helper.sh', false]
];
function unapprovedURLs(text) {
  return [...text.matchAll(/https?:\/\/[^\s<>"'`)]+/gi)]
    .map(match => match[0]).filter(value => !allowedDocumentation(value));
}
for (const [value, expected] of controls) {
  const rejected = unapprovedURLs(`Reference: (${value})`);
  if (rejected.length !== (expected ? 0 : 1) || (!expected && rejected[0] !== value)) {
    throw new Error(`documentation URL extraction/rejection control failed: ${value}`);
  }
}
function scan(file) {
  const stat = fs.lstatSync(file);
  if (stat.isSymbolicLink()) throw new Error(`unexpected linked capability: ${file}`);
  if (stat.isDirectory()) {
    for (const name of fs.readdirSync(file)) scan(path.join(file, name));
    return;
  }
  const text = fs.readFileSync(file, 'utf8');
  for (const value of unapprovedURLs(text)) {
    throw new Error(`unapproved external URL in ${file}: ${value}`);
  }
}
for (const file of process.argv.slice(2)) scan(file);
NODE

echo "[8/8] checking generated and structural validators"
bash commands/generate-role-skill-map.sh --check >/dev/null
bash commands/validate-role-skill-map.sh >/dev/null
bash commands/validate-roles.sh >/dev/null
bash commands/validate-skill-safety.sh skills/direct-blender-production >/dev/null

echo "Blender art capability tests passed."
