using System.Text.Json;
using OpenCaw.ProofToModel.Domain;
namespace OpenCaw.ProofToModel.Application;

public interface IWorkspace
{
    string Root
    {
        get;
    }
    string Resolve(string path);
    string Relative(string path);
    string HashFile(string absolutePath);
    void Save<T>(string path, T value);
    T Load<T>(string path);
    FileStream Lock(string path);
}
public interface INativeProcess
{
    Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null);
}
public interface IAlphaProcessor
{
    AlphaMatte? Inspect(string path);
    void SaveMask(string path, AlphaMatte matte);
    void PadSquare(string input, string output, int side);
}
public static class Serialization
{
    public static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true, PropertyNameCaseInsensitive = true };
}
