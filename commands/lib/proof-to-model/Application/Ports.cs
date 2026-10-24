using System.Text.Json;
using OpenCaw.ProofToModel.Domain;
namespace OpenCaw.ProofToModel.Application;

public interface IWorkspace : OpenCaw.AssetProduction.IWorkspace;
public interface INativeProcess : OpenCaw.AssetProduction.INativeProcess;
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
