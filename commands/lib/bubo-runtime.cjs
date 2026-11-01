'use strict';

// Host-side revision/build admission. Execution and its algorithms live in Bubo.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');
const BASE = path.resolve(__dirname, '../..');
const fail = message => { throw new Error(message); };
const samePath = (left, right) => process.platform === 'win32' ? left.toLowerCase() === right.toLowerCase() : left === right;
const within = (root, full) => { const rel = path.relative(root, full); return rel === '' || (rel !== '..' && !rel.startsWith('..' + path.sep) && !path.isAbsolute(rel)); };
function native(value) { return process.platform === 'win32' ? value.replace(/^\/(?:mnt\/)?([a-zA-Z])\//, (_, drive) => drive.toUpperCase() + ':/') : value; }
function syntax(value) {
  if (typeof value !== 'string' || !value || /[\x00-\x1f]/.test(value) || /^\\\\[?.]\\/.test(value)) fail('Invalid filesystem path.');
  for (const part of value.split(/[\\/]/).filter(Boolean)) {
    if (part === '.' || part === '..' || part.toLowerCase() === '.git') fail('Traversal and Git metadata are reserved.');
    if (part.includes(':') && !(process.platform === 'win32' && /^[A-Za-z]:$/.test(part))) fail('Colon-qualified path aliases are unsupported.');
    if (process.platform === 'win32' && (/[. ]$/.test(part) || /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(part))) fail('Windows path aliases are unsupported.');
  }
}
function components(full) {
  const volume = path.parse(full).root;
  let current = volume;
  const parts = path.relative(volume, full).split(path.sep).filter(Boolean);
  for (let index = 0; index < parts.length; index++) {
    current = path.join(current, parts[index]);
    let stat;
    try { stat = fs.lstatSync(current); } catch (error) { if (error.code === 'ENOENT') return; throw error; }
    if (stat.isSymbolicLink()) fail('Filesystem paths cannot traverse symbolic links or junctions.');
    if (index < parts.length - 1 && !stat.isDirectory()) fail('An existing path ancestor is not a directory.');
  }
}
function projectPath(root, value, allowRoot = false) {
  syntax(value); const full = path.resolve(root, native(value));
  if (!within(root, full) || (!allowRoot && samePath(root, full))) fail('Path escapes or selects the whole project root.');
  components(full); return full;
}
function hash(file) {
  const digest = crypto.createHash('sha256'), buffer = Buffer.allocUnsafe(65536);
  const fd = fs.openSync(file, 'r');
  try { let count; while ((count = fs.readSync(fd, buffer, 0, buffer.length, null))) digest.update(buffer.subarray(0, count)); }
  finally { fs.closeSync(fd); }
  return digest.digest('hex');
}
function json(file) {
  if (!fs.statSync(file).isFile() || fs.statSync(file).size > 8 * 1024 * 1024) fail('Missing or oversized JSON: ' + file);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
function run(executable, args, options = {}) {
  const result = cp.spawnSync(executable, args, { cwd: BASE, encoding: 'utf8', windowsHide: true, timeout: 30000, maxBuffer: 16 * 1024 * 1024, ...options });
  if (result.error || result.status !== 0) fail(`${path.basename(executable)} failed: ${result.error?.message || result.stderr?.trim() || result.stdout?.trim() || result.status}`);
  return result.stdout;
}
const git = (root, args) => run('git', ['-C', root, ...args]).trim();
function lock() {
  const value = json(path.join(BASE, 'runtime/bubo.lock.json'));
  if (value.schemaVersion !== 1 || value.path !== 'runtime/bubo' || value.repository !== 'https://github.com/TimothyMeadows/Bubo.git'
      || !/^[a-f0-9]{40}$/.test(value.revision) || value.apiVersion !== 2 || !/^[a-f0-9]{64}$/.test(value.resourceCatalogSha256)
      || value.buildReceipt !== 'artifacts/bubo/build-info.json') fail('Invalid Bubo dependency lock.');
  return value;
}
function missing() {
  return 'Bubo is not initialized. Run git -C "<project-root>/.hephaera" submodule update --init --recursive --checkout runtime/bubo, then run ./.hephaera/commands/build-bubo-runtime.sh. No sibling or source fallback was used.';
}
function dependency() {
  const pinned = lock(), root = projectPath(BASE, pinned.path);
  if (!fs.existsSync(path.join(root, '.git')) || !fs.existsSync(path.join(root, 'Bubo.slnx'))) fail(missing());
  if (!samePath(path.resolve(git(root, ['rev-parse', '--show-toplevel'])), root)) fail(missing());
  if (git(root, ['rev-parse', 'HEAD']) !== pinned.revision) fail('Bubo revision mismatch. Initialize the recorded runtime/bubo commit; do not use --remote or a sibling checkout.');
  const entry = git(BASE, ['ls-files', '--stage', '--', pinned.path]).split(/\s+/);
  if (entry[0] !== '160000' || entry[1] !== pinned.revision || entry[2] !== '0') fail('Bubo lock and recorded parent gitlink disagree.');
  if (git(root, ['status', '--porcelain', '--untracked-files=no'])) fail('Bubo source is modified; restore/review the pinned dependency before execution.');
  const catalogFile = projectPath(root, 'resources/catalog.json');
  if (hash(catalogFile) !== pinned.resourceCatalogSha256) fail('Pinned Bubo resource catalog changed.');
  return { pinned, root, catalog: json(catalogFile) };
}
function resource(relative) {
  const info = dependency();
  const key = 'resources/' + relative;
  const file = projectPath(info.root, key);
  if (!Object.hasOwn(info.catalog.files || {}, key) || hash(file) !== info.catalog.files[key]) fail('Unrecorded or altered Bubo resource: ' + relative);
  return file;
}
function verified() {
  const info = dependency(), folder = projectPath(info.root, 'artifacts/bubo');
  const receiptFile = projectPath(info.root, info.pinned.buildReceipt);
  if (!fs.existsSync(receiptFile)) fail('Bubo CLI is not built. Run ./.hephaera/commands/build-bubo-runtime.sh explicitly; production never runs dotnet run or installs software.');
  const receipt = json(receiptFile), capability = receipt.capabilities, build = capability?.build;
  if (receipt.schemaVersion !== 'bubo-build/v1' || receipt.sourceRevision !== info.pinned.revision || receipt.sourceDirty !== false)
    fail('Bubo build receipt is stale/dirty or does not identify the pinned revision. Rebuild explicitly.');
  if (capability.schemaVersion !== 'bubo-capabilities/v1' || !capability.apiVersions?.includes(info.pinned.apiVersion)
      || build?.resourceCatalogSha256 !== info.pinned.resourceCatalogSha256 || !build.assemblies || !build.launch) fail('Bubo build/API/resource contract mismatch.');
  for (const [name, expected] of Object.entries({ ...build.assemblies, ...build.launch })) {
    if (path.basename(name) !== name || !/^[a-f0-9]{64}$/.test(expected) || hash(projectPath(folder, name)) !== expected) fail('Bubo built artifact changed: ' + name);
  }
  const assemblies = fs.readdirSync(folder).filter(name => name.endsWith('.dll')).sort();
  if (JSON.stringify(assemblies) !== JSON.stringify(Object.keys(build.assemblies).sort())) fail('Unexpected or missing Bubo runtime assembly.');
  const catalogFile = projectPath(folder, 'resources/catalog.json');
  if (hash(catalogFile) !== info.pinned.resourceCatalogSha256) fail('Published Bubo resource catalog changed.');
  const catalog = json(catalogFile);
  for (const [name, expected] of Object.entries(catalog.files || {})) {
    if (!name.startsWith('resources/') || !/^[a-f0-9]{64}$/.test(expected) || hash(projectPath(folder, name)) !== expected) fail('Published Bubo audited resource changed: ' + name);
  }
  const executable = projectPath(folder, process.platform === 'win32' ? 'bubo.exe' : 'bubo');
  if (!fs.existsSync(executable)) fail('Bubo prebuilt apphost is missing; rebuild explicitly.');
  const live = JSON.parse(run(executable, ['capabilities', '--api-version', String(info.pinned.apiVersion)]));
  if (live.schemaVersion !== 'bubo-capabilities/v1' || !live.apiVersions?.includes(2)
      || JSON.stringify(canonical(live.build)) !== JSON.stringify(canonical(build))) fail('Bubo live capability/build identity differs from its receipt.');
  return { ...info, folder, executable, receipt, capability: live };
}
function main(args) {
  if (args.length === 1 && args[0] === 'verify') {
    const info = verified(); console.log(JSON.stringify({ revision: info.pinned.revision, apiVersion: 2, build: info.capability.build }, null, 2)); return;
  }
  if (args.length === 2 && args[0] === 'resource') { console.log(resource(args[1])); return; }
  fail('Use bubo-runtime.cjs verify | resource RESOURCE_RELATIVE_PATH.');
}
module.exports = { BASE, dependency, verified, resource, projectPath, components, syntax, hash, json, run, git, native, canonical, within, samePath };
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; } }
