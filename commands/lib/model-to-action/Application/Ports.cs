using System.Text.Json.Nodes;
namespace OpenCaw.ModelAction.Application;
public interface IEngineResolver { Task<JsonObject> Resolve(CancellationToken cancellation); }
