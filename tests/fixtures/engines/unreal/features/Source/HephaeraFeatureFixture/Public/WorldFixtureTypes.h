#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "WorldFixtureTypes.generated.h"

// Fixture-only reflected value types. They are not an application save format.
USTRUCT()
struct FHephaeraWorldSavedEntity
{
    GENERATED_BODY()

    UPROPERTY()
    FGuid EntityId;

    UPROPERTY()
    FName DefinitionId;

    UPROPERTY()
    int32 LegacyScore = 0;

    UPROPERTY()
    int32 Score = 0;
};

UCLASS()
class UHephaeraWorldSave : public USaveGame
{
    GENERATED_BODY()

public:
    UPROPERTY()
    int32 SchemaVersion = 1;

    UPROPERTY()
    TArray<FHephaeraWorldSavedEntity> Entities;
};
