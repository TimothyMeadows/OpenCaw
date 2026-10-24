# Locomotion and prediction boundaries

CharacterMovement owns collision-aware movement for its Character. Route player and AI intent into it rather than independently writing the capsule transform. Physics, root motion and navigation integrate with that authority.

## Extension decisions

Define supported modes, transition preconditions and interruption. Tune acceleration, braking and floor/step behavior in actual units. Moving platforms need deliberate base changes and invalid-base recovery. Teleports use an engine-supported discontinuity path so prediction does not treat them as ordinary travel.

Custom networked movement retains enough validated state for replay/correction. Inspect `FSavedMove_Character`, compressed flags and release-specific network move-data extensions. A client-only field that changes movement but is absent from replay causes inconsistent correction. Bound payloads; cosmetic smoothing cannot authorize displacement.

Root-motion sources, montages and motion warping need a displacement owner and cancellation rule. An animation event must not become authoritative remote movement or damage merely because it occurred locally.

## Mover

Mover APIs, backend choices and maturity vary by release. Verify explicit project selection and experimental-risk decisions. Do not combine independent prediction owners or silently convert a CharacterMovement game. Resolve input, collision, animation, abilities, navigation and multiplayer migration before edits.

## Evidence classes

| Evidence | Establishes |
| --- | --- |
| Standalone swept movement | Collision, mode changes and bounded stopping in that fixture. |
| Separate server/client processes | Prediction, saved-move replay and correction under measured network conditions. |
| Target playtest | Response, camera comfort, animation alignment and perceptual correction quality. |

Include base loss, interruption, unpossession and fast direction changes. Record frame rate, movement settings, latency/loss, correction magnitude/frequency and budget. Do not assign fake network roles to claim client correction was exercised.

## Official references

- [CharacterMovement](https://dev.epicgames.com/documentation/en-us/unreal-engine/character-movement-component-in-unreal-engine)
- [Networked movement](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine)
- [Mover concepts](https://dev.epicgames.com/documentation/en-us/unreal-engine/mover-features-and-concepts-in-unreal-engine)

Match installed headers and documentation to the host version before overriding APIs.
