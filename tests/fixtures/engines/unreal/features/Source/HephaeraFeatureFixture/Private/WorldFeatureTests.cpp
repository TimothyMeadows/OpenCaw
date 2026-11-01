#if WITH_DEV_AUTOMATION_TESTS && WITH_EDITOR
#include "FeatureEvidence.h"
#include "WorldFixtureTypes.h"

#include "Components/InstancedStaticMeshComponent.h"
#include "Data/PCGBasePointData.h"
#include "Engine/Engine.h"
#include "Engine/Level.h"
#include "Engine/LevelStreamingDynamic.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Engine/WorldInitializationValues.h"
#include "EngineUtils.h"
#include "FileHelpers.h"
#include "GameFramework/Actor.h"
#include "HAL/PlatformTime.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/AutomationTest.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/Crc.h"
#include "Misc/PackageName.h"
#include "PCGComponent.h"
#include "PCGData.h"
#include "Serialization/MemoryReader.h"
#include "Serialization/MemoryWriter.h"
#include "UObject/StrongObjectPtr.h"

namespace HephaeraWorldFixture
{
constexpr double StageTimeoutSeconds = 30.0;
constexpr uint32 SaveMagic = 0x5741434f; // Fixture envelope, not a platform file contract.
constexpr int32 MaximumSaveBytes = 1024 * 1024;

bool RequiredConfig(FAutomationTestBase* Test, const TCHAR* Key, FString& Value)
{
    if (!GConfig->GetString(TEXT("Hephaera.UnrealFeatures"), Key, Value, GGameIni) || Value.IsEmpty())
    {
        Test->AddError(FString::Printf(TEXT("Missing native fixture binding %s; author the assets in WorldFixtures.md before running"), Key));
        return false;
    }
    return true;
}

// The context and world are owned by this test, never by an interactive Editor session.
struct FStreamingState
{
    TStrongObjectPtr<UWorld> World;
    TWeakObjectPtr<ULevelStreamingDynamic> Streaming;
    TWeakObjectPtr<AActor> FirstMarker;
    FName MarkerTag;
    int32 Stage = 0;
    double Deadline = FPlatformTime::Seconds() + StageTimeoutSeconds;

    ~FStreamingState()
    {
        if (World.IsValid())
        {
            World->DestroyWorld(false);
            if (GEngine) GEngine->DestroyWorldContext(World.Get());
        }
    }
};

class FStreamingCycle final : public IAutomationLatentCommand
{
public:
    FStreamingCycle(FAutomationTestBase* InTest, TSharedRef<FStreamingState> InState)
        : Test(InTest), State(MoveTemp(InState)) {}

    virtual bool Update() override
    {
        if (FPlatformTime::Seconds() > State->Deadline)
        {
            Test->AddError(FString::Printf(TEXT("Real streaming lifecycle timed out in stage %d"), State->Stage));
            return true;
        }
        ULevelStreamingDynamic* Stream = State->Streaming.Get();
        if (!Stream || !State->World.IsValid())
        {
            Test->AddError(TEXT("Streaming owner vanished before lifecycle completion"));
            return true;
        }
        State->World->UpdateLevelStreaming();
        if (State->Stage == 0 || State->Stage == 2)
        {
            ULevel* Level = Stream->GetLoadedLevel();
            if (!Level || !Level->bIsVisible) return false;
            TArray<AActor*> Markers;
            for (AActor* Actor : Level->Actors)
            {
                if (IsValid(Actor) && Actor->ActorHasTag(State->MarkerTag)) Markers.Add(Actor);
            }
            if (!Test->TestEqual(TEXT("Exactly one real marker in the visible streamed level"), Markers.Num(), 1)) return true;
            if (State->Stage == 0) State->FirstMarker = Markers[0];
            else Test->TestTrue(TEXT("Reload creates a distinct actor instance"), State->FirstMarker.Get() != Markers[0]);
            Stream->SetShouldBeVisible(false);
            Stream->SetShouldBeLoaded(false);
            ++State->Stage;
            State->Deadline = FPlatformTime::Seconds() + StageTimeoutSeconds;
            return false;
        }
        if (Stream->GetLoadedLevel() != nullptr) return false;
        Test->TestFalse(TEXT("Unloaded stream is no longer visible"), Stream->IsLevelVisible());
        if (State->Stage == 3) return true;
        Stream->SetShouldBeLoaded(true);
        Stream->SetShouldBeVisible(true);
        State->Stage = 2;
        State->Deadline = FPlatformTime::Seconds() + StageTimeoutSeconds;
        return false;
    }

private:
    FAutomationTestBase* Test;
    TSharedRef<FStreamingState> State;
};

TArray<FString> InstanceSignature(AActor* Owner)
{
    TArray<FString> Result;
    if (!Owner) return Result;
    TInlineComponentArray<UInstancedStaticMeshComponent*> Components(Owner);
    for (UInstancedStaticMeshComponent* Component : Components)
    {
        if (!IsValid(Component) || !Component->IsRegistered()) continue;
        for (int32 Index = 0; Index < Component->GetInstanceCount(); ++Index)
        {
            FTransform Transform;
            if (Component->GetInstanceTransform(Index, Transform, true))
                Result.Add(GetPathNameSafe(Component->GetStaticMesh()) + TEXT("|") + Transform.ToString());
        }
    }
    Result.Sort();
    return Result;
}

int32 OutputPointCount(UPCGComponent* Component)
{
    int32 Count = 0;
    for (const FPCGTaggedData& Tagged : Component->GetGeneratedGraphOutput().TaggedData)
    {
        if (const UPCGBasePointData* Points = Cast<UPCGBasePointData>(Tagged.Data.Get())) Count += Points->GetNumPoints();
    }
    return Count;
}

struct FProceduralState
{
    TWeakObjectPtr<UPCGComponent> Component;
    TWeakObjectPtr<AActor> Owner;
    FDelegateHandle GeneratedHandle;
    FDelegateHandle CleanedHandle;
    int32 Generated = 0;
    int32 Cleaned = 0;
    int32 Stage = 0;
    int32 CancelObservationTicks = 0;
    double Deadline = FPlatformTime::Seconds() + StageTimeoutSeconds;
    TArray<FString> FirstSignature;

    ~FProceduralState()
    {
        if (UPCGComponent* PCG = Component.Get())
        {
            PCG->OnPCGGraphGeneratedDelegate.Remove(GeneratedHandle);
            PCG->OnPCGGraphCleanedDelegate.Remove(CleanedHandle);
            PCG->CancelGeneration();
            PCG->CleanupLocalImmediate(true, true);
        }
    }
};

class FProceduralCycle final : public IAutomationLatentCommand
{
public:
    FProceduralCycle(FAutomationTestBase* InTest, TSharedRef<FProceduralState> InState)
        : Test(InTest), State(MoveTemp(InState)) {}

    virtual bool Update() override
    {
        if (FPlatformTime::Seconds() > State->Deadline)
        {
            Test->AddError(FString::Printf(TEXT("Real PCG execution/cleanup timed out in stage %d"), State->Stage));
            return true;
        }
        UPCGComponent* PCG = State->Component.Get();
        if (!PCG || !State->Owner.IsValid())
        {
            Test->AddError(TEXT("PCG owner vanished before its expected cleanup"));
            return true;
        }
        if (State->Stage == 6)
        {
            // Allow several real Automation ticks to catch a delayed completion/resource revival.
            if (++State->CancelObservationTicks < 3) return false;
            Test->TestFalse(TEXT("Cancelled generation remains stopped across ticks"), PCG->IsGenerating());
            Test->TestEqual(TEXT("Cancelled request never publishes a fourth completion"), State->Generated, 3);
            Test->TestTrue(TEXT("Cancelled request does not recreate mesh instances"), InstanceSignature(State->Owner.Get()).IsEmpty());
            return true;
        }
        if (State->Stage % 2 == 0)
        {
            const int32 ExpectedGenerated = State->Stage / 2 + 1;
            if (State->Generated < ExpectedGenerated || PCG->IsGenerating()) return false;
            TArray<FString> Signature = InstanceSignature(State->Owner.Get());
            if (!Test->TestTrue(TEXT("Native graph produced nonempty point output"), OutputPointCount(PCG) > 0) ||
                !Test->TestTrue(TEXT("Native graph produced managed mesh instances"), !Signature.IsEmpty())) return true;
            if (State->Stage == 0) State->FirstSignature = Signature;
            else if (State->Stage == 2) Test->TestTrue(TEXT("Identical seed regenerates identical sorted transforms"), Signature == State->FirstSignature);
            else Test->TestTrue(TEXT("Changed seed changes generated transforms"), Signature != State->FirstSignature);
            PCG->CleanupLocal(true);
            ++State->Stage;
        }
        else
        {
            const int32 ExpectedCleaned = (State->Stage + 1) / 2;
            if (State->Cleaned < ExpectedCleaned || PCG->IsCleaningUp()) return false;
            if (!Test->TestTrue(TEXT("Cleanup removes all fixture generated mesh instances"), InstanceSignature(State->Owner.Get()).IsEmpty())) return true;
            if (State->Stage == 5)
            {
                // Exercise an actual cancellation immediately after a fresh scheduling request.
                PCG->GenerateLocal(true);
                PCG->CancelGeneration();
                PCG->CleanupLocalImmediate(true, true);
                Test->TestFalse(TEXT("Cancelled generation is no longer running"), PCG->IsGenerating());
                Test->TestTrue(TEXT("Cancelled generation leaves no mesh instances"), InstanceSignature(State->Owner.Get()).IsEmpty());
                State->Stage = 6;
                State->Deadline = FPlatformTime::Seconds() + StageTimeoutSeconds;
                return false;
            }
            if (State->Stage == 3) PCG->Seed = 271829;
            PCG->GenerateLocal(true);
            ++State->Stage;
        }
        State->Deadline = FPlatformTime::Seconds() + StageTimeoutSeconds;
        return false;
    }

private:
    FAutomationTestBase* Test;
    TSharedRef<FProceduralState> State;
};

bool Encode(UHephaeraWorldSave* Save, TArray<uint8>& Bytes)
{
    TArray<uint8> Payload;
    if (!UGameplayStatics::SaveGameToMemory(Save, Payload) || Payload.IsEmpty() || Payload.Num() > MaximumSaveBytes) return false;
    uint32 Magic = SaveMagic;
    int32 Size = Payload.Num();
    uint32 Crc = FCrc::MemCrc32(Payload.GetData(), Payload.Num());
    Bytes.Reset();
    FMemoryWriter Writer(Bytes);
    Writer << Magic << Size << Crc;
    Writer.Serialize(Payload.GetData(), Size);
    return !Writer.IsError();
}

UHephaeraWorldSave* Decode(const TArray<uint8>& Bytes)
{
    constexpr int32 HeaderBytes = sizeof(uint32) + sizeof(int32) + sizeof(uint32);
    if (Bytes.Num() < HeaderBytes || Bytes.Num() > HeaderBytes + MaximumSaveBytes) return nullptr;
    FMemoryReader Reader(Bytes);
    uint32 Magic = 0;
    int32 Size = 0;
    uint32 ExpectedCrc = 0;
    Reader << Magic << Size << ExpectedCrc;
    if (Reader.IsError() || Magic != SaveMagic || Size <= 0 || Size > MaximumSaveBytes || Size != Bytes.Num() - HeaderBytes) return nullptr;
    TArray<uint8> Payload;
    Payload.SetNumUninitialized(Size);
    Reader.Serialize(Payload.GetData(), Size);
    if (Reader.IsError() || FCrc::MemCrc32(Payload.GetData(), Size) != ExpectedCrc) return nullptr;
    return Cast<UHephaeraWorldSave>(UGameplayStatics::LoadGameFromMemory(Payload));
}

bool Restore(const UHephaeraWorldSave* Save, TArray<FHephaeraWorldSavedEntity>& Live)
{
    if (!Save || Save->SchemaVersion < 1 || Save->SchemaVersion > 2 || Save->Entities.Num() > 1000) return false;
    TArray<FHephaeraWorldSavedEntity> Candidate = Save->Entities;
    TSet<FGuid> Ids;
    for (FHephaeraWorldSavedEntity& Entity : Candidate)
    {
        if (Save->SchemaVersion == 1) Entity.Score = Entity.LegacyScore;
        if (!Entity.EntityId.IsValid() || Ids.Contains(Entity.EntityId) || Entity.DefinitionId != FName(TEXT("FixtureDefinition")) || Entity.Score < 0 || Entity.Score > 1000000) return false;
        Ids.Add(Entity.EntityId);
        Entity.LegacyScore = 0;
    }
    Live = MoveTemp(Candidate); // The fixture's single commit point after complete validation.
    return true;
}
} // namespace HephaeraWorldFixture

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraWorldStreamingTest,
    "Hephaera.UnrealFeatures.WorldStreaming",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FHephaeraWorldStreamingTest::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.WorldStreaming"))) return false;
    using namespace HephaeraWorldFixture;
    FString LevelName, Tag;
    if (!RequiredConfig(this, TEXT("StreamingLevel"), LevelName) || !RequiredConfig(this, TEXT("StreamingMarkerTag"), Tag)) return false;
    if (!TestTrue(TEXT("Streaming level is a native package path"), FPackageName::IsValidLongPackageName(LevelName))) return false;
    TSharedRef<FStreamingState> State = MakeShared<FStreamingState>();
    UWorld::InitializationValues Init;
    Init.AllowAudioPlayback(false).CreatePhysicsScene(false).CreateNavigation(false).CreateAISystem(false).ShouldSimulatePhysics(false).SetTransactional(false);
    State->World.Reset(UWorld::CreateWorld(EWorldType::Game, false, NAME_None, nullptr, false, ERHIFeatureLevel::Num, &Init));
    if (!TestNotNull(TEXT("Owned native streaming world created"), State->World.Get()) || !TestNotNull(TEXT("Engine world context available"), GEngine)) return false;
    GEngine->CreateNewWorldContext(EWorldType::Game).SetCurrentWorld(State->World.Get());
    State->MarkerTag = FName(*Tag);
    const FString ObjectPath = LevelName + TEXT(".") + FPackageName::GetShortName(LevelName);
    bool Loaded = false;
    ULevelStreamingDynamic* Stream = ULevelStreamingDynamic::LoadLevelInstanceBySoftObjectPtr(State->World.Get(), TSoftObjectPtr<UWorld>(FSoftObjectPath(ObjectPath)), FVector::ZeroVector, FRotator::ZeroRotator, Loaded);
    if (!TestTrue(TEXT("Real streaming request accepted"), Loaded) || !TestNotNull(TEXT("Streaming handle exists"), Stream)) return false;
    State->Streaming = Stream;
    Stream->SetShouldBeLoaded(true);
    Stream->SetShouldBeVisible(true);
    ADD_LATENT_AUTOMATION_COMMAND(FStreamingCycle(this, State));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraProceduralRegenerationTest,
    "Hephaera.UnrealFeatures.ProceduralRegeneration",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FHephaeraProceduralRegenerationTest::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.ProceduralRegeneration"))) return false;
    using namespace HephaeraWorldFixture;
    FString MapName, Tag;
    if (!RequiredConfig(this, TEXT("ProceduralMap"), MapName) || !RequiredConfig(this, TEXT("ProceduralActorTag"), Tag)) return false;
    if (!TestTrue(TEXT("Procedural map is a native package path"), FPackageName::IsValidLongPackageName(MapName))) return false;
    const FString Filename = FPackageName::LongPackageNameToFilename(MapName, FPackageName::GetMapPackageExtension());
    UWorld* World = UEditorLoadingAndSavingUtils::LoadMap(Filename);
    if (!TestNotNull(TEXT("Real procedural fixture map loaded"), World)) return false;
    TArray<AActor*> Matches;
    for (TActorIterator<AActor> It(World); It; ++It) if (It->ActorHasTag(FName(*Tag))) Matches.Add(*It);
    if (!TestEqual(TEXT("Exactly one configured procedural actor"), Matches.Num(), 1)) return false;
    UPCGComponent* PCG = Matches[0]->FindComponentByClass<UPCGComponent>();
    if (!TestNotNull(TEXT("Native UPCGComponent exists"), PCG) || !TestNotNull(TEXT("Native authored PCG graph exists"), PCG->GetGraph())) return false;
    if (!TestFalse(TEXT("Fixture uses explicitly nonpartitioned PCG"), PCG->IsPartitioned()) ||
        !TestTrue(TEXT("Fixture has no pre-baked mesh instances"), InstanceSignature(Matches[0]).IsEmpty())) return false;
    TSharedRef<FProceduralState> State = MakeShared<FProceduralState>();
    State->Component = PCG;
    State->Owner = Matches[0];
    TWeakPtr<FProceduralState> WeakState(State);
    State->GeneratedHandle = PCG->OnPCGGraphGeneratedDelegate.AddLambda([WeakState](UPCGComponent*)
    {
        if (TSharedPtr<FProceduralState> Pinned = WeakState.Pin()) ++Pinned->Generated;
    });
    State->CleanedHandle = PCG->OnPCGGraphCleanedDelegate.AddLambda([WeakState](UPCGComponent*)
    {
        if (TSharedPtr<FProceduralState> Pinned = WeakState.Pin()) ++Pinned->Cleaned;
    });
    PCG->Seed = 314159;
    PCG->GenerateLocal(true);
    ADD_LATENT_AUTOMATION_COMMAND(FProceduralCycle(this, State));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FHephaeraSaveMigrationTest,
    "Hephaera.UnrealFeatures.SaveMigration",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FHephaeraSaveMigrationTest::RunTest(const FString& Parameters)
{
    if (!HephaeraFeatureEvidence(*this, TEXT("Hephaera.UnrealFeatures.SaveMigration"))) return false;
    using namespace HephaeraWorldFixture;
    TStrongObjectPtr<UHephaeraWorldSave> Legacy(NewObject<UHephaeraWorldSave>());
    FHephaeraWorldSavedEntity Entity;
    Entity.EntityId = FGuid::NewGuid();
    Entity.DefinitionId = TEXT("FixtureDefinition");
    Entity.LegacyScore = 125;
    Legacy->Entities.Add(Entity);
    TArray<uint8> Bytes;
    if (!TestTrue(TEXT("Native USaveGame serialized inside bounded envelope"), Encode(Legacy.Get(), Bytes))) return false;
    TStrongObjectPtr<UHephaeraWorldSave> Loaded(Decode(Bytes));
    if (!TestNotNull(TEXT("Native USaveGame deserialized"), Loaded.Get())) return false;
    TArray<FHephaeraWorldSavedEntity> Live;
    if (!TestTrue(TEXT("Legacy schema migrated before committing"), Restore(Loaded.Get(), Live)) || !TestEqual(TEXT("One entity restored"), Live.Num(), 1)) return false;
    TestEqual(TEXT("Stable entity identity roundtrips"), Live[0].EntityId, Entity.EntityId);
    TestEqual(TEXT("Legacy score migrated"), Live[0].Score, 125);
    TestEqual(TEXT("Migration removes legacy representation"), Live[0].LegacyScore, 0);
    TestTrue(TEXT("Repeat restore succeeds"), Restore(Loaded.Get(), Live));
    TestEqual(TEXT("Repeat restore does not duplicate entities"), Live.Num(), 1);
    Loaded->SchemaVersion = 3;
    TestFalse(TEXT("Future schema rejected"), Restore(Loaded.Get(), Live));
    Loaded->SchemaVersion = 2;
    Loaded->Entities[0].Score = -1;
    TestFalse(TEXT("Invalid numeric state rejected"), Restore(Loaded.Get(), Live));
    Loaded->Entities[0].Score = 10;
    Loaded->Entities.Add(Loaded->Entities[0]);
    TestFalse(TEXT("Duplicate entity identity rejected"), Restore(Loaded.Get(), Live));
    Loaded->Entities.SetNum(1);
    Loaded->Entities[0].DefinitionId = TEXT("MissingDefinition");
    TestFalse(TEXT("Missing authored definition rejected"), Restore(Loaded.Get(), Live));
    TestEqual(TEXT("Rejected restore preserves live cardinality"), Live.Num(), 1);
    TestEqual(TEXT("Rejected restore preserves live value"), Live[0].Score, 125);
    TestEqual(TEXT("Rejected restore preserves live identity"), Live[0].EntityId, Entity.EntityId);
    TArray<uint8> Corrupt = Bytes;
    Corrupt.Last() ^= 0x7f;
    TestNull(TEXT("Corrupt payload rejected before engine object decode"), Decode(Corrupt));
    TArray<uint8> Truncated = Bytes;
    Truncated.SetNum(Truncated.Num() - 1);
    TestNull(TEXT("Truncated payload rejected"), Decode(Truncated));
    TArray<uint8> Empty;
    TestNull(TEXT("Empty envelope rejected"), Decode(Empty));
    TestEqual(TEXT("Decoder failures do not mutate live state"), Live[0].Score, 125);
    return true;
}
#endif
