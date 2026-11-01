using UnrealBuildTool;

public class HephaeraFeatureFixtureEditorTarget : TargetRules
{
    public HephaeraFeatureFixtureEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.Latest;
        ExtraModuleNames.Add("HephaeraFeatureFixture");
    }
}
