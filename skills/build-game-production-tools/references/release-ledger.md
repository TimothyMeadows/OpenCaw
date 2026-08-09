# Production Release Ledger

Use this reference when a game tool owns changelog data, release history, or an in-product version browser. The ledger describes what was approved and observed; it does not publish or deploy artifacts.

## Authority model

Keep one authoritative ledger for each release channel. Derived pages, menus, feeds, and reports must be reproducible from it and must not become competing sources of truth.

Separate these identities:

- a monotonic, gap-free sequence number for ordering within the channel;
- a user-facing version or release label;
- the immutable source revision and artifact digest;
- the deployment target and the version observed there.

Each entry records its predecessor, release label, source revision, artifact digest, content summary, compatibility notes, approval evidence, target, release state, and observation evidence. Use explicit `unknown` values when external state cannot be inspected.

## Write contract

1. Read the current ledger tail and build the candidate against that exact revision.
2. Reject duplicate sequence numbers, release labels, source revisions, or artifact digests unless the schema explicitly permits an alias.
3. Require the new sequence to be exactly one greater than the current channel tail and its predecessor to name that tail.
4. Validate required evidence and compatibility notes before reviewed integration.
5. Append the accepted entry atomically. If the tail changed, rebuild against the new tail instead of forcing the write.
6. Represent corrections, withdrawals, and rollbacks as later linked entries. Never erase the event that occurred.

A release candidate and an observed deployment are different states. Do not claim deployment success from a built artifact, an accepted ledger write, or a successful publication command.

## Reader behavior

For an in-product history or changelog view:

- preserve semantic reading order and stable entry anchors;
- support keyboard, pointer, controller, and back-navigation paths appropriate to the host;
- return focus to the control that opened the view;
- preserve the selected entry when the view closes and reopens during the same session;
- make loading, empty, partial, stale, and unavailable states explicit;
- keep version identity and compatibility information available without relying on color or motion.

## Live-version verification

Verify a released entry by reading the target's exposed build identity and comparing its source revision or artifact digest with the ledger. Record the target, observation time, observed identity, expected identity, method, and result.

Treat these outcomes distinctly:

- `verified`: the observed immutable identity matches the ledger entry;
- `contradicted`: an immutable identity is available and differs;
- `unknown`: the target or a trustworthy identity cannot be inspected;
- `stale`: the evidence predates a later release or target change.

Never turn `unknown` into success because a target is reachable. When a rollout is partial, record every inspected target or cohort rather than generalizing from one observation.

## Acceptance checks

- Concurrent writers cannot create duplicate or skipped sequence numbers.
- A rollback preserves both the failed release and the restoring release.
- Derived views reproduce the authoritative order and stable anchors.
- Closing and reopening a history view restores selection and focus correctly.
- Missing or stale deployment evidence is reported as unknown or stale.
- The version served by each inspected target matches the recorded immutable identity.
- A ledger operation must not publish, deploy, mutate an account, or rewrite release history.
