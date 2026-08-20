'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const {
  PASS_IDS,
  rootPath,
  relativeInside,
  sha256,
  validateManifest
} = require('./code-model-cli.cjs');

const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const SHA_PATTERN = /^[a-f0-9]{64}$/;
const DECISIONS = new Set(['pass', 'revise-spec', 'revise-code', 'request-input', 'stop']);
const GATE_TYPES = new Set(['machine', 'reviewer']);
const GATE_STATUSES = new Set(['pending', 'active', 'passed', 'blocked', 'stopped']);
const VIEWS = new Set(['front', 'rear', 'left', 'right', 'top', 'bottom', 'orbit-left', 'orbit-right', 'hero', 'runtime']);
const GATE_CONTRACTS = [
  ['blockout-readability', 'blockout', 'reviewer', 'character-readability', 'Frozen identity and silhouette intent', 'Confirm the whole character reads at its intended presentation scale.'],
  ['structure-integrity', 'structure', 'machine', 'structure-integrity', 'Declared body plan and transforms', 'Confirm grounding, relationships, symmetry, and attachments are structurally coherent.'],
  ['form-readability', 'form', 'reviewer', 'part-readability', 'Whole character and selected semantic parts', 'Confirm required and signature parts read without detached or ambiguous form.'],
  ['materials-style', 'materials', 'reviewer', 'materials-style', 'Active style contract and focal hierarchy', 'Confirm material and value choices support the declared identity and style.'],
  ['interaction-runtime', 'interaction', 'machine', 'runtime-behavior', 'Declared motion and interaction context', 'Confirm applicable motion, contacts, sockets, colliders, and teardown behavior.'],
  ['optimization-budget', 'optimization', 'machine', 'runtime-budget', 'Representative actor count and target budgets', 'Confirm deterministic construction, budgets, and repeated lifecycle ownership.']
];

function fail(message) {
  throw new Error(message);
}

function textSha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}

function objectSha256(value) {
  return textSha256(JSON.stringify(canonical(value)));
}

function parseOptions(values, repeatable = new Set(), flags = new Set()) {
  const options = { _: [] };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith('--')) {
      options._.push(value);
      continue;
    }
    const key = value.slice(2);
    if (flags.has(key)) {
      options[key] = true;
      continue;
    }
    if (index + 1 >= values.length || values[index + 1].startsWith('--')) fail(`--${key} requires a value.`);
    const next = values[++index];
    if (repeatable.has(key)) {
      if (!options[key]) options[key] = [];
      options[key].push(next);
    } else if (options[key] !== undefined) fail(`--${key} may be provided only once.`);
    else options[key] = next;
  }
  return options;
}

function rejectUnknownOptions(options, allowed) {
  for (const key of Object.keys(options)) {
    if (key !== '_' && !allowed.has(key)) fail(`Unknown option: --${key}`);
  }
}

function requireObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label} must be an object.`);
  return value;
}

function onlyKeys(value, allowed, label) {
  requireObject(value, label);
  const extra = Object.keys(value).filter((key) => !allowed.includes(key));
  if (extra.length) fail(`${label} contains unsupported fields: ${extra.join(', ')}`);
}

function requireString(value, label, allowEmpty = false) {
  if (typeof value !== 'string' || (!allowEmpty && !value.trim())) fail(`${label} must be ${allowEmpty ? 'a string' : 'a non-empty string'}.`);
  return value;
}

function requireId(value, label) {
  requireString(value, label);
  if (!ID_PATTERN.test(value)) fail(`${label} must be lowercase kebab-case.`);
  return value;
}

function requireInteger(value, label, minimum = 0) {
  if (!Number.isInteger(value) || value < minimum) fail(`${label} must be an integer >= ${minimum}.`);
  return value;
}

function requireNumberOrNull(value, label) {
  if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
    fail(`${label} must be null or a finite non-negative number.`);
  }
}

function requireArray(value, label, minimum = 0) {
  if (!Array.isArray(value) || value.length < minimum) fail(`${label} must contain at least ${minimum} item(s).`);
  return value;
}

function requireUniqueStrings(value, label, minimum = 0, ids = false) {
  requireArray(value, label, minimum);
  const seen = new Set();
  for (const [index, entry] of value.entries()) {
    if (ids) requireId(entry, `${label}[${index}]`);
    else requireString(entry, `${label}[${index}]`);
    if (seen.has(entry)) fail(`${label} contains a duplicate: ${entry}`);
    seen.add(entry);
  }
  return value;
}

function readJson(file, label) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
  }
}

function atomicWrite(file, value, expectedSha = null) {
  if (expectedSha && sha256(file) !== expectedSha) fail('Character profile changed during the operation; retry from current state.');
  const temporary = `${file}.tmp-${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
  let installed = false;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: 'wx' });
    fs.renameSync(temporary, file);
    installed = true;
  } finally {
    if (!installed && fs.existsSync(temporary)) fs.rmSync(temporary, { force: true });
  }
}

function withProfileLock(profileFile, callback) {
  const lock = `${profileFile}.lock`;
  try {
    fs.mkdirSync(lock);
  } catch (error) {
    if (error.code === 'EEXIST') fail(`Character profile is locked by another operation: ${lock}`);
    throw error;
  }
  try {
    return callback();
  } finally {
    fs.rmdirSync(lock);
  }
}

function relativeArtifact(root, value, label) {
  const located = relativeInside(root, value, label, true);
  const stat = fs.lstatSync(located.absolute);
  if (!stat.isFile() || stat.isSymbolicLink()) fail(`${label} must be a regular non-symbolic-link file.`);
  return located;
}

function manifestContractProjection(manifest) {
  const projection = JSON.parse(JSON.stringify(manifest));
  delete projection.passes;
  return projection;
}

function profileContractProjection(profile) {
  const projection = JSON.parse(JSON.stringify(profile));
  for (const gate of projection.gates ?? []) {
    delete gate.status;
    delete gate.attempts;
    delete gate.results;
  }
  return projection;
}

function contractHashes(profile, manifest) {
  return {
    manifest: objectSha256(manifestContractProjection(manifest)),
    profile: objectSha256(profileContractProjection(profile))
  };
}

function linkedModel(root, profile, mode = 'base', requireSource = false) {
  const linked = relativeArtifact(root, profile.codeModel.manifest, 'Linked code-model manifest');
  const validated = validateManifest(root, linked.absolute, mode === 'complete' ? 'complete' : 'base');
  if (validated.manifest.modelId !== profile.codeModel.modelId) {
    fail(`Linked code-model modelId ${validated.manifest.modelId} does not match ${profile.codeModel.modelId}.`);
  }
  const source = requireSource
    ? relativeArtifact(root, validated.manifest.target.sourcePath, 'Linked code-model source')
    : relativeInside(root, validated.manifest.target.sourcePath, 'Linked code-model source');
  return { ...validated, linked, source };
}

function validatePathHash(root, record, label, usedPaths = null) {
  onlyKeys(record, ['path', 'sha256'], label);
  const located = relativeArtifact(root, record.path, `${label} path`);
  if (!SHA_PATTERN.test(record.sha256 ?? '') || sha256(located.absolute) !== record.sha256) fail(`${label} hash does not match.`);
  if (usedPaths) {
    if (usedPaths.has(located.relative)) fail(`Evidence path is reused: ${located.relative}`);
    usedPaths.add(located.relative);
  }
  return located;
}

function validateIdentityList(items, label, allowedParents = null) {
  const seen = new Set();
  requireArray(items, label);
  items.forEach((item, index) => {
    requireObject(item, `${label}[${index}]`);
    requireId(item.id, `${label}[${index}].id`);
    if (seen.has(item.id)) fail(`${label} repeats id ${item.id}.`);
    seen.add(item.id);
  });
  if (allowedParents) {
    items.forEach((item, index) => {
      if (item.parent !== null && !allowedParents.has(item.parent)) fail(`${label}[${index}].parent references unknown id ${item.parent}.`);
    });
  }
  return seen;
}

function requireAcyclicParents(items, label) {
  const parents = new Map(items.map((item) => [item.id, item.parent]));
  const complete = new Set();
  for (const item of items) {
    if (complete.has(item.id)) continue;
    const active = new Set();
    let current = item.id;
    while (current !== null) {
      if (active.has(current)) fail(`${label} contains a parent cycle at ${current}.`);
      if (complete.has(current)) break;
      active.add(current);
      current = parents.get(current) ?? null;
    }
    for (const id of active) complete.add(id);
  }
}

function gateExpectedStatus(gate) {
  const latest = gate.results.at(-1)?.decision;
  if (latest === 'pass') return 'passed';
  if (latest === 'request-input') return 'blocked';
  if (latest === 'stop') return 'stopped';
  return gate.attempts > 0 || gate.status === 'active' ? 'active' : 'pending';
}

function validateProfile(root, profileValue, mode = 'base', profilePath = null) {
  const located = profilePath ? relativeArtifact(root, profilePath, 'Character profile') : null;
  const profile = profileValue !== null && typeof profileValue === 'object'
    ? profileValue
    : readJson(located.absolute, 'Character profile');
  onlyKeys(profile, ['schemaVersion', 'characterId', 'title', 'codeModel', 'intent', 'silhouette', 'structure', 'motion', 'budgets', 'reviewPolicy', 'gates'], 'profile');
  if (profile.schemaVersion !== 'opencaw-code-character/v1') fail('schemaVersion must be opencaw-code-character/v1.');
  requireId(profile.characterId, 'characterId');
  requireString(profile.title, 'title');

  onlyKeys(profile.codeModel, ['manifest', 'modelId'], 'codeModel');
  requireString(profile.codeModel.manifest, 'codeModel.manifest');
  requireId(profile.codeModel.modelId, 'codeModel.modelId');

  onlyKeys(profile.intent, ['kind', 'brief', 'intendedUse', 'presentation', 'temperament', 'identity', 'signatureParts'], 'intent');
  if (!['character', 'creature'].includes(profile.intent.kind)) fail('intent.kind must be character or creature.');
  for (const key of ['brief', 'intendedUse', 'temperament', 'identity']) requireString(profile.intent[key], `intent.${key}`);
  requireUniqueStrings(profile.intent.signatureParts, 'intent.signatureParts', 1, true);
  onlyKeys(profile.intent.presentation, ['distance', 'pixelHeights', 'representativeActors'], 'intent.presentation');
  if (!['close', 'mid', 'far', 'mixed'].includes(profile.intent.presentation.distance)) fail('intent.presentation.distance is invalid.');
  requireArray(profile.intent.presentation.pixelHeights, 'intent.presentation.pixelHeights', 1);
  const pixelSet = new Set();
  for (const height of profile.intent.presentation.pixelHeights) {
    requireInteger(height, 'intent.presentation.pixelHeights item', 8);
    if (height > 4096 || pixelSet.has(height)) fail('intent.presentation.pixelHeights must contain unique values between 8 and 4096.');
    pixelSet.add(height);
  }
  requireInteger(profile.intent.presentation.representativeActors, 'intent.presentation.representativeActors', 1);

  onlyKeys(profile.silhouette, ['primaryView', 'requiredViews', 'negativeSpace', 'asymmetryPolicy', 'questions'], 'silhouette');
  if (!VIEWS.has(profile.silhouette.primaryView)) fail('silhouette.primaryView is invalid.');
  requireUniqueStrings(profile.silhouette.requiredViews, 'silhouette.requiredViews', 1);
  for (const view of profile.silhouette.requiredViews) if (!VIEWS.has(view)) fail(`Unknown silhouette view: ${view}`);
  if (!profile.silhouette.requiredViews.includes(profile.silhouette.primaryView)) fail('silhouette.requiredViews must include primaryView.');
  requireString(profile.silhouette.negativeSpace, 'silhouette.negativeSpace');
  requireString(profile.silhouette.asymmetryPolicy, 'silhouette.asymmetryPolicy');
  requireUniqueStrings(profile.silhouette.questions, 'silhouette.questions', 1);

  onlyKeys(profile.structure, ['coordinateSystem', 'pivot', 'grounding', 'parts', 'joints', 'symmetryGroups', 'attachments', 'sockets', 'colliders'], 'structure');
  for (const key of ['coordinateSystem', 'pivot', 'grounding']) requireString(profile.structure[key], `structure.${key}`);
  const partIds = validateIdentityList(profile.structure.parts, 'structure.parts');
  profile.structure.parts.forEach((part, index) => {
    onlyKeys(part, ['id', 'parent', 'role', 'required'], `structure.parts[${index}]`);
    if (part.parent !== null) requireId(part.parent, `structure.parts[${index}].parent`);
    if (!['primary', 'secondary', 'detail'].includes(part.role)) fail(`structure.parts[${index}].role is invalid.`);
    if (typeof part.required !== 'boolean') fail(`structure.parts[${index}].required must be boolean.`);
  });
  profile.structure.parts.forEach((part) => { if (part.parent !== null && !partIds.has(part.parent)) fail(`Part ${part.id} references unknown parent ${part.parent}.`); });
  requireAcyclicParents(profile.structure.parts, 'structure.parts');
  for (const signature of profile.intent.signatureParts) if (!partIds.has(signature)) fail(`Signature part is not declared in structure.parts: ${signature}`);

  const jointIds = validateIdentityList(profile.structure.joints, 'structure.joints');
  profile.structure.joints.forEach((joint, index) => {
    onlyKeys(joint, ['id', 'parent', 'semantic'], `structure.joints[${index}]`);
    if (joint.parent !== null) requireId(joint.parent, `structure.joints[${index}].parent`);
    requireString(joint.semantic, `structure.joints[${index}].semantic`);
    if (joint.parent !== null && !jointIds.has(joint.parent)) fail(`Joint ${joint.id} references unknown parent ${joint.parent}.`);
  });
  requireAcyclicParents(profile.structure.joints, 'structure.joints');
  const parentIds = new Set([...partIds, ...jointIds]);
  const symmetryIds = validateIdentityList(profile.structure.symmetryGroups, 'structure.symmetryGroups');
  void symmetryIds;
  profile.structure.symmetryGroups.forEach((group, index) => {
    onlyKeys(group, ['id', 'members', 'toleranceRatio'], `structure.symmetryGroups[${index}]`);
    requireUniqueStrings(group.members, `structure.symmetryGroups[${index}].members`, 2, true);
    for (const member of group.members) if (!partIds.has(member)) fail(`Symmetry member is not a declared part: ${member}`);
    if (typeof group.toleranceRatio !== 'number' || group.toleranceRatio < 0 || group.toleranceRatio > 1) fail(`structure.symmetryGroups[${index}].toleranceRatio must be between 0 and 1.`);
  });
  for (const [index, attachment] of requireArray(profile.structure.attachments, 'structure.attachments').entries()) {
    onlyKeys(attachment, ['part', 'host', 'toleranceRatio'], `structure.attachments[${index}]`);
    requireId(attachment.part, `structure.attachments[${index}].part`);
    requireId(attachment.host, `structure.attachments[${index}].host`);
    if (!partIds.has(attachment.part) || !partIds.has(attachment.host)) fail(`structure.attachments[${index}] references an unknown part.`);
    if (attachment.part === attachment.host) fail(`structure.attachments[${index}] cannot attach a part to itself.`);
    if (typeof attachment.toleranceRatio !== 'number' || attachment.toleranceRatio < 0 || attachment.toleranceRatio > 1) fail(`structure.attachments[${index}].toleranceRatio must be between 0 and 1.`);
  }
  const socketIds = validateIdentityList(profile.structure.sockets, 'structure.sockets');
  profile.structure.sockets.forEach((socket, index) => {
    onlyKeys(socket, ['id', 'parent', 'purpose'], `structure.sockets[${index}]`);
    requireId(socket.parent, `structure.sockets[${index}].parent`);
    requireString(socket.purpose, `structure.sockets[${index}].purpose`);
    if (!parentIds.has(socket.parent)) fail(`Socket ${socket.id} references unknown parent ${socket.parent}.`);
  });
  const colliderIds = validateIdentityList(profile.structure.colliders, 'structure.colliders');
  void colliderIds;
  profile.structure.colliders.forEach((collider, index) => {
    onlyKeys(collider, ['id', 'kind', 'parent', 'shape'], `structure.colliders[${index}]`);
    if (!['navigation', 'hurt', 'attack', 'targeting', 'interaction'].includes(collider.kind)) fail(`structure.colliders[${index}].kind is invalid.`);
    requireId(collider.parent, `structure.colliders[${index}].parent`);
    requireString(collider.shape, `structure.colliders[${index}].shape`);
    if (!parentIds.has(collider.parent) && !socketIds.has(collider.parent)) fail(`Collider ${collider.id} references unknown parent ${collider.parent}.`);
  });

  onlyKeys(profile.motion, ['mode', 'skeletonId', 'maxInfluencesPerVertex', 'requiredRoles', 'clips', 'representativePoses'], 'motion');
  if (!['static', 'articulated', 'skinned'].includes(profile.motion.mode)) fail('motion.mode is invalid.');
  if (profile.motion.skeletonId !== null) requireId(profile.motion.skeletonId, 'motion.skeletonId');
  requireInteger(profile.motion.maxInfluencesPerVertex, 'motion.maxInfluencesPerVertex');
  requireUniqueStrings(profile.motion.requiredRoles, 'motion.requiredRoles', 0, true);
  requireUniqueStrings(profile.motion.representativePoses, 'motion.representativePoses', 0, true);
  const clipIds = new Set();
  const clipRoles = new Set();
  for (const [index, clip] of requireArray(profile.motion.clips, 'motion.clips').entries()) {
    onlyKeys(clip, ['id', 'role', 'loop', 'rootMotion', 'contacts'], `motion.clips[${index}]`);
    requireId(clip.id, `motion.clips[${index}].id`);
    requireId(clip.role, `motion.clips[${index}].role`);
    if (clipIds.has(clip.id)) fail(`motion.clips repeats id ${clip.id}.`);
    clipIds.add(clip.id); clipRoles.add(clip.role);
    if (typeof clip.loop !== 'boolean') fail(`motion.clips[${index}].loop must be boolean.`);
    if (!['none', 'runtime', 'baked'].includes(clip.rootMotion)) fail(`motion.clips[${index}].rootMotion is invalid.`);
    requireUniqueStrings(clip.contacts, `motion.clips[${index}].contacts`, 0, true);
  }
  for (const role of profile.motion.requiredRoles) if (!clipRoles.has(role)) fail(`Required motion role has no clip: ${role}`);
  if (profile.motion.mode === 'static' && (profile.motion.skeletonId !== null || profile.motion.maxInfluencesPerVertex !== 0 || profile.motion.clips.length)) fail('Static motion must not declare a skeleton, influences, or clips.');
  if (profile.motion.mode === 'skinned' && (profile.motion.skeletonId === null || profile.motion.maxInfluencesPerVertex < 1)) fail('Skinned motion requires skeletonId and positive maxInfluencesPerVertex.');

  onlyKeys(profile.budgets, ['bones', 'clips', 'shaderVariants', 'textureBytes', 'representativeActors', 'cpuMilliseconds', 'gpuMilliseconds'], 'budgets');
  for (const key of ['bones', 'clips', 'shaderVariants', 'textureBytes']) requireInteger(profile.budgets[key], `budgets.${key}`);
  requireInteger(profile.budgets.representativeActors, 'budgets.representativeActors', 1);
  requireNumberOrNull(profile.budgets.cpuMilliseconds, 'budgets.cpuMilliseconds');
  requireNumberOrNull(profile.budgets.gpuMilliseconds, 'budgets.gpuMilliseconds');
  if (profile.budgets.representativeActors !== profile.intent.presentation.representativeActors) fail('Character and presentation representative actor budgets must match.');
  if (profile.motion.clips.length > profile.budgets.clips) fail('Declared clips exceed the clip budget.');

  onlyKeys(profile.reviewPolicy, ['builderIds', 'independentReview', 'maxGateAttempts', 'repeatedFailureLimit'], 'reviewPolicy');
  requireUniqueStrings(profile.reviewPolicy.builderIds, 'reviewPolicy.builderIds', 1, true);
  if (profile.reviewPolicy.independentReview !== true) fail('reviewPolicy.independentReview must be true.');
  requireInteger(profile.reviewPolicy.maxGateAttempts, 'reviewPolicy.maxGateAttempts', 1);
  requireInteger(profile.reviewPolicy.repeatedFailureLimit, 'reviewPolicy.repeatedFailureLimit', 1);
  if (profile.reviewPolicy.repeatedFailureLimit > profile.reviewPolicy.maxGateAttempts) fail('repeatedFailureLimit cannot exceed maxGateAttempts.');

  requireArray(profile.gates, 'gates', GATE_CONTRACTS.length);
  if (profile.gates.length !== GATE_CONTRACTS.length) fail(`gates must contain exactly ${GATE_CONTRACTS.length} entries.`);
  const gateIds = new Set();
  const usedEvidencePaths = new Set();
  let lastPassIndex = -1;
  let activeCount = 0;
  let encounteredRequiredIncomplete = false;
  const hasResults = profile.gates.some((gate) => Array.isArray(gate?.results) && gate.results.length > 0);
  const currentLinked = linkedModel(root, profile, mode, mode === 'complete' || hasResults);
  const currentHashes = contractHashes(profile, currentLinked.manifest);
  const currentSourceSha = fs.existsSync(currentLinked.source.absolute) ? sha256(currentLinked.source.absolute) : null;
  const passCoverage = new Set();
  for (const [gateIndex, gate] of profile.gates.entries()) {
    const label = `gates[${gateIndex}]`;
    const [expectedId, expectedPass, expectedType] = GATE_CONTRACTS[gateIndex];
    onlyKeys(gate, ['id', 'pass', 'type', 'required', 'status', 'claim', 'calibration', 'attempts', 'results'], label);
    requireId(gate.id, `${label}.id`);
    if (gate.id !== expectedId || gate.pass !== expectedPass || gate.type !== expectedType || gate.required !== true) {
      fail(`${label} must be required ${expectedType} gate ${expectedId} for ${expectedPass}.`);
    }
    if (gateIds.has(gate.id)) fail(`gates repeats id ${gate.id}.`);
    gateIds.add(gate.id);
    const passIndex = PASS_IDS.indexOf(gate.pass);
    if (passIndex < 0 || passIndex < lastPassIndex) fail('gates must follow the generic CODE pass order.');
    lastPassIndex = passIndex; passCoverage.add(gate.pass);
    if (!GATE_TYPES.has(gate.type)) fail(`${label}.type is invalid.`);
    if (typeof gate.required !== 'boolean') fail(`${label}.required must be boolean.`);
    if (!GATE_STATUSES.has(gate.status)) fail(`${label}.status is invalid.`);
    if (gate.status === 'active') activeCount += 1;
    onlyKeys(gate.claim, ['kind', 'context', 'rationale', 'thresholds'], `${label}.claim`);
    requireId(gate.claim.kind, `${label}.claim.kind`);
    requireString(gate.claim.context, `${label}.claim.context`);
    requireString(gate.claim.rationale, `${label}.claim.rationale`);
    requireObject(gate.claim.thresholds, `${label}.claim.thresholds`);
    onlyKeys(gate.calibration, ['passing', 'failing'], `${label}.calibration`);
    for (const category of ['passing', 'failing']) {
      requireArray(gate.calibration[category], `${label}.calibration.${category}`);
      for (const [index, item] of gate.calibration[category].entries()) validatePathHash(root, item, `${label}.calibration.${category}[${index}]`);
    }
    requireInteger(gate.attempts, `${label}.attempts`);
    if (gate.attempts > profile.reviewPolicy.maxGateAttempts) fail(`${gate.id} exceeds maxGateAttempts.`);
    if (!Array.isArray(gate.results) || gate.results.length !== gate.attempts) fail(`${gate.id} result count must equal attempts.`);
    let priorCreated = '';
    const failureClassCounts = new Map();
    for (const [resultIndex, result] of gate.results.entries()) {
      const resultLabel = `${label}.results[${resultIndex}]`;
      onlyKeys(result, ['decision', 'summary', 'remainingGaps', 'failureClass', 'strategySummary', 'strategySha256', 'reviewer', 'evidence', 'manifestContractSha256', 'profileContractSha256', 'sourceSha256', 'createdAt'], resultLabel);
      if (!DECISIONS.has(result.decision)) fail(`${resultLabel}.decision is invalid.`);
      requireString(result.summary, `${resultLabel}.summary`);
      requireString(result.remainingGaps, `${resultLabel}.remainingGaps`, true);
      requireString(result.failureClass, `${resultLabel}.failureClass`, true);
      requireString(result.strategySummary, `${resultLabel}.strategySummary`);
      if (result.strategySha256 !== textSha256(result.strategySummary)) fail(`${resultLabel}.strategySha256 does not match strategySummary.`);
      if (result.decision === 'pass' && result.failureClass) fail(`${resultLabel}.failureClass must be empty for pass.`);
      if (result.decision !== 'pass' && !result.failureClass) fail(`${resultLabel}.failureClass is required for non-pass decisions.`);
      if (result.decision !== 'pass') requireId(result.failureClass, `${resultLabel}.failureClass`);
      const previousResult = gate.results[resultIndex - 1];
      if (previousResult && previousResult.decision !== 'pass' && previousResult.strategySha256 === result.strategySha256) {
        fail(`${gate.id} reused a strategy after a failed result.`);
      }
      if (previousResult && ['pass', 'stop'].includes(previousResult.decision)) {
        fail(`${gate.id} contains a result after terminal decision ${previousResult.decision}.`);
      }
      if (result.decision !== 'pass') {
        const failureCount = (failureClassCounts.get(result.failureClass) ?? 0) + 1;
        failureClassCounts.set(result.failureClass, failureCount);
        if (result.decision === 'revise-code' && failureCount >= profile.reviewPolicy.repeatedFailureLimit) {
          fail(`${gate.id} continued revise-code after repeated failure class ${result.failureClass}.`);
        }
      }
      if (!SHA_PATTERN.test(result.manifestContractSha256 ?? '') || !SHA_PATTERN.test(result.profileContractSha256 ?? '') || !SHA_PATTERN.test(result.sourceSha256 ?? '')) fail(`${resultLabel} contains an invalid contract or source hash.`);
      const createdAtMilliseconds = Date.parse(result.createdAt);
      if (Number.isNaN(createdAtMilliseconds) || new Date(createdAtMilliseconds).toISOString() !== result.createdAt) {
        fail(`${resultLabel}.createdAt must be canonical UTC.`);
      }
      if (priorCreated && result.createdAt < priorCreated) fail(`${gate.id} results are not chronological.`);
      priorCreated = result.createdAt;
      requireArray(result.evidence, `${resultLabel}.evidence`, 1);
      for (const [evidenceIndex, evidence] of result.evidence.entries()) {
        onlyKeys(evidence, ['kind', 'path', 'sha256'], `${resultLabel}.evidence[${evidenceIndex}]`);
        requireId(evidence.kind, `${resultLabel}.evidence[${evidenceIndex}].kind`);
        validatePathHash(root, { path: evidence.path, sha256: evidence.sha256 }, `${resultLabel}.evidence[${evidenceIndex}]`, usedEvidencePaths);
      }
      if (gate.type === 'reviewer') {
        requireObject(result.reviewer, `${resultLabel}.reviewer`);
        onlyKeys(result.reviewer, ['id', 'type', 'packetPath', 'packetSha256', 'observedAnswer'], `${resultLabel}.reviewer`);
        requireId(result.reviewer.id, `${resultLabel}.reviewer.id`);
        if (profile.reviewPolicy.builderIds.includes(result.reviewer.id)) fail(`${gate.id} reviewer is also an active builder.`);
        if (!['agent', 'human'].includes(result.reviewer.type)) fail(`${resultLabel}.reviewer.type is invalid.`);
        requireString(result.reviewer.observedAnswer, `${resultLabel}.reviewer.observedAnswer`);
        const packet = validatePathHash(root, { path: result.reviewer.packetPath, sha256: result.reviewer.packetSha256 }, `${resultLabel}.reviewer packet`);
        if (!result.evidence.some((entry) => entry.kind === 'reviewer-packet' && entry.path === packet.relative)) fail(`${resultLabel} must include its reviewer packet as reviewer-packet evidence.`);
      } else if (result.reviewer !== null) fail(`${resultLabel}.reviewer must be null for machine gates.`);
    }
    const expectedStatus = gateExpectedStatus(gate);
    if (gate.status !== expectedStatus) fail(`${gate.id} status does not match its latest result.`);
    if (gate.required) {
      if (gate.status !== 'passed') encounteredRequiredIncomplete = true;
      else if (encounteredRequiredIncomplete) fail(`Required gate ${gate.id} passed after an earlier required gate remained incomplete.`);
    }
    const latest = gate.results.at(-1);
    if (gate.status === 'passed' && latest) {
      if (latest.manifestContractSha256 !== currentHashes.manifest || latest.profileContractSha256 !== currentHashes.profile || latest.sourceSha256 !== currentSourceSha) {
        if (mode === 'complete') fail(`Passing gate ${gate.id} is stale against the current profile, manifest, or source.`);
      }
    }
    if (mode === 'complete' && gate.required && gate.status !== 'passed') fail(`Required gate is incomplete: ${gate.id}`);
    if (mode === 'complete' && gate.type === 'machine' && gate.required) {
      if (!gate.calibration.passing.length || !gate.calibration.failing.length) fail(`Machine gate ${gate.id} requires passing and failing calibration evidence.`);
    }
  }
  if (activeCount > 1) fail('Only one character gate may be active.');
  for (const pass of PASS_IDS) if (!passCoverage.has(pass)) fail(`Character gates do not cover CODE pass: ${pass}`);
  if (mode === 'complete' && profile.gates.some((gate) => gate.required && gate.status !== 'passed')) fail('Every required character gate must pass for complete validation.');
  if (mode === 'strict' || mode === 'complete') {
    const serialized = JSON.stringify(profile);
    if (/<[^>]+>|\bTODO\b|\bTBD\b/i.test(serialized)) fail('Strict character profiles must not contain placeholders.');
  }
  return { profile, located, linked: currentLinked, hashes: currentHashes, sourceSha256: currentSourceSha };
}

function defaultGates() {
  return GATE_CONTRACTS.map(([id, pass, type, kind, context, rationale], index) => ({
    id, pass, type, required: true, status: index === 0 ? 'active' : 'pending',
    claim: { kind, context, rationale, thresholds: {} },
    calibration: { passing: [], failing: [] }, attempts: 0, results: []
  }));
}

function positiveInteger(value, fallback, label, minimum = 1) {
  if (value === undefined) return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum) fail(`${label} must be an integer >= ${minimum}.`);
  return parsed;
}

function create(root, values) {
  const options = parseOptions(values, new Set(['signature-part', 'builder', 'view', 'pixel-height', 'animation-role']));
  rejectUnknownOptions(options, new Set(['manifest', 'output', 'title', 'kind', 'brief', 'intended-use', 'presentation-distance', 'representative-actors', 'temperament', 'identity', 'signature-part', 'builder', 'view', 'pixel-height', 'motion-mode', 'skeleton-id', 'max-influences', 'animation-role', 'max-gate-attempts', 'repeated-failure-limit']));
  if (options._.length !== 1) fail('Create requires exactly one CHARACTER_ID.');
  const characterId = requireId(options._[0], 'CHARACTER_ID');
  requireString(options.manifest, '--manifest');
  requireString(options.brief, '--brief');
  requireString(options['intended-use'], '--intended-use');
  const linked = relativeArtifact(root, options.manifest, 'Linked code-model manifest');
  const linkedValidation = validateManifest(root, linked.absolute, 'base');
  const output = relativeInside(root, options.output ?? `.ai/tasks/${characterId}/code-character.json`, 'Character profile output');
  if (!output.relative.startsWith('.ai/tasks/')) fail('Character profile output must be below .ai/tasks/.');
  if (fs.existsSync(output.absolute)) fail(`Character profile already exists: ${output.relative}`);
  fs.mkdirSync(path.dirname(output.absolute), { recursive: true });
  const modelParts = linkedValidation.manifest.runtime.parts;
  const signatureParts = options['signature-part'] ?? [modelParts[0]];
  for (const part of signatureParts) if (!modelParts.includes(part)) fail(`Signature part is not declared by the generic manifest: ${part}`);
  const views = options.view ?? ['front', 'left', 'right', 'hero'];
  for (const view of views) if (!VIEWS.has(view)) fail(`Unknown --view: ${view}`);
  const pixelHeights = (options['pixel-height'] ?? ['32', '96']).map((value) => positiveInteger(value, undefined, '--pixel-height', 8));
  const representativeActors = positiveInteger(options['representative-actors'], 1, '--representative-actors');
  const motionMode = options['motion-mode'] ?? 'static';
  if (!['static', 'articulated', 'skinned'].includes(motionMode)) fail('--motion-mode must be static, articulated, or skinned.');
  const requiredRoles = options['animation-role'] ?? [];
  const clips = requiredRoles.map((role) => ({ id: role, role, loop: role !== 'action', rootMotion: 'none', contacts: [] }));
  const maxInfluences = positiveInteger(options['max-influences'], motionMode === 'skinned' ? 4 : 0, '--max-influences', 0);
  const skeletonId = motionMode === 'skinned' ? requireId(options['skeleton-id'] ?? `${characterId}-skeleton`, '--skeleton-id') : null;
  const parts = modelParts.map((id, index) => ({ id, parent: index === 0 ? null : modelParts[0], role: index === 0 ? 'primary' : index === 1 ? 'secondary' : 'detail', required: true }));
  const profile = {
    schemaVersion: 'opencaw-code-character/v1',
    characterId,
    title: options.title ?? characterId.split('-').map((word) => word[0].toUpperCase() + word.slice(1)).join(' '),
    codeModel: { manifest: linked.relative, modelId: linkedValidation.manifest.modelId },
    intent: {
      kind: options.kind ?? 'character', brief: options.brief, intendedUse: options['intended-use'],
      presentation: { distance: options['presentation-distance'] ?? 'mixed', pixelHeights, representativeActors },
      temperament: options.temperament ?? 'Defined by the task brief.',
      identity: options.identity ?? options.brief,
      signatureParts
    },
    silhouette: {
      primaryView: views[0], requiredViews: [...new Set(views)],
      negativeSpace: 'Preserve readable separation between major masses at the declared presentation scale.',
      asymmetryPolicy: 'Use intentional asymmetry only when it supports the frozen identity and remains readable from required views.',
      questions: ['What character or creature is visible?', 'Which semantic part carries the identity?', 'Does each required view read as one coherent actor?']
    },
    structure: {
      coordinateSystem: linkedValidation.manifest.runtime.coordinateSystem,
      pivot: 'Use the generic model origin anchor as the stable actor pivot.',
      grounding: 'Place the documented contact surface on the host ground plane without presentation-only offsets.',
      parts, joints: [], symmetryGroups: [],
      attachments: parts.slice(1).map((part) => ({ part: part.id, host: modelParts[0], toleranceRatio: 0.02 })),
      sockets: [], colliders: []
    },
    motion: {
      mode: motionMode, skeletonId, maxInfluencesPerVertex: maxInfluences,
      requiredRoles, clips, representativePoses: motionMode === 'static' ? [] : ['rest']
    },
    budgets: {
      bones: motionMode === 'static' ? 0 : 128,
      clips: clips.length,
      shaderVariants: linkedValidation.manifest.budgets.materials,
      textureBytes: 0,
      representativeActors,
      cpuMilliseconds: null,
      gpuMilliseconds: null
    },
    reviewPolicy: {
      builderIds: options.builder ?? ['codex-builder'],
      independentReview: true,
      maxGateAttempts: positiveInteger(options['max-gate-attempts'], 3, '--max-gate-attempts'),
      repeatedFailureLimit: positiveInteger(options['repeated-failure-limit'], 2, '--repeated-failure-limit')
    },
    gates: defaultGates()
  };
  if (profile.reviewPolicy.repeatedFailureLimit > profile.reviewPolicy.maxGateAttempts) fail('Repeated failure limit cannot exceed max gate attempts.');
  validateProfile(root, profile, 'base');
  atomicWrite(output.absolute, profile);
  process.stdout.write(`Created ${output.relative}\n`);
  process.stdout.write('Next character gate: blockout-readability\n');
}

function validateOperation(root, values) {
  const options = parseOptions(values, new Set(), new Set(['strict', 'complete']));
  rejectUnknownOptions(options, new Set(['strict', 'complete']));
  if (options.strict && options.complete) fail('Choose --strict or --complete, not both.');
  if (options._.length !== 1) fail('Validate requires exactly one PROFILE.');
  const mode = options.complete ? 'complete' : options.strict ? 'strict' : 'base';
  const result = validateProfile(root, null, mode, options._[0]);
  process.stdout.write(`Code-character profile validation passed (${mode}).\n`);
  process.stdout.write(`Character: ${result.profile.characterId}\n`);
  process.stdout.write(`Gates: ${result.profile.gates.filter((gate) => gate.status === 'passed').length}/${result.profile.gates.length}\n`);
  if (mode === 'complete') process.stdout.write(`Linked manifest SHA-256: ${sha256(result.linked.linked.absolute)}\n`);
}

function parseEvidence(root, entries) {
  const evidence = [];
  const used = new Set();
  for (const entry of entries ?? []) {
    const separator = entry.indexOf('=');
    if (separator < 1) fail('--evidence must use KIND=PATH.');
    const kind = entry.slice(0, separator);
    requireId(kind, 'Evidence kind');
    const located = relativeArtifact(root, entry.slice(separator + 1), 'Gate evidence');
    if (used.has(located.relative)) fail(`Duplicate gate evidence path: ${located.relative}`);
    used.add(located.relative);
    evidence.push({ kind, path: located.relative, sha256: sha256(located.absolute) });
  }
  return evidence;
}

function record(root, values) {
  const options = parseOptions(values, new Set(['evidence']));
  rejectUnknownOptions(options, new Set(['gate', 'decision', 'summary', 'remaining-gaps', 'failure-class', 'strategy', 'evidence', 'reviewer-id', 'reviewer-type', 'reviewer-packet', 'observed-answer']));
  if (options._.length !== 1) fail('Record requires exactly one PROFILE.');
  requireString(options.gate, '--gate');
  if (!DECISIONS.has(options.decision)) fail('--decision is invalid.');
  requireString(options.summary, '--summary');
  requireString(options.strategy, '--strategy');
  const profileLocated = relativeArtifact(root, options._[0], 'Character profile');
  return withProfileLock(profileLocated.absolute, () => {
    const beforeSha = sha256(profileLocated.absolute);
    const result = validateProfile(root, null, 'base', profileLocated.absolute);
    const { profile, linked } = result;
    const source = relativeArtifact(root, linked.manifest.target.sourcePath, 'Linked code-model source');
    const gate = profile.gates.find((candidate) => candidate.id === options.gate);
    if (!gate) fail(`Unknown character gate: ${options.gate}`);
    const currentGate = profile.gates.find((candidate) => candidate.status !== 'passed');
    if (!currentGate || currentGate.id !== gate.id) fail(`The next character gate is ${currentGate?.id ?? 'complete'}.`);
    const currentPass = linked.manifest.passes.find((pass) => pass.status !== 'passed');
    if (!currentPass || currentPass.id !== gate.pass) fail(`Gate ${gate.id} belongs to ${gate.pass}, but the linked CODE pass is ${currentPass?.id ?? 'complete'}.`);
    if (gate.status === 'stopped') fail(`Gate ${gate.id} is stopped and cannot accept another result.`);
    if (gate.attempts >= profile.reviewPolicy.maxGateAttempts) fail(`Gate ${gate.id} exhausted its attempt limit.`);
    const strategySha256 = textSha256(options.strategy);
    const previous = gate.results.at(-1);
    if (previous && previous.decision !== 'pass' && previous.strategySha256 === strategySha256) fail('A failed character gate must use a changed strategy.');
    const failureClass = options['failure-class'] ?? '';
    if (options.decision === 'pass' && failureClass) fail('--failure-class must be omitted for pass.');
    if (options.decision !== 'pass') requireId(failureClass, '--failure-class');
    if (options.decision === 'revise-code') {
      const priorSame = gate.results.filter((entry) => entry.decision !== 'pass' && entry.failureClass === failureClass).length;
      if (priorSame + 1 >= profile.reviewPolicy.repeatedFailureLimit) {
        fail(`Failure class ${failureClass} reached the repeated-failure limit; use revise-spec, request-input, or stop.`);
      }
    }
    const evidence = parseEvidence(root, options.evidence);
    if (!evidence.length) fail('Gate results require at least one --evidence KIND=PATH.');
    let reviewer = null;
    if (gate.type === 'reviewer') {
      requireId(options['reviewer-id'], '--reviewer-id');
      if (profile.reviewPolicy.builderIds.includes(options['reviewer-id'])) fail('Reviewer identity overlaps an active builder identity.');
      if (!['agent', 'human'].includes(options['reviewer-type'])) fail('--reviewer-type must be agent or human.');
      requireString(options['reviewer-packet'], '--reviewer-packet');
      requireString(options['observed-answer'], '--observed-answer');
      const packet = relativeArtifact(root, options['reviewer-packet'], 'Reviewer packet');
      const packetEntry = evidence.find((entry) => entry.kind === 'reviewer-packet' && entry.path === packet.relative);
      if (!packetEntry) fail('Reviewer packet must also be supplied as --evidence reviewer-packet=PATH.');
      reviewer = { id: options['reviewer-id'], type: options['reviewer-type'], packetPath: packet.relative, packetSha256: sha256(packet.absolute), observedAnswer: options['observed-answer'] };
    } else if (options['reviewer-id'] || options['reviewer-type'] || options['reviewer-packet'] || options['observed-answer']) {
      fail('Machine gates do not accept reviewer options.');
    }
    if (options.decision === 'pass' && gate.type === 'machine') {
      if (!gate.calibration.passing.length || !gate.calibration.failing.length) fail(`Machine gate ${gate.id} needs passing and failing calibration evidence before it can pass.`);
      for (const category of ['passing', 'failing']) for (const item of gate.calibration[category]) validatePathHash(root, item, `${gate.id} ${category} calibration`);
    }
    const hashes = contractHashes(profile, linked.manifest);
    const newResult = {
      decision: options.decision,
      summary: options.summary,
      remainingGaps: options['remaining-gaps'] ?? '',
      failureClass,
      strategySummary: options.strategy,
      strategySha256,
      reviewer,
      evidence,
      manifestContractSha256: hashes.manifest,
      profileContractSha256: hashes.profile,
      sourceSha256: sha256(source.absolute),
      createdAt: new Date().toISOString()
    };
    gate.attempts += 1;
    gate.results.push(newResult);
    if (options.decision === 'pass') {
      gate.status = 'passed';
      const next = profile.gates[profile.gates.indexOf(gate) + 1];
      if (next) next.status = 'active';
    } else if (options.decision === 'request-input') gate.status = 'blocked';
    else if (options.decision === 'stop') gate.status = 'stopped';
    else gate.status = 'active';
    validateProfile(root, profile, 'base');
    atomicWrite(profileLocated.absolute, profile, beforeSha);
    process.stdout.write(`Recorded ${options.decision} for ${gate.id}.\n`);
    const next = profile.gates.find((candidate) => candidate.status !== 'passed');
    process.stdout.write(`Next character gate: ${next?.id ?? 'complete'}\n`);
  });
}

function assertPassReady(rootValue, profilePath, manifestRelative, passId) {
  const root = rootPath(rootValue);
  if (!PASS_IDS.includes(passId)) fail(`Unknown CODE pass: ${passId}`);
  const result = validateProfile(root, null, 'base', profilePath);
  if (result.linked.linked.relative !== relativeInside(root, manifestRelative, 'Code-model manifest', true).relative) fail('Character profile is linked to a different code-model manifest.');
  const gates = result.profile.gates.filter((gate) => gate.pass === passId && gate.required);
  if (!gates.length) fail(`Character profile has no required gates for ${passId}.`);
  for (const gate of gates) {
    if (gate.status !== 'passed') fail(`Character gate must pass before ${passId}: ${gate.id}`);
    const latest = gate.results.at(-1);
    if (!latest || latest.manifestContractSha256 !== result.hashes.manifest || latest.profileContractSha256 !== result.hashes.profile || latest.sourceSha256 !== result.sourceSha256) {
      fail(`Character gate is stale before ${passId}: ${gate.id}`);
    }
  }
  return true;
}

function main() {
  const [operation, rootArg, ...values] = process.argv.slice(2);
  if (!operation || !rootArg) fail('Internal invocation requires an operation and project root.');
  const root = rootPath(rootArg);
  if (operation === 'create') return create(root, values);
  if (operation === 'validate') return validateOperation(root, values);
  if (operation === 'record') return record(root, values);
  fail(`Unknown code-character operation: ${operation}`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { assertPassReady, contractHashes, profileContractProjection, validateProfile };
