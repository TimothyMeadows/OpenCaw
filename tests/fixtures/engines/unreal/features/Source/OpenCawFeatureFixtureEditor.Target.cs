using UnrealBuildTool;

public class OpenCawFeatureFixtureEditorTarget : TargetRules
{
    public OpenCawFeatureFixtureEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        ExtraModuleNames.Add("OpenCawFeatureFixture");
    }
}
