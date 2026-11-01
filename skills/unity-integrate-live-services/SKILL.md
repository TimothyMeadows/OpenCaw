---
name: unity-integrate-live-services
description: Integrate explicitly selected Unity Gaming Services authentication, persistent data, server functions and configuration with bounded failure handling.
engines: [UNITY]
---

# Unity Integrate Live Services

## When to use

Implement a selected UGS feature in a Unity client or its project-owned backend. Sessions, voice, purchasing and advertising have separate owners; this skill does not select those products.

## Activation and inputs

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unity-integrate-live-services`; require effective `UNITY`, compatibility and permitted output scope. Read actual Editor/package locks, the selected services, development environment, player identity/account model, data ownership, request budgets and permitted operations. Missing service selection or environment blocks live calls. Service activation, package installation, credentials and billing changes require separate authorization.

## Workflow

1. Map initialization, authentication, sign-out and account switching. Own one initialization operation per configuration; identify anonymous-account recovery and linking before persistent progress depends on that identity.
2. Bind pending requests and listeners to a player/environment generation. A response started for another account must not update the current player's UI or cache. Define cancellation and cleanup even when an SDK operation cannot itself be cancelled.
3. Separate mutable game state, player preferences and configuration. Use Cloud Save conflict/version semantics deliberately; put protected progression, economy changes and leaderboard submissions behind validated server operations and access policies.
4. Give retriable mutations an application operation ID and durable deduplication. A timeout leaves outcome uncertain; query/reconcile rather than blindly awarding again. Bound concurrency, payload sizes and retry/backoff against actual quotas.
5. Treat Remote Config as versioned input with local defaults and validation. Select when changes become effective; do not let an unvalidated remote value change authoritative rules mid-match.
6. Keep deployable Cloud Code/configuration/policy artifacts reviewable. Ordinary local verification does not deploy, alter environments, upload logs or activate services.

Read [service contracts](references/service-contracts.md) for API selection, authority, conflicts and recovery scenarios.

## Verification and output

Provide package/environment identities, client/server ownership, state transitions, schema and operation IDs, access-policy changes and bounded failure tests. Separate deterministic simulations from real SDK and authorized service evidence. Test expired identity, account switching, offline startup, rate limits, duplicate requests and conflicts; missing accounts or authorization is blocked/not-run. Keep tokens, receipts, personal player data and service credentials out of reports. Store project observations below resolved `.hephaera/.cache`.
