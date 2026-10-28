# Store transactions and recovery

## Match the installed version

Read the package lock before choosing the API. IAP 5 uses the event-driven `StoreController` and order types; IAP 4 interfaces and `ProcessPurchase` are a separate lifecycle. Inspect project-owned Codeless buttons/listeners and catalog loading first. Do not initialize a second store controller, attach duplicate completion listeners or assume a catalog API's sync/async behavior carries across versions. [IAP initialization](https://docs.unity.com/en-us/iap/set-up-in-app-purchasing), [upgrade guidance](https://docs.unity.com/en-us/iap/upgrade-to-iap-v5).

For the selected IAP 5 package, identify connection, products/purchases fetches, pending/deferred/failure and confirmation events. Subscribe before initiating the corresponding operation. A confirmation callback may represent failure; inspect its actual order type and reason. Preserve a pending order across a transient confirmation failure rather than passing a failed-order object back to confirmation. [Purchase lifecycle](https://docs.unity.com/en-us/iap/purchases).

Inspect local versus Remote Catalog ownership before changing authoring workflows. From IAP 5.4.4, Codeless creation menus are available only to projects with an existing local catalog; existing scenes/catalogs continue to work. Do not assume those menus exist in a new project or migrate/deploy a catalog implicitly. [Codeless availability](https://docs.unity.com/en-us/iap/codeless).

## Application-owned correctness

The store/application namespace and validated transaction ID form an idempotency identity. Persist the first accepted account association with that transaction; switching players must not create another grant key. Reject or reconcile a conflicting account through an explicit entitlement-transfer policy. Validate signed receipts on the selected trusted backend. Persist the grant and processed transaction identity together, or use a durable recovery protocol that cannot lose the grant or duplicate it after a crash. An in-memory HashSet or PlayerPrefs flag cannot certify durable paid fulfillment.

Represent deferred payment without granting. Failed validation remains unfulfilled. A paid pending order is retriable work, not a disposable UI notification. Confirm only after durable fulfillment; if acknowledgment fails, keep retry/reconciliation responsibility without awarding again. Do not log receipt payloads or tokens; retain sanitized correlation and outcome records. [Receipt validation](https://docs.unity.com/en-us/iap/receipt-validation).

Treat restore as entitlement reconciliation. Consumables require your persistent ledger once the store has consumed/acknowledged them. Non-consumables and subscriptions need current store/backend evidence, including cancellations, expiration and refunds. Never permanently cache a subscription as owned just because a previous launch succeeded. Codeless callbacks still need the same validation and durable grant boundary.

## Sandbox acceptance

Use a configured store sandbox/test account and a project-owned product. Capture sanitized state transitions for successful purchase, user cancellation, deferred payment and invalid receipt. Restart the client after validation but before durable grant, after grant but before confirmation, and during a failed confirmation. Each retry reaches one durable entitlement. Replay the same pending transaction and restore across reinstall/account changes; a second account must not receive another grant from the same store transaction. Assert the declared ownership and no duplicate consumable award.

Package compilation and synthetic callback tests cannot prove store receipts, payment UI or restoration. A live-money purchase is outside ordinary verification. Record sandbox/store/package/platform identities, selected product types and before/after entitlement evidence without personal account details.
