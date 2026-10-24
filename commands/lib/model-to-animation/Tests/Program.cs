using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAnimation.Application;
using OpenCaw.ModelAnimation.Domain;

var evidence = Path.Combine(Directory.GetCurrentDirectory(), ".opencaw/.cache/tasks/model-to-animation-design/evidence/runtime-unit-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(evidence);
var w = new Workspace(evidence);
var fake = new FakeProcess(w);
var engine = new FakeEngine();
var passed = 0;
void Check(bool value, string name) { if (!value) throw new Exception(name); passed++; Console.WriteLine("PASS SIMULATED: " + name); }
async Task Reject(Func<Task> action, string name) { try { await action(); } catch (Exception) { Check(true, name); return; } throw new Exception("Expected rejection: " + name); }
var baseline = w.Resolve("baseline");
var scripts = Path.Combine(baseline, ".styles/.workflows/model-to-animation/blender");
Directory.CreateDirectory(scripts);
Directory.CreateDirectory(Path.Combine(baseline, "commands/lib"));
File.WriteAllText(Path.Combine(baseline, "commands/lib/engine-contract.cjs"), "// synthetic resolver fixture; not executed");
File.WriteAllText(Path.Combine(scripts, "motion.py"), "# synthetic script bytes; not executed\n");
File.WriteAllText(Path.Combine(scripts, "scripts.json"), JsonSerializer.Serialize(new { schemaVersion = 1, files = new Dictionary<string, string> { { "motion.py", Workspace.Hash(Path.Combine(scripts, "motion.py")) } } }));
File.WriteAllText(w.Resolve("STYLE.md"), "Fixture visual contract; no generation spending\n");
File.WriteAllText(w.Resolve("blender.exe"), "SYNTHETIC BINARY BYTES; NEVER EXECUTED");
w.Save("rights.json", new { authorized = true, provider = "owned", license = "Synthetic original fixture", notes = "No Adobe dependencies; the material represents ordinary substance." });
WriteGlb(w.Resolve("model.glb"));
w.Save("recipe.json", FixtureRecipe());
Dictionary<string, string> Settings(string name) => new() { { "task", "motion-tests" }, { "asset", name }, { "version", "v1" }, { "actor", "fixture-author" }, { "model", "model.glb" }, { "rights", "rights.json" }, { "recipe", "recipe.json" }, { "blender", w.Resolve("blender.exe") }, { "baseline-root", baseline } };
async Task Run(Dictionary<string, string> options, string command, CancellationToken cancellation = default) => await new Pipeline(w, options, fake, engine).Execute(command, cancellation);
async Task<Dictionary<string, string>> New(string name)
{
    var options = Settings(name);
    await Run(options, "init");
    options["manifest"] = ".opencaw/.cache/tasks/motion-tests/model-to-animation/" + name + "/v1/manifest.json";
    return options;
}
Manifest State(Dictionary<string, string> options) => w.Load<Manifest>(options["manifest"]);
async Task<string> Fingerprint(Dictionary<string, string> options, string kind)
{
    var old = Console.Out;
    var capture = new StringWriter();
    try
    {
        Console.SetOut(capture);
        await Run(options, "status");
    }
    finally { Console.SetOut(old); }
    return JsonNode.Parse(capture.ToString())!["approvalFingerprints"]![kind]!.GetValue<string>();
}
async Task Approve(Dictionary<string, string> options, string kind, string reviewer = "fixture-human", bool human = true, bool runtime = false)
{
    var state = State(options);
    var receipt = new JsonObject { ["kind"] = kind, ["reviewer"] = reviewer, ["human"] = human, ["decision"] = "approved", ["reason"] = "SYNTHETIC TEST RECEIPT; no actual human, tool, gameplay or visual acceptance", ["fingerprint"] = await Fingerprint(options, kind) };
    if (runtime)
    {
        var proofs = new JsonArray();
        foreach (var type in new[] { "runtime-test", "runtime-capture", "performance-profile" })
        {
            var file = ".opencaw/.cache/tasks/motion-tests/reviews/" + state.Asset + "-" + type + ".json";
            w.Save(file, new
            {
                simulationOnly = true,
                scope = "test-only assertion"
            });
            proofs.Add(new JsonObject { ["kind"] = type, ["path"] = file, ["sha256"] = Workspace.Hash(w.Resolve(file)) });
        }
        receipt["runtime"] = new JsonObject { ["status"] = "passed", ["engine"] = "THREEJS", ["modelSha256"] = Workspace.Hash(w.Resolve(state.Stages["export"].Artifacts["glb"])), ["packageSha256"] = Workspace.Hash(w.Resolve(state.Stages["export"].Artifacts["package"])), ["evidence"] = proofs };
    }
    var path = ".opencaw/.cache/tasks/motion-tests/reviews/" + state.Asset + "-" + kind + ".json";
    w.Save(path, receipt);
    options["kind"] = kind;
    options["reviewer"] = reviewer;
    options["evidence"] = path;
    await Run(options, "record");
}
async Task Ready(Dictionary<string, string> options) { foreach (var command in new[] { "inspect", "prepare", "rig" }) await Run(options, command); await Approve(options, "rig"); }
try
{
    var denied = Settings("denied");
    w.Save("denied-rights.json", new
    {
        authorized = false
    });
    denied["rights"] = "denied-rights.json";
    await Reject(() => Run(denied, "init"), "unauthorized original stops before asset creation");
    foreach (var provenance in new[] { new JsonObject { ["authorized"] = true, ["provider"] = "Adobe" }, new JsonObject { ["authorized"] = true, ["sourceUri"] = "https://www.mixamo.com/example" }, new JsonObject { ["authorized"] = true, ["source"] = "Mixamo" }, new JsonObject { ["authorized"] = true, ["origin"] = "Adobe" }, new JsonObject { ["authorized"] = true, ["source"] = "Firefly" }, new JsonObject { ["authorized"] = true, ["sourceUrl"] = "https://api.adobe.io/assets/1" } })
    {
        w.Save("excluded-rights.json", provenance);
        var excluded = Settings("excluded");
        excluded["rights"] = "excluded-rights.json";
        await Reject(() => Run(excluded, "init"), "declared excluded provider/origin rejected");
    }
    Check(!Directory.Exists(w.Resolve(".art-staging/model-to-animation/excluded")), "excluded provenance causes no production writes");
    MotionValidation.NoExcludedProviders(new JsonObject { ["source"] = "adobe-clay-building", ["notes"] = "No Adobe products; ordinary material substance" });
    Check(true, "ordinary source names and negative policy notes remain valid");
    var invalid = Settings("invalid");
    invalid["model"] = "model.fbx";
    await Reject(() => Run(invalid, "init"), "FBX requires explicit reviewed GLB handoff rather than implicit importer");
    var unknown = FixtureRecipe();
    unknown["callback"] = "not-executed";
    w.Save("invalid-recipe.json", unknown);
    invalid = Settings("invalid-recipe");
    invalid["recipe"] = "invalid-recipe.json";
    await Reject(() => Run(invalid, "init"), "arbitrary recipe callback rejected");
    engine.Value["effectiveEngine"] = "PHASERJS";
    await Reject(() => Run(Settings("phaser"), "init"), "Phaser cannot silently become a native skinned3D workflow");
    engine.Value["effectiveEngine"] = "THREEJS";
    var options = await New("valid");
    var initial = State(options);
    Check(initial.Profile == "rigid" && initial.Originals.Count >= 4, "rigid profile registers immutable originals without fake combat bones");
    Check(!initial.Approvals.Any(), "initialization creates no human approval");
    Check(w.Load<JsonObject>(initial.Rights)["notes"]!.GetValue<string>().Contains("No Adobe"), "negative exclusion notes and ordinary material substance are not mistaken for vendor provenance");
    await Reject(() => Run(options, "prepare"), "preparation cannot skip source inspection");
    Check(fake.Calls == 0, "stage order rejects before native process launches");
    foreach (var command in new[] { "inspect", "prepare", "rig" })
        await Run(options, command);
    var calls = fake.Calls;
    await Reject(() => Run(options, "author"), "motion production requires human rig/hierarchy selection");
    Check(fake.Calls == calls, "missing rig approval prevents tool launch");
    await Reject(() => Approve(options, "rig", human: false), "rig approval requires explicit human assertion");
    await Approve(options, "rig");
    await Run(options, "author");
    await Run(options, "bake");
    await Run(options, "export");
    var exported = State(options);
    Check(exported.Stages["motion"].Operation == "author" && exported.Approvals.Count == 1, "native author branch preserves only applicable rig approval");
    var package = w.Load<JsonObject>(exported.Stages["export"].Artifacts["package"]);
    Check(package["verification"]!["status"]!.GetValue<string>() == "pending" && package["engine"]!["effectiveEngine"]!.GetValue<string>() == "THREEJS", "export records actual selection and leaves acceptance pending");
    await Reject(() => Approve(options, "motion"), "whole motion acceptance cannot precede full review");
    await Run(options, "review");
    await Approve(options, "motion");
    await Reject(() => Approve(options, "independent", "FIXTURE-AUTHOR"), "creator cannot become independent reviewer through capitalization");
    await Approve(options, "independent", "fixture-critic");
    await Reject(() => Approve(options, "human"), "runtime acceptance cannot omit actual engine evidence");
    await Approve(options, "human", runtime: true);
    await Run(options, "validate");
    options["destination"] = "assets/models/fixture/v1";
    await Run(options, "promote");
    Check(File.Exists(w.Resolve("assets/models/fixture/v1/model.glb")), "fixture promotion copies hash-bound motion model after synthetic gates");
    var published = w.Load<JsonObject>("assets/models/fixture/v1/motion-package.json");
    Check(published["model"]!["path"]!.GetValue<string>() == "assets/models/fixture/v1/model.glb" && published["verification"]!["status"]!.GetValue<string>() == "accepted", "promotion records explicit path rebinding and acceptance receipt");
    await Reject(() => Run(options, "promote"), "promotion never overwrites existing runtime output");
    var snapshot = File.ReadAllBytes(w.Resolve(exported.Stages["export"].Artifacts["glb"]));
    File.AppendAllText(w.Resolve(exported.Stages["export"].Artifacts["glb"]), "tamper");
    await Reject(() => Run(options, "validate"), "tampered exported geometry invalidates package evidence");
    File.WriteAllBytes(w.Resolve(exported.Stages["export"].Artifacts["glb"]), snapshot);
    var humanReceipt = State(options).Approvals.Single(a => a.Kind == "human").Evidence;
    var humanBytes = File.ReadAllBytes(w.Resolve(humanReceipt));
    File.AppendAllText(w.Resolve(humanReceipt), " ");
    await Reject(() => Run(options, "validate"), "edited human evidence becomes stale");
    File.WriteAllBytes(w.Resolve(humanReceipt), humanBytes);
    var failure = await New("native-failure");
    await Ready(failure);
    fake.Mode = "exit-after-output";
    await Reject(() => Run(failure, "author"), "successful-looking native output cannot rescue failed process");
    Check(State(failure).Stages["motion"].Status == "failed", "failed process persists failed attempt");
    fake.Mode = "normal";
    var oldAttempt = State(failure).Stages["motion"].Attempt;
    await Run(failure, "author");
    Check(State(failure).Stages["motion"].Attempt != oldAttempt && Directory.Exists(w.Resolve(oldAttempt)), "recovery preserves failed attempt and uses a new immutable directory");
    var mutant = await New("input-mutation");
    await Ready(mutant);
    fake.Mode = "mutate-input";
    await Reject(() => Run(mutant, "author"), "same-invocation input mutation cannot become complete");
    Check(State(mutant).Stages["motion"].Status == "failed", "input mutation records failed stage despite passing-looking report");
    fake.Mode = "normal";
    var lens = await New("engine-change");
    engine.Value["definitionSha256"] = "changed";
    calls = fake.Calls;
    await Reject(() => Run(lens, "inspect"), "changed canonical engine receipt stops before tool launch");
    Check(fake.Calls == calls, "stale engine prevents native work");
    engine.Value.Remove("definitionSha256");
    var audit = await New("script-hash");
    File.AppendAllText(Path.Combine(scripts, "motion.py"), "changed");
    await Reject(() => Run(audit, "inspect"), "modified script rejected against audited hash manifest");
    File.WriteAllText(Path.Combine(scripts, "motion.py"), "# synthetic script bytes; not executed\n");
    var retarget = await New("retarget");
    await Ready(retarget);
    w.Save("mapping.json", new
    {
        schemaVersion = 1,
        provider = "owned",
        rights = new
        {
            authorized = true,
            license = "synthetic-original"
        },
        rootTranslationScale = 1,
        bones = new[] { new { source = "fixture", target = "fixture" } },
        clips = new[] { new { id = "idle", sourceClip = "idle" } }
    });
    retarget["motion-source"] = "model.glb";
    retarget["mapping"] = "mapping.json";
    await Run(retarget, "retarget");
    var retargeted = State(retarget).Stages["motion"];
    Check(retargeted.Operation == "retarget" && retargeted.Artifacts.ContainsKey("motionSource") && retargeted.Inputs.ContainsKey("mapping.json"), "retarget branch preserves actual source/mapping ancestry explicitly");
    w.Save("excluded-map.json", new
    {
        provider = "Mixamo",
        rights = new
        {
            authorized = true,
            license = "fixture"
        }
    });
    retarget["mapping"] = "excluded-map.json";
    await Reject(() => Run(retarget, "retarget"), "retarget refuses excluded provider support rather than silently remapping");
    using (var held = w.Lock(Path.GetDirectoryName(options["manifest"])!.Replace('\\', '/') + "/asset.lock"))
    {
        await Reject(() => Run(options, "validate"), "owned asset lock prevents concurrent state mutation");
    }
    using var cancelled = new CancellationTokenSource();
    cancelled.Cancel();
    var cancel = await New("cancelled");
    await Reject(() => Run(cancel, "inspect", cancelled.Token), "cancelled invocation cannot claim stage success");
    foreach (var mode in new[] { "escape-artifact", "missing-artifact", "wrong-input", "blocking-finding", "empty-output", "mutate-tool" })
    {
        var adverse = await New("adverse-" + mode);
        await Ready(adverse);
        fake.Mode = mode;
        await Reject(() => Run(adverse, "author"), mode + " is rejected in the producing invocation");
        Check(State(adverse).Stages["motion"].Status == "failed", mode + " preserves failed state rather than passing-looking evidence");
        fake.Mode = "normal";
        if (mode == "mutate-tool")
            File.WriteAllText(w.Resolve("blender.exe"), "SYNTHETIC BINARY BYTES; NEVER EXECUTED");
    }
    var boundedRecipe = FixtureRecipe();
    boundedRecipe["budgets"]!["maxAttempts"] = 1;
    w.Save("bounded.json", boundedRecipe);
    var bounded = Settings("bounded");
    bounded["recipe"] = "bounded.json";
    await Run(bounded, "init");
    bounded["manifest"] = ".opencaw/.cache/tasks/motion-tests/model-to-animation/bounded/v1/manifest.json";
    await Ready(bounded);
    fake.Mode = "exit-after-output";
    await Reject(() => Run(bounded, "author"), "bounded producer retains first failed attempt");
    fake.Mode = "normal";
    calls = fake.Calls;
    await Reject(() => Run(bounded, "author"), "exhausted attempt budget blocks retry before native work");
    Check(fake.Calls == calls && State(bounded).History.Count(item => item["event"]?.GetValue<string>() == "stage-start" && item["stage"]?.GetValue<string>() == "motion") == 1, "failed attempt budget cannot silently reset");
    var revisedBase = FixtureRecipe();
    var untouched = revisedBase["clips"]![0]!.DeepClone().AsObject();
    untouched["id"] = "untouched";
    revisedBase["clips"]!.AsArray().Add(untouched);
    w.Save("revision-base.json", revisedBase);
    var revising = Settings("targeted-revision");
    revising["recipe"] = "revision-base.json";
    await Run(revising, "init");
    revising["manifest"] = ".opencaw/.cache/tasks/motion-tests/model-to-animation/targeted-revision/v1/manifest.json";
    await Ready(revising);
    await Run(revising, "author");
    var prior = State(revising);
    var priorBlend = prior.Stages["motion"].Artifacts["blend"];
    var priorBlendHash = Workspace.Hash(w.Resolve(priorBlend));
    var rigFingerprint = await Fingerprint(revising, "rig");
    var replacement = revisedBase["clips"]![0]!.DeepClone().AsObject();
    replacement["channels"]![0]!["keyframes"]![1]![1]![2] = .2;
    w.Save("clip-revision.json", new JsonObject { ["schemaVersion"] = 1, ["clip"] = "idle", ["replacement"] = replacement, ["reason"] = "SYNTHETIC targeted pose correction" });
    revising["revision"] = "clip-revision.json";
    await Run(revising, "author");
    var revisionState = State(revising);
    var effective = w.Load<JsonObject>(revisionState.EffectiveRecipe);
    var revisionJob = w.Load<JsonObject>(revisionState.Stages["motion"].Attempt + "/job.json");
    Check(revisionJob["input"]!.GetValue<string>() == priorBlend && revisionJob["revisionClip"]!.GetValue<string>() == "idle", "targeted revision loads the actual previous motion rather than regenerating other retargeted actions");
    Check(JsonNode.DeepEquals(effective["clips"]![1], untouched) && !JsonNode.DeepEquals(effective["clips"]![0], revisedBase["clips"]![0]), "only selected clip definition changes in immutable effective recipe");
    Check(Workspace.Hash(w.Resolve(priorBlend)) == priorBlendHash && await Fingerprint(revising, "rig") == rigFingerprint && revisionState.Approvals.Count == 1, "targeted revision preserves previous attempt and current rig approval");
    Check(revisionState.History.Any(item => item["event"]?.GetValue<string>() == "motion-revision" && item["clipDefinitionHashes"] is JsonObject), "targeted revision records per-clip identity history");
    var successfulEffective = revisionState.EffectiveRecipe;
    fake.Mode = "exit-after-output";
    await Reject(() => Run(revising, "author"), "failed revision retains previous effective recipe pointer");
    fake.Mode = "normal";
    Check(State(revising).EffectiveRecipe == successfulEffective, "failed authoring cannot advance immutable effective recipe");
    var failedRevision = State(revising).Stages["motion"].Attempt;
    var successfulBase = State(revising).LastSuccessfulMotion!;
    Check(successfulBase.Status == "complete" && successfulBase.Artifacts["recipe"] == successfulEffective, "failed revision retains a separate successful motion source for recovery");
    calls = fake.Calls;
    await Reject(() => Run(revising, "bake"), "failed revision cannot use its recovery source to bypass motion completion");
    Check(fake.Calls == calls, "failed revision blocks downstream tools before launch");
    await Run(revising, "author");
    var retried = State(revising);
    var retryJob = w.Load<JsonObject>(retried.Stages["motion"].Attempt + "/job.json");
    Check(retried.Stages["motion"].Status == "complete" && retryJob["input"]!.GetValue<string>() == successfulBase.Artifacts["blend"], "same targeted revision retries successfully from the last complete actual motion");
    Check(retried.Stages["motion"].Attempt != failedRevision && Directory.Exists(w.Resolve(failedRevision)) && retried.History.Any(item => item["event"]?.GetValue<string>() == "stage-failed" && item["state"]?["attempt"]?.GetValue<string>() == failedRevision), "retry retains failed attempt metadata and immutable files");
    byte[]? interruptedState = null;
    fake.JobObserved = _ =>
    {
        interruptedState = File.ReadAllBytes(w.Resolve(revising["manifest"]));
        throw new InvalidOperationException("SYNTHETIC abrupt process termination after durable stage-start");
    };
    await Reject(() => Run(revising, "author"), "interrupted revision fixture captures durable running state");
    fake.JobObserved = null;
    File.WriteAllBytes(w.Resolve(revising["manifest"]), interruptedState!);
    var interrupted = State(revising);
    Check(interrupted.Stages["motion"].Status == "running" && interrupted.LastSuccessfulMotion?.Attempt == retried.Stages["motion"].Attempt, "persisted interrupted revision retains its complete recovery source");
    var interruptedAttempt = interrupted.Stages["motion"].Attempt;
    await Run(revising, "author");
    var recovered = State(revising);
    var recoveredJob = w.Load<JsonObject>(recovered.Stages["motion"].Attempt + "/job.json");
    Check(recovered.Stages["motion"].Status == "complete" && recoveredJob["input"]!.GetValue<string>() == retried.Stages["motion"].Artifacts["blend"], "interrupted targeted revision retries from the persisted successful motion");
    Check(recovered.History.Any(item => item["event"]?.GetValue<string>() == "stage-interrupted" && item["state"]?["attempt"]?.GetValue<string>() == interruptedAttempt && item["state"]?["status"]?.GetValue<string>() == "running") && Directory.Exists(w.Resolve(interruptedAttempt)), "interrupted attempt provenance remains recorded after recovery");
    fake.Mode = "exit-after-output";
    await Reject(() => Run(revising, "author"), "stale-recovery fixture records another failed revision");
    fake.Mode = "normal";
    var staleSource = State(revising).LastSuccessfulMotion!.Artifacts["blend"];
    var staleBytes = File.ReadAllBytes(w.Resolve(staleSource));
    File.AppendAllText(w.Resolve(staleSource), "SYNTHETIC changed successful motion");
    calls = fake.Calls;
    await Reject(() => Run(revising, "author"), "targeted recovery rejects a modified last-successful motion source");
    Check(fake.Calls == calls, "stale recovery rejects before native launch");
    File.WriteAllBytes(w.Resolve(staleSource), staleBytes);
    revising.Remove("revision");
    await Run(revising, "rig");
    Check(State(revising).LastSuccessfulMotion is null, "rerunning an upstream rig clears obsolete motion recovery");
    await Approve(revising, "rig");
    revising["revision"] = "clip-revision.json";
    calls = fake.Calls;
    await Reject(() => Run(revising, "author"), "targeted revision cannot reuse old motion after upstream rig replacement");
    Check(fake.Calls == calls, "missing current recovery source prevents native work");
    Console.WriteLine("PASS " + passed + " native orchestration assertions; all Blender/engine execution and approval assertions are SIMULATED");
    File.WriteAllText(Path.Combine(evidence, "verification.json"), JsonSerializer.Serialize(new
    {
        assertions = passed,
        status = "pass",
        simulatedProcesses = true,
        liveBlender = false,
        liveEngine = false
    }));
    return 0;
}
catch (Exception error) { Console.Error.WriteLine(error); return 1; }

static JsonObject FixtureRecipe() => JsonNode.Parse("""
{"schemaVersion":1,"profile":"rigid","fps":24,"requiredClips":["idle"],"rig":{"mode":"preserve","rootNode":"Body"},"parts":[{"node":"Body"}],"anchors":[{"id":"exhaust","node":"Body","position":[0,0,0]}],"clips":[{"id":"idle","role":"idle","loop":true,"rootMotion":"in-place","startFrame":0,"endFrame":12,"channels":[{"target":{"node":"Body"},"property":"location","keyframes":[[0,[0,0,0]],[6,[0,0,0.1]],[12,[0,0,0]]]}],"markers":[]}],"states":[{"id":"idle","clip":"idle"}],"transitions":[],"parameters":[],"effects":[],"budgets":{"maxTriangles":1000,"maxBones":0,"maxInfluences":0,"maxMaterials":10,"maxTextureBytes":1000000,"maxRuntimeBytes":1000000,"maxClips":5,"maxClipSeconds":10,"maxSamples":10000,"maxPreviewFrames":1000,"maxAttempts":10,"timeoutSeconds":30,"maxLogBytes":1000000},"review":{"renderer":"BLENDER_WORKBENCH","fps":12,"resolution":[64,64],"cameras":["front"]}}
""")!.AsObject();
static void WriteGlb(string file)
{
    var json = Encoding.UTF8.GetBytes("""{"asset":{"version":"2.0","generator":"Synthetic non-inference test fixture"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Body","mesh":0,"children":[1]},{"name":"anchor.exhaust"}],"meshes":[{"primitives":[{"attributes":{"POSITION":2}}]}],"buffers":[{"byteLength":68}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":8},{"buffer":0,"byteOffset":8,"byteLength":24},{"buffer":0,"byteOffset":32,"byteLength":36}],"accessors":[{"bufferView":0,"componentType":5126,"count":2,"type":"SCALAR","min":[0],"max":[0.5]},{"bufferView":1,"componentType":5126,"count":2,"type":"VEC3"},{"bufferView":2,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]}],"animations":[{"name":"idle","channels":[{"sampler":0,"target":{"node":0,"path":"translation"}}],"samplers":[{"input":0,"output":1,"interpolation":"LINEAR"}]}]}""");
    var pad = (4 - json.Length % 4) % 4;
    using var output = File.Create(file);
    using var writer = new BinaryWriter(output);
    writer.Write(0x46546c67u);
    writer.Write(2u);
    writer.Write((uint)(20 + json.Length + pad + 8 + 68));
    writer.Write((uint)(json.Length + pad));
    writer.Write(0x4e4f534au);
    writer.Write(json);
    writer.Write(Enumerable.Repeat((byte)32, pad).ToArray());
    writer.Write(68u);
    writer.Write(0x004e4942u);
    foreach (var value in new float[] { 0, .5f, 0, 0, 0, 0, 0, .1f, 0, 0, 0, 1, 0, 0, 0, 1, 0 })
        writer.Write(value);
}
sealed class FakeEngine : IEngineResolver
{
    public JsonObject Value { get; } = new() { ["schemaVersion"] = 1, ["projectEngine"] = "THREEJS", ["effectiveEngine"] = "THREEJS", ["selectionSource"] = "synthetic-fixture" };
    public Task<JsonObject> Resolve(CancellationToken cancellation) => Task.FromResult(Value.DeepClone().AsObject());
}
sealed class FakeProcess(Workspace workspace) : INativeProcess
{
    public int Calls
    {
        get; private set;
    }
    public string Mode { get; set; } = "normal";
    public Action<JsonObject>? JobObserved
    {
        get; set;
    }
    public Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
    {
        cancellation.ThrowIfCancellationRequested();
        Calls++;
        File.WriteAllText(log, "stdout: SYNTHETIC Blender 4.5.10 protocol fixture; no executable launched\n");
        var args = arguments.ToArray();
        if (args.Contains("--version"))
            return Task.CompletedTask;
        var failureFlag = Array.IndexOf(args, "--python-exit-code");
        if (failureFlag < 0 || args[failureFlag + 1] != "1")
            throw new InvalidOperationException("Native authoring must propagate Python exception exit status");
        var job = JsonNode.Parse(File.ReadAllText(args[Array.IndexOf(args, "--job") + 1]))!.AsObject();
        JobObserved?.Invoke(job);
        var output = job["outputDir"]!.GetValue<string>();
        var operation = job["operation"]!.GetValue<string>();
        var input = job["input"]!.GetValue<string>();
        var artifacts = new JsonObject();
        var report = output + "/report.json";
        workspace.Save(report, new
        {
            simulationOnly = true
        });
        artifacts["report"] = report;
        if (operation is not ("inspect" or "review"))
        {
            var blend = output + "/source.blend";
            File.WriteAllText(workspace.Resolve(blend), "BLENDER SYNTHETIC TEST BYTES");
            artifacts["blend"] = blend;
        }
        if (operation == "export")
        {
            var glb = output + "/model.glb";
            File.Copy(workspace.Resolve("model.glb"), workspace.Resolve(glb), false);
            artifacts["glb"] = glb;
            var package = new JsonObject { ["schemaVersion"] = "opencaw-motion-package/v1", ["profile"] = job["profile"]!.DeepClone(), ["model"] = new JsonObject { ["path"] = glb, ["sha256"] = Workspace.Hash(workspace.Resolve(glb)) }, ["source"] = new JsonObject { ["path"] = artifacts["blend"]!.GetValue<string>(), ["sha256"] = Workspace.Hash(workspace.Resolve(artifacts["blend"]!.GetValue<string>())) }, ["clips"] = new JsonArray(new JsonObject { ["id"] = "idle", ["action"] = "idle", ["duration"] = .5, ["role"] = "idle", ["loop"] = true, ["rootMotion"] = "in-place" }) };
            package["coordinateSystem"] = new JsonObject { ["sourceUp"] = "Z", ["runtimeUp"] = "Y" };
            package["rig"] = new JsonObject { ["mode"] = "preserve" };
            package["provenance"] = new JsonObject { ["provider"] = "owned", ["license"] = "synthetic" };
            package["budgets"] = job["recipe"]!["budgets"]!.DeepClone();
            foreach (var key in new[] { "anchors", "parameters", "states", "transitions", "effects" })
                package[key] = job["recipe"]![key]!.DeepClone();
            foreach (var item in package["anchors"]!.AsArray())
            {
                var anchor = item!.AsObject();
                anchor["parent"] = anchor["node"]!.DeepClone();
                anchor["node"] = "anchor." + anchor["id"]!.GetValue<string>();
            }
            var packagePath = output + "/motion-package.json";
            workspace.Save(packagePath, package);
            artifacts["package"] = packagePath;
        }
        if (operation == "review")
        {
            var html = output + "/review.html";
            File.WriteAllText(workspace.Resolve(html), "<!doctype html><p>SYNTHETIC review fixture</p>");
            artifacts["review"] = html;
        }
        if (Mode == "escape-artifact")
            artifacts["blend"] = "../escape.blend";
        if (Mode == "missing-artifact")
            artifacts.Remove("blend");
        if (Mode == "empty-output")
            File.WriteAllText(workspace.Resolve(output + "/source.blend"), "");
        var inputHash = Mode == "wrong-input" ? new string('0', 64) : Workspace.Hash(workspace.Resolve(input));
        workspace.Save(job["result"]!.GetValue<string>(), new JsonObject { ["schemaVersion"] = "opencaw-motion-stage/v1", ["operation"] = operation, ["profile"] = job["profile"]!.DeepClone(), ["inputSha256"] = inputHash, ["artifacts"] = artifacts, ["metrics"] = new JsonObject(), ["findings"] = Mode == "blocking-finding" ? new JsonArray(new JsonObject { ["severity"] = "fatal" }) : new JsonArray(), ["clips"] = new JsonArray() });
        if (Mode == "mutate-tool")
            File.AppendAllText(executable, "mutation");
        if (Mode == "mutate-input")
            File.AppendAllText(workspace.Resolve(input), "mutated");
        if (Mode == "exit-after-output")
            throw new InvalidOperationException("SYNTHETIC nonzero native exit after passing-looking output");
        return Task.CompletedTask;
    }
}
