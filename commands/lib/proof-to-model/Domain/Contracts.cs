using System.Text.Json.Nodes;
namespace OpenCaw.ProofToModel.Domain;

public sealed class Manifest
{
    public int SchemaVersion { get; set; } = 1;
    public string Asset { get; set; } = ""; public string Version { get; set; } = "";
    public string Task { get; set; } = ""; public string Staging { get; set; } = "";
    public string StyleHash { get; set; } = ""; public string Proof { get; set; } = "";
    public string Rights { get; set; } = ""; public string Recipe { get; set; } = "";
    public string ProofMetadata { get; set; } = "";
    public string SourceSet { get; set; } = "";
    public string Classification { get; set; } = "";
    public string ProofSet { get; set; } = "";
    public string Brief { get; set; } = "";
    public string Toolchain { get; set; } = ""; public string CreatedBy { get; set; } = "";
    public Dictionary<string, Stage> Stages { get; set; } = new(StringComparer.Ordinal);
    public List<Approval> Approvals { get; set; } = [];
    public List<JsonObject> History { get; set; } = [];
}
public sealed class Stage
{
    public string Status { get; set; } = "running"; public string Fingerprint { get; set; } = "";
    public string Attempt { get; set; } = ""; public string? Error
    {
        get; set;
    }
    public Dictionary<string, string> Inputs { get; set; } = [];
    public Dictionary<string, string> ExternalInputs { get; set; } = [];
    public Dictionary<string, string> Outputs { get; set; } = [];
    public Dictionary<string, string> Artifacts { get; set; } = [];
}
public sealed record Approval(string Kind, string Reviewer, string Evidence, string EvidenceHash, string Fingerprint, DateTimeOffset Timestamp);
// Adapted from Bubo TranscriptEvent (MIT, pinned source in vendor/bubo).
public sealed record AuditEvent
{
    public DateTimeOffset Timestamp { get; init; } = DateTimeOffset.UtcNow;
    public required string Type
    {
        get; init;
    }
    public required string Message
    {
        get; init;
    }
    public IReadOnlyDictionary<string, string> Data { get; init; } = new Dictionary<string, string>(StringComparer.Ordinal);
}
