using System.Text.Json;
namespace OpenCaw.AssetProduction;

public static class AuditJournal
{
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    public static void Append(IWorkspace workspace, string path, object value)
    {
        var full = workspace.Resolve(path);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        var record = JsonSerializer.Serialize(value, Json);
        if (System.Text.Encoding.UTF8.GetByteCount(record) > 1048576) throw new InvalidOperationException("Audit event exceeds one MiB");
        File.AppendAllText(full, record + "\n");
    }
}
