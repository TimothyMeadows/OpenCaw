# Three.js particles with three.quarks

## Automatic selection

Selecting THREEJS selects **three.quarks** for new particle and VFX work. Engine resolution, compatible role capabilities and `threejs-build-particles` expose the same default, including a validated isolated Three.js override. Babylon.js, Phaser, Unity, Unreal and Godot retain their engine-specific particle systems. MAUI packaging and visual/media pipeline selection stay independent.

Selection is a capability declaration. It neither imports Quarks nor installs packages, changes a renderer, upgrades Three.js, creates effects or edits existing games. Read-directive engine contracts pick it up automatically; stale inline definitions require explicit regeneration as usual. There is no silent fallback to custom Points or another library when dependencies or renderer support are unavailable.

## Dependencies and read-only discovery

The initial real-library CPU acceptance set is `three@0.182.0`, `three.quarks@0.17.1` and `quarks.core@0.17.1`. Quarks declares a Three peer range of `>=0.182.0` and a wildcard core dependency; keep the resolved core version and package integrity in the host lockfile. These versions describe the tested baseline, not permission to upgrade an existing host. Newer matching versions remain unverified until their actual APIs and targets are checked.

From an installed host project's root:

```bash
bash .hephaera/commands/resolve-engine.sh
bash .hephaera/commands/threejs-particles.sh inspect --renderer WebGLRenderer
```

Inspect reads bounded project/package/lock metadata without importing third-party JavaScript. It compares root declarations, lock and installed versions, and detects unsupported nested Three/core resolution. An exact metadata match is **not** installed-content verification, executable readiness or rendering proof. `executionReadiness`, installed content and actual rendering remain `unverified`. npm lockfile v2/v3 and ordinary direct node_modules layouts have executable discovery coverage. Other package managers, workspace links, aliases, complex version ranges and dependency graphs need their own explicit lock/resolution review; do not convert or reinstall a project just to make this inspector green.

Core `three.quarks` uses the established WebGL integration. A declared WebGPURenderer is unavailable here; do not select WebGL silently. The experimental `quarks.nodes`, optional R3F package and hosted visual editor are separate choices. No editor account, asset download, cloud service or upload is required.

For a new explicitly authorized npm setup with this tested baseline, the project owner can add:

```bash
npm install --save-exact three@0.182.0 three.quarks@0.17.1 quarks.core@0.17.1
```

Inspect the existing host lock first. Never run that command to overwrite an older Three revision without an explicit migration decision. Respect the host's package manager and normal supply-chain policy. Keep one compatible Three copy; preserve Three, Quarks and core MIT notices. The baseline test fixture uses exact versions, a committed npm lock and scripts-disabled installation. Hephaera production commands install nothing.

## Integrate a bounded runtime

```bash
bash .hephaera/commands/threejs-particles.sh scaffold \
  --output src/engine/particles --renderer WebGLRenderer
```

Scaffold copies the reviewed helper, example and usage contract into a new owned directory. Existing output, unsafe paths, linked components, incompatible engine projects and invalid override scopes are refused. It records source and engine identities in `hephaera-particles.json`. It does not modify package declarations, lockfiles or renderers, and it does not overwrite or automatically migrate an older helper. An interrupted unpublished copy stays in durable project-local scaffold state for inspection.

Use the copied `example.mjs` with host-installed imports; read `.engine/threejs/particles/README.md` in the shared baseline for the exact helper API. The helper owns one BatchedRenderer for its scene and uses the existing presentation update loop. The host remains responsible for the canvas, renderer, scene, camera and simulation.

The helper covers bounded point/sphere-emitter billboard effects and explicit lifecycle ownership. Quarks' broader mesh/trail/shader/JSON/custom behavior APIs require separately reviewed host integration and matching budgets; the bounded helper does not certify arbitrary upstream configurations. No particle completion callback grants damage, targeting, movement, travel arrival or authoritative projectile outcomes.

Define finite emission, capacity, lifetime, system/instance and delta bounds before activation. Upstream0.17.1 has no public hard `maxParticle` cap, and batch buffers can grow. Do not mistake that README parameter or a buffer's capacity for a configured safety bound. The helper validates its supported recipe and budgets; unsupported behaviors, sub-emitters and hidden emission sources are not accepted by it. One renderer update owns particle time; do not also update systems from another loop.

Pause freezes emission/simulation; resume consumes normal bounded frame time without catching up the entire hidden interval. Cancellation and pooling/reset retire old generations and clear active particles while retaining bounded reusable pools/batches. Final remove/disposal releases owned batch geometry plus generated/settings materials. Borrowed materials, textures and model geometry remain host-owned. Shared scene ownership, zero-delta emission, world transforms and reused IDs need explicit tests. Read upstream APIs against the locked version rather than assuming all versions have identical cleanup methods.

## Effects, motion and accessibility

Bind effects to reviewed model/action anchors and controller-owned events. Capture target points explicitly. Keep movement, collision, gameplay projectiles and hit results outside particle simulation. Do not let phase/clip completion duplicate gameplay. Coordinate rendering, sound, UI, camera and any actual haptics through the existing feedback owner.

Use finite quality tiers, reduced-motion/flash settings and bounded transparent overdraw, textures, shader variants and active instances. Preserve essential cues. Imported JSON/textures need source rights, provenance, current asset review and compatible budgets; generated inputs still obey STYLE/MEDIA and separate promotion requirements. Creating code-only particle helpers does not generate or promote image/audio assets.

Pinned Bubo motion/action sample adapters retain their historical CPU Points implementations and hashes. They are not relabeled Quarks, and this change does not rewrite a submodule or its prior approvals. For new host particle production use this selected Quarks owner. Reusing a legacy sample's built-in particles requires an explicit reviewed host migration/integration; a current engine metadata field does not transform that sample. Animation/clip handoff and effect authority remain separate.

MAUI packages bundle the host's static build normally. Route `hephaera:lifecycle` suspend/resume into the particle owner and existing presentation clock, and clean up on scene/window teardown. A browser or CPU pass does not establish WebGL, transparency, context-loss, input, frame pacing, thermal or memory behavior in Windows/Android WebViews or Apple WKWebView. Actual target/game/device QA remains required; WebGPU support and deterministic particle replay are not implied.

## Verification and provenance

Offline engine/CLI tests check selection, overrides, metadata honesty and source-copy guards. `tests/test-threejs-quarks-runtime.mjs` uses the real locked package trio for CPU lifecycle/resource tests. Explicit fixture setup:

```bash
npm ci --ignore-scripts --no-audit --no-fund --prefix tests/fixtures/threejs-quarks
node tests/test-threejs-quarks-runtime.mjs
```

This does not create a WebGL context or certify visual quality, frame budgets, mobile/MAUI readiness or GPU driver cleanup. Preserve actual renderer/device evidence separately. No commits, pushes, external release, vendor editor or package promotion is granted by particle selection.

- [Upstream project](https://github.com/Alchemist0823/three.quarks)
- [Published0.17.1 source manifest](https://github.com/Alchemist0823/three.quarks/blob/a432a153354ed568c5aa2c94777376c546b5425b/packages/three.quarks/package.json)
- [Pinned package lifecycle implementation](https://github.com/Alchemist0823/three.quarks/blob/a432a153354ed568c5aa2c94777376c546b5425b/packages/three.quarks/src/ParticleSystem.ts)
- [Pinned batch renderer](https://github.com/Alchemist0823/three.quarks/blob/a432a153354ed568c5aa2c94777376c546b5425b/packages/three.quarks/src/BatchedRenderer.ts)
