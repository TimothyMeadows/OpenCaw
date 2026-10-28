using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAction.Domain;
using static OpenCaw.ModelAction.Application.ActionValidation;
namespace OpenCaw.ModelAction.Application;

public sealed partial class Pipeline(IWorkspace w, Dictionary<string, string> options, INativeProcess native, IEngineResolver engines)
{
    static readonly string[] Order = ["inspect", "compose", "export", "review"];
    Manifest m = new(); string path = "";
    string Need(string key) => options.GetValueOrDefault(key) ?? throw new InvalidOperationException("Missing --" + key);
    string Baseline => Path.GetFullPath(Need("baseline-root"));
    string State => Path.GetDirectoryName(path)!.Replace('\\', '/');
    string TaskPrefix => ".opencaw/.cache/tasks/" + m.Task + "/";
    string HashFile(string value) => w.HashFile(w.Resolve(value));
    JsonObject LoadObject(string value)
    {
        var file = w.Resolve(value);
        if (!File.Exists(file) || new FileInfo(file).Length is < 2 or > 8 * 1024 * 1024) throw new InvalidOperationException("Missing/oversized JSON input: " + value);
        return w.Load<JsonObject>(value);
    }
    JsonObject Recipe => LoadObject(m.Recipe);
    JsonObject Motion => LoadObject(m.Motion);
    JsonObject Budget => Recipe["budgets"]!.AsObject();
    void Save()
    {
        w.Save(path, m);
        AuditJournal.Append(w, State + "/audit.jsonl", new { timestamp = DateTimeOffset.UtcNow, type = "state", asset = m.Asset, manifest = path, stages = m.Stages.ToDictionary(pair => pair.Key, pair => pair.Value.Status) });
    }
    void CheckLayout()
    {
        if (m.SchemaVersion != "opencaw-model-action/v1") throw new InvalidOperationException("Unsupported action manifest");
        Id(m.Task); Id(m.Asset); Id(m.Version);
        if (path != $"{TaskPrefix}model-to-action/{m.Asset}/{m.Version}/manifest.json" || m.Staging != $".art-staging/model-to-action/{m.Asset}/{m.Version}") throw new InvalidOperationException("Action state violates repository-local layout");
        foreach (var input in new[] { m.Model, m.Motion, m.Recipe, m.SourceReview, m.EngineReceipt }.Concat(m.Originals.Keys))
            if (!Relative(w, input).StartsWith(m.Staging + "/original/", StringComparison.Ordinal)) throw new InvalidOperationException("Original ancestry escapes its asset");
        foreach (var (name, stage) in m.Stages)
        {
            if (!Order.Contains(name) || stage.Status is not ("running" or "failed" or "complete") || !Relative(w, stage.Attempt).StartsWith(m.Staging + "/attempts/" + name + "-", StringComparison.Ordinal)) throw new InvalidOperationException("Invalid action stage layout/status");
            foreach (var artifact in stage.Artifacts.Values) if (!Relative(w, artifact).StartsWith(stage.Attempt + "/", StringComparison.Ordinal)) throw new InvalidOperationException("Stage artifact escapes attempt");
        }
        foreach (var approval in m.Approvals) RequireEvidence(approval.Evidence);
    }
    void RequireEvidence(string value)
    {
        if (!Relative(w, value).StartsWith(TaskPrefix, StringComparison.Ordinal)) throw new InvalidOperationException("Review evidence must remain in its active task cache");
    }
    void VerifyHashes(IEnumerable<KeyValuePair<string, string>> values, bool external = false)
    {
        foreach (var (name, expected) in values)
        {
            Hash(expected);
            var file = external ? name : w.Resolve(name);
            if (!File.Exists(file) || w.HashFile(file) != expected) throw new InvalidOperationException("Changed/missing bound evidence: " + name + "; use a fresh version or rerun the affected stage");
        }
    }
    Stage Require(string name) => m.Stages.TryGetValue(name, out var stage) && stage.Status == "complete" ? stage : throw new InvalidOperationException("Complete " + name + " first");
    string Artifact(string name, string kind) => Require(name).Artifacts.GetValueOrDefault(kind) ?? throw new InvalidOperationException("Stage omitted " + kind);
    JsonObject Plan()
    {
        var plan = ActionCompiler.Compile(Recipe, Motion, m.Asset, m.Version);
        plan["engine"] = m.Engine.DeepClone();
        plan["motion"] = new JsonObject { ["path"] = m.Motion, ["sha256"] = HashFile(m.Motion) };
        plan["sourceMotion"]!["packageSha256"] = HashFile(m.Motion);
        plan["sourceMotion"]!["modelSha256"] = HashFile(m.Model);
        plan["sourceMotion"]!["rights"] = LoadObject(m.SourceReview)["rights"]!.DeepClone();
        plan["sourceMotion"]!["sourceReviewSha256"] = HashFile(m.SourceReview);
        return plan;
    }
    void SourceApproval(JsonObject source, JsonObject plan, string packageHash, string modelHash)
    {
        NoExcludedOrigins(source);
        if (source["rights"] is not JsonObject rights || rights["authorized"]?.GetValue<bool>() != true || string.IsNullOrWhiteSpace(Text(rights, "license"))) throw new InvalidOperationException("Source model and used clips require explicit authorized rights and license evidence");
        if (source["schemaVersion"]?.GetValue<int>() != 1 || Text(source, "kind") != "source-motion" || Text(source, "decision") != "approved" || source["human"]?.GetValue<bool>() != true || Text(source, "reason").Length < 8 || string.IsNullOrWhiteSpace(Text(source, "reviewer"))) throw new InvalidOperationException("Explicit human source-motion review required");
        if (Text(source, "motionPackageSha256") != packageHash || Text(source, "modelSha256") != modelHash || Text(source, "rigId") != Text(plan["rig"]!.AsObject(), "id")) throw new InvalidOperationException("Source review does not bind current motion/model/rig");
        Unique(Array(source, "clips"), "id");
        var reviewed = Array(source, "clips").Select(node => node!.AsObject()).ToDictionary(node => Text(node, "id"), StringComparer.Ordinal);
        foreach (var clip in plan["sourceMotion"]!["clips"]!.AsArray().Select(node => node!.AsObject()))
            if (!reviewed.TryGetValue(Text(clip, "id"), out var item) || Text(item, "motionSha256") != Text(clip, "motionSha256")) throw new InvalidOperationException("Every used source clip needs its exact reviewed motion hash");
    }
    async Task Fresh(string? rerun, CancellationToken cancellation)
    {
        VerifyHashes(m.Originals); VerifyHashes(m.SourceInputs); VerifyHashes(m.BaselineInputs, true);
        if (!File.Exists(m.Blender) || w.HashFile(m.Blender) != m.BlenderSha256) throw new InvalidOperationException("Configured Blender binary changed");
        var selection = await engines.Resolve(cancellation);
        if (!JsonNode.DeepEquals(selection, m.Engine) || !JsonNode.DeepEquals(LoadObject(m.EngineReceipt), m.Engine)) throw new InvalidOperationException("Engine selection/context changed; initialize a fresh version");
        SourceApproval(LoadObject(m.SourceReview), Plan(), HashFile(m.Motion), HashFile(m.Model));
        var stop = System.Array.IndexOf(Order, rerun);
        foreach (var (name, stage) in m.Stages.Where(pair => stop < 0 || System.Array.IndexOf(Order, pair.Key) < stop))
            if (stage.Status == "complete") { VerifyHashes(stage.Inputs); VerifyHashes(stage.Outputs); VerifyHashes(stage.ExternalInputs, true); }
    }
    string Fingerprint()
    {
        var inputs = m.Originals.Concat(m.SourceInputs).Concat(m.Stages.Where(pair => pair.Value.Status == "complete").SelectMany(pair => pair.Value.Outputs))
            .GroupBy(pair => pair.Key).Select(group => group.First()).OrderBy(pair => pair.Key, StringComparer.Ordinal).ToArray();
        VerifyHashes(inputs); VerifyHashes(m.BaselineInputs, true);
        var value = string.Join("\n", inputs.Select(pair => pair.Key + ":" + pair.Value)) + "\nBlender:" + m.BlenderSha256;
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    }
    void RequireApproval(string kind)
    {
        if (!m.Approvals.Any(a => a.Kind == kind && a.Fingerprint == Fingerprint() && File.Exists(w.Resolve(a.Evidence)) && HashFile(a.Evidence) == a.EvidenceHash)) throw new InvalidOperationException("Current " + kind + " approval required");
    }
    public async Task Execute(string command, CancellationToken cancellation)
    {
        if (command == "init") { await Init(cancellation); return; }
        path = Relative(w, Need("manifest")); m = w.Load<Manifest>(path); CheckLayout();
        using var ownership = w.Lock(State + "/asset.lock"); m = w.Load<Manifest>(path); CheckLayout();
        await Fresh(command, cancellation);
        if (command == "status") { var hash = Fingerprint(); Console.WriteLine(JsonSerializer.Serialize(new { manifest = m, approvalFingerprints = new { action = hash, independent = hash, human = hash } }, Workspace.Json)); return; }
        if (command == "doctor")
        {
            var directory = State + "/doctor-" + Guid.NewGuid().ToString("N"); Directory.CreateDirectory(w.Resolve(directory));
            await CheckBlender(directory, cancellation); Console.WriteLine("READY: existing Blender4.5 and canonical engine checked; no dependency installed"); return;
        }
        if (command == "record") { Record(); return; }
        if (command == "validate") { Validate(); Console.WriteLine("VALID: current action ancestry, stage outputs and receipts; no automatic artistic/runtime acceptance"); return; }
        if (command == "promote") { Promote(); return; }
        var index = System.Array.IndexOf(Order, command);
        if (index < 0) throw new InvalidOperationException("Unknown action command");
        if (index > 0) Require(Order[index - 1]);
        await RunStage(command, cancellation);
    }
    async Task Init(CancellationToken cancellation)
    {
        var task = Id(Need("task")); var asset = Id(Need("asset")); var version = Id(Need("version"));
        if (string.IsNullOrWhiteSpace(Need("actor"))) throw new InvalidOperationException("Creator identity required");
        var motionPath = Relative(w, Need("motion-package")); var recipePath = Relative(w, Need("recipe")); var reviewPath = Relative(w, Need("source-review"));
        if (!reviewPath.StartsWith(".opencaw/.cache/tasks/" + task + "/", StringComparison.Ordinal)) throw new InvalidOperationException("Source review must belong to the active task cache");
        var motion = LoadObject(motionPath); var recipe = LoadObject(recipePath); var reviewed = LoadObject(reviewPath);
        var plan = ActionCompiler.Compile(recipe, motion, asset, version);
        var model = Relative(w, Text(motion["model"]!.AsObject(), "path"));
        if (new FileInfo(w.Resolve(model)).Length > recipe["budgets"]!["maxRuntimeBytes"]!.GetValue<long>()) throw new InvalidOperationException("Source GLB exceeds runtime byte budget");
        var glb = Glb(w.Resolve(model)); Source(motion, glb);
        if (Text(motion["model"]!.AsObject(), "sha256") != HashFile(model)) throw new InvalidOperationException("Motion package model bytes do not match");
        SourceApproval(reviewed, plan, HashFile(motionPath), HashFile(model));
        var engine = await engines.Resolve(cancellation);
        if (Text(engine, "effectiveEngine") == "PHASERJS") throw new InvalidOperationException("Phaser requires an explicitly selected 2D sprite/pre-rendered action handoff; GLB action composition is not that handoff");
        if (Text(motion["engine"]!.AsObject(), "effectiveEngine") != Text(engine, "effectiveEngine")) throw new InvalidOperationException("Source motion engine conflicts with current project; no engine selected implicitly");
        var blender = Path.GetFullPath(Need("blender"));
        if (!Path.IsPathFullyQualified(Need("blender")) || !File.Exists(blender)) throw new InvalidOperationException("Supply the existing absolute Blender4.5 executable; no installer");
        path = $".opencaw/.cache/tasks/{task}/model-to-action/{asset}/{version}/manifest.json";
        if (File.Exists(w.Resolve(path)) || Directory.Exists(w.Resolve($".art-staging/model-to-action/{asset}/{version}"))) throw new InvalidOperationException("Asset version already exists");
        m = new Manifest { Task = task, Asset = asset, Version = version, Actor = Need("actor"), Profile = Text(motion, "profile"), Staging = $".art-staging/model-to-action/{asset}/{version}", Blender = blender, BlenderSha256 = w.HashFile(blender), Engine = engine };
        using var ownership = w.Lock(State + "/asset.lock");
        if (File.Exists(w.Resolve(path)) || Directory.Exists(w.Resolve(m.Staging))) throw new InvalidOperationException("Another initialization owns this version");
        var bundle = Path.Combine(Baseline, ".styles/.workflows/model-to-action/blender/scripts.json");
        VerifyBundle(bundle, m.BaselineInputs);
        var canonical = Path.Combine(Baseline, "commands/lib/engine-contract.cjs"); m.BaselineInputs[canonical] = w.HashFile(canonical);
        foreach (var assembly in new[] { typeof(Pipeline).Assembly.Location, typeof(Workspace).Assembly.Location }) if (!string.IsNullOrWhiteSpace(assembly)) m.BaselineInputs[assembly] = w.HashFile(assembly);
        var original = m.Staging + "/original/"; Directory.CreateDirectory(w.Resolve(original));
        string Copy(string source, string name)
        {
            var expected = HashFile(source); var target = original + name; File.Copy(w.Resolve(source), w.Resolve(target), false);
            if (HashFile(target) != expected) throw new InvalidOperationException("Source changed while copying originals");
            m.SourceInputs[source] = expected; m.Originals[target] = expected; return target;
        }
        m.Model = Copy(model, "model.glb"); m.Motion = Copy(motionPath, "motion.json"); m.Recipe = Copy(recipePath, "recipe.json"); m.SourceReview = Copy(reviewPath, "source-review.json");
        m.EngineReceipt = original + "engine.json"; w.Save(m.EngineReceipt, engine); m.Originals[m.EngineReceipt] = HashFile(m.EngineReceipt);
        if (File.Exists(w.Resolve("STYLE.md"))) m.SourceInputs["STYLE.md"] = HashFile("STYLE.md");
        m.History.Add(new JsonObject { ["event"] = "init", ["sourceMotionPackage"] = motionPath, ["sourceModel"] = model, ["sourceReview"] = reviewPath, ["timestamp"] = DateTimeOffset.UtcNow.ToString("O") });
        Save(); Console.WriteLine(path);
    }
}
