'use strict';

// Internal test harness, not an engine selector or production command.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const engine = require('../../commands/lib/engine-contract.cjs');
const ROOT = path.resolve(__dirname, '../..');
const DIRECTORY = path.join(ROOT, 'tests/fixtures/engines/unreal/features');
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function manifest() {
  const value = JSON.parse(fs.readFileSync(path.join(DIRECTORY, 'fixture.json'), 'utf8'));
  if (value.schemaVersion !== 1 || value.engine !== 'UNREAL' || value.cases.length !== 12 || new Set(value.cases.map(c => c.name)).size !== 12) throw new Error('Invalid Unreal feature manifest');
  return value;
}

function configuration(file) {
  const output = {};
  let selected = false;
  for (const raw of fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith(';')) continue;
    if (line.startsWith('[')) { selected = line === '[OpenCaw.UnrealFeatures]'; continue; }
    if (!selected) continue;
    const match = line.match(/^([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*?)\s*$/);
    if (!match || Object.hasOwn(output, match[1])) throw new Error('Invalid or duplicate Unreal feature configuration');
    output[match[1]] = match[2].replace(/^"(.*)"$/, '$1');
  }
  return output;
}

function prerequisites(test, config, projectDirectory, safeFile) {
  const identities = [];
  for (const [key, kind] of Object.entries(test.requires)) {
    const value = config[key];
    if (!value) return { blocked: 'Real native fixture prerequisite is missing: ' + key };
    if (/[\x00-\x1f]/.test(value)) throw new Error('Control character in native feature setting');
    if (kind === 'tag') {
      if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(value)) throw new Error('Invalid fixture tag: ' + key);
    } else if (kind === 'plugin') {
      if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(value)) throw new Error('Invalid fixture plugin name');
      const descriptor = path.join(projectDirectory, 'Plugins', 'GameFeatures', value, value + '.uplugin');
      if (!fs.existsSync(descriptor)) return { blocked: 'Native-authored Game Feature plugin is missing: ' + key };
      safeFile(descriptor, projectDirectory);
      JSON.parse(fs.readFileSync(descriptor, 'utf8'));
      identities.push({ key, sha256: sha(descriptor) });
    } else {
      const pattern = kind === 'map' ? /^\/Game\/([A-Za-z0-9_]+(?:\/[A-Za-z0-9_]+)*)$/ : /^\/Game\/([A-Za-z0-9_]+(?:\/[A-Za-z0-9_]+)*)(?:\.([A-Za-z0-9_]+))?$/;
      const match = value.match(pattern);
      if (!match || (match[2] && match[2] !== path.posix.basename(match[1]))) throw new Error('Fixture assets must be project-owned /Game packages: ' + key);
      const file = path.join(projectDirectory, 'Content', match[1] + (kind === 'map' ? '.umap' : '.uasset'));
      if (!fs.existsSync(file)) return { blocked: 'Native-authored asset is missing: ' + key };
      safeFile(file, projectDirectory);
      identities.push({ key, sha256: sha(file) });
    }
  }
  return { identities };
}

function inspectEvidence(file, testName, nonce, startedAt, inspectReport) {
  if (!/^[a-f0-9-]{36}$/.test(nonce)) throw new Error('Invalid native report invocation identity');
  const stat = fs.statSync(file);
  if (stat.mtimeMs < startedAt - 2000 || stat.mtimeMs > Date.now() + 2000) throw new Error('Stale native feature report timestamp');
  const checked = inspectReport(file, testName);
  const report = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  const entries = report.tests[0].entries;
  const marker = 'OpenCawFeatureEvidence run=' + nonce + ' case=' + testName;
  if (!Array.isArray(entries) || entries.filter(entry => entry.event?.message === marker && entry.event?.type === 'Info').length !== 1) throw new Error('Native feature report lacks the fresh invocation marker');
  return { ...checked, runId: nonce, reportSha256: sha(file) };
}

function unavailableBuild(text) {
  if (/SDK[^\n]{0,100}(?:not installed|not found|missing)|(?:Visual Studio|compiler|toolchain)[^\n]{0,100}(?:not found|missing|must be installed)/i.test(text)) return 'Native compiler/platform SDK unavailable';
  // Availability diagnostics only. Header errors, invalid Build.cs and source
  // compilation failures are failures, even if they mention a selected module.
  if (/Unable to find plugin ['"]?(?:GameplayAbilities|MassEntity|GameFeatures|Niagara|PCG)\b|(?:Plugin|Module) ['"](?:GameplayAbilities|MassEntity|GameFeatures|Niagara|PCG)['"][^\n]{0,100}(?:could not be found|is not installed)/i.test(text)) return 'An explicitly selected native fixture plugin/module is unavailable';
  return null;
}

async function run(context, api) {
  const meta = manifest();
  const result = (test, status, reason, extra = {}) => ({ engine: 'UNREAL', phase: 'native-feature', test: test.name, status, reason, ...extra });
  const all = (status, reason) => meta.cases.map(test => result(test, status, reason));
  const selected = process.env.OPENCAW_UNREAL_FEATURE_PROJECT;
  if (!selected) return all('blocked', 'Select repository-local OPENCAW_UNREAL_FEATURE_PROJECT; this suite requires UE ' + meta.engineMinor);
  const sourceProject = api.safeLocalFile(selected, DIRECTORY);
  if (path.basename(sourceProject) !== meta.project) throw new Error('Unexpected Unreal feature project identity');
  const editor = api.executable(process.env.OPENCAW_UNREAL_EDITOR, ['UnrealEditor-Cmd', 'UnrealEditor', 'UnrealEditor.exe']);
  if (!editor) return all('blocked', 'Matching Unreal Editor is unavailable');
  const version = process.env.OPENCAW_UNREAL_VERSION;
  if (!/^5\.\d+(?:\.\d+)?$/.test(version || '') || !(version === meta.engineMinor || version.startsWith(meta.engineMinor + '.'))) return all('blocked', 'Feature fixture requires explicitly matching UE ' + meta.engineMinor + '; no host version was changed');
  const ubt = api.executable(process.env.OPENCAW_UNREAL_UBT, ['UnrealBuildTool', 'UnrealBuildTool.exe'], true);
  const dotnet = ubt && /\.dll$/i.test(ubt) ? api.executable(null, ['dotnet']) : null;
  if (!ubt || (/\.dll$/i.test(ubt) && !dotnet)) return all('blocked', 'Matching Unreal Build Tool/native dotnet prerequisite is unavailable');
  const platform = { win32: 'Win64', linux: 'Linux', darwin: 'Mac' }[process.platform];
  if (!platform) return all('blocked', 'Unsupported native build host');
  const directory = path.join(context.temp, 'unreal-features');
  api.copyFixture(path.dirname(sourceProject), directory);
  const project = path.join(directory, meta.project);
  const content = JSON.parse(fs.readFileSync(project, 'utf8'));
  if (content.EngineAssociation !== meta.engineMinor && content.EngineAssociation !== version) throw new Error('Feature project EngineAssociation conflicts with the fixture contract');
  content.EngineAssociation = version;
  fs.writeFileSync(project, JSON.stringify(content, null, 2) + '\n');
  engine.generate(directory, 'UNREAL');
  engine.requireEngine(directory, 'UNREAL');
  const config = configuration(path.join(directory, 'Config/DefaultGame.ini'));
  const checks = meta.cases.map(test => prerequisites(test, config, directory, api.safeLocalFile));
  const args = [meta.target, platform, 'Development', '-Project=' + project, '-WaitMutex', '-NoHotReloadFromIDE'];
  const build = await context.run(dotnet || ubt, dotnet ? [ubt, ...args] : args, { cwd: directory, log: path.join(directory, 'feature-build.log') });
  const failure = api.nativeFailure(build);
  if (failure) {
    const unavailable = unavailableBuild(build.text);
    return all(unavailable ? 'blocked' : 'fail', unavailable || failure);
  }
  const results = [];
  for (let index = 0; index < meta.cases.length; index++) {
    const test = meta.cases[index];
    const prerequisite = checks[index];
    if (prerequisite.blocked) { results.push(result(test, 'blocked', prerequisite.blocked)); continue; }
    const nonce = crypto.randomUUID();
    const reportDirectory = path.join(directory, 'report-' + nonce);
    const startedAt = Date.now();
    const executed = await context.run(editor, [project, '-unattended', '-nop4', '-nosplash', '-NullRHI', '-stdout', '-FullStdOutLogOutput', '-ExecCmds=Automation RunTests ' + test.name, '-TestExit=Automation Test Queue Empty', '-ReportExportPath=' + reportDirectory], { cwd: directory, log: path.join(directory, nonce + '.log'), env: { OPENCAW_UNREAL_FEATURE_RUN: nonce } });
    const failed = api.nativeFailure(executed);
    if (failed) { results.push(result(test, 'fail', failed)); continue; }
    try {
      const actual = executed.text.match(/Engine Version:\s*(5\.\d+\.\d+)/)?.[1];
      if (!actual || (version.split('.').length === 2 ? !actual.startsWith(version + '.') : actual !== version)) throw new Error('Actual Unreal startup version does not match the selected fixture');
      const checked = inspectEvidence(path.join(reportDirectory, 'index.json'), test.name, nonce, startedAt, api.inspectUnrealReport);
      results.push(result(test, 'pass', 'Actual UBT build and fresh selected Automation result', { ...checked, engineVersion: actual, assets: prerequisite.identities, acceptance: test.limit }));
    } catch (error) { results.push(result(test, 'fail', error.message)); }
  }
  return results;
}

module.exports = { DIRECTORY, manifest, configuration, prerequisites, inspectEvidence, unavailableBuild, run };
