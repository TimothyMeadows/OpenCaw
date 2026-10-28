# Animation integration

Read this for animation architecture or a change affecting skeletons, action timing or root motion. Resolve signatures and plugin maturity against the installed engine version; these are integration decisions, not a globally selected animation stack.

## Data and evaluation

Record the SkeletalMesh, Skeleton, AnimInstance class, linked-layer interfaces, retargeter and source clip identities. A shared humanoid label does not prove compatible bone axes, proportions, root extraction or socket offsets. Validate authored motion on the actual mesh with equipment and collision.

Keep actor/component reads on the game thread. Gather velocity, movement mode and action state into the animation update's supported snapshot or property-access path. `NativeThreadSafeUpdateAnimation`, parallel evaluation and AnimGraph worker work do not authorize arbitrary Actor, World or mutable UObject access. A weak pointer or GC guard establishes neither a coherent snapshot nor synchronization. Check the selected version's supported property access and proxy mechanism before moving calculations off-thread.

Use state machines for persistent locomotion state, Blend Spaces for sampled motion, and explicit layer interfaces for equipment or body-region substitution. Decide which owner relinks layers after mesh or equipment changes; detach obsolete instances and refresh required references. Avoid one graph writing a value another asynchronous path assumes immutable.

## Actions and locomotion

With `UAnimInstance::Montage_Play`, record whether startup succeeded and which action/montage instance owns the result. Pair end/blending-out delegates with that identity. Replacing a montage can invoke the old callback during new playback; completion must compare the current action before releasing locks, equipment state or presentation handles. Cancellation, death, teardown and interrupted blends each require cleanup.

Notifies represent animation sampling. Skipped frames, LOD policy, interrupted states, prediction and dedicated-server evaluation can change when or whether they occur. Notify-state Begin/End does not replace authoritative lifetime management. Use server-validated attack windows and idempotent presentation event IDs; end an owned trail or loop on cancellation even if a notify end is absent.

Coordinate root-motion mode with CharacterMovement, collision and network prediction. Do not apply extracted displacement twice. Test turns, slopes and correction while a root-motion montage is active. Motion Warping adjusts selected authored motion; it does not establish authoritative target validity. Retargeting must preserve the intended root and contact points before gameplay compensations are considered.

## Optional animation systems

Pose Search and Motion Matching need compatible databases, preprocessing and a declared selection/update budget. Control Rig needs a defined evaluation order relative to animation, IK and attachments. Choosers and Linked Anim Layers need valid alternatives for the selected actor state. Stop when required assets or plugins are absent; report the missing choice instead of substituting a different locomotion solution.

## Acceptance

Use native captures of starts/stops, turns, feet, hands and sockets at gameplay camera distance. Exercise montage replacement, interrupted notify states, mesh replacement, possession, visibility changes, low frame rates and travel. Record update/evaluation CPU, bone count and actor/LOD matrix on representative hardware. A Blueprint compile or automation assertion cannot prove deformation, contact, readability or multiplayer correction quality.

Official references, with version matching:

- [Animation optimization and thread-safe updates](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-optimization-in-unreal-engine)
- [Animation Montages](https://dev.epicgames.com/documentation/en-us/unreal-engine/animation-montage-in-unreal-engine)
- [Motion Matching](https://dev.epicgames.com/documentation/en-us/unreal-engine/motion-matching-in-unreal-engine)
