# Chaos timing, collision and ownership

Choose collision from gameplay intent. Units, object scale and imported transforms affect contact and tolerances. Record a collision matrix distinguishing blockers/overlaps/ignored objects and query versus simulation consumers.

## Timing boundaries

Forces integrate over time; impulses change momentum once. Repeated callbacks/substeps must not repeat a one-shot impulse or damage transaction. Async physics consumes synchronized snapshots and physics-owned data, not arbitrary actor fields. Garbage-collection reachability does not make those fields thread-safe.

Substeps can delay/multiply delivered events. Use stable owned identities to deduplicate authoritative interactions and presentation. Traces specify profile/channel, ignored actors and required result fields; revalidate hit ownership before delayed application.

| Situation | Decision |
| --- | --- |
| Tunneling | Check scale, thickness, velocity, supported sweep/CCD before raising global work. |
| Ragdoll entry | Transfer transform/pose, collision and replication ownership. |
| Recovery | Choose safe capsule placement; avoid body and controller competing. |
| Constraint break | Authoritative event, multiplicity and cleanup. |
| Streamed removal | Cancel dependent work and remove owned callbacks. |

Complex-as-simple collision is not a universal dynamic-body solution. Validate supported query/simulation combinations in the installed version. Collision body/triangle budgets differ from render budgets.

## Evidence

Run actual high-speed, constraint and stacked-body fixtures. Record settings, render/physics rates, CPU cost, penetration/energy tolerances and failures. Repeatable scripted stepping does not establish cross-platform deterministic lockstep. Network body replication and character prediction need their own evidence.

## Official references

- [Physics](https://dev.epicgames.com/documentation/en-us/unreal-engine/physics-in-unreal-engine)
- [Collision overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/collision-in-unreal-engine---overview)
- [Sub-stepping](https://dev.epicgames.com/documentation/en-us/unreal-engine/physics-sub-stepping-in-unreal-engine)

Match settings and API signatures to the actual host.
