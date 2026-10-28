using System.Text.Json.Nodes;
namespace OpenCaw.ModelAnimation.Application;

public interface IEngineResolver
{
    Task<JsonObject> Resolve(CancellationToken cancellation);
}
