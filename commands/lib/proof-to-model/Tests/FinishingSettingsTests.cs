using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;

static class FinishingSettingsTests
{
    const string Legacy = "{\"schemaVersion\":1,\"topologyPreparation\":{\"method\":\"none\"},\"collision\":{\"method\":\"exact-hull\"}}";
    const string Selected = "{\"schemaVersion\":1,\"topologyPreparation\":{\"method\":\"voxel-remesh\",\"voxelSize\":0.002,\"maxEstimatedVoxels\":200000000,\"maxPreparedTriangles\":8000000},\"collision\":{\"method\":\"kdop-26\",\"padding\":0.001,\"maxVolumeRatio\":2}}";
    static string SimplificationSelection()
    {
        var value = JsonNode.Parse(Selected)!.AsObject();
        value["quadriFlow"] = new JsonObject
        {
            ["coordinateScale"] = 1024,
            ["simplification"] = new JsonObject
            {
                ["method"] = "collapse", ["targetTriangles"] = 1000000,
                ["maxVertexSurfaceErrorMetres"] = .003,
                ["protectedRegions"] = new JsonArray(new JsonObject
                {
                    ["id"] = "gear-zone", ["min"] = new JsonArray(-.1, -.2, -.3), ["max"] = new JsonArray(.1, .2, .3)
                })
            }
        };
        return value.ToJsonString();
    }
    static readonly string[] ChildEnvironmentKeys = ["TEMP", "TMP", "TMPDIR", "PYTHONDONTWRITEBYTECODE"];
    const string InheritedMarker = "OPENCAW_BLENDER_TEMP_TEST_SENTINEL";
    public static int ObserveChildEnvironment(string[] args)
    {
        // Actual subprocess observation, not a Blender/mesh producer or a human
        // assertion. NativeProcess owns this short-lived fixture child.
        var temporaryDirectory = Path.GetTempPath();
        var expected = Environment.GetEnvironmentVariable("TEMP");
        if (expected is null || !Path.TrimEndingDirectorySeparator(temporaryDirectory).Equals(Path.TrimEndingDirectorySeparator(expected),
                OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
        {
            Console.Write(JsonSerializer.Serialize(new
            {
                actualChildProcess = true, blockedBeforeWrite = true,
                environment = ChildEnvironmentKeys.ToDictionary(name => name, Environment.GetEnvironmentVariable),
                runtimeTemporaryDirectory = temporaryDirectory,
                reason = "Runtime temporary API did not select the explicitly confined directory; no witness written"
            }, Serialization.Json));
            return 23;
        }
        var witness = Path.Combine(temporaryDirectory, "controlled-child-" + Guid.NewGuid().ToString("N") + ".txt");
        File.WriteAllText(witness, "CONTROLLED TEST ONLY: child temporary/failure witness, not a real Blender crash");
        Console.Write(JsonSerializer.Serialize(new
        {
            actualChildProcess = true,
            environment = ChildEnvironmentKeys.ToDictionary(name => name, Environment.GetEnvironmentVariable),
            runtimeTemporaryDirectory = temporaryDirectory,
            inheritedMarker = Environment.GetEnvironmentVariable(InheritedMarker),
            witness,
            intentionalFailure = args.Contains("--fail", StringComparer.Ordinal)
        }, Serialization.Json));
        return args.Contains("--fail", StringComparer.Ordinal) ? 19 : 0;
    }
    public static async Task Run(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        JsonObject Parse(string json) => FinishingSettings.Parse(Encoding.UTF8.GetBytes(json));
        check(Parse(Legacy)["topologyPreparation"]!["method"]!.GetValue<string>() == "none", "finishing settings explicitly select legacy no-preparation/exact-hull");
        check(Parse(Selected)["collision"]!["method"]!.GetValue<string>() == "kdop-26", "finishing settings explicitly select bounded voxel preparation and kdop-26");
        check(!Parse(Selected).ContainsKey("quadriFlow") && !Parse(Legacy).ContainsKey("quadriFlow"), "absent solver choice is preserved without an implicit coordinate factor or repair selection");
        foreach (var legacy in new[] { Legacy, Selected })
            await reject(() => Task.Run(() => Parse(legacy[..^1] + ",\"rigidParts\":{\"uvAtlas\":{\"method\":\"smart-project-pixels\",\"islandMarginPixels\":2}}}")),
                "v1 rejects the rigid-only UV atlas selection without changing its recipe/default behavior");
        var solverSelected = Selected[..^1] + ",\"quadriFlow\":{\"coordinateScale\":1024}}";
        foreach (var scale in new[] { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 })
        {
            var selected = Parse(solverSelected.Replace(":1024}", ":" + scale + "}"));
            check(selected["quadriFlow"]!["coordinateScale"]!.GetValue<int>() == scale, "explicit power-of-two solver coordinate choice is retained: " + scale);
        }
        foreach (var exact in new[] { "1024.0", "1.024e3", "1024000e-3", "0.1024e4", "1024e" + new string('0', 1000) })
            check(Parse(solverSelected.Replace(":1024}", ":" + exact + "}"))["quadriFlow"]!["coordinateScale"]!.GetValue<int>() == 1024, "solver exact JSON integer notation is normalized without losing explicit selection");
        foreach (var mutate in new Action<JsonObject>[] {
            x => x["quadriFlow"] = null, x => x["quadriFlow"] = new JsonArray(),
            x => x["quadriFlow"] = new JsonObject(),
            x => x["quadriFlow"]!["unknown"] = true,
            x => x["quadriFlow"]!["coordinateScale"] = "1024",
            x => x["quadriFlow"]!["coordinateScale"] = true,
            x => x["quadriFlow"]!["coordinateScale"] = 0,
            x => x["quadriFlow"]!["coordinateScale"] = -1,
            x => x["quadriFlow"]!["coordinateScale"] = 3,
            x => x["quadriFlow"]!["coordinateScale"] = 1025,
            x => x["quadriFlow"]!["coordinateScale"] = 2048,
            x => x["quadriFlow"]!["coordinateScale"] = .5,
            x => x["quadriFlow"]!["coordinateScale"] = 2.5,
            x => x["quadriFlow"]!["coordinateScale"] = null
        })
        {
            var candidate = Parse(solverSelected); mutate(candidate);
            await reject(() => Task.Run(() => Parse(candidate.ToJsonString())), "solver missing/unknown/malformed/non-power-of-two selection fails closed");
        }
        foreach (var invalid in new[] {
            solverSelected.Replace(",\"quadriFlow\":", ",\"quadriFlow\":{\"coordinateScale\":1024},\"quadriFlow\":"),
            solverSelected.Replace("\"coordinateScale\":1024", "\"coordinateScale\":1024,\"coordinateScale\":1024"),
            solverSelected.Replace(":1024}", ":1024.000000000000000000000001}"),
            solverSelected.Replace(":1024}", ":1024000000000000000000001e-21}"),
            solverSelected.Replace(":1024}", ":1e-999999999}"),
            solverSelected.Replace(":1024}", ":1e999999999999999999999999}"),
            solverSelected.Replace("\"schemaVersion\":1", "\"schemaVersion\":1.000000000000000000000001"),
            Selected.Replace("200000000", "200000000.000000000000000001")
        }) await reject(() => Task.Run(() => Parse(invalid)), "solver duplicate/exact-fraction/underflow/oversized-exponent or rounded legacy integer rejected");
        await CheckSimplificationContract(check, reject);
        Parse(Selected.Replace("200000000", "2e8").Replace("\"schemaVersion\":1", "\"schemaVersion\":1.0"));
        check(true, "finishing integer fields follow JSON Schema mathematical integer semantics");
        foreach (var invalid in new[] { "null", "[]", "{}", "{", Legacy.Replace("\"schemaVersion\":1", "\"schemaVersion\":true") })
            await reject(() => Task.Run(() => Parse(invalid)), "finishing malformed or non-object contract rejected: " + invalid[..Math.Min(28, invalid.Length)]);
        foreach (var mutate in new Action<JsonObject>[] {
            x => x.Remove("collision"), x => x["unknown"] = true, x => x["schemaVersion"] = 2,
            x => x["schemaVersion"] = "1", x => x["topologyPreparation"] = null,
            x => x["topologyPreparation"]!["method"] = "automatic", x => x["collision"]!["method"] = "box",
            x => x["topologyPreparation"]!.AsObject().Remove("voxelSize"),
            x => x["topologyPreparation"]!["voxelSize"] = 0, x => x["topologyPreparation"]!["voxelSize"] = -1,
            x => x["topologyPreparation"]!["voxelSize"] = 1.01, x => x["topologyPreparation"]!["voxelSize"] = "0.002",
            x => x["topologyPreparation"]!["maxEstimatedVoxels"] = 0,
            x => x["topologyPreparation"]!["maxEstimatedVoxels"] = 2000000001L,
            x => x["topologyPreparation"]!["maxEstimatedVoxels"] = 10.5,
            x => x["topologyPreparation"]!["maxPreparedTriangles"] = 3,
            x => x["topologyPreparation"]!["maxPreparedTriangles"] = 20000001,
            x => x["topologyPreparation"]!["maxPreparedTriangles"] = true,
            x => x["collision"]!.AsObject().Remove("padding"), x => x["collision"]!["padding"] = -.01,
            x => x["collision"]!["padding"] = 1.01, x => x["collision"]!["padding"] = "0",
            x => x["collision"]!["maxVolumeRatio"] = .999, x => x["collision"]!["maxVolumeRatio"] = 100.01,
            x => x["collision"]!["unselected"] = "fallback"
        })
        {
            var candidate = JsonNode.Parse(Selected)!.AsObject(); mutate(candidate);
            await reject(() => Task.Run(() => Parse(candidate.ToJsonString())), "finishing unknown/incomplete/typed/out-of-budget selection rejected");
        }
        foreach (var invalid in new[] {
            Legacy.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            Legacy.Replace("\"method\":\"none\"", "\"method\":\"none\",\"method\":\"none\""),
            Legacy.Replace("\"method\":\"none\"", "\"method\":\"none\",\"voxelSize\":0.1"),
            Legacy.Replace("\"method\":\"exact-hull\"", "\"method\":\"exact-hull\",\"padding\":0"),
            Selected.Replace("0.002", "1e999"), Selected.Replace("0.002", "NaN"),
            Selected.Replace("0.001", "Infinity"), new string(' ', FinishingSettings.MaximumBytes + 1)
        }) await reject(() => Task.Run(() => Parse(invalid)), "finishing duplicate/extraneous/nonfinite/oversize contract rejected");
        var edge = JsonNode.Parse(Selected)!.AsObject();
        edge["topologyPreparation"]!["voxelSize"] = 1;
        edge["topologyPreparation"]!["maxEstimatedVoxels"] = FinishingSettings.MaximumEstimatedVoxels;
        edge["topologyPreparation"]!["maxPreparedTriangles"] = FinishingSettings.MaximumPreparedTriangles;
        edge["collision"]!["padding"] = 1; edge["collision"]!["maxVolumeRatio"] = 100;
        Parse(edge.ToJsonString()); check(true, "finishing declared upper boundaries are accepted without raising recipe budgets");

        // Actual application/state/file guards with an explicitly SIMULATED Blender producer.
        var directory = parent.Resolve("finishing-settings-fixtures"); Directory.CreateDirectory(directory);
        var w = new Workspace(directory);
        File.WriteAllText(w.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL\n");
        RgbaPng.Write(w.Resolve("source.png"), new RgbaPng.Image(2, 2, Enumerable.Repeat((byte)255, 16).ToArray()));
        w.Save("rights.json", new { authorized = true });
        w.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
        w.Save("toolchain.json", new { schemaVersion = 1, files = Array.Empty<object>(), models = Array.Empty<object>(), blender = new { path = Environment.ProcessPath! }, limits = new { maxAttempts = 20, timeoutSeconds = 10 } });
        var baseline = w.Resolve("trusted-baseline");
        var scripts = Path.Combine(baseline, ".styles/.pipelines/proof-to-model/blender"); Directory.CreateDirectory(scripts);
        foreach (var file in new[] { "finish.py", "review.py", "common.py" }) File.WriteAllText(Path.Combine(scripts, file), "# Explicit simulated producer fixture; not real Blender automation\n");
        var opts = new Dictionary<string, string> { ["mode"] = "single-view-diagnostic", ["asset"] = "finishing", ["version"] = "v1", ["task"] = "tests", ["proof"] = "source.png", ["rights"] = "rights.json", ["recipe"] = "recipe.json", ["toolchain"] = "toolchain.json", ["actor"] = "fixture-builder", ["baseline-root"] = baseline };
        var native = new SimulatedFinisher(w);
        await new Pipeline(w, opts, native, new AlphaProcessor()).Execute("init", default);
        var manifest = ".opencaw/.cache/tasks/tests/proof-to-model/finishing/v1/manifest.json"; opts["manifest"] = manifest;
        var state = w.Load<Manifest>(manifest);
        Directory.CreateDirectory(w.Resolve(state.Staging + "/fixture"));
        var raw = state.Staging + "/fixture/raw.glb"; WriteSyntheticGlb(w.Resolve(raw));
        var normalized = state.Staging + "/fixture/normalized.dat"; File.WriteAllText(w.Resolve(normalized), "SIMULATED preprocessing bytes");
        state.Stages["preprocess"] = new Stage { Status = "complete", Attempt = state.Staging + "/fixture", Outputs = new() { [normalized] = Workspace.Hash(w.Resolve(normalized)) }, Artifacts = new() { ["normalized"] = normalized } };
        state.Stages["reconstruct"] = new Stage { Status = "complete", Attempt = state.Staging + "/fixture", Inputs = new() { [normalized] = Workspace.Hash(w.Resolve(normalized)) }, Outputs = new() { [raw] = Workspace.Hash(w.Resolve(raw)) }, Artifacts = new() { ["glb"] = raw } };
        var core = new[] { state.Proof, state.ProofMetadata, state.Rights, state.Recipe, state.Toolchain, "STYLE.md" };
        string Fingerprint(IEnumerable<string> files) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", files.Order().Select(path => path + ":" + Workspace.Hash(w.Resolve(path)))))));
        foreach (var kind in new[] { "proof", "preprocessing" })
        {
            var path = ".opencaw/.cache/tasks/tests/reviews/synthetic-" + kind + ".json";
            w.Save(path, new { kind, reason = "SIMULATED human assertion; no real approval or inference" });
            state.Approvals.Add(new(kind, "synthetic-only", path, Workspace.Hash(w.Resolve(path)), Fingerprint(kind == "proof" ? core : core.Append(normalized)), DateTimeOffset.UtcNow));
        }
        w.Save(manifest, state);
        var upstream = JsonSerializer.Serialize(state.Stages, Serialization.Json);
        var approvals = JsonSerializer.Serialize(state.Approvals, Serialization.Json);
        var recipeHash = Workspace.Hash(w.Resolve(state.Recipe));
        async Task Run(string command, Dictionary<string, string>? options = null) => await new Pipeline(w, options ?? opts, native, new AlphaProcessor()).Execute(command, default);
        void UpstreamUnchanged()
        {
            var current = w.Load<Manifest>(manifest);
            var before = JsonNode.Parse(upstream)!.AsObject();
            check(new[] { "preprocess", "reconstruct" }.All(name => JsonNode.DeepEquals(before[name], JsonSerializer.SerializeToNode(current.Stages[name], Serialization.Json))), "SIMULATED finishing preserves upstream stage identities, hashes and outputs");
            check(JsonSerializer.Serialize(current.Approvals.Where(a => a.Kind is "proof" or "preprocessing"), Serialization.Json) == approvals, "SIMULATED finishing preserves exact proof and preprocessing approvals");
            check(Workspace.Hash(w.Resolve(current.Recipe)) == recipeHash && current.Recipe == "recipe.json", "SIMULATED finishing never rewrites or rebinds recipe");
        }
        await Run("finish");
        check(native.Jobs.Last()["finishingSettings"] is null && !w.Load<Manifest>(manifest).Stages["finish"].Artifacts.ContainsKey("finishingSettings"), "SIMULATED default finish keeps null settings and legacy none/exact-hull behavior");
        UpstreamUnchanged();
        File.WriteAllText(w.Resolve("finishing.json"), Selected + "\n"); opts["finish-settings"] = "finishing.json";
        await Run("finish");
        state = w.Load<Manifest>(manifest); var finish = state.Stages["finish"];
        var snapshot = finish.Artifacts["finishingSettings"];
        check(snapshot == finish.Attempt + "/finishing-settings.json" && File.ReadAllBytes(w.Resolve(snapshot)).SequenceEqual(File.ReadAllBytes(w.Resolve("finishing.json"))), "SIMULATED finish preserves exact immutable settings snapshot as output artifact");
        check(finish.Inputs["finishing.json"] == finish.Inputs[snapshot] && finish.Outputs[snapshot] == finish.Inputs[snapshot], "SIMULATED original settings and attempt snapshot are both hash-bound");
        check(JsonNode.DeepEquals(native.Jobs.Last()["finishingSettings"], JsonNode.Parse(Selected)), "SIMULATED fixed Blender job receives only the validated explicit settings object");
        UpstreamUnchanged();
        var validateOptions = new Dictionary<string, string>(opts); validateOptions.Remove("finish-settings");
        await Run("validate", validateOptions);
        File.WriteAllText(w.Resolve("finishing.json"), solverSelected.Replace(":1024}", ":1024.0}"));
        await Run("finish");
        state = w.Load<Manifest>(manifest); finish = state.Stages["finish"]; snapshot = finish.Artifacts["finishingSettings"];
        check(native.Jobs.Last()["finishingSettings"]!["quadriFlow"]!["coordinateScale"]!.GetValue<int>() == 1024, "SIMULATED fixed Blender job receives the explicit normalized solver factor");
        check(File.ReadAllBytes(w.Resolve(snapshot)).SequenceEqual(File.ReadAllBytes(w.Resolve("finishing.json"))) && finish.Inputs[snapshot] == finish.Inputs["finishing.json"], "SIMULATED solver choice retains original exact decimal receipt bytes and source/snapshot hashes");
        UpstreamUnchanged();
        await Run("validate", validateOptions);
        var simplificationSelected = SimplificationSelection().Replace("\"targetTriangles\":1000000", "\"targetTriangles\":1000000.0");
        File.WriteAllText(w.Resolve("finishing.json"), simplificationSelected);
        await Run("finish");
        state = w.Load<Manifest>(manifest); finish = state.Stages["finish"]; snapshot = finish.Artifacts["finishingSettings"];
        var reducedJob = native.Jobs.Last()["finishingSettings"]!["quadriFlow"]!["simplification"]!;
        check(reducedJob["targetTriangles"]!.GetValue<int>() == 1000000 && reducedJob["protectedRegions"]!.AsArray().Single()!["id"]!.GetValue<string>() == "gear-zone", "SIMULATED fixed Blender job receives explicit normalized simplification and world regions");
        check(File.ReadAllText(w.Resolve(snapshot)) == simplificationSelected && finish.Inputs[snapshot] == finish.Inputs["finishing.json"], "SIMULATED simplification retains exact original decimal source bytes and immutable hashes");
        UpstreamUnchanged();
        await Run("validate", validateOptions);
        File.WriteAllText(w.Resolve("finishing.json"), solverSelected);
        await Run("finish");
        state = w.Load<Manifest>(manifest); finish = state.Stages["finish"]; snapshot = finish.Artifacts["finishingSettings"];
        check(!native.Jobs.Last()["finishingSettings"]!["quadriFlow"]!.AsObject().ContainsKey("simplification"), "SIMULATED omitting simplification never inherits a previous reduction choice");
        UpstreamUnchanged();
        var historyCount = state.History.Count; var launches = native.Jobs.Count;
        foreach (var path in new[] { "missing.json", "../escape.json", "folder/../finishing.json", "./finishing.json", w.Resolve("finishing.json"), "C:finishing.json", "finishing.txt", "NUL.json", "CONIN$.json", "COM¹.json", "folder./finishing.json", "folder /finishing.json", "foo?.json" })
            await reject(() => Run("finish", new(opts) { ["finish-settings"] = path }), "SIMULATED missing/escaped/aliased/nonrelative finishing input rejected");
        File.WriteAllText(w.Resolve("invalid.json"), Legacy.Replace("\"method\":\"none\"", "\"method\":\"none\",\"extra\":true"));
        await reject(() => Run("finish", new(opts) { ["finish-settings"] = "invalid.json" }), "SIMULATED malformed settings rejected before stage state/native work");
        File.WriteAllText(w.Resolve("oversize.json"), new string(' ', FinishingSettings.MaximumBytes + 1));
        await reject(() => Run("finish", new(opts) { ["finish-settings"] = "oversize.json" }), "SIMULATED oversize settings blocked by bounded read before stage state");
        var target = parent.Resolve("outside-finishing-settings"); Directory.CreateDirectory(target); File.WriteAllText(Path.Combine(target, "finishing.json"), Selected);
        var link = w.Resolve("linked-settings");
        if (OperatingSystem.IsWindows())
            await new NativeProcess().Run(Environment.GetEnvironmentVariable("COMSPEC")!, ["/d", "/c", "mklink", "/J", link, target], w.Root, w.Resolve("finishing-junction.log"), 5);
        else Directory.CreateSymbolicLink(link, target);
        await reject(() => Run("finish", new(opts) { ["finish-settings"] = "linked-settings/finishing.json" }), "SIMULATED actual junction/symlink finishing input rejected before state or launch");
        Directory.Delete(link); // Remove only the owned link, without recursing into its target.
        foreach (var command in new[] { "init", "review", "status", "validate", "setup", "reconstruct", "preprocess", "record", "promote" })
            await reject(() => Run(command), "SIMULATED finishing-only option rejected on " + command);
        check(w.Load<Manifest>(manifest).History.Count == historyCount && native.Jobs.Count == launches, "SIMULATED invalid settings/command selections cause no stage writes or launches");
        File.AppendAllText(w.Resolve("finishing.json"), " ");
        await reject(() => Run("validate", validateOptions), "SIMULATED changed original finishing settings invalidate current finishing evidence");
        await Run("finish");
        state = w.Load<Manifest>(manifest); snapshot = state.Stages["finish"].Artifacts["finishingSettings"];
        check(state.Stages["finish"].Attempt != finish.Attempt && File.Exists(w.Resolve(finish.Attempt + "/finishing-settings.json")), "SIMULATED settings revision uses fresh attempt and preserves previous immutable attempt");
        UpstreamUnchanged();
        var snapshotBytes = File.ReadAllBytes(w.Resolve(snapshot)); File.AppendAllText(w.Resolve(snapshot), " ");
        await reject(() => Run("validate", validateOptions), "SIMULATED changed immutable settings snapshot invalidates package");
        File.WriteAllBytes(w.Resolve(snapshot), snapshotBytes);
        state.Stages["review"] = new Stage { Status = "complete", Attempt = "synthetic-review", Outputs = new() { [normalized] = Workspace.Hash(w.Resolve(normalized)) } };
        state.Stages["guided"] = new Stage { Status = "complete", Attempt = "synthetic-guided", Outputs = new() { [raw] = Workspace.Hash(w.Resolve(raw)) } };
        var dependentReceipt = ".opencaw/.cache/tasks/tests/reviews/synthetic-independent.json";
        w.Save(dependentReceipt, new { reason = "SIMULATED dependent approval for invalidation only" });
        state.Approvals.Add(new("independent", "synthetic", dependentReceipt, Workspace.Hash(w.Resolve(dependentReceipt)), "not-real", DateTimeOffset.UtcNow)); w.Save(manifest, state);
        File.WriteAllText(w.Resolve("finishing.json"), Legacy);
        await Run("finish");
        state = w.Load<Manifest>(manifest);
        check(!state.Stages.ContainsKey("guided") && !state.Stages.ContainsKey("review") && state.Approvals.All(a => a.Kind is "proof" or "preprocessing"), "SIMULATED changed finishing selection invalidates only finishing dependents and their approvals");
        UpstreamUnchanged();
        native.ReplaceSnapshot = true;
        await reject(() => Run("finish"), "SIMULATED producer cannot alias or substitute native settings snapshot artifact");
        native.ReplaceSnapshot = false;
        check(w.Load<Manifest>(manifest).Stages["finish"].Status == "failed", "SIMULATED forbidden producer result remains a failed attempt");
        native.Mutate = () => File.AppendAllText(w.Resolve("finishing.json"), " ");
        await reject(() => Run("finish"), "SIMULATED changed settings during native execution cannot complete");
        native.Mutate = null;
        check(w.Load<Manifest>(manifest).Stages["finish"].Status == "failed", "SIMULATED interrupted/stale settings attempt retains failure evidence");
        opts.Remove("finish-settings"); await Run("finish");
        check(native.Jobs.Last()["finishingSettings"] is null, "SIMULATED explicitly omitting settings restores documented legacy choice without inheriting prior selection");
        UpstreamUnchanged();
        opts["finish-settings"] = "finishing.json";
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            await reject(() => new Pipeline(w, opts, native, new AlphaProcessor()).Execute("finish", cancelled.Token), "SIMULATED cancelled finishing retains its settings snapshot without completing native work");
        }
        state = w.Load<Manifest>(manifest);
        check(state.Stages["finish"].Status == "failed" && File.Exists(w.Resolve(state.Stages["finish"].Artifacts["finishingSettings"])), "SIMULATED failed/cancelled finishing preserves the immutable attempt snapshot");
        UpstreamUnchanged();
        await CheckBlenderTemporaryRouting(parent, w, manifest, opts, native, check, reject);
        await CheckMultiViewPreservation(parent, baseline, check);
    }

    static async Task CheckSimplificationContract(Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        JsonObject Parse(string json) => FinishingSettings.Parse(Encoding.UTF8.GetBytes(json));
        JsonObject Simplification(JsonObject value) => value["quadriFlow"]!["simplification"]!.AsObject();
        JsonArray Regions(JsonObject value) => Simplification(value)["protectedRegions"]!.AsArray();
        var selected = SimplificationSelection();
        check(Parse(selected)["quadriFlow"]!["simplification"]!["targetTriangles"]!.GetValue<int>() == 1000000, "explicit simplification requires method, triangle budget, error and regions together");
        foreach (var exact in new[] { "1000000.0", "1e6", "10000000e-1", "0.0001e10" })
            check(Simplification(Parse(selected.Replace("\"targetTriangles\":1000000", "\"targetTriangles\":" + exact)))["targetTriangles"]!.GetValue<int>() == 1000000, "simplification triangle budget uses exact integral decimal/exponent semantics");
        foreach (var target in new[] { 4, 8000000 })
        {
            var value = Parse(selected); Simplification(value)["targetTriangles"] = target;
            check(Simplification(Parse(value.ToJsonString()))["targetTriangles"]!.GetValue<int>() == target, "simplification exact triangle boundary accepted");
        }
        var unprotected = Parse(selected); Simplification(unprotected)["protectedRegions"] = new JsonArray();
        check(Regions(Parse(unprotected.ToJsonString())).Count == 0, "explicit empty protected-region list is accepted without invented boxes");
        var boundary = Parse(selected);
        Simplification(boundary)["maxVertexSurfaceErrorMetres"] = 1;
        Regions(boundary)[0]!["id"] = new string('a', 80);
        Regions(boundary)[0]!["min"] = new JsonArray(-1e9, -1e9, -1e9);
        Regions(boundary)[0]!["max"] = new JsonArray(1e9, 1e9, 1e9);
        Parse(boundary.ToJsonString()); check(true, "simplification ID/error/world-coordinate upper boundaries accepted");
        var many = Parse(selected); var manyRegions = new JsonArray();
        for (var index = 0; index < 128; index++)
        {
            var region = Regions(many)[0]!.DeepClone(); region["id"] = "r" + index; manyRegions.Add(region);
        }
        Simplification(many)["protectedRegions"] = manyRegions;
        check(Regions(Parse(many.ToJsonString())).Count == 128, "all128 explicitly named regions are accepted within the file budget");
        var ordinal = Parse(selected); Regions(ordinal)[0]!["id"] = "Gear";
        var lower = Regions(ordinal)[0]!.DeepClone(); lower["id"] = "gear"; Regions(ordinal).Add(lower);
        check(Regions(Parse(ordinal.ToJsonString())).Count == 2, "protected region identity uses explicit ordinal case-sensitive uniqueness");
        foreach (var mutate in new Action<JsonObject>[]
        {
            x => x["quadriFlow"]!.AsObject().Remove("coordinateScale"),
            x => x["quadriFlow"]!["simplification"] = null,
            x => x["quadriFlow"]!["simplification"] = new JsonArray(),
            x => x["quadriFlow"]!["simplification"] = true,
            x => x["quadriFlow"]!["simplification"] = new JsonObject(),
            x => Simplification(x).Remove("method"), x => Simplification(x).Remove("targetTriangles"),
            x => Simplification(x).Remove("maxVertexSurfaceErrorMetres"), x => Simplification(x).Remove("protectedRegions"),
            x => Simplification(x)["fallback"] = "automatic", x => Simplification(x)["method"] = "automatic",
            x => Simplification(x)["method"] = false, x => Simplification(x)["method"] = null,
            x => Simplification(x)["targetTriangles"] = 3, x => Simplification(x)["targetTriangles"] = 8000001,
            x => Simplification(x)["targetTriangles"] = -1, x => Simplification(x)["targetTriangles"] = 4.5,
            x => Simplification(x)["targetTriangles"] = "1000000", x => Simplification(x)["targetTriangles"] = true,
            x => Simplification(x)["targetTriangles"] = null,
            x => Simplification(x)["maxVertexSurfaceErrorMetres"] = 0,
            x => Simplification(x)["maxVertexSurfaceErrorMetres"] = -1,
            x => Simplification(x)["maxVertexSurfaceErrorMetres"] = 1.001,
            x => Simplification(x)["maxVertexSurfaceErrorMetres"] = "0.003",
            x => Simplification(x)["maxVertexSurfaceErrorMetres"] = true,
            x => Simplification(x)["maxVertexSurfaceErrorMetres"] = null,
            x => Simplification(x)["protectedRegions"] = null,
            x => Simplification(x)["protectedRegions"] = new JsonObject(),
            x => Simplification(x)["protectedRegions"] = false,
            x => Regions(x)[0] = null, x => Regions(x)[0] = new JsonArray(), x => Regions(x)[0] = new JsonObject(),
            x => Regions(x)[0]!["unexpected"] = true, x => Regions(x)[0]!.AsObject().Remove("min"),
            x => Regions(x)[0]!["id"] = "", x => Regions(x)[0]!["id"] = "bad/name",
            x => Regions(x)[0]!["id"] = "bad\\name", x => Regions(x)[0]!["id"] = ".hidden",
            x => Regions(x)[0]!["id"] = "-leading", x => Regions(x)[0]!["id"] = "bad space",
            x => Regions(x)[0]!["id"] = "bad\n", x => Regions(x)[0]!["id"] = "bad\0",
            x => Regions(x)[0]!["id"] = "é", x => Regions(x)[0]!["id"] = new string('a', 81),
            x => Regions(x)[0]!["id"] = true, x => Regions(x)[0]!["id"] = null,
            x => Regions(x)[0]!["min"] = new JsonArray(0, 0),
            x => Regions(x)[0]!["min"] = new JsonArray(0, 0, 0, 0),
            x => Regions(x)[0]!["min"] = null, x => Regions(x)[0]!["max"] = "1,1,1",
            x => Regions(x)[0]!["min"]![0] = true, x => Regions(x)[0]!["max"]![0] = "0.1",
            x => Regions(x)[0]!["min"]![0] = -1000000001, x => Regions(x)[0]!["max"]![2] = 1000000001,
            x => Regions(x)[0]!["min"]![0] = .1, x => Regions(x)[0]!["min"]![1] = .3,
            x => Regions(x)[0]!["min"]![2] = .3,
            x => Regions(x).Add(Regions(x)[0]!.DeepClone()),
            x => { for (var i = 1; i < 129; i++) { var region = Regions(x)[0]!.DeepClone(); region["id"] = "r" + i; Regions(x).Add(region); } }
        })
        {
            var candidate = Parse(selected); mutate(candidate);
            await reject(() => Task.Run(() => Parse(candidate.ToJsonString())), "simplification incomplete/unknown/typed/bounded/region selection fails closed");
        }
        foreach (var invalid in new[]
        {
            selected.Replace("\"targetTriangles\":1000000", "\"targetTriangles\":1000000.0000000000000000001"),
            selected.Replace("\"targetTriangles\":1000000", "\"targetTriangles\":1e-99999"),
            selected.Replace("\"targetTriangles\":1000000", "\"targetTriangles\":1e99999999999999999999999"),
            selected.Replace("\"targetTriangles\":1000000", "\"targetTriangles\":1000000,\"targetTriangles\":1000000"),
            selected.Replace("\"method\":\"collapse\"", "\"method\":\"collapse\",\"method\":\"collapse\""),
            selected.Replace("\"id\":\"gear-zone\"", "\"id\":\"gear-zone\",\"id\":\"gear-zone\""),
            selected.Replace("\"maxVertexSurfaceErrorMetres\":0.003", "\"maxVertexSurfaceErrorMetres\":1e999"),
            selected.Replace("\"maxVertexSurfaceErrorMetres\":0.003", "\"maxVertexSurfaceErrorMetres\":1e-999"),
            selected.Replace("\"min\":[-0.1,-0.2,-0.3]", "\"min\":[1e999,-0.2,-0.3]")
        }) await reject(() => Task.Run(() => Parse(invalid)), "simplification duplicate/nonfinite/exact-fraction/underflow contract rejected");
    }

    static async Task CheckBlenderTemporaryRouting(Workspace parent, Workspace w, string manifest,
        Dictionary<string, string> options, SimulatedFinisher native,
        Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        var parentEnvironment = ChildEnvironmentKeys.ToDictionary(name => name, Environment.GetEnvironmentVariable);
        var markerBefore = Environment.GetEnvironmentVariable(InheritedMarker);
        var marker = "fixed inherited test marker";
        async Task Run(string command, IWorkspace? workspace = null)
        {
            var selected = new Dictionary<string, string>(options);
            if (command != "finish") selected.Remove("finish-settings");
            await new Pipeline(workspace ?? w, selected, native, new AlphaProcessor()).Execute(command, default);
        }
        try
        {
            Environment.SetEnvironmentVariable(InheritedMarker, marker);
            native.ProbeEnvironment = true;
            var observationsBefore = native.EnvironmentObservations.Count;
            await Run("finish");
            var finish = w.Load<Manifest>(manifest).Stages["finish"];
            await Run("review");
            var review = w.Load<Manifest>(manifest).Stages["review"];
            var observations = native.EnvironmentObservations.Skip(observationsBefore).ToArray();
            check(observations.Length == 4, "actual child probes observed both version and batch environments for finish and review");
            foreach (var stage in new[] { finish, review })
            {
                var expected = w.Resolve(stage.Attempt + "/temp");
                var applicable = observations.Where(observation => Path.TrimEndingDirectorySeparator(observation["runtimeTemporaryDirectory"]!.GetValue<string>()) == expected).ToArray();
                check(applicable.Length == 2, "actual runtime temporary API resolves to this real stage-attempt directory for both child calls");
                check(Directory.Exists(expected) && (File.GetAttributes(expected) & FileAttributes.ReparsePoint) == 0, "child temporary directory is real and project-confined");
                foreach (var observation in applicable)
                {
                    var environment = observation["environment"]!.AsObject();
                    check(environment.Count == 4 && new[] { "TEMP", "TMP", "TMPDIR" }.All(name => environment[name]!.GetValue<string>() == expected)
                        && environment["PYTHONDONTWRITEBYTECODE"]!.GetValue<string>() == "1", "actual child receives exactly the four intended temporary/bytecode overrides");
                    check(observation["inheritedMarker"]!.GetValue<string>() == marker, "actual child preserves an unrelated inherited environment value");
                    var witness = observation["witness"]!.GetValue<string>();
                    check(witness.StartsWith(expected + Path.DirectorySeparatorChar, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal) && File.Exists(witness), "actual child temporary witness stays inside its attempt");
                }
                var identity = w.Load<JsonObject>(stage.Artifacts["toolIdentity"]);
                var job = w.Load<JsonObject>(stage.Attempt + "/job.json");
                check(identity["processEnvironment"]!["temporaryDirectory"]!.GetValue<string>() == stage.Attempt + "/temp"
                    && JsonNode.DeepEquals(identity["processEnvironment"], job["processEnvironment"])
                    && identity["processEnvironment"]!["pythonDontWriteBytecode"]!.GetValue<bool>(), "native tool identity and job bind matching safe routing metadata");
            }
            check(ChildEnvironmentKeys.All(name => Environment.GetEnvironmentVariable(name) == parentEnvironment[name]), "child routing never mutates the parent process temporary/bytecode environment");
            foreach (var version in new[] { true, false })
            {
                native.FailVersionProbe = version; native.FailBatchProbe = !version;
                await reject(() => Run("finish"), "actual child intentional failure remains a failed native stage");
                var failed = w.Load<Manifest>(manifest).Stages["finish"];
                var identity = w.Load<JsonObject>(failed.Artifacts["toolIdentity"]);
                var witness = native.EnvironmentObservations.Last()["witness"]!.GetValue<string>();
                check(failed.Status == "failed" && File.Exists(witness) && identity["processEnvironment"]!["temporaryDirectory"]!.GetValue<string>() == failed.Attempt + "/temp", "failed version/batch child retains confined witness and native routing provenance");
                check(version == (identity["version"] is null), "version-failure provenance records unavailable version rather than inventing a successful probe");
                native.FailVersionProbe = false; native.FailBatchProbe = false;
            }
            native.ProbeEnvironment = false;
            var callsBefore = native.Calls.Count;
            var fileProxy = new TemporaryPathFault(w, path => File.WriteAllText(path, "CONTROLLED invalid temporary-directory file"));
            await reject(() => Run("finish", fileProxy), "a regular file cannot masquerade as a Blender temporary directory");
            check(native.Calls.Count == callsBefore, "invalid temporary-directory file is rejected before either native call");
            var target = parent.Resolve("blender-temp-junction-target"); Directory.CreateDirectory(target);
            var sentinel = Path.Combine(target, "unrelated-sentinel.txt"); File.WriteAllText(sentinel, "unchanged outside mocked project, inside controlled fixture root");
            var sentinelHash = Workspace.Hash(sentinel);
            void Link(string path)
            {
                if (OperatingSystem.IsWindows())
                    new NativeProcess().Run(Environment.GetEnvironmentVariable("COMSPEC")!, ["/d", "/c", "mklink", "/J", path, target], w.Root,
                        w.Resolve("temp-junction-" + Guid.NewGuid().ToString("N") + ".log"), 5).GetAwaiter().GetResult();
                else Directory.CreateSymbolicLink(path, target);
            }
            var junctionProxy = new TemporaryPathFault(w, Link);
            await reject(() => Run("finish", junctionProxy), "a pre-launch temporary-directory junction/symlink is rejected");
            check(native.Calls.Count == callsBefore && Workspace.Hash(sentinel) == sentinelHash, "pre-launch link rejection makes no child call and preserves its target");
            if (junctionProxy.InjectedPath is { } initialLink) Directory.Delete(initialLink);
            string? replaced = null;
            native.AfterVersion = environment =>
            {
                replaced = environment!["TEMP"];
                Directory.Delete(replaced); // Empty owned temp directory; no recursive deletion.
                Link(replaced);
                return Task.CompletedTask;
            };
            await reject(() => Run("finish"), "temporary-directory replacement after version probe blocks the batch launch");
            check(native.Calls.Count == callsBefore + 1 && Workspace.Hash(sentinel) == sentinelHash, "between-launch revalidation rejects the replaced directory without a batch child");
            native.AfterVersion = null;
            if (replaced is not null) Directory.Delete(replaced);
            if (OperatingSystem.IsWindows())
            {
                var longRoot = parent.Resolve("long-temp-project-" + new string('l', 150));
                Directory.CreateDirectory(longRoot);
                foreach (var source in Directory.EnumerateFiles(w.Root, "*", SearchOption.AllDirectories))
                {
                    var targetFile = Path.Combine(longRoot, Path.GetRelativePath(w.Root, source));
                    Directory.CreateDirectory(Path.GetDirectoryName(targetFile)!);
                    File.Copy(source, targetFile);
                }
                var longWorkspace = new Workspace(longRoot);
                var beforeLong = native.Calls.Count;
                await reject(() => Run("finish", longWorkspace), "overlong Windows child temporary paths are rejected before either launch");
                var failedLong = longWorkspace.Load<Manifest>(manifest).Stages["finish"];
                check(native.Calls.Count == beforeLong && failedLong.Error!.Contains("shorter project/task path", StringComparison.Ordinal)
                    && !Directory.Exists(Path.Combine(longRoot, failedLong.Attempt.Replace('/', Path.DirectorySeparatorChar), "temp")), "Windows path-limit rejection is actionable and does not choose or create an alternate temp location");
                var longTemporary = w.Resolve("runtime-length-probe-" + new string('p', 150) + "/temp");
                Directory.CreateDirectory(longTemporary);
                var unsafeEnvironment = new Dictionary<string, string>
                {
                    ["TEMP"] = longTemporary, ["TMP"] = longTemporary, ["TMPDIR"] = longTemporary, ["PYTHONDONTWRITEBYTECODE"] = "1"
                };
                var lengthLog = w.Resolve("controlled-long-temp-observation.log");
                await reject(() => new NativeProcess().Run(Environment.ProcessPath!, ["--blender-environment-probe"], w.Root, lengthLog, 15,
                    environment: unsafeEnvironment), "actual child observer refuses a fallback temporary API path before writing");
                var blocked = JsonNode.Parse(Compatibility.StripStreamMarkers(File.ReadAllText(lengthLog)))!.AsObject();
                check(blocked["blockedBeforeWrite"]!.GetValue<bool>() && !blocked.ContainsKey("witness"), "overlong-path regression produces no external witness or fallback write");
            }
            native.ReplaceToolIdentity = true;
            await reject(() => Run("finish"), "producer cannot substitute the native temporary/tool identity artifact");
            var failedSubstitution = w.Load<Manifest>(manifest).Stages["finish"];
            check(failedSubstitution.Status == "failed" && failedSubstitution.Artifacts["toolIdentity"] == failedSubstitution.Attempt + "/tool-identity.json", "failed substitution retains the original native provenance binding");
            native.ReplaceToolIdentity = false;
        }
        finally
        {
            Environment.SetEnvironmentVariable(InheritedMarker, markerBefore);
            native.ProbeEnvironment = false; native.FailVersionProbe = false; native.FailBatchProbe = false;
            native.AfterVersion = null; native.ReplaceToolIdentity = false;
        }
    }

    sealed class TemporaryPathFault(Workspace inner, Action<string> inject) : IWorkspace
    {
        bool armed = true;
        public string? InjectedPath { get; private set; }
        public string Root => inner.Root;
        public string Resolve(string path)
        {
            if (armed && path.Replace('\\', '/').EndsWith("/temp", StringComparison.Ordinal))
            {
                armed = false; InjectedPath = inner.Resolve(path); inject(InjectedPath);
            }
            return inner.Resolve(path);
        }
        public string Relative(string path) => inner.Relative(path);
        public string HashFile(string path) => inner.HashFile(path);
        public void Save<T>(string path, T value) => inner.Save(path, value);
        public T Load<T>(string path) => inner.Load<T>(path);
        public FileStream Lock(string path) => inner.Lock(path);
    }

    static async Task CheckMultiViewPreservation(Workspace parent, string baseline, Action<bool, string> check)
    {
        // Extend a separate copy of the earlier successful six-view ENGINE SIMULATION.
        // Toolchain/approval construction below is synthetic fixture setup, never a
        // production migration or an authorization to rebind real upstream evidence.
        var original = Directory.GetDirectories(parent.Root, "mv-runtime-valid-*").Single();
        var root = parent.Resolve("mv-finishing-preservation"); Directory.CreateDirectory(root);
        foreach (var file in Directory.EnumerateFiles(original, "*", SearchOption.AllDirectories))
        {
            var output = Path.Combine(root, Path.GetRelativePath(original, file)); Directory.CreateDirectory(Path.GetDirectoryName(output)!); File.Copy(file, output);
        }
        var w = new Workspace(root);
        var manifest = ".opencaw/.cache/tasks/multiview-runtime-tests/proof-to-model/valid/v1/manifest.json";
        var state = w.Load<Manifest>(manifest); var toolchain = w.Load<JsonObject>(state.Toolchain);
        toolchain["blender"] = new JsonObject { ["path"] = Environment.ProcessPath! }; w.Save(state.Toolchain, toolchain);
        foreach (var stage in state.Stages.Values)
        {
            if (stage.Inputs.ContainsKey(state.Toolchain)) stage.Inputs[state.Toolchain] = Workspace.Hash(w.Resolve(state.Toolchain));
            stage.Fingerprint = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", stage.Inputs.Keys.Order().Select(path => path + ":" + Workspace.Hash(w.Resolve(path)))))));
        }
        state.Approvals.Clear(); w.Save(manifest, state);
        var native = new SimulatedFinisher(w);
        var opts = new Dictionary<string, string> { ["manifest"] = manifest, ["baseline-root"] = baseline };
        foreach (var kind in new[] { "proof-set", "preprocessing" })
        {
            var output = new StringWriter(); var previous = Console.Out;
            try { Console.SetOut(output); await new Pipeline(w, opts, native, new AlphaProcessor()).Execute("status", default); }
            finally { Console.SetOut(previous); }
            var status = JsonNode.Parse(output.ToString())!;
            var receipt = ".opencaw/.cache/tasks/multiview-runtime-tests/reviews/synthetic-finisher-" + kind + ".json";
            w.Save(receipt, new { kind, reviewer = "synthetic-only", decision = "approved", human = true,
                reason = "SIMULATED test receipt; not production human acceptance",
                fingerprint = status["approvalFingerprints"]![kind == "proof-set" ? "proofSet" : "preprocessing"]!.GetValue<string>() });
            var record = new Dictionary<string, string>(opts) { ["kind"] = kind, ["reviewer"] = "synthetic-only", ["evidence"] = receipt };
            await new Pipeline(w, record, native, new AlphaProcessor()).Execute("record", default);
        }
        state = w.Load<Manifest>(manifest);
        var upstream = JsonSerializer.Serialize(state.Stages, Serialization.Json);
        var approvals = JsonSerializer.Serialize(state.Approvals, Serialization.Json);
        var paths = new[] { state.Proof, state.SourceSet, state.Classification, state.ProofSet, state.Recipe }
            .Concat(state.Stages.Values.SelectMany(stage => stage.Inputs.Keys.Concat(stage.Outputs.Keys))).Distinct().ToDictionary(path => path, path => Workspace.Hash(w.Resolve(path)));
        var solverSelected = SimplificationSelection();
        File.WriteAllText(w.Resolve("finishing.json"), solverSelected); opts["finish-settings"] = "finishing.json";
        await new Pipeline(w, opts, native, new AlphaProcessor()).Execute("finish", default);
        var current = w.Load<Manifest>(manifest);
        var retained = current.Stages.Where(pair => pair.Key != "finish").ToDictionary(pair => pair.Key, pair => pair.Value);
        check(JsonSerializer.Serialize(retained, Serialization.Json) == upstream && paths.All(pair => Workspace.Hash(w.Resolve(pair.Key)) == pair.Value), "SIMULATED six-view finishing preserves exact classify/proof/camera/preprocess/reconstruction contracts and file hashes");
        check(JsonSerializer.Serialize(current.Approvals, Serialization.Json) == approvals, "SIMULATED six-view finishing retains exact whole-set and preprocessing approvals");
        check(native.Jobs.Single()["mode"]!.GetValue<string>() == "multi-view" && JsonNode.DeepEquals(native.Jobs.Single()["finishingSettings"], JsonNode.Parse(solverSelected)), "SIMULATED six-view finish forwards separate explicit solver settings without altering the camera/proof job contract");
    }

    static void WriteSyntheticGlb(string path)
    {
        var data = new byte[20]; BitConverter.GetBytes(0x46546c67u).CopyTo(data, 0); BitConverter.GetBytes(2u).CopyTo(data, 4); BitConverter.GetBytes(20u).CopyTo(data, 8); File.WriteAllBytes(path, data);
    }
    sealed class SimulatedFinisher(Workspace w) : INativeProcess
    {
        public List<JsonObject> Jobs { get; } = [];
        public List<(bool Version, Dictionary<string, string>? Environment)> Calls { get; } = [];
        public List<JsonObject> EnvironmentObservations { get; } = [];
        public bool ProbeEnvironment { get; set; }
        public bool FailVersionProbe { get; set; }
        public bool FailBatchProbe { get; set; }
        public bool ReplaceToolIdentity { get; set; }
        public Func<IReadOnlyDictionary<string, string>?, Task>? AfterVersion { get; set; }
        public bool ReplaceSnapshot { get; set; }
        public Action? Mutate { get; set; }
        public async Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
        {
            cancellation.ThrowIfCancellationRequested(); var args = arguments.ToArray(); Directory.CreateDirectory(Path.GetDirectoryName(log)!);
            var version = args.SequenceEqual(["--version"]);
            Calls.Add((version, environment?.ToDictionary(pair => pair.Key, pair => pair.Value)));
            if (ProbeEnvironment)
            {
                var childLog = Path.Combine(Path.GetDirectoryName(log)!, "actual-child-environment-" + Guid.NewGuid().ToString("N") + ".log");
                var childArgs = new List<string> { "--blender-environment-probe" };
                if (version ? FailVersionProbe : FailBatchProbe) childArgs.Add("--fail");
                try { await new NativeProcess().Run(Environment.ProcessPath!, childArgs, cwd, childLog, 15, cancellation, maximumLogBytes, environment); }
                finally
                {
                    if (File.Exists(childLog))
                    {
                        var observed = Compatibility.StripStreamMarkers(File.ReadAllText(childLog)).Trim();
                        if (observed.Length != 0) EnvironmentObservations.Add(JsonNode.Parse(observed)!.AsObject());
                    }
                }
            }
            if (version)
            {
                File.WriteAllText(log, "Blender 4.5.10 LTS\nSIMULATED VERSION ONLY");
                if (AfterVersion is not null) await AfterVersion(environment);
                return;
            }
            var job = w.Load<JsonObject>(args[Array.IndexOf(args, "--job") + 1]); Jobs.Add(job);
            var output = job["outputDir"]!.GetValue<string>(); Directory.CreateDirectory(w.Resolve(output));
            File.WriteAllText(w.Resolve(output + "/source.blend"), "BLENDER-SIMULATED-NOT-A-PRODUCTION-MODEL");
            WriteSyntheticGlb(w.Resolve(output + "/asset.glb"));
            w.Save(output + "/report.json", new { scope = "SIMULATED producer only; not Blender geometry, visual acceptance or human approval" });
            var artifacts = new JsonObject { ["blend"] = output + "/source.blend", ["glb"] = output + "/asset.glb", ["report"] = output + "/report.json" };
            if (ReplaceSnapshot) artifacts["finishingSettings"] = output + "/report.json";
            if (ReplaceToolIdentity) artifacts["toolIdentity"] = output + "/report.json";
            w.Save(job["result"]!.GetValue<string>(), new JsonObject { ["status"] = "prepared", ["stages"] = new JsonArray(), ["measurements"] = new JsonObject(), ["artifacts"] = artifacts });
            File.WriteAllText(log, "SIMULATED producer, no real native Blender execution."); Mutate?.Invoke();
            return;
        }
    }
}
