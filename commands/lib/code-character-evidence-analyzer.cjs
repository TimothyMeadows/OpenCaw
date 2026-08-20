'use strict';

const crypto = require('crypto');

const MACHINE_GATES = ['structure-integrity', 'interaction-runtime', 'optimization-budget'];

function fail(message) {
  throw new Error(message);
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}

function objectSha256(value) {
  return crypto.createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}

function requireObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label} must be an object.`);
  return value;
}

function onlyKeys(value, allowed, label) {
  requireObject(value, label);
  const extras = Object.keys(value).filter((key) => !allowed.includes(key));
  if (extras.length) fail(`${label} contains unsupported fields: ${extras.join(', ')}.`);
}

function requireArray(value, label) {
  if (!Array.isArray(value)) fail(`${label} must be an array.`);
  return value;
}

function finiteNumber(value, label, minimum = 0) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum) {
    fail(`${label} must be a finite number >= ${minimum}.`);
  }
  return value;
}

function integer(value, label, minimum = 0) {
  if (!Number.isInteger(value) || value < minimum) fail(`${label} must be an integer >= ${minimum}.`);
  return value;
}

function stringArray(value, label) {
  requireArray(value, label);
  if (value.some((entry) => typeof entry !== 'string' || !entry)) fail(`${label} must contain non-empty strings.`);
  if (new Set(value).size !== value.length) fail(`${label} must not contain duplicates.`);
  return value;
}

function strings(value, label) {
  requireArray(value, label);
  if (value.some((entry) => typeof entry !== 'string' || !entry)) fail(`${label} must contain non-empty strings.`);
  return value;
}

function gateThresholds(profile, gateId) {
  const gate = profile.gates.find((candidate) => candidate.id === gateId);
  if (!gate || gate.type !== 'machine') fail(`Profile is missing machine gate ${gateId}.`);
  return requireObject(gate.claim.thresholds, `${gateId} thresholds`);
}

function check(id, status, observed, expected, rationale) {
  if (!['pass', 'fail', 'not-applicable'].includes(status)) fail(`Invalid check status for ${id}.`);
  return { id, status, observed, expected, rationale };
}

function comparisonStatus(left, right) {
  return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
}

function evaluateCapture(profile, observation) {
  const capture = requireObject(observation.capture, 'capture');
  onlyKeys(capture, ['seed', 'viewport', 'views', 'externalRequests', 'serviceWorkers'], 'capture');
  integer(capture.seed, 'capture.seed', -2147483648);
  requireObject(capture.viewport, 'capture.viewport');
  onlyKeys(capture.viewport, ['width', 'height', 'pixelRatio'], 'capture.viewport');
  integer(capture.viewport.width, 'capture.viewport.width', 1);
  integer(capture.viewport.height, 'capture.viewport.height', 1);
  finiteNumber(capture.viewport.pixelRatio, 'capture.viewport.pixelRatio', 0.1);
  const views = requireArray(capture.views, 'capture.views');
  const expected = [];
  for (const view of profile.silhouette.requiredViews) {
    for (const pixelHeight of profile.intent.presentation.pixelHeights) {
      expected.push(`${view}:${pixelHeight}:whole`, `${view}:${pixelHeight}:semantic-mask`);
      for (const part of profile.intent.signatureParts) expected.push(`${view}:${pixelHeight}:isolated:${part}`);
    }
  }
  expected.push('runtime:runtime:whole');
  const observed = views.map((entry, index) => {
    requireObject(entry, `capture.views[${index}]`);
    onlyKeys(entry, ['key', 'path', 'sha256'], `capture.views[${index}]`);
    if (typeof entry.key !== 'string' || !entry.key) fail(`capture.views[${index}].key must be a non-empty string.`);
    return entry.key;
  });
  const missing = expected.filter((key) => !observed.includes(key));
  const duplicates = observed.filter((key, index) => observed.indexOf(key) !== index);
  const externalRequests = strings(capture.externalRequests, 'capture.externalRequests');
  const securityFailures = [];
  if (capture.serviceWorkers !== 'blocked') securityFailures.push('service workers were not blocked');
  if (externalRequests.length) securityFailures.push('external network requests were attempted');
  return check(
    'capture-coverage',
    missing.length || duplicates.length || securityFailures.length ? 'fail' : 'pass',
    { captured: observed.length, missing, duplicates: [...new Set(duplicates)], securityFailures },
    { required: expected.length, views: profile.silhouette.requiredViews, pixelHeights: profile.intent.presentation.pixelHeights, externalRequests: 0, serviceWorkers: 'blocked' },
    'Capture inventory and isolation are checked for completeness and confinement only; image readability remains an independent reviewer decision.'
  );
}

function evaluateStructure(profile, observation) {
  const structure = requireObject(observation.structure, 'structure');
  onlyKeys(structure, ['parts', 'joints', 'sockets', 'colliders', 'minimumY', 'groundY', 'height', 'attachmentGaps', 'symmetry'], 'structure');
  const thresholds = gateThresholds(profile, 'structure-integrity');
  const groundingTolerance = finiteNumber(thresholds.groundingToleranceRatio, 'structure-integrity groundingToleranceRatio');
  const parts = requireArray(structure.parts, 'structure.parts');
  const observedParts = new Map();
  for (const [index, part] of parts.entries()) {
    requireObject(part, `structure.parts[${index}]`);
    onlyKeys(part, ['id', 'parent'], `structure.parts[${index}]`);
    if (typeof part.id !== 'string' || !part.id) fail(`structure.parts[${index}].id must be a string.`);
    if (part.parent !== null && typeof part.parent !== 'string') fail(`structure.parts[${index}].parent must be null or a string.`);
    if (observedParts.has(part.id)) fail(`structure.parts repeats ${part.id}.`);
    observedParts.set(part.id, part.parent);
  }
  const requiredParts = profile.structure.parts.filter((part) => part.required);
  const missingParts = requiredParts.filter((part) => !observedParts.has(part.id)).map((part) => part.id);
  const wrongParents = profile.structure.parts
    .filter((part) => observedParts.has(part.id) && observedParts.get(part.id) !== part.parent)
    .map((part) => ({ id: part.id, observed: observedParts.get(part.id), expected: part.parent }));

  finiteNumber(structure.minimumY, 'structure.minimumY', -Number.MAX_VALUE);
  finiteNumber(structure.groundY, 'structure.groundY', -Number.MAX_VALUE);
  finiteNumber(structure.height, 'structure.height', Number.EPSILON);
  const groundingRatio = Math.abs(structure.minimumY - structure.groundY) / structure.height;

  const attachmentGaps = requireArray(structure.attachmentGaps, 'structure.attachmentGaps');
  const attachmentByPair = new Map();
  for (const [index, item] of attachmentGaps.entries()) {
    requireObject(item, `structure.attachmentGaps[${index}]`);
    onlyKeys(item, ['part', 'host', 'gapRatio'], `structure.attachmentGaps[${index}]`);
    finiteNumber(item.gapRatio, `structure.attachmentGaps[${index}].gapRatio`);
    attachmentByPair.set(`${item.part}->${item.host}`, item.gapRatio);
  }
  const attachmentFailures = profile.structure.attachments.flatMap((attachment) => {
    const key = `${attachment.part}->${attachment.host}`;
    const gap = attachmentByPair.get(key);
    return gap === undefined || gap > attachment.toleranceRatio
      ? [{ pair: key, observed: gap ?? null, maximum: attachment.toleranceRatio }]
      : [];
  });

  const symmetry = requireArray(structure.symmetry, 'structure.symmetry');
  const symmetryById = new Map(symmetry.map((item, index) => {
    requireObject(item, `structure.symmetry[${index}]`);
    onlyKeys(item, ['id', 'deviationRatio'], `structure.symmetry[${index}]`);
    finiteNumber(item.deviationRatio, `structure.symmetry[${index}].deviationRatio`);
    return [item.id, item.deviationRatio];
  }));
  const symmetryFailures = profile.structure.symmetryGroups.flatMap((group) => {
    const deviation = symmetryById.get(group.id);
    return deviation === undefined || deviation > group.toleranceRatio
      ? [{ id: group.id, observed: deviation ?? null, maximum: group.toleranceRatio }]
      : [];
  });

  return [
    evaluateCapture(profile, observation),
    check('required-parts', missingParts.length ? 'fail' : 'pass', { missing: missingParts }, { required: requiredParts.map((part) => part.id) }, 'Every required semantic part must be exposed by the adapter.'),
    check('parent-relationships', wrongParents.length ? 'fail' : 'pass', { mismatches: wrongParents }, { declared: profile.structure.parts.map(({ id, parent }) => ({ id, parent })) }, 'Observed semantic parent relationships must match the frozen body plan.'),
    check('grounding', groundingRatio <= groundingTolerance ? 'pass' : 'fail', { ratio: groundingRatio, minimumY: structure.minimumY, groundY: structure.groundY }, { maximumRatio: groundingTolerance }, 'Grounding is normalized by observed character height.'),
    check('attachments', attachmentFailures.length ? 'fail' : 'pass', { failures: attachmentFailures }, { declared: profile.structure.attachments }, 'Each declared attachment is measured against its own contextual tolerance.'),
    check('symmetry', symmetryFailures.length ? 'fail' : 'pass', { failures: symmetryFailures }, { declared: profile.structure.symmetryGroups }, 'Only declared symmetry groups are checked; intentional asymmetry remains reviewer-owned.')
  ];
}

function evaluateInteraction(profile, observation) {
  const motion = requireObject(observation.motion, 'motion');
  const structure = requireObject(observation.structure, 'structure');
  onlyKeys(motion, ['mode', 'skeletonId', 'maxInfluencesPerVertex', 'roles', 'contacts', 'movingPartCount'], 'motion');
  const thresholds = gateThresholds(profile, 'interaction-runtime');
  const contactTolerance = finiteNumber(thresholds.contactToleranceRatio, 'interaction-runtime contactToleranceRatio');
  const lifecycleCycles = integer(thresholds.lifecycleCycles, 'interaction-runtime lifecycleCycles', 1);
  if (!['static', 'articulated', 'skinned'].includes(motion.mode)) fail('motion.mode must be static, articulated, or skinned.');
  integer(motion.movingPartCount, 'motion.movingPartCount');
  integer(motion.maxInfluencesPerVertex, 'motion.maxInfluencesPerVertex');
  const roles = stringArray(motion.roles, 'motion.roles');
  const observedJoints = stringArray(structure.joints, 'structure.joints');
  const observedSockets = stringArray(structure.sockets, 'structure.sockets');
  const observedColliders = stringArray(structure.colliders, 'structure.colliders');
  const modeFailures = [];
  if (motion.mode !== profile.motion.mode) modeFailures.push(`observed ${motion.mode}; declared ${profile.motion.mode}`);
  if (profile.motion.mode === 'static' && (motion.movingPartCount !== 0 || roles.length || motion.skeletonId !== null || motion.maxInfluencesPerVertex !== 0)) {
    modeFailures.push('static character reported motion, roles, a skeleton, or skin influences');
  }
  if (profile.motion.mode === 'articulated') {
    if (motion.movingPartCount < 1) modeFailures.push('articulated character reported no moving parts');
    if (motion.skeletonId !== null || motion.maxInfluencesPerVertex !== 0) modeFailures.push('articulated character reported a skinning contract');
  }
  if (profile.motion.mode === 'skinned') {
    if (motion.skeletonId !== profile.motion.skeletonId) modeFailures.push('skeleton identity differs from the profile');
    if (motion.maxInfluencesPerVertex > profile.motion.maxInfluencesPerVertex) modeFailures.push('skin influence limit is exceeded');
  }
  const missingRoles = profile.motion.requiredRoles.filter((role) => !roles.includes(role));
  const contacts = requireArray(motion.contacts, 'motion.contacts');
  if (profile.motion.mode === 'static' && contacts.length) modeFailures.push('static character reported animation contacts');
  const contactFailures = contacts.flatMap((contact, index) => {
    requireObject(contact, `motion.contacts[${index}]`);
    onlyKeys(contact, ['id', 'errorRatio'], `motion.contacts[${index}]`);
    finiteNumber(contact.errorRatio, `motion.contacts[${index}].errorRatio`);
    return contact.errorRatio > contactTolerance ? [{ id: contact.id, errorRatio: contact.errorRatio }] : [];
  });
  const requiredContacts = [...new Set(profile.motion.clips.flatMap((clip) => clip.contacts))];
  const observedContactIds = new Set(contacts.map((contact) => contact.id));
  for (const id of requiredContacts) if (!observedContactIds.has(id)) contactFailures.push({ id, errorRatio: null });

  const lifecycle = requireArray(observation.runtime.lifecycle, 'runtime.lifecycle');
  const interactionCycles = lifecycle.slice(0, lifecycleCycles);
  const lifecycleFailures = interactionCycles.filter((item) => item.staleCallbacks !== 0 || item.resourceDelta !== 0);
  const requiredSemantic = [
    ...profile.structure.joints.map((item) => ['joint', item.id, observedJoints]),
    ...profile.structure.sockets.map((item) => ['socket', item.id, observedSockets]),
    ...profile.structure.colliders.map((item) => ['collider', item.id, observedColliders])
  ];
  const missingSemantic = requiredSemantic.filter(([, id, observed]) => !observed.includes(id)).map(([kind, id]) => `${kind}:${id}`);

  return [
    check('declared-motion-mode', modeFailures.length ? 'fail' : 'pass', { mode: motion.mode, failures: modeFailures }, { mode: profile.motion.mode }, 'Declaring a simpler motion mode cannot bypass checks for the frozen profile mode.'),
    check('interaction-semantics', missingSemantic.length ? 'fail' : 'pass', { missing: missingSemantic }, { joints: profile.structure.joints.map((item) => item.id), sockets: profile.structure.sockets.map((item) => item.id), colliders: profile.structure.colliders.map((item) => item.id) }, 'Declared runtime interaction semantics must be exposed.'),
    check('animation-roles', missingRoles.length ? 'fail' : profile.motion.mode === 'static' ? 'not-applicable' : 'pass', { missing: missingRoles, observed: roles }, { required: profile.motion.requiredRoles }, profile.motion.mode === 'static' ? 'Static characters have no animation-role requirement.' : 'All frozen animation roles must be measurable.'),
    check('animation-contacts', contactFailures.length ? 'fail' : requiredContacts.length ? 'pass' : 'not-applicable', { failures: contactFailures }, { required: requiredContacts, maximumErrorRatio: contactTolerance }, requiredContacts.length ? 'Declared contacts are normalized and checked against the contextual tolerance.' : 'No animation contacts are declared.'),
    check('interaction-lifecycle', lifecycle.length < lifecycleCycles || lifecycleFailures.length ? 'fail' : 'pass', { cycles: lifecycle.length, failures: lifecycleFailures }, { minimumCycles: lifecycleCycles, resourceDelta: 0, staleCallbacks: 0 }, 'Repeated update, attachment, animation, and dispose cycles must release owned state.')
  ];
}

function budgetChecks(profile, manifest, metrics) {
  const checks = [];
  onlyKeys(metrics, ['triangles', 'drawCalls', 'materials', 'textures', 'bones', 'clips', 'shaderVariants', 'textureBytes', 'cpuMilliseconds', 'gpuMilliseconds'], 'runtime.metrics');
  const limits = {
    triangles: manifest.budgets.triangles,
    drawCalls: manifest.budgets.drawCalls,
    materials: manifest.budgets.materials,
    textures: manifest.budgets.textures,
    bones: profile.budgets.bones,
    clips: profile.budgets.clips,
    shaderVariants: profile.budgets.shaderVariants,
    textureBytes: profile.budgets.textureBytes
  };
  for (const [name, maximum] of Object.entries(limits)) {
    integer(metrics[name], `runtime.metrics.${name}`);
    checks.push(check(`budget-${name}`, metrics[name] <= maximum ? 'pass' : 'fail', metrics[name], { maximum }, 'Budget is evaluated in the frozen representative context.'));
  }
  for (const name of ['cpuMilliseconds', 'gpuMilliseconds']) {
    const maximum = profile.budgets[name];
    const observed = metrics[name];
    if (maximum === null) checks.push(check(`budget-${name}`, 'not-applicable', observed ?? null, { maximum: null }, 'The profile does not claim a timing budget.'));
    else {
      finiteNumber(observed, `runtime.metrics.${name}`);
      checks.push(check(`budget-${name}`, observed <= maximum ? 'pass' : 'fail', observed, { maximum }, 'Timing is evaluated only when the profile freezes a contextual limit.'));
    }
  }
  return checks;
}

function evaluateOptimization(profile, manifest, observation) {
  const runtime = requireObject(observation.runtime, 'runtime');
  onlyKeys(runtime, ['constructionHashes', 'lifecycle', 'actors', 'metrics'], 'runtime');
  const thresholds = gateThresholds(profile, 'optimization-budget');
  const constructionRuns = integer(thresholds.constructionRuns, 'optimization-budget constructionRuns', 2);
  const lifecycleCycles = integer(thresholds.lifecycleCycles, 'optimization-budget lifecycleCycles', 1);
  const hashes = strings(runtime.constructionHashes, 'runtime.constructionHashes');
  integer(runtime.actors, 'runtime.actors', 1);
  const lifecycle = requireArray(runtime.lifecycle, 'runtime.lifecycle');
  const lifecycleFailures = lifecycle.filter((item, index) => {
    requireObject(item, `runtime.lifecycle[${index}]`);
    onlyKeys(item, ['cycle', 'resourceDelta', 'staleCallbacks'], `runtime.lifecycle[${index}]`);
    integer(item.cycle, `runtime.lifecycle[${index}].cycle`, 1);
    integer(item.resourceDelta, `runtime.lifecycle[${index}].resourceDelta`);
    integer(item.staleCallbacks, `runtime.lifecycle[${index}].staleCallbacks`);
    return item.resourceDelta !== 0 || item.staleCallbacks !== 0;
  });
  const deterministic = hashes.length >= constructionRuns && new Set(hashes.slice(0, constructionRuns)).size === 1;
  const checks = [
    check('deterministic-seed', observation.capture.seed === manifest.runtime.deterministicSeed ? 'pass' : 'fail', observation.capture.seed, { required: manifest.runtime.deterministicSeed }, 'The browser adapter must use the seed frozen in the linked code-model manifest.'),
    check('deterministic-construction', deterministic ? 'pass' : 'fail', { runs: hashes.length, uniqueHashes: new Set(hashes).size }, { minimumRuns: constructionRuns, uniqueHashes: 1 }, 'Repeated construction must produce the same stable semantic hash.'),
    check('representative-actors', runtime.actors === profile.budgets.representativeActors ? 'pass' : 'fail', runtime.actors, { required: profile.budgets.representativeActors }, 'Measurements must use the exact representative actor count frozen in the profile.'),
    check('resource-lifecycle', lifecycle.length >= lifecycleCycles && !lifecycleFailures.length ? 'pass' : 'fail', { cycles: lifecycle.length, failures: lifecycleFailures }, { minimumCycles: lifecycleCycles, resourceDelta: 0, staleCallbacks: 0 }, 'Repeated construction and disposal must not grow owned resources or retain callbacks.'),
    ...budgetChecks(profile, manifest, requireObject(runtime.metrics, 'runtime.metrics'))
  ];
  return checks;
}

function gateResult(id, checks) {
  return {
    id,
    decision: checks.some((item) => item.status === 'fail') ? 'fail' : 'pass',
    checks
  };
}

function analyze(profile, manifest, observation, context) {
  requireObject(profile, 'profile');
  requireObject(manifest, 'manifest');
  requireObject(observation, 'observation');
  onlyKeys(observation, ['schemaVersion', 'capture', 'structure', 'motion', 'runtime'], 'observation');
  if (observation.schemaVersion !== 'opencaw-code-character-observation/v1') {
    fail('Observation schemaVersion must be opencaw-code-character-observation/v1.');
  }
  const captureMode = context.captureMode;
  if (!['browser', 'fixture'].includes(captureMode)) fail('captureMode must be browser or fixture.');
  const gateResults = [
    gateResult('structure-integrity', evaluateStructure(profile, observation)),
    gateResult('interaction-runtime', evaluateInteraction(profile, observation)),
    gateResult('optimization-budget', evaluateOptimization(profile, manifest, observation))
  ];
  if (!comparisonStatus(gateResults.map((item) => item.id), MACHINE_GATES)) fail('Analyzer emitted a non-machine gate.');
  const report = {
    schemaVersion: 'opencaw-code-character-evidence/v1',
    characterId: profile.characterId,
    captureMode,
    trustedMachineEvidence: captureMode === 'browser',
    trustReason: captureMode === 'browser'
      ? 'Captured through the loopback-only sandboxed browser harness.'
      : 'Fixture analysis calibrates measurement semantics and is not runtime evidence.',
    contracts: context.contracts,
    observationSha256: objectSha256(observation),
    overallDecision: gateResults.some((item) => item.decision === 'fail') ? 'fail' : 'pass',
    gateResults,
    comparison: context.comparison ?? null,
    reviewerBoundary: 'No machine result approves blockout readability, form readability, materials, style, identity, appeal, or other aesthetic judgments.'
  };
  return report;
}

module.exports = { MACHINE_GATES, analyze, canonical, objectSha256 };
