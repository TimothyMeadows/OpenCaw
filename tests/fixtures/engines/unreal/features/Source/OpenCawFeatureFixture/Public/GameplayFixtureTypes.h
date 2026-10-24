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
struct FOpenCawFixtureJobControl
{
    FOpenCawFixtureJobControl();
    ~FOpenCawFixtureJobControl();
    std::atomic<bool> Canceled{false};
    FEvent* Gate = nullptr;
};

UCLASS()
class OPENCAWFEATUREFIXTURE_API AOpenCawFixtureAsyncRecipient : public AActor
{
    GENERATED_BODY()
public:
    int32 Value = 0;
    uint32 RequestGeneration = 1;
    TSharedPtr<FOpenCawFixtureJobControl, ESPMode::ThreadSafe> Job;
    virtual void EndPlay(const EEndPlayReason::Type Reason) override;
};

UCLASS()
class OPENCAWFEATUREFIXTURE_API UOpenCawFixtureAttributes : public UAttributeSet
{
    GENERATED_BODY()
public:
    UPROPERTY()
    FGameplayAttributeData Health;
    static FGameplayAttribute HealthAttribute();
};

UCLASS()
class OPENCAWFEATUREFIXTURE_API AOpenCawFixtureAbilityOwner : public AActor, public IAbilitySystemInterface
{
    GENERATED_BODY()
public:
    AOpenCawFixtureAbilityOwner();
    virtual UAbilitySystemComponent* GetAbilitySystemComponent() const override;
    UPROPERTY()
    TObjectPtr<UAbilitySystemComponent> Abilities;
    UPROPERTY()
    TObjectPtr<UOpenCawFixtureAttributes> Attributes;
};

UCLASS()
class OPENCAWFEATUREFIXTURE_API UOpenCawFixtureOwnedAbility : public UGameplayAbility
{
    GENERATED_BODY()
public:
    UOpenCawFixtureOwnedAbility();
    virtual void ActivateAbility(const FGameplayAbilitySpecHandle Handle,
        const FGameplayAbilityActorInfo* ActorInfo,
        const FGameplayAbilityActivationInfo ActivationInfo,
        const FGameplayEventData* TriggerEventData) override;
};

UCLASS()
class OPENCAWFEATUREFIXTURE_API UOpenCawFixtureOtherAbility : public UGameplayAbility
{
    GENERATED_BODY()
};

UCLASS()
class OPENCAWFEATUREFIXTURE_API UOpenCawFixtureDamage : public UGameplayEffect
{
    GENERATED_BODY()
public:
    UOpenCawFixtureDamage();
};

// Author the bound BehaviorTree with one native instance of this long-running task.
UCLASS()
class OPENCAWFEATUREFIXTURE_API UOpenCawFixtureAbortTask : public UBTTaskNode
{
    GENERATED_BODY()
public:
    UOpenCawFixtureAbortTask();
    virtual EBTNodeResult::Type ExecuteTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory) override;
    virtual EBTNodeResult::Type AbortTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory) override;
    static int32 Started;
    static int32 Aborted;
    static int32 LateCompletions;
private:
    FTimerHandle CompletionTimer;
};

// An actual GameFeatureData action owns an engine OnEndFrame delegate.
UCLASS(meta=(DisplayName="OpenCaw Feature Frame Probe"))
class OPENCAWFEATUREFIXTURE_API UOpenCawFixtureFeatureAction : public UGameFeatureAction
{
    GENERATED_BODY()
public:
    virtual void OnGameFeatureActivating(FGameFeatureActivatingContext& Context) override;
    virtual void OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context) override;
    virtual void OnGameFeatureUnloading() override;
    static TWeakObjectPtr<UOpenCawFixtureFeatureAction> LastActivated;
    int32 FrameCallbacks = 0;
private:
    void ObserveFrame();
    void RemoveOwnedDelegate();
    FDelegateHandle FrameHandle;
};

USTRUCT()
struct FOpenCawFixtureMassValue : public FMassFragment
{
    GENERATED_BODY()
    UPROPERTY()
    int32 Value = 0;
};
