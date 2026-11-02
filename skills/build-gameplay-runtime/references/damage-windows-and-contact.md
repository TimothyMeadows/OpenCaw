# Damage windows and contact

Use this optional reference when combat, hazards, or other damage interactions need explicit contact and immunity rules. Select the applicable mechanics; a noncombat game needs no invented attack system. Timing, damage categories, and repeat-hit policies are project decisions.

Resolve `ENGINE.md` and compatible physics/query, actor, animation, and networking skills before engine API work. This agnostic contract retains the existing simulation owner. Animation sampling, visibility, particles, audio, and haptics cannot grant damage or immunity; [feedback](gameplay-feedback-and-haptics.md) presents accepted state separately.

## Identity and ownership

Distinguish an attack definition from one execution of it. Replaying a clip or receiving another contact callback does not start a new attack.

| Identity | Meaning and lifetime |
| --- | --- |
| Attacker | Stable entity identity plus spawn generation; a reused actor/object is a new occupant. |
| Attack execution | One authoritative activation, unique within its attacker generation; persists across its windows, queries, and correction/replay. |
| Strike | One authored damage opportunity within that execution, such as a swing or bounded damage pulse. |
| Target | Damage recipient identity plus spawn generation, independent of its hurtbox shape count. |
| Shape/region | Query geometry and optional region metadata; maps to a recipient without creating extra hits implicitly. |
| Accepted-hit event | Stable execution/strike/recipient result identity plus revision as required by the event contract; presentation handles retain their own owner generations. |

A typical once-per-strike ledger key combines the stable attacker entity ID plus spawn generation, attack execution ID, strike ID, and damage-recipient ID plus spawn generation. A shared damage pool spanning several entities, or independently damageable parts, needs an explicit recipient identity and policy rather than accidental shape-level accounting.

## Active windows and contact data

Declare anticipation, active, recovery, and cancellation transitions in authoritative time. Specify exact endpoints; for example, a selected `[openTick, closeTick)` interval includes opening and excludes closing. No universal duration or tick rate is implied.

- Record clock, execution/strike identity, geometry, layers, target filters, damage category, and relevant source/target state. State when damage values and target eligibility are sampled.
- Queries and callbacks produce candidates. Validate the contact time against the applicable window and correction policy; a callback arriving during a newer execution cannot borrow its active state.
- Define overlap versus sweep/interval sampling and treatment of fast motion or windows shorter than a step. A skipped animation frame cannot erase or extend the authoritative window. Use the selected physics owner's supported queries and synchronization rules.
- Bound candidate counts and handle truncated/saturated query results explicitly. An incomplete buffer does not prove that no other target was contacted.
- Close owned windows on interruption and terminal transitions. Do not depend on a clip-end or notify-end event being delivered after cancellation, offscreen sampling, death, or scene disposal.

## Resolve and commit a contact

Use one authoritative resolution path for the interaction. Its order is part of the rules, especially when a hit can create immunity or kill a participant.

1. Check the execution, strike, attacker/target generations, active interval, query filters, and current allowed states. Reject stale identities and invalid geometry/ownership evidence.
2. Map all matching hurtboxes to their declared recipients. Resolve region multipliers, shield/body overlap, or competing contact points through a defined rule rather than callback order.
3. Evaluate friendly fire, damage category, immunity/exceptions, and the strike's repeat-hit policy. State whether a blocked/immune contact consumes that strike's opportunity or may be retried while it remains active.
4. Reserve the accepted ledger entry and commit damage, resource changes, and any on-hit immunity under one authoritative transaction/transition before invoking observers. Reentrant callbacks cannot apply the same hit again; failed validation cannot partially spend or apply it.
5. Emit the accepted result once through the event owner. A rejected-contact effect may have its own truthful event; it must not masquerade as damage acceptance or acquire damage authority.

## Duplicate contacts and intentional repeat hits

- For a once-per-strike rule, several attacking shapes, several target hurtboxes, persistent overlap, repeated callbacks, or several simulation steps still resolve to one accepted ledger key.
- A deliberate multi-hit attack declares distinct strikes or a bounded cadence/hit allowance per recipient. Generate opportunities from authoritative action time, not render frames, particle collisions, or callback frequency.
- Specify whether exiting/reentering a shape re-arms a hit, whether immunity consumes an opportunity, and what happens after an interrupted strike resumes. No implicit new identity may defeat the declared cap.
- Distinct attackers/executions retain distinct identities. Resolve same-tick contacts using a declared stable order or batch snapshot policy; define trades, lethal interruption, and whether newly granted immunity blocks later contacts in that same tick.
- Bound live executions, recipient ledgers, retained correction history, and query work. Retire entries only when they are outside their valid replay/contact lifetime; capacity pressure cannot silently evict live keys and permit duplicate damage.

## Immunity windows

Invincibility frames are an authoritative damage-eligibility rule. They need not correspond to rendered frames, and a hidden/flashing mesh is not the source of protection.

| Decision | Required rule |
| --- | --- |
| Scope | Recipient/spawn generation, allowed damage categories, excluded hazards, and explicit bypass sources. |
| Lifetime | Authoritative start, expiry, endpoint comparisons, clock, pause/hit-stop behavior, and source identity. |
| Overlap | Reject, replace, refresh, extend with a cap, or retain independent grants; define priority and maximum protection where relevant. |
| Revocation | What cancellation, dispel, source destruction, mode change, death, and scene exit remove or preserve. |
| Observation | How UI/feedback sees current effective protection without becoming its authority. |

Evaluate effective immunity at contact resolution even if a scheduled expiry callback has not run. A grant ending exactly at the tested endpoint follows the declared comparison; delayed animation sampling cannot extend it. Rejected duplicate events cannot refresh expiry unless the rules expressly authorize a distinct grant.

For independent grants, removing one source removes only its own handle. Recompute effective protection from remaining valid grants; an old timeout must not clear a newer replacement or another owner's grant. Refresh/extend rules retain source/generation identity and a bounded expiry.

Define the evaluation order for category exceptions, shields, immunity, damage reduction, and on-hit grants. If contact is denied during immunity, test the chosen consume-versus-retry rule when protection expires while shapes remain overlapping.

## Interruption, reuse, and correction

| Boundary | Required behavior |
| --- | --- |
| Action cancellation or attacker death | Close that execution's future opportunities and owned queries; state whether already committed hits or independent projectiles remain valid. |
| Target death and respawn | Retire old target eligibility/grants; a new spawn cannot inherit contacts or immunity unless persistence rules explicitly restore it. |
| Despawn and pooled reuse | Advance spawn generation, reset owned windows/grants/ledgers as appropriate, and reject old query/expiry/effect callbacks. |
| Scene exit or save/load | Invalidate scene-owned work; restore only versioned authoritative state under explicit load rules, without replaying old hit effects. |
| Replay or prediction correction | Rebuild authoritative state under the selected reconciliation model while preserving execution identity; suppress duplicate external effects and irreversible spending. |

When networking is selected, the authoritative server/host validates action ownership, costs, timing, allowed targets, and applicable query/rewind evidence under the game's network contract. A client animation marker or claimed hit is a request, not trusted damage. Bound historical validation and reject stale or impossible claims. No networking layer is required for a local game.

If provisional local feedback is selected, identify it separately and cancel/reconcile it when a prediction is rejected. Do not replay accepted effects each time the same authoritative event is reconstructed. Actual server/client behavior needs separate process/runtime evidence; a local fixture cannot certify correction or latency fairness.

## Future acceptance scenarios

These are requirements for future selected-engine work, not executed gameplay tests. Set concrete rules and expected results before implementation; include real queries/contact sampling as well as isolated ledger/state cases.

| Scenario | Expected observation |
| --- | --- |
| Contact before/at/after opening and closing | Only the declared interval accepts; delayed callbacks and skipped visual frames cannot change it. |
| Several attack shapes and target hurtboxes overlap across steps | Recipient mapping and ledger yield the declared single hit, without callback-order damage multipliers. |
| Authored multi-hit/cadence with persistent overlap or reentry | Only declared strike opportunities apply; no render-rate or callback-frequency bonus hits occur. |
| Immune/blocked contact, then expiry while still overlapping | The declared consume/retry policy holds; a rejected contact does not silently refresh immunity. |
| Different categories or explicit bypass damage | Scope and ordering match the immunity/shield/reduction contract with truthful feedback. |
| Refresh/extend/replace or independently stack grants | Bounds hold; an older grant's timeout/revocation cannot remove newer or unrelated protection. |
| Two attackers in the same tick, including lethal or on-hit immunity | Stable-order/batch and trade rules determine all outcomes without callback-order drift. |
| Cancel/death during a window, then deliver its old callback | Closed executions cannot reopen; committed-hit and surviving-projectile rules remain explicit. |
| Kill, respawn, or pool/reuse either participant | New generations reject old contacts, grants, and expiry callbacks without inheriting hit ledgers accidentally. |
| Observer reentry, repeated delivery, or correction/replay | Accepted state/spending and external feedback follow their separate idempotency contracts. |
| Saturated query results or ledger capacity | Declared bounded failure/diagnostics occur; partial data and evicted live keys cannot manufacture acceptance. |
| Vary render rate, pause/hit-stop, or disable feedback | Authoritative windows/categories follow their clocks; cosmetic settings never grant or remove protection. |

## Evidence and handoff

Record source/build, effective engine, physics/query backend, clock/tick settings, identities, expected/observed outcomes, and traces or runtime captures. Isolated tests establish only their state/query scope. Actual selected-engine contact, interruption, pose alignment, target performance, and player readability require representative runtime and playtest evidence.

Use the existing [feedback owner](gameplay-feedback-and-haptics.md) for bounded hit-stop, visual deformation, accessible protection cues, and haptics. Mark unavailable native/browser/device/network/player checks `not-run` or `blocked` with reasons; no document, synthetic report, or animation manifest certifies them.
