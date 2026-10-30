'use strict';

// Owned metadata and nonexecutable bytes only. These tests never load a model,
// inspect a private recording, spend a generation allowance or certify quality.
const assert = require('assert/strict'), fs = require('fs'), path = require('path');
const cp = require('child_process');
const runtime = require('../commands/lib/bubo-runtime.cjs');
const styles = require('../commands/lib/style-contract.cjs');
const adapter = require('../commands/lib/bubo-media-adapter.cjs');
const cache = path.basename(runtime.BASE) === '.opencaw' ? path.join(runtime.BASE, '.cache') : path.join(runtime.BASE, '.opencaw/.cache');
const evidence = path.join(cache, 'tasks/opencaw-retire-comfyui/evidence/media-context');
fs.mkdirSync(evidence, { recursive: true });
const root = fs.mkdtempSync(path.join(evidence, 'owned-'));
const task = 'owned-media', workspace = '.opencaw/.cache/bubo-media';
const stateRoot = '.opencaw/.cache/tasks/' + task + '/bubo-media';
const mediaState = '.opencaw/.cache/retained-media-ledger';
const manifest = 'inputs/request.json';
let assertions = 0;
function check(value, message) { assert(value, message); assertions++; }
function rejects(action, expression, message) { assert.throws(action, expression, message); assertions++; }
function write(name, value) {
  const file = path.join(root, name); fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value, null, 2) + '\n');
  return name;
}
function dir(name) { fs.mkdirSync(path.join(root, name), { recursive: true }); return name; }
const identity = name => ({ path: name, sha256: runtime.hash(path.join(root, name)) });
const copy = value => JSON.parse(JSON.stringify(value));
function snapshot(folder = root) {
  const rows = [];
  function visit(current) {
    for (const name of fs.readdirSync(current).sort()) {
      const full = path.join(current, name), relative = path.relative(folder, full), stat = fs.lstatSync(full);
      rows.push([relative, stat.isSymbolicLink() ? 'link:' + fs.readlinkSync(full) : stat.isDirectory() ? 'directory' : runtime.hash(full)]);
      if (stat.isDirectory() && !stat.isSymbolicLink()) visit(full);
    }
  }
  visit(folder); return JSON.stringify(rows);
}
const mediaText = '# MEDIA.md\n\nGenerated from OpenCaw media pipeline templates:\n- CLOUD\n- LOCAL\n\n---\n\n'
  + ['Pipeline Availability', 'Capability Matrix', 'Destinations And Budgets', 'Rights, Consent, And Provenance', 'Review And Promotion'].map(value => '## ' + value + '\n').join('\n')
  + '\nDiscover image, music, sound-effect (SFX), and voice independently through the pinned Bubo runtime.\n'
  + '\nRequire the user to choose a provider. Never switch or fall back between providers silently.\n';
write('MEDIA.md', mediaText);
write('inputs/rights.json', { fixture: 'OWNED synthetic prompt rights, no actual human approval', authorized: true });
write('inputs/license.json', { fixture: 'OWNED synthetic license assertion, no acceptance of external terms' });
write('inputs/never-auto-discover.json', { fixture: 'An incidental prompt string is not typed evidence.' });
const modelDirectory = dir(workspace + '/tools/models/owned');
const python = identity(write(workspace + '/tools/environment/python-owned.bin', 'OWNED nonexecutable Python identity fixture'));
const receiptPath = write(workspace + '/receipts/owned.json', {
  schemaVersion: 'bubo-media-installation/v1', backend: 'stable-audio-open', modelDirectory,
  licenses: [identity('inputs/license.json')], python,
  fixture: 'Host admission only; no installation/native readiness claim'
});
const backends = [
  ['flux-schnell', 'image'], ['stable-audio-open', 'sfx'], ['ace-step-turbo', 'music'],
  ['qwen3-tts-customvoice', 'preset-speech'], ['qwen3-tts-base', 'consented-cloning']
].map(([id, modality]) => ({ id, modality }));
const bundle = dir('.opencaw/runtime/bubo/artifacts/bubo');
const info = {
  pinned: { revision: '1'.repeat(40), apiVersion: 1, resourceCatalogSha256: '2'.repeat(64) },
  root: path.join(root, '.opencaw/runtime/bubo'), folder: path.join(root, bundle),
  executable: path.join(root, write(bundle + '/bubo-owned.bin', 'OWNED nonexecutable apphost fixture')),
  capability: { mediaBackends: backends, build: { sourceRevision: '1'.repeat(40), sourceDirty: false } }
};
const base = {
  schemaVersion: 'bubo-media-request/v1', requestId: 'owned-request', task, backend: 'stable-audio-open',
  outputDirectory: workspace + '/staging/owned-request', rights: identity('inputs/rights.json'), installation: identity(receiptPath),
  items: [{ id: 'owned-output', prompt: 'Synthetic fixture only: inputs/never-auto-discover.json', seed: 123, durationSeconds: 1 }],
  budget: { maxOutputs: 1, maxOutputBytes: 4096, maxAudioSeconds: 2 }
};
function options(extra = []) { return adapter.parse(['--root', root, '--task', task, '--manifest', manifest, ...extra]); }
function prepare(request = base, extra = [], operation = 'generate') {
  write(manifest, request);
  return adapter.contextFor(operation, options(extra), info);
}
function withReceipt(changes) {
  const receipt = { ...JSON.parse(fs.readFileSync(path.join(root, receiptPath), 'utf8')), ...changes };
  return { ...base, installation: identity(write(workspace + '/receipts/variant.json', receipt)) };
}

// Protected host/runtime identity cannot be supplied through the public parser.
for (const key of ['host-context', 'api-version', 'runtime', 'runtime-revision', 'resource-catalog-sha256', 'promotion'])
  rejects(() => adapter.parse(['--' + key, 'injected']), /protected|Unknown|Expected unique --option/, key + ' protected');
rejects(() => adapter.parse(['--task', task, '--task', task]), /duplicate/);
rejects(() => adapter.parse(['--manifest']), /Missing value/);
rejects(() => adapter.parse(['--execute', 'false']), /only true/);
rejects(() => adapter.parse(['--load', 'false']), /only true/);
check(adapter.parse(['--execute']).get('execute') === 'true', 'Explicit setup execute shorthand');
rejects(() => prepare(base, ['--execute']), /only to explicit setup/);
rejects(() => prepare(base, ['--load', 'true']), /only to zero-sample/);
rejects(() => adapter.contextFor('promote', options(), info), /promotion is separate/);
rejects(() => adapter.contextFor('generate', new Map([...options(), ['host-context', 'injected']]), info), /protected/);
rejects(() => adapter.contextFor('generate', new Map([...options(), ['task', '../unsafe']]), info), /safe --task/);
rejects(() => prepare({ ...base, task: 'other-task' }), /ownership/);
for (const [key, value] of [['timeout', '0'], ['timeout', 'Infinity'], ['max-log-bytes', '1.5'], ['max-private-bytes', '-1']])
  rejects(() => prepare(base, ['--' + key, value]), /finite/);

// Audio policy remains independent from STYLE/ENGINE. Context construction is
// read-only and cannot start a subprocess, even when explicit load is admitted.
write(manifest, base);
const before = snapshot(), saved = new Map();
let prepared;
try {
  for (const key of ['spawn', 'spawnSync', 'exec', 'execSync', 'execFile', 'execFileSync', 'fork']) {
    saved.set(key, cp[key]); cp[key] = () => { throw new Error('Context attempted subprocess: ' + key); };
  }
  prepared = adapter.contextFor('generate', options(['--timeout', '321', '--max-log-bytes', '4096', '--max-private-bytes', '8192']), info);
  const inspected = adapter.contextFor('inspect', options(['--load', 'true']), info);
  check(inspected.options.get('load') === 'true', 'Zero-sample load remains explicit');
} finally { for (const [key, value] of saved) cp[key] = value; }
check(snapshot() === before, 'Context and explicit inspect admission write no state or files');
check(!fs.existsSync(path.join(root, 'STYLE.md')) && !fs.existsSync(path.join(root, 'ENGINE.md')), 'Audio fixtures have no visual/engine contracts');
check(prepared.context.policy.purpose === 'local-media' && prepared.context.policy.pipeline === 'LOCAL', 'Explicit LOCAL audio policy');
check(!prepared.context.policy.imageStyle && !prepared.context.policy.engine && !prepared.context.policy.libraries, 'Audio fabricates no visual selection or libraries');
check(!prepared.context.permissions.provisioning && !prepared.context.permissions.promotion, 'Generation grants neither provisioning nor promotion');
check(prepared.context.budgets.timeoutSeconds === 321 && prepared.context.budgets.maxLogBytes === 4096 && prepared.context.budgets.maxPrivateBytes === 8192, 'Finite host process ceilings retained');
assert.deepEqual([...prepared.options.keys()], ['root', 'manifest']); assertions++;
check(prepared.context.references.some(value => value.path === 'inputs/rights.json' && value.kind === 'rights'), 'Rights have typed admission');
check(prepared.context.references.some(value => value.path === 'inputs/license.json' && value.kind === 'rights'), 'License assertion has typed admission');
check(!prepared.context.references.some(value => value.path === 'inputs/never-auto-discover.json'), 'Incidental prompt paths are not recursively admitted');
check(prepared.context.tools.length === 1 && prepared.context.tools[0].sha256 === python.sha256, 'Only exact selected executable is admitted');
check(prepared.context.task === task && !prepared.options.has('task') && prepared.stateRoot === stateRoot && prepared.context.roots.staging === workspace + '/staging', 'Task ownership stays in context/request while canonical staging and native arguments match the media API');
check(prepared.context.roots.inputs.includes(bundle), 'Pinned publication is read-only input');

// Required provider policy and typed evidence cannot be substituted or stale.
write('inputs/qa-media.md', mediaText);
check(prepare(base, ['--media', 'inputs/qa-media.md']).context.policy.media.path === 'inputs/qa-media.md', 'Explicit local QA policy is supported');
for (const altered of [mediaText.replace('- LOCAL\n', ''), mediaText.replace('- CLOUD\n- LOCAL', '- LOCAL\n- CLOUD'), mediaText.replace('Require the user to choose', 'A provider is selected'), mediaText.replace('Never switch or fall back between providers silently.', '')]) {
  write('inputs/qa-media.md', altered);
  rejects(() => prepare(base, ['--media', 'inputs/qa-media.md']), /MEDIA policy/);
}
for (const retired of ['ComfyUI', 'comfy-cli', 'use-comfyui-local-generation', 'run-comfyui-workflow']) {
  write('inputs/qa-media.md', mediaText + '\nUse ' + retired + ' for LOCAL execution.\n');
  rejects(() => prepare(base, ['--media', 'inputs/qa-media.md']), /retired|Bubo|LOCAL/i);
}
write('inputs/qa-media.md', mediaText.replace('image, music, sound-effect (SFX), and voice', 'media'));
rejects(() => prepare(base, ['--media', 'inputs/qa-media.md']), /modality|image|music|voice|SFX|sound-effect/i);
write('inputs/qa-media.md', mediaText + '\naccess_token=OWNED_TEST_CREDENTIAL_123456789\n');
rejects(() => prepare(base, ['--media', 'inputs/qa-media.md']), /credential/);
rejects(() => prepare({ ...base, rights: { ...base.rights, sha256: '0'.repeat(64) } }), /hash changed/);
rejects(() => prepare({ ...base, rights: { ...base.rights, path: 'inputs/missing.json' } }), /Missing regular/);
rejects(() => prepare({ ...base, rights: { ...base.rights, path: 'https://invalid.example/rights' } }), /Colon|Invalid|escapes/);
rejects(() => prepare({ ...base, installation: { ...base.installation, sha256: '0'.repeat(64) } }), /hash changed/);
rejects(() => prepare({ ...base, rights: base.rights.path }), /typed|identity/i);
rejects(() => prepare({ ...base, installation: base.installation.path }), /typed|identity/i);
rejects(() => prepare(withReceipt({ licenses: ['inputs/license.json'] })), /typed|identity/i);
rejects(() => prepare({ ...base, backend: 'undeclared-backend' }), /not declared/);
rejects(() => prepare({ ...base, items: [] }), /bounded/);
rejects(() => prepare({ ...base, items: [...base.items, ...base.items, ...base.items, ...base.items, ...base.items] }), /bounded/);
for (const seed of [9007199254740993, Number.MAX_SAFE_INTEGER+1, -1, 1.5, null])
  rejects(() => prepare({ ...base, items: [{ ...base.items[0], seed }] }), /nonnegative safe integers/);
check(prepare({ ...base, items: [{ ...base.items[0], seed: Number.MAX_SAFE_INTEGER }] }).request.items[0].seed===Number.MAX_SAFE_INTEGER, 'Maximum safe seed is preserved exactly');
rejects(() => prepare(base, ['--selection', 'inputs/rights.json']), /Audio does not consume/);
for (const location of ['assets/generated', '.opencaw/.cache', '.opencaw/.cache/tasks/' + task, '.opencaw/.cache/local-media/acceptance-roots', '../outside'])
  rejects(() => prepare(base, ['--workspace', location]), /cache child|separate ownership|Traversal/);
rejects(() => prepare(base, ['--media-state', workspace + '/staging']), /separate ownership/);
rejects(() => prepare({ ...base, outputDirectory: 'assets/runtime' }), /workspace staging/);
rejects(() => prepare({ ...base, rights: identity(write(stateRoot + '/forbidden-rights.json', '{}')) }), /overlap mutable/);
const originalPython = fs.readFileSync(path.join(root, python.path));
write(python.path, 'Changed selected tool');
rejects(() => prepare(), /executable\/module is missing or changed/);
write(python.path, originalPython);
let links = 0;
const linked = path.join(root, '.opencaw/.cache/linked-workspace');
try {
  fs.symlinkSync(path.join(root, workspace), linked, process.platform === 'win32' ? 'junction' : 'dir'); links++;
  rejects(() => prepare(base, ['--workspace', '.opencaw/.cache/linked-workspace']), /symbolic links or junctions/);
} catch (error) { if (!['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) throw error; }

// Images additionally bind current STYLE and task-local explicit LOCAL choice.
const originalStyle = fs.readFileSync(path.join(runtime.BASE, 'STYLE.md'), 'utf8').replace(/\r\n/g, '\n');
write('STYLE.md', originalStyle);
const imageReceipt = { ...JSON.parse(fs.readFileSync(path.join(root, receiptPath), 'utf8')), backend: 'flux-schnell' };
const imageInstallation = identity(write(workspace + '/receipts/image.json', imageReceipt));
const image = { ...base, backend: 'flux-schnell', installation: imageInstallation, items: [{ id: 'owned-output', prompt: 'Owned image fixture', seed: 5, width: 64, height: 64 }] };
rejects(() => prepare(image), /Images require primary LOCAL/);
const selectionPath = '.opencaw/.cache/tasks/' + task + '/local-selection.json';
const selection = styles.resolve(root, 'STYLE.md', { override: 'LOCAL' });
write(selectionPath, selection);
const imageContext = prepare(image, ['--selection', selectionPath]).context;
check(imageContext.policy.imageStyle.sha256 === runtime.hash(path.join(root, 'STYLE.md')), 'Images bind current STYLE bytes');
check(imageContext.policy.pipeline === 'LOCAL' && !imageContext.policy.engine, 'Image LOCAL does not imply an engine selection');
write('inputs/copied-selection.json', selection);
rejects(() => prepare(image, ['--selection', 'inputs/copied-selection.json']), /bind this task/);
write(selectionPath, { ...selection, pipeline: 'CLOUD' });
rejects(() => prepare(image, ['--selection', selectionPath]), /bind this task/);
write(selectionPath, selection); write('STYLE.md', originalStyle + '\n');
rejects(() => prepare(image, ['--selection', selectionPath]), /current STYLE/);
write('STYLE.md', originalStyle);

// All reference-cloning inputs and consent provenance are separately hash-bound.
const cloneReceipt = { ...imageReceipt, backend: 'qwen3-tts-base' };
const cloneInstallation = identity(write(workspace + '/receipts/clone.json', cloneReceipt));
write('inputs/owned-reference.wav', Buffer.from('OWNED synthetic audio bytes; never decoded'));
write('inputs/owned-transcript.txt', 'Owned synthetic transcript, no private recording.');
write('inputs/consent-source.json', { fixture: 'Synthetic explicit QA-only consent source, no person or recording' });
write('inputs/consent.json', { sourceEvidence: identity('inputs/consent-source.json'), scope: 'qa-only' });
const reference = { audio: identity('inputs/owned-reference.wav'), transcript: identity('inputs/owned-transcript.txt'), rights: identity('inputs/rights.json'), consent: identity('inputs/consent.json') };
const clone = { ...base, backend: 'qwen3-tts-base', installation: cloneInstallation, items: [{ id: 'owned-output', prompt: 'Owned text', seed: 9, voice: { reference } }] };
const cloned = prepare(clone);
for (const [name, kind] of [['audio', 'input'], ['transcript', 'input'], ['rights', 'rights'], ['consent', 'consent']])
  check(cloned.context.references.some(value => value.path === reference[name].path && value.kind === kind), 'Cloning admits exact ' + name + ' kind');
check(cloned.context.references.some(value => value.path === 'inputs/consent-source.json' && value.kind === 'consent'), 'Consent source assertion is retained');
for (const name of ['audio', 'transcript', 'rights', 'consent']) {
  const altered = copy(clone); delete altered.items[0].voice.reference[name];
  rejects(() => prepare(altered), /all four typed/);
  const untyped = copy(clone); untyped.items[0].voice.reference[name] = reference[name].path;
  rejects(() => prepare(untyped), /typed|identity/i);
}
const substituted = copy(clone); substituted.items[0].voice.reference.audio.path = 'https://invalid.example/voice.wav';
rejects(() => prepare(substituted), /Colon|Invalid|escapes/);
const sourceBytes = fs.readFileSync(path.join(root, 'inputs/consent.json'));
write('inputs/consent.json', { fixture: 'Missing source assertion' });
const missingSource = copy(clone); missingSource.items[0].voice.reference.consent = identity('inputs/consent.json');
rejects(() => prepare(missingSource), /existing source assertion/);
write('inputs/consent.json', { sourceEvidence: 'inputs/consent-source.json', scope: 'qa-only' });
const untypedSource = copy(clone); untypedSource.items[0].voice.reference.consent = identity('inputs/consent.json');
rejects(() => prepare(untypedSource), /typed|identity/i);
write('inputs/consent.json', sourceBytes);
check(!cloned.context.permissions.promotion, 'QA-only clone consent grants no promotion authority');
write('inputs/owned-transcript.txt', 'Changed synthetic transcript');
rejects(() => prepare(clone), /hash changed/);
write('inputs/owned-transcript.txt', 'Owned synthetic transcript, no private recording.');

// Acceptance binding does not create/reset Bubo claims or inherit approval.
const approvalPath = write('inputs/approval.json', { schemaVersion: 'bubo-media-acceptance-budget/v1', maximumCandidates: 1, maximumRevisions: 1, sharedStateRoot: mediaState, fixture: 'OWNED policy fixture; never used for inference' });
const accepted = { ...base, acceptance: { approval: identity(approvalPath) } };
rejects(() => prepare(accepted), /explicitly retained/);
rejects(() => prepare(accepted, ['--media-state', '.opencaw/.cache/another-ledger']), /Approval root differs/);
const claim = write(mediaState + '/claims/owned-used-budget.json', { fixture: true, candidateUsed: true, revisionUsed: true });
const claimBytes = fs.readFileSync(path.join(root, claim));
const bound = prepare(accepted, ['--media-state', mediaState]);
const prebind = snapshot();
check(!fs.existsSync(path.join(root, '.opencaw/.cache/local-media/acceptance-roots')), 'Context does not create acceptance binding');
check(snapshot() === prebind, 'Shared acceptance context leaves claims unchanged');
const bindingFile = adapter.bindSharedState(bound), bindingBytes = fs.readFileSync(bindingFile);
check(adapter.bindSharedState(bound) === bindingFile && fs.readFileSync(bindingFile).equals(bindingBytes), 'Binding is create-new then compare without rewriting');
const newWorkspace = '.opencaw/.cache/alternate-workspace';
const relocatedReceipt = identity(write(newWorkspace + '/receipts/owned.json', {
  schemaVersion: 'bubo-media-installation/v1', backend: base.backend,
  modelDirectory: dir(newWorkspace + '/tools/models/owned'), licenses: [identity('inputs/license.json')],
  python: identity(write(newWorkspace + '/tools/environment/python-owned.bin', 'OWNED nonexecutable relocated tool'))
}));
const relocatedRequest = { ...accepted, installation: relocatedReceipt, outputDirectory: newWorkspace + '/staging/owned' };
const relocated = prepare(relocatedRequest, ['--workspace', newWorkspace, '--media-state', mediaState]);
check(relocated.sharedBinding.approvalSha256 === bound.sharedBinding.approvalSha256 && relocated.mediaState === mediaState, 'Workspace changes retain the same approval ledger');
rejects(() => prepare(accepted, ['--media-state', '.opencaw/.cache/another-ledger'], 'inspect'), /already bound/);
check(fs.readFileSync(bindingFile).equals(bindingBytes) && fs.readFileSync(path.join(root, claim)).equals(claimBytes), 'Rejected root changes preserve policy and consumed claim bytes');

// Explicit platform module identities, never ambient PATH discovery.
const moduleFile = write('platform/owned-module.bin', 'OWNED nonexecutable platform module');
const platformPath = write('inputs/platform-modules.json', { schemaVersion: 'opencaw-platform-modules/v1', modules: [identity(moduleFile)] });
check(prepare(base, ['--platform-modules', platformPath]).context.tools.some(value => value.kind === 'platform-module' && value.sha256 === identity(moduleFile).sha256), 'Explicit module is separately classified and hash-bound');
write(platformPath, { schemaVersion: 'opencaw-platform-modules/v1', modules: [{ ...identity(moduleFile), sha256: '0'.repeat(64) }] });
rejects(() => prepare(base, ['--platform-modules', platformPath]), /missing or changed/);
write(platformPath, { schemaVersion: 'opencaw-platform-modules/v1', modules: [identity(moduleFile)], discover: true });
rejects(() => prepare(base, ['--platform-modules', platformPath]), /platform module manifest/);

// Registration is dry-run by default and can write only its declared new receipt.
const setup = { schemaVersion: 'bubo-media-setup/v1', task, backend: 'stable-audio-open', modelDirectory, python, licenses: [identity('inputs/license.json')], receiptPath: workspace + '/installations/new.json' };
const dry = prepare(setup, [], 'setup');
check(!dry.context.permissions.provisioning && !dry.context.permissions.promotion, 'Registration default is dry-run without promotion');
assert.deepEqual(dry.context.roots.outputs, [setup.receiptPath]); assertions++;
check(prepare(setup, ['--execute'], 'setup').context.permissions.provisioning, 'Only explicit setup enables provisioning');
for (const receipt of [receiptPath, workspace + '/tools/receipt.json', workspace + '/downloads/receipt.json', workspace + '/staging/receipt.json', stateRoot + '/receipt.json', workspace + '/receipts/new.json', workspace + '/installations/nested/new.json', workspace + '/installations/new.txt'])
  rejects(() => prepare({ ...setup, receiptPath: receipt }, [], 'setup'), /new separate workspace receipt/);
const registrationRecord={schemaVersion:'bubo-media-installation/v1',backend:setup.backend,platform:'owned-fixture',catalogSha256:'7'.repeat(64)};
write(setup.receiptPath,registrationRecord);
const discovered=require('../commands/lib/bubo-media-host.cjs').installationRecords(root,workspace,registrationRecord.catalogSha256);
check(discovered.some(value=>value.path===setup.receiptPath && value.catalogMatches && value.installedContentVerified===false), 'An admitted registration receipt is discoverable without claiming installed-content readiness');

// Archives can retain their dedicated download location without granting it
// executable/model-directory authority or overlapping mutable production state.
const pythonArchive = write(workspace + '/downloads/python-owned.archive', 'OWNED archive metadata fixture, never opened as an archive');
const sourceArchive = write(workspace + '/downloads/source-owned.archive', 'OWNED source archive metadata fixture, never extracted');
const archiveContext = prepare(withReceipt({ pythonArchive, sourceArchive })).context;
check(archiveContext.roots.tools.includes(workspace + '/downloads'), 'Dedicated downloads have explicit dependency-read admission');
const retainedToolArchive = write(workspace + '/tools/source-owned.archive', 'OWNED retained archive fixture, never extracted');
check(prepare(withReceipt({ sourceArchive: retainedToolArchive })).context.roots.tools.includes(workspace + '/tools'), 'Existing tools-child archives remain compatible');
const downloadModel = dir(workspace + '/downloads/forbidden-models');
rejects(() => prepare(withReceipt({ modelDirectory: downloadModel })), /tools|director|download/i);
rejects(() => prepare(withReceipt({ python: identity(sourceArchive) })), /executables.*tools|tools.*executable/i);
rejects(() => prepare(withReceipt({ sourceArchive: write(workspace + '/staging/forbidden.archive', 'OWNED mutable output fixture') })), /tools|archive|download|mutable/i);
const provision = { schemaVersion: 'bubo-media-provision/v1', task, backend: base.backend, licenses: [identity('inputs/license.json')],
  installationRoot: workspace + '/tools/owned-new-install', downloadRoot: workspace + '/downloads/owned-new-downloads', bootstrapPython: python };
const provisioned = prepare(provision, [], 'setup');
check(!provisioned.context.permissions.provisioning && !fs.existsSync(path.join(root, provision.installationRoot)), 'Provision admission remains dry-run and creates no installation');
for (const roots of [{ installationRoot: workspace + '/downloads/wrong-install' }, { downloadRoot: workspace + '/tools/wrong-download' }, { downloadRoot: provision.installationRoot }])
  rejects(() => prepare({ ...provision, ...roots }, [], 'setup'), /Provisioning|installation|download|separate/i);

// Host provenance preserves native evidence and leaves review/promotion pending.
const provenancePrepared = prepare();
const outputPath = write(base.outputDirectory + '/000.owned', 'OWNED output bytes, no decoded media or quality evidence');
const settingsPath = write(base.outputDirectory + '/000.settings.json', { fixture: true, effectiveSeed: 123 });
const catalogPath = write(bundle + '/resources/media/catalog.json', { backends: [{ id: base.backend, files: [{ path: 'owned-model.bin', sha256: '3'.repeat(64), revision: '4'.repeat(40), repository: 'owned-fixture', license: 'OWNED' }] }] });
info.catalog = { files: { 'resources/media/catalog.json': identity(catalogPath).sha256 } };
const native = { status: 'generated-staged', backend: base.backend, requestPath: manifest, promotion: false, humanReview: 'pending', requestSha256: runtime.hash(path.join(root, manifest)), completedAt: '2026-01-01T00:00:00Z', workerSourceSha256: '5'.repeat(64),
  actualSettings: { fixture: true }, timing: { fixtureOnly: true }, cleanup: { fixtureOnly: true },
  outputs: [{ id: base.items[0].id, path: outputPath, sha256: identity(outputPath).sha256, bytes: fs.statSync(path.join(root, outputPath)).size, sampleRate: 24000, humanReview: 'pending', promotion: false, actual: { nativeMetadata: identity(settingsPath) } }] };
const nativePath = write(stateRoot + '/media/' + base.requestId + '/manifest.json', native);
const dispatch = dir(stateRoot + '/dispatch/owned/bubo-host/owned');
write(dispatch + '/host-context.json', provenancePrepared.context);
const result = { schemaVersion: 'bubo-execution-result/v1', apiVersion: 1, status: 'succeeded', workflow: 'media', operation: 'generate',
  runtime: info.capability.build, hostContextSha256: identity(dispatch + '/host-context.json').sha256, data: native };
write(dispatch + '/result.json', result);
const preserved = [nativePath, dispatch + '/result.json', dispatch + '/host-context.json', settingsPath, outputPath].map(name => [name, identity(name).sha256]);
rejects(() => adapter.exportProvenance(provenancePrepared, { ...result, status: 'failed' }, info, dispatch), /Only successful staged/);
const different = copy(result); different.data.outputs[0].promotion = true;
rejects(() => adapter.exportProvenance(provenancePrepared, different, info, dispatch), /result\/context ancestry differs/i);
write(dispatch + '/result.json', different);
rejects(() => adapter.exportProvenance(provenancePrepared, different, info, dispatch), /manifest.*differ/i);
write(dispatch + '/result.json', result);
write(dispatch + '/host-context.json', { ...provenancePrepared.context, task: 'another-task' });
rejects(() => adapter.exportProvenance(provenancePrepared, result, info, dispatch), /result\/context ancestry differs/i);
write(dispatch + '/host-context.json', provenancePrepared.context);
const originalCatalog = fs.readFileSync(path.join(root, catalogPath));
write(catalogPath, Buffer.concat([originalCatalog, Buffer.from('\n')]));
rejects(() => adapter.exportProvenance(provenancePrepared, result, info, dispatch), /catalog.*changed|catalog.*identity|catalog.*pinned/i);
write(catalogPath, originalCatalog);
const originalOutput = fs.readFileSync(path.join(root, outputPath)), changedOutput = Buffer.from(originalOutput);
changedOutput[0] ^= 1; write(outputPath, changedOutput);
rejects(() => adapter.exportProvenance(provenancePrepared, result, info, dispatch), /output.*identity|output.*hash|output.*changed|staged.*identity/i);
write(outputPath, originalOutput);
write(settingsPath, { fixture: 'changed' });
rejects(() => adapter.exportProvenance(provenancePrepared, result, info, dispatch), /settings ancestry changed/);
write(settingsPath, { fixture: true, effectiveSeed: 123 });
const exported = adapter.exportProvenance(provenancePrepared, result, info, dispatch);
check(exported.length === 1 && !path.isAbsolute(exported[0]), 'Export returns canonical project-relative neutral manifest');
const neutral = JSON.parse(fs.readFileSync(path.join(root, exported[0]), 'utf8'));
check(neutral.schemaVersion === 1 && neutral.backend.kind === 'local' && neutral.backend.provider === 'Bubo' && neutral.backend.capability === base.backend, 'Existing provider-neutral schema records selected native backend');
check(neutral.review.status === 'pending' && neutral.outputs[0].status === 'staged' && neutral.runtime.destination.unavailable, 'Generation does not imply human acceptance or runtime promotion');
for (const [key, source] of [['nativeManifest', nativePath], ['nativeResult', dispatch + '/result.json'], ['hostContext', dispatch + '/host-context.json'], ['nativeSettings', settingsPath], ['sourceRequest', manifest]])
  check(neutral.generation.parameters[key].sha256 === identity(source).sha256, 'Neutral ancestry retains exact ' + key);
check(neutral.generation.parameters.runtime.revision === info.pinned.revision && neutral.generation.parameters.runtime.resourceCatalogSha256 === info.pinned.resourceCatalogSha256, 'Runtime and resource identities are explicit');
for (const [name, sha] of preserved) check(identity(name).sha256 === sha, 'Export leaves native evidence unchanged: ' + name);
const exportBytes = fs.readFileSync(path.join(root, exported[0]));
rejects(() => adapter.exportProvenance(provenancePrepared, result, info, dispatch), /EEXIST/);
check(fs.readFileSync(path.join(root, exported[0])).equals(exportBytes), 'Existing neutral provenance cannot be overwritten');

fs.writeFileSync(path.join(evidence, 'latest.json'), JSON.stringify({ status: 'pass', assertions, root, platform: process.platform, nodeVersion: process.version, linkedPathAssertions: links, nativeExecution: false, modelLoading: false, modelGeneration: false, humanAcceptance: false, scope: 'Owned model-free host policy, admission, immutable shared scope and provenance fixtures only.' }, null, 2) + '\n');
console.log('PASS:', assertions, 'model-free media host context assertions');
