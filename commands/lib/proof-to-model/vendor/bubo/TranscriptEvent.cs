namespace Bubo.LocalAgent.Abstractions;

public sealed record TranscriptEvent
{
    public DateTimeOffset Timestamp { get; init; } = DateTimeOffset.UtcNow;

    public required string Type { get; init; }

    public required string Message { get; init; }

    public IReadOnlyDictionary<string, string> Data { get; init; } =
        new Dictionary<string, string>(StringComparer.Ordinal);
}
