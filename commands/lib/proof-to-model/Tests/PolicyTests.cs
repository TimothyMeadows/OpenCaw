using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;
static class PolicyTests
{
    public static async Task Run(Workspace w, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        check(Compatibility.AtLeast("617.42", "575") && !Compatibility.AtLeast("570.99", "575"), "driver versions compared numerically");
        check(Compatibility.AtLeast("13.1", "12.9") && !Compatibility.AtLeast("12.8", "12.9"), "CUDA compatibility minimum enforced");
        var cfg = w.Load<JsonObject>("toolchain.json");
        var cfgOriginal = cfg.DeepClone();
        cfg["limits"] = new JsonObject { ["maxAttempts"] = 1, ["timeoutSeconds"] = 5 };
        w.Save("toolchain.json", cfg);
        var opts = new Dictionary<string, string> { { "asset", "budgets" }, { "version", "v1" }, { "task", "tests" }, { "proof", "matte.png" }, { "rights", "rights.json" }, { "recipe", "recipe.json" }, { "toolchain", "toolchain.json" }, { "actor", "builder" } };
        await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("init", default);
        var manifest = ".opencaw/.cache/tasks/tests/proof-to-model/budgets/v1/manifest.json";
        opts["manifest"] = manifest;
        string Fingerprint(string kind)
        {
            var state = w.Load<Manifest>(manifest);
            IEnumerable<string> outputs = kind == "proof" ? [] : kind == "preprocessing" ? state.Stages["preprocess"].Outputs.Keys : state.Stages.Where(p => p.Value.Status == "complete" && (!(kind is "rigging" or "animation") || p.Key != "review")).SelectMany(p => p.Value.Outputs.Keys);
            return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", outputs.Concat(new[] { state.Proof, state.ProofMetadata, "rights.json", "recipe.json", "toolchain.json", "STYLE.md" }).Order().Select(x => x + ":" + Workspace.Hash(w.Resolve(x)))))));
        }
        async Task Approve(string kind, string reviewer = "human", string? artifact = null)
        {
            var receipt = ".opencaw/.cache/tasks/tests/reviews/policy-" + kind + ".json";
            var evidence = new JsonObject { ["kind"] = kind, ["reviewer"] = reviewer, ["decision"] = "approved", ["fingerprint"] = Fingerprint(kind), ["reason"] = "Synthetic policy test receipt; not production acceptance", ["human"] = true };
            if (artifact is not null)
            {
                opts["artifact"] = artifact;
                evidence["artifactHash"] = Workspace.Hash(w.Resolve(artifact));
                if (opts.TryGetValue("source", out var editable))
                {
                    evidence["sourceHash"] = Workspace.Hash(w.Resolve(editable));
                    evidence["sourceCorrespondence"] = "Synthetic matching-source policy fixture; not real Blender verification";
                }
            }
            else
                opts.Remove("artifact");
            w.Save(receipt, evidence);
            opts["kind"] = kind;
            opts["reviewer"] = reviewer;
            opts["evidence"] = receipt;
            await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("record", default);
        }
        await Approve("proof");
        opts["timeout"] = "6";
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("preprocess", default), "timeout override cannot exceed selected budget");
        check(w.Load<Manifest>(manifest).Stages.Count == 0, "over-budget request creates no stage attempt");
        opts.Remove("timeout");
        await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("preprocess", default);
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("preprocess", default), "maxAttempts prevents repeated native stage execution");
        await Approve("preprocessing");
        // Controlled prebuilt manifests test guided routing without claiming Blender verification.
        var state = w.Load<Manifest>(manifest);
        var attempt = state.Staging + "/fixture";
        Directory.CreateDirectory(w.Resolve(attempt));
        string MakeGlb(string name, JsonObject body)
        {
            var path = attempt + "/" + name;
            var json = Encoding.UTF8.GetBytes(body.ToJsonString());
            var pad = (4 - json.Length % 4) % 4;
            using var stream = File.Create(w.Resolve(path));
            using var writer = new BinaryWriter(stream);
            writer.Write(0x46546c67u);
            writer.Write(2u);
            writer.Write((uint)(20 + json.Length + pad));
            writer.Write((uint)(json.Length + pad));
            writer.Write(0x4E4F534Au);
            writer.Write(json);
            writer.Write(Enumerable.Repeat((byte)32, pad).ToArray());
            return path;
        }
        var raw = MakeGlb("source.glb", new JsonObject { ["asset"] = new JsonObject { ["version"] = "2.0" } });
        var hash = Workspace.Hash(w.Resolve(raw));
        state.Stages["reconstruct"] = new()
        {
            Status = "complete",
            Attempt = attempt,
            Fingerprint = new string('0', 64),
            Inputs = [],
            Outputs = new() { { raw, hash } },
            Artifacts = new() { { "glb", raw } }
        };
        state.Stages["finish"] = new()
        {
            Status = "complete",
            Attempt = attempt,
            Fingerprint = new string('0', 64),
            Inputs = new() { { raw, hash } },
            Outputs = new() { { raw, hash } },
            Artifacts = new() { { "glb", raw } }
        };
        w.Save(manifest, state);
        var derivative = MakeGlb("guided.glb", new JsonObject { ["asset"] = new JsonObject { ["version"] = "2.0" }, ["skins"] = new JsonArray(new JsonObject { ["joints"] = new JsonArray(0) }), ["animations"] = new JsonArray(new JsonObject { ["name"] = "fixture-motion" }) });
        var editable = attempt + "/editable.blend";
        File.WriteAllText(w.Resolve(editable), "BLENDER-v450syntheticfixture");
        opts["source"] = editable;
        await Approve("rigging", artifact: derivative);
        state = w.Load<Manifest>(manifest);
        check(state.Stages["guided"].Artifacts["glb"] != derivative && Workspace.Hash(w.Resolve(state.Stages["guided"].Artifacts["glb"])) == Workspace.Hash(w.Resolve(derivative)), "guided derivative copied into immutable versioned attempt");
        await Approve("animation");
        check(w.Load<Manifest>(manifest).Approvals.Any(a => a.Kind == "rigging") && w.Load<Manifest>(manifest).Approvals.Any(a => a.Kind == "animation"), "one guided derivative records both rig and animation evidence");
        opts["artifact"] = raw;
        opts["kind"] = "rigging";
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("record", default), "static GLB cannot satisfy guided rigging evidence");
        opts.Remove("artifact");
        var donorOptions = new Dictionary<string, string>(opts) { ["asset"] = "donor-rejected", ["reuse-manifest"] = manifest };
        donorOptions.Remove("manifest");
        await reject(() => new Pipeline(w, donorOptions, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "reuse rejects donor lacking independent and human acceptance");
        state = w.Load<Manifest>(manifest);
        var report = attempt + "/review.json";
        w.Save(report, new
        {
            fixture = true
        });
        state.Stages["review"] = new()
        {
            Status = "complete",
            Attempt = attempt,
            Fingerprint = new string('0', 64),
            Inputs = state.Stages["guided"].Outputs,
            Outputs = new() { { report, Workspace.Hash(w.Resolve(report)) } },
            Artifacts = new() { { "report", report } }
        };
        w.Save(manifest, state);
        await Approve("independent", "independent-fixture-reviewer");
        await Approve("human");
        w.Save("reuse-rights.json", new
        {
            authorized = true,
            reuseAuthorized = true
        });
        donorOptions["asset"] = "donor-reused";
        donorOptions["rights"] = "reuse-rights.json";
        await new Pipeline(w, donorOptions, new NativeProcess(), new AlphaProcessor()).Execute("init", default);
        var reusedPath = ".opencaw/.cache/tasks/tests/proof-to-model/donor-reused/v1/manifest.json";
        var reused = w.Load<Manifest>(reusedPath);
        check(reused.Stages["reconstruct"].Status == "complete" && reused.History.Any(entry => entry["event"]?.GetValue<string>() == "reuse"), "fully approved donor copies reconstruction with durable ancestry");
        await reject(() => new Pipeline(w, new Dictionary<string, string> { { "manifest", reusedPath } }, new NativeProcess(), new AlphaProcessor()).Execute("finish", default), "reused asset requires its own current proof and preprocessing approvals");
        File.AppendAllText(w.Resolve(derivative), "mutated");
        await reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("validate", default), "guided source mutation invalidates derived lineage");
        w.Save("toolchain.json", cfgOriginal);
        // Assert actual child PID death after both timeout and cancellation.
        async Task VerifyTree(string name, bool cancel)
        {
            var pidfile = w.Resolve(name + ".pid");
            var timer = Stopwatch.StartNew();
            using var stop = new CancellationTokenSource();
            if (cancel)
                stop.CancelAfter(1200);
            await reject(() => new NativeProcess().Run(Environment.ProcessPath!, ["--spawn-child", pidfile], w.Root, w.Resolve(name + ".log"), cancel ? 10 : 2, stop.Token), name + " raises bounded termination");
            check(File.Exists(pidfile), name + " actually spawned descendant");
            var pid = int.Parse(File.ReadAllText(pidfile));
            bool alive;
            try
            {
                using var process = Process.GetProcessById(pid);
                alive = !process.HasExited;
            }
            catch (ArgumentException) { alive = false; }
            check(!alive && timer.Elapsed < TimeSpan.FromSeconds(6), name + " descendant process terminated within bound");
        }
        await VerifyTree("timeout-tree", false);
        await VerifyTree("cancel-tree", true);
        var target = w.Resolve("link-target");
        Directory.CreateDirectory(target);
        var link = w.Resolve("junction");
        if (OperatingSystem.IsWindows())
        {
            await new NativeProcess().Run(Environment.GetEnvironmentVariable("COMSPEC")!, ["/d", "/c", "mklink", "/J", link, target], w.Root, w.Resolve("junction.log"), 5);
        }
        else
            Directory.CreateSymbolicLink(link, target);
        await reject(() => Task.Run(() => w.Resolve("junction/file")), "symlink or junction segment rejected");
        await reject(() => Task.Run(() => new Workspace(link).Resolve("file")), "symlink or junction project root rejected");
        Directory.Delete(link, false);
        foreach (var component in new[] { ".opencaw", ".opencaw/.cache" })
        {
            var project = w.Resolve("cache-layout-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(project);
            var componentLink = Path.Combine(project, component.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(componentLink)!);
            if (OperatingSystem.IsWindows())
                await new NativeProcess().Run(Environment.GetEnvironmentVariable("COMSPEC")!, ["/d", "/c", "mklink", "/J", componentLink, target], w.Root, w.Resolve("cache-junction-" + Guid.NewGuid().ToString("N") + ".log"), 5);
            else
                Directory.CreateSymbolicLink(componentLink, target);
            await reject(() => Task.Run(() => new Workspace(project).Save(".opencaw/.cache/tasks/blocked/manifest.json", new { blocked = true })), "native cache component junction rejected: " + component);
            check(!Directory.EnumerateFileSystemEntries(target).Any(), "cache junction rejection preserves its target: " + component);
            Directory.Delete(componentLink, false);
        }
        var styleOriginal = File.ReadAllText(w.Resolve("STYLE.md"));
        File.AppendAllText(w.Resolve("STYLE.md"), "\n## External Asset Libraries\n\n- sample: `C:/fixture-readonly-library`\n");
        var libraryOpts = new Dictionary<string, string> { { "asset", "library-test" }, { "version", "v1" }, { "task", "tests" }, { "proof", "matte.png" }, { "rights", "rights.json" }, { "recipe", "recipe.json" }, { "toolchain", "toolchain.json" }, { "actor", "builder" } };
        await reject(() => new Pipeline(w, libraryOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "configured library requires explicit search evidence");
        w.Save("library-search.json", new
        {
            styleContractHash = Workspace.Hash(w.Resolve("STYLE.md")),
            libraries = new[] { new { id = "sample", root = "C:/fixture-readonly-library", available = true, result = "no-suitable-match", reason = "Synthetic search fixture; no production library search claimed" } }
        });
        libraryOpts["library-search"] = "library-search.json";
        await new Pipeline(w, libraryOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default);
        var libraryManifest = w.Load<Manifest>(".opencaw/.cache/tasks/tests/proof-to-model/library-test/v1/manifest.json");
        check(w.Load<JsonObject>(libraryManifest.ProofMetadata)["librarySearch"] is JsonObject, "search result bound into immutable proof metadata");
        var unavailable = w.Load<JsonObject>("library-search.json");
        unavailable["libraries"]![0]!["available"] = false;
        w.Save("unavailable-search.json", unavailable);
        libraryOpts["asset"] = "unavailable-library";
        libraryOpts["library-search"] = "unavailable-search.json";
        await reject(() => new Pipeline(w, libraryOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "unavailable configured library blocks initialization");
        File.WriteAllText(w.Resolve("STYLE.md"), styleOriginal);
        var briefOpts = new Dictionary<string, string>(libraryOpts) { ["asset"] = "brief-invalid", ["brief"] = "invalid-brief.json" };
        briefOpts.Remove("library-search");
        w.Save("invalid-brief.json", new
        {
            purpose = "fixture",
            scale = new
            {
                units = "centimetres",
                metersPerUnit = .01
            },
            interfaces = Array.Empty<string>()
        });
        await reject(() => new Pipeline(w, briefOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "unsupported brief unit scale rejected before creating asset");
        File.WriteAllText(w.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- CLOUD\n");
        var selection = new JsonObject { ["pipeline"] = "PROOF_TO_MODEL", ["selectionSource"] = "prompt", ["styleContract"] = "STYLE.md", ["styleSha256"] = Workspace.Hash(w.Resolve("STYLE.md")), ["fallbackPolicy"] = "stop", ["resolvedAt"] = DateTimeOffset.UtcNow.ToString("O") };
        w.Save("selection.json", selection);
        var overrideOpts = new Dictionary<string, string>(libraryOpts) { ["asset"] = "prompt-override", ["selection"] = "selection.json" };
        overrideOpts.Remove("library-search");
        await new Pipeline(w, overrideOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default);
        var overridden = w.Load<Manifest>(".opencaw/.cache/tasks/tests/proof-to-model/prompt-override/v1/manifest.json");
        check(w.Load<JsonObject>(overridden.ProofMetadata)["pipelineSelection"]?["styleSha256"]?.GetValue<string>() == Workspace.Hash(w.Resolve("STYLE.md")), "canonical resolver-shaped prompt selection accepted and preserved");
        selection["styleSha256"] = new string('0', 64);
        w.Save("selection.json", selection);
        overrideOpts["asset"] = "prompt-stale";
        await reject(() => new Pipeline(w, overrideOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "stale canonical selection hash rejected");
        selection["styleSha256"] = Workspace.Hash(w.Resolve("STYLE.md"));
        selection["styleContractHash"] = new string('0', 64);
        w.Save("selection.json", selection);
        overrideOpts["asset"] = "prompt-conflicting";
        await reject(() => new Pipeline(w, overrideOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "conflicting canonical and legacy selection hashes rejected");
        selection.Remove("styleContractHash");
        selection["styleContract"] = "OTHER_STYLE.md";
        w.Save("selection.json", selection);
        overrideOpts["asset"] = "prompt-wrong-contract";
        await reject(() => new Pipeline(w, overrideOpts, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "prompt override cannot identify a different style contract");
        File.WriteAllText(w.Resolve("STYLE.md"), styleOriginal);
    }
}
