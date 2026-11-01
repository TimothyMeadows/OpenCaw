using UnrealBuildTool;

public class HephaeraNativeFixtureTarget : TargetRules
{
    public HephaeraNativeFixtureTarget(TargetInfo target) : base(target)
    {
        Type = TargetType.Game;
        ExtraModuleNames.Add("HephaeraNativeFixture");
    }
}
