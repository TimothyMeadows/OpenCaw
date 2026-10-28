# LevelPlay callback and privacy ownership

## SDK and dependency selection

Inspect `com.unity.services.levelplay`, the resolved native adapter versions, Android dependency resolution and iOS native linkage before editing. A package's presence does not prove its mediated networks are configured or compatible. Keep application keys and ad-unit IDs environment-specific; they are identifiers, not a substitute for authorization. Use the installed package's ad-unit API rather than combining legacy `IronSourceRewardedVideoEvents` with new owned ad objects. [Rewarded API migration](https://docs.unity.com/en-us/grow/levelplay/sdk/unity/migrate-rewarded-ad-unit-api).

Configure the selected privacy/age flags before initialization when required by that SDK version. Map the project's consent source and platform tracking permission to the provider's documented settings; do not treat denial as approval or infer legal compliance from one flag. An approved policy may permit a contextual mode or require ads disabled. Record the selected behavior and test it on the intended platform. [LevelPlay Unity integration](https://docs.unity.com/en-us/grow/levelplay/sdk/unity).

## Event ordering

An ad controller owns its listeners and display attempts. Use the selected ad object's load, display/failure, reward and close events, not a timer. Reward and close ordering must not decide whether an earned reward is lost: retain attempt ownership through the SDK's documented reward completion boundary. A duplicate callback must not award twice; a close callback must never award by itself.

Where the selected SDK omits a provider transaction identity in client callbacks, maintain a project-owned unique attempt identity and exactly owned callbacks, then reconcile through a trusted backend when durable/valuable rewards require it. Do not invent a provider proof from that local ID. Server-to-server integrations need signature validation, durable replay protection and a shared grant identity if both client and server signals are observed.

Separate ad loading from current game pause state. On no-fill, display failure, user return and scene teardown, restore the correct input/audio/time owner. Avoid unbounded reload loops and simultaneous requests that conflict with SDK readiness. Remove only this controller's handlers; global removal can break other placements.

## Real device acceptance

Use explicitly configured provider test ads. Verify the intended adapter initializes and a test placement loads/displays on each target platform. Exercise offline/no-fill/show failure, close without reward, both reward/close orderings where reproducible, duplicate delivery through an injected test boundary, background/foreground and scene destruction. Check denial/unknown privacy settings and disabled mode without sending unauthorized real traffic.

Retain sanitized SDK/device/adapter versions, event sequence, attempt identity and entitlement before/after. Native SDK events and an observed ad are separate from an isolated deterministic callback test. Do not click real ads or fabricate reward proof during automated verification.
