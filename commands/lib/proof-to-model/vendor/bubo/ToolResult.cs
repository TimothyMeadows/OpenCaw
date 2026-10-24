namespace Bubo.LocalAgent.Abstractions;

public sealed record ToolResult
{
    public required bool Success { get; init; }

    public string Output { get; init; } = string.Empty;

    public string Error { get; init; } = string.Empty;

    public int? ExitCode { get; init; }
}
