---
name: unreal-build-mass-entities
description: Build Unreal Mass fragments, queries and processors with declared data access, deferred mutation and safe entity lifetimes.
engines: [UNREAL]
---

# Unreal Build Mass Entities

## When to use

Implement data-oriented composition, entity processing or Mass spawn/despawn. Decision graphs, character locomotion and optional crowd/representation integrations have separate ownership.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-mass-entities` before edits or tool launches. Require effective engine `UNREAL` and `compatible: true`; revalidate task override and output scope. A skill never selects its engine.

Read release, selected Mass modules/plugins, simulation phase, actor bridge, spawn policy and CPU/memory budgets. Core storage does not imply optional MassGameplay features. Record context/evidence in resolved `.opencaw/.cache/tasks/<task>/`; preserve `ENGINE.md`.

## Workflow

1. Model required behavior as fragments, tags and appropriately shared/chunk data. Avoid copying an Actor pointer graph into each entity or generating unnecessary archetype variants.
2. Declare query requirements, optional data, read/write access and dependencies. Query registration and execution-context APIs vary by release; inspect installed headers.
3. Schedule processors in deliberate phases/groups. Parallel work consumes declared safe data; UObject/Actor interaction needs the supported synchronized/game-thread bridge.
4. Defer structural mutations during iteration through the supported manager command buffers. Flush at an owned safe boundary; do not invalidate iterated archetype/chunk views with immediate mutation.
5. Track handles/generations through reserve, build, spawn and despawn. Validate before use, release unbuilt reservations correctly and reject stale generations when storage indices are reused.
6. Retire actor representation, navigation and external resources through explicit integration seams. Destroying an entity alone does not prove those resources were cleaned up.
7. Measure chunk occupancy, archetype churn, query cost and processor scaling. Mass processing alone does not provide AI behavior, rendering or network replication.

Read [entity processing and lifetimes](references/entity-processing-lifetimes.md) when adding processors or spawn/despawn paths.

## Verification

Use real manager/query/processor fixtures for data access, deferred structural changes, stale-handle rejection and teardown. Profile representative populations and any actor bridge. Separate core lifecycle coverage from optional crowd, AI, representation and network features not exercised.

## Output

Composition/query/access plan, native fragments/processors, spawn/bridge ownership and measured lifecycle/scaling evidence. Record environment, expected/observed results and blocked/not-run checks separately.

## Boundaries

No automatic plugin activation or installation. Match host type locations, APIs and target platform. Preserve authority, budgets, native assets and approval/publication gates.
