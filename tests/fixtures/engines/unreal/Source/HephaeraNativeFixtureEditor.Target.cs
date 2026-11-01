using UnrealBuildTool;

public class HephaeraNativeFixtureEditorTarget : TargetRules
{
    public HephaeraNativeFixtureEditorTarget(TargetInfo target) : base(target)
    {
        Type = TargetType.Editor;
        ExtraModuleNames.Add("HephaeraNativeFixture");
    }
}
