# Input and locomotion feel

Use this optional reference when a requested controller needs late-jump grace, action buffering, or deliberate starting/stopping behavior. Select only the mechanics that serve the game's rules. Windows and movement values are tuning decisions; this reference supplies no universal durations, tick rate, or physics settings.

Resolve `ENGINE.md` and compatible control, movement/physics, and animation skills with `resolve-skill.sh` before implementation. This agnostic reference defines ownership and acceptance requirements, not engine APIs. Retain the host's existing collision-aware movement and simulation owners; Three.js rendering alone supplies neither.

## Declare the action contract

Before tuning, record the following for each eligible action. Jump, dodge, attack, and menu confirmation can require different policies; do not put all input into one interchangeable queue.

| Decision | Required declaration |
| --- | --- |
| Intent | Logical action, local player, input context, edge or held/repeat semantics, and supported devices. |
| Identity | Input sequence plus player/session generation; actor identity plus spawn generation. |
| Eligibility | Allowed states, grounded/air entitlement, resources, cooldowns, blocking conditions, and authority. |
| Timing | Capture-to-simulation timestamp mapping, grace/buffer clock, duration, and exact inclusion/expiry boundaries. |
| Arbitration | Capacity, replacement/overflow, priority between eligible actions, and rejection/retention behavior. |
| Acceptance | Atomic transition, resource reservation/spend, consumed intent, and retired entitlement. |
| Reset | Pause/focus/modal policy, cancellation, device/player transfer, teleport, death, and new spawn. |

An animation transition, sound, or visual effect reports an accepted action; it does not establish eligibility. See [motion integration](motion-package-integration.md) for authored motion versus authoritative movement and [feedback clocks](gameplay-feedback-and-haptics.md#clocks-hit-stop-and-interruption) for presentation interruption.

## Clocks and update order

Keep input capture, simulation, and presentation distinct. Device callbacks collect input; one simulation owner evaluates it; presentation follows the accepted state. Several simulation steps in one rendered frame must not consume an edge several times.

- Choose a monotonic timestamp or tick domain for each window. Translate capture time into that domain once; do not subtract unrelated device, wall, simulation, or presentation clocks. Define treatment of late events, clock resets, and queued input after a stall.
- Declare whether windows advance during pause, slow motion, hit-stop, hidden-tab suspension, or a modal. A simulation-time window may freeze; an unscaled window may expire. Choose deliberately and prevent an old queue from bursting on resume.
- Define the simulation stage that supplies the current support/contact snapshot, then arbitrate actions against that snapshot and current actor state. Give snapshots a tick/revision; repeatedly reading an old `grounded` flag cannot refresh grace.
- Specify boundary comparisons. For example, a chosen half-open window includes its start and excludes its end; another convention needs equally explicit cases. A zero window disables the extension rather than retaining an unbounded request; normal immediate eligible input still works when buffering or grace is disabled.
- Preserve the selected fixed-step/catch-up policy. Declare which intents survive dropped simulation time and how their age is calculated; do not rewind expiry to make a delayed input eligible. Fixed stepping alone does not establish deterministic physics or networking.

## Late-jump grace

Coyote time permits a selected ground jump shortly after qualifying support ends. It is a bounded extension of a jump entitlement, not a new air jump.

1. Derive support from the movement/collision owner's confirmed contact and walkability rules. Record the support episode and its last valid simulation time; define slopes, moving platforms, one-way surfaces, and loss of the supporting object.
2. Open grace only for a qualifying support departure. Deliberate takeoff, teleport, respawn, forced movement, or a movement-mode change must follow explicit rules rather than inheriting the same permission accidentally.
3. Evaluate current support or an unexpired grace entitlement alongside normal state, cost, cooldown, and jump rules. If air jumps also exist, arbitrate their separate entitlement explicitly; one accepted intent cannot spend both.
4. Accept the jump and consume its intent/ground-grace entitlement in the same authoritative transition. Retire that support episode even if the collision solver still reports a residual contact during takeoff.
5. Re-arm only from genuine qualifying support reentry under the movement contract. A stale snapshot, repeated contact callback, cosmetic landing animation, or unchanged platform reference cannot restore the spent jump.

Specify platform-velocity inheritance and slope-edge behavior with the selected movement owner. Tune grace against the intended challenge and accessibility needs; it need not be enabled in every jumping game.

## Action buffering and single consumption

A buffer retains a bounded intent until an allowed action becomes eligible. It does not promise eventual execution and cannot bypass current state, costs, cooldowns, or authority checks.

1. Assign each press edge a stable sequence and ownership generation. Holding a button is not a stream of new edges; OS key repeat is not an implicit gameplay repeat policy. If repeat or hold-to-act is selected, give its generated requests explicit identities and cadence.
2. Store only allowed actions, with capture/expiry, player/context, target actor generation where applicable, and any required action parameters. Set finite capacity and overflow/replacement rules; distinguish latest-intent replacement from a combo sequence.
3. At the declared simulation stage, discard expired or invalid-owner intents, then evaluate the remaining candidates using current eligibility. Define ties and whether a denied request stays pending until expiry or is rejected immediately. Rejection spends no action cost and cannot refresh expiry.
4. Reserve acceptance and mark the intent consumed atomically before callbacks or presentation. Multiple simulation steps, simultaneous grounded/grace checks, synchronous listeners, and replayed delivery cannot accept the same intent twice.
5. If an accepted action later cancels, keep its intent consumed unless the rules explicitly issue a new request. A buffered jump accepted on landing cannot linger to trigger another jump after takeoff.
6. Clear or invalidate requests when their context ends. A menu press cannot become a world attack, and an old player's input cannot control a newly assigned actor. Late callbacks must check both input-owner and actor-spawn generations.

Where networking or replay is selected, retain the intent identities and relevant timing/eligibility state in the existing authoritative reconciliation contract. Re-simulation may rebuild state; duplicate effects and resource spending still need explicit prevention. Local input fixtures alone do not prove network correction.

## Acceleration, braking, and friction

Tune the movement controller through its supported intent/velocity interface. Do not add a second transform writer or use presentation easing to move an authoritative collider.

- Declare world units, time units, maximum speed, acceleration, release braking/deceleration, and reverse-input response. Separate ground, air, slope, and selected movement modes. State diagonal-input normalization and camera-relative direction rules where relevant.
- Distinguish acceleration toward a desired velocity from duration-based easing or continuous damping. If a parameter represents a response rate or drag coefficient, document that meaning rather than labeling it as acceleration.
- Define what happens at zero input, opposite input, low speed, and the maximum-speed limit. Prevent unintended sign changes or oscillation when a large step crosses the stopping point; preserve deliberate sliding or overshoot when designed.
- Surface friction belongs to the selected physics/contact model. It can affect sliding and moving contacts differently from controller braking; avoid globally changing material friction to repair one controller's stopping feel.
- Resolve platform motion, collisions, knockback, root motion, and navigation through the existing movement authority. Define how their contributions combine or interrupt; cosmetic smoothing must not conceal invalid displacement.
- Measure time/distance to speed, stopping distance, reversal, slope behavior, and platform transfer over representative render rates and stalls. Keep physics cadence and inputs recorded so comparisons remain meaningful.

## Reset and ownership boundaries

Use idempotent invalidation rather than relying only on clearing visible animation state. A reset must retire old generations so a delayed delivery cannot recreate pending work.

| Boundary | Required policy |
| --- | --- |
| Pause, modal, or focus loss | Collect releases/cancellation safely; declare queue clear/freeze/expiry and held-input rearming before resuming world actions. |
| Device disconnect, rebind, or player transfer | Clear held state and old-context requests; resolve fresh ownership without replaying the former device's queue. |
| Teleport, support destruction, or mode switch | Revalidate support and entitlements; declare whether grace/buffers survive each transition. |
| Death, restart, scene exit, or save/load | Retire pending requests, support history, and action ownership as required by the transition; restoration cannot synthesize a fresh press. |
| Despawn and pooled reuse | Increment spawn/owner generation; reset support episodes, consumed/pending intents, held state, and movement transients. Reject callbacks bound to the previous occupant. |

## Future acceptance scenarios

The following are requirements for a future selected-engine implementation, not tests executed by this documentation. Choose project-specific values and expected boundary comparisons before running cases.

| Scenario | Expected observation |
| --- | --- |
| Ledge exit, then press before/at/after grace expiry | Only the declared eligible interval accepts a ground/grace jump; rejected cases do not acquire an extra air jump. |
| Press exactly as contact is lost or landing is confirmed | Declared update order decides eligibility; ground, grace, and buffer paths cannot accept the edge twice. |
| Jump, then retain a solver contact or repeat its callback | The spent support episode does not refill grace; genuine support reentry is required to re-arm it. |
| Early landing press, then several simulation steps per frame | One pending intent accepts once when eligible; expiry and post-takeoff steps cannot create another jump. |
| Hold, OS repeat, rapid presses, full buffer, or simultaneous actions | Edge/hold/repeat semantics, replacement, priority, costs, and capacity match the declared contract. |
| Cancel an accepted action, then become eligible again | Its consumed intent stays retired; only a distinct eligible request can act again. |
| Slope limit, moving/one-way platform, or destroyed support | Walkability, departure, velocity inheritance, and entitlement follow the movement contract without stale grounded refresh. |
| Pause/hit-stop/modal/focus loss across a pending request | Chosen clocks and reset policy hold; releases are observed and resume causes no unintended burst or stuck action. |
| Disconnect/reassign, teleport, death/restart, or scene change | Old-context intents cannot leak into the new player, actor, support episode, or scene. |
| Despawn/reuse an actor, then deliver its old callback | Generation mismatch rejects it; the new occupant receives no inherited jump, buffered action, or movement transient. |
| Change render rate, stall, then resume | Accepted identities/order and measured movement stay within declared tolerances; catch-up limits and dropped-time policy remain intact. |
| Release, reverse, traverse slopes, or collide at speed | Recorded stopping/reversal and collision behavior match tuning without a second movement writer or unexplained oscillation. |

## Record evidence and tune on target

Record expected versus observed results, source/build, engine and movement backend, input device, clock/tick settings, tuning values, and relevant traces/captures. Targeted state tests can verify eligibility and consumption; actual movement requires selected-engine runtime evidence. Test multiplayer correction separately when applicable.

Review responsiveness, stopping readability, camera/animation alignment, and accessibility with intended players on representative target hardware. Automated timing checks do not establish that movement feels good. Mark unavailable runtime, network, device, or player checks `not-run` or `blocked`, and preserve their limits when reporting completion.
