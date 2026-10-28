---
name: unity-integrate-purchases
description: Integrate explicitly selected Unity IAP stores with validated receipts, durable fulfillment, pending-order recovery and restoration.
engines: [UNITY]
---

# Unity Integrate Purchases

## When to use

Implement an explicitly selected store/IAP workflow, product catalog or entitlement recovery. Game economy design is separate from store transaction correctness.

## Activation and inputs

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unity-integrate-purchases`; require effective `UNITY`, compatibility and permitted output scope. Inspect `com.unity.purchasing`, target store/platform, existing initialization path, product IDs/types, receipt-validation owner, durable entitlement store and authorized sandbox. Do not activate stores, accept agreements, spend money or change production catalogs implicitly.

## Workflow

1. Match the installed IAP version. Subscribe to the current store lifecycle before connecting; own exactly one initialization path. Keep Codeless/catalog and code-driven initialization from racing.
2. Validate product/store identities, price display and returned order/receipt through the selected validation backend. Client callbacks and product IDs alone are insufficient evidence of paid entitlement.
3. Deduplicate the validated store transaction globally within its store/application namespace and bind its first accepted account association durably. An account switch must not create another grant key for the same purchase; transfers require explicit policy. Persist validation and fulfillment atomically or through a recoverable transaction protocol before acknowledging. Duplicate or replayed pending events must not grant twice.
4. Keep paid-pending, deferred, failed, fulfilled and confirmed states distinct. Confirmation failure does not undo a durable grant; retry acknowledgment without granting again. Preserve the original pending order for the installed API's confirmation path.
5. Restore non-consumables and current subscription entitlement deliberately. Consumable recovery depends on the durable fulfillment ledger; cached subscriptions require expiry/refund re-evaluation. Recover after crash, reinstall and account changes according to declared ownership.
6. Own handlers and asynchronous operations through disconnect/reconnect and scene teardown. Purchase UI reflects pending/unknown/owned state and remains responsive after cancellation or failure.

Read [store transactions](references/transaction-lifecycle.md) for version boundaries, reconciliation and sandbox scenarios.

## Verification and output

Deliver store/package/catalog identities, validation/fulfillment ownership, a durable transaction-state model and sandbox evidence. Test duplicate callbacks, pending redelivery, crash between fulfillment and confirmation, deferred payment, failed validation, restore and expired/refunded subscription. Simulated events do not certify a real store or SDK. Never include raw receipts, customer identities or signing credentials in reports. Keep unavailable store/account/device checks blocked/not-run and observations under resolved `.opencaw/.cache`.
