#pragma once

#include "CoreMinimal.h"
#include "HAL/PlatformMisc.h"
#include "Misc/AutomationTest.h"

// A fresh runner nonce binds a real Automation entry to this invocation. It is
// not an approval token and does not establish visual or gameplay correctness.
inline bool HephaeraFeatureEvidence(FAutomationTestBase& Test, const TCHAR* CaseName)
{
    const FString Run = FPlatformMisc::GetEnvironmentVariable(TEXT("HEPHAERA_UNREAL_FEATURE_RUN"));
    if (Run.IsEmpty())
    {
        Test.AddError(TEXT("Feature evidence requires a fresh native runner invocation."));
        return false;
    }
    Test.AddInfo(FString::Printf(TEXT("HephaeraFeatureEvidence run=%s case=%s"), *Run, CaseName));
    return true;
}
