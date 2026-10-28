# Camera ownership

Use this for player-view implementation or a temporary camera claim. Match APIs to the installed engine; this guidance does not select the Gameplay Cameras plugin or require a custom camera framework.

## Native responsibilities

`APlayerController` selects a view target, and its `APlayerCameraManager` evaluates the player view. A target Actor can supply the camera through its active CameraComponent or camera calculation. Assign who may call `SetViewTarget`/`SetViewTargetWithBlend`; independently calling them from pawn, UI, cinematic and spectator code creates restoration races.

`FViewTargetTransitionParams` and blend APIs control interpolation, including outgoing-view locking. Establish how a teleport, newly destroyed target or higher-priority camera interrupts that interpolation. Do not repeatedly restart a blend every tick. Automatic target management during possession may overwrite manual choices; coordinate that policy rather than turning it off for every project.

Temporary camera requests need an identity, owning local player, priority and fallback. On release, restore only if that request still owns the view. A delayed end callback from an earlier sequence must not restore a pawn over a newer spectator or cinematic view. Validate the fallback actor's world/lifetime; current possession can differ from possession at acquisition. Releasing an obsolete request is idempotent.

## Spatial response

For a SpringArm arrangement, verify `TargetArmLength`, socket/target offsets, probe channel/size and collision behavior on the actual target geometry. Camera collision and character collision have different purposes. Lag/rotation lag need declared limits and teleport reset behavior. A renderer clipping through a wall cannot be fixed by trusting the camera actor's origin alone.

Separate presentation FOV, shake and smoothing from authoritative hit traces or movement. If gameplay aim depends on a view ray, reconcile it through the project's validated control/target contract instead of treating a shaken camera transform as server truth. Coordinate camera updates after the relevant actor motion, including physics and animation-driven attachments.

## Effects and optional frameworks

`APlayerCameraManager` supports camera modifiers and shakes. Retain owned modifier/shake instances and remove only those instances. Bound amplitude, duration and concurrent layers. Local-player intensity/reduced-motion options must affect the resulting view consistently and must not alter authoritative damage or timings.

Gameplay Cameras and Cinematic Camera rigs introduce additional assets and API/version constraints. Verify the selected plugin's maturity, module/target availability and evaluator ownership before using it. CineCameraActor lens settings may suit authored shots but do not automatically replace gameplay camera logic. Keep camera-cut transitions coordinated with the sequence's restore policy.

## Acceptance

Automation can compare actual controller view targets across acquisition, replacement, cancellation and cleanup, and can assert player isolation. It does not establish split-screen player routing without a real local-player setup. Exercise collisions, teleports, high/low frame rates, death and travel in the target build. Record world scale, FOV, blend settings and accessibility configuration with native captures; a NullRHI test proves no framing or comfort result.

Official references, with version matching:

- [PlayerController API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/APlayerController)
- [PlayerCameraManager API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/APlayerCameraManager)
- [SpringArm camera collision](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-spring-arm-components-in-unreal-engine)
