---
name: phaserjs-animate-sprites
description: Build Phaser sprite clips and presentation tweens with versioned atlas contracts, interruption and restart-safe ownership.
engines: [PHASERJS]
---

# Animate Phaser Sprites

## When to use

Implement sprite animation, atlas frame selection, tweened presentation or actor animation state adapters.

## Engine and dependencies

Before edits or tool launches, run `resolve-engine.sh` and `resolve-skill.sh phaserjs-animate-sprites`; require compatibility and respect task override scope. Inspect the locked Phaser major, atlas/frame metadata, gameplay states and clock policy. Use authorized project sprites; skeletal-animation middleware, authoring tools and their licenses remain separate selections.

## Workflow

1. Validate texture keys, frame names/order, trim/pivot metadata and clip durations. Build named animation definitions through `this.anims` with explicit repeat, frame rate and delay; namespace shared keys and avoid redefining them on every scene restart.
2. Separate shared AnimationManager definitions from each Sprite's animation state and scene-owned `TweenManager` work. Configure per-actor playback and transitions; missing clips must report the intended fallback or block according to the gameplay contract.
3. Define movement, facing, hit-react and one-shot precedence. Restart, complete, stop and interrupt are distinct paths. A transition token prevents a cancelled clip's completion listener from mutating the replacement state.
4. Use tweens for presentation channels with explicit target/property ownership and cancellation restoration. Do not tween a physics-owned authoritative position. Remove/stop owned tweens when actors despawn and reset pooled sprites' frame, alpha, scale and playback state.
5. Keep gameplay outcomes on the simulation clock. Animation events can drive bounded presentation; skipped frames, slow motion or pause cannot duplicate damage or delay authoritative invulnerability indefinitely. Version-specific filters/FX must follow the selected Phaser renderer.
6. Remove event handlers and owned playback on shutdown; preserve global definitions and textures while other scenes or sprites still need them.

## Output and verification

Deliver atlas/clip contracts, transitions and interruption/cleanup behavior. Check missing frames, trimmed alignment, rapid state changes, duplicate completion listeners, pooled reuse, scene restart, pause and varied frame rates. Record visual timing and readability in a running build; definition validation alone cannot prove animation quality. Consult the [animation guide](https://docs.phaser.io/phaser/concepts/animations) and verify APIs against the host revision.
