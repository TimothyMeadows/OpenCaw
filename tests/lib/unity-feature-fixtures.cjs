'use strict';

// Internal conditional fixture runner. Neither this configuration nor a native
// report is a grant to install packages, activate services or accept an asset.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const engine = require('../../commands/lib/engine-contract.cjs');
const ROOT = path.resolve(__dirname, '../..');
const DIRECTORY = path.join(ROOT, 'tests/fixtures/engines/unity/features');
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const fail = message => { throw new Error(message); };
const versionPattern = /^\d+\.\d+\.\d+[A-Za-z0-9.-]*$/;
const packagePattern = /^com\.[a-z0-9]+(?:[.-][a-z0-9]+)+$/;

function manifest() {
  const value = JSON.parse(fs.readFileSync(path.join(DIRECTORY, 'fixture.json'), 'utf8'));
  if (value.schemaVersion !== 1 || value.engine !== 'UNITY' || !Array.isArray(value.cases) || value.cases.length !== 16 || new Set(value.cases.map(test => test.id)).size !== 16) fail('Invalid Unity feature inventory');
  for (const test of value.cases) {
    if (!/^[A-Za-z][A-Za-z0-9]*$/.test(test.id) || !/^OpenCawUnity(?:Content|Presentation|Tooling)Cases\.[A-Za-z][A-Za-z0-9]*$/.test(test.method) || test.method.split('.').at(-1) !== test.id || !Number.isInteger(test.minimumChecks) || test.minimumChecks < 1 || !test.limit) fail('Invalid Unity feature case contract');
  }
  if (value.manual.length !== 10 || new Set(value.manual.map(test => test.id)).size !== 10) fail('Incomplete Unity supplemental procedures');
  return value;
}

function configuration(file) {
  const value = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (value.schemaVersion !== 1 || !value.settings || typeof value.settings !== 'object' || Array.isArray(value.settings) || !value.packages || typeof value.packages !== 'object' || Array.isArray(value.packages) || Object.keys(value).some(key => !['schemaVersion', 'settings', 'packages'].includes(key))) fail('Invalid Unity fixture configuration');
  for (const [key, setting] of Object.entries(value.settings)) {
    if (!/^[A-Za-z][A-Za-z0-9]*$/.test(key) || typeof setting !== 'string' || !setting.trim() || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(setting)) fail('Invalid Unity fixture setting');
  }
  for (const [id, version] of Object.entries(value.packages)) {
    if (!packagePattern.test(id) || typeof version !== 'string' || !versionPattern.test(version)) fail('Fixture package selections require exact registry package identities/versions');
  }
  return value;
}

function packageInventory(directory, safeFile) {
  const manifestFile = safeFile(path.join(directory, 'Packages/manifest.json'), directory);
  const lockFile = safeFile(path.join(directory, 'Packages/packages-lock.json'), directory);
  const dependencies = JSON.parse(fs.readFileSync(manifestFile, 'utf8')).dependencies;
  const locked = JSON.parse(fs.readFileSync(lockFile, 'utf8')).dependencies;
  if (!dependencies || !locked) fail('Missing fixture package manifest/lock dependencies');
  for (const [id, version] of Object.entries(dependencies)) {
    if (!packagePattern.test(id) || typeof version !== 'string' || !versionPattern.test(version) || locked[id]?.version !== version) fail('Fixture manifest/lock identity mismatch or unsupported source: ' + id);
  }
  const caches = new Map();
  const cacheRoot = path.join(directory, 'Library/PackageCache');
  if (fs.existsSync(cacheRoot)) {
    if (fs.lstatSync(path.join(directory, 'Library')).isSymbolicLink()) fail('Fixture Library cannot be linked');
    if (fs.lstatSync(cacheRoot).isSymbolicLink()) fail('Fixture package cache cannot be linked');
    for (const entry of fs.readdirSync(cacheRoot, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) fail('Fixture package cache entries cannot be linked');
      if (!entry.isDirectory()) continue;
      const folder = path.join(cacheRoot, entry.name);
      const file = path.join(folder, 'package.json');
      if (!fs.existsSync(file)) continue;
      safeFile(file, directory);
      const content = JSON.parse(fs.readFileSync(file, 'utf8'));
      if (!packagePattern.test(content.name || '') || !versionPattern.test(content.version || '')) fail('Invalid installed fixture package identity');
      const key = content.name + '@' + content.version;
      if (caches.has(key)) fail('Ambiguous installed fixture package: ' + key);
      caches.set(key, { directory: folder, name: entry.name, sha256: sha(file) });
    }
  }
  const copies = [];
  let blocked = null;
  for (const [id, item] of Object.entries(locked)) {
    if (!packagePattern.test(id) || !versionPattern.test(item.version || '')) fail('Invalid locked fixture package');
    if (item.source === 'builtin') continue;
    if (item.source !== 'registry') { blocked = 'This isolated fixture requires already resolved builtin/registry packages; unsupported source: ' + id; break; }
    const cached = caches.get(id + '@' + item.version);
    if (!cached) { blocked = 'Already installed project-local package cache is missing: ' + id; break; }
    copies.push(cached);
  }
  return { dependencies, locked, copies, blocked, manifestSha256: sha(manifestFile), lockSha256: sha(lockFile) };
}

function prerequisites(test, config, inventory, directory, safeFile) {
  if (test.execution === 'manual') return { blocked: 'Prepared-Editor procedure required: -noUpm deliberately disables Package Manager; no restoration was enabled' };
  if (inventory.blocked) return { blocked: inventory.blocked };
  const identities = [];
  for (const alternatives of test.packages) {
    const id = alternatives.find(name => Object.hasOwn(config.packages, name));
    if (!id) return { blocked: 'Explicit package selection is missing: ' + alternatives.join(' or ') };
    const version = config.packages[id];
    if (inventory.dependencies[id] !== version || inventory.locked[id]?.version !== version) return { blocked: 'Selected package does not match the prepared fixture manifest/lock: ' + id };
    identities.push({ package: id, version });
  }
  for (const [key, kind] of Object.entries(test.settings)) {
    const value = config.settings[key];
    if (!value) return { blocked: 'Native fixture setting is missing: ' + key };
    if (kind === 'asset' || kind === 'file') {
      if (!value.startsWith('Assets/') || value.includes('\\') || /[\x00-\x1f]/.test(value) || value.split('/').some(part => !part || part === '..' || part === '.')) fail('Fixture input must be an owned Assets path: ' + key);
      const file = path.join(directory, value);
      if (!fs.existsSync(file)) return { blocked: 'Native-authored fixture input is missing: ' + key };
      safeFile(file, directory);
      identities.push({ setting: key, sha256: sha(file) });
    }
  }
  return { identities };
}

function inspectReport(file, test, runId, inputSha256, startedAt, expectedVersion) {
  if (!fs.existsSync(file) || fs.statSync(file).size > 4 * 1024 * 1024) fail('Missing or oversized native Unity report');
  const stat = fs.statSync(file);
  if (stat.mtimeMs < startedAt - 2000 || stat.mtimeMs > Date.now() + 2000) fail('Stale native Unity report timestamp');
  const report = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (report.schemaVersion !== 1 || report.fixture !== 'opencaw-unity-feature' || report.caseName !== test.id || report.runId !== runId || report.inputSha256 !== inputSha256 || report.engineVersion !== expectedVersion) fail('Wrong or stale native Unity report identity');
  if (!['pass', 'blocked', 'fail'].includes(report.status) || typeof report.reason !== 'string' || !report.reason || !Array.isArray(report.observations) || !Number.isInteger(report.checks) || report.checks < 0) fail('Incomplete native Unity report');
  const start = Date.parse(report.startedUtc);
  if (!Number.isFinite(start) || start < startedAt - 2000 || start > Date.now() + 2000) fail('Stale native Unity invocation time');
  if (report.status === 'pass') {
    if (report.checks < test.minimumChecks || report.observations.filter(item => typeof item === 'string' && item.startsWith('CHECK ')).length !== report.checks) fail('Empty or incomplete native Unity assertions');
    if (report.fixturePlayMode !== test.playMode || (test.playMode && report.fixtureDomainReloadDisabled !== true)) fail('Native Unity fixture execution mode mismatch');
  }
  return { status: report.status, reason: report.reason, checks: report.checks, observations: report.observations, runId, inputSha256, engineVersion: report.engineVersion, reportSha256: sha(file) };
}

function unavailable(text) {
  if (/no valid (?:Unity Editor )?licen[cs]e|licen[cs](?:e|ing)[^\n]{0,90}(?:unavailable|not found|not active|failed)/i.test(text)) return 'Matching installed Editor license is unavailable';
  if (/(?:WebGL|Web|platform)[^\n]{0,100}(?:support module[^\n]{0,30}(?:missing|not installed)|not supported|is not installed)|(?:SDK|toolchain)[^\n]{0,100}(?:missing|not found|not installed)/i.test(text)) return 'Required installed platform module/SDK is unavailable';
  return null;
}

// Bind the actual isolated launch inputs, including native assets, their meta
// identities and copied package implementation files, not only package.json.
function inputReceipt(directory) {
  const entries = [];
  const visit = folder => {
    for (const item of fs.readdirSync(folder, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name, 'en'))) {
      const file = path.join(folder, item.name);
      if (item.isSymbolicLink()) fail('Unity launch inputs cannot traverse links');
      if (item.isDirectory()) visit(file);
      else if (item.isFile()) entries.push([path.relative(directory, file).replaceAll(path.sep, '/'), sha(file)]);
      else fail('Unity launch inputs contain an unsupported filesystem entry');
    }
  };
  visit(directory);
  return entries;
}

async function run(context, api) {
  const meta = manifest();
  const verdict = (test, status, reason, details = {}) => ({ engine: 'UNITY', phase: test.execution === 'manual' ? 'manual-native' : 'native-feature', test: test.id, status, reason, ...details });
  const manual = meta.manual.map(test => ({ engine: 'UNITY', phase: 'manual-native', test: test.id, status: test.kind === 'online' ? 'blocked' : 'not-run', reason: test.reason }));
  const all = (status, reason) => [...meta.cases.map(test => verdict(test, status, reason)), ...manual];
  const selected = process.env.OPENCAW_UNITY_FEATURE_CONFIG;
  if (!selected) return all('blocked', 'Select a prepared repository-local OPENCAW_UNITY_FEATURE_CONFIG; no native tooling or service is installed');
  const configFile = api.safeLocalFile(selected);
  const relative = path.relative(ROOT, configFile).replaceAll(path.sep, '/');
  if (!(relative.startsWith('tests/fixtures/engines/unity/features/') || /^\.opencaw\/\.cache\/tasks\/[a-z0-9-]+\//.test(relative)) || path.extname(configFile) !== '.json') fail('Unity fixture configuration must be task-local or inside its fixture directory');
  const config = configuration(configFile);
  const editor = api.executable(process.env.OPENCAW_UNITY_EDITOR, ['Unity', 'Unity.exe']);
  if (!editor) return all('blocked', 'Matching Unity Editor is unavailable');
  const version = process.env.OPENCAW_UNITY_VERSION;
  if (!versionPattern.test(version || '')) return all('blocked', 'Set exact OPENCAW_UNITY_VERSION for the matching installed Editor');
  const inventory = packageInventory(DIRECTORY, api.safeLocalFile);
  const prepared = meta.cases.map(test => prerequisites(test, config, inventory, DIRECTORY, api.safeLocalFile));
  const results = [];
  for (let index = 0; index < meta.cases.length; index++) {
    const test = meta.cases[index];
    const ready = prepared[index];
    if (ready.blocked) { results.push(verdict(test, 'blocked', ready.blocked)); continue; }
    const runId = crypto.randomUUID();
    const directory = path.join(context.temp, 'unity-' + test.id + '-' + runId);
    api.copyFixture(DIRECTORY, directory);
    for (const cached of inventory.copies) api.copyFixture(cached.directory, path.join(directory, 'Library/PackageCache', cached.name));
    fs.mkdirSync(path.join(directory, 'ProjectSettings'), { recursive: true });
    fs.writeFileSync(path.join(directory, 'ProjectSettings/ProjectVersion.txt'), 'm_EditorVersion: ' + version + '\n');
    if (test.symbols.length) fs.writeFileSync(path.join(directory, 'Assets/csc.rsp'), '-define:' + test.symbols.join(';') + '\n');
    engine.generate(directory, 'UNITY');
    engine.requireEngine(directory, 'UNITY');
    const output = path.join(directory, 'outputs', runId); fs.mkdirSync(output, { recursive: true });
    const report = path.join(output, 'report.json');
    const inputs = { copiedFiles: inputReceipt(directory), configSha256: sha(configFile), version, packageManifest: inventory.manifestSha256, packageLock: inventory.lockSha256, test: test.id, prerequisites: ready.identities };
    const inputSha256 = crypto.createHash('sha256').update(JSON.stringify(inputs)).digest('hex');
    fs.writeFileSync(path.join(output, 'inputs.json'), JSON.stringify(inputs, null, 2) + '\n', { flag: 'wx' });
    const log = path.join(directory, 'editor.log');
    const args = ['-batchmode', '-noUpm', '-projectPath', directory, '-executeMethod', 'OpenCawUnityFeatureDriver.Run', '-logFile', log];
    if (!test.graphics) args.push('-nographics');
    if (test.buildTarget) args.push('-buildTarget', test.buildTarget);
    const env = { OPENCAW_UNITY_FEATURE_CASE: test.id, OPENCAW_UNITY_FEATURE_METHOD: test.method, OPENCAW_UNITY_FEATURE_RUN: runId, OPENCAW_UNITY_FEATURE_REPORT: report, OPENCAW_UNITY_FEATURE_OUTPUT: output, OPENCAW_UNITY_FEATURE_INPUT_SHA256: inputSha256, OPENCAW_UNITY_FEATURE_TIMEOUT_MS: String(context.timeoutMs || 180000), OPENCAW_UNITY_FEATURE_PLAYMODE: test.playMode ? '1' : '0' };
    for (const key of Object.keys(test.settings)) env['OPENCAW_UNITY_FIXTURE_' + key] = config.settings[key];
    const startedAt = Date.now();
    const executed = await context.run(editor, args, { cwd: directory, log: path.join(directory, 'process.log'), env });
    const failure = api.nativeFailure(executed);
    const nativeLog = fs.existsSync(log) ? fs.readFileSync(log, 'utf8').slice(-512 * 1024) : '';
    if (failure && executed.code !== 78) {
      const prerequisite = unavailable(executed.text + nativeLog);
      results.push(verdict(test, prerequisite ? 'blocked' : 'fail', prerequisite || failure));
      continue;
    }
    try {
      if (executed.timedOut || executed.cancelled || executed.spawnError) fail(failure);
      const checked = inspectReport(report, test, runId, inputSha256, startedAt, version);
      if (executed.code !== (checked.status === 'blocked' ? 78 : checked.status === 'pass' ? 0 : 1)) fail('Native Unity process/report disagreement');
      if (checked.status === 'pass' && test.id === 'WebBuild' && !fs.existsSync(path.join(output, 'web-player/index.html'))) fail('Native WebGL BuildReport did not produce the expected player artifact');
      results.push(verdict(test, checked.status, checked.reason, { ...checked, acceptance: test.limit }));
    } catch (error) { results.push(verdict(test, 'fail', error.message)); }
  }
  return [...results, ...manual];
}

module.exports = { ROOT, DIRECTORY, manifest, configuration, packageInventory, prerequisites, inspectReport, unavailable, inputReceipt, run };
