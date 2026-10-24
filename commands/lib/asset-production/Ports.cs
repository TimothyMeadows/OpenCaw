namespace OpenCaw.AssetProduction;

public interface IWorkspace
{
    string Root { get; }
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
