#!/usr/bin/env bash
set -euo pipefail

root=".styles/.pipelines"
[[ -d "$root" ]] || { echo "Missing art pipeline directory: $root" >&2; exit 1; }
[[ -f "$root/INDEX.md" ]] || { echo "Missing art pipeline index." >&2; exit 1; }
[[ ! -e ".styles/.gpu" ]] || { echo "Legacy .styles/.gpu directory must not exist." >&2; exit 1; }
[[ ! -e ".media" ]] || { echo "Legacy .media directory must not exist." >&2; exit 1; }

declare -A paths=(
  [CLOUD]="cloud/PIPELINE.md"
  [LOCAL]="local/PIPELINE.md"
  [PROOF_TO_MODEL]="proof-to-model/PIPELINE.md"
  [CODE]="code/PIPELINE.md"
  [BLENDER]="blender/PIPELINE.md"
)
for pipeline in CLOUD LOCAL PROOF_TO_MODEL CODE BLENDER; do
  file="$root/${paths[$pipeline]}"
  [[ -f "$file" ]] || { echo "Missing art pipeline contract: $file" >&2; exit 1; }
  heading="$(head -n 1 "$file" | tr -d '\r')"
  [[ "$heading" == "# $pipeline Art Pipeline" ]] || { echo "Invalid art pipeline heading: $file" >&2; exit 1; }
  for section in "## Intent" "## Inputs" "## Production Rules" "## Output Contract" "## Acceptance Checks" "## Role Fit"; do
    awk -v expected="$section" '{ sub(/\r$/, ""); if ($0 == expected) found=1 } END { exit !found }' "$file" || { echo "$file is missing $section" >&2; exit 1; }
  done
  grep -Fq -- "- \`$pipeline\`" "$root/INDEX.md" || { echo "Art pipeline is not indexed: $pipeline" >&2; exit 1; }
  grep -Eiq 'never (switch|fall back)|never.*silently' "$file" || { echo "$file lacks a no-silent-fallback boundary" >&2; exit 1; }
done

grep -Fq 'Blender 4.5 LTS' "$root/blender/PIPELINE.md" || { echo "BLENDER contract must pin Blender 4.5 LTS." >&2; exit 1; }
grep -Eiq 'immutable source|preserve.*source' "$root/blender/PIPELINE.md" || { echo "BLENDER contract lacks immutable-source protection." >&2; exit 1; }
grep -Eiq 'never install|do not install' "$root/blender/PIPELINE.md" || { echo "BLENDER contract lacks the no-install boundary." >&2; exit 1; }

for asset in _shared/media-generation-manifest.schema.json local/toolchain.json local/model-packs.json proof-to-model/manifest.schema.json proof-to-model/source-set.schema.json proof-to-model/classification.schema.json proof-to-model/proof-set.schema.json proof-to-model/toolchain.json proof-to-model/toolchain.single-view-diagnostic.json proof-to-model/recipes/static-prop.json code/code-model-manifest.schema.json code/code-character-profile.schema.json code/code-character-observation.schema.json code/code-character-evidence-report.schema.json; do
  [[ -f "$root/$asset" ]] || { echo "Missing art pipeline support asset: $root/$asset" >&2; exit 1; }
done

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate art pipeline assets." >&2; exit 1; }
"$node_bin" <<'NODE'
const fs = require('fs');
const files = [
  '.styles/.pipelines/_shared/media-generation-manifest.schema.json',
  '.styles/.pipelines/local/toolchain.json',
  '.styles/.pipelines/local/model-packs.json',
  '.styles/.pipelines/code/code-model-manifest.schema.json',
  '.styles/.pipelines/code/code-character-profile.schema.json',
  '.styles/.pipelines/code/code-character-observation.schema.json',
  '.styles/.pipelines/code/code-character-evidence-report.schema.json'
];
files.push('.styles/.pipelines/proof-to-model/manifest.schema.json', '.styles/.pipelines/proof-to-model/toolchain.json', '.styles/.pipelines/proof-to-model/recipes/static-prop.json');
const proofRoot = '.styles/.pipelines/proof-to-model/';
files.push(...['source-set.schema.json', 'classification.schema.json', 'proof-set.schema.json', 'toolchain.single-view-diagnostic.json'].map(file => proofRoot + file));
for (const file of files) JSON.parse(fs.readFileSync(file, 'utf8'));
const readProof = file => JSON.parse(fs.readFileSync(proofRoot + file, 'utf8'));
const manifest = readProof('manifest.schema.json');
if (!manifest.properties.schemaVersion.enum.includes(2)) throw new Error('Proof production requires manifest v2.');
for (const key of ['sourceSet', 'classification', 'proofSet']) if (!manifest.properties[key]) throw new Error(`Proof manifest omits ${key}`);
const classification = readProof('classification.schema.json');
for (const key of ['sources', 'sourceViews', 'subjects', 'research', 'unknowns', 'conflicts']) if (!classification.required.includes(key)) throw new Error(`Classification schema omits ${key}`);
const proofSet = readProof('proof-set.schema.json');
if (proofSet.properties.views.minItems !== 6 || proofSet.properties.views.maxItems !== 6 || !proofSet.properties.views.items.properties.cameraAngleX) throw new Error('Proof schema requires six views and per-view intrinsics.');
const mv = readProof('toolchain.json'), diagnostic = readProof('toolchain.single-view-diagnostic.json');
if (mv.modelFamily !== 'mv' || mv.viewCount !== 6) throw new Error('Default proof toolchain must select six-view MV inference.');
if (mv.modelDir === diagnostic.modelDir || mv.reconstruction.arguments.includes('--sv-image')) throw new Error('MV must remain separate from single-view diagnostics.');
for (const [flag, value] of [['--pixal3d-weights','mv'], ['--num-views','6'], ['--res','1024']]) if (mv.reconstruction.arguments[mv.reconstruction.arguments.indexOf(flag) + 1] !== value) throw new Error(`Missing pinned MV argument ${flag}`);
if (mv.models.filter(model => /\.gguf$/.test(model.path) && !/\/birefnet\.gguf$/.test(model.path)).length !== 9 || mv.models.some(model => model.licenseAccepted !== false || /_sv\.gguf$/.test(model.path))) throw new Error('Default MV requires nine explicit unaccepted model pins plus its explicit matting dependency.');
if (mv.models.filter(model => /_mv\.gguf$/.test(model.path)).length !== 4) throw new Error('MV flow inventory is incomplete.');
if (!Number.isInteger(readProof('recipes/static-prop.json').proofPreparation.maxSetRevisions)) throw new Error('Proof preparation requires an explicit revision budget.');
const code = JSON.parse(fs.readFileSync(files[3], 'utf8'));
const required = ['schemaVersion','modelId','intent','pipelineSelection','inputs','target','renderer','runtime','budgets','reviewPolicy','passes'];
for (const key of required) if (!code.required.includes(key)) throw new Error(`Code model schema omits ${key}`);
const character = JSON.parse(fs.readFileSync(files[4], 'utf8'));
const characterRequired = ['schemaVersion','characterId','codeModel','intent','silhouette','structure','motion','budgets','reviewPolicy','gates'];
for (const key of characterRequired) if (!character.required.includes(key)) throw new Error(`Code character schema omits ${key}`);
if (character.properties.schemaVersion.const !== 'opencaw-code-character/v1') throw new Error('Code character schema version is invalid.');
const observation = JSON.parse(fs.readFileSync(files[5], 'utf8'));
if (observation.properties.schemaVersion.const !== 'opencaw-code-character-observation/v1') throw new Error('Code character observation schema version is invalid.');
const evidence = JSON.parse(fs.readFileSync(files[6], 'utf8'));
if (evidence.properties.schemaVersion.const !== 'opencaw-code-character-evidence/v1') throw new Error('Code character evidence schema version is invalid.');
NODE

bash commands/validate-media-templates.sh

# MODEL_TO_ANIMATION is a downstream workflow, not another primary pipeline.
for asset in WORKFLOW.md manifest.schema.json recipe.schema.json motion-package.schema.json blender/motion.py blender/scripts.json engines/threejs-motion.mjs; do
  [[ -f ".styles/.workflows/model-to-animation/$asset" ]] || { echo "Missing motion workflow asset: $asset" >&2; exit 1; }
done
"$node_bin" <<'NODE'
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const base = '.styles/.workflows/model-to-animation';
for (const name of ['manifest.schema.json', 'recipe.schema.json', 'motion-package.schema.json']) {
  const schema = JSON.parse(fs.readFileSync(path.join(base, name), 'utf8'));
  if (!schema.$schema || !schema.properties) throw new Error(`Incomplete motion schema: ${name}`);
}
const scripts = JSON.parse(fs.readFileSync(path.join(base, 'blender/scripts.json'), 'utf8'));
if (scripts.schemaVersion !== 1 || !scripts.files?.['motion.py']) throw new Error('Motion script inventory is incomplete.');
for (const [name, expected] of Object.entries(scripts.files)) {
  if (!/^[a-z][a-z0-9_]*\.py$/.test(name)) throw new Error('Invalid motion script basename.');
  const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(base, 'blender', name))).digest('hex');
  if (actual !== expected) throw new Error(`Changed audited motion script: ${name}`);
}
const actual = fs.readdirSync(path.join(base, 'blender')).filter(name => name.endsWith('.py')).sort();
if (JSON.stringify(actual) !== JSON.stringify(Object.keys(scripts.files).sort())) throw new Error('Motion script inventory does not cover the exact Python bundle.');
NODE
echo "Art pipeline validation passed."
