using System.Text.RegularExpressions;
namespace OpenCaw.ProofToModel.Domain;

public static class Compatibility
{
    public static string StripStreamMarkers(string log) => log.Replace("stdout: ", "", StringComparison.Ordinal).Replace("stderr: ", "", StringComparison.Ordinal);
    public static string? CudaVersionFromLog(string log)
    {
        var match = Regex.Match(StripStreamMarkers(log), @"CUDA(?: UMD)? Version:\s*(\d+\.\d+)");
        return match.Success ? match.Groups[1].Value : null;
    }
    public static bool IsBlender45Log(string log) => Regex.IsMatch(StripStreamMarkers(log), @"Blender 4\.5(?:\.|\s)");
    public static bool AtLeast(string actual, string minimum)
    {
        var normalized = Regex.Match(actual, @"\d+(?:\.\d+)*").Value;
        var required = Regex.Match(minimum, @"\d+(?:\.\d+)*").Value;
        if (!normalized.Contains('.'))
            normalized += ".0";
        if (!required.Contains('.'))
            required += ".0";
        return Version.TryParse(normalized, out var installed) && Version.TryParse(required, out var expected) && installed >= expected;
    }
    public static void Require(string actual, string minimum, string label)
    {
        if (!AtLeast(actual, minimum))
            throw new InvalidOperationException(label + " requires " + minimum + ", detected " + actual);
    }
}
