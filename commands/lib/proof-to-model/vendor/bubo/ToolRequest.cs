namespace Bubo.LocalAgent.Abstractions;

public sealed record ToolRequest
{
    public required string Name { get; init; }

    public required string WorkspaceRoot { get; init; }

    public IReadOnlyDictionary<string, string> Arguments { get; init; } =
        new Dictionary<string, string>(StringComparer.Ordinal);
}
