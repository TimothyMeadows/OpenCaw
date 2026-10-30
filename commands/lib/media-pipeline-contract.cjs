'use strict';

// Independent host production contexts. No model discovery, execution or provider selection.
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const runtime = require('./bubo-runtime.cjs');
const styles = require('./style-contract.cjs');
const BASE = path.resolve(__dirname, '../..');
const DOMAINS = ['AUDIO', 'MUSIC', 'VOICE'];
const fail = message => { throw new Error(message); };
const canonical = value => JSON.stringify(runtime.canonical(value));
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const normalize = value => typeof value === 'string' ? value.trim().toLowerCase().replace(/[ _]+/g, '-') : '';
const own = (value, key) => Object.hasOwn(value, key);

function rootDirectory(argument) {
  if (typeof argument !== 'string' || !argument) fail('Explicit resolved --root is required; no workspace parent is inferred.');
  const value = runtime.native(argument); runtime.syntax(value);
  const root = path.resolve(value); runtime.components(root);
  if (!fs.statSync(root).isDirectory()) fail('Project root must be a real directory.');
  return root;
}
function read(file, maximum = 1048576) {
  runtime.components(file);
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || stat.size > maximum) fail('Pipeline policy must be a bounded regular file.');
  const bytes = fs.readFileSync(file);
  if (bytes.length > maximum) fail('Pipeline policy exceeded its read bound.');
  return { bytes, text: bytes.toString('utf8').replace(/\r\n/g, '\n'), sha256: digest(bytes) };
}
function shared(relative) {
  return runtime.projectPath(BASE, '.media/pipelines/' + relative);
}
function registry() {
  const value = JSON.parse(read(shared('registry.json')).text);
  if (!value || value.schemaVersion !== 1 || Object.keys(value).sort().join(',') !== 'domains,schemaVersion'
      || !value.domains || Object.keys(value.domains).sort().join(',') !== DOMAINS.join(',')) fail('Invalid media-domain registry.');
  const domainNames = new Map(), modalities = new Map();
  for (const [domain, definition] of Object.entries(value.domains)) {
    if (!definition || Object.keys(definition).sort().join(',') !== 'aliases,contract,declaration,implementation,modalities,template'
        || definition.contract !== domain + '.md' || definition.declaration !== domain.toLowerCase() + '/PIPELINE.md'
        || definition.template !== domain.toLowerCase() + '/CONTRACT.md'
        || !Array.isArray(definition.aliases) || !definition.aliases.length || !definition.modalities
        || Array.isArray(definition.modalities) || !Object.keys(definition.modalities).length) fail('Invalid media-domain definition: ' + domain);
    for (const alias of [domain, ...definition.aliases]) {
      const key = normalize(alias);
      if (!key || !/^[a-z][a-z0-9-]*$/.test(key) || (domainNames.has(key) && domainNames.get(key) !== domain)) fail('Ambiguous media-domain alias.');
      domainNames.set(key, domain);
    }
    for (const [modality, aliases] of Object.entries(definition.modalities)) {
      if (!/^[a-z][a-z0-9-]*$/.test(modality) || !Array.isArray(aliases)) fail('Invalid media modality declaration.');
      for (const alias of [modality, ...aliases]) {
        const key = normalize(alias), identity = domain + ':' + modality;
        if (!key || !/^[a-z][a-z0-9-]*$/.test(key) || (modalities.has(key) && modalities.get(key) !== identity)) fail('Ambiguous media modality alias.');
        modalities.set(key, identity);
      }
    }
    const implementation = definition.implementation;
    if (!implementation || Object.keys(implementation).sort().join(',') !== 'entryPoint,status'
        || !['declared', 'implemented'].includes(implementation.status)
        || (implementation.status === 'declared' && implementation.entryPoint !== null)
        || (implementation.status === 'implemented' && !/^commands\/[a-z-]+\.sh$/.test(implementation.entryPoint || '')))
      fail('Invalid media implementation readiness: ' + domain);
  }
  return value;
}
function route({ domain, modality } = {}, data = registry()) {
  let selected = null, selectedModality = null;
  if (domain !== undefined && domain !== null) {
    const key = normalize(domain);
    const matches = Object.entries(data.domains).filter(([id, def]) => [id, ...def.aliases].some(alias => normalize(alias) === key));
    if (matches.length !== 1) fail('Unknown media domain; select AUDIO, MUSIC or VOICE.');
    selected = matches[0][0];
  }
  if (modality !== undefined && modality !== null) {
    const key = normalize(modality), matches = [];
    for (const [id, def] of Object.entries(data.domains))
      for (const [kind, aliases] of Object.entries(def.modalities))
        if ([kind, ...aliases].some(alias => normalize(alias) === key)) matches.push({ domain: id, modality: kind });
    if (matches.length !== 1) fail('Unknown or ambiguous modality; use SFX/ambience, instrumental/supplied-lyrics, or preset-speech/consented-cloning.');
    if (selected && selected !== matches[0].domain) fail('Explicit media domain and modality conflict.');
    selected = matches[0].domain; selectedModality = matches[0].modality;
  }
  if (!selected) fail('Select a media domain or modality, or use --all for independent contexts.');
  return { domain: selected, modality: selectedModality };
}
function reference(root, argument, optional = false) {
  const file = runtime.projectPath(root, argument);
  if (!fs.existsSync(file)) {
    // Inspect even dangling links; components() above rejects them before existence.
    if (optional) return null;
    fail('Requested pipeline policy is missing: ' + argument);
  }
  const value = read(file);
  return { path: path.relative(root, file).split(path.sep).join('/'), sha256: value.sha256 };
}
function sections(text, heading) {
  const lines = text.split('\n'), starts = lines.flatMap((line, index) => line === '## ' + heading ? [index] : []);
  if (starts.length !== 1) fail('Pipeline contract needs exactly one ' + heading + ' section.');
  const start = starts[0] + 1; let end = start;
  while (end < lines.length && !lines[end].startsWith('## ')) end++;
  return lines.slice(start, end).map(line => line.trim()).filter(Boolean);
}
function validate({ root: rootArgument, domain: domainArgument, contract: contractArgument } = {}) {
  const root = rootDirectory(rootArgument), data = registry();
  const { domain } = route({ domain: domainArgument }, data), definition = data.domains[domain];
  const file = runtime.projectPath(root, contractArgument || definition.contract), value = read(file);
  const { text } = value, lines = text.split('\n');
  if (!lines.includes('# ' + domain + '.md') || lines.filter(line => line === '<!-- opencaw-media-pipeline:v1 domain=' + domain + ' -->').length !== 1
      || [...text.matchAll(/<!-- opencaw-media-pipeline:v1 domain=([A-Z]+) -->/g)].length !== 1) fail('Pipeline contract identity does not match ' + domain + '.');
  if (canonical(sections(text, 'Pipeline Selection')) !== canonical(['- ' + domain])) fail('Pipeline contract must select only its own domain.');
  if (canonical(sections(text, 'Shared Media Authority')) !== canonical(['- MEDIA.md'])) fail('MEDIA.md must remain the shared media authority.');
  for (const heading of ['Provider And Execution Authority', 'Brief Requirements', 'State And Ancestry', 'Review And Promotion', 'Read Pipeline Instructions']) sections(text, heading);
  const providerPolicy = sections(text, 'Provider And Execution Authority').join('\n');
  if (!providerPolicy.includes('Provider selection comes from MEDIA.md and explicit task authorization.')
      || !/Never switch or fall back between providers silently\./.test(providerPolicy)
      || !/explicit promotion authorization/.test(sections(text, 'Review And Promotion').join('\n'))
      || !/shared approval-bound native media-state root/.test(sections(text, 'State And Ancestry').join('\n')))
    fail('Pipeline contract lacks provider, shared-allowance or separate promotion boundaries.');
  const declaration = read(shared(definition.declaration));
  const inlineStart = '<!-- opencaw-media-inline:start -->\n', inlineEnd = '\n<!-- opencaw-media-inline:end -->';
  const inline = text.includes(inlineStart) || text.includes(inlineEnd);
  const directives = [...text.matchAll(/^Read `([^`]+)` instructions\s*$/gm)];
  if (inline) {
    if (directives.length || text.split(inlineStart).length !== 2 || text.split(inlineEnd).length !== 2
        || text.split(inlineStart)[1].split(inlineEnd)[0].trim() !== declaration.text.trim()) fail('Inline pipeline definition is stale, mixed or malformed; regenerate explicitly.');
  } else {
    if (directives.length !== 1) fail('Pipeline contract needs one matching read directive or current inline definition.');
    const target = runtime.projectPath(root, directives[0][1].replace(/^\.\//, ''));
    if (read(target).text.trim() !== declaration.text.trim()
        || !directives[0][1].replace(/\\/g, '/').endsWith('/.media/pipelines/' + definition.declaration))
      fail('Pipeline read directive does not identify the selected shared declaration.');
  }
  return { schemaVersion: 1, domain, contract: { path: path.relative(root, file).split(path.sep).join('/'), sha256: value.sha256 }, mode: inline ? 'inline' : 'link' };
}
function render({ root: rootArgument, domain: domainArgument, inline = false } = {}) {
  const root = rootDirectory(rootArgument), data = registry();
  const { domain } = route({ domain: domainArgument }, data), definition = data.domains[domain];
  const template = read(shared(definition.template)).text;
  if (template.split('{{DEFINITION}}').length !== 2) fail('Domain contract template requires one definition placeholder.');
  const mounted = runtime.samePath(root, BASE) ? '.' : './.opencaw';
  const declaration = read(shared(definition.declaration)).text.trim();
  const instructions = '## Read Pipeline Instructions\n\n' + (inline
    ? '<!-- opencaw-media-inline:start -->\n' + declaration + '\n<!-- opencaw-media-inline:end -->'
    : 'Read `' + mounted + '/.media/pipelines/' + definition.declaration + '` instructions');
  return { domain, content: template.replace('{{DEFINITION}}', instructions).trimEnd() + '\n' };
}
function generate(options = {}) {
  const root = rootDirectory(options.root), rendered = render(options), data = registry();
  const output = runtime.projectPath(root, options.output || data.domains[rendered.domain].contract);
  if (fs.existsSync(output)) {
    if (read(output).text !== rendered.content) fail('Existing domain contract differs; preserve it and use a fresh --output or edit it explicitly.');
    return { ...validate({ root, domain: rendered.domain, contract: output }), created: false };
  }
  // Validate before installing any bytes, including read targets in link mode.
  if (!options.inline) {
    const directive = rendered.content.match(/^Read `([^`]+)` instructions$/m);
    const target = runtime.projectPath(root, directive[1].replace(/^\.\//, ''));
    if (read(target).text.trim() !== read(shared(data.domains[rendered.domain].declaration)).text.trim()) fail('Missing or stale installed shared domain declaration.');
  }
  runtime.components(path.dirname(output)); fs.mkdirSync(path.dirname(output), { recursive: true });
  runtime.components(output); fs.writeFileSync(output, rendered.content, { flag: 'wx', mode: 0o600 });
  return { ...validate({ root, domain: rendered.domain, contract: output }), created: true };
}
function resolve(options = {}) {
  const root = rootDirectory(options.root), data = registry();
  const selected = route(options, data), definition = data.domains[selected.domain];
  const contractPath = options.contract || definition.contract;
  const contract = reference(root, contractPath, !options.contract);
  if (contract) validate({ root, domain: selected.domain, contract: contract.path });
  const mediaPath = options.media || 'MEDIA.md', media = reference(root, mediaPath, !options.media);
  const declaration = read(shared(definition.declaration)), template = read(shared(definition.template));
  const unavailableReasons = [];
  if (!contract) unavailableReasons.push('Configure ' + definition.contract + ' explicitly before this domain workflow.');
  if (!media) unavailableReasons.push('MEDIA.md is absent; provider/setup/generation authorization remains unconfigured.');
  let entryPoint = null;
  if (definition.implementation.status === 'implemented') {
    const file = runtime.projectPath(BASE, definition.implementation.entryPoint);
    entryPoint = { path: definition.implementation.entryPoint, sha256: read(file).sha256 };
  } else unavailableReasons.push('Domain workflow execution is not implemented in this revision.');
  const relative = argument => path.relative(root, runtime.projectPath(root, argument)).split(path.sep).join('/');
  const policySha256 = digest(canonical({ schemaVersion: 1, ...selected, definition, declarationSha256: declaration.sha256,
    templateSha256: template.sha256, contractPath: relative(contractPath), contract, mediaPath: relative(mediaPath), media, entryPoint }));
  return { schemaVersion: 1, ...selected, configured: Boolean(contract), contract, media, policySha256,
    executionAvailable: Boolean(contract && media && entryPoint), nativeReadiness: 'unverified', entryPoint, unavailableReasons,
    definition: { ...definition, declarationSha256: declaration.sha256, templateSha256: template.sha256 } };
}
function resolveAll(options = {}) {
  if (options.domain || options.modality || options.contract) fail('Aggregate loading does not accept a single-domain selection/contract.');
  const root = rootDirectory(options.root), contexts = {};
  if ((options.style || options.override) && !options.visual) fail('--style/--override require explicitly requested --visual loading.');
  if (options.visual) {
    const file = runtime.projectPath(root, options.style || 'STYLE.md');
    if (fs.existsSync(file)) {
      read(file); contexts.visual = { configured: true, ...styles.resolve(root, file, { override: options.override }) };
    } else if (options.style || options.override) fail('Requested visual contract is missing.');
    else contexts.visual = { configured: false, pipeline: null, styleContract: null, styleSha256: null, unavailableReason: 'STYLE.md is absent; no visual pipeline was selected.' };
  }
  for (const domain of DOMAINS) contexts[domain.toLowerCase()] = resolve({ root, domain, media: options.media });
  return { schemaVersion: 1, contexts };
}
function main(args) {
  const operation = args.shift();
  if (args.includes('--help') || args.includes('-h')) {
    console.log('Independent media contracts: generate DOMAIN [--root ROOT] [--output FILE] [--inline]; validate DOMAIN [--root ROOT] [--contract FILE]; resolve [DOMAIN|--domain DOMAIN|--modality MODALITY] [--all] [--visual] [--root ROOT] [--contract FILE] [--media FILE] [--style FILE] [--override VISUAL_PIPELINE]. JSON results. No model/provider/setup/generation side effects.'); return;
  }
  const options = {}, values = new Set(['root','domain','modality','contract','media','output','style','override']);
  const booleans = new Set(['inline','all','visual','json']);
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (!arg.startsWith('--')) {
      if (options.domain) fail('Only one explicit domain is allowed.'); options.domain = arg; continue;
    }
    const key = arg.slice(2);
    if (own(options, key)) fail('Duplicate pipeline option: ' + arg);
    if (booleans.has(key)) options[key] = true;
    else if (values.has(key) && args[index+1] && !args[index+1].startsWith('--')) options[key] = args[++index];
    else fail('Unknown or missing pipeline option: ' + arg);
  }
  const allowed = { generate: ['root','domain','output','inline','json'], validate: ['root','domain','contract','json'], resolve: ['root','domain','modality','contract','media','all','visual','style','override','json'] }[operation];
  if (!allowed || Object.keys(options).some(key => !allowed.includes(key))) fail('Option is unavailable for the requested pipeline operation.');
  let result;
  if (operation === 'generate') result = generate(options);
  else if (operation === 'validate') result = validate(options);
  else if (options.all || (!options.domain && !options.modality)) result = resolveAll(options);
  else {
    if (options.visual || options.style || options.override) fail('Visual composition requires --all --visual.');
    result = resolve(options);
  }
  console.log(JSON.stringify(result, null, 2));
}
module.exports = { BASE, DOMAINS, registry, route, normalize, rootDirectory, render, generate, validate, resolve, resolveAll };
if (require.main === module) { try { main(process.argv.slice(2)); } catch (error) { console.error(error.message); process.exitCode = 1; } }
