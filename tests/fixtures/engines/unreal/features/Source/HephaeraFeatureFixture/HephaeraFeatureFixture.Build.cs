using UnrealBuildTool;

public class HephaeraFeatureFixture : ModuleRules
{
    public HephaeraFeatureFixture(ReadOnlyTargetRules Target) : base(Target)
    {
        if (!Target.bBuildEditor)
            throw new BuildException("HephaeraFeatureFixture is an isolated Editor test module.");
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] {
            "Core", "CoreUObject", "Engine", "AIModule", "GameplayAbilities",
            "GameplayTags", "GameplayTasks", "GameFeatures", "MassEntity",
            "Niagara", "LevelSequence", "MovieScene", "PCG"
        });
        PrivateDependencyModuleNames.AddRange(new[] { "UnrealEd", "NavigationSystem", "Projects" });
    }
}
