---
name: unreal-build-async-systems
description: Implement Unreal background computation and asynchronous callbacks with explicit thread ownership, cancellation and stale-result rejection.
engines: [UNREAL]
---

# Unreal Build Async Systems

## When to use

Implement background computation, task scheduling or delayed callback application in Unreal. Asset identity/loading belongs to asset integration; ability and AI tasks retain their feature-specific rules.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-async-systems` before edits or tool launches. Require effective engine `UNREAL` and `compatible: true`; revalidate any task override and permitted output scope. A skill never selects its engine.

Read the actual engine version, task APIs, owner lifetime, throughput/latency budget and shutdown behavior. CPU jobs, asset loads, gameplay tasks and network requests do not share one cancellation API. Record observed context under the resolved `.opencaw/.cache/tasks/<task>/`; `ENGINE.md` remains the selector.

## Workflow

1. Define a bounded work item: immutable input, owner/request generation, cancellation state, deadline and output-size limit. Snapshot actor/component data on its owning thread before scheduling.
2. Choose UE::Tasks, Async, an engine subsystem or an existing project queue against the installed release. Bound concurrent work; avoid blocking the game thread on a continuation that needs that thread.
3. Compute on captured values and synchronized non-UObject shared state. Strong/weak object pointers and `FGCScopeGuard` address lifetime concerns, not synchronization of game-thread-owned fields. Use only APIs documented for the worker context.
4. Give cancellation an owner and synchronization protocol. Observe it at bounded checkpoints; retiring a request does not necessarily preempt the underlying operation or free its input immediately.
5. Marshal application to the owning thread. Revalidate weak owner, world, cancellation, request generation and current authority before mutation. A valid owner with a newer request still rejects an old completion.
6. Pair delegates/timers with cleanup and define EndPlay, travel, unload and shutdown order. Non-UObject job data may safely outlive the actor; a captured raw `this` may not.
7. Measure queue delay, work time, cancellation latency and discarded results. Keep permission to compute separate from permission to mutate world state or write artifacts.

Read [task ownership and cancellation](references/task-ownership-cancellation.md) when implementing handoffs or teardown.

## Verification

Exercise valid completion, superseding requests, queued/running cancellation, owner destruction, travel and shutdown under load. Check both accepted and discarded results, bounded queues and absence of dangling callbacks/deadlock. A stress pass does not by itself prove thread safety.

## Output

Thread/ownership diagram, bounded task implementation, cancellation/result-application protocol and scoped evidence. Record environment, expected/observed outcomes and blocked/not-run checks separately. Compilation and structural checks are not runtime evidence.

## Boundaries

Do not install plugins, invent preemptive cancellation or change the project engine. Match host headers and target platforms. Preserve budgets, provenance and existing approval/publication gates.
