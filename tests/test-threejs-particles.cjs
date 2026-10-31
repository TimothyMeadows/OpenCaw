'use strict';

// Metadata/scaffold fixtures only. Actual Quarks lifecycle has its own suite.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const engine = require('../commands/lib/engine-contract.cjs');
const particles = require('../commands/lib/threejs-particles.cjs');
const ROOT = path.resolve(__dirname, '..');
const parent = path.join(ROOT, '.opencaw/.cache/tasks/opencaw-threejs-quarks');
fs.mkdirSync(parent, { recursive: true });
const fixtures = fs.mkdtempSync(path.join(parent, 'cli-fixtures-'));
const cliFile = path.join(ROOT, 'commands/lib/threejs-particles.cjs');
const template = path.join(ROOT, '.engine/threejs/particles');
const pins = { three: '0.182.0', 'three.quarks': '0.17.1', 'quarks.core': '0.17.1' };
let checks = 0, linkSkips = 0;
const equal = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const ok = value => { assert.ok(value); checks++; };
const rejects = (action, pattern = /./) => { assert.throws(action, pattern); checks++; };
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function write(root, relative, value) {
  const file = path.join(root, relative); fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof value === 'string' || Buffer.isBuffer(value) ? value : JSON.stringify(value, null, 2) + '\n');
}
function host(name, selected = 'THREEJS') {
  const root = path.join(fixtures, name); fs.mkdirSync(root); engine.generate(root, selected); return root;
}
function dependencies(root) {
  const deps = { ...pins };
  write(root, 'package.json', { private: true, dependencies: deps });
  const packages = { '': { dependencies: { ...deps } } };
  for (const [name, version] of Object.entries(pins)) {
    packages[`node_modules/${name}`] = { version, integrity: 'sha512-Zml4dHVyZQ==' };
    write(root, `node_modules/${name}/package.json`, { name, version, type: 'module', main: 'index.js' });
    write(root, `node_modules/${name}/index.js`, 'throw new Error("Inspect must not import a package");\n');
  }
  write(root, 'package-lock.json', { lockfileVersion: 3, packages });
}
function ready(name) { const root = host(name); dependencies(root); return root; }
function changeLock(root, mutate) { const data = json(path.join(root, 'package-lock.json')); mutate(data); write(root, 'package-lock.json', data); }
function snapshot(root) {
  const result = [];
  function visit(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const file = path.join(dir, entry.name), relative = path.relative(root, file);
      if (entry.isSymbolicLink()) result.push([relative, 'link']);
      else if (entry.isDirectory()) { result.push([relative, 'directory']); visit(file); }
      else result.push([relative, hash(file)]);
    }
  }
  visit(root); return result;
}
function link(target, file, directory = true) {
  try { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.symlinkSync(target, file, directory ? (process.platform === 'win32' ? 'junction' : 'dir') : 'file'); return true; }
  catch (error) { if (['EPERM', 'EACCES', 'ENOSYS'].includes(error.code)) { linkSkips++; return false; } throw error; }
}
function inspect(root, opt = {}) { return particles.inspect(root, { renderer: 'WebGLRenderer', ...opt }); }

try {
  equal(particles.parse(['inspect', '--renderer', 'WebGLRenderer']).operation, 'inspect');
  equal(particles.parse(['scaffold', '--output', 'src/fx']).opt.output, 'src/fx');
  for (const args of [[], ['install'], ['inspect', '--output', 'src/fx'], ['inspect', '--renderer'], ['inspect', '--renderer', 'WebGLRenderer', '--renderer', 'WebGLRenderer'], ['inspect', '--unknown', 'x']]) rejects(() => particles.parse(args));

  const missing = host('missing'); const before = snapshot(missing);
  const absent = inspect(missing);
  equal(absent.backend, 'THREE_QUARKS'); equal(absent.metadataReadyForIntegration, false);
  equal(absent.installedContent, 'unverified'); equal(absent.executionReadiness, 'unverified');
  equal(snapshot(missing), before); equal(fs.existsSync(path.join(missing, '.opencaw')), false);

  const root = ready('metadata'); const baseline = snapshot(root); const result = inspect(root);
  equal(result.testedPair, true); equal(result.metadataReadyForIntegration, true);
  equal(result.peerCompatible, true); equal(result.renderer.actualRendering, 'unverified');
  equal(result.packages.map(p => p.installedVersion), Object.values(pins));
  equal(snapshot(root), baseline);
  const cli = cp.spawnSync(process.execPath, [cliFile, 'inspect', '--root', root, '--renderer', 'WebGLRenderer'], { encoding: 'utf8' });
  equal(cli.status, 0); equal(JSON.parse(cli.stdout).metadataReadyForIntegration, true);
  ok(!cli.stdout.includes('powered by three.quarks')); equal(snapshot(root), baseline);
  equal(particles.inspect(root).metadataReadyForIntegration, false);
  equal(inspect(root, { renderer: 'WebGPURenderer' }).metadataReadyForIntegration, false);
  rejects(() => inspect(root, { renderer: 'UnknownRenderer' }), /renderer/i);

  const native = host('native', 'UNITY'); rejects(() => inspect(native), /THREEJS/);
  equal(fs.existsSync(path.join(native, '.opencaw')), false);
  const stale = ready('stale-manifest'); const manifest = json(path.join(stale, 'package.json'));
  manifest.dependencies['three.quarks'] = '0.16.0'; write(stale, 'package.json', manifest);
  equal(inspect(stale).metadataReadyForIntegration, false);
  const inconsistent = ready('inconsistent-spec');
  const inconsistentManifest = json(path.join(inconsistent, 'package.json')); inconsistentManifest.dependencies['three.quarks'] = '0.16.0'; write(inconsistent, 'package.json', inconsistentManifest);
  changeLock(inconsistent, d => { d.packages[''].dependencies['three.quarks'] = '0.16.0'; });
  equal(inspect(inconsistent).metadataReadyForIntegration, false);
  const alias = ready('alias-spec'); const aliasManifest = json(path.join(alias, 'package.json')); aliasManifest.dependencies['three.quarks'] = 'npm:unrelated@0.17.1'; write(alias, 'package.json', aliasManifest);
  changeLock(alias, d => { d.packages[''].dependencies['three.quarks'] = 'npm:unrelated@0.17.1'; });
  equal(inspect(alias).metadataReadyForIntegration, false);
  const older = ready('old-three'); write(older, 'node_modules/three/package.json', { name: 'three', version: '0.181.0' }); changeLock(older, d => { d.packages['node_modules/three'].version = '0.181.0'; });
  equal(inspect(older).peerCompatible, false); equal(inspect(older).metadataReadyForIntegration, false);
  const untested = ready('untested-core'); write(untested, 'node_modules/quarks.core/package.json', { name: 'quarks.core', version: '0.18.0' }); changeLock(untested, d => { d.packages['node_modules/quarks.core'].version = '0.18.0'; });
  equal(inspect(untested).testedPair, false);
  const wrongName = ready('wrong-name'); write(wrongName, 'node_modules/three.quarks/package.json', { name: 'other', version: '0.17.1' }); equal(inspect(wrongName).metadataReadyForIntegration, false);
  const noIntegrity = ready('missing-integrity'); changeLock(noIntegrity, d => { delete d.packages['node_modules/three.quarks'].integrity; }); equal(inspect(noIntegrity).metadataReadyForIntegration, false);
  const malformed = ready('malformed'); write(malformed, 'package-lock.json', 'not json'); equal(inspect(malformed).metadataReadyForIntegration, false);
  const oldLock = ready('old-lock'); changeLock(oldLock, d => { d.lockfileVersion = 1; }); equal(inspect(oldLock).lock.supportedFormat, false);
  const duplicate = ready('duplicate'); changeLock(duplicate, d => { d.packages['node_modules/unrelated/node_modules/three'] = { version: '0.182.0' }; }); equal(inspect(duplicate).duplicateThree, true); equal(inspect(duplicate).metadataReadyForIntegration, false);
  const nestedThree = ready('nested-three'); write(nestedThree, 'node_modules/three.quarks/node_modules/three/package.json', { name: 'three', version: '0.181.0' }); equal(inspect(nestedThree).metadataReadyForIntegration, false);
  const nestedCore = ready('nested-core'); write(nestedCore, 'node_modules/three.quarks/node_modules/quarks.core/package.json', { name: 'quarks.core', version: '0.16.0' }); equal(inspect(nestedCore).metadataReadyForIntegration, false);
  const unsafeNested = ready('linked-three'); const foreign = host('foreign'); write(foreign, 'package.json', { name: 'three', version: '0.182.0' });
  if (link(foreign, path.join(unsafeNested, 'node_modules/three.quarks/node_modules/three'))) equal(inspect(unsafeNested).metadataReadyForIntegration, false);
  const unsafeCore = ready('linked-core'); const foreignCore = host('foreign-core'); write(foreignCore, 'package.json', { name: 'quarks.core', version: '0.17.1' });
  if (link(foreignCore, path.join(unsafeCore, 'node_modules/three.quarks/node_modules/quarks.core'))) equal(inspect(unsafeCore).metadataReadyForIntegration, false);

  const gpu = ready('gpu'); const gpuBefore = snapshot(gpu); rejects(() => particles.scaffold(gpu, { renderer: 'WebGPURenderer' }), /WebGPU|WebGL/i); equal(snapshot(gpu), gpuBefore);
  const unsafe = ready('unsafe-output');
  for (const output of ['../outside', '/outside', 'src/../outside', 'src\\fx', '.opencaw/fx', '.git/fx', 'node_modules/fx', 'commands/fx', 'runtime/fx', 'src/fx:stream', 'src/fx.', 'src/NUL']) rejects(() => particles.scaffold(unsafe, { output }), /path|Output|traversal|scope|root/i);
  write(unsafe, 'occupied/sentinel.txt', 'foreign'); rejects(() => particles.scaffold(unsafe, { output: 'occupied' }), /exists/i); equal(fs.readFileSync(path.join(unsafe, 'occupied/sentinel.txt'), 'utf8'), 'foreign');
  write(unsafe, 'bad-parent', 'file'); rejects(() => particles.scaffold(unsafe, { output: 'bad-parent/particles' }), /directory|ENOTDIR/i);

  ok(fs.existsSync(path.join(template, 'three-quarks-runtime.mjs')));
  const fresh = ready('scaffold'); const filesBefore = snapshot(fresh); const created = particles.scaffold(fresh, { renderer: 'WebGLRenderer' });
  equal(created.backend, 'THREE_QUARKS'); equal(created.installationPerformed, false); equal(created.executionReadiness, 'unverified');
  const output = path.join(fresh, created.output), receipt = json(path.join(output, 'opencaw-particles.json'));
  for (const source of receipt.source) equal(hash(path.join(output, source.name)), hash(path.join(template, source.name)));
  equal(receipt.dependencies.metadataReadyForIntegration, true); equal(receipt.runtimeAcceptance, 'unverified');
  for (const [name, sha] of filesBefore.filter(([, value]) => value !== 'directory')) equal(hash(path.join(fresh, name)), sha);
  rejects(() => particles.scaffold(fresh), /exists/);
  rejects(() => particles.scaffold(fresh, { output: `${created.output}/nested` }), /nest|owned/i);
  const symlinkOutput = ready('linked-output'); const outside = host('outside');
  if (link(outside, path.join(symlinkOutput, 'src'))) rejects(() => particles.scaffold(symlinkOutput), /link|symbolic/i);
  const locked = ready('locked'); fs.mkdirSync(path.join(locked, '.opencaw/.cache/threejs-particles/scaffolds/operation.lock'), { recursive: true }); rejects(() => particles.scaffold(locked), /lock/i); ok(fs.existsSync(path.join(locked, '.opencaw/.cache/threejs-particles/scaffolds/operation.lock')));

  const override = host('override', 'UNITY'); write(override, '.opencaw/.cache/tasks/quarks/TASK.md', '# isolated particle test\n');
  const selected = engine.resolve(override, { override: 'THREEJS', task: 'quarks', scope: 'prototypes/quarks', recordOverride: true });
  rejects(() => particles.scaffold(override, { engineEvidence: selected.evidence }), /scope|outside|prototype/i);
  const isolated = particles.scaffold(override, { engineEvidence: selected.evidence, output: 'prototypes/quarks/particles' }); equal(isolated.output, 'prototypes/quarks/particles'); equal(isolated.dependencies.executionReadiness, 'unverified');

  const installed = host('installed'); const baselineDir = path.join(installed, '.opencaw');
  for (const file of ['commands/lib/engine-contract.cjs', 'commands/lib/threejs-particles.cjs', '.engine/registry.json', ...Object.keys(JSON.parse(fs.readFileSync(path.join(ROOT, '.engine/registry.json'))).engines).map(id => `.engine/${id}.md`)]) { const target = path.join(baselineDir, file); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.copyFileSync(path.join(ROOT, file), target); }
  fs.cpSync(template, path.join(baselineDir, '.engine/threejs/particles'), { recursive: true });
  require(path.join(baselineDir, 'commands/lib/engine-contract.cjs')).generate(installed, 'THREEJS'); dependencies(installed);
  const installedCli = cp.spawnSync(process.execPath, [path.join(baselineDir, 'commands/lib/threejs-particles.cjs'), 'scaffold', '--root', installed, '--renderer', 'WebGLRenderer'], { encoding: 'utf8' });
  equal(installedCli.status, 0); equal(JSON.parse(installedCli.stdout).backend, 'THREE_QUARKS');
  ok(fs.existsSync(path.join(installed, 'src/engine/particles/three-quarks-runtime.mjs')));

  console.log(`Three.js particle CLI: ${checks} checks passed (offline metadata/scaffold fixtures; ${linkSkips} unavailable link cases; no package execution/rendering acceptance).`);
} finally {
  // Delete only this suite's verified project-local disposable fixture root.
  const intended = path.resolve(parent), resolved = path.resolve(fixtures);
  if (!resolved.startsWith(intended + path.sep)) throw new Error('Unsafe fixture cleanup target.');
  fs.rmSync(resolved, { recursive: true, force: true });
}
