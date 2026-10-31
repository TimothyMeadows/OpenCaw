import * as THREE from 'three';
import * as Quarks from 'three.quarks';
import {createThreeQuarksRuntime} from './three-quarks-runtime.mjs';

// Call with the actual host objects and current resolve-engine evidence.
export function attachGameParticles({scene, renderer, engineSelection, anchor = scene, material}) {
  const particles = createThreeQuarksRuntime({THREE, Quarks, scene, renderer, engineSelection, maxSystems: 8, maxParticles: 1024});
  const exhaust = particles.createEmitter({id: 'exhaust', parent: anchor, capacity: 64, rate: 20, lifetime: 1, size: .08, speed: 2, color: [1, .4, .1, 1], material});
  return {
    // Invoke once from the host's presentation loop, before renderer.render().
    update(deltaSeconds) { particles.update(deltaSeconds); },
    pause() { particles.pause(); }, resume() { particles.resume(); },
    cancel() { exhaust.stop(); },
    // Capture exhaust.generation and supply it when scheduling host callbacks.
    restart(token) { return exhaust.restart(token); },
    setReducedMotion(value) { particles.setReducedMotion(value); },
    dispose() { particles.dispose(); }
  };
}
