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
for skill in "${skills[@]}"; do require_text '.roles/ROLE_SKILL_MAP.json' "\"$skill\""; done
for command in "${commands[@]}"; do require_file "$command"; [[ -x "$command" ]] || fail "$command is not executable"; bash -n "$command"; done

echo "[2/8] checking deterministic production brief"
brief_one="$(commands/print-blender-production-brief.sh prop engine --profile static-asset)"
brief_two="$(commands/print-blender-production-brief.sh prop engine --profile static-asset)"
[[ "$brief_one" == "$brief_two" ]] || fail "production brief is not deterministic"
grep -Fq -- '- Supported Blender: 4.5 LTS' <<<"$brief_one" || fail "brief does not pin Blender 4.5 LTS"
expect_failure bad-brief commands/print-blender-production-brief.sh prop engine --profile unsupported

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
if [[ "${1:-}" == "--version" ]]; then echo 'Blender 4.5.3'; exit 0; fi
printf '%s\n' "$@" >"$FAKE_BLENDER_ARGS"
output=''
while [[ $# -gt 0 ]]; do if [[ "$1" == '--output' ]]; then output="$2"; break; fi; shift; done
[[ -n "$output" ]]
cp "$FAKE_BLENDER_REPORT" "$output"
EOF
chmod +x "$fake_blender"
export FAKE_BLENDER_ARGS="$args_log" FAKE_BLENDER_REPORT="$valid_report"
dry_output="$fixture_root/dry.json"
commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$dry_output" --dry-run >/dev/null
[[ ! -e "$dry_output" ]] || fail "inspector dry run mutated output"
report_output="$fixture_root/scene-report.json"
commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$report_output" >/dev/null
require_file "$report_output"
for flag in --background --factory-startup --disable-autoexec --offline-mode --python-exit-code; do grep -Fxq -- "$flag" "$args_log" || fail "inspector omitted $flag"; done
grep -Fxq -- '4' "$args_log" || fail "inspector omitted nonzero Python exit code"
expect_failure overwrite commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$report_output"
commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender" --output "$report_output" --replace >/dev/null
expect_failure missing-binary commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$temp_root/missing"
bad_blender="$temp_root/bad-blender"; sed 's/Blender 4.5.3/Blender 4.4.9/' "$fake_blender" >"$bad_blender"; chmod +x "$bad_blender"
expect_failure wrong-version commands/inspect-blender-scene.sh "$fixture_root/scene.blend" --root "$fixture_root" --profile static-asset --blender "$bad_blender"
ln -s "$fixture_root/scene.blend" "$fixture_root/linked.blend"
expect_failure scene-symlink commands/inspect-blender-scene.sh "$fixture_root/linked.blend" --root "$fixture_root" --profile static-asset --blender "$fake_blender"
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
  scan_command=(rg -n -i 'https?://|[A-Za-z]:\\Users\\|api[_ -]?key|automatic publication')
else
  scan_command=(grep -R -E -n -i 'https?://|[A-Za-z]:\\Users\\|api[_ -]?key|automatic publication')
fi
if "${scan_command[@]}" "${skills[@]/#/skills/}" .roles/arts/blender-production-artist commands/lib/inspect-blender-scene.py; then fail "Blender capability files contain an external identity, personal path, credential, or publication automation"; fi

echo "[8/8] checking generated and structural validators"
bash commands/generate-role-skill-map.sh --check >/dev/null
bash commands/validate-role-skill-map.sh >/dev/null
bash commands/validate-roles.sh >/dev/null
bash commands/validate-skill-safety.sh skills/direct-blender-production >/dev/null

echo "Blender art capability tests passed."
