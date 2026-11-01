#!/usr/bin/env bash
set -euo pipefail

root=".styles/.pipelines"
[[ -d "$root" ]] || { echo "Missing art pipeline directory: $root" >&2; exit 1; }
[[ -f "$root/INDEX.md" ]] || { echo "Missing art pipeline index." >&2; exit 1; }
[[ ! -e ".styles/.gpu" ]] || { echo "Legacy .styles/.gpu directory must not exist." >&2; exit 1; }
for legacy in CLOUD_SESSION.md COMFYUI_LOCAL.md INDEX.md media-generation-manifest.schema.json model-packs.json toolchain.json; do
  [[ ! -e ".media/$legacy" ]] || { echo "Legacy .media asset must not exist: $legacy" >&2; exit 1; }
done

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

for asset in _shared/media-generation-manifest.schema.json proof-to-model/manifest.schema.json proof-to-model/source-set.schema.json proof-to-model/classification.schema.json proof-to-model/proof-set.schema.json proof-to-model/finishing-settings.schema.json proof-to-model/rigid-source-topology.schema.json proof-to-model/finish-budget.schema.json proof-to-model/toolchain.json proof-to-model/toolchain.single-view-diagnostic.json proof-to-model/recipes/static-prop.json proof-to-model/blender/finish.py proof-to-model/blender/review.py proof-to-model/blender/common.py proof-to-model/blender/rigid_finish.py proof-to-model/blender/rigid_source_topology.py code/code-model-manifest.schema.json code/code-character-profile.schema.json code/code-character-observation.schema.json code/code-character-evidence-report.schema.json; do
  if [[ "$asset" == proof-to-model/* ]]; then
    node commands/lib/bubo-runtime.cjs resource "$asset" >/dev/null
  else
    [[ -f "$root/$asset" ]] || { echo "Missing art pipeline support asset: $root/$asset" >&2; exit 1; }
  fi
done

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate art pipeline assets." >&2; exit 1; }
"$node_bin" <<'NODE'
const fs = require('fs');
const files = [
  '.styles/.pipelines/_shared/media-generation-manifest.schema.json',
  '.styles/.pipelines/code/code-model-manifest.schema.json',
  '.styles/.pipelines/code/code-character-profile.schema.json',
  '.styles/.pipelines/code/code-character-observation.schema.json',
  '.styles/.pipelines/code/code-character-evidence-report.schema.json'
];
files.push('runtime/bubo/resources/proof-to-model/manifest.schema.json', 'runtime/bubo/resources/proof-to-model/toolchain.json', 'runtime/bubo/resources/proof-to-model/recipes/static-prop.json');
const proofRoot = require('path').dirname(require('./commands/lib/bubo-runtime.cjs').resource('proof-to-model/manifest.schema.json')) + '/';
files.push(...['source-set.schema.json', 'classification.schema.json', 'proof-set.schema.json', 'finishing-settings.schema.json', 'rigid-source-topology.schema.json', 'finish-budget.schema.json', 'toolchain.single-view-diagnostic.json'].map(file => proofRoot + file));
for (const file of files) JSON.parse(fs.readFileSync(file, 'utf8'));
const readProof = file => JSON.parse(fs.readFileSync(proofRoot + file, 'utf8'));
const manifest = readProof('manifest.schema.json');
if (!manifest.properties.schemaVersion.enum.includes(2)) throw new Error('Proof production requires manifest v2.');
for (const key of ['sourceSet', 'classification', 'proofSet']) if (!manifest.properties[key]) throw new Error(`Proof manifest omits ${key}`);
const classification = readProof('classification.schema.json');
for (const key of ['sources', 'sourceViews', 'subjects', 'research', 'unknowns', 'conflicts']) if (!classification.required.includes(key)) throw new Error(`Classification schema omits ${key}`);
const proofSet = readProof('proof-set.schema.json');
if (proofSet.properties.views.minItems !== 6 || proofSet.properties.views.maxItems !== 6 || !proofSet.properties.views.items.properties.cameraAngleX) throw new Error('Proof schema requires six views and per-view intrinsics.');
const finishSettings = readProof('finishing-settings.schema.json');
const sameKeys = (actual, expected) => Array.isArray(actual) && actual.length === expected.length && JSON.stringify([...actual].sort()) === JSON.stringify([...expected].sort());
const closedObject = (schema, required, allowed, label) => {
  if (schema?.type !== 'object' || schema.additionalProperties !== false || !sameKeys(schema.required, required) || !sameKeys(Object.keys(schema.properties || {}), allowed)) throw new Error(`${label} requires explicit fields in a closed object.`);
};
const bounded = (schema, type, minimum, maximum, label) => {
  if (schema?.type !== type || schema.minimum !== minimum || schema.maximum !== maximum) throw new Error(`${label} requires explicit ${type} bounds.`);
};
if (!Array.isArray(finishSettings.oneOf) || finishSettings.oneOf.length !== 2 || !sameKeys(finishSettings.oneOf.map(branch => branch.$ref), ['#/$defs/legacyQuadriFlow', '#/$defs/rigidParts']) || finishSettings.oneOf.some(branch => !sameKeys(Object.keys(branch), ['$ref']))) throw new Error('Finishing settings require exactly the explicit v1/v2 alternatives.');
const legacyFinish = finishSettings.$defs?.legacyQuadriFlow;
const rigidFinish = finishSettings.$defs?.rigidParts;
closedObject(legacyFinish, ['schemaVersion','topologyPreparation','collision'], ['schemaVersion','topologyPreparation','collision','quadriFlow'], 'Legacy finishing settings');
closedObject(rigidFinish, ['schemaVersion','method','topologyPreparation','collision','rigidParts','resources'], ['schemaVersion','method','topologyPreparation','collision','rigidParts','resources'], 'Rigid finishing settings');
if (legacyFinish.properties.schemaVersion.type !== 'integer' || legacyFinish.properties.schemaVersion.const !== 1 || rigidFinish.properties.schemaVersion.type !== 'integer' || rigidFinish.properties.schemaVersion.const !== 2 || rigidFinish.properties.method.const !== 'rigid-parts') throw new Error('Finishing versions and the rigid-parts route must remain explicit.');
closedObject(rigidFinish.properties.topologyPreparation, ['method'], ['method'], 'Rigid topology preparation');
if (rigidFinish.properties.topologyPreparation.properties.method.const !== 'none') throw new Error('Rigid finishing cannot implicitly select topology preparation.');
for (const [label, collision] of [['Legacy', legacyFinish.properties.collision], ['Rigid', rigidFinish.properties.collision]]) {
  const branches = collision.oneOf;
  if (!Array.isArray(branches) || branches.length !== 2 || !sameKeys(branches.map(branch => branch.properties?.method?.const), ['exact-hull','kdop-26'])) throw new Error(`${label} finishing requires explicit collision alternatives.`);
  for (const branch of branches) {
    const keys = branch.properties.method.const === 'exact-hull' ? ['method'] : ['method','padding','maxVolumeRatio'];
    const hasOptionalFrame = label === 'Rigid' && branch.properties.method.const === 'kdop-26';
    closedObject(branch, keys, hasOptionalFrame ? [...keys, 'frame'] : keys, `${label} collision`);
    if (keys.length > 1) {
      bounded(branch.properties.padding, 'number', 0, 1, `${label} collision padding`);
      bounded(branch.properties.maxVolumeRatio, 'number', 1, 100, `${label} collision volume`);
    }
    if (hasOptionalFrame) {
      const frame = branch.properties.frame;
      if (frame?.type !== 'string' || !sameKeys(frame.enum, ['world', 'principal-axes-v1']) || Object.hasOwn(frame, 'default')) throw new Error('Rigid collision frame requires explicit world/principal selection without a default.');
    }
  }
}
const rigidInputs = rigidFinish.properties.rigidParts;
closedObject(rigidInputs, ['handoff','handoffSha256','reviewEvidence','reviewEvidenceSha256','maxLod0Triangles','maxGlbBytes'], ['handoff','handoffSha256','reviewEvidence','reviewEvidenceSha256','maxLod0Triangles','maxGlbBytes','uvAtlas','importNormals','lods','sourceTopology'], 'Rigid handoff settings');
const sourceTopology = rigidInputs.properties.sourceTopology;
closedObject(sourceTopology, ['method','receipt','receiptSha256'], ['method','receipt','receiptSha256'], 'Reviewed source topology');
if (sourceTopology.properties.method.const !== 'reviewed-source-corners-v1' || Object.hasOwn(sourceTopology, 'default') || Object.values(sourceTopology.properties).some(p => Object.hasOwn(p, 'default'))) throw new Error('Source topology requires an explicit versioned receipt, never default selection.');
if (!sameKeys(rigidInputs.dependentRequired?.sourceTopology, ['lods'])) throw new Error('Reviewed source topology requires explicitly selected constrained LODs.');
const topologyPath = sourceTopology.properties.receipt;
if (topologyPath.type !== 'string' || topologyPath.minLength !== 1 || topologyPath.maxLength !== 4096 || !new RegExp(topologyPath.pattern).test('.hephaera/.cache/tasks/task/owners.json') || new RegExp(topologyPath.pattern).test('outside.json')) throw new Error('Source topology requires a bounded task-local receipt path.');
if (sourceTopology.properties.receiptSha256.type !== 'string' || sourceTopology.properties.receiptSha256.pattern !== '^[a-f0-9]{64}$') throw new Error('Source topology requires an exact receipt SHA256.');
const topologyReceipt = readProof('rigid-source-topology.schema.json');
closedObject(topologyReceipt, ['schemaVersion','kind','preparedGlbSha256','meshes'], ['schemaVersion','kind','preparedGlbSha256','meshes'], 'Source topology receipt');
if (topologyReceipt.properties.schemaVersion.const !== 1 || topologyReceipt.properties.schemaVersion.type !== 'integer' || topologyReceipt.properties.kind.const !== 'rigid-source-corner-topology') throw new Error('Source topology receipt version/kind must be explicit.');
const topologyMeshes = topologyReceipt.properties.meshes;
if (topologyMeshes.type !== 'array' || topologyMeshes.minItems !== 1 || topologyMeshes.maxItems !== 512) throw new Error('Source topology mesh inventory requires1..512 entries.');
const topologyMesh = topologyMeshes.items;
const topologyFields = ['node','fileNodeIndex','sourceVertexCount','indexedCorners','ownersI32LEHex','ownersSha256'];
closedObject(topologyMesh, topologyFields, topologyFields, 'Source topology mesh');
bounded(topologyMesh.properties.fileNodeIndex, 'integer', 0, 1000000, 'Source topology node index');
bounded(topologyMesh.properties.sourceVertexCount, 'integer', 1, 8000000, 'Source topology vertex count');
bounded(topologyMesh.properties.indexedCorners, 'integer', 3, 16777216, 'Source topology indexed corners');
if (topologyMesh.properties.indexedCorners.multipleOf !== 3 || topologyMesh.properties.ownersI32LEHex.type !== 'string' || topologyMesh.properties.ownersI32LEHex.minLength !== 24 || topologyMesh.properties.ownersI32LEHex.maxLength !== 134217728 || topologyMesh.properties.ownersI32LEHex.pattern !== '^[a-f0-9]+$') throw new Error('Source topology requires bounded triangle-corner little-endian owner hex.');
for (const digest of [topologyReceipt.properties.preparedGlbSha256, topologyMesh.properties.ownersSha256]) if (digest.type !== 'string' || digest.pattern !== '^[a-f0-9]{64}$') throw new Error('Source topology must bind prepared GLB and exact typed owner bytes.');
const topologyNode = topologyMesh.properties.node;
if (topologyNode.type !== 'string' || topologyNode.minLength !== 1 || topologyNode.maxLength !== 256 || new RegExp(topologyNode.pattern).test('\u0000') || !new RegExp(topologyNode.pattern).test('LOW.valid')) throw new Error('Source topology node names require bounded non-NUL strings.');
const importNormals = rigidInputs.properties.importNormals;
closedObject(importNormals, ['method'], ['method'], 'Rigid normal import');
if (importNormals.properties.method.const !== 'stored-corner-fan-v1' || Object.hasOwn(importNormals, 'default') || Object.hasOwn(importNormals.properties.method, 'default')) throw new Error('Rigid normal import requires an explicit versioned method without a default.');
const rigidLods = rigidInputs.properties.lods;
closedObject(rigidLods, ['method','maxVertexSurfaceErrorMetres'], ['method','maxVertexSurfaceErrorMetres','contactPolicy'], 'Rigid constrained LODs');
const contactPolicy = rigidLods.properties.contactPolicy;
if (contactPolicy?.type !== 'string' || contactPolicy.const !== 'protected-contact-rings-v1' || Object.hasOwn(contactPolicy, 'default')) throw new Error('Contact LOD policy requires explicit protected-contact-rings-v1 selection without a default.');
const contactRules = rigidInputs.allOf;
const contactRule = Array.isArray(contactRules) && contactRules.length === 1 ? contactRules[0] : null;
if (!contactRule || !sameKeys(Object.keys(contactRule), ['if','then']) ||
    !sameKeys(Object.keys(contactRule.if || {}), ['required','properties']) || !sameKeys(contactRule.if.required, ['lods']) ||
    !sameKeys(Object.keys(contactRule.if.properties || {}), ['lods']) ||
    !sameKeys(Object.keys(contactRule.if.properties.lods || {}), ['required']) || !sameKeys(contactRule.if.properties.lods.required, ['contactPolicy']) ||
    !sameKeys(Object.keys(contactRule.then || {}), ['required']) || !sameKeys(contactRule.then.required, ['sourceTopology'])) throw new Error('Explicit contact LOD selection requires reviewed source topology; omission preserves legacy admission.');
if (rigidLods.properties.method.const !== 'original-component-finite-collapse-v1' || Object.hasOwn(rigidLods, 'default') || Object.hasOwn(rigidLods.properties.method, 'default')) throw new Error('Rigid LODs require an explicit versioned method without a default.');
const lodErrors = rigidLods.properties.maxVertexSurfaceErrorMetres;
if (lodErrors.type !== 'array' || lodErrors.minItems !== 1 || lodErrors.maxItems !== 8 || Object.hasOwn(lodErrors, 'default')) throw new Error('Rigid LOD error bounds require 1..8 explicit entries.');
if (lodErrors.items?.type !== 'number' || lodErrors.items.exclusiveMinimum !== 0 || lodErrors.items.maximum !== 1 || Object.hasOwn(lodErrors.items, 'minimum') || Object.hasOwn(lodErrors.items, 'default')) throw new Error('Rigid LOD error bounds require finite positive world-metre values at most one metre.');
const uvAtlas = rigidInputs.properties.uvAtlas;
closedObject(uvAtlas, ['method','islandMarginPixels'], ['method','islandMarginPixels','triangleRepair'], 'Rigid UV atlas');
if (uvAtlas.properties.method.const !== 'smart-project-pixels') throw new Error('Rigid UV atlas requires explicit smart-project-pixels.');
bounded(uvAtlas.properties.islandMarginPixels, 'integer', 1, 64, 'Rigid UV atlas pixel margin');
const uvRepair = uvAtlas.properties.triangleRepair;
closedObject(uvRepair, ['method','minCellPixels','maxTriangles'], ['method','minCellPixels','maxTriangles'], 'Rigid isolated UV repair');
if (uvRepair.properties.method.const !== 'density-preserving-isolated-cells-v1' || Object.hasOwn(uvRepair, 'default') || Object.values(uvRepair.properties).some(p => Object.hasOwn(p, 'default'))) throw new Error('UV repair requires explicit bounded selection without a default.');
if (uvRepair.properties.minCellPixels.type !== 'integer' || uvRepair.properties.minCellPixels.const !== 4) throw new Error('UV repair v1 requires exactly four minimum cell pixels.');
bounded(uvRepair.properties.maxTriangles, 'integer', 1, 16384, 'Rigid UV repair face budget');
for (const key of ['handoff','reviewEvidence']) if (rigidInputs.properties[key].type !== 'string' || rigidInputs.properties[key].minLength !== 1 || rigidInputs.properties[key].maxLength !== 4096) throw new Error(`Rigid ${key} requires a bounded nonempty path.`);
for (const key of ['handoffSha256','reviewEvidenceSha256']) if (rigidInputs.properties[key].type !== 'string' || rigidInputs.properties[key].pattern !== '^[a-f0-9]{64}$' || rigidInputs.properties[key].minLength !== 64 || rigidInputs.properties[key].maxLength !== 64) throw new Error(`Rigid ${key} requires an exact SHA-256 identity.`);
bounded(rigidInputs.properties.maxLod0Triangles, 'integer', 4, 8000000, 'Rigid LOD0 triangles');
bounded(rigidInputs.properties.maxGlbBytes, 'integer', 1024, 2147483648, 'Rigid GLB bytes');
closedObject(rigidFinish.properties.resources, ['maxPrivateBytes'], ['maxPrivateBytes'], 'Rigid resources');
bounded(rigidFinish.properties.resources.properties.maxPrivateBytes, 'integer', 67108864, 68719476736, 'Rigid memory');
const solver = legacyFinish.properties.quadriFlow;
if (!solver || solver.additionalProperties !== false || !solver.required?.includes('coordinateScale') || JSON.stringify(solver.properties?.coordinateScale?.enum) !== JSON.stringify([1,2,4,8,16,32,64,128,256,512,1024])) throw new Error('Finishing solver coordinates require an explicit closed power-of-two selection.');
const reduction = solver.properties.simplification;
if (!reduction || reduction.additionalProperties !== false || reduction.properties?.method?.const !== 'collapse') throw new Error('Finishing simplification requires a closed explicit Collapse selection.');
for (const key of ['method','targetTriangles','maxVertexSurfaceErrorMetres','protectedRegions']) if (!reduction.required?.includes(key) || !reduction.properties[key]) throw new Error(`Finishing simplification omits ${key}`);
const finishBudget = readProof('finish-budget.schema.json');
if (finishBudget.properties?.schemaVersion?.const !== 1 || finishBudget.additionalProperties !== false || finishBudget.properties?.human?.const !== true || finishBudget.properties?.stage?.const !== 'finish') throw new Error('Finish budget requires a closed human-approved finish-only schema.');
for (const key of ['schemaVersion','kind','stage','decision','human','reviewer','reason','manifestSha256','consumedFinishAttempts','maxFinishAttempts']) if (!finishBudget.required?.includes(key) || !finishBudget.properties[key]) throw new Error(`Finish budget omits ${key}`);
const mv = readProof('toolchain.json'), diagnostic = readProof('toolchain.single-view-diagnostic.json');
if (mv.modelFamily !== 'mv' || mv.viewCount !== 6) throw new Error('Default proof toolchain must select six-view MV inference.');
if (mv.modelDir === diagnostic.modelDir || mv.reconstruction.arguments.includes('--sv-image')) throw new Error('MV must remain separate from single-view diagnostics.');
for (const [flag, value] of [['--pixal3d-weights','mv'], ['--num-views','6'], ['--res','1024']]) if (mv.reconstruction.arguments[mv.reconstruction.arguments.indexOf(flag) + 1] !== value) throw new Error(`Missing pinned MV argument ${flag}`);
if (mv.models.filter(model => /\.gguf$/.test(model.path) && !/\/birefnet\.gguf$/.test(model.path)).length !== 9 || mv.models.some(model => model.licenseAccepted !== false || /_sv\.gguf$/.test(model.path))) throw new Error('Default MV requires nine explicit unaccepted model pins plus its explicit matting dependency.');
if (mv.models.filter(model => /_mv\.gguf$/.test(model.path)).length !== 4) throw new Error('MV flow inventory is incomplete.');
if (!Number.isInteger(readProof('recipes/static-prop.json').proofPreparation.maxSetRevisions)) throw new Error('Proof preparation requires an explicit revision budget.');
const code = JSON.parse(fs.readFileSync('.styles/.pipelines/code/code-model-manifest.schema.json', 'utf8'));
const required = ['schemaVersion','modelId','intent','pipelineSelection','inputs','target','renderer','runtime','budgets','reviewPolicy','passes'];
for (const key of required) if (!code.required.includes(key)) throw new Error(`Code model schema omits ${key}`);
const character = JSON.parse(fs.readFileSync('.styles/.pipelines/code/code-character-profile.schema.json', 'utf8'));
const characterRequired = ['schemaVersion','characterId','codeModel','intent','silhouette','structure','motion','budgets','reviewPolicy','gates'];
for (const key of characterRequired) if (!character.required.includes(key)) throw new Error(`Code character schema omits ${key}`);
if (character.properties.schemaVersion.const !== 'hephaera-code-character/v1') throw new Error('Code character schema version is invalid.');
const observation = JSON.parse(fs.readFileSync('.styles/.pipelines/code/code-character-observation.schema.json', 'utf8'));
if (observation.properties.schemaVersion.const !== 'hephaera-code-character-observation/v1') throw new Error('Code character observation schema version is invalid.');
const evidence = JSON.parse(fs.readFileSync('.styles/.pipelines/code/code-character-evidence-report.schema.json', 'utf8'));
if (evidence.properties.schemaVersion.const !== 'hephaera-code-character-evidence/v1') throw new Error('Code character evidence schema version is invalid.');
NODE

bash commands/validate-media-templates.sh

# MODEL_TO_ANIMATION is a downstream workflow, not another primary pipeline.
for asset in WORKFLOW.md manifest.schema.json recipe.schema.json motion-package.schema.json blender/motion.py blender/scripts.json engines/threejs-motion.mjs; do
  if [[ "$asset" == WORKFLOW.md ]]; then
    [[ -f ".styles/.workflows/model-to-animation/$asset" ]] || { echo "Missing motion host contract: $asset" >&2; exit 1; }
  else
    node commands/lib/bubo-runtime.cjs resource "model-to-animation/$asset" >/dev/null
  fi
done
"$node_bin" <<'NODE'
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const base = path.dirname(require('./commands/lib/bubo-runtime.cjs').resource('model-to-animation/manifest.schema.json'));
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
# Composed actions are listed alongside motion as a downstream production path.
for asset in WORKFLOW.md action-recipe.schema.json action-package.schema.json manifest.schema.json blender/action.py blender/scripts.json engines/threejs-action.mjs; do
  if [[ "$asset" == WORKFLOW.md ]]; then
    [[ -f ".styles/.workflows/model-to-action/$asset" ]] || { echo "Missing action host contract: $asset" >&2; exit 1; }
  else
    node commands/lib/bubo-runtime.cjs resource "model-to-action/$asset" >/dev/null
  fi
done
"$node_bin" <<'NODE'
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const base = path.dirname(require('./commands/lib/bubo-runtime.cjs').resource('model-to-action/manifest.schema.json'));
for (const name of ['action-recipe.schema.json', 'action-package.schema.json', 'manifest.schema.json']) {
  const schema = JSON.parse(fs.readFileSync(path.join(base, name), 'utf8'));
  if (!schema.$schema || !schema.properties) throw new Error(`Incomplete action schema: ${name}`);
}
const scripts = JSON.parse(fs.readFileSync(path.join(base, 'blender/scripts.json'), 'utf8'));
if (scripts.schemaVersion !== 1 || !scripts.files?.['action.py']) throw new Error('Action script inventory is incomplete.');
for (const [name, expected] of Object.entries(scripts.files)) {
  if (!/^[a-z][a-z0-9_]*\.py$/.test(name)) throw new Error('Invalid action script basename.');
  const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(base, 'blender', name))).digest('hex');
  if (actual !== expected) throw new Error(`Changed audited action script: ${name}`);
}
const actual = fs.readdirSync(path.join(base, 'blender')).filter(name => name.endsWith('.py')).sort();
if (JSON.stringify(actual) !== JSON.stringify(Object.keys(scripts.files).sort())) throw new Error('Action script inventory does not cover the exact Python bundle.');
for (const file of ['.styles/.pipelines/INDEX.md','.styles/INDEX.md','README.md']) {
  if (!fs.readFileSync(file,'utf8').includes('MODEL_TO_ACTION')) throw new Error(`Action pipeline is not discoverable in ${file}`);
}
NODE
echo "Art pipeline validation passed."
