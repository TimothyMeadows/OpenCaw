#include "GameplayFixtureTypes.h"

#include "AbilitySystemComponent.h"
#include "BehaviorTree/BehaviorTree.h"
#include "BehaviorTree/BehaviorTreeComponent.h"
#include "Engine/World.h"
#include "HAL/Event.h"
#include "HAL/PlatformProcess.h"
#include "Misc/CoreDelegates.h"
#include "TimerManager.h"
#include "UObject/UnrealType.h"

FOpenCawFixtureJobControl::FOpenCawFixtureJobControl()
    : Gate(FPlatformProcess::GetSynchEventFromPool(true)) {}

FOpenCawFixtureJobControl::~FOpenCawFixtureJobControl()
{
    FPlatformProcess::ReturnSynchEventToPool(Gate);
}

void AOpenCawFixtureAsyncRecipient::EndPlay(const EEndPlayReason::Type Reason)
{
    ++RequestGeneration;
    if (Job)
    {
        Job->Canceled.store(true);
        Job->Gate->Trigger();
    }
    Super::EndPlay(Reason);
}

FGameplayAttribute UOpenCawFixtureAttributes::HealthAttribute()
{
    return FGameplayAttribute(FindFPropertyChecked<FProperty>(StaticClass(),
        GET_MEMBER_NAME_CHECKED(UOpenCawFixtureAttributes, Health)));
}

AOpenCawFixtureAbilityOwner::AOpenCawFixtureAbilityOwner()
{
    Abilities = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("Abilities"));
    Attributes = CreateDefaultSubobject<UOpenCawFixtureAttributes>(TEXT("Attributes"));
}

UAbilitySystemComponent* AOpenCawFixtureAbilityOwner::GetAbilitySystemComponent() const
{
    return Abilities;
}

UOpenCawFixtureOwnedAbility::UOpenCawFixtureOwnedAbility()
{
    InstancingPolicy = EGameplayAbilityInstancingPolicy::InstancedPerActor;
    NetExecutionPolicy = EGameplayAbilityNetExecutionPolicy::ServerOnly;
}

void UOpenCawFixtureOwnedAbility::ActivateAbility(const FGameplayAbilitySpecHandle Handle,
    const FGameplayAbilityActorInfo* ActorInfo,
    const FGameplayAbilityActivationInfo ActivationInfo,
    const FGameplayEventData* TriggerEventData)
{
    // Deliberately stays active until the owning grant is canceled in the fixture.
    SetCanBeCanceled(true);
}

UOpenCawFixtureDamage::UOpenCawFixtureDamage()
{
    DurationPolicy = EGameplayEffectDurationType::Instant;
    FGameplayModifierInfo Modifier;
    Modifier.Attribute = UOpenCawFixtureAttributes::HealthAttribute();
    Modifier.ModifierOp = EGameplayModOp::Additive;
    Modifier.ModifierMagnitude = FScalableFloat(-17.0f);
    Modifiers.Add(Modifier);
}

int32 UOpenCawFixtureAbortTask::Started = 0;
int32 UOpenCawFixtureAbortTask::Aborted = 0;
int32 UOpenCawFixtureAbortTask::LateCompletions = 0;

UOpenCawFixtureAbortTask::UOpenCawFixtureAbortTask()
{
    bCreateNodeInstance = true;
    NodeName = TEXT("OpenCaw owned latent operation");
}

EBTNodeResult::Type UOpenCawFixtureAbortTask::ExecuteTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory)
{
    ++Started;
    const TWeakObjectPtr<UBehaviorTreeComponent> Brain(&OwnerComp);
    OwnerComp.GetWorld()->GetTimerManager().SetTimer(CompletionTimer,
        FTimerDelegate::CreateWeakLambda(this, [this, Brain]()
        {
            ++LateCompletions;
            if (Brain.IsValid()) FinishLatentTask(*Brain.Get(), EBTNodeResult::Succeeded);
        }), 0.1f, false);
    return EBTNodeResult::InProgress;
}

EBTNodeResult::Type UOpenCawFixtureAbortTask::AbortTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory)
{
    OwnerComp.GetWorld()->GetTimerManager().ClearTimer(CompletionTimer);
    ++Aborted;
    return EBTNodeResult::Aborted;
}

TWeakObjectPtr<UOpenCawFixtureFeatureAction> UOpenCawFixtureFeatureAction::LastActivated;

void UOpenCawFixtureFeatureAction::OnGameFeatureActivating(FGameFeatureActivatingContext& Context)
{
    Super::OnGameFeatureActivating(Context);
    RemoveOwnedDelegate();
    FrameHandle = FCoreDelegates::OnEndFrame.AddUObject(this, &UOpenCawFixtureFeatureAction::ObserveFrame);
    LastActivated = this;
}

void UOpenCawFixtureFeatureAction::OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context)
{
    RemoveOwnedDelegate();
    Super::OnGameFeatureDeactivating(Context);
}

void UOpenCawFixtureFeatureAction::OnGameFeatureUnloading()
{
    RemoveOwnedDelegate();
    Super::OnGameFeatureUnloading();
}

void UOpenCawFixtureFeatureAction::ObserveFrame() { ++FrameCallbacks; }

void UOpenCawFixtureFeatureAction::RemoveOwnedDelegate()
{
    FCoreDelegates::OnEndFrame.Remove(FrameHandle);
    FrameHandle.Reset();
}

#if WITH_DEV_AUTOMATION_TESTS

#include "FeatureEvidence.h"
#include "AIController.h"
#include "Async/Async.h"
#include "Components/BoxComponent.h"
#include "Engine/Engine.h"
#include "Engine/URL.h"
#include "Engine/World.h"
#include "GameFeaturesSubsystem.h"
#include "GameFeatureData.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Interfaces/IPluginManager.h"
#include "MassCommandBuffer.h"
#include "MassEntityManager.h"
#include "Misc/AutomationTest.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/Paths.h"
#include "UObject/StrongObjectPtr.h"

namespace
{
constexpr uint32 FeatureFlags = EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter;

struct FGameplayWorld
{
    UWorld* World = nullptr;
    FGameplayWorld()
    {
        UWorld::InitializationValues Values;
        Values.AllowAudioPlayback(false).CreatePhysicsScene(true).CreateNavigation(false)
            .CreateAISystem(true).ShouldSimulatePhysics(false).SetTransactional(false);
        World = UWorld::CreateWorld(EWorldType::Game, false, NAME_None, nullptr, true,
            ERHIFeatureLevel::Num, &Values);
        if (World && GEngine)
        {
            GEngine->CreateNewWorldContext(EWorldType::Game).SetCurrentWorld(World);
            World->InitializeActorsForPlay(FURL());
            World->BeginPlay();
        }
    }
    ~FGameplayWorld()
    {
        if (World)
        {
            if (GEngine) GEngine->DestroyWorldContext(World);
            World->DestroyWorld(false);
        }
    }
};

struct FWorkResult
{
    int32 Value = 0;
    bool bWorkerThread = false;
    bool bCanceled = false;
    bool bGateOpened = false;
};

TFuture<FWorkResult> LaunchWork(int32 Snapshot,
    TSharedRef<FOpenCawFixtureJobControl, ESPMode::ThreadSafe> Control)
{
    return Async(EAsyncExecution::ThreadPool, [Snapshot, Control]()
    {
        FWorkResult Result;
        Result.bWorkerThread = !IsInGameThread();
        Result.bGateOpened = Control->Gate->Wait(2000);
        Result.bCanceled = Control->Canceled.load();
        Result.Value = Snapshot * 2;
        return Result;
    });
}

bool ApplyWorkResult(TWeakObjectPtr<AOpenCawFixtureAsyncRecipient> Recipient,
    uint32 Generation, const FWorkResult& Result)
{
    check(IsInGameThread());
    if (!Recipient.IsValid() || Recipient->IsActorBeingDestroyed() || !Recipient->HasAuthority() ||
        !Recipient->Job.IsValid() || Recipient->Job->Canceled.load() ||
        Recipient->RequestGeneration != Generation || Result.bCanceled || !Result.bGateOpened)
    {
        return false;
    }
    Recipient->Value = Result.Value;
    return true;
}

class FAsyncTeardownCommand : public IAutomationLatentCommand
{
public:
    explicit FAsyncTeardownCommand(FAutomationTestBase* InTest) : Test(InTest)
    {
        Deadline = FPlatformTime::Seconds() + 5.0;
        if (!Test->TestNotNull(TEXT("Async world"), Context.World)) return;
        Recipient = Context.World->SpawnActor<AOpenCawFixtureAsyncRecipient>();
        Retired = Context.World->SpawnActor<AOpenCawFixtureAsyncRecipient>();
        if (!Test->TestTrue(TEXT("Both recipients spawned"), Recipient.IsValid() && Retired.IsValid())) return;
        if (!Recipient->HasActorBegunPlay()) Recipient->DispatchBeginPlay();
        if (!Retired->HasActorBegunPlay()) Retired->DispatchBeginPlay();
        Recipient->Value = 11;
        Recipient->Job = MakeShared<FOpenCawFixtureJobControl, ESPMode::ThreadSafe>();
        Retired->Job = MakeShared<FOpenCawFixtureJobControl, ESPMode::ThreadSafe>();
        RetiredGeneration = Retired->RequestGeneration;
        SupersededGeneration = Recipient->RequestGeneration;
        Superseded = LaunchWork(5, Recipient->Job.ToSharedRef());
        ++Recipient->RequestGeneration;
        AcceptedGeneration = Recipient->RequestGeneration;
        Valid = LaunchWork(Recipient->Value, Recipient->Job.ToSharedRef());
        RetiredControl = Retired->Job;
        Late = LaunchWork(9, RetiredControl.ToSharedRef());
        Test->TestTrue(TEXT("Retired actor destroyed"), Retired->Destroy());
        Test->TestTrue(TEXT("EndPlay canceled its owned worker state"), RetiredControl->Canceled.load());
        Recipient->Job->Gate->Trigger();
        bStarted = true;
    }

    virtual bool Update() override
    {
        if (!bStarted) return true;
        if (!Valid.IsReady() || !Late.IsReady() || !Superseded.IsReady())
        {
            if (FPlatformTime::Seconds() < Deadline) return false;
            Test->AddError(TEXT("Bounded worker completion deadline exceeded"));
            return true;
        }
        const FWorkResult Normal = Valid.Get();
        const FWorkResult Removed = Late.Get();
        const FWorkResult Old = Superseded.Get();
        Test->TestTrue(TEXT("Actual background workers ran"),
            Normal.bWorkerThread && Removed.bWorkerThread && Old.bWorkerThread);
        Test->TestTrue(TEXT("Bounded wait gates opened"), Normal.bGateOpened && Removed.bGateOpened);
        Test->TestFalse(TEXT("Live request was not canceled"), Normal.bCanceled);
        Test->TestFalse(TEXT("Superseded completion rejected by actual application path"),
            ApplyWorkResult(Recipient, SupersededGeneration, Old));
        Test->TestEqual(TEXT("Rejected stale result preserves recipient state"), Recipient->Value, 11);
        Test->TestTrue(TEXT("Current completion accepted by same application path"),
            ApplyWorkResult(Recipient, AcceptedGeneration, Normal));
        Test->TestTrue(TEXT("Live completion applied on game thread"), IsInGameThread());
        Test->TestEqual(TEXT("Snapshot result applied"), Recipient->Value, 22);
        Test->TestTrue(TEXT("Retired job observed cancellation"), Removed.bCanceled);
        Test->TestFalse(TEXT("Destroyed recipient rejected by same application path"),
            ApplyWorkResult(Retired, RetiredGeneration, Removed));
        Test->TestTrue(TEXT("Retired recipient unavailable for application"),
            !Retired.IsValid() || Retired->IsActorBeingDestroyed());
        return true;
    }
private:
    FAutomationTestBase* Test;
    FGameplayWorld Context;
    TWeakObjectPtr<AOpenCawFixtureAsyncRecipient> Recipient;
    TWeakObjectPtr<AOpenCawFixtureAsyncRecipient> Retired;
    TSharedPtr<FOpenCawFixtureJobControl, ESPMode::ThreadSafe> RetiredControl;
    TFuture<FWorkResult> Valid;
    TFuture<FWorkResult> Late;
    TFuture<FWorkResult> Superseded;
    uint32 AcceptedGeneration = 0;
    uint32 SupersededGeneration = 0;
    uint32 RetiredGeneration = 0;
    double Deadline = 0;
    bool bStarted = false;
};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawAsyncTeardown, "OpenCaw.UnrealFeatures.AsyncTeardown", FeatureFlags)
bool FOpenCawAsyncTeardown::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.AsyncTeardown"))) return false;
    ADD_LATENT_AUTOMATION_COMMAND(FAsyncTeardownCommand(this));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawGASOwnership, "OpenCaw.UnrealFeatures.GASOwnership", FeatureFlags)
bool FOpenCawGASOwnership::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.GASOwnership"))) return false;
    FGameplayWorld Context;
    if (!TestNotNull(TEXT("GAS world"), Context.World)) return false;
    auto* Owner = Context.World->SpawnActor<AOpenCawFixtureAbilityOwner>();
    auto* Target = Context.World->SpawnActor<AOpenCawFixtureAbilityOwner>();
    AActor* AvatarA = Context.World->SpawnActor<AActor>();
    AActor* AvatarB = Context.World->SpawnActor<AActor>();
    if (!TestTrue(TEXT("GAS recipients spawned"), Owner && Target && AvatarA && AvatarB)) return false;
    if (!TestTrue(TEXT("Only authority grants this fixture loadout"), Owner->HasAuthority())) return false;
    UAbilitySystemComponent* ASC = Owner->Abilities;
    ASC->AddAttributeSetSubobject(Owner->Attributes.Get());
    Target->Abilities->AddAttributeSetSubobject(Target->Attributes.Get());
    ASC->InitAbilityActorInfo(Owner, AvatarA);
    Target->Abilities->InitAbilityActorInfo(Target, Target);
    TMap<FName, FGameplayAbilitySpecHandle> Grants;
    auto GrantOwned = [&]()
    {
        const FName Source(TEXT("FixtureFeature"));
        if (const FGameplayAbilitySpecHandle* Existing = Grants.Find(Source))
        {
            if (ASC->FindAbilitySpecFromHandle(*Existing)) return *Existing;
        }
        FGameplayAbilitySpecHandle Handle = ASC->GiveAbility(
            FGameplayAbilitySpec(UOpenCawFixtureOwnedAbility::StaticClass(), 1, INDEX_NONE, Owner));
        Grants.Add(Source, Handle);
        return Handle;
    };
    const FGameplayAbilitySpecHandle Owned = GrantOwned();
    const FGameplayAbilitySpecHandle Other = ASC->GiveAbility(
        FGameplayAbilitySpec(UOpenCawFixtureOtherAbility::StaticClass(), 1));
    ASC->InitAbilityActorInfo(Owner, AvatarB);
    TestTrue(TEXT("Respawn retains the owned grant identity"), GrantOwned() == Owned);
    TestEqual(TEXT("Respawn does not duplicate startup abilities"), ASC->GetActivatableAbilities().Num(), 2);
    TestEqual(TEXT("Persistent ASC follows the new avatar"), ASC->GetAvatarActor(), AvatarB);
    const FGameplayAttribute Health = UOpenCawFixtureAttributes::HealthAttribute();
    ASC->SetNumericAttributeBase(Health, 100.0f);
    Target->Abilities->SetNumericAttributeBase(Health, 100.0f);
    FGameplayEffectSpecHandle Damage = ASC->MakeOutgoingSpec(
        UOpenCawFixtureDamage::StaticClass(), 1.0f, ASC->MakeEffectContext());
    if (!TestTrue(TEXT("Native damage spec exists"), Damage.IsValid())) return false;
    ASC->ApplyGameplayEffectSpecToTarget(*Damage.Data.Get(), Target->Abilities.Get());
    TestEqual(TEXT("Intended target receives damage"), Target->Abilities->GetNumericAttribute(Health), 83.0f);
    TestEqual(TEXT("Caster is not damaged instead"), ASC->GetNumericAttribute(Health), 100.0f);
    if (!TestTrue(TEXT("Owned ability activates on authority"), ASC->TryActivateAbility(Owned))) return false;
    FGameplayAbilitySpec* Active = ASC->FindAbilitySpecFromHandle(Owned);
    if (!TestNotNull(TEXT("Active spec retained"), Active)) return false;
    TestTrue(TEXT("Native ability is executing before cancellation"), Active->IsActive());
    ASC->CancelAbilityHandle(Owned);
    TestFalse(TEXT("Cancellation retires native activation"), Active->IsActive());
    ASC->ClearAbility(Owned);
    TestNull(TEXT("Owned grant removed"), ASC->FindAbilitySpecFromHandle(Owned));
    TestNotNull(TEXT("Unrelated grant retained"), ASC->FindAbilitySpecFromHandle(Other));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawMovement, "OpenCaw.UnrealFeatures.Movement", FeatureFlags)
bool FOpenCawMovement::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.Movement"))) return false;
    FGameplayWorld Context;
    if (!TestNotNull(TEXT("Movement world"), Context.World)) return false;
    auto* Character = Context.World->SpawnActor<ACharacter>();
    auto* Wall = Context.World->SpawnActor<AActor>();
    if (!TestTrue(TEXT("Collision actors spawned"), Character && Wall)) return false;
    if (!TestTrue(TEXT("Standalone fixture owns movement authority"), Character->HasAuthority())) return false;
    UBoxComponent* Box = NewObject<UBoxComponent>(Wall);
    Wall->AddInstanceComponent(Box);
    Wall->SetRootComponent(Box);
    Box->SetBoxExtent(FVector(20.0, 200.0, 200.0));
    Box->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
    Box->SetCollisionObjectType(ECC_WorldStatic);
    Box->SetCollisionResponseToAllChannels(ECR_Block);
    Box->RegisterComponent();
    Wall->SetActorLocation(FVector(200.0, 0.0, 0.0));
    UCharacterMovementComponent* Movement = Character->GetCharacterMovement();
    TestEqual(TEXT("Character capsule has one movement owner"), Movement->UpdatedComponent.Get(),
        Character->GetRootComponent());
    Movement->SetMovementMode(MOVE_Flying);
    FHitResult Hit;
    Movement->MoveUpdatedComponent(FVector(400.0, 0.0, 0.0), FQuat::Identity, true, &Hit);
    TestTrue(TEXT("Native swept movement hits blocking wall"), Hit.bBlockingHit);
    TestTrue(TEXT("Collision prevents tunneling past the wall"), Character->GetActorLocation().X < 200.0);
    Movement->Velocity = FVector(300.0, 0.0, 0.0);
    Movement->StopMovementImmediately();
    TestTrue(TEXT("Movement cancellation clears velocity"), Movement->Velocity.IsNearlyZero());
    Movement->DisableMovement();
    TestTrue(TEXT("Disable retires movement mode"), Movement->MovementMode == MOVE_None);
    TestTrue(TEXT("Movement owner teardown succeeds"), Character->Destroy());
    AddInfo(TEXT("Coverage: standalone CMC collision/stop only; multi-process correction remains a separate required acceptance run."));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawAICancellation, "OpenCaw.UnrealFeatures.AICancellation", FeatureFlags)
bool FOpenCawAICancellation::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.AICancellation"))) return false;
    FString TreePath;
    if (!GConfig->GetString(TEXT("OpenCaw.UnrealFeatures"), TEXT("BehaviorTree"), TreePath, GGameIni) || TreePath.IsEmpty())
    {
        AddError(TEXT("BLOCKED: bind native-authored BehaviorTree in [OpenCaw.UnrealFeatures]."));
        return false;
    }
    UBehaviorTree* Tree = LoadObject<UBehaviorTree>(nullptr, *TreePath);
    if (!TestNotNull(TEXT("Bound native BehaviorTree loads"), Tree)) return false;
    FGameplayWorld Context;
    if (!TestNotNull(TEXT("AI world"), Context.World)) return false;
    auto* Controller = Context.World->SpawnActor<AAIController>();
    auto* Pawn = Context.World->SpawnActor<ACharacter>();
    if (!TestTrue(TEXT("AI controller and pawn spawned"), Controller && Pawn)) return false;
    if (!TestTrue(TEXT("AI fixture controls authority"), Controller->HasAuthority())) return false;
    Controller->Possess(Pawn);
    UOpenCawFixtureAbortTask::Started = 0;
    UOpenCawFixtureAbortTask::Aborted = 0;
    UOpenCawFixtureAbortTask::LateCompletions = 0;
    if (!TestTrue(TEXT("Bound BehaviorTree starts"), Controller->RunBehaviorTree(Tree))) return false;
    auto* Brain = Cast<UBehaviorTreeComponent>(Controller->GetBrainComponent());
    if (!TestNotNull(TEXT("Actual BehaviorTree component"), Brain)) return false;
    for (int32 Frame = 0; Frame != 8 && UOpenCawFixtureAbortTask::Started == 0; ++Frame)
        Context.World->Tick(LEVELTICK_All, 0.001f);
    TestEqual(TEXT("Real long-running task entered once"), UOpenCawFixtureAbortTask::Started, 1);
    Brain->StopTree(EBTStopMode::Forced);
    TestEqual(TEXT("Native abort callback ran once"), UOpenCawFixtureAbortTask::Aborted, 1);
    for (int32 Frame = 0; Frame != 20; ++Frame) Context.World->Tick(LEVELTICK_All, 0.02f);
    TestFalse(TEXT("Tree stopped after abort"), Brain->IsRunning());
    TestEqual(TEXT("Owned timer cannot complete an aborted task"), UOpenCawFixtureAbortTask::LateCompletions, 0);
    Controller->UnPossess();
    TestNull(TEXT("Controller no longer owns retired pawn"), Controller->GetPawn());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawMassLifecycle, "OpenCaw.UnrealFeatures.MassLifecycle", FeatureFlags)
bool FOpenCawMassLifecycle::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.MassLifecycle"))) return false;
    TSharedRef<FMassEntityManager> Manager = MakeShared<FMassEntityManager>(nullptr);
    Manager->Initialize();
    const UScriptStruct* Types[] = {FOpenCawFixtureMassValue::StaticStruct()};
    const FMassArchetypeHandle Archetype = Manager->CreateArchetype(
        MakeArrayView(Types), FMassArchetypeCreationParams());
    const FMassEntityHandle Entity = Manager->CreateEntity(Archetype, FMassArchetypeSharedFragmentValues());
    if (!TestTrue(TEXT("Real entity was built"), Manager->IsEntityValid(Entity) && Manager->IsEntityBuilt(Entity)))
    {
        Manager->Deinitialize();
        return false;
    }
    Manager->GetFragmentDataChecked<FOpenCawFixtureMassValue>(Entity).Value = 37;
    TestEqual(TEXT("Native fragment state survives access"),
        Manager->GetFragmentDataChecked<FOpenCawFixtureMassValue>(Entity).Value, 37);
    Manager->Defer().DestroyEntity(Entity);
    TestTrue(TEXT("Deferred deletion does not mutate before flush"), Manager->IsEntityValid(Entity));
    TestTrue(TEXT("Native command buffer holds pending work"), Manager->Defer().HasPendingCommands());
    Manager->FlushCommands();
    TestFalse(TEXT("Flush invalidates retired entity handle"), Manager->IsEntityValid(Entity));
    const FMassEntityHandle Replacement = Manager->CreateEntity(Archetype, FMassArchetypeSharedFragmentValues());
    TestTrue(TEXT("Replacement entity exists"), Manager->IsEntityValid(Replacement));
    TestFalse(TEXT("Replacement does not resurrect retired handle"), Manager->IsEntityValid(Entity));
    TestTrue(TEXT("Replacement has distinct full identity"), Replacement != Entity);
    Manager->DestroyEntity(Replacement);
    Manager->Deinitialize();
    return true;
}

namespace
{
struct FFeatureTransition
{
    bool bComplete = false;
    bool bSucceeded = false;
};

class FGameFeatureUnloadCommand : public IAutomationLatentCommand
{
public:
    FGameFeatureUnloadCommand(FAutomationTestBase* InTest, const FString& InURL)
        : Test(InTest), URL(InURL), Pending(MakeShared<FFeatureTransition>())
    {
        Deadline = FPlatformTime::Seconds() + 20.0;
        BeginActivation();
    }
    virtual bool Update() override
    {
        if (FPlatformTime::Seconds() > Deadline)
        {
            Test->AddError(TEXT("GameFeature transition exceeded bounded deadline"));
            UGameFeaturesSubsystem::Get().DeactivateGameFeaturePlugin(URL);
            UGameFeaturesSubsystem::Get().UnloadGameFeaturePlugin(URL, false);
            return true;
        }
        if (!Pending->bComplete) return false;
        if (!Pending->bSucceeded)
        {
            Test->AddError(TEXT("Native GameFeature transition failed"));
            UGameFeaturesSubsystem::Get().DeactivateGameFeaturePlugin(URL);
            UGameFeaturesSubsystem::Get().UnloadGameFeaturePlugin(URL, false);
            return true;
        }
        if (Phase == 0 || Phase == 3)
        {
            UOpenCawFixtureFeatureAction* Active = UOpenCawFixtureFeatureAction::LastActivated.Get();
            if (!Test->TestNotNull(TEXT("Bound native GameFeature action activated"), Active)) return true;
            Probe.Reset(Active);
            if (!Test->TestTrue(TEXT("Feature installed actual engine frame delegate"),
                FCoreDelegates::OnEndFrame.IsBoundToObject(Active))) return true;
            InitialCallbacks = Active->FrameCallbacks;
            ++Phase;
            return false;
        }
        if (Phase == 1 || Phase == 4)
        {
            if (Probe->FrameCallbacks <= InitialCallbacks) return false;
            Test->TestTrue(TEXT("Installed delegate ran through an actual engine frame"),
                Probe->FrameCallbacks > InitialCallbacks);
            const TSharedRef<FFeatureTransition> State = MakeShared<FFeatureTransition>();
            Pending = State;
            UGameFeaturesSubsystem::Get().UnloadGameFeaturePlugin(URL,
                FGameFeaturePluginUnloadComplete::CreateLambda([State](const UE::GameFeatures::FResult& Result)
                {
                    State->bSucceeded = !Result.HasError();
                    State->bComplete = true;
                }), false);
            ++Phase;
            return false;
        }
        if (Phase == 2 || Phase == 5)
        {
            Test->TestFalse(TEXT("Unload removed feature-owned engine delegate"),
                FCoreDelegates::OnEndFrame.IsBoundToObject(Probe.Get()));
            Test->TestNull(TEXT("Plugin no longer exposes active GameFeatureData"),
                UGameFeaturesSubsystem::Get().GetGameFeatureDataForActivePluginByURL(URL));
            if (Phase == 5) return true;
            Probe.Reset();
            ++Phase;
            BeginActivation();
        }
        return false;
    }
private:
    void BeginActivation()
    {
        const TSharedRef<FFeatureTransition> State = MakeShared<FFeatureTransition>();
        Pending = State;
        UOpenCawFixtureFeatureAction::LastActivated.Reset();
        UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin(URL,
            FGameFeaturePluginLoadComplete::CreateLambda([State](const UE::GameFeatures::FResult& Result)
            {
                State->bSucceeded = !Result.HasError();
                State->bComplete = true;
            }));
    }
    FAutomationTestBase* Test;
    FString URL;
    TSharedRef<FFeatureTransition> Pending;
    TStrongObjectPtr<UOpenCawFixtureFeatureAction> Probe;
    int32 InitialCallbacks = 0;
    int32 Phase = 0;
    double Deadline = 0;
};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawGameFeatureUnload, "OpenCaw.UnrealFeatures.GameFeatureUnload", FeatureFlags)
bool FOpenCawGameFeatureUnload::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.GameFeatureUnload"))) return false;
    FString PluginName;
    if (!GConfig->GetString(TEXT("OpenCaw.UnrealFeatures"), TEXT("GameFeaturePluginName"), PluginName, GGameIni) || PluginName.IsEmpty())
    {
        AddError(TEXT("BLOCKED: bind isolated GameFeaturePluginName in [OpenCaw.UnrealFeatures]."));
        return false;
    }
    const TSharedPtr<IPlugin> Plugin = IPluginManager::Get().FindPlugin(PluginName);
    if (!TestTrue(TEXT("Feature plugin belongs to this fixture project"), Plugin.IsValid() &&
        FPaths::IsUnderDirectory(Plugin->GetBaseDir(), FPaths::ProjectPluginsDir()))) return false;
    FString URL;
    if (!TestTrue(TEXT("Selected native feature URL resolves"),
        UGameFeaturesSubsystem::Get().GetPluginURLByName(PluginName, URL))) return false;
    if (!TestNull(TEXT("Fixture feature starts inactive"),
        UGameFeaturesSubsystem::Get().GetGameFeatureDataForActivePluginByURL(URL))) return false;
    ADD_LATENT_AUTOMATION_COMMAND(FGameFeatureUnloadCommand(this, URL));
    return true;
}
#endif
