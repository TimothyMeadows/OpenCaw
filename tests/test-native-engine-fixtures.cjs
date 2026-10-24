'use strict';

// Fixture structure, simulated process checks and actual native results are
// separate evidence. Native process execution is not an operating-system sandbox.
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const engine = require('../commands/lib/engine-contract.cjs');
const ROOT = path.resolve(__dirname, '..');
const FIXTURES = path.join(__dirname, 'fixtures/engines');
const unrealFeatures = require('./lib/unreal-feature-fixtures.cjs');
const unityFeatures = require('./lib/unity-feature-fixtures.cjs');
const LOG_LIMIT = 512 * 1024;

function contained(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative !== '' && relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative);
}

function safeLocalFile(value, allowedRoot = ROOT) {
  if (!value || /[\x00-\x1f]/.test(value) || value.split(/[\\/]/).includes('..')) throw new Error('Fixture path contains traversal or control characters');
  const absolute = path.resolve(ROOT, value);
  if (!contained(allowedRoot, absolute)) throw new Error('Configured fixture must stay inside its repository-local fixture directory');
  let current = ROOT;
  for (const part of path.relative(ROOT, absolute).split(path.sep)) {
    current = path.join(current, part);
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error('Configured fixture must not traverse symbolic links');
  }
  if (!fs.statSync(absolute).isFile()) throw new Error('Configured fixture must be a file');
  if (!contained(fs.realpathSync(ROOT), fs.realpathSync(absolute)) || !contained(fs.realpathSync(allowedRoot), fs.realpathSync(absolute))) throw new Error('Configured fixture resolves outside its permitted directory');
  return absolute;
}

function executable(value, names, allowDll = false) {
  const candidates = value ? [value] : names;
  for (const candidate of candidates) {
    if (/[\x00-\x1f]/.test(candidate)) throw new Error('Executable selection contains control characters');
    const extensions = process.platform === 'win32' && !path.extname(candidate) ? ['', '.exe'] : [''];
    const directories = path.isAbsolute(candidate) || /[\\/]/.test(candidate) ? [''] : (process.env.PATH || '').split(path.delimiter);
    for (const directory of directories) {
      for (const extension of extensions) {
        const file = path.resolve(directory, candidate + extension);
        try {
          if (!fs.statSync(file).isFile()) continue;
          if (/\.(bat|cmd|ps1|sh)$/i.test(file)) throw new Error('Select a native executable, without a shell wrapper');
          if (/\.dll$/i.test(file) && !allowDll) throw new Error('A DLL is only supported for explicit Unreal Build Tool selection');
          if (process.platform !== 'win32') fs.accessSync(file, /\.dll$/i.test(file) ? fs.constants.R_OK : fs.constants.X_OK);
          return file;
        } catch (error) {
          if (!['ENOENT', 'ENOTDIR', 'EACCES'].includes(error.code)) throw error;
        }
      }
    }
  }
  return null;
}

function killTree(child) {
  if (!child.pid) return;
  if (process.platform === 'win32') {
    const taskkill = executable(process.env.SystemRoot ? path.join(process.env.SystemRoot, 'System32/taskkill.exe') : null, ['taskkill.exe']);
    cp.spawnSync(taskkill, ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore', timeout: 5000 });
  } else {
    try { process.kill(-child.pid, 'SIGKILL'); } catch (error) { if (error.code !== 'ESRCH') throw error; }
  }
}

function runProcess(command, args, options) {
  if (process.platform === 'win32' && !executable(process.env.SystemRoot ? path.join(process.env.SystemRoot, 'System32/taskkill.exe') : null, ['taskkill.exe'])) throw new Error('Native execution requires Windows process-tree cleanup support');
  return new Promise(resolve => {
    const started = Date.now();
    const log = fs.openSync(options.log, 'wx');
    let bytes = 0;
    let text = '';
    let timedOut = false;
    let cancelled = false;
    let spawnError = null;
    const child = cp.spawn(command, args, {
      cwd: options.cwd,
      env: { ...process.env, ...options.env },
      shell: false,
      windowsHide: true,
      detached: process.platform !== 'win32',
      stdio: ['ignore', 'pipe', 'pipe']
    });
    const consume = data => {
      const buffer = Buffer.from(data);
      const kept = buffer.subarray(0, Math.max(0, LOG_LIMIT - bytes));
      if (kept.length) { fs.writeSync(log, kept); text += kept.toString('utf8'); bytes += kept.length; }
    };
    child.stdout.on('data', consume);
    child.stderr.on('data', consume);
    const cancel = () => { cancelled = true; killTree(child); };
    const timer = setTimeout(() => { timedOut = true; killTree(child); }, options.timeoutMs);
    options.signal?.addEventListener('abort', cancel, { once: true });
    if (options.signal?.aborted) cancel();
    child.on('error', error => { spawnError = error.message; });
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      options.signal?.removeEventListener('abort', cancel);
      fs.closeSync(log);
      resolve({ code, signal, timedOut, cancelled, spawnError, text, logBytes: bytes, elapsedMs: Date.now() - started });
    });
  });
}

function readReport(file, fixture, minimumChecks, expectedVersion) {
  if (!fs.existsSync(file) || fs.statSync(file).size > LOG_LIMIT) throw new Error('Missing or oversized native report');
  const result = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (result.fixture !== fixture || result.status !== 'pass' || !Number.isInteger(result.checks) || result.checks < minimumChecks) throw new Error('Native report has a wrong identity, failed status or incomplete checks');
  if (typeof result.engineVersion !== 'string' || !result.engineVersion) throw new Error('Native report does not identify the actual engine version');
  if (expectedVersion && result.engineVersion !== expectedVersion) throw new Error('Actual Editor version does not match the configured project version');
  return result;
}

function inspectUnrealReport(file, testName) {
  if (!fs.existsSync(file) || fs.statSync(file).size > LOG_LIMIT * 8) throw new Error('Missing or oversized Unreal Automation report');
  const report = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (!Array.isArray(report.tests) || report.tests.length !== 1) throw new Error('Automation must discover exactly the selected fixture test');
  const test = report.tests[0];
  if ((test.fullTestPath || test.testDisplayName) !== testName || test.state !== 'Success') throw new Error('Selected Automation fixture did not pass');
  if (Number(report.failed || 0) !== 0 || Number(report.notRun || 0) !== 0) throw new Error('Automation report contains failed or unrun tests');
  if ((test.entries || []).some(entry => entry.event?.type === 'Error')) throw new Error('Automation test contains error events');
  return { tests: 1, testName, state: test.state };
}

function fixtureMetadata(name) {
  const directory = path.join(FIXTURES, name);
  const metadata = JSON.parse(fs.readFileSync(path.join(directory, 'fixture.json'), 'utf8'));
  assert.equal(metadata.schemaVersion, 1);
  assert.equal(metadata.engine.toLowerCase(), name);
  assert.ok(metadata.files.length > 0);
  for (const file of metadata.files) safeLocalFile(path.join(directory, file), directory);
  return metadata;
}

function copyFixture(source, destination) {
  const skipped = new Set(['Binaries', 'Intermediate', 'Saved', 'Library', 'Temp', '.godot', '.git']);
  fs.mkdirSync(destination, { recursive: true });
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) throw new Error('Fixture copies cannot contain symbolic links');
    if (skipped.has(entry.name)) continue;
    const from = path.join(source, entry.name);
    const to = path.join(destination, entry.name);
    if (entry.isDirectory()) copyFixture(from, to);
    else if (entry.isFile()) fs.copyFileSync(from, to, fs.constants.COPYFILE_EXCL);
    else throw new Error('Fixture contains an unsupported filesystem entry');
  }
}

function nativeFailure(result) {
  if (result.timedOut) return 'Native process exceeded its time budget';
  if (result.cancelled) return 'Native process was cancelled';
  if (result.spawnError) return 'Native process could not start: ' + result.spawnError;
  if (result.code !== 0) return 'Native process exited ' + result.code;
  return null;
}

const hash = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const verdict = (id, phase, status, reason, details = {}) => ({ engine: id, phase, status, reason, ...details });

async function unity(context) {
  const editor = executable(process.env.OPENCAW_UNITY_EDITOR, ['Unity', 'Unity.exe']);
  if (!editor) return [verdict('UNITY', 'native-smoke', 'blocked', 'Matching Unity Editor is unavailable on PATH or OPENCAW_UNITY_EDITOR')];
  const version = process.env.OPENCAW_UNITY_VERSION;
  if (!/^\d+\.\d+\.\d+[A-Za-z0-9._-]*$/.test(version || '')) return [verdict('UNITY', 'native-smoke', 'blocked', 'Set exact OPENCAW_UNITY_VERSION to the installed licensed Editor version')];
  const target = process.env.OPENCAW_UNITY_BUILD_TARGET || '';
  const targets = { StandaloneWindows64: ['win32', 'fixture.exe'], StandaloneLinux64: ['linux', 'fixture.x86_64'], StandaloneOSX: ['darwin', 'fixture.app'] };
  if (target && !targets[target]) throw new Error('Unsupported OPENCAW_UNITY_BUILD_TARGET');
  const directory = path.join(context.temp, 'unity');
  copyFixture(path.join(FIXTURES, 'unity'), directory);
  fs.mkdirSync(path.join(directory, 'ProjectSettings'));
  fs.writeFileSync(path.join(directory, 'ProjectSettings/ProjectVersion.txt'), 'm_EditorVersion: ' + version + '\n');
  engine.generate(directory, 'UNITY');
  engine.requireEngine(directory, 'UNITY');
  const report = path.join(directory, 'editor-report.json');
  const buildOutput = target ? path.join(directory, 'build', targets[target][1]) : '';
  if (target) fs.mkdirSync(path.dirname(buildOutput));
  const result = await context.run(editor, ['-batchmode', '-nographics', '-noUpm', '-projectPath', directory, '-executeMethod', 'OpenCawFixture.Run', '-logFile', path.join(directory, 'editor.log')], {
    cwd: directory, log: path.join(directory, 'editor-process.log'),
    env: { OPENCAW_FIXTURE_REPORT: report, OPENCAW_FIXTURE_BUILD_TARGET: target, OPENCAW_FIXTURE_BUILD_OUTPUT: buildOutput }
  });
  const error = nativeFailure(result);
  if (error) {
    const nativeLog = fs.existsSync(path.join(directory, 'editor.log')) ? fs.readFileSync(path.join(directory, 'editor.log'), 'utf8').slice(-LOG_LIMIT) : '';
    const licensing = /no valid (?:Unity Editor )?licen[cs]e|licen[cs](?:e|ing)[^\n]{0,90}(?:unavailable|not found|not active|failed)/i.test(result.text + nativeLog);
    return [verdict('UNITY', 'native-smoke', licensing ? 'blocked' : 'fail', licensing ? 'Installed Editor license is unavailable; no terms were accepted' : error)];
  }
  const checked = readReport(report, 'opencaw-native-unity', 5, version);
  const results = [verdict('UNITY', 'native-smoke', 'pass', 'Actual Editor lifecycle/serialization checks passed', { checks: checked.checks, engineVersion: checked.engineVersion, reportSha256: hash(report) })];
  if (!target) { results.push(verdict('UNITY', 'build', 'not-run', 'No OPENCAW_UNITY_BUILD_TARGET selected')); return results; }
  if (checked.buildStatus === 'blocked') { results.push(verdict('UNITY', 'build', 'blocked', checked.buildReason)); return results; }
  if (checked.buildStatus !== 'pass' || !fs.existsSync(buildOutput)) return [...results, verdict('UNITY', 'build', 'fail', 'Unity build output or successful BuildReport is missing')];
  results.push(verdict('UNITY', 'build', 'pass', 'Actual BuildReport succeeded', { target }));
  if (targets[target][0] !== process.platform) { results.push(verdict('UNITY', 'player', 'not-run', 'Selected build is for another host platform')); return results; }
  let player = buildOutput;
  if (target === 'StandaloneOSX') player = path.join(buildOutput, 'Contents/MacOS', fs.readdirSync(path.join(buildOutput, 'Contents/MacOS'))[0]);
  const playerReport = path.join(directory, 'player-report.json');
  const played = await context.run(player, ['-batchmode', '-nographics', '-logFile', path.join(directory, 'player.log')], { cwd: directory, log: path.join(directory, 'player-process.log'), env: { OPENCAW_FIXTURE_REPORT: playerReport } });
  if (nativeFailure(played)) return [...results, verdict('UNITY', 'player', 'fail', nativeFailure(played))];
  let playerChecked;
  try { playerChecked = readReport(playerReport, 'opencaw-native-unity-player', 5, version); }
  catch (error) { return [...results, verdict('UNITY', 'player', 'fail', error.message)]; }
  results.push(verdict('UNITY', 'player', 'pass', 'Built player completed component lifecycle checks', { checks: playerChecked.checks, reportSha256: hash(playerReport), playerSha256: hash(player) }));
  return results;
}

async function godot(context) {
  const editor = executable(process.env.OPENCAW_GODOT_EDITOR, ['godot', 'godot4', 'Godot', 'godot.exe']);
  if (!editor) return [verdict('GODOT', 'native-smoke', 'blocked', 'Godot 4 Editor is unavailable on PATH or OPENCAW_GODOT_EDITOR')];
  const directory = path.join(context.temp, 'godot');
  copyFixture(path.join(FIXTURES, 'godot'), directory);
  engine.generate(directory, 'GODOT');
  engine.requireEngine(directory, 'GODOT');
  const version = await context.run(editor, ['--version'], { cwd: directory, log: path.join(directory, 'version.log') });
  if (nativeFailure(version)) throw new Error(nativeFailure(version));
  if (!/^4\./m.test(version.text.trim())) return [verdict('GODOT', 'native-smoke', 'blocked', 'Fixture requires a matching Godot 4 Editor')];
  const imported = await context.run(editor, ['--headless', '--path', directory, '--editor', '--import'], { cwd: directory, log: path.join(directory, 'import.log') });
  if (nativeFailure(imported)) throw new Error(nativeFailure(imported));
  const report = path.join(directory, 'runtime-report.json');
  const result = await context.run(editor, ['--headless', '--path', directory, '--script', 'res://harness.gd'], { cwd: directory, log: path.join(directory, 'runtime.log'), env: { OPENCAW_FIXTURE_REPORT: report, OPENCAW_FIXTURE_FORCE_FAILURE: '0' } });
  if (nativeFailure(result)) throw new Error(nativeFailure(result));
  const checked = readReport(report, 'opencaw-native-godot', 5);
  const failureReport = path.join(directory, 'intentional-failure-report.json');
  const failed = await context.run(editor, ['--headless', '--path', directory, '--script', 'res://harness.gd'], { cwd: directory, log: path.join(directory, 'intentional-failure.log'), env: { OPENCAW_FIXTURE_REPORT: failureReport, OPENCAW_FIXTURE_FORCE_FAILURE: '1' } });
  if (failed.code === 0 || failed.timedOut || failed.spawnError || !fs.existsSync(failureReport) || JSON.parse(fs.readFileSync(failureReport, 'utf8')).status !== 'fail') throw new Error('Godot intentional failure did not produce a failing report and exit');
  const results = [verdict('GODOT', 'native-smoke', 'pass', 'Actual node lifecycle/state checks and intentional failure exit passed', { checks: checked.checks, engineVersion: checked.engineVersion, reportSha256: hash(report) })];
  const preset = process.env.OPENCAW_GODOT_EXPORT_PRESET;
  if (!preset) { results.push(verdict('GODOT', 'export', 'not-run', 'No OPENCAW_GODOT_EXPORT_PRESET selected')); return results; }
  const presets = { Linux: ['linux', 'fixture.x86_64'], Windows: ['win32', 'fixture.exe'], macOS: ['darwin', 'fixture.app'] };
  if (!presets[preset]) throw new Error('Unsupported OPENCAW_GODOT_EXPORT_PRESET');
  const output = path.join(directory, 'export', presets[preset][1]);
  fs.mkdirSync(path.dirname(output));
  const exported = await context.run(editor, ['--headless', '--path', directory, '--export-debug', preset, output], { cwd: directory, log: path.join(directory, 'export.log') });
  if (nativeFailure(exported)) {
    if (/export templates[^\n]{0,150}(?:not found|missing|installed)|no export template|cannot find[^\n]{0,80}template/i.test(exported.text)) {
      results.push(verdict('GODOT', 'export', 'blocked', 'Matching installed export templates are unavailable')); return results;
    }
    return [...results, verdict('GODOT', 'export', 'fail', nativeFailure(exported))];
  }
  if (!fs.existsSync(output)) return [...results, verdict('GODOT', 'export', 'fail', 'Godot reported export success without the selected output')];
  results.push(verdict('GODOT', 'export', 'pass', 'Actual Godot export completed', { preset }));
  if (presets[preset][0] !== process.platform) { results.push(verdict('GODOT', 'player', 'not-run', 'Export target differs from the current host')); return results; }
  let player = output;
  if (preset === 'macOS') player = path.join(output, 'Contents/MacOS', fs.readdirSync(path.join(output, 'Contents/MacOS'))[0]);
  const playerReport = path.join(directory, 'export-player-report.json');
  const played = await context.run(player, ['--headless'], { cwd: directory, log: path.join(directory, 'export-player.log'), env: { OPENCAW_FIXTURE_REPORT: playerReport, OPENCAW_FIXTURE_FORCE_FAILURE: '0' } });
  if (nativeFailure(played)) return [...results, verdict('GODOT', 'player', 'fail', nativeFailure(played))];
  let playerChecked;
  try { playerChecked = readReport(playerReport, 'opencaw-native-godot', 5); }
  catch (error) { return [...results, verdict('GODOT', 'player', 'fail', error.message)]; }
  results.push(verdict('GODOT', 'player', 'pass', 'Exported player independently completed lifecycle/state checks', { checks: playerChecked.checks, reportSha256: hash(playerReport), playerSha256: hash(player) }));
  return results;
}

async function unreal(context) {
  const selected = process.env.OPENCAW_UNREAL_PROJECT;
  const sourceProject = selected ? safeLocalFile(selected, path.join(FIXTURES, 'unreal')) : null;
  if (sourceProject && path.extname(sourceProject) !== '.uproject') throw new Error('Unreal fixture selection must be a .uproject');
  const editor = executable(process.env.OPENCAW_UNREAL_EDITOR, ['UnrealEditor-Cmd', 'UnrealEditor', 'UnrealEditor.exe']);
  if (!editor) return [verdict('UNREAL', 'native-smoke', 'blocked', 'Matching Unreal Editor is unavailable on PATH or OPENCAW_UNREAL_EDITOR')];
  if (!sourceProject) return [verdict('UNREAL', 'native-smoke', 'blocked', 'Explicit repository-local OPENCAW_UNREAL_PROJECT fixture selection is required')];
  const version = process.env.OPENCAW_UNREAL_VERSION;
  if (!/^5\.\d+(?:\.\d+)?$/.test(version || '')) return [verdict('UNREAL', 'native-smoke', 'blocked', 'OPENCAW_UNREAL_VERSION must identify the matching Unreal 5 installation')];
  const ubt = executable(process.env.OPENCAW_UNREAL_UBT, ['UnrealBuildTool', 'UnrealBuildTool.exe'], true);
  if (!ubt) return [verdict('UNREAL', 'native-smoke', 'blocked', 'Matching installed Unreal Build Tool is unavailable')];
  const dotnet = /\.dll$/i.test(ubt) ? executable(null, ['dotnet']) : null;
  if (/\.dll$/i.test(ubt) && !dotnet) return [verdict('UNREAL', 'native-smoke', 'blocked', 'Installed dotnet is required to invoke the selected UBT DLL')];
  const directory = path.join(context.temp, 'unreal');
  copyFixture(path.dirname(sourceProject), directory);
  const project = path.join(directory, path.basename(sourceProject));
  const content = JSON.parse(fs.readFileSync(project, 'utf8'));
  if (content.EngineAssociation && content.EngineAssociation !== version) throw new Error('Unreal fixture EngineAssociation differs from the configured version');
  content.EngineAssociation = version;
  fs.writeFileSync(project, JSON.stringify(content, null, 2) + '\n');
  engine.generate(directory, 'UNREAL');
  engine.requireEngine(directory, 'UNREAL');
  const platform = { win32: 'Win64', linux: 'Linux', darwin: 'Mac' }[process.platform];
  if (!platform) return [verdict('UNREAL', 'native-smoke', 'blocked', 'Unsupported fixture build host')];
  const buildArgs = ['OpenCawNativeFixtureEditor', platform, 'Development', '-Project=' + project, '-WaitMutex', '-NoHotReloadFromIDE'];
  const built = await context.run(dotnet || ubt, dotnet ? [ubt, ...buildArgs] : buildArgs, { cwd: directory, log: path.join(directory, 'build.log') });
  if (nativeFailure(built)) {
    if (/SDK[^\n]{0,100}(?:not installed|not found|missing)|(?:Visual Studio|compiler|toolchain)[^\n]{0,100}(?:not found|missing|must be installed)/i.test(built.text)) return [verdict('UNREAL', 'native-smoke', 'blocked', 'Required native compiler or platform SDK is unavailable')];
    throw new Error(nativeFailure(built));
  }
  const reportDirectory = path.join(directory, 'automation-report');
  const executed = await context.run(editor, [project, '-unattended', '-nop4', '-nosplash', '-NullRHI', '-stdout', '-FullStdOutLogOutput', '-ExecCmds=Automation RunTests OpenCaw.Fixtures.LifecycleState', '-TestExit=Automation Test Queue Empty', '-ReportExportPath=' + reportDirectory], { cwd: directory, log: path.join(directory, 'automation.log') });
  if (nativeFailure(executed)) throw new Error(nativeFailure(executed));
  const actualVersion = executed.text.match(/Engine Version:\s*(5\.\d+\.\d+)/);
  if (!actualVersion || (version.split('.').length === 2 ? !actualVersion[1].startsWith(version + '.') : actualVersion[1] !== version)) throw new Error('Unreal startup did not identify the configured matching engine version');
  const report = path.join(reportDirectory, 'index.json');
  const checked = inspectUnrealReport(report, 'OpenCaw.Fixtures.LifecycleState');
  return [verdict('UNREAL', 'native-smoke', 'pass', 'Actual UBT build and selected Automation lifecycle/state fixture passed', { ...checked, engineVersion: actualVersion[1], reportSha256: hash(report) }), verdict('UNREAL', 'package', 'not-run', 'This source-only transient-world fixture does not cook a binary map or certify packaged content')];
}

async function runnerChecks(temp) {
  let checks = 0;
  for (const name of ['unity', 'godot', 'unreal']) { fixtureMetadata(name); checks++; }
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(FIXTURES, 'unity/Packages/manifest.json'), 'utf8')).dependencies, {}); checks++;
  const ordinary = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'unreal/OpenCawNativeFixture.uproject'), 'utf8'));
  assert.equal(ordinary.Modules[0].Name, 'OpenCawNativeFixture'); checks++;
  const features = unrealFeatures.manifest();
  for (const file of features.files) safeLocalFile(path.join(unrealFeatures.DIRECTORY, file), unrealFeatures.DIRECTORY);
  checks++;
  const unityMeta = unityFeatures.manifest();
  for (const file of unityMeta.files) safeLocalFile(path.join(unityFeatures.DIRECTORY, file), unityFeatures.DIRECTORY);
  checks++;
  const report = path.join(temp, 'simulated-report.json');
  const good = { fixture: 'simulated', status: 'pass', checks: 2, engineVersion: 'simulation' };
  fs.writeFileSync(report, JSON.stringify(good));
  assert.equal(readReport(report, 'simulated', 2).engineVersion, 'simulation'); checks++;
  for (const invalid of [{ ...good, fixture: 'other' }, { ...good, checks: 0 }, { ...good, status: 'fail' }, { ...good, engineVersion: '' }]) {
    fs.writeFileSync(report, JSON.stringify(invalid));
    assert.throws(() => readReport(report, 'simulated', 2)); checks++;
  }
  assert.throws(() => readReport(path.join(temp, 'missing.json'), 'simulated', 1)); checks++;
  fs.writeFileSync(report, '{corrupt'); assert.throws(() => readReport(report, 'simulated', 1)); checks++;
  fs.writeFileSync(report, JSON.stringify(good)); assert.throws(() => readReport(report, 'simulated', 2, 'wrong')); checks++;
  const automation = path.join(temp, 'simulated-automation.json');
  const automatic = { failed: 0, notRun: 0, tests: [{ fullTestPath: 'Fixture.Test', state: 'Success', entries: [] }] };
  fs.writeFileSync(automation, JSON.stringify(automatic)); assert.equal(inspectUnrealReport(automation, 'Fixture.Test').tests, 1); checks++;
  for (const invalid of [{ ...automatic, tests: [] }, { ...automatic, failed: 1 }, { ...automatic, tests: [{ fullTestPath: 'Fixture.Test', state: 'Fail' }] }]) {
    fs.writeFileSync(automation, JSON.stringify(invalid)); assert.throws(() => inspectUnrealReport(automation, 'Fixture.Test')); checks++;
  }
  assert.throws(() => safeLocalFile('../outside.uproject', path.join(FIXTURES, 'unreal'))); checks++;
  assert.throws(() => safeLocalFile('README.md', path.join(FIXTURES, 'unreal'))); checks++;
  const linkTarget = path.join(temp, 'link-target');
  fs.mkdirSync(linkTarget);
  fs.writeFileSync(path.join(linkTarget, 'fixture.json'), '{}');
  const linked = path.join(temp, 'linked');
  try {
    fs.symlinkSync(linkTarget, linked, process.platform === 'win32' ? 'junction' : 'dir');
    assert.throws(() => safeLocalFile(path.join(linked, 'fixture.json'), temp)); checks++;
    assert.throws(() => safeLocalFile(path.join(linked, 'fixture.json'), linked)); checks++;
  } catch (error) {
    if (!['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) throw error;
    console.log('NOT-RUN simulated symlink escape checks: this host cannot create the controlled link');
  }
  assert.equal(executable(path.join(temp, 'missing-editor'), []), null); checks++;
  const literal = 'argument with spaces;$(not-a-shell)';
  const passed = await runProcess(process.execPath, ['-e', 'console.log(process.argv[1])', literal], { cwd: temp, log: path.join(temp, 'simulated-success.log'), timeoutMs: 5000 });
  assert.equal(passed.code, 0); assert.equal(passed.text.trim(), literal); checks++;
  const failed = await runProcess(process.execPath, ['-e', 'process.exit(7)'], { cwd: temp, log: path.join(temp, 'simulated-failure.log'), timeoutMs: 5000 });
  assert.equal(failed.code, 7); checks++;
  const large = await runProcess(process.execPath, ['-e', 'process.stdout.write("x".repeat(1048576))'], { cwd: temp, log: path.join(temp, 'simulated-large.log'), timeoutMs: 5000 });
  assert.equal(large.code, 0); assert.equal(large.logBytes, LOG_LIMIT); checks++;
  const timed = await runProcess(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { cwd: temp, log: path.join(temp, 'simulated-timeout.log'), timeoutMs: 150 });
  assert.equal(timed.timedOut, true); assert.notEqual(timed.code, 0); checks++;
  const controller = new AbortController();
  const cancelling = runProcess(process.execPath, ['-e', 'setInterval(()=>{},1000)'], { cwd: temp, log: path.join(temp, 'simulated-cancel.log'), timeoutMs: 5000, signal: controller.signal });
  setTimeout(() => controller.abort(), 150);
  const cancelled = await cancelling; assert.equal(cancelled.cancelled, true); checks++;
  const grandchildPid = path.join(temp, 'grandchild.pid');
  const grandchildCode = 'require("fs").writeFileSync(process.argv[1], String(process.pid)); setInterval(()=>{},1000)';
  const parentCode = 'require("child_process").spawn(process.execPath, ["-e", process.argv[1], process.argv[2]], {stdio:"inherit", windowsHide:true}); setInterval(()=>{},1000)';
  const tree = await runProcess(process.execPath, ['-e', parentCode, grandchildCode, grandchildPid], { cwd: temp, log: path.join(temp, 'simulated-tree-timeout.log'), timeoutMs: 800 });
  assert.equal(tree.timedOut, true);
  assert.ok(fs.existsSync(grandchildPid), 'Controlled descendant did not start before the timeout');
  const descendant = Number(fs.readFileSync(grandchildPid, 'utf8'));
  let alive = false;
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      process.kill(descendant, 0); alive = true;
      if (process.platform === 'linux') {
        try { if (/^\d+ \(.+\) Z /.test(fs.readFileSync('/proc/' + descendant + '/stat', 'utf8'))) alive = false; }
        catch (error) { if (error.code !== 'ENOENT') throw error; alive = false; }
      }
    } catch (error) { if (error.code !== 'ESRCH') throw error; alive = false; }
    if (!alive) break;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.equal(alive, false, 'Owned descendant survived timeout process-tree cleanup'); checks++;
  // Simulate failed native invocations through the complete feature runner.
  // Exit status must defeat any implied report success; these are not engines.
  const priorSelection = process.env.OPENCAW_UNREAL_FEATURE_PROJECT;
  const priorVersion = process.env.OPENCAW_UNREAL_VERSION;
  try {
    process.env.OPENCAW_UNREAL_FEATURE_PROJECT = path.join(unrealFeatures.DIRECTORY, 'OpenCawFeatureFixture.uproject');
    process.env.OPENCAW_UNREAL_VERSION = '5.8';
    const api = { safeLocalFile, executable: () => process.execPath, copyFixture, nativeFailure, inspectUnrealReport };
    const failureTemp = path.join(temp, 'simulated-feature-build'); fs.mkdirSync(failureTemp);
    const failures = await unrealFeatures.run({ temp: failureTemp, run: async () => ({ code: 7, text: '' }) }, api);
    assert.equal(failures.length, 12); assert.ok(failures.every(result => result.status === 'fail' && /exited 7/.test(result.reason))); checks++;
    const processTemp = path.join(temp, 'simulated-feature-process'); fs.mkdirSync(processTemp);
    let calls = 0;
    const processes = await unrealFeatures.run({ temp: processTemp, run: async () => (++calls === 1 ? { code: 0, text: '' } : { code: 9, text: 'Engine Version: 5.8.0' }) }, api);
    const executed = processes.filter(result => !features.cases.find(test => test.name === result.test).requires || Object.keys(features.cases.find(test => test.name === result.test).requires).length === 0);
    assert.ok(executed.length > 0); assert.ok(executed.every(result => result.status === 'fail' && /exited 9/.test(result.reason))); checks++;
  } finally {
    if (priorSelection === undefined) delete process.env.OPENCAW_UNREAL_FEATURE_PROJECT; else process.env.OPENCAW_UNREAL_FEATURE_PROJECT = priorSelection;
    if (priorVersion === undefined) delete process.env.OPENCAW_UNREAL_VERSION; else process.env.OPENCAW_UNREAL_VERSION = priorVersion;
  }
  return checks;
}

function cleanup(temp) {
  const parent = path.resolve(__dirname);
  const absolute = path.resolve(temp);
  if (path.dirname(absolute) !== parent || !path.basename(absolute).startsWith('.native-engine-fixtures-') || fs.lstatSync(absolute).isSymbolicLink()) throw new Error('Refusing cleanup outside the owned temporary test directory');
  fs.rmSync(absolute, { recursive: true, force: true });
}

async function main(args = process.argv.slice(2)) {
  for (const arg of args) if (!['--structure-only', '--require-native'].includes(arg)) throw new Error('Unknown native fixture option: ' + arg);
  const seconds = Number(process.env.OPENCAW_NATIVE_TIMEOUT_SECONDS || 180);
  if (!Number.isFinite(seconds) || seconds < 1 || seconds > 600) throw new Error('Native timeout must be between 1 and 600 seconds');
  const temp = fs.mkdtempSync(path.join(__dirname, '.native-engine-fixtures-'));
  const abort = new AbortController();
  const cancel = () => abort.abort();
  process.on('SIGINT', cancel);
  process.on('SIGTERM', cancel);
  try {
    const checks = await runnerChecks(temp);
    console.log('PASS fixture structure and simulated-process/report checks: ' + checks + ' (no native engine claim)');
    const context = { temp, timeoutMs: seconds * 1000, run: (command, values, options) => runProcess(command, values, { ...options, timeoutMs: seconds * 1000, signal: abort.signal }) };
    const results = [];
    for (const [id, action] of [['UNITY', unity], ['GODOT', godot], ['UNREAL', unreal]]) {
      if (args.includes('--structure-only')) results.push(verdict(id, 'native-smoke', 'not-run', 'Structure-only mode selected'));
      else if (abort.signal.aborted) results.push(verdict(id, 'native-smoke', 'not-run', 'Runner cancelled before this engine'));
      else {
        try { results.push(...await action(context)); }
        catch (error) { results.push(verdict(id, 'native-smoke', 'fail', error.message)); }
      }
    }
    if (args.includes('--structure-only')) {
      for (const test of unrealFeatures.manifest().cases) results.push(verdict('UNREAL', 'native-feature', 'not-run', 'Structure-only mode selected', { test: test.name }));
    } else if (!abort.signal.aborted) {
      try { results.push(...await unrealFeatures.run(context, { safeLocalFile, executable, copyFixture, nativeFailure, inspectUnrealReport })); }
      catch (error) { results.push(verdict('UNREAL', 'native-feature', 'fail', error.message)); }
    }
    if (args.includes('--structure-only')) {
      for (const test of unityFeatures.manifest().cases) results.push(verdict('UNITY', test.execution === 'manual' ? 'manual-native' : 'native-feature', 'not-run', 'Structure-only mode selected', { test: test.id }));
      for (const test of unityFeatures.manifest().manual) results.push(verdict('UNITY', 'manual-native', 'not-run', test.reason, { test: test.id }));
    } else if (!abort.signal.aborted) {
      try { results.push(...await unityFeatures.run(context, { safeLocalFile, executable, copyFixture, nativeFailure })); }
      catch (error) { results.push(verdict('UNITY', 'native-feature', 'fail', error.message)); }
    }
    for (const result of results) console.log(result.status.toUpperCase() + ' ' + result.engine + ' ' + result.phase + (result.test ? ' ' + result.test : '') + ': ' + result.reason);
    const nativePasses = results.filter(result => result.phase === 'native-smoke' && result.status === 'pass').length;
    const featurePasses = results.filter(result => result.engine === 'UNREAL' && result.phase === 'native-feature' && result.status === 'pass').length;
    const unityPasses = results.filter(result => result.engine === 'UNITY' && result.phase === 'native-feature' && result.status === 'pass').length;
    const nativeComplete = nativePasses === 3 && featurePasses === unrealFeatures.manifest().cases.length && unityPasses === unityFeatures.manifest().cases.filter(test => test.execution !== 'manual').length;
    const summary = { fixtureStructure: 'pass', simulatedProcessChecks: checks, nativeEnginesPassed: nativePasses, unrealFeatureCasesPassed: featurePasses, unityFeatureCasesPassed: unityPasses, nativeAcceptance: nativeComplete ? 'automated smoke and Unreal/Unity feature cases passed; manual/service/player/visual/device acceptance remains separately scoped' : 'incomplete', results };
    console.log(JSON.stringify(summary, null, 2));
    return results.some(result => result.status === 'fail') || abort.signal.aborted || (args.includes('--require-native') && !nativeComplete) ? 1 : 0;
  } finally {
    process.removeListener('SIGINT', cancel);
    process.removeListener('SIGTERM', cancel);
    cleanup(temp);
  }
}

module.exports = { main, runProcess, readReport, inspectUnrealReport, safeLocalFile, executable, fixtureMetadata, copyFixture, nativeFailure, cleanup };
if (require.main === module) main().then(code => { process.exitCode = code; }).catch(error => { console.error('FAIL native fixture runner: ' + error.message); process.exitCode = 1; });
