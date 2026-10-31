import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createPostprocessingRuntime, VERIFIED_VERSIONS} from '../.engine/threejs/postprocessing/postprocessing-runtime.mjs';

const fixture = new URL('./fixtures/threejs-postprocessing/node_modules/', import.meta.url);
if (!fs.existsSync(new URL('postprocessing/package.json', fixture))) throw new Error('Install the exact fixture explicitly: npm ci --ignore-scripts --prefix tests/fixtures/threejs-postprocessing');
const THREE = await import(new URL('three/build/three.module.js', fixture));
const Postprocessing = await import(new URL('postprocessing/build/index.js', fixture));
const Quarks = await import(new URL('three.quarks/dist/three.quarks.esm.js', fixture));
let checks = 0;
const eq = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const ok = value => { assert.ok(value); checks++; };
const rejects = (fn, pattern) => { assert.throws(fn, pattern); checks++; };
const selection = {effectiveEngine: 'THREEJS', postprocessing: {backend: 'PMNDRS_POSTPROCESSING'}};

// These are explicitly CPU-only context/renderer fixtures. Actual package passes,
// FXAA shader generation, targets and lifecycles execute. No GPU context, shader
// compilation, image quality, native WebView or MAUI readiness is established.
class ContextFixture {
  VERSION = 1; MAX_TEXTURE_SIZE = 2; MAX_RENDERBUFFER_SIZE = 3;
  FRAMEBUFFER = 4; FRAMEBUFFER_COMPLETE = 5;
  lost = false; complete = true; limit = 8192; probes = 0;
  getParameter(key) { return key === this.VERSION ? 'WebGL 2.0 CPU fixture' : this.limit; }
  isContextLost() { return this.lost; }
  getContextAttributes() { return {alpha: false}; }
  checkFramebufferStatus() { this.probes++; return this.complete ? this.FRAMEBUFFER_COMPLETE : -1; }
}
class EventFixture extends EventTarget {
  counts = new Map(); hidden = false;
  addEventListener(name, fn) { super.addEventListener(name, fn); this.counts.set(name, (this.counts.get(name) || 0) + 1); }
  removeEventListener(name, fn) { super.removeEventListener(name, fn); this.counts.set(name, (this.counts.get(name) || 0) - 1); }
}
function host(patch = {}) {
  const gl = new ContextFixture(), doc = new EventFixture(), canvas = new EventFixture(), lifecycle = new EventFixture();
  doc.defaultView = {WebGL2RenderingContext: ContextFixture}; canvas.ownerDocument = doc;
  const renderer = {
    isWebGLRenderer: true, domElement: canvas, outputColorSpace: THREE.SRGBColorSpace,
    toneMapping: THREE.NoToneMapping, autoClear: true, shadowMap: {autoUpdate: true}, xr: {isPresenting: false},
    width: 320, height: 180, ratio: 1, target: null, cube: 0, mip: 0, calls: [], drawCalls: 0,
    getContext: () => gl, getSize(target) { return target.set(this.width, this.height); },
    getDrawingBufferSize(target) { return target.set(Math.floor(this.width * this.ratio), Math.floor(this.height * this.ratio)); },
    getPixelRatio() { return this.ratio; },
    setSize(w, h) { this.width = w; this.height = h; },
    setDrawingBufferSize(w, h, ratio) { this.width = w; this.height = h; this.ratio = ratio; },
    getRenderTarget() { return this.target; }, getActiveCubeFace() { return this.cube; }, getActiveMipmapLevel() { return this.mip; },
    setRenderTarget(target, cube = 0, mip = 0) { this.target = target; this.cube = cube; this.mip = mip; },
    clear() {}, getClearAlpha() { return 1; }, getClearColor(target) { return target.set(0); },
    render(scene, camera) { this.calls.push({scene, camera, target: this.target}); this.drawCalls++; if (this.onRender) this.onRender(); },
    ...patch
  };
  const scene = new THREE.Scene(), camera = new THREE.PerspectiveCamera();
  const options = {THREE, Postprocessing, scene, camera, renderer, engineSelection: selection, lifecycleTarget: lifecycle, visibilityTarget: doc};
  return {gl, doc, canvas, lifecycle, renderer, scene, camera, options};
}
function observed(h, extra = {}) {
  const captured = {};
  const classes = {...Postprocessing};
  for (const name of ['EffectComposer', 'RenderPass', 'EffectPass', 'FXAAEffect']) {
    classes[name] = class extends Postprocessing[name] {
      constructor(...args) { super(...args); captured[name] = this; this.disposals = 0; }
      dispose() { this.disposals++; super.dispose(); }
    };
  }
  const runtime = createPostprocessingRuntime({...h.options, Postprocessing: classes, ...extra});
  return {runtime, ...captured};
}
function event(target, name, detail) { const value = new Event(name, {cancelable: true}); if (detail) value.detail = detail; target.dispatchEvent(value); return value; }

eq(THREE.REVISION, '182'); eq(Postprocessing.version, '6.39.5'); eq(VERIFIED_VERSIONS, {three: '0.182.0', postprocessing: '6.39.5'});
rejects(() => createPostprocessingRuntime(), /Resolve THREEJS/);
for (const [patch, pattern] of [
  [{engineSelection: {effectiveEngine: 'UNITY'}}, /Resolve THREEJS/],
  [{THREE: {...THREE, REVISION: '183'}}, /r182/],
  [{Postprocessing: {...Postprocessing, version: '0'}}, /6.39.5/],
  [{Postprocessing: {...Postprocessing, FXAAEffect: null}}, /Missing postprocessing API/],
  [{scene: new THREE.Group()}, /Scene and Camera/], [{camera: {}}, /Scene and Camera/],
  [{maxDimension: 8193}, /maxDimension/], [{maxDimension: 1.1}, /integer/],
  [{maxPixels: 0}, /maxPixels/], [{maxPixelRatio: 4}, /maxPixelRatio/], [{maxDelta: .5}, /maxDelta/]
]) { const h = host(); rejects(() => createPostprocessingRuntime({...h.options, ...patch}), pattern); eq(h.renderer.autoClear, true); }
for (const [patch, pattern] of [
  [{isWebGLRenderer: false}, /existing WebGLRenderer/], [{isWebGPURenderer: true}, /existing WebGLRenderer/],
  [{getContext: () => ({})}, /actual renderer context/], [{outputColorSpace: THREE.LinearSRGBColorSpace}, /SRGBColorSpace/],
  [{toneMapping: THREE.ACESFilmicToneMapping}, /NoToneMapping/], [{xr: {isPresenting: true}}, /XR/],
  [{width: 4096, height: 4096}, /pixel budget/], [{ratio: 3}, /pixelRatio/]
]) { const h = host(patch); rejects(() => createPostprocessingRuntime(h.options), pattern); eq(h.renderer.autoClear, true); }
{
  const h = host(); h.gl.lost = true; rejects(() => createPostprocessingRuntime(h.options), /context is lost/); eq(h.renderer.autoClear, true);
}
{
  const h = host(); h.gl.limit = 128; rejects(() => createPostprocessingRuntime(h.options), /size limit/); eq(h.renderer.autoClear, true);
}
{
  const h = host(); h.gl.complete = false; rejects(() => createPostprocessingRuntime(h.options), /framebuffer is incomplete/); eq(h.renderer.autoClear, true); eq(h.renderer.target, null);
  h.gl.complete = true; createPostprocessingRuntime(h.options).dispose();
}
{
  const h = host(); const {runtime, EffectComposer: composer, RenderPass: renderPass, EffectPass: effectPass, FXAAEffect: effect} = observed(h);
  eq(h.renderer.autoClear, false); eq(composer.multisampling, 0); eq(composer.inputBuffer.texture.type, THREE.UnsignedByteType);
  eq(composer.inputBuffer.texture.colorSpace, THREE.SRGBColorSpace); eq(composer.inputBuffer.depthBuffer, true); eq(composer.inputBuffer.stencilBuffer, false);
  eq(composer.passes.length, 2); eq(renderPass.scene, h.scene); eq(renderPass.camera, h.camera); eq(effectPass.effects, [effect]);
  ok(/fxaa/i.test(effectPass.fullscreenMaterial.fragmentShader)); eq(effectPass.renderToScreen, true); eq(composer.inputBuffer.width, 320); eq(composer.inputBuffer.height, 180);
  eq(h.gl.probes, 2); eq(h.renderer.target, null);
  eq(runtime.inspect().nativeReadiness, 'unverified'); eq(runtime.inspect().shaderAndVisualAcceptance, 'unverified');
  rejects(() => createPostprocessingRuntime(h.options), /already/);
  eq(runtime.render(.05), true); eq(h.renderer.calls.length, 2); eq(h.renderer.calls[0].scene, h.scene); eq(h.renderer.calls[1].scene, effectPass.scene);
  eq(h.renderer.calls[0].target, composer.inputBuffer); eq(h.renderer.calls[1].target, null); eq(runtime.inspect().frames, 1); eq(runtime.inspect().time, .05);
  eq(runtime.render(0), true); eq(runtime.inspect().time, .05);
  for (const value of [-1, NaN, Infinity, undefined, .101]) rejects(() => runtime.render(value), /deltaSeconds/);
  runtime.pause(); eq(runtime.render(.05), false); runtime.resume(); eq(runtime.render(.05), true);
  event(h.lifecycle, 'opencaw:lifecycle', {state: 'suspend'}); runtime.resume(); eq(runtime.render(.05), false);
  event(h.lifecycle, 'opencaw:lifecycle', {state: 'resume'}); eq(runtime.render(.05), true);
  h.doc.hidden = true; event(h.doc, 'visibilitychange'); eq(runtime.render(.05), false);
  h.doc.hidden = false; event(h.doc, 'visibilitychange'); eq(runtime.render(.05), true);
  const before = h.renderer.drawCalls; h.gl.lost = true;
  const loss = event(h.canvas, 'webglcontextlost'); eq(loss.defaultPrevented, true); eq(runtime.render(.05), false); eq(h.renderer.drawCalls, before);
  rejects(() => runtime.revalidate(), /context is lost/);
  h.gl.lost = false; event(h.canvas, 'webglcontextrestored'); eq(runtime.render(.05), false); eq(runtime.inspect().needsRevalidation, true);
  eq(runtime.revalidate().framebuffer, 'complete'); eq(runtime.render(.05), true);
  const sized = runtime.resize(640, 360, 1.5); eq(sized, {width: 640, height: 360, pixelRatio: 1.5, physicalWidth: 960, physicalHeight: 540});
  eq(composer.inputBuffer.width, 960); eq(composer.inputBuffer.height, 540); eq(effectPass.fullscreenMaterial.uniforms.resolution.value.x, 960);
  eq(runtime.render(.05), true); eq(h.renderer.target, null);
  for (const args of [[0, 10, 1], [1.5, 10, 1], [10, 10, 3], [1920, 1080, 2], [4096, 1, 2]]) rejects(() => runtime.resize(...args), /width|pixelRatio|physical size/);
  eq(h.renderer.width, 640); eq(h.renderer.ratio, 1.5);
  h.renderer.width = 600; rejects(() => runtime.render(.05), /size changed outside/); runtime.revalidate(); eq(composer.inputBuffer.width, 900);
  const external = new THREE.WebGLRenderTarget(1, 1); h.renderer.setRenderTarget(external, 2, 1);
  runtime.revalidate(); eq(h.renderer.target, external); eq(h.renderer.cube, 2); eq(h.renderer.mip, 1);
  rejects(() => runtime.render(.05), /offscreen pass/); h.renderer.setRenderTarget(null);
  h.renderer.toneMapping = THREE.ACESFilmicToneMapping; rejects(() => runtime.render(.05), /NoToneMapping/); h.renderer.toneMapping = THREE.NoToneMapping;
  h.renderer.autoClear = true; rejects(() => runtime.render(.05), /autoClear changed/); h.renderer.autoClear = false;
  h.renderer.onRender = () => runtime.render(.01); rejects(() => runtime.render(.05), /Reentrant/); eq(h.renderer.target, null); eq(runtime.inspect().needsRevalidation, true);
  h.renderer.onRender = null; runtime.revalidate(); eq(runtime.render(.05), true);
  let inputDisposes = 0, outputDisposes = 0, fxMaterialDisposes = 0, sharedDisposes = 0;
  composer.inputBuffer.addEventListener('dispose', () => inputDisposes++); composer.outputBuffer.addEventListener('dispose', () => outputDisposes++);
  effectPass.fullscreenMaterial.addEventListener('dispose', () => fxMaterialDisposes++);
  const onSharedDispose = () => sharedDisposes++; Postprocessing.Pass.fullscreenGeometry.addEventListener('dispose', onSharedDispose);
  eq(runtime.dispose(), true); eq(runtime.dispose(), false); eq(inputDisposes, 1); eq(outputDisposes, 1); eq(fxMaterialDisposes, 1);
  eq(renderPass.disposals, 1); eq(effectPass.disposals, 1); eq(effect.disposals, 1); eq(sharedDisposes, 0); eq(composer.disposals, 0); eq(composer.passes.length, 0);
  eq(h.renderer.autoClear, true); eq(runtime.inspect().disposed, true); eq(runtime.inspect().graphicsReadiness, 'disposed');
  for (const target of [h.canvas, h.lifecycle, h.doc]) for (const count of target.counts.values()) eq(count, 0);
  rejects(() => runtime.render(.01), /disposed/); rejects(() => runtime.resize(10, 10, 1), /disposed/); rejects(() => runtime.revalidate(), /disposed/);
  createPostprocessingRuntime(h.options).dispose(); Postprocessing.Pass.fullscreenGeometry.removeEventListener('dispose', onSharedDispose); external.dispose();
}
{
  // Real Quarks object stays part of the exact scene rasterized by RenderPass.
  const h = host(), quarks = new Quarks.BatchedRenderer(); h.scene.add(quarks);
  const geometry = new THREE.BoxGeometry(), texture = new THREE.Texture(), material = new THREE.MeshBasicMaterial({map: texture});
  const mesh = new THREE.Mesh(geometry, material); h.scene.add(mesh);
  let geometryDisposes = 0, textureDisposes = 0, materialDisposes = 0;
  geometry.addEventListener('dispose', () => geometryDisposes++); texture.addEventListener('dispose', () => textureDisposes++); material.addEventListener('dispose', () => materialDisposes++);
  const {runtime} = observed(h); runtime.render(.01); eq(h.renderer.calls[0].scene.children.includes(quarks), true);
  runtime.dispose(); eq(h.scene.children, [quarks, mesh]); eq(geometryDisposes, 0); eq(textureDisposes, 0); eq(materialDisposes, 0);
  geometry.dispose(); material.dispose(); texture.dispose();
}
{
  // Failed attachment removes partial listeners and releases ownership/state.
  const h = host(); rejects(() => createPostprocessingRuntime({...h.options, lifecycleTarget: {}}), /Lifecycle targets/);
  eq(h.renderer.autoClear, true); for (const count of h.canvas.counts.values()) eq(count, 0);
  createPostprocessingRuntime(h.options).dispose();
}
{
  const h = host(); const {runtime, EffectComposer: composer} = observed(h);
  h.gl.complete = false; rejects(() => runtime.resize(640, 360, 1), /incomplete/); eq(runtime.render(.01), false);
  h.gl.complete = true; runtime.revalidate(); eq(runtime.render(.01), true); eq(composer.inputBuffer.width, 640);
  h.gl.limit = 1024; event(h.canvas, 'webglcontextrestored'); runtime.revalidate(); rejects(() => runtime.resize(1200, 500, 1), /physical size/);
  runtime.dispose();
}
{
  const h = host(); let captured;
  class Composer extends Postprocessing.EffectComposer { constructor(...args) { super(...args); captured = this; } }
  let calls = 0; const original = h.renderer.getSize;
  h.renderer.getSize = function(target) { if (++calls === 2) throw new Error('fixture renderer setup failure'); return original.call(this, target); };
  rejects(() => createPostprocessingRuntime({...h.options, Postprocessing: {...Postprocessing, EffectComposer: Composer}}), /setup failure/);
  eq(h.renderer.autoClear, true); eq(captured.renderer, null); eq(captured.passes.length, 0);
  h.renderer.getSize = original; createPostprocessingRuntime(h.options).dispose();
}
{
  const h = host(); const runtime = createPostprocessingRuntime(h.options);
  h.gl.lost = true; eq(runtime.inspect().graphicsReadiness, 'requires-revalidation');
  h.gl.lost = false; event(h.canvas, 'webglcontextrestored');
  h.gl.complete = false; rejects(() => runtime.revalidate(), /incomplete/); eq(runtime.render(.01), false);
  h.gl.complete = true; runtime.revalidate(); eq(runtime.render(.01), true);
  runtime.dispose();
}

{
  const h = host(); const runtime = createPostprocessingRuntime(h.options);
  h.gl.lost = true; event(h.canvas, 'webglcontextlost');
  h.gl.lost = false; h.gl.limit = 512; event(h.canvas, 'webglcontextrestored');
  eq(runtime.inspect().restorationRequired, true);
  rejects(() => runtime.resize(640, 360, 1), /explicit revalidate/);
  eq(h.renderer.width, 320); eq(h.renderer.height, 180); eq(runtime.render(.01), false);
  eq(runtime.inspect().restorationRequired, true);
  runtime.revalidate(); eq(runtime.inspect().restorationRequired, false);
  rejects(() => runtime.resize(640, 360, 1), /physical size/);
  runtime.resize(500, 300, 1); eq(runtime.render(.01), true);
  runtime.dispose();
}

console.log(`Three.js postprocessing actual-package CPU lifecycle: ${checks} assertions passed (renderer/context fixtures; GPU/native acceptance unverified).`);
