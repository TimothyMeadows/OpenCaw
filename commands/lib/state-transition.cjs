'use strict';

// Explicit legacy-state boundary. Never imports or rewrites historical receipts.
const fs = require('node:fs'), path = require('node:path');
const LEGACY = '.opencaw/.cache', CACHE = '.hephaera/.cache', MARKER = CACHE + '/STATE_TRANSITION.json';
const BOOTSTRAP = /<!--\s*OPENCAW_BOOTSTRAP_(?:START|END)\s*-->/;
const fail = message => { throw new Error(message); };
function rootPath(value) {
  if (typeof value !== 'string' || !value || /[\x00-\x1f]/.test(value)) fail('An explicit project root is required for state transition checks.');
  const root = path.resolve(process.platform === 'win32' ? value.replace(/^\/(?:mnt\/)?([a-zA-Z])\//, (_, drive) => drive.toUpperCase() + ':/') : value);
  const stat = fs.lstatSync(root);
  if (!stat.isDirectory() || stat.isSymbolicLink()) fail('State transition root must be a real directory.');
  return root;
}
function entry(root, relative, kind) {
  let current = root;
  const parts = relative.split('/');
  for (let index = 0; index < parts.length; index++) {
    current = path.join(current, parts[index]);
    let stat;
    try { stat = fs.lstatSync(current); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
    if (stat.isSymbolicLink()) fail('State transition paths must not traverse symbolic links.');
    if (index < parts.length - 1 || kind === 'directory') {
      if (!stat.isDirectory()) fail('State transition directory collides with another file type.');
    } else if (!stat.isFile()) fail('State transition metadata must be a regular file.');
    if (index === parts.length - 1) return { path: current, stat };
  }
  return null;
}
function bootstrap(root) {
  const found = entry(root, 'AGENTS.md', 'file');
  if (!found) return false;
  if (found.stat.size > 1048576) fail('AGENTS metadata exceeds the state transition inspection bound.');
  return BOOTSTRAP.test(fs.readFileSync(found.path, 'utf8'));
}
function inspect(value) {
  const root = rootPath(value), legacy = entry(root, LEGACY, 'directory'), marker = entry(root, MARKER, 'file');
  const legacyBootstrap = bootstrap(root);
  return { schemaVersion: 'hephaera-state-transition-inspection/v1', legacyCache: LEGACY, canonicalCache: CACHE,
    marker: MARKER, legacyPresent: Boolean(legacy), markerPresent: Boolean(marker), legacyBootstrap,
    productionBlocked: Boolean(legacy || marker || legacyBootstrap), automaticMigration: false,
    notes: 'Read-only metadata discovery; no receipts, approvals, journals or private media were opened or rebound.' };
}
function assertProductionAllowed(root, operation = 'production') {
  const state = inspect(root);
  if (state.productionBlocked) fail(`State transition blocks ${operation}; run state-transition.sh inspect and review the preserved legacy state. No old approval, ledger or receipt was rebound.`);
  return state;
}
function assertBootstrapAllowed(root) {
  const state = inspect(root);
  if (state.legacyBootstrap) fail('Legacy managed AGENTS bootstrap must be migrated explicitly before Hephaera scaffolding; no second bootstrap was appended.');
  if (state.legacyPresent && !state.markerPresent) fail('Prepare the state transition explicitly before creating canonical local state: state-transition.sh prepare.');
  return state;
}
function assertIssueWritesAllowed(root, task) {
  if (typeof task !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(task)) fail('A safe task identity is required for issue transition checks.');
  const base = rootPath(root), state = inspect(base);
  if (state.markerPresent || state.legacyBootstrap || entry(base, LEGACY + '/tasks/' + task, 'directory'))
    fail('State transition blocks this task issue write; preserve and reconcile its original operation identity before creating or retrying an issue.');
  return state;
}
module.exports = { inspect, assertProductionAllowed, assertBootstrapAllowed, assertIssueWritesAllowed };
