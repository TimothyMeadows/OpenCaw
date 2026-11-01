// Host-owned raster postprocessing. Imports are supplied by the host, never discovered here.
export const VERIFIED_VERSIONS = Object.freeze({three: '0.182.0', postprocessing: '6.39.5'});
const owners = new WeakMap();
const fail = message => { throw new Error(message); };
const finite = (value, min, max, name) => {
  if (!Number.isFinite(value) || value < min || value > max) fail(`${name} must be finite in [${min}, ${max}].`);
  return value;
};
const integer = (value, min, max, name) => {
  finite(value, min, max, name);
  if (!Number.isInteger(value)) fail(`${name} must be an integer.`);
  return value;
};
function contextOf(renderer) {
  if (!renderer?.isWebGLRenderer || renderer.isWebGPURenderer || typeof renderer.getContext !== 'function') fail('The postprocessing backend requires the existing WebGLRenderer; no renderer fallback is available.');
  const gl = renderer.getContext();
  const Context = renderer.domElement?.ownerDocument?.defaultView?.WebGL2RenderingContext ?? globalThis.WebGL2RenderingContext;
  if (typeof Context !== 'function' || !(gl instanceof Context) || typeof gl.getParameter !== 'function' || !/^WebGL 2\.0/.test(gl.getParameter(gl.VERSION))) fail('The actual renderer context must be WebGL2; a renderer declaration is insufficient.');
  if (gl.isContextLost()) fail('The WebGL2 context is lost. Revalidate after restoration.');
  return gl;
}
function profile(THREE, renderer) {
  if (renderer.outputColorSpace !== THREE.SRGBColorSpace || renderer.toneMapping !== THREE.NoToneMapping) fail('This LDR profile requires SRGBColorSpace and NoToneMapping. Review the host color/tone profile explicitly; no setting was changed.');
  if (renderer.xr?.isPresenting) fail('XR presentation is outside this postprocessing profile.');
}
function dimensions(THREE, renderer, bounds) {
  const css = renderer.getSize(new THREE.Vector2());
  const physical = renderer.getDrawingBufferSize(new THREE.Vector2());
  const ratio = finite(renderer.getPixelRatio(), .25, bounds.maxPixelRatio, 'pixelRatio');
  integer(css.x, 1, bounds.maxDimension, 'width'); integer(css.y, 1, bounds.maxDimension, 'height');
  integer(physical.x, 1, bounds.maxDimension, 'physical width'); integer(physical.y, 1, bounds.maxDimension, 'physical height');
  if (physical.x * physical.y > bounds.maxPixels) fail('Physical pixel budget exceeded. Choose an explicit bounded size/quality.');
  if (physical.x !== Math.floor(css.x * ratio) || physical.y !== Math.floor(css.y * ratio)) fail('Renderer drawing-buffer size disagrees with its logical size and pixel ratio.');
  return {width: css.x, height: css.y, pixelRatio: ratio, physicalWidth: physical.x, physicalHeight: physical.y};
}
function checkTargets(renderer, gl, targets) {
  const previous = renderer.getRenderTarget();
  const cube = renderer.getActiveCubeFace();
  const mip = renderer.getActiveMipmapLevel();
  try {
    for (const target of targets) {
      renderer.setRenderTarget(target);
      if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) fail('The actual LDR/depth framebuffer is incomplete; this device profile is unavailable.');
    }
  } finally { renderer.setRenderTarget(previous, cube, mip); }
}
// EffectComposer.dispose() also disposes module-shared Pass.fullscreenGeometry.
// Keep that borrowed geometry alive for other composers; release our exact pinned
// public resources instead. The host ultimately owns renderer/context teardown.
function disposeOwned(composer) {
  if (!composer) return;
  for (const pass of composer.passes) pass.dispose();
  composer.passes = [];
  composer.deleteDepthTexture();
  composer.inputBuffer.dispose(); composer.outputBuffer.dispose();
  composer.copyPass.dispose(); composer.timer.dispose();
  composer.renderer = null;
}
export function createPostprocessingRuntime({THREE, Postprocessing, scene, camera, renderer, engineSelection,
  maxDimension = 4096, maxPixels = 2073600, maxPixelRatio = 2, maxDelta = .1,
  lifecycleTarget = globalThis.window, visibilityTarget = renderer?.domElement?.ownerDocument} = {}) {
  if (engineSelection?.effectiveEngine !== 'THREEJS' || engineSelection.postprocessing?.backend !== 'PMNDRS_POSTPROCESSING') fail('Resolve THREEJS and its PMNDRS_POSTPROCESSING capability before constructing postprocessing.');
  if (THREE?.REVISION !== '182' || Postprocessing?.version !== VERIFIED_VERSIONS.postprocessing) fail('This reviewed helper requires Three r182 and postprocessing 6.39.5; review other locked versions explicitly.');
  for (const name of ['EffectComposer', 'RenderPass', 'EffectPass', 'FXAAEffect']) if (typeof Postprocessing[name] !== 'function') fail(`Missing postprocessing API: ${name}.`);
  if (!(scene instanceof THREE.Scene) || !(camera instanceof THREE.Camera)) fail('Supply host-owned Scene and Camera from the same Three instance.');
  if (owners.has(renderer)) fail('This renderer already has an owned postprocessing runtime.');
  const bounds = {maxDimension: integer(maxDimension, 1, 8192, 'maxDimension'), maxPixels: integer(maxPixels, 1, 16777216, 'maxPixels'), maxPixelRatio: finite(maxPixelRatio, .25, 3, 'maxPixelRatio')};
  finite(maxDelta, .001, .25, 'maxDelta');
  let gl = contextOf(renderer); profile(THREE, renderer);
  let size = dimensions(THREE, renderer, bounds);
  let gpuLimit = Math.min(gl.getParameter(gl.MAX_TEXTURE_SIZE), gl.getParameter(gl.MAX_RENDERBUFFER_SIZE));
  if (!Number.isFinite(gpuLimit) || gpuLimit < Math.max(size.physicalWidth, size.physicalHeight)) fail('Device texture/renderbuffer size limit is insufficient.');
  const savedAutoClear = renderer.autoClear;
  let composer, renderPass, effect, effectPass, disposed = false, paused = false, suspended = false;
  let hidden = visibilityTarget?.hidden === true, lost = false, needsRevalidation = false, restorationRequired = false, frames = 0, time = 0, rendering = false;
  const listeners = [];
  const listen = (target, name, handler) => {
    if (!target) return;
    if (typeof target.addEventListener !== 'function' || typeof target.removeEventListener !== 'function') fail('Lifecycle targets must implement addEventListener/removeEventListener.');
    target.addEventListener(name, handler); listeners.push([target, name, handler]);
  };
  const active = () => { if (disposed) fail('Postprocessing runtime is disposed.'); };
  const markLost = () => { lost = true; needsRevalidation = true; restorationRequired = true; };
  const currentContext = () => {
    const current = contextOf(renderer);
    if (current !== gl) fail('Renderer context identity changed; dispose and recreate this runtime.');
    return current;
  };
  function verifyTargets() { checkTargets(renderer, gl, [composer.inputBuffer, composer.outputBuffer]); }
  try {
    composer = new Postprocessing.EffectComposer(null, {depthBuffer: true, stencilBuffer: false, multisampling: 0, frameBufferType: THREE.UnsignedByteType});
    composer.setRenderer(renderer);
    renderPass = new Postprocessing.RenderPass(scene, camera);
    composer.addPass(renderPass);
    effect = new Postprocessing.FXAAEffect();
    effectPass = new Postprocessing.EffectPass(camera, effect);
    composer.addPass(effectPass);
    verifyTargets();
    listen(renderer.domElement, 'webglcontextlost', event => { event.preventDefault(); markLost(); });
    listen(renderer.domElement, 'webglcontextrestored', () => { lost = false; needsRevalidation = true; restorationRequired = true; });
    listen(lifecycleTarget, 'hephaera:lifecycle', event => {
      if (event.detail?.state === 'suspend') suspended = true;
      else if (event.detail?.state === 'resume') suspended = false;
    });
    listen(visibilityTarget, 'visibilitychange', () => { hidden = visibilityTarget.hidden === true; });
  } catch (error) {
    for (const [target, name, handler] of listeners) target.removeEventListener(name, handler);
    // A pass added to the composer owns its effects recursively. A construction
    // failure before addPass leaves the unregistered pass/effect with us.
    if (effectPass && !composer?.passes.includes(effectPass)) effectPass.dispose();
    else if (effect && !effectPass) effect.dispose();
    if (renderPass && !composer?.passes.includes(renderPass)) renderPass.dispose();
    try { disposeOwned(composer); }
    finally { renderer.autoClear = savedAutoClear; }
    throw error;
  }
  owners.set(renderer, true);
  return Object.freeze({
    render(deltaSeconds) {
      active(); finite(deltaSeconds, 0, maxDelta, 'deltaSeconds');
      if (rendering) fail('Reentrant postprocessing rendering is unavailable.');
      if (gl.isContextLost()) markLost();
      if (paused || suspended || hidden || lost || needsRevalidation) return false;
      currentContext(); profile(THREE, renderer);
      const now = dimensions(THREE, renderer, bounds);
      if (JSON.stringify(now) !== JSON.stringify(size)) fail('Renderer size changed outside the runtime; use resize or explicit revalidate.');
      if (renderer.getRenderTarget() !== null) fail('Postprocessing renders to the game canvas; finish the host offscreen pass first.');
      if (renderer.autoClear !== false) fail('Renderer autoClear changed during owned postprocessing.');
      rendering = true;
      try { composer.render(deltaSeconds); frames++; time += deltaSeconds; return true; }
      catch (error) { needsRevalidation = true; throw error; }
      finally { rendering = false; renderer.setRenderTarget(null); }
    },
    resize(width, height, pixelRatio = renderer.getPixelRatio()) {
      active(); if (rendering) fail('Cannot resize during rendering.');
      if (gl.isContextLost()) markLost();
      if (restorationRequired) fail('Context restoration requires explicit revalidate before resizing or rendering.');
      currentContext(); profile(THREE, renderer);
      integer(width, 1, bounds.maxDimension, 'width'); integer(height, 1, bounds.maxDimension, 'height');
      finite(pixelRatio, .25, bounds.maxPixelRatio, 'pixelRatio');
      const w = Math.floor(width * pixelRatio), h = Math.floor(height * pixelRatio);
      if (w < 1 || h < 1 || w > Math.min(bounds.maxDimension, gpuLimit) || h > Math.min(bounds.maxDimension, gpuLimit) || w * h > bounds.maxPixels) fail('Requested physical size exceeds the pixel/device budget.');
      // One atomic logical-size/DPR update avoids transient oversized buffers.
      needsRevalidation = true;
      renderer.setDrawingBufferSize(width, height, pixelRatio);
      composer.setSize(width, height, false);
      size = dimensions(THREE, renderer, bounds);
      needsRevalidation = true;
      verifyTargets(); needsRevalidation = false;
      return {...size};
    },
    pause() { active(); paused = true; },
    resume() { active(); paused = false; },
    revalidate() {
      active(); if (rendering) fail('Cannot revalidate during rendering.');
      needsRevalidation = true;
      currentContext(); profile(THREE, renderer);
      const next = dimensions(THREE, renderer, bounds);
      const limit = Math.min(gl.getParameter(gl.MAX_TEXTURE_SIZE), gl.getParameter(gl.MAX_RENDERBUFFER_SIZE));
      if (!Number.isFinite(limit) || Math.max(next.physicalWidth, next.physicalHeight) > limit) fail('Restored device size limit is insufficient.');
      composer.setSize(next.width, next.height, false); verifyTargets();
      size = next; gpuLimit = limit; lost = false; needsRevalidation = false; restorationRequired = false;
      return {context: 'webgl2', framebuffer: 'complete', profile: 'ldr', shaderAndVisualAcceptance: 'unverified', nativeReadiness: 'unverified'};
    },
    inspect() {
      return {backend: 'PMNDRS_POSTPROCESSING', profile: 'ldr-fxaa', frames, time, disposed,
        paused, suspended, hidden, contextLost: lost || (!disposed && gl.isContextLost()), needsRevalidation, restorationRequired,
        ...size, bounds: {...bounds}, graphicsReadiness: disposed ? 'disposed' : needsRevalidation || lost || gl.isContextLost() ? 'requires-revalidation' : 'context-and-framebuffer-checked',
        shaderAndVisualAcceptance: 'unverified', nativeReadiness: 'unverified'};
    },
    dispose() {
      if (disposed) return false;
      if (rendering) fail('Cannot dispose during rendering.');
      disposed = true;
      for (const [target, name, handler] of listeners) target.removeEventListener(name, handler);
      try { disposeOwned(composer); }
      finally { renderer.autoClear = savedAutoClear; owners.delete(renderer); }
      return true;
    }
  });
}
