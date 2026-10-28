---
name: phaserjs-build-controls
description: Implement Phaser keyboard, pointer, gamepad and virtual controls with explicit scene, player and modal input ownership.
engines: [PHASERJS]
---

# Build Phaser Controls

## When to use

Add or repair Phaser player actions, pointer interactions, touch controls, device switching or control feedback.

## Engine and dependencies

Before edits or tool launches, run `resolve-engine.sh` and `resolve-skill.sh phaserjs-build-controls`; require compatibility and respect task override scope. Inspect the locked Phaser major, Scene Input Plugin configuration, browser targets and player/action contract. Use project packages; do not add a controls plugin, dependency or CDN implicitly.

## Workflow

1. Map `this.input.keyboard`, pointer events and the configured gamepad plugin to project actions. Distinguish held values, press/release edges and buffered commands; use declared clock ownership for expiration. Rebind prompts from the same binding source.
2. Use `setInteractive` with appropriate hit areas and one owner for each interactive object. For world aiming, convert through the relevant camera rather than confusing screen coordinates with scrolled/zoomed world coordinates. Define drag thresholds, release outside the canvas and multitouch pointer ownership.
3. Assign each local player its device and virtual controls. Apply dead zones, touch target size and held-state clearing. Keyboard capture must not swallow text entry or browser navigation outside the active game surface.
4. Coordinate parallel HUD/gameplay scenes, modal input and `topOnly`/scene input policies. A UI click must not also activate the world; define cancel/back and focus restoration. Pause or sleep is not proof that all external listeners stopped.
5. Clear actions and release pointers on blur, cancellation, disconnect and shutdown. Own listener and key cleanup without removing another scene's bindings. Device reconnect requires fresh assignment and no stale action replay.
6. Use a capability-checked browser haptic adapter only for the assigned device. Bound intensity/duration, honor settings and cancel on pause/disconnect. Unsupported vibration and asynchronous errors remain presentation failures.

## Output and verification

Deliver the action adapter and lifecycle/input ownership notes. Check scroll/zoomed picking, two touches, held keys during blur, scene restart, modal click-through, rebinding and controller reassignment. Test rejected haptic requests; physical hardware is required for tactile verification. Consult the [Phaser input guide](https://docs.phaser.io/phaser/concepts/input) for the host revision.
