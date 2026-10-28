using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using System.Text;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAnimation.Domain;
using static OpenCaw.ModelAnimation.Application.MotionValidation;
namespace OpenCaw.ModelAnimation.Application;

public sealed partial class Pipeline(IWorkspace w, Dictionary<string, string> options, INativeProcess native, IEngineResolver engines)
{
    static readonly string[] Order = ["inspect", "prepare", "rig", "motion", "bake", "export", "review"];
    string path = ""; Manifest m = new();
    string Need(string name) => options.GetValueOrDefault(name) ?? throw new InvalidOperationException("Missing --" + name);
    string State => Path.GetDirectoryName(path)!.Replace('\\', '/');
    string HashFile(string relative) => w.HashFile(w.Resolve(relative));
    JsonObject Recipe => LoadObject(m.EffectiveRecipe);
    JsonObject Budget => LoadObject(m.Recipe)["budgets"]!.AsObject();
    string Baseline => Path.GetFullPath(Need("baseline-root"));
    string TaskPrefix => ".opencaw/.cache/tasks/" + m.Task + "/";
    JsonObject LoadObject(string relative)
    {
        var file = w.Resolve(relative);
        if (!File.Exists(file) || new FileInfo(file).Length is < 2 or > 8 * 1024 * 1024)
            throw new InvalidOperationException("Missing/oversized JSON input: " + relative);
        return w.Load<JsonObject>(relative);
    }
    void Save()
    {
        w.Save(path, m);
        AuditJournal.Append(w, State + "/audit.jsonl", new
        {
            timestamp = DateTimeOffset.UtcNow,
            type = "state",
            asset = m.Asset,
            manifest = path,
            stages = m.Stages.ToDictionary(pair => pair.Key, pair => pair.Value.Status)
        });
    }
    void CheckLayout()
    {
        if (m.SchemaVersion != "opencaw-model-animation/v1")
            throw new InvalidOperationException("Unsupported motion manifest");
        Id(m.Task);
        Id(m.Asset);
        Id(m.Version);
        if (!path.StartsWith(TaskPrefix, StringComparison.Ordinal) || m.Staging != $".art-staging/model-to-animation/{m.Asset}/{m.Version}" || !m.Model.StartsWith(m.Staging + "/original/", StringComparison.Ordinal))
            throw new InvalidOperationException("Motion state/originals violate repository-local layout");
        foreach (var input in m.Originals.Keys)
            if (!Relative(w, input).StartsWith(m.Staging + "/original/", StringComparison.Ordinal))
                throw new InvalidOperationException("Original ancestry escapes its asset");
        foreach (var pair in m.Stages)
            CheckStageLayout(pair.Key, pair.Value);
        if (m.LastSuccessfulMotion is not null)
        {
            CheckStageLayout("motion", m.LastSuccessfulMotion);
            if (m.LastSuccessfulMotion.Status != "complete")
                throw new InvalidOperationException("Motion recovery requires a complete prior stage");
        }
        if (m.EffectiveRecipe != m.Recipe && !Relative(w, m.EffectiveRecipe).StartsWith(m.Staging + "/attempts/motion-", StringComparison.Ordinal))
            throw new InvalidOperationException("Effective motion recipe escapes immutable ancestry");
        foreach (var approval in m.Approvals)
            RequireEvidence(approval.Evidence);
    }
    void CheckStageLayout(string name, Stage stage)
    {
        if (!Order.Contains(name) || stage.Status is not ("running" or "failed" or "complete") || !Relative(w, stage.Attempt).StartsWith(m.Staging + "/attempts/" + name + "-", StringComparison.Ordinal))
            throw new InvalidOperationException("Invalid stage layout/status");
        foreach (var artifact in stage.Artifacts.Values)
            if (!Relative(w, artifact).StartsWith(stage.Attempt + "/", StringComparison.Ordinal))
                throw new InvalidOperationException("Stage artifact escapes attempt");
    }
    void VerifyHashes(IEnumerable<KeyValuePair<string, string>> hashes, bool external = false)
    {
        foreach (var pair in hashes)
        {
            var file = external ? pair.Key : w.Resolve(pair.Key);
            if (!File.Exists(file) || w.HashFile(file) != pair.Value)
                throw new InvalidOperationException("Changed/missing bound evidence: " + pair.Key + "; initialize a fresh asset version or rerun the affected stage");
        }
    }
    async Task Fresh(string? rerun, CancellationToken cancellation)
    {
        if (HashFile(m.EffectiveRecipe) != m.EffectiveRecipeSha256)
            throw new InvalidOperationException("Effective motion recipe changed");
        VerifyHashes(m.Originals);
        VerifyHashes(m.SourceInputs);
        VerifyHashes(m.BaselineInputs, true);
        if (LoadObject(m.Rights)["authorized"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("Current model rights are not authorized");
        if (!File.Exists(m.Blender) || w.HashFile(m.Blender) != m.BlenderSha256)
            throw new InvalidOperationException("Configured Blender binary changed");
        var engine = await engines.Resolve(cancellation);
        if (!JsonNode.DeepEquals(engine, m.Engine) || !JsonNode.DeepEquals(LoadObject(m.EngineReceipt), m.Engine))
            throw new InvalidOperationException("Engine selection/context changed; initialize a fresh version");
        MotionValidation.Recipe(Recipe);
        var stop = System.Array.IndexOf(Order, rerun);
        foreach (var pair in m.Stages.Where(pair => stop < 0 || System.Array.IndexOf(Order, pair.Key) < stop))
            if (pair.Value.Status == "complete")
            {
                VerifyHashes(pair.Value.Inputs);
                VerifyHashes(pair.Value.Outputs);
                VerifyHashes(pair.Value.ExternalInputs, true);
            }
    }
    string Fingerprint(string kind)
    {
        var stop = kind == "rig" ? System.Array.IndexOf(Order, "rig") : Order.Length - 1;
        var inputs = m.Originals.Concat(m.SourceInputs).Concat(m.Stages.Where(pair => pair.Value.Status == "complete" && System.Array.IndexOf(Order, pair.Key) <= stop).SelectMany(pair => pair.Value.Outputs)).GroupBy(pair => pair.Key).Select(group => group.First()).OrderBy(pair => pair.Key, StringComparer.Ordinal).ToArray();
        VerifyHashes(inputs);
        var value = string.Join("\n", inputs.Select(pair => pair.Key + ":" + HashFile(pair.Key))) + "\nBlender:" + m.BlenderSha256;
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    }
    bool Approved(string kind) => m.Approvals.Any(a => a.Kind == kind && a.Fingerprint == Fingerprint(kind) && File.Exists(w.Resolve(a.Evidence)) && HashFile(a.Evidence) == a.EvidenceHash);
    void RequireApproval(string kind)
    {
        if (!Approved(kind))
            throw new InvalidOperationException("Current " + kind + " approval required; record explicit evidence");
    }
    Stage Require(string stage) => m.Stages.TryGetValue(stage, out var value) && value.Status == "complete" ? value : throw new InvalidOperationException("Complete " + stage + " first");
    string Artifact(string stage, string key) => Require(stage).Artifacts.GetValueOrDefault(key) ?? throw new InvalidOperationException("Missing " + stage + " artifact " + key);
    void RequireEvidence(string evidence)
    {
        if (!Relative(w, evidence).StartsWith(TaskPrefix, StringComparison.Ordinal))
            throw new InvalidOperationException("Approval/evidence must remain under its task cache");
    }

    public async Task Execute(string command, CancellationToken cancellation)
    {
        if (command == "init")
        {
            await Init(cancellation);
            return;
        }
        path = Relative(w, Need("manifest"));
        m = w.Load<Manifest>(path);
        CheckLayout();
        using var ownership = w.Lock(State + "/asset.lock");
        m = w.Load<Manifest>(path);
        CheckLayout();
        if (command == "status")
        {
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                manifest = m,
                approvalFingerprints = new
                {
                    rig = Fingerprint("rig"),
                    motion = Fingerprint("motion"),
                    independent = Fingerprint("independent"),
                    human = Fingerprint("human")
                }
            }, Workspace.Json));
            return;
        }
        await Fresh(command is "author" or "retarget" ? "motion" : command, cancellation);
        if (command == "doctor")
        {
            await Doctor(cancellation);
            return;
        }
        if (command == "record")
        {
            Record();
            return;
        }
        if (command == "validate")
        {
            Validate();
            Console.WriteLine("VALID: motion package hashes, stage order and current evidence checked; visual quality requires actual review");
            return;
        }
        if (command == "promote")
        {
            Promote();
            return;
        }
        var stage = command is "author" or "retarget" ? "motion" : command;
        var index = System.Array.IndexOf(Order, stage);
        if (index < 0)
            throw new InvalidOperationException("Unknown model-to-animation command: " + command);
        if (index > 0)
            Require(Order[index - 1]);
        if (index > System.Array.IndexOf(Order, "rig"))
            RequireApproval("rig");
        await RunStage(stage, command, cancellation);
    }
    async Task Init(CancellationToken cancellation)
    {
        var task = Id(Need("task"));
        var asset = Id(Need("asset"));
        var version = Id(Need("version"));
        path = Relative(w, options.GetValueOrDefault("manifest", $".opencaw/.cache/tasks/{task}/model-to-animation/{asset}/{version}/manifest.json"));
        if (!path.StartsWith($".opencaw/.cache/tasks/{task}/", StringComparison.Ordinal))
            throw new InvalidOperationException("Manifest belongs under its task cache");
        var model = Relative(w, Need("model"));
        if (Path.GetExtension(model).ToLowerInvariant() != ".glb")
            throw new InvalidOperationException("Export a reviewed self-contained GLB from the selected authoring workflow; no implicit FBX/blend importer is installed");
        MotionValidation.Glb(w.Resolve(model));
        var rights = LoadObject(Relative(w, Need("rights")));
        if (rights["authorized"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("Model rights require authorized:true");
        NoExcludedProviders(rights);
        var recipe = LoadObject(Relative(w, Need("recipe")));
        MotionValidation.Recipe(recipe);
        var engine = await engines.Resolve(cancellation);
        if (Text(engine, "effectiveEngine") == "PHASERJS")
            throw new InvalidOperationException("PHASERJS requires an explicitly selected 2D sprite/rendered-animation handoff; this native GLB workflow cannot claim skinned3D support");
        if (engine["outputScope"] is not null)
            throw new InvalidOperationException("Animation selection cannot authorize a task engine override or write outside its declared prototype scope");
        var blender = Path.GetFullPath(Need("blender"));
        if (!Path.IsPathRooted(Need("blender")) || !File.Exists(blender))
            throw new InvalidOperationException("Configure an existing absolute Blender4.5 executable; no software is installed");
        if (!File.Exists(w.Resolve("STYLE.md")))
            throw new InvalidOperationException("STYLE.md is required; select the project's visual contract first");
        if (File.Exists(w.Resolve(path)))
            throw new InvalidOperationException("Asset version already exists");
        using var ownership = w.Lock(State + "/asset.lock");
        if (File.Exists(w.Resolve(path)))
            throw new InvalidOperationException("Asset version already exists");
        m = new()
        {
            Task = task,
            Asset = asset,
            Version = version,
            Actor = Need("actor"),
            Profile = Text(recipe, "profile"),
            Staging = $".art-staging/model-to-animation/{asset}/{version}",
            Blender = blender,
            BlenderSha256 = w.HashFile(blender),
            Engine = engine
        };
        Directory.CreateDirectory(w.Resolve(m.Staging + "/original"));
        string Copy(string source, string name)
        {
            source = Relative(w, source);
            var target = m.Staging + "/original/" + name;
            m.SourceInputs[source] = HashFile(source);
            File.Copy(w.Resolve(source), w.Resolve(target), false);
            m.Originals[target] = HashFile(target);
            if (m.Originals[target] != m.SourceInputs[source])
                throw new InvalidOperationException("Original copy changed during initialization");
            return target;
        }
        m.Model = Copy(model, "model.glb");
        m.Rights = Copy(Need("rights"), "rights.json");
        m.Recipe = Copy(Need("recipe"), "recipe.json");
        m.EffectiveRecipe = m.Recipe;
        m.EffectiveRecipeSha256 = HashFile(m.Recipe);
        if (options.TryGetValue("editable-source", out var editable))
        {
            if (Path.GetExtension(editable).ToLowerInvariant() != ".blend")
                throw new InvalidOperationException("Editable source must be .blend bytes");
            Copy(editable, "editable-source.blend");
        }
        if (options.TryGetValue("source-metadata", out var metadata))
        {
            NoExcludedProviders(LoadObject(metadata));
            Copy(metadata, "source-metadata.json");
        }
        m.SourceInputs["STYLE.md"] = HashFile("STYLE.md");
        if (File.Exists(w.Resolve("ARCHITECTURE.md")))
            m.SourceInputs["ARCHITECTURE.md"] = HashFile("ARCHITECTURE.md");
        m.EngineReceipt = m.Staging + "/original/engine.json";
        w.Save(m.EngineReceipt, engine);
        m.Originals[m.EngineReceipt] = HashFile(m.EngineReceipt);
        var guard = Path.Combine(Baseline, "commands/lib/engine-contract.cjs");
        if (!File.Exists(guard))
            throw new InvalidOperationException("Missing canonical engine resolver");
        m.BaselineInputs[guard] = w.HashFile(guard);
        m.History.Add(new()
        {
            ["event"] = "init",
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("O"),
            ["nativeExecution"] = "pending"
        });
        Save();
        Console.WriteLine(path);
    }
    async Task Doctor(CancellationToken cancellation)
    {
        var directory = State + "/doctor-" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(w.Resolve(directory));
        await CheckBlender(directory, cancellation);
        Console.WriteLine("READY: Blender4.5 version/binary and canonical engine selection checked; no dependency installed");
    }
    void Validate()
    {
        foreach (var pair in m.Stages)
        {
            if (pair.Value.Status != "complete")
                throw new InvalidOperationException("Incomplete or interrupted stage: " + pair.Key);
            var index = System.Array.IndexOf(Order, pair.Key);
            for (var i = 0; i < index; i++)
                Require(Order[i]);
        }
        foreach (var approval in m.Approvals)
        {
            if (approval.Fingerprint != Fingerprint(approval.Kind) || !File.Exists(w.Resolve(approval.Evidence)) || HashFile(approval.Evidence) != approval.EvidenceHash)
                throw new InvalidOperationException("Stale recorded approval: " + approval.Kind);
            if (approval.Kind == "human")
                ValidateRuntimeAcceptance(LoadObject(approval.Evidence));
        }
        if (m.Stages.ContainsKey("motion"))
            RequireApproval("rig");
        if (m.Stages.ContainsKey("export"))
            ValidatePackage(LoadObject(Artifact("export", "package")), Require("export"));
    }
}
