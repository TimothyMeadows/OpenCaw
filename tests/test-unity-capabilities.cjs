'use strict';

// Structural contracts and explicitly synthetic report/process outcomes only.
// This suite never launches Unity, resolves packages or invokes online services.
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const engine = require('../commands/lib/engine-contract.cjs');
const native = require('./test-native-engine-fixtures.cjs');
const features = require('./lib/unity-feature-fixtures.cjs');
const root = engine.BASE;
const temporary = fs.mkdtempSync(path.join(__dirname, '.unity-capabilities-'));
let checks = 0;
const equal = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const rejects = (action, pattern) => { assert.throws(action, pattern); checks++; };
const json = (file, value) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(value)); };

function inventoryFixture(name, dependencies, locked, cached = []) {
  const directory = path.join(temporary, name);
  json(path.join(directory, 'Packages/manifest.json'), { dependencies });
  json(path.join(directory, 'Packages/packages-lock.json'), { dependencies: locked });
  for (const [folder, identity] of cached) json(path.join(directory, 'Library/PackageCache', folder, 'package.json'), identity);
  return directory;
}

async function main() {
  try {
    const expected = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/engine-skill-inventory.json'), 'utf8'));
    const registryFile = path.join(root, '.engine/registry.json');
    const registry = JSON.parse(fs.readFileSync(registryFile, 'utf8'));
    const roleMap = JSON.parse(fs.readFileSync(path.join(root, '.roles/ROLE_SKILL_MAP.json'), 'utf8'));
    equal(Object.keys(expected).sort(), ['BABYLONJS', 'GODOT', 'PHASERJS', 'THREEJS', 'UNITY', 'UNREAL']);
    equal(expected.UNITY.length, 19);
    const additions = ['unity-build-2d-content', 'unity-localize-content', 'unity-configure-rendering', 'unity-build-editor-tools', 'unity-optimize-web', 'unity-integrate-live-services', 'unity-integrate-multiplayer-services', 'unity-integrate-voice-chat', 'unity-integrate-purchases', 'unity-integrate-ads'];
    equal(expected.UNITY.slice(9), additions);
    for (const [id, names] of Object.entries(expected)) equal([...registry.engines[id].skills].sort(), [...names].sort());
    const unityRoles = Object.entries(roleMap).filter(([id, role]) => id !== '__shared__' && role.skills.some(name => name.startsWith('unity-')));
    equal(unityRoles.length > 0, true);
    for (const id of Object.keys(expected)) {
      const project = path.join(temporary, id); fs.mkdirSync(project); engine.generate(project, id);
      for (const name of expected.UNITY) {
        const selected = engine.skill(project, name);
        equal(selected.compatible, id === 'UNITY');
        if (id !== 'UNITY') equal(/UNITY/.test(selected.exclusionReason), true);
      }
      for (const [role, mapping] of unityRoles) {
        const capabilities = engine.roleCapabilities(project, role);
        const owned = mapping.skills.filter(name => name.startsWith('unity-'));
        equal(capabilities.skills.filter(name => name.startsWith('unity-')).sort(), id === 'UNITY' ? [...owned].sort() : []);
        if (id !== 'UNITY') for (const name of owned) equal(capabilities.excludedSkills.some(item => item.skill === name && /UNITY/.test(item.reason)), true);
      }
    }
    const unity = path.join(temporary, 'UNITY');
    equal(engine.roleCapabilities(unity, 'computer-science/gameplay-engineer').skills.filter(name => name.startsWith('unity-')).sort(), [...expected.UNITY].sort());
    for (const role of ['computer-science/backend-architect', 'computer-science/security-engineer']) {
      const available = engine.roleCapabilities(unity, role).skills;
      for (const name of additions.slice(5)) equal(available.includes(name), true);
    }
    equal(engine.roleCapabilities(unity, 'computer-science/qa-engineer').skills.includes('unity-run-tooling'), true);

    // Change read results only. Never mutate the shared registry or skill sources.
    const originalRead = fs.readFileSync;
    for (const mutate of [
      value => value.engines.UNITY.skills.push(value.engines.UNITY.skills[0]),
      value => { value.engines.UNITY.skills = []; },
      value => value.engines.UNITY.skills.pop(),
      value => value.engines.UNITY.skills.push(value.engines.UNREAL.skills[0])
    ]) {
      const changed = structuredClone(registry); mutate(changed);
      try {
        fs.readFileSync = function(file, ...args) { return path.resolve(String(file)) === registryFile ? JSON.stringify(changed) : originalRead.call(fs, file, ...args); };
        rejects(() => engine.validateCatalog(), /duplicate|unique|empty|registered|mismatch|nonempty|engine|inventory|binding/i);
      } finally { fs.readFileSync = originalRead; }
    }

    const topics = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/unity-topic-coverage.json'), 'utf8'));
    equal(topics.length, 34);
    equal(topics.map(topic => topic.id), Array.from({ length: 34 }, (_, index) => 'CA-' + String(index + 80).padStart(3, '0')));
    equal(topics.filter(topic => topic.disposition !== 'defer').length, 33);
    equal(topics.filter(topic => topic.disposition === 'defer').map(topic => [topic.id, topic.owner]), [['CA-081', null]]);
    const ledger = fs.readFileSync(path.join(root, 'skills/EXTERNAL_SOURCES.md'), 'utf8');
    for (const topic of topics) {
      equal(['create', 'enhance', 'defer'].includes(topic.disposition), true);
      if (topic.owner) {
        equal(expected.UNITY.includes(topic.owner), true);
        equal(ledger.includes(`| ${topic.id} | ${topic.disposition} | ${topic.topic} | \`${topic.owner}\` |`), true);
      } else equal(ledger.includes(`| ${topic.id} | defer | ${topic.topic} | Deferred pending an industrial asset requirement and licensed entitlement |`), true);
    }
    equal(new Set(topics.filter(topic => topic.owner).map(topic => topic.owner)).size, 16);

    const meta = features.manifest();
    equal(meta.cases.length, 16);
    equal(meta.cases.filter(test => test.execution !== 'manual').length, 15);
    equal(meta.manual.filter(test => test.kind === 'online').map(test => test.id).sort(), ['Ads', 'LiveServices', 'MultiplayerServices', 'Purchases', 'VoiceChat']);
    equal(meta.cases.find(test => test.id === 'PackageInventory').execution, 'manual');
    equal(meta.cases.find(test => test.id === 'LocalizationLifecycle').playMode, true);
    equal(meta.cases.find(test => test.id === 'WebBuild').buildTarget, 'WebGL');
    equal(meta.cases.find(test => test.id === 'UIFontCoverage').minimumChecks, 2);
    equal(meta.files.includes('Assets/HephaeraUnityPresentationProbe.cs'), true);
    for (const file of meta.files) equal(fs.existsSync(native.safeLocalFile(path.join(features.DIRECTORY, file), features.DIRECTORY)), true);
    const source = ['Content', 'Presentation', 'ToolingService'].map(name => fs.readFileSync(path.join(features.DIRECTORY, 'Assets/Editor', name + 'FeatureCases.cs'), 'utf8')).join('\n');
    for (const test of meta.cases) {
      equal(source.includes(`IEnumerator ${test.id}(HephaeraUnityFeatureContext context)`), true);
      equal(typeof test.limit === 'string' && test.limit.length > 0, true);
      equal(typeof test.graphics, 'boolean'); equal(typeof test.playMode, 'boolean');
    }
    for (const procedure of meta.manual) equal(fs.existsSync(native.safeLocalFile(path.join(features.DIRECTORY, procedure.document), features.DIRECTORY)), true);

    const configurationFile = path.join(temporary, 'configuration.json');
    const config = { schemaVersion: 1, settings: { localizedText: 'Line one\nLine two\t日本語' }, packages: { 'com.unity.localization': '1.5.13' } };
    fs.writeFileSync(configurationFile, '\uFEFF' + JSON.stringify(config)); equal(features.configuration(configurationFile), config);
    for (const change of [
      value => { value.schemaVersion = 2; }, value => { value.settings = []; }, value => { value.packages = []; },
      value => { value.settings = 'text'; }, value => { value.packages = 'text'; }, value => { value.settings = null; },
      value => { value.unknown = true; }, value => { value.settings = { '9invalid': 'value' }; },
      value => { value.settings = { empty: ' ' }; }, value => { value.settings = { control: '\u0000' }; },
      value => { value.packages = { 'com.unity.localization': 'latest' }; },
      value => { value.packages = { 'com.unity.localization': '1.5.*' }; },
      value => { value.packages = { 'com.unity.localization': 'file:../sdk' }; },
      value => { value.packages = { 'not-a-package': '1.0.0' }; }
    ]) {
      const changed = structuredClone(config); change(changed); json(configurationFile, changed);
      rejects(() => features.configuration(configurationFile), /Invalid|exact/);
    }

    const builtin = features.packageInventory(features.DIRECTORY, native.safeLocalFile);
    equal(builtin.blocked, null); equal(builtin.copies, []);
    equal(/^[a-f0-9]{64}$/.test(builtin.manifestSha256) && /^[a-f0-9]{64}$/.test(builtin.lockSha256), true);
    const id = 'com.unity.synthetic'; const version = '1.2.3';
    const dependency = { [id]: version }; const lock = { [id]: { version, source: 'registry', depth: 0, dependencies: {} } };
    const cache = [[id + '@' + version, { name: id, version }]];
    const prepared = inventoryFixture('prepared', dependency, lock, cache);
    const inventory = features.packageInventory(prepared, native.safeLocalFile);
    equal(inventory.blocked, null); equal(inventory.copies.length, 1);
    equal(inventory.copies[0].name, id + '@' + version);
    const absent = inventoryFixture('absent-cache', dependency, lock);
    equal(/cache is missing/.test(features.packageInventory(absent, native.safeLocalFile).blocked), true);
    const mismatched = inventoryFixture('mismatched-lock', dependency, { [id]: { ...lock[id], version: '2.0.0' } });
    rejects(() => features.packageInventory(mismatched, native.safeLocalFile), /mismatch/);
    const unsupported = inventoryFixture('unsupported-source', dependency, { [id]: { ...lock[id], source: 'git' } });
    equal(/unsupported source/.test(features.packageInventory(unsupported, native.safeLocalFile).blocked), true);
    const floating = inventoryFixture('floating-version', { [id]: 'latest' }, lock);
    rejects(() => features.packageInventory(floating, native.safeLocalFile), /mismatch|unsupported/);
    const duplicate = inventoryFixture('duplicate-cache', dependency, lock, [...cache, ['second-directory', { name: id, version }]]);
    rejects(() => features.packageInventory(duplicate, native.safeLocalFile), /Ambiguous/);
    const missingLock = inventoryFixture('missing-lock', dependency, lock); fs.unlinkSync(path.join(missingLock, 'Packages/packages-lock.json'));
    rejects(() => features.packageInventory(missingLock, native.safeLocalFile), /ENOENT/);
    const indirect = 'com.unity.synthetic-indirect';
    const transitive = inventoryFixture('transitive-cache', dependency, { ...lock, [indirect]: { version: '2.0.0', source: 'registry', depth: 1, dependencies: {} } }, [...cache, [indirect + '@2.0.0', { name: indirect, version: '2.0.0' }]]);
    equal(features.packageInventory(transitive, native.safeLocalFile).copies.length, 2);

    const nativeCase = { packages: [[id]], settings: { nativeAsset: 'asset' } };
    const selected = { packages: dependency, settings: { nativeAsset: 'Assets/Synthetic 日本.asset' } };
    equal(/selection is missing/.test(features.prerequisites(nativeCase, { ...selected, packages: {} }, inventory, prepared, native.safeLocalFile).blocked), true);
    equal(/does not match/.test(features.prerequisites(nativeCase, { ...selected, packages: { [id]: '9.0.0' } }, inventory, prepared, native.safeLocalFile).blocked), true);
    equal(/setting is missing/.test(features.prerequisites(nativeCase, { ...selected, settings: {} }, inventory, prepared, native.safeLocalFile).blocked), true);
    equal(/input is missing/.test(features.prerequisites(nativeCase, selected, inventory, prepared, native.safeLocalFile).blocked), true);
    fs.mkdirSync(path.join(prepared, 'Assets')); fs.writeFileSync(path.join(prepared, selected.settings.nativeAsset), 'SIMULATION ONLY: never launch as a native asset');
    const identities = features.prerequisites(nativeCase, selected, inventory, prepared, native.safeLocalFile).identities;
    equal(identities.length, 2); equal(identities[0], { package: id, version }); equal(identities[1].sha256.length, 64);
    for (const invalid of ['../outside.asset', 'Assets/../outside.asset', 'Assets/./file.asset', 'Assets//file.asset', 'Assets\\file.asset']) {
      rejects(() => features.prerequisites(nativeCase, { ...selected, settings: { nativeAsset: invalid } }, inventory, prepared, native.safeLocalFile), /owned Assets/);
    }
    equal(/UPM|Package Manager/.test(features.prerequisites(meta.cases.find(test => test.id === 'PackageInventory'), {}, builtin, prepared, native.safeLocalFile).blocked), true);
    equal(features.prerequisites({ packages: [], settings: {} }, { packages: {}, settings: {} }, { blocked: 'unavailable cache' }, prepared, native.safeLocalFile).blocked, 'unavailable cache');

    // Bind implementation and metadata bytes, not package names/version strings alone.
    const implementation = path.join(prepared, 'Library/PackageCache', id + '@' + version, 'Runtime.cs');
    const assetMeta = path.join(prepared, selected.settings.nativeAsset + '.meta');
    fs.writeFileSync(implementation, '// SIMULATION package implementation A'); fs.writeFileSync(assetMeta, 'SIMULATION metadata A');
    const before = features.inputReceipt(prepared); equal(features.inputReceipt(prepared), before);
    fs.writeFileSync(implementation, '// SIMULATION package implementation B');
    const changedImplementation = features.inputReceipt(prepared);
    equal(JSON.stringify(changedImplementation) === JSON.stringify(before), false);
    equal(new Map(changedImplementation).get('Library/PackageCache/' + id + '@' + version + '/package.json'), new Map(before).get('Library/PackageCache/' + id + '@' + version + '/package.json'));
    fs.writeFileSync(assetMeta, 'SIMULATION metadata B');
    const changedMeta = features.inputReceipt(prepared);
    equal(new Map(changedMeta).get(selected.settings.nativeAsset + '.meta') === new Map(changedImplementation).get(selected.settings.nativeAsset + '.meta'), false);
    equal(new Map(changedMeta).get(selected.settings.nativeAsset), new Map(before).get(selected.settings.nativeAsset));
    const link = path.join(prepared, 'Assets/linked');
    try {
      fs.symlinkSync(path.join(temporary, 'UNITY'), link, process.platform === 'win32' ? 'junction' : 'dir');
      rejects(() => features.inputReceipt(prepared), /links/);
      rejects(() => native.safeLocalFile(path.join(link, 'ENGINE.md'), prepared), /links/);
      fs.unlinkSync(link);
    } catch (error) {
      if (!['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) throw error;
      console.log('NOT-RUN synthetic link rejection: this host cannot create the controlled link');
    }

    const test = meta.cases.find(item => item.id === 'Physics3D');
    const reportFile = path.join(temporary, 'synthetic-report.json');
    const runId = crypto.randomUUID(); const inputSha256 = 'a'.repeat(64); const engineVersion = '6000.3.0f1';
    const good = { schemaVersion: 1, fixture: 'hephaera-unity-feature', caseName: test.id, runId, inputSha256, engineVersion, status: 'pass', checks: test.minimumChecks, observations: Array.from({ length: test.minimumChecks }, (_, index) => 'CHECK SIMULATION ' + index), reason: 'SIMULATION ONLY', startedUtc: new Date().toISOString(), fixturePlayMode: false, fixtureDomainReloadDisabled: false };
    const inspect = () => features.inspectReport(reportFile, test, runId, inputSha256, Date.now(), engineVersion);
    json(reportFile, good); equal(inspect().status, 'pass'); equal(inspect().reportSha256.length, 64);
    for (const change of [
      value => { value.schemaVersion = 2; }, value => { value.fixture = 'other'; }, value => { value.caseName = 'Physics2D'; },
      value => { value.runId = crypto.randomUUID(); }, value => { value.inputSha256 = 'b'.repeat(64); }, value => { value.engineVersion = 'other'; },
      value => { value.status = 'not-run'; }, value => { value.reason = ''; }, value => { value.checks = 0; value.observations = []; },
      value => { value.checks = 1.5; }, value => { value.observations = []; }, value => { value.fixturePlayMode = true; },
      value => { value.startedUtc = new Date(Date.now() - 60000).toISOString(); }, value => { value.startedUtc = new Date(Date.now() + 60000).toISOString(); },
      value => { value.startedUtc = 'invalid'; }
    ]) {
      const changed = structuredClone(good); change(changed); json(reportFile, changed);
      rejects(inspect, /identity|Incomplete|Empty|mode|Stale/);
    }
    json(reportFile, good);
    const old = new Date(Date.now() - 60000); fs.utimesSync(reportFile, old, old); rejects(inspect, /Stale/);
    const future = new Date(Date.now() + 60000); fs.utimesSync(reportFile, future, future); rejects(inspect, /Stale/);
    fs.writeFileSync(reportFile, '{corrupt'); rejects(inspect, /JSON|property|Unexpected/);
    rejects(() => features.inspectReport(path.join(temporary, 'absent-report.json'), test, runId, inputSha256, Date.now(), engineVersion), /Missing/);
    const playCase = meta.cases.find(item => item.id === 'AudioLifecycle');
    json(reportFile, { ...good, caseName: playCase.id, checks: playCase.minimumChecks, observations: Array.from({ length: playCase.minimumChecks }, (_, index) => 'CHECK SIMULATION ' + index), fixturePlayMode: true });
    rejects(() => features.inspectReport(reportFile, playCase, runId, inputSha256, Date.now(), engineVersion), /mode/);
    for (const status of ['blocked', 'fail']) { json(reportFile, { ...good, status, checks: 0, observations: [] }); equal(inspect().status, status); }
    equal(features.unavailable('No valid Unity Editor license is available'), 'Matching installed Editor license is unavailable');
    equal(features.unavailable('WebGL support module is not installed'), 'Required installed platform module/SDK is unavailable');
    equal(features.unavailable('error CS0117: invalid fixture API'), null);

    // Simulated processes cannot gain native status from a report beside failure.
    const previous = { config: process.env.HEPHAERA_UNITY_FEATURE_CONFIG, version: process.env.HEPHAERA_UNITY_VERSION };
    try {
      delete process.env.HEPHAERA_UNITY_FEATURE_CONFIG;
      const api = { safeLocalFile: native.safeLocalFile, executable: () => process.execPath, copyFixture: native.copyFixture, nativeFailure: native.nativeFailure };
      const disabled = await features.run({ run: () => { throw new Error('Unexpected launch'); } }, api);
      equal(disabled.length, 26); equal(disabled.every(result => result.status !== 'pass'), true);
      process.env.HEPHAERA_UNITY_FEATURE_CONFIG = path.join(features.DIRECTORY, 'fixture-config.example.json');
      process.env.HEPHAERA_UNITY_VERSION = engineVersion;
      for (const result of [{ code: 7, text: '' }, { code: 0, timedOut: true, text: '' }, { code: 0, cancelled: true, text: '' }, { code: null, spawnError: 'SIMULATION unavailable executable', text: '' }]) {
        const simulationDirectory = fs.mkdtempSync(path.join(temporary, 'process-'));
        let launches = 0;
        const results = await features.run({ temp: simulationDirectory, run: async (command, args, options) => {
          launches++; equal(args.includes('-noUpm'), true);
          const selectedCase = meta.cases.find(item => item.id === options.env.HEPHAERA_UNITY_FEATURE_CASE);
          json(options.env.HEPHAERA_UNITY_FEATURE_REPORT, { ...good, caseName: selectedCase.id, runId: options.env.HEPHAERA_UNITY_FEATURE_RUN, inputSha256: options.env.HEPHAERA_UNITY_FEATURE_INPUT_SHA256, startedUtc: new Date().toISOString(), fixturePlayMode: selectedCase.playMode, fixtureDomainReloadDisabled: selectedCase.playMode });
          return result;
        } }, api);
        equal(launches > 0, true); equal(results.filter(item => item.status === 'fail').length, launches); equal(results.some(item => item.status === 'pass'), false);
      }
    } finally {
      if (previous.config === undefined) delete process.env.HEPHAERA_UNITY_FEATURE_CONFIG; else process.env.HEPHAERA_UNITY_FEATURE_CONFIG = previous.config;
      if (previous.version === undefined) delete process.env.HEPHAERA_UNITY_VERSION; else process.env.HEPHAERA_UNITY_VERSION = previous.version;
    }
    console.log(`Unity capability checks passed (${checks} assertions; structural contracts and SIMULATION report/process checks do not establish native acceptance).`);
  } finally {
    if (path.dirname(temporary) !== __dirname || !path.basename(temporary).startsWith('.unity-capabilities-') || fs.lstatSync(temporary).isSymbolicLink()) throw new Error('Unsafe test cleanup');
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
