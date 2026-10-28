using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace OpenCaw.AssetProduction;

// Canonical selection adapter shared by asset workflows; this is not a selector.
public static class CanonicalEngineContext
{
    public static async Task<JsonObject> Resolve(IWorkspace workspace, string baseline, INativeProcess process, string task, CancellationToken cancellation)
    {
        if (!Regex.IsMatch(task, "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$") || task == "..")
            throw new InvalidOperationException("Invalid task identity for engine evidence");
        var canonical = Path.Combine(Path.GetFullPath(baseline), "commands/lib/engine-contract.cjs");
        if (!File.Exists(canonical))
            throw new InvalidOperationException("Canonical engine resolver is unavailable");
        var executable = "node" + (OperatingSystem.IsWindows() ? ".exe" : "");
        var node = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Select(directory => Path.Combine(directory, executable)).FirstOrDefault(File.Exists)
            ?? throw new InvalidOperationException("Node.js is required by the canonical engine resolver; no software installed");
        var attempt = ".opencaw/.cache/tasks/" + task + "/asset-engine-probes/" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(workspace.Resolve(attempt));
        var result = workspace.Resolve(attempt + "/engine.json");
        const string invoke = "const fs=require('fs'); const resolver=require(process.argv[1]); const value=resolver.resolve(process.argv[2],{}); fs.writeFileSync(process.argv[3],JSON.stringify(value),{flag:'wx'});";
        await process.Run(node, ["-e", invoke, canonical, workspace.Root, result], workspace.Root,
            workspace.Resolve(attempt + "/process.log"), 20, cancellation, 262144);
        if (!File.Exists(result) || new FileInfo(result).Length > 262144)
            throw new InvalidOperationException("Engine resolver produced no bounded receipt");
        var value = JsonNode.Parse(File.ReadAllText(result))!.AsObject();
        if (value["effectiveEngine"]?.GetValue<string>() is not ("THREEJS" or "BABYLONJS" or "UNITY" or "UNREAL" or "GODOT" or "PHASERJS"))
            throw new InvalidOperationException("Canonical resolver returned an unknown engine");
        return value;
    }
}
