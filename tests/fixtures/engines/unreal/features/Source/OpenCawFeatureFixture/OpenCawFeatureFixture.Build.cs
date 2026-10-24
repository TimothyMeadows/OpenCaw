using UnrealBuildTool;

public class OpenCawFeatureFixture : ModuleRules
{
    public OpenCawFeatureFixture(ReadOnlyTargetRules Target) : base(Target)
    {
        if (!Target.bBuildEditor)
            throw new BuildException("OpenCawFeatureFixture is an isolated Editor test module.");
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] {
            "Core", "CoreUObject", "Engine", "AIModule", "GameplayAbilities",
            "GameplayTags", "GameplayTasks", "GameFeatures", "MassEntity",
            "Niagara", "LevelSequence", "MovieScene", "PCG"
        });
        PrivateDependencyModuleNames.AddRange(new[] { "UnrealEd", "NavigationSystem", "Projects" });
    }
}
