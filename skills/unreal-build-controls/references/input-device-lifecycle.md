# Input contexts and device lifetime

Enhanced Input routes actions through mapping contexts on a LocalPlayer subsystem. Verify explicit plugin selection and version. Bind on the intended input-component lifetime and install contexts when the correct LocalPlayer is available; controller, pawn and LocalPlayer are different owners.

| Transition | Observable behavior |
| --- | --- |
| Repeated possession | One active context/binding set for the feature. |
| Menu during held attack | Deliberate consumption and gameplay-held-intent policy. |
| Menu closes | Valid focus restored; submit cannot replay into gameplay. |
| Remap | Gameplay and HUD display the same effective mapping. |
| Device/player leaves | Owned input/effects stop; other players remain unaffected. |

Choose mapping priority and key consumption deliberately. Persist user preferences rather than installed-context pointers. For held-key suppression on rebuild use supported release-specific options and verify transitions; do not assume every context change produces a fresh press.

## Haptic output

Force feedback and newer device-specific haptic surfaces differ. Use APIs actually supported by the selected platform; PlayerController ownership does not guarantee physical device support. Do not invent platform SDK behavior.

Record effect/player identity, clock, duration, intensity, priority and cancellation reasons. Define overlap mixing/replacement and whether pause uses gameplay or real time. Stable effect identity prevents a canceled attack from stopping another effect. Apply user intensity/accessibility settings before dispatch.

On disconnect, focus loss, unpossession and travel, stop owned active effects. Cancellation is safe to repeat. Reconnect establishes current device ownership and starts fresh output only; expired patterns cannot replay. Failure or unsupported haptics never roll back gameplay state.

Automated tests establish routing and attempted cancellation. Tactile acceptance needs actual device/platform/settings and observed output. Browser gamepad results cannot certify native force feedback.

## Official references

- [Enhanced Input](https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine)
- [Force feedback](https://dev.epicgames.com/documentation/en-us/unreal-engine/force-feedback-in-unreal-engine)
- [Input overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/input-overview-in-unreal-engine)

Use host-version signatures and selected platform support.
