# NGO replication and service handoffs

## Keep the selected stack explicit

Read the installed `com.unity.netcode.gameobjects`, transport and selected connection-service packages. NGO is not Netcode for Entities; adopting one never selects the other. A MPS session may coordinate grouping and connections, while NGO owns network objects, replicated state and gameplay authority. Existing custom transports or individual Lobby/Relay integrations remain project choices unless migration is requested. [NGO package documentation](https://docs.unity3d.com/Packages/com.unity.netcode.gameobjects@2.7/manual/index.html).

Record a readiness chain: authentication, session membership, transport connection, approval, scene/object synchronization, then player controls. Keep failure and teardown ownership at each boundary. On a late service join after cancellation, release the session/transport through the service owner; never let a stale success start a new NetworkManager. On transport failure, replicated-state recovery needs a fresh authoritative snapshot, not just a session rejoin callback.

## Ownership and scene lifetime

Use version-supported `OnNetworkSpawn`/`OnNetworkDespawn` and ownership-change callbacks for network lifetime. Do not assume `Start` precedes or follows spawn consistently for all spawn modes. Subscribe/unsubscribe within the actual owner, validate network object availability during asynchronous work and guard callbacks after despawn. Pooled objects reset local presentation/owner state before reuse. Register network prefabs and verify their build/cook inclusion for every joining client.

Define sender/ownership validation on server requests, size/rate limits and legal state transitions. RPCs express requests/events; durable state must be recoverable by late join. A client-supplied target or score is not authority. Keep serialization/content IDs versioned and verify invalid IDs cannot load arbitrary assets or execute code.

Session-owner migration does not recreate the authoritative simulation. Document whether host loss ends a match, reconnects to a retained server or uses a selected, tested state-transfer system. Do not claim rollback prediction from interpolation or client anticipation. Preserve declared NGO topology and selected transport instead of enabling distributed authority or another service implicitly.

## Multi-process evidence

Run a separate server/host and at least two actual clients. Verify approval rejection, late join, authoritative target validation, scene transition, ownership transfer, respawn and disconnect while callbacks are pending. Introduce latency/loss/jitter with the selected test facilities and measure traffic against the project budget. Test session and transport reconnect before accepting controls. A local fake transport or service simulation is useful failure evidence but cannot certify deployed gameplay, hosting or platform networking.
