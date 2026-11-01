#pragma once

#include "CoreMinimal.h"
#include "AbilitySystemInterface.h"
#include "Abilities/GameplayAbility.h"
#include "AttributeSet.h"
#include "BehaviorTree/BTTaskNode.h"
#include "GameFeatureAction.h"
#include "GameFramework/Actor.h"
#include "GameplayEffect.h"
#include "MassEntityTypes.h"
#include <atomic>
#include "GameplayFixtureTypes.generated.h"

class UAbilitySystemComponent;
class FEvent;

// Worker-owned value state; workers never dereference the recipient actor.
struct FHephaeraFixtureJobControl
{
    FHephaeraFixtureJobControl();
    ~FHephaeraFixtureJobControl();
    std::atomic<bool> Canceled{false};
    FEvent* Gate = nullptr;
};

UCLASS()
class HEPHAERAFEATUREFIXTURE_API AHephaeraFixtureAsyncRecipient : public AActor
{
    GENERATED_BODY()
public:
    int32 Value = 0;
    uint32 RequestGeneration = 1;
    TSharedPtr<FHephaeraFixtureJobControl, ESPMode::ThreadSafe> Job;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
};

UCLASS()
class HEPHAERAFEATUREFIXTURE_API UHephaeraFixtureAttributes : public UAttributeSet
{
    GENERATED_BODY()
public:
    UPROPERTY()
    FGameplayAttributeData Health;
    static FGameplayAttribute HealthAttribute();
};

UCLASS()
class HEPHAERAFEATUREFIXTURE_API AHephaeraFixtureAbilityOwner : public AActor, public IAbilitySystemInterface
{
    GENERATED_BODY()
public:
    AHephaeraFixtureAbilityOwner();
    virtual UAbilitySystemComponent* GetAbilitySystemComponent() const override;
    UPROPERTY()
    TObjectPtr<UAbilitySystemComponent> Abilities;
    UPROPERTY()
    TObjectPtr<UHephaeraFixtureAttributes> Attributes;
};

UCLASS()
class HEPHAERAFEATUREFIXTURE_API UHephaeraFixtureOwnedAbility : public UGameplayAbility
{
    GENERATED_BODY()
public:
    UHephaeraFixtureOwnedAbility();
    virtual void ActivateAbility(const FGameplayAbilitySpecHandle Handle,
        const FGameplayAbilityActorInfo* ActorInfo,
        const FGameplayAbilityActivationInfo ActivationInfo,
        const FGameplayEventData* TriggerEventData) override;
};

UCLASS()
class HEPHAERAFEATUREFIXTURE_API UHephaeraFixtureOtherAbility : public UGameplayAbility
{
    GENERATED_BODY()
};

UCLASS()
class HEPHAERAFEATUREFIXTURE_API UHephaeraFixtureDamage : public UGameplayEffect
{
    GENERATED_BODY()
public:
    UHephaeraFixtureDamage();
};

// Author the bound BehaviorTree with one native instance of this long-running task.
UCLASS()
class HEPHAERAFEATUREFIXTURE_API UHephaeraFixtureAbortTask : public UBTTaskNode
{
    GENERATED_BODY()
public:
    UHephaeraFixtureAbortTask();
    virtual EBTNodeResult::Type ExecuteTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory) override;
    virtual EBTNodeResult::Type AbortTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory) override;
    static int32 Started;
    static int32 Aborted;
    static int32 LateCompletions;
private:
    FTimerHandle CompletionTimer;
};

// An actual GameFeatureData action owns an engine OnEndFrame delegate.
UCLASS(meta=(DisplayName="Hephaera Feature Frame Probe"))
class HEPHAERAFEATUREFIXTURE_API UHephaeraFixtureFeatureAction : public UGameFeatureAction
{
    GENERATED_BODY()
public:
    virtual void OnGameFeatureActivating(FGameFeatureActivatingContext& Context) override;
    virtual void OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context) override;
    virtual void OnGameFeatureUnloading() override;
    static TWeakObjectPtr<UHephaeraFixtureFeatureAction> LastActivated;
    int32 FrameCallbacks = 0;
private:
    void ObserveFrame();
    void RemoveOwnedDelegate();
    FDelegateHandle FrameHandle;
};

USTRUCT()
struct FHephaeraFixtureMassValue : public FMassFragment
{
    GENERATED_BODY()
    UPROPERTY()
    int32 Value = 0;
};
