'use strict';

// Offline host-orchestration fixtures. No native toolchains, signing or stores.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const { EventEmitter } = require('node:events');
const engines = require('../commands/lib/engine-contract.cjs');
const packaging = require('../commands/lib/web-game-package.cjs');

const base = path.resolve(__dirname, '..');
const parent = path.join(base, '.opencaw/.cache/tasks/opencaw-maui-web-packaging');
fs.mkdirSync(parent, { recursive: true });
const fixtures = fs.mkdtempSync(path.join(parent, 'qa-fixtures-'));
const originals = { spawn: cp.spawn, spawnSync: cp.spawnSync, platform: Object.getOwnPropertyDescriptor(process, 'platform') };
let checks = 0;
const eq = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const ok = value => { assert.ok(value); checks++; };
const rejects = (action, pattern) => { assert.throws(action, pattern); checks++; };
const rejectsAsync = async (action, pattern) => { await assert.rejects(action, pattern); checks++; };
function write(root, relative, content) {
  const file = path.join(root, relative); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, content);
}
function host(name, engine = 'THREEJS') {
  const root = path.join(fixtures, name); fs.mkdirSync(root); engines.generate(root, engine); return root;
}
const defaults = { appId: 'com.example.game', title: 'Game & Friends', output: 'platforms/maui', webRoot: 'dist', entry: 'index.html' };
function initialize(name, options = {}) {
  const root = host(name); packaging.init(root, { ...defaults, ...options }); return root;
}
async function ready(name, options = {}) {
  const root = initialize(name, options);
  write(root, 'dist/index.html', '<!doctype html><script src="chunks/game.js"></script>');
  write(root, 'dist/chunks/game.js', 'globalThis.gameFixture = true;');
  write(root, 'dist/assets/level.bin', Buffer.from([1, 2, 3]));
  await packaging.sync(root, {}); return root;
}
function readConfig(root) { return JSON.parse(fs.readFileSync(path.join(root, 'web-game-package.json'), 'utf8')); }
function changeConfig(root, patch) { write(root, 'web-game-package.json', JSON.stringify({ ...readConfig(root), ...patch }, null, 2) + '\n'); }
function stateFiles(root, name) {
  const directory = packaging.context(root).state;
  if (!fs.existsSync(directory)) return [];
  const result = [];
  function visit(dir) { for (const entry of fs.readdirSync(dir, { withFileTypes: true })) { const file = path.join(dir, entry.name); if (entry.isDirectory()) visit(file); else if (entry.name === name) result.push(file); } }
  visit(directory); return result;
}
function mockNative(mode = 'success') {
  const observed = { probes: [], commands: [], kills: [], active: null };
  Object.defineProperty(process, 'platform', { ...originals.platform, value: 'win32' });
  cp.spawnSync = (command, args, options) => {
    if (command === 'taskkill') { observed.kills.push(args); process.nextTick(() => observed.active.emit('exit', 137)); return { status: 0, stdout: '' }; }
    eq(command, 'dotnet'); observed.probes.push(args);
    return { status: 0, stdout: args[0] === '--version' ? '10.0.400\n' : 'Installed Workload Id Manifest Version\nmaui-windows 10.0.20/10.0.100 VS\n' };
  };
  cp.spawn = (command, args, options) => {
    observed.commands.push({ command, args, options });
    const child = new EventEmitter(); child.pid = 91919191; observed.active = child;
    process.nextTick(() => {
      const out = args[args.indexOf('-o') + 1];
      if (mode === 'timeout') return;
      if (mode === 'error') { child.emit('error', new Error('fixture process failed to start')); return; }
      if (mode !== 'missing') write(out, mode === 'wrong-format' ? 'GameHost.txt' : 'GameHost.exe', mode === 'empty' ? Buffer.alloc(0) : Buffer.from('fixture-native-bytes'));
      if (mode === 'changed-source') write(options.cwd, 'dist/chunks/game.js', 'changed while compiler held inputs');
      if (mode === 'changed-signing') write(options.cwd, 'signing/private.props', '<Project><!-- changed signing policy --></Project>');
      child.emit('exit', mode === 'failed' ? 17 : 0);
    });
    return child;
  };
  return observed;
}
function restoreNative() { cp.spawn = originals.spawn; cp.spawnSync = originals.spawnSync; Object.defineProperty(process, 'platform', originals.platform); }

(async () => {
  eq(Object.keys(packaging.TARGETS), ['WINDOWS', 'MACOS', 'ANDROID', 'IOS']);
  eq(packaging.parse(['package', '--target', 'WINDOWS', '--rid', 'win-x64']).operation, 'package');
  rejects(() => packaging.parse(['init', '--app-id']), /missing|option/i);
  rejects(() => packaging.parse(['package', '--target', 'WINDOWS', '--target', 'IOS']), /repeated|option/i);
  rejects(() => packaging.parse(['sync', '--app-id', 'com.example.game']), /not supported/i);
  rejects(() => packaging.parse(['release']), /Unknown/);
  rejects(() => packaging.parse(['package', '--property', 'A=B']), /Unknown/);

  const help = originals.spawnSync(process.execPath, [path.join(base, 'commands/lib/web-game-package.cjs'), '--help'], { encoding: 'utf8' });
  eq(help.status, 0); ok(help.stdout.includes('Linux/TV are unsupported'));
  const noSideEffects = host('read-only-selection');
  const beforeResolve = fs.readdirSync(noSideEffects);
  const resolve = originals.spawnSync(process.execPath, [path.join(base, 'commands/lib/web-game-package.cjs'), 'resolve', '--root', noSideEffects], { encoding: 'utf8' });
  eq(resolve.status, 0); eq(JSON.parse(resolve.stdout).packaging.profile, 'MAUI'); eq(fs.readdirSync(noSideEffects), beforeResolve);

  const native = host('native', 'UNITY');
  rejects(() => packaging.init(native, defaults), /native exporter/i);
  eq(fs.readdirSync(native), ['ENGINE.md']);

  const initRoot = initialize('safe-init');
  const nativeHost = path.join(initRoot, defaults.output);
  const props = fs.readFileSync(path.join(nativeHost, 'OpenCawGame.props'), 'utf8');
  ok(props.includes('Game &amp; Friends')); ok(props.includes('<ApplicationId>com.example.game</ApplicationId>'));
  ok(fs.existsSync(path.join(nativeHost, 'Platforms/Windows/Package.appxmanifest')));
  ok(fs.existsSync(path.join(nativeHost, 'Platforms/Android/AndroidManifest.xml')));
  ok(fs.existsSync(path.join(nativeHost, 'Platforms/iOS/Info.plist')));
  ok(fs.existsSync(path.join(nativeHost, 'Platforms/MacCatalyst/Info.plist')));
  eq(fs.existsSync(path.join(nativeHost, 'Platforms/Linux')), false);
  rejects(() => packaging.init(initRoot, defaults), /already exists/i);
  eq(fs.readFileSync(path.join(nativeHost, 'OpenCawGame.props'), 'utf8'), props);

  const foreign = host('foreign'); write(foreign, 'platforms/maui/private.txt', 'preserve foreign source');
  rejects(() => packaging.init(foreign, defaults), /already exists/i);
  eq(fs.readFileSync(path.join(foreign, 'platforms/maui/private.txt'), 'utf8'), 'preserve foreign source');
  eq(fs.existsSync(path.join(foreign, 'web-game-package.json')), false);
  for (const [name, patch] of [
    ['traversal', { output: '../escape' }], ['absolute', { output: '/tmp/escape' }],
    ['drive', { output: 'C:/escape' }], ['ads', { output: 'native:stream' }],
    ['reserved', { output: 'platforms/CON' }], ['trailing', { output: 'platforms/maui.' }],
    ['cache', { output: '.opencaw/.cache/native' }], ['git', { output: '.git/native' }],
    ['overlap-source', { output: 'dist/native' }], ['overlap-host', { webRoot: 'platforms' }],
    ['config-overlap', { config: 'dist/config.json' }], ['bad-id', { appId: 'not-valid' }],
    ['remote-entry', { entry: 'https://example.com/index.html' }], ['entry-traversal', { entry: '../index.html' }],
    ['msbuild-title', { title: '$([System.IO.File]::ReadAllText(\'secret\'))' }],
    ['msbuild-entry', { entry: 'bad$(MSBuildProjectDirectory).html' }],
    ['property-separator', { output: 'platforms/maui;Injected=true' }]
  ]) {
    const root = host(name);
    assert.throws(() => packaging.init(root, { ...defaults, ...patch }), /unsafe|portable|overlap|invalid|reverse-DNS|MSBuild|expression|metasyntax|cannot target/i, name); checks++;
    eq(fs.readdirSync(root), ['ENGINE.md']);
  }

  const root = await ready('sync');
  let c = packaging.context(root); let snapshot = packaging.verifySnapshot(c);
  eq(snapshot.identity.webFiles.length, 3);
  eq(fs.readFileSync(path.join(c.host, 'Resources/Raw/wwwroot/chunks/game.js'), 'utf8'), 'globalThis.gameFixture = true;');
  write(root, 'dist/assets/new.bin', Buffer.from([4]));
  rejects(() => packaging.verifySnapshot(packaging.context(root)), /inputs changed/i);
  await packaging.sync(root, {}); c = packaging.context(root);
  eq(packaging.verifySnapshot(c).identity.webFiles.length, 4);
  fs.unlinkSync(path.join(root, 'dist/assets/level.bin')); await packaging.sync(root, {});
  eq(fs.existsSync(path.join(c.host, 'Resources/Raw/wwwroot/assets/level.bin')), false);
  eq(stateFiles(root, 'snapshot.json').length, 3);
  write(root, 'platforms/maui/Resources/Raw/wwwroot/chunks/game.js', 'foreign edit');
  await rejectsAsync(() => packaging.sync(root, {}), /changed|foreign/i);
  eq(fs.readFileSync(path.join(c.host, 'Resources/Raw/wwwroot/chunks/game.js'), 'utf8'), 'foreign edit');

  const foreignAssets = initialize('foreign-assets'); write(foreignAssets, 'dist/index.html', 'game');
  write(foreignAssets, 'platforms/maui/Resources/Raw/wwwroot/foreign.txt', 'keep');
  await rejectsAsync(() => packaging.sync(foreignAssets, {}), /ownership snapshot/i);
  eq(fs.readFileSync(path.join(foreignAssets, 'platforms/maui/Resources/Raw/wwwroot/foreign.txt'), 'utf8'), 'keep');
  const changedNative = await ready('changed-native'); write(changedNative, 'platforms/maui/GamePage.cs', '// explicit native edit');
  rejects(() => packaging.verifySnapshot(packaging.context(changedNative)), /inputs changed/i);
  const changedConfig = await ready('changed-config'); changeConfig(changedConfig, { buildNumber: 2 });
  rejects(() => packaging.verifySnapshot(packaging.context(changedConfig)), /inputs changed/i);
  await packaging.sync(changedConfig, {});
  ok(fs.readFileSync(path.join(changedConfig, 'platforms/maui/OpenCawGame.props'), 'utf8').includes('<ApplicationVersion>2</ApplicationVersion>'));
  const owner = initialize('wrong-owner'); changeConfig(owner, { appId: 'com.other.game' });
  rejects(() => packaging.context(owner), /another configuration/i);
  const lockedRoot = await ready('locked'); const state = packaging.context(lockedRoot).state;
  fs.mkdirSync(path.join(state, 'operation.lock'));
  await rejectsAsync(() => packaging.sync(lockedRoot, {}), /lock exists/i);
  ok(fs.existsSync(path.join(state, 'operation.lock')));

  const changedEngine = await ready('changed-engine');
  fs.appendFileSync(path.join(changedEngine, 'ENGINE.md'), '\nA reviewed engine contract change.\n');
  rejects(() => packaging.verifySnapshot(packaging.context(changedEngine)), /inputs changed/i);
  const changedStage = await ready('changed-stage');
  write(changedStage, 'platforms/maui/Resources/Raw/wwwroot/foreign.bin', 'preserve');
  rejects(() => packaging.verifySnapshot(packaging.context(changedStage)), /changed|foreign/i);
  await rejectsAsync(() => packaging.sync(changedStage, {}), /changed|foreign/i);
  eq(fs.readFileSync(path.join(changedStage, 'platforms/maui/Resources/Raw/wwwroot/foreign.bin'), 'utf8'), 'preserve');

  const linkRoot = initialize('link'); write(linkRoot, 'dist/index.html', 'game');
  const target = path.join(linkRoot, 'real'); fs.mkdirSync(target); write(target, 'asset.txt', 'keep');
  fs.symlinkSync(target, path.join(linkRoot, 'dist/link'), process.platform === 'win32' ? 'junction' : 'dir');
  await rejectsAsync(() => packaging.sync(linkRoot, {}), /link|junction/i);
  eq(fs.readFileSync(path.join(target, 'asset.txt'), 'utf8'), 'keep');
  const stateLinkRoot = initialize('state-link'); write(stateLinkRoot, 'dist/index.html', 'game');
  const foreignState = path.join(stateLinkRoot, 'foreign-state'); fs.mkdirSync(foreignState);
  write(foreignState, 'preserve.txt', 'foreign state');
  const ownedCache = path.join(stateLinkRoot, '.opencaw/.cache'), savedCache = path.join(stateLinkRoot, 'saved-cache');
  assert.ok(fs.realpathSync(ownedCache).startsWith(fs.realpathSync(stateLinkRoot) + path.sep));
  assert.ok(path.resolve(savedCache).startsWith(path.resolve(stateLinkRoot) + path.sep));
  fs.renameSync(ownedCache, savedCache); // Preserve init journals before substituting the unsafe cache fixture.
  fs.symlinkSync(foreignState, path.join(stateLinkRoot, '.opencaw/.cache'), process.platform === 'win32' ? 'junction' : 'dir');
  await rejectsAsync(() => packaging.sync(stateLinkRoot, {}), /link|junction/i);
  eq(fs.readdirSync(foreignState), ['preserve.txt']);

  // Same source modules mounted at the canonical installed path: no source-checkout
  // relative path assumptions. This is an installed-module fixture, not Git clone QA.
  const installedRoot = host('installed');
  const baseline = path.join(installedRoot, '.opencaw'); fs.mkdirSync(baseline);
  for (const rel of ['commands/lib/web-game-package.cjs', 'commands/lib/engine-contract.cjs', '.engine/registry.json']) {
    write(baseline, rel, fs.readFileSync(path.join(base, rel)));
  }
  for (const id of ['THREEJS', 'BABYLONJS', 'PHASERJS', 'UNITY', 'UNREAL', 'GODOT']) write(baseline, `.engine/${id}.md`, fs.readFileSync(path.join(base, `.engine/${id}.md`)));
  for (const entry of packaging.tree(path.join(base, '.packaging/maui/template'))) write(baseline, `.packaging/maui/template/${entry.path}`, fs.readFileSync(path.join(base, '.packaging/maui/template', entry.path)));
  const installedEngine = require(path.join(baseline, 'commands/lib/engine-contract.cjs'));
  const installedPackaging = require(path.join(baseline, 'commands/lib/web-game-package.cjs'));
  installedEngine.generate(installedRoot, 'PHASERJS'); installedPackaging.init(installedRoot, defaults);
  write(installedRoot, 'dist/index.html', '<!doctype html><p>Installed host fixture</p>');
  await installedPackaging.sync(installedRoot, {});
  eq(installedPackaging.context(installedRoot).selected.effectiveEngine, 'PHASERJS');
  eq(installedPackaging.verifySnapshot(installedPackaging.context(installedRoot)).identity.webFiles.length, 1);

  const planRoot = await ready('plans');
  let observed = mockNative();
  try {
    const prior = stateFiles(planRoot, 'intent.json').length;
    const windows = packaging.plan(planRoot, { target: 'WINDOWS', format: 'msix', rid: 'win-x64' });
    eq(windows.command, 'dotnet'); ok(windows.args.includes('-p:WindowsPackageType=MSIX'));
    ok(windows.args.includes('-p:PublishAot=false')); ok(windows.args.includes('-p:TrimMode=partial'));
    ok(windows.args.some(value => value.endsWith('GameHost.csproj'))); eq(windows.externalSubmission, false); eq(windows.releaseReady, false);
    eq(stateFiles(planRoot, 'intent.json').length, prior); eq(observed.commands.length, 0);
    const ios = packaging.plan(planRoot, { target: 'IOS' });
    ok(ios.args.includes('-p:ArchiveOnBuild=true')); ok(ios.args.includes('-p:BuildIpa=true')); eq(ios.prerequisites.hostCompatible, false);
    const mac = packaging.plan(planRoot, { target: 'MACOS', format: 'pkg' }); ok(mac.args.includes('-p:CreatePackage=true'));
    const android = packaging.plan(planRoot, { target: 'ANDROID', format: 'aab' }); ok(android.args.includes('-p:AndroidPackageFormats=aab'));
    rejects(() => packaging.plan(planRoot, { target: 'LINUX' }), /unsupported/i);
    rejects(() => packaging.plan(planRoot, { target: 'TVOS' }), /unsupported/i);
    rejects(() => packaging.plan(planRoot, { target: 'WINDOWS', rid: 'win10-x64' }), /Unsupported/);
    rejects(() => packaging.plan(planRoot, { target: 'WINDOWS', rid: 'win-x64 -p:Injected=true' }), /Unsupported/);
    rejects(() => packaging.plan(planRoot, { target: 'ANDROID', format: 'ipa' }), /Unsupported/);
    const successful = await packaging.execute(planRoot, { operation: 'package', target: 'WINDOWS', format: 'folder' });
    eq(successful.status, 'succeeded'); eq(successful.nativeReadiness, 'compiled'); eq(successful.releaseReady, false); eq(successful.storeSubmitted, false);
    eq(successful.files.length, 1); eq(successful.files[0].size, Buffer.byteLength('fixture-native-bytes'));
    eq(successful.deviceQa, 'not-run'); eq(successful.signing, 'unverified');
    eq(observed.commands.length, 1); eq(observed.commands[0].command, 'dotnet'); eq(observed.commands[0].options.stdio, ['ignore', 'ignore', 'ignore']);
    ok(!JSON.stringify(successful).includes('fixture-native-bytes'));
    const other = await packaging.execute(planRoot, { operation: 'package', target: 'WINDOWS' });
    ok(successful.output !== other.output); eq(stateFiles(planRoot, 'result.json').length, 2);

    const signingRoot = await ready('signing-privacy');
    write(signingRoot, 'signing/private.props', '<Project><!-- SYNTHETIC_SIGNING_SENTINEL --></Project>');
    const signingPlan = packaging.plan(signingRoot, { target: 'WINDOWS', signingProperties: 'signing/private.props' });
    ok(!JSON.stringify(signingPlan).includes('SYNTHETIC_SIGNING_SENTINEL'));
    const signingResult = await packaging.execute(signingRoot, { operation: 'package', target: 'WINDOWS', signingProperties: 'signing/private.props' });
    ok(!JSON.stringify(signingResult).includes('SYNTHETIC_SIGNING_SENTINEL'));
    ok(/^[a-f0-9]{64}$/.test(signingResult.signingPropertiesSha256));
    rejects(() => packaging.plan(signingRoot, { target: 'WINDOWS', signingProperties: '../outside.props' }), /unsafe|portable/i);
    write(signingRoot, 'signing/injected.props;Payload=true', '<Project />');
    rejects(() => packaging.plan(signingRoot, { target: 'WINDOWS', signingProperties: 'signing/injected.props;Payload=true' }), /MSBuild|portable/i);
  } finally { restoreNative(); }

  for (const mode of ['failed', 'missing', 'wrong-format', 'empty', 'error', 'changed-source', 'timeout']) {
    const nativeRoot = await ready(`execute-${mode}`); observed = mockNative(mode);
    try {
      await rejectsAsync(() => packaging.execute(nativeRoot, { operation: 'package', target: 'WINDOWS', timeoutSeconds: mode === 'timeout' ? 1 : 5 }), /failed|cancelled|output|artifact|changed|directory/i);
      eq(stateFiles(nativeRoot, 'result.json').length, 1);
      const result = JSON.parse(fs.readFileSync(stateFiles(nativeRoot, 'result.json')[0], 'utf8'));
      eq(result.status, 'failed'); eq(result.releaseReady, false); eq(result.storeSubmitted, false);
      eq(fs.existsSync(path.join(packaging.context(nativeRoot).state, 'operation.lock')), false);
      if (mode === 'timeout') eq(observed.kills.length, 1);
    } finally { restoreNative(); }
  }
  const changedSigning = await ready('changed-signing');
  write(changedSigning, 'signing/private.props', '<Project><!-- original signing policy --></Project>');
  observed = mockNative('changed-signing');
  try {
    await rejectsAsync(() => packaging.execute(changedSigning, { operation: 'package', target: 'WINDOWS', signingProperties: 'signing/private.props' }), /changed/i);
    eq(JSON.parse(fs.readFileSync(stateFiles(changedSigning, 'result.json')[0], 'utf8')).status, 'failed');
  } finally { restoreNative(); }
  const invalidTimeout = await ready('invalid-timeout'); observed = mockNative();
  try {
    await rejectsAsync(() => packaging.execute(invalidTimeout, { operation: 'package', target: 'WINDOWS', timeoutSeconds: 0 }), /timeout/i);
    eq(stateFiles(invalidTimeout, 'intent.json').length, 0); eq(observed.commands.length, 0);
  } finally { restoreNative(); }
  console.log(`Web-game packaging: ${checks} checks passed (offline host fixtures; no native, device, signing or store acceptance).`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  restoreNative();
  const resolved = fs.realpathSync(fixtures), verifiedParent = fs.realpathSync(parent);
  assert.ok(verifiedParent.startsWith(fs.realpathSync(base) + path.sep));
  assert.ok(resolved.startsWith(verifiedParent + path.sep));
  fs.rmSync(resolved, { recursive: true, force: true });
});
