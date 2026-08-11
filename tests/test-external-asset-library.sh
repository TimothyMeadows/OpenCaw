#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
runtime_dir="$(mktemp -d "$repo_root/tests/.external-assets-runtime-XXXXXX")"
project="$runtime_dir/project"
library="$runtime_dir/External Library"
mkdir -p "$project/.ai/tasks/library-test" "$library/characters/Hero Rig/textures" "$library/props" "$library/bad-bundle"

cleanup() {
  local resolved
  resolved="$(cd "$(dirname "$runtime_dir")" && pwd -P)/$(basename "$runtime_dir")"
  case "$resolved" in "$repo_root"/tests/.external-assets-runtime-*) rm -rf -- "$resolved" ;; esac
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
contains_exact_line() {
  sed 's/\r$//' "$2" | grep -Fqx -- "$1"
}
hash_file() { sha256sum "$1" | awk '{print $1}'; }

printf 'blend fixture\n' > "$library/characters/Hero Rig/hero.blend"
printf 'walk animation\n' > "$library/characters/Hero Rig/walk.bvh"
printf 'texture fixture\n' > "$library/characters/Hero Rig/textures/hero.png"
printf 'crate model\n' > "$library/props/crate.glb"
printf 'not a model\n' > "$library/props/readme.txt"
printf 'bad bundle model\n' > "$library/bad-bundle/model.glb"
ln -s ../props/crate.glb "$library/linked.glb"
ln -s ../props/crate.glb "$library/bad-bundle/linked.glb"
source_hash_before="$(hash_file "$library/props/crate.glb")"
source_stat_before="$(stat -c '%Y:%s' "$library/props/crate.glb")"

echo '[1/7] validating optional generation, preservation, replacement, and clearing'
project_command bash commands/generate-style.sh CEL_SHADED_COMIC >/dev/null
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
! grep -Fq '## External Asset Libraries' "$project/STYLE.md" || fail 'default generation added an external library section'
grep -Fq 'EXTERNAL_ASSET_LIBRARY_COUNT=0' < <(project_command bash commands/list-external-asset-libraries.sh) || fail 'unconfigured library count was not zero'

project_command bash commands/generate-style.sh \
  --asset-library "studio=$library" \
  --asset-library 'windows=C:\Shared Assets\Models' \
  --asset-library 'unc=\\server\share\models' \
  CEL_SHADED_COMIC >/dev/null
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
contains_exact_line "- studio: \`$library\`" "$project/STYLE.md" || fail 'POSIX library was not generated'
contains_exact_line '- windows: `C:\Shared Assets\Models`' "$project/STYLE.md" || fail 'Windows library was not generated'
contains_exact_line '- unc: `\\server\share\models`' "$project/STYLE.md" || fail 'UNC library was not generated'
list_json="$(project_command bash commands/list-external-asset-libraries.sh --json)"
grep -Fq '"id": "studio"' <<< "$list_json" || fail 'JSON list omitted studio'
grep -Fq '"readOnly": true' <<< "$list_json" || fail 'JSON list omitted read-only state'

project_command bash commands/generate-style.sh --pipeline CSS3 CEL_SHADED_COMIC >/dev/null
contains_exact_line "- studio: \`$library\`" "$project/STYLE.md" || fail 'style regeneration did not preserve studio'
contains_exact_line '- windows: `C:\Shared Assets\Models`' "$project/STYLE.md" || fail 'style regeneration did not preserve windows'
contains_exact_line '- unc: `\\server\share\models`' "$project/STYLE.md" || fail 'style regeneration did not preserve UNC path'

project_command bash commands/generate-style.sh --asset-library "studio=$library" CEL_SHADED_COMIC >/dev/null
contains_exact_line "- studio: \`$library\`" "$project/STYLE.md" || fail 'replacement omitted studio'
! grep -Fq -- '- windows:' "$project/STYLE.md" || fail 'explicit replacement retained an omitted library'
project_command bash commands/generate-style.sh --clear-asset-libraries CEL_SHADED_COMIC >/dev/null
! grep -Fq '## External Asset Libraries' "$project/STYLE.md" || fail 'explicit clearing retained the external section'

echo '[2/7] rejecting malformed contracts and unsafe configured paths'
expect_failure "$runtime_dir/relative.log" bash commands/generate-style.sh --asset-library studio=relative/models CEL_SHADED_COMIC
expect_failure "$runtime_dir/root.log" bash commands/generate-style.sh --asset-library studio=/ CEL_SHADED_COMIC
expect_failure "$runtime_dir/drive-root.log" bash commands/generate-style.sh --asset-library 'studio=C:\' CEL_SHADED_COMIC
expect_failure "$runtime_dir/unc-root.log" bash commands/generate-style.sh --asset-library 'studio=\\server\share' CEL_SHADED_COMIC
expect_failure "$runtime_dir/config-traversal.log" bash commands/generate-style.sh --asset-library studio=/srv/../models CEL_SHADED_COMIC
expect_failure "$runtime_dir/url.log" bash commands/generate-style.sh --asset-library studio=https://example.invalid/models CEL_SHADED_COMIC
expect_failure "$runtime_dir/id.log" bash commands/generate-style.sh --asset-library 'Bad_Id=/srv/models' CEL_SHADED_COMIC
expect_failure "$runtime_dir/duplicate-id.log" bash commands/generate-style.sh --asset-library studio=/srv/one --asset-library studio=/srv/two CEL_SHADED_COMIC
expect_failure "$runtime_dir/duplicate-path.log" bash commands/generate-style.sh --asset-library one=/srv/models --asset-library two=/srv/models CEL_SHADED_COMIC
expect_failure "$runtime_dir/clear-mixed.log" bash commands/generate-style.sh --clear-asset-libraries --asset-library studio=/srv/models CEL_SHADED_COMIC

project_command bash commands/generate-style.sh --asset-library "studio=$library" CEL_SHADED_COMIC >/dev/null
sed '/Inspect configured external libraries before creating or downloading/d' "$project/STYLE.md" > "$runtime_dir/missing-precedence.md"
expect_failure "$runtime_dir/missing-precedence.log" bash commands/validate-style-contract.sh "$runtime_dir/missing-precedence.md"
sed '/Copy each selected asset into/d' "$project/STYLE.md" > "$runtime_dir/missing-copy.md"
expect_failure "$runtime_dir/missing-copy.log" bash commands/validate-style-contract.sh "$runtime_dir/missing-copy.md"
cp "$project/STYLE.md" "$runtime_dir/duplicate.md"
sed -i "/^- studio:/a - studio: \`$library\`" "$runtime_dir/duplicate.md"
expect_failure "$runtime_dir/duplicate-contract.log" bash commands/validate-style-contract.sh "$runtime_dir/duplicate.md"

echo '[3/7] inventorying supported assets without following symbolic links'
inventory="$(project_command bash commands/inspect-external-asset-library.sh studio --json)"
grep -Fq 'characters/Hero Rig/hero.blend' <<< "$inventory" || fail 'inventory omitted blend asset'
grep -Fq 'characters/Hero Rig/walk.bvh' <<< "$inventory" || fail 'inventory omitted animation asset'
grep -Fq 'props/crate.glb' <<< "$inventory" || fail 'inventory omitted glb asset'
! grep -Fq 'props/readme.txt' <<< "$inventory" || fail 'inventory included unsupported text file'
grep -Fq 'linked.glb' <<< "$inventory" || fail 'inventory did not report skipped symbolic link'
expect_failure "$runtime_dir/missing-id.log" bash commands/inspect-external-asset-library.sh missing --json
project_command bash commands/generate-style.sh --asset-library 'missing=/definitely/not/an/opencaw/library' CEL_SHADED_COMIC >/dev/null
project_command bash commands/validate-style-contract.sh "$project/STYLE.md" >/dev/null
expect_failure "$runtime_dir/missing-root.log" bash commands/inspect-external-asset-library.sh missing --json

echo '[4/7] copying a single asset with hash-bound task evidence'
project_command bash commands/generate-style.sh --asset-library "studio=$library" CEL_SHADED_COMIC >/dev/null
copy_result="$(project_command bash commands/copy-external-asset.sh studio props/crate.glb --evidence .ai/tasks/library-test/crate-copy.json)"
crate_copy="$project/assets/models/studio/props/crate.glb"
[[ -f "$crate_copy" ]] || fail 'single asset was not copied to its deterministic destination'
[[ "$(hash_file "$crate_copy")" == "$source_hash_before" ]] || fail 'copied asset hash differs from source'
grep -Fq '"sourceReadOnly": true' <<< "$copy_result" || fail 'copy output omitted source read-only state'
grep -Fq '"destination": "assets/models/studio/props/crate.glb"' "$project/.ai/tasks/library-test/crate-copy.json" || fail 'copy evidence destination is wrong'
grep -Fq "$source_hash_before" "$project/.ai/tasks/library-test/crate-copy.json" || fail 'copy evidence omitted hash'
! grep -Fq "$library" "$project/.ai/tasks/library-test/crate-copy.json" || fail 'copy evidence duplicated the absolute library root'
[[ "$(hash_file "$library/props/crate.glb")" == "$source_hash_before" ]] || fail 'copy mutated source bytes'
[[ "$(stat -c '%Y:%s' "$library/props/crate.glb")" == "$source_stat_before" ]] || fail 'copy mutated source metadata'
expect_failure "$runtime_dir/overwrite.log" bash commands/copy-external-asset.sh studio props/crate.glb

echo '[5/7] copying complete bundles and rejecting unsafe sources'
project_command bash commands/copy-external-asset.sh studio 'characters/Hero Rig' --evidence .ai/tasks/library-test/hero-copy.json >/dev/null
hero_copy="$project/assets/models/studio/characters/Hero Rig"
[[ -f "$hero_copy/hero.blend" && -f "$hero_copy/walk.bvh" && -f "$hero_copy/textures/hero.png" ]] || fail 'complete asset bundle was not copied'
[[ -w "$hero_copy/hero.blend" ]] || fail 'project-local template copy is not writable'
expect_failure "$runtime_dir/unsupported.log" bash commands/copy-external-asset.sh studio props/readme.txt
expect_failure "$runtime_dir/traversal.log" bash commands/copy-external-asset.sh studio ../outside.glb
expect_failure "$runtime_dir/absolute.log" bash commands/copy-external-asset.sh studio /outside.glb
expect_failure "$runtime_dir/source-link.log" bash commands/copy-external-asset.sh studio linked.glb
expect_failure "$runtime_dir/bundle-link.log" bash commands/copy-external-asset.sh studio bad-bundle
[[ ! -e "$project/assets/models/studio/bad-bundle" ]] || fail 'failed bundle copy left a destination'
! find "$project/assets/models" -maxdepth 1 -name '.opencaw-copy-*' -print -quit | grep -q . || fail 'failed copy left temporary residue'

echo '[6/7] enforcing project confinement, non-overlap, and evidence boundaries'
mkdir -p "$library/symlinked"
printf 'symlink target model\n' > "$library/symlinked/model.glb"
mkdir -p "$runtime_dir/outside-destination"
mkdir -p "$project/assets/models/studio"
ln -s "$runtime_dir/outside-destination" "$project/assets/models/studio/symlinked"
expect_failure "$runtime_dir/destination-link.log" bash commands/copy-external-asset.sh studio symlinked/model.glb
rm "$project/assets/models/studio/symlinked"
expect_failure "$runtime_dir/evidence-escape.log" bash commands/copy-external-asset.sh studio symlinked/model.glb --evidence "$runtime_dir/outside-evidence.json"
[[ ! -e "$project/assets/models/studio/symlinked/model.glb" ]] || fail 'evidence-boundary failure copied the asset'
printf 'project-contained model\n' > "$project/project-source.glb"
project_command bash commands/generate-style.sh --asset-library "project=$project" CEL_SHADED_COMIC >/dev/null
expect_failure "$runtime_dir/overlap.log" bash commands/copy-external-asset.sh project project-source.glb

echo '[7/7] checking skills, roles, documentation, command structure, and integration'
for command in list-external-asset-libraries inspect-external-asset-library copy-external-asset; do
  [[ -x "commands/$command.sh" ]] || fail "command is not executable: $command"
  bash "commands/$command.sh" --help >/dev/null || fail "$command --help failed"
done
grep -Fq '`use-external-asset-library`' skills/INDEX.md || fail 'skill catalog omits external asset library skill'
grep -Fq 'use-external-asset-library' .roles/ROLE_SKILL_MAP.json || fail 'role map omits external asset library skill'
grep -Fiq 'optional external 3D asset libraries' README.md || fail 'README omits optional external library documentation'
grep -Fq 'Never load, import, execute, or use an asset directly from an external library' AGENTS.md || fail 'AGENTS omits copy-first boundary'
grep -Fq './tests/test-external-asset-library.sh' commands/validate-opencaw.sh || fail 'integrated validation omits external asset library tests'
bash commands/generate-role-skill-map.sh --check >/dev/null
bash commands/validate-role-skill-map.sh >/dev/null
bash commands/validate-commands.sh >/dev/null
echo 'External asset library tests passed.'
