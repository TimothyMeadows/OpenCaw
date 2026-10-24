# Integrate motion without changing movement authority

`build-model-animations` produces staged skinned, articulated or rigid motion packages. Resolve the effective engine and compatible animation/material/VFX owners before implementation. Verify actual skeleton/hierarchy identity, clip roles, units, axes, anchors and source hashes rather than trusting names.

Choose one displacement owner. In-place clips follow measured controller speed; extracted root motion supplies intent through the declared collision-aware controller. Apply translation once. Character jumping, swimming, death and vehicle warp remain explicit gameplay states; playback/end events cannot independently award damage, change death state, complete travel or grant rewards.

Use continuous speed/acceleration/turn parameters for normal movement and explicit enter/sustain/exit/cancel phases for special modes. Bind mechanical wheel/steering/suspension channels and ship anchors to their actual model nodes. Reject missing independent parts and undeclared duplicate writers rather than animating the whole model to disguise a broken hierarchy.

Separate animation, effects, audio and camera clocks from simulation where required. Handle interruption, pause/time scale, replay, pooling, actor generations, late callbacks, loading failures and scene teardown. The presentation adapter must not own global game time or silently reset another owner's controller state.

Inspect complete clips and transitions in the selected runtime. Validate contacts, foot sliding, root displacement, equipment, cancellation, resource cleanup and measured CPU/GPU/memory budgets. Engine-independent schema tests and Blender playback cannot certify native collisions, runtime visual quality or physical feel.
