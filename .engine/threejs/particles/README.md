# Bounded three.quarks starter

`three-quarks-runtime.mjs` is an independently authored host integration tested with `three@0.182.0`, `three.quarks@0.17.1` and `quarks.core@0.17.1`. The host supplies its locked Three/Quarks namespace imports, actual Scene/WebGLRenderer and current THREEJS particle-selection evidence. No import downloads packages, creates another frame loop or changes the selected renderer.

The helper owns one BatchedRenderer per Scene, one shared base geometry/default material and point/sphere billboard recipes. This is a bounded starter, not a replacement implementation of the complete upstream loader, mesh/trail, behavior, editor or plugin APIs. Custom upstream features require a reviewed host integration with equivalent bounds and actual renderer evidence. It does not select experimental WebGPU nodes.

## API

`createThreeQuarksRuntime({THREE, Quarks, scene, renderer, engineSelection, maxSystems, maxParticles, maxDelta})` returns `createEmitter(recipe)`, `update(seconds)`, `pause()`, `resume()`, `clear()`, `reset()`, `remove(id)`, `setQuality(0|1|2)`, `setReducedMotion(boolean)`, `stats()` and idempotent `dispose()`.

Each recipe requires `id` and integer `capacity`. Other fields are `kind: rate|burst`, `rate`, `count`, `lifetime`, `duration`, `looping`, `size`, `speed`, four linear `color` RGBA values, `space: world|local`, `parent`, borrowed `material`, `shape: point|sphere`, `radius` and `autoStart`. A time emitter reserves at least `ceil(rate * (lifetime + maxDelta)) + 2` slots. A non-looping burst has one explicit count no greater than capacity. Bursts, distance emission, prewarming and arbitrary behaviors cannot be combined through this helper. Scene capacity is the sum of reservations; it is not an OS memory bound or exact GPU-buffer byte budget.

The returned emitter handle exposes its Three.js `emitter` transform and `generation`, plus `play(token?)`, `pause(token?)`, `restart(token?)`, `stop(token?)`, `clear(token?)`, `dispose(token?)` and `stats()`. Removed/recreated IDs never accept an old handle. A restart, stop or clear advances the handle's generation; host asynchronous callbacks must capture and pass their token. Calls without a token are intentional current synchronous commands. No completion/gameplay callbacks are scheduled internally.

`stop`/`clear` remove active particles and pause at the beginning, retaining a bounded reusable CPU pool. `play` resumes; `restart` clears/replays. Runtime `clear`/`reset` stop every emitter; reset also resets its diagnostic clock. Neither silently resumes a globally paused runtime. Disposal removes systems/attachments and releases owned pools, generated batch geometry and both batch-owned material clones. Caller material, textures, anchors and the main scene/renderer remain caller-owned. Release caller-held references after disposal.

## Clock, bounds and lifecycle

Supply one presentation clock in seconds. Delta must be finite and at most configured `maxDelta` (default .1, maximum .25); the helper subdivides accepted deltas into at most .1-second upstream steps. It does not discard accepted time through Quarks' internal clamp, and zero delta is a no-op. Pause freezes particle simulation and this clock. Do not replay a hidden-tab backlog; clamp or reset it according to the game's explicit timing policy. Update the game/anchor transforms first; the helper updates world matrices before simulating.

Emitter parents must be attached beneath the owned Scene. Moving an emitter out of it releases that emitter and fails the tick explicitly. Do not modify `emitter.system` configuration outside the helper; its owned emission settings are checked before updates. The guards are cooperative, not a sandbox against game code that directly mutates upstream objects. Active/pool counts are checked against conservative reservations after each bounded step.

Quality tiers reduce emission to zero/half/full. Reduced motion further reduces future emission to one quarter. Quality zero hides the emitter while aging existing particles. These settings do not retroactively grant a new burst or silently restart an effect. Reduced flash, texture contrast and gameplay readability still need authored materials and actual visual review.

Quarks 0.17.1 exposes `neededToUpdateRender`, `batches`, `systems` and `systemToBatchIndex` publicly. Initial renderer settings are already registered before its public dirty flag is cleared, avoiding an initial Map delete/re-add that would advance one system twice. This helper does not expose renderer-setting mutation. Empty batches are removed and remaining public indices rebuilt; geometry and both generated shader/settings material clones are disposed separately because upstream SpriteBatch.dispose releases geometry alone. Preserve this tested API contract when updating packages.

`example.mjs` shows imports and host lifecycle wiring. For MAUI, the host can route `opencaw:lifecycle` suspend/resume to pause/resume while its one normal game loop owns updates. Actual WebGL shader/render output, target performance, mobile/MAUI behavior and bitwise deterministic replay are unverified by CPU-only acceptance tests.
