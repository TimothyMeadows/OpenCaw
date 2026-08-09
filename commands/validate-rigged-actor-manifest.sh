#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-rigged-actor-manifest.sh <manifest> [--root <repo>] [--require-verified]

Validates an opencaw-rigged-actor/v1 JSON manifest. --root verifies every
declared file is a regular repository-confined file with the declared SHA-256.
--require-verified requires complete production-readiness evidence.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -ge 1 ]] || { usage >&2; exit 1; }
manifest="$1"
shift
root=""
require_verified="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--root requires a repository path." >&2; exit 1; }
      [[ -z "$root" ]] || { echo "--root may be provided only once." >&2; exit 1; }
      root="$2"
      shift 2
      ;;
    --require-verified)
      [[ "$require_verified" == "false" ]] || { echo "--require-verified may be provided only once." >&2; exit 1; }
      require_verified="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -f "$manifest" ]] || { echo "Manifest not found: $manifest" >&2; exit 1; }
if [[ -n "$root" ]]; then
  [[ -d "$root" ]] || { echo "Repository root not found: $root" >&2; exit 1; }
fi

node_bin="$(command -v node 2>/dev/null || command -v node.exe 2>/dev/null || true)"
[[ -n "$node_bin" ]] || { echo "Node.js is required to validate rigged actor manifests." >&2; exit 1; }

manifest_for_node="$(realpath "$manifest")"
root_for_node=""
if [[ -n "$root" ]]; then
  root_for_node="$(realpath "$root")"
fi
if [[ "$node_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then
  manifest_for_node="$(wslpath -w "$manifest_for_node")"
  if [[ -n "$root_for_node" ]]; then
    root_for_node="$(wslpath -w "$root_for_node")"
  fi
fi

"$node_bin" - "$manifest_for_node" "$root_for_node" "$require_verified" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const manifestPath = path.resolve(process.argv[2]);
const rootArgument = process.argv[3];
const requireVerified = process.argv[4] === 'true';
const errors = [];

let document;
try {
  document = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
} catch (error) {
  console.error(`Invalid manifest JSON: ${error.message}`);
  process.exit(1);
}

const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const nonEmptyString = value => typeof value === 'string' && value.trim().length > 0;
const validId = value => typeof value === 'string' && /^[a-z][a-z0-9-]*$/.test(value);
const validHash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const validDateTime = value => typeof value === 'string'
  && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(value)
  && !Number.isNaN(Date.parse(value));
const required = (object, fields, where) => {
  if (!isObject(object)) {
    errors.push(`${where} must be an object`);
    return false;
  }
  for (const field of fields) {
    if (!Object.prototype.hasOwnProperty.call(object, field)) errors.push(`${where}.${field} is required`);
  }
  return true;
};
const only = (object, fields, where) => {
  if (!isObject(object)) return;
  for (const field of Object.keys(object)) {
    if (!fields.includes(field)) errors.push(`${where}.${field} is not allowed`);
  }
};
const uniqueIds = (items, where) => {
  const seen = new Set();
  if (!Array.isArray(items)) return;
  items.forEach((item, index) => {
    if (!isObject(item) || !validId(item.id)) {
      errors.push(`${where}[${index}].id must be a lowercase kebab-case identifier`);
      return;
    }
    if (seen.has(item.id)) errors.push(`${where} contains duplicate id '${item.id}'`);
    seen.add(item.id);
  });
};

if (!isObject(document)) {
  console.error('Manifest must be a JSON object.');
  process.exit(1);
}

const topLevel = [
  'schemaVersion', 'actor', 'files', 'coordinateSystem', 'skeleton', 'sockets',
  'clips', 'equipment', 'detachableParts', 'colliders', 'budgets', 'provenance',
  'verification'
];
required(document, [
  'schemaVersion', 'actor', 'files', 'coordinateSystem', 'skeleton', 'sockets',
  'clips', 'colliders', 'budgets', 'provenance', 'verification'
], 'manifest');
only(document, topLevel, 'manifest');
if (document.schemaVersion !== 'opencaw-rigged-actor/v1') {
  errors.push('schemaVersion must be opencaw-rigged-actor/v1');
}

required(document.actor, ['id', 'displayName', 'kind', 'deliveryStage'], 'actor');
only(document.actor, ['id', 'displayName', 'kind', 'deliveryStage'], 'actor');
if (isObject(document.actor)) {
  if (!validId(document.actor.id)) errors.push('actor.id must be a lowercase kebab-case identifier');
  if (!nonEmptyString(document.actor.displayName)) errors.push('actor.displayName is required');
  if (!['character', 'monster'].includes(document.actor.kind)) errors.push('actor.kind must be character or monster');
  if (!['source', 'integration', 'shipped'].includes(document.actor.deliveryStage)) {
    errors.push('actor.deliveryStage must be source, integration, or shipped');
  }
  if (document.actor.deliveryStage === 'shipped' && !rootArgument) {
    errors.push('a shipped manifest requires --root so shipped files can be verified');
  }
  if (document.actor.kind === 'character') {
    if (!Object.prototype.hasOwnProperty.call(document, 'equipment')) errors.push('character manifests require equipment');
    if (Object.prototype.hasOwnProperty.call(document, 'detachableParts')) errors.push('character manifests must not define detachableParts');
  }
  if (document.actor.kind === 'monster') {
    if (!Object.prototype.hasOwnProperty.call(document, 'detachableParts')) errors.push('monster manifests require detachableParts');
    if (Object.prototype.hasOwnProperty.call(document, 'equipment')) errors.push('monster manifests must not define equipment');
  }
}

const declaredFiles = [];
const registerFile = (record, where, extensions = null) => {
  required(record, ['path', 'sha256'], where);
  only(record, ['path', 'sha256'], where);
  if (!isObject(record)) return;
  const relativePath = record.path;
  if (!nonEmptyString(relativePath)) {
    errors.push(`${where}.path is required`);
  } else {
    const normalized = path.posix.normalize(relativePath);
    const segments = relativePath.split('/');
    const invalid = relativePath.includes('\\')
      || relativePath.startsWith('/')
      || /^[A-Za-z]:/.test(relativePath)
      || relativePath.startsWith('//')
      || normalized !== relativePath
      || segments.some(segment => segment === '' || segment === '.' || segment === '..');
    if (invalid) errors.push(`${where}.path must be a normalized repository-relative path using forward slashes`);
    if (extensions && !extensions.includes(path.posix.extname(relativePath).toLowerCase())) {
      errors.push(`${where}.path must use one of: ${extensions.join(', ')}`);
    }
  }
  if (!validHash(record.sha256)) errors.push(`${where}.sha256 must be a lowercase SHA-256`);
  if (nonEmptyString(relativePath) && validHash(record.sha256)) {
    declaredFiles.push({ where, relativePath, sha256: record.sha256 });
  }
};

required(document.files, ['source', 'runtime'], 'files');
only(document.files, ['source', 'runtime'], 'files');
if (isObject(document.files)) {
  registerFile(document.files.source, 'files.source', ['.glb', '.gltf', '.fbx']);
  registerFile(document.files.runtime, 'files.runtime', ['.glb', '.gltf', '.fbx']);
  if (isObject(document.files.source) && isObject(document.files.runtime)
      && document.files.source.path === document.files.runtime.path) {
    errors.push('files.source.path and files.runtime.path must be different');
  }
}

required(document.coordinateSystem, [
  'unitsPerMeter', 'upAxis', 'forwardAxis', 'handedness', 'pivot', 'grounding'
], 'coordinateSystem');
only(document.coordinateSystem, [
  'unitsPerMeter', 'upAxis', 'forwardAxis', 'handedness', 'pivot', 'grounding'
], 'coordinateSystem');
if (isObject(document.coordinateSystem)) {
  if (!(typeof document.coordinateSystem.unitsPerMeter === 'number'
      && Number.isFinite(document.coordinateSystem.unitsPerMeter)
      && document.coordinateSystem.unitsPerMeter > 0)) {
    errors.push('coordinateSystem.unitsPerMeter must be a positive finite number');
  }
  const axes = ['+X', '-X', '+Y', '-Y', '+Z', '-Z'];
  if (!axes.includes(document.coordinateSystem.upAxis)) errors.push('coordinateSystem.upAxis is invalid');
  if (!axes.includes(document.coordinateSystem.forwardAxis)) errors.push('coordinateSystem.forwardAxis is invalid');
  if (axes.includes(document.coordinateSystem.upAxis) && axes.includes(document.coordinateSystem.forwardAxis)
      && document.coordinateSystem.upAxis.slice(1) === document.coordinateSystem.forwardAxis.slice(1)) {
    errors.push('coordinateSystem.upAxis and forwardAxis must use different dimensions');
  }
  if (!['left', 'right'].includes(document.coordinateSystem.handedness)) errors.push('coordinateSystem.handedness must be left or right');
  if (!nonEmptyString(document.coordinateSystem.pivot)) errors.push('coordinateSystem.pivot is required');
  if (!nonEmptyString(document.coordinateSystem.grounding)) errors.push('coordinateSystem.grounding is required');
}

required(document.skeleton, ['id', 'rootBone', 'bindPose', 'bones', 'maxInfluencesPerVertex'], 'skeleton');
only(document.skeleton, ['id', 'rootBone', 'bindPose', 'bones', 'maxInfluencesPerVertex'], 'skeleton');
const boneIds = new Set();
if (isObject(document.skeleton)) {
  if (!validId(document.skeleton.id)) errors.push('skeleton.id must be a lowercase kebab-case identifier');
  if (!validId(document.skeleton.rootBone)) errors.push('skeleton.rootBone must be a lowercase kebab-case identifier');
  if (!nonEmptyString(document.skeleton.bindPose)) errors.push('skeleton.bindPose is required');
  if (!Array.isArray(document.skeleton.bones) || document.skeleton.bones.length === 0) {
    errors.push('skeleton.bones must contain at least one bone identifier');
  } else {
    for (const [index, bone] of document.skeleton.bones.entries()) {
      if (!validId(bone)) errors.push(`skeleton.bones[${index}] must be a lowercase kebab-case identifier`);
      else if (boneIds.has(bone)) errors.push(`skeleton.bones contains duplicate id '${bone}'`);
      else boneIds.add(bone);
    }
    if (validId(document.skeleton.rootBone) && !boneIds.has(document.skeleton.rootBone)) {
      errors.push('skeleton.rootBone must be present in skeleton.bones');
    }
  }
  if (!Number.isInteger(document.skeleton.maxInfluencesPerVertex)
      || document.skeleton.maxInfluencesPerVertex < 1
      || document.skeleton.maxInfluencesPerVertex > 8) {
    errors.push('skeleton.maxInfluencesPerVertex must be an integer from 1 through 8');
  }
}

const socketIds = new Set();
if (!Array.isArray(document.sockets)) {
  errors.push('sockets must be an array');
} else {
  uniqueIds(document.sockets, 'sockets');
  document.sockets.forEach((socket, index) => {
    const where = `sockets[${index}]`;
    required(socket, ['id', 'parentBone', 'purpose'], where);
    only(socket, ['id', 'parentBone', 'purpose'], where);
    if (!isObject(socket)) return;
    if (validId(socket.id)) socketIds.add(socket.id);
    if (!validId(socket.parentBone) || !boneIds.has(socket.parentBone)) {
      errors.push(`${where}.parentBone must reference a declared skeleton bone`);
    }
    if (!nonEmptyString(socket.purpose)) errors.push(`${where}.purpose is required`);
  });
}

const requiredClipRoles = ['idle', 'locomotion', 'attack', 'hit-react', 'death'];
const clipRoles = new Set();
if (!Array.isArray(document.clips) || document.clips.length === 0) {
  errors.push('clips must contain animation records');
} else {
  uniqueIds(document.clips, 'clips');
  document.clips.forEach((clip, index) => {
    const where = `clips[${index}]`;
    required(clip, ['id', 'role', 'skeletonId', 'loop', 'rootMotion', 'events'], where);
    only(clip, ['id', 'role', 'skeletonId', 'loop', 'rootMotion', 'events'], where);
    if (!isObject(clip)) return;
    if (!validId(clip.role)) errors.push(`${where}.role must be a lowercase kebab-case identifier`);
    else clipRoles.add(clip.role);
    if (!isObject(document.skeleton) || clip.skeletonId !== document.skeleton.id) {
      errors.push(`${where}.skeletonId must match skeleton.id`);
    }
    if (typeof clip.loop !== 'boolean') errors.push(`${where}.loop must be a boolean`);
    if (!['none', 'extract', 'baked'].includes(clip.rootMotion)) errors.push(`${where}.rootMotion is invalid`);
    if (!Array.isArray(clip.events)) {
      errors.push(`${where}.events must be an array`);
    } else {
      uniqueIds(clip.events, `${where}.events`);
      clip.events.forEach((event, eventIndex) => {
        const eventWhere = `${where}.events[${eventIndex}]`;
        required(event, ['id', 'type', 'timeSeconds'], eventWhere);
        only(event, ['id', 'type', 'timeSeconds'], eventWhere);
        if (!isObject(event)) return;
        if (!validId(event.type)) errors.push(`${eventWhere}.type must be a lowercase kebab-case identifier`);
        if (!(typeof event.timeSeconds === 'number' && Number.isFinite(event.timeSeconds) && event.timeSeconds >= 0)) {
          errors.push(`${eventWhere}.timeSeconds must be a non-negative finite number`);
        }
      });
    }
  });
}
for (const role of requiredClipRoles) {
  if (!clipRoles.has(role)) errors.push(`clips are missing required action role '${role}'`);
}

const validateAttachments = (items, where) => {
  if (!Array.isArray(items)) {
    errors.push(`${where} must be an array`);
    return;
  }
  uniqueIds(items, where);
  items.forEach((item, index) => {
    const itemWhere = `${where}[${index}]`;
    required(item, ['id', 'socketId', 'path', 'sha256'], itemWhere);
    only(item, ['id', 'socketId', 'path', 'sha256'], itemWhere);
    if (!isObject(item)) return;
    if (!validId(item.socketId) || !socketIds.has(item.socketId)) {
      errors.push(`${itemWhere}.socketId must reference a declared socket`);
    }
    registerFile({ path: item.path, sha256: item.sha256 }, itemWhere, ['.glb', '.gltf', '.fbx']);
  });
};
if (isObject(document.actor) && document.actor.kind === 'character') validateAttachments(document.equipment, 'equipment');
if (isObject(document.actor) && document.actor.kind === 'monster') validateAttachments(document.detachableParts, 'detachableParts');

const requiredColliderRoles = ['navigation', 'hurt', 'attack', 'targeting'];
const colliderRoles = new Set();
if (!Array.isArray(document.colliders) || document.colliders.length === 0) {
  errors.push('colliders must contain collider records');
} else {
  uniqueIds(document.colliders, 'colliders');
  document.colliders.forEach((collider, index) => {
    const where = `colliders[${index}]`;
    required(collider, ['id', 'role', 'parentRef', 'shape'], where);
    only(collider, ['id', 'role', 'parentRef', 'shape'], where);
    if (!isObject(collider)) return;
    if (!validId(collider.role)) errors.push(`${where}.role must be a lowercase kebab-case identifier`);
    else colliderRoles.add(collider.role);
    if (!nonEmptyString(collider.shape)) errors.push(`${where}.shape is required`);
    if (!nonEmptyString(collider.parentRef) || !/^(bone|socket):[a-z][a-z0-9-]*$/.test(collider.parentRef)) {
      errors.push(`${where}.parentRef must use bone:<id> or socket:<id>`);
    } else {
      const [kind, id] = collider.parentRef.split(':');
      if (kind === 'bone' && !boneIds.has(id)) errors.push(`${where}.parentRef references an unknown bone`);
      if (kind === 'socket' && !socketIds.has(id)) errors.push(`${where}.parentRef references an unknown socket`);
    }
  });
}
for (const role of requiredColliderRoles) {
  if (!colliderRoles.has(role)) errors.push(`colliders are missing required role '${role}'`);
}

const budgetFields = ['triangles', 'bones', 'materials', 'textureBytes', 'runtimeBytes'];
required(document.budgets, budgetFields, 'budgets');
only(document.budgets, budgetFields, 'budgets');
if (isObject(document.budgets)) {
  for (const field of budgetFields) {
    if (!Number.isInteger(document.budgets[field]) || document.budgets[field] < 1) {
      errors.push(`budgets.${field} must be a positive integer`);
    }
  }
  if (Number.isInteger(document.budgets.bones) && boneIds.size > document.budgets.bones) {
    errors.push('declared skeleton bone count exceeds budgets.bones');
  }
}

required(document.provenance, ['sourceUri', 'author', 'license', 'rights', 'capturedAt'], 'provenance');
only(document.provenance, ['sourceUri', 'author', 'license', 'rights', 'capturedAt'], 'provenance');
if (isObject(document.provenance)) {
  for (const field of ['sourceUri', 'author', 'license']) {
    if (!nonEmptyString(document.provenance[field])) errors.push(`provenance.${field} is required`);
  }
  if (!['owned', 'licensed', 'cleared'].includes(document.provenance.rights)) errors.push('provenance.rights is invalid');
  if (!validDateTime(document.provenance.capturedAt)) errors.push('provenance.capturedAt must be a canonical UTC date-time');
}

const evidenceTypes = new Set();
required(document.verification, ['status', 'verifier', 'verifiedAt', 'evidence'], 'verification');
only(document.verification, ['status', 'verifier', 'verifiedAt', 'evidence'], 'verification');
if (isObject(document.verification)) {
  if (!['pending', 'verified', 'rejected'].includes(document.verification.status)) errors.push('verification.status is invalid');
  if (!(document.verification.verifier === null || nonEmptyString(document.verification.verifier))) {
    errors.push('verification.verifier must be null or a non-empty string');
  }
  if (!(document.verification.verifiedAt === null || validDateTime(document.verification.verifiedAt))) {
    errors.push('verification.verifiedAt must be null or a canonical UTC date-time');
  }
  if (!Array.isArray(document.verification.evidence)) {
    errors.push('verification.evidence must be an array');
  } else {
    uniqueIds(document.verification.evidence, 'verification.evidence');
    document.verification.evidence.forEach((evidence, index) => {
      const where = `verification.evidence[${index}]`;
      required(evidence, ['id', 'type', 'path', 'sha256', 'notes'], where);
      only(evidence, ['id', 'type', 'path', 'sha256', 'notes'], where);
      if (!isObject(evidence)) return;
      if (!['automated-test', 'runtime-capture', 'gameplay-review', 'performance-profile'].includes(evidence.type)) {
        errors.push(`${where}.type is invalid`);
      } else {
        evidenceTypes.add(evidence.type);
      }
      if (!nonEmptyString(evidence.notes)) errors.push(`${where}.notes is required`);
      registerFile({ path: evidence.path, sha256: evidence.sha256 }, where);
    });
  }
  if (document.verification.status === 'verified') {
    if (!nonEmptyString(document.verification.verifier)) errors.push('verified manifests require verification.verifier');
    if (!validDateTime(document.verification.verifiedAt)) errors.push('verified manifests require verification.verifiedAt');
    if (!Array.isArray(document.verification.evidence) || document.verification.evidence.length === 0) {
      errors.push('verified manifests require verification evidence');
    }
  }
}

if (requireVerified) {
  if (!isObject(document.verification) || document.verification.status !== 'verified') {
    errors.push('--require-verified requires verification.status to be verified');
  }
  for (const type of ['automated-test', 'runtime-capture', 'gameplay-review', 'performance-profile']) {
    if (!evidenceTypes.has(type)) errors.push(`--require-verified requires '${type}' evidence`);
  }
}

if (rootArgument) {
  let rootReal;
  try {
    rootReal = fs.realpathSync(path.resolve(rootArgument));
    if (!fs.statSync(rootReal).isDirectory()) throw new Error('not a directory');
  } catch (error) {
    errors.push(`repository root cannot be resolved: ${error.message}`);
  }
  if (rootReal) {
    const normalizeCase = value => process.platform === 'win32' ? value.toLowerCase() : value;
    const rootKey = normalizeCase(rootReal);
    const isWithinRoot = candidate => {
      const candidateKey = normalizeCase(candidate);
      return candidateKey === rootKey || candidateKey.startsWith(rootKey + path.sep);
    };
    for (const file of declaredFiles) {
      const candidate = path.resolve(rootReal, ...file.relativePath.split('/'));
      if (!isWithinRoot(candidate)) {
        errors.push(`${file.where}.path escapes the repository root`);
        continue;
      }
      let stat;
      try {
        stat = fs.lstatSync(candidate);
      } catch {
        errors.push(`${file.where}.path does not exist under --root`);
        continue;
      }
      if (stat.isSymbolicLink()) {
        errors.push(`${file.where}.path must not be a symbolic link`);
        continue;
      }
      if (!stat.isFile()) {
        errors.push(`${file.where}.path must be a regular file`);
        continue;
      }
      let realFile;
      try {
        realFile = fs.realpathSync(candidate);
      } catch (error) {
        errors.push(`${file.where}.path cannot be resolved: ${error.message}`);
        continue;
      }
      if (!isWithinRoot(realFile)) {
        errors.push(`${file.where}.path resolves outside the repository root`);
        continue;
      }
      const contents = fs.readFileSync(realFile);
      const actualHash = crypto.createHash('sha256').update(contents).digest('hex');
      if (actualHash !== file.sha256) errors.push(`${file.where}.sha256 does not match the file under --root`);
      if (file.where === 'files.runtime' && isObject(document.budgets)
          && Number.isInteger(document.budgets.runtimeBytes)
          && contents.length > document.budgets.runtimeBytes) {
        errors.push('runtime file size exceeds budgets.runtimeBytes');
      }
    }
  }
}

if (errors.length > 0) {
  [...new Set(errors)].sort().forEach(error => console.error(error));
  process.exit(1);
}

const kind = isObject(document.actor) ? document.actor.kind : 'unknown';
const stage = isObject(document.actor) ? document.actor.deliveryStage : 'unknown';
console.log(`Rigged actor manifest validation passed (${kind}, ${stage}, ${document.clips.length} clip(s)).`);
NODE
