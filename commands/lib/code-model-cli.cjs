'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PASS_IDS = ['blockout', 'structure', 'form', 'materials', 'interaction', 'optimization'];
const DECISIONS = new Set(['pass', 'revise-spec', 'revise-code', 'request-input', 'stop']);
const EVIDENCE_VIEWS = new Set(['front', 'orbit-left', 'orbit-right', 'runtime', 'report']);
const SHA_PATTERN = /^[a-f0-9]{64}$/;
const MODEL_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function fail(message) {
  throw new Error(message);
}

function wslToWindows(value) {
  if (process.platform !== 'win32' || typeof value !== 'string') return value;
  const match = value.match(/^\/mnt\/([a-zA-Z])\/(.*)$/);
  return match ? `${match[1].toUpperCase()}:\\${match[2].replaceAll('/', '\\')}` : value;
}

function rootPath(value) {
  return fs.realpathSync(wslToWindows(value));
}

function resolveFromRoot(root, value) {
  const normalized = wslToWindows(value);
  return path.resolve(path.isAbsolute(normalized) ? normalized : path.join(root, normalized));
}

function relativeInside(root, value, label, mustExist = false) {
  const candidate = resolveFromRoot(root, value);
  const relative = path.relative(root, candidate);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
    fail(`${label} must stay inside the project root.`);
  }

  if (mustExist) {
    if (!fs.existsSync(candidate)) fail(`${label} does not exist: ${value}`);
    const real = fs.realpathSync(candidate);
    const realRelative = path.relative(root, real);
    if (!realRelative || realRelative.startsWith('..') || path.isAbsolute(realRelative)) {
      fail(`${label} resolves outside the project root.`);
    }
    if (fs.lstatSync(candidate).isSymbolicLink()) fail(`${label} must not be a symbolic link.`);
  } else {
    let ancestor = path.dirname(candidate);
    while (!fs.existsSync(ancestor)) {
      const parent = path.dirname(ancestor);
      if (parent === ancestor) fail(`${label} has no safe existing parent.`);
      ancestor = parent;
    }
    const realAncestor = fs.realpathSync(ancestor);
    const ancestorRelative = path.relative(root, realAncestor);
    if (ancestorRelative.startsWith('..') || path.isAbsolute(ancestorRelative)) {
      fail(`${label} parent resolves outside the project root.`);
    }
    if (fs.existsSync(candidate) && fs.lstatSync(candidate).isSymbolicLink()) {
      fail(`${label} must not be a symbolic link.`);
    }
  }

  return { absolute: candidate, relative: relative.split(path.sep).join('/') };
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function parseOptions(values, repeatable = new Set()) {
  const options = { _: [] };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith('--')) {
      options._.push(value);
      continue;
    }
    const key = value.slice(2);
    if (key === 'prompt-override' || key === 'planar' || key === 'strict' || key === 'complete' || key === 'json') {
      options[key] = true;
      continue;
    }
    if (index + 1 >= values.length || values[index + 1].startsWith('--')) fail(`${value} requires a value.`);
    const next = values[++index];
    if (repeatable.has(key)) {
      options[key] ??= [];
      options[key].push(next);
    } else if (Object.hasOwn(options, key)) {
      fail(`${value} may be supplied only once.`);
    } else {
      options[key] = next;
    }
  }
  return options;
}

function rejectUnknownOptions(options, allowed) {
  for (const key of Object.keys(options)) {
    if (key !== '_' && !allowed.has(key)) fail(`Unknown option: --${key}`);
  }
}

function positiveInteger(value, fallback, label, allowZero = false) {
  const result = value === undefined ? fallback : Number(value);
  if (!Number.isInteger(result) || result < (allowZero ? 0 : 1)) fail(`${label} must be ${allowZero ? 'a non-negative' : 'a positive'} integer.`);
  return result;
}

function unavailable(reason) {
  return { unavailable: true, reason };
}

function detectThreeVersion(root) {
  const installed = path.join(root, 'node_modules', 'three', 'package.json');
  if (fs.existsSync(installed)) {
    try {
      const version = JSON.parse(fs.readFileSync(installed, 'utf8')).version;
      if (version) return version;
    } catch { /* validator reports malformed host state elsewhere */ }
  }
  return unavailable('The host does not have a detectable installed Three.js version.');
}

function readJson(file, label) {
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
  }
  return parsed;
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  if (fs.existsSync(file) && fs.lstatSync(file).isSymbolicLink()) fail('Manifest output must not be a symbolic link.');
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.trim() === '') fail(`${label} must be a non-empty string.`);
}

function onlyKeys(value, allowed, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label} must be an object.`);
  for (const key of Object.keys(value)) if (!allowed.includes(key)) fail(`${label} contains unknown field: ${key}.`);
}

function requireUnavailableOrString(value, label) {
  if (typeof value === 'string' && value.length > 0) return;
  if (value && typeof value === 'object') onlyKeys(value, ['unavailable', 'reason'], label);
  if (!value || value.unavailable !== true || typeof value.reason !== 'string' || value.reason.length === 0) {
    fail(`${label} must be a value or an explicit unavailable marker.`);
  }
}

function validateManifest(root, manifestPath, mode = 'base') {
  const located = relativeInside(root, manifestPath, 'Code-model manifest', true);
  const manifest = readJson(located.absolute, 'Code-model manifest');
  onlyKeys(manifest, ['schemaVersion', 'modelId', 'title', 'intent', 'pipelineSelection', 'inputs', 'target', 'renderer', 'runtime', 'budgets', 'reviewPolicy', 'passes'], 'manifest');
  if (manifest.schemaVersion !== 1) fail('schemaVersion must be 1.');
  if (!MODEL_ID_PATTERN.test(manifest.modelId ?? '')) fail('modelId must use lowercase kebab-case.');
  requireString(manifest.title, 'title');
  onlyKeys(manifest.intent, ['brief', 'intendedUse', 'styleContract'], 'intent');
  requireString(manifest.intent?.brief, 'intent.brief');
  requireString(manifest.intent?.intendedUse, 'intent.intendedUse');
  requireString(manifest.intent?.styleContract, 'intent.styleContract');
  onlyKeys(manifest.pipelineSelection, ['pipeline', 'selectionSource', 'styleContract', 'styleSha256'], 'pipelineSelection');
  if (manifest.pipelineSelection?.pipeline !== 'CODE') fail('pipelineSelection.pipeline must be CODE.');
  if (!['style', 'prompt'].includes(manifest.pipelineSelection?.selectionSource)) fail('pipelineSelection.selectionSource must be style or prompt.');
  if (!SHA_PATTERN.test(manifest.pipelineSelection?.styleSha256 ?? '')) fail('pipelineSelection.styleSha256 is invalid.');
  if (manifest.pipelineSelection.styleContract !== manifest.intent.styleContract) fail('Style contract fields must match.');
  const style = relativeInside(root, manifest.intent.styleContract, 'Style contract', true);
  if (sha256(style.absolute) !== manifest.pipelineSelection.styleSha256) fail('The active STYLE.md hash no longer matches the manifest.');

  if (!Array.isArray(manifest.inputs) || manifest.inputs.length < 1) fail('inputs must contain the originating brief.');
  let briefCount = 0;
  for (const [index, input] of manifest.inputs.entries()) {
    onlyKeys(input, ['kind', 'source', 'rights', 'consent', 'sha256'], `inputs[${index}]`);
    if (!['brief', 'reference-image'].includes(input?.kind)) fail(`inputs[${index}].kind is invalid.`);
    requireString(input.source, `inputs[${index}].source`);
    requireString(input.rights, `inputs[${index}].rights`);
    if (!['not-applicable', 'confirmed', 'not-confirmed'].includes(input.consent)) fail(`inputs[${index}].consent is invalid.`);
    requireUnavailableOrString(input.sha256, `inputs[${index}].sha256`);
    if (input.kind === 'brief') briefCount += 1;
    if (input.kind === 'reference-image') {
      if (input.consent === 'not-confirmed') fail('Reference-image consent must be confirmed or not applicable.');
      const reference = relativeInside(root, input.source, `Reference image ${index}`, true);
      if (typeof input.sha256 !== 'string' || sha256(reference.absolute) !== input.sha256) fail(`Reference image ${index} hash does not match.`);
    }
  }
  if (briefCount !== 1) fail('inputs must contain exactly one brief record.');

  onlyKeys(manifest.target, ['sourcePath', 'factoryExport'], 'target');
  requireString(manifest.target?.sourcePath, 'target.sourcePath');
  if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(manifest.target?.factoryExport ?? '')) fail('target.factoryExport is invalid.');
  const source = relativeInside(root, manifest.target.sourcePath, 'Target source path', mode === 'complete');
  onlyKeys(manifest.renderer, ['library', 'installedVersion', 'language'], 'renderer');
  if (manifest.renderer?.library !== 'three') fail('renderer.library must be three.');
  if (!['typescript', 'javascript'].includes(manifest.renderer?.language)) fail('renderer.language must be typescript or javascript.');
  requireUnavailableOrString(manifest.renderer?.installedVersion, 'renderer.installedVersion');
  onlyKeys(manifest.runtime, ['interface', 'deterministicSeed', 'coordinateSystem', 'parts', 'anchors', 'cleanup'], 'runtime');
  requireString(manifest.runtime?.interface, 'runtime.interface');
  if (!Number.isInteger(manifest.runtime?.deterministicSeed)) fail('runtime.deterministicSeed must be an integer.');
  requireString(manifest.runtime?.coordinateSystem, 'runtime.coordinateSystem');
  requireString(manifest.runtime?.cleanup, 'runtime.cleanup');
  for (const key of ['parts', 'anchors']) {
    if (!Array.isArray(manifest.runtime?.[key]) || manifest.runtime[key].length < 1) fail(`runtime.${key} must contain semantic names.`);
    if (new Set(manifest.runtime[key]).size !== manifest.runtime[key].length) fail(`runtime.${key} contains duplicates.`);
    manifest.runtime[key].forEach((item, index) => requireString(item, `runtime.${key}[${index}]`));
  }
  onlyKeys(manifest.budgets, ['triangles', 'drawCalls', 'materials', 'textures'], 'budgets');
  for (const [key, allowZero] of [['triangles', false], ['drawCalls', false], ['materials', false], ['textures', true]]) {
    positiveInteger(manifest.budgets?.[key], undefined, `budgets.${key}`, allowZero);
  }
  const policy = manifest.reviewPolicy;
  onlyKeys(policy, ['nonPlanar', 'requiredViews', 'maxAttemptsPerPass', 'maxAttemptsTotal'], 'reviewPolicy');
  if (typeof policy?.nonPlanar !== 'boolean') fail('reviewPolicy.nonPlanar must be boolean.');
  const expectedViews = policy.nonPlanar ? ['front', 'orbit-left', 'orbit-right'] : ['front'];
  if (JSON.stringify(policy.requiredViews) !== JSON.stringify(expectedViews)) fail(`reviewPolicy.requiredViews must be ${expectedViews.join(', ')}.`);
  positiveInteger(policy.maxAttemptsPerPass, undefined, 'reviewPolicy.maxAttemptsPerPass');
  positiveInteger(policy.maxAttemptsTotal, undefined, 'reviewPolicy.maxAttemptsTotal');
  if (policy.maxAttemptsTotal < policy.maxAttemptsPerPass) fail('The total attempt limit cannot be lower than the per-pass limit.');

  if (!Array.isArray(manifest.passes) || manifest.passes.length !== PASS_IDS.length) fail('passes must contain the six ordered CODE passes.');
  const firstIncompleteIndex = manifest.passes.findIndex((pass) => pass.status !== 'passed');
  let totalAttempts = 0;
  let encounteredIncomplete = false;
  let activeCount = 0;
  for (let index = 0; index < PASS_IDS.length; index += 1) {
    const pass = manifest.passes[index];
    onlyKeys(pass, ['id', 'status', 'attempts', 'reviews'], `passes[${index}]`);
    if (pass?.id !== PASS_IDS[index]) fail(`Pass ${index + 1} must be ${PASS_IDS[index]}.`);
    if (!['pending', 'active', 'passed', 'blocked', 'stopped'].includes(pass.status)) fail(`Pass ${pass.id} has an invalid status.`);
    if (!Number.isInteger(pass.attempts) || pass.attempts < 0) fail(`Pass ${pass.id} has invalid attempts.`);
    if (!Array.isArray(pass.reviews) || pass.reviews.length !== pass.attempts) fail(`Pass ${pass.id} review count must equal attempts.`);
    if (pass.attempts > policy.maxAttemptsPerPass) fail(`Pass ${pass.id} exceeds its attempt limit.`);
    totalAttempts += pass.attempts;
    if (pass.status === 'active') activeCount += 1;
    if (pass.status !== 'passed') encounteredIncomplete = true;
    else if (encounteredIncomplete) fail(`Passed pass ${pass.id} appears after an incomplete pass.`);
    for (const [reviewIndex, review] of pass.reviews.entries()) {
      onlyKeys(review, ['decision', 'summary', 'remainingGaps', 'createdAt', 'evidence'], `Pass ${pass.id} review ${reviewIndex + 1}`);
      if (!DECISIONS.has(review?.decision)) fail(`Pass ${pass.id} review ${reviewIndex + 1} has an invalid decision.`);
      requireString(review.summary, `Pass ${pass.id} review summary`);
      if (typeof review.remainingGaps !== 'string') fail(`Pass ${pass.id} review remainingGaps must be a string.`);
      if (Number.isNaN(Date.parse(review.createdAt))) fail(`Pass ${pass.id} review createdAt is invalid.`);
      if (!Array.isArray(review.evidence)) fail(`Pass ${pass.id} review evidence must be an array.`);
      const seenViews = new Set();
      for (const evidence of review.evidence) {
        onlyKeys(evidence, ['path', 'sha256', 'view'], `Pass ${pass.id} review evidence`);
        if (!EVIDENCE_VIEWS.has(evidence?.view)) fail(`Pass ${pass.id} review evidence view is invalid.`);
        if (seenViews.has(evidence.view)) fail(`Pass ${pass.id} review repeats evidence view ${evidence.view}.`);
        seenViews.add(evidence.view);
        const artifact = relativeInside(root, evidence.path, `Evidence ${evidence.path}`, true);
        if (!SHA_PATTERN.test(evidence.sha256 ?? '') || sha256(artifact.absolute) !== evidence.sha256) fail(`Evidence hash does not match: ${evidence.path}`);
      }
      if (review.decision === 'pass') {
        for (const view of policy.requiredViews) if (!seenViews.has(view)) fail(`Passing ${pass.id} review lacks ${view} evidence.`);
      }
    }
    const lastDecision = pass.reviews.at(-1)?.decision;
    const expectedStatus = lastDecision === 'pass' ? 'passed'
      : lastDecision === 'request-input' ? 'blocked'
      : lastDecision === 'stop' ? 'stopped'
      : pass.attempts > 0 ? 'active' : index === firstIncompleteIndex ? 'active' : 'pending';
    if (pass.status !== expectedStatus) fail(`Pass ${pass.id} status does not match its latest review.`);
  }
  if (activeCount > 1) fail('Only one pass may be active.');
  if (totalAttempts > policy.maxAttemptsTotal) fail('Manifest exceeds the total attempt limit.');

  if (mode === 'strict' || mode === 'complete') {
    if (/\b(?:TODO|TBD|placeholder)\b/i.test(manifest.intent.brief)) fail('The brief still contains a placeholder.');
    if (!/\bdispose\s*\(/.test(manifest.runtime.interface)) fail('runtime.interface must assign cleanup ownership through dispose().');
  }
  if (mode === 'complete') {
    const installedVersion = detectThreeVersion(root);
    if (typeof installedVersion !== 'string') fail('Complete validation requires an installed host Three.js version.');
    if (manifest.renderer.installedVersion !== installedVersion) fail('The manifest Three.js version no longer matches the installed host version.');
    if (!manifest.passes.every((pass) => pass.status === 'passed')) fail('Every CODE pass must be passed for complete validation.');
    const code = fs.readFileSync(source.absolute, 'utf8');
    if (/\b(?:GLTFLoader|FBXLoader|OBJLoader)\b|\.(?:glb|gltf|fbx|obj)(?:['"?]|\b)/i.test(code)) fail('Target source depends on a loaded mesh/model asset.');
    if (!/from\s+['"]three['"]|require\(['"]three['"]\)/.test(code)) fail('Target source must use the host Three.js package.');
    if (!new RegExp(`\\b${manifest.target.factoryExport}\\b`).test(code)) fail('Target source does not expose the recorded factory export.');
    if (!/\bdispose\s*\(/.test(code)) fail('Target source does not implement disposal.');
  }
  return { manifest, located, totalAttempts };
}

function create(root, values) {
  const options = parseOptions(values, new Set(['reference', 'part', 'anchor']));
  rejectUnknownOptions(options, new Set([
    'brief', 'style', 'prompt-override', 'output', 'source', 'title', 'intended-use', 'factory',
    'part', 'anchor', 'reference', 'reference-rights', 'reference-consent', 'planar', 'seed',
    'coordinates', 'interface', 'triangles', 'draw-calls', 'materials', 'textures',
    'max-attempts-per-pass', 'max-attempts-total', 'resolved-style', 'selection-json'
  ]));
  if (options._.length !== 1) fail('create requires exactly one model id.');
  const modelId = options._[0];
  if (!MODEL_ID_PATTERN.test(modelId)) fail('Model id must use lowercase kebab-case.');
  requireString(options.brief, '--brief');
  const outputValue = options.output ?? `.ai/tasks/${modelId}/code-model.json`;
  const output = relativeInside(root, outputValue, 'Manifest output');
  if (!output.relative.startsWith('.ai/tasks/')) fail('Manifest output must stay below .ai/tasks.');
  const sourceValue = options.source ?? `src/models/${modelId}.ts`;
  const source = relativeInside(root, sourceValue, 'Target source path');
  if (!/\.(?:ts|tsx|js|jsx|mjs|cjs)$/.test(source.relative)) fail('Target source path must be a TypeScript or JavaScript file.');
  const style = relativeInside(root, options['resolved-style'], 'Style contract', true);
  const selection = JSON.parse(options['selection-json']);
  if (selection.pipeline !== 'CODE') fail('Resolved pipeline must be CODE.');
  if (!['style', 'prompt'].includes(selection.selectionSource)) fail('Resolved selection source is invalid.');
  if (selection.styleSha256 !== sha256(style.absolute)) fail('Resolved style hash does not match STYLE.md.');
  if (selection.styleContract !== style.relative) fail('Resolved style contract path does not match --style.');

  const references = options.reference ?? [];
  const rights = options['reference-rights'];
  const consent = options['reference-consent'] ?? 'not-applicable';
  if (references.length && !rights) fail('--reference-rights is required with --reference.');
  if (!['confirmed', 'not-applicable'].includes(consent)) fail('--reference-consent must be confirmed or not-applicable.');
  const inputs = [{
    kind: 'brief', source: 'current-prompt', rights: 'user-provided', consent: 'not-applicable',
    sha256: unavailable('The brief is stored in intent.brief rather than a separate file.')
  }];
  for (const referenceValue of references) {
    const reference = relativeInside(root, referenceValue, 'Reference image', true);
    inputs.push({ kind: 'reference-image', source: reference.relative, rights, consent, sha256: sha256(reference.absolute) });
  }

  const nonPlanar = options.planar !== true;
  const title = options.title ?? modelId.split('-').map((part) => part[0].toUpperCase() + part.slice(1)).join(' ');
  const factory = options.factory ?? `create${title.replace(/[^A-Za-z0-9_$]/g, '')}`;
  const parts = options.part ?? ['body'];
  const anchors = options.anchor ?? ['origin'];
  const manifest = {
    schemaVersion: 1,
    modelId,
    title,
    intent: {
      brief: options.brief,
      intendedUse: options['intended-use'] ?? 'real-time web model',
      styleContract: style.relative
    },
    pipelineSelection: {
      pipeline: 'CODE',
      selectionSource: selection.selectionSource,
      styleContract: style.relative,
      styleSha256: selection.styleSha256
    },
    inputs,
    target: { sourcePath: source.relative, factoryExport: factory },
    renderer: {
      library: 'three',
      installedVersion: detectThreeVersion(root),
      language: /\.(?:js|jsx|mjs|cjs)$/.test(source.relative) ? 'javascript' : 'typescript'
    },
    runtime: {
      interface: options.interface ?? 'CodeModelInstance { root: THREE.Group; parts: ReadonlyMap<string, THREE.Object3D>; anchors: ReadonlyMap<string, THREE.Object3D>; update?(deltaSeconds: number): void; dispose(): void; }',
      deterministicSeed: Number.isInteger(Number(options.seed)) ? Number(options.seed) : 1,
      coordinateSystem: options.coordinates ?? 'Y-up, right-handed, local origin at ground center',
      parts,
      anchors,
      cleanup: 'dispose() owns all geometry, material, texture, listener, and helper cleanup created by the factory.'
    },
    budgets: {
      triangles: positiveInteger(options.triangles, 60000, '--triangles'),
      drawCalls: positiveInteger(options['draw-calls'], 64, '--draw-calls'),
      materials: positiveInteger(options.materials, 16, '--materials'),
      textures: positiveInteger(options.textures, 0, '--textures', true)
    },
    reviewPolicy: {
      nonPlanar,
      requiredViews: nonPlanar ? ['front', 'orbit-left', 'orbit-right'] : ['front'],
      maxAttemptsPerPass: positiveInteger(options['max-attempts-per-pass'], 3, '--max-attempts-per-pass'),
      maxAttemptsTotal: positiveInteger(options['max-attempts-total'], 12, '--max-attempts-total')
    },
    passes: PASS_IDS.map((id, index) => ({ id, status: index === 0 ? 'active' : 'pending', attempts: 0, reviews: [] }))
  };
  if (manifest.reviewPolicy.maxAttemptsTotal < manifest.reviewPolicy.maxAttemptsPerPass) fail('The total attempt limit cannot be lower than the per-pass limit.');
  writeJson(output.absolute, manifest);
  process.stdout.write(`Wrote ${output.relative}\n`);
  process.stdout.write('Next pass: blockout\n');
}

function validate(root, values) {
  const options = parseOptions(values);
  rejectUnknownOptions(options, new Set(['strict', 'complete']));
  if (options._.length !== 1) fail('validate requires one manifest path.');
  if (options.strict && options.complete) fail('Choose --strict or --complete, not both.');
  const mode = options.complete ? 'complete' : options.strict ? 'strict' : 'base';
  const result = validateManifest(root, options._[0], mode);
  process.stdout.write(`Code-model manifest validation passed (${mode}).\n`);
  process.stdout.write(`Model: ${result.manifest.modelId}\n`);
  process.stdout.write(`Attempts: ${result.totalAttempts}/${result.manifest.reviewPolicy.maxAttemptsTotal}\n`);
}

function next(root, values) {
  const options = parseOptions(values);
  rejectUnknownOptions(options, new Set(['json']));
  if (options._.length !== 1) fail('next requires one manifest path.');
  const { manifest, totalAttempts } = validateManifest(root, options._[0], 'base');
  const current = manifest.passes.find((pass) => pass.status !== 'passed');
  let result;
  if (!current) result = { state: 'COMPLETE', nextPass: null, reason: 'All ordered passes are complete.' };
  else if (current.status === 'stopped') result = { state: 'STOP', nextPass: current.id, reason: 'The latest review stopped the model.' };
  else if (current.status === 'blocked') result = { state: 'REQUEST_INPUT', nextPass: current.id, reason: 'The latest review requires user input.' };
  else if (current.attempts >= manifest.reviewPolicy.maxAttemptsPerPass) result = { state: 'STOP', nextPass: current.id, reason: 'The pass attempt limit is exhausted.' };
  else if (totalAttempts >= manifest.reviewPolicy.maxAttemptsTotal) result = { state: 'STOP', nextPass: current.id, reason: 'The overall attempt limit is exhausted.' };
  else result = { state: 'READY', nextPass: current.id, reason: 'The next ordered pass is unlocked.' };
  result.attempts = { pass: current?.attempts ?? 0, total: totalAttempts };
  if (options.json) process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  else {
    process.stdout.write(`STATE=${result.state}\nNEXT_PASS=${result.nextPass ?? ''}\nREASON=${result.reason}\n`);
    process.stdout.write(`PASS_ATTEMPTS=${result.attempts.pass}\nTOTAL_ATTEMPTS=${result.attempts.total}\n`);
  }
}

function record(root, values) {
  const options = parseOptions(values, new Set(['evidence']));
  rejectUnknownOptions(options, new Set(['pass', 'decision', 'summary', 'remaining-gaps', 'evidence', 'character-profile']));
  if (options._.length !== 1) fail('record requires one manifest path.');
  if (!PASS_IDS.includes(options.pass)) fail('--pass must name an ordered CODE pass.');
  if (!DECISIONS.has(options.decision)) fail('--decision is invalid.');
  requireString(options.summary, '--summary');
  const result = validateManifest(root, options._[0], 'base');
  const { manifest } = result;
  const current = manifest.passes.find((pass) => pass.status !== 'passed');
  if (!current) fail('All CODE passes are already complete.');
  if (current.status === 'stopped') fail('The manifest is stopped and cannot accept another review.');
  if (current.id !== options.pass) fail(`The next review must be for ${current.id}.`);
  if (current.attempts >= manifest.reviewPolicy.maxAttemptsPerPass) fail(`Pass ${current.id} has exhausted its attempt limit.`);
  if (result.totalAttempts >= manifest.reviewPolicy.maxAttemptsTotal) fail('The overall attempt limit is exhausted.');

  const evidence = [];
  const seenViews = new Set();
  for (const entry of options.evidence ?? []) {
    const separator = entry.indexOf('=');
    if (separator < 1) fail('--evidence must use view=path.');
    const view = entry.slice(0, separator);
    const fileValue = entry.slice(separator + 1);
    if (!EVIDENCE_VIEWS.has(view)) fail(`Unknown evidence view: ${view}`);
    if (seenViews.has(view)) fail(`Duplicate evidence view: ${view}`);
    seenViews.add(view);
    const artifact = relativeInside(root, fileValue, 'Review evidence', true);
    evidence.push({ path: artifact.relative, sha256: sha256(artifact.absolute), view });
  }
  if (options.decision === 'pass') {
    for (const view of manifest.reviewPolicy.requiredViews) {
      if (!seenViews.has(view)) fail(`A passing review requires ${view} evidence.`);
    }
    if (options['character-profile']) {
      const { assertPassReady } = require('./code-character-cli.cjs');
      assertPassReady(root, options['character-profile'], result.located.relative, current.id);
    }
  }
  current.attempts += 1;
  current.reviews.push({
    decision: options.decision,
    summary: options.summary,
    remainingGaps: options['remaining-gaps'] ?? '',
    createdAt: new Date().toISOString(),
    evidence
  });
  if (options.decision === 'pass') {
    current.status = 'passed';
    const nextPass = manifest.passes[manifest.passes.indexOf(current) + 1];
    if (nextPass) nextPass.status = 'active';
  } else if (options.decision === 'request-input') current.status = 'blocked';
  else if (options.decision === 'stop') current.status = 'stopped';
  else current.status = 'active';
  writeJson(result.located.absolute, manifest);
  process.stdout.write(`Recorded ${options.decision} for ${current.id}.\n`);
  const nextPass = manifest.passes.find((pass) => pass.status !== 'passed');
  process.stdout.write(`Next state: ${nextPass?.status ?? 'complete'}${nextPass ? ` (${nextPass.id})` : ''}\n`);
}

function main() {
  const [operation, rootArg, ...values] = process.argv.slice(2);
  if (!operation || !rootArg) fail('Internal invocation requires an operation and project root.');
  const root = rootPath(rootArg);
  if (operation === 'create') return create(root, values);
  if (operation === 'validate') return validate(root, values);
  if (operation === 'next') return next(root, values);
  if (operation === 'record') return record(root, values);
  fail(`Unknown code-model operation: ${operation}`);
}

module.exports = { PASS_IDS, rootPath, relativeInside, sha256, validateManifest };

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
