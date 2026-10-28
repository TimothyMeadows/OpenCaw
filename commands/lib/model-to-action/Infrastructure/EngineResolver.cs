using System.Text.Json.Nodes;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAction.Application;
namespace OpenCaw.ModelAction.Infrastructure;
public sealed class EngineResolver(IWorkspace workspace, string baseline, INativeProcess process, string task) : IEngineResolver
{
    public Task<JsonObject> Resolve(CancellationToken cancellation) => CanonicalEngineContext.Resolve(workspace, baseline, process, task, cancellation);
}
