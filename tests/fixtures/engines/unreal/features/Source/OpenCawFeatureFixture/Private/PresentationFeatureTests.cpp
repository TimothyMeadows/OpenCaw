#include "PresentationFixtureTypes.h"

#if WITH_DEV_AUTOMATION_TESTS && WITH_EDITOR
#include "FeatureEvidence.h"
#include "Camera/CameraActor.h"
#include "Camera/PlayerCameraManager.h"
#include "FileHelpers.h"
#include "Engine/Engine.h"
#include "Engine/URL.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "GameFramework/PlayerController.h"
#include "LevelSequence.h"
#include "LevelSequenceActor.h"
#include "LevelSequencePlayer.h"
#include "Misc/AutomationTest.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/PackageName.h"
#include "Misc/ScopeExit.h"
#include "MovieScene.h"
#include "MovieSceneSequencePlaybackSettings.h"
#include "MovieSceneSequencePlayer.h"
#include "NiagaraComponent.h"
#include "NiagaraFunctionLibrary.h"
#include "NiagaraParameterStore.h"
#include "NiagaraSystem.h"
#include "NiagaraTypes.h"
#include "UObject/ObjectKey.h"
#include "UObject/StrongObjectPtr.h"

namespace OpenCawPresentationFixtures
{
    constexpr const TCHAR* ConfigSection = TEXT("OpenCaw.UnrealFeatures");

    bool RequiredConfig(FAutomationTestBase& Test, const TCHAR* Key, FString& Value)
    {
        if (!GConfig || !GConfig->GetString(ConfigSection, Key, Value, GGameIni) || Value.IsEmpty())
        {
            Test.AddError(FString::Printf(TEXT("Missing [%s] %s in GGameIni; author the native asset described in PresentationFixtures.md."), ConfigSection, Key));
            return false;
        }
        return true;
    }

    UWorld* LoadPresentationMap(FAutomationTestBase& Test)
    {
        FString Package;
        if (!RequiredConfig(Test, TEXT("PresentationMap"), Package)) return nullptr;
        if (!Package.StartsWith(TEXT("/Game/")) || !FPackageName::IsValidLongPackageName(Package))
        {
            Test.AddError(TEXT("PresentationMap must be a /Game/ long package name, without an object suffix."));
            return nullptr;
        }
        const FString Filename = FPackageName::LongPackageNameToFilename(Package, FPackageName::GetMapPackageExtension());
        UWorld* World = UEditorLoadingAndSavingUtils::LoadMap(Filename);
        Test.TestNotNull(TEXT("Configured native presentation map loads"), World);
        return World;
    }

    // A fixture-owned adapter around real view-target APIs. Its generation is
    // application policy, not a claim that Unreal arbitrates competing callers.
    class FViewOwner
    {
    public:
        FViewOwner(APlayerController* InController, AActor* InFallback)
            : Controller(InController), Fallback(InFallback) {}

        uint64 Acquire(AActor* Target)
        {
            ++Generation;
            Controller->SetViewTarget(Target);
            return Generation;
        }

        void Release(uint64 Request)
        {
            if (Request == Generation && Controller.IsValid() && Fallback.IsValid())
            {
                ++Generation;
                Controller->SetViewTarget(Fallback.Get());
            }
        }

    private:
        TWeakObjectPtr<APlayerController> Controller;
        TWeakObjectPtr<AActor> Fallback;
        uint64 Generation = 0;
    };
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawCameraOwnership,
    "OpenCaw.UnrealFeatures.CameraOwnership",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FOpenCawCameraOwnership::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.CameraOwnership"))) return false;
    using namespace OpenCawPresentationFixtures;
    if (!TestNotNull(TEXT("Native engine exists"), GEngine)) return false;
    UWorld* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (!TestNotNull(TEXT("Camera fixture world exists"), World)) return false;
    GEngine->CreateNewWorldContext(EWorldType::Game).SetCurrentWorld(World);
    ON_SCOPE_EXIT
    {
        GEngine->DestroyWorldContext(World);
        World->DestroyWorld(false);
    };
    if (!TestTrue(TEXT("Camera fixture world has completed native world initialization"), World->IsInitialized())) return false;
    World->InitializeActorsForPlay(FURL(), true, nullptr);

    APlayerController* First = World->SpawnActor<APlayerController>();
    APlayerController* Second = World->SpawnActor<APlayerController>();
    ACameraActor* FirstGameplay = World->SpawnActor<ACameraActor>();
    ACameraActor* SecondGameplay = World->SpawnActor<ACameraActor>();
    ACameraActor* OlderShot = World->SpawnActor<ACameraActor>();
    ACameraActor* NewerShot = World->SpawnActor<ACameraActor>();
    if (!TestNotNull(TEXT("First controller spawned"), First) ||
        !TestNotNull(TEXT("Second controller spawned"), Second) ||
        !TestNotNull(TEXT("First gameplay camera spawned"), FirstGameplay) ||
        !TestNotNull(TEXT("Second gameplay camera spawned"), SecondGameplay) ||
        !TestNotNull(TEXT("Older shot camera spawned"), OlderShot) ||
        !TestNotNull(TEXT("Newer shot camera spawned"), NewerShot)) return false;

    First->bAutoManageActiveCameraTarget = false;
    Second->bAutoManageActiveCameraTarget = false;
    if (!First->PlayerCameraManager) First->SpawnPlayerCameraManager();
    if (!Second->PlayerCameraManager) Second->SpawnPlayerCameraManager();
    if (!TestNotNull(TEXT("First camera manager exists"), First->PlayerCameraManager.Get()) ||
        !TestNotNull(TEXT("Second camera manager exists"), Second->PlayerCameraManager.Get())) return false;
    TestTrue(TEXT("Controllers own distinct native camera managers"), First->PlayerCameraManager != Second->PlayerCameraManager);

    First->SetViewTarget(FirstGameplay);
    Second->SetViewTarget(SecondGameplay);
    FViewOwner Owner(First, FirstGameplay);
    const uint64 Older = Owner.Acquire(OlderShot);
    TestTrue(TEXT("First request selects its actual view target"), First->GetViewTarget() == OlderShot);
    TestTrue(TEXT("Other controller retains its view target"), Second->GetViewTarget() == SecondGameplay);

    const uint64 Newer = Owner.Acquire(NewerShot);
    Owner.Release(Older);
    TestTrue(TEXT("Retired request cannot restore over the replacement camera"), First->GetViewTarget() == NewerShot);
    Owner.Release(Newer);
    TestTrue(TEXT("Current request restores a valid gameplay target"), First->GetViewTarget() == FirstGameplay);
    Owner.Release(Newer);
    TestTrue(TEXT("Repeated release leaves gameplay target intact"), First->GetViewTarget() == FirstGameplay);

    const uint64 Destroyed = Owner.Acquire(OlderShot);
    TestTrue(TEXT("Temporary target destruction succeeds"), OlderShot->Destroy());
    Owner.Release(Destroyed);
    TestTrue(TEXT("Destroyed shot releases to a live fallback"), First->GetViewTarget() == FirstGameplay);
    TestTrue(TEXT("Cleanup never changes the other controller"), Second->GetViewTarget() == SecondGameplay);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawVFXPooling,
    "OpenCaw.UnrealFeatures.VFXPooling",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FOpenCawVFXPooling::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.VFXPooling"))) return false;
    using namespace OpenCawPresentationFixtures;
    UWorld* World = LoadPresentationMap(*this);
    if (!World) return false;
    FString AssetPath;
    if (!RequiredConfig(*this, TEXT("NiagaraSystem"), AssetPath)) return false;
    UNiagaraSystem* System = LoadObject<UNiagaraSystem>(nullptr, *AssetPath);
    if (!TestNotNull(TEXT("Configured Niagara system loads as a real system"), System)) return false;
    if (!TestTrue(TEXT("System contains an emitter"), System->GetNumEmitters() > 0) ||
        !TestFalse(TEXT("CPU fixture contains no GPU emitters"), System->HasAnyGPUEmitters()) ||
        !TestTrue(TEXT("System is valid and compiled before the run"), System->IsValid() && System->IsReadyToRun()) ||
        !TestTrue(TEXT("System enables a resident component pool"), System->MaxPoolSize > 0)) return false;
    const FName Parameter(TEXT("User.OpenCawIntensity"));
    const FNiagaraVariable Intensity(FNiagaraTypeDefinition::GetFloatDef(), Parameter);
    if (!TestTrue(TEXT("Asset exposes the required typed user parameter"), System->GetExposedParameters().IndexOf(Intensity) != INDEX_NONE)) return false;

    TStrongObjectPtr<UOpenCawPresentationCallbacks> OldCallbacks(NewObject<UOpenCawPresentationCallbacks>());
    TStrongObjectPtr<UOpenCawPresentationCallbacks> NewCallbacks(NewObject<UOpenCawPresentationCallbacks>());
    UNiagaraComponent* Active = nullptr;
    ON_SCOPE_EXIT
    {
        if (IsValid(Active))
        {
            Active->OnSystemFinished.RemoveAll(OldCallbacks.Get());
            Active->OnSystemFinished.RemoveAll(NewCallbacks.Get());
            Active->DeactivateImmediate();
            Active->ReleaseToPool();
        }
    };

    Active = UNiagaraFunctionLibrary::SpawnSystemAtLocation(World, System, FVector::ZeroVector,
        FRotator::ZeroRotator, FVector::OneVector, false, false, ENCPoolMethod::ManualRelease, false);
    if (!TestNotNull(TEXT("Manual pool acquisition returns a component"), Active)) return false;
    if (!TestTrue(TEXT("Engine honored ManualRelease pooling"), Active->PoolingMethod == ENCPoolMethod::ManualRelease)) return false;
    Active->SetForceSolo(true);
    Active->SetAllowScalability(false);
    Active->SetVariableFloat(Parameter, 2.0f);
    Active->OnSystemFinished.AddDynamic(OldCallbacks.Get(), &UOpenCawPresentationCallbacks::OnNiagaraFinished);
    Active->Activate(true);
    Active->AdvanceSimulation(2, 1.0f / 60.0f);
    TestFalse(TEXT("Real system remains incomplete during its declared lifetime"), Active->IsComplete());
    Active->DeactivateImmediate();
    TestTrue(TEXT("Immediate cancellation completes the effect"), Active->IsComplete());
    TestEqual(TEXT("Engine completion reached the old owner once"), OldCallbacks->NiagaraFinishCount, 1);
    Active->OnSystemFinished.RemoveAll(OldCallbacks.Get());
    const FObjectKey ReleasedIdentity(Active);
    Active->ReleaseToPool();
    Active = nullptr; // No dereference through a retired pool handle.

    const FVector NewLocation(120.0, 40.0, 80.0);
    Active = UNiagaraFunctionLibrary::SpawnSystemAtLocation(World, System, NewLocation,
        FRotator::ZeroRotator, FVector::OneVector, false, false, ENCPoolMethod::ManualRelease, false);
    if (!TestNotNull(TEXT("Second manual acquisition succeeds"), Active)) return false;
    TestTrue(TEXT("The engine actually reuses the returned component"), FObjectKey(Active) == ReleasedIdentity);
    Active->SetForceSolo(true);
    Active->SetAllowScalability(false);
    Active->SetVariableFloat(Parameter, 0.25f);
    Active->OnSystemFinished.AddDynamic(NewCallbacks.Get(), &UOpenCawPresentationCallbacks::OnNiagaraFinished);
    Active->Activate(true);
    Active->AdvanceSimulation(2, 1.0f / 60.0f);
    bool bValidParameter = false;
    const float ObservedIntensity = Active->GetVariableFloat(Parameter, bValidParameter);
    TestTrue(TEXT("Reused component exposes its new float override"), bValidParameter);
    TestTrue(TEXT("Reused component uses the new owner's value"), FMath::IsNearlyEqual(ObservedIntensity, 0.25f));
    TestTrue(TEXT("Reused component uses the new spawn transform"), Active->GetComponentLocation().Equals(NewLocation));
    Active->DeactivateImmediate();
    TestEqual(TEXT("New playback completion reaches only its new owner"), NewCallbacks->NiagaraFinishCount, 1);
    TestEqual(TEXT("Retired completion callback remains detached"), OldCallbacks->NiagaraFinishCount, 1);
    Active->OnSystemFinished.RemoveAll(NewCallbacks.Get());
    Active->ReleaseToPool();
    Active = nullptr;
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawSequenceInterruption,
    "OpenCaw.UnrealFeatures.SequenceInterruption",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FOpenCawSequenceInterruption::RunTest(const FString& Parameters)
{
    if (!OpenCawFeatureEvidence(*this, TEXT("OpenCaw.UnrealFeatures.SequenceInterruption"))) return false;
    using namespace OpenCawPresentationFixtures;
    UWorld* World = LoadPresentationMap(*this);
    if (!World) return false;
    FString AssetPath;
    if (!RequiredConfig(*this, TEXT("LevelSequence"), AssetPath)) return false;
    ULevelSequence* Sequence = LoadObject<ULevelSequence>(nullptr, *AssetPath);
    if (!TestNotNull(TEXT("Configured real LevelSequence loads"), Sequence) ||
        !TestNotNull(TEXT("Sequence contains a MovieScene"), Sequence->GetMovieScene())) return false;

    AOpenCawPresentationProbe* Probe = nullptr;
    int32 ProbeCount = 0;
    for (TActorIterator<AOpenCawPresentationProbe> It(World); It; ++It)
    {
        if (It->ActorHasTag(TEXT("OpenCawSequenceProbe"))) { Probe = *It; ++ProbeCount; }
    }
    if (!TestEqual(TEXT("Authored map contains exactly one tagged probe"), ProbeCount, 1)) return false;
    if (!TestTrue(TEXT("Sequence binds the actual world probe"), Sequence->FindBindingFromObject(Probe, World).IsValid())) return false;
    const float Baseline = Probe->AnimatedValue;
    FMovieSceneSequencePlaybackSettings Settings;
    Settings.bAutoPlay = false;
    Settings.bDisableCameraCuts = true;
    Settings.FinishCompletionStateOverride = EMovieSceneCompletionModeOverride::ForceRestoreState;
    ALevelSequenceActor* SequenceActor = nullptr;
    ULevelSequencePlayer* Player = ULevelSequencePlayer::CreateLevelSequencePlayer(World, Sequence, Settings, SequenceActor);
    if (!TestNotNull(TEXT("Native sequence player is created"), Player) ||
        !TestNotNull(TEXT("Native sequence actor is created"), SequenceActor)) return false;
    TStrongObjectPtr<UOpenCawPresentationCallbacks> Callbacks(NewObject<UOpenCawPresentationCallbacks>());
    ON_SCOPE_EXIT
    {
        Player->OnStop.RemoveAll(Callbacks.Get());
        Player->OnFinished.RemoveAll(Callbacks.Get());
        Player->Stop();
        SequenceActor->Destroy();
    };
    Player->OnStop.AddDynamic(Callbacks.Get(), &UOpenCawPresentationCallbacks::OnSequenceStopped);
    Player->OnFinished.AddDynamic(Callbacks.Get(), &UOpenCawPresentationCallbacks::OnSequenceFinished);

    Player->Play();
    Player->SetPlaybackPosition(FMovieSceneSequencePlaybackParams(0.5f, EUpdatePositionMethod::Jump));
    TestTrue(TEXT("Native player is playing before interruption"), Player->IsPlaying());
    TestTrue(TEXT("Real bound property changed through sequence evaluation"), !FMath::IsNearlyEqual(Probe->AnimatedValue, Baseline));
    Player->Pause();
    TestTrue(TEXT("Native player enters paused state"), Player->IsPaused());
    Player->Stop();
    TestFalse(TEXT("Interrupted native player is not playing"), Player->IsPlaying());
    TestFalse(TEXT("Stopped player is no longer paused"), Player->IsPaused());
    TestTrue(TEXT("Stop restores the actual preanimated property"), FMath::IsNearlyEqual(Probe->AnimatedValue, Baseline));
    TestEqual(TEXT("Explicit stop emits the stop delegate"), Callbacks->SequenceStopCount, 1);
    TestEqual(TEXT("Interruption does not emit natural completion"), Callbacks->SequenceFinishCount, 0);
    Player->OnStop.RemoveAll(Callbacks.Get());
    Player->OnFinished.RemoveAll(Callbacks.Get());

    Player->Play();
    Player->SetPlaybackPosition(FMovieSceneSequencePlaybackParams(1.0f, EUpdatePositionMethod::Jump));
    TestTrue(TEXT("Restarted playback evaluates its own new state"), !FMath::IsNearlyEqual(Probe->AnimatedValue, Baseline));
    Player->Stop();
    TestTrue(TEXT("Repeated playback cancellation still restores baseline"), FMath::IsNearlyEqual(Probe->AnimatedValue, Baseline));
    TestEqual(TEXT("Retired owner no longer receives sequence stop"), Callbacks->SequenceStopCount, 1);
    return true;
}
#endif
