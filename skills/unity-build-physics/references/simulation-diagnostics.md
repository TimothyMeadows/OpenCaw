# Simulation selection and physics diagnostics

## Select the actual implementation

Record Editor version, installed modules/packages, component types and existing simulation owner. Classic 3D uses Rigidbody/Collider with a 3D physics scene; classic 2D uses Rigidbody2D/Collider2D and its own simulation/query world. Physics Core is a separate, version-qualified selection where available. Determine its documented world/body/shape APIs, maturity, supported platforms and integration boundaries from the actual installed Editor. Do not enable it implicitly, claim it exists in every Unity 6 release or substitute classic 2D fixture results as Physics Core acceptance.

For each active world, record automatic versus scripted simulation, timestep, substep/catch-up limits, gravity, units, interpolation, broadphase and authority. Simulate once per intended step; avoid both automatic stepping and a second manual step. Fixed scheduling does not imply deterministic outcomes across machines. Network/replay acceptance needs measured tolerances and an explicitly selected synchronization strategy.

## Collision and queries

Create a small interaction matrix for solid contacts, triggers and queries. Check body type, enabled state, active hierarchy, layers, ignored pairs, collider geometry, transform synchronization and query-specific masks/trigger flags. Global layer-matrix settings and per-query masks answer different questions. Detect nonalloc result-buffer saturation; incomplete data is not proof of no other hits.

Test fast thin bodies against representative obstacles before selecting CCD. Document supported collision-detection modes for the selected body/domain and their performance cost. CCD does not repair invalid teleports or competing Transform writes. Validate collider scales, meshes and moving kinematic surfaces against the actual engine backend. Contact material, iteration or timestep changes require measured improvements rather than masking a motion-owner bug.

## Sleep and force diagnosis

For classic 3D Rigidbody, an ordinary nonzero `AddForce` wakes an eligible sleeping dynamic body; a zero force does not. Calling `WakeUp` universally is not the correct first repair. Inspect `isKinematic`, active state, mass/force mode, constraints, sleep threshold, timestep and competing writes. Inactive or kinematic bodies do not become valid force targets merely by waking them. For 2D or Physics Core, read that domain's actual force/wake contract instead of assuming identical semantics.

Record pre-step and post-step body state and the simulation that consumed the force. Use version-compatible velocity properties (`linearVelocity` in current Unity 6 APIs versus legacy names where applicable). Avoid measuring an interpolated render transform as though it were the simulation state.

## Meaningful checks

Use isolated native physics scenes to test a falling body/contact, a bounded query, sleep/nonzero-force behavior and cleanup without rewriting global project settings. Repeat render-rate and fixed-step pressure scenarios in a real player. A simple simulation fixture establishes only its selected backend and API; it does not certify character feel, all layer rules, CCD suitability or Physics Core support.

## Sources

- [Rigidbody.AddForce](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Rigidbody.AddForce.html).
- [LocalPhysicsMode](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/SceneManagement.LocalPhysicsMode.html).
- [PhysicsScene.Simulate](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/PhysicsScene.Simulate.html).
- [PhysicsScene2D.Simulate](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/PhysicsScene2D.Simulate.html).

Use installed-version documentation for newer domain-specific APIs; unavailable implementations remain blocked rather than simulated as native success.
