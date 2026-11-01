'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {pathToFileURL} = require('node:url');
const ROOT = path.resolve(__dirname, '..');
const ADAPTER = path.join(ROOT, 'runtime/bubo/resources/model-to-action/engines/threejs-action.mjs');
const DEPENDENCIES = path.join(ROOT, '.hephaera/.cache/tasks/model-to-animation-design/dependency-audit/browser-fixture/node_modules');
const selection = {effectiveEngine: 'THREEJS', selectionSource: 'contract', contractSha256: 'a'.repeat(64), definitionSha256: 'b'.repeat(64), registrySha256: 'c'.repeat(64)};
const hash = 'd'.repeat(64);
const clone = value => JSON.parse(JSON.stringify(value));

function packageData() {
  const steps = [{id: 'prepare', clip: 'source-prepare', occurrence: 0, start: 0, end: .5, sourceStart: 0, sourceEnd: .5, rate: 1, blendIn: 0, motionSha256: hash}, {id: 'cast', clip: 'source-cast', occurrence: 0, start: .5, end: 1, sourceStart: 0, sourceEnd: .5, rate: 1, blendIn: 0, motionSha256: hash}];
  const base = {schemaVersion: 'hephaera-action-package/v1', asset: 'fixture', version: 'v1', profile: 'skinned', fps: 24,
    engine: {...selection}, coordinateSystem: {runtimeUp: '+Y', runtimeForward: '+Z'}, model: {path: 'model.glb', sha256: hash},
    rig: {id: hash, rootBone: 'Root', rootNode: 'MotionRoot'}, sourceMotion: {rigId: hash, packageSha256: hash, modelSha256: hash, clips: [{id: 'source-prepare', motionSha256: hash}, {id: 'source-cast', motionSha256: hash}]},
    anchors: [{id: 'hand', node: 'anchor.hand'}], targets: [{id: 'fixed', mode: 'fixed-world-point', maxDistance: 30}],
    budgets: {maxActions: 16, maxStepsPerAction: 64, maxExpandedSteps: 256, maxActionSeconds: 120, maxEffects: 64, maxParticles: 2048, maxFrames: 20000, maxReviewFrames: 1200, maxRuntimeBytes: 33554432, timeoutSeconds: 180, maxLogBytes: 16777216, maxAttempts: 16}, actions: []};
  for (const id of ['dance', 'combo', 'fireball']) base.actions.push({id, role: id, clip: id, duration: 1, motionSha256: hash, steps: clone(steps), markers: [{id: id + '-release', at: .5, name: 'release', step: 'cast', occurrence: 0}], cues: []});
  base.actions[2].cues = [{id: 'charge', type: 'orb', anchor: 'hand', start: 0, end: .5, radius: .1, color: '#ff6600'}, {id: 'sparks', type: 'particles', anchor: 'hand', start: .25, end: .75, radius: .05, color: '#ff8800', capacity: 16, rate: 100, seed: 3}, {id: 'bolt', type: 'projectile', anchor: 'hand', target: 'fixed', start: .5, end: 1, radius: .12, color: '#ffaa00'}];
  return base;
}

async function protocolSuite(module) {
  let count = 0;
  const pass = condition => { assert.ok(condition); count++; };
  const reject = (change, pattern) => { const value = packageData(); change(value); assert.throws(() => module.validateActionPresentation(value, selection), pattern); count++; };
  pass(module.validateActionPresentation(packageData(), selection).actions.size === 3);
  assert.throws(() => module.validateActionPresentation(packageData(), {...selection, effectiveEngine: 'UNITY'}), /THREEJS/); count++;
  reject(p => p.engine.registrySha256 = 'e'.repeat(64), /Stale/);
  reject(p => delete p.rig, /root identity/);
  reject(p => p.sourceMotion.clips[0].rootMotion = 'extract', /in-place/);
  reject(p => p.actions[0].steps[0].motionSha256 = 'e'.repeat(64), /stale/);
  reject(p => p.actions[0].steps[1].start = .6, /span|continuity/);
  reject(p => p.actions[0].steps[0].rate = 0, /rate/);
  reject(p => p.actions[0].steps[0].occurrence = 16, /occurrence/);
  reject(p => p.actions[2].cues[0].anchor = 'missing', /anchor/);
  reject(p => p.actions[2].cues[2].target = 'missing', /target/);
  reject(p => p.actions[2].cues[2].end = .4, /cue end/);
  reject(p => p.actions[2].cues[0].color = 'red', /color/);
  reject(p => p.actions[2].cues[1].capacity = 2049, /capacity/);
  reject(p => p.actions[2].cues[1].seed = -1, /seed/);
  reject(p => p.actions[0].markers[0].occurrence = 8, /missing step/);
  reject(p => p.actions[0].duration = NaN, /finite/);
  reject(p => p.provenance = {provider: 'Adobe'}, /Excluded/);
  reject(p => p.provenance = {source: 'Mixamo'}, /Excluded/);
  reject(p => p.provenance = {url: 'https://api.adobe.io/assets/1'}, /Excluded/);
  const ordinary = packageData(); ordinary.provenance = {notes: 'No Adobe dependencies', source: 'adobe-clay-building'};
  pass(module.validateActionPresentation(ordinary, selection).actions.size === 3);
  const copied = packageData(), normalized = module.validateActionPresentation(copied, selection); copied.actions[0].duration = 99; pass(normalized.actions.get('dance').duration === 1);
  console.log(`PASS: ${count} action data protocol assertions; no renderer/visual claim`);
  return count;
}

async function actualSuite(module) {
  const THREE = await import(pathToFileURL(path.join(DEPENDENCIES, 'three/build/three.module.js')).href);
  let count = 0;
  const pass = (value, message) => { assert.ok(value, message); count++; };
  const near = (value, expected, message) => pass(Math.abs(value - expected) < 1e-5, message);
  function fixture(options = {}) {
    const scene = new THREE.Scene(), movement = new THREE.Group(), visual = new THREE.Group(), root = new THREE.Group(), hand = new THREE.Group(), anchor = new THREE.Group();
    scene.add(movement); movement.position.x = 10; movement.add(visual); visual.name = 'Asset'; visual.add(root); root.name = 'Root'; root.add(hand); hand.name = 'Hand'; hand.add(anchor); anchor.name = 'anchorhand'; anchor.userData.name = 'anchor.hand';
    const animations = ['dance', 'combo', 'fireball'].map(name => new THREE.AnimationClip(name, 1, [new THREE.VectorKeyframeTrack('Hand.position', [0, .5, 1], options.handKeys?.[name] || [0, 0, 0, 1, 0, 0, 2, 0, 0]), new THREE.VectorKeyframeTrack('Root.position', [0, 1], [0, 0, 0, 0, 0, 0])]));
    const pkg = options.package || packageData(), events = [];
    const presentation = module.createActionPresentation({THREE, visualRoot: visual, movementRoot: movement, effectParent: scene, animations, actionPackage: pkg, engineSelection: selection, maxDelta: 1, onPresentationEvent: event => { events.push(event); options.onEvent?.(event); }});
    return {scene, movement, visual, root, hand, anchor, animations, pkg, events, presentation};
  }
  const f = fixture(), p = f.presentation, source = JSON.stringify(f.animations.map(c => c.toJSON()));
  const target = [15, 0, 0]; p.play('fireball', {targets: {fixed: target}}); target[0] = 99;
  pass(p.stats().activeEffects === 1, 'charge visible at zero');
  p.update(.25); near(f.hand.position.x, .5, 'actual AnimationMixer advances baked pose'); near(p.stats().effects.find(e => e.id === 'charge').worldPosition[0], 10.5, 'charge follows actual model anchor');
  p.pause(true); const beforePause = p.stats(); p.update(.5); near(p.stats().time, beforePause.time, 'pause freezes timeline'); near(f.hand.position.x, .5, 'pause freezes pose');
  p.pause(false); p.update(.5);
  const bolt = p.stats().effects.find(e => e.id === 'bolt'); near(bolt.worldPosition[0], 13, 'release uses exact intermediate boundary pose and one target trajectory'); near(bolt.target[0], 15, 'target snapshot ignores caller mutation');
  near(f.movement.position.x, 10, 'presentation never writes authoritative root');
  const released = f.events.find(e => e.type === 'cue-start' && e.cue === 'bolt'); near(released.time, .5, 'release event is exact boundary'); near(released.origin[0], 11, 'release origin sampled at exact pose');
  const atHalf = f.events.filter(e => e.time === .5).map(e => e.type); pass(atHalf.indexOf('cue-end') < atHalf.indexOf('cue-start'), 'end before begin at shared boundary');
  p.update(.25); pass(p.state === 'complete' && p.stats().ownedResources === 0, 'complete releases all resources');
  pass(f.events.filter(e => e.type === 'action-complete').length === 1, 'completion emitted once'); p.update(.5); pass(f.events.filter(e => e.type === 'action-complete').length === 1, 'later clock cannot duplicate completion');
  p.play('dance'); assert.throws(() => p.play('fireball', {targets: {fixed: [NaN, 0, 0]}}), /finite/); count++; pass(p.currentAction === 'dance', 'invalid target does not destroy current action');
  p.play('fireball', {targets: {fixed: [15, 0, 0]}}); p.update(.3); p.setQuality(0); p.setReducedMotion(true); pass(p.stats().liveParticles <= 16, 'quality change remains bounded'); p.cancel(); pass(p.state === 'idle' && p.stats().ownedResources === 0, 'cancel releases attachments and particles'); near(f.hand.position.x, 0, 'cancel restores original pose');
  p.play('fireball', {targets: {fixed: [15, 0, 0]}}); f.movement.position.x = 100; assert.throws(() => p.update(.5), /distance at release/); count++; pass(p.state === 'idle' && p.stats().ownedResources === 0, 'release failure clears acquired effects'); near(f.movement.position.x, 100, 'distance failure does not rewrite controller movement'); f.movement.position.x = 10;
  assert.throws(() => module.createActionPresentation({THREE, visualRoot: f.visual, movementRoot: f.movement, effectParent: f.scene, animations: f.animations, actionPackage: f.pkg, engineSelection: selection}), /already has/); count++;
  p.dispose(); p.dispose(); pass(p.stats().resourcesCreated === p.stats().resourcesDisposed, 'idempotent disposal releases each owned resource once'); pass(JSON.stringify(f.animations.map(c => c.toJSON())) === source, 'source clips and keyframes remain unchanged'); assert.throws(() => p.update(.1), /disposed/); count++;
  for (const operation of ['cancel', 'reset', 'dispose', 'play']) {
    let actor, acted = false;
    actor = fixture({onEvent: event => { if (event.type === 'marker' && !acted) { acted = true; operation === 'play' ? actor.presentation.play('dance') : actor.presentation[operation](); } }});
    actor.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}}); const oldGeneration = actor.presentation.generation; actor.presentation.update(.8);
    pass(!actor.events.some(e => e.generation === oldGeneration && e.type === 'cue-start' && e.cue === 'bolt'), `${operation} marker reentrancy stops stale cues`);
    pass(actor.presentation.stats().ownedResources === 0, `${operation} marker reentrancy releases resources`);
    actor.presentation.dispose();
  }
  let markerPaused, markerPausedOnce = false;
  markerPaused = fixture({onEvent: event => { if (event.type === 'marker' && !markerPausedOnce) { markerPausedOnce = true; markerPaused.presentation.pause(true); } }});
  markerPaused.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}}); markerPaused.presentation.update(.8);
  pass(markerPaused.presentation.state === 'paused', 'marker callback can pause the current action');
  near(markerPaused.presentation.stats().time, .5, 'callback pause stops consumption of the remaining frame delta');
  near(markerPaused.hand.position.x, 1, 'callback pause freezes the exact release-boundary pose');
  pass(!markerPaused.events.some(event => event.type === 'cue-start' && event.cue === 'bolt'), 'same-time projectile start remains pending while marker callback paused');
  pass(!markerPaused.events.some(event => event.type === 'cue-end' && event.cue === 'sparks'), 'later particle end remains pending while paused');
  const pausedEffects = markerPaused.presentation.stats().ownedResources; markerPaused.presentation.update(.2);
  near(markerPaused.presentation.stats().time, .5, 'subsequent paused update consumes no time');
  pass(markerPaused.presentation.stats().ownedResources === pausedEffects, 'pause retains valid already-owned effect resources');
  markerPaused.presentation.pause(false); markerPaused.presentation.update(.1);
  near(markerPaused.presentation.stats().time, .6, 'resume consumes only the new frame delta');
  pass(markerPaused.events.filter(event => event.type === 'marker').length === 1, 'resume never replays the consumed marker');
  pass(markerPaused.events.filter(event => event.type === 'cue-start' && event.cue === 'bolt').length === 1, 'resume dispatches the pending same-time cue exactly once');
  near(markerPaused.events.find(event => event.type === 'cue-start' && event.cue === 'bolt').time, .5, 'resumed cue retains its exact pending boundary time');
  markerPaused.presentation.update(.4);
  pass(markerPaused.presentation.state === 'complete' && markerPaused.presentation.stats().ownedResources === 0, 'resumed action completes and releases owned resources');
  pass(markerPaused.events.filter(event => event.type === 'cue-end' && event.cue === 'sparks').length === 1, 'resumed later particle end occurs once');
  markerPaused.presentation.dispose();
  let acquiredPause, acquiredPausedOnce = false;
  acquiredPause = fixture({onEvent: event => { if (event.type === 'cue-start' && event.cue === 'bolt' && !acquiredPausedOnce) { acquiredPausedOnce = true; acquiredPause.presentation.pause(true); } }});
  acquiredPause.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}}); acquiredPause.presentation.update(.8);
  near(acquiredPause.presentation.stats().time, .5, 'cue callback pause stops at the cue boundary');
  pass(acquiredPause.presentation.stats().effects.some(effect => effect.id === 'bolt'), 'pause does not invalidate the newly acquired cue resource');
  acquiredPause.presentation.pause(false); acquiredPause.presentation.update(.5);
  pass(acquiredPause.events.filter(event => event.type === 'cue-start' && event.cue === 'bolt').length === 1 && acquiredPause.presentation.stats().ownedResources === 0, 'cue callback resume neither duplicates nor leaks the projectile'); acquiredPause.presentation.dispose();
  const endPausePackage = packageData(); endPausePackage.actions[0].markers[0].at = 1;
  let endPaused, endPausedOnce = false;
  endPaused = fixture({package: endPausePackage, onEvent: event => { if (event.type === 'marker' && !endPausedOnce) { endPausedOnce = true; endPaused.presentation.pause(true); } }});
  endPaused.presentation.play('dance'); endPaused.presentation.update(1);
  pass(endPaused.presentation.state === 'paused' && !endPaused.events.some(event => event.type === 'action-complete'), 'final boundary callback pause leaves completion pending');
  endPaused.presentation.pause(false); endPaused.presentation.update(.1);
  pass(endPaused.presentation.state === 'complete' && endPaused.events.filter(event => event.type === 'action-complete').length === 1, 'resuming at the final boundary completes once'); endPaused.presentation.dispose();
  for (const operation of ['reset', 'dispose']) {
    const actor = fixture(); let invoked = false;
    actor.anchor.addEventListener('childadded', () => { if (!invoked) { invoked = true; actor.presentation[operation](); } });
    actor.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}});
    pass(actor.presentation.stats().ownedResources === 0, `${operation} during resource acquisition cleans partial resources`);
    actor.presentation.dispose();
  }
  const nested = fixture({onEvent: event => { if (event.type === 'marker') assert.throws(() => nested.presentation.update(.01), /reenter/); }}); nested.presentation.play('combo'); nested.presentation.update(.7); count++; nested.presentation.dispose();
  for (const at of ['cancel', 'cue-end', 'supersede']) {
    const actor = fixture(); let invoked = false;
    actor.anchor.addEventListener('childadded', event => event.child.addEventListener('removed', () => { if (!invoked) { invoked = true; actor.presentation.play('dance'); } }));
    actor.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}});
    if (at === 'cancel') actor.presentation.cancel();
    else if (at === 'supersede') actor.presentation.play('combo');
    else actor.presentation.update(.6);
    pass(actor.presentation.currentAction === 'dance' && actor.presentation.state === 'playing', 'resource-removal callback retains new owner during ' + at);
    actor.presentation.update(.1); near(actor.hand.position.x, .2, 'old cleanup cannot restore over replacement pose');
    pass(actor.presentation.stats().ownedResources === 0, 'cleanup does not delete replacement cue ownership'); actor.presentation.dispose();
  }
  const throwing = fixture();
  throwing.anchor.addEventListener('childadded', event => event.child.addEventListener('removed', () => { throw new Error('host removal callback failed'); }));
  throwing.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}});
  assert.throws(() => throwing.presentation.cancel(), /host removal callback/); count++; pass(throwing.presentation.stats().ownedResources === 0, 'throwing host disposal callbacks cannot leak resources'); throwing.presentation.dispose();
  const acquisition = fixture();
  acquisition.anchor.addEventListener('childadded', event => { event.child.addEventListener('removed', () => { throw new Error('secondary removal failure'); }); throw new Error('host acquisition callback failed'); });
  assert.throws(() => acquisition.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}}), /host acquisition/); count++;
  pass(acquisition.presentation.state === 'idle' && acquisition.presentation.stats().ownedResources === 0, 'failed acquisition cleans every partial resource despite secondary callback failure'); acquisition.presentation.dispose();
  const wrong = packageData(); wrong.rig.rootBone = 'Hand'; const actor = fixture(); actor.presentation.dispose(); assert.throws(() => module.createActionPresentation({THREE, visualRoot: actor.visual, movementRoot: actor.movement, effectParent: actor.scene, animations: actor.animations, actionPackage: wrong, engineSelection: selection}), /root or ancestor moves/); count++;
  const nearPackage = packageData(); nearPackage.targets[0].maxDistance = 5;
  const incoming = fixture({package: nearPackage, handKeys: {dance: [0, 0, 0, 20, 0, 0, 0, 0, 0], fireball: [0, 0, 0, 0, 0, 0, 0, 0, 0]}});
  incoming.presentation.play('dance'); incoming.presentation.update(.5); near(incoming.hand.position.x, 20, 'outgoing clip has a distant hand pose');
  incoming.presentation.play('fireball', {targets: {fixed: [11, 0, 0]}});
  pass(incoming.presentation.currentAction === 'fireball', 'incoming target is not rejected against the outgoing clip pose');
  incoming.presentation.update(.5);
  near(incoming.events.find(event => event.type === 'cue-start' && event.cue === 'bolt').origin[0], 10, 'incoming projectile range uses its actual release anchor');
  incoming.presentation.update(.5); pass(incoming.presentation.state === 'complete' && incoming.presentation.stats().ownedResources === 0, 'valid incoming target completes without leaked effects'); incoming.presentation.dispose();
  const distant = fixture({package: nearPackage});
  distant.presentation.play('fireball', {targets: {fixed: [100, 0, 0]}});
  const distantGeneration = distant.presentation.generation;
  pass(distant.presentation.stats().effects.some(effect => effect.id === 'charge'), 'action may charge before its actual release range is evaluated');
  assert.throws(() => distant.presentation.update(.8), /distance at release/); count++;
  pass(distant.presentation.state === 'idle' && distant.presentation.stats().ownedResources === 0, 'distant release cancels and cleans charge/particle resources');
  pass(distant.presentation.generation > distantGeneration, 'failed release invalidates the previous presentation generation');
  pass(!distant.events.some(event => event.generation === distantGeneration && ((event.type === 'cue-start' && event.cue === 'bolt') || event.time > .5)), 'failed release dispatches no projectile or later-generation cue events');
  near(distant.movement.position.x, 10, 'failed release leaves authoritative root untouched');
  const distantEventCount = distant.events.length; distant.presentation.update(.2); pass(distant.events.length === distantEventCount, 'later updates cannot continue a failed release timeline'); distant.presentation.dispose();
  const large = fixture(); for (let i = 0; i < 100; i++) { large.presentation.play('fireball', {targets: {fixed: [15, 0, 0]}}); large.presentation.update(.25); large.presentation.cancel(); pass(large.presentation.stats().ownedResources === 0 && large.presentation.stats().eventHistory <= 128, 'bounded repeated acquisition/disposal'); } large.presentation.dispose();
  console.log(`PASS: ${count} actual Three.js ${THREE.REVISION} action assertions; Node has no renderer/visual acceptance`);
  return {assertions: count, threeRevision: THREE.REVISION, realRenderer: false};
}

async function main() {
  if (process.argv.includes('--browser')) return browserFixture(process.argv.slice(2));
  const module = await import(pathToFileURL(ADAPTER).href);
  const protocol = await protocolSuite(module);
  let actual = null;
  if (fs.existsSync(path.join(DEPENDENCIES, 'three/build/three.module.js'))) actual = await actualSuite(module);
  else console.log('BLOCKED: actual Three.js dependency unavailable; no install attempted');
  const outputIndex = process.argv.indexOf('--output');
  if (outputIndex >= 0) fs.writeFileSync(process.argv[outputIndex + 1], JSON.stringify({protocolAssertions: protocol, actualThree: actual, simulatedProcesses: false, realRenderer: false}, null, 2) + '\n');
}

async function browserFixture(values) {
  const http = require('node:http');
  const option = name => { const index = values.indexOf(name); return index >= 0 ? values[index + 1] : null; };
  const inside = (base, value) => value === base || value.startsWith(base + path.sep);
  const confined = value => {
    const file = path.resolve(value); if (!inside(ROOT, file)) throw new Error('Fixture path escapes repository');
    let current = ROOT;
    for (const part of path.relative(ROOT, file).split(path.sep).filter(Boolean)) { current = path.join(current, part); if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) throw new Error('Fixture links/junctions are unsupported'); }
    return file;
  };
  const config = JSON.parse(fs.readFileSync(confined(option('--config')), 'utf8'));
  if (config.schemaVersion !== 1 || !Array.isArray(config.packages) || config.packages.length < 1 || config.packages.length > 8) throw new Error('Bounded action package inventory required');
  const project = confined(config.projectRoot), output = confined(config.output), dependencies = confined(config.dependencies);
  if (fs.readdirSync(output).some(name => !['browser-config.json', 'browser.log'].includes(name))) throw new Error('Output already contains evidence');
  const evidenceRoot = inside(project, output) ? project : ROOT;
  const packages = config.packages.map(value => {
    const file = confined(value), manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
    const model = confined(path.resolve(project, manifest.model.path));
    if (!inside(fs.realpathSync(project), fs.realpathSync(model))) throw new Error('Model escapes project');
    if (crypto.createHash('sha256').update(fs.readFileSync(model)).digest('hex') !== manifest.model.sha256) throw new Error('Actual model hash mismatch');
    return {file, manifest, model};
  });
  const chromium = require(path.join(dependencies, 'playwright-core')).chromium;
  const requested = [], blocked = [];
  const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, 'http://127.0.0.1').pathname; requested.push(pathname);
    response.setHeader('Cache-Control', 'no-store'); response.setHeader('X-Content-Type-Options', 'nosniff');
    if (pathname === '/') { response.setHeader('Content-Type', 'text/html;charset=utf-8'); response.end(browserPage()); return; }
    if (pathname === '/fixtures.json') { response.setHeader('Content-Type', 'application/json'); response.end(JSON.stringify({engineSelection: config.engineSelection, fixtures: packages.map((entry, index) => ({name: path.basename(path.dirname(entry.file)), package: entry.manifest, modelUrl: '/model/' + index + '.glb'}))})); return; }
    let file = pathname === '/adapter.mjs' ? ADAPTER : null;
    if (/^\/model\/\d+\.glb$/.test(pathname)) file = packages[Number(pathname.match(/\d+/)[0])]?.model;
    if (pathname.startsWith('/deps/')) {
      const relative = decodeURIComponent(pathname.slice(6));
      if (relative.includes('\\') || relative.split('/').some(part => ['.', '..'].includes(part))) { response.writeHead(403); response.end(); return; }
      const candidate = path.resolve(dependencies, relative);
      if (inside(dependencies, candidate) && fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
        const real = fs.realpathSync(confined(candidate)); if (inside(fs.realpathSync(dependencies), real)) file = real;
      }
    }
    if (!file || !fs.existsSync(file)) { response.writeHead(404); response.end(); return; }
    response.setHeader('Content-Type', /\.m?js$/.test(file) ? 'text/javascript;charset=utf-8' : 'model/gltf-binary'); fs.createReadStream(file).pipe(response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = 'http://127.0.0.1:' + server.address().port;
  let context;
  try {
    context = await chromium.launchPersistentContext(path.join(output, 'browser-profile'), {executablePath: config.browserExecutable, headless: true, viewport: {width: 720, height: 560}, serviceWorkers: 'block', args: ['--disable-background-networking', '--disable-component-update', '--disable-sync', '--no-first-run', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']});
    await context.route('**/*', route => { const address = new URL(route.request().url()); if (address.origin === origin || ['data:', 'blob:'].includes(address.protocol)) return route.continue(); blocked.push(route.request().url()); return route.abort('blockedbyclient'); });
    const page = await context.newPage(), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(origin, {waitUntil: 'networkidle'});
    await page.waitForFunction(() => window.__HEPHAERA_ACTION_DONE, null, {timeout: 120000});
    const result = await page.evaluate(() => window.__HEPHAERA_ACTION_RESULT);
    if (result.error) throw new Error(result.error);
    assert.equal(result.status, 'passed'); assert.equal(result.actualBrowser, true); assert.equal(result.actualWebGL, true); assert.ok(result.cases.length);
    const captures = [];
    for (const [index, frame] of result.captures.entries()) {
      assert.ok(index < 64 && /^data:image\/png;base64,/.test(frame.dataUrl) && frame.dataUrl.length < 8 * 1024 * 1024);
      const file = path.join(output, 'frame-' + String(index).padStart(2, '0') + '-' + frame.action.replace(/[^a-z0-9_-]/gi, '_') + '.png');
      fs.writeFileSync(file, Buffer.from(frame.dataUrl.split(',')[1], 'base64'));
      const {dataUrl, ...metadata} = frame;
      captures.push({...metadata, path: path.relative(evidenceRoot, file).replace(/\\/g, '/'), sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')});
    }
    assert.ok(captures.length); result.captures = captures;
    const capture = path.join(output, 'runtime-capture.png'); fs.copyFileSync(path.join(evidenceRoot, captures.find(frame => frame.phase === 'projectile')?.path || captures[0].path), capture);
    await page.screenshot({path: path.join(output, 'runtime-overview.png'), fullPage: true});
    const denied = await page.evaluate(async () => { try { await fetch('https://hephaera-network-test.invalid/blocked'); return false; } catch { return true; } });
    assert.ok(denied && blocked.length); assert.deepEqual(errors, []);
    const report = {...result, engine: 'THREEJS', engineSelection: config.engineSelection, adapterSha256: crypto.createHash('sha256').update(fs.readFileSync(ADAPTER)).digest('hex'), fixturePackages: packages.map(entry => ({path: entry.file, sha256: crypto.createHash('sha256').update(fs.readFileSync(entry.file)).digest('hex'), modelSha256: entry.manifest.model.sha256})), requests: requested, blockedRequests: blocked, limits: 'Original engineering fixtures in software WebGL; loopback routing is not an OS network sandbox. No human or target-hardware acceptance.'};
    const test = path.join(output, 'runtime-test.json'), perf = path.join(output, 'performance-profile.json');
    fs.writeFileSync(test, JSON.stringify(report, null, 2) + '\n');
    fs.writeFileSync(perf, JSON.stringify({schemaVersion: 1, status: 'passed', actualWebGL: true, threeRevision: result.threeRevision, cases: result.cases.map(value => ({name: value.name, frames: value.frames, frameCpuMs: value.frameCpuMs, peakParticles: value.peakParticles, rendererInfo: value.rendererInfo})), limitation: 'CPU submission times and renderer counters through SwiftShader; not physical GPU frame timing or device qualification.'}, null, 2) + '\n');
    const evidence = [['runtime-test', test], ['runtime-capture', capture], ['performance-profile', perf]].map(([kind, file]) => ({kind, path: path.relative(evidenceRoot, file).replace(/\\/g, '/'), sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}));
    fs.writeFileSync(path.join(output, 'engine-evidence.json'), JSON.stringify({schemaVersion: 1, status: 'passed', engine: 'THREEJS', actualBrowser: true, evidenceRoot, pathBase: evidenceRoot === project ? 'project-root' : 'repository-root', evidence}, null, 2) + '\n');
    console.log(`PASS: ${result.assertions} actual Three.js ${result.threeRevision} action browser assertions on ${result.cases.length} packages`);
  } finally { if (context) await context.close(); await new Promise(resolve => server.close(resolve)); }
}

function browserPage() {
  return '<!doctype html><meta charset="utf-8"><title>Controlled action fixture</title><style>body{margin:0;background:#141821;color:#ddd;font:13px sans-serif}canvas{display:block}pre{white-space:pre-wrap;padding:12px}</style><script type="importmap">{"imports":{"three":"/deps/three/build/three.module.js","three/addons/":"/deps/three/examples/jsm/"}}</script><body><div>Controlled MODEL_TO_ACTION fixture; no production acceptance</div><div id="viewport"></div><pre id="status"></pre><script type="module">import * as THREE from "three"; import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js"; import {clone} from "three/addons/utils/SkeletonUtils.js"; import {createActionPresentation} from "/adapter.mjs"; (' + browserProgram.toString() + ')(THREE,GLTFLoader,clone,createActionPresentation).catch(error=>{window.__HEPHAERA_ACTION_RESULT={status:"failed",error:String(error.stack||error)};window.__HEPHAERA_ACTION_DONE=true;document.getElementById("status").textContent=String(error.stack||error)});</script>';
}

async function browserProgram(THREE, GLTFLoader, skeletonClone, createActionPresentation) {
  const payload = await (await fetch('/fixtures.json')).json();
  const result = {schemaVersion: 1, status: 'passed', actualBrowser: true, actualWebGL: true, threeRevision: THREE.REVISION, assertions: 0, cases: [], captures: []};
  const check = (value, label) => { if (!value) throw new Error(label); result.assertions++; };
  const near = (value, expected, label) => check(Math.abs(value - expected) < 2e-4, label + ': ' + value + ' != ' + expected);
  const scene = new THREE.Scene(); scene.background = new THREE.Color('#141821');
  const renderer = new THREE.WebGLRenderer({antialias: true, preserveDrawingBuffer: true}); renderer.setSize(720, 430); document.getElementById('viewport').appendChild(renderer.domElement);
  const camera = new THREE.PerspectiveCamera(40, 720 / 430, .01, 1000);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x303030, 2)); const light = new THREE.DirectionalLight(0xffffff, 3); light.position.set(4, 8, 5); scene.add(light);
  const find = (root, name) => { const original = [], exact = []; root.traverse(value => { if (value.userData.name === name) original.push(value); if (value.name === name || value.uuid === name) exact.push(value); }); const list = original.length ? original : exact; check(list.length === 1, 'unambiguous original node ' + name); return list[0]; };
  const metrics = values => { const sorted = [...values].sort((a, b) => a - b); return {median: sorted[Math.floor(sorted.length / 2)] || 0, p95: sorted[Math.floor(sorted.length * .95)] || 0, max: sorted.at(-1) || 0}; };
  for (const fixture of payload.fixtures) {
    const source = await new GLTFLoader().loadAsync(fixture.modelUrl), pkg = fixture.package;
    const clipsBefore = JSON.stringify(source.animations.map(value => value.toJSON()));
    const movement = new THREE.Group(), visual = skeletonClone(source.scene); movement.position.set(3, 0, -1); movement.add(visual); scene.add(movement);
    const second = skeletonClone(source.scene); const bones = [], otherBones = []; visual.traverse(value => { if (value.isBone) bones.push(value); }); second.traverse(value => { if (value.isBone) otherBones.push(value); });
    check(!bones.length || bones.every((value, index) => value !== otherBones[index]), 'skeleton-aware actor copies have independent bones');
    // Resolve the authoritative parent's initial placement before measuring the
    // child. Otherwise Box3 can frame yesterday's matrix while rendering uses
    // the freshly updated parent, producing passing but off-screen captures.
    scene.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(visual), centre = box.getCenter(new THREE.Vector3()), size = Math.max(.5, box.getSize(new THREE.Vector3()).length());
    camera.position.copy(centre).add(new THREE.Vector3(size * 1.05, size * .65, size * 1.7)); camera.lookAt(centre);
    camera.updateMatrixWorld(true);
    const projected = centre.clone().project(camera);
    check(Math.abs(projected.x) < .01 && Math.abs(projected.y) < .01 && projected.z > -1 && projected.z < 1, 'actual actor bounds are framed inside the runtime capture');
    const rootBefore = movement.matrix.clone(), positionBefore = movement.position.clone(), events = [], timings = [], actionResults = []; let frames = 0, peak = 0, captureEnabled = true, pauseMarker = null;
    const capture = (action, phase) => { if (result.captures.length >= 64) return; renderer.render(scene, camera); result.captures.push({action, phase, fixture: fixture.name, dataUrl: renderer.domElement.toDataURL('image/png')}); };
    const presentation = createActionPresentation({THREE, visualRoot: visual, movementRoot: movement, effectParent: scene, animations: source.animations, actionPackage: pkg, engineSelection: payload.engineSelection,
      onPresentationEvent: event => { events.push(event); if (pauseMarker && event.type === 'marker' && event.markerId === pauseMarker) { pauseMarker = null; presentation.pause(true); } if (captureEnabled && event.type === 'cue-start' && (event.cueType === 'orb' || event.cueType === 'projectile')) capture(event.action, event.cueType); }});
    function targetsFor(action) {
      const targets = {};
      for (const cue of action.cues) if (cue.type === 'projectile') {
        const anchor = find(visual, pkg.anchors.find(value => value.id === cue.anchor).node).getWorldPosition(new THREE.Vector3());
        const maximum = pkg.targets.find(value => value.id === cue.target).maxDistance;
        targets[cue.target] = anchor.add(new THREE.Vector3(Math.min(1.5, maximum / 5), Math.min(.25, maximum / 10), -.3)).toArray();
      }
      return targets;
    }
    function skinPoint() { let found; visual.traverse(value => { if (!found && value.isSkinnedMesh) found = value; }); if (!found) return null; found.skeleton.update(); const attribute = found.geometry.getAttribute('position'); return Array.from({length: Math.min(256, attribute.count)}, (_, index) => found.applyBoneTransform(index, new THREE.Vector3().fromBufferAttribute(attribute, index)).applyMatrix4(found.matrixWorld)); }
    for (const action of pkg.actions) {
      const localEvents = events.length, targets = targetsFor(action), immutable = JSON.parse(JSON.stringify(targets));
      presentation.play(action.id, {targets}); for (const point of Object.values(targets)) point[0] += 100;
      let changed = false, previousPose = skinPoint(), before = 0, count = 0;
      while (presentation.state !== 'complete') {
        check(++count < 10000, 'bounded actual action playback');
        if (count === 2) { presentation.pause(true); presentation.update(.1); near(presentation.stats().time, before, 'pause freezes action clock'); presentation.pause(false); }
        const dt = [.07, .11, .19, .03, .13][count % 5], start = performance.now(); presentation.update(dt); renderer.render(scene, camera); timings.push(performance.now() - start); frames++;
        const state = presentation.stats(); before = state.time; peak = Math.max(peak, state.liveParticles);
        near(movement.position.distanceTo(positionBefore), 0, 'authoritative world root stays controller-owned');
        check(state.liveParticles <= pkg.budgets.maxParticles && state.eventHistory <= 128, 'actual effects/events remain bounded');
        const pose = skinPoint(); if (pose && previousPose) changed ||= pose.some((value, index) => value.distanceTo(previousPose[index]) > 1e-5); previousPose = pose;
        for (const effect of state.effects) if (effect.type === 'projectile') {
          const cue = action.cues.find(value => value.id === effect.id), release = events.findLast(value => value.type === 'cue-start' && value.cue === effect.id && value.instance === state.instance);
          const expected = new THREE.Vector3().fromArray(release.origin).lerp(new THREE.Vector3().fromArray(immutable[cue.target]), (state.time - cue.start) / (cue.end - cue.start));
          near(expected.distanceTo(new THREE.Vector3().fromArray(effect.worldPosition)), 0, 'actual projectile follows fixed captured trajectory once');
          check(JSON.stringify(effect.target) === JSON.stringify(immutable[cue.target]), 'caller mutation cannot redirect projectile');
          if (!result.captures.some(value => value.action === action.id && value.phase === 'flight')) capture(action.id, 'flight');
        }
        if (!result.captures.some(value => value.action === action.id && value.phase === 'pose') && state.time >= action.duration / 3) capture(action.id, 'pose');
      }
      const observed = events.slice(localEvents), entered = observed.filter(value => value.type === 'step-enter').map(value => value.step + ':' + value.occurrence);
      check(JSON.stringify(entered) === JSON.stringify(action.steps.map(value => value.id + ':' + value.occurrence)), 'actual step progression matches ordered expanded recipe');
      check(observed.filter(value => value.type === 'action-complete').length === 1, 'actual action completes exactly once');
      for (const cue of action.cues) { const begin = observed.filter(value => value.type === 'cue-start' && value.cue === cue.id), end = observed.filter(value => value.type === 'cue-end' && value.cue === cue.id); check(begin.length === 1 && end.length === 1, 'each actual cue has exactly one start/end'); near(begin[0].time, cue.start, 'actual cue begins at exact substep'); near(end[0].time, cue.end, 'actual cue ends at exact substep'); if (cue.type === 'projectile') near(new THREE.Vector3().fromArray(end[0].worldPosition).distanceTo(new THREE.Vector3().fromArray(immutable[cue.target])), 0, 'visual projectile ends at captured target without hit authority'); }
      if (pkg.profile === 'skinned') check(changed, 'actual skinned mesh vertices change during compound playback');
      check(presentation.stats().ownedResources === 0, 'completion releases every owned effect resource');
      actionResults.push({id: action.id, steps: entered, cueCount: action.cues.length, actualSkinnedVertexChange: changed, frames: count});
    }
    captureEnabled = false;
    const pauseAction = pkg.actions.find(value => value.cues.some(cue => cue.type === 'projectile' && value.markers.some(marker => Math.abs(marker.at - cue.start) < 1e-8)));
    check(!!pauseAction, 'actual compound fixture supplies a marker at projectile release for callback-pause verification');
    const pauseCue = pauseAction.cues.find(cue => cue.type === 'projectile' && pauseAction.markers.some(marker => Math.abs(marker.at - cue.start) < 1e-8));
    const pauseBoundary = pauseAction.markers.find(marker => Math.abs(marker.at - pauseCue.start) < 1e-8);
    const pauseEvents = events.length; pauseMarker = pauseBoundary.id;
    presentation.play(pauseAction.id, {targets: targetsFor(pauseAction)});
    let pauseFrames = 0;
    while (presentation.state !== 'paused') { check(++pauseFrames < 10000, 'bounded actual callback-pause playback'); presentation.update(.2); }
    near(presentation.stats().time, pauseBoundary.at, 'actual marker callback stops exactly at release boundary');
    check(!events.slice(pauseEvents).some(event => event.type === 'cue-start' && event.cue === pauseCue.id), 'actual same-time projectile waits while marker callback paused');
    presentation.update(.2); near(presentation.stats().time, pauseBoundary.at, 'actual callback pause does not consume another frame');
    presentation.pause(false); presentation.update(.05);
    near(presentation.stats().time, pauseBoundary.at + .05, 'actual callback resume consumes only fresh frame time');
    check(events.slice(pauseEvents).filter(event => event.type === 'marker' && event.markerId === pauseBoundary.id).length === 1, 'actual callback resume never replays the consumed marker');
    check(events.slice(pauseEvents).filter(event => event.type === 'cue-start' && event.cue === pauseCue.id).length === 1, 'actual callback resume starts pending projectile exactly once');
    presentation.cancel(); check(presentation.stats().ownedResources === 0, 'actual callback-pause cancellation releases retained resources');
    const farTargets = targetsFor(pauseAction), failureEvents = events.length;
    for (const cue of pauseAction.cues) if (cue.type === 'projectile') {
      const origin = find(visual, pkg.anchors.find(value => value.id === cue.anchor).node).getWorldPosition(new THREE.Vector3());
      farTargets[cue.target] = origin.add(new THREE.Vector3(pkg.targets.find(value => value.id === cue.target).maxDistance * 2 + size * 2, 0, 0)).toArray();
    }
    presentation.play(pauseAction.id, {targets: farTargets}); const failureGeneration = presentation.generation;
    let failedAtRelease = false, failureFrames = 0;
    try { while (presentation.state === 'playing') { check(++failureFrames < 10000, 'bounded actual distant-target playback'); presentation.update(.2); } }
    catch (error) { if (!/distance at release/.test(error.message)) throw error; failedAtRelease = true; }
    check(failedAtRelease && presentation.state === 'idle', 'actual distant visual target fails at release and cancels presentation');
    check(presentation.stats().ownedResources === 0 && presentation.generation > failureGeneration, 'actual failed release invalidates stale work and clears all cue resources');
    check(!events.slice(failureEvents).some(event => event.type === 'cue-start' && event.cueType === 'projectile'), 'actual failed release allocates no visual projectile');
    const failureEventCount = events.length; presentation.update(.2); check(events.length === failureEventCount, 'actual failed timeline emits no later cues');
    near(movement.position.distanceTo(positionBefore), 0, 'actual failed release preserves controller movement authority');
    const action = pkg.actions.find(value => value.cues.length) || pkg.actions[0];
    for (let cycle = 0; cycle < 20; cycle++) { presentation.play(action.id, {targets: targetsFor(action)}); presentation.update(Math.min(.1, action.duration)); presentation.setQuality(cycle % 3); presentation.setReducedMotion(cycle % 2 === 0); presentation.cancel(); check(presentation.stats().ownedResources === 0, 'repeated cancel disposes all owned effects'); }
    presentation.dispose(); presentation.dispose(); check(presentation.stats().resourcesCreated === presentation.stats().resourcesDisposed, 'actual disposal is idempotent and resources released once');
    check(JSON.stringify(source.animations.map(value => value.toJSON())) === clipsBefore, 'original actual animation tracks remain unchanged');
    let rejected = false; try { presentation.update(.1); } catch { rejected = true; } check(rejected, 'disposed actual clock rejects writes');
    result.cases.push({name: fixture.name, profile: pkg.profile, actions: actionResults, frames, frameCpuMs: metrics(timings), peakParticles: peak, resourcesCreated: presentation.stats().resourcesCreated, resourcesDisposed: presentation.stats().resourcesDisposed, rendererInfo: {calls: renderer.info.render.calls, triangles: renderer.info.render.triangles, points: renderer.info.render.points, geometries: renderer.info.memory.geometries, textures: renderer.info.memory.textures}});
    movement.removeFromParent(); document.getElementById('status').textContent = JSON.stringify({...result, captures: result.captures.map(({dataUrl, ...value}) => value)}, null, 2);
  }
  window.__HEPHAERA_ACTION_RESULT = result; window.__HEPHAERA_ACTION_DONE = true;
}
if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });
module.exports = {packageData, selection};
