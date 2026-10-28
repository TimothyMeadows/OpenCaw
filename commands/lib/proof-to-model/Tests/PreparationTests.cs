using System.Buffers.Binary;
using System.IO.Compression;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;

static class PreparationTests
{
    public static JsonObject Classification(Workspace workspace, Manifest state)
    {
        var sources = workspace.Load<JsonObject>(state.SourceSet)["images"]!.AsArray();
        var ids = new JsonArray(sources.Select(image => JsonValue.Create(image!["id"]!.GetValue<string>())).ToArray());
        var claims = new JsonArray(new JsonObject { ["id"] = "shape", ["description"] = "Fixture color and metal <armor> label are test data, not a visual finding.", ["sourceIds"] = ids.DeepClone(), ["confidence"] = "high", ["disposition"] = "observed" });
        return new JsonObject
        {
            ["schemaVersion"] = 1, ["sourceSetHash"] = workspace.HashFile(workspace.Resolve(state.SourceSet)),
            ["sources"] = new JsonArray(sources.Select(image => (JsonNode)new JsonObject { ["sourceId"] = image!["id"]!.GetValue<string>(), ["sha256"] = image["sha256"]!.GetValue<string>() }).ToArray()),
            ["sourceViews"] = new JsonArray(sources.Select((image, index) => (JsonNode)new JsonObject { ["sourceId"] = image!["id"]!.GetValue<string>(), ["view"] = MultiViewGeometry.Views[index % 6], ["usable"] = true, ["reason"] = "Controlled synthetic view fixture; not measured calibration" }).ToArray()),
            ["researchStatus"] = "not-required", ["researchReason"] = "Controlled geometric fixture; this report does not certify actual anatomy or research.",
            ["research"] = new JsonArray(),
            ["subjects"] = new JsonArray(new JsonObject
            {
                ["id"] = "fixture", ["kind"] = "nonliving", ["classification"] = "Synthetic engineering images", ["sourceIds"] = ids.DeepClone(),
                ["claims"] = claims,
                ["parts"] = new JsonArray(new JsonObject { ["id"] = "body", ["name"] = "Fixture body", ["visibility"] = "visible", ["disposition"] = "observed", ["sourceIds"] = ids.DeepClone(), ["claimIds"] = new JsonArray("shape") })
            }),
            ["relations"] = new JsonArray(), ["unknowns"] = new JsonArray(), ["conflicts"] = new JsonArray(),
            ["preservationConstraints"] = new JsonArray("Preserve original fixture identities"), ["prohibitedSubstitutions"] = new JsonArray("Do not claim these fixtures prove anatomical correctness")
        };
    }
    public static JsonObject ProofSet(Workspace workspace, Manifest state)
    {
        var images = workspace.Load<JsonObject>(state.SourceSet)["images"]!.AsArray();
        if (images.Count != 6) throw new InvalidOperationException("All-source proof fixture requires six actual originals");
        return new JsonObject
        {
            ["schemaVersion"] = 1, ["revision"] = 1,
            ["sourceSetHash"] = workspace.HashFile(workspace.Resolve(state.SourceSet)), ["classificationHash"] = workspace.HashFile(workspace.Resolve(state.Classification)),
            ["camera"] = new JsonObject { ["convention"] = "blender-nerf-z-up", ["calibration"] = "nominal-prescribed", ["meshScale"] = 1, ["cameraAngleX"] = 0.3490658503988659, ["distance"] = 3.1192049980163574 },
            ["views"] = new JsonArray(MultiViewGeometry.Views.Select((name, index) => (JsonNode)new JsonObject
            {
                ["view"] = name, ["image"] = images[index]!["path"]!.GetValue<string>(), ["sha256"] = images[index]!["sha256"]!.GetValue<string>(),
                ["origin"] = "source", ["sourceIds"] = new JsonArray(images[index]!["id"]!.GetValue<string>()), ["revision"] = 1, ["cameraToWorld"] = MultiViewGeometry.Matrix(name)
            }).ToArray())
        };
    }
    public static async Task Run(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var root = parent.Resolve("source-preparation-fixtures"); Directory.CreateDirectory(root);
        var w = new Workspace(root);
        File.WriteAllText(w.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL\n");
        w.Save("rights.json", new { authorized = true, source = "Synthetic engineering fixtures" });
        w.Save("recipe.json", new { targetFaces = 100, textureSize = 32, cageExtrusion = .1, maxRayDistance = .1, uvMargin = .01, lodRatios = new[] { .5 }, colliderMaxFaces = 100, maxTriangles = 1000, maxMaterials = 3, maxTextureBytes = 100000, parts = Array.Empty<string>(), riggingRequired = false, animationRequired = false, proofPreparation = new { maxSetRevisions = 100 } });
        w.Save("toolchain.json", new { schemaVersion = 1, files = Array.Empty<object>(), models = Array.Empty<object>(), limits = new { maxAttempts = 100, timeoutSeconds = 10 } });
        var originals = new JsonArray();
        for (var i = 0; i < 6; i++)
        {
            var path = "source-" + i + ".png"; WritePng(w.Resolve(path), (byte)(30 + i * 20));
            originals.Add(new JsonObject { ["id"] = "source-" + i, ["path"] = path });
        }
        w.Save("sources.json", new JsonObject { ["schemaVersion"] = 1, ["images"] = originals });
        var options = new Dictionary<string, string> { ["task"] = "preparation", ["asset"] = "six-sources", ["version"] = "v1", ["actor"] = "fixture-builder", ["sources"] = "sources.json", ["rights"] = "rights.json", ["recipe"] = "recipe.json", ["toolchain"] = "toolchain.json" };
        async Task Run(string command) => await new Pipeline(w, options, new NativeProcess(), new AlphaProcessor()).Execute(command, default);
        await Run("init");
        var manifestPath = ".opencaw/.cache/tasks/preparation/proof-to-model/six-sources/v1/manifest.json";
        options["manifest"] = manifestPath;
        Manifest State() => w.Load<Manifest>(manifestPath);
        var initial = State();
        check(initial.SchemaVersion == 2 && w.Load<JsonObject>(initial.SourceSet)["images"]!.AsArray().Count == 6, "v2 init registers all six immutable original identities");
        check(initial.Proof.EndsWith("/original/proof.png", StringComparison.Ordinal), "primary proof remains original source, never generated front");
        await reject(() => Run("prepare-proofs"), "proof preparation cannot precede source classification");
        var classification = Classification(w, initial);
        var contaminated = classification.DeepClone().AsObject();
        contaminated["sources"]![0]!["sourceId"] = "generated-front";
        w.Save("classification-contaminated.json", contaminated); options["classification"] = "classification-contaminated.json";
        await reject(() => Run("classify"), "classification rejects generated or renamed evidence IDs");
        contaminated = classification.DeepClone().AsObject(); contaminated["sources"]![0]!["sha256"] = new string('0', 64);
        w.Save("classification-hash.json", contaminated); options["classification"] = "classification-hash.json";
        await reject(() => Run("classify"), "classification rejects substituted original hashes");
        contaminated = classification.DeepClone().AsObject(); contaminated["subjects"]![0]!["claims"]![0]!["image"] = "unregistered-proof.png";
        w.Save("classification-hidden-proof.json", contaminated); options["classification"] = "classification-hidden-proof.json";
        await reject(() => Run("classify"), "classification rejects hidden proof-image fields instead of ignoring them");
        contaminated = classification.DeepClone().AsObject(); contaminated["subjects"]![0]!["claims"]![0]!["disposition"] = "research-inferred";
        w.Save("classification-inference.json", contaminated); options["classification"] = "classification-inference.json";
        await reject(() => Run("classify"), "inferred anatomy cannot claim research without supporting records");
        contaminated = classification.DeepClone().AsObject(); contaminated["subjects"]![0]!["parts"]![0]!["visibility"] = "hidden";
        w.Save("classification-hidden-observed.json", contaminated); options["classification"] = "classification-hidden-observed.json";
        await reject(() => Run("classify"), "fully hidden parts cannot be falsely described as observed anatomy");
        contaminated = classification.DeepClone().AsObject(); contaminated["subjects"]![0]!["parts"]![0]!["disposition"] = "research-inferred";
        w.Save("classification-part-inference.json", contaminated); options["classification"] = "classification-part-inference.json";
        await reject(() => Run("classify"), "inferred parts require matching inference claims and research support");
        w.Save("classification.json", classification); options["classification"] = "classification.json"; await Run("classify");
        check(State().Stages["classify"].Status == "complete" && File.Exists(w.Resolve(State().Classification)), "source-only report imports into immutable classification attempt");
        var coverage = w.Load<JsonObject>(State().Stages["classify"].Artifacts["proof-plan"]);
        check(coverage["minimumGeneratedViews"]!.GetValue<int>() == 0 && coverage["generationExecution"]!.GetValue<bool>() == false, "six usable original angles produce an honest zero-generation coverage plan");
        var proofs = ProofSet(w, State());
        var invalid = proofs.DeepClone().AsObject(); invalid["views"]!.AsArray().RemoveAt(5);
        w.Save("proofs-missing.json", invalid); options["proof-set"] = "proofs-missing.json";
        await reject(() => Run("prepare-proofs"), "five images cannot satisfy six-view preparation");
        invalid = proofs.DeepClone().AsObject(); invalid["views"]![1]!["image"] = invalid["views"]![0]!["image"]!.GetValue<string>(); invalid["views"]![1]!["sha256"] = invalid["views"]![0]!["sha256"]!.GetValue<string>();
        w.Save("proofs-duplicate.json", invalid); options["proof-set"] = "proofs-duplicate.json";
        await reject(() => Run("prepare-proofs"), "duplicate bytes cannot masquerade as separate angles");
        invalid = proofs.DeepClone().AsObject();
        foreach (var key in new[] { "image", "sha256", "sourceIds" })
        {
            var previous = invalid["views"]![1]![key]!.DeepClone(); invalid["views"]![1]![key] = invalid["views"]![2]![key]!.DeepClone(); invalid["views"]![2]![key] = previous;
        }
        w.Save("proofs-wrong-angle.json", invalid); options["proof-set"] = "proofs-wrong-angle.json";
        await reject(() => Run("prepare-proofs"), "an original back image cannot silently fill the right-camera slot");
        w.Save("proofs.json", proofs); options["proof-set"] = "proofs.json"; await Run("prepare-proofs");
        var first = State(); var selected = w.Load<JsonObject>(first.ProofSet);
        check(first.Stages["prepare-proofs"].Status == "complete" && selected["views"]!.AsArray().Count == 6, "all-original six-view set is prepared without media generation");
        check(!File.Exists(w.Resolve("MEDIA.md")) && first.Approvals.Count == 0, "proof registration creates neither media contract nor human approval");
        check(selected["views"]!.AsArray().All(view => view!["image"]!.GetValue<string>().StartsWith(first.Stages["prepare-proofs"].Attempt + "/views/", StringComparison.Ordinal)), "actual selected images are copied into immutable attempt staging");
        var html = File.ReadAllText(w.Resolve(first.Stages["prepare-proofs"].Artifacts["proof-review"]));
        check(html.Contains("source-only", StringComparison.OrdinalIgnoreCase) && (html.Contains("&lt;armor&gt;", StringComparison.Ordinal) || html.Contains("\\u003Carmor\\u003E", StringComparison.Ordinal)) && !html.Contains("metal <armor>", StringComparison.Ordinal), "review packet includes safely escaped classification and all original evidence");
        var statusText = new StringWriter(); var previousOutput = Console.Out;
        try { Console.SetOut(statusText); await Run("status"); } finally { Console.SetOut(previousOutput); }
        var status = JsonNode.Parse(statusText.ToString())!.AsObject();
        var approvalPath = ".opencaw/.cache/tasks/preparation/reviews/proof-set.json";
        w.Save(approvalPath, new { kind = "proof-set", reviewer = "fixture-human", decision = "approved", human = true, reason = "SYNTHETIC TEST RECEIPT; not actual production approval", fingerprint = status["approvalFingerprints"]!["proofSet"]!.GetValue<string>() });
        options["kind"] = "proof-set"; options["reviewer"] = "fixture-human"; options["evidence"] = approvalPath; await Run("record");
        check(State().Approvals.Any(a => a.Kind == "proof-set"), "explicit whole-set synthetic human receipt is recorded separately");
        var revised = selected.DeepClone().AsObject(); revised["revision"] = 2;
        WritePng(w.Resolve("new-right.png"), 210); WritePng(w.Resolve("rejected-right.png"), 230);
        var newView = revised["views"]![1]!.AsObject(); newView["image"] = "new-right.png"; newView["sha256"] = w.HashFile(w.Resolve("new-right.png")); newView["origin"] = "generated"; newView["sourceIds"] = new JsonArray("source-0"); newView["revision"] = 2;
        var generationReceipt = ".opencaw/.cache/tasks/preparation/generation/right.json";
        newView["generationReceipt"] = generationReceipt;
        var batchReceipt = Receipt(w, State(), "run-right-1", "new-right.png", "rejected-right.png");
        batchReceipt["outputs"]!.AsArray().Add(batchReceipt["outputs"]![1]!.DeepClone());
        w.Save(generationReceipt, batchReceipt);
        w.Save("proofs-revised.json", revised); options["proof-set"] = "proofs-revised.json";
        await reject(() => Run("prepare-proofs"), "generated view registration requires explicit current media and generation authorization");
        File.WriteAllText(w.Resolve("MEDIA.md"), "Synthetic test media contract; no actual provider call is authorized or made.\n");
        var authorizationPath = ".opencaw/.cache/tasks/preparation/generation/authorization.json";
        var authorization = Authorization(w, State(), 1, 2); w.Save(authorizationPath, authorization);
        revised["generationPolicy"] = new JsonObject { ["pipeline"] = "CLOUD", ["mediaContract"] = "MEDIA.md", ["mediaContractHash"] = w.HashFile(w.Resolve("MEDIA.md")), ["authorization"] = authorizationPath };
        w.Save("proofs-budget.json", revised); options["proof-set"] = "proofs-budget.json";
        await reject(() => Run("prepare-proofs"), "image budget includes rejected batch outputs, not only selected angle");
        check(State().History.Count(item => item["event"]?.GetValue<string>() == "proof-generated-output") == 3 && State().History.Where(item => item["event"]?.GetValue<string>() == "proof-generated-output").All(item => File.Exists(w.Resolve(item["retainedReceipt"]!.GetValue<string>()))), "failed over-budget registration counts even byte-identical rejected outputs and preserves immutable receipts");
        await reject(() => Run("prepare-proofs"), "retry cannot erase an over-budget generation batch");
        check(State().History.Count(item => item["event"]?.GetValue<string>() == "proof-generated-output") == 3, "re-registering the same failed batch does not double-count retained generation");
        authorization["maxGeneratedCandidates"] = 3; w.Save(authorizationPath, authorization);
        w.Save("proofs-authorized.json", revised); options["proof-set"] = "proofs-authorized.json"; await Run("prepare-proofs");
        var second = State(); var secondSet = w.Load<JsonObject>(second.ProofSet);
        check(secondSet["revision"]!.GetValue<int>() == 2 && secondSet["revisedViews"]!.AsArray().Count == 1, "targeted angle replacement advances one candidate within a new proof-set revision");
        check(!second.Approvals.Any(a => a.Kind == "proof-set"), "one revised angle invalidates approval of the whole six-view set");
        check(Enumerable.Range(0, 6).Where(i => i != 1).All(i => secondSet["views"]![i]!["image"]!.GetValue<string>() == selected["views"]![i]!["image"]!.GetValue<string>()), "five unaffected views retain exact immutable image identity");
        check(second.History.Count(item => item["event"]?.GetValue<string>() == "proof-generated-output") == 3 && second.History.Any(item => item["status"]?.GetValue<string>() == "rejected" && File.Exists(w.Resolve(item["image"]!.GetValue<string>()))), "selected and rejected generated candidates remain durably retained");
        check(first.Proof == second.Proof && File.Exists(w.Resolve(first.ProofSet)), "revision preserves primary original and historical proof-set evidence");
        var stale = secondSet.DeepClone().AsObject(); stale["revision"] = 3; stale["classificationHash"] = new string('0', 64);
        w.Save("proofs-stale.json", stale); options["proof-set"] = "proofs-stale.json";
        await reject(() => Run("prepare-proofs"), "stale classification cannot produce a current proof set");
        var receiptCopy = secondSet["views"]![1]!["generationReceipt"]!.GetValue<string>();
        var receiptBytes = File.ReadAllBytes(w.Resolve(receiptCopy)); File.AppendAllText(w.Resolve(receiptCopy), " ");
        await reject(() => Run("validate"), "changed immutable generation receipt invalidates current pipeline evidence");
        File.WriteAllBytes(w.Resolve(receiptCopy), receiptBytes);
        var originalSet = File.ReadAllBytes(w.Resolve(second.SourceSet));
        var sourceMutant = w.Load<JsonObject>(second.SourceSet); sourceMutant["images"]![1]!["sha256"] = new string('0', 64); w.Save(second.SourceSet, sourceMutant);
        await reject(() => Run("classify"), "changed source-set inventory cannot be reclassified as unchanged originals");
        File.WriteAllBytes(w.Resolve(second.SourceSet), originalSet);
        options["classification"] = "classification.json"; await Run("classify");
        check(string.IsNullOrEmpty(State().ProofSet) && !State().Stages.ContainsKey("prepare-proofs"), "new classification invalidates dependent proof selection while preserving historical files");
        check(File.Exists(w.Resolve(second.ProofSet)), "classification revisions never delete historical proof evidence");
        authorization["maxGeneratedCandidates"] = 10; authorization["maxRevisionsPerView"] = 1; w.Save(authorizationPath, authorization);
        var resetSet = ProofSet(w, State());
        var resetView = resetSet["views"]![1]!.AsObject();
        resetView["image"] = "new-right.png"; resetView["sha256"] = w.HashFile(w.Resolve("new-right.png")); resetView["origin"] = "generated"; resetView["sourceIds"] = new JsonArray("source-0"); resetView["generationReceipt"] = generationReceipt;
        resetSet["generationPolicy"] = revised["generationPolicy"]!.DeepClone();
        w.Save("reset-proofs.json", resetSet); options["proof-set"] = "reset-proofs.json"; await Run("prepare-proofs");
        await Run("classify");
        WritePng(w.Resolve("another-right.png"), 250);
        var anotherReceipt = ".opencaw/.cache/tasks/preparation/generation/another-right.json";
        w.Save(anotherReceipt, Receipt(w, State(), "run-right-2", "another-right.png"));
        resetSet["classificationHash"] = w.HashFile(w.Resolve(State().Classification));
        resetView["image"] = "another-right.png"; resetView["sha256"] = w.HashFile(w.Resolve("another-right.png")); resetView["generationReceipt"] = anotherReceipt;
        w.Save("reset-proofs-2.json", resetSet); options["proof-set"] = "reset-proofs-2.json";
        await reject(() => Run("prepare-proofs"), "identical reclassification cannot reset cumulative per-view generation limit");
        check(State().History.Count(item => item["event"]?.GetValue<string>() == "proof-generated-view" && item["view"]?.GetValue<string>() == "right") == 2, "failed per-view revision attempt retains both generation-run identities");
        foreach (var (name, count, oblique, expected) in new[] { ("single-front", 1, false, 5), ("single-oblique", 1, true, 6), ("multiple-coverage", 3, false, 3) })
        {
            var settings = new Dictionary<string, string> { ["task"] = "preparation", ["asset"] = name, ["version"] = "v1", ["actor"] = "fixture-builder", ["rights"] = "rights.json", ["recipe"] = "recipe.json", ["toolchain"] = "toolchain.json" };
            if (count == 1) settings["proof"] = "source-0.png";
            else
            {
                var sourceInput = name + "-sources.json";
                w.Save(sourceInput, new JsonObject { ["schemaVersion"] = 1, ["images"] = new JsonArray(originals.Take(count).Select(node => node!.DeepClone()).ToArray()) });
                settings["sources"] = sourceInput;
            }
            await new Pipeline(w, settings, new NativeProcess(), new AlphaProcessor()).Execute("init", default);
            var taskManifest = ".opencaw/.cache/tasks/preparation/proof-to-model/" + name + "/v1/manifest.json"; settings["manifest"] = taskManifest;
            var state = w.Load<Manifest>(taskManifest); var analysis = Classification(w, state);
            if (oblique) { analysis["sourceViews"]![0]!["view"] = "oblique"; analysis["sourceViews"]![0]!["usable"] = false; }
            var report = name + "-classification.json"; w.Save(report, analysis); settings["classification"] = report;
            await new Pipeline(w, settings, new NativeProcess(), new AlphaProcessor()).Execute("classify", default);
            state = w.Load<Manifest>(taskManifest); var plan = w.Load<JsonObject>(state.Stages["classify"].Artifacts["proof-plan"]);
            check(plan["minimumGeneratedViews"]!.GetValue<int>() == expected && plan["missingViews"]!.AsArray().Count == expected, name + " plans only the actual missing canonical proofs");
        }
        var anatomy = Classification(w, State());
        JsonObject Claim(string id, string description) => new() { ["id"] = id, ["description"] = description, ["sourceIds"] = new JsonArray("source-0"), ["confidence"] = "medium", ["disposition"] = "observed" };
        var inferred = Claim("hidden-legs", "Synthetic schema hypothesis: four horse legs, exact occluded pose unknown");
        inferred["disposition"] = "research-inferred"; inferred["basis"] = "Controlled reference metadata, not an executed research claim"; inferred["impact"] = "Preserve separate rider and mount anatomy"; inferred["alternatives"] = new JsonArray("Source-specific fantasy anatomy must take precedence"); inferred["researchIds"] = new JsonArray("horse-anatomy");
        anatomy["researchStatus"] = "performed"; anatomy["researchReason"] = "Synthetic supplied-research receipt contract test; no network research was executed";
        anatomy["research"] = new JsonArray(new JsonObject { ["id"] = "horse-anatomy", ["url"] = "https://example.invalid/horse-anatomy", ["title"] = "Synthetic anatomy reference", ["sourceQuestion"] = "Which occluded mount parts need a declared hypothesis?", ["sourceIds"] = new JsonArray("source-0"), ["retrievedAt"] = DateTimeOffset.UtcNow.ToString("O") });
        anatomy["subjects"] = new JsonArray(
            new JsonObject { ["id"] = "horse", ["kind"] = "living", ["classification"] = "Horse category fixture", ["sourceIds"] = new JsonArray("source-0"), ["claims"] = new JsonArray(Claim("visible-body", "Synthetic visible mount claim"), inferred), ["parts"] = new JsonArray(new JsonObject { ["id"] = "legs", ["name"] = "Occluded legs", ["visibility"] = "hidden", ["disposition"] = "research-inferred", ["sourceIds"] = new JsonArray("source-0"), ["claimIds"] = new JsonArray("hidden-legs") }) },
            new JsonObject { ["id"] = "rider", ["kind"] = "living", ["classification"] = "Distinct rider fixture", ["sourceIds"] = new JsonArray("source-0"), ["claims"] = new JsonArray(Claim("rider-body", "Synthetic rider observation")), ["parts"] = new JsonArray() },
            new JsonObject { ["id"] = "helmet", ["kind"] = "nonliving", ["classification"] = "Skull-shaped metal armor fixture", ["sourceIds"] = new JsonArray("source-0"), ["claims"] = new JsonArray(Claim("metal-shape", "Synthetic metallic armor material, not biological skeletal tissue")), ["parts"] = new JsonArray() });
        anatomy["relations"] = new JsonArray(new JsonObject { ["from"] = "rider", ["to"] = "horse", ["type"] = "mounted-on", ["description"] = "Separate living entities with a declared assembly relationship", ["sourceIds"] = new JsonArray("source-0") }, new JsonObject { ["from"] = "rider", ["to"] = "helmet", ["type"] = "wears", ["description"] = "Armor belongs to the rider, not mount anatomy", ["sourceIds"] = new JsonArray("source-0") });
        anatomy["unknowns"] = new JsonArray(new JsonObject { ["description"] = "Exact hidden leg pose", ["impact"] = "Pose affects proof consistency", ["sourceIds"] = new JsonArray("source-0"), ["requiresResolution"] = true });
        w.Save("anatomy-classification.json", anatomy); options["classification"] = "anatomy-classification.json"; await Run("classify");
        check(w.Load<JsonObject>(State().Classification)["subjects"]!.AsArray().Count == 3, "classification preserves distinct living subjects, inferred hidden parts and nonliving armor through explicit graph records");
        coverage = w.Load<JsonObject>(State().Stages["classify"].Artifacts["proof-plan"]);
        check(coverage["blockedBy"]!.AsArray().Count == 1, "consequential unresolved anatomy is visible in proof-plan blockers");
        w.Save("anatomy-proofs.json", ProofSet(w, State())); options["proof-set"] = "anatomy-proofs.json";
        await reject(() => Run("prepare-proofs"), "unresolved consequential anatomy blocks otherwise valid six-view preparation");
        anatomy["unknowns"]![0]!["resolution"] = "Synthetic declared static pose selected; not a newly observed source fact";
        w.Save("anatomy-resolved.json", anatomy); options["classification"] = "anatomy-resolved.json"; await Run("classify");
        w.Save("anatomy-resolved-proofs.json", ProofSet(w, State())); options["proof-set"] = "anatomy-resolved-proofs.json"; await Run("prepare-proofs");
        check(State().Stages["prepare-proofs"].Status == "complete", "explicit hidden-pose interpretation permits proof preparation without relabeling inference as observation");
    }
    static JsonObject Authorization(Workspace w, Manifest state, int maximum, int revisions) => new()
    {
        ["schemaVersion"] = 1, ["authorized"] = true, ["purpose"] = "proof-to-model-multiview", ["pipeline"] = "CLOUD",
        ["sourceSetHash"] = w.HashFile(w.Resolve(state.SourceSet)), ["classificationHash"] = w.HashFile(w.Resolve(state.Classification)), ["mediaContractHash"] = w.HashFile(w.Resolve("MEDIA.md")),
        ["actor"] = "fixture-person", ["reason"] = "SYNTHETIC TEST RECEIPT; no real generation or spending", ["maxGeneratedCandidates"] = maximum, ["maxRevisionsPerView"] = revisions
    };
    static JsonObject Receipt(Workspace w, Manifest state, string runId, string image, string? rejected = null)
    {
        JsonObject Unavailable() => new() { ["unavailable"] = true, ["reason"] = "Synthetic fixture has no provider" };
        var source = w.Load<JsonObject>(state.SourceSet)["images"]![0]!;
        var outputs = new JsonArray(new JsonObject { ["stagedPath"] = image, ["sha256"] = w.HashFile(w.Resolve(image)), ["status"] = "staged", ["runtimeTarget"] = Unavailable() });
        if (rejected is not null) outputs.Add(new JsonObject { ["stagedPath"] = rejected, ["sha256"] = w.HashFile(w.Resolve(rejected)), ["status"] = "rejected", ["runtimeTarget"] = Unavailable(), ["rejectionReason"] = "Controlled rejected fixture output" });
        return new JsonObject
        {
            ["schemaVersion"] = 1, ["runId"] = runId, ["createdAt"] = DateTimeOffset.UtcNow.ToString("O"), ["modality"] = "image",
            ["backend"] = new JsonObject { ["kind"] = "cloud-session", ["provider"] = "simulation-only", ["capability"] = "controlled-generated-artifact", ["toolVersion"] = Unavailable() },
            ["model"] = new JsonObject { ["name"] = Unavailable(), ["revision"] = Unavailable(), ["digest"] = Unavailable(), ["license"] = Unavailable() },
            ["workflow"] = new JsonObject { ["name"] = Unavailable(), ["revision"] = Unavailable(), ["digest"] = Unavailable() },
            ["generation"] = new JsonObject { ["prompt"] = "SYNTHETIC TEST ONLY", ["negativePrompt"] = Unavailable(), ["parameters"] = new JsonObject(), ["seed"] = Unavailable() },
            ["inputs"] = new JsonArray(new JsonObject { ["description"] = "Immutable original fixture", ["source"] = source["path"]!.GetValue<string>(), ["rights"] = "Authorized synthetic fixture", ["consent"] = "not-applicable" }),
            ["outputs"] = outputs, ["runtime"] = new JsonObject { ["destination"] = Unavailable(), ["budgets"] = new JsonObject { ["images"] = outputs.Count } },
            ["review"] = new JsonObject { ["status"] = "pending", ["reviewer"] = Unavailable(), ["reviewedAt"] = Unavailable(), ["notes"] = "No human approval is created" }
        };
    }
    static void WritePng(string path, byte red)
    {
        using var stream = File.Create(path); stream.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        void Chunk(string name, byte[] data)
        {
            Span<byte> value = stackalloc byte[4]; BinaryPrimitives.WriteInt32BigEndian(value, data.Length); stream.Write(value);
            var tag = System.Text.Encoding.ASCII.GetBytes(name); stream.Write(tag); stream.Write(data);
            uint crc = 0xffffffff;
            foreach (var b in tag.Concat(data)) { crc ^= b; for (var i = 0; i < 8; i++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1; }
            BinaryPrimitives.WriteUInt32BigEndian(value, ~crc); stream.Write(value);
        }
        var header = new byte[13]; BinaryPrimitives.WriteInt32BigEndian(header, 16); BinaryPrimitives.WriteInt32BigEndian(header.AsSpan(4), 16); header[8] = 8; header[9] = 6; Chunk("IHDR", header);
        using var pixels = new MemoryStream();
        using (var compressed = new ZLibStream(pixels, CompressionLevel.SmallestSize, true))
            for (var y = 0; y < 16; y++) { compressed.WriteByte(0); for (var x = 0; x < 16; x++) compressed.Write(new byte[] { red, 90, 140, x is > 1 and < 14 && y is > 1 and < 14 ? (byte)255 : (byte)0 }); }
        Chunk("IDAT", pixels.ToArray()); Chunk("IEND", []);
    }
}
