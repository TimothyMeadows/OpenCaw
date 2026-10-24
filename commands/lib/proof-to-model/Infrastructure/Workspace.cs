using System.Security.Cryptography;
using System.Text.Json;
using OpenCaw.ProofToModel.Application;
namespace OpenCaw.ProofToModel.Infrastructure;
// Adapted from Bubo WorkspaceGuard at the attributed commit. Guards native file access,
// and deliberately makes no claim of providing an operating-system sandbox.
public sealed class Workspace(string root) : IWorkspace
{
    public string Root { get; } = Path.GetFullPath(root);
    readonly StringComparison comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
    public string Resolve(string path)
    {
        if ((File.GetAttributes(Root) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidOperationException("Project root cannot be a reparse point");
        var full = Path.GetFullPath(path, Root);
        if (!full.Equals(Root, comparison) && !full.StartsWith(Root + Path.DirectorySeparatorChar, comparison))
            throw new InvalidOperationException("Path escapes project: " + path);
        var relative = Path.GetRelativePath(Root, full);
        if (relative.Split(Path.DirectorySeparatorChar)[0].Equals(".git", comparison))
            throw new InvalidOperationException("Git metadata is reserved");
        var current = Root;
        foreach (var segment in relative.Split(Path.DirectorySeparatorChar))
        {
            current = Path.Combine(current, segment);
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Symbolic links/reparse points are prohibited: " + current);
        }
        return full;
    }
    public string Relative(string path) => Path.GetRelativePath(Root, Resolve(path)).Replace('\\', '/');
    public static string Hash(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexStringLower(SHA256.HashData(stream));
    }
    public string HashFile(string absolutePath) => Hash(absolutePath);
    public static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true, PropertyNameCaseInsensitive = true };
    public void Save<T>(string path, T value)
    {
        var full = Resolve(path);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        var temp = full + "." + Guid.NewGuid() + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(value, Json));
        File.Move(temp, full, true);
    }
    public T Load<T>(string path) => JsonSerializer.Deserialize<T>(File.ReadAllText(Resolve(path)), Json) ?? throw new InvalidOperationException("Invalid JSON");
    public FileStream Lock(string path)
    {
        var full = Resolve(path);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        try
        {
            return new FileStream(full, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException) { throw new InvalidOperationException("Another run owns this asset/GPU lock"); }
    }
}
