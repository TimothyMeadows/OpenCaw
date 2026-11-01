'use strict';

// One host policy implementation for public commands and runtime adapters.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const engines = require('./engine-contract.cjs');
const BASE = path.resolve(__dirname, '../..');
const contracts = { CLOUD: 'cloud', LOCAL: 'local', PROOF_TO_MODEL: 'proof-to-model', CODE: 'code', BLENDER: 'blender' };
const native = value => process.platform === 'win32' ? value.replace(/^\/(?:mnt\/)?([A-Za-z])\//, (_, drive) => drive.toUpperCase() + ':/') : value;
const fail = message => { throw new Error(message); };
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const regular = file => fs.existsSync(file) && fs.statSync(file).isFile();
const contract = pipeline => '.styles/.pipelines/' + contracts[pipeline] + '/PIPELINE.md';
function normalize(raw) {
  const value = raw.replace(/[- ]/g, '_').toUpperCase();
  const aliases = { IMAGEGEN: 'CLOUD', IMAGE_GEN: 'CLOUD', '2D_TO_3D': 'PROOF_TO_MODEL', THREE: 'CODE', THREEJS: 'CODE', THREE_JS: 'CODE', BLEND: 'BLENDER', BPY: 'BLENDER' };
  if (['COMFYUI', 'COMFY_UI'].includes(value)) fail('ComfyUI execution is retired. Select LOCAL explicitly for pinned Bubo execution; historical receipts remain valid history.');
  if (['CSS', 'CSS3', 'CSS_VECTOR', 'VECTOR'].includes(value)) fail('CSS3 is retired. Select PROOF_TO_MODEL for 2D-to-3D assets, or CODE/BLENDER explicitly; regenerate STYLE.md with --pipeline PROOF_TO_MODEL. CSS/SVG interface work remains available outside art pipelines.');
  if (Object.hasOwn(contracts, value)) return value;
  if (Object.hasOwn(aliases, value)) return aliases[value];
  fail('Unknown art pipeline override: ' + raw);
}
function list(lines, heading, end) {
  let active = false; const values = [];
  for (const line of lines) {
    if (line === heading) { active = true; continue; }
    if (end.test(line)) active = false;
    if (active && line.startsWith('- ')) values.push(line.slice(2));
  }
  return values;
}
function validate(styleArgument) {
  const styleFile = path.resolve(native(styleArgument));
  if (!fs.statSync(styleFile).isFile() || fs.statSync(styleFile).size > 8 * 1024 * 1024) fail('STYLE.md must be a bounded regular policy file.');
  const bytes = fs.readFileSync(styleFile);
  if (bytes.length > 8 * 1024 * 1024) fail('STYLE.md exceeds the bounded host policy size.');
  const text = bytes.toString('utf8').replace(/\r\n/g, '\n'), lines = text.split('\n'), errors = [];
  const requirePolicy = (valid, message) => { if (!valid) errors.push(message); };
  requirePolicy(lines.includes('# STYLE.md'), 'STYLE.md is missing the expected top-level heading.');
  const styles = list(lines, 'Generated from Hephaera style templates:', /^Primary Hephaera art pipeline:/);
  const primary = list(lines, 'Primary Hephaera art pipeline:', /^Allowed Hephaera art pipelines:/);
  const allowed = list(lines, 'Allowed Hephaera art pipelines:', /^---$/);
  requirePolicy(styles.length > 0, 'STYLE.md does not list any generated Hephaera style templates.');
  requirePolicy(primary.length === 1, 'STYLE.md must list exactly one primary Hephaera art pipeline.');
  requirePolicy(allowed.length > 0, 'STYLE.md must list at least one allowed Hephaera art pipeline.');
  const styleIndex = fs.readFileSync(path.join(BASE, '.styles/INDEX.md'), 'utf8');
  const pipelineIndex = fs.readFileSync(path.join(BASE, '.styles/.pipelines/INDEX.md'), 'utf8');
  const seen = new Set();
  for (const pipeline of allowed) {
    let canonical; try { canonical = normalize(pipeline); } catch (error) { canonical = null; errors.push(error.message); }
    requirePolicy(canonical === pipeline, 'Invalid canonical art pipeline in STYLE.md: ' + pipeline);
    requirePolicy(!seen.has(pipeline), 'Duplicate allowed art pipeline in STYLE.md: ' + pipeline); seen.add(pipeline);
    if (canonical === pipeline) {
      requirePolicy(regular(path.join(BASE, contract(pipeline))), 'Missing referenced art pipeline contract: ' + contract(pipeline));
      requirePolicy(pipelineIndex.includes('- `' + pipeline + '`'), 'Art pipeline is not indexed: ' + pipeline);
    }
  }
  if (primary.length === 1) requirePolicy(seen.has(primary[0]), 'Primary art pipeline is not present in the allowed pipeline list: ' + primary[0]);
  for (const style of styles) {
    requirePolicy(/^[A-Z0-9]+(?:_[A-Z0-9]+)*$/.test(style), 'Invalid style template name in STYLE.md: ' + style);
    requirePolicy(/^[A-Z0-9]+(?:_[A-Z0-9]+)*$/.test(style) && regular(path.join(BASE, '.styles', style + '.md')), 'Missing referenced style template: ' + style);
    requirePolicy(styleIndex.includes('- ' + style), 'Referenced style template is not listed in .styles/INDEX.md: ' + style);
  }
  if (lines.some(line => line.startsWith('This document intentionally stays concise by referencing selected style and pipeline templates.'))) {
    for (const style of styles) requirePolicy(text.includes('.styles/' + style + '.md'), 'Link-mode STYLE.md is missing a read directive for: ' + style);
    for (const pipeline of allowed) if (Object.hasOwn(contracts, pipeline)) requirePolicy(text.includes(contract(pipeline)), 'Link-mode STYLE.md is missing a pipeline read directive for: ' + pipeline);
  }
  for (const match of text.matchAll(/\.styles\/([A-Z0-9_]+)\.md/g)) requirePolicy(regular(path.join(BASE, '.styles', match[1] + '.md')), 'STYLE.md read directive points to a missing style template: ' + match[1]);
  requirePolicy(/prompt override.*does not rewrite|prompt.*does not rewrite.*STYLE\.md/i.test(text), 'STYLE.md lacks the task-local prompt override rule.');
  requirePolicy(/never (switch or )?fall back.*silently|never.*silently.*fall back/i.test(text), 'STYLE.md lacks the no-silent-fallback rule.');
  const heading = '## External Asset Libraries', headings = lines.filter(line => line === heading).length;
  requirePolicy(headings <= 1, 'STYLE.md contains more than one External Asset Libraries section.');
  const libraries = [], ids = new Set(), paths = new Set();
  if (headings) {
    for (const line of lines.slice(lines.indexOf(heading) + 1)) {
      if (line.startsWith('#')) break;
      if (!line.startsWith('- ')) continue;
      const match = line.match(/^- ([a-z0-9][a-z0-9-]{0,62}): `([^`]*)`$/);
      if (!match) { errors.push('Malformed external asset library entry in ' + styleFile + ': ' + line); continue; }
      const [, id, libraryPath] = match, normalized = libraryPath.replace(/\\/g, '/');
      const absolute = libraryPath.startsWith('/') ? libraryPath !== '/' : /^[A-Za-z]:[\\/].+/.test(libraryPath) || /^\\\\[^\\/]+[\\/][^\\/]+[\\/].+/.test(libraryPath);
      requirePolicy(absolute && !/[\r\n\t`]/.test(libraryPath) && libraryPath === libraryPath.trim() && !libraryPath.includes('://') && !normalized.split('/').some(part => part === '.' || part === '..'), 'External asset library path must be an absolute filesystem path without traversal or control characters: ' + libraryPath);
      const key = /^[A-Za-z]:[\\/]|^\\\\/.test(libraryPath) ? libraryPath.toLowerCase() : libraryPath;
      requirePolicy(!ids.has(id), 'Duplicate external asset library id in STYLE.md: ' + id);
      requirePolicy(!paths.has(key), 'Duplicate external asset library path in STYLE.md: ' + libraryPath);
      ids.add(id); paths.add(key); libraries.push({ id, path: libraryPath, readOnly: true });
    }
    requirePolicy(libraries.length > 0, 'External Asset Libraries section must contain at least one configured library.');
  }
  if (libraries.length) {
    requirePolicy(/external librar(y|ies).*before creating or downloading|before creating or downloading.*external librar(y|ies)/i.test(text), 'STYLE.md external asset policy must prefer configured libraries before creating or downloading models.');
    requirePolicy(/external librar(y|ies).*read-only|read-only.*external librar(y|ies)/i.test(text), 'STYLE.md external asset policy must declare libraries read-only.');
    requirePolicy(/assets\/models\/.+before (loading|importing|editing)|before (loading|importing|editing).+assets\/models\//i.test(text), 'STYLE.md external asset policy must require copying into assets/models before use.');
  }
  if (errors.length) fail([...new Set(errors)].join('\n'));
  return { styleFile, sha256: digest(bytes), styles, primary: primary[0], allowed, libraries };
}
function resolve(rootArgument, styleArgument, options = {}, validated = null) {
  const root = path.resolve(native(rootArgument));
  const style = engines.inside(root, native(styleArgument || path.join(root, 'STYLE.md')));
  const value = validated || validate(style.absolute);
  if (value.styleFile !== style.absolute) fail('Validated STYLE identity does not match the selected contract.');
  const pipeline = options.override ? normalize(options.override) : value.primary;
  if (pipeline === 'CODE') {
    if (options.engineEvidence && !options.engineOutput) fail('An engine override requires --engine-output.');
    engines.requireEngine(root, 'THREEJS', options.engineEvidence ? { evidence: options.engineEvidence, output: options.engineOutput } : {});
  }
  return { schemaVersion: 1, pipeline, selectionSource: options.override ? 'prompt' : 'style', styleContract: style.relative,
    styleSha256: value.sha256, fallbackPolicy: 'stop', resolvedAt: new Date().toISOString() };
}
function main(args) {
  const operation = args.shift();
  if (args.includes('--help') || args.includes('-h')) { console.log('Host style policy: validate [STYLE.md]; resolve [--style FILE] [--override PIPELINE] [--json] [--evidence TASK_FILE] [--engine-evidence FILE --engine-output SOURCE]; libraries [--style FILE] [--json].'); return; }
  const options = {}, fields = { '--root': 'root', '--style': 'style', '--override': 'override', '--evidence': 'evidence', '--engine-evidence': 'engineEvidence', '--engine-output': 'engineOutput' };
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === '--json') options.json = true;
    else if (fields[arg]) { if (!args[index + 1] || args[index + 1].startsWith('--') || options[fields[arg]]) fail('Missing or duplicate ' + arg); options[fields[arg]] = args[++index]; }
    else if (operation === 'validate' && !arg.startsWith('-') && !options.style) options.style = arg;
    else fail('Unknown argument: ' + arg);
  }
  const allowed = { validate: ['root', 'style'], libraries: ['root', 'style', 'json'], resolve: ['root', 'style', 'json', 'override', 'evidence', 'engineEvidence', 'engineOutput'] };
  if (!allowed[operation]) fail('Unknown host style operation.');
  for (const name of Object.keys(options)) if (!allowed[operation].includes(name)) fail('Unsupported option for ' + operation + ': ' + name);
  const root = path.resolve(native(options.root || fail('Explicit resolved host root is required.'))), style = validate(options.style || path.join(root, 'STYLE.md'));
  if (operation === 'validate') console.log('Style contract validation passed.\nReferenced styles: ' + style.styles.join(' ') + '\nPrimary art pipeline: ' + style.primary + '\nAllowed art pipelines: ' + style.allowed.join(' ') + '\nExternal asset libraries: ' + (style.libraries.map(item => item.id).join(' ') || 'none'));
  else if (operation === 'libraries') {
    if (options.json) console.log(JSON.stringify(style.libraries, null, 2));
    else console.log('EXTERNAL_ASSET_LIBRARY_COUNT=' + style.libraries.length + style.libraries.map(item => '\n' + item.id + '\t' + item.path).join(''));
  } else if (operation === 'resolve') {
    const selected = resolve(root, style.styleFile, options, style);
    if (options.evidence) {
      const tasks = fs.realpathSync(path.join(root, '.hephaera/.cache/tasks'));
      const output = engines.inside(root, path.resolve(native(options.evidence))).absolute;
      const relative = path.relative(tasks, output);
      if (!relative || relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) fail('Evidence output must stay below .hephaera/.cache/tasks.');
      fs.mkdirSync(path.dirname(output), { recursive: true }); engines.inside(root, output);
      fs.writeFileSync(output, JSON.stringify(selected, null, 2) + '\n');
    }
    if (options.json) console.log(JSON.stringify(selected, null, 2));
    else console.log('ART_PIPELINE=' + selected.pipeline + '\nSELECTION_SOURCE=' + selected.selectionSource + '\nSTYLE_SHA256=' + selected.styleSha256 + (options.evidence ? '\nEVIDENCE_FILE=' + options.evidence : ''));
  } else fail('Unknown host style operation.');
}
module.exports = { validate, resolve, normalize };
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; } }
