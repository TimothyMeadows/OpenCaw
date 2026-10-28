# Niagara runtime

Use this for Niagara authoring or runtime integration. Inspect real system assets and installed-version headers; a template name or successful spawn call is not proof of a production effect.

## Assets and parameter contracts

Record system/emitter identities, materials, meshes, textures, data interfaces, user parameters and target requirements. Choose CPU/GPU simulation based on target support and interaction needs. GPU results or collision are unsuitable as authoritative gameplay truth. Fixed/dynamic bounds must cover the actual lifetime and camera use; overlarge bounds can destroy culling efficiency.

Expose typed `User.*` parameters with units, defaults and ranges. Set the full owned parameter set before activation, and validate spelling/types against the real asset. `UNiagaraComponent::SetVariableFloat`, vector/color/object setters and corresponding version-supported getters do not replace asset inspection: adding an override alone does not prove an emitter consumes it. Document which graph input each parameter drives.

## Spawn, pool and retirement

`UNiagaraFunctionLibrary::SpawnSystemAtLocation`/`SpawnSystemAttached` have explicit activation, cull and pool options. Treat a null result, cull rejection and asset failure distinctly. Spawn without automatic activation when a parameter must be set before the first update. Attached effects need socket/space ownership and a response to source actor teardown.

Choose `ENCPoolMethod::None`, `AutoRelease` or `ManualRelease` intentionally. With AutoRelease, the handle becomes unowned when the system returns; do not retain it as a safe mutable actor field. With ManualRelease, record a single retirement path and call `ReleaseToPool` according to the installed API's completion semantics. `Deactivate` may allow particles to finish, while `DeactivateImmediate` ends them abruptly; choose this per effect. Do not mix pool return, arbitrary component destruction and automatic destruction policies.

Before reacquisition activation, explicitly write the new transform, attachment, user parameters and callback bindings. Pooling is an allocation optimization, not a guarantee that every application parameter was reset. An old event's completion must compare its event/generation ownership before cancelling a newer playback. Once released, never read or update that component through the retired handle.

## Clocks and scalability

Specify game-time, real-time or sequence-driven age. Pause, dilation, seeking and editor scrubbing are separate cases; avoid advancing an effect through two clocks. Bounded impact requests may be merged/capped, but a presentation cap must not discard authoritative damage or inventory events.

Use NiagaraEffectType and project scalability policies to limit instances, distance/significance and quality. Validate reactivation behavior after culling and virtualization-like suspension. Measure particle counts, data-interface cost, CPU simulation and GPU/overdraw at representative peak concurrency. CPU headless operation cannot prove GPU simulation, materials, sorting or supported target rendering.

## Acceptance

A useful pool test creates a real finite CPU-emitter system, sets a visible-driving parameter, activates, cancels, releases and reacquires with a different parameter/transform. It checks actual reuse and resulting state, then tests overlapping owners. Missing assets must block or fail; replacing them with an empty system removes the claim being tested. Capture target visuals for silhouette, timing, occlusion, flashing and gameplay readability, with alternative cues for essential information.

Official references, with version matching:

- [NiagaraFunctionLibrary API](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/Niagara/UNiagaraFunctionLibrary)
- [NiagaraComponent API](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/Niagara/UNiagaraComponent)
- [Niagara scalability](https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-and-best-practices-for-niagara)
