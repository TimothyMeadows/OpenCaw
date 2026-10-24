# Gameplay Feedback And Haptic Feedback

Gameplay feedback coordinates visible, audible, timed, and tactile responses to events. Haptic feedback means tactile output through a supported physical device. Treat device support, successful API submission, and physically observed output as three different findings.

## Event and channel ownership

Emit presentation events after authoritative transitions. A useful event contains a stable identity, simulation tick or revision, subject, audience/local player, event type, magnitude tier, world position, and expiration. A hit event reflects an accepted hit; a VFX collision or haptic callback never accepts the hit itself. Prevent duplicate delivery from replay, prediction correction, reconnect, or repeated subscriptions using the runtime's event policy.

Map each event to a bounded set of applicable channels: actor animation, VFX, audio, camera, HUD, and haptics. State duration and concurrency limits, priority, cooldown, intensity mapping, and reduced-motion/flash alternatives. Distinguish a short confirmation from a sustained state with explicit end/cancel. Avoid stacking camera displacements, full-screen flashes, and vibration independently without a combined intensity cap.

For overlapping effects choose a policy per channel: replace, strongest-wins, blend within a limit, coalesce, or bounded queue with expiration. Releasing one effect must not cancel another owner's newer effect. Use handles or generations for ownership. Test rapid repeated impacts, two simultaneous sources, owner destruction, rejected predictions, and a sustained effect interrupted by a modal or scene transition.

## Clocks, hit-stop, and interruption

Declare whether each duration follows simulation, presentation/unscaled, audio, or device time. A pause may stop gameplay while an accessibility cue or menu transition uses unscaled time. Define whether queued events expire while paused; old events must not burst when play resumes.

If hit-stop is selected, make it a scoped request to the existing clock owner with maximum duration, exclusions, and composition rules. Releasing its request restores the effective pause/slow-motion policy, not a hardcoded timescale of one. Never pause network authority, input release collection, or UI cancellation unintentionally. Animation interruption and audio/VFX fades should preserve truthful game state even when a presentation sequence ends early.

Cancel applicable feedback on death, despawn, save/load, owner or scene disposal, player reassignment, and focus/pause transitions. Cleanup must be idempotent. Catch adapter failures at the presentation boundary, record useful diagnostics, and keep simulation progressing.

## Haptic adapter contract

- Resolve a device through the local player's current input ownership. A controller index is not a stable identity. Remote-player events must not vibrate the local player's unrelated device; split-screen adapters must isolate ownership.
- Probe the actual selected API and device capability, including motor/trigger/mobile differences. Keep unsupported, disabled by preference, disconnected, pending, succeeded, failed, and cancelled outcomes explicit. No implicit purchase, library, permission request, or platform service is required by this skill.
- Apply saved global and per-player enable/intensity settings and a bounded event scale. Clamp amplitude and duration to supported ranges, bound duty cycle and concurrency, and provide separate adjustment where useful. Essential cues also need visible or audible equivalents.
- Keep asynchronous API requests cancellable by owner/generation. Reject or expire stale queued effects. Handle rejected promises, native errors, denied permission, and stop failures without leaking callbacks or making a gameplay transition wait for device completion.
- Stop on pause/focus loss when required by the declared policy, scene exit, ownership change, and disconnect. A device-local stop must not stop another player's active device. Teardown attempts must tolerate an already missing device.
- Reconnect requires fresh capability and player-ownership resolution. Do not replay the pre-disconnect queue or send a delayed stop from an old generation to a newly assigned effect. New eligible gameplay events may resume output after preferences and capability are checked.

Use the compatible engine control skill for the API and selected plugin/platform rules. Engine-independent tests can exercise adapter scheduling and failure paths. A physical device test is required to claim tactile output, strength, comfort, or timing as experienced by a person.

## Acceptance scenarios

| Scenario | Expected result | Evidence boundary |
| --- | --- | --- |
| Two local players and two devices | Each event affects only its owning player's enabled device | Device-routing tests; physical test for actual output |
| Rapid impacts and sustained effect overlap | Declared cap, priority, expiration, and cancellation hold | Deterministic adapter/clock test and runtime capture |
| Hit-stop during user pause or slow motion | Ending the effect preserves the clock owner's remaining requests | Controlled clock-state test |
| Disable haptics or use an unsupported device | No tactile request; equivalent essential cue remains | Adapter logs plus UI/runtime check |
| API rejects or device disconnects mid-effect | No unhandled error, stale replay, or simulation dependency | Injected error/disconnect plus actual-device test when available |
| Reconnect under another player, then receive late callback | No cross-player output or cancellation of a new generation | Ownership/generation test |
| Exit scene, lose focus, reopen HUD, or repeat teardown | Applicable channels stop once and leave no listeners or pending work | Lifecycle counters and representative runtime test |

Record expected and observed results, build/runtime/device, and artifacts with each verdict. Missing hardware is `not-run` or `blocked` with a reason; simulated API success is not physical acceptance.
