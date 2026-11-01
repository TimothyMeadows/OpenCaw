#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "PresentationFixtureTypes.generated.h"

class UNiagaraComponent;

// Place one instance in the authored presentation fixture map. The sequence
// must animate this real reflected property; an empty sequence cannot pass.
UCLASS()
class HEPHAERAFEATUREFIXTURE_API AHephaeraPresentationProbe : public AActor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, BlueprintReadWrite, Interp, Category="Hephaera Fixture")
    float AnimatedValue = 17.0f;
};

// Counters observe actual engine multicast delegates, not simulated playback.
UCLASS(Transient)
class HEPHAERAFEATUREFIXTURE_API UHephaeraPresentationCallbacks : public UObject
{
    GENERATED_BODY()

public:
    int32 SequenceStopCount = 0;
    int32 SequenceFinishCount = 0;
    int32 NiagaraFinishCount = 0;

    UFUNCTION()
    void OnSequenceStopped() { ++SequenceStopCount; }

    UFUNCTION()
    void OnSequenceFinished() { ++SequenceFinishCount; }

    UFUNCTION()
    void OnNiagaraFinished(UNiagaraComponent* Component) { ++NiagaraFinishCount; }
};
