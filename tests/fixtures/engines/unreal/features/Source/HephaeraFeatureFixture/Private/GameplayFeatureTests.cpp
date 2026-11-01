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

FHephaeraFixtureJobControl::FHephaeraFixtureJobControl()
    : Gate(FPlatformProcess::GetSynchEventFromPool(true)) {}

FHephaeraFixtureJobControl::~FHephaeraFixtureJobControl()
{
    FPlatformProcess::ReturnSynchEventToPool(Gate);
}

void AHephaeraFixtureAsyncRecipient::EndPlay(const EEndPlayReason::Type Reason)
{
    ++RequestGeneration;
    if (Job)
    {
        Job->Canceled.store(true);
        Job->Gate->Trigger();
    }
    Super::EndPlay(Reason);
}

FGameplayAttribute UHephaeraFixtureAttributes::HealthAttribute()
{
    return FGameplayAttribute(FindFPropertyChecked<FProperty>(StaticClass(),
        GET_MEMBER_NAME_CHECKED(UHephaeraFixtureAttributes, Health)));
}

AHephaeraFixtureAbilityOwner::AHephaeraFixtureAbilityOwner()
{
    Abilities = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("Abilities"));
    Attributes = CreateDefaultSubobject<UHephaeraFixtureAttributes>(TEXT("Attributes"));
}

UAbilitySystemComponent* AHephaeraFixtureAbilityOwner::GetAbilitySystemComponent() const
{
    return Abilities;
}

UHephaeraFixtureOwnedAbility::UHephaeraFixtureOwnedAbility()
{
    InstancingPolicy = EGameplayAbilityInstancingPolicy::InstancedPerActor;
    NetExecutionPolicy = EGameplayAbilityNetExecutionPolicy::ServerOnly;
}

void UHephaeraFixtureOwnedAbility::ActivateAbility(const FGameplayAbilitySpecHandle Handle,
    const FGameplayAbilityActorInfo* ActorInfo,
    const FGameplayAbilityActivationInfo ActivationInfo,
    const FGameplayEventData* TriggerEventData)
{
    // Deliberately stays active until the owning grant is canceled in the fixture.
    SetCanBeCanceled(true);
}

UHephaeraFixtureDamage::UHephaeraFixtureDamage()
{
    DurationPolicy = EGameplayEffectDurationType::Instant;
    FGameplayModifierInfo Modifier;
    Modifier.Attribute = UHephaeraFixtureAttributes::HealthAttribute();
    Modifier.ModifierOp = EGameplayModOp::Additive;
    Modifier.ModifierMagnitude = FScalableFloat(-17.0f);
    Modifiers.Add(Modifier);
}

int32 UHephaeraFixtureAbortTask::Started = 0;
int32 UHephaeraFixtureAbortTask::Aborted = 0;
int32 UHephaeraFixtureAbortTask::LateCompletions = 0;

UHephaeraFixtureAbortTask::UHephaeraFixtureAbortTask()
{
    bCreateNodeInstance = true;
    NodeName = TEXT("Hephaera owned latent operation");
}

EBTNodeResult::Type UHephaeraFixtureAbortTask::ExecuteTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory)
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

EBTNodeResult::Type UHephaeraFixtureAbortTask::AbortTask(UBehaviorTreeComponent& OwnerComp, uint8* NodeMemory)
{
    OwnerComp.GetWorld()->GetTimerManager().ClearTimer(CompletionTimer);
    ++Aborted;
    return EBTNodeResult::Aborted;
}

TWeakObjectPtr<UHephaeraFixtureFeatureAction> UHephaeraFixtureFeatureAction::LastActivated;

void UHephaeraFixtureFeatureAction::OnGameFeatureActivating(FGameFeatureActivatingContext& Context)
{
    Super::OnGameFeatureActivating(Context);
    RemoveOwnedDelegate();
    FrameHandle = FCoreDelegates::OnEndFrame.AddUObject(this, &UHephaeraFixtureFeatureAction::ObserveFrame);
    LastActivated = this;
}

void UHephaeraFixtureFeatureAction::OnGameFeatureDeactivating(FGameFeatureDeactivatingContext& Context)
{
    RemoveOwnedDelegate();
    Super::OnGameFeatureDeactivating(Context);
}

void UHephaeraFixtureFeatureAction::OnGameFeatureUnloading()
{
    RemoveOwnedDelegate();
    Super::OnGameFeatureUnloading();
}

void UHephaeraFixtureFeatureAction::ObserveFrame() { ++FrameCallbacks; }

void UHephaeraFixtureFeatureAction::RemoveOwnedDelegate()
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
    TSharedRef<FHephaeraFixtureJobControl, ESPMode::ThreadSafe> Control)
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

bool ApplyWorkResult(TWeakObjectPtr<AHephaeraFixtureAsyncRecipient> Recipient,
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
        Recipient = Context.World->SpawnActor<AHephaeraFixtureAsyncRecipient>();
        Retired = Context.World->SpawnActor<AHephaeraFixtureAsyncRecipient>();
        if (!Test->TestTrue(TEXT("Both recipients spawned"), Recipient.IsValid() && Retired.IsValid())) return;
        if (!Recipient->HasActorBegunPlay()) Recipient->DispatchBeginPlay();
        if (!Retired->HasActorBegunPlay()) Retired->DispatchBeginPlay();
        Recipient->Value = 11;
        Recipient->Job = MakeShared<FHephaeraFixtureJobControl, ESPMode::ThreadSafe>();
        Retired->Job = MakeShared<FHephaeraFixtureJobControl, ESPMode::ThreadSafe>();
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
    TWeakObjectPtr<AHephaeraFixtureAsyncRecipient> Recipient;
    TWeakObjectPtr<AHephaeraFixtureAsyncRecipient> Retired;
    TSharedPtr<FHephaeraFixtureJobControl, ESPMode::ThreadSafe> RetiredControl;
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraAsyncTeardown, "Hephaera.UnrealFeatures.AsyncTeardown", FeatureFlags)
bool FHephaeraAsyncTeardown::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.AsyncTeardown"))) return false;
    ADD_LATENT_AUTOMATION_COMMAND(FAsyncTeardownCommand(this));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraGASOwnership, "Hephaera.UnrealFeatures.GASOwnership", FeatureFlags)
bool FHephaeraGASOwnership::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.GASOwnership"))) return false;
    FGameplayWorld Context;
    if (!TestNotNull(TEXT("GAS world"), Context.World)) return false;
    auto* Owner = Context.World->SpawnActor<AHephaeraFixtureAbilityOwner>();
    auto* Target = Context.World->SpawnActor<AHephaeraFixtureAbilityOwner>();
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
            FGameplayAbilitySpec(UHephaeraFixtureOwnedAbility::StaticClass(), 1, INDEX_NONE, Owner));
        Grants.Add(Source, Handle);
        return Handle;
    };
    const FGameplayAbilitySpecHandle Owned = GrantOwned();
    const FGameplayAbilitySpecHandle Other = ASC->GiveAbility(
        FGameplayAbilitySpec(UHephaeraFixtureOtherAbility::StaticClass(), 1));
    ASC->InitAbilityActorInfo(Owner, AvatarB);
    TestTrue(TEXT("Respawn retains the owned grant identity"), GrantOwned() == Owned);
    TestEqual(TEXT("Respawn does not duplicate startup abilities"), ASC->GetActivatableAbilities().Num(), 2);
    TestEqual(TEXT("Persistent ASC follows the new avatar"), ASC->GetAvatarActor(), AvatarB);
    const FGameplayAttribute Health = UHephaeraFixtureAttributes::HealthAttribute();
    ASC->SetNumericAttributeBase(Health, 100.0f);
    Target->Abilities->SetNumericAttributeBase(Health, 100.0f);
    FGameplayEffectSpecHandle Damage = ASC->MakeOutgoingSpec(
        UHephaeraFixtureDamage::StaticClass(), 1.0f, ASC->MakeEffectContext());
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraMovement, "Hephaera.UnrealFeatures.Movement", FeatureFlags)
bool FHephaeraMovement::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.Movement"))) return false;
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraAICancellation, "Hephaera.UnrealFeatures.AICancellation", FeatureFlags)
bool FHephaeraAICancellation::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.AICancellation"))) return false;
    FString TreePath;
    if (!GConfig->GetString(TEXT("Hephaera.UnrealFeatures"), TEXT("BehaviorTree"), TreePath, GGameIni) || TreePath.IsEmpty())
    {
        AddError(TEXT("BLOCKED: bind native-authored BehaviorTree in [Hephaera.UnrealFeatures]."));
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
    UHephaeraFixtureAbortTask::Started = 0;
    UHephaeraFixtureAbortTask::Aborted = 0;
    UHephaeraFixtureAbortTask::LateCompletions = 0;
    if (!TestTrue(TEXT("Bound BehaviorTree starts"), Controller->RunBehaviorTree(Tree))) return false;
    auto* Brain = Cast<UBehaviorTreeComponent>(Controller->GetBrainComponent());
    if (!TestNotNull(TEXT("Actual BehaviorTree component"), Brain)) return false;
    for (int32 Frame = 0; Frame != 8 && UHephaeraFixtureAbortTask::Started == 0; ++Frame)
        Context.World->Tick(LEVELTICK_All, 0.001f);
    TestEqual(TEXT("Real long-running task entered once"), UHephaeraFixtureAbortTask::Started, 1);
    Brain->StopTree(EBTStopMode::Forced);
    TestEqual(TEXT("Native abort callback ran once"), UHephaeraFixtureAbortTask::Aborted, 1);
    for (int32 Frame = 0; Frame != 20; ++Frame) Context.World->Tick(LEVELTICK_All, 0.02f);
    TestFalse(TEXT("Tree stopped after abort"), Brain->IsRunning());
    TestEqual(TEXT("Owned timer cannot complete an aborted task"), UHephaeraFixtureAbortTask::LateCompletions, 0);
    Controller->UnPossess();
    TestNull(TEXT("Controller no longer owns retired pawn"), Controller->GetPawn());
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraMassLifecycle, "Hephaera.UnrealFeatures.MassLifecycle", FeatureFlags)
bool FHephaeraMassLifecycle::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.MassLifecycle"))) return false;
    TSharedRef<FMassEntityManager> Manager = MakeShared<FMassEntityManager>(nullptr);
    Manager->Initialize();
    const UScriptStruct* Types[] = {FHephaeraFixtureMassValue::StaticStruct()};
    const FMassArchetypeHandle Archetype = Manager->CreateArchetype(
        MakeArrayView(Types), FMassArchetypeCreationParams());
    const FMassEntityHandle Entity = Manager->CreateEntity(Archetype, FMassArchetypeSharedFragmentValues());
    if (!TestTrue(TEXT("Real entity was built"), Manager->IsEntityValid(Entity) && Manager->IsEntityBuilt(Entity)))
    {
        Manager->Deinitialize();
        return false;
    }
    Manager->GetFragmentDataChecked<FHephaeraFixtureMassValue>(Entity).Value = 37;
    TestEqual(TEXT("Native fragment state survives access"),
        Manager->GetFragmentDataChecked<FHephaeraFixtureMassValue>(Entity).Value, 37);
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
            UHephaeraFixtureFeatureAction* Active = UHephaeraFixtureFeatureAction::LastActivated.Get();
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
        UHephaeraFixtureFeatureAction::LastActivated.Reset();
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
    TStrongObjectPtr<UHephaeraFixtureFeatureAction> Probe;
    int32 InitialCallbacks = 0;
    int32 Phase = 0;
    double Deadline = 0;
};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraGameFeatureUnload, "Hephaera.UnrealFeatures.GameFeatureUnload", FeatureFlags)
bool FHephaeraGameFeatureUnload::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.GameFeatureUnload"))) return false;
    FString PluginName;
    if (!GConfig->GetString(TEXT("Hephaera.UnrealFeatures"), TEXT("GameFeaturePluginName"), PluginName, GGameIni) || PluginName.IsEmpty())
    {
        AddError(TEXT("BLOCKED: bind isolated GameFeaturePluginName in [Hephaera.UnrealFeatures]."));
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
