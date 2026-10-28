# Presentation ownership and review

Use one full-body presentation owner per rig. The host must suspend/arbitrate the locomotion or MODEL_TO_ANIMATION mixer before action playback writes the same bones. This workflow does not supply upper-body masks, IK, body turning, aim solving or an authoritative ability controller.

Effects bind actual exported anchors. Charge cues follow those anchors. At release, capture the sampled world origin and fly a visual projectile toward the immutable target point copied at action start. Pause uses the same presentation clock. Cancellation, supersession, reset and disposal invalidate old action generations and clean up owned visuals, including when invoked synchronously from event callbacks. Target movement/mutation does not create homing or confirm a hit.

Inspect whole sequences: pose continuity, blend extremes, contact/foot sliding, repeated steps, equipment, release anchor alignment and end pose. Blender cue proxies are technical review aids; verify actual engine effects separately. Test variable frame deltas across boundaries, pause/resume, missing/invalid targets, interruption, repeated actors and lifecycle cleanup. Browser/software rendering does not certify physical GPU timing or another engine's native assets.

Keep authoritative movement, collisions, contacts, damage, resource costs, cooldowns and projectile outcomes in gameplay. Presentation events may inform a host integration, but they are not exactly-once authoritative commands. Source/action selection, independent review and human runtime acceptance remain distinct. Evidence binds current model/package/engine hashes and actual runtime-test, runtime-capture and performance-profile artifacts. No automated report manufactures acceptance or permission to promote.
