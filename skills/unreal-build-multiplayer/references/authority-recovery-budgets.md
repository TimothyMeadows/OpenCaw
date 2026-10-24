# Replication, trust and recovery

Separate durable state, requests and presentation. A client asks to act; the server evaluates its authoritative world. Validate ownership, target eligibility, range/visibility, action state, rate and cost as applicable before mutation. An RPC actor parameter remains untrusted.

## State visibility

RepNotify supports presentation but cannot be the sole authoritative rule path. Conditional replication needs deliberate privacy and observer behavior. Dormancy, relevancy re-entry and late join reconstruct current state without a historical multicast.

Network actors and accounts/sessions have distinct lifetimes. Resolve stable identities after reconnect and reject callbacks from older sessions/avatars. Travel needs a transfer owner; actor addresses are not persistence identifiers.

## Prediction

CharacterMovement owns saved moves, correction and smoothing on its intended path. GAS uses prediction keys and rejection handling. Select supported seams rather than adding a second client transform loop. Rigid-body replication and selected Mover features have different prerequisites.

Speculative presentation needs event identity and reconciliation. Do not charge a predicted and confirmed cost as independent transactions or deliver authoritative damage from an untrusted animation event. Unreliable loss can miss a cosmetic event; required state must survive.

## Budgets and evidence

Declare clients, relevant actors per client, average/peak bandwidth, request rate and server-frame cost. Measure representative content with constrained bandwidth, loss, latency and jitter. Bound arrays/payloads and expensive request queries. Reliable delivery does not remove queue pressure or abuse risk.

Acceptance includes late join, relevancy exit/re-entry, dormancy wake, invalid/replayed targets, disconnect during requests, controller transfer and travel. Record listen/dedicated topology and separate processes. Compile and single-process PIE do not establish transport behavior or permission enforcement.

## Official references

- [Networking overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/networking-overview-for-unreal-engine)
- [Actor replication](https://dev.epicgames.com/documentation/en-us/unreal-engine/replicating-actors-in-unreal-engine)
- [RPCs](https://dev.epicgames.com/documentation/en-us/unreal-engine/remote-procedure-calls-in-unreal-engine)
- [Network profiler](https://dev.epicgames.com/documentation/en-us/unreal-engine/network-profiler-in-unreal-engine)

Use the actual host version and selected replication system.
