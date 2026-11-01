# Tooling and optional service acceptance

These are conditional native fixture families. The Editor case below uses real installed Unity APIs. Default batch execution disables UPM with `-noUpm`, so its package-request case is **BLOCKED/not-run** there; it requires the explicitly prepared Editor described below. The five online families and optional CLI workflow require separately configured environments and actual observations; they are also **BLOCKED/not-run** in the shared automatic run. No simulated service result can satisfy native acceptance.

## PackageInventory: conditional native Editor case

Entry point: `HephaeraUnityToolingCases.PackageInventory(context)`.

Prerequisites: matching installed Editor, resolved fixture `Packages/manifest.json` and `packages-lock.json`, and `RequiredPackages` containing an explicit comma-separated set of installed package IDs. Use an already prepared Editor/project with UPM available and explicit authorization for that environment; startup resolution is not authorized by this test. Do not remove `-noUpm` from ordinary batch verification to make the case run. No compiler symbols beyond the native Editor build are needed. Run on the isolated fixture copy through the fixture coroutine entry point; its harness owns Editor coroutine pumping, deadline and invocation-bound report checks.

The case calls `UnityEditor.PackageManager.Client.List(true, true)` in offline mode, yields until terminal completion, rejects failure/empty/duplicate inventories, checks selected registered name/version identities, and proves manifest/lock remain unchanged. It checks that this Editor source is excluded from player assembly sources. Missing lock blocks. Missing required packages, failed requests or timeouts fail; no package is added/restored to make them pass. This does not certify registry availability or package mutation behavior.

## Native online procedure requirements

For every family, record actual Editor/player/platform/package versions, selected development environment, approved scope, request/event correlation IDs, expected and observed states, cleanup results and a fresh run identity. Do not retain access tokens, raw receipts, voice recordings, personal player IDs or secret keys. Require the actual project's compiled SDK adapter and its locked package APIs; no simulated adapter, fabricated callback/report or constant-success probe qualifies. Use isolated development/sandbox data and explicitly authorized operations. A missing SDK, account, device, authorization or real adapter is BLOCKED/not-run, never pass.

### LiveServices

Packages: selected `com.unity.services.core`, `com.unity.services.authentication` and applicable `com.unity.services.cloudsave`, `com.unity.services.cloudcode`, `com.unity.remote-config`, `com.unity.services.leaderboards`. Not every service is required when the project does not select it; record each selected service's acceptance separately.

1. Initialize the selected environment with `UnityServices.InitializeAsync` and authenticate through the actual provider. Start a read, switch/sign out identity before completion, and prove the old response cannot update the replacement player/HUD. Reconnect after expiry/offline state within the declared retry budget.
2. For selected Cloud Save, read an item/write lock, make a competing authorized update and submit the stale lock. Observe a real conflict and declared reload/merge; prove neither writer is silently discarded. For selected Cloud Code mutation, repeat the same application operation ID and observe one durable grant. Verify direct protected client writes are denied by the development access policy.
3. Fetch selected Remote Config/leaderboards through the locked APIs. Reject malformed configuration at the activation boundary; verify authoritative score validation and current season identity. Capture sanitized actual before/after state and terminal request results. Cleanup only data created by this authorized run.

### MultiplayerServices

Packages: `com.unity.services.multiplayer`, selected authentication and explicitly selected transport/NGO dependencies. Requires at least two real client processes, configured development session/matchmaking/Relay resources as selected, and a declared host-loss policy.

1. Create/join a session with locked `MultiplayerService.Instance` APIs. Observe membership, transport connection and authoritative scene readiness as distinct gates. Race two joins for the final slot and verify the rejected attempt owns no connection.
2. Cancel join/matchmaking while the request is pending. If the real service completes late, observe leave/ticket cleanup and no stale screen or input activation. Check actual owned subscriptions/handles after shutdown.
3. Disconnect and use the installed reconnect API before and after retention expiry; check stable player identity plus a fresh authoritative snapshot or explicit rejection. Kill the host and verify the declared recovery/end-match policy; session-owner election alone cannot pass state-recovery acceptance. Record sanitized session/ticket/transport correlation and release run-owned resources.

### VoiceChat

Packages: `com.unity.services.vivox` and its locked dependencies. Requires configured development Vivox identity/channel access, two consenting users and target devices with microphones/output devices.

1. Initialize/login and join the selected channel with actual `VivoxService.Instance` APIs. Observe correct participant membership and exactly owned callbacks. Confirm actual audible transmit/receive, push-to-talk and local/participant mute scopes.
2. Deny/revoke microphone permission, unplug/change devices, suspend/reconnect and verify disabled/receive-only policy without hidden transmission. In a positional channel call the installed `Set3DPosition` API for the local actor and verify actual near/far/spatial output, including actor replacement.
3. Destroy the owner while joining, then leave/logout. Verify late joins are released, no obsolete participant UI is updated and no handlers/channel remain owned. Record device/state observations without recording conversations. API success alone does not prove audible output.

### Purchases

Package: `com.unity.purchasing` at the project's selected version. Requires real store sandbox/test accounts, configured test products and compiled application validation/fulfillment adapter backed by a durable ledger. No live-money purchase is authorized by this suite.

1. Connect/fetch through the installed store API. In IAP 5, handle `OnPurchasePending` and inspect the actual `Order` type in confirmation results. Observe a valid sandbox receipt, backend validation, durable grant and only then `ConfirmPurchase`. Capture sanitized entitlement state/correlation.
2. Crash after validation, after durable fulfillment and before confirmation. Restart to receive a real pending redelivery; assert one durable grant, retried acknowledgment and terminal confirmation. Inject a confirmation failure through a controlled adapter boundary and retain the original pending order. This injected failure is labeled simulation even inside a native run.
3. Exercise deferred/cancelled/failed transactions, validation rejection, restoration, subscription expiry/refund and account changes with supported store test tools. Verify no grant for deferred/unverified orders and current entitlement for restore. In IAP 5.4.4+, inspect existing local catalog before assuming Codeless authoring availability. Keep catalog deployment separate.

### Ads

Package: `com.unity.services.levelplay` and selected native adapters. Requires configured provider test ads, selected privacy policy/settings and real target devices. Never use real ad clicks or unapproved ad traffic.

1. Apply selected privacy/age settings at the installed SDK's required time, initialize actual adapters, and load/show the configured test placement. Record real load/display/reward/close events with ad-object/attempt ownership. Award on the verified reward signal exactly once; close alone awards nothing.
2. Exercise offline/no-fill/display failure and return/background behavior; check bounded retries and correct game pause/input/audio restoration. Repeat close/reward orderings and duplicate delivery through a controlled adapter seam where the provider cannot reproduce them; label injected portions simulation. Validate server-signature/replay handling separately when server-to-server rewards are selected.
3. Test unknown/denied privacy policy state and scene teardown. Verify permitted contextual/disabled mode, exact listener cleanup and safe late reward reconciliation without reopening obsolete UI. Record actual SDK/adapter/device identity and durable reward outcome; never fabricate provider transaction proof from a local attempt ID.

## Optional ToolingCli native procedure

Requires already selected Unity CLI, Unity 6.0+ and installed `com.unity.pipeline`. Record installed CLI version/help/schema, canonical project path, actual Editor identity and instance connection. With two isolated Editor projects open, explicitly target one and prove only it performs the approved test operation. Observe asynchronous acceptance, pending and terminal result; disconnect/reconnect to the same instance and reject stale results. Exercise compiling, Safe Mode and paused/non-advancing-frame conditions without killing the user's Editor. No install/login/log-upload command is part of this procedure.

## Deterministic protocol simulations

`tests/test-unity-service-contracts.cjs` exercises application-owned lifecycle decisions with synthetic outcomes: authentication generations and retries, session cancellation/reconnect cleanup, microphone permission and callback teardown, durable purchase deduplication/recovery and rewarded-ad ordering/privacy. Its output explicitly says **SIMULATION**. These tests do not load Unity, the real SDKs, store/voice/ad devices or services and cannot satisfy any native procedure above.
