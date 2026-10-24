using UnrealBuildTool;

public class OpenCawNativeFixtureTarget : TargetRules
{
    public OpenCawNativeFixtureTarget(TargetInfo target) : base(target)
    {
        Type = TargetType.Game;
        ExtraModuleNames.Add("OpenCawNativeFixture");
    }
}
