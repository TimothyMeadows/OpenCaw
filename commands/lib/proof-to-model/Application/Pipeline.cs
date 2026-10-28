using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.IO.Compression;
using OpenCaw.ProofToModel.Domain;

namespace OpenCaw.ProofToModel.Application;

public sealed partial class Pipeline(IWorkspace w, Dictionary<string, string> options, INativeProcess native, IAlphaProcessor alpha)
{

    string manifestPath = ""; Manifest m = new();
    (string Path, byte[] Bytes, JsonObject Value)? finishingSelection;
    (string Path, byte[] Bytes, FinishAttemptBudget Value)? finishBudgetSelection;
    RigidSelection? rigidSelection;
    string? budgetManifestHash;
    string Need(string key) => options.GetValueOrDefault(key) ?? throw new InvalidOperationException("Missing --" + key);
    string Id(string value) => Regex.IsMatch(value, "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$") && value != ".." ? value : throw new InvalidOperationException("Unsafe identifier");
    string Hash(string relative) => w.HashFile(w.Resolve(relative));
    string State => Path.GetDirectoryName(manifestPath)!.Replace('\\', '/');
    string Fingerprint(IEnumerable<string> paths) => Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(string.Join("\n", paths.Order().Select(x => x + ":" + Hash(x))))));
    void Save()
    {
        w.Save(manifestPath, m);
        var audit = new AuditEvent { Type = "state", Message = "Asset state persisted", Data = new Dictionary<string, string> { { "asset", m.Asset }, { "manifest", manifestPath } } };
        OpenCaw.AssetProduction.AuditJournal.Append(w, State + "/audit.jsonl", audit);
    }
    JsonObject Toolchain => w.Load<JsonObject>(m.Toolchain);
    bool IsMultiView => m.SchemaVersion == 2;
    string[] StageOrder => IsMultiView ? ["classify", "prepare-proofs", "preprocess", "reconstruct", "finish", "guided", "review"] : ["preprocess", "reconstruct", "finish", "guided", "review"];
    string ProofApprovalKind => IsMultiView ? "proof-set" : "proof";
    string CurrentStyle => Hash("STYLE.md");
    IEnumerable<string> MetadataPaths => new[] { m.ProofMetadata, m.Brief }.Where(path => !string.IsNullOrEmpty(path));
    void Fresh(string? rerun = null)
    {
        if (w.Load<JsonObject>(m.Rights)["authorized"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("Current rights evidence does not authorize this input");
        if (!string.IsNullOrEmpty(m.ProofMetadata))
        {
            var metadata = w.Load<JsonObject>(m.ProofMetadata);
            foreach (var file in metadata["libraryArtifactHashes"]?.AsObject() ?? [])
                if (!File.Exists(w.Resolve(file.Key)) || Hash(file.Key) != file.Value!.GetValue<string>())
                    throw new InvalidOperationException("Stale library-copy ancestry: " + file.Key);
        }
        if (CurrentStyle != m.StyleHash)
            throw new InvalidOperationException("Style contract changed; initialize a new asset version");
        if (IsMultiView)
        {
            var classification = m.Classification;
            var proofSet = m.ProofSet;
            try
            {
                if (rerun == "classify") m.Classification = "";
                if (rerun is "classify" or "prepare-proofs") m.ProofSet = "";
                ValidatePreparation();
            }
            finally { m.Classification = classification; m.ProofSet = proofSet; }
        }
        var ordered = StageOrder;
        var stop = Array.IndexOf(ordered, rerun);
        var relevant = stop < 0 ? m.Stages.Values : m.Stages.Where(pair => Array.IndexOf(ordered, pair.Key) < stop).Select(pair => pair.Value);
        foreach (var stage in relevant.Where(s => s.Status == "complete"))
        {
            foreach (var file in stage.Inputs.Concat(stage.Outputs))
                if (!File.Exists(w.Resolve(file.Key)) || Hash(file.Key) != file.Value)
                    throw new InvalidOperationException("Stale or corrupt evidence: " + file.Key + "; initialize a new version or rerun from the invalid stage");
            foreach (var file in stage.ExternalInputs)
                if (!File.Exists(file.Key) || w.HashFile(file.Key) != file.Value)
                    throw new InvalidOperationException("Changed external tool/baseline script: " + file.Key);
        }
    }
    string ApprovalFingerprint(string kind)
    {
        IEnumerable<string> outputs = kind is "proof" or "proof-set" ? [] : kind == "preprocessing" ? (m.Stages.GetValueOrDefault("preprocess")?.Outputs.Keys ?? Enumerable.Empty<string>()) : m.Stages.Where(p => p.Value.Status == "complete" && (!(kind is "rigging" or "animation") || p.Key != "review")).SelectMany(p => p.Value.Outputs.Keys);
        return Fingerprint(outputs.Append(m.Proof).Append(m.Rights).Append(m.Recipe).Append(m.Toolchain).Append("STYLE.md").Concat(MetadataPaths).Concat(IsMultiView ? PreparationPaths() : []));
    }
    bool Approved(string kind) => m.Approvals.Any(a => a.Kind == kind && a.Fingerprint == ApprovalFingerprint(kind) && File.Exists(w.Resolve(a.Evidence)) && Hash(a.Evidence) == a.EvidenceHash);
    void RequireApproval(string kind)
    {
        if (!Approved(kind))
            throw new InvalidOperationException("Current " + kind + " approval required; record evidence explicitly");
    }
    Stage RequireStage(string name) => m.Stages.TryGetValue(name, out var stage) && stage.Status == "complete" ? stage : throw new InvalidOperationException("Complete " + name + " first");
    string Artifact(string stage, string name) => RequireStage(stage).Artifacts.TryGetValue(name, out var path) ? path : throw new InvalidOperationException("Missing " + name + " artifact");
    public async Task Execute(string command, CancellationToken cancellation)
    {
        if (options.ContainsKey("finish-settings") && command != "finish")
            throw new InvalidOperationException("--finish-settings is supported only by finish");
        if (options.ContainsKey("finish-budget") && command != "finish")
            throw new InvalidOperationException("--finish-budget is supported only by finish");
        if (command == "init")
        {
            Init();
            return;
        }
        manifestPath = w.Relative(Need("manifest"));
        m = w.Load<Manifest>(manifestPath);
        CheckStatePaths();
        using var assetLock = w.Lock(State + "/asset.lock");
        // Re-read after acquiring ownership: a preceding run may have atomically
        // saved newer state between the initial layout check and this lock.
        budgetManifestHash = options.ContainsKey("finish-budget") ? Hash(manifestPath) : null;
        m = w.Load<Manifest>(manifestPath);
        if (budgetManifestHash is not null && Hash(manifestPath) != budgetManifestHash)
            throw new InvalidOperationException("Manifest changed while loading finish budget context");
        CheckStatePaths();
        if (!IsMultiView && command is not ("status" or "doctor") && options.GetValueOrDefault("mode") != "single-view-diagnostic")
            throw new InvalidOperationException("Historical v1 state is single-view. Initialize a fresh v2 version for six-view production; --mode single-view-diagnostic explicitly selects diagnostic execution only.");
        if (command == "status")
        {
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                manifest = m,
                manifestSha256 = Hash(manifestPath),
                finishBudget = new { consumedFinishAttempts = ConsumedAttempts("finish") },
                approvalFingerprints = new
                {
                    proof = ApprovalFingerprint("proof"),
                    proofSet = ApprovalFingerprint("proof-set"),
                    preprocessing = ApprovalFingerprint("preprocessing"),
                    rigging = ApprovalFingerprint("rigging"),
                    animation = ApprovalFingerprint("animation"),
                    independent = ApprovalFingerprint("independent"),
                    human = ApprovalFingerprint("human")
                }
            }, Serialization.Json));
            return;
        }
        if (command is "doctor" or "setup")
        {
            await Setup(command == "setup", cancellation);
            return;
        }
        Fresh(command);
        switch (command)
        {
            case "reuse":
                if (!IsMultiView) throw new InvalidOperationException("Use a fresh v2 six-view asset for production reuse");
                await ReuseMultiView(cancellation);
                break;
            case "classify":
                if (!IsMultiView) throw new InvalidOperationException("Classification requires a new v2 asset version");
                m.Classification = "";
                m.ProofSet = "";
                await RunStage(command, PreparationPaths().Append(Need("classification")), RegisterClassification, cancellation);
                break;
            case "prepare-proofs":
                if (!IsMultiView) throw new InvalidOperationException("Six-view proof preparation requires a new v2 asset version");
                RequireStage("classify");
                await RunStage(command, PreparationPaths().Append(Need("proof-set")), RegisterProofSet, cancellation);
                break;
            case "preprocess":
                if (IsMultiView) { RequireStage("classify"); RequireStage("prepare-proofs"); }
                RequireApproval(ProofApprovalKind);
                await RunStage(command, new[] { m.Proof, m.Rights, m.Recipe, m.Toolchain, "STYLE.md" }.Concat(IsMultiView ? PreparationPaths() : []), IsMultiView ? PreprocessViews : Preprocess, cancellation);
                break;
            case "reconstruct":
                RequireApproval(ProofApprovalKind);
                RequireApproval("preprocessing");
                RequireStage("preprocess");
                await RunStage(command, RequireStage("preprocess").Outputs.Keys.Append(m.Toolchain).Concat(IsMultiView ? PreparationPaths() : []), IsMultiView ? ReconstructViews : Reconstruct, cancellation);
                break;
            case "finish":
                RequireApproval(ProofApprovalKind);
                RequireApproval("preprocessing");
                RequireStage("reconstruct");
                finishingSelection = ReadFinishingSettings();
                rigidSelection = ReadRigidSelection();
                finishBudgetSelection = ReadFinishBudget();
                await RunStage(command, RequireStage("reconstruct").Outputs.Keys.Append(m.Recipe).Append(m.Toolchain)
                    .Concat(finishingSelection is { } selected ? new[] { selected.Path } : [])
                    .Concat(rigidSelection?.Inputs.Keys ?? Enumerable.Empty<string>())
                    .Concat(finishBudgetSelection is { } budget ? new[] { budget.Path } : []), Finish, cancellation);
                break;
            case "review":
                RequireStage("finish");
                await RunStage(command, RequireStage("finish").Outputs.Keys.Append(m.Proof).Append(m.Toolchain).Concat(IsMultiView ? PreparationPaths() : []), Review, cancellation);
                break;
            case "record":
                Record();
                break;
            case "validate":
                Validate();
                Console.WriteLine("VALID: current hashes, ordered stage evidence and recorded approvals verified");
                break;
            case "promote":
                Promote();
                break;
            default:
                throw new InvalidOperationException("Unknown command: " + command);
        }
    }
    void Init()
    {
        var selectedMode = options.GetValueOrDefault("mode", "multi-view");
        if (selectedMode is not ("multi-view" or "single-view-diagnostic"))
            throw new InvalidOperationException("Mode must be multi-view or explicitly single-view-diagnostic; no silent fallback");
        if (selectedMode == "multi-view" && options.ContainsKey("reuse-manifest"))
            throw new InvalidOperationException("Register/classify/approve the new six-view asset first, then use reuse --reuse-manifest; init cannot inherit a donor's approvals");
        if (options.ContainsKey("sources") && options.ContainsKey("proof"))
            throw new InvalidOperationException("Supply --proof as one original or --sources as a source set, not both");
        var initialProof = options.TryGetValue("sources", out var sourceSetPath)
            ? w.Load<JsonObject>(sourceSetPath)["images"]?.AsArray().FirstOrDefault()?["path"]?.GetValue<string>() ?? throw new InvalidOperationException("Source set requires images with paths")
            : Need("proof");
        var asset = Id(Need("asset"));
        var version = Id(Need("version"));
        var task = Id(Need("task"));
        manifestPath = w.Relative(options.GetValueOrDefault("manifest", $".opencaw/.cache/tasks/{task}/proof-to-model/{asset}/{version}/manifest.json"));
        if (!manifestPath.StartsWith($".opencaw/.cache/tasks/{task}/", StringComparison.Ordinal))
            throw new InvalidOperationException("Manifest must remain under its .opencaw/.cache/tasks/<task>/ directory");
        if (File.Exists(w.Resolve(manifestPath)))
            throw new InvalidOperationException("Asset version already exists");
        using var assetLock = w.Lock(Path.GetDirectoryName(manifestPath) + "/asset.lock");
        m = new()
        {
            SchemaVersion = selectedMode == "multi-view" ? 2 : 1,
            Asset = asset,
            Version = version,
            Task = task,
            Staging = $".art-staging/proof-to-model/{asset}/{version}",
            Proof = w.Relative(initialProof),
            Rights = w.Relative(Need("rights")),
            Recipe = w.Relative(Need("recipe")),
            Toolchain = w.Relative(Need("toolchain")),
            CreatedBy = Need("actor"),
            StyleHash = CurrentStyle
        };
        foreach (var path in new[] { m.Proof, m.Rights, m.Recipe, m.Toolchain })
            if (!File.Exists(w.Resolve(path)))
                throw new InvalidOperationException("Missing input: " + path);
        var styleText = File.ReadAllText(w.Resolve("STYLE.md"));
        JsonObject? selectionEvidence = null;
        if (!Regex.IsMatch(styleText, @"Primary OpenCaw art pipeline:\s*\r?\n- PROOF_TO_MODEL\b"))
        {
            var selection = w.Load<JsonObject>(Need("selection"));
            var canonicalHash = selection["styleSha256"]?.GetValue<string>();
            var legacyHash = selection["styleContractHash"]?.GetValue<string>();
            if (canonicalHash is not null && legacyHash is not null && canonicalHash != legacyHash)
                throw new InvalidOperationException("Conflicting pipeline selection style hashes");
            if (selection["styleContract"] is { } contract && !w.Relative(contract.GetValue<string>()).Equals("STYLE.md", OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
                throw new InvalidOperationException("Pipeline selection must identify the current project STYLE.md");
            if (selection["selectionSource"]?.GetValue<string>() != "prompt" || selection["pipeline"]?.GetValue<string>() != "PROOF_TO_MODEL" || (canonicalHash ?? legacyHash) != CurrentStyle)
                throw new InvalidOperationException("PROOF_TO_MODEL must be selected by STYLE or current prompt evidence");
            selectionEvidence = selection;
        }
        var rights = w.Load<JsonObject>(m.Rights);
        if (rights["authorized"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("Rights evidence requires authorized:true");
        var metadata = options.TryGetValue("proof-metadata", out var metadataPath) ? w.Load<JsonObject>(metadataPath) : new JsonObject { ["source"] = "existing-authorized-image", ["prompt"] = "unavailable:not-provided", ["references"] = new JsonArray(), ["provider"] = "unavailable:not-provided", ["model"] = "unavailable:not-provided", ["seed"] = "unavailable:not-provided" };
        if (selectionEvidence is not null)
        {
            metadata["pipelineSelection"] = selectionEvidence;
            w.Save(State + "/pipeline-selection.json", selectionEvidence);
        }
        BindLibraries(styleText, metadata);
        JsonObject? initialBrief = options.TryGetValue("brief", out var initialBriefPath) ? w.Load<JsonObject>(initialBriefPath) : null;
        if (initialBrief is not null)
            ValidateBrief(initialBrief);
        ValidateRecipe();
        Directory.CreateDirectory(w.Resolve(m.Staging + "/original"));
        var original = m.Staging + "/original/proof" + Path.GetExtension(m.Proof);
        File.Copy(w.Resolve(m.Proof), w.Resolve(original), false);
        var source = m.Proof;
        m.Proof = original;
        m.ProofMetadata = m.Staging + "/original/proof-metadata.json";
        metadata["originalPath"] = source;
        metadata["proofHash"] = Hash(m.Proof);
        metadata["rights"] = m.Rights;
        metadata["rightsHash"] = Hash(m.Rights);
        w.Save(m.ProofMetadata, metadata);
        if (initialBrief is not null)
        {
            initialBrief["budgets"] = w.Load<JsonObject>(m.Recipe);
            initialBrief["rights"] = m.Rights;
            initialBrief["rightsHash"] = Hash(m.Rights);
            m.Brief = m.Staging + "/original/brief.json";
            w.Save(m.Brief, initialBrief);
        }
        if (IsMultiView)
            InitializeSources();
        Save();
        if (options.TryGetValue("reuse-manifest", out var donor))
            Reuse(donor);
        Console.WriteLine(manifestPath);
    }
    void BindLibraries(string styleText, JsonObject metadata)
    {
        var section = Regex.Match(styleText, @"(?ms)^## External Asset Libraries\s*\r?\n(?<section>.*?)(?=^## |\z)").Groups["section"].Value;
        var configured = Regex.Matches(section, @"(?m)^-\s+(?<id>[A-Za-z0-9._-]+):\s+`(?<root>[^`]+)`\s*$");
        if (configured.Count == 0)
            return;
        var search = w.Load<JsonObject>(Need("library-search"));
        if (search["styleContractHash"]?.GetValue<string>() != CurrentStyle || search["libraries"] is not JsonArray entries)
            throw new InvalidOperationException("Library search evidence must bind current style and every configured library");
        var hashes = new JsonObject();
        foreach (Match library in configured)
        {
            var id = library.Groups["id"].Value;
            var root = library.Groups["root"].Value;
            var entry = entries.Select(item => item!.AsObject()).SingleOrDefault(item => item["id"]?.GetValue<string>() == id) ?? throw new InvalidOperationException("Missing library search result: " + id);
            if (entry["root"]?.GetValue<string>() != root || entry["available"]?.GetValue<bool>() != true || string.IsNullOrWhiteSpace(entry["reason"]?.GetValue<string>()))
                throw new InvalidOperationException("Unavailable/unverified library requires direction: " + id);
            var result = entry["result"]?.GetValue<string>();
            if (result == "no-suitable-match")
                continue;
            if (result != "selected")
                throw new InvalidOperationException("Library result must be selected or no-suitable-match");
            var evidence = w.Relative(entry["copyEvidence"]?.GetValue<string>() ?? throw new InvalidOperationException("Selected library asset requires existing copyEvidence"));
            var copy = w.Load<JsonObject>(evidence);
            if (copy["schemaVersion"]?.GetValue<string>() != "opencaw-external-asset-copy/v1" || copy["libraryId"]?.GetValue<string>() != id || copy["styleSha256"]?.GetValue<string>() != CurrentStyle || copy["sourceReadOnly"]?.GetValue<bool>() != true)
                throw new InvalidOperationException("Invalid library copy ancestry");
            foreach (var file in copy["files"]!.AsArray())
            {
                var path = w.Relative(file!["path"]!.GetValue<string>());
                if (!path.StartsWith("assets/models/" + id + "/", StringComparison.Ordinal) || Hash(path) != file["sha256"]!.GetValue<string>())
                    throw new InvalidOperationException("Missing/corrupt repository-local asset copy");
                hashes[path] = Hash(path);
            }
            hashes[evidence] = Hash(evidence);
            entry["copyReceipt"] = copy;
        }
        metadata["librarySearch"] = search;
        metadata["libraryArtifactHashes"] = hashes;
    }
    void CheckStatePaths()
    {
        if (m.SchemaVersion is not (1 or 2))
            throw new InvalidOperationException("Unsupported manifest schema version");
        Id(m.Asset);
        Id(m.Version);
        Id(m.Task);
        if (!manifestPath.StartsWith($".opencaw/.cache/tasks/{m.Task}/", StringComparison.Ordinal) || m.Staging != $".art-staging/proof-to-model/{m.Asset}/{m.Version}" || !m.Proof.StartsWith(m.Staging + "/original/", StringComparison.Ordinal))
            throw new InvalidOperationException("Manifest/staging/original proof paths violate the repository-local asset layout");
        foreach (var approval in m.Approvals)
            RequireTaskEvidence(approval.Evidence);
        if (IsMultiView && (!m.SourceSet.StartsWith(m.Staging + "/original/", StringComparison.Ordinal) || !File.Exists(w.Resolve(m.SourceSet))))
            throw new InvalidOperationException("V2 requires its immutable original source set; initialize a fresh asset version");
        foreach (var path in new[] { m.Classification, m.ProofSet }.Where(x => !string.IsNullOrEmpty(x)))
            if (!w.Relative(path).StartsWith(m.Staging + "/attempts/", StringComparison.Ordinal))
                throw new InvalidOperationException("Preparation records must remain in this asset's immutable attempts");
    }
    void RequireTaskEvidence(string evidence)
    {
        if (!w.Relative(evidence).StartsWith($".opencaw/.cache/tasks/{m.Task}/", StringComparison.Ordinal))
            throw new InvalidOperationException("Review evidence must remain under its .opencaw/.cache/tasks/<task>/ directory; create fresh task-local evidence");
    }
    void Reuse(string donorPath)
    {
        if (IsMultiView)
            throw new InvalidOperationException("V2 reuse requires current classification and approved six-view preparation; use reuse after preparation, never a single-view donor at init");
        var donorOptions = new Dictionary<string, string> { { "manifest", w.Relative(donorPath) } };
        var donor = new Pipeline(w, donorOptions, native, alpha) { manifestPath = w.Relative(donorPath) };
        donor.m = w.Load<Manifest>(donor.manifestPath);
        donor.CheckStatePaths();
        donor.Validate();
        donor.RequireApproval("proof");
        donor.RequireApproval("preprocessing");
        donor.RequireApproval("independent");
        donor.RequireApproval("human");
        if (donor.m.StyleHash != m.StyleHash || Hash(donor.m.Recipe) != Hash(m.Recipe) || Hash(donor.m.Toolchain) != Hash(m.Toolchain) || Hash(donor.m.Proof) != Hash(m.Proof))
            throw new InvalidOperationException("Reuse ancestry incompatible with selected proof/style/recipe/toolchain; explicit adaptation required");
        var rights = w.Load<JsonObject>(m.Rights);
        if (rights["reuseAuthorized"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("Reuse requires rights reuseAuthorized:true");
        foreach (var name in new[] { "preprocess", "reconstruct" })
        {
            var source = donor.RequireStage(name);
            var stage = new Stage { Status = "complete", Attempt = m.Staging + "/reuse/" + name };
            Directory.CreateDirectory(w.Resolve(stage.Attempt));
            foreach (var artifact in source.Artifacts)
            {
                var target = stage.Attempt + "/" + artifact.Key + Path.GetExtension(artifact.Value);
                File.Copy(w.Resolve(artifact.Value), w.Resolve(target), false);
                stage.Artifacts[artifact.Key] = target;
                stage.Outputs[target] = Hash(target);
            }
            stage.Inputs = source.Inputs.Concat(source.Outputs).GroupBy(x => x.Key).ToDictionary(x => x.Key, x => x.First().Value);
            stage.Inputs[donor.manifestPath] = Hash(donor.manifestPath);
            stage.Inputs[m.Rights] = Hash(m.Rights);
            stage.ExternalInputs = new(source.ExternalInputs);
            stage.Fingerprint = Fingerprint(stage.Inputs.Keys);
            m.Stages[name] = stage;
        }
        m.History.Add(new()
        {
            ["event"] = "reuse",
            ["donorManifest"] = donor.manifestPath,
            ["donorHash"] = Hash(donor.manifestPath),
            ["note"] = "Copied reconstruction with complete donor approvals; new asset requires its own explicit proof/preprocessing and final reviews"
        });
        Save();
    }
    void ValidateRecipe()
    {
        var recipe = w.Load<JsonObject>(m.Recipe);
        foreach (var key in new[] { "targetFaces", "textureSize", "cageExtrusion", "maxRayDistance", "uvMargin", "lodRatios", "colliderMaxFaces", "maxTriangles", "maxMaterials", "maxTextureBytes", "parts", "riggingRequired", "animationRequired" })
            if (recipe[key] is null)
                throw new InvalidOperationException("Recipe missing " + key);
        foreach (var key in new[] { "targetFaces", "textureSize", "cageExtrusion", "maxRayDistance", "uvMargin", "colliderMaxFaces", "maxTriangles", "maxMaterials", "maxTextureBytes" })
            if (recipe[key]!.GetValue<double>() <= 0)
                throw new InvalidOperationException("Recipe requires positive " + key);
        var ratios = recipe["lodRatios"]!.AsArray().Select(x => x!.GetValue<double>()).ToArray();
        if (ratios.Length == 0 || ratios.Any(x => x <= 0 || x >= 1) || ratios.Zip(ratios.Skip(1)).Any(x => x.First <= x.Second))
            throw new InvalidOperationException("LOD ratios must decrease inside (0,1)");
        if (IsMultiView && (recipe["proofPreparation"]?["maxSetRevisions"]?.GetValue<int>() is not int revisions || revisions < 1 || revisions > 100))
            throw new InvalidOperationException("V2 recipe requires proofPreparation.maxSetRevisions inside 1..100");
    }
    async Task RunStage(string name, IEnumerable<string> inputs, Func<Stage, CancellationToken, Task> run, CancellationToken cancellation)
    {
        var maxAttempts = IsMultiView && name is "classify" or "prepare-proofs"
            ? w.Load<JsonObject>(m.Recipe)["proofPreparation"]!["maxSetRevisions"]!.GetValue<int>()
            : Toolchain["limits"]?["maxAttempts"]?.GetValue<int>() ?? 3;
        if (name == "finish" && finishBudgetSelection is { } budget)
        {
            ValidateFinishBudgetContext(budget.Value);
            maxAttempts = budget.Value.MaxFinishAttempts;
        }
        if (maxAttempts < 1 || ConsumedAttempts(name) >= maxAttempts)
            throw new InvalidOperationException(name == "finish" ? "Finish attempt budget exhausted; authorize exactly one additional finish with --finish-budget TASK_LOCAL_JSON bound to the current status manifestSha256 and consumedFinishAttempts" : "Stage attempt budget exhausted; select a new asset version/budget explicitly");
        _ = Timeout;
        var paths = inputs.Concat(MetadataPaths).Distinct().ToArray();
        var stage = new Stage { Attempt = m.Staging + "/attempts/" + name + "-" + Guid.NewGuid().ToString("N"), Inputs = paths.ToDictionary(x => x, Hash), Fingerprint = Fingerprint(paths) };
        Directory.CreateDirectory(w.Resolve(stage.Attempt));
        var start = new JsonObject
        {
            ["event"] = "stage-start",
            ["stage"] = name,
            ["attempt"] = stage.Attempt,
            ["timestamp"] = DateTimeOffset.UtcNow.ToString("O")
        };
        if (name == "finish" && finishBudgetSelection is { } authorization)
        {
            var snapshot = BindInputSnapshot(stage, authorization.Path, authorization.Bytes, "finishBudget", "finish-budget.json");
            stage.Outputs[snapshot] = stage.Inputs[snapshot];
            start["finishBudget"] = new JsonObject
            {
                ["source"] = authorization.Path, ["sourceSha256"] = stage.Inputs[authorization.Path],
                ["snapshot"] = snapshot, ["snapshotSha256"] = stage.Inputs[snapshot],
                ["manifestSha256"] = authorization.Value.ManifestSha256,
                ["consumedFinishAttempts"] = authorization.Value.ConsumedFinishAttempts,
                ["maxFinishAttempts"] = authorization.Value.MaxFinishAttempts,
                ["reviewer"] = authorization.Value.Reviewer, ["reason"] = authorization.Value.Reason,
                ["kind"] = "finish-attempt-budget", ["stage"] = "finish", ["decision"] = "approved", ["human"] = true
            };
            if (Hash(manifestPath) != budgetManifestHash) throw new InvalidOperationException("Manifest changed before spending finish budget receipt");
        }
        m.History.Add(start);
        m.Stages[name] = stage;
        var order = StageOrder;
        foreach (var later in order.Skip(Array.IndexOf(order, name) + 1))
            m.Stages.Remove(later);
        if (IsMultiView)
            m.Approvals.RemoveAll(a => name is "classify" or "prepare-proofs" || (a.Kind != "proof-set" && (name == "preprocess" || a.Kind != "preprocessing") && !(name == "review" && (a.Kind is "rigging" or "animation"))));
        else
            m.Approvals.RemoveAll(a => a.Kind != "proof" && (name == "preprocess" || a.Kind != "preprocessing") && !(name == "review" && (a.Kind is "rigging" or "animation")));
        Save();
        try
        {
            await new StageRegistry([(name, ct => run(stage, ct))]).Execute(name, cancellation);
            foreach (var artifact in stage.Artifacts.Values)
            {
                ValidateArtifact(artifact);
                stage.Outputs[artifact] = Hash(artifact);
            }
            foreach (var input in stage.Inputs)
                if (!File.Exists(w.Resolve(input.Key)) || Hash(input.Key) != input.Value)
                    throw new InvalidOperationException("Stage changed a bound input: " + input.Key);
            foreach (var input in stage.ExternalInputs)
                if (!File.Exists(input.Key) || w.HashFile(input.Key) != input.Value)
                    throw new InvalidOperationException("Stage changed a bound tool/script: " + input.Key);
            if (stage.Outputs.Count == 0)
                throw new InvalidOperationException("Stage emitted no artifacts");
            stage.Fingerprint = Fingerprint(stage.Inputs.Keys);
            stage.Status = "complete";
            Save();
        }
        catch (Exception e) { stage.Status = "failed"; stage.Error = e.Message; Save(); throw; }
    }
    static string Text(JsonObject value, string key) => value[key]?.GetValue<string>() ?? throw new InvalidOperationException("Toolchain missing " + key);
    JsonObject Section(string name) => Toolchain[name]?.AsObject() ?? throw new InvalidOperationException("Toolchain missing " + name);
    string Executable(string section)
    {
        var spec = Section(section);
        if (section == "blender")
        {
            var external = options.GetValueOrDefault("blender", Text(spec, "path"));
            if (!Path.IsPathRooted(external))
            {
                external = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator).Select(p => Path.Combine(p, external + (OperatingSystem.IsWindows() && !external.EndsWith(".exe") ? ".exe" : ""))).FirstOrDefault(File.Exists) ?? throw new InvalidOperationException("Blender executable not found; specify --blender");
            }
            if (!File.Exists(external))
                throw new InvalidOperationException("Missing Blender executable");
            return Path.GetFullPath(external);
        }
        var configured = Text(spec, "path");
        if (!OperatingSystem.IsWindows() && configured.EndsWith(".exe"))
            configured = configured[..^4];
        var path = w.Resolve(configured);
        if (!File.Exists(path))
            throw new InvalidOperationException("Missing dependency; use setup explicitly: " + path);
        var expected = spec["sha256"]?.GetValue<string>();
        if (expected is null)
        {
            var receipt = w.Load<JsonObject>(".local/tools/proof-to-model/installation.json");
            if (receipt["toolchainHash"]?.GetValue<string>() != Hash(m.Toolchain))
                throw new InvalidOperationException("Installation receipt toolchain is stale");
            foreach (var item in receipt["hashes"]!.AsObject())
                if (!File.Exists(w.Resolve(item.Key)) || Hash(item.Key) != item.Value!.GetValue<string>())
                    throw new InvalidOperationException("Installed dependency changed: " + item.Key);
            expected = receipt["hashes"]?[w.Relative(path)]?.GetValue<string>();
        }
        if (expected is null || !w.HashFile(path).Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Dependency hash not verified: " + path);
        return path;
    }
    void Models(Stage? stage = null)
    {
        foreach (var model in Toolchain["models"]?.AsArray() ?? [])
        {
            var spec = model!.AsObject();
            if (spec["licenseAccepted"]?.GetValue<bool>() != true)
                throw new InvalidOperationException("Model license evidence required");
            var path = Text(spec, "path");
            if (Hash(path) != Text(spec, "sha256").ToLowerInvariant())
                throw new InvalidOperationException("Model hash mismatch: " + path);
            if (stage is not null)
                stage.Inputs[w.Relative(path)] = Hash(path);
        }
        if (stage is not null && File.Exists(w.Resolve(".local/tools/proof-to-model/installation.json")))
        {
            var receipt = w.Load<JsonObject>(".local/tools/proof-to-model/installation.json");
            foreach (var item in receipt["hashes"]?.AsObject() ?? [])
                stage.Inputs[w.Relative(item.Key)] = Hash(item.Key);
            stage.Inputs[".local/tools/proof-to-model/installation.json"] = Hash(".local/tools/proof-to-model/installation.json");
        }
    }
    string[] Arguments(string section, string input, string output, string attempt)
    {
        var spec = Section(section);
        var tokens = new Dictionary<string, string> { { "{input}", w.Resolve(input) }, { "{output}", w.Resolve(output) }, { "{outputDir}", w.Resolve(attempt) }, { "{outputStem}", Path.Combine(Path.GetDirectoryName(w.Resolve(output))!, Path.GetFileNameWithoutExtension(output)) }, { "{modelDir}", w.Resolve(Toolchain["modelDir"]?.GetValue<string>() ?? ".local/tools/proof-to-model/models") } };
        var args = spec["arguments"]?.AsArray().Select(x => x!.GetValue<string>()).Select(x => { foreach (var token in tokens) x = x.Replace(token.Key, token.Value); return x; }).ToArray() ?? throw new InvalidOperationException("Missing explicit argument template " + section);
        if (args.Any(x => Regex.IsMatch(x, "\\{[^}]+\\}")))
            throw new InvalidOperationException("Unknown argument token");
        return args;
    }
    int Timeout
    {
        get
        {
            var maximum = Toolchain["limits"]?["timeoutSeconds"]?.GetValue<int>() ?? 1800;
            var selected = int.Parse(options.GetValueOrDefault("timeout", maximum.ToString()));
            if (selected < 1 || selected > maximum)
                throw new InvalidOperationException("Timeout exceeds selected toolchain budget");
            return selected;
        }
    }
    long LogBudget => Toolchain["limits"]?["maxLogBytes"]?.GetValue<long>() ?? 16777216;
    async Task RunEngine(Stage stage, string[] arguments, CancellationToken cancellation)
    {
        var executable = Executable("engine");
        stage.ExternalInputs[executable] = w.HashFile(executable);
        if (!int.TryParse(options.GetValueOrDefault("gpu", "0"), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var deviceId) || deviceId < 0)
            throw new InvalidOperationException("GPU must be a nonnegative integer device index");
        var device = deviceId.ToString(System.Globalization.CultureInfo.InvariantCulture);
        using var gpu = w.Lock(".local/tools/proof-to-model/gpu-" + device + ".lock");
        var receipt = stage.Attempt + "/execution.json";
        w.Save(receipt, new
        {
            schemaVersion = 1,
            executable,
            executableHash = w.HashFile(executable),
            engine = Section("engine"),
            arguments,
            device,
            timeoutSeconds = Timeout,
            maxLogBytes = LogBudget,
            nativeExecution = true,
            osSandbox = false
        });
        stage.Artifacts["execution"] = receipt;
        await native.Run(executable, arguments, w.Root, w.Resolve(stage.Attempt + "/process.log"), Timeout, cancellation, LogBudget, new Dictionary<string, string> { { "CUDA_VISIBLE_DEVICES", device } });
    }
    async Task Preprocess(Stage s, CancellationToken c)
    {
        var matte = alpha.Inspect(w.Resolve(m.Proof));
        var cutout = s.Attempt + "/normalized_cutout.png";
        var preserved = matte?.Suitable == true;
        if (preserved)
        {
            File.Copy(w.Resolve(m.Proof), w.Resolve(cutout));
        }
        else
        {
            Models(s);
            var output = s.Attempt + "/normalized.glb";
            var args = Arguments("preprocessing", m.Proof, output, s.Attempt);
            if (!args.Contains("birefnet") || !args.Contains("--bg-only"))
                throw new InvalidOperationException("Explicit BiRefNet --bg-only required; threshold fallback forbidden");
            await RunEngine(s, args, c);
            var pattern = Section("preprocessing")["outputPattern"]?.GetValue<string>() ?? "{outputStem}_cutout.png";
            cutout = pattern.Replace("{outputStem}", Path.ChangeExtension(output, null));
            matte = alpha.Inspect(w.Resolve(cutout));
            if (matte?.Suitable != true)
                throw new InvalidOperationException("BiRefNet did not produce a usable foreground alpha matte");
        }
        alpha.SaveMask(w.Resolve(s.Attempt + "/mask.png"), matte!);
        w.Save(s.Attempt + "/transforms.json", new
        {
            schemaVersion = 1,
            operation = preserved ? "preserve-existing-alpha" : "birefnet",
            input = m.Proof,
            inputHash = Hash(m.Proof),
            width = matte!.Width,
            height = matte.Height,
            transform = preserved ? new[] { 1, 0, 0, 0, 1, 0, 0, 0, 1 } : null,
            transformAvailability = preserved ? "exact-identity" : "unavailable:engine-does-not-disclose-pixel-transform"
        });
        s.Artifacts["normalized"] = w.Relative(cutout);
        s.Artifacts["mask"] = s.Attempt + "/mask.png";
        s.Artifacts["transforms"] = s.Attempt + "/transforms.json";
        foreach (var file in Directory.GetFiles(w.Resolve(s.Attempt), "*", SearchOption.AllDirectories))
            if (!file.EndsWith("process.log"))
                s.Artifacts.TryAdd("retained-" + s.Artifacts.Count, w.Relative(file));
    }
    async Task Reconstruct(Stage s, CancellationToken c)
    {
        Models(s);
        var output = s.Attempt + "/raw.glb";
        await RunEngine(s, Arguments("reconstruction", Artifact("preprocess", "normalized"), output, s.Attempt), c);
        s.Artifacts["glb"] = output;
        foreach (var file in Directory.GetFiles(w.Resolve(s.Attempt), "*", SearchOption.AllDirectories))
            if (!file.EndsWith("process.log"))
                s.Artifacts.TryAdd("retained-" + s.Artifacts.Count, w.Relative(file));
        if (!s.Artifacts.Values.Any(x => x.EndsWith("transforms.json")) || !s.Artifacts.Values.Any(x => x.EndsWith("input.png")))
            throw new InvalidOperationException("Engine did not retain single-view input and transforms ancestry");
    }
    int ConsumedAttempts(string stage) => m.History.Count(item => item["event"]?.GetValue<string>() == "stage-start" && item["stage"]?.GetValue<string>() == stage);
    void ValidateFinishBudgetContext(FinishAttemptBudget receipt)
    {
        var configured = Toolchain["limits"]?["maxAttempts"]?.GetValue<int>() ?? 3;
        var consumed = ConsumedAttempts("finish");
        if (configured < 1 || consumed < configured)
            throw new InvalidOperationException("Finish budget recovery is allowed only after the valid configured finish budget is exhausted");
        if (receipt.ManifestSha256 != budgetManifestHash || Hash(manifestPath) != budgetManifestHash)
            throw new InvalidOperationException("Stale finish budget receipt: manifestSha256 must match the exact current manifest file");
        if (receipt.ConsumedFinishAttempts != consumed)
            throw new InvalidOperationException("Stale finish budget receipt: consumedFinishAttempts must match current finish stage-start history");
    }
    (string Path, byte[] Bytes, FinishAttemptBudget Value)? ReadFinishBudget()
    {
        if (!options.ContainsKey("finish-budget")) return null;
        var input = ReadRelativeJsonInput("finish-budget", FinishAttemptBudget.MaximumBytes, taskEvidence: true);
        var receipt = FinishAttemptBudget.Parse(input.Bytes);
        ValidateFinishBudgetContext(receipt);
        return (input.Path, input.Bytes, receipt);
    }
    (string Path, byte[] Bytes, JsonObject Value)? ReadFinishingSettings()
    {
        if (!options.ContainsKey("finish-settings")) return null;
        var input = ReadRelativeJsonInput("finish-settings", FinishingSettings.MaximumBytes);
        var value = FinishingSettings.Parse(input.Bytes);
        if (value["rigidParts"]?["uvAtlas"] is not null)
            FinishingSettings.ValidateUvAtlasRecipe(value, w.Load<JsonObject>(m.Recipe)["textureSize"]!.GetValue<double>());
        if (value["rigidParts"]?["lods"] is not null)
            FinishingSettings.ValidateLodRecipe(value, w.Load<JsonObject>(m.Recipe)["lodRatios"]!.AsArray().Count);
        return (input.Path, input.Bytes, value);
    }
    (string Path, byte[] Bytes) ReadRelativeJsonInput(string option, int maximumBytes, bool taskEvidence = false)
    {
        var supplied = Need(option);
        var normalized = supplied.Replace('\\', '/');
        if (string.IsNullOrWhiteSpace(normalized) || Path.IsPathRooted(supplied) || normalized.Contains(':')
            || normalized.Split('/').Any(part => part is "" or "." or ".." || part.EndsWith(' ') || part.EndsWith('.')
                || part.Any(char.IsControl) || part.IndexOfAny(['<', '>', '"', '|', '?', '*']) >= 0
                || Regex.IsMatch(part, @"^(CON|PRN|AUX|NUL|COM[1-9Â¹Â²Â³]|LPT[1-9Â¹Â²Â³]|CONIN\$|CONOUT\$)(\.|$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
            || !normalized.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("--" + option + " requires a project-relative JSON path without traversal or aliases");
        var path = w.Relative(normalized);
        if (taskEvidence) RequireTaskEvidence(path);
        using var stream = File.OpenRead(w.Resolve(path));
        using var reader = new BinaryReader(stream);
        return (path, reader.ReadBytes(maximumBytes + 1));
    }
    string BindInputSnapshot(Stage stage, string source, byte[] bytes, string artifact, string filename)
    {
        var expected = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(bytes));
        if (stage.Inputs.GetValueOrDefault(source) != expected || Hash(source) != expected)
            throw new InvalidOperationException("Bound " + artifact + " input changed after validation; retry explicitly with current evidence");
        var snapshot = stage.Attempt + "/" + filename;
        using (var output = new FileStream(w.Resolve(snapshot), FileMode.CreateNew, FileAccess.Write, FileShare.None)) output.Write(bytes);
        stage.Inputs[snapshot] = expected;
        stage.Artifacts[artifact] = snapshot;
        return snapshot;
    }
    async Task Finish(Stage s, CancellationToken c)
    {
        ValidateRecipe();
        if (finishingSelection is { } selected)
            BindInputSnapshot(s, selected.Path, selected.Bytes, "finishingSettings", "finishing-settings.json");
        if (rigidSelection is not null) await SnapshotRigidInputs(s, c);
        await Blender(s, "finish", Artifact("reconstruct", "glb"), c);
        foreach (var required in new[] { "blend", "glb", "report" })
            if (!s.Artifacts.ContainsKey(required))
                throw new InvalidOperationException("Missing finishing artifact " + required);
        var recipe = w.Load<JsonObject>(m.Recipe);
        if (recipe["riggingRequired"]!.GetValue<bool>() || recipe["animationRequired"]!.GetValue<bool>())
        {
            w.Save(s.Attempt + "/subject-work.json", new
            {
                riggingRequired = recipe["riggingRequired"]!.GetValue<bool>(),
                animationRequired = recipe["animationRequired"]!.GetValue<bool>(),
                status = "pending-guided-subject-work",
                source = s.Artifacts["glb"]
            });
            s.Artifacts["subjectWork"] = s.Attempt + "/subject-work.json";
        }
    }
    string FinalGlb => Artifact(m.Stages.ContainsKey("guided") ? "guided" : "finish", "glb");
    async Task Review(Stage s, CancellationToken c)
    {
        var recipe = w.Load<JsonObject>(m.Recipe);
        if (recipe["riggingRequired"]!.GetValue<bool>())
            RequireApproval("rigging");
        if (recipe["animationRequired"]!.GetValue<bool>())
            RequireApproval("animation");
        if (m.Stages.ContainsKey("guided"))
            foreach (var input in RequireStage("guided").Outputs)
                s.Inputs[input.Key] = input.Value;
        await Blender(s, "review", FinalGlb, c);
    }
    async Task Blender(Stage s, string mode, string input, CancellationToken c)
    {
        if (options.ContainsKey("pipeline-dir"))
            throw new InvalidOperationException("Arbitrary pipeline-dir script bundles are prohibited; use the trusted installed baseline");
        var baseline = options.GetValueOrDefault("baseline-root");
        if (baseline is null)
        {
            var directory = new DirectoryInfo(AppContext.BaseDirectory);
            while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "commands/proof-to-model.sh")))
                directory = directory.Parent;
            baseline = directory?.FullName ?? throw new InvalidOperationException("Trusted baseline missing; specify --baseline-root");
        }
        var scriptDirectory = Path.Combine(Path.GetFullPath(baseline), ".styles/.pipelines/proof-to-model/blender");
        var bundle = s.Attempt + "/scripts";
        Directory.CreateDirectory(w.Resolve(bundle));
        foreach (var file in rigidSelection is not null && mode == "finish"
                     ? new[] { "finish.py", "review.py", "common.py", "rigid_finish.py", "rigid_source_topology.py" }
                     : new[] { "finish.py", "review.py", "common.py" })
        {
            var source = Path.Combine(scriptDirectory, file);
            if ((File.GetAttributes(source) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Baseline script cannot be a reparse point");
            s.ExternalInputs[source] = w.HashFile(source);
            var target = bundle + "/" + file;
            File.Copy(source, w.Resolve(target), false);
            s.Inputs[target] = Hash(target);
        }
        var blender = Executable("blender");
        s.ExternalInputs[blender] = w.HashFile(blender);
        var temporaryDirectory = s.Attempt + "/temp";
        string ConfinedTemporaryDirectory()
        {
            var path = w.Resolve(temporaryDirectory);
            // GetTempPath/GetTempPath2 use MAX_PATH-sized results on Windows.
            // An overlong TEMP/TMP may be ignored in favour of USERPROFILE;
            // reject before launch instead of routing writes outside the asset.
            if (OperatingSystem.IsWindows() && Path.TrimEndingDirectorySeparator(path).Length + 2 > 260)
                throw new InvalidOperationException("Blender temporary directory exceeds the Windows temporary-path limit; select a shorter project/task path. No alternate temporary location was selected.");
            Directory.CreateDirectory(path);
            // Re-resolve after creation and before each launch; existing links,
            // junctions, non-directories and escaped parents must not route temp.
            path = w.Resolve(temporaryDirectory);
            if (!Directory.Exists(path) || (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Blender temporary directory must be a real confined attempt directory");
            return path;
        }
        var childTemporaryDirectory = ConfinedTemporaryDirectory();
        var childEnvironment = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["TEMP"] = childTemporaryDirectory, ["TMP"] = childTemporaryDirectory,
            ["TMPDIR"] = childTemporaryDirectory, ["PYTHONDONTWRITEBYTECODE"] = "1"
        };
        var processEnvironment = new
        {
            temporaryDirectory,
            temporaryEnvironmentVariables = new[] { "TEMP", "TMP", "TMPDIR" },
            pythonDontWriteBytecode = true,
            scope = "Child process environment routing; not an operating-system sandbox"
        };
        var maximumPrivateBytes = mode == "finish" && rigidSelection is not null
            ? finishingSelection!.Value.Value["resources"]!["maxPrivateBytes"]!.GetValue<long>() : (long?)null;
        void SaveToolIdentity(string? observedVersion) => w.Save(s.Attempt + "/tool-identity.json", new
        {
            executable = blender,
            sha256 = w.HashFile(blender),
            version = observedVersion,
            processEnvironment,
            resourcePolicy = maximumPrivateBytes is null ? null : new
            {
                maxPrivateBytes = maximumPrivateBytes,
                accounting = "Windows owned-job aggregate committed memory including descendants; not resident RAM or GPU memory",
                limitations = "Process.Start precedes job assignment; assignment failure terminates the launched tree. No OS sandbox is claimed."
            }
        });
        SaveToolIdentity(null);
        s.Artifacts["toolIdentity"] = s.Attempt + "/tool-identity.json";
        // Retain routing/executable provenance even if the version probe fails
        // or the process is interrupted before a job/result can be produced.
        Save();
        _ = ConfinedTemporaryDirectory();
        if (maximumPrivateBytes is { } probeLimit)
            await native.RunWithLimits(blender, ["--version"], w.Root, w.Resolve(s.Attempt + "/blender-version.log"), 15, probeLimit, c, LogBudget, childEnvironment);
        else
            await native.Run(blender, ["--version"], w.Root, w.Resolve(s.Attempt + "/blender-version.log"), 15, c, LogBudget, childEnvironment);
        var version = Compatibility.StripStreamMarkers(File.ReadAllText(w.Resolve(s.Attempt + "/blender-version.log")));
        if (!Compatibility.IsBlender45Log(version))
            throw new InvalidOperationException("Blender 4.5 LTS required");
        SaveToolIdentity(version);
        var script = bundle + "/" + mode + ".py";
        var job = s.Attempt + "/job.json";
        var result = s.Attempt + "/outputs/result.json";
        var recipe = w.Load<JsonObject>(m.Recipe);
        var subjectRequirements = recipe.DeepClone();
        if (mode == "finish")
        {
            recipe["riggingRequired"] = false;
            recipe["animationRequired"] = false;
        }
        w.Save(job, new
        {
            schemaVersion = IsMultiView && mode == "review" ? 2 : 1,
            mode = IsMultiView ? "multi-view" : "single-view-diagnostic",
            root = w.Root,
            input,
            inputFrame = IsMultiView ? mode == "finish" ? "pixal3d-mv-export" : "opencaw-proof-z-up" : "legacy-native",
            engineToProofScale = IsMultiView ? 1.0 / CurrentProofSet()["camera"]!["meshScale"]!.GetValue<double>() : 1.0,
            proof = IsMultiView ? CurrentFrontProof() : m.Proof,
            proofSet = IsMultiView && mode == "review" ? w.Load<JsonObject>(Artifact("preprocess", "dataset")) : null,
            sourceSet = IsMultiView && mode == "review" ? w.Load<JsonObject>(m.SourceSet) : null,
            classification = IsMultiView && mode == "review" ? w.Load<JsonObject>(m.Classification) : null,
            outputDir = s.Attempt + "/outputs",
            recipe,
            finishingSettings = mode == "finish" ? finishingSelection?.Value : null,
            rigidHandoff = mode == "finish" ? rigidSelection?.Handoff : null,
            taskEvidenceRoot = mode == "finish" && rigidSelection is not null ? $".opencaw/.cache/tasks/{m.Task}" : null,
            subjectRequirements,
            processEnvironment,
            result
        });
        _ = ConfinedTemporaryDirectory();
        string[] arguments = ["--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python", w.Resolve(script), "--", "--job", w.Resolve(job)];
        if (maximumPrivateBytes is { } selectedLimit)
            await native.RunWithLimits(blender, arguments, w.Root, w.Resolve(s.Attempt + "/process.log"), Timeout, selectedLimit, c, LogBudget, childEnvironment);
        else
            await native.Run(blender, arguments, w.Root, w.Resolve(s.Attempt + "/process.log"), Timeout, c, LogBudget, childEnvironment);
        var data = w.Load<JsonObject>(result);
        if (data["status"]?.GetValue<string>() != "prepared" || data["stages"] is not JsonArray || data["measurements"] is not JsonObject)
            throw new InvalidOperationException("Invalid Blender measured result");
        foreach (var artifact in data["artifacts"]!.AsObject())
        {
            if (artifact.Key is "finishingSettings" or "finishBudget" or "toolIdentity" or "rigidHandoff" or "rigidPreparedSource" or "rigidPreparationReview" or "rigidAuthoringEvidence" or "rigidLineage")
                throw new InvalidOperationException("Native finishing settings/budget/tool identity cannot be replaced by a producer artifact");
            var path = w.Relative(artifact.Value!.GetValue<string>());
            if (!path.StartsWith(s.Attempt + "/outputs/", StringComparison.Ordinal))
                throw new InvalidOperationException("Blender artifact escapes attempt output");
            s.Artifacts[artifact.Key] = path;
        }
        s.Artifacts["result"] = result;
        if (mode == "finish" && rigidSelection is { } rigid)
        {
            var limits = finishingSelection!.Value.Value["rigidParts"]!;
            if (data["rigidHandoffSha256"]?.GetValue<string>() != ByteHash(rigid.HandoffBytes)
                || data["inputSha256"]?.GetValue<string>() != Hash(input)
                || data["finishingSettings"]?["method"]?.GetValue<string>() != "rigid-parts")
                throw new InvalidOperationException("Rigid producer result lacks exact raw/handoff/method identities");
            var triangles = data["measurements"]?["lod0Triangles"]?.GetValue<long>() ?? 0;
            var bytes = data["measurements"]?["glbBytes"]?.GetValue<long>() ?? 0;
            if (triangles < 1 || triangles > limits["maxLod0Triangles"]!.GetValue<long>()
                || bytes < 1 || bytes > limits["maxGlbBytes"]!.GetValue<long>()
                || !s.Artifacts.TryGetValue("glb", out var finishedGlb) || new FileInfo(w.Resolve(finishedGlb)).Length != bytes)
                throw new InvalidOperationException("Rigid producer must report actual bounded LOD0/GLB measurements, not empty or mismatched evidence");
        }
    }
    void Record()
    {
        var kind = Need("kind");
        if (!new[] { "proof", "proof-set", "preprocessing", "independent", "human", "rigging", "animation" }.Contains(kind))
            throw new InvalidOperationException("Unknown approval kind");
        if (kind == "proof" && IsMultiView || kind == "proof-set" && !IsMultiView)
            throw new InvalidOperationException("Record the current " + ProofApprovalKind + " approval; single-image approval cannot approve six-view production");
        if (kind == "proof-set")
        {
            RequireStage("classify");
            RequireStage("prepare-proofs");
            _ = CurrentProofSet();
        }
        var reviewer = Need("reviewer");
        if (kind == "independent" && reviewer == m.CreatedBy)
            throw new InvalidOperationException("Independent reviewer must differ from asset creator");
        if (kind is "independent" or "human")
            RequireStage("review");
        if (kind == "preprocessing")
            RequireStage("preprocess");
        if (kind == "human")
            RequireApproval("independent");
        var evidence = w.Relative(Need("evidence"));
        RequireTaskEvidence(evidence);
        var receipt = w.Load<JsonObject>(evidence);
        var fingerprint = ApprovalFingerprint(kind);
        if (receipt["kind"]?.GetValue<string>() != kind || receipt["reviewer"]?.GetValue<string>() != reviewer || receipt["decision"]?.GetValue<string>() != "approved" || receipt["fingerprint"]?.GetValue<string>() != fingerprint || string.IsNullOrWhiteSpace(receipt["reason"]?.GetValue<string>()))
            throw new InvalidOperationException("Review evidence must identify kind, reviewer, approved decision, reason and current fingerprint: " + fingerprint);
        if (kind is "proof" or "proof-set" or "human" && receipt["human"]?.GetValue<bool>() != true)
            throw new InvalidOperationException("Human decision assertion required; CLI does not authenticate reviewer identity");
        if (kind is "rigging" or "animation")
        {
            RequireStage("finish");
            if (options.TryGetValue("artifact", out var derivative))
                RegisterGuided(kind, w.Relative(derivative), receipt);
            var data = ReadGlbJson(FinalGlb);
            var key = kind == "rigging" ? "skins" : "animations";
            if (data[key] is not JsonArray elements || elements.Count == 0)
                throw new InvalidOperationException("Guided artifact lacks actual " + key);
            fingerprint = ApprovalFingerprint(kind);
        }
        m.Approvals.Add(new(kind, reviewer, evidence, Hash(evidence), fingerprint, DateTimeOffset.UtcNow));
        Save();
    }
    JsonObject ReadGlbJson(string path)
    {
        ValidateArtifact(path);
        using var stream = File.OpenRead(w.Resolve(path));
        using var reader = new BinaryReader(stream);
        stream.Position = 12;
        var length = reader.ReadInt32();
        if (length < 2 || length > 16777216 || reader.ReadUInt32() != 0x4E4F534A)
            throw new InvalidOperationException("Missing bounded GLB JSON chunk");
        return JsonNode.Parse(reader.ReadBytes(length))?.AsObject() ?? throw new InvalidOperationException("Invalid GLB JSON");
    }
    void RegisterGuided(string kind, string derivative, JsonObject receipt)
    {
        var json = ReadGlbJson(derivative);
        var key = kind == "rigging" ? "skins" : "animations";
        if (json[key] is not JsonArray values || values.Count == 0)
            throw new InvalidOperationException("Guided derivative has no " + key);
        if (receipt["artifactHash"]?.GetValue<string>() != Hash(derivative))
            throw new InvalidOperationException("Subject-work receipt requires exact artifactHash");
        if (!derivative.StartsWith(m.Staging + "/", StringComparison.Ordinal))
            throw new InvalidOperationException("Guided derivative must reside in this version's staging tree");
        var editable = w.Relative(Need("source"));
        if (!editable.StartsWith(m.Staging + "/", StringComparison.Ordinal) || Path.GetExtension(editable) != ".blend")
            throw new InvalidOperationException("Guided work requires matching editable .blend --source in this version's staging tree");
        ValidateArtifact(editable);
        if (receipt["sourceHash"]?.GetValue<string>() != Hash(editable) || string.IsNullOrWhiteSpace(receipt["sourceCorrespondence"]?.GetValue<string>()))
            throw new InvalidOperationException("Subject expert must bind sourceHash and explicitly explain sourceCorrespondence with the exported derivative");
        var parent = m.Stages.ContainsKey("guided") ? RequireStage("guided") : RequireStage("finish");
        var stage = new Stage { Status = "complete", Attempt = m.Staging + "/attempts/guided-" + Guid.NewGuid().ToString("N"), Inputs = parent.Outputs.ToDictionary(p => p.Key, p => p.Value) };
        stage.Inputs[derivative] = Hash(derivative);
        stage.Inputs[editable] = Hash(editable);
        stage.Inputs[m.Recipe] = Hash(m.Recipe);
        Directory.CreateDirectory(w.Resolve(stage.Attempt));
        var target = stage.Attempt + "/guided.glb";
        File.Copy(w.Resolve(derivative), w.Resolve(target));
        stage.Artifacts["glb"] = target;
        stage.Outputs[target] = Hash(target);
        var sourceTarget = stage.Attempt + "/guided.blend";
        File.Copy(w.Resolve(editable), w.Resolve(sourceTarget));
        stage.Artifacts["blend"] = sourceTarget;
        stage.Outputs[sourceTarget] = Hash(sourceTarget);
        stage.Fingerprint = Fingerprint(stage.Inputs.Keys);
        m.Stages["guided"] = stage;
        m.Stages.Remove("review");
        m.Approvals.RemoveAll(a => a.Kind is "independent" or "human" or "rigging" or "animation");
        m.History.Add(new()
        {
            ["event"] = "guided-subject-work",
            ["source"] = derivative,
            ["sha256"] = Hash(derivative),
            ["kind"] = kind
        });
    }
    void Validate()
    {
        Fresh();
        foreach (var pair in m.Stages)
        {
            if (pair.Value.Status != "complete")
                throw new InvalidOperationException("Incomplete or interrupted stage: " + pair.Key);
            foreach (var path in pair.Value.Artifacts.Values)
                ValidateArtifact(path);
        }
        if (m.Stages.ContainsKey("reconstruct"))
        {
            RequireStage("preprocess");
            RequireApproval(ProofApprovalKind);
            RequireApproval("preprocessing");
            if (IsMultiView) ValidateMultiViewDataset(w.Load<JsonObject>(Artifact("preprocess", "dataset")));
        }
        if (m.Stages.ContainsKey("preprocess"))
            RequireApproval(ProofApprovalKind);
        if (IsMultiView && m.Stages.ContainsKey("preprocess"))
        {
            RequireStage("classify");
            RequireStage("prepare-proofs");
        }
        if (m.Stages.ContainsKey("finish"))
            RequireStage("reconstruct");
        if (m.Stages.ContainsKey("review"))
            RequireStage("finish");
    }
    void ValidateArtifact(string relative)
    {
        var full = w.Resolve(relative);
        if (!File.Exists(full) || new FileInfo(full).Length == 0)
            throw new InvalidOperationException("Empty/missing artifact: " + relative);
        if (Path.GetExtension(full) == ".glb")
        {
            using var stream = File.OpenRead(full);
            using var reader = new BinaryReader(stream);
            if (stream.Length < 20 || reader.ReadUInt32() != 0x46546c67 || reader.ReadUInt32() != 2 || reader.ReadUInt32() != stream.Length)
                throw new InvalidOperationException("Invalid GLB container");
        }
        if (Path.GetExtension(full) == ".png")
        {
            using var stream = File.OpenRead(full);
            using var reader = new BinaryReader(stream);
            var bytes = reader.ReadBytes(33);
            if (bytes.Length < 33 || !bytes.Take(8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }))
                throw new InvalidOperationException("Invalid PNG");
        }
        if (Path.GetExtension(full) == ".blend")
        {
            using var stream = File.OpenRead(full);
            using var reader = new BinaryReader(stream);
            if (!reader.ReadBytes(7).SequenceEqual("BLENDER"u8.ToArray())) throw new InvalidOperationException("Invalid Blender file");
        }
    }
    void Promote()
    {
        if (!IsMultiView)
            throw new InvalidOperationException("Single-view diagnostic assets cannot be promoted; initialize an approved six-view v2 production asset");
        Validate();
        if (string.IsNullOrEmpty(m.Brief))
            throw new InvalidOperationException("Promotion requires an immutable --brief at init (purpose, scale.units=metres, scale.metersPerUnit=1, interfaces). Initialize a new version with a brief; no scale is inferred.");
        ValidateBrief(w.Load<JsonObject>(m.Brief));
        RequireStage("review");
        RequireApproval("independent");
        RequireApproval("human");
        var recipe = w.Load<JsonObject>(m.Recipe);
        if (recipe["riggingRequired"]!.GetValue<bool>())
            RequireApproval("rigging");
        if (recipe["animationRequired"]!.GetValue<bool>())
            RequireApproval("animation");
        var destination = w.Relative(Need("destination"));
        if (!destination.StartsWith("assets/models/", StringComparison.Ordinal))
            throw new InvalidOperationException("Promotion destination must be under assets/models");
        if (Directory.Exists(w.Resolve(destination)) || File.Exists(w.Resolve(destination)))
            throw new InvalidOperationException("Promotion cannot overwrite an asset");
        var temporary = destination + ".pending-" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(w.Resolve(temporary));
        try
        {
            foreach (var pair in RequireStage("finish").Artifacts.Where(x => x.Key != "result"))
            {
                var source = pair.Key == "glb" ? FinalGlb : pair.Key == "blend" && m.Stages.ContainsKey("guided") ? Artifact("guided", "blend") : pair.Value;
                var target = temporary + "/" + Path.GetFileName(pair.Value);
                File.Copy(w.Resolve(source), w.Resolve(target), false);
                if (Hash(target) != Hash(source))
                    throw new InvalidOperationException("Promotion copy hash mismatch");
            }
            Directory.Move(w.Resolve(temporary), w.Resolve(destination));
            m.History.Add(new()
            {
                ["event"] = "promoted",
                ["destination"] = destination,
                ["timestamp"] = DateTimeOffset.UtcNow.ToString("O")
            });
            Save();
        }
        catch { throw; }
    }
    void ValidateBrief(JsonObject brief)
    {
        if (string.IsNullOrWhiteSpace(brief["purpose"]?.GetValue<string>()) || brief["scale"] is not JsonObject scale || scale["units"]?.GetValue<string>() != "metres" || scale["metersPerUnit"]?.GetValue<double>() != 1 || brief["interfaces"] is not JsonArray)
            throw new InvalidOperationException("Brief requires purpose, scale:{units:'metres',metersPerUnit:1}, and explicit interfaces array; native GLB exports use metre units");
    }
    async Task ProbeGpu(CancellationToken cancellation)
    {
        var engine = Toolchain["engine"]?.AsObject();
        if (engine?["minimumDriver"] is null && engine?["minimumCuda"] is null)
            return;
        var executable = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator).Select(path => Path.Combine(path, OperatingSystem.IsWindows() ? "nvidia-smi.exe" : "nvidia-smi")).FirstOrDefault(File.Exists) ?? throw new InvalidOperationException("nvidia-smi unavailable: install a compatible NVIDIA driver explicitly; no driver was installed");
        var folder = State + "/diagnostics/gpu-" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(w.Resolve(folder));
        await native.Run(executable, ["--query-gpu=driver_version", "--format=csv,noheader,nounits"], w.Root, w.Resolve(folder + "/driver.log"), 15, cancellation);
        var drivers = Regex.Matches(Compatibility.StripStreamMarkers(File.ReadAllText(w.Resolve(folder + "/driver.log"))), @"\d+\.\d+").Select(match => match.Value).ToArray();
        if (drivers.Length == 0)
            throw new InvalidOperationException("NVIDIA driver query returned no GPUs");
        if (engine?["minimumDriver"] is { } minimumDriver)
            foreach (var driver in drivers)
                Compatibility.Require(driver, minimumDriver.GetValue<string>(), "NVIDIA driver");
        await native.Run(executable, [], w.Root, w.Resolve(folder + "/cuda.log"), 15, cancellation);
        var cuda = Compatibility.CudaVersionFromLog(File.ReadAllText(w.Resolve(folder + "/cuda.log")));
        if (cuda is null)
            throw new InvalidOperationException("NVIDIA CUDA compatibility could not be measured");
        if (engine?["minimumCuda"] is { } minimumCuda)
            Compatibility.Require(cuda, minimumCuda.GetValue<string>(), "Driver CUDA compatibility");
        w.Save(folder + "/report.json", new
        {
            drivers,
            cudaCompatibility = cuda,
            probe = executable,
            probeHash = w.HashFile(executable),
            checkedAt = DateTimeOffset.UtcNow
        });
    }
    async Task Setup(bool setup, CancellationToken cancellation)
    {
        var toolchain = Toolchain;
        Console.WriteLine(JsonSerializer.Serialize(toolchain, Serialization.Json));
        if (!setup)
        {
            await ProbeGpu(cancellation);
            Executable("engine");
            Executable("blender");
            Models();
            Console.WriteLine("Native dependencies verified; not an OS sandbox");
            return;
        }
        if (!options.ContainsKey("execute"))
        {
            Console.WriteLine("DRY RUN: no downloads or installs; --execute requires explicit licenseAccepted for every file");
            return;
        }
        using var installLock = w.Lock(".local/tools/proof-to-model/setup.lock");
        await ProbeGpu(cancellation);
        if (System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture != System.Runtime.InteropServices.Architecture.X64)
            throw new InvalidOperationException("Pinned inference archives require an x64 host");
        var files = (toolchain["files"]?.AsArray() ?? throw new InvalidOperationException("Toolchain requires explicit pinned files")).DeepClone().AsArray();
        if (toolchain["engine"]?["archives"] is JsonArray archives)
        {
            var platform = OperatingSystem.IsWindows() ? "windows-x64-cuda12" : OperatingSystem.IsLinux() ? "linux-x64-cuda12" : "unsupported";
            var archive = archives.Select(x => x!.AsObject()).SingleOrDefault(x => x["platform"]!.GetValue<string>() == platform)?.DeepClone().AsObject() ?? throw new InvalidOperationException("Unsupported platform");
            archive["path"] = ".local/tools/proof-to-model/downloads/" + Path.GetFileName(new Uri(Text(archive, "url")).AbsolutePath);
            archive["extractTo"] = archive["destination"]!.GetValue<string>();
            files.Insert(0, archive);
        }
        long total = 0;
        foreach (var item in files)
        {
            var spec = item!.AsObject();
            if (spec["licenseAccepted"]?.GetValue<bool>() != true || spec["license"] is null)
                throw new InvalidOperationException("Explicit per-file license evidence required");
            if (!Regex.IsMatch(Text(spec, "sha256"), "^[A-Fa-f0-9]{64}$"))
                throw new InvalidOperationException("Unpinned download");
            if (!new Uri(Text(spec, "url")).Scheme.Equals("https"))
                throw new InvalidOperationException("HTTPS download required");
            var path = w.Relative(Text(spec, "path"));
            if (!path.StartsWith(".local/tools/proof-to-model/"))
                throw new InvalidOperationException("Install destination must be project-local tools");
            total += spec["sizeBytes"]?.GetValue<long>() ?? throw new InvalidOperationException("Download size budget required");
        }
        if (new DriveInfo(Path.GetPathRoot(w.Root)!).AvailableFreeSpace < Math.Max(checked(total * 3), toolchain["limits"]?["minimumFreeBytes"]?.GetValue<long>() ?? 0))
            throw new InvalidOperationException("Insufficient install space");
        var hashes = new JsonObject();
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(30) };
        foreach (var item in files)
        {
            var spec = item!.AsObject();
            var path = w.Resolve(Text(spec, "path"));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            if (File.Exists(path))
            {
                if (w.HashFile(path) != Text(spec, "sha256").ToLowerInvariant())
                    throw new InvalidOperationException("Existing install differs from pin");
            }
            else
            {
                var temp = path + ".download-" + Guid.NewGuid().ToString("N");
                using var response = await client.GetAsync(Text(spec, "url"), HttpCompletionOption.ResponseHeadersRead, cancellation);
                response.EnsureSuccessStatusCode();
                await using (var stream = File.Create(temp))
                {
                    await using var source = await response.Content.ReadAsStreamAsync(cancellation);
                    var expectedSize = spec["sizeBytes"]!.GetValue<long>();
                    var buffer = new byte[131072];
                    long copied = 0;
                    int count;
                    while ((count = await source.ReadAsync(buffer, cancellation)) > 0)
                    {
                        copied += count;
                        if (copied > expectedSize)
                            throw new InvalidOperationException("Download exceeded pinned size");
                        await stream.WriteAsync(buffer.AsMemory(0, count), cancellation);
                    }
                    if (copied != expectedSize)
                        throw new InvalidOperationException("Truncated download");
                }
                if (w.HashFile(temp) != Text(spec, "sha256").ToLowerInvariant())
                {
                    File.Delete(temp);
                    throw new InvalidOperationException("Download hash mismatch");
                }
                File.Move(temp, path, false);
            }
            hashes[w.Relative(path)] = w.HashFile(path);
            if (spec["extractTo"] is { } extract)
            {
                var target = w.Relative(extract.GetValue<string>());
                if (!target.StartsWith(".local/tools/proof-to-model/"))
                    throw new InvalidOperationException("Unsafe archive destination");
                var staging = target + ".extract-" + Guid.NewGuid().ToString("N");
                Directory.CreateDirectory(w.Resolve(staging));
                string Safe(string name)
                {
                    var output = w.Resolve(staging + "/" + name);
                    if (!w.Relative(output).StartsWith(staging + "/", StringComparison.Ordinal))
                        throw new InvalidOperationException("Archive path escapes destination");
                    Directory.CreateDirectory(Path.GetDirectoryName(output)!);
                    return output;
                }
                if (path.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                {
                    using var zip = ZipFile.OpenRead(path);
                    foreach (var entry in zip.Entries)
                    {
                        if (entry.FullName.EndsWith('/'))
                            continue;
                        if ((entry.ExternalAttributes >> 16 & 0xF000) == 0xA000)
                            throw new InvalidOperationException("Archive symlink prohibited");
                        entry.ExtractToFile(Safe(entry.FullName), false);
                    }
                }
                else if (path.EndsWith(".tar.gz", StringComparison.OrdinalIgnoreCase))
                {
                    using var input = File.OpenRead(path);
                    using var gzip = new GZipStream(input, CompressionMode.Decompress);
                    using var tar = new System.Formats.Tar.TarReader(gzip);
                    while (tar.GetNextEntry() is { } entry)
                    {
                        if (entry.EntryType == System.Formats.Tar.TarEntryType.Directory)
                            continue;
                        if (entry.EntryType is not (System.Formats.Tar.TarEntryType.RegularFile or System.Formats.Tar.TarEntryType.V7RegularFile))
                            throw new InvalidOperationException("Archive links/special files prohibited");
                        entry.ExtractToFile(Safe(entry.Name), false);
                    }
                }
                else
                    throw new InvalidOperationException("Unsupported archive format");
                var executable = spec["executable"]?.GetValue<string>();
                if (executable is not null && !Directory.GetFiles(w.Resolve(staging), executable, SearchOption.AllDirectories).Any())
                    throw new InvalidOperationException("Archive missing pinned executable");
                foreach (var source in Directory.GetFiles(w.Resolve(staging), "*", SearchOption.AllDirectories))
                {
                    var relative = Path.GetRelativePath(w.Resolve(staging), source);
                    var output = w.Resolve(target + "/" + relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(output)!);
                    if (File.Exists(output) && w.HashFile(output) != w.HashFile(source))
                        throw new InvalidOperationException("Refusing to replace changed installation");
                    if (!File.Exists(output))
                        File.Move(source, output);
                    hashes[w.Relative(output)] = w.HashFile(output);
                }
            }
        }
        w.Save(".local/tools/proof-to-model/installation.json", new
        {
            schemaVersion = 1,
            toolchainHash = Hash(m.Toolchain),
            hashes,
            installedAt = DateTimeOffset.UtcNow
        });
        Console.WriteLine("Pinned installation receipt recorded");
    }
}
