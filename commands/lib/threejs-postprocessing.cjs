'use strict';

// Metadata-only discovery: do not execute host packages or claim rendering readiness.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const engines = require('./engine-contract.cjs');
const BASE = path.resolve(__dirname, '../..');
const TEMPLATE = path.join(BASE, '.engine/threejs/postprocessing');
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const fail = message => { throw new Error(message); };
const encode = value => JSON.stringify(value, null, 2) + '\n';
function safe(root, value, label) {
  if (typeof value !== 'string' || !value || path.isAbsolute(value) || value.includes('\\') || /[:\x00-\x1f<>"|?*]/.test(value) || value.split('/').some(p => !p || p === '.' || p === '..' || /[. ]$/.test(p) || /^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)/i.test(p))) fail(`${label} must be a portable project-relative path.`);
  return engines.inside(root, value, label).absolute;
}
function metadata(root, value, limit = 1024 * 1024) {
  let file;
  try { file = safe(root, value, 'Metadata'); }
  catch { return { available: false, state: 'unverified', reason: 'Linked or unsafe metadata path is unverified.' }; }
  if (!fs.existsSync(file)) return { available: false, state: 'missing', reason: 'Missing.' };
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.size > limit) return { available: false, state: 'unverified', reason: 'Metadata must be a bounded regular file.' };
  try { return { available: true, state: 'present', data: JSON.parse(fs.readFileSync(file, 'utf8')), sha256: sha(file) }; }
  catch { return { available: false, state: 'unverified', reason: 'Malformed metadata.' }; }
}
function selection(root, opt = {}) {
  const selected = engines.resolve(root, opt.engineEvidence ? { evidence: opt.engineEvidence, ...(opt.output ? { output: opt.output } : {}) } : (opt.output ? { output: opt.output } : {}));
  if (selected.effectiveEngine !== 'THREEJS' || selected.postprocessing?.backend !== 'PMNDRS_POSTPROCESSING') fail('postprocessing is the THREEJS postprocessing backend. Resolve the selected engine; no fallback was selected.');
  return selected;
}
function version(value) {
  const m = typeof value === 'string' && value.match(/^(\d+)\.(\d+)\.(\d+)$/);
  return m ? m.slice(1).map(Number) : null;
}
function atLeast(value, minimum) {
  const a = version(value), b = version(minimum); if (!a || !b) return null;
  for (let i = 0; i < 3; i++) { if (a[i] !== b[i]) return a[i] > b[i]; }
  return true;
}
function accepts(spec, installed) {
  if (typeof spec !== 'string' || !version(installed)) return null;
  if (version(spec)) return spec === installed;
  const m = spec.match(/^(\^|~|>=)(\d+\.\d+\.\d+)$/);
  if (!m) return null; // Other semver syntax/managers need explicit host review.
  if (!atLeast(installed, m[2])) return false;
  if (m[1] === '>=') return true;
  const a = version(installed), b = version(m[2]);
  if (m[1] === '~') return a[0] === b[0] && a[1] === b[1];
  return b[0] > 0 ? a[0] === b[0] : b[1] > 0 ? a[0] === 0 && a[1] === b[1] : installed === m[2];
}
function shadow(root, name) {
  const value = `node_modules/postprocessing/node_modules/${name}`;
  try {
    const directory = safe(root, value, 'Nested dependency');
    if (!fs.existsSync(directory)) return { package: name, state: 'missing' };
    const info = metadata(root, value + '/package.json');
    return { package: name, state: 'present', version: info.available ? info.data?.version || null : null };
  } catch { return { package: name, state: 'unverified' }; }
}
function inspect(root, opt = {}) {
  root = fs.realpathSync(root); const selected = selection(root, opt);
  const known = { three: selected.postprocessing.testedThreeVersion, postprocessing: selected.postprocessing.testedVersion };
  if (opt.renderer !== undefined && !['WebGLRenderer', 'WebGPURenderer'].includes(opt.renderer)) fail('renderer must be WebGLRenderer or WebGPURenderer.');
  const manifest = metadata(root, 'package.json');
  const lock = metadata(root, 'package-lock.json', 16 * 1024 * 1024);
  const usableLock = lock.available && [2, 3].includes(lock.data?.lockfileVersion) && lock.data?.packages && typeof lock.data.packages === 'object';
  const declarations = manifest.available ? { ...manifest.data?.devDependencies, ...manifest.data?.dependencies } : {};
  const lockedDeclarations = usableLock ? { ...lock.data.packages['']?.devDependencies, ...lock.data.packages['']?.dependencies } : {};
  const packages = [], problems = [];
  for (const name of Object.keys(known)) {
    const record = usableLock ? lock.data.packages[`node_modules/${name}`] : null;
    const installed = metadata(root, `node_modules/${name}/package.json`);
    const declared = typeof declarations[name] === 'string' ? declarations[name] : null;
    const installedVersion = installed.available && installed.data?.name === name && version(installed.data?.version) ? installed.data.version : null;
    const lockedVersion = record && version(record.version) ? record.version : null;
    const integrity = typeof record?.integrity === 'string' && /^sha(?:256|384|512)-[A-Za-z0-9+/=]+$/.test(record.integrity) ? record.integrity : null;
    const matching = Boolean(installedVersion && lockedVersion && installedVersion === lockedVersion && integrity);
    const row = { package: name, declared, lockedVersion, installedVersion, integrity, installedMetadataSha256: installed.available ? installed.sha256 : null, metadataMatchesLock: matching, testedVersion: known[name], testedVersionMatch: installedVersion === known[name], contentIntegrity: 'unverified' };
    const declarationMatchesLock = declared !== null && declared === lockedDeclarations[name];
    row.declarationMatchesLock = declarationMatchesLock;
    row.declaredRangeAcceptsInstalled = accepts(declared, installedVersion);
    if (!declared || !matching || !declarationMatchesLock || row.declaredRangeAcceptsInstalled !== true) problems.push(`${name}: declaration/lock/installed metadata is missing, inconsistent or needs specifier review.`);
    packages.push(row);
  }
  const three = packages.find(p => p.package === 'three');
  const peer = atLeast(three.installedVersion, '0.168.0') === true && atLeast(three.installedVersion, '0.187.0') === false;
  if (peer !== true) problems.push('The installed Three.js version does not establish the required >=0.168.0 <0.187.0 stable peer range.');
  const duplicateThree = usableLock ? Object.keys(lock.data.packages).filter(k => k === 'node_modules/three' || k.endsWith('/node_modules/three')).length > 1 : false;
  if (duplicateThree) problems.push('Multiple locked Three.js copies require explicit dependency review.');
  const nestedDependencies = ['three'].map(name => shadow(root, name));
  if (nestedDependencies.some(p => p.state !== 'missing')) problems.push('Nested or unsafe Three.js dependency resolution is unverified.');
  const testedPair = packages.every(p => p.testedVersionMatch && p.metadataMatchesLock) && !duplicateThree && nestedDependencies.every(p => p.state === 'missing');
  if (!testedPair) problems.push('This installed combination is not the exact CPU-tested baseline; record fresh compatibility evidence.');
  const rendererSupported = opt.renderer === 'WebGLRenderer';
  if (!rendererSupported) problems.push(opt.renderer === 'WebGPURenderer' ? 'This postprocessing integration requires WebGLRenderer; WebGPU is not supported by this integration; no backend was changed.' : 'The actual host renderer is unverified; declare WebGLRenderer and test its real target.');
  return {
    schemaVersion: 1, engine: 'THREEJS', backend: selected.postprocessing.backend, selectionSource: 'engine', packages,
    lock: { manager: usableLock ? 'npm' : 'unverified', file: lock.available ? 'package-lock.json' : null, sha256: lock.available ? lock.sha256 : null, supportedFormat: Boolean(usableLock) },
    peerThreeRange: '>=0.168.0 <0.187.0', peerCompatible: peer, duplicateThree, nestedDependencies,
    renderer: { declared: opt.renderer || null, supportedDeclaration: rendererSupported, actualRendering: 'unverified' },
    testedPair, metadataReadyForIntegration: testedPair && rendererSupported && problems.length === 0,
    installedContent: 'unverified', executionReadiness: 'unverified', problems,
    notes: ['Metadata does not verify installed package bytes, executable behavior, rendering, performance or MAUI devices.', 'Other package managers/workspaces require their own lock and resolution verification; no packages were imported or installed.']
  };
}
function outputPath(root, value) {
  const target = safe(root, value, 'Output');
  if (value.split('/').some(p => ['.git', '.hephaera', 'node_modules', 'runtime', '.engine', 'commands', 'skills'].includes(p.toLowerCase()))) fail('Output cannot overwrite baseline, dependency or durable state directories.');
  let current = root;
  for (const part of value.split('/').slice(0, -1)) {
    current = path.join(current, part);
    if (fs.existsSync(current) && !fs.lstatSync(current).isDirectory()) fail('Output parent must be a directory.');
    if (fs.existsSync(path.join(current, 'hephaera-postprocessing.json'))) fail('Output cannot nest inside another owned postprocessing module.');
  }
  return target;
}
function scaffold(root, opt = {}) {
  root = fs.realpathSync(root); const output = opt.output || 'src/engine/postprocessing';
  if (opt.renderer === 'WebGPURenderer') fail('The selected postprocessing integration requires WebGLRenderer; WebGPU is unavailable and no renderer was changed.');
  const selected = selection(root, { ...opt, output });
  const target = outputPath(root, output);
  if (fs.existsSync(target)) fail('Output already exists; choose a new owned directory. Nothing was overwritten.');
  const files = fs.readdirSync(TEMPLATE).sort().map(name => {
    const file = path.join(TEMPLATE, name);
    if (!/^[a-zA-Z0-9][a-zA-Z0-9.-]*$/.test(name) || !/\.(?:mjs|mts|md)$/.test(name) || !fs.lstatSync(file).isFile() || fs.lstatSync(file).isSymbolicLink()) fail('Unexpected postprocessing template entry.');
    return { name, sha256: sha(file) };
  });
  if (!files.some(f => f.name === 'postprocessing-runtime.mjs')) fail('Postprocessing runtime template is incomplete.');
  const stateRelative = '.hephaera/.cache/threejs-postprocessing/scaffolds';
  const state = engines.inside(root, stateRelative, 'Scaffold state').absolute;
  fs.mkdirSync(state, { recursive: true });
  const lock = path.join(state, 'operation.lock');
  try { fs.mkdirSync(lock); } catch { fail('Another scaffold operation or abandoned lock exists; inspect before retrying.'); }
  try {
    const stage = engines.inside(root, `${stateRelative}/${Date.now()}-${crypto.randomBytes(6).toString('hex')}`, 'Scaffold stage').absolute;
    fs.mkdirSync(stage);
    for (const f of files) fs.writeFileSync(path.join(stage, f.name), fs.readFileSync(path.join(TEMPLATE, f.name)), { flag: 'wx' });
    const receipt = { schemaVersion: 1, backend: 'PMNDRS_POSTPROCESSING', output, engine: { effectiveEngine: selected.effectiveEngine, contractSha256: selected.contractSha256, registrySha256: selected.registrySha256, definitionSha256: selected.definitionSha256, evidence: selected.evidence || null }, source: files, dependencies: inspect(root, opt), installationPerformed: false, runtimeAcceptance: 'unverified' };
    fs.writeFileSync(path.join(stage, 'hephaera-postprocessing.json'), encode(receipt), { flag: 'wx' });
    const fresh = selection(root, { ...opt, output });
    if (JSON.stringify(fresh) !== JSON.stringify(selected) || files.some(f => sha(path.join(TEMPLATE, f.name)) !== f.sha256 || sha(path.join(stage, f.name)) !== f.sha256)) fail('Engine/template changed during scaffold; staged evidence retained, output not published.');
    outputPath(root, output);
    if (fs.existsSync(target)) fail('Output became occupied; unpublished stage retained.');
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.renameSync(stage, target);
    return { schemaVersion: 1, backend: 'PMNDRS_POSTPROCESSING', output, files: [...files.map(f => f.name), 'hephaera-postprocessing.json'], installationPerformed: false, executionReadiness: 'unverified', dependencies: receipt.dependencies };
  } finally { fs.rmdirSync(lock); }
}
const HELP = `Usage: threejs-postprocessing.sh <inspect|scaffold> [options]
  inspect [--renderer WebGLRenderer|WebGPURenderer]
  scaffold [--output src/engine/postprocessing] [--renderer WebGLRenderer]
  --engine-evidence FILE  Consume a valid isolated THREEJS engine override.
Inspect reads npm metadata only; other lock formats require explicit review.
Scaffold copies source to a new owned project directory; neither operation installs,
upgrades or imports packages, selects a renderer, or verifies actual rendering.
`;
function parse(args) {
  const [operation, ...rest] = args; const opt = {};
  const fields = { '--root': 'root', '--output': 'output', '--renderer': 'renderer', '--engine-evidence': 'engineEvidence' };
  if (!['inspect', 'scaffold'].includes(operation)) fail('Use inspect or scaffold; --help lists options.');
  for (let i = 0; i < rest.length; i++) {
    const field = fields[rest[i]];
    if (!field || Object.hasOwn(opt, field) || !rest[i + 1] || rest[i + 1].startsWith('--')) fail('Unknown, repeated or missing option.');
    opt[field] = rest[++i];
  }
  if (operation === 'inspect' && opt.output) fail('Inspect is read-only and does not take --output.');
  return { operation, opt };
}
function main(args) {
  if (!args.length || args.includes('--help')) { console.log(HELP); return; }
  const { operation, opt } = parse(args);
  if (!opt.root) fail('Use the Bash command with its resolved project root.');
  const root = process.platform === 'win32' ? opt.root.replace(/^\/(?:mnt\/)?([a-zA-Z])\//, (_, d) => `${d.toUpperCase()}:/`) : opt.root;
  console.log(encode(operation === 'inspect' ? inspect(root, opt) : scaffold(root, opt)).trimEnd());
}
module.exports = { inspect, scaffold, parse, main };
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error(JSON.stringify({ error: error.message })); process.exitCode = 1; } }
