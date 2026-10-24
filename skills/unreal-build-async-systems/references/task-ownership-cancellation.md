# Snapshot, compute, apply

On the owning thread, copy minimal immutable input and record the request/world generation. On a worker, compute with value data and synchronized non-UObject state. Back on the owning thread, validate the recipient and generation before application.

An Actor transform is not safe to read on a worker merely because an object pointer remains reachable. Garbage-collection guards do not serialize gameplay writes. A lock protects data only if every reader and writer uses the same protocol. Use version-supported engine thread-safe APIs where explicitly documented.

Observe `TWeakObjectPtr` on the game thread during application. Also check that EndPlay/deactivation has not retired the request. Capture stable request identity rather than looking up whichever pawn currently belongs to a controller.

## Cancellation and shutdown

| Boundary | Required behavior |
| --- | --- |
| Queued | Retire owned work without creating a replacement operation. |
| Computing | Observe cancellation at bounded checkpoints and release data after completion. |
| Completion queued | Revalidate cancellation/generation again when applying. |
| Owner removed | No mutation or resurrection of the retired actor. |
| Shutdown | Stop new work; drain/join only where it cannot deadlock. |

Task handles do not universally support preemptive cancellation. Define the operation's real stop behavior and retain resources until it has truly ended. Timeout means an observed deadline failure, not proof a thread stopped. Avoid unlimited fan-out and blocking a worker pool with external waits.

Prefer dependencies and continuations over synchronous game-thread waits. A necessary join must be bounded and must not wait for a continuation scheduled to the blocked thread. Record queue and output-size limits, rejected work and teardown latency.

## Evidence

Test a receiver alive, destroyed during work and superseded by a new generation. Include callbacks queued before cancellation. Use actual engine async primitives; toggling a local flag without scheduling does not exercise concurrency or lifetime.

## Official references

- [Tasks System](https://dev.epicgames.com/documentation/en-us/unreal-engine/tasks-systems-in-unreal-engine)
- [Thread ownership](https://dev.epicgames.com/documentation/en-us/unreal-engine/threaded-rendering-in-unreal-engine)
- [Object pointers](https://dev.epicgames.com/documentation/en-us/unreal-engine/object-pointers-in-unreal-engine)

Inspect the host headers for selected primitives, synchronization and cancellation behavior.
