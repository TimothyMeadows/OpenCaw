'use strict';

// Host orchestration only. MAUI owns compilation and native platform tooling.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const engines = require('./engine-contract.cjs');
const BASE = path.resolve(__dirname, '../..');
const TEMPLATE = path.join(BASE, '.packaging/maui/template');
const CONFIG = 'web-game-package.json';
const OWNER = '.opencaw-maui-host.json';
const SNAPSHOT = '.opencaw-web-snapshot.json';
const PENDING = 'pending-transaction.json';
const TARGETS = Object.freeze({
  WINDOWS: { framework: 'net10.0-windows10.0.19041.0', hosts: ['win32'], workloads: ['maui', 'maui-windows'], rids: ['win-x64', 'win-arm64', 'win-x86'], formats: ['folder', 'msix'] },
  MACOS: { framework: 'net10.0-maccatalyst', hosts: ['darwin'], workloads: ['maui', 'maui-maccatalyst', 'maccatalyst'], rids: ['maccatalyst-arm64', 'maccatalyst-x64'], formats: ['app', 'pkg'] },
  ANDROID: { framework: 'net10.0-android', hosts: ['win32', 'darwin'], workloads: ['maui', 'maui-android', 'android'], rids: ['android-arm64', 'android-x64'], formats: ['apk', 'aab'] },
  IOS: { framework: 'net10.0-ios', hosts: ['darwin'], workloads: ['maui', 'maui-ios', 'ios'], rids: ['ios-arm64'], formats: ['ipa'] }
});
const fail = message => { throw new Error(message); };
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const hashFile = file => digest(fs.readFileSync(file));
const encode = value => JSON.stringify(value, null, 2) + '\n';
const writeNew = (file, value) => fs.writeFileSync(file, value, { flag: 'wx' });
const overlap = (a, b) => a === b || a.startsWith(b + '/') || b.startsWith(a + '/');

function relative(value, label) {
  if (typeof value !== 'string' || !value || value.includes('\\') || /[:\x00-\x1f<>"|?*;$%@]/.test(value) || path.posix.isAbsolute(value)) fail(`${label} must be a portable project-relative path without MSBuild metacharacters.`);
  const parts = value.split('/');
  if (parts.some(p => !p || p === '.' || p === '..' || /[. ]$/.test(p) || /^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)/i.test(p))) fail(`${label} contains unsafe path components.`);
  if (parts.some(p => ['.git', '.opencaw', 'node_modules'].includes(p.toLowerCase()))) fail(`${label} cannot target Git, OpenCaw or dependencies.`);
  return value;
}
function confined(root, value, label) {
  relative(value, label);
  return engines.inside(root, value, label).absolute;
}
function regular(file, label) {
  if (!fs.existsSync(file) || !fs.lstatSync(file).isFile() || fs.lstatSync(file).isSymbolicLink()) fail(`${label} must be a regular existing file.`);
}
function tree(dir, options = {}) {
  if (!fs.existsSync(dir) || !fs.lstatSync(dir).isDirectory() || fs.lstatSync(dir).isSymbolicLink()) fail('Expected a regular directory.');
  const entries = [], folded = new Set(); let total = 0, visited = 0;
  function visit(current, prefix) {
    if (prefix.split('/').length > 32 || ++visited > 30000) fail('Asset/source directory depth/count exceeds the bound.');
    for (const name of fs.readdirSync(current).sort()) {
      const namePath = prefix ? `${prefix}/${name}` : name;
      const file = path.join(current, name), stat = fs.lstatSync(file);
      if (stat.isSymbolicLink()) fail('Links/junctions are not permitted in asset/source trees.');
      if (options.exclude?.(namePath)) continue;
      relative(namePath, 'Asset/source name');
      const key = namePath.toLowerCase();
      if (folded.has(key)) fail('Case-insensitive path collision in asset/source tree.');
      folded.add(key);
      if (stat.isDirectory()) visit(file, namePath);
      else if (stat.isFile()) {
        total += stat.size;
        if (total > 1024 * 1024 * 1024 || entries.length >= 20000) fail('Asset/source tree exceeds the 1 GiB / 20,000-file bound.');
        entries.push({ path: namePath, size: stat.size, sha256: hashFile(file) });
      } else fail('Only regular files/directories are permitted.');
    }
  }
  visit(dir, '');
  return entries;
}
const fingerprint = entries => digest(JSON.stringify(entries));
function validateConfig(c) {
  const keys = ['schemaVersion', 'profile', 'appId', 'title', 'displayVersion', 'buildNumber', 'hostDirectory', 'webRoot', 'entry'];
  if (!c || typeof c !== 'object' || Array.isArray(c) || Object.keys(c).some(k => !keys.includes(k)) || keys.some(k => !Object.hasOwn(c, k))) fail('Invalid packaging configuration fields.');
  if (c.schemaVersion !== 1 || c.profile !== 'MAUI') fail('Expected packaging schemaVersion 1 and profile MAUI.');
  if (!/^[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*){2,}$/.test(c.appId || '') || c.appId.length > 150) fail('Use a lowercase reverse-DNS appId, e.g. com.example.game.');
  if (typeof c.title !== 'string' || !c.title.trim() || c.title.length > 80 || /[\x00-\x1f$@%]/.test(c.title)) fail('Invalid application title; MSBuild expressions are not allowed.');
  if (!/^\d{1,3}\.\d{1,2}\.\d{1,2}$/.test(c.displayVersion)) fail('displayVersion must be numeric major.minor.patch (up to 999.99.99).');
  if (!Number.isSafeInteger(c.buildNumber) || c.buildNumber < 1 || c.buildNumber > 65535) fail('buildNumber must be an integer from 1 to 65535.');
  for (const k of ['hostDirectory', 'webRoot', 'entry']) relative(c[k], k);
  if (overlap(c.hostDirectory.toLowerCase(), c.webRoot.toLowerCase())) fail('Native host and web source cannot overlap.');
  if (!/\.html?$/i.test(c.entry)) fail('Entry must be a local HTML file.');
  return c;
}
function selection(root, opt) {
  const result = engines.resolve(root, opt.engineEvidence ? { evidence: opt.engineEvidence } : {});
  if (result.packaging?.profile !== 'MAUI') fail('The effective engine uses its native exporter; MAUI packaging requires a registered web engine.');
  return result;
}
function pathTypes(root, value, kind, label) {
  const target = confined(root, value, label);
  const parts = value.split('/'); let current = root;
  for (let i = 0; i < parts.length; i++) {
    current = path.join(current, parts[i]);
    let stat; try { stat = fs.lstatSync(current); } catch (error) { if (error.code === 'ENOENT') break; throw error; }
    if (stat.isSymbolicLink() || (i < parts.length - 1 && !stat.isDirectory()) || (i === parts.length - 1 && kind === 'directory' && !stat.isDirectory()) || (i === parts.length - 1 && kind === 'file' && !stat.isFile())) fail(`${label} has a link or invalid file/directory parent type.`);
  }
  return target;
}
function ownedAncestor(root, value) {
  let current = path.dirname(path.join(root, value));
  while (current !== root) {
    if (fs.existsSync(path.join(current, OWNER))) fail('Packaging paths cannot nest inside another owned native host.');
    current = path.dirname(current);
  }
}
function nativeBuildRoots(root, host) {
  let visited = 0;
  function visit(dir, depth = 0) {
    if (depth > 64 || ++visited > 50000) fail('Native output directory scan exceeded its bound.');
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const file = path.join(dir, entry.name);
      if (entry.isSymbolicLink()) fail('Native bin/obj cannot contain links/junctions.');
      if (entry.isDirectory()) visit(file, depth + 1);
      else if (!entry.isFile()) fail('Native bin/obj requires regular files/directories.');
    }
  }
  for (const name of ['bin', 'obj']) {
    const value = path.relative(root, path.join(host, name)).split(path.sep).join('/');
    const file = pathTypes(root, value, 'directory', 'Native build output');
    if (fs.existsSync(file)) visit(file);
  }
}
function stateDirectory(root, configRelative) {
  return engines.inside(root, `.opencaw/.cache/packaging/${digest(configRelative).slice(0, 16)}`, 'Packaging state').absolute;
}
function assertNoPending(c) {
  const file = statePath(c, PENDING);
  if (fs.existsSync(file)) fail('A pending packaging transaction requires explicit recover --config FILE before further operations. Inspect abandoned locks first.');
}
function context(root, opt = {}) {
  root = fs.realpathSync(root);
  const selected = selection(root, opt);
  const configRelative = relative(opt.config || CONFIG, 'Configuration');
  const configPath = pathTypes(root, configRelative, 'file', 'Configuration');
  regular(configPath, 'Configuration');
  const config = validateConfig(json(configPath));
  for (const name of [configRelative, config.hostDirectory, config.webRoot]) {
    if (selected.outputScope && !name.startsWith(selected.outputScope + '/')) fail('Packaging paths must remain within the recorded engine override scope.');
  }
  if (overlap(configRelative.toLowerCase(), config.hostDirectory.toLowerCase()) || overlap(configRelative.toLowerCase(), config.webRoot.toLowerCase())) fail('Configuration cannot overlap host/web content.');
  const host = pathTypes(root, config.hostDirectory, 'directory', 'Native host');
  const web = pathTypes(root, config.webRoot, 'directory', 'Web source');
  for (const value of [configRelative, config.hostDirectory, config.webRoot]) ownedAncestor(root, value);
  // Never write the installed baseline, even from a maintainer checkout.
  if (BASE.toLowerCase().startsWith(root.toLowerCase() + path.sep) && (overlap(host.toLowerCase(), BASE.toLowerCase()) || overlap(web.toLowerCase(), BASE.toLowerCase()))) fail('Packaging cannot write or stage the shared baseline.');
  if (fs.existsSync(host)) {
    const owner = path.join(host, OWNER);
    regular(owner, 'Native host ownership');
    const receipt = json(owner);
    if (receipt.schemaVersion !== 1 || receipt.producer !== 'OpenCaw/MAUI' || receipt.config !== configRelative || receipt.appId !== config.appId) fail('Native host belongs to another configuration/application.');
  }
  const state = stateDirectory(root, configRelative);
  const result = { root, selected, configRelative, configPath, config, host, web, state };
  assertNoPending(result);
  return result;
}
function engineIdentity(s) {
  return { effectiveEngine: s.effectiveEngine, contractSha256: s.contractSha256, definitionSha256: s.definitionSha256, registrySha256: s.registrySha256, evidence: s.evidence || null, taskSha256: s.taskSha256 || null };
}
function nativeFiles(host) {
  nativeBuildRoots(host, host);
  const entries = tree(host, { exclude: p => /^(?:bin|obj)(?:\/|$)/.test(p) || p === SNAPSHOT || p === 'Resources/Raw/wwwroot' || p.startsWith('Resources/Raw/wwwroot/') });
  if (entries.some(e => e.path !== OWNER && e.path.endsWith('/' + OWNER))) fail('Native host contains another owned nested host.');
  return entries;
}
function currentIdentity(c, properties) {
  const entries = nativeFiles(c.host);
  if (properties !== undefined) {
    const entry = entries.find(e => e.path === 'OpenCawGame.props');
    if (!entry) fail('Generated application properties are missing.');
    entry.size = Buffer.byteLength(properties); entry.sha256 = digest(properties);
  }
  return {
    configSha256: hashFile(c.configPath), engine: engineIdentity(selection(c.root, c.selected.evidence ? { engineEvidence: c.selected.evidence } : {})),
    orchestratorSha256: hashFile(__filename), templateSha256: fingerprint(tree(TEMPLATE)), nativeSha256: fingerprint(entries),
    webFiles: tree(c.web)
  };
}
function verifySnapshot(c) {
  const file = path.join(c.host, SNAPSHOT); regular(file, 'Web snapshot');
  const snapshot = json(file), now = currentIdentity(c);
  if (snapshot.schemaVersion !== 1 || JSON.stringify(snapshot.identity) !== JSON.stringify(now)) fail('Packaging inputs changed; review changes and explicitly sync the web build again.');
  const staged = tree(path.join(c.host, 'Resources/Raw/wwwroot'));
  if (JSON.stringify(staged) !== JSON.stringify(now.webFiles)) fail('Staged web assets were changed or have foreign files; preserve/review them before sync.');
  return { snapshot, identity: now };
}
function acquire(c, recovering = false) {
  engines.inside(c.root, path.relative(c.root, c.state).split(path.sep).join('/'), 'Packaging state');
  fs.mkdirSync(c.state, { recursive: true });
  const locks = [path.join(path.dirname(c.state), 'workspace.lock'), path.join(c.state, 'operation.lock')], acquired = [];
  try {
    for (const file of locks) { fs.mkdirSync(file); acquired.push(file); }
    if (!recovering) assertNoPending(c);
  } catch (error) {
    for (const file of acquired.reverse()) fs.rmdirSync(file);
    if (error.code === 'EEXIST') fail('Another packaging operation or an abandoned operation lock exists; verify no active operation before manually removing only its empty lock directory.');
    throw error;
  }
  return () => { for (const file of acquired.reverse()) fs.rmdirSync(file); };
}
async function locked(c, action, recovering = false) {
  const release = acquire(c, recovering);
  try { return await action(); } finally { release(); }
}
function statePath(c, suffix) {
  return engines.inside(c.root, path.relative(c.root, path.join(c.state, suffix)).split(path.sep).join('/'), 'Packaging state').absolute;
}
const xml = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));
function props(c) {
  return `<Project>\n  <PropertyGroup>\n    <MauiVersion>10.0.20</MauiVersion>\n    <ApplicationTitle>${xml(c.title)}</ApplicationTitle>\n    <ApplicationId>${xml(c.appId)}</ApplicationId>\n    <ApplicationDisplayVersion>${c.displayVersion}</ApplicationDisplayVersion>\n    <ApplicationVersion>${c.buildNumber}</ApplicationVersion>\n    <OpenCawDefaultFile>${xml(c.entry)}</OpenCawDefaultFile>\n  </PropertyGroup>\n</Project>\n`;
}
function describe(file) {
  if (!fs.existsSync(file)) return null;
  const stat = fs.lstatSync(file);
  if (stat.isSymbolicLink()) fail('Transaction paths cannot contain links.');
  if (stat.isDirectory()) return { type: 'directory', sha256: fingerprint(tree(file)) };
  if (stat.isFile()) return { type: 'file', sha256: hashFile(file) };
  fail('Transaction paths require regular files/directories.');
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function checkedTransaction(c, pointer) {
  if (pointer.schemaVersion !== 1 || typeof pointer.journal !== 'string') fail('Invalid pending transaction pointer.');
  const file = engines.inside(c.root, pointer.journal, 'Transaction journal').absolute;
  if (!file.startsWith(c.state + path.sep)) fail('Transaction journal belongs to another configuration.');
  regular(file, 'Transaction journal');
  if (hashFile(file) !== pointer.sha256) fail('Pending transaction journal changed; inspect it without retrying.');
  const journal = json(file), directory = path.dirname(file);
  if (journal.schemaVersion !== 1 || journal.config !== c.configRelative || !['init','sync'].includes(journal.operation) || !Array.isArray(journal.entries) || !journal.entries.length || journal.entries.length > 3) fail('Invalid transaction journal.');
  for (const entry of journal.entries) {
    const target = pathTypes(c.root, entry.target, entry.after.type, 'Transaction destination');
    for (const name of ['staged', 'backup']) {
      const value = engines.inside(c.root, entry[name], 'Transaction data').absolute;
      if (!value.startsWith(directory + path.sep)) fail('Transaction data leaves its owned version directory.');
    }
    if (overlap(path.relative(c.root, target).split(path.sep).join('/'), path.relative(c.root, directory).split(path.sep).join('/'))) fail('Transaction destination overlaps its journal.');
  }
  return { journal, directory };
}
function rollback(c, journal) {
  for (const entry of [...journal.entries].reverse()) {
    const target = pathTypes(c.root, entry.target, entry.after.type, 'Transaction destination');
    const staged = engines.inside(c.root, entry.staged, 'Transaction stage').absolute;
    const backup = engines.inside(c.root, entry.backup, 'Transaction backup').absolute;
    const actual = describe(target), saved = describe(backup);
    if (same(actual, entry.before) && saved === null) continue; // Not started or already restored.
    if (same(actual, entry.after)) {
      if (fs.existsSync(staged)) fail('Ambiguous transaction: both staged and published bytes exist.');
      fs.renameSync(target, staged);
    } else if (!same(actual, entry.before) && actual !== null) fail('Transaction destination has foreign changes; automatic rollback refused.');
    if (entry.before !== null) {
      if (saved !== null) {
        if (!same(saved, entry.before) || fs.existsSync(target)) fail('Transaction backup changed or destination is occupied.');
        fs.renameSync(backup, target);
      } else if (!same(describe(target), entry.before)) fail('Transaction prior bytes are unavailable; inspect the journal.');
    } else if (fs.existsSync(target)) fail('Transaction fresh destination is occupied.');
  }
}
function clearPending(c, pointer) {
  const file = statePath(c, PENDING); regular(file, 'Pending transaction');
  if (!same(json(file), pointer)) fail('Pending transaction identity changed.');
  fs.unlinkSync(file); // The immutable pointer copy and journal remain in its version.
}
function transact(c, directory, operation, pairs, validate) {
  const entries = pairs.map(([target, staged, role]) => ({
    role, target: path.relative(c.root, target).split(path.sep).join('/'),
    staged: path.relative(c.root, staged).split(path.sep).join('/'),
    backup: path.relative(c.root, path.join(directory, 'previous-' + role)).split(path.sep).join('/'),
    before: describe(target), after: describe(staged)
  }));
  if (operation === 'init' && entries.some(entry => entry.before !== null)) fail('Initialization destinations already exist; nothing was overwritten.');
  const journal = { schemaVersion: 1, operation, config: c.configRelative, entries };
  const journalFile = path.join(directory, 'transaction.json'); writeNew(journalFile, encode(journal));
  const pointer = { schemaVersion: 1, journal: path.relative(c.root, journalFile).split(path.sep).join('/'), sha256: hashFile(journalFile) };
  writeNew(path.join(directory, 'pending-reference.json'), encode(pointer));
  writeNew(statePath(c, PENDING), encode(pointer));
  let committed = false;
  try {
    for (const entry of entries) {
      const target = pathTypes(c.root, entry.target, entry.after.type, 'Transaction destination');
      if (!same(describe(target), entry.before)) fail('Destination changed before transaction publication.');
      fs.mkdirSync(path.dirname(target), { recursive: true });
      if (entry.before !== null) fs.renameSync(target, path.join(c.root, entry.backup));
      fs.renameSync(path.join(c.root, entry.staged), target);
    }
    validate();
    writeNew(path.join(directory, 'transaction-result.json'), encode({ schemaVersion: 1, status: 'committed' }));
    committed = true;
  } catch (error) {
    let restored = false;
    try { rollback(c, journal); restored = true; } catch (rollbackError) {
      writeNew(path.join(directory, 'recovery-required.json'), encode({ schemaVersion: 1, status: 'recovery-required', reason: 'Rollback could not safely restore owned bytes; inspect the transaction and run recover.' }));
    }
    if (restored) {
      writeNew(path.join(directory, 'transaction-result.json'), encode({ schemaVersion: 1, status: 'rolled-back' }));
      clearPending(c, pointer);
    }
    throw error;
  }
  if (committed) clearPending(c, pointer);
  return journal;
}
function init(root, opt) {
  root = fs.realpathSync(root); const selected = selection(root, opt);
  const configRelative = relative(opt.config || CONFIG, 'Configuration');
  const configPath = pathTypes(root, configRelative, 'file', 'Configuration');
  if (fs.existsSync(configPath)) fail('Configuration already exists; edit it explicitly and use sync.');
  const config = validateConfig({ schemaVersion: 1, profile: 'MAUI', appId: opt.appId, title: opt.title, displayVersion: '1.0.0', buildNumber: 1, hostDirectory: opt.output || 'platforms/maui', webRoot: opt.webRoot || 'dist', entry: opt.entry || 'index.html' });
  if (selected.outputScope && [configRelative, config.hostDirectory, config.webRoot].some(p => !p.startsWith(selected.outputScope + '/'))) fail('Packaging paths must remain inside the engine override scope.');
  if ([config.hostDirectory, config.webRoot].some(p => overlap(configRelative.toLowerCase(), p.toLowerCase()))) fail('Configuration cannot overlap host/web content.');
  const host = pathTypes(root, config.hostDirectory, 'directory', 'Native host');
  pathTypes(root, config.webRoot, 'directory', 'Web source');
  for (const value of [configRelative, config.hostDirectory, config.webRoot]) ownedAncestor(root, value);
  if (fs.existsSync(host)) fail('Native output already exists; choose a fresh directory. Nothing was overwritten.');
  if (BASE.toLowerCase().startsWith(root.toLowerCase() + path.sep) && overlap(host.toLowerCase(), BASE.toLowerCase())) fail('Native host cannot be written inside the shared baseline.');
  const files = tree(TEMPLATE);
  if (!files.some(f => f.path === 'GameHost.csproj')) fail('MAUI template is incomplete.');
  const c = { root, selected, configRelative, configPath, config, host, state: stateDirectory(root, configRelative) };
  const release = acquire(c);
  try {
    if (fs.existsSync(host) || fs.existsSync(configPath)) fail('Initialization destinations already exist; nothing was overwritten.');
    for (const value of [configRelative, config.hostDirectory, config.webRoot]) ownedAncestor(root, value);
    const id = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}`;
    const version = statePath(c, `initializations/${id}`); fs.mkdirSync(version, { recursive: true });
    const staged = path.join(version, 'host'); fs.mkdirSync(staged);
    for (const file of files) {
      const target = path.join(staged, file.path); fs.mkdirSync(path.dirname(target), { recursive: true });
      writeNew(target, fs.readFileSync(path.join(TEMPLATE, file.path)));
    }
    writeNew(path.join(staged, 'OpenCawGame.props'), props(config));
    writeNew(path.join(staged, OWNER), encode({ schemaVersion: 1, producer: 'OpenCaw/MAUI', config: configRelative, appId: config.appId, templateSha256: fingerprint(files) }));
    const configStage = path.join(version, 'config.json'); writeNew(configStage, encode(config));
    if (fingerprint(tree(TEMPLATE)) !== fingerprint(files)) fail('Native template changed during initialization.');
    transact(c, version, 'init', [[host, staged, 'host'], [configPath, configStage, 'config']], () => {
      if (hashFile(configPath) !== digest(encode(config))) fail('Initialized configuration changed.');
    });
    return { schemaVersion: 1, profile: 'MAUI', config: configRelative, hostDirectory: config.hostDirectory, platforms: Object.keys(TARGETS), compiled: false, next: 'Build the static web game, then run sync.' };
  } finally { release(); }
}
async function sync(root, opt) {
  const c = context(root, opt);
  return locked(c, async () => {
    regular(path.join(c.host, 'GameHost.csproj'), 'Native project');
    regular(confined(c.web, c.config.entry, 'Web entry'), 'Web entry');
    const destination = pathTypes(c.root, `${c.config.hostDirectory}/Resources/Raw/wwwroot`, 'directory', 'Staged web assets');
    const snapshotFile = pathTypes(c.root, `${c.config.hostDirectory}/${SNAPSHOT}`, 'file', 'Web snapshot');
    if (fs.existsSync(snapshotFile)) regular(snapshotFile, 'Existing asset ownership snapshot');
    if (fs.existsSync(destination)) {
      const existing = tree(destination);
      if (existing.length) {
        regular(snapshotFile, 'Existing asset ownership snapshot');
        if (!same(existing, json(snapshotFile).identity?.webFiles)) fail('Existing staged assets were changed or have foreign files; nothing was replaced.');
      }
    }
    const propFile = pathTypes(c.root, `${c.config.hostDirectory}/OpenCawGame.props`, 'file', 'Generated application properties');
    regular(propFile, 'Generated application properties');
    const before = currentIdentity(c), propertyBytes = props(c.config), identity = currentIdentity(c, propertyBytes);
    if (!identity.webFiles.length) fail('No web build assets were found.');
    const id = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}`;
    const version = statePath(c, `snapshots/${id}`); fs.mkdirSync(version, { recursive: true });
    const stage = path.join(version, 'wwwroot'); fs.mkdirSync(stage);
    for (const f of identity.webFiles) {
      const file = path.join(stage, f.path); fs.mkdirSync(path.dirname(file), { recursive: true });
      writeNew(file, fs.readFileSync(path.join(c.web, f.path)));
    }
    if (!same(tree(stage), identity.webFiles) || !same(currentIdentity(c), before)) fail('Web/native inputs changed during sync; retry after inspecting the source.');
    const snapshot = { schemaVersion: 1, id, identity };
    const stagedProps = path.join(version, 'OpenCawGame.props'), stagedSnapshot = path.join(version, 'snapshot-to-publish.json');
    writeNew(stagedProps, propertyBytes); writeNew(stagedSnapshot, encode(snapshot));
    writeNew(path.join(version, 'snapshot.json'), encode(snapshot));
    transact(c, version, 'sync', [[propFile, stagedProps, 'props'], [destination, stage, 'wwwroot'], [snapshotFile, stagedSnapshot, 'snapshot']], () => verifySnapshot(c));
    return { schemaVersion: 1, synchronized: true, snapshot: id, files: identity.webFiles.length, bytes: identity.webFiles.reduce((n, f) => n + f.size, 0), compiled: false };
  });
}
async function recover(root, opt = {}) {
  if (opt.engineEvidence) fail('recover does not accept engine-evidence; it restores only the original hash-owned transaction journal.');
  root = fs.realpathSync(root);
  const configRelative = relative(opt.config || CONFIG, 'Configuration');
  const c = { root, configRelative, state: stateDirectory(root, configRelative) };
  return locked(c, async () => {
    const pending = statePath(c, PENDING); regular(pending, 'Pending transaction');
    const pointer = json(pending), { journal, directory } = checkedTransaction(c, pointer);
    const resultFile = path.join(directory, 'transaction-result.json');
    let status = fs.existsSync(resultFile) ? json(resultFile).status : null;
    if (status === 'committed') {
      for (const entry of journal.entries) if (!same(describe(path.join(root, entry.target)), entry.after)) fail('Committed transaction output changed; recovery refused.');
    } else {
      rollback(c, journal);
      if (!fs.existsSync(resultFile)) writeNew(resultFile, encode({ schemaVersion: 1, status: 'rolled-back' }));
      status = 'rolled-back';
    }
    clearPending(c, pointer);
    return { schemaVersion: 1, recovered: true, status, config: configRelative, compiled: false };
  }, true);
}
function targetOptions(opt) {
  const target = String(opt.target || 'WINDOWS').toUpperCase(), def = TARGETS[target];
  if (!def) fail('Target must be WINDOWS, MACOS, ANDROID or IOS. Linux and TV are unsupported.');
  const rid = opt.rid || def.rids[0], format = opt.format || def.formats[0];
  if (!def.rids.includes(rid) || !def.formats.includes(format)) fail('Unsupported runtime identifier or package format for selected target.');
  return { target, def, rid, format };
}
function probe(args, root) {
  const r = cp.spawnSync('dotnet', args, { cwd: root, encoding: 'utf8', timeout: 30000, maxBuffer: 2 * 1024 * 1024, windowsHide: true, env: { ...process.env, DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE: 'true', DOTNET_SKIP_FIRST_TIME_EXPERIENCE: '1', DOTNET_NOLOGO: '1' } });
  return { ok: !r.error && r.status === 0, output: r.stdout || '' };
}
function doctor(root, opt) {
  const selected = selection(root, opt), { target, def } = targetOptions(opt);
  const version = probe(['--version'], root), workloads = version.ok ? probe(['workload', 'list'], root) : { ok: false, output: '' };
  const installed = workloads.ok ? workloads.output.split(/\r?\n/).map(line => line.trim().split(/\s+/)).filter(parts => def.workloads.includes(parts[0]) && /^[a-zA-Z0-9.+/_-]{1,100}$/.test(parts[1] || '')).map(parts => ({ id: parts[0], manifestVersion: parts[1] })) : [];
  const sdkVersion = version.ok && /^10\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?$/.test(version.output.trim()) ? version.output.trim() : null;
  const hostCompatible = def.hosts.includes(process.platform), sdkAvailable = sdkVersion !== null;
  const missing = [];
  if (!hostCompatible) missing.push(`${target} requires a ${def.hosts.join(' or ')} build host.`);
  if (!sdkAvailable) missing.push('An explicitly installed .NET 10 SDK is required.');
  if (!installed.length) missing.push(`Required installed workload: ${def.workloads.join(' or ')}.`);
  return { schemaVersion: 1, profile: selected.packaging.profile, target, hostCompatible, sdkAvailable, sdkVersion, installedWorkloads: installed, workloadDetected: installed.length > 0, buildEligible: missing.length === 0, missing, nativeReadiness: 'unverified', signing: 'unverified', deviceQa: 'not-run', installationPerformed: false, notes: target === 'ANDROID' ? ['JDK/Android SDK and actual compiler checks remain required.'] : ['Platform SDK/WebView, signing and actual target execution remain separate checks.'] };
}
function plan(root, opt = {}) {
  const c = context(root, opt), { target, def, rid, format } = targetOptions(opt);
  if (/[;$%@]/.test(c.root)) fail('Project root contains MSBuild metacharacters; use a portable project location.');
  const operation = opt.operation || 'package';
  if (!['build', 'package'].includes(operation)) fail('Plan operation must be build or package.');
  const snapshot = verifySnapshot(c);
  let signing = null;
  if (opt.signingProperties) { signing = confined(c.root, opt.signingProperties, 'Signing properties'); regular(signing, 'Signing properties'); }
  const args = [operation === 'package' ? 'publish' : 'build', path.join(c.host, 'GameHost.csproj'), '-f', def.framework, '-c', 'Release', '-r', rid, `-p:TargetFrameworks=${def.framework}`, '-p:PublishAot=false', '-p:TrimMode=partial'];
  if (signing) args.push(`-p:OpenCawSigningProps=${signing}`);
  if (target === 'WINDOWS') args.push(`-p:WindowsPackageType=${format === 'msix' ? 'MSIX' : 'None'}`, '-p:WindowsAppSDKSelfContained=true', '-p:SelfContained=true');
  if (target === 'ANDROID') args.push(`-p:AndroidPackageFormats=${format}`);
  if (target === 'IOS' && operation === 'package') args.push('-p:ArchiveOnBuild=true', '-p:BuildIpa=true');
  if (target === 'MACOS') args.push(`-p:CreatePackage=${format === 'pkg' ? 'true' : 'false'}`);
  return { schemaVersion: 1, profile: 'MAUI', engine: c.selected.effectiveEngine, operation, target, rid, format, command: 'dotnet', args, snapshot: snapshot.snapshot.id, config: c.configRelative, prerequisites: doctor(root, opt), signingProperties: opt.signingProperties || null, externalSubmission: false, releaseReady: false };
}
async function execute(root, opt) {
  const timeout = opt.timeoutSeconds === undefined ? 1200 : Number(opt.timeoutSeconds);
  if (!Number.isSafeInteger(timeout) || timeout < 1 || timeout > 3600) fail('timeout-seconds must be an integer from 1 to 3600.');
  const c = context(root, opt);
  return locked(c, async () => {
    const requested = plan(root, opt);
    if (!requested.prerequisites.buildEligible) fail('Native prerequisites unavailable; run doctor for explicit missing requirements. Nothing was installed.');
    const id = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}`;
    const run = statePath(c, `runs/${id}`); fs.mkdirSync(run, { recursive: true });
    const output = path.join(run, 'output');
    const args = [...requested.args, '-o', output];
    if (requested.target === 'WINDOWS' && requested.format === 'msix') args.push(`-p:AppxPackageDir=${path.join(output, 'AppPackages')}${path.sep}`);
    const signingHash = opt.signingProperties ? hashFile(confined(c.root, opt.signingProperties, 'Signing properties')) : null;
    const before = verifySnapshot(c);
    const record = { schemaVersion: 1, id, status: 'started', ...requested, args: undefined, inputSha256: digest(JSON.stringify(before.identity)), signingPropertiesSha256: signingHash, storeSubmitted: false, releaseReady: false };
    writeNew(path.join(run, 'intent.json'), encode(record));
    let result;
    try {
      result = await new Promise((resolve, reject) => {
        const child = cp.spawn('dotnet', args, { cwd: c.root, stdio: ['ignore', 'ignore', 'ignore'], windowsHide: true, detached: process.platform !== 'win32', env: { ...process.env, DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE: 'true', DOTNET_SKIP_FIRST_TIME_EXPERIENCE: '1', DOTNET_NOLOGO: '1' } });
        let timer; let killed = false;
        const kill = () => { killed = true; if (!child.pid) return; if (process.platform === 'win32') cp.spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true }); else { try { process.kill(-child.pid, 'SIGKILL'); } catch {} } };
        const interrupt = () => kill(); process.once('SIGINT', interrupt); process.once('SIGTERM', interrupt);
        const clean = () => { clearTimeout(timer); process.removeListener('SIGINT', interrupt); process.removeListener('SIGTERM', interrupt); };
        child.once('error', error => { clean(); reject(error); });
        child.once('exit', code => { clean(); resolve({ code, cancelled: killed }); });
        timer = setTimeout(kill, timeout * 1000);
      });
      if (result.code !== 0 || result.cancelled) fail(`dotnet ${requested.operation} failed or was cancelled (exit ${result.code}). Run the reviewed plan manually for compiler diagnostics; no tool output or signing values were persisted.`);
      const after = verifySnapshot(c);
      if (digest(JSON.stringify(after.identity)) !== record.inputSha256 || (opt.signingProperties && hashFile(confined(c.root, opt.signingProperties, 'Signing properties')) !== signingHash)) fail('Inputs changed during native execution; output is not accepted.');
      const files = tree(output);
      if (!files.length) fail('Native execution produced no output.');
      if (requested.operation === 'package') {
        const patterns = { folder: /^GameHost\.exe$/i, msix: /\.msix(?:bundle)?$/i, apk: /\.apk$/i, aab: /\.aab$/i, ipa: /\.ipa$/i, pkg: /\.pkg$/i, app: /^[^/]+\.app\/Contents\/MacOS\/GameHost$/i };
        if (!files.some(f => f.size > 0 && patterns[requested.format].test(f.path))) fail('Expected nonempty fresh package artifact was not produced; this run is not a successful package.');
      }
      const assetsFile = pathTypes(c.root, `${c.config.hostDirectory}/obj/project.assets.json`, 'file', 'Resolved dependency graph');
      const resolvedDependencies = fs.existsSync(assetsFile) ? { path: path.relative(c.root, assetsFile).split(path.sep).join('/'), sha256: hashFile(assetsFile), size: fs.statSync(assetsFile).size } : null;
      const receipt = { ...record, status: 'succeeded', orchestratorSha256: before.identity.orchestratorSha256, resolvedDependencies, files, output: path.relative(c.root, output).split(path.sep).join('/'), nativeReadiness: 'compiled', signing: 'unverified', deviceQa: 'not-run' };
      writeNew(path.join(run, 'result.json'), encode(receipt));
      return receipt;
    } catch (error) {
      writeNew(path.join(run, 'result.json'), encode({ ...record, status: 'failed', reason: 'Native execution or artifact/input verification failed; no prior result reused.', exitCode: result?.code ?? null }));
      throw error;
    }
  });
}
const HELP = `Usage: web-game-package.sh <resolve|doctor|init|sync|recover|plan|build|package> [options]
  init --app-id com.example.game --title "My Game" [--web-root dist] [--output platforms/maui] [--entry index.html]
  sync                         Copy a verified built static game into the owned host.
  recover                      Restore a pending hash-owned init/sync transaction after inspecting locks.
  doctor --target WINDOWS      Read-only .NET/workload/build-host checks; installs nothing.
  plan [--operation package]   Print native argv and prerequisites; performs no restore/build.
  build|package --target WINDOWS|MACOS|ANDROID|IOS [--rid ID] [--format FORMAT]
  --signing-properties FILE    Project-local private MSBuild properties; use environment secrets.
  --config FILE                Default web-game-package.json; --engine-evidence FILE for isolated override.
  --timeout-seconds N          Native process bound (1..3600; default 1200).
  Linux/TV are unsupported. No operation uploads/submits to a store or installs workloads.
`;
function parse(values) {
  const [operation, ...rest] = values;
  const names = { '--root': 'root', '--config': 'config', '--app-id': 'appId', '--title': 'title', '--web-root': 'webRoot', '--output': 'output', '--entry': 'entry', '--target': 'target', '--rid': 'rid', '--format': 'format', '--operation': 'operation', '--signing-properties': 'signingProperties', '--timeout-seconds': 'timeoutSeconds', '--engine-evidence': 'engineEvidence' };
  const opt = {};
  for (let i = 0; i < rest.length; i++) {
    const key = names[rest[i]];
    if (!key || Object.hasOwn(opt, key) || i + 1 >= rest.length || rest[i + 1].startsWith('--')) fail('Unknown, repeated or missing option value. Use --help.');
    opt[key] = rest[++i];
  }
  const shared = operation === 'recover' ? ['root'] : ['root', 'engineEvidence'];
  const allowed = { resolve: [], doctor: ['target', 'rid', 'format'], init: ['config', 'appId', 'title', 'webRoot', 'output', 'entry'], sync: ['config'], recover: ['config'], plan: ['config', 'target', 'rid', 'format', 'operation', 'signingProperties'], build: ['config', 'target', 'rid', 'format', 'signingProperties', 'timeoutSeconds'], package: ['config', 'target', 'rid', 'format', 'signingProperties', 'timeoutSeconds'] };
  if (!Object.hasOwn(allowed, operation)) fail('Unknown packaging operation. Use --help.');
  if (Object.keys(opt).some(k => ![...shared, ...allowed[operation]].includes(k))) fail('Option is not supported by this operation.');
  return { operation, opt };
}
async function main(args) {
  if (!args.length || args.includes('--help')) { console.log(HELP); return; }
  const { operation, opt } = parse(args);
  if (!opt.root) fail('Resolved project root is required. Use the Bash entrypoint.');
  const root = process.platform === 'win32' ? opt.root.replace(/^\/(?:mnt\/)?([a-zA-Z])\//, (_, d) => `${d.toUpperCase()}:/`) : opt.root;
  let result;
  if (operation === 'resolve') result = selection(root, opt);
  else if (operation === 'doctor') result = doctor(root, opt);
  else if (operation === 'init') result = init(root, opt);
  else if (operation === 'sync') result = await sync(root, opt);
  else if (operation === 'recover') result = await recover(root, opt);
  else if (operation === 'plan') result = plan(root, opt);
  else result = await execute(root, { ...opt, operation });
  if (['build', 'package'].includes(operation)) {
    const { files, ...summary } = result;
    summary.fileCount = files.length;
    summary.receipt = summary.output.replace(/\/output$/, '/result.json');
    result = summary;
  }
  console.log(encode(result).trimEnd());
}
module.exports = { TARGETS, init, sync, recover, plan, execute, doctor, context, verifySnapshot, tree, parse, main };
if (require.main === module) main(process.argv.slice(2)).catch(error => { console.error(JSON.stringify({ error: error.message })); process.exitCode = 1; });
