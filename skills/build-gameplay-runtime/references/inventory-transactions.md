# Inventory Transactions

## Ownership model

- Give every item instance a stable identity and exactly one authoritative owner or location.
- Separate immutable item definitions from mutable instances, containers, reservations, equipment state, and presentation.
- Treat world drops, containers, characters, equipment slots, crafting inputs, and temporary transfer buffers as explicit locations.
- Keep UI selection, sorting, filters, animation, and drag previews outside authoritative inventory state.

## Atomic operations

Implement pickup, drop, move, split, merge, equip, unequip, consume, craft, trade, and reward delivery as transactions:

1. Validate source ownership, destination capacity, item rules, quantities, version, and permissions.
2. Compute the complete state change without mutating authoritative state.
3. Commit all removals, additions, reservations, and side effects as one operation.
4. Emit one durable result containing transaction ID, prior version, new version, and outcome.
5. On failure, leave every item, quantity, and owner unchanged.

Make retries idempotent. A repeated transaction ID must return the prior result or fail without applying the operation again.

## Conservation invariants

- No item instance exists in more than one authoritative location.
- No transfer silently creates, destroys, or changes quantity except an explicitly typed source, sink, split, merge, craft, or consume operation.
- A failed or cancelled operation preserves the exact prior state.
- Equipment remains part of inventory truth even when presentation attaches a rendered asset.
- Reservations expire or resolve deterministically and cannot strand inaccessible items.

## Persistence and migration

- Serialize stable IDs, definition versions, quantities, durability or charges, ownership, locations, and transaction/version metadata.
- Validate saves before replacing live state. Preserve the last known-good state when parsing, validation, or migration fails.
- Make migrations versioned, deterministic, and repeatable. Record replacements for retired definitions and an explicit policy for unsupported items.
- Do not serialize render nodes, component references, open UI state, or temporary animation state as inventory truth.

## Accessibility and presentation

- Expose every operation through keyboard and assistive-technology-friendly controls, not only drag-and-drop.
- Announce transfer results, capacity failures, quantity changes, and equipment state without relying on color, motion, or sound alone.
- Preserve focus and selection after sorting, filtering, transfers, failures, and modal closure.
- Render from committed inventory state and reconcile optimistic presentation with the authoritative result.

## Verification

- Property-test conservation across generated transaction sequences.
- Test capacity boundaries, partial quantities, duplicate retries, stale versions, interrupted persistence, migration chains, and concurrent requests.
- Simulate failure at each commit boundary and prove no-loss rollback.
- Round-trip saves and compare canonical state, not UI order.
- Play through pickup, equip, consume, craft, death, reload, and scene transition with presentation disabled to prove state ownership is independent.
