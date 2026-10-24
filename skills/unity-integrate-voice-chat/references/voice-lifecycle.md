# Vivox channels, permissions and devices

## API selection

Check `com.unity.services.vivox` and its dependencies against the locked Editor and targets. Current Vivox Unity APIs expose initialization/login and channel operations through `VivoxService.Instance`; older integrations use different types. Match signatures to the installed package and existing authentication model. Never mix legacy login/session examples with current service interfaces. [Vivox Unity documentation](https://docs.unity.com/en-us/vivox-unity).

Separate OS capture permission, account login, audio device readiness, channel membership and transmission. Login alone must not begin microphone capture contrary to the selected policy. Check platform manifest/usage descriptions; a denied permission should not trigger repeated automatic prompts. After permission changes, re-evaluate actual device availability and transmission state.

Maintain an account/channel generation and exactly owned callback subscriptions. A new participant event from a previous generation must not create a row in a replacement channel. Participant identity is not the player's display name; use stable IDs internally and sanitize evidence. On logout, cancel local work and await leave/logout where supported; if an SDK call completes late, perform the corresponding release rather than merely ignoring it.

## Positional behavior

For a positional channel, use the package's `JoinPositionalChannelAsync` and selected `Channel3DProperties`. Call `Set3DPosition` with the locally controlled actor and active channel only after audio is connected. The Unity SDK handles coordinate conversion; scale distance settings and actor coordinates consistently. Pick a measured update rate, pause when inactive and handle actor replacement/teleport. [Positional configuration](https://docs.unity.com/en-us/vivox-unity/developer-guide/channels/positional-channel-configuration), [channel distances](https://docs.unity.com/en-us/vivox-unity/developer-guide/channels/positional-channel-properties).

Do not confuse microphone mute with receive volume or local participant mute. A local mute affects what this player hears; a server-authorized moderation action has different permission and scope. Preserve per-user settings across device changes and ensure a recycled UI row cannot apply mute to a different participant.

## Native acceptance

Use two authorized development clients and consenting users. Confirm the expected participant identities and channel membership, then verify transmit/receive, push-to-talk, local mute, participant mute and spatial near/far behavior. Deny microphone permission before join; receive-only/disabled policy remains accurate and no transmission begins. Unplug/reselect capture and output devices, suspend/reconnect, destroy the owning scene, and check that handlers and channels are released.

Record SDK/OS/device identities and event/state timings without recording conversations or exposing tokens. A successful API callback does not prove the intended sound was heard. Automated simulations test ownership and cleanup contracts only.
