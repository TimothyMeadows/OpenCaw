#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "WorldFixtureTypes.generated.h"

// Fixture-only reflected value types. They are not an application save format.
USTRUCT()
struct FOpenCawWorldSavedEntity
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
class UOpenCawWorldSave : public USaveGame
{
    GENERATED_BODY()

public:
    UPROPERTY()
    int32 SchemaVersion = 1;

    UPROPERTY()
    TArray<FOpenCawWorldSavedEntity> Entities;
};
