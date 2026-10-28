using System.Text;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Application;
using OpenCaw.ProofToModel.Domain;
using OpenCaw.ProofToModel.Infrastructure;

/// <summary>Real filesystem/PNG preparation with a deliberately simulated inference process.</summary>
static class MultiViewPipelineTests
{
    const string TaskName = "multiview-runtime-tests";
    static readonly string[] ModelNames = ["dinov3.gguf", "pixal3d_naf.gguf", "pixal3d_ss_flow_mv.gguf", "pixal3d_shape_flow_512_mv.gguf", "pixal3d_shape_flow_1024_mv.gguf", "pixal3d_tex_flow_1024_mv.gguf", "ss_dec.gguf", "shape_dec.gguf", "tex_dec.gguf"];

    public static async Task Run(Workspace parent, Action<bool, string> check, Func<Func<Task>, string, Task> reject)
    {
        async Task<Fixture> Prepare(string name, Action<Fixture, JsonObject>? configure = null, bool diagnostic = false)
        {
            var root = parent.Resolve("mv-runtime-" + name + "-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            var fixture = new Fixture(new Workspace(root), name);
            var workspace = fixture.Workspace;
            File.WriteAllText(workspace.Resolve("STYLE.md"), "Primary OpenCaw art pipeline:\n- PROOF_TO_MODEL\n");
            workspace.Save("rights.json", new { authorized = true, source = "Synthetic engineering fixtures; no external asset rights asserted" });
            workspace.Save("recipe.json", new
            {
                targetFaces = 100, textureSize = 32, cageExtrusion = .1, maxRayDistance = .1, uvMargin = .01,
                lodRatios = new[] { .5 }, colliderMaxFaces = 100, maxTriangles = 1000, maxMaterials = 3,
                maxTextureBytes = 100000, parts = Array.Empty<string>(), riggingRequired = false, animationRequired = false,
                proofPreparation = new { maxSetRevisions = 10 }
            });
            var models = new JsonArray();
            Directory.CreateDirectory(workspace.Resolve(fixture.ModelDirectory));
            foreach (var model in ModelNames)
            {
                var path = fixture.ModelDirectory + "/" + model;
                File.WriteAllText(workspace.Resolve(path), "SIMULATED MODEL IDENTITY ONLY; NOT GGUF WEIGHTS: " + model);
                models.Add(new JsonObject { ["path"] = path, ["sha256"] = workspace.HashFile(workspace.Resolve(path)), ["license"] = "synthetic-test-fixture", ["licenseAccepted"] = true });
            }
            File.WriteAllText(workspace.Resolve("simulated-engine.bin"), "SIMULATED EXECUTABLE IDENTITY; NO NATIVE ENGINE IS EXECUTED");
            var toolchain = new JsonObject
            {
                ["schemaVersion"] = 1, ["modelFamily"] = "mv", ["viewCount"] = 6, ["modelDir"] = fixture.ModelDirectory,
                ["engine"] = new JsonObject { ["path"] = "simulated-engine.bin", ["sha256"] = workspace.HashFile(workspace.Resolve("simulated-engine.bin")), ["version"] = "synthetic-process-fixture" },
                ["models"] = models, ["files"] = new JsonArray(),
                ["limits"] = new JsonObject { ["maxAttempts"] = 10, ["timeoutSeconds"] = 10, ["maxLogBytes"] = 100000 },
                ["reconstruction"] = new JsonObject
                {
                    ["arguments"] = new JsonArray("--views", "{input}", "--models", "{modelDir}", "--pixal3d-weights", "mv", "--num-views", "6", "--res", "1024", "--require-gpu", "{output}")
                }
            };
            configure?.Invoke(fixture, toolchain);
            workspace.Save("toolchain.json", toolchain);
            var originals = new JsonArray();
            var sizes = new[] { (8, 6), (5, 8), (8, 8), (6, 8), (10, 8), (8, 10) };
            for (var i = 0; i < 6; i++)
            {
                var (width, height) = sizes[i];
                var pixels = new byte[width * height * 4];
                for (var y = 0; y < height; y++)
                    for (var x = 0; x < width; x++)
                    {
                        var offset = (y * width + x) * 4;
                        pixels[offset] = (byte)(30 + i * 20);
                        pixels[offset + 1] = (byte)(40 + x);
                        pixels[offset + 2] = (byte)(80 + y);
                        pixels[offset + 3] = x > 0 && y > 0 && x < width - 1 && y < height - 1 ? (byte)255 : (byte)0;
                    }
                var image = "source-" + i + ".png";
                RgbaPng.Write(workspace.Resolve(image), new(width, height, pixels));
                originals.Add(new JsonObject { ["id"] = "source-" + i, ["path"] = image });
            }
            workspace.Save("sources.json", new JsonObject { ["schemaVersion"] = 1, ["images"] = originals });
            if (diagnostic) fixture.Options["mode"] = "single-view-diagnostic";
            await fixture.Execute("init");
            fixture.Options["manifest"] = fixture.ManifestPath;
            if (diagnostic) return fixture;
            workspace.Save("classification.json", PreparationTests.Classification(workspace, fixture.State));
            fixture.Options["classification"] = "classification.json";
            await fixture.Execute("classify");
            var proofs = PreparationTests.ProofSet(workspace, fixture.State);
            proofs["views"]![1]!["cameraAngleX"] = .42;
            proofs["views"]![5]!["cameraAngleX"] = .38;
            workspace.Save("proof-set.json", proofs);
            fixture.Options["proof-set"] = "proof-set.json";
            await fixture.Execute("prepare-proofs");
            return fixture;
        }

        async Task Approve(Fixture fixture, string kind)
        {
            var output = new StringWriter();
            var previous = Console.Out;
            try { Console.SetOut(output); await fixture.Execute("status"); }
            finally { Console.SetOut(previous); }
            var status = JsonNode.Parse(output.ToString())!.AsObject();
            var key = kind == "proof-set" ? "proofSet" : kind;
            var receipt = ".opencaw/.cache/tasks/" + TaskName + "/reviews/" + kind + "-" + Guid.NewGuid().ToString("N") + ".json";
            fixture.Workspace.Save(receipt, new
            {
                kind, reviewer = "synthetic-human", decision = "approved", human = true,
                reason = "SIMULATED TEST APPROVAL; no actual human production review occurred",
                fingerprint = status["approvalFingerprints"]![key]!.GetValue<string>()
            });
            fixture.Options["kind"] = kind;
            fixture.Options["reviewer"] = "synthetic-human";
            fixture.Options["evidence"] = receipt;
            await fixture.Execute("record");
        }

        async Task Ready(Fixture fixture)
        {
            await Approve(fixture, "proof-set");
            await fixture.Execute("preprocess");
            await Approve(fixture, "preprocessing");
        }

        var valid = await Prepare("valid");
        await reject(() => valid.Execute("preprocess"), "SYNTHETIC: six-view preparation does not manufacture whole-set approval");
        check(valid.Process.Launches == 0 && !valid.State.Stages.ContainsKey("preprocess"), "SYNTHETIC: missing proof-set approval blocks before native launch or preprocessing attempt");
        await Approve(valid, "proof-set");
        await valid.Execute("preprocess");
        check(valid.Process.Launches == 0, "six real PNGs with suitable alpha preprocess without inference or background-removal calls");
        var prepared = valid.Workspace.Load<JsonObject>(valid.State.Stages["preprocess"].Artifacts["dataset"]);
        var expectedFov = MultiViewGeometry.PaddedFov(.42, 5, 10);
        check(Math.Abs(prepared["views"]![1]!["cameraAngleX"]!.GetValue<double>() - expectedFov) < 1e-12,
            "nonsquare right proof preserves its approved per-view focal length on the common canvas");
        check(prepared["views"]![1]!["normalization"]!["centerOffsetPixels"]![0]!.GetValue<double>() == -.5,
            "odd common-canvas padding records the actual nominal half-pixel offset");
        check(prepared["views"]!.AsArray().All(view => RgbaPng.Read(valid.Workspace.Resolve(view!["image"]!.GetValue<string>())).Width == 10),
            "all six actual conditioning PNGs share the maximum full-frame canvas");
        await reject(() => valid.Execute("reconstruct"), "SYNTHETIC: reconstruction requires separate preprocessing review");
        check(valid.Process.Launches == 0 && !valid.State.Stages.ContainsKey("reconstruct"), "SYNTHETIC: missing preprocessing approval prevents a process launch");
        await Approve(valid, "preprocessing");
        await valid.Execute("reconstruct");
        var completed = valid.State.Stages["reconstruct"];
        var receipt = valid.Workspace.Load<JsonObject>(completed.Artifacts["inputReceipt"]);
        check(completed.Status == "complete" && valid.Process.Launches == 1 && valid.Process.FramesRead == 6,
            "SYNTHETIC: successful process fixture reads all six actual PNGs before emitting a triangle GLB");
        check(valid.Process.LastReadHashes.Distinct(StringComparer.Ordinal).Count() == 6,
            "SYNTHETIC: six distinct image byte identities were consumed, not one repeated filename");
        check(receipt["viewCount"]!.GetValue<int>() == 6 && receipt["views"]!.AsArray().Count == 6
            && receipt["outputSha256"]!.GetValue<string>() == valid.Workspace.HashFile(valid.Workspace.Resolve(completed.Artifacts["glb"])),
            "SYNTHETIC: reconstruction receipt binds six inputs and the actual fixture output hash");
        check(receipt["upstreamValidationLimit"]!.GetValue<string>().Contains("not anatomical", StringComparison.Ordinal),
            "SYNTHETIC: technical success does not claim anatomical or visual acceptance");
        await valid.Execute("validate");
        check(true, "SYNTHETIC: complete staged hashes and separate approvals validate after simulated reconstruction");

        foreach (var scenario in new[] { "wrong-family", "missing-inventory", "missing-model-file", "denied-license", "mesh-scale-override", "view-count-override" })
        {
            var fixture = await Prepare(scenario, (f, config) =>
            {
                if (scenario == "wrong-family") config["modelFamily"] = "sv";
                if (scenario == "missing-inventory") config["models"]!.AsArray().RemoveAt(0);
                if (scenario == "missing-model-file") File.Delete(f.Workspace.Resolve(f.ModelDirectory + "/" + ModelNames[0]));
                if (scenario == "denied-license") config["models"]![0]!["licenseAccepted"] = false;
                if (scenario == "mesh-scale-override")
                {
                    var arguments = config["reconstruction"]!["arguments"]!.AsArray();
                    arguments.Insert(arguments.Count - 1, "--mesh-scale");
                    arguments.Insert(arguments.Count - 1, "2");
                }
                if (scenario == "view-count-override") config["reconstruction"]!["arguments"]![7] = "4";
            });
            await Ready(fixture);
            await reject(() => fixture.Execute("reconstruct"), "SYNTHETIC: " + scenario + " fails before native work");
            check(fixture.Process.Launches == 0 && fixture.State.Stages["reconstruct"].Status == "failed",
                "SYNTHETIC: " + scenario + " records failure without launching the process fixture");
        }

        foreach (var scenario in new[] { "submitted-image", "submitted-dataset", "submitted-transforms", "bound-dataset", "bound-model", "bound-toolchain", "bound-executable" })
        {
            var fixture = await Prepare("mutation-" + scenario);
            await Ready(fixture);
            fixture.Process.Mutate = invocation =>
            {
                var workspace = fixture.Workspace;
                var attempt = Path.GetDirectoryName(invocation.Output)!;
                switch (scenario)
                {
                    case "submitted-image":
                        File.AppendAllText(invocation.FrameFiles[0], "changed input bytes");
                        break;
                    case "submitted-dataset":
                        File.AppendAllText(Path.Combine(attempt, "submitted-dataset.json"), " ");
                        break;
                    case "submitted-transforms":
                        var cameras = workspace.Load<JsonObject>(invocation.Transforms);
                        cameras["frames"]![0]!["camera_angle_x"] = .9;
                        workspace.Save(invocation.Transforms, cameras);
                        break;
                    case "bound-dataset":
                        File.AppendAllText(workspace.Resolve(fixture.State.Stages["preprocess"].Artifacts["dataset"]), " ");
                        break;
                    case "bound-model":
                        File.AppendAllText(workspace.Resolve(fixture.ModelDirectory + "/" + ModelNames[0]), "changed model bytes");
                        break;
                    case "bound-toolchain":
                        File.AppendAllText(workspace.Resolve("toolchain.json"), " ");
                        break;
                    case "bound-executable":
                        File.AppendAllText(invocation.Executable, "changed executable bytes");
                        break;
                }
            };
            await reject(() => fixture.Execute("reconstruct"), "SYNTHETIC: process mutation of " + scenario + " fails in the same invocation");
            check(fixture.Process.Launches == 1 && fixture.State.Stages["reconstruct"].Status == "failed",
                "SYNTHETIC: " + scenario + " cannot persist a complete reconstruction awaiting later stale detection");
            check(fixture.Process.LastOutput is not null && File.Exists(fixture.Process.LastOutput),
                "SYNTHETIC: mutation rejection is exercised despite an emitted valid fixture GLB");
        }

        var failed = await Prepare("failed-process");
        await Ready(failed);
        failed.Process.ThrowAfterWrite = true;
        await reject(() => failed.Execute("reconstruct"), "SYNTHETIC: failed process is not rescued by a valid output or passing-looking log");
        check(failed.State.Stages["reconstruct"].Status == "failed" && File.Exists(failed.Process.LastOutput),
            "SYNTHETIC: actual failed-process contract retains the candidate and records a failed stage");
        var meshless = await Prepare("meshless-output");
        await Ready(meshless);
        meshless.Process.MeshlessOutput = true;
        await reject(() => meshless.Execute("reconstruct"), "SYNTHETIC: a valid GLB container without a mesh cannot satisfy reconstruction");
        check(meshless.State.Stages["reconstruct"].Status == "failed", "SYNTHETIC: empty mesh discovery remains failed");

        var diagnostic = await Prepare("diagnostic-promotion", diagnostic: true);
        var diagnosticError = "";
        await reject(async () =>
        {
            try { await diagnostic.Execute("promote"); }
            catch (InvalidOperationException error) { diagnosticError = error.Message; throw; }
        }, "single-view diagnostic mode cannot promote a runtime asset");
        check(diagnosticError.Contains("diagnostic assets cannot be promoted", StringComparison.Ordinal)
            && !Directory.Exists(diagnostic.Workspace.Resolve("assets/models")),
            "diagnostic promotion stops at its explicit mode boundary before any destination is created");
    }

    sealed class Fixture
    {
        public Workspace Workspace { get; }
        public SimulatedProcess Process { get; }
        public Dictionary<string, string> Options { get; }
        public string ModelDirectory => ".local/tools/proof-to-model/models/synthetic-mv";
        public string ManifestPath { get; }
        public Manifest State => Workspace.Load<Manifest>(ManifestPath);
        public Fixture(Workspace workspace, string name)
        {
            Workspace = workspace;
            Process = new SimulatedProcess(workspace);
            ManifestPath = ".opencaw/.cache/tasks/" + TaskName + "/proof-to-model/" + name + "/v1/manifest.json";
            Options = new()
            {
                ["task"] = TaskName, ["asset"] = name, ["version"] = "v1", ["actor"] = "synthetic-builder",
                ["sources"] = "sources.json", ["rights"] = "rights.json", ["recipe"] = "recipe.json", ["toolchain"] = "toolchain.json"
            };
        }
        public Task Execute(string command) => new Pipeline(Workspace, Options, Process, new AlphaProcessor()).Execute(command, default);
    }

    sealed record Invocation(string Executable, string Output, string Transforms, string[] FrameFiles);

    sealed class SimulatedProcess(Workspace workspace) : INativeProcess
    {
        public int Launches { get; private set; }
        public int FramesRead { get; private set; }
        public List<string> LastReadHashes { get; } = [];
        public string? LastOutput { get; private set; }
        public bool ThrowAfterWrite { get; set; }
        public bool MeshlessOutput { get; set; }
        public Action<Invocation>? Mutate { get; set; }
        public Task Run(string executable, IEnumerable<string> arguments, string cwd, string log, int seconds,
            CancellationToken cancellation = default, long maximumLogBytes = 16777216, IReadOnlyDictionary<string, string>? environment = null)
        {
            cancellation.ThrowIfCancellationRequested();
            Launches++;
            var args = arguments.ToArray();
            string Value(string flag)
            {
                var index = Array.IndexOf(args, flag);
                if (index < 0 || index + 1 >= args.Length) throw new InvalidOperationException("Simulated process missing " + flag);
                return args[index + 1];
            }
            if (Value("--num-views") != "6" || Value("--pixal3d-weights") != "mv" || Value("--res") != "1024")
                throw new InvalidOperationException("Simulated process did not receive the six-view MV invocation");
            var directory = Value("--views");
            var transformsPath = Path.Combine(directory, "transforms.json");
            var transforms = workspace.Load<JsonObject>(transformsPath);
            var frames = transforms["frames"]!.AsArray();
            if (frames.Count != 6) throw new InvalidOperationException("Simulated process actually discovered fewer than six frames");
            var expected = workspace.Load<JsonObject>(Path.Combine(Path.GetDirectoryName(directory)!, "submitted-dataset.json"));
            var actualFiles = new List<string>();
            LastReadHashes.Clear();
            foreach (var (frame, index) in frames.Select((node, index) => (node!.AsObject(), index)))
            {
                var path = workspace.Resolve(Path.Combine(directory, frame["file_path"]!.GetValue<string>()));
                var pixels = RgbaPng.Read(path);
                var reviewed = expected["views"]![index]!.AsObject();
                var hash = workspace.HashFile(path);
                if (pixels.Width != 10 || pixels.Height != 10 || !pixels.Pixels.Where((_, offset) => offset % 4 == 3).Any(alpha => alpha > 0)
                    || hash != reviewed["sha256"]!.GetValue<string>()
                    || !JsonNode.DeepEquals(frame["transform_matrix"], reviewed["cameraToWorld"])
                    || frame["camera_angle_x"]!.GetValue<double>() != reviewed["cameraAngleX"]!.GetValue<double>())
                    throw new InvalidOperationException("Simulated process observed a different image, camera or alpha canvas");
                FramesRead++;
                LastReadHashes.Add(hash);
                actualFiles.Add(path);
            }
            LastOutput = args.Last();
            WriteGlb(LastOutput, MeshlessOutput);
            File.WriteAllText(log, "SIMULATED PROCESS ONLY; not native inference, SDK execution or production acceptance. PASS-looking text cannot override process failure.");
            Mutate?.Invoke(new(executable, LastOutput, transformsPath, actualFiles.ToArray()));
            if (ThrowAfterWrite) throw new InvalidOperationException("Simulated process exited unsuccessfully after writing a valid candidate");
            return Task.CompletedTask;
        }
    }

    static void WriteGlb(string path, bool meshless)
    {
        var body = new JsonObject { ["asset"] = new JsonObject { ["version"] = "2.0", ["generator"] = "OpenCaw deterministic process simulation; not inferred geometry" } };
        using var binary = new MemoryStream();
        using (var writer = new BinaryWriter(binary, Encoding.UTF8, true))
        {
            foreach (var value in new float[] { 0, 0, 0, 1, 0, 0, 0, 1, 0 }) writer.Write(value);
            foreach (var value in new ushort[] { 0, 1, 2 }) writer.Write(value);
            writer.Write((ushort)0);
        }
        if (!meshless)
        {
            body["buffers"] = new JsonArray(new JsonObject { ["byteLength"] = 44 });
            body["bufferViews"] = new JsonArray(new JsonObject { ["buffer"] = 0, ["byteOffset"] = 0, ["byteLength"] = 36, ["target"] = 34962 }, new JsonObject { ["buffer"] = 0, ["byteOffset"] = 36, ["byteLength"] = 6, ["target"] = 34963 });
            body["accessors"] = new JsonArray(new JsonObject { ["bufferView"] = 0, ["componentType"] = 5126, ["count"] = 3, ["type"] = "VEC3", ["min"] = new JsonArray(0, 0, 0), ["max"] = new JsonArray(1, 1, 0) }, new JsonObject { ["bufferView"] = 1, ["componentType"] = 5123, ["count"] = 3, ["type"] = "SCALAR" });
            body["meshes"] = new JsonArray(new JsonObject { ["primitives"] = new JsonArray(new JsonObject { ["attributes"] = new JsonObject { ["POSITION"] = 0 }, ["indices"] = 1, ["mode"] = 4 }) });
            body["nodes"] = new JsonArray(new JsonObject { ["mesh"] = 0 });
            body["scenes"] = new JsonArray(new JsonObject { ["nodes"] = new JsonArray(0) });
            body["scene"] = 0;
        }
        var json = Encoding.UTF8.GetBytes(body.ToJsonString());
        var padding = (4 - json.Length % 4) % 4;
        var binaryBytes = meshless ? [] : binary.ToArray();
        using var file = File.Create(path);
        using var output = new BinaryWriter(file);
        output.Write(0x46546c67u);
        output.Write(2u);
        output.Write((uint)(20 + json.Length + padding + (meshless ? 0 : 8 + binaryBytes.Length)));
        output.Write((uint)(json.Length + padding));
        output.Write(0x4e4f534au);
        output.Write(json);
        output.Write(Enumerable.Repeat((byte)32, padding).ToArray());
        if (!meshless)
        {
            output.Write((uint)binaryBytes.Length);
            output.Write(0x004e4942u);
            output.Write(binaryBytes);
        }
    }
}
