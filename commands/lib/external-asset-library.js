'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const supportedExtensions = new Set([
  '.3ds', '.abc', '.blend', '.bvh', '.dae', '.fbx', '.glb', '.gltf',
  '.obj', '.ply', '.stl', '.usd', '.usda', '.usdc'
]);

function fail(message) {
  throw new Error(message);
}

function comparable(value) {
  const normalized = path.resolve(value).replace(/[\\/]+$/, '');
  return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function inside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function portable(value) {
  return value.split(path.sep).join('/');
}

function sha256(file) {
  const hash = crypto.createHash('sha256');
  const descriptor = fs.openSync(file, 'r');
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  try {
    let bytes;
    do {
      bytes = fs.readSync(descriptor, buffer, 0, buffer.length, null);
      if (bytes > 0) hash.update(buffer.subarray(0, bytes));
    } while (bytes > 0);
  } finally {
    fs.closeSync(descriptor);
  }
  return hash.digest('hex');
}

function requireRoot(rootArgument) {
  const lexical = path.resolve(rootArgument);
  let stat;
  try { stat = fs.lstatSync(lexical); }
  catch { fail(`External asset library is unavailable: ${rootArgument}`); }
  if (!stat.isDirectory() || stat.isSymbolicLink()) fail('External asset library root must be a non-symbolic-link directory.');
  const real = fs.realpathSync(lexical);
  if (comparable(lexical) !== comparable(real)) fail('External asset library root path contains a symbolic link or junction.');
  return real;
}

function normalizeRelative(input) {
  if (!input || /[\0\r\n\t]/.test(input)) fail('Asset path must be a non-empty single-line relative path.');
  const normalized = input.replace(/\\/g, '/').replace(/^\.\//, '').replace(/\/$/, '');
  if (!normalized || normalized.startsWith('/') || /^[A-Za-z]:/.test(normalized)) fail('Asset path must be relative to the configured library root.');
  const segments = normalized.split('/');
  if (segments.some(segment => !segment || segment === '.' || segment === '..')) fail('Asset path contains an empty, current, or parent-traversal segment.');
  return segments;
}

function resolveSource(root, segments) {
  let current = root;
  for (const segment of segments) {
    current = path.join(current, segment);
    let stat;
    try { stat = fs.lstatSync(current); }
    catch { fail(`External asset does not exist: ${segments.join('/')}`); }
    if (stat.isSymbolicLink()) fail(`External asset path contains a symbolic link or junction: ${segments.join('/')}`);
  }
  const real = fs.realpathSync(current);
  if (!inside(root, real)) fail('External asset resolves outside the configured library root.');
  return real;
}

function inventory(root, libraryId) {
  const assets = [];
  const skippedLinks = [];
  const skippedUnsafeEntries = [];
  function walk(directory, relativeDirectory) {
    const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const absolute = path.join(directory, entry.name);
      const relative = relativeDirectory ? `${relativeDirectory}/${entry.name}` : entry.name;
      if (/[\0\r\n\t]/.test(entry.name)) { skippedUnsafeEntries.push(relative); continue; }
      let stat;
      try { stat = fs.lstatSync(absolute); }
      catch { skippedUnsafeEntries.push(relative); continue; }
      if (stat.isSymbolicLink()) { skippedLinks.push(relative); continue; }
      if (stat.isDirectory()) { walk(absolute, relative); continue; }
      if (!stat.isFile()) continue;
      const extension = path.extname(entry.name).toLowerCase();
      if (supportedExtensions.has(extension)) assets.push({ path: relative, extension, sizeBytes: stat.size });
    }
  }
  walk(root, '');
  return {
    schemaVersion: 'opencaw-external-asset-library/v1',
    libraryId,
    readOnly: true,
    supportedAssetCount: assets.length,
    assets,
    skippedSymbolicLinks: skippedLinks,
    skippedUnsafeEntries
  };
}

function ensureSafeDirectory(root, segments) {
  let current = root;
  for (const segment of segments) {
    current = path.join(current, segment);
    if (fs.existsSync(current)) {
      const stat = fs.lstatSync(current);
      if (!stat.isDirectory() || stat.isSymbolicLink()) fail(`Destination path is not a safe directory: ${current}`);
      continue;
    }
    fs.mkdirSync(current);
  }
  return current;
}

function copyFileVerified(source, destination) {
  const sourceStat = fs.statSync(source);
  fs.copyFileSync(source, destination, fs.constants.COPYFILE_EXCL);
  try { fs.chmodSync(destination, (sourceStat.mode & 0o777) | 0o200); } catch { /* Windows permissions may not map to POSIX bits. */ }
  const sourceHash = sha256(source);
  const destinationHash = sha256(destination);
  if (sourceHash !== destinationHash) fail(`Copied asset hash mismatch: ${source}`);
  return { sha256: destinationHash, sizeBytes: sourceStat.size };
}

function copyTree(source, destination, copied, destinationRoot) {
  fs.mkdirSync(destination);
  const entries = fs.readdirSync(source, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const sourceItem = path.join(source, entry.name);
    const destinationItem = path.join(destination, entry.name);
    if (/[\0\r\n\t]/.test(entry.name)) fail(`External asset bundle contains an unsafe filename: ${sourceItem}`);
    const stat = fs.lstatSync(sourceItem);
    if (stat.isSymbolicLink()) fail(`External asset bundle contains a symbolic link or junction: ${sourceItem}`);
    if (stat.isDirectory()) { copyTree(sourceItem, destinationItem, copied, destinationRoot); continue; }
    if (!stat.isFile()) fail(`External asset bundle contains an unsupported filesystem entry: ${sourceItem}`);
    const proof = copyFileVerified(sourceItem, destinationItem);
    copied.push({ path: portable(path.relative(destinationRoot, destinationItem)), ...proof });
  }
}

function preflightTree(source) {
  let supported = 0;
  function walk(directory) {
    const entries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      const item = path.join(directory, entry.name);
      if (/[\0\r\n\t]/.test(entry.name)) fail(`External asset bundle contains an unsafe filename: ${item}`);
      const stat = fs.lstatSync(item);
      if (stat.isSymbolicLink()) fail(`External asset bundle contains a symbolic link or junction: ${item}`);
      if (stat.isDirectory()) { walk(item); continue; }
      if (!stat.isFile()) fail(`External asset bundle contains an unsupported filesystem entry: ${item}`);
      if (supportedExtensions.has(path.extname(entry.name).toLowerCase())) supported += 1;
    }
  }
  walk(source);
  if (supported === 0) fail('External asset bundle contains no supported 3D model, rig, or animation file.');
}

function prepareEvidence(projectRoot, evidenceArgument) {
  if (!evidenceArgument || evidenceArgument === '-') return null;
  const tasksRoot = path.join(projectRoot, '.ai', 'tasks');
  ensureSafeDirectory(projectRoot, ['.ai', 'tasks']);
  const output = path.resolve(evidenceArgument);
  if (!inside(tasksRoot, output) || output === tasksRoot) fail('Copy evidence must be a file below the project .ai/tasks directory.');
  const relativeSegments = path.relative(tasksRoot, path.dirname(output)).split(path.sep).filter(Boolean);
  ensureSafeDirectory(tasksRoot, relativeSegments);
  if (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink()) fail('Copy evidence must not be a symbolic link.');
  return output;
}

function copyAsset(root, projectArgument, libraryId, sourceArgument, styleSha256, evidenceArgument) {
  if (!/^[a-z0-9][a-z0-9-]{0,62}$/.test(libraryId)) fail('Invalid external asset library id.');
  const projectLexical = path.resolve(projectArgument);
  const projectStat = fs.lstatSync(projectLexical);
  if (!projectStat.isDirectory() || projectStat.isSymbolicLink()) fail('Project root must be a non-symbolic-link directory.');
  const projectRoot = fs.realpathSync(projectLexical);
  if (comparable(projectLexical) !== comparable(projectRoot)) fail('Project root path contains a symbolic link or junction.');
  if (inside(projectRoot, root) || inside(root, projectRoot)) fail('External asset library and project roots must not overlap.');

  const sourceSegments = normalizeRelative(sourceArgument);
  const source = resolveSource(root, sourceSegments);
  const sourceStat = fs.lstatSync(source);
  if (!sourceStat.isFile() && !sourceStat.isDirectory()) fail('External asset must be a regular file or directory bundle.');
  if (sourceStat.isFile() && !supportedExtensions.has(path.extname(source).toLowerCase())) fail('A single copied asset must use a supported 3D model, rig, or animation format.');
  if (sourceStat.isDirectory()) preflightTree(source);

  const evidence = prepareEvidence(projectRoot, evidenceArgument);
  const modelsRoot = ensureSafeDirectory(projectRoot, ['assets', 'models']);
  const parentSegments = [libraryId, ...sourceSegments.slice(0, -1)];
  const destinationParent = ensureSafeDirectory(modelsRoot, parentSegments);
  const destination = path.join(destinationParent, sourceSegments[sourceSegments.length - 1]);
  if (!inside(modelsRoot, destination)) fail('Destination escapes assets/models.');
  if (fs.existsSync(destination)) fail(`Destination already exists; refusing to overwrite: ${portable(path.relative(projectRoot, destination))}`);

  const temporaryRoot = fs.mkdtempSync(path.join(modelsRoot, '.opencaw-copy-'));
  const staged = path.join(temporaryRoot, 'payload');
  const copied = [];
  try {
    if (sourceStat.isDirectory()) {
      copyTree(source, staged, copied, staged);
    } else {
      const proof = copyFileVerified(source, staged);
      copied.push({ path: path.basename(destination), ...proof });
    }
    fs.renameSync(staged, destination);
  } catch (error) {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
    throw error;
  }
  fs.rmSync(temporaryRoot, { recursive: true, force: true });

  const destinationRelative = portable(path.relative(projectRoot, destination));
  const result = {
    schemaVersion: 'opencaw-external-asset-copy/v1',
    libraryId,
    sourceRelativePath: sourceSegments.join('/'),
    sourceReadOnly: true,
    destination: destinationRelative,
    styleSha256,
    rightsStatus: 'requires-asset-level-review',
    copiedAt: new Date().toISOString(),
    files: copied.map(item => ({
      path: sourceStat.isDirectory() ? `${destinationRelative}/${item.path}` : destinationRelative,
      sha256: item.sha256,
      sizeBytes: item.sizeBytes
    }))
  };
  if (evidence) fs.writeFileSync(evidence, `${JSON.stringify(result, null, 2)}\n`, { encoding: 'utf8', flag: 'w' });
  return result;
}

const [mode, ...args] = process.argv.slice(2);
try {
  if (mode === 'inventory') {
    const [rootArgument, libraryId, format = 'json'] = args;
    const result = inventory(requireRoot(rootArgument), libraryId);
    if (format === 'text') {
      console.log(`EXTERNAL_ASSET_LIBRARY=${result.libraryId}`);
      console.log(`READ_ONLY=true`);
      console.log(`SUPPORTED_ASSET_COUNT=${result.supportedAssetCount}`);
      for (const asset of result.assets) console.log(`${asset.path}\t${asset.extension}\t${asset.sizeBytes}`);
      for (const link of result.skippedSymbolicLinks) console.log(`SKIPPED_SYMBOLIC_LINK=${link}`);
      for (const entry of result.skippedUnsafeEntries) console.log(`SKIPPED_UNSAFE_ENTRY=${entry}`);
    } else {
      process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    }
  } else if (mode === 'copy') {
    const [rootArgument, projectArgument, libraryId, sourceArgument, styleSha256, evidenceArgument = '-'] = args;
    process.stdout.write(`${JSON.stringify(copyAsset(requireRoot(rootArgument), projectArgument, libraryId, sourceArgument, styleSha256, evidenceArgument), null, 2)}\n`);
  } else {
    fail('Usage: external-asset-library.js inventory|copy ...');
  }
} catch (error) {
  console.error(error && error.message ? error.message : String(error));
  process.exit(1);
}
