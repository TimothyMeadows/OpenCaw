'use strict';

// Host-owned inspection policy, output publication and v1 report validation.
// Bubo owns the inspector and native execution; no art/engine selection occurs.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const runtime = require('./bubo-runtime.cjs');
const host = require('./bubo-host-adapter.cjs');
const fail = message => { throw new Error(message); };
const usage = 'inspect-blender-scene.sh <scene.blend> --root PROJECT --profile PROFILE [--blender EXECUTABLE] [--output REPORT] [--replace] [--dry-run]';
async function main(args) {
  if (args.length === 1 && ['-h', '--help'].includes(args[0])) { console.log(usage); return; }
  const sceneArg = args.shift();
  if (!sceneArg || sceneArg.startsWith('--')) fail(usage);
  const values = new Map();
  while (args.length) {
    const key = args.shift();
    if (!['--root', '--profile', '--blender', '--output', '--replace', '--dry-run'].includes(key) || values.has(key)) fail('Unknown or duplicate inspection argument: ' + key);
    const value = ['--replace', '--dry-run'].includes(key) ? true : args.shift();
    if (!value || typeof value === 'string' && value.startsWith('--')) fail('Missing value: ' + key);
    values.set(key, value);
  }
  const rootArg = values.get('--root');
  if (!rootArg) fail('Explicit --root is required.');
  const root = path.resolve(runtime.native(rootArg)); runtime.components(root);
  runtime.syntax(root);
  if (!fs.statSync(root).isDirectory()) fail('Root must be an existing directory.');
  // Legacy paths are relative to the invocation cwd, then confined to the root.
  const scene = runtime.projectPath(root, path.resolve(runtime.native(sceneArg)));
  if (path.extname(scene).toLowerCase() !== '.blend' || !fs.statSync(scene).isFile()) fail('Scene must be a regular local .blend file.');
  const profile = values.get('--profile');
  if (!['static-asset', 'rigged-actor', 'procedural-scene', 'render-scene', 'simulation'].includes(profile)) fail('Unsupported Blender inspection profile.');
  const info = runtime.verified();
  let selectedBlender = values.get('--blender') || 'blender';
  if (/[\\/]/.test(selectedBlender)) selectedBlender = path.resolve(runtime.native(selectedBlender));
  const blender = host.executable(selectedBlender, root, true);
  const version = runtime.run(blender, ['--version']).split(/\r?\n/)[0];
  if (!/^Blender\s4\.5\.\d+/.test(version)) fail('Blender 4.5.x is required; found: ' + version);
  let destination = null;
  function admitDestination(file) {
    runtime.projectPath(root, file);
    if (runtime.within(info.root, file)) fail('Inspection output cannot replace the read-only Bubo dependency.');
    if (runtime.samePath(file, scene) || runtime.samePath(file, blender)) fail('Inspection output cannot replace a registered input or native tool.');
    for (const scope of ['requests', 'bubo-host', 'bubo-executions']) {
      const ledger = path.join(root, '.opencaw/.cache/tasks/blender-inspection', scope);
      if (runtime.within(ledger, file)) fail('Inspection execution receipts and input references are read-only.');
    }
  }
  if (values.has('--output')) {
    destination = runtime.projectPath(root, path.resolve(runtime.native(values.get('--output'))));
    admitDestination(destination);
    if (!fs.statSync(path.dirname(destination)).isDirectory()) fail('Output parent must be an existing directory.');
    if (fs.existsSync(destination) && (!fs.statSync(destination).isFile() || !values.get('--replace'))) fail('Output exists or is not a regular file; use --replace for an existing report.');
  }
  if (values.get('--dry-run')) {
    console.log(`Blender: ${blender}\nVersion: ${version}\nScene: ${path.relative(root, scene)}\nProfile: ${profile}\nOutput: ${destination || 'stdout'}\nFlags: --background --factory-startup --disable-autoexec --offline-mode --python-exit-code 1`); return;
  }
  const task = 'blender-inspection', stateRoot = '.opencaw/.cache/tasks/' + task;
  const relative = full => path.relative(root, full).split(path.sep).join('/');
  const id = crypto.randomUUID();
  const folder = runtime.projectPath(root, stateRoot + '/requests/' + id);
  fs.mkdirSync(folder, { recursive: true }); runtime.components(folder);
  const policyFile = path.join(folder, 'inspection-policy.json');
  const jobFile = path.join(folder, 'job.json');
  const output = '.art-staging/blender-inspection/' + id + '/report.json';
  fs.writeFileSync(policyFile, JSON.stringify({ schemaVersion: 1, purpose: 'read-only-blender-inspection', profile, scene: relative(scene), safeBackground: true, autoExecution: false, offline: true, sourceReadOnly: true }, null, 2) + '\n', { flag: 'wx' });
  fs.writeFileSync(jobFile, JSON.stringify({ schemaVersion: 1, scene: relative(scene), profile, output }, null, 2) + '\n', { flag: 'wx' });
  const context = { schemaVersion: 'bubo-host-context/v1', projectRoot: root, task,
    roots: { state: stateRoot, staging: '.art-staging/blender-inspection', inputs: runtime.within(root, info.folder) ? [relative(info.folder)] : [], tools: [], outputs: [] },
    policy: { purpose: 'read-only-blender-inspection', receipt: { path: relative(policyFile), sha256: runtime.hash(policyFile) } },
    references: [policyFile, jobFile, scene].map(file => ({ path: relative(file), sha256: runtime.hash(file), kind: file === policyFile ? 'policy' : 'input' })),
    tools: [{ path: blender, sha256: runtime.hash(blender), kind: 'selected-native-tool' }],
    budgets: { timeoutSeconds: 180, maxLogBytes: 16777216 }, permissions: { provisioning: false, promotion: false } };
  const options = new Map([['root', root], ['manifest', relative(jobFile)], ['blender', blender]]);
  await host.execute('blender-inspection', 'inspect', options, { root, task, stateRoot, context }, info, false);
  const reportFile = runtime.projectPath(root, output);
  host.policyCommand('validate-blender-scene-report.sh', [reportFile, '--root', root], root, false);
  if (runtime.hash(scene) !== context.references[2].sha256) fail('Inspection source bytes changed.');
  if (destination) {
    admitDestination(destination);
    if (fs.existsSync(destination) && !values.get('--replace')) fail('Output appeared during inspection.');
    const temporary = path.join(path.dirname(destination), '.opencaw-inspection-' + id + '.tmp');
    fs.copyFileSync(reportFile, temporary, fs.constants.COPYFILE_EXCL);
    try {
      admitDestination(destination);
      if (values.get('--replace')) fs.renameSync(temporary, destination);
      else fs.linkSync(temporary, destination); // Atomic exclusive publication.
    }
    finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    console.log(destination);
  } else process.stdout.write(fs.readFileSync(reportFile, 'utf8'));
}
if (require.main === module) main(process.argv.slice(2)).catch(error => { console.error(error.message); process.exitCode = 1; });
module.exports = { main };
