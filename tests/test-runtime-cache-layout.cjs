'use strict';

// Real temporary filesystem/process checks. No game engine, package download,
// external API or asset promotion is involved.
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const engine = require('../commands/lib/engine-contract.cjs');
const { relativeInside } = require('../commands/lib/code-model-cli.cjs');
const base = path.resolve(__dirname, '..');
const runtime = fs.mkdtempSync(path.join(base, 'tests/.cache-layout-runtime-'));
let checks = 0;
function check(value, message) { assert(value, message); checks++; }
function rejects(action, pattern) { assert.throws(action, pattern); checks++; }
function project(name) { const p = path.join(runtime, name); fs.mkdirSync(p); return p; }
function write(root, file, value) { const p = path.join(root, file); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, value); }
function copy(library, root, evidence) {
  return cp.spawnSync(process.execPath, [path.join(base, 'commands/lib/external-asset-library.js'), 'copy', library, root, 'fixture', 'model.glb', 'a'.repeat(64), path.join(root, evidence)], { encoding: 'utf8' });
}
try {
  const library = project('library'); write(library, 'model.glb', 'File-copy fixture; not a geometry acceptance test.');
  const fresh = project('fresh');
  const receipt = '.hephaera/.cache/tasks/copy/copy.json';
  const result = copy(library, fresh, receipt);
  check(result.status === 0, result.stderr);
  check(fs.existsSync(path.join(fresh, receipt)), 'fresh copy writes task evidence to the installed private cache');
  check(fs.existsSync(path.join(fresh, 'assets/models/fixture/model.glb')), 'asset copy retains the runtime asset destination');
  check(!fs.existsSync(path.join(fresh, '.ai')), 'fresh copy creates no retired state directory');

  // Windows Node can report access denial when inspecting a WSL-created link.
  // Deny the operation without claiming that permission denial proves a link.
  const inspect = fs.lstatSync;
  const blockedComponent = path.join(fresh, '.hephaera', '.cache');
  try {
    for (const code of ['EACCES', 'EPERM', 'ELOOP']) {
      fs.lstatSync = function (file, ...args) {
        if (file === blockedComponent) { const error = new Error('inspection denied'); error.code = code; throw error; }
        return inspect.call(fs, file, ...args);
      };
      const message = new RegExp(`Cannot inspect a path component \\(${code}\\); a symbolic link or permission boundary`);
      rejects(() => relativeInside(fresh, receipt, 'Task evidence'), message);
      rejects(() => engine.inside(fresh, receipt), message);
    }
  } finally { fs.lstatSync = inspect; }

  const retired = project('retired');
  const denied = copy(library, retired, '.ai/tasks/copy/copy.json');
  check(denied.status === 1 && denied.stderr.includes('.hephaera/.cache/tasks'), 'retired copy-evidence path is rejected');
  check(!fs.existsSync(path.join(retired, 'assets')), 'retired evidence does not authorize an asset copy');

  for (const component of ['.hephaera', '.hephaera/.cache']) {
    const root = project(component === '.hephaera' ? 'mount-link' : 'cache-link');
    const target = path.join(root, 'elsewhere'); fs.mkdirSync(target);
    const link = path.join(root, component); fs.mkdirSync(path.dirname(link), { recursive: true });
    try { fs.symlinkSync(target, link, process.platform === 'win32' ? 'junction' : 'dir'); }
    catch (error) {
      if (!['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) throw error;
      console.log(`BLOCKED: symlink fixture ${component} unavailable (${error.code}).`);
      continue;
    }
    rejects(() => relativeInside(root, receipt, 'Task evidence'), /symbolic links/);
    rejects(() => engine.inside(root, receipt), /symbolic links/);
    const blocked = copy(library, root, receipt);
    check(blocked.status === 1 && blocked.stderr.includes('safe directory'), `${component} link rejected by direct asset-copy process`);
    check(fs.readdirSync(target).length === 0, `${component} link target remains untouched`);
    fs.unlinkSync(link);
  }

  const producer = project('producer');
  for (const [kind, operation, args] of [
    ['model', 'create', ['fixture', '--output', '.ai/tasks/fixture/model.json']],
    ['model', 'record', ['.ai/tasks/fixture/model.json']],
    ['character', 'create', ['fixture', '--manifest', '.ai/tasks/fixture/model.json']],
    ['model', 'record', ['.hephaera/.cache/tasks/fixture/model.json', '--evidence', 'front=.ai/tasks/fixture/front.png']]
  ]) rejects(() => engine.codeProduction(producer, kind, operation, args), /\.ai layout is retired/);
  check(!fs.existsSync(path.join(producer, '.ai')), 'retired CODE receipts are rejected without creating their paths');
  console.log(`Runtime cache layout tests passed (${checks} assertions).`);
} finally {
  const relative = path.relative(path.join(base, 'tests'), runtime);
  assert(relative.startsWith('.cache-layout-runtime-') && !relative.includes(path.sep));
  fs.rmSync(runtime, { recursive: true, force: true });
}
