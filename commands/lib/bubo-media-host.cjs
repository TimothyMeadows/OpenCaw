'use strict';

// Read-only discovery; Bubo owns model pins and installed-content verification.
const fs = require('fs'), path = require('path'), cp = require('child_process');
const runtime = require('./bubo-runtime.cjs');
const fail = message => { throw new Error(message); };
function parse(values) {
  const options = new Map();
  for (let index = 0; index < values.length; index++) {
    const flag = values[index];
    if (!['--root', '--workspace', '--json', '--help'].includes(flag) || options.has(flag.slice(2))) fail('Use unique --root ROOT, --workspace PATH, --json or --help.');
    if (flag === '--json' || flag === '--help') options.set(flag.slice(2), true);
    else { const value = values[++index]; if (!value || value.startsWith('--')) fail('Missing value for ' + flag); options.set(flag.slice(2), value); }
  }
  return options;
}
function gpu() {
  const result = cp.spawnSync('nvidia-smi', ['--query-gpu=index,name,memory.total,driver_version', '--format=csv,noheader,nounits'], { encoding: 'utf8', windowsHide: true, timeout: 5000, maxBuffer: 65536 });
  if (result.error || result.status !== 0) return { kind: 'unavailable', devices: [], inferenceTested: false };
  const devices = result.stdout.trim().split(/\r?\n/).filter(Boolean).map(row => {
    const [index, name, memory, driver] = row.split(',').map(value => value.trim());
    return { index: Number(index), name, vramBytes: Number.isFinite(Number(memory)) ? Number(memory) * 1024 * 1024 : null, driver };
  });
  return { kind: devices.length ? 'nvidia' : 'unavailable', devices, inferenceTested: false, driverMemoryMeasured: false };
}
function installationRecords(root, workspace, catalogSha256) {
  const records = [], directory = runtime.projectPath(root, path.join(workspace, 'installations'));
  if (fs.existsSync(directory)) {
    if (!fs.statSync(directory).isDirectory()) fail('Installation metadata path must be a directory.');
    const entries = fs.readdirSync(directory, { withFileTypes: true });
    if (entries.length > 128) fail('Installation metadata directory exceeds discovery limit.');
    for (const entry of entries) {
      if (!entry.name.endsWith('.json')) continue;
      const file = runtime.projectPath(root, path.join(directory, entry.name));
      if (!entry.isFile()) fail('Installation metadata must be regular files without symbolic links.');
      try {
        const value = runtime.json(file);
        if (value.schemaVersion !== 'bubo-media-installation/v1' || typeof value.backend !== 'string') fail('Unsupported installation metadata.');
        records.push({ path: path.relative(root, file).split(path.sep).join('/'), backend: value.backend, platform: value.platform,
          catalogMatches: value.catalogSha256 === catalogSha256, metadataSha256: runtime.hash(file), installedContentVerified: false, nativeValidation: 'not-run' });
      } catch (error) { records.push({ path: path.relative(root, file).split(path.sep).join('/'), metadataValid: false, reason: error.message, installedContentVerified: false }); }
    }
  }
  return records;
}
function inspect(rootArgument, workspaceArgument) {
  if (!rootArgument) fail('The resolved project --root is required.');
  const root = path.resolve(runtime.native(rootArgument)); runtime.syntax(root); runtime.components(root);
  if (!fs.statSync(root).isDirectory()) fail('Project root must be an existing directory.');
  const cache = runtime.projectPath(root, '.opencaw/.cache');
  const workspace = runtime.projectPath(root, workspaceArgument || '.opencaw/.cache/bubo-media');
  if (!runtime.within(cache, workspace) || runtime.samePath(cache, workspace)) fail('Media workspace must be a scoped project-cache child; external installations are not inspected.');
  let initialized = false, built = false, revision = null, reason = null, backends = [], catalogSha256 = null;
  try {
    const info = runtime.verified(); initialized = built = true; revision = info.pinned.revision;
    catalogSha256 = runtime.hash(runtime.projectPath(info.folder, 'resources/media/catalog.json'));
    backends = info.capability.mediaBackends.map(item => ({ ...item, declarationSource: 'verified-prebuilt-capabilities' }));
  } catch (error) {
    reason = error.message;
    try {
      const source = runtime.dependency(); initialized = true; revision = source.pinned.revision;
      const file = runtime.resource('media/catalog.json'), catalog = runtime.json(file); catalogSha256 = runtime.hash(file);
      if (catalog.schemaVersion !== 'bubo-media-catalog/v1' || !Array.isArray(catalog.backends)) fail('Pinned runtime has no supported media catalog.');
      backends = catalog.backends.map(item => ({ id: item.id, modality: item.modality, declarationSource: 'verified-pinned-source-catalog' }));
    } catch (sourceError) { reason += ' ' + sourceError.message; }
  }
  const records = installationRecords(root, workspace, catalogSha256);
  const modalities = Object.fromEntries(['image', 'sfx', 'music', 'voice'].map(name => [name, { advertised: false, ready: false, backends: [], readiness: 'unavailable' }]));
  for (const backend of backends) {
    const name = ['preset-speech', 'consented-cloning'].includes(backend.modality) ? 'voice' : backend.modality;
    if (!Object.hasOwn(modalities, name)) continue;
    const receipts = records.filter(item => item.backend === backend.id);
    modalities[name].advertised = true;
    const readiness = !built ? 'runtime-build-required' : receipts.some(item => item.catalogMatches) ? 'installed-content-inspection-required' : receipts.length ? 'registration-refresh-required' : 'installation-required';
    modalities[name].backends.push({ ...backend, readiness, receipts, installedContentVerified: false, nativeValidation: 'not-run' });
  }
  for (const value of Object.values(modalities)) if (value.backends.length) {
    const states = new Set(value.backends.map(item => item.readiness));
    value.readiness = states.size === 1 ? [...states][0] : 'mixed-readiness';
  }
  return { schemaVersion: 'opencaw-local-media-host/v1', pipeline: 'LOCAL', projectRoot: root,
    workspace: path.relative(root, workspace).split(path.sep).join('/'), platform: process.platform, platformSupported: ['win32', 'linux'].includes(process.platform),
    runtime: { initialized, built, revision, catalogSha256, reason }, gpu: gpu(), modalities,
    generation: false, modelLoading: false, installation: false, externalInstallationsInspected: false,
    limits: ['Advertisements do not establish installed-model/native quality readiness; each specific request needs full Bubo inspection.', '--load true is an explicitly selected zero-sample diagnostic, never ordinary discovery.', 'Native evidence must name its actual platform; no macOS or alternate GPU fallback is inferred.'] };
}
function main(values) {
  const options = parse(values);
  if (options.has('help')) { console.log('inspect-local-media-host.sh [--root ROOT] [--workspace PROJECT_CACHE_CHILD] [--json]\nRead-only Bubo LOCAL image/SFX/music/voice discovery. No external installation inspection, model loading, software installation or inferred native readiness.'); return; }
  const result = inspect(options.get('root'), options.get('workspace'));
  if (options.has('json')) console.log(JSON.stringify(result, null, 2));
  else { console.log(`LOCAL runtime: ${result.runtime.built ? 'verified prebuilt' : result.runtime.initialized ? 'initialized; build required' : 'not initialized'}`); for (const [name, value] of Object.entries(result.modalities)) console.log(`${name}: ${value.readiness}`); if (result.runtime.reason) console.log(result.runtime.reason); }
}
module.exports = { parse, inspect, installationRecords };
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; } }
