using UnrealBuildTool;

public class OpenCawNativeFixtureEditorTarget : TargetRules
{
    public OpenCawNativeFixtureEditorTarget(TargetInfo target) : base(target)
    {
        Type = TargetType.Editor;
        ExtraModuleNames.Add("OpenCawNativeFixture");
    }
}
