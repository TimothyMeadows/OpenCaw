import * as THREE from 'three';
import * as Postprocessing from 'postprocessing';
import {createPostprocessingRuntime} from './postprocessing-runtime.mjs';

// Use the actual existing renderer/scene/camera and fresh engine selection.
// Configure SRGBColorSpace + NoToneMapping explicitly as part of the host's LDR
// renderer profile before attachment. The helper never changes that profile.
export function attachGamePostprocessing({scene, camera, renderer, engineSelection}) {
  return createPostprocessingRuntime({THREE, Postprocessing, scene, camera, renderer,
    engineSelection, maxDimension: 4096, maxPixels: 1920 * 1080, maxPixelRatio: 2});
}
// One host loop: simulation -> presentation -> particles.update(delta) ->
// postprocessing.render(delta). Do not also renderer.render(scene, camera).
// Call resize(logicalWidth, logicalHeight, explicitDpr) for bounded sizing.
// The helper handles MAUI hephaera:lifecycle and document visibility. After context
// restoration call revalidate() explicitly; inspect() retains native QA unknowns.
// At final application teardown, retire ALL composer/pass users of this package
// instance, then explicitly Postprocessing.Pass.fullscreenGeometry.dispose(),
// then renderer.dispose(). The shared getter is pinned upstream internal API;
// recheck on version changes. Keep shared scene/assets caller-owned.
