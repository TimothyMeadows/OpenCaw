'use strict';
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const engine = require('../commands/lib/engine-contract.cjs');
const base = engine.BASE;
const runtime = fs.mkdtempSync(path.join(base, 'tests/.engine-runtime-'));
let checks = 0;
function project(name) { const p = path.join(runtime, name); fs.mkdirSync(p); return p; }
function write(root, file, text) { const p = path.join(root, file); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, text); }
function rejects(action, pattern) { assert.throws(action, pattern); checks++; }
function equal(actual, expected) { assert.deepEqual(actual, expected); checks++; }
function cli(root, op, args = []) { return cp.spawnSync(process.execPath, [path.join(base, 'commands/lib/engine-contract.cjs'), op, root, ...args], { encoding: 'utf8' }); }
try {
  const root = project('default');
  equal(engine.resolve(root).effectiveEngine, 'THREEJS');
  equal(fs.existsSync(path.join(root, 'ENGINE.md')), false);
  // Installed definitions and historical/cache fixtures are not project engine
  // evidence. Their native project files must not override the host selection.
  write(root, '.hephaera/.cache/tasks/history/game/project.godot', '[application]');
  write(root, '.hephaera/fixtures/ProjectSettings/ProjectVersion.txt', 'fixture');
  equal(engine.resolve(root).existingEngines, []);
  // Historical hidden-install caches are durable tooling state, never game
  // evidence. Do not descend into their deep model/package environments.
  write(root, '.previous-tool/.cache/' + 'history/'.repeat(14) + 'project.godot', '[application]');
  equal(engine.resolve(root).existingEngines, []);
  rejects(() => engine.engineId('nonsense'), /Unknown/);
  const definitions = JSON.parse(fs.readFileSync(path.join(base, '.engine/registry.json'))).engines;
  for (const [id, def] of Object.entries(definitions)) {
    const p = project(id);
    for (const alias of [id, ...def.aliases]) equal(engine.engineId(alias), id);
    engine.generate(p, def.aliases[0]);
    equal(engine.resolve(p).effectiveEngine, id);
    equal(fs.readFileSync(path.join(p, 'ENGINE.md'), 'utf8').includes('### Inline Engine Definition'), false);
    fs.appendFileSync(path.join(p, 'ENGINE.md'), '\nCustom project content stays.\n');
    engine.generate(p, id, { inline: true });
    equal(engine.resolve(p).effectiveEngine, id);
    equal(fs.readFileSync(path.join(p, 'ENGINE.md'), 'utf8').includes('Custom project content stays.'), true);
    equal(fs.readFileSync(path.join(p, 'ENGINE.md'), 'utf8').includes('### Inline Engine Definition'), true);
    engine.generate(p, id);
    const content = fs.readFileSync(path.join(p, 'ENGINE.md'), 'utf8');
    write(p, 'ENGINE.md', content.replaceAll('\n', '\r\n'));
    equal(engine.resolve(p).effectiveEngine, id);
    for (const name of def.skills) equal(engine.skill(p, name).compatible, true);
  }
  const unity = path.join(runtime, 'UNITY');
  equal(engine.skill(unity, 'build-game-ui').compatible, true);
  equal(engine.skill(unity, 'test-playable-games').compatible, true);
  equal(engine.skill(unity, 'threejs-build-scenes').compatible, false);
  equal(cli(unity, 'skill', ['threejs-build-scenes']).status, 1);
  const wrong = engine.skill(unity, 'build-threejs-code-models');
  equal(wrong.skill, 'threejs-build-code-models');
  equal(wrong.alias, true);
  equal(wrong.compatible, false);
  rejects(() => engine.requireEngine(unity, 'THREEJS'), /requires THREEJS/);
  write(unity, 'alternate.md', fs.readFileSync(path.join(runtime, 'THREEJS/ENGINE.md'), 'utf8'));
  rejects(() => engine.skill(unity, 'threejs-build-scenes', { contract: 'alternate.md' }), /authoritative/);
  equal(cli(unity, 'resolve', ['--contract', 'alternate.md']).status, 1);
  const capabilities = engine.roleCapabilities(unity, 'computer-science/gameplay-engineer', {});
  equal(capabilities.skills.includes('unity-build-scenes'), true);
  equal(capabilities.skills.includes('threejs-build-scenes'), false);
  equal(capabilities.excludedSkills.some(s => s.skill === 'threejs-build-scenes' && /THREEJS/.test(s.reason)), true);
  equal(capabilities.excludedCommands.some(s => /create-code-character-profile/.test(s.command)), true);
  rejects(() => engine.roleCapabilities(unity, 'unknown-role', {}), /qualified/);

  const invalid = project('invalid');
  write(invalid, 'ENGINE.md', '# Custom contract\n');
  rejects(() => engine.resolve(invalid), /exactly one/);
  rejects(() => engine.generate(invalid, 'UNITY'), /custom content was preserved/);
  write(invalid, 'ENGINE.md', 'Selected Hephaera engine:\n- UNKNOWN\n');
  rejects(() => engine.resolve(invalid), /canonical/);
  write(invalid, 'ENGINE.md', 'Selected Hephaera engine:\n- UNITY\n- GODOT\n');
  rejects(() => engine.resolve(invalid), /one canonical/);
  write(invalid, 'ENGINE.md', 'Selected Hephaera engine:\n- UNITY\n\nRead `./.engine/UNITY.md` instructions\nSelected Hephaera engine:\n- UNITY\n');
  rejects(() => engine.resolve(invalid), /exactly one/);
  write(invalid, 'ENGINE.md', 'Selected Hephaera engine:\n- UNITY\n\nRead `./.engine/GODOT.md` instructions\n');
  rejects(() => engine.resolve(invalid), /conflicting/);
  write(invalid, 'ENGINE.md', 'Selected Hephaera engine:\n- UNITY\n\n### Inline Engine Definition\n\n# GODOT\n\n<!-- hephaera-engine:end -->');
  rejects(() => engine.resolve(invalid), /matching/);
  const validLinked = fs.readFileSync(path.join(runtime, 'THREEJS/ENGINE.md'), 'utf8');
  write(invalid, 'ENGINE.md', validLinked + '\n### Inline Engine Definition\n\n# GODOT\n');
  rejects(() => engine.resolve(invalid), /both/);
  write(invalid, 'ENGINE.md', validLinked.replace(/Read `[^`]+` instructions/, 'Read `./missing/.engine/THREEJS.md` instructions'));
  rejects(() => engine.resolve(invalid), /registered shared definition/);

  const conflicting = project('conflicting');
  write(conflicting, 'ProjectSettings/ProjectVersion.txt', 'm_EditorVersion: test\n');
  rejects(() => engine.resolve(conflicting), /conflicts/);
  const nested = project('nested');
  write(nested, 'game/client/ProjectSettings/ProjectVersion.txt', 'm_EditorVersion: test');
  rejects(() => engine.resolve(nested), /conflicts/);
  engine.generate(nested, 'UNITY'); equal(engine.resolve(nested).effectiveEngine, 'UNITY');
  engine.generate(conflicting, 'UNITY');
  equal(engine.resolve(conflicting).existingEngines, ['UNITY']);
  rejects(() => engine.generate(conflicting, 'THREEJS'), /conflicts/);
  write(conflicting, 'package.json', '{"dependencies":{"three":"locked"}}');
  rejects(() => engine.resolve(conflicting), /conflicts/);
  for (const [id, evidence] of [['GODOT', 'project.godot'], ['UNREAL', 'Game.uproject']]) {
    const p = project('evidence-' + id); write(p, evidence, '{}');
    rejects(() => engine.resolve(p), /conflicts/); engine.generate(p, id);
    equal(engine.resolve(p).effectiveEngine, id);
  }
  for (const [id, dep] of [['THREEJS', 'three'], ['BABYLONJS', '@babylonjs/core'], ['PHASERJS', 'phaser']]) {
    const p = project('package-' + id); write(p, 'package.json', JSON.stringify({ dependencies: { [dep]: 'locked' } }));
    engine.generate(p, id); equal(engine.resolve(p).existingEngines, [id]);
  }
  const legacy = project('legacy');
  write(legacy, 'ARCHITECTURE.md', 'Read `./.hephaera/.architecture/BABYLONJS.md` instructions\n');
  rejects(() => engine.resolve(legacy), /legacy architecture/);
  engine.generate(legacy, 'BABYLONJS');
  equal(engine.resolve(legacy).effectiveEngine, 'BABYLONJS');
  write(legacy, 'ARCHITECTURE.md', '<!-- BEGIN TEMPLATE: BABYLONJS -->\nLegacy compatibility redirect\n<!-- END TEMPLATE: BABYLONJS -->');
  equal(engine.resolve(legacy).existingEngines, ['BABYLONJS']);
  rejects(() => engine.generate(root, ''), /Unknown/);
  for (const id of ['THREEJS', 'BABYLONJS', 'PHASERJS']) equal(fs.readFileSync(path.join(base, '.architecture', id + '.md'), 'utf8').includes('compatibility redirect'), true);

  const override = project('override');
  engine.generate(override, 'THREEJS');
  write(override, '.hephaera/.cache/tasks/demo/TASK.md', 'Authorized isolated Unity prototype.');
  const before = fs.readFileSync(path.join(override, 'ENGINE.md'), 'utf8');
  rejects(() => engine.resolve(override, { override: 'UNITY' }), /requires/);
  rejects(() => engine.resolve(override, { override: 'UNITY', recordOverride: true, task: 'demo', scope: 'src/game' }), /isolated/);
  rejects(() => engine.resolve(override, { override: 'UNITY', recordOverride: true, task: 'demo', scope: '../escape' }), /inside/);
  rejects(() => engine.resolve(override, { override: 'UNITY', recordOverride: true, task: 'missing', scope: 'prototypes/demo' }), /existing task/);
  write(override, 'prototypes/occupied/existing.txt', 'Existing game content');
  rejects(() => engine.resolve(override, { override: 'UNITY', recordOverride: true, task: 'demo', scope: 'prototypes/occupied' }), /empty/);
  const receipt = engine.resolve(override, { override: 'UNITY', recordOverride: true, task: 'demo', scope: 'prototypes/unity-demo' });
  equal(receipt.evidence, '.hephaera/.cache/tasks/demo/engine-override.json');
  const opt = { evidence: receipt.evidence, output: 'prototypes/unity-demo/Assets/Actor.cs' };
  equal(engine.skill(override, 'unity-build-scenes', opt).compatible, true);
  equal(fs.readFileSync(path.join(override, 'ENGINE.md'), 'utf8'), before);
  rejects(() => engine.resolve(override, { ...opt, output: 'src/game/Actor.cs' }), /outside/);
  rejects(() => engine.resolve(override, { ...opt, output: '../escape' }), /inside/);
  rejects(() => engine.resolve(override, { ...opt, task: 'other' }), /another task/);
  rejects(() => engine.resolve(override, { ...opt, override: 'GODOT' }), /differs/);
  const receiptFile = path.join(override, receipt.evidence); const originalReceipt = fs.readFileSync(receiptFile, 'utf8');
  write(override, receipt.evidence, originalReceipt.replace('prototypes/unity-demo', 'prototypes/other'));
  rejects(() => engine.resolve(override, opt), /changed/);
  write(override, receipt.evidence, originalReceipt);
  write(override, 'prototypes/unity-demo/project.godot', '[application]');
  rejects(() => engine.resolve(override, opt), /prototype engine evidence/);
  fs.unlinkSync(path.join(override, 'prototypes/unity-demo/project.godot'));
  write(override, '.hephaera/.cache/tasks/demo/TASK.md', 'Changed task instructions');
  rejects(() => engine.resolve(override, opt), /Stale/);
  write(override, '.hephaera/.cache/tasks/demo/TASK.md', 'Authorized isolated Unity prototype.');
  fs.appendFileSync(path.join(override, 'ENGINE.md'), '\nChanged contract.');
  rejects(() => engine.resolve(override, opt), /Stale/);
  write(override, 'ENGINE.md', before);
  const cachedPrototype = project('cached-prototype');
  write(cachedPrototype, '.hephaera/.cache/tasks/demo/TASK.md', 'Authorized cached Unity prototype.');
  const cachedReceipt = engine.resolve(cachedPrototype, { override: 'UNITY', recordOverride: true, task: 'demo', scope: '.hephaera/.cache/tasks/demo/prototypes/unity' });
  equal(engine.skill(cachedPrototype, 'unity-build-scenes', { evidence: cachedReceipt.evidence, output: '.hephaera/.cache/tasks/demo/prototypes/unity/Assets/Actor.cs' }).compatible, true);
  rejects(() => engine.resolve(cachedPrototype, { output: '.hephaera/.cache/tasks/demo/prototypes/unity/Assets/Actor.cs' }), /recorded/);
  rejects(() => engine.resolve(cachedPrototype, { evidence: cachedReceipt.evidence, output: '.hephaera/.cache/tasks/demo/prototypes/other/Actor.cs' }), /outside/);
  // Fresh-install semantics do not discover tasks or accept receipts in the
  // retired memory directory, even when their contents are otherwise valid.
  const retired = project('retired-cache');
  write(retired, '.ai/tasks/demo/TASK.md', 'Retired task location.');
  rejects(() => engine.resolve(retired, { override: 'UNITY', recordOverride: true, task: 'demo', scope: 'prototypes/unity' }), /existing task/);
  write(override, '.ai/tasks/demo/engine-override.json', originalReceipt);
  write(override, '.ai/tasks/demo/engine-override.json.sha256', require('crypto').createHash('sha256').update(originalReceipt).digest('hex') + '\n');
  rejects(() => engine.resolve(override, { evidence: '.ai/tasks/demo/engine-override.json', output: 'prototypes/unity-demo/Assets/Actor.cs' }), /belong/);
  try {
    fs.symlinkSync(path.join(runtime, 'missing-target'), path.join(override, 'prototypes/dangling'), 'junction');
    rejects(() => engine.inside(override, 'prototypes/dangling/Asset.cs'), /symbolic/);
  } catch (e) { if (!['EPERM', 'EACCES', 'ENOTSUP'].includes(e.code)) throw e; console.log('SKIP: symlink fixture unavailable: ' + e.code); }

  // Wrong-engine producers are invoked directly, catching wrapper bypasses before argument validation/writes.
  for (const [file, operation] of [['code-model-cli.cjs', 'create'], ['code-character-cli.cjs', 'create'], ['code-character-evidence-cli.cjs', 'capture'], ['code-character-evidence-cli.cjs', 'analyze']]) {
    const p = cp.spawnSync(process.execPath, [path.join(base, 'commands/lib', file), operation, unity, 'blocked'], { encoding: 'utf8' });
    equal(p.status, 1); equal(p.stderr.includes('requires THREEJS'), true);
    equal(fs.existsSync(path.join(unity, '.hephaera/.cache')), false);
  }
  const validPrototype = project('valid-code-prototype');
  engine.generate(validPrototype, 'UNITY'); write(validPrototype, '.hephaera/.cache/tasks/demo/TASK.md', 'Three.js prototype allowed.');
  const codeReceipt = engine.resolve(validPrototype, { override: 'THREEJS', task: 'demo', scope: 'prototypes/three-demo', recordOverride: true });
  equal(engine.codeProduction(validPrototype, 'model', 'create', ['demo', '--source', 'prototypes/three-demo/model.ts', '--engine-evidence', codeReceipt.evidence])[0], 'demo');
  rejects(() => engine.codeProduction(validPrototype, 'model', 'create', ['demo', '--source', 'src/game/model.ts', '--engine-evidence', codeReceipt.evidence]), /outside/);
  rejects(() => engine.codeProduction(validPrototype, 'model', 'create', ['demo', '--source', 'prototypes/three-demo/model.ts', '--output', '.hephaera/.cache/tasks/other/model.json', '--engine-evidence', codeReceipt.evidence]), /recorded task/);
  rejects(() => engine.codeProduction(validPrototype, 'model', 'create', ['demo', '--source', 'prototypes/three-demo/model.ts', '--evidence', 'front=.ai/tasks/demo/front.png', '--engine-evidence', codeReceipt.evidence]), /recorded task/);
  const ordinary = project('ordinary-producer');
  write(ordinary, 'prototypes/unity-game/ProjectSettings/ProjectVersion.txt', 'Unity fixture');
  rejects(() => engine.resolve(ordinary, { output: 'prototypes/unity-game/Assets/Actor.ts' }), /recorded/);
  rejects(() => engine.codeProduction(ordinary, 'model', 'create', ['demo', '--source', 'prototypes/unity-game/Assets/Actor.ts']), /recorded/);
  write(ordinary, 'tests/game/project.godot', '[application]');
  rejects(() => engine.resolve(ordinary, { output: 'tests/game/Actor.ts' }), /incompatible/);
  write(ordinary, '.hephaera/.cache/tasks/demo/model.json', JSON.stringify({ target: { sourcePath: 'prototypes/unity-game/Assets/Actor.ts' } }));
  rejects(() => engine.codeProduction(ordinary, 'character', 'create', ['--manifest', '.hephaera/.cache/tasks/demo/model.json', 'demo']), /recorded/);
  // Classification mutants are actual isolated skill files, never existing skills.
  const name = 'engine-validation-fixture'; const folder = path.join(base, 'skills', name);
  assert(!fs.existsSync(folder)); fs.mkdirSync(folder);
  try {
    for (const text of ['', 'engines: []', 'engines: [UNKNOWN]', 'engines: [AGNOSTIC, UNITY]', 'engines: [AGNOSTIC]\nengines: [UNITY]', 'engines: [AGNOSTIC]\n"engines": [UNITY]', 'engines: [UNITY]']) {
      fs.writeFileSync(path.join(folder, 'SKILL.md'), `---\nname: ${name}\n${text}\n---\n`);
      rejects(() => engine.classify(name), /engines|prefix/);
    }
  } finally { fs.rmSync(folder, { recursive: true }); }
  const expectedInventory = JSON.parse(fs.readFileSync(path.join(base, 'tests/fixtures/engine-skill-inventory.json'), 'utf8'));
  const registeredInventory = JSON.parse(fs.readFileSync(path.join(base, '.engine/registry.json'), 'utf8'));
  for (const [id, names] of Object.entries(expectedInventory)) {
    equal([...registeredInventory.engines[id].skills].sort(), [...names].sort());
  }
  equal(engine.validateCatalog().engineSkills, Object.values(expectedInventory).reduce((total, names) => total + names.length, 0));
  equal(cli(root, 'resolve', ['--unknown']).status, 1);
  equal(cli(root, 'resolve', ['UNITY']).status, 1);
  equal(cli(root, 'resolve').stdout, cli(root, 'resolve').stdout);
  console.log(`Engine selection tests passed (${checks} assertions; no editor or tactile execution claimed).`);
} finally {
  if (runtime.startsWith(path.join(base, 'tests/.engine-runtime-'))) fs.rmSync(runtime, { recursive: true, force: true });
}
