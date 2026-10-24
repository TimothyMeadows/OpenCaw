#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Engine/World.h"
#include "GameFramework/Actor.h"
#include "Components/SceneComponent.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOpenCawLifecycleStateTest,
    "OpenCaw.Fixtures.LifecycleState",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FOpenCawLifecycleStateTest::RunTest(const FString& Parameters)
{
    UWorld* World = UWorld::CreateWorld(EWorldType::Game, false);
    if (!TestNotNull(TEXT("Transient world exists"), World)) return false;
    AActor* Actor = World->SpawnActor<AActor>();
    if (!TestNotNull(TEXT("Actor spawned"), Actor))
    {
        World->DestroyWorld(false);
        return false;
    }
    USceneComponent* Component = NewObject<USceneComponent>(Actor);
    Actor->AddInstanceComponent(Component);
    Component->RegisterComponent();
    TestTrue(TEXT("Component registered with the world"), Component->IsRegistered());
    Component->Activate(true);
    TestTrue(TEXT("Component became active"), Component->IsActive());
    Component->Deactivate();
    TestFalse(TEXT("Component deactivated"), Component->IsActive());
    Component->UnregisterComponent();
    TestFalse(TEXT("Component unregistered"), Component->IsRegistered());
    TestTrue(TEXT("Actor destruction succeeded"), Actor->Destroy());
    World->DestroyWorld(false);
    return true;
}
#endif
