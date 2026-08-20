'use strict';

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { createRequire } = require('module');
const { analyze, objectSha256 } = require('./code-character-evidence-analyzer.cjs');
const { contractHashes, profileMeasurementProjection, validateProfile } = require('./code-character-cli.cjs');
const { relativeInside, rootPath, sha256 } = require('./code-model-cli.cjs');

const VIEW_IDS = new Set(['front', 'rear', 'left', 'right', 'top', 'bottom', 'orbit-left', 'orbit-right', 'hero', 'runtime']);

function fail(message) {
  throw new Error(message);
}

function readJson(file, label) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
  }
}

function parseOptions(values, repeatable = new Set()) {
  const options = { _: [] };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith('--')) {
      options._.push(value);
      continue;
    }
    const key = value.slice(2);
    if (index + 1 >= values.length || values[index + 1].startsWith('--')) fail(`--${key} requires a value.`);
    const next = values[++index];
    if (repeatable.has(key)) (options[key] ??= []).push(next);
    else if (options[key] !== undefined) fail(`--${key} may be supplied only once.`);
    else options[key] = next;
  }
  return options;
}

function rejectUnknown(options, allowed) {
  for (const key of Object.keys(options)) if (key !== '_' && !allowed.has(key)) fail(`Unknown option: --${key}`);
}

function atomicWrite(file, value) {
  const temporary = `${file}.tmp-${process.pid}-${crypto.randomBytes(5).toString('hex')}`;
  let installed = false;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { flag: 'wx' });
    fs.renameSync(temporary, file);
    installed = true;
  } finally {
    if (!installed && fs.existsSync(temporary)) fs.rmSync(temporary, { force: true });
  }
}

function regularFile(root, value, label) {
  const located = relativeInside(root, value, label, true);
  const stat = fs.lstatSync(located.absolute);
  if (!stat.isFile() || stat.isSymbolicLink()) fail(`${label} must be a regular non-symbolic-link file.`);
  return located;
}

function outputFile(root, value, label) {
  const located = relativeInside(root, value, label);
  fs.mkdirSync(path.dirname(located.absolute), { recursive: true });
  if (fs.existsSync(located.absolute)) fail(`${label} already exists: ${located.relative}`);
  if (!relativeInside(root, path.dirname(located.absolute), `${label} parent`, true)) fail(`${label} parent is unsafe.`);
  return located;
}

function reportContext(root, validated, captureMode, comparisonPath = null) {
  const source = regularFile(root, validated.linked.manifest.target.sourcePath, 'Linked code-model source');
  const hashes = contractHashes(validated.profile, validated.linked.manifest);
  const contracts = {
    profile: { path: validated.located.relative, sha256: hashes.profile, measurementSpecSha256: objectSha256(profileMeasurementProjection(validated.profile)) },
    manifest: { path: validated.linked.linked.relative, sha256: hashes.manifest },
    source: { path: source.relative, sha256: sha256(source.absolute) }
  };
  let comparison = null;
  if (comparisonPath) {
    const located = regularFile(root, comparisonPath, 'Comparison report');
    const previous = readJson(located.absolute, 'Comparison report');
    if (previous.schemaVersion !== 'opencaw-code-character-evidence/v1') fail('Comparison report has an unsupported schemaVersion.');
    if (previous.characterId !== validated.profile.characterId) fail('Comparison report belongs to a different character.');
    comparison = {
      report: { path: located.relative, sha256: sha256(located.absolute) },
      previousSourceSha256: previous.contracts?.source?.sha256 ?? null,
      changedSource: previous.contracts?.source?.sha256 !== contracts.source.sha256,
      previousOverallDecision: previous.overallDecision,
      previousGateDecisions: Object.fromEntries((previous.gateResults ?? []).map((gate) => [gate.id, gate.decision]))
    };
  }
  return { captureMode, contracts, comparison };
}

function analyzeOperation(root, values) {
  const options = parseOptions(values);
  rejectUnknown(options, new Set(['measurements', 'output', 'compare']));
  if (options._.length !== 1) fail('Analyze requires exactly one PROFILE.');
  if (!options.measurements || !options.output) fail('Analyze requires --measurements and --output.');
  const validated = validateProfile(root, null, 'strict', options._[0]);
  const measurement = regularFile(root, options.measurements, 'Measurement fixture');
  const output = outputFile(root, options.output, 'Evidence report output');
  const context = reportContext(root, validated, 'fixture', options.compare);
  context.contracts.measurements = { path: measurement.relative, sha256: sha256(measurement.absolute) };
  const report = analyze(validated.profile, validated.linked.manifest, readJson(measurement.absolute, 'Measurement fixture'), context);
  atomicWrite(output.absolute, report);
  process.stdout.write(`Analyzed untrusted calibration fixture: ${measurement.relative}\n`);
  process.stdout.write(`Evidence report: ${output.relative}\n`);
  process.stdout.write(`Machine result: ${report.overallDecision}\n`);
}

function locatePackage(root, packageName) {
  const hostRequire = createRequire(path.join(root, '__opencaw-evidence-host__.cjs'));
  let entry;
  try {
    entry = hostRequire.resolve(packageName);
  } catch {
    fail(`${packageName === 'three' ? 'Three.js' : 'Playwright'} is unavailable in the host project; install or approve it through the host architecture. OpenCaw installed nothing.`);
  }
  let current = path.dirname(entry);
  while (current !== path.dirname(current)) {
    const packageFile = path.join(current, 'package.json');
    if (fs.existsSync(packageFile)) {
      const metadata = readJson(packageFile, `${packageName} package metadata`);
      if (metadata.name === packageName || (packageName === 'playwright' && metadata.name === 'playwright-core')) {
        return { root: current, entry, metadata, hostRequire };
      }
    }
    current = path.dirname(current);
  }
  fail(`Unable to locate the installed ${packageName} package root.`);
}

function safeServeFile(response, base, relative, label) {
  const candidate = path.resolve(base, relative);
  const rel = path.relative(base, candidate);
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel) || !fs.existsSync(candidate)) {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end(`${label} not found`);
    return;
  }
  const real = fs.realpathSync(candidate);
  const realRel = path.relative(base, real);
  if (realRel.startsWith('..') || path.isAbsolute(realRel) || fs.lstatSync(candidate).isSymbolicLink()) {
    response.writeHead(403, { 'content-type': 'text/plain; charset=utf-8' });
    response.end(`${label} rejected`);
    return;
  }
  const extension = path.extname(real).toLowerCase();
  if (!['.js', '.mjs', '.json'].includes(extension)) {
    response.writeHead(415, { 'content-type': 'text/plain; charset=utf-8' });
    response.end(`${label} must be JavaScript or JSON`);
    return;
  }
  const contentType = extension === '.json' ? 'application/json; charset=utf-8' : 'text/javascript; charset=utf-8';
  response.writeHead(200, { 'content-type': contentType, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  fs.createReadStream(real).pipe(response);
}

function pageSource(adapterUrl) {
  return `<!doctype html>
<meta charset="utf-8">
<title>OpenCaw code-character evidence</title>
<style>html,body{margin:0;background:#111;color:#eee}#stage{position:relative;overflow:hidden;width:800px;height:800px}canvas{display:block}</style>
<div id="stage"></div>
<script type="module">
import * as THREE from '/three/three.module.js';
import { createCodeCharacterEvidenceAdapter } from '${adapterUrl}';
const stage = document.querySelector('#stage');
let adapter;
window.__opencawEvidence = {
  async start(config) {
    if (typeof createCodeCharacterEvidenceAdapter !== 'function') throw new Error('Adapter must export createCodeCharacterEvidenceAdapter.');
    adapter = await createCodeCharacterEvidenceAdapter({ THREE, stage, profile: config.profile, seed: config.seed });
    for (const method of ['capture','sampleStructure','sampleMotion','sampleRuntime','constructionHash','lifecycleCycle','dispose']) {
      if (typeof adapter?.[method] !== 'function') throw new Error('Adapter is missing required method: ' + method);
    }
    return true;
  },
  async capture(request) { await adapter.capture(request); if (!stage.querySelector('canvas')) throw new Error('Adapter capture must render a canvas below #stage.'); },
  async sample(config) {
    const structure = await adapter.sampleStructure(config);
    const motion = await adapter.sampleMotion(config);
    const sampled = await adapter.sampleRuntime(config);
    const constructionHashes = [];
    for (let run = 1; run <= config.constructionRuns; run += 1) constructionHashes.push(await adapter.constructionHash({ run, ...config }));
    const lifecycle = [];
    for (let cycle = 1; cycle <= config.lifecycleCycles; cycle += 1) lifecycle.push(await adapter.lifecycleCycle({ cycle, ...config }));
    return { structure, motion, runtime: { ...sampled, constructionHashes, lifecycle } };
  },
  async stop() { await adapter?.dispose(); adapter = null; }
};
</script>`;
}

async function startServer(root, threeRoot, adapter) {
  const adapterUrl = `/project/${adapter.relative.split('/').map(encodeURIComponent).join('/')}`;
  const html = pageSource(adapterUrl);
  const server = http.createServer((request, response) => {
    try {
      const url = new URL(request.url, 'http://127.0.0.1');
      if (request.method !== 'GET') {
        response.writeHead(405, { allow: 'GET' });
        response.end();
      } else if (url.pathname === '/' || url.pathname === '/index.html') {
        response.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
        response.end(html);
      } else if (url.pathname.startsWith('/three/')) {
        safeServeFile(response, path.join(threeRoot, 'build'), decodeURIComponent(url.pathname.slice('/three/'.length)), 'Three.js module');
      } else if (url.pathname.startsWith('/project/')) {
        safeServeFile(response, root, decodeURIComponent(url.pathname.slice('/project/'.length)), 'Project module');
      } else {
        response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('Not found');
      }
    } catch {
      response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('Malformed request');
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') fail('Evidence server did not receive an OS-assigned loopback port.');
  return { server, origin: `http://127.0.0.1:${address.port}` };
}

function artifactName(key) {
  return `${key.replace(/[^a-z0-9-]+/gi, '-').replace(/^-+|-+$/g, '').toLowerCase()}.png`;
}

async function captureOperation(root, values) {
  const options = parseOptions(values, new Set(['view']));
  rejectUnknown(options, new Set(['adapter', 'output-dir', 'view', 'compare', 'viewport-width', 'viewport-height', 'pixel-ratio']));
  if (options._.length !== 1) fail('Capture requires exactly one PROFILE.');
  if (!options.adapter || !options['output-dir']) fail('Capture requires --adapter and --output-dir.');
  const validated = validateProfile(root, null, 'strict', options._[0]);
  const adapter = regularFile(root, options.adapter, 'Browser evidence adapter');
  if (!/\.m?js$/i.test(adapter.relative)) fail('Browser evidence adapter must be a JavaScript ESM file.');
  const requestedViews = options.view ?? validated.profile.silhouette.requiredViews;
  for (const view of requestedViews) if (!VIEW_IDS.has(view) || view === 'runtime') fail(`Unsupported capture view: ${view}`);
  for (const view of validated.profile.silhouette.requiredViews) if (!requestedViews.includes(view)) fail(`Capture cannot omit required view: ${view}`);
  const width = Number(options['viewport-width'] ?? 800);
  const height = Number(options['viewport-height'] ?? 800);
  const pixelRatio = Number(options['pixel-ratio'] ?? 1);
  if (!Number.isInteger(width) || width < 64 || width > 4096 || !Number.isInteger(height) || height < 64 || height > 4096) fail('Viewport dimensions must be integers from 64 to 4096.');
  if (!Number.isFinite(pixelRatio) || pixelRatio < 0.5 || pixelRatio > 4) fail('Pixel ratio must be from 0.5 to 4.');

  const output = relativeInside(root, options['output-dir'], 'Evidence output directory');
  if (fs.existsSync(output.absolute)) fail(`Evidence output directory already exists: ${output.relative}`);
  fs.mkdirSync(path.dirname(output.absolute), { recursive: true });
  const realOutputParent = fs.realpathSync(path.dirname(output.absolute));
  const outputParentRelative = path.relative(root, realOutputParent);
  if (outputParentRelative.startsWith('..') || path.isAbsolute(outputParentRelative)) fail('Evidence output parent resolves outside the project root.');
  const lock = `${output.absolute}.lock`;
  try {
    fs.mkdirSync(lock);
  } catch (error) {
    if (error.code === 'EEXIST') fail(`Evidence output is locked by another capture: ${output.relative}`);
    throw error;
  }

  let server;
  let browser;
  let completed = false;
  try {
    const threePackage = locatePackage(root, 'three');
    const threeModule = path.join(threePackage.root, 'build', 'three.module.js');
    if (!fs.existsSync(threeModule)) fail('Installed Three.js does not expose build/three.module.js required by the browser harness.');
    const playwrightPackage = locatePackage(root, 'playwright');
    const playwright = playwrightPackage.hostRequire(playwrightPackage.entry);
    if (!playwright?.chromium?.launch) fail('Installed Playwright package does not expose Chromium.');
    ({ server, origin: options.origin } = await startServer(root, threePackage.root, adapter));
    try {
      browser = await playwright.chromium.launch({ headless: true, chromiumSandbox: true });
    } catch (error) {
      fail(`Playwright Chromium browser is unavailable or failed its sandboxed launch: ${error.message}. OpenCaw installed nothing and did not disable the sandbox.`);
    }
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: pixelRatio, serviceWorkers: 'block' });
    const page = await context.newPage();
    const externalRequests = [];
    await page.route('**/*', async (route) => {
      const target = new URL(route.request().url());
      if (target.origin !== options.origin) {
        externalRequests.push(target.href);
        await route.abort('blockedbyclient');
      } else await route.continue();
    });
    await page.goto(options.origin, { waitUntil: 'networkidle' });
    const seed = validated.linked.manifest.runtime.deterministicSeed;
    await page.evaluate(async ({ profile, seed: deterministicSeed }) => window.__opencawEvidence.start({ profile, seed: deterministicSeed }), { profile: validated.profile, seed });
    fs.mkdirSync(output.absolute);
    const stage = page.locator('#stage');
    const captured = [];
    const captureOne = async (request, key) => {
      await page.evaluate((value) => window.__opencawEvidence.capture(value), request);
      const filename = artifactName(key);
      const absolute = path.join(output.absolute, filename);
      await stage.screenshot({ path: absolute, animations: 'disabled' });
      captured.push({ key, path: `${output.relative}/${filename}`, sha256: sha256(absolute) });
    };
    for (const view of requestedViews) {
      for (const pixelHeight of validated.profile.intent.presentation.pixelHeights) {
        await captureOne({ view, pixelHeight, kind: 'whole' }, `${view}:${pixelHeight}:whole`);
        await captureOne({ view, pixelHeight, kind: 'semantic-mask' }, `${view}:${pixelHeight}:semantic-mask`);
        for (const partId of validated.profile.intent.signatureParts) {
          await captureOne({ view, pixelHeight, kind: 'isolated', partId }, `${view}:${pixelHeight}:isolated:${partId}`);
        }
      }
    }
    await captureOne({ view: 'runtime', pixelHeight: 'runtime', kind: 'whole' }, 'runtime:runtime:whole');
    const structureThresholds = validated.profile.gates.find((gate) => gate.id === 'structure-integrity').claim.thresholds;
    const interactionThresholds = validated.profile.gates.find((gate) => gate.id === 'interaction-runtime').claim.thresholds;
    const optimizationThresholds = validated.profile.gates.find((gate) => gate.id === 'optimization-budget').claim.thresholds;
    const sampleConfig = {
      actorCount: validated.profile.budgets.representativeActors,
      constructionRuns: optimizationThresholds.constructionRuns,
      lifecycleCycles: Math.max(interactionThresholds.lifecycleCycles, optimizationThresholds.lifecycleCycles),
      groundingToleranceRatio: structureThresholds.groundingToleranceRatio,
      contactToleranceRatio: interactionThresholds.contactToleranceRatio
    };
    const sampled = await page.evaluate((config) => window.__opencawEvidence.sample(config), sampleConfig);
    await page.evaluate(() => window.__opencawEvidence.stop());
    const observation = {
      schemaVersion: 'opencaw-code-character-observation/v1',
      capture: { seed, viewport: { width, height, pixelRatio }, views: captured, externalRequests, serviceWorkers: 'blocked' },
      structure: sampled.structure,
      motion: sampled.motion,
      runtime: sampled.runtime
    };
    const observationPath = path.join(output.absolute, 'observation.json');
    atomicWrite(observationPath, observation);
    const reportAnalysisContext = reportContext(root, validated, 'browser', options.compare);
    reportAnalysisContext.contracts.adapter = { path: adapter.relative, sha256: sha256(adapter.absolute) };
    reportAnalysisContext.contracts.captureConfiguration = {
      sha256: objectSha256({ seed, viewport: { width, height, pixelRatio }, requestedViews, pixelHeights: validated.profile.intent.presentation.pixelHeights, signatureParts: validated.profile.intent.signatureParts, sampleConfig })
    };
    const report = analyze(validated.profile, validated.linked.manifest, observation, reportAnalysisContext);
    report.browserSecurity = { origin: options.origin, osAssignedPort: true, chromiumSandbox: true, serviceWorkers: 'blocked', externalRequests };
    const reportPath = path.join(output.absolute, 'report.json');
    atomicWrite(reportPath, report);
    completed = true;
    process.stdout.write(`Captured sandboxed browser evidence: ${output.relative}\n`);
    process.stdout.write(`Machine result: ${report.overallDecision}\n`);
  } finally {
    if (browser) await browser.close().catch(() => {});
    if (server) await new Promise((resolve) => server.close(resolve));
    if (!completed && fs.existsSync(output.absolute)) fs.rmSync(output.absolute, { recursive: true, force: true });
    if (fs.existsSync(lock)) fs.rmdirSync(lock);
  }
}

async function main() {
  const [operation, rootArg, ...values] = process.argv.slice(2);
  if (!operation || !rootArg) fail('Internal invocation requires an operation and project root.');
  const root = rootPath(rootArg);
  if (operation === 'analyze') return analyzeOperation(root, values);
  if (operation === 'capture') return captureOperation(root, values);
  fail(`Unknown code-character evidence operation: ${operation}`);
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}

module.exports = { locatePackage, pageSource, startServer };
