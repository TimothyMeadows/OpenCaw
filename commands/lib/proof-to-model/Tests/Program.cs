using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;
if (args.Length > 0 && args[0] == "--compatibility") { CompatibilityTests.Run(); return 0; }
if (args.Length > 0 && args[0] == "--echo") { Console.Write(args[1]); return 0; }
if (args.Length > 0 && args[0] == "--sleep") { await Task.Delay(TimeSpan.FromSeconds(30)); return 0; }
if (args.Length > 0 && args[0] == "--spawn-child")
{
    var start = new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false };
    start.ArgumentList.Add("--sleep");
    using var child = System.Diagnostics.Process.Start(start)!;
    File.WriteAllText(args[1], child.Id.ToString());
    await Task.Delay(TimeSpan.FromSeconds(30));
    return 0;
}
if (args.Length > 0 && args[0] == "--blender-environment-probe")
    return FinishingSettingsTests.ObserveChildEnvironment(args);
if (args.Length > 0 && args[0] is "--rigid-memory-allocate" or "--rigid-memory-parent")
    return RigidFinishingTests.ObserveAllocation(args);
var root = Path.Combine(Path.GetTempPath(), "opencaw-proof-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
var w = new Workspace(root);
var passed = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception(name); passed++; Console.WriteLine("PASS " + name); }
async Task Reject(Func<Task> action, string name) { try { await action(); } catch (Exception) { Check(true, name); return; } throw new Exception("Expected rejection: " + name); }
try
{
    await Reject(() => Task.Run(() => w.Resolve("../escape")), "path traversal rejected");
    await Reject(() => Task.Run(() => w.Resolve(".git/config")), "reserved metadata rejected");
    using (var held = w.Lock("lock"))
    {
        await Reject(() => Task.Run(() => w.Lock("lock")), "asset lock contention rejected");
    }
    w.Save("roundtrip.json", new
    {
        schemaVersion = 1,
        value = "persistent"
    });
    Check(w.Load<JsonObject>("roundtrip.json")["value"]!.GetValue<string>() == "persistent", "atomic state roundtrip");
    File.WriteAllText(w.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL\n");
    File.WriteAllText(w.Resolve("proof.png"), "fixture deliberately not production PNG");
    w.Save("rights.json", new
    {
        authorized = true
    });
    w.Save("toolchain.json", new
    {
        schemaVersion = 1,
        files = Array.Empty<object>(),
        models = Array.Empty<object>()
    });
    w.Save("recipe.json", new
    {
        targetFaces = 100,
        textureSize = 64,
        cageExtrusion = .1,
        maxRayDistance = .1,
        uvMargin = .01,
        lodRatios = new[] { .5, .25 },
        colliderMaxFaces = 100,
        maxTriangles = 1000,
        maxMaterials = 5,
        maxTextureBytes = 100000,
        parts = Array.Empty<string>(),
        riggingRequired = false,
        animationRequired = false
    });
    var opts = new Dictionary<string, string> { { "mode", "single-view-diagnostic" }, { "asset", "fixture" }, { "version", "v1" }, { "task", "tests" }, { "proof", "proof.png" }, { "rights", "rights.json" }, { "recipe", "recipe.json" }, { "toolchain", "toolchain.json" }, { "actor", "builder" } };
    await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("init", default);
    var manifest = ".opencaw/.cache/tasks/tests/proof-to-model/fixture/v1/manifest.json";
    opts["manifest"] = manifest;
    Check(File.Exists(w.Resolve(manifest)), "init persists manifest");
    Check(w.Load<Manifest>(manifest).Proof.StartsWith(".art-staging/"), "proof preserved in versioned immutable staging");
    await Reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("init", default), "version cannot overwrite original");
    await Reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("reconstruct", default), "reconstruction cannot skip proof approval");
    await Reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("promote", default), "promotion cannot skip production stages");
    var proofFingerprint = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(string.Join("\n", new[] { w.Load<Manifest>(manifest).Proof, w.Load<Manifest>(manifest).ProofMetadata, "rights.json", "recipe.json", "toolchain.json", "STYLE.md" }.Order().Select(x => x + ":" + Workspace.Hash(w.Resolve(x)))))));
    var approvalPath = ".opencaw/.cache/tasks/tests/reviews/proof.json";
    w.Save(approvalPath, new
    {
        kind = "proof",
        reviewer = "human",
        decision = "approved",
        fingerprint = proofFingerprint,
        reason = "Explicit synthetic approval fixture, not a production human approval",
        human = true
    });
    opts["kind"] = "proof";
    opts["reviewer"] = "human";
    var retiredApproval = ".ai/tasks/tests/reviews/proof.json";
    w.Save(retiredApproval, w.Load<JsonObject>(approvalPath));
    opts["evidence"] = retiredApproval;
    await Reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("record", default), "retired approval path cannot authorize native production");
    Check(w.Load<Manifest>(manifest).Approvals.Count == 0, "retired receipt rejection preserves manifest approvals");
    var retiredManifest = ".ai/tasks/tests/manifest.json";
    w.Save(retiredManifest, w.Load<Manifest>(manifest));
    var oldOptions = new Dictionary<string, string>(opts) { ["manifest"] = retiredManifest };
    await Reject(() => new Pipeline(w, oldOptions, new NativeProcess(), new AlphaProcessor()).Execute("status", default), "retired manifest layout rejected before asset lock");
    Check(!File.Exists(w.Resolve(".ai/tasks/tests/asset.lock")), "retired state remains without native writes");
    opts["evidence"] = approvalPath;
    await new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("record", default);
    Check(w.Load<Manifest>(manifest).Approvals.Count == 1, "approval evidence hash persisted");
    await Reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("preprocess", default), "missing native dependency fails closed");
    Check(w.Load<Manifest>(manifest).Stages["preprocess"].Status == "failed", "failed attempts persist for recovery");
    await ExtendedTests.Run(w, Check, Reject);
    await PolicyTests.Run(w, Check, Reject);
    await PreparationTests.Run(w, Check, Reject);
    await MultiViewReuseTests.Run(w, Check, Reject);
    await MultiViewGeometryTests.Run(w, Check, Reject);
    await MultiViewPipelineTests.Run(w, Check, Reject);
    await FinishingSettingsTests.Run(w, Check, Reject);
    await FinishAttemptBudgetTests.Run(w, Check, Reject);
    await RigidFinishingTests.Run(w, Check, Reject);
    passed += CompatibilityTests.Run();
    File.AppendAllText(w.Resolve("STYLE.md"), "changed");
    await Reject(() => new Pipeline(w, opts, new NativeProcess(), new AlphaProcessor()).Execute("validate", default), "changed style invalidates evidence");
    var registry = new StageRegistry([("a", _ => Task.CompletedTask)]);
    await registry.Execute("A", default);
    Check(true, "adapted Bubo registry uses case-insensitive names");
    await Reject(() => registry.Execute("missing", default), "unregistered stage rejected");
    if (OperatingSystem.IsWindows())
    {
        var exe = Environment.GetEnvironmentVariable("COMSPEC") ?? "C:/Windows/System32/cmd.exe";
        await new NativeProcess().Run(exe, ["/d", "/c", "echo native-fixture"], root, w.Resolve("native.log"), 5);
        Check(File.ReadAllText(w.Resolve("native.log")).Contains("native-fixture"), "native output streamed and retained");
        await Reject(() => new NativeProcess().Run(exe, ["/d", "/c", "exit 7"], root, w.Resolve("exit.log"), 5), "native nonzero exits rejected");
        await Reject(() => new NativeProcess().Run(exe, ["/d", "/c", "ping -n 30 127.0.0.1 > nul"], root, w.Resolve("timeout.log"), 1), "native deadline kills process tree");
    }
    else
    {
        await new NativeProcess().Run("/bin/sh", ["-c", "printf native-fixture"], root, w.Resolve("native.log"), 5);
        Check(File.ReadAllText(w.Resolve("native.log")).Contains("native-fixture"), "native output retained");
        await Reject(() => new NativeProcess().Run("/bin/sh", ["-c", "sleep 30"], root, w.Resolve("timeout.log"), 1), "native deadline kills process tree");
    }
    Console.WriteLine($"PASS {passed} assertions; fixture tests do not claim live reconstruction");
    return 0;
}
finally { Directory.Delete(root, true); }
