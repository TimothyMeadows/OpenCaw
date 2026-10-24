using System.Text.Json.Nodes;

namespace OpenCaw.ProofToModel.Application;

public sealed partial class Pipeline
{
    async Task ReuseMultiView(CancellationToken cancellation)
    {
        if (!IsMultiView) throw new InvalidOperationException("Multi-view reuse requires a new v2 target, never a single-view diagnostic");
        RequireStage("classify"); RequireStage("prepare-proofs"); RequireApproval("proof-set");
        if (w.Load<JsonObject>(m.Rights)["reuseAuthorized"]?.GetValue<bool>() != true) throw new InvalidOperationException("Current target rights require reuseAuthorized:true");
        RequireMultiViewToolchain();
        var path = w.Relative(Need("reuse-manifest"));
        if (path == manifestPath) throw new InvalidOperationException("An asset cannot reuse itself");
        var donor = new Pipeline(w, new Dictionary<string, string> { ["manifest"] = path }, native, alpha) { manifestPath = path, m = w.Load<OpenCaw.ProofToModel.Domain.Manifest>(path) };
        donor.CheckStatePaths();
        if (!donor.IsMultiView) throw new InvalidOperationException("Single-view donors cannot satisfy six-view reuse");
        if (donor.m.Staging == m.Staging) throw new InvalidOperationException("Reuse source and target staging trees must be distinct");
        using var donorLock = w.Lock(donor.State + "/asset.lock");
        // Another approved native operation may have atomically saved the donor
        // between discovery and lock acquisition. Bind the locked snapshot only.
        donor.m = w.Load<OpenCaw.ProofToModel.Domain.Manifest>(path);
        donor.CheckStatePaths();
        if (!donor.IsMultiView || donor.m.Staging == m.Staging) throw new InvalidOperationException("Locked donor must remain a distinct v2 six-view asset");
        donor.Validate(); donor.RequireMultiViewToolchain();
        foreach (var stage in new[] { "classify", "prepare-proofs", "preprocess", "reconstruct", "finish", "review" }) donor.RequireStage(stage);
        var requiredApprovals = new List<string> { "proof-set", "preprocessing", "independent", "human" };
        var donorRecipe = w.Load<JsonObject>(donor.m.Recipe);
        foreach (var kind in new[] { "rigging", "animation" }) if (donorRecipe[kind + "Required"]!.GetValue<bool>()) requiredApprovals.Add(kind);
        foreach (var kind in requiredApprovals) donor.RequireApproval(kind);
        if (string.IsNullOrEmpty(donor.m.Brief)) throw new InvalidOperationException("A fully reviewed reusable donor requires its immutable production brief");
        donor.ValidateBrief(w.Load<JsonObject>(donor.m.Brief));
        if (m.StyleHash != donor.m.StyleHash || Hash(m.Recipe) != Hash(donor.m.Recipe) || Hash(m.Toolchain) != Hash(donor.m.Toolchain)) throw new InvalidOperationException("Reuse requires matching current style, recipe and pinned tool/model configuration");
        var sourceIdentities = donor.SourceIdentities(donor.CurrentSourceSet());
        var targetIdentities = SourceIdentities(CurrentSourceSet());
        if (!sourceIdentities.Values.Select(image => PreparationText(image, "sha256")).Order(StringComparer.Ordinal).SequenceEqual(targetIdentities.Values.Select(image => PreparationText(image, "sha256")).Order(StringComparer.Ordinal)) || Hash(m.Proof) != Hash(donor.m.Proof)) throw new InvalidOperationException("Reuse originals or primary source differ");
        if (!JsonNode.DeepEquals(ReuseClassification(donor.ReadPreparation(donor.m.Classification), sourceIdentities), ReuseClassification(ReadPreparation(m.Classification), targetIdentities))) throw new InvalidOperationException("Reuse classification, research, interpretation or source-angle coverage differs");
        var ownSet = CurrentProofSet(); var donorSet = donor.CurrentProofSet();
        if (!JsonNode.DeepEquals(ReuseProofIdentity(donorSet, sourceIdentities), ReuseProofIdentity(ownSet, targetIdentities))) throw new InvalidOperationException("Reuse proof image, camera, material interpretation or source ancestry differs");
        var donorDataset = w.Load<JsonObject>(donor.Artifact("preprocess", "dataset"));
        donor.ValidateMultiViewDataset(donorDataset);
        donor.ValidateReuseReconstructionReceipt();
        var sourceManifestHash = Hash(path);
        if (m.Stages.TryGetValue("reconstruct", out var existingReconstruction) && existingReconstruction.Status == "complete") throw new InvalidOperationException("Target already has reconstruction; reuse cannot overwrite current production evidence");
        var resumePreprocessing = m.Stages.TryGetValue("preprocess", out var existingPreprocessing) && existingPreprocessing.Status == "complete";
        if (resumePreprocessing)
        {
            if (!existingPreprocessing!.Artifacts.TryGetValue("reuseReceipt", out var previousReceipt) || w.Load<JsonObject>(previousReceipt)["sourceManifestHash"]?.GetValue<string>() != sourceManifestHash) throw new InvalidOperationException("Reuse cannot overwrite existing unrelated preprocessing; initialize a fresh asset version");
            ValidateMultiViewDataset(w.Load<JsonObject>(Artifact("preprocess", "dataset")));
        }
        var ancestry = donor.m.Stages.Values.SelectMany(stage => stage.Inputs.Keys.Concat(stage.Outputs.Keys))
            .Concat(donor.MetadataPaths).Concat(donor.PreparationPaths()).Append(donor.m.Rights).Append(donor.m.Recipe).Append(donor.m.Toolchain).Append(path)
            .Concat(requiredApprovals.Select(kind => donor.m.Approvals.Last(approval => approval.Kind == kind && approval.Fingerprint == donor.ApprovalFingerprint(kind) && Hash(approval.Evidence) == approval.EvidenceHash).Evidence))
            .Concat(PreparationPaths()).Append(m.Rights).Append(m.Recipe).Append(m.Toolchain).Append("STYLE.md").Distinct(StringComparer.Ordinal).ToArray();
        cancellation.ThrowIfCancellationRequested();
        m.History.Add(new JsonObject { ["event"] = "multi-view-reuse-start", ["sourceManifest"] = path, ["sourceManifestHash"] = sourceManifestHash, ["timestamp"] = DateTimeOffset.UtcNow.ToString("O"), ["nativeExecution"] = false });
        Save();
        if (!resumePreprocessing)
            await RunStage("preprocess", ancestry, (stage, token) => ImportReusePreprocessing(stage, donor, donorDataset, ownSet, sourceManifestHash, token), cancellation);
        await RunStage("reconstruct", ancestry.Concat(RequireStage("preprocess").Outputs.Keys), (stage, token) => ImportReuseReconstruction(stage, donor, sourceManifestHash, token), cancellation);
        m.History.Add(new JsonObject { ["event"] = "multi-view-reuse-complete", ["sourceManifest"] = path, ["sourceManifestHash"] = sourceManifestHash, ["nativeExecution"] = false, ["preprocessingApproval"] = "pending", ["independentReview"] = "pending", ["humanAcceptance"] = "pending" });
        Save();
    }
    static JsonObject ReuseClassification(JsonObject report, Dictionary<string, JsonObject> sources)
    {
        var result = report.DeepClone().AsObject(); result.Remove("sourceSetHash");
        void Normalize(JsonNode? node)
        {
            if (node is JsonObject value)
            {
                if (value["sourceId"] is JsonValue single) value["sourceId"] = PreparationText(sources[single.GetValue<string>()], "sha256");
                if (value["sourceIds"] is JsonArray many) value["sourceIds"] = new JsonArray(many.Select(id => PreparationText(sources[id!.GetValue<string>()], "sha256")).Order(StringComparer.Ordinal).Select(id => JsonValue.Create(id)).ToArray());
                foreach (var child in value.ToArray()) Normalize(child.Value);
            }
            else if (node is JsonArray array) foreach (var child in array) Normalize(child);
        }
        Normalize(result);
        foreach (var key in new[] { "sources", "sourceViews" }) result[key] = new JsonArray(result[key]!.AsArray().Select(node => node!.DeepClone()).OrderBy(node => node["sourceId"]!.GetValue<string>(), StringComparer.Ordinal).ToArray());
        return result;
    }
    static JsonObject ReuseProofIdentity(JsonObject report, Dictionary<string, JsonObject> sources)
    {
        return new JsonObject
        {
            ["camera"] = report["camera"]!.DeepClone(),
            ["views"] = new JsonArray(report["views"]!.AsArray().Select(node =>
            {
                var view = node!.AsObject();
                return (JsonNode)new JsonObject { ["view"] = PreparationText(view, "view"), ["sha256"] = PreparationText(view, "sha256"), ["origin"] = PreparationText(view, "origin"), ["sourceHashes"] = new JsonArray(view["sourceIds"]!.AsArray().Select(id => PreparationText(sources[id!.GetValue<string>()], "sha256")).Order(StringComparer.Ordinal).Select(hash => JsonValue.Create(hash)).ToArray()), ["cameraToWorld"] = view["cameraToWorld"]!.DeepClone(), ["cameraAngleX"] = view["cameraAngleX"]?.DeepClone(), ["width"] = view["width"]!.DeepClone(), ["height"] = view["height"]!.DeepClone() };
            }).ToArray())
        };
    }
    void ValidateReuseReconstructionReceipt()
    {
        var receipt = w.Load<JsonObject>(Artifact("reconstruct", "inputReceipt"));
        var datasetPath = Artifact("reconstruct", "submittedDataset");
        var dataset = w.Load<JsonObject>(datasetPath);
        ValidateMultiViewDataset(dataset);
        var output = Artifact("reconstruct", "glb");
        if (receipt["mode"]?.GetValue<string>() != "multi-view" || receipt["viewCount"]?.GetValue<int>() != 6 || receipt["dataset"]?.GetValue<string>() != datasetPath || receipt["datasetSha256"]?.GetValue<string>() != Hash(datasetPath) || receipt["transformsSha256"]?.GetValue<string>() != Hash(ViewText(dataset, "transforms")) || receipt["output"]?.GetValue<string>() != output || receipt["outputSha256"]?.GetValue<string>() != Hash(output) || !JsonNode.DeepEquals(receipt["views"], dataset["views"])) throw new InvalidOperationException("Donor reconstruction does not bind its actual complete six-frame input/output dataset");
        var gltf = ReadGlbJson(output);
        if (gltf["asset"]?["version"]?.GetValue<string>() != "2.0" || gltf["meshes"] is not JsonArray meshes || !meshes.Any(mesh => mesh?["primitives"] is JsonArray primitives && primitives.Count > 0)) throw new InvalidOperationException("Donor reconstruction has no actual GLB mesh");
    }
    Dictionary<string, string> CopyReuseAttempt(OpenCaw.ProofToModel.Domain.Stage target, Pipeline donor, string name, CancellationToken cancellation)
    {
        var source = donor.RequireStage(name);
        if (!source.Attempt.StartsWith(donor.m.Staging + "/attempts/", StringComparison.Ordinal)) throw new InvalidOperationException("Donor attempt escapes its immutable staging tree");
        var map = new Dictionary<string, string>(StringComparer.Ordinal);
        var retained = new List<string>();
        var directories = new Stack<string>(); directories.Push(w.Resolve(source.Attempt));
        var visitedDirectories = 0;
        while (directories.Count > 0)
        {
            cancellation.ThrowIfCancellationRequested();
            var directory = w.Resolve(directories.Pop());
            if (++visitedDirectories > 10000) throw new InvalidOperationException("Donor attempt directory inventory exceeds reuse bounds");
            foreach (var child in Directory.EnumerateDirectories(directory)) directories.Push(w.Resolve(child));
            foreach (var file in Directory.EnumerateFiles(directory))
            {
                retained.Add(w.Resolve(file));
                if (retained.Count > 10000) throw new InvalidOperationException("Donor attempt file inventory exceeds reuse bounds");
            }
        }
        var files = retained.ToArray();
        if (files.Length is < 1 or > 10000) throw new InvalidOperationException("Donor attempt file inventory is empty or exceeds reuse bounds");
        var bytes = files.Sum(file => new FileInfo(w.Resolve(file)).Length);
        if (bytes > 64L * 1024 * 1024 * 1024) throw new InvalidOperationException("Donor attempt exceeds the 64 GiB reuse-copy budget");
        var drive = new DriveInfo(Path.GetPathRoot(w.Root)!);
        if (drive.AvailableFreeSpace < bytes) throw new InvalidOperationException("Insufficient free space for immutable reuse copies");
        foreach (var file in files)
        {
            cancellation.ThrowIfCancellationRequested();
            var original = w.Relative(file);
            var relative = Path.GetRelativePath(w.Resolve(source.Attempt), w.Resolve(original)).Replace('\\', '/');
            var copied = target.Attempt + "/donor-" + name + "/" + relative;
            Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(copied))!);
            File.Copy(w.Resolve(original), w.Resolve(copied), false);
            if (Hash(original) != Hash(copied)) throw new InvalidOperationException("Immutable donor copy hash mismatch");
            target.Inputs[original] = Hash(original); map[original] = copied;
            target.Artifacts["donor-file-" + map.Count] = copied;
        }
        foreach (var artifact in source.Artifacts)
            if (!map.ContainsKey(artifact.Value)) throw new InvalidOperationException("Donor stage artifact is outside its declared attempt; explicit adaptation is required");
        target.ExternalInputs = new(source.ExternalInputs);
        return map;
    }
    static void RebindReusePaths(JsonNode? node, IReadOnlyDictionary<string, string> map)
    {
        if (node is JsonObject value)
        {
            foreach (var pair in value.ToArray())
            {
                if (pair.Value is JsonValue text && text.TryGetValue<string>(out var path) && map.TryGetValue(path, out var replacement)) value[pair.Key] = replacement;
                else RebindReusePaths(pair.Value, map);
            }
        }
        else if (node is JsonArray array)
            for (var index = 0; index < array.Count; index++)
            {
                if (array[index] is JsonValue text && text.TryGetValue<string>(out var path) && map.TryGetValue(path, out var replacement)) array[index] = replacement;
                else RebindReusePaths(array[index], map);
            }
    }
    Task ImportReusePreprocessing(OpenCaw.ProofToModel.Domain.Stage stage, Pipeline donor, JsonObject donorDataset, JsonObject ownSet, string sourceManifestHash, CancellationToken cancellation)
    {
        var copies = CopyReuseAttempt(stage, donor, "preprocess", cancellation);
        var paths = new Dictionary<string, string>(copies, StringComparer.Ordinal);
        var sourceViews = donor.CurrentProofSet()["views"]!.AsArray();
        for (var index = 0; index < 6; index++) paths[PreparationText(sourceViews[index]!.AsObject(), "image")] = PreparationText(ownSet["views"]![index]!.AsObject(), "image");
        var dataset = ownSet.DeepClone().AsObject();
        var views = new JsonArray();
        for (var index = 0; index < 6; index++)
        {
            var own = ownSet["views"]![index]!.DeepClone().AsObject(); var source = donorDataset["views"]![index]!.AsObject();
            foreach (var key in new[] { "image", "sha256", "mask", "maskSha256", "cameraAngleX", "normalization" }) own[key] = source[key]!.DeepClone();
            RebindReusePaths(own, paths);
            own["approvedImage"] = ownSet["views"]![index]!["image"]!.DeepClone(); own["approvedSha256"] = ownSet["views"]![index]!["sha256"]!.DeepClone();
            views.Add(own);
        }
        dataset["views"] = views;
        dataset["approvedProofSet"] = m.ProofSet; dataset["approvedProofSetSha256"] = Hash(m.ProofSet); dataset["approvalFingerprint"] = ApprovalFingerprint("proof-set");
        dataset["transforms"] = copies[donor.Artifact("preprocess", "transforms")]; dataset["transformsSha256"] = Hash(ViewText(dataset, "transforms"));
        dataset["engineExportFrame"] = "pixal3d-mv-export"; dataset["sixViewNativeAcceptance"] = "not-established-by-reuse";
        var report = stage.Attempt + "/dataset.json"; w.Save(report, dataset);
        stage.Artifacts["dataset"] = report; stage.Artifacts["transforms"] = ViewText(dataset, "transforms"); stage.Artifacts["normalized"] = ViewText(views[0]!.AsObject(), "image");
        ValidateMultiViewDataset(dataset);
        WriteReuseReceipt(stage, donor, "preprocess", copies, sourceManifestHash);
        return Task.CompletedTask;
    }
    Task ImportReuseReconstruction(OpenCaw.ProofToModel.Domain.Stage stage, Pipeline donor, string sourceManifestHash, CancellationToken cancellation)
    {
        var copies = CopyReuseAttempt(stage, donor, "reconstruct", cancellation);
        var sourceSubmitted = w.Load<JsonObject>(donor.Artifact("reconstruct", "submittedDataset"));
        var sourceViews = sourceSubmitted["views"]!.AsArray();
        var ownDataset = w.Load<JsonObject>(Artifact("preprocess", "dataset"));
        var dataset = ownDataset.DeepClone().AsObject();
        var transforms = copies[donor.Artifact("reconstruct", "submittedTransforms")];
        dataset["transforms"] = transforms; dataset["transformsSha256"] = Hash(transforms);
        for (var index = 0; index < 6; index++) dataset["views"]![index]!["image"] = copies[ViewText(sourceViews[index]!.AsObject(), "image")];
        var submitted = stage.Attempt + "/submitted-dataset.json"; w.Save(submitted, dataset);
        stage.Artifacts["submittedDataset"] = submitted; stage.Artifacts["submittedTransforms"] = transforms;
        var glb = copies[donor.Artifact("reconstruct", "glb")]; stage.Artifacts["glb"] = glb;
        ValidateMultiViewDataset(dataset);
        var receipt = stage.Attempt + "/reconstruction-inputs.json";
        w.Save(receipt, new JsonObject { ["schemaVersion"] = 1, ["mode"] = "multi-view", ["viewCount"] = 6, ["operation"] = "reuse", ["nativeExecution"] = false, ["sourceManifest"] = donor.manifestPath, ["sourceManifestHash"] = sourceManifestHash, ["sourceInputReceipt"] = copies[donor.Artifact("reconstruct", "inputReceipt")], ["sourceInputReceiptHash"] = Hash(donor.Artifact("reconstruct", "inputReceipt")), ["dataset"] = submitted, ["datasetSha256"] = Hash(submitted), ["transformsSha256"] = Hash(transforms), ["views"] = dataset["views"]!.DeepClone(), ["output"] = glb, ["outputSha256"] = Hash(glb), ["engineExportFrame"] = "pixal3d-mv-export", ["upstreamValidationLimit"] = "Reused hash-bound six-frame artifacts; no new inference or six-view visual acceptance is asserted" });
        stage.Artifacts["inputReceipt"] = receipt;
        WriteReuseReceipt(stage, donor, "reconstruct", copies, sourceManifestHash);
        return Task.CompletedTask;
    }
    void WriteReuseReceipt(OpenCaw.ProofToModel.Domain.Stage stage, Pipeline donor, string name, Dictionary<string, string> copies, string sourceManifestHash)
    {
        var receipt = stage.Attempt + "/reuse.json";
        w.Save(receipt, new JsonObject { ["schemaVersion"] = 1, ["operation"] = "reuse", ["nativeExecution"] = false, ["sourceManifest"] = donor.manifestPath, ["sourceManifestHash"] = sourceManifestHash, ["sourceStage"] = name, ["sourceAttempt"] = donor.RequireStage(name).Attempt, ["sourceFingerprint"] = donor.RequireStage(name).Fingerprint, ["ownProofSet"] = m.ProofSet, ["ownProofSetHash"] = Hash(m.ProofSet), ["copies"] = new JsonArray(copies.Select(pair => (JsonNode)new JsonObject { ["source"] = pair.Key, ["destination"] = pair.Value, ["sha256"] = Hash(pair.Value) }).ToArray()), ["preprocessingApproval"] = "pending", ["independentReview"] = "pending", ["humanAcceptance"] = "pending" });
        stage.Artifacts["reuseReceipt"] = receipt;
    }
}
