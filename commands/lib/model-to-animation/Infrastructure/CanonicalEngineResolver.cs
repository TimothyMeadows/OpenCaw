using System.Text.Json.Nodes;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAnimation.Application;
namespace OpenCaw.ModelAnimation.Infrastructure;

// Invokes the canonical exported resolver under the shared bounded native runner.
// The fixed wrapper writes clean JSON rather than decoding stream-log prefixes.
public sealed class CanonicalEngineResolver(IWorkspace workspace, string baseline, INativeProcess process, string task) : IEngineResolver
{
    public Task<JsonObject> Resolve(CancellationToken cancellation) =>
        CanonicalEngineContext.Resolve(workspace, baseline, process, task, cancellation);
}
