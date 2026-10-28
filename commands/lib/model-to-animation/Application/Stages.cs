using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAnimation.Domain;
using static OpenCaw.ModelAnimation.Application.MotionValidation;
namespace OpenCaw.ModelAnimation.Application;

public sealed partial class Pipeline
{
    async Task CheckBlender(string directory, CancellationToken cancellation)
    {
        var log = directory + "/blender-version.log";
        await native.Run(m.Blender, ["--version"], w.Root, w.Resolve(log), Math.Min(30, Budget["timeoutSeconds"]!.GetValue<int>()), cancellation, (long)Budget["maxLogBytes"]!.GetValue<double>());
        var version = File.ReadAllText(w.Resolve(log)).Replace("stdout: ", "").Replace("stderr: ", "");
        if (!Regex.IsMatch(version, @"Blender\s+4\.5(?:\.\d+)?\b"))
            throw new InvalidOperationException("Existing Blender4.5LTS required; no fallback or installation");
        if (w.HashFile(m.Blender) != m.BlenderSha256)
            throw new InvalidOperationException("Blender changed during version inspection");
    }
    async Task RunStage(string name, string operation, CancellationToken cancellation)
    {
        var limit = Budget["maxAttempts"]!.GetValue<int>();
        if (m.History.Count(item => item["event"]?.GetValue<string>() == "stage-start" && item["stage"]?.GetValue<string>() == name) >= limit)
            throw new InvalidOperationException("Stage attempt budget exhausted; select a new version/explicit budget");
        var index = System.Array.IndexOf(Order, name);
        var effectiveRecipe = Recipe;
        Stage? priorMotion = null;
        JsonObject? revision = null;
        if (options.ContainsKey("revision"))
        {
            if (operation != "author")
                throw new InvalidOperationException("Targeted motion revisions use author --revision; no provider fallback");
            priorMotion = RevisionBase();
            VerifyHashes(priorMotion.Inputs);
            VerifyHashes(priorMotion.Outputs);
            VerifyHashes(priorMotion.ExternalInputs, true);
            revision = LoadObject(Relative(w, Need("revision")));
            Fields(revision, "schemaVersion", "clip", "replacement", "reason");
            if (revision["schemaVersion"]?.GetValue<int>() != 1 || Text(revision, "reason").Length < 8 || revision["replacement"] is not JsonObject replacement)
                throw new InvalidOperationException("Revision requires schema1, existing clip replacement and substantive reason");
            var clip = Text(revision, "clip");
            if (Text(replacement, "id") != clip)
                throw new InvalidOperationException("Revision cannot rename the selected clip");
            var selected = Array(effectiveRecipe, "clips").Select((node, position) => (Node: node!.AsObject(), Position: position)).Where(item => Text(item.Node, "id") == clip).ToArray();
            if (selected.Length != 1)
                throw new InvalidOperationException("Revision must target exactly one existing clip");
            effectiveRecipe["clips"]![selected[0].Position] = replacement.DeepClone();
            MotionValidation.Recipe(effectiveRecipe);
        }
        var stage = new Stage { Operation = operation, Attempt = m.Staging + "/attempts/" + name + "-" + Guid.NewGuid().ToString("N") };
        var inputs = m.Originals.Concat(m.SourceInputs).Concat(m.Stages.Where(pair => System.Array.IndexOf(Order, pair.Key) < index && pair.Value.Status == "complete").SelectMany(pair => pair.Value.Outputs));
        stage.Inputs = inputs.GroupBy(pair => pair.Key).ToDictionary(group => group.Key, group => group.First().Value, StringComparer.Ordinal);
        if (index > System.Array.IndexOf(Order, "rig"))
        {
            var selected = m.Approvals.Last(a => a.Kind == "rig" && a.Fingerprint == Fingerprint("rig") && HashFile(a.Evidence) == a.EvidenceHash);
            stage.Inputs[selected.Evidence] = selected.EvidenceHash;
        }
        if (priorMotion is not null)
        {
            foreach (var pair in priorMotion.Inputs.Concat(priorMotion.Outputs))
                stage.Inputs[pair.Key] = pair.Value;
            stage.Inputs[Relative(w, Need("revision"))] = HashFile(Need("revision"));
        }
        stage.ExternalInputs = new(m.BaselineInputs, StringComparer.Ordinal)
        {
            [m.Blender] = m.BlenderSha256
        };
        if (priorMotion is not null)
            foreach (var pair in priorMotion.ExternalInputs)
                stage.ExternalInputs[pair.Key] = pair.Value;
        if (operation == "retarget")
        {
            var motion = Relative(w, Need("motion-source"));
            _ = MotionValidation.Glb(w.Resolve(motion));
            var mapping = Relative(w, Need("mapping"));
            var map = LoadObject(mapping);
            NoExcludedProviders(map);
            if (Text(map, "provider") is not ("owned" or "licensed-library") || map["rights"]?["authorized"]?.GetValue<bool>() != true || string.IsNullOrWhiteSpace(map["rights"]?["license"]?.GetValue<string>()))
                throw new InvalidOperationException("Retarget source requires explicit owned/licensed-library provenance, rights and license");
            stage.Inputs[motion] = HashFile(motion);
            stage.Inputs[mapping] = HashFile(mapping);
        }
        Directory.CreateDirectory(w.Resolve(stage.Attempt));
        if (m.Stages.TryGetValue(name, out var previous))
        {
            if (name == "motion" && previous.Status == "complete")
                m.LastSuccessfulMotion = CopyStage(previous);
            if (previous.Status == "running")
                RecordAttempt("stage-interrupted", name, previous);
        }
        if (index < System.Array.IndexOf(Order, "motion"))
            m.LastSuccessfulMotion = null;
        m.Stages[name] = stage;
        foreach (var later in Order.Skip(index + 1))
            m.Stages.Remove(later);
        m.Approvals.RemoveAll(a => name is "inspect" or "prepare" or "rig" || a.Kind != "rig");
        m.History.Add(new()
        {
            ["event"] = "stage-start",
            ["stage"] = name,
            ["operation"] = operation,
            ["attempt"] = stage.Attempt,
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("O")
        });
        Save();
        try
        {
            cancellation.ThrowIfCancellationRequested();
            var bundle = CopyBundle(stage);
            await CheckBlender(stage.Attempt, cancellation);
            var input = priorMotion is not null ? priorMotion.Artifacts["blend"] : name == "inspect" || name == "prepare" ? m.Model : name == "review" ? Artifact("export", "glb") : Artifact(Order[index - 1], "blend");
            if (name == "motion")
            {
                var effectivePath = stage.Attempt + "/effective-recipe.json";
                w.Save(effectivePath, effectiveRecipe);
                stage.Artifacts["recipe"] = effectivePath;
                stage.Inputs[effectivePath] = HashFile(effectivePath);
                if (revision is not null)
                {
                    var revisionPath = stage.Attempt + "/clip-revision.json";
                    w.Save(revisionPath, revision);
                    stage.Artifacts["revision"] = revisionPath;
                    stage.Inputs[revisionPath] = HashFile(revisionPath);
                }
            }
            JsonNode? motionSource = null, mapping = null;
            if (operation == "retarget")
            {
                var target = stage.Attempt + "/motion-source.glb";
                File.Copy(w.Resolve(Need("motion-source")), w.Resolve(target), false);
                stage.Artifacts["motionSource"] = target;
                var mapped = stage.Attempt + "/mapping.json";
                File.Copy(w.Resolve(Need("mapping")), w.Resolve(mapped), false);
                stage.Artifacts["mapping"] = mapped;
                motionSource = target;
                mapping = LoadObject(mapped);
            }
            var job = new JsonObject { ["schemaVersion"] = 1, ["root"] = w.Root, ["operation"] = operation, ["input"] = input, ["outputDir"] = stage.Attempt, ["result"] = stage.Attempt + "/result.json", ["asset"] = m.Asset, ["version"] = m.Version, ["profile"] = m.Profile, ["recipe"] = effectiveRecipe, ["motionSource"] = motionSource, ["mapping"] = mapping };
            if (revision is not null)
                job["revisionClip"] = Text(revision, "clip");
            var jobPath = stage.Attempt + "/job.json";
            w.Save(jobPath, job);
            stage.Inputs[jobPath] = HashFile(jobPath);
            await native.Run(m.Blender, ["--factory-startup", "--background", "--disable-autoexec", "--python-exit-code", "1", "--python", w.Resolve(bundle + "/motion.py"), "--", "--job", w.Resolve(jobPath)], w.Root, w.Resolve(stage.Attempt + "/process.log"), Budget["timeoutSeconds"]!.GetValue<int>(), cancellation, (long)Budget["maxLogBytes"]!.GetValue<double>());
            var result = LoadObject(stage.Attempt + "/result.json");
            if (Text(result, "schemaVersion") != "opencaw-motion-stage/v1" || Text(result, "operation") != operation || Text(result, "profile") != m.Profile || Text(result, "inputSha256") != HashFile(input))
                throw new InvalidOperationException("Native stage report does not match invocation/input");
            if (result["findings"] is not JsonArray findings || findings.Any(item => item?["severity"]?.GetValue<string>() is "fatal" or "error" or "blocking"))
                throw new InvalidOperationException("Native stage has blocking or incomplete findings");
            var artifacts = result["artifacts"]?.AsObject() ?? throw new InvalidOperationException("Native stage has no artifacts");
            foreach (var pair in artifacts)
            {
                var value = Relative(w, pair.Value!.GetValue<string>());
                if (!value.StartsWith(stage.Attempt + "/", StringComparison.Ordinal))
                    throw new InvalidOperationException("Native artifact escapes its immutable attempt");
                stage.Artifacts[pair.Key] = value;
            }
            string[] required = name switch
            {
                "inspect" => ["report"],
                "export" => ["blend", "glb", "package"],
                "review" => ["review", "report"],
                _ => ["blend"]
            };
            foreach (var key in required)
                if (!stage.Artifacts.ContainsKey(key))
                    throw new InvalidOperationException("Native stage omitted " + key);
            stage.Artifacts["result"] = stage.Attempt + "/result.json";
            if (name == "export")
            {
                var package = LoadObject(stage.Artifacts["package"]);
                package["engine"] = m.Engine.DeepClone();
                package["ancestry"] = new JsonObject { ["model"] = m.Model, ["modelSha256"] = HashFile(m.Model), ["recipeSha256"] = HashFile(m.Recipe), ["effectiveRecipeSha256"] = m.EffectiveRecipeSha256, ["rightsSha256"] = HashFile(m.Rights), ["rigFingerprint"] = Fingerprint("rig") };
                package["verification"] = new JsonObject { ["status"] = "pending", ["note"] = "Native export does not establish human or runtime acceptance" };
                w.Save(stage.Artifacts["package"], package);
                ValidatePackage(package, stage);
            }
            var files = Directory.GetFiles(w.Resolve(stage.Attempt), "*", SearchOption.AllDirectories);
            if (files.Length > Budget["maxPreviewFrames"]!.GetValue<int>() + 200)
                throw new InvalidOperationException("Native output file budget exceeded");
            foreach (var file in files)
            {
                var relative = w.Relative(file);
                ValidateArtifact(relative);
                stage.Outputs[relative] = HashFile(relative);
            }
            VerifyHashes(stage.Inputs);
            VerifyHashes(stage.ExternalInputs, true);
            VerifyHashes(m.Originals);
            VerifyHashes(m.SourceInputs);
            var engine = await engines.Resolve(cancellation);
            if (!JsonNode.DeepEquals(engine, m.Engine))
                throw new InvalidOperationException("Engine context changed during native stage");
            if (stage.Outputs.Count == 0)
                throw new InvalidOperationException("Native stage emitted no output");
            if (name == "motion")
            {
                var previousRecipe = m.EffectiveRecipeSha256;
                m.EffectiveRecipe = stage.Artifacts["recipe"];
                m.EffectiveRecipeSha256 = HashFile(m.EffectiveRecipe);
                var hashes = new JsonObject();
                foreach (var clip in Array(effectiveRecipe, "clips").Select(node => node!.AsObject()))
                    hashes[Text(clip, "id")] = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(clip.ToJsonString())));
                m.History.Add(new JsonObject { ["event"] = revision is null ? "motion-recipe" : "motion-revision", ["clip"] = revision?["clip"]?.DeepClone(), ["reason"] = revision?["reason"]?.DeepClone(), ["previousRecipeSha256"] = previousRecipe, ["effectiveRecipe"] = m.EffectiveRecipe, ["effectiveRecipeSha256"] = m.EffectiveRecipeSha256, ["clipDefinitionHashes"] = hashes });
            }
            stage.Status = "complete";
            if (name == "motion")
                m.LastSuccessfulMotion = CopyStage(stage);
            Save();
        }
        catch (Exception e)
        {
            stage.Status = "failed";
            stage.Error = e.Message;
            RecordAttempt("stage-failed", name, stage);
            Save();
            throw;
        }
    }
    Stage RevisionBase()
    {
        var previous = m.Stages.GetValueOrDefault("motion");
        var candidate = previous?.Status == "complete" ? previous : m.LastSuccessfulMotion;
        if (candidate is null || candidate.Status != "complete")
            throw new InvalidOperationException("Complete motion first; no successful motion exists for targeted revision recovery");
        if (!candidate.Artifacts.TryGetValue("recipe", out var recipe) || recipe != m.EffectiveRecipe || !candidate.Outputs.TryGetValue(recipe, out var recipeHash) || recipeHash != m.EffectiveRecipeSha256 || !candidate.Artifacts.TryGetValue("blend", out var blend) || !candidate.Outputs.ContainsKey(blend))
            throw new InvalidOperationException("Prior motion no longer matches the current successful recipe/source");
        return candidate;
    }
    static Stage CopyStage(Stage stage) => new()
    {
        Status = stage.Status,
        Operation = stage.Operation,
        Attempt = stage.Attempt,
        Error = stage.Error,
        Inputs = new(stage.Inputs, StringComparer.Ordinal),
        ExternalInputs = new(stage.ExternalInputs, StringComparer.Ordinal),
        Outputs = new(stage.Outputs, StringComparer.Ordinal),
        Artifacts = new(stage.Artifacts, StringComparer.Ordinal)
    };
    void RecordAttempt(string reason, string name, Stage stage)
    {
        m.History.Add(new JsonObject
        {
            ["event"] = reason,
            ["stage"] = name,
            ["attempt"] = stage.Attempt,
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("O"),
            ["state"] = System.Text.Json.JsonSerializer.SerializeToNode(stage, Workspace.Json)
        });
    }
    string CopyBundle(Stage stage)
    {
        var directory = Path.Combine(Baseline, ".styles/.workflows/model-to-animation/blender");
        var manifest = Path.Combine(directory, "scripts.json");
        if (!File.Exists(manifest))
            throw new InvalidOperationException("Missing audited motion script manifest");
        RejectLinks(directory);
        var spec = JsonNode.Parse(File.ReadAllText(manifest))!.AsObject();
        if (spec["schemaVersion"]?.GetValue<int>() != 1 || spec["files"] is not JsonObject files || files.Count is < 1 or > 20 || files["motion.py"] is null)
            throw new InvalidOperationException("Invalid audited script inventory");
        var destination = stage.Attempt + "/scripts";
        Directory.CreateDirectory(w.Resolve(destination));
        stage.ExternalInputs[manifest] = w.HashFile(manifest);
        foreach (var pair in files)
        {
            if (!Regex.IsMatch(pair.Key, "^[a-z][a-z0-9_]*\\.py$"))
                throw new InvalidOperationException("Script manifest must contain fixed local Python basenames");
            var source = Path.Combine(directory, pair.Key);
            RejectLinks(source);
            var expected = pair.Value!.GetValue<string>();
            MotionValidation.Hash(expected);
            if (!File.Exists(source) || w.HashFile(source) != expected)
                throw new InvalidOperationException("Audited Blender script changed: " + pair.Key);
            var target = destination + "/" + pair.Key;
            File.Copy(source, w.Resolve(target), false);
            if (HashFile(target) != expected)
                throw new InvalidOperationException("Script copy hash mismatch");
            stage.ExternalInputs[source] = expected;
            stage.Inputs[target] = expected;
        }
        return destination;
    }
    static void RejectLinks(string path)
    {
        var current = new FileInfo(Path.GetFullPath(path));
        for (FileSystemInfo? item = current; item is not null; item = item is FileInfo info ? info.Directory : ((DirectoryInfo)item).Parent)
            if (item.Exists && (item.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Audited tool scripts cannot traverse links");
    }
    void ValidateArtifact(string relative)
    {
        var file = w.Resolve(relative);
        var info = new FileInfo(file);
        if (!info.Exists || info.Length == 0)
            throw new InvalidOperationException("Missing/empty artifact: " + relative);
        if (info.Length > 64L * 1024 * 1024 * 1024)
            throw new InvalidOperationException("Artifact byte budget exceeded");
        var extension = Path.GetExtension(file).ToLowerInvariant();
        if (extension == ".glb")
            _ = MotionValidation.Glb(file, (long)Budget["maxRuntimeBytes"]!.GetValue<double>());
        if (extension == ".blend")
        {
            using var stream = File.OpenRead(file);
            var header = new byte[7];
            if (stream.Read(header) != 7 || !header.SequenceEqual("BLENDER"u8.ToArray()))
                throw new InvalidOperationException("Invalid editable Blender source");
        }
        if (extension == ".json")
            _ = LoadObject(relative);
    }
    void ValidatePackage(JsonObject package, Stage stage)
    {
        if (Text(package, "schemaVersion") != "opencaw-motion-package/v1" || Text(package, "profile") != m.Profile)
            throw new InvalidOperationException("Wrong motion package profile/schema");
        NoExcludedProviders(package);
        foreach (var key in new[] { "coordinateSystem", "rig", "provenance", "budgets" })
            if (package[key] is not JsonObject)
                throw new InvalidOperationException("Package omitted structured " + key);
        if (!JsonNode.DeepEquals(package["budgets"], Recipe["budgets"]))
            throw new InvalidOperationException("Export changed production budgets");
        foreach (var key in new[] { "model", "source" })
        {
            var item = package[key]!.AsObject();
            var file = Relative(w, Text(item, "path"));
            var expected = Text(item, "sha256");
            MotionValidation.Hash(expected);
            if (!file.StartsWith(stage.Attempt + "/", StringComparison.Ordinal) || HashFile(file) != expected)
                throw new InvalidOperationException("Package source/model hash or lineage mismatch");
            if (file != stage.Artifacts[key == "model" ? "glb" : "blend"])
                throw new InvalidOperationException("Package substituted an export artifact");
        }
        var glb = MotionValidation.Glb(w.Resolve(stage.Artifacts["glb"]), (long)Budget["maxRuntimeBytes"]!.GetValue<double>());
        if (m.Profile == "skinned" && (glb["skins"] is not JsonArray skins || !skins.Any(skin => skin?["joints"] is JsonArray joints && joints.Count > 0)))
            throw new InvalidOperationException("Skinned package has no actual exported skin");
        var exported = (glb["animations"]?.AsArray() ?? []).Select(node => node!.AsObject()).ToArray();
        var clips = Array(package, "clips").Select(node => node!.AsObject()).ToArray();
        var ids = clips.Select(clip => Text(clip, "id")).ToArray();
        if (ids.Distinct(StringComparer.Ordinal).Count() != ids.Length || Array(Recipe, "requiredClips").Any(id => !ids.Contains(id!.GetValue<string>())))
            throw new InvalidOperationException("Package omitted or duplicated required motion");
        foreach (var clip in clips)
        {
            Number(clip, "duration", .0001, Budget["maxClipSeconds"]!.GetValue<double>());
            var declared = Array(Recipe, "clips").Select(node => node!.AsObject()).SingleOrDefault(item => Text(item, "id") == Text(clip, "id")) ?? throw new InvalidOperationException("Export declared an unrequested clip");
            if (Text(clip, "role") != Text(declared, "role") || !JsonNode.DeepEquals(clip["loop"], declared["loop"]) || Text(clip, "rootMotion") != Text(declared, "rootMotion"))
                throw new InvalidOperationException("Export changed clip semantics");
            var action = clip["action"]?.GetValue<string>() ?? Text(clip, "id");
            var matches = exported.Where(item => item["name"]?.GetValue<string>() == action || item["name"]?.GetValue<string>() == Text(clip, "id")).ToArray();
            if (matches.Length != 1 || matches[0]["channels"] is not JsonArray channels || channels.Count == 0 || matches[0]["samplers"] is not JsonArray samplers || samplers.Count == 0)
                throw new InvalidOperationException("Declared clip is not a real uniquely bound GLB animation: " + action);
        }
        var anchors = Array(package, "anchors").Select(node => node!.AsObject()).ToArray();
        var prescribed = Array(Recipe, "anchors").Select(node => node!.AsObject()).ToArray();
        if (anchors.Length != prescribed.Length)
            throw new InvalidOperationException("Export changed anchor inventory");
        var nodeNames = (glb["nodes"]?.AsArray() ?? []).Select(node => node?["name"]?.GetValue<string>()).ToHashSet(StringComparer.Ordinal);
        foreach (var anchor in prescribed)
        {
            var id = Text(anchor, "id");
            var matches = anchors.Where(item => Text(item, "id") == id).ToArray();
            if (matches.Length != 1 || Text(matches[0], "node") != "anchor." + id || Text(matches[0], "parent") != Text(anchor, "node") || !JsonNode.DeepEquals(matches[0]["position"], anchor["position"]) || !nodeNames.Contains(Text(matches[0], "node")))
                throw new InvalidOperationException("Export changed anchor identity, ownership or physical node: " + id);
        }
        foreach (var key in new[] { "parameters", "states", "transitions", "effects" })
            if (!JsonNode.DeepEquals(package[key], Recipe[key]))
                throw new InvalidOperationException("Export changed semantic runtime binding: " + key);
        if (package["engine"] is not null && !JsonNode.DeepEquals(package["engine"], m.Engine))
            throw new InvalidOperationException("Package conflicts with effective engine");
    }
}
