#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-blender-scene-report.sh <report> [--root <repo>] [--require-clean]

Validates an opencaw-blender-scene/v1 JSON scene report. --root verifies
repository-confined files and hashes. --require-clean applies delivery gates.
EOF
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ $# -ge 1 ]] || { usage >&2; exit 1; }
report="$1"
shift
root=""
require_clean="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 && -z "$root" ]] || { echo "--root requires one path." >&2; exit 1; }
      root="$2"; shift 2 ;;
    --require-clean)
      [[ "$require_clean" == "false" ]] || { echo "--require-clean may be provided once." >&2; exit 1; }
      require_clean="true"; shift ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -f "$report" && ! -L "$report" ]] || { echo "Report must be a regular non-symlink file: $report" >&2; exit 1; }
[[ -z "$root" || -d "$root" ]] || { echo "Repository root not found: $root" >&2; exit 1; }
node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate Blender scene reports." >&2; exit 1; }
report_path="$(realpath "$report")"
root_path=""
[[ -z "$root" ]] || root_path="$(realpath "$root")"
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  report_path="$(wslpath -w "$report_path")"
  [[ -z "$root_path" ]] || root_path="$(wslpath -w "$root_path")"
fi

"$node_bin" - "$report_path" "$root_path" "$require_clean" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [reportPath, rootArg, requireCleanArg] = process.argv.slice(2);
const requireClean = requireCleanArg === 'true';
const errors = [];
let doc;
try { doc = JSON.parse(fs.readFileSync(reportPath, 'utf8')); }
catch (error) { console.error(`Invalid scene report JSON: ${error.message}`); process.exit(1); }

const obj = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const text = value => typeof value === 'string' && value.length > 0;
const finite = value => typeof value === 'number' && Number.isFinite(value);
const integer = value => Number.isInteger(value) && value >= 0;
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const id = value => typeof value === 'string' && /^[a-z][a-z0-9._-]*$/.test(value);
const relPath = value => typeof value === 'string' && value.length > 0 && !value.includes('\\') && !path.posix.isAbsolute(value) && !/^[A-Za-z]:/.test(value) && value.split('/').every(part => part && part !== '.' && part !== '..');
const arr = (value, where) => { if (!Array.isArray(value)) { errors.push(`${where} must be an array`); return []; } return value; };
const unique = (items, where) => {
  const seen = new Set();
  const names = new Set();
  for (const item of items) {
    if (!obj(item) || !id(item.id)) { errors.push(`${where} entries require a stable id`); continue; }
    if (seen.has(item.id)) errors.push(`${where} contains duplicate id ${item.id}`);
    seen.add(item.id);
    if (typeof item.name === 'string') {
      if (names.has(item.name)) errors.push(`${where} contains duplicate name ${item.name}`);
      names.add(item.name);
    }
  }
  return seen;
};
const ids = {};
const collections = arr(doc.collections, 'collections'); ids.collections = unique(collections, 'collections');
const objects = arr(doc.objects, 'objects'); ids.objects = unique(objects, 'objects');
const meshes = arr(doc.meshes, 'meshes'); ids.meshes = unique(meshes, 'meshes');
const materials = arr(doc.materials, 'materials'); ids.materials = unique(materials, 'materials');
const images = arr(doc.images, 'images'); ids.images = unique(images, 'images');
const armatures = arr(doc.armatures, 'armatures'); ids.armatures = unique(armatures, 'armatures');
const actions = arr(doc.actions, 'actions'); ids.actions = unique(actions, 'actions');
const nodeGroups = arr(doc.nodeGroups, 'nodeGroups'); ids.nodeGroups = unique(nodeGroups, 'nodeGroups');
const modifiers = arr(doc.modifiers, 'modifiers'); ids.modifiers = unique(modifiers, 'modifiers');
const simulations = arr(doc.simulations, 'simulations'); ids.simulations = unique(simulations, 'simulations');
const dependencies = arr(doc.dependencies, 'dependencies'); ids.dependencies = unique(dependencies, 'dependencies');
const findings = arr(doc.findings, 'findings');

if (doc.schemaVersion !== 'opencaw-blender-scene/v1') errors.push('unsupported schemaVersion');
const profiles = new Set(['static-asset','rigged-actor','procedural-scene','render-scene','simulation']);
if (!profiles.has(doc.profile)) errors.push('unsupported profile');
if (typeof doc.blenderVersion !== 'string' || !/^4\.5\.\d+$/.test(doc.blenderVersion)) errors.push('blenderVersion must be Blender 4.5.x');
if (!obj(doc.source) || !relPath(doc.source.path) || !doc.source.path.endsWith('.blend') || !hash(doc.source.sha256)) errors.push('source requires a normalized relative .blend path and lowercase SHA-256');
if (!obj(doc.units) || !['NONE','METRIC','IMPERIAL'].includes(doc.units.system) || !finite(doc.units.scaleLength) || doc.units.scaleLength <= 0) errors.push('units are invalid');
if (!obj(doc.render) || !text(doc.render.engine) || !integer(doc.render.resolutionX) || doc.render.resolutionX < 1 || !integer(doc.render.resolutionY) || doc.render.resolutionY < 1 || !finite(doc.render.fps) || doc.render.fps <= 0 || !(doc.render.activeCamera === null || ids.objects.has(doc.render.activeCamera))) errors.push('render settings are invalid');

const refs = (values, set, where) => {
  if (!Array.isArray(values)) { errors.push(`${where} must be an array`); return; }
  for (const value of values) if (!set.has(value)) errors.push(`${where} references unknown id ${value}`);
};
for (const item of collections) { if (!text(item.name)) errors.push(`collection ${item.id} needs a name`); if (item.parentId !== null && !ids.collections.has(item.parentId)) errors.push(`collection ${item.id} has unknown parent`); }
for (const item of objects) {
  if (!text(item.name) || !text(item.type)) errors.push(`object ${item.id} needs name and type`);
  if (item.parentId !== null && !ids.objects.has(item.parentId)) errors.push(`object ${item.id} has unknown parent`);
  refs(item.collectionIds, ids.collections, `object ${item.id}.collectionIds`);
  refs(item.materialIds, ids.materials, `object ${item.id}.materialIds`);
  refs(item.actionIds, ids.actions, `object ${item.id}.actionIds`);
  refs(item.nodeGroupIds, ids.nodeGroups, `object ${item.id}.nodeGroupIds`);
  refs(item.modifierIds, ids.modifiers, `object ${item.id}.modifierIds`);
  if (item.meshId !== null && !ids.meshes.has(item.meshId)) errors.push(`object ${item.id} has unknown mesh`);
  if (item.armatureId !== null && !ids.armatures.has(item.armatureId)) errors.push(`object ${item.id} has unknown armature`);
  const t = item.transform;
  if (!obj(t) || !['location','rotation','scale'].every(key => Array.isArray(t[key]) && t[key].length === 3 && t[key].every(finite))) errors.push(`object ${item.id} transform must be finite`);
}
for (const item of meshes) {
  if (!ids.objects.has(item.objectId)) errors.push(`mesh ${item.id} has unknown object`);
  else if (!objects.some(object => object.id === item.objectId && object.meshId === item.id)) errors.push(`mesh ${item.id} owner does not reference the mesh`);
  for (const key of ['vertices','edges','faces','triangles']) if (!integer(item[key])) errors.push(`mesh ${item.id}.${key} must be a nonnegative integer`);
  refs(item.materialIds, ids.materials, `mesh ${item.id}.materialIds`);
  if (!Array.isArray(item.uvLayers) || !item.uvLayers.every(text)) errors.push(`mesh ${item.id}.uvLayers is invalid`);
  if (!obj(item.invalidTopology) || !['nonManifoldEdges','looseVertices','zeroAreaFaces'].every(key => integer(item.invalidTopology[key]))) errors.push(`mesh ${item.id}.invalidTopology is invalid`);
}
for (const item of materials) { if (!text(item.name)) errors.push(`material ${item.id} needs a name`); refs(item.imageIds, ids.images, `material ${item.id}.imageIds`); refs(item.nodeGroupIds, ids.nodeGroups, `material ${item.id}.nodeGroupIds`); }
for (const item of images) { if (!text(item.name) || typeof item.packed !== 'boolean' || typeof item.exists !== 'boolean') errors.push(`image ${item.id} is invalid`); if (!item.packed && !relPath(item.path)) errors.push(`image ${item.id} requires a normalized relative path`); if (item.sha256 !== null && !hash(item.sha256)) errors.push(`image ${item.id} has an invalid hash`); }
for (const item of armatures) { if (!text(item.name) || !text(item.skeletonId) || !ids.objects.has(item.objectId)) errors.push(`armature ${item.id} is invalid`); }
for (const item of actions) { if (!text(item.name) || !ids.armatures.has(item.armatureId) || !finite(item.frameStart) || !finite(item.frameEnd) || item.frameEnd < item.frameStart) errors.push(`action ${item.id} is invalid`); }
for (const item of nodeGroups) { if (!text(item.name) || !text(item.type)) errors.push(`node group ${item.id} is invalid`); if (item.realizationPolicy !== null && !['keep-instances','realize-for-edit','realize-for-simulation','realize-for-render','realize-for-export','frozen-output'].includes(item.realizationPolicy)) errors.push(`node group ${item.id} has invalid realization policy`); }
for (const item of modifiers) { if (!text(item.name) || !text(item.type) || !ids.objects.has(item.objectId)) errors.push(`modifier ${item.id} is invalid`); if (item.nodeGroupId !== null && !ids.nodeGroups.has(item.nodeGroupId)) errors.push(`modifier ${item.id} has unknown node group`); }
for (const item of simulations) {
  if (!text(item.name) || !text(item.type) || !ids.objects.has(item.objectId) || !obj(item.cache)) errors.push(`simulation ${item.id} is invalid`);
  else { const c=item.cache; if (typeof c.required !== 'boolean' || typeof c.baked !== 'boolean' || typeof c.resolved !== 'boolean' || (c.required && !relPath(c.path))) errors.push(`simulation ${item.id} cache is invalid`); }
}
for (const item of dependencies) { if (!text(item.kind) || typeof item.packed !== 'boolean' || typeof item.exists !== 'boolean' || typeof item.insideRoot !== 'boolean') errors.push(`dependency ${item.id} is invalid`); if (!item.packed && !relPath(item.path)) errors.push(`dependency ${item.id} requires a normalized relative path`); if (item.sha256 !== null && !hash(item.sha256)) errors.push(`dependency ${item.id} has an invalid hash`); }
for (const item of findings) if (!obj(item) || !['error','warning','info'].includes(item.severity) || !text(item.code) || !text(item.subject) || !text(item.message)) errors.push('finding entries are invalid');

const expectedTotals = {collections:collections.length,objects:objects.length,meshes:meshes.length,materials:materials.length,images:images.length,armatures:armatures.length,actions:actions.length,nodeGroups:nodeGroups.length,modifiers:modifiers.length,simulations:simulations.length,dependencies:dependencies.length,cameras:objects.filter(o=>o.type==='CAMERA').length};
if (!obj(doc.totals)) errors.push('totals must be an object'); else for (const [key,value] of Object.entries(expectedTotals)) if (doc.totals[key] !== value) errors.push(`totals.${key} must equal ${value}`);

if (doc.profile === 'static-asset' && meshes.length === 0) errors.push('static-asset profile requires a mesh');
if (doc.profile === 'rigged-actor' && (meshes.length === 0 || armatures.length === 0 || actions.length === 0)) errors.push('rigged-actor profile requires mesh, armature, and action records');
if (doc.profile === 'procedural-scene' && !nodeGroups.some(n => n.realizationPolicy !== null)) errors.push('procedural-scene profile requires a realization policy');
if (doc.profile === 'render-scene' && (doc.render?.activeCamera === null || !objects.some(o => o.id === doc.render?.activeCamera && o.type === 'CAMERA'))) errors.push('render-scene profile requires an active camera');
if (doc.profile === 'simulation' && simulations.length === 0) errors.push('simulation profile requires a simulation record');

if (rootArg) {
  const root = fs.realpathSync(rootArg);
  const inside = candidate => candidate === root || candidate.startsWith(root + path.sep);
  const hasSymlinkComponent = relative => {
    let current = root;
    for (const part of relative.split('/')) {
      current = path.join(current, part);
      if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) return true;
    }
    return false;
  };
  const verifyFile = (relative, declaredHash, where) => {
    if (!relPath(relative)) return;
    const candidate = path.resolve(root, ...relative.split('/'));
    let actual;
    try { actual = fs.realpathSync(candidate); } catch { errors.push(`${where} is missing: ${relative}`); return; }
    if (!inside(actual) || hasSymlinkComponent(relative) || !fs.statSync(actual).isFile()) { errors.push(`${where} escapes the root, contains a symlink, or is not a regular file`); return; }
    if (declaredHash) { const actualHash=crypto.createHash('sha256').update(fs.readFileSync(actual)).digest('hex'); if (actualHash !== declaredHash) errors.push(`${where} hash mismatch`); }
  };
  verifyFile(doc.source?.path, doc.source?.sha256, 'source');
  for (const item of dependencies) if (!item.packed) { if (!item.insideRoot) errors.push(`dependency ${item.id} is marked external`); verifyFile(item.path, item.sha256, `dependency ${item.id}`); }
  for (const item of images) if (!item.packed) verifyFile(item.path, item.sha256, `image ${item.id}`);
  for (const item of simulations) if (requireClean && item.cache?.required && relPath(item.cache.path)) {
    const candidate = path.resolve(root, ...item.cache.path.split('/'));
    let actual;
    try { actual = fs.realpathSync(candidate); } catch { errors.push(`simulation ${item.id} cache is missing`); continue; }
    if (!inside(actual) || hasSymlinkComponent(item.cache.path)) errors.push(`simulation ${item.id} cache escapes the root or contains a symlink`);
  }
}

if (requireClean) {
  if (findings.some(f => f.severity === 'error')) errors.push('clean delivery rejects error findings');
  for (const mesh of meshes) if (Object.values(mesh.invalidTopology || {}).some(value => value > 0)) errors.push(`clean delivery rejects invalid topology on ${mesh.id}`);
  for (const item of dependencies) if (!item.packed && (!item.exists || !item.insideRoot)) errors.push(`clean delivery rejects missing or external dependency ${item.id}`);
  for (const item of simulations) if (item.cache?.required && (!item.cache.baked || !item.cache.resolved)) errors.push(`clean delivery rejects unresolved cache ${item.id}`);
}

if (errors.length) { for (const error of [...new Set(errors)]) console.error(`- ${error}`); process.exit(1); }
console.log(`Blender scene report validation passed (${doc.profile}, ${doc.blenderVersion}).`);
NODE
