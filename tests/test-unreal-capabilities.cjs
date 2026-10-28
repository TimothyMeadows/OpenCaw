'use strict';
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const engine = require('../commands/lib/engine-contract.cjs');
const native = require('./test-native-engine-fixtures.cjs');
const features = require('./lib/unreal-feature-fixtures.cjs');
const root = engine.BASE;
const temporary = fs.mkdtempSync(path.join(__dirname, '.unreal-capabilities-'));
let checks = 0;
const equal = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const rejects = (action, pattern) => { assert.throws(action, pattern); checks++; };
try {
  const expected = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/engine-skill-inventory.json'), 'utf8'));
  const registryFile = path.join(root, '.engine/registry.json');
  const registry = JSON.parse(fs.readFileSync(registryFile, 'utf8'));
  equal(expected.UNREAL.length, 22);
  for (const [id, names] of Object.entries(expected)) equal([...registry.engines[id].skills].sort(), [...names].sort());
  const additions = expected.UNREAL.slice(10);
  equal(additions.length, 12);
  for (const id of Object.keys(expected)) {
    const project = path.join(temporary, id);
    fs.mkdirSync(project);
    engine.generate(project, id);
    for (const name of expected.UNREAL) {
      const selected = engine.skill(project, name);
      equal(selected.compatible, id === 'UNREAL');
      if (id !== 'UNREAL') equal(/UNREAL/.test(selected.exclusionReason), true);
    }
    const capabilities = engine.roleCapabilities(project, 'computer-science/gameplay-engineer');
    for (const name of additions) equal(capabilities.skills.includes(name), id === 'UNREAL');
    if (id !== 'UNREAL') for (const name of additions) equal(capabilities.excludedSkills.some(s => s.skill === name && /UNREAL/.test(s.reason)), true);
  }
  const project = path.join(temporary, 'UNREAL');
  const roleRequirements = {
    'arts/art-director': ['cameras', 'vfx', 'cinematics', 'worlds', 'procedural-content'],
    'arts/game-vfx-artist': ['vfx', 'cameras', 'cinematics'],
    'arts/technical-3d-artist': ['procedural-content', 'cinematics']
  };
  for (const [role, suffixes] of Object.entries(roleRequirements)) {
    const skills = engine.roleCapabilities(project, role).skills;
    for (const suffix of suffixes) equal(skills.includes('unreal-build-' + suffix), true);
  }
  equal(engine.roleCapabilities(project, 'computer-science/qa-engineer').skills.includes('unreal-run-tooling'), true);

  // Mutate the read result only: live catalog/skills and pre-existing work never change.
  const originalRead = fs.readFileSync;
  for (const mutate of [
    r => r.engines.UNREAL.skills.push(r.engines.UNREAL.skills[0]),
    r => { r.engines.UNREAL.skills = []; },
    r => r.engines.UNREAL.skills.pop(),
    r => r.engines.UNREAL.skills.push(r.engines.UNITY.skills[0])
  ]) {
    const changed = structuredClone(registry); mutate(changed);
    try {
      fs.readFileSync = function(file, ...args) { return path.resolve(String(file)) === registryFile ? JSON.stringify(changed) : originalRead.call(fs, file, ...args); };
      rejects(() => engine.validateCatalog(), /duplicate|unique|empty|registered|mismatch|nonempty|engine|inventory/i);
    } finally { fs.readFileSync = originalRead; }
  }
  const topics = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/unreal-topic-coverage.json'), 'utf8'));
  equal(topics.length, 31); equal(new Set(topics.map(t => t.id)).size, 31);
  const ledger = fs.readFileSync(path.join(root, 'skills/EXTERNAL_SOURCES.md'), 'utf8');
  for (const topic of topics) {
    equal(ledger.includes(`| ${topic.id} | ${topic.disposition} | ${topic.topic} | \`${topic.owner}\` |`), true);
    equal(topic.owner === '.engine/UNREAL.md' || expected.UNREAL.includes(topic.owner), true);
  }
  equal(new Set(topics.filter(t => t.owner !== '.engine/UNREAL.md').map(t => t.owner)).size, 22);
  const meta = features.manifest();
  equal(features.unavailableBuild("Unable to find plugin 'PCG' (referenced via OpenCawFeatureFixture.uproject)"), 'An explicitly selected native fixture plugin/module is unavailable');
  equal(features.unavailableBuild('Visual Studio compiler not found'), 'Native compiler/platform SDK unavailable');
  equal(features.unavailableBuild('PCG error C2039: invalid member in fixture.cpp'), null);
  const source = ['Gameplay', 'Presentation', 'World'].map(name => fs.readFileSync(path.join(features.DIRECTORY, 'Source/OpenCawFeatureFixture/Private', name + 'FeatureTests.cpp'), 'utf8')).join('\n');
  for (const test of meta.cases) {
    equal(source.includes('"' + test.name + '"'), true);
    equal(source.includes('OpenCawFeatureEvidence(*this, TEXT("' + test.name + '"))'), true);
    equal(typeof test.limit, 'string');
  }
  const featureProject = JSON.parse(fs.readFileSync(path.join(features.DIRECTORY, meta.project), 'utf8'));
  equal(featureProject.Modules[0].Type, 'Editor');
  equal(featureProject.EngineAssociation, meta.engineMinor);
  const configFile = path.join(temporary, 'settings.ini');
  fs.writeFileSync(configFile, '[Other]\r\nIgnored=1\r\n[OpenCaw.UnrealFeatures]\r\nStreamingLevel=/Game/Fixture/Stream\r\nStreamingMarkerTag=Marker\r\n');
  const config = features.configuration(configFile);
  equal(config, { StreamingLevel: '/Game/Fixture/Stream', StreamingMarkerTag: 'Marker' });
  fs.appendFileSync(configFile, 'StreamingLevel=second\n');
  rejects(() => features.configuration(configFile), /duplicate/);
  const streaming = meta.cases.find(test => test.name.endsWith('.WorldStreaming'));
  equal(/missing/.test(features.prerequisites(streaming, {}, temporary, native.safeLocalFile).blocked), true);
  rejects(() => features.prerequisites(streaming, { StreamingLevel: '/Game/../Escape', StreamingMarkerTag: 'Marker' }, temporary, native.safeLocalFile), /project-owned/);
  const content = path.join(temporary, 'Content/Fixture'); fs.mkdirSync(content, { recursive: true });
  fs.writeFileSync(path.join(content, 'Stream.umap'), 'SIMULATION ONLY: never launch as an asset');
  const identities = features.prerequisites(streaming, config, temporary, native.safeLocalFile).identities;
  equal(identities.length, 1); equal(identities[0].sha256.length, 64);
  rejects(() => features.prerequisites(streaming, { ...config, StreamingMarkerTag: '../invalid' }, temporary, native.safeLocalFile), /tag/);
  const plugin = meta.cases.find(test => test.name.endsWith('.GameFeatureUnload'));
  rejects(() => features.prerequisites(plugin, { GameFeaturePluginName: '../outside' }, temporary, native.safeLocalFile), /plugin/);
  equal(/missing/.test(features.prerequisites(plugin, { GameFeaturePluginName: 'NativePlugin' }, temporary, native.safeLocalFile).blocked), true);

  const file = path.join(temporary, 'automation.json');
  const nonce = crypto.randomUUID();
  const name = meta.cases[0].name;
  const good = { failed: 0, notRun: 0, tests: [{ fullTestPath: name, state: 'Success', entries: [{ event: { type: 'Info', message: `OpenCawFeatureEvidence run=${nonce} case=${name}` } }] }] };
  const inspect = () => features.inspectEvidence(file, name, nonce, Date.now(), native.inspectUnrealReport);
  fs.writeFileSync(file, JSON.stringify(good)); equal(inspect().runId, nonce);
  for (const change of [
    r => { r.tests = []; },
    r => r.tests.push(structuredClone(r.tests[0])),
    r => { r.tests[0].state = 'NotRun'; },
    r => { r.tests[0].fullTestPath = 'Other'; },
    r => { r.failed = 1; },
    r => { r.notRun = 1; },
    r => { r.tests[0].entries = []; },
    r => { r.tests[0].entries[0].event.message = 'old invocation'; },
    r => r.tests[0].entries.push(structuredClone(r.tests[0].entries[0])),
    r => r.tests[0].entries.push({ event: { type: 'Error', message: 'native assertion failed' } })
  ]) {
    const changed = structuredClone(good); change(changed); fs.writeFileSync(file, JSON.stringify(changed));
    rejects(inspect, /Automation|fixture|marker|report|error/);
  }
  fs.writeFileSync(file, JSON.stringify(good));
  rejects(() => features.inspectEvidence(file, name, crypto.randomUUID(), Date.now(), native.inspectUnrealReport), /marker/);
  const old = new Date(Date.now() - 60000); fs.utimesSync(file, old, old); rejects(inspect, /Stale/);
  const future = new Date(Date.now() + 60000); fs.utimesSync(file, future, future); rejects(inspect, /Stale/);
  equal(fs.existsSync(path.join(root, 'tests/proof-to-3d')), false);
  console.log(`Unreal capability checks passed (${checks} assertions; report/configuration simulations do not establish native acceptance).`);
} finally {
  if (path.dirname(temporary) !== __dirname || !path.basename(temporary).startsWith('.unreal-capabilities-') || fs.lstatSync(temporary).isSymbolicLink()) throw new Error('Unsafe test cleanup');
  fs.rmSync(temporary, { recursive: true, force: true });
}
