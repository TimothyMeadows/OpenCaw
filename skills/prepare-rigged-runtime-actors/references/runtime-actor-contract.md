# Runtime Actor Contract

Use this contract to move a rigged actor from authored source through integration and representative gameplay without making an engine-specific assumption.

## Asset identity and transforms

- Preserve the source asset as immutable evidence. Write optimization, compression, mesh merging, and retargeting results to a distinct runtime path.
- Give the actor, skeleton, clips, sockets, attachments, detachable parts, and colliders stable lowercase IDs.
- Record units per meter, handedness, up axis, forward axis, pivot policy, and grounding policy. Apply conversions once at the import boundary rather than throughout gameplay code.
- Verify the rest pose at identity transform. Feet or the intended contact surface must meet the documented ground plane without hidden scene offsets.
- Keep gameplay scale independent from camera tricks and presentation-only parent transforms.

## Skeleton and skinning

- Assign one stable skeleton identity to the runtime actor and every compatible clip.
- Freeze the root bone, bind pose name, ordered bone set, and maximum influences per vertex.
- Reject missing, renamed, duplicated, or non-finite bone transforms before animation playback.
- Inspect shoulders, hips, wrists, ankles, neck, and other high-deformation areas at representative extremes.
- Treat retargeting as a versioned build operation. Record the target skeleton identity and re-run contact, root-motion, and collider verification after retargeting.

## Sockets and actor variants

- Parent each socket to a declared bone and document its semantic purpose. Keep authored correction transforms in asset data rather than scattering offsets through gameplay code.
- For a character, model equipment as independently loadable assets attached to stable sockets. Define ownership, visibility, replacement, and disposal behavior.
- For a monster, model detachable parts as explicit runtime assets attached to stable sockets. Define the state transition that detaches each part and the collider or effect consequences.
- Do not represent character equipment and monster detachable parts as interchangeable data; their lifecycle and gameplay meanings differ.

## Animation contract

- Provide semantic roles for idle, locomotion, attack, hit reaction, and death. Additional clips may refine direction, speed, weapon, ability, or phase.
- Declare whether each clip loops and whether root motion is absent, extracted by the runtime, or already baked into authored motion.
- Bind contact, damage, footfall, launch, attachment, and effect events to explicit clip time rather than visual guesses.
- Test transition entry, interruption, cancellation, blending, completion, looping, and teardown. A visual completion callback must not be the sole authoritative state transition.
- Verify each clip against the actor's exact skeleton identity before loading it into an animation graph.

## Collider contract

- Keep navigation, hurt, attack, and targeting colliders distinct so tuning one concern does not silently change another.
- Parent a collider to a documented bone or socket. Avoid deriving collider transforms from material names, mesh visibility, or unversioned node searches.
- Drive attack enablement from authoritative combat timing. Disable or recycle attack colliders deterministically on cancellation, interruption, death, and teardown.
- Test collider state while animations blend and while equipment or detachable parts change.

## Loading and lifecycle

- Give one runtime owner responsibility for loading, caching, instantiation, animation graphs, attachments, and disposal.
- Deduplicate immutable geometry and textures where supported, while keeping mutable animation and gameplay state per actor instance.
- Fail visibly when the skeleton, required clips, sockets, or files do not match the manifest. Do not substitute a different actor silently.
- Release event subscriptions, animation mixers, render resources, audio emitters, timers, workers, and cached references when their owning scope ends.
- Exercise repeated spawn/despawn and scene transitions to detect memory or resource growth.

## Budgets and evidence

- Measure triangles, bones, materials, texture bytes, and runtime package bytes from the shipped candidate.
- Profile representative actor counts, animation blends, attachments, effects, and target devices. Record both steady-state and transition spikes.
- Keep a degraded-quality path when the host product requires constrained targets; preserve gameplay state and timing across quality levels.
- Require four evidence classes before production readiness:
  - automated tests for schema, state, compatibility, and teardown;
  - runtime capture showing animation, attachment, collider, and failure behavior;
  - gameplay review at representative camera scale and actor count;
  - performance profile against explicit budgets.

## Acceptance checklist

- Source and runtime artifacts are distinct, hashed, and repository-confined.
- Coordinate conversion, pivot, and grounding are explicit and stable.
- All required animation roles target the declared skeleton and have timing policy.
- Character equipment or monster detachable parts resolve only to declared sockets.
- Navigation, hurt, attack, and targeting colliders resolve to declared bones or sockets.
- Repeated load, spawn, detach/equip, death, despawn, and scene teardown leave no stale state or unbounded resources.
- Representative gameplay and performance evidence match the exact runtime file hash.
