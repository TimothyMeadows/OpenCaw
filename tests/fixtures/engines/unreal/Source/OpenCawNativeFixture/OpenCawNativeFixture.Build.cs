using UnrealBuildTool;

public class OpenCawNativeFixture : ModuleRules
{
    public OpenCawNativeFixture(ReadOnlyTargetRules target) : base(target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine" });
    }
}
