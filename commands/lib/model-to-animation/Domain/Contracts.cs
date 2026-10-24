using System.Text.Json.Nodes;
namespace OpenCaw.ModelAnimation.Domain;

public sealed class Manifest
{
    public string SchemaVersion { get; set; } = "opencaw-model-animation/v1";
    public string Task { get; set; } = "";
    public string Asset { get; set; } = "";
    public string Version { get; set; } = "";
    public string Actor { get; set; } = "";
    public string Profile { get; set; } = "";
    public string Staging { get; set; } = "";
    public string Model { get; set; } = "";
    public string Recipe { get; set; } = "";
    public string EffectiveRecipe { get; set; } = "";
    public string EffectiveRecipeSha256 { get; set; } = "";
    public string Rights { get; set; } = "";
    public string Blender { get; set; } = "";
    public string BlenderSha256 { get; set; } = "";
    public string EngineReceipt { get; set; } = "";
    public JsonObject Engine { get; set; } = new();
    public Dictionary<string, string> Originals { get; set; } = new(StringComparer.Ordinal);
    public Dictionary<string, string> BaselineInputs { get; set; } = new(StringComparer.Ordinal);
    public Dictionary<string, string> SourceInputs { get; set; } = new(StringComparer.Ordinal);
    public Dictionary<string, Stage> Stages { get; set; } = new(StringComparer.Ordinal);
    public Stage? LastSuccessfulMotion
    {
        get; set;
    }
    public List<Approval> Approvals { get; set; } = [];
    public List<JsonObject> History { get; set; } = [];
}
public sealed class Stage
{
    public string Status { get; set; } = "running";
    public string Operation { get; set; } = "";
    public string Attempt { get; set; } = "";
    public string? Error
    {
        get; set;
    }
    public Dictionary<string, string> Inputs { get; set; } = new(StringComparer.Ordinal);
    public Dictionary<string, string> ExternalInputs { get; set; } = new(StringComparer.Ordinal);
    public Dictionary<string, string> Outputs { get; set; } = new(StringComparer.Ordinal);
    public Dictionary<string, string> Artifacts { get; set; } = new(StringComparer.Ordinal);
}
public sealed record Approval(string Kind, string Reviewer, string Evidence, string EvidenceHash, string Fingerprint, DateTimeOffset Timestamp);
