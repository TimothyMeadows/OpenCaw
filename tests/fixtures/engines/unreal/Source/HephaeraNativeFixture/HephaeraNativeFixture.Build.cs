using UnrealBuildTool;

public class HephaeraNativeFixture : ModuleRules
{
    public HephaeraNativeFixture(ReadOnlyTargetRules target) : base(target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine" });
    }
}
