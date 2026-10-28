using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAction.Domain;
using static OpenCaw.ModelAction.Application.ActionValidation;
namespace OpenCaw.ModelAction.Application;

public sealed partial class Pipeline
{
    async Task CheckBlender(string directory, CancellationToken cancellation)
    {
        var log = directory + "/blender-version.log";
        await native.Run(m.Blender, ["--version"], w.Root, w.Resolve(log), Math.Min(30, Budget["timeoutSeconds"]!.GetValue<int>()), cancellation, (long)Budget["maxLogBytes"]!.GetValue<double>());
        if (!Regex.IsMatch(File.ReadAllText(w.Resolve(log)), @"Blender\s+4\.5(?:\.\d+)?\b")) throw new InvalidOperationException("Existing Blender4.5LTS required; no fallback or installation");
        if (w.HashFile(m.Blender) != m.BlenderSha256) throw new InvalidOperationException("Blender changed during version inspection");
    }
    void VerifyBundle(string manifest, Dictionary<string, string> hashes)
    {
        RejectLinks(manifest);
        if (!File.Exists(manifest)) throw new InvalidOperationException("Missing audited action script manifest");
        var spec = JsonNode.Parse(File.ReadAllText(manifest))!.AsObject();
        if (spec["schemaVersion"]?.GetValue<int>() != 1 || spec["files"] is not JsonObject files || files.Count is < 1 or > 20 || files["action.py"] is null) throw new InvalidOperationException("Invalid fixed action script inventory");
        var directory = Path.GetDirectoryName(manifest)!;
        hashes[manifest] = w.HashFile(manifest);
        foreach (var pair in files)
        {
            if (!Regex.IsMatch(pair.Key, "^[a-z][a-z0-9_]*\\.py$")) throw new InvalidOperationException("Audited scripts use fixed local Python basenames");
            var source = Path.Combine(directory, pair.Key); RejectLinks(source);
            var expected = pair.Value!.GetValue<string>(); Hash(expected);
            if (!File.Exists(source) || w.HashFile(source) != expected) throw new InvalidOperationException("Audited action script changed: " + pair.Key);
            hashes[source] = expected;
        }
        if (!Directory.GetFiles(directory, "*.py").Select(Path.GetFileName).Order(StringComparer.Ordinal).SequenceEqual(files.Select(pair => pair.Key).Order(StringComparer.Ordinal))) throw new InvalidOperationException("Script inventory must cover the exact Python bundle");
    }
    static void RejectLinks(string path)
    {
        for (FileSystemInfo? item = new FileInfo(Path.GetFullPath(path)); item is not null; item = item is FileInfo file ? file.Directory : ((DirectoryInfo)item).Parent)
            if (item.Exists && (item.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidOperationException("Audited sources cannot traverse links/reparse points");
    }
    string CopyBundle(Stage stage)
    {
        var manifest = Path.Combine(Baseline, ".styles/.workflows/model-to-action/blender/scripts.json");
        VerifyBundle(manifest, stage.ExternalInputs);
        var files = JsonNode.Parse(File.ReadAllText(manifest))!["files"]!.AsObject();
        var destination = stage.Attempt + "/scripts"; Directory.CreateDirectory(w.Resolve(destination));
        foreach (var pair in files)
        {
            var target = destination + "/" + pair.Key; File.Copy(Path.Combine(Path.GetDirectoryName(manifest)!, pair.Key), w.Resolve(target), false);
            if (HashFile(target) != pair.Value!.GetValue<string>()) throw new InvalidOperationException("Audited script copy hash mismatch");
            stage.Inputs[target] = HashFile(target);
        }
        return destination;
    }
    async Task RunStage(string name, CancellationToken cancellation)
    {
        var index = System.Array.IndexOf(Order, name);
        if (m.History.Count(item => item["event"]?.GetValue<string>() == "stage-start" && item["stage"]?.GetValue<string>() == name) >= Budget["maxAttempts"]!.GetValue<int>()) throw new InvalidOperationException("Action stage attempt budget exhausted; use a new reviewed version");
        var stage = new Stage { Attempt = m.Staging + "/attempts/" + name + "-" + Guid.NewGuid().ToString("N") };
        stage.Inputs = m.Originals.Concat(m.SourceInputs).Concat(m.Stages.Where(pair => System.Array.IndexOf(Order, pair.Key) < index && pair.Value.Status == "complete").SelectMany(pair => pair.Value.Outputs))
            .GroupBy(pair => pair.Key).ToDictionary(group => group.Key, group => group.First().Value, StringComparer.Ordinal);
        stage.ExternalInputs = new(m.BaselineInputs, StringComparer.Ordinal) { [m.Blender] = m.BlenderSha256 };
        if (m.Stages.TryGetValue(name, out var previous)) m.History.Add(new JsonObject { ["event"] = previous.Status == "running" ? "stage-interrupted" : "stage-replaced", ["stage"] = name, ["state"] = System.Text.Json.JsonSerializer.SerializeToNode(previous, Workspace.Json) });
        Directory.CreateDirectory(w.Resolve(stage.Attempt)); m.Stages[name] = stage;
        foreach (var later in Order.Skip(index + 1)) m.Stages.Remove(later);
        m.Approvals.Clear();
        m.History.Add(new JsonObject { ["event"] = "stage-start", ["stage"] = name, ["attempt"] = stage.Attempt, ["timestamp"] = DateTimeOffset.UtcNow.ToString("O") }); Save();
        try
        {
            cancellation.ThrowIfCancellationRequested();
            var scripts = CopyBundle(stage); await CheckBlender(stage.Attempt, cancellation);
            var plan = Plan(); var input = name is "inspect" or "compose" ? m.Model : name == "export" ? Artifact("compose", "blend") : Artifact("export", "glb");
            var planPath = stage.Attempt + "/compiled-plan.json"; w.Save(planPath, plan); stage.Inputs[planPath] = HashFile(planPath); stage.Artifacts["plan"] = planPath;
            var job = new JsonObject { ["schemaVersion"] = 1, ["root"] = w.Root, ["operation"] = name, ["input"] = input, ["outputDir"] = stage.Attempt, ["result"] = stage.Attempt + "/result.json", ["asset"] = m.Asset, ["version"] = m.Version, ["profile"] = m.Profile, ["motionPackage"] = Motion, ["plan"] = plan, ["review"] = Recipe["review"]!.DeepClone() };
            var jobPath = stage.Attempt + "/job.json"; w.Save(jobPath, job); stage.Inputs[jobPath] = HashFile(jobPath);
            await native.Run(m.Blender, ["--factory-startup", "--background", "--disable-autoexec", "--python-exit-code", "1", "--python", w.Resolve(scripts + "/action.py"), "--", "--job", w.Resolve(jobPath)], w.Root, w.Resolve(stage.Attempt + "/process.log"), Budget["timeoutSeconds"]!.GetValue<int>(), cancellation, (long)Budget["maxLogBytes"]!.GetValue<double>());
            var result = LoadObject(stage.Attempt + "/result.json");
            if (Text(result, "schemaVersion") != "opencaw-action-stage/v1" || Text(result, "operation") != name || Text(result, "inputSha256") != HashFile(input)) throw new InvalidOperationException("Native action result does not match invoked operation/input");
            if (result["findings"] is not JsonArray findings) throw new InvalidOperationException("Native action findings are incomplete");
            foreach (var finding in findings)
            {
                var severity = Text(finding!.AsObject(), "severity").ToLowerInvariant();
                if (severity is not ("information" or "info" or "warning" or "review")) throw new InvalidOperationException("Native action finding is blocking or has unknown severity");
            }
            if (result["metrics"] is not JsonObject metrics || metrics.Count == 0) throw new InvalidOperationException("Native action metrics missing");
            if (name is "compose" or "export") ValidateActions(Array(result, "actions"), plan);
            var artifacts = result["artifacts"]?.AsObject() ?? throw new InvalidOperationException("Native action omitted artifacts");
            foreach (var pair in artifacts)
            {
                var value = Relative(w, pair.Value!.GetValue<string>());
                if (!value.StartsWith(stage.Attempt + "/", StringComparison.Ordinal)) throw new InvalidOperationException("Native artifact escapes immutable attempt");
                stage.Artifacts[pair.Key] = value;
            }
            string[] required = name switch { "inspect" => ["report"], "compose" => ["blend"], "export" => ["blend", "glb", "package", "verificationIndex", "verificationData", "verificationFrames"], "review" => ["review", "report", "reviewReport"], _ => throw new InvalidOperationException("Unknown stage") };
            foreach (var key in required) if (!stage.Artifacts.ContainsKey(key)) throw new InvalidOperationException("Native stage omitted " + key);
            if (name == "export") ValidateVerificationArtifacts(stage);
            foreach (var artifact in stage.Artifacts.Values)
                if (!File.Exists(w.Resolve(artifact))) throw new InvalidOperationException("Native stage declared a missing artifact: " + artifact);
            stage.Artifacts["result"] = stage.Attempt + "/result.json";
            if (name == "export")
            {
                var package = LoadObject(stage.Artifacts["package"]);
                foreach (var key in new[] { "schemaVersion", "asset", "version", "profile", "fps", "rig", "coordinateSystem", "sourceMotion", "anchors", "targets", "budgets", "motion", "engine" }) package[key] = plan[key]!.DeepClone();
                package["model"] = new JsonObject { ["path"] = stage.Artifacts["glb"], ["sha256"] = HashFile(stage.Artifacts["glb"]) };
                package["source"] = new JsonObject { ["path"] = stage.Artifacts["blend"], ["sha256"] = HashFile(stage.Artifacts["blend"]) };
                package["verification"] = new JsonObject { ["status"] = "pending", ["note"] = "Export does not create action, independent or human runtime acceptance" };
                ValidateActions(Array(package, "actions"), plan); w.Save(stage.Artifacts["package"], package); ValidatePackage(package, stage);
            }
            if (name == "review") ValidateReview(LoadObject(stage.Artifacts["reviewReport"]), stage, plan);
            var files = Directory.GetFiles(w.Resolve(stage.Attempt), "*", SearchOption.AllDirectories);
            if (files.Length > Budget["maxReviewFrames"]!.GetValue<int>() + 200) throw new InvalidOperationException("Native action output file budget exceeded");
            var verificationPrefix = stage.Attempt + "/verification/";
            if (files.Where(file => w.Relative(file).StartsWith(verificationPrefix, StringComparison.Ordinal)).Sum(file => new FileInfo(file).Length) > VerificationBytes(Budget))
                throw new InvalidOperationException("Native action verification spool exceeds maxVerificationBytes");
            foreach (var file in files)
            {
                var relative = w.Relative(file); ValidateArtifact(relative); stage.Outputs[relative] = HashFile(relative);
            }
            VerifyHashes(stage.Inputs); VerifyHashes(stage.ExternalInputs, true); VerifyHashes(m.Originals); VerifyHashes(m.SourceInputs);
            if (!JsonNode.DeepEquals(await engines.Resolve(cancellation), m.Engine)) throw new InvalidOperationException("Engine context changed during native action stage");
            stage.Status = "complete"; Save();
        }
        catch (Exception error)
        {
            stage.Status = "failed"; stage.Error = error.Message;
            m.History.Add(new JsonObject { ["event"] = "stage-failed", ["stage"] = name, ["state"] = System.Text.Json.JsonSerializer.SerializeToNode(stage, Workspace.Json) }); Save(); throw;
        }
    }
    static void ValidateActions(JsonArray actual, JsonObject plan)
    {
        Unique(actual, "id");
        var expected = Array(plan, "actions").Select(node => node!.AsObject()).ToDictionary(node => Text(node, "id"), StringComparer.Ordinal);
        if (actual.Count != expected.Count) throw new InvalidOperationException("Actual compound action inventory is incomplete");
        foreach (var action in actual.Select(node => node!.AsObject()))
        {
            if (!expected.TryGetValue(Text(action, "id"), out var target)) throw new InvalidOperationException("Unexpected actual compound action");
            Hash(Text(action, "motionSha256"));
            if (Math.Abs(Number(action, "duration", .000001, 3600) - target["duration"]!.GetValue<double>()) > 1e-5) throw new InvalidOperationException("Native action duration differs from compiled sequence");
            foreach (var key in new[] { "role", "clip", "steps", "cues", "markers" }) if (!JsonNode.DeepEquals(action[key], target[key])) throw new InvalidOperationException("Native action changed compiled " + key);
        }
    }
    static void ValidateVerificationArtifacts(Stage stage)
    {
        foreach (var (role, file) in new[] { ("verificationIndex", "index.json"), ("verificationData", "poses.bin"), ("verificationFrames", "frames.jsonl") })
            if (!stage.Artifacts.TryGetValue(role, out var path) || path != stage.Attempt + "/verification/" + file)
                throw new InvalidOperationException("Action verification artifact role must name its exact immutable file: " + role);
    }
    void ValidatePackage(JsonObject package, Stage stage)
    {
        ValidateVerificationArtifacts(stage);
        var plan = Plan(); ValidateActions(Array(package, "actions"), plan);
        if (Text(package, "schemaVersion") != "opencaw-action-package/v1") throw new InvalidOperationException("Unsupported action package");
        foreach (var key in new[] { "asset", "version", "profile", "fps", "rig", "coordinateSystem", "sourceMotion", "anchors", "targets", "budgets", "motion", "engine" })
            if (!JsonNode.DeepEquals(package[key], plan[key])) throw new InvalidOperationException("Action package differs from source plan: " + key);
        foreach (var pair in new[] { ("model", "glb"), ("source", "blend") })
            if (Text(package[pair.Item1]!.AsObject(), "path") != stage.Artifacts[pair.Item2] || Text(package[pair.Item1]!.AsObject(), "sha256") != HashFile(stage.Artifacts[pair.Item2])) throw new InvalidOperationException("Action package file identity mismatch");
        if (new FileInfo(w.Resolve(stage.Artifacts["glb"])).Length > Budget["maxRuntimeBytes"]!.GetValue<long>()) throw new InvalidOperationException("Action GLB exceeds runtime budget");
        var glb = Glb(w.Resolve(stage.Artifacts["glb"]));
        var names = Array(glb, "animations").Select(node => Text(node!.AsObject(), "name")).ToHashSet(StringComparer.Ordinal);
        if (!names.SetEquals(Array(package, "actions").Select(node => Text(node!.AsObject(), "clip")))) throw new InvalidOperationException("Runtime GLB must contain exact composite animation names");
        var nodeNames = Array(glb, "nodes").Where(node => node?["name"] is not null).Select(node => node!["name"]!.GetValue<string>()).ToArray();
        foreach (var anchor in Array(package, "anchors").Select(node => node!.AsObject()))
            if (nodeNames.Count(name => name == Text(anchor, "node")) != 1) throw new InvalidOperationException("Exported action anchor is missing or ambiguous");
        if (m.Profile == "skinned" && (glb["skins"] is not JsonArray skins || skins.Count == 0)) throw new InvalidOperationException("Exported skinned action has no actual skin");
    }
    void ValidateReview(JsonObject report, Stage stage, JsonObject plan)
    {
        var count = Integer(report, "frameCount", 1, Budget["maxReviewFrames"]!.GetValue<int>());
        if (Integer(report, "requestedFrameCount", 1, Budget["maxReviewFrames"]!.GetValue<int>()) != count || Text(report, "humanApproval") != "pending") throw new InvalidOperationException("Technical sequence review is incomplete or manufactures human approval");
        var packets = Array(report, "packets");
        Unique(packets, "id");
        var names = packets.Select(node => Text(node!.AsObject(), "id")).ToHashSet(StringComparer.Ordinal);
        if (!names.SetEquals(Array(plan, "actions").Select(node => Text(node!.AsObject(), "id")))) throw new InvalidOperationException("Technical review omits compound action");
        var frames = packets.SelectMany(node => Array(node!.AsObject(), "frames")).Select(node => node!.AsObject()).ToArray();
        if (frames.Length != count || frames.Select(node => Text(node, "path")).Distinct(StringComparer.Ordinal).Count() != count) throw new InvalidOperationException("Technical review frame identities are duplicated/incomplete");
        foreach (var frame in frames)
        {
            var file = Relative(w, Text(frame, "path"));
            if (!file.StartsWith(stage.Attempt + "/", StringComparison.Ordinal) || !file.EndsWith(".png", StringComparison.OrdinalIgnoreCase) || HashFile(file) != Text(frame, "sha256")) throw new InvalidOperationException("Technical review frame is stale/escaped");
            Number(frame, "time", 0, 3600);
        }
        var review = Recipe["review"]!.AsObject(); var fps = review["fps"]!.GetValue<double>();
        var cameras = Array(review, "cameras").Select(node => node!.GetValue<string>()).ToArray();
        foreach (var action in Array(plan, "actions").Select(node => node!.AsObject()))
        {
            var duration = action["duration"]!.GetValue<double>(); var times = new List<double> { 0, duration };
            for (var index = 0; index <= Math.Ceiling(duration * fps); index++) times.Add(Math.Min(duration, index / fps));
            foreach (var step in Array(action, "steps")) { times.Add(step!["start"]!.GetValue<double>()); times.Add(step["end"]!.GetValue<double>()); }
            foreach (var cue in Array(action, "cues")) { times.Add(cue!["start"]!.GetValue<double>()); times.Add(cue["end"]!.GetValue<double>()); }
            foreach (var marker in Array(action, "markers")) times.Add(marker!["at"]!.GetValue<double>());
            var packet = packets.Single(node => Text(node!.AsObject(), "id") == Text(action, "id"))!.AsObject();
            var samples = Array(packet, "frames").Select(node => node!.AsObject()).ToArray();
            foreach (var camera in cameras)
                foreach (var time in times)
                    if (!samples.Any(sample => (sample["camera"]?.GetValue<string>() ?? sample["view"]?.GetValue<string>()) == camera && Math.Abs(sample["time"]!.GetValue<double>() - time) < 1e-5)) throw new InvalidOperationException("Technical review omits a required camera/time boundary sample");
        }
    }
    void ValidateArtifact(string relative)
    {
        var file = w.Resolve(relative); var info = new FileInfo(file);
        if (!info.Exists || info.Length == 0) throw new InvalidOperationException("Missing/empty native action output: " + relative);
        switch (info.Extension.ToLowerInvariant())
        {
            case ".json": _ = LoadObject(relative); break;
            case ".glb": if (info.Length > Budget["maxRuntimeBytes"]!.GetValue<long>()) throw new InvalidOperationException("GLB output exceeds byte budget"); _ = Glb(file); break;
            case ".blend": using (var stream = File.OpenRead(file)) { var header = new byte[7]; if (stream.Read(header) != 7 || System.Text.Encoding.ASCII.GetString(header) != "BLENDER") throw new InvalidOperationException("Invalid editable Blender output"); } break;
            case ".png": using (var stream = File.OpenRead(file)) { var header = new byte[8]; if (stream.Read(header) != 8 || !header.SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })) throw new InvalidOperationException("Invalid review PNG"); } break;
            case ".html": var text = File.ReadAllText(file); if (!text.Contains("<html", StringComparison.OrdinalIgnoreCase) && !text.Contains("<!doctype", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Invalid technical review HTML"); break;
            case ".py": if (!m.Stages.Values.Any(stage => stage.Inputs.ContainsKey(relative))) throw new InvalidOperationException("Unexpected executable script in action output"); break;
            case ".blend1":
            case ".log":
            case ".txt":
            case ".md": break;
            case ".bin":
            case ".jsonl":
                if (!m.Stages.TryGetValue("export", out var stage) || stage.Status != "running" ||
                    relative != stage.Attempt + "/verification/" + (info.Extension.Equals(".bin", StringComparison.OrdinalIgnoreCase) ? "poses.bin" : "frames.jsonl") ||
                    info.Length > VerificationBytes(Budget))
                    throw new InvalidOperationException("Unexpected or over-budget action verification payload");
                if (info.Extension.Equals(".bin", StringComparison.OrdinalIgnoreCase))
                {
                    using var stream = File.OpenRead(file);
                    var signature = System.Text.Encoding.ASCII.GetBytes("OPENCAW-POSE-V1\0\0");
                    var header = new byte[signature.Length];
                    if (stream.Read(header) != header.Length || !header.SequenceEqual(signature))
                        throw new InvalidOperationException("Invalid action verification binary header");
                }
                break;
            default: throw new InvalidOperationException("Unexpected native output type: " + info.Extension);
        }
    }
}
