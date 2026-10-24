# GAS ownership, transactions and target trust

Document OwnerActor, AvatarActor and the object retaining the ASC. A persistent PlayerState ASC can serve successive pawns; possession refreshes actor info without duplicating startup grants. Server and owning-client initialization follow the project's lifecycle rather than one universal BeginPlay call.

Track `FGameplayAbilitySpecHandle` and owned active-effect handles per source. A class lookup alone may be insufficient if the same class legitimately has several source instances; use loadout/source identity. Remove only owned grants instead of clearing the shared ASC. Decide what happens to executing abilities before removal.

## Activation and targeting

| Concern | Boundary |
| --- | --- |
| Cost/cooldown | Validate and commit once through the supported prediction/authority path. |
| Client target data | Untrusted; validate actor, action and gameplay constraints on authority. |
| Damage | Apply a per-activation spec to the intended target ASC. |
| Cancellation | Release tasks/tags/delegates and reject late application. |
| Avatar change | Retire old callbacks without deleting unrelated persistent grants. |

An ability spec is a grant; an effect spec is an application payload. Neither is the class default object defining authored defaults. AttributeSets define base/current values, replication and clamping. Execution calculations consume validated bounded inputs. Cues and animation events must not decide authoritative hit outcomes.

A standalone fixture can establish that the target's attribute changed and the caster's did not. It cannot establish that a hostile network client cannot forge the target; that requires separate network validation evidence.

## Prediction and cleanup

Follow prediction-key/window ownership for the chosen execution policy. Do not charge predicted and authoritative costs as unrelated transactions. Identify presentation events so confirmation does not duplicate impact or temporary actors. Cancellation retires delayed target data even if its operation could not be preempted.

Test persistent ASC respawn, repeated initialization, source unload, concurrent effects, target rejection, insufficient resources, interruption and death. Distinguish native lifecycle evidence, multi-process prediction results and player-facing review.

## Official references

- [Gameplay Ability System](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-ability-system-for-unreal-engine)
- [Using abilities](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-gameplay-abilities-in-unreal-engine)
- [Gameplay effects](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-effects-for-the-gameplay-ability-system-in-unreal-engine)
- [AbilitySystemComponent API](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/GameplayAbilities/UAbilitySystemComponent)

Use host-version signatures and explicitly selected plugin/replication policy.
