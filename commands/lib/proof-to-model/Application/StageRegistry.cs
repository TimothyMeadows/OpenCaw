namespace OpenCaw.ProofToModel.Application;
// Adapted from Bubo ToolRegistry: deterministic, case-insensitive registered names,
// duplicate registration rejected by ToDictionary. No coding-agent tool registrations.
public sealed class StageRegistry(IEnumerable<(string Name, Func<CancellationToken, Task> Run)> stages)
{
    readonly Dictionary<string, Func<CancellationToken, Task>> registered = stages.ToDictionary(s => s.Name, s => s.Run, StringComparer.OrdinalIgnoreCase);
    public Task Execute(string name, CancellationToken cancellation) => registered.TryGetValue(name, out var run) ? run(cancellation) : throw new InvalidOperationException("Unknown stage: " + name);
}
