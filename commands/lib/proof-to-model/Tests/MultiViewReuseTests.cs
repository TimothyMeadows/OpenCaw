using System.Text;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;

static class MultiViewReuseTests
{
    sealed class NoNative : INativeProcess
    {
        public int Calls { get; private set; }
        public Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
        { Calls++; throw new InvalidOperationException("Reuse fixture forbids native process launches"); }
    }
    sealed class CancelAfterImportedPreprocessing(Workspace inner, string asset, CancellationTokenSource cancellation) : IWorkspace
    {
        public string Root => inner.Root;
        public bool Triggered { get; private set; }
        public string Resolve(string path) => inner.Resolve(path);
        public string Relative(string path) => inner.Relative(path);
        public string HashFile(string path) => inner.HashFile(path);
        public T Load<T>(string path) => inner.Load<T>(path);
        public FileStream Lock(string path) => inner.Lock(path);
        public void Save<T>(string path, T value)
        {
            inner.Save(path, value);
            if (!Triggered && value is Manifest state && state.Asset == asset && state.Stages.TryGetValue("preprocess", out var stage) && stage.Status == "complete" && !state.Stages.ContainsKey("reconstruct"))
            { Triggered = true; cancellation.Cancel(); }
        }
    }
    public static async Task Run(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var directory = parent.Resolve("multi-view-reuse-fixtures"); Directory.CreateDirectory(directory);
        var w = new Workspace(directory); var native = new NoNative();
        File.WriteAllText(w.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL\n");
        w.Save("rights.json", new { authorized = true, reuseAuthorized = true, source = "Controlled fixture, not production rights" });
        w.Save("brief.json", new { purpose = "Synthetic reuse contract fixture", scale = new { units = "metres", metersPerUnit = 1 }, interfaces = Array.Empty<string>() });
        w.Save("recipe.json", new { targetFaces = 100, textureSize = 32, cageExtrusion = .1, maxRayDistance = .1, uvMargin = .01, lodRatios = new[] { .5 }, colliderMaxFaces = 100, maxTriangles = 1000, maxMaterials = 3, maxTextureBytes = 100000, parts = Array.Empty<string>(), riggingRequired = false, animationRequired = false, proofPreparation = new { maxSetRevisions = 20 } });
        var modelNames = new[] { "dinov3.gguf", "pixal3d_naf.gguf", "pixal3d_ss_flow_mv.gguf", "pixal3d_shape_flow_512_mv.gguf", "pixal3d_shape_flow_1024_mv.gguf", "pixal3d_tex_flow_1024_mv.gguf", "ss_dec.gguf", "shape_dec.gguf", "tex_dec.gguf" };
        Directory.CreateDirectory(w.Resolve(".local/fixture-models"));
        var models = new JsonArray();
        foreach (var name in modelNames)
        {
            var path = ".local/fixture-models/" + name; File.WriteAllText(w.Resolve(path), "NOT MODEL WEIGHTS: " + name);
            models.Add(new JsonObject { ["path"] = path, ["sha256"] = w.HashFile(w.Resolve(path)), ["licenseAccepted"] = true, ["license"] = "synthetic-fixture-only" });
        }
        w.Save("toolchain.json", new JsonObject { ["schemaVersion"] = 1, ["modelFamily"] = "mv", ["viewCount"] = 6, ["modelDir"] = ".local/fixture-models", ["models"] = models, ["files"] = new JsonArray(), ["limits"] = new JsonObject { ["maxAttempts"] = 10, ["timeoutSeconds"] = 10 } });
        for (var index = 0; index < 6; index++)
        {
            var pixels = new byte[16 * 16 * 4];
            for (var y = 0; y < 16; y++) for (var x = 0; x < 16; x++)
            {
                var at = (y * 16 + x) * 4; pixels[at] = (byte)(40 + index * 25); pixels[at + 1] = 100; pixels[at + 2] = 140; pixels[at + 3] = x is > 1 and < 14 && y is > 1 and < 14 ? (byte)255 : (byte)0;
            }
            RgbaPng.Write(w.Resolve("original-" + index + ".png"), new RgbaPng.Image(16, 16, pixels));
        }
        async Task Execute(Dictionary<string, string> settings, string command, CancellationToken cancellation = default) => await new Pipeline(w, settings, native, new AlphaProcessor()).Execute(command, cancellation);
        Manifest State(Dictionary<string, string> settings) => w.Load<Manifest>(settings["manifest"]);
        async Task Approve(Dictionary<string, string> settings, string kind, string reviewer)
        {
            var capture = new StringWriter(); var previous = Console.Out;
            try { Console.SetOut(capture); await Execute(settings, "status"); } finally { Console.SetOut(previous); }
            var key = kind == "proof-set" ? "proofSet" : kind;
            var fingerprint = JsonNode.Parse(capture.ToString())!["approvalFingerprints"]![key]!.GetValue<string>();
            var path = ".opencaw/.cache/tasks/reuse-tests/reviews/" + State(settings).Asset + "-" + kind + ".json";
            w.Save(path, new { kind, reviewer, fingerprint, decision = "approved", human = true, reason = "SYNTHETIC FIXTURE ASSERTION; not actual person, production review or native acceptance" });
            settings["kind"] = kind; settings["reviewer"] = reviewer; settings["evidence"] = path;
            await Execute(settings, "record");
        }
        async Task<Dictionary<string, string>> Asset(string name, string prefix, bool approval = true, bool differentClassification = false)
        {
            var sources = new JsonArray(Enumerable.Range(0, 6).Select(index => (JsonNode)new JsonObject { ["id"] = prefix + index, ["path"] = "original-" + index + ".png" }).ToArray());
            var sourcePath = name + "-sources.json"; w.Save(sourcePath, new JsonObject { ["schemaVersion"] = 1, ["images"] = sources });
            var settings = new Dictionary<string, string> { ["task"] = "reuse-tests", ["asset"] = name, ["version"] = "v1", ["actor"] = "fixture-builder", ["sources"] = sourcePath, ["rights"] = "rights.json", ["brief"] = "brief.json", ["recipe"] = "recipe.json", ["toolchain"] = "toolchain.json" };
            await Execute(settings, "init"); settings["manifest"] = ".opencaw/.cache/tasks/reuse-tests/proof-to-model/" + name + "/v1/manifest.json";
            var classification = PreparationTests.Classification(w, State(settings));
            if (differentClassification) classification["subjects"]![0]!["classification"] = "Different approved structural interpretation";
            var analysisPath = name + "-classification.json"; w.Save(analysisPath, classification); settings["classification"] = analysisPath; await Execute(settings, "classify");
            var proofPath = name + "-proofs.json"; w.Save(proofPath, PreparationTests.ProofSet(w, State(settings))); settings["proof-set"] = proofPath; await Execute(settings, "prepare-proofs");
            if (approval) await Approve(settings, "proof-set", "fixture-proof-owner");
            return settings;
        }
        var donor = await Asset("approved-donor", "donor-");
        await Execute(donor, "preprocess"); await Approve(donor, "preprocessing", "fixture-input-reviewer");
        var donorState = State(donor);
        var reconstruction = new Stage { Status = "complete", Attempt = donorState.Staging + "/attempts/reconstruct-controlled", Inputs = new(donorState.Stages["preprocess"].Outputs) };
        Directory.CreateDirectory(w.Resolve(reconstruction.Attempt + "/submitted"));
        var dataset = w.Load<JsonObject>(donorState.Stages["preprocess"].Artifacts["dataset"]);
        var nativeFrames = w.Load<JsonObject>(dataset["transforms"]!.GetValue<string>());
        for (var index = 0; index < 6; index++)
        {
            var view = dataset["views"]![index]!.AsObject(); var path = reconstruction.Attempt + "/submitted/" + nativeFrames["frames"]![index]!["file_path"]!.GetValue<string>();
            File.Copy(w.Resolve(view["image"]!.GetValue<string>()), w.Resolve(path)); view["image"] = path; reconstruction.Artifacts["input-" + index] = path;
        }
        var transforms = reconstruction.Attempt + "/submitted/transforms.json"; w.Save(transforms, nativeFrames); dataset["transforms"] = transforms; dataset["transformsSha256"] = w.HashFile(w.Resolve(transforms));
        var submitted = reconstruction.Attempt + "/submitted-dataset.json"; w.Save(submitted, dataset);
        var raw = reconstruction.Attempt + "/raw.glb"; WriteFixtureGlb(w.Resolve(raw));
        var receipt = reconstruction.Attempt + "/reconstruction-inputs.json";
        w.Save(receipt, new JsonObject { ["schemaVersion"] = 1, ["mode"] = "multi-view", ["viewCount"] = 6, ["nativeExecution"] = false, ["simulatedProcessFixture"] = true, ["dataset"] = submitted, ["datasetSha256"] = w.HashFile(w.Resolve(submitted)), ["transformsSha256"] = w.HashFile(w.Resolve(transforms)), ["views"] = dataset["views"]!.DeepClone(), ["output"] = raw, ["outputSha256"] = w.HashFile(w.Resolve(raw)) });
        File.WriteAllText(w.Resolve(reconstruction.Attempt + "/process.log"), "CONTROLLED STATE FIXTURE; no reconstruction process executed\n");
        reconstruction.Artifacts["submittedDataset"] = submitted; reconstruction.Artifacts["submittedTransforms"] = transforms; reconstruction.Artifacts["inputReceipt"] = receipt; reconstruction.Artifacts["glb"] = raw;
        foreach (var artifact in reconstruction.Artifacts.Values) reconstruction.Outputs[artifact] = w.HashFile(w.Resolve(artifact));
        reconstruction.Fingerprint = FixtureFingerprint(w, reconstruction.Inputs.Keys); donorState.Stages["reconstruct"] = reconstruction;
        foreach (var name in new[] { "finish", "review" })
        {
            var stage = new Stage { Status = "complete", Attempt = donorState.Staging + "/attempts/" + name + "-controlled", Inputs = new(reconstruction.Outputs) };
            Directory.CreateDirectory(w.Resolve(stage.Attempt)); var report = stage.Attempt + "/fixture-report.json";
            w.Save(report, new { simulatedStateFixture = true, nativeEditorOrInferenceResult = false, stage = name }); stage.Artifacts["fixture"] = report; stage.Outputs[report] = w.HashFile(w.Resolve(report)); stage.Fingerprint = FixtureFingerprint(w, stage.Inputs.Keys); donorState.Stages[name] = stage;
        }
        w.Save(donor["manifest"], donorState); await Approve(donor, "independent", "fixture-independent-critic"); await Approve(donor, "human", "fixture-runtime-owner");
        await Execute(donor, "validate");
        check(native.Calls == 0, "controlled approved-donor fixture uses real image preparation but no inference/editor process");
        var target = await Asset("reuse-target", "target-"); target["reuse-manifest"] = donor["manifest"];
        var unapproved = await Asset("unapproved-target", "unapproved-", false); unapproved["reuse-manifest"] = donor["manifest"];
        await reject(() => Execute(unapproved, "reuse"), "target cannot inherit donor proof approval");
        check(!State(unapproved).Stages.ContainsKey("preprocess"), "missing target approval blocks before importing donor bytes");
        var before = State(target);
        var v1 = State(donor); v1.SchemaVersion = 1; var v1Path = Path.GetDirectoryName(donor["manifest"])!.Replace('\\', '/') + "/v1-diagnostic.json"; w.Save(v1Path, v1);
        target["reuse-manifest"] = v1Path; await reject(() => Execute(target, "reuse"), "single-view donor cannot satisfy six-view reuse");
        var missing = State(donor); missing.Approvals.RemoveAll(approval => approval.Kind == "human"); var missingPath = Path.GetDirectoryName(donor["manifest"])!.Replace('\\', '/') + "/unapproved.json"; w.Save(missingPath, missing);
        target["reuse-manifest"] = missingPath; await reject(() => Execute(target, "reuse"), "donor requires current separate human runtime acceptance");
        target["reuse-manifest"] = donor["manifest"];
        var rawBytes = File.ReadAllBytes(w.Resolve(raw)); File.AppendAllText(w.Resolve(raw), "corrupt");
        await reject(() => Execute(target, "reuse"), "stale donor output cannot be imported despite prior approvals"); File.WriteAllBytes(w.Resolve(raw), rawBytes);
        var different = await Asset("different-interpretation", "other-", differentClassification: true); different["reuse-manifest"] = donor["manifest"];
        await reject(() => Execute(different, "reuse"), "matching source bytes cannot bypass conflicting structural classification");
        check(!State(target).Stages.ContainsKey("preprocess") && !State(different).Stages.ContainsKey("preprocess"), "incompatible donors fail before reuse stage writes");
        var donorHash = w.HashFile(w.Resolve(donor["manifest"])); await Execute(target, "reuse");
        var reused = State(target); var prepared = w.Load<JsonObject>(reused.Stages["preprocess"].Artifacts["dataset"]); var imported = w.Load<JsonObject>(reused.Stages["reconstruct"].Artifacts["submittedDataset"]);
        check(reused.Stages["preprocess"].Status == "complete" && reused.Stages["reconstruct"].Status == "complete", "explicit reuse imports both validated preprocessing and raw reconstruction stages");
        check(native.Calls == 0, "reuse performs no model, Blender or native process execution");
        check(w.HashFile(w.Resolve(reused.Stages["reconstruct"].Artifacts["glb"])) == w.HashFile(w.Resolve(raw)), "reused reconstruction preserves exact donor GLB bytes");
        check(prepared["approvedProofSet"]!.GetValue<string>() == reused.ProofSet && prepared["approvedProofSetSha256"]!.GetValue<string>() == w.HashFile(w.Resolve(reused.ProofSet)), "prepared dataset is rebound to the target's own approved proof-set identity");
        check(Enumerable.Range(0, 6).All(index => prepared["views"]![index]!["approvedImage"]!.GetValue<string>() == w.Load<JsonObject>(reused.ProofSet)["views"]![index]!["image"]!.GetValue<string>()), "all six prepared frames bind target approved images across different asset-local paths");
        check(Enumerable.Range(0, 6).All(index => imported["views"]![index]!["image"]!.GetValue<string>().StartsWith(reused.Stages["reconstruct"].Attempt + "/", StringComparison.Ordinal)), "all actual reused inference frames are immutable target-local copies");
        var importReceipt = w.Load<JsonObject>(reused.Stages["reconstruct"].Artifacts["inputReceipt"]);
        check(importReceipt["operation"]!.GetValue<string>() == "reuse" && !importReceipt["nativeExecution"]!.GetValue<bool>(), "new receipt honestly reports reuse rather than pretending to execute inference");
        check(w.HashFile(w.Resolve(importReceipt["sourceInputReceipt"]!.GetValue<string>())) == w.HashFile(w.Resolve(receipt)), "raw donor input receipt is copied byte-for-byte with complete original ancestry");
        check(reused.Approvals.Count == 1 && reused.Approvals[0].Kind == "proof-set", "donor approvals never become target preprocessing, independent or human acceptance");
        await reject(() => Execute(target, "finish"), "reused bytes cannot bypass new target preprocessing approval");
        await reject(() => Execute(target, "validate"), "validation reports pending target preprocessing acceptance explicitly");
        await Approve(target, "preprocessing", "new-fixture-input-reviewer"); await Execute(target, "validate");
        check(State(target).Approvals.Any(approval => approval.Kind == "preprocessing") && !State(target).Approvals.Any(approval => approval.Kind is "independent" or "human"), "new preprocessing acceptance validates rebound artifacts while final review remains pending");
        check(w.HashFile(w.Resolve(donor["manifest"])) == donorHash && State(target).History.Any(item => item["event"]?.GetValue<string>() == "multi-view-reuse-complete"), "reuse preserves donor state and records durable copy ancestry");
        await reject(() => Execute(target, "reuse"), "a second reuse cannot overwrite an existing completed reconstruction");
        var ownRaw = reused.Stages["reconstruct"].Artifacts["glb"]; var ownBytes = File.ReadAllBytes(w.Resolve(ownRaw)); File.AppendAllText(w.Resolve(ownRaw), "tamper");
        await reject(() => Execute(target, "validate"), "tampered target copy invalidates reuse evidence"); File.WriteAllBytes(w.Resolve(ownRaw), ownBytes);
        var interrupted = await Asset("interrupted-reuse", "resume-"); interrupted["reuse-manifest"] = donor["manifest"];
        using (var interruption = new CancellationTokenSource())
        {
            var guarded = new CancelAfterImportedPreprocessing(w, State(interrupted).Asset, interruption);
            await reject(() => new Pipeline(guarded, interrupted, native, new AlphaProcessor()).Execute("reuse", interruption.Token), "reuse interruption after persisted preprocessing fails the remaining reconstruction import");
            var partial = State(interrupted);
            check(guarded.Triggered && partial.Stages["preprocess"].Status == "complete" && partial.Stages["reconstruct"].Status == "failed", "cancellation fixture actually preserves completed preprocessing and failed reconstruction state");
            var attempt = partial.Stages["preprocess"].Attempt;
            var report = partial.Stages["preprocess"].Artifacts["dataset"];
            var reportHash = w.HashFile(w.Resolve(report));
            var preparedHashes = partial.Stages["preprocess"].Outputs.ToDictionary(pair => pair.Key, pair => pair.Value);
            await Execute(interrupted, "reuse");
            var recovered = State(interrupted);
            check(recovered.Stages["preprocess"].Attempt == attempt && w.HashFile(w.Resolve(report)) == reportHash && preparedHashes.All(pair => w.HashFile(w.Resolve(pair.Key)) == pair.Value), "interrupted reuse resumes exact existing preprocessing bytes and approval bindings without recopying");
            check(recovered.Stages["reconstruct"].Status == "complete" && recovered.Stages["reconstruct"].Attempt != partial.Stages["reconstruct"].Attempt, "reuse recovery completes reconstruction in a new immutable attempt");
            check(recovered.Approvals.Count == 1 && recovered.Approvals[0].Kind == "proof-set" && w.HashFile(w.Resolve(donor["manifest"])) == donorHash && native.Calls == 0, "recovery leaves new preprocessing/final acceptance pending, donor unchanged and native execution absent");
        }
        var cancelled = await Asset("cancelled-target", "cancelled-"); cancelled["reuse-manifest"] = donor["manifest"]; using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
        await reject(() => Execute(cancelled, "reuse", cancellation.Token), "cancelled reuse stops before copying production evidence");
        check(!State(cancelled).Stages.ContainsKey("preprocess") && native.Calls == 0, "cancelled reuse leaves no imported stages or native launch");
    }
    static string FixtureFingerprint(Workspace w, IEnumerable<string> paths) => Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", paths.Order().Select(path => path + ":" + w.HashFile(w.Resolve(path)))))));
    static void WriteFixtureGlb(string path)
    {
        var document = new JsonObject { ["asset"] = new JsonObject { ["version"] = "2.0", ["generator"] = "Controlled reuse fixture, no native inference" }, ["meshes"] = new JsonArray(new JsonObject { ["primitives"] = new JsonArray(new JsonObject { ["attributes"] = new JsonObject { ["POSITION"] = 0 } }) }) };
        var json = Encoding.UTF8.GetBytes(document.ToJsonString()); var padding = (4 - json.Length % 4) % 4;
        using var stream = File.Create(path); using var writer = new BinaryWriter(stream);
        writer.Write(0x46546c67u); writer.Write(2u); writer.Write((uint)(20 + json.Length + padding)); writer.Write((uint)(json.Length + padding)); writer.Write(0x4E4F534Au); writer.Write(json); writer.Write(Enumerable.Repeat((byte)32, padding).ToArray());
    }
}
