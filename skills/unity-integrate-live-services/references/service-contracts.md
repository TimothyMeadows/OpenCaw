# UGS ownership and recovery

## Version and environment

Read `Packages/manifest.json` and `packages-lock.json`; distinguish `com.unity.services.core`, `com.unity.services.authentication` and each selected feature package. Resolve the configured Unity project and named service environment. A local game engine selection does not establish a service account or authorize production access. Use project-selected initialization options with `UnityServices.InitializeAsync`; authenticate only through the installed Authentication API and the intended provider. Do not substitute anonymous login for a required platform identity.

Serialize initialization and provider linking. Handle signed-out/expired state and failed refresh without recursive login loops. A failed link must preserve recoverable existing progress. Maintain a generation for identity/environment transitions; awaiting a Task is insufficient ownership proof when the scene or player changes during it.

## Data and authority

Choose Cloud Save player access classes against actual permission requirements. Read and retain write locks for optimistic concurrency; on conflict, reload and apply the declared merge policy. Omitting a lock for creation differs from null/overwrite semantics. Do not remove a lock just to make an operation pass. A multi-key save is not automatically an application-wide transaction. [Cloud Save write locks](https://docs.unity.com/en-us/cloud-save/concepts/write-locks).

Cloud Code scripts/modules must derive acting identity from trusted invocation context, validate bounds and content IDs, and enforce duplicate-operation behavior. Keep server credentials on the server. Access policies must cover direct client bypass paths, including writes to protected progress and leaderboard scores. Record the policy's development-environment behavior before requesting deployment. [Server access control](https://docs.unity.com/en-us/cloud-code/server-access-control).

Leaderboard score type, aggregation, reset schedule and season identity are explicit product choices. Do not accept a client-reported arbitrary score as an authoritative result. Remote Config fetches need a known default, schema/range checks and an activation boundary; asynchronous completion must not mutate a destroyed HUD or a newer login session.

## Recovery matrix

| Trigger | Required observable behavior |
|---|---|
| A request succeeds after sign-out or account switch | Its old generation cannot update the new player's state |
| A mutation times out after the server committed it | Reconciliation/deduplication avoids a second reward |
| Cloud Save version conflicts | Report/reload/merge by policy; preserve the other writer's update |
| Token expires or service is unavailable | Bounded retry or explicit sign-in/offline state; no infinite spinner |
| Remote configuration is missing/malformed | Use declared local defaults and report the rejected revision |
| Development access policy denies a direct protected write | Client cannot bypass the server-owned path |

Unit protocol tests can check these decisions with injected outcomes. Actual service acceptance needs the matching SDK and an authorized development project; preserve request/correlation IDs and sanitized before/after state, never secrets. [Cloud Code and Cloud Save](https://docs.unity.com/en-us/cloud-save/tutorials/cloud-code).
