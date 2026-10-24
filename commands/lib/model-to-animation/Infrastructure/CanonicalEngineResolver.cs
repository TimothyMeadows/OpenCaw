using System.Text.Json.Nodes;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAnimation.Application;
namespace OpenCaw.ModelAnimation.Infrastructure;

// Invokes the canonical exported resolver under the shared bounded native runner.
// The fixed wrapper writes clean JSON rather than decoding stream-log prefixes.
public sealed class CanonicalEngineResolver(IWorkspace workspace, string baseline, INativeProcess process, string task) : IEngineResolver
{
    public async Task<JsonObject> Resolve(CancellationToken cancellation)
    {
        var root = Path.GetFullPath(baseline);
        var canonical = Path.Combine(root, "commands/lib/engine-contract.cjs");
        if (!File.Exists(canonical))
            throw new InvalidOperationException("Canonical engine resolver is unavailable");
        var node = FindExecutable("node");
        var attempt = ".opencaw/.cache/tasks/" + MotionValidation.Id(task) + "/model-animation-engine-probes/" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(workspace.Resolve(attempt));
        var result = workspace.Resolve(attempt + "/engine.json");
        const string invoke = "const fs=require('fs'); const resolver=require(process.argv[1]); const value=resolver.resolve(process.argv[2],{}); fs.writeFileSync(process.argv[3],JSON.stringify(value),{flag:'wx'});";
        await process.Run(node, ["-e", invoke, canonical, workspace.Root, result], workspace.Root, workspace.Resolve(attempt + "/process.log"), 20, cancellation, 262144);
        if (!File.Exists(result) || new FileInfo(result).Length > 262144)
            throw new InvalidOperationException("Engine resolver produced no bounded receipt");
        var value = JsonNode.Parse(File.ReadAllText(result))!.AsObject();
        if (value["effectiveEngine"]?.GetValue<string>() is not ("THREEJS" or "BABYLONJS" or "UNITY" or "UNREAL" or "GODOT" or "PHASERJS"))
            throw new InvalidOperationException("Canonical resolver returned an unknown engine");
        return value;
    }
    static string FindExecutable(string name)
    {
        var executable = name + (OperatingSystem.IsWindows() ? ".exe" : "");
        return (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator).Select(directory => Path.Combine(directory, executable)).FirstOrDefault(File.Exists) ?? throw new InvalidOperationException("Node.js is required by the canonical engine resolver; no software installed");
    }
}
