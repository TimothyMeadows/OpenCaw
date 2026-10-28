using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;

static class FinishAttemptBudgetTests
{
    static JsonObject Receipt(string hash, int consumed = 3) => new()
    {
        ["schemaVersion"] = 1, ["kind"] = "finish-attempt-budget", ["stage"] = "finish", ["decision"] = "approved",
        ["human"] = true, ["reviewer"] = "SIMULATED reviewer", ["reason"] = "SYNTHETIC TEST ONLY: one extra fixture attempt, not actual human approval",
        ["manifestSha256"] = hash, ["consumedFinishAttempts"] = consumed, ["maxFinishAttempts"] = consumed + 1
    };
    public static async Task Run(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        FinishAttemptBudget Parse(JsonObject value) => FinishAttemptBudget.Parse(Encoding.UTF8.GetBytes(value.ToJsonString()));
        var valid = Receipt(new string('a', 64));
        check(Parse(valid).MaxFinishAttempts == 4, "budget parser accepts exactly one additional explicit finish attempt");
        var integer = (JsonObject)valid.DeepClone(); integer["schemaVersion"] = 1.0; integer["consumedFinishAttempts"] = 3.0; integer["maxFinishAttempts"] = 4.0;
        check(Parse(integer).ConsumedFinishAttempts == 3, "budget integers match JSON Schema numerical integer semantics");
        foreach (var exact in new[] { "3.0", "30e-1", "3000000e-6", "0.0003e4", "3e" + new string('0', 1000) })
        {
            var text = valid.ToJsonString().Replace("\"consumedFinishAttempts\":3", "\"consumedFinishAttempts\":" + exact);
            check(FinishAttemptBudget.Parse(Encoding.UTF8.GetBytes(text)).ConsumedFinishAttempts == 3, "budget exact decimal/exponent integer normalization accepts bounded values");
        }
        foreach (var fraction in new[] { "3.000000000000000000000001", "3000000000000000000000001e-24", "3e" + new string('9', 1000) })
        {
            var text = valid.ToJsonString().Replace("\"consumedFinishAttempts\":3", "\"consumedFinishAttempts\":" + fraction);
            await reject(() => Task.Run(() => FinishAttemptBudget.Parse(Encoding.UTF8.GetBytes(text))), "budget rejects near-integer fractional residue or huge exponent without binary64 rounding");
        }
        foreach (var underflow in new[] { "1e-9999", "-1e-9999", "0.000000000000000000000000001" })
        {
            var text = Receipt(new string('a', 64), 0).ToJsonString().Replace("\"consumedFinishAttempts\":0", "\"consumedFinishAttempts\":" + underflow);
            await reject(() => Task.Run(() => FinishAttemptBudget.Parse(Encoding.UTF8.GetBytes(text))), "budget fractional underflow cannot masquerade as exact zero");
        }
        var zeroExponent = Receipt(new string('a', 64), 0).ToJsonString().Replace("\"consumedFinishAttempts\":0", "\"consumedFinishAttempts\":0e" + new string('9', 1000));
        check(FinishAttemptBudget.Parse(Encoding.UTF8.GetBytes(zeroExponent)).ConsumedFinishAttempts == 0, "budget exact zero handles arbitrarily large bounded-input exponent without allocation growth");
        var unicode = (JsonObject)valid.DeepClone(); unicode["reviewer"] = string.Concat(Enumerable.Repeat("🦉", 200));
        check(Parse(unicode).Reviewer.EnumerateRunes().Count() == 200, "budget reviewer limit counts Unicode characters rather than UTF-16 units");
        var boundary = Receipt(new string('0', 64), 99); boundary["reason"] = new string('x', 4000);
        check(Parse(boundary).MaxFinishAttempts == 100, "budget100 and reason4000 boundaries accepted");
        foreach (var change in new Action<JsonObject>[] {
            x => x.Remove("reason"), x => x["extra"] = 1, x => x["schemaVersion"] = 2,
            x => x["schemaVersion"] = "1", x => x["kind"] = "approval", x => x["stage"] = "reconstruct",
            x => x["decision"] = "pending", x => x["human"] = false, x => x["human"] = 1,
            x => x["reviewer"] = "\u0085\u00a0", x => x["reason"] = "\u0085\u3000", x => x["reviewer"] = "first\nsecond",
            x => x["reviewer"] = "first\u2028second", x => x["reviewer"] = "first\tsecond", x => x["reviewer"] = new string('x', 201),
            x => x["reviewer"] = string.Concat(Enumerable.Repeat("🦉", 201)), x => x["reason"] = new string('x', 4001),
            x => x["reason"] = null, x => x["manifestSha256"] = new string('A', 64), x => x["manifestSha256"] = new string('g', 64),
            x => x["manifestSha256"] = "abc", x => x["manifestSha256"] = new string('a', 64) + "\n", x => x["consumedFinishAttempts"] = "3", x => x["consumedFinishAttempts"] = 3.5,
            x => x["consumedFinishAttempts"] = -1, x => x["consumedFinishAttempts"] = 100,
            x => x["maxFinishAttempts"] = 3, x => x["maxFinishAttempts"] = 5, x => x["maxFinishAttempts"] = 101,
            x => x["maxFinishAttempts"] = true
        })
        {
            var bad = (JsonObject)valid.DeepClone(); change(bad);
            await reject(() => Task.Run(() => Parse(bad)), "budget missing/unknown/nonhuman/string/count/Unicode/boundary violations rejected");
        }
        foreach (var text in new[] { "null", "[]", "{}", "{", valid.ToJsonString().Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            valid.ToJsonString().Replace("\"maxFinishAttempts\":4", "\"maxFinishAttempts\":1e999"), new string(' ', FinishAttemptBudget.MaximumBytes + 1) })
            await reject(() => Task.Run(() => FinishAttemptBudget.Parse(Encoding.UTF8.GetBytes(text))), "budget malformed/duplicate/nonfinite/oversize JSON rejected");

        var fixture = await Fixture.Create(parent, "success");
        var before = fixture.State;
        var upstream = fixture.Upstream(); var approvals = fixture.Approvals(); var config = fixture.W.HashFile(fixture.W.Resolve("toolchain.json"));
        await reject(() => fixture.Run(), "SIMULATED default exhausted finish remains blocked without a receipt");
        check(fixture.Count == 3 && fixture.Native.Calls == 0, "SIMULATED exhausted default does not create a fourth attempt");
        var receipt = fixture.WriteReceipt(); fixture.Options["finish-budget"] = receipt;
        var originalBytes = File.ReadAllBytes(fixture.W.Resolve(receipt)); var originalHash = fixture.Hash;
        fixture.Native.OnInvoke = () => {
            var persisted = fixture.State; var entry = persisted.History.Last(); var stage = persisted.Stages["finish"];
            check(fixture.Count == 4 && entry["finishBudget"]!["manifestSha256"]!.GetValue<string>() == originalHash && stage.Status == "running", "SIMULATED budget spend is durably recorded before any native launch");
            check(stage.Outputs[stage.Artifacts["finishBudget"]] == stage.Inputs[receipt], "SIMULATED budget snapshot hash is persisted before native execution");
        };
        await fixture.Run(); fixture.Native.OnInvoke = null;
        var finish = fixture.State.Stages["finish"]; var snapshot = finish.Artifacts["finishBudget"];
        check(fixture.Count == 4 && finish.Status == "complete", "SIMULATED valid human receipt admits exactly one extra finish");
        check(File.ReadAllBytes(fixture.W.Resolve(snapshot)).SequenceEqual(originalBytes) && finish.Inputs[receipt] == finish.Inputs[snapshot] && finish.Outputs[snapshot] == finish.Inputs[receipt], "SIMULATED receipt original and exact snapshot are bound as inputs/output artifact");
        var history = fixture.State.History.Last()["finishBudget"]!;
        check(history["source"]!.GetValue<string>() == receipt && history["snapshot"]!.GetValue<string>() == snapshot && history["sourceSha256"]!.GetValue<string>() == history["snapshotSha256"]!.GetValue<string>(), "SIMULATED history retains both authorization paths and exact hashes");
        check(fixture.Upstream() == upstream && fixture.Approvals() == approvals && fixture.W.HashFile(fixture.W.Resolve("toolchain.json")) == config, "SIMULATED budget grant preserves upstream stages, proof approvals and original toolchain");
        var after = fixture.Hash; var calls = fixture.Native.Calls;
        await reject(() => fixture.Run(), "SIMULATED same budget receipt cannot be replayed after success");
        var copiedReceipt = ".opencaw/.cache/tasks/tests/reviews/copied-budget.json"; File.WriteAllBytes(fixture.W.Resolve(copiedReceipt), originalBytes);
        fixture.Options["finish-budget"] = copiedReceipt;
        await reject(() => fixture.Run(), "SIMULATED identical receipt bytes at a different task path cannot be replayed");
        check(fixture.Hash == after && fixture.Native.Calls == calls && fixture.Count == 4, "SIMULATED replay rejections do not write state or launch tools");
        fixture.Options.Remove("finish-budget"); await fixture.Command("validate");
        File.AppendAllText(fixture.W.Resolve(receipt), " ");
        await reject(() => fixture.Command("validate"), "SIMULATED source receipt mutation invalidates completed finish evidence");
        File.WriteAllBytes(fixture.W.Resolve(receipt), originalBytes);
        File.AppendAllText(fixture.W.Resolve(snapshot), " ");
        await reject(() => fixture.Command("validate"), "SIMULATED immutable budget snapshot mutation invalidates completed evidence");
        File.WriteAllBytes(fixture.W.Resolve(snapshot), originalBytes);

        var invalid = await Fixture.Create(parent, "invalid");
        var path = invalid.WriteReceipt(); invalid.Options["finish-budget"] = path;
        var baseline = invalid.Hash;
        async Task Bad(Action<JsonObject> change, string label)
        {
            var candidate = Receipt(baseline); change(candidate); invalid.W.Save(path, candidate);
            await reject(() => invalid.Run(), "SIMULATED " + label);
            check(invalid.Hash == baseline && invalid.Count == 3 && invalid.Native.Calls == 0, "SIMULATED invalid budget request is nonmutating");
        }
        await Bad(x => x["manifestSha256"] = new string('b', 64), "budget requires exact full current manifest hash");
        await Bad(x => { x["consumedFinishAttempts"] = 2; x["maxFinishAttempts"] = 3; }, "budget requires exact consumed history count");
        await Bad(x => x["maxFinishAttempts"] = 5, "budget cannot authorize multiple extra attempts");
        await Bad(x => x["stage"] = "preprocess", "budget cannot select another stage");
        invalid.W.Save(path, Receipt(baseline)); File.AppendAllText(invalid.W.Resolve(invalid.ManifestPath), " ");
        var sameCountChangedManifest = invalid.Hash;
        await reject(() => invalid.Run(), "SIMULATED changed full manifest with unchanged attempt count invalidates receipt");
        check(invalid.Hash == sameCountChangedManifest && invalid.Count == 3, "SIMULATED stale manifest rejection preserves supplied state");
        invalid.WriteReceipt(); baseline = invalid.Hash;
        var permitted = invalid.Options["finish-budget"];
        foreach (var badPath in new[] { "../escape.json", "./budget.json", "folder/../budget.json", "NUL.json", invalid.W.Resolve(permitted), "outside-task.json" })
        {
            File.WriteAllText(invalid.W.Resolve("outside-task.json"), Receipt(baseline).ToJsonString());
            invalid.Options["finish-budget"] = badPath;
            await reject(() => invalid.Run(), "SIMULATED budget path must be lexically safe, project-relative and task-local");
        }
        invalid.Options["finish-budget"] = permitted;
        var junctionTarget = parent.Resolve("budget-junction-target"); Directory.CreateDirectory(junctionTarget); File.WriteAllText(Path.Combine(junctionTarget, "receipt.json"), Receipt(baseline).ToJsonString());
        var junction = invalid.W.Resolve(".opencaw/.cache/tasks/tests/reviews/link");
        if (OperatingSystem.IsWindows()) await new NativeProcess().Run(Environment.GetEnvironmentVariable("COMSPEC")!, ["/d", "/c", "mklink", "/J", junction, junctionTarget], invalid.W.Root, invalid.W.Resolve("junction.log"), 5);
        else Directory.CreateSymbolicLink(junction, junctionTarget);
        invalid.Options["finish-budget"] = ".opencaw/.cache/tasks/tests/reviews/link/receipt.json";
        await reject(() => invalid.Run(), "SIMULATED actual task-local junction escape cannot provide budget authority"); Directory.Delete(junction);
        invalid.Options["finish-budget"] = permitted;
        foreach (var command in new[] { "init", "status", "doctor", "setup", "classify", "prepare-proofs", "preprocess", "reconstruct", "review", "record", "validate", "promote" })
            await reject(() => invalid.Command(command), "SIMULATED finish budget flag rejected on " + command);
        check(invalid.Hash == baseline && invalid.Native.Calls == 0, "SIMULATED invalid path/command grants never save manifest or launch native code");

        var unexhausted = await Fixture.Create(parent, "unexhausted", consumed: 2);
        unexhausted.Options["finish-budget"] = unexhausted.WriteReceipt();
        await reject(() => unexhausted.Run(), "SIMULATED recovery cannot override an unexhausted configured budget");
        check(unexhausted.Count == 2 && unexhausted.Native.Calls == 0, "SIMULATED premature authorization does not lower configured limit");
        var failed = await Fixture.Create(parent, "failed"); var failedReceipt = failed.WriteReceipt(); failed.Options["finish-budget"] = failedReceipt; failed.Native.Fail = true;
        await reject(() => failed.Run(), "SIMULATED failed native finishing still spends the one authorized start");
        check(failed.Count == 4 && failed.State.Stages["finish"].Status == "failed" && failed.State.Stages["finish"].Artifacts.ContainsKey("finishBudget"), "SIMULATED failed attempt retains budget snapshot, hashes and spent history");
        failed.Native.Fail = false; await reject(() => failed.Run(), "SIMULATED failed attempt cannot reuse the same receipt");
        var cancelled = await Fixture.Create(parent, "cancelled"); cancelled.Options["finish-budget"] = cancelled.WriteReceipt();
        using (var cancel = new CancellationTokenSource()) { cancel.Cancel(); await reject(() => cancelled.Run(cancel.Token), "SIMULATED cancelled finishing spends its durable authorization"); }
        check(cancelled.Count == 4 && cancelled.State.Stages["finish"].Status == "failed" && cancelled.Native.Calls == 0 && cancelled.State.Stages["finish"].Outputs.Count == 1, "SIMULATED cancellation before tool launch preserves the sole budget snapshot output");
        await reject(() => cancelled.Run(), "SIMULATED cancelled authorization cannot be replayed");
        var interrupted = await Fixture.Create(parent, "interrupted"); interrupted.Options["finish-budget"] = interrupted.WriteReceipt();
        await reject(() => new Pipeline(new InterruptAfterSpend(interrupted.W), interrupted.Options, interrupted.Native, new AlphaProcessor()).Execute("finish", default), "SIMULATED interruption after durable spend before producer launch");
        check(interrupted.Count == 4 && interrupted.State.Stages["finish"].Status == "running" && interrupted.Native.Calls == 0, "SIMULATED interrupted running state retains one spent authorization");
        await reject(() => interrupted.Run(), "SIMULATED interrupted authorization cannot replay through recovery");
        var substitution = await Fixture.Create(parent, "substitution"); substitution.Options["finish-budget"] = substitution.WriteReceipt(); substitution.Native.ReplaceBudget = true;
        await reject(() => substitution.Run(), "SIMULATED producer cannot replace native finishBudget artifact");
        check(substitution.Count == 4 && substitution.State.Stages["finish"].Status == "failed", "SIMULATED producer substitution spends receipt but cannot complete stage");
        foreach (var target in new[] { "source", "snapshot" })
        {
            var mutation = await Fixture.Create(parent, "mutation-" + target); var receiptPath = mutation.WriteReceipt(); mutation.Options["finish-budget"] = receiptPath;
            mutation.Native.Mutate = () => File.AppendAllText(mutation.W.Resolve(target == "source" ? receiptPath : mutation.State.Stages["finish"].Artifacts["finishBudget"]), " ");
            await reject(() => mutation.Run(), "SIMULATED mid-run " + target + " mutation cannot create a completed budgeted finish");
            check(mutation.Count == 4 && mutation.State.Stages["finish"].Status == "failed", "SIMULATED mutated budget attempt remains spent and failed");
        }
        var current = await Fixture.Create(parent, "status"); var statusHash = current.Hash; var output = new StringWriter(); var previous = Console.Out;
        try { Console.SetOut(output); await current.Command("status"); } finally { Console.SetOut(previous); }
        var status = JsonNode.Parse(output.ToString())!;
        check(status["manifestSha256"]!.GetValue<string>() == statusHash && status["finishBudget"]!["consumedFinishAttempts"]!.GetValue<int>() == 3 && current.Hash == statusHash, "actual status exposes exact receipt context without writing or granting authority");
    }

    sealed class Fixture
    {
        public required Workspace W { get; init; }
        public required string ManifestPath { get; init; }
        public required Dictionary<string, string> Options { get; init; }
        public required SimulatedFinish Native { get; init; }
        public Manifest State => W.Load<Manifest>(ManifestPath);
        public string Hash => W.HashFile(W.Resolve(ManifestPath));
        public int Count => State.History.Count(item => item["event"]?.GetValue<string>() == "stage-start" && item["stage"]?.GetValue<string>() == "finish");
        public Task Run(CancellationToken token = default) => new Pipeline(W, Options, Native, new AlphaProcessor()).Execute("finish", token);
        public Task Command(string name) => new Pipeline(W, Options, Native, new AlphaProcessor()).Execute(name, default);
        public string Upstream() => JsonSerializer.Serialize(State.Stages.Where(pair => pair.Key is "preprocess" or "reconstruct").ToDictionary(pair => pair.Key, pair => pair.Value), Serialization.Json);
        public string Approvals() => JsonSerializer.Serialize(State.Approvals, Serialization.Json);
        public string WriteReceipt()
        {
            var path = ".opencaw/.cache/tasks/tests/reviews/budget.json";
            W.Save(path, Receipt(Hash, Count)); return path;
        }
        public static async Task<Fixture> Create(Workspace parent, string name, int consumed = 3)
        {
            var root = parent.Resolve("finish-budget-" + name); Directory.CreateDirectory(root); var w = new Workspace(root);
            File.WriteAllText(w.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL\n");
            RgbaPng.Write(w.Resolve("source.png"), new RgbaPng.Image(2, 2, Enumerable.Repeat((byte)255, 16).ToArray()));
            w.Save("rights.json", new { authorized = true, source = "SIMULATED fixture only" }); w.Save("recipe.json", parent.Load<JsonObject>("recipe.json"));
            w.Save("toolchain.json", new { schemaVersion = 1, files = Array.Empty<object>(), models = Array.Empty<object>(), blender = new { path = Environment.ProcessPath! }, limits = new { maxAttempts = 3, timeoutSeconds = 10 } });
            var baseline = w.Resolve("baseline"); var scripts = Path.Combine(baseline, ".styles/.pipelines/proof-to-model/blender"); Directory.CreateDirectory(scripts);
            foreach (var file in new[] { "finish.py", "review.py", "common.py" }) File.WriteAllText(Path.Combine(scripts, file), "# SIMULATED fixed producer fixture, not Blender code\n");
            var options = new Dictionary<string, string> { ["mode"] = "single-view-diagnostic", ["asset"] = "budget", ["version"] = "v1", ["task"] = "tests", ["proof"] = "source.png", ["rights"] = "rights.json", ["recipe"] = "recipe.json", ["toolchain"] = "toolchain.json", ["actor"] = "synthetic-builder", ["baseline-root"] = baseline };
            var native = new SimulatedFinish(w); await new Pipeline(w, options, native, new AlphaProcessor()).Execute("init", default);
            var manifest = ".opencaw/.cache/tasks/tests/proof-to-model/budget/v1/manifest.json"; options["manifest"] = manifest;
            var state = w.Load<Manifest>(manifest); Directory.CreateDirectory(w.Resolve(state.Staging + "/fixture"));
            var normalized = state.Staging + "/fixture/input.dat"; File.WriteAllText(w.Resolve(normalized), "SIMULATED preprocessing");
            var raw = state.Staging + "/fixture/raw.glb"; SyntheticGlb(w.Resolve(raw));
            state.Stages["preprocess"] = new Stage { Status = "complete", Attempt = state.Staging + "/fixture", Outputs = new() { [normalized] = w.HashFile(w.Resolve(normalized)) }, Artifacts = new() { ["normalized"] = normalized } };
            state.Stages["reconstruct"] = new Stage { Status = "complete", Attempt = state.Staging + "/fixture", Outputs = new() { [raw] = w.HashFile(w.Resolve(raw)) }, Artifacts = new() { ["glb"] = raw } };
            var core = new[] { state.Proof, state.ProofMetadata, state.Rights, state.Recipe, state.Toolchain, "STYLE.md" };
            foreach (var kind in new[] { "proof", "preprocessing" })
            {
                var path = ".opencaw/.cache/tasks/tests/reviews/" + kind + ".json"; w.Save(path, new { reason = "SIMULATED approval only" });
                var paths = kind == "proof" ? core : core.Append(normalized);
                var fingerprint = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", paths.Order().Select(file => file + ":" + w.HashFile(w.Resolve(file)))))));
                state.Approvals.Add(new(kind, "synthetic", path, w.HashFile(w.Resolve(path)), fingerprint, DateTimeOffset.UtcNow));
            }
            for (var index = 0; index < consumed; index++) state.History.Add(new JsonObject { ["event"] = "stage-start", ["stage"] = "finish", ["attempt"] = "SIMULATED-previous-failed-" + index });
            w.Save(manifest, state); return new() { W = w, Options = options, Native = native, ManifestPath = manifest };
        }
    }
    static void SyntheticGlb(string path)
    {
        var bytes = new byte[20]; BitConverter.GetBytes(0x46546c67u).CopyTo(bytes, 0); BitConverter.GetBytes(2u).CopyTo(bytes, 4); BitConverter.GetBytes(20u).CopyTo(bytes, 8); File.WriteAllBytes(path, bytes);
    }
    sealed class SimulatedFinish(Workspace w) : INativeProcess
    {
        public int Calls { get; private set; }
        public bool Fail { get; set; }
        public bool ReplaceBudget { get; set; }
        public Action? OnInvoke { get; set; }
        public Action? Mutate { get; set; }
        public Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
        {
            cancellation.ThrowIfCancellationRequested(); Calls++; OnInvoke?.Invoke(); if (Fail) throw new IOException("SIMULATED failed producer");
            var args = arguments.ToArray(); Directory.CreateDirectory(Path.GetDirectoryName(log)!);
            if (args.SequenceEqual(["--version"])) { File.WriteAllText(log, "Blender 4.5.10 LTS\nSIMULATED version"); return Task.CompletedTask; }
            var job = w.Load<JsonObject>(args[Array.IndexOf(args, "--job") + 1]); var output = job["outputDir"]!.GetValue<string>(); Directory.CreateDirectory(w.Resolve(output));
            File.WriteAllText(w.Resolve(output + "/source.blend"), "BLENDER-SIMULATED"); SyntheticGlb(w.Resolve(output + "/model.glb")); w.Save(output + "/report.json", new { simulated = true });
            var artifacts = new JsonObject { ["blend"] = output + "/source.blend", ["glb"] = output + "/model.glb", ["report"] = output + "/report.json" };
            if (ReplaceBudget) artifacts["finishBudget"] = output + "/report.json";
            w.Save(job["result"]!.GetValue<string>(), new JsonObject { ["status"] = "prepared", ["stages"] = new JsonArray(), ["measurements"] = new JsonObject(), ["artifacts"] = artifacts });
            File.WriteAllText(log, "SIMULATED native producer; no actual Blender finishing or human approval."); Mutate?.Invoke(); return Task.CompletedTask;
        }
    }
    sealed class InterruptAfterSpend(Workspace inner) : IWorkspace
    {
        public string Root => inner.Root;
        public string Resolve(string path) => inner.Resolve(path);
        public string Relative(string path) => inner.Relative(path);
        public string HashFile(string path) => inner.HashFile(path);
        public T Load<T>(string path) => inner.Load<T>(path);
        public FileStream Lock(string path) => inner.Lock(path);
        public void Save<T>(string path, T value)
        {
            inner.Save(path, value);
            if (value is Manifest state && state.Stages.TryGetValue("finish", out var stage) && stage.Status == "running" && state.History.Last()["finishBudget"] is not null)
                throw new IOException("SIMULATED crash immediately after persisted budget spend, before native launch");
        }
    }
}
