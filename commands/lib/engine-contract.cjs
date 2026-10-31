'use strict';

// Standard-library engine selection. Cooperative guards, not an OS sandbox.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const BASE = path.resolve(__dirname, '../..');
const read = p => fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const hash = p => fs.existsSync(p) ? crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex') : null;
const registry = () => JSON.parse(read(path.join(BASE, '.engine/registry.json')));
const fail = message => { throw new Error(message); };
const normalized = value => String(value).toLowerCase().replace(/[\s._-]/g, '');
// Packaging is a capability of the effective engine, never a second selector.
// Read metadata at use time; receipts cannot inject a different packaging profile.
function packagingSelection(id) {
  const definition = registry().engines[id];
  if (!definition || !['web', 'native'].includes(definition.runtimeKind)) fail(`Invalid runtimeKind metadata for ${id}; use web or native.`);
  const web = definition.runtimeKind === 'web';
  return {
    runtimeKind: definition.runtimeKind,
    packaging: web
      ? { profile: 'MAUI', selectionSource: 'engine', platforms: ['WINDOWS', 'MACOS', 'ANDROID', 'IOS'], nativeReadiness: 'unverified' }
      : { profile: null, selectionSource: 'engine', platforms: [], nativeReadiness: 'not-applicable', reason: 'Use the selected engine native exporter.' }
  };
}
// Particle selection follows the effective engine. It advertises the supported
// integration; host package locks, installed APIs and rendering remain separate.
function particleSelection(id) {
  const definition = registry().engines[id];
  const expected = id === 'THREEJS' ? 'THREE_QUARKS' : null;
  if (!definition || !Object.hasOwn(definition, 'particleBackend') || definition.particleBackend !== expected) fail(`Invalid particleBackend metadata for ${id}; THREEJS requires THREE_QUARKS and other engines retain their own backend.`);
  return { particles: expected === null ? null : {
    backend: 'THREE_QUARKS', package: 'three.quarks', skill: 'threejs-build-particles',
    selectionSource: 'engine', renderer: 'WebGLRenderer', readiness: 'unverified',
    testedVersion: '0.17.1', testedCoreVersion: '0.17.1', minimumThreeVersion: '0.182.0'
  } };
}
function engineId(value) {
  const match = Object.entries(registry().engines).filter(([id, def]) => [id, ...def.aliases].some(a => normalized(a) === normalized(value)));
  if (match.length !== 1) fail(`Unknown or ambiguous engine '${value}'. Select THREEJS, BABYLONJS, PHASERJS, UNITY, UNREAL or GODOT with generate-engine.sh.`);
  return match[0][0];
}
function nativePath(value) {
  if (process.platform !== 'win32') return value;
  return value.replace(/^\/(?:mnt\/)?([a-zA-Z])\//, (_, drive) => `${drive.toUpperCase()}:/`);
}
function inside(root, value, label = 'Path') {
  if (!value || /[\x00-\x1f]/.test(value)) fail(`${label} is empty or contains control characters.`);
  if (value.split(/[\\/]/).includes('..')) fail(`${label} must stay inside its declared scope without traversal.`);
  const absolute = path.resolve(root, nativePath(value));
  const relative = path.relative(root, absolute);
  if (!relative || relative.startsWith('..' + path.sep) || relative === '..' || path.isAbsolute(relative)) fail(`${label} must stay inside the project root.`);
  let current = root;
  for (const part of relative.split(path.sep)) {
    if (part === '.git') fail(`${label} cannot use .git.`);
    current = path.join(current, part);
    let stat;
    try { stat = fs.lstatSync(current); }
    catch (error) {
      if (['EACCES', 'EPERM', 'ELOOP'].includes(error.code)) fail(`${label} must not be a symbolic link or traverse symbolic links. Cannot inspect a path component (${error.code}); a symbolic link or permission boundary may prevent inspection. Use an accessible regular project path.`);
      if (error.code !== 'ENOENT') throw error;
    }
    if (stat?.isSymbolicLink()) fail(`${label} must not be a symbolic link or traverse symbolic links, including dangling links.`);
  }
  return { absolute, relative: relative.split(path.sep).join('/') };
}
function contract(root, value = 'ENGINE.md') {
  const file = inside(root, value, 'Engine contract');
  if (!fs.existsSync(file.absolute)) {
    if (file.relative !== 'ENGINE.md') fail('The requested engine contract is missing.');
    return { projectEngine: registry().defaultEngine, selectionSource: 'default', contract: file.relative, contractSha256: null };
  }
  const text = read(file.absolute);
  const matches = [...text.matchAll(/^Selected OpenCaw engine:\s*\n((?:- [^\n]+\n?)+)/gm)];
  if (matches.length !== 1) fail('ENGINE.md must declare exactly one Selected OpenCaw engine block. Regenerate or migrate it explicitly.');
  const values = matches[0][1].trim().split('\n').map(v => v.replace(/^- /, '').trim());
  if (values.length !== 1 || !Object.hasOwn(registry().engines, values[0])) fail('ENGINE.md must select one canonical registered engine. Use generate-engine.sh to migrate.');
  const projectEngine = values[0];
  const directives = [...text.matchAll(/^Read `([^`]*\.engine\/([A-Z]+)\.md)` instructions\s*$/gm)];
  if (directives.some(m => m[2] !== projectEngine)) fail('ENGINE.md contains a conflicting engine read directive.');
  const expectedDefinition = fs.realpathSync(path.join(BASE, '.engine', registry().engines[projectEngine].definition));
  for (const directive of directives) {
    const target = path.resolve(root, nativePath(directive[1]));
    if (!fs.existsSync(target) || fs.realpathSync(target) !== expectedDefinition) fail('Engine read directive must resolve to its registered shared definition; repair the mount path.');
  }
  if (directives.length && text.includes('### Inline Engine Definition')) fail('ENGINE.md contains both read directives and an inline definition. Regenerate its managed block.');
  if (!directives.length) {
    const inline = text.match(/### Inline Engine Definition\n\n([\s\S]*?)\n\n<!-- opencaw-engine:end -->/);
    if (!inline || inline[1].trim() !== read(path.join(BASE, '.engine', registry().engines[projectEngine].definition)).trim()) fail('ENGINE.md needs its matching read directive or current complete generated inline definition. Regenerate stale inline content.');
  }
  return { projectEngine, selectionSource: 'contract', contract: file.relative, contractSha256: hash(file.absolute) };
}
function existingEngines(root) {
  const found = new Set();
  const add = (id, condition) => { if (condition) found.add(id); };
  add('UNITY', fs.existsSync(path.join(root, 'ProjectSettings/ProjectVersion.txt')));
  add('GODOT', fs.existsSync(path.join(root, 'project.godot')));
  add('UNREAL', fs.readdirSync(root).some(p => p.endsWith('.uproject')));
  const pkg = path.join(root, 'package.json');
  if (fs.existsSync(pkg)) {
    if (fs.lstatSync(pkg).isSymbolicLink()) fail('Engine package evidence must not be a symbolic link.');
    let data; try { data = JSON.parse(read(pkg)); } catch { fail('Malformed project package.json; resolve it before engine selection.'); }
    const deps = { ...data.dependencies, ...data.devDependencies };
    add('THREEJS', Object.hasOwn(deps, 'three'));
    add('BABYLONJS', Object.keys(deps).some(k => k === 'babylonjs' || k === '@babylonjs/core'));
    add('PHASERJS', Object.hasOwn(deps, 'phaser'));
  }
  const architecture = path.join(root, 'ARCHITECTURE.md');
  if (fs.existsSync(architecture)) {
    if (fs.lstatSync(architecture).isSymbolicLink()) fail('Legacy engine evidence must not be a symbolic link.');
    const text = read(architecture);
    for (const m of text.matchAll(/^Read `[^`]*\.architecture\/(THREEJS|BABYLONJS|PHASERJS)\.md` instructions\s*$/gm)) found.add(m[1]);
    for (const m of text.matchAll(/<!-- BEGIN TEMPLATE: (THREEJS|BABYLONJS|PHASERJS) -->/g)) found.add(m[1]);
  }
  return [...found].sort();
}
function prototypeEngines(root) {
  if (!fs.existsSync(root)) return [];
  const found = new Set(); let visited = 0;
  function visit(dir, depth) {
    if (depth > 24 || ++visited > 10000) fail('Prototype evidence scan exceeded its bound; reduce the isolated output scope.');
    for (const id of existingEngines(dir)) found.add(id);
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isSymbolicLink()) fail('Prototype output must not contain symbolic links.');
      if (entry.isDirectory() && !['.git', '.opencaw', 'node_modules', '.local', 'Library', 'Temp', 'bin', 'obj'].includes(entry.name)) visit(path.join(dir, entry.name), depth + 1);
    }
  }
  visit(root, 0); return [...found].sort();
}
function productionEngines(root) {
  const found = new Set(); let visited = 0;
  // Only this baseline's pinned execution dependency is tooling evidence. A
  // host's own runtime/bubo (or another runtime project) still selects an engine.
  const dependency = path.join(BASE, 'runtime', 'bubo');
  const isDependency = dir => process.platform === 'win32'
    ? path.resolve(dir).toLowerCase() === dependency.toLowerCase()
    : path.resolve(dir) === dependency;
  // Directory entries are single components; excluding the installed baseline
  // also excludes its private cache and historical engine fixtures.
  const excluded = new Set(['.git', '.opencaw', '.local', '.engine', '.styles', '.architecture', '.roles', 'skills', 'commands', 'tests', 'prototypes', 'node_modules', 'Library', 'Temp', 'bin', 'obj']);
  function visit(dir, depth) {
    if (isDependency(dir)) return;
    if (depth > 12 || ++visited > 20000) fail('Existing engine discovery exceeded its bound; narrow the project root or migrate engine evidence explicitly.');
    for (const id of existingEngines(dir)) found.add(id);
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory() && !entry.isSymbolicLink() && !excluded.has(entry.name)) visit(path.join(dir, entry.name), depth + 1);
    }
  }
  visit(root, 0); return [...found].sort();
}
function validateOutput(root, value, selection, hasReceipt) {
  const output = inside(root, value, 'Output');
  if (!hasReceipt && (/^prototypes\//.test(output.relative) || /^\.opencaw\/\.cache\/tasks\/[^/]+\/prototypes\//.test(output.relative))) fail('Isolated prototype writes require their recorded engine override evidence.');
  let current = root;
  for (const part of path.relative(root, path.dirname(output.absolute)).split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    if (fs.existsSync(current) && existingEngines(current).some(id => id !== selection.effectiveEngine)) fail('Output targets an existing incompatible engine project. Use the matching engine and isolated task evidence.');
  }
  return output;
}
function resolve(root, options = {}) {
  root = fs.realpathSync(nativePath(root));
  if (options.contract && path.resolve(root, nativePath(options.contract)) !== path.join(root, 'ENGINE.md') && !options.validationOnly) fail('ENGINE.md is authoritative. Alternate contracts are supported only for read-only validation, not skill activation or production.');
  const selected = contract(root, options.contract);
  const existing = productionEngines(root);
  if (existing.some(e => e !== selected.projectEngine)) fail(`Existing engine evidence (${existing.join(', ')}) conflicts with ${selected.projectEngine}. Migrate ENGINE.md and legacy architecture directives explicitly; no fallback or implicit installation was performed.`);
  const definition = path.join(BASE, '.engine', registry().engines[selected.projectEngine].definition);
  const result = { schemaVersion: 1, ...selected, effectiveEngine: selected.projectEngine, ...packagingSelection(selected.projectEngine), ...particleSelection(selected.projectEngine), definitionSha256: hash(definition), registrySha256: hash(path.join(BASE, '.engine/registry.json')), existingEngines: existing, outputScope: null, task: null };
  if (options.override && !options.recordOverride && !options.evidence) fail('An override requires --record-override --task TASK --scope prototypes/NAME, or an existing --evidence receipt.');
  if (options.recordOverride) {
    if (!options.override || !/^[a-z0-9][a-z0-9-]*$/.test(options.task || '')) fail('Record an explicit --override ENGINE and safe --task TASK.');
    const scope = inside(root, options.scope, 'Override output scope');
    const taskPrefix = `.opencaw/.cache/tasks/${options.task}/prototypes/`;
    if (!/^prototypes\/[a-z0-9][a-z0-9-]*$/.test(scope.relative) && !(scope.relative.startsWith(taskPrefix) && /^[a-z0-9][a-z0-9-]*$/.test(scope.relative.slice(taskPrefix.length)))) fail('Overrides require an isolated prototypes/NAME or .opencaw/.cache/tasks/TASK/prototypes/NAME directory. Existing game paths are not permitted.');
    const taskFile = inside(root, `.opencaw/.cache/tasks/${options.task}/TASK.md`, 'Task contract');
    if (!fs.existsSync(taskFile.absolute)) fail('An existing task contract is required before recording an override.');
    if (fs.existsSync(scope.absolute) && (!fs.statSync(scope.absolute).isDirectory() || fs.readdirSync(scope.absolute).length)) fail('Record a new override before creating prototype output; the scope must be absent or empty.');
    const receipt = { ...result, selectionSource: 'prompt', effectiveEngine: engineId(options.override), ...packagingSelection(engineId(options.override)), ...particleSelection(engineId(options.override)), task: options.task, taskSha256: hash(taskFile.absolute), outputScope: scope.relative, effectiveDefinitionSha256: hash(path.join(BASE, '.engine', registry().engines[engineId(options.override)].definition)) };
    const file = inside(root, `.opencaw/.cache/tasks/${options.task}/engine-override.json`, 'Override evidence');
    const digest = inside(root, `${file.relative}.sha256`, 'Override digest');
    if (fs.existsSync(file.absolute)) fail('Override evidence already exists. Use a new task for a different selection; do not overwrite evidence.');
    fs.writeFileSync(file.absolute, JSON.stringify(receipt, null, 2) + '\n', { flag: 'wx' });
    fs.writeFileSync(digest.absolute, hash(file.absolute) + '\n', { flag: 'wx' });
    return { ...receipt, evidence: file.relative };
  }
  if (options.evidence) {
    const file = inside(root, options.evidence, 'Override evidence');
    const digest = inside(root, `${file.relative}.sha256`, 'Override digest');
    if (!fs.existsSync(digest.absolute) || read(digest.absolute).trim() !== hash(file.absolute)) fail('Override evidence changed or has no integrity digest; review and record a new task receipt.');
    let receipt; try { receipt = JSON.parse(read(file.absolute)); } catch { fail('Missing or malformed engine override evidence.'); }
    if (!/^[a-z0-9][a-z0-9-]*$/.test(receipt.task || '') || file.relative !== `.opencaw/.cache/tasks/${receipt.task}/engine-override.json`) fail('Override evidence must belong to its recorded task.');
    const taskFile = inside(root, `.opencaw/.cache/tasks/${receipt.task}/TASK.md`, 'Task contract');
    if (receipt.schemaVersion !== 1 || receipt.selectionSource !== 'prompt' || receipt.taskSha256 !== hash(taskFile.absolute) || receipt.projectEngine !== result.projectEngine || receipt.contract !== result.contract || receipt.contractSha256 !== result.contractSha256 || receipt.definitionSha256 !== result.definitionSha256 || receipt.registrySha256 !== result.registrySha256) fail('Stale or mismatched engine override evidence; review changed contracts and create a new task receipt.');
    const effective = engineId(receipt.effectiveEngine);
    if (receipt.effectiveDefinitionSha256 !== hash(path.join(BASE, '.engine', registry().engines[effective].definition))) fail('Override engine definition changed; evidence is stale.');
    if (options.task && options.task !== receipt.task) fail('Override evidence belongs to another task.');
    if (options.override && engineId(options.override) !== effective) fail('Override selection differs from recorded evidence.');
    const scope = inside(root, receipt.outputScope, 'Override scope');
    if (!/^prototypes\/[a-z0-9][a-z0-9-]*$/.test(scope.relative) && !new RegExp(`^\\.opencaw/\\.cache/tasks/${receipt.task}/prototypes/[a-z0-9][a-z0-9-]*$`).test(scope.relative)) fail('Override scope is not an isolated prototype.');
    if (prototypeEngines(scope.absolute).some(id => id !== effective)) fail('Existing prototype engine evidence conflicts with the recorded override. Do not edit an incompatible game.');
    if (options.output) {
      const output = validateOutput(root, options.output, receipt, true);
      if (output.relative !== scope.relative && !output.relative.startsWith(scope.relative + '/')) fail('Output is outside the approved override scope.');
    }
    return { ...receipt, ...packagingSelection(effective), ...particleSelection(effective), existingEngines: existing, evidence: file.relative };
  }
  if (options.output) validateOutput(root, options.output, result, false);
  return result;
}
function classify(name) {
  const file = path.join(BASE, 'skills', name, 'SKILL.md');
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name) || !fs.existsSync(file)) fail(`Unknown skill '${name}'.`);
  const front = read(file).match(/^---\n([\s\S]*?)\n---\n/);
  if (!front) fail(`Missing skill frontmatter: ${name}`);
  const declarations = [...front[1].matchAll(/^[ \t]*(?:engines|['"]engines['"])[ \t]*:.*$/gm)];
  if (declarations.length !== 1) fail(`${name} must have exactly one engines declaration.`);
  const match = declarations[0][0].match(/^engines: \[([A-Z]+)\]\s*$/);
  const engine = match?.[1];
  if (engine !== 'AGNOSTIC' && !Object.hasOwn(registry().engines, engine || '')) fail(`${name} needs engines: [AGNOSTIC] or exactly one registered canonical engine.`);
  const prefixed = Object.entries(registry().engines).find(([, def]) => name.startsWith(def.prefix));
  if (engine === 'AGNOSTIC' ? !!prefixed : !name.startsWith(registry().engines[engine].prefix)) fail(`Engine prefix/tag mismatch: ${name}`);
  return engine;
}
function skill(root, name, options = {}) {
  const aliases = registry().skillAliases;
  const canonical = aliases[name] || name;
  const engine = classify(canonical);
  const selection = resolve(root, options);
  const compatible = engine === 'AGNOSTIC' || engine === selection.effectiveEngine;
  return { ...selection, requestedSkill: name, skill: canonical, alias: canonical !== name, engine, compatible, exclusionReason: compatible ? null : `${canonical} requires ${engine}; effective engine is ${selection.effectiveEngine}. Use a compatible feature or an explicit isolated-prototype override.`, prerequisites: engine === 'AGNOSTIC' ? 'Check the skill platform and tool prerequisites separately.' : 'Use host-selected engine version and dependencies; nothing is installed by selection.' };
}
function requireEngine(root, expected, options = {}) {
  const selected = resolve(root, options);
  if (selected.effectiveEngine !== expected) fail(`This producer requires ${expected}; effective engine is ${selected.effectiveEngine}. Three.js CODE production cannot be reinterpreted for another engine. Select an appropriate workflow; no engine or art contract was changed.`);
  if (selected.selectionSource === 'prompt' && !options.output) fail('Override producers must supply and validate every output scope before writes or tool launches.');
  return selected;
}
// Consume the same evidence for existing CODE commands without changing artifact schemas.
function codeProduction(root, kind, operation, values) {
  const remaining = [...values]; const at = remaining.indexOf('--engine-evidence');
  if (at < 0) {
    const selection = requireEngine(root, 'THREEJS');
    const flag = name => { const index = remaining.indexOf('--' + name); return index < 0 ? undefined : remaining[index + 1]; };
    const operands = []; const switches = new Set(['--planar', '--prompt-override', '--json', '--strict', '--complete']);
    for (let index = 0; index < remaining.length; index++) {
      if (!remaining[index].startsWith('--')) operands.push(remaining[index]);
      else if (!switches.has(remaining[index])) index++;
    }
    const check = value => {
      if (!value) return;
      const located = validateOutput(root, value, selection, false);
      if (located.relative === '.ai' || located.relative.startsWith('.ai/')) fail('The .ai layout is retired. Create fresh task artifacts under .opencaw/.cache/tasks/.');
    };
    const load = value => {
      if (!value) return null;
      check(value);
      const located = inside(root, value, 'Production artifact');
      if (!fs.existsSync(located.absolute)) return null;
      try { return JSON.parse(read(located.absolute)); } catch { return null; } // The artifact validator reports malformed data.
    };
    let model;
    if (kind === 'model' && operation === 'create') check(flag('source') || `src/models/${operands[0]}.ts`);
    else if (kind === 'character' && operation === 'create') model = load(flag('manifest'));
    else {
      const data = load(operands[0]);
      model = kind === 'model' ? data : load(data?.codeModel?.manifest);
      check(operands[0]);
    }
    check(model?.target?.sourcePath);
    check(flag('output')); check(flag('output-dir')); check(flag('profile')); check(flag('character-profile'));
    const evidencePaths = new Set(['--evidence', '--passing', '--failing', '--reviewer-packet', '--compare', '--measurements']);
    for (let index = 0; index < remaining.length; index++) {
      if (!evidencePaths.has(remaining[index])) continue;
      const value = remaining[index + 1];
      if (value) check(remaining[index] === '--evidence' && value.includes('=') ? value.slice(value.indexOf('=') + 1) : value);
    }
    return remaining;
  }
  const evidence = remaining[at + 1];
  if (!evidence || evidence.startsWith('--')) fail('--engine-evidence requires a receipt path.');
  remaining.splice(at, 2);
  if (remaining.includes('--engine-evidence')) fail('Duplicate --engine-evidence.');
  const selected = resolve(root, { evidence });
  if (selected.effectiveEngine !== 'THREEJS') fail('CODE production requires a THREEJS override.');
  function option(name, fallback) {
    const index = remaining.indexOf('--' + name);
    return index < 0 ? fallback : remaining[index + 1];
  }
  const operands = []; const flags = new Set(['--planar', '--prompt-override', '--json', '--strict', '--complete']);
  for (let index = 0; index < remaining.length; index++) {
    if (!remaining[index].startsWith('--')) operands.push(remaining[index]);
    else if (!flags.has(remaining[index])) index++;
  }
  const first = operands[0];
  const source = value => resolve(root, { evidence, output: value });
  function taskArtifact(value) {
    const located = inside(root, value, 'Task artifact');
    if (!located.relative.startsWith(`.opencaw/.cache/tasks/${selected.task}/`) || /(?:^|\/)(?:TASK\.md|engine-override\.json(?:\.sha256)?)$/i.test(located.relative)) fail('Override manifests and review outputs must stay in their recorded task without overwriting the task or receipt.');
    return located;
  }
  function model(value) {
    const file = taskArtifact(value);
    const data = JSON.parse(read(file.absolute)); source(data.target?.sourcePath);
  }
  function profile(value) {
    const file = taskArtifact(value); const data = JSON.parse(read(file.absolute)); model(data.codeModel?.manifest);
  }
  if (kind === 'model') {
    if (operation === 'create') { taskArtifact(option('output', `.opencaw/.cache/tasks/${first}/code-model.json`)); source(option('source', `src/models/${first}.ts`)); }
    else model(first);
  } else if (kind === 'character') {
    if (operation === 'create') { taskArtifact(option('output', `.opencaw/.cache/tasks/${first}/code-character.json`)); model(option('manifest')); }
    else profile(first);
  } else if (kind === 'evidence') {
    profile(first);
    if (operation === 'capture') { source(option('adapter')); taskArtifact(option('output-dir')); }
    else taskArtifact(option('output'));
  } else fail('Unknown CODE producer.');
  for (let index = 0; index < remaining.length; index++) {
    if (!['--evidence', '--passing', '--failing', '--reviewer-packet'].includes(remaining[index])) continue;
    const value = remaining[index + 1];
    if (value) taskArtifact(remaining[index] === '--evidence' && value.includes('=') ? value.slice(value.indexOf('=') + 1) : value);
  }
  return remaining;
}
function generate(root, value, options = {}) {
  const file = inside(root, 'ENGINE.md', 'Engine contract');
  const exists = fs.existsSync(file.absolute);
  const current = exists ? read(file.absolute) : '';
  const id = value !== undefined ? engineId(value) : contract(root).projectEngine;
  const def = registry().engines[id];
  const packaging = packagingSelection(id); // Validate metadata before any contract write.
  const particles = particleSelection(id);
  const relative = path.relative(root, BASE).split(path.sep).join('/');
  const directive = `Read \`${relative ? './' + relative + '/' : './'}.engine/${def.definition}\` instructions`;
  const body = ['<!-- opencaw-engine:start -->', '## Engine Selection', '', 'Selected OpenCaw engine:', `- ${id}`, '', options.inline ? `### Inline Engine Definition\n\n${read(path.join(BASE, '.engine', def.definition)).trim()}` : directive, '', '<!-- opencaw-engine:end -->'].join('\n');
  let content;
  if (!exists) content = `# ENGINE.md\n\nThis project selects one game engine. Architecture and art pipeline selection remain separate.\n\n${body}\n\n## Project Engine Instructions\n\nUse host-locked versions and explicit dependencies.\n`;
  else {
    const blocks = [...current.matchAll(/<!-- opencaw-engine:start -->[\s\S]*?<!-- opencaw-engine:end -->/g)];
    if (blocks.length !== 1) fail('Existing ENGINE.md has no unique managed block. Migrate it explicitly; custom content was preserved.');
    content = current.replace(blocks[0][0], body);
  }
  // Check repository evidence against the proposed contract before writing it.
  const existing = productionEngines(root);
  if (existing.some(e => e !== id)) fail(`Requested ${id} conflicts with existing ${existing.join(', ')} evidence. Migrate the existing game and legacy directives before regeneration.`);
  fs.writeFileSync(file.absolute, content);
  return { engine: id, ...packaging, ...particles, contract: 'ENGINE.md', inline: !!options.inline, customContentPreserved: exists };
}
function validateCatalog() {
  const data = registry();
  if (data.schemaVersion !== 1 || data.defaultEngine !== 'THREEJS' || JSON.stringify(Object.keys(data.engines).sort()) !== JSON.stringify(['THREEJS', 'BABYLONJS', 'PHASERJS', 'UNITY', 'UNREAL', 'GODOT'].sort())) fail('Invalid v1 engine registry.');
  const aliases = new Map();
  const registeredSkills = new Set();
  let count = 0;
  for (const [id, def] of Object.entries(data.engines)) {
    packagingSelection(id);
    particleSelection(id);
    if (def.prefix !== `${id.toLowerCase()}-` || def.definition !== `${id}.md` || !def.languages.length) fail(`Invalid definition metadata for ${id}`);
    if (!fs.existsSync(path.join(BASE, '.engine', def.definition))) fail(`Missing definition ${id}`);
    for (const a of [id, ...def.aliases]) {
      const prior = aliases.get(normalized(a));
      if (prior && prior !== id) fail(`Conflicting engine alias ${a}`);
      aliases.set(normalized(a), id);
    }
    if (!Array.isArray(def.skills) || !def.skills.length) fail(`Missing feature inventory for ${id}`);
    for (const name of def.skills) {
      if (typeof name !== 'string' || registeredSkills.has(name)) fail(`Duplicate or invalid engine feature binding ${name}`);
      if (classify(name) !== id) fail(`Invalid capability binding ${name}`);
      registeredSkills.add(name);
      count++;
    }
  }
  for (const name of fs.readdirSync(path.join(BASE, 'skills')).sort()) {
    if (fs.existsSync(path.join(BASE, 'skills', name, 'SKILL.md'))) {
      const engine = classify(name);
      if (engine !== 'AGNOSTIC' && !data.engines[engine].skills.includes(name)) fail(`Unregistered engine skill ${name}`);
    }
  }
  for (const [alias, target] of Object.entries(data.skillAliases)) {
    if (fs.existsSync(path.join(BASE, 'skills', alias))) fail(`Legacy skill directory still exists: ${alias}`);
    classify(target);
  }
  for (const [file, id] of Object.entries(data.commandBindings)) if (!fs.existsSync(path.join(BASE, file)) || !data.engines[id]) fail(`Invalid command engine binding ${file}`);
  return { valid: true, engines: 6, engineSkills: count };
}
function roleCapabilities(root, role, options) {
  const map = JSON.parse(read(path.join(BASE, '.roles/ROLE_SKILL_MAP.json')));
  if (!map[role] || role === '__shared__') fail('Use a resolved domain-qualified role ID from resolve-role.sh.');
  const selection = resolve(root, options);
  const names = [...new Set([...map.__shared__.skills, ...map[role].skills])].sort();
  const included = [], excluded = [];
  for (const name of names) {
    const item = skill(root, name, options);
    (item.compatible ? included : excluded).push(item.compatible ? item.skill : { skill: item.skill, reason: item.exclusionReason });
  }
  const commands = [], excludedCommands = [];
  for (const name of [...new Set([...map.__shared__.commands, ...map[role].commands])].sort()) {
    const bound = registry().commandBindings[name];
    if (!bound || bound === selection.effectiveEngine) commands.push(name);
    else excludedCommands.push({ command: name, reason: `Requires ${bound}; effective engine is ${selection.effectiveEngine}.` });
  }
  return { ...selection, role, skills: included, excludedSkills: excluded, commands, excludedCommands };
}
function options(values) {
  const flags = { '--inline': 'inline', '--record-override': 'recordOverride', '--json': 'json' };
  const fields = { '--contract': 'contract', '--override': 'override', '--task': 'task', '--scope': 'scope', '--evidence': 'evidence', '--output': 'output', '--require-engine': 'requiredEngine', '--command': 'command', '--assert-engine': 'assertEngine' };
  const result = { positional: [] };
  while (values.length) {
    const arg = values.shift();
    if (flags[arg]) { if (result[flags[arg]]) fail(`Duplicate ${arg}`); result[flags[arg]] = true; }
    else if (fields[arg]) { if (!values.length || values[0].startsWith('--') || result[fields[arg]]) fail(`Missing or duplicate ${arg}`); result[fields[arg]] = values.shift(); }
    else if (arg.startsWith('-')) fail(`Unknown option ${arg}`);
    else result.positional.push(arg);
  }
  return result;
}
function main() {
  const [operation, rootArg, ...values] = process.argv.slice(2);
  const root = fs.realpathSync(nativePath(rootArg));
  if (values.includes('--help') || values.includes('-h')) {
    console.log('Engine commands: generate-engine.sh [--inline] [ENGINE]; validate-engine-contract.sh [ENGINE.md]; validate-engines.sh; resolve-engine.sh [--json] [--override ENGINE --task TASK --scope prototypes/NAME --record-override | --evidence FILE --output PATH]; resolve-skill.sh SKILL [selection options]; resolve-role-capabilities.sh DOMAIN/ROLE [selection options].'); return;
  }
  const opt = options(values);
  const positional = opt.positional;
  const allowed = {
    generate: ['inline', 'json'], validate: ['contract', 'json'], catalog: ['json'],
    resolve: ['json', 'override', 'task', 'scope', 'evidence', 'output', 'recordOverride', 'requiredEngine', 'command', 'assertEngine'],
    skill: ['json', 'task', 'evidence', 'output'], role: ['json', 'task', 'evidence', 'output']
  };
  for (const key of Object.keys(opt)) if (key !== 'positional' && !allowed[operation]?.includes(key)) fail(`Option ${key} is not supported by this engine command.`);
  if (positional.length > 1) fail('Too many positional arguments.');
  if (operation === 'catalog' && positional.length) fail('validate-engines.sh does not take an engine selection.');
  if (opt.scope && !opt.recordOverride) fail('--scope is only used while recording an override.');
  if (opt.recordOverride && opt.evidence) fail('Create a receipt or consume one; do not combine --record-override with --evidence.');
  if (opt.recordOverride && operation !== 'resolve') fail('Record override evidence with resolve-engine.sh before selecting skills or roles.');
  if (opt.inline && operation !== 'generate') fail('--inline is only supported by generate-engine.sh.');
  if (operation !== 'resolve' && (opt.requiredEngine || opt.command)) fail('Command guards belong to resolve-engine.sh.');
  let result;
  if (operation === 'generate') result = generate(root, positional[0], opt);
  else if (operation === 'validate') { if (positional[0]) opt.contract = positional[0]; if (!fs.existsSync(inside(root, opt.contract || 'ENGINE.md').absolute)) fail('Missing ENGINE.md. Generate a contract, or use resolve-engine.sh for the unconfigured default.'); result = { ...resolve(root, { ...opt, validationOnly: true }), valid: true }; }
  else if (operation === 'catalog') result = validateCatalog();
  else if (operation === 'skill') { result = skill(root, positional[0], opt); if (!result.compatible) process.exitCode = 1; }
  else if (operation === 'role') result = roleCapabilities(root, positional[0], opt);
  else if (operation === 'resolve') {
    if (positional.length) fail('Use --override for an explicit task engine; positional engine selection is not supported.');
    const expected = opt.requiredEngine ? engineId(opt.requiredEngine) : registry().commandBindings[opt.command];
    if (opt.command && !expected) fail('Unknown engine-bound command.');
    result = expected ? requireEngine(root, expected, opt) : resolve(root, opt);
    if (opt.assertEngine && engineId(opt.assertEngine) !== result.effectiveEngine) fail('Handoff engine conflicts with the resolved engine. Change ENGINE.md explicitly; a handoff argument cannot select an engine.');
  } else fail(`Unknown operation ${operation}`);
  console.log(JSON.stringify(result, null, 2));
}
module.exports = { engineId, packagingSelection, particleSelection, resolve, skill, classify, requireEngine, codeProduction, generate, validateCatalog, roleCapabilities, inside, BASE };
if (require.main === module) { try { main(); } catch (error) { console.error(JSON.stringify({ error: error.message, compatible: false })); process.exitCode = 1; } }
