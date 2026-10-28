# Session lifecycle and replication handoff

## Select the installed API

The Multiplayer Services SDK represents sessions across grouping and connection services; it is not a separate gameplay simulation. Inspect `MultiplayerService.Instance` and the installed package's `CreateSessionAsync`, join/query/match and reconnect interfaces before implementing signatures. Authentication and environment initialization are prerequisites. Older projects using individual service SDKs need an explicit migration decision, not a second competing session manager. [MPS overview](https://docs.unity.com/en-us/mps-sdk).

Define separate readiness gates: identity ready; service membership established; transport connected; NGO objects and scenes synchronized; player input admitted. Route each failure to the owning layer. A lobby count, Relay allocation or successful SDK Task does not prove a functioning player connection.

## Ownership and cancellation

One active matchmaking operation owns its ticket, generation, completion and cleanup. If the user cancels while a join request is outstanding, ignore its presentation result but still release an eventual successful membership/connection. Do not run fire-and-forget cleanup silently: await completion within a budget and report the remaining resource identity if cleanup fails. Unsubscribe exactly the handlers this owner registered.

For reconnect, record the retained membership/session ID and deadline. Select package-supported reconnect APIs and validate the player is still permitted to return. Restore transport and request fresh authoritative state; discard obsolete pending gameplay commands. Treat removal, full sessions, host disappearance and timeout as explicit terminal or user-selected retry states. A new account cannot inherit another account's retained session.

Hosting and host migration require a chosen simulation recovery strategy. Transferring session ownership is different from state transfer, transport reassignment and authoritative resumption. Unity's retired Multiplay hosting product is not a default recommendation; inspect current support for the selected provider and platform. [Multiplay notice](https://status.unity.com/info_notices/362941).

## Acceptance scenarios

- Two clients race for the last slot: one joins, the rejected client owns no ghost connection or retry loop.
- Cancel just before a match/join completes: late success is cleaned up and cannot enable player input.
- Drop connectivity, then reconnect before and after retention expiry: correct retained identity and snapshot, or a clear leave/retry path.
- Lose host: apply the declared host-loss policy; do not report seamless migration from session election alone.
- Destroy the screen or switch accounts during each asynchronous stage: no callbacks update the replacement screen/account and no ticket remains unowned.

Run actual SDK acceptance only in an authorized development environment with multiple processes and sanitized session/transport correlation IDs. Simulated protocol tests cover ordering contracts and cannot certify Relay, matchmaking, hosting or NGO gameplay.
