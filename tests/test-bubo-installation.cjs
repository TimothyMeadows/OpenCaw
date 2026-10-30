'use strict';

// Offline integration checks of the actual admission, engine and scaffold code.
// The default tiny Bubo repository is never executable. --real-runtime instead
// copies an existing pinned build and runs only its prebuilt capabilities command.
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const args = process.argv.slice(2);
assert(args.length === 0 || (args.length === 1 && args[0] === '--real-runtime'), 'Usage: node tests/test-bubo-installation.cjs [--real-runtime]');
const realMode = args.length === 1;
const base = path.resolve(__dirname, '..');
const cache = path.basename(base) === '.opencaw' ? path.join(base, '.cache') : path.join(base, '.opencaw/.cache');
const evidence = path.join(cache, 'tasks/opencaw-retire-comfyui/evidence/installation');
fs.mkdirSync(evidence, { recursive: true });
const fixture = fs.mkdtempSync(path.join(evidence, realMode ? 'fixture-real-' : 'fixture-'));
const environment = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(fixture, 'gitconfig'),
  GIT_ALLOW_PROTOCOL: 'file', GIT_TERMINAL_PROMPT: '0', GIT_AUTHOR_NAME: 'OpenCaw installation fixture',
  GIT_AUTHOR_EMAIL: 'fixture@example.invalid', GIT_COMMITTER_NAME: 'OpenCaw installation fixture',
  GIT_COMMITTER_EMAIL: 'fixture@example.invalid' };
for (const name of ['OPENCAW_PROJECT_ROOT', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE']) delete environment[name];
fs.writeFileSync(environment.GIT_CONFIG_GLOBAL, '[core]\n autocrlf = false\n[commit]\n gpgsign = false\n');
const observations = [];
function check(value, message) { assert(value, message); observations.push(message); }
function equal(actual, expected, message) { assert.deepEqual(actual, expected, message); observations.push(message); }
function rejects(action, pattern, message) { assert.throws(action, pattern, message); observations.push(message); }
function write(root, relative, contents) {
  const file = path.join(root, relative); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, contents);
}
function digest(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }
function command(executable, args, cwd = fixture, allowedFailure = false) {
  const result = cp.spawnSync(executable, args, { cwd, env: environment, encoding: 'utf8', windowsHide: true, timeout: 60000, maxBuffer: 4 * 1024 * 1024 });
  assert.ifError(result.error);
  if (!allowedFailure) assert.equal(result.status, 0, `${path.basename(executable)} ${args.join(' ')}\n${result.stderr}\n${result.stdout}`);
  return result;
}
function git(root, ...args) { return command('git', ['-C', root, ...args]).stdout.trim(); }
function init(root) { fs.mkdirSync(root, { recursive: true }); git(root, 'init', '-q', '--initial-branch=main'); }
function commit(root, message) { git(root, 'add', '.'); git(root, 'commit', '-qm', message); return git(root, 'rev-parse', 'HEAD'); }
function runtime(baseline, operation) {
  return command(process.execPath, [path.join(baseline, 'commands/lib/bubo-runtime.cjs'), ...operation], baseline, true);
}
function bashExecutable() {
  if (process.platform !== 'win32') return 'bash';
  const gitExec = command('git', ['--exec-path']).stdout.trim();
  const candidate = path.resolve(gitExec, '../../..', 'bin/bash.exe');
  assert(fs.existsSync(candidate), 'An existing Git Bash runtime is required on Windows; no provider is installed by this test.');
  return candidate;
}
function shell(baseline, script) { return command(bash, [path.join(baseline, 'commands', script)], baseline); }
const bash = realMode ? null : bashExecutable();

function realRuntime() {
  const dependency = path.join(base, 'runtime/bubo'), bundle = path.join(dependency, 'artifacts/bubo');
  const lockFile = path.join(base, 'runtime/bubo.lock.json'), receiptFile = path.join(bundle, 'build-info.json');
  const executable = process.platform === 'win32' ? 'bubo.exe' : 'bubo';
  assert(fs.existsSync(receiptFile) && fs.existsSync(path.join(bundle, executable)),
    '--real-runtime requires the recorded Bubo dependency and an existing prebuilt CLI. Run initialize-bubo-runtime.sh and build-bubo-runtime.sh explicitly first; this test does not build, install or download anything.');
  const lock = JSON.parse(fs.readFileSync(lockFile, 'utf8')), receipt = JSON.parse(fs.readFileSync(receiptFile, 'utf8'));
  const revision = git(dependency, 'rev-parse', 'HEAD');
  equal(revision, lock.revision, 'Real source checkout identifies the actual recorded Bubo revision');
  equal(receipt.sourceRevision, revision, 'Real build receipt identifies that same recorded revision');
  equal(receipt.sourceDirty, false, 'Real build receipt records a clean source build');
  equal(git(dependency, 'status', '--porcelain', '--untracked-files=no'), '', 'Real source checkout is unchanged before fixture creation');
  const files = [];
  function inventory(dir, relative = '') {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const name = path.join(relative, entry.name), full = path.join(dir, entry.name), stat = fs.lstatSync(full);
      assert(!stat.isSymbolicLink(), 'Real bundle copies cannot follow symbolic links: ' + name);
      if (stat.isDirectory()) inventory(full, name);
      else { assert(stat.isFile(), 'Real bundle contains only regular files: ' + name); files.push({ name, sha256: digest(full), mode: stat.mode & 0o777 }); }
    }
  }
  inventory(bundle);
  check(files.length > 0, 'Real bundle inventory contains actual published files');
  const source = path.join(fixture, 'real-opencaw-source'); init(source);
  for (const name of ['commands/lib/bubo-runtime.cjs', 'runtime/bubo.lock.json', '.gitignore']) {
    const target = path.join(source, name); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.copyFileSync(path.join(base, name), target);
  }
  git(source, 'submodule', 'add', '-q', dependency, 'runtime/bubo');
  git(path.join(source, 'runtime/bubo'), 'checkout', '-q', '--detach', revision);
  commit(source, 'Actual pinned Bubo admission fixture');
  const rejectionEvidence = [], forms = [];
  for (const form of ['clone', 'submodule']) {
    const host = path.join(fixture, `real-${form}-host`); init(host);
    const baseline = path.join(host, '.opencaw');
    if (form === 'clone') command('git', ['clone', '-q', '--no-hardlinks', '--recurse-submodules', source, baseline]);
    else {
      git(host, 'submodule', 'add', '-q', source, '.opencaw');
      git(host, 'submodule', 'update', '--init', '--recursive', '--checkout', '--', '.opencaw');
    }
    const copiedDependency = path.join(baseline, 'runtime/bubo'), copiedBundle = path.join(copiedDependency, 'artifacts/bubo');
    equal(git(copiedDependency, 'rev-parse', 'HEAD'), revision, `${form}: actual dependency clone checks out the recorded Bubo revision`);
    equal(git(baseline, 'ls-files', '--stage', '--', 'runtime/bubo').split(/\s+/).slice(0, 3), ['160000', revision, '0'], `${form}: actual Git parent records the matching Bubo gitlink`);
    for (const file of files) {
      const target = path.join(copiedBundle, file.name), original = path.join(bundle, file.name);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.copyFileSync(original, target); // Independent file contents; never link().
      fs.chmodSync(target, file.mode);
      assert.equal(digest(target), file.sha256, 'Copied bundle file bytes differ: ' + file.name);
      const sourceStat = fs.statSync(original, { bigint: true }), targetStat = fs.statSync(target, { bigint: true });
      assert(!(sourceStat.ino !== 0n && sourceStat.dev === targetStat.dev && sourceStat.ino === targetStat.ino), 'Copied bundle must not share a source inode: ' + file.name);
    }
    check(true, `${form}: all ${files.length} actual bundle files have matching bytes and independent file identities`);
    const admitted = runtime(baseline, ['verify']);
    equal(admitted.status, 0, `${form}: actual prebuilt capabilities pass full revision/API/build/resource admission`);
    const identity = JSON.parse(admitted.stdout);
    equal(identity.revision, revision, `${form}: admitted CLI reports the recorded revision`);
    equal(identity.build, receipt.capabilities.build, `${form}: observed live capability build agrees with the original build receipt`);
    const liveMedia = JSON.parse(command(path.join(copiedBundle, executable), ['capabilities', '--api-version', '1'], copiedBundle).stdout);
    equal(liveMedia.mediaBackends.map(item => [item.id, item.modality]).sort(), [
      ['flux-schnell', 'image'], ['stable-audio-open', 'sfx'], ['ace-step-turbo', 'music'],
      ['qwen3-tts-customvoice', 'preset-speech'], ['qwen3-tts-base', 'consented-cloning']
    ].sort(), `${form}: actual prebuilt CLI advertises all five selected backends without loading models`);
    equal(runtime(baseline, ['resource', 'media/catalog.json']).status, 0, `${form}: recorded source admits the pinned media catalog`);
    function changed(name, mutate, expected, label) {
      const full = path.join(copiedBundle, name), original = fs.existsSync(full) ? fs.readFileSync(full) : null;
      const mode = original === null ? null : fs.statSync(full).mode & 0o777;
      try {
        fs.writeFileSync(full, mutate(original));
        const rejected = runtime(baseline, ['verify']);
        check(rejected.status === 1 && expected.test(rejected.stderr), `${form}: ${label} is rejected by its specific admission guard (${rejected.stderr.trim()})`);
        rejectionEvidence.push({ form, case: label, exitCode: rejected.status, diagnostic: rejected.stderr.trim() });
      } finally {
        if (original === null) fs.unlinkSync(full);
        else { fs.writeFileSync(full, original); fs.chmodSync(full, mode); }
      }
      equal(runtime(baseline, ['verify']).status, 0, `${form}: restoring ${label} bytes permits a fresh successful admission`);
    }
    const modifyReceipt = update => bytes => { const value = JSON.parse(bytes.toString('utf8')); update(value); return JSON.stringify(value, null, 2); };
    changed('build-info.json', modifyReceipt(value => { value.capabilities.apiVersions = [999]; }), /build\/API\/resource contract mismatch/, 'incompatible execution API');
    changed('build-info.json', modifyReceipt(value => { value.sourceRevision = '0'.repeat(40); }), /receipt is stale\/dirty/, 'stale build revision');
    changed('build-info.json', modifyReceipt(value => { value.sourceDirty = true; }), /receipt is stale\/dirty/, 'dirty build marker');
    changed('resources/catalog.json', bytes => Buffer.concat([bytes, Buffer.from('\n')]), /Published Bubo resource catalog changed/, 'published resource catalog tamper');
    const resource = Object.keys(JSON.parse(fs.readFileSync(path.join(copiedBundle, 'resources/catalog.json'), 'utf8')).files).sort()[0];
    changed(resource, bytes => Buffer.concat([bytes, Buffer.from('\nfixture tamper\n')]), /Published Bubo audited resource changed/, 'published audited resource tamper');
    changed('resources/media/catalog.json', bytes => Buffer.concat([bytes, Buffer.from('\n')]), /Published Bubo audited resource changed/, 'published media catalog tamper');
    changed('resources/media/voice/worker.py', bytes => Buffer.concat([bytes, Buffer.from('\n# owned nonexecuted tamper\n')]), /Published Bubo audited resource changed/, 'published voice worker tamper');
    changed('Bubo.Host.dll', bytes => Buffer.concat([bytes, Buffer.from([0])]), /Bubo built artifact changed: Bubo\.Host\.dll/, 'runtime assembly tamper');
    changed(executable, bytes => Buffer.concat([bytes, Buffer.from([0])]), /Bubo built artifact changed: bubo(?:\.exe)?/, 'apphost tamper');
    for (const config of ['bubo.runtimeconfig.json', 'bubo.deps.json']) changed(config, bytes => Buffer.concat([bytes, Buffer.from('\n')]), /Bubo built artifact changed:/, config + ' tamper');
    changed('unexpected-fixture.dll', () => Buffer.from('Reject the inventory before attempting to load this fixture.'), /Unexpected or missing Bubo runtime assembly/, 'unexpected runtime assembly');
    changed('build-info.json', modifyReceipt(value => { value.capabilities.build.cliSha256 = '0'.repeat(64); }), /live capability\/build identity differs/, 'receipt disagreement with actual prebuilt capabilities');
    equal(git(copiedDependency, 'status', '--porcelain', '--untracked-files=no'), '', `${form}: isolated build checks preserve pinned tracked source files`);
    forms.push({ form, revision, cliSha256: identity.build.cliSha256, copiedFiles: files.length, rejectedCases: 13 });
  }
  for (const file of files) assert.equal(digest(path.join(bundle, file.name)), file.sha256, 'Actual input bundle was modified: ' + file.name);
  check(true, 'Every original published bundle file retains its initial hash after isolated mutations');
  equal(git(dependency, 'status', '--porcelain', '--untracked-files=no'), '', 'Actual pinned Bubo source remains unchanged after both isolated forms');
  fs.writeFileSync(path.join(evidence, 'real-runtime-latest.json'), JSON.stringify({ schemaVersion: 1, mode: 'real-runtime', status: 'pass',
    assertions: observations.length, platform: process.platform, revision, resourceCatalogSha256: lock.resourceCatalogSha256,
    nativeBuilds: 0, executedCommands: ['prebuilt capabilities --api-version 1'], networkProtocolsAllowed: ['file'],
    forms, rejectionEvidence, observations }, null, 2) + '\n');
  console.log(`Real Bubo build admission tests passed (${observations.length} assertions; 26 isolated rejection cases; actual prebuilt capabilities; no builds/models).`);
}

let completed = false;
try {
  if (realMode) {
    realRuntime();
    completed = true;
  } else {
  const bubo = path.join(fixture, 'bubo-source'); init(bubo);
  write(bubo, 'Bubo.slnx', '<Solution />\n');
  write(bubo, 'dev/browser/package.json', JSON.stringify({ devDependencies: { three: 'fixture-only' } }));
  write(bubo, 'resources/proof-to-model/manifest.schema.json', '{"fixture":"resource admission only"}\n');
  const resourceKey = 'resources/proof-to-model/manifest.schema.json';
  const mediaResource = 'resources/media/catalog.json', voiceResource = 'resources/media/voice/worker.py';
  write(bubo, mediaResource, JSON.stringify({ schemaVersion: 'owned-media-catalog-fixture/v1', backends: [
    { id: 'flux-schnell', modality: 'image' }, { id: 'stable-audio-open', modality: 'sfx' },
    { id: 'ace-step-turbo', modality: 'music' }, { id: 'qwen3-tts-customvoice', modality: 'preset-speech' },
    { id: 'qwen3-tts-base', modality: 'consented-cloning' }
  ], fixture: 'OWNED metadata; no native execution or model-quality evidence' }));
  write(bubo, voiceResource, '# OWNED NONEXECUTABLE fixture; never imported or launched\n');
  write(bubo, 'resources/catalog.json', JSON.stringify({ schemaVersion: 1, files: Object.fromEntries(
    [resourceKey, mediaResource, voiceResource].map(name => [name, digest(path.join(bubo, name))])) }, null, 2));
  const pinned = commit(bubo, 'Pinned offline dependency fixture');
  const source = path.join(fixture, 'opencaw-source'); init(source);
  for (const file of ['commands/lib/bubo-runtime.cjs', 'commands/lib/bubo-host-adapter.cjs', 'commands/lib/style-contract.cjs',
    'commands/lib/engine-contract.cjs', 'commands/lib/memory-common.sh', 'commands/proof-to-model.sh',
    'commands/model-to-animation.sh', 'commands/model-to-action.sh',
    'commands/lib/platform-common.sh', 'commands/initialize-bubo-runtime.sh', 'commands/resolve-opencaw-paths.sh',
    'commands/create-host-ai-scaffold.sh', '.gitignore']) {
    const destination = path.join(source, file); fs.mkdirSync(path.dirname(destination), { recursive: true }); fs.copyFileSync(path.join(base, file), destination);
  }
  fs.cpSync(path.join(base, 'commands/lib'), path.join(source, 'commands/lib'), { recursive: true });
  for (const file of ['commands/bubo-media.sh', 'commands/install-bubo-media.sh', 'commands/inspect-local-media-host.sh']) {
    const destination = path.join(source, file); fs.mkdirSync(path.dirname(destination), { recursive: true }); fs.copyFileSync(path.join(base, file), destination);
  }
  fs.cpSync(path.join(base, '.engine'), path.join(source, '.engine'), { recursive: true });
  write(source, 'AGENTS.md', '# Controlled installation fixture\n');
  git(source, 'submodule', 'add', '-q', bubo, 'runtime/bubo');
  const lock = { schemaVersion: 1, repository: 'https://github.com/TimothyMeadows/Bubo.git', path: 'runtime/bubo',
    revision: pinned, apiVersion: 1, resourceCatalogSha256: digest(path.join(bubo, 'resources/catalog.json')), buildReceipt: 'artifacts/bubo/build-info.json' };
  write(source, 'runtime/bubo.lock.json', JSON.stringify(lock, null, 2));
  commit(source, 'Installation code with an actual nested gitlink');
  write(bubo, 'later-upstream.txt', 'This later upstream revision must not be selected.\n');
  const newer = commit(bubo, 'Advance upstream beyond recorded dependency');
  check(newer !== pinned, 'Fixture upstream has an actual newer commit than the recorded pin');

  // This is a maintainer root: unlike installed hosts, its baseline directory
  // is not hidden beneath .opencaw and must exclude exactly its dependency.
  const maintainerEngine = require(path.join(source, 'commands/lib/engine-contract.cjs'));
  maintainerEngine.generate(source, 'UNITY');
  equal(maintainerEngine.resolve(source).existingEngines, [], 'Maintainer discovery excludes the exact baseline-owned dependency before reading its development package');
  for (const relative of ['runtime/game', 'runtime/bubo-extra', 'nested/runtime/bubo']) {
    const marker = path.join(source, relative, 'project.godot'); write(source, path.relative(source, marker), '[application]\n');
    rejects(() => maintainerEngine.resolve(source), /GODOT.*conflicts/, `Maintainer discovery retains unrelated engine evidence at ${relative}`);
    fs.unlinkSync(marker);
  }
  // The clone/submodule sources remain pristine; this host contract is only for
  // the discovery assertion above, not part of their pinned baseline commit.
  fs.unlinkSync(path.join(source, 'ENGINE.md'));

  function installed(form) {
    const host = path.join(fixture, `${form}-host`); init(host);
    write(host, 'AGENTS.md', '# Host instructions\nKeep host-owned content.\n');
    const baseline = path.join(host, '.opencaw');
    if (form === 'clone') command('git', ['clone', '-q', source, baseline]);
    else git(host, 'submodule', 'add', '-q', source, '.opencaw');
    check(!fs.existsSync(path.join(baseline, 'runtime/bubo/.git')), `${form}: nonrecursive installation begins with an uninitialized Bubo dependency`);
    const missing = runtime(baseline, ['resource', 'proof-to-model/manifest.schema.json']);
    check(missing.status === 1 && /not initialized.*submodule update --init --recursive --checkout runtime\/bubo/.test(missing.stderr), `${form}: production resource lookup fails with recorded initialization instructions`);
    check(!fs.existsSync(path.join(host, 'STYLE.md')), `${form}: adapter startup fixture deliberately has no host style policy`);
    for (const workflow of ['proof-to-model', 'model-to-animation', 'model-to-action']) {
      for (const operation of ['init', 'finish']) {
        const help = command(bash, [path.join(baseline, 'commands', workflow + '.sh'), operation, '--help'], baseline);
        check(help.status === 0 && help.stdout.includes(workflow + ' <operation>') && help.stdout.includes('Operations:'), `${form}: ${workflow} ${operation} --help remains available before dependency initialization or policy setup`);
      }
      const production = command(process.execPath, [path.join(baseline, 'commands/lib/bubo-host-adapter.cjs'), workflow, 'init', '--root', host], baseline, true);
      check(production.status === 1 && /not initialized.*submodule update --init --recursive --checkout runtime\/bubo/.test(production.stderr)
        && !/STYLE\.md|not built|Missing value|Cannot find module/.test(production.stderr), `${form}: real ${workflow} adapter reports dependency initialization before policy or build work`);
    }
    for (const operation of ['setup', 'inspect', 'generate']) {
      const help = command(bash, [path.join(baseline, 'commands/bubo-media.sh'), operation, '--help'], baseline);
      check(help.status === 0 && ['setup', 'inspect', 'generate', '--manifest'].every(word => help.stdout.includes(word)), `${form}: media ${operation} help remains available before initialization or policy setup`);
      const production = command(process.execPath, [path.join(baseline, 'commands/lib/bubo-media-adapter.cjs'), operation, '--root', host, '--task', 'fixture', '--manifest', 'missing.json'], baseline, true);
      check(production.status === 1 && /not initialized.*submodule update --init --recursive --checkout runtime\/bubo/.test(production.stderr)
        && !/Cannot find module|MEDIA\.md|Missing manifest/.test(production.stderr), `${form}: actual media ${operation} reports the missing dependency before policy or state work`);
    }
    check(!fs.existsSync(path.join(baseline, '.cache')), `${form}: help and rejected production adapters create no durable task or policy state`);
    shell(baseline, 'create-host-ai-scaffold.sh');
    for (const name of ['SYSTEM_MEMORY', 'MEMORY', 'REPO_MAP', 'RULES', 'DEBUG']) {
      check(fs.existsSync(path.join(baseline, '.cache', name + '.md')), `${form}: missing Bubo does not block ${name} scaffold creation`);
    }
    check(fs.readFileSync(path.join(host, 'AGENTS.md'), 'utf8').includes('Keep host-owned content.'), `${form}: scaffold preserves host instructions`);
    const memoryBefore = digest(path.join(baseline, '.cache/MEMORY.md'));
    shell(baseline, 'create-host-ai-scaffold.sh');
    equal(digest(path.join(baseline, '.cache/MEMORY.md')), memoryBefore, `${form}: repeated uninitialized scaffold preserves memory bytes`);
    check(!fs.existsSync(path.join(baseline, 'runtime/bubo/.git')), `${form}: startup never initializes a dependency implicitly`);
    const engine = require(path.join(baseline, 'commands/lib/engine-contract.cjs'));
    equal(engine.resolve(host).effectiveEngine, 'THREEJS', `${form}: uninitialized startup resolves the default engine`);
    engine.generate(host, 'UNITY');
    equal(engine.resolve(host).existingEngines, [], `${form}: selected engine resolves before dependency initialization`);

    if (form === 'submodule') git(host, 'submodule', 'update', '--init', '--recursive', '--checkout', '--', '.opencaw');
    else shell(baseline, 'initialize-bubo-runtime.sh');
    equal(git(path.join(baseline, 'runtime/bubo'), 'rev-parse', 'HEAD'), pinned, `${form}: recursive initialization selects the recorded gitlink rather than newer upstream HEAD`);
    const admitted = runtime(baseline, ['resource', 'proof-to-model/manifest.schema.json']);
    equal(admitted.status, 0, `${form}: actual resource admission succeeds after recorded recursive initialization`);
    equal(runtime(baseline, ['resource', 'media/catalog.json']).status, 0, `${form}: recursive initialization admits exact media catalog metadata`);
    equal(runtime(baseline, ['resource', 'media/voice/worker.py']).status, 0, `${form}: source resource admission resolves audited voice worker bytes without executing them`);
    const unbuilt = runtime(baseline, ['verify']);
    check(unbuilt.status === 1 && /not built.*build-bubo-runtime\.sh explicitly/.test(unbuilt.stderr), `${form}: native launch admission requires an explicit build`);
    check(!fs.existsSync(path.join(baseline, 'runtime/bubo/artifacts')), `${form}: failed native admission performs no build or installation`);
    equal(engine.resolve(host).existingEngines, [], `${form}: dependency development packages do not conflict with host UNITY selection`);
    for (const relative of ['runtime/bubo', 'runtime/game', 'runtime/bubo-extra', 'nested/runtime/bubo']) {
      const marker = path.join(host, relative, 'project.godot'); write(host, path.relative(host, marker), '[application]\n');
      rejects(() => engine.resolve(host), /GODOT.*conflicts/, `${form}: host engine evidence remains visible at ${relative}`);
      fs.unlinkSync(marker);
    }
    git(path.join(baseline, 'runtime/bubo'), 'checkout', '-q', '--detach', newer);
    const drift = runtime(baseline, ['resource', 'proof-to-model/manifest.schema.json']);
    check(drift.status === 1 && /revision mismatch/.test(drift.stderr), `${form}: an initialized but unrecorded newer revision is rejected`);
    shell(baseline, 'initialize-bubo-runtime.sh');
    equal(git(path.join(baseline, 'runtime/bubo'), 'rev-parse', 'HEAD'), pinned, `${form}: explicit initialization restores the recorded pin after drift`);
    const resource = path.join(baseline, 'runtime/bubo', resourceKey);
    fs.appendFileSync(resource, '\nchanged fixture resource\n');
    const dirty = runtime(baseline, ['resource', 'proof-to-model/manifest.schema.json']);
    check(dirty.status === 1 && /source is modified/.test(dirty.stderr), `${form}: tracked dependency mutations are rejected before resource consumption`);
    git(path.join(baseline, 'runtime/bubo'), 'checkout', '--', resourceKey);
    equal(runtime(baseline, ['resource', 'proof-to-model/manifest.schema.json']).status, 0, `${form}: restored resource bytes are freshly admitted`);
    const originalLock = fs.readFileSync(path.join(baseline, 'runtime/bubo.lock.json'));
    git(path.join(baseline, 'runtime/bubo'), 'checkout', '-q', '--detach', newer);
    write(baseline, 'runtime/bubo.lock.json', JSON.stringify({ ...lock, revision: newer }));
    const gitlink = runtime(baseline, ['resource', 'proof-to-model/manifest.schema.json']);
    check(gitlink.status === 1 && /recorded parent gitlink disagree/.test(gitlink.stderr), `${form}: changing both lock and checkout cannot bypass the recorded parent gitlink`);
    fs.writeFileSync(path.join(baseline, 'runtime/bubo.lock.json'), originalLock);
    shell(baseline, 'initialize-bubo-runtime.sh');
    check(fs.existsSync(path.join(baseline, '.cache/MEMORY.md')), `${form}: recorded initialization preserves existing durable host state`);
    return { form, recordedRevision: pinned, newerUpstream: newer };
  }
  const forms = [installed('clone'), installed('submodule')];
  const recursiveHost = path.join(fixture, 'recursive-clone-host'); fs.mkdirSync(recursiveHost);
  const recursiveBaseline = path.join(recursiveHost, '.opencaw');
  command('git', ['clone', '-q', '--recurse-submodules', source, recursiveBaseline]);
  equal(git(path.join(recursiveBaseline, 'runtime/bubo'), 'rev-parse', 'HEAD'), pinned, 'Documented recursive clone checks out the recorded nested dependency despite newer upstream HEAD');
  equal(runtime(recursiveBaseline, ['resource', 'proof-to-model/manifest.schema.json']).status, 0, 'Documented recursive clone immediately admits pinned source resources without building');
  const installedUpdate = command('git', ['-C', recursiveBaseline, 'submodule', 'update', '--init', '--recursive', '--checkout', '--', 'runtime/bubo']);
  equal(installedUpdate.status, 0, 'Documented direct-clone recursive update command operates on the recorded dependency');
  // A parent-level second update would reset .opencaw to the old host gitlink.
  // Exercise a real OpenCaw update and initialize Bubo from inside that updated
  // baseline so the new OpenCaw revision survives until the host records it.
  git(path.join(source, 'runtime/bubo'), 'fetch', '-q', 'origin');
  git(path.join(source, 'runtime/bubo'), 'checkout', '-q', '--detach', newer);
  write(source, 'runtime/bubo.lock.json', JSON.stringify({ ...lock, revision: newer }, null, 2));
  const updatedBaseline = commit(source, 'Reviewed baseline revision records its next dependency commit');
  for (const { form } of forms) {
    const host = path.join(fixture, `${form}-host`), baseline = path.join(host, '.opencaw');
    if (form === 'clone') git(baseline, 'pull', '--ff-only');
    else git(host, 'submodule', 'update', '--remote', '--checkout', '--', '.opencaw');
    git(baseline, 'submodule', 'update', '--init', '--recursive', '--checkout', '--', 'runtime/bubo');
    equal(git(baseline, 'rev-parse', 'HEAD'), updatedBaseline, `${form}: documented update retains the newer OpenCaw revision until the host records it`);
    equal(git(path.join(baseline, 'runtime/bubo'), 'rev-parse', 'HEAD'), newer, `${form}: documented update initializes the dependency recorded by the newer OpenCaw revision`);
    equal(runtime(baseline, ['resource', 'proof-to-model/manifest.schema.json']).status, 0, `${form}: updated lock, parent gitlink and resource remain consistent`);
    check(fs.existsSync(path.join(baseline, '.cache/MEMORY.md')), `${form}: updating the baseline preserves durable host memory`);
  }
  fs.writeFileSync(path.join(evidence, 'latest.json'), JSON.stringify({ schemaVersion: 1, status: 'pass', assertions: observations.length,
    platform: process.platform, nativeBuilds: 0, networkProtocolsAllowed: ['file'], forms, observations }, null, 2) + '\n');
  console.log(`Bubo installation tests passed (${observations.length} assertions; offline clone/submodule fixtures; no native builds).`);
  completed = true;
  }
} catch (error) {
  if (realMode) fs.writeFileSync(path.join(evidence, 'real-runtime-latest.json'), JSON.stringify({ schemaVersion: 1, mode: 'real-runtime',
    status: 'fail', assertions: observations.length, diagnostic: error.message, nativeBuilds: 0, observations }, null, 2) + '\n');
  throw error;
} finally {
  // Resolve and bound the target before recursive cleanup, including on Windows.
  const target = path.resolve(fixture), relative = path.relative(path.resolve(evidence), target);
  assert(relative.startsWith('fixture-') && !relative.includes(path.sep) && !path.isAbsolute(relative), 'Fixture cleanup must remain inside the installation evidence directory');
  if (completed) fs.rmSync(target, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  else console.error('Failed installation fixture preserved at ' + target);
}
