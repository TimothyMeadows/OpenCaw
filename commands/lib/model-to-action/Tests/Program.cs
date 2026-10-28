using System.Buffers.Binary;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using OpenCaw.AssetProduction;
using OpenCaw.ModelAction.Application;
using OpenCaw.ModelAction.Domain;

var root = Path.Combine(Directory.GetCurrentDirectory(), ".opencaw/.cache/tasks/model-to-action/evidence/native-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
var w = new Workspace(root);
var engine = new FakeEngine();
var fake = new FakeProcess(w);
var passed = 0;
void Check(bool value, string name) { if (!value) throw new Exception(name); passed++; Console.WriteLine("PASS SIMULATED: " + name); }
async Task Reject(Func<Task> action, string name) { try { await action(); } catch (Exception) { Check(true, name); return; } throw new Exception("Expected rejection: " + name); }
var baseline = w.Resolve("baseline");
var scripts = Path.Combine(baseline, ".styles/.workflows/model-to-action/blender");
Directory.CreateDirectory(scripts);
Directory.CreateDirectory(Path.Combine(baseline, "commands/lib"));
File.WriteAllText(Path.Combine(baseline, "commands/lib/engine-contract.cjs"), "// INERT TEST RESOLVER; NEVER EXECUTED\n");
File.WriteAllText(Path.Combine(scripts, "action.py"), "# INERT SCRIPT BYTES; NEVER EXECUTED\n");
File.WriteAllText(Path.Combine(scripts, "scripts.json"), JsonSerializer.Serialize(new { schemaVersion = 1, files = new Dictionary<string, string> { ["action.py"] = Workspace.Hash(Path.Combine(scripts, "action.py")) } }));
File.WriteAllText(w.Resolve("blender.exe"), "SYNTHETIC TOOL BYTES; NEVER EXECUTED");
Fixture.WriteGlb(w.Resolve("model.glb"), ["kick", "punch"]);
w.Save("motion.json", Fixture.Motion(Workspace.Hash(w.Resolve("model.glb"))));
w.Save("recipe.json", Fixture.Recipe());
File.WriteAllText(w.Resolve("STYLE.md"), "Original controlled simulated fixture\n");
var sourceReview = ".opencaw/.cache/tasks/fixture/source-review.json";
w.Save(sourceReview, new JsonObject { ["schemaVersion"] = 1, ["kind"] = "source-motion", ["decision"] = "approved", ["human"] = true, ["reviewer"] = "fixture-human", ["reason"] = "SYNTHETIC HUMAN ASSERTION, not actual production review", ["rights"] = new JsonObject { ["authorized"] = true, ["license"] = "Original synthetic protocol fixture model and motions" }, ["motionPackageSha256"] = Workspace.Hash(w.Resolve("motion.json")), ["modelSha256"] = Workspace.Hash(w.Resolve("model.glb")), ["rigId"] = new string('a', 64), ["clips"] = new JsonArray(new JsonObject { ["id"] = "kick", ["motionSha256"] = new string('b', 64) }, new JsonObject { ["id"] = "punch", ["motionSha256"] = new string('c', 64) }) });
Dictionary<string, string> Settings(string asset) => new() { ["task"] = "fixture", ["asset"] = asset, ["version"] = "v1", ["actor"] = "builder", ["motion-package"] = "motion.json", ["recipe"] = "recipe.json", ["source-review"] = sourceReview, ["blender"] = w.Resolve("blender.exe"), ["baseline-root"] = baseline };
async Task Run(Dictionary<string, string> settings, string command, CancellationToken token = default) => await new Pipeline(w, settings, fake, engine).Execute(command, token);
async Task<Dictionary<string, string>> New(string name) { var testArgs = Settings(name); await Run(testArgs, "init"); testArgs["manifest"] = ".opencaw/.cache/tasks/fixture/model-to-action/" + name + "/v1/manifest.json"; return testArgs; }
Manifest State(Dictionary<string, string> settings) => w.Load<Manifest>(settings["manifest"]);
async Task<string> Fingerprint(Dictionary<string, string> settings)
{
    var old = Console.Out;
    var output = new StringWriter();
    try
    {
        Console.SetOut(output);
        await Run(settings, "status");
    }
    finally { Console.SetOut(old); }
    return JsonNode.Parse(output.ToString())!["approvalFingerprints"]!["action"]!.GetValue<string>();
}
async Task Ready(Dictionary<string, string> settings) { foreach (var stage in new[] { "inspect", "compose", "export", "review" }) await Run(settings, stage); }
async Task Approve(Dictionary<string, string> settings, string kind, string reviewer = "fixture-human", bool runtime = true)
{
    var manifest = State(settings);
    var receipt = new JsonObject { ["kind"] = kind, ["reviewer"] = reviewer, ["decision"] = "approved", ["human"] = true, ["reason"] = "SYNTHETIC controlled test receipt; no human/gameplay/art acceptance", ["fingerprint"] = await Fingerprint(settings) };
    if (kind == "human" && runtime)
    {
        var records = new JsonArray();
        foreach (var type in new[] { "runtime-test", "runtime-capture", "performance-profile" })
        {
            var file = ".opencaw/.cache/tasks/fixture/reviews/" + manifest.Asset + "-" + type + ".json";
            w.Save(file, new
            {
                simulationOnly = true
            });
            records.Add(new JsonObject { ["kind"] = type, ["path"] = file, ["sha256"] = Workspace.Hash(w.Resolve(file)) });
        }
        receipt["runtime"] = new JsonObject { ["status"] = "passed", ["engine"] = "THREEJS", ["modelSha256"] = Workspace.Hash(w.Resolve(manifest.Stages["export"].Artifacts["glb"])), ["packageSha256"] = Workspace.Hash(w.Resolve(manifest.Stages["export"].Artifacts["package"])), ["evidence"] = records };
    }
    var path = ".opencaw/.cache/tasks/fixture/reviews/" + manifest.Asset + "-" + kind + ".json";
    w.Save(path, receipt);
    settings["kind"] = kind;
    settings["reviewer"] = reviewer;
    settings["evidence"] = path;
    await Run(settings, "record");
}
try
{
    var motion = w.Load<JsonObject>("motion.json");
    var recipe = w.Load<JsonObject>("recipe.json");
    var plan = ActionCompiler.Compile(recipe, motion, "test", "v1");
    Check(plan["budgets"]!["maxVerificationBytes"]!.GetValue<long>() == ActionVerificationBudget.DefaultBytes && !recipe["budgets"]!.AsObject().ContainsKey("maxVerificationBytes"), "legacy recipes receive the8GiB verification default without mutating source evidence");
    var limitedVerification = recipe.DeepClone().AsObject();
    limitedVerification["budgets"]!["maxVerificationBytes"] = 65536;
    Check(ActionCompiler.Compile(limitedVerification, motion, "test", "v1")["budgets"]!["maxVerificationBytes"]!.GetValue<long>() == 65536, "explicit verification spool budget survives compilation");
    foreach (var invalid in new JsonNode?[] { JsonValue.Create(0), JsonValue.Create(1023), JsonValue.Create(1024.5), JsonValue.Create(ActionVerificationBudget.MaximumBytes + 1), JsonValue.Create("8589934592"), null })
    {
        var malformed = recipe.DeepClone().AsObject(); malformed["budgets"]!["maxVerificationBytes"] = invalid?.DeepClone();
        await Reject(() => Task.Run(() => ActionCompiler.Compile(malformed, motion, "test", "v1")), "invalid or excessive verification budget fails compilation");
    }
    var action = plan["actions"]![0]!.AsObject();
    Check(action["steps"]!.AsArray().Count == 3 && action["duration"]!.GetValue<double>() == 2.25, "compiler expands bounded repeats and incoming overlap with exact total duration");
    Check(action["steps"]![2]!["start"]!.GetValue<double>() == 1.75 && action["steps"]![2]!["sourceStart"]!.GetValue<double>() == .25, "compiler keeps trim ancestry separate from action clock");
    Check(action["cues"]![0]!["start"]!.GetValue<double>() == .5 && action["cues"]![0]!["end"]!.GetValue<double>() == 2.25, "source marker and explicit occurrence offset resolve to exact action times");
    Check(plan["rig"]!["rootNode"]!.GetValue<string>() == "Root" && plan["sourceMotion"]!["clips"]!.AsArray().Count == 2, "plan preserves root identity and each actual source clip hash");
    foreach (var (name, edit) in new (string, Action<JsonObject>)[] {
        ("missing source clip", r => r["actions"]![0]!["steps"]![0]!["clip"]="missing"),
        ("reversed trim", r => r["actions"]![0]!["steps"]![0]!["from"]=1.1),
        ("zero playback rate", r => r["actions"]![0]!["steps"]![0]!["rate"]=0),
        ("excessive repeats", r => r["actions"]![0]!["steps"]![0]!["repeat"]=17),
        ("first-step overlap", r => r["actions"]![0]!["steps"]![0]!["blendIn"]=.25),
        ("non-frame-aligned duration", r => r["actions"]![0]!["steps"]![0]!["rate"]=3),
        ("missing marker", r => r["actions"]![0]!["cues"]![0]!["start"]!["marker"]="none"),
        ("ambiguous address", r => r["actions"]![0]!["cues"]![0]!["start"]!["offset"]=0),
        ("missing occurrence", r => r["actions"]![0]!["cues"]![0]!["start"]!["occurrence"]=3),
        ("unknown effect anchor", r => r["actions"]![0]!["cues"]![0]!["anchor"]="missing"),
        ("missing fixed target preview", r => r["review"]!["targets"]!.AsObject().Clear()),
        ("gameplay-authority expression", r => r["actions"]![0]!["cues"]![0]!["damage"]=20),
        ("action time budget", r => r["budgets"]!["maxActionSeconds"]=1),
        ("expanded step budget", r => r["budgets"]!["maxExpandedSteps"]=1),
        ("bake frame budget", r => r["budgets"]!["maxFrames"]=2),
        ("review frame budget", r => r["budgets"]!["maxReviewFrames"]=1) })
    {
        var bad = recipe.DeepClone().AsObject();
        edit(bad);
        await Reject(() => Task.Run(() => ActionCompiler.Compile(bad, motion, "test", "v1")), name + " fails compilation");
    }
    var extracted = motion.DeepClone().AsObject();
    extracted["clips"]![0]!["rootMotion"] = "extract";
    await Reject(() => Task.Run(() => ActionCompiler.Compile(recipe, extracted, "test", "v1")), "extracted source explicitly rejected instead of discarding controller motion");
    var duplicate = motion.DeepClone().AsObject();
    duplicate["clips"]![0]!["markers"]!.AsArray().Add(new JsonObject { ["event"] = "release", ["time"] = .75 });
    await Reject(() => Task.Run(() => ActionCompiler.Compile(recipe, duplicate, "test", "v1")), "source marker must resolve exactly once in trim");
    var triple = recipe.DeepClone().AsObject();
    var steps = triple["actions"]![0]!["steps"]!.AsArray();
    steps[0]!["repeat"] = 1;
    steps[1]!["from"] = 0;
    steps[1]!["to"] = 1;
    steps[1]!["blendIn"] = .75;
    var third = steps[1]!.DeepClone();
    third["id"] = "third";
    steps.Add(third);
    await Reject(() => Task.Run(() => ActionCompiler.Compile(triple, motion, "test", "v1")), "three simultaneous clip owners fail compilation");
    ActionValidation.NoExcludedOrigins(new JsonObject { ["source"] = "adobe-clay-building", ["notes"] = "No Adobe provider; material substance" });
    Check(true, "ordinary material names and negative notes remain valid");
    foreach (var value in new[] { new JsonObject { ["source"] = "Mixamo" }, new JsonObject { ["provider"] = "Adobe" }, new JsonObject { ["sourceUrl"] = "https://api.adobe.io/asset" } })
        await Reject(() => Task.Run(() => ActionValidation.NoExcludedOrigins(value)), "declared excluded authoring origin rejected");

    JsonObject Particle(JsonObject value, int capacity = 32, double rate = 8)
    {
        var cue = value["actions"]![0]!["cues"]![0]!.AsObject();
        cue["type"] = "particles";
        cue.Remove("target");
        cue["capacity"] = capacity;
        cue["rate"] = rate;
        cue["seed"] = 17;
        return value;
    }
    foreach (var (name, edit) in new (string, Action<JsonObject>)[] {
        ("unsupported-particle-rate", r => Particle(r, rate:1000.01)),
        ("unsupported-particle-budget", r => r["budgets"]!["maxParticles"]=65537),
        ("unsupported-particle-capacity", r => Particle(r, capacity:65537)),
        ("unsupported-side-camera", r => r["review"]!["cameras"]=new JsonArray("side")),
        ("unsupported-fractional-review-fps", r => r["review"]!["fps"]=1.5),
        ("unsupported-zero-review-fps", r => r["review"]!["fps"]=0),
        ("unsupported-review-size", r => r["review"]!["resolution"]=new JsonArray(128,2049)),
        ("unsupported-action-budget", r => r["budgets"]!["maxActionSeconds"]=.5),
        ("review-boundary-budget", r => {r["budgets"]!["maxReviewFrames"]=20; var address=r["actions"]![0]!["cues"]![0]!["start"]!.AsObject();address.Remove("marker");address["offset"]=.125;}),
        ("review-pixel-budget", r => {r["review"]!["fps"]=60;r["review"]!["resolution"]=new JsonArray(2048,2048);})
    })
    {
        var unsupported = recipe.DeepClone().AsObject();
        edit(unsupported);
        await Reject(() => Task.Run(() => ActionCompiler.Compile(unsupported, motion, "test", "v1")), name + " fails exact shared contract compilation");
        var unsupportedPath = name + ".json";
        w.Save(unsupportedPath, unsupported);
        var unsupportedArgs = Settings(name);
        unsupportedArgs["recipe"] = unsupportedPath;
        var calls = fake.Calls;
        await Reject(() => Run(unsupportedArgs, "init"), name + " fails init before production");
        Check(!Directory.Exists(w.Resolve(".art-staging/model-to-action/" + name)) && fake.Calls == calls, name + " creates no staging and launches no producer");
    }
    var fiveViews = recipe.DeepClone().AsObject();
    fiveViews["review"]!["cameras"] = new JsonArray("front", "three-quarter", "right", "left", "back");
    Check(ActionCompiler.Compile(fiveViews, motion, "test", "v1")["actions"]!.AsArray().Count == 1, "all five implemented review camera directions compile");
    var multipleParticles = Particle(recipe.DeepClone().AsObject(), capacity: 2048, rate: 1000);
    var secondAction = multipleParticles["actions"]![0]!.DeepClone();
    secondAction["id"] = "alternate";
    multipleParticles["actions"]!.AsArray().Add(secondAction);
    Check(ActionCompiler.Compile(multipleParticles, motion, "test", "v1")["actions"]!.AsArray().Count == 2, "mutually exclusive actions each own a full particle budget rather than summing across unused actions");

    var savedReview = File.ReadAllText(w.Resolve(sourceReview));
    var badReview = w.Load<JsonObject>(sourceReview);
    badReview["human"] = false;
    w.Save(sourceReview, badReview);
    await Reject(() => Run(Settings("unreviewed"), "init"), "source approval cannot be automatically manufactured");
    Check(!Directory.Exists(w.Resolve(".art-staging/model-to-action/unreviewed")), "unreviewed input creates no production staging");
    File.WriteAllText(w.Resolve(sourceReview), savedReview);
    foreach (var mode in new[] { "absent", "unauthorized", "missing-license", "excluded-origin" })
    {
        var permission = w.Load<JsonObject>(sourceReview);
        if (mode == "absent")
            permission.Remove("rights");
        if (mode == "unauthorized")
            permission["rights"]!["authorized"] = false;
        if (mode == "missing-license")
            permission["rights"]!.AsObject().Remove("license");
        if (mode == "excluded-origin")
            permission["rights"]!["source"] = "Adobe";
        w.Save(sourceReview, permission);
        await Reject(() => Run(Settings("rights-" + mode), "init"), mode + " source rights fails before asset creation");
        Check(!Directory.Exists(w.Resolve(".art-staging/model-to-action/rights-" + mode)), "rights denial creates no production staging");
        File.WriteAllText(w.Resolve(sourceReview), savedReview);
    }
    engine.Selection = "UNITY";
    await Reject(() => Run(Settings("wrong-engine"), "init"), "wrong source engine fails before production write or Blender");
    engine.Selection = "THREEJS";
    engine.Selection = "PHASERJS";
    await Reject(() => Run(Settings("phaser"), "init"), "Phaser requires explicit 2D handoff");
    engine.Selection = "THREEJS";
    foreach (var mode in new[] { "missing-verification", "missing-verification-file", "oversized-verification", "alias-verification", "substitute-verification-index", "swap-verification-payloads" })
    {
        Dictionary<string, string> evidenceArgs;
        if (mode == "oversized-verification")
        {
            var tiny = Fixture.Recipe(); tiny["budgets"]!["maxVerificationBytes"] = 1024;
            w.Save("tiny-verification.json", tiny);
            evidenceArgs = Settings("evidence-" + mode); evidenceArgs["recipe"] = "tiny-verification.json";
            await Run(evidenceArgs, "init");
            evidenceArgs["manifest"] = ".opencaw/.cache/tasks/fixture/model-to-action/evidence-" + mode + "/v1/manifest.json";
        }
        else evidenceArgs = await New("evidence-" + mode);
        await Run(evidenceArgs, "inspect"); await Run(evidenceArgs, "compose");
        fake.Mode = mode;
        await Reject(() => Run(evidenceArgs, "export"), mode + " cannot create passing exported action evidence");
        fake.Mode = "normal";
        Check(State(evidenceArgs).Stages["export"].Status == "failed", mode + " leaves durable failed export state");
    }
    var testArgs = await New("complete");
    await Reject(() => Run(testArgs, "compose"), "inspect required before actual composition");
    await Ready(testArgs);
    await Run(testArgs, "validate");
    var acceptedMap = State(testArgs);
    var aliasMap = State(testArgs); aliasMap.Stages["export"].Artifacts["verificationIndex"] = aliasMap.Stages["export"].Artifacts["package"];
    w.Save(testArgs["manifest"], aliasMap);
    await Reject(() => Run(testArgs, "validate"), "persisted verification role alias cannot validate as current evidence");
    w.Save(testArgs["manifest"], acceptedMap);
    Check(State(testArgs).Approvals.Count == 0, "all native stages leave human action/runtime approval pending");
    testArgs["destination"] = "assets/models/action-fixture";
    await Reject(() => Run(testArgs, "promote"), "native export cannot promote without acceptance");
    await Approve(testArgs, "action");
    await Reject(() => Approve(testArgs, "independent", "BUILDER"), "independent reviewer cannot be creator through case variation");
    await Approve(testArgs, "independent", "fixture-independent");
    await Reject(() => Approve(testArgs, "human", runtime: false), "human runtime acceptance cannot omit engine artifacts");
    await Approve(testArgs, "human");
    await Run(testArgs, "promote");
    var promoted = w.Load<JsonObject>("assets/models/action-fixture/action-package.json");
    Check(promoted["model"]!["path"]!.GetValue<string>() == "assets/models/action-fixture/model.glb" && promoted["motion"]!["path"]!.GetValue<string>() == "assets/models/action-fixture/motion-source.json", "promotion copies exact assets and explicitly rebinds package paths");
    Check(JsonNode.DeepEquals(promoted["sourceMotion"]!["rights"], w.Load<JsonObject>(sourceReview)["rights"]) && promoted["sourceMotion"]!["sourceReviewSha256"]!.GetValue<string>() == Workspace.Hash(w.Resolve(sourceReview)), "standalone package preserves exact reviewed model and clip rights with receipt hash");
    await Reject(() => Run(testArgs, "promote"), "accepted action destination cannot be overwritten");
    var accepted = State(testArgs).Approvals.Last(a => a.Kind == "human").Evidence;
    var acceptedBytes = File.ReadAllText(w.Resolve(accepted));
    File.AppendAllText(w.Resolve(accepted), " ");
    await Reject(() => Run(testArgs, "validate"), "edited acceptance evidence becomes stale");
    File.WriteAllText(w.Resolve(accepted), acceptedBytes);
    var modelBytes = File.ReadAllBytes(w.Resolve("model.glb"));
    File.AppendAllText(w.Resolve("model.glb"), "tamper");
    await Reject(() => Run(testArgs, "inspect"), "changed original source fails before new production");
    File.WriteAllBytes(w.Resolve("model.glb"), modelBytes);
    engine.Selection = "UNITY";
    await Reject(() => Run(testArgs, "compose"), "changed project engine invalidates action state");
    engine.Selection = "THREEJS";
    using (w.Lock(Path.GetDirectoryName(testArgs["manifest"])!.Replace('\\', '/') + "/asset.lock"))
        await Reject(() => Run(testArgs, "compose"), "asset ownership lock prevents concurrent mutation");
    await Run(testArgs, "compose");
    Check(State(testArgs).Approvals.Count == 0 && !State(testArgs).Stages.ContainsKey("export"), "new composition invalidates dependent exports and all final approvals");

    foreach (var mode in new[] { "exit-after-output", "missing-result", "corrupt-blend", "escaped-artifact", "wrong-action", "changed-cues", "mutate-source", "critical-finding", "unknown-finding", "extra-executable", "extra-binary", "wrong-schema", "empty-metrics" })
    {
        var adverse = await New("adverse-" + mode);
        await Run(adverse, "inspect");
        fake.Mode = mode;
        await Reject(() => Run(adverse, "compose"), mode + " cannot create passing compound action");
        fake.Mode = "normal";
        Check(State(adverse).Stages["compose"].Status == "failed", mode + " records failed stage");
        if (mode == "mutate-source")
            File.WriteAllBytes(w.Resolve("model.glb"), modelBytes);
    }
    var recovery = await New("recovery");
    await Run(recovery, "inspect");
    fake.Mode = "exit-after-output";
    await Reject(() => Run(recovery, "compose"), "failed process after valid files is not accepted");
    fake.Mode = "normal";
    var failed = State(recovery).Stages["compose"].Attempt;
    await Run(recovery, "compose");
    Check(State(recovery).Stages["compose"].Attempt != failed && Directory.Exists(w.Resolve(failed)), "retry creates a fresh immutable attempt and retains failed output");
    var interrupted = State(recovery);
    interrupted.Stages["compose"].Status = "running";
    w.Save(recovery["manifest"], interrupted);
    await Run(recovery, "compose");
    Check(State(recovery).History.Any(item => item["event"]?.GetValue<string>() == "stage-interrupted"), "persisted interrupted attempt is retained during retry");
    await Run(recovery, "export");
    fake.Mode = "short-review";
    await Reject(() => Run(recovery, "review"), "passing-looking frame counts cannot conceal missing required camera/time coverage");
    fake.Mode = "normal";
    await Run(recovery, "review");
    await Run(recovery, "validate");
    Check(true, "complete review retry restores valid actual-stage protocol state");
    var cancel = await New("cancelled");
    await Run(cancel, "inspect");
    using (var cancelled = new CancellationTokenSource())
    {
        cancelled.Cancel();
        await Reject(() => Run(cancel, "compose", cancelled.Token), "explicit cancellation leaves failed attempt rather than completion");
    }
    var boundedRecipe = recipe.DeepClone().AsObject();
    boundedRecipe["budgets"]!["maxAttempts"] = 1;
    w.Save("bounded.json", boundedRecipe);
    var boundedArgs = Settings("bounded");
    boundedArgs["recipe"] = "bounded.json";
    await Run(boundedArgs, "init");
    boundedArgs["manifest"] = ".opencaw/.cache/tasks/fixture/model-to-action/bounded/v1/manifest.json";
    await Run(boundedArgs, "inspect");
    fake.Mode = "missing-result";
    await Reject(() => Run(boundedArgs, "compose"), "bounded initial producer failure retained");
    fake.Mode = "normal";
    var launchCount = fake.Calls;
    await Reject(() => Run(boundedArgs, "compose"), "exhausted attempt budget blocks further production");
    Check(fake.Calls == launchCount, "exhausted stage never launches fake native producer");
    var scriptBytes = File.ReadAllText(Path.Combine(scripts, "action.py"));
    File.AppendAllText(Path.Combine(scripts, "action.py"), "# changed");
    await Reject(() => Run(recovery, "inspect"), "changed fixed script invalidates source evidence");
    File.WriteAllText(Path.Combine(scripts, "action.py"), scriptBytes);
    var escaped = Settings("escape");
    escaped["motion-package"] = "../outside.json";
    await Reject(() => Run(escaped, "init"), "source path escape fails");
    Console.WriteLine("PASS " + passed + " action orchestration/compiler assertions; Blender, engine resolver, approvals and promotion are SIMULATED");
    File.WriteAllText(Path.Combine(root, "verification.json"), JsonSerializer.Serialize(new
    {
        status = "pass",
        assertions = passed,
        simulatedProcesses = true,
        actualBlender = false,
        actualRuntime = false,
        humanAcceptance = false
    }, Workspace.Json));
    return 0;
}
catch (Exception error) { Console.Error.WriteLine(error); return 1; }

sealed class FakeEngine : IEngineResolver
{
    public string Selection = "THREEJS";
    public Task<JsonObject> Resolve(CancellationToken cancellation) => Task.FromResult(new JsonObject { ["effectiveEngine"] = Selection, ["projectEngine"] = Selection, ["contractSha256"] = new string('1', 64), ["definitionSha256"] = new string('2', 64), ["registrySha256"] = new string('3', 64) });
}
sealed class FakeProcess(Workspace w) : INativeProcess
{
    public string Mode = "normal"; public int Calls;
    public Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds, CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
    {
        Calls++;
        cancellation.ThrowIfCancellationRequested();
        Directory.CreateDirectory(Path.GetDirectoryName(log)!);
        var testArgs = arguments.ToArray();
        File.WriteAllText(log, testArgs.Contains("--version") ? "Blender 4.5.10 LTS SYNTHETIC VERSION" : "SIMULATED PROCESS; not actual Blender\n");
        if (testArgs.Contains("--version"))
            return Task.CompletedTask;
        var jobPath = testArgs[System.Array.IndexOf(testArgs, "--job") + 1];
        var job = JsonNode.Parse(File.ReadAllText(jobPath))!.AsObject();
        var op = job["operation"]!.GetValue<string>();
        if (Mode == "missing-result")
            return Task.CompletedTask;
        var folder = job["outputDir"]!.GetValue<string>();
        var plan = job["plan"]!.DeepClone().AsObject();
        var artifacts = new JsonObject();
        var actions = plan["actions"]!.DeepClone().AsArray();
        foreach (var action in actions)
            action!["motionSha256"] = new string('d', 64);
        if (Mode == "wrong-action")
            actions[0]!["id"] = "wrong";
        if (Mode == "changed-cues")
            actions[0]!["cues"]![0]!["radius"] = .4;
        if (op == "inspect")
        {
            artifacts["report"] = folder + "/inspection.json";
            w.Save(folder + "/inspection.json", new
            {
                simulationOnly = true
            });
        }
        if (op is "compose" or "export")
        {
            artifacts["blend"] = folder + "/source.blend";
            File.WriteAllText(w.Resolve(folder + "/source.blend"), Mode == "corrupt-blend" ? "not-a-blend" : "BLENDER_SIMULATED_BYTES");
        }
        if (op == "export")
        {
            artifacts["glb"] = folder + "/model.glb";
            Fixture.WriteGlb(w.Resolve(folder + "/model.glb"), actions.Select(node => node!["clip"]!.GetValue<string>()).ToArray());
            plan["actions"] = actions.DeepClone();
            artifacts["package"] = folder + "/action-package.json";
            w.Save(folder + "/action-package.json", plan);
            if (Mode == "alias-verification")
            {
                foreach (var role in new[] { "verificationIndex", "verificationData", "verificationFrames" })
                    artifacts[role] = artifacts["package"]!.DeepClone();
            }
            else if (Mode != "missing-verification")
            {
                var evidence = folder + "/verification/"; Directory.CreateDirectory(w.Resolve(evidence));
                artifacts["verificationIndex"] = evidence + "index.json";
                artifacts["verificationData"] = evidence + "poses.bin";
                artifacts["verificationFrames"] = evidence + "frames.jsonl";
                w.Save(evidence + "index.json", new { simulationOnly = true, note = "SYNTHETIC fixture bytes; not real pose evidence" });
                var payload = Encoding.ASCII.GetBytes("OPENCAW-POSE-V1\0\0SYNTHETIC POSE BYTES");
                File.WriteAllBytes(w.Resolve(evidence + "poses.bin"), payload);
                if (Mode != "missing-verification-file") File.WriteAllText(w.Resolve(evidence + "frames.jsonl"), "{\"simulationOnly\":true}\n");
                if (Mode == "oversized-verification")
                {
                    using var oversized = File.OpenWrite(w.Resolve(evidence + "poses.bin"));
                    oversized.SetLength(2048);
                }
                if (Mode == "substitute-verification-index")
                {
                    w.Save(evidence + "substitute.json", new { simulationOnly = true });
                    artifacts["verificationIndex"] = evidence + "substitute.json";
                }
                if (Mode == "swap-verification-payloads")
                {
                    artifacts["verificationData"] = evidence + "frames.jsonl";
                    artifacts["verificationFrames"] = evidence + "poses.bin";
                }
            }
        }
        if (op == "review")
        {
            var packets = new JsonArray();
            var count = 0;
            var fps = job["review"]!["fps"]!.GetValue<double>();
            foreach (var action in actions)
            {
                var duration = action!["duration"]!.GetValue<double>();
                var times = new HashSet<double> { 0, duration };
                for (var i = 0; i <= Math.Ceiling(duration * fps); i++)
                    times.Add(Math.Min(duration, i / fps));
                foreach (var step in action["steps"]!.AsArray())
                {
                    times.Add(step!["start"]!.GetValue<double>());
                    times.Add(step["end"]!.GetValue<double>());
                }
                foreach (var cue in action["cues"]!.AsArray())
                {
                    times.Add(cue!["start"]!.GetValue<double>());
                    times.Add(cue["end"]!.GetValue<double>());
                }
                foreach (var marker in action["markers"]!.AsArray())
                    times.Add(marker!["at"]!.GetValue<double>());
                var frames = new JsonArray();
                foreach (var camera in job["review"]!["cameras"]!.AsArray())
                foreach (var time in times.Order())
                {
                    if (Mode == "short-review" && count == 0)
                    {
                        Mode = "short-review-skipped";
                        continue;
                    }
                    var file = folder + "/f" + count + ".png";
                    File.WriteAllBytes(w.Resolve(file), [137, 80, 78, 71, 13, 10, 26, 10]);
                    frames.Add(new JsonObject { ["path"] = file, ["sha256"] = Workspace.Hash(w.Resolve(file)), ["time"] = time, ["camera"] = camera!.GetValue<string>() });
                    count++;
                }
                packets.Add(new JsonObject { ["id"] = action["id"]!.GetValue<string>(), ["frames"] = frames });
            }
            artifacts["review"] = folder + "/review.html";
            File.WriteAllText(w.Resolve(folder + "/review.html"), "<!doctype html><html>SIMULATED review</html>");
            artifacts["report"] = folder + "/report.json";
            artifacts["reviewReport"] = folder + "/report.json";
            w.Save(folder + "/report.json", new JsonObject { ["frameCount"] = count, ["requestedFrameCount"] = count, ["humanApproval"] = "pending", ["packets"] = packets });
        }
        if (Mode == "escaped-artifact")
            artifacts["blend"] = "inputs/escaped.blend";
        if (Mode == "extra-executable")
            File.WriteAllText(w.Resolve(folder + "/unexpected.exe"), "INERT BYTES; NEVER EXECUTED");
        if (Mode == "extra-binary")
            File.WriteAllText(w.Resolve(folder + "/unexpected.bin"), "INERT UNREGISTERED BINARY; NEVER EXECUTED");
        var findings = new JsonArray();
        if (Mode is "critical-finding" or "unknown-finding")
            findings.Add(new JsonObject { ["severity"] = Mode == "critical-finding" ? "critical" : "not-a-known-severity" });
        w.Save(job["result"]!.GetValue<string>(), new JsonObject { ["schemaVersion"] = Mode == "wrong-schema" ? "wrong/v1" : "opencaw-action-stage/v1", ["operation"] = op, ["inputSha256"] = Workspace.Hash(w.Resolve(job["input"]!.GetValue<string>())), ["artifacts"] = artifacts, ["actions"] = actions, ["metrics"] = Mode == "empty-metrics" ? new JsonObject() : new JsonObject { ["simulationOnly"] = true }, ["findings"] = findings });
        if (Mode == "mutate-source")
            File.AppendAllText(w.Resolve("model.glb"), "mutated");
        if (Mode == "exit-after-output")
            throw new InvalidOperationException("SIMULATED producer nonzero exit after plausible outputs");
        return Task.CompletedTask;
    }
}
static class Fixture
{
    public static JsonObject Motion(string modelHash) => JsonNode.Parse("""
    {"schemaVersion":"opencaw-motion-package/v1","profile":"rigid","model":{"path":"model.glb","sha256":"MODEL"},"engine":{"effectiveEngine":"THREEJS"},"rig":{"id":"RIG","rootNode":"Root"},"anchors":[{"id":"hand","node":"anchor.hand","parent":"Visual","position":[0,0,0]}],"clips":[{"id":"kick","action":"kick","duration":1,"rootMotion":"in-place","motionSha256":"KICK","markers":[{"event":"release","time":0.5},{"event":"beat","time":0.25}]},{"id":"punch","action":"punch","duration":1,"rootMotion":"in-place","motionSha256":"PUNCH","markers":[]}],"provenance":{"provider":"owned","notes":"No Adobe services used"}}
    """.Replace("MODEL", modelHash).Replace("RIG", new string('a', 64)).Replace("KICK", new string('b', 64)).Replace("PUNCH", new string('c', 64)))!.AsObject();
    public static JsonObject Recipe() => JsonNode.Parse("""
    {"schemaVersion":1,"fps":4,"actions":[{"id":"combo","role":"presentation","steps":[{"id":"first","clip":"kick","from":0,"to":1,"rate":1,"repeat":2,"blendIn":0},{"id":"last","clip":"punch","from":0.25,"to":0.75,"rate":1,"repeat":1,"blendIn":0.25}],"cues":[{"id":"projectile","type":"projectile","anchor":"hand","start":{"step":"first","occurrence":0,"marker":"release"},"end":{"step":"last","occurrence":0,"offset":0.5},"color":"#ff8000","radius":0.1,"target":"point"}]}],"targets":[{"id":"point","mode":"fixed-world-point","maxDistance":100}],"budgets":{"maxActions":16,"maxStepsPerAction":64,"maxExpandedSteps":256,"maxActionSeconds":120,"maxEffects":64,"maxParticles":2048,"maxFrames":20000,"maxReviewFrames":1200,"maxRuntimeBytes":33554432,"timeoutSeconds":180,"maxLogBytes":16777216,"maxAttempts":16},"review":{"fps":4,"resolution":[128,128],"cameras":["front","three-quarter"],"targets":{"point":[2,0,0]}}}
    """)!.AsObject();
    public static void WriteGlb(string path, string[] names)
    {
        var json = new JsonObject { ["asset"] = new JsonObject { ["version"] = "2.0", ["generator"] = "OpenCaw SYNTHETIC PROTOCOL FIXTURE" }, ["nodes"] = new JsonArray(new JsonObject { ["name"] = "Root", ["children"] = new JsonArray(1, 2) }, new JsonObject { ["name"] = "Visual", ["mesh"] = 0 }, new JsonObject { ["name"] = "anchor.hand" }), ["meshes"] = new JsonArray(new JsonObject { ["primitives"] = new JsonArray(new JsonObject { ["attributes"] = new JsonObject { ["POSITION"] = 0 } }) }), ["animations"] = new JsonArray(names.Select(name => (JsonNode)new JsonObject { ["name"] = name, ["channels"] = new JsonArray(new JsonObject { ["sampler"] = 0, ["target"] = new JsonObject { ["node"] = 1, ["path"] = "translation" } }), ["samplers"] = new JsonArray(new JsonObject { ["input"] = 1, ["output"] = 2 }) }).ToArray()), ["buffers"] = new JsonArray(new JsonObject { ["byteLength"] = 68 }), ["bufferViews"] = new JsonArray(new JsonObject { ["buffer"] = 0, ["byteOffset"] = 0, ["byteLength"] = 36 }, new JsonObject { ["buffer"] = 0, ["byteOffset"] = 36, ["byteLength"] = 8 }, new JsonObject { ["buffer"] = 0, ["byteOffset"] = 44, ["byteLength"] = 24 }), ["accessors"] = new JsonArray(new JsonObject { ["bufferView"] = 0, ["componentType"] = 5126, ["count"] = 3, ["type"] = "VEC3" }, new JsonObject { ["bufferView"] = 1, ["componentType"] = 5126, ["count"] = 2, ["type"] = "SCALAR", ["min"] = new JsonArray(0), ["max"] = new JsonArray(1) }, new JsonObject { ["bufferView"] = 2, ["componentType"] = 5126, ["count"] = 2, ["type"] = "VEC3" }) };
        var content = Encoding.UTF8.GetBytes(json.ToJsonString());
        var padded = (content.Length + 3) / 4 * 4;
        var bytes = new byte[20 + padded + 8 + 68];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes, 0x46546c67);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(4), 2);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(8), (uint)bytes.Length);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(12), (uint)padded);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(16), 0x4e4f534a);
        content.CopyTo(bytes, 20);
        for (var i = 20 + content.Length; i < 20 + padded; i++)
            bytes[i] = 32;
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(20 + padded), 68);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.AsSpan(24 + padded), 0x004e4942);
        BinaryPrimitives.WriteSingleLittleEndian(bytes.AsSpan(28 + padded + 40), 1);
        File.WriteAllBytes(path, bytes);
    }
}
