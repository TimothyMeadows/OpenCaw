---
name: unreal-build-gameplay-abilities
description: Build Unreal GAS abilities, effects and prediction with owned grants, avatar-safe initialization and authoritative target validation.
engines: [UNREAL]
---

# Unreal Build Gameplay Abilities

## When to use

Implement or repair GAS abilities, attributes, effects, cues, costs and predicted activation. Shared combat design stays agnostic; use this feature for the concrete Unreal implementation.

## Activation and prerequisites

Run `commands/resolve-engine.sh` and `commands/resolve-skill.sh unreal-build-gameplay-abilities` before edits or tool launches. Require effective engine `UNREAL` and `compatible: true`; revalidate task overrides and permitted output scope. Skill selection never selects the engine.

Read host version, explicit GameplayAbilities selection, ASC placement, owner/avatar lifetime, replication policy and input routing. Record context/evidence under resolved `.opencaw/.cache/tasks/<task>/`; `ENGINE.md` remains authoritative.

## Workflow

1. Define ASC owner, avatar and attributes on server and owning client. Refresh actor info when the avatar changes; distinguish a persistent PlayerState ASC from a pawn-owned ASC.
2. Grant on authority and retain handles keyed by grant source. Initialization is idempotent across possession, respawn and feature activation. Remove only owned abilities, effects and bindings at the end of their lifetime.
3. Specify activation requirements, costs, cooldowns, instancing and cancellation. Commit the transaction once; every terminal activation path ends the ability and releases its tasks/tags/delegates.
4. Build target data from validated intent. On authority check actor identity, eligibility/team, range/visibility and action state as applicable. Apply damage to the intended target ASC, not the caster as a convenient default.
5. Define attribute base/current values, replication and clamping. Bound execution-calculation and SetByCaller inputs. Keep per-activation effect specs separate from authored defaults; do not mutate class default objects at runtime.
6. Use supported prediction keys/windows for the selected policy. Reconcile rejection, costs/cooldowns and presentation once. GameplayCues communicate presentation; they do not establish authoritative damage.
7. Handle death, interruption, replacement, unpossession and disconnect. Coordinate grants with feature unload and reject delayed targeting results from an old avatar generation.

Read [GAS ownership and targeting](references/gas-grants-targets-prediction.md) when implementing persistence, combat or prediction.

## Verification

Test repeated possession/respawn without duplicate grants, owned removal preserving unrelated abilities, target damage with unchanged caster, invalid targets, cost/cooldown rejection, cancellation and avatar loss. Test prediction acceptance/rejection in real separate server/client processes; standalone lifecycle tests cannot certify it.

## Output

ASC/grant ownership ledger, native abilities/effects/attributes/cues, authority/target contract and scoped evidence. Record environment, expected/observed outcomes and blocked/not-run native checks separately.

## Boundaries

No implicit plugin activation or installation. Match host APIs, target modules and selected netcode. Use actual Editor/project automation for binary assets. Preserve budgets and approval/publication gates.
