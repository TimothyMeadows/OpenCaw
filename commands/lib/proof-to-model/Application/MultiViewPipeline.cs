using System.Globalization;
using System.Text.Json.Nodes;
using OpenCaw.ProofToModel.Domain;

namespace OpenCaw.ProofToModel.Application;

public sealed partial class Pipeline
{
    static string ViewText(JsonObject value, string key) => value[key]?.GetValue<string>() ?? throw new InvalidOperationException("Multi-view record missing " + key);

    void RequireMultiViewToolchain()
    {
        if (Toolchain["modelFamily"]?.GetValue<string>() != "mv" || Toolchain["viewCount"]?.GetValue<int>() != 6)
            throw new InvalidOperationException("Six-view production requires an explicitly selected MV model family and viewCount=6; SV is not a fallback");
        var directory = w.Relative(Toolchain["modelDir"]?.GetValue<string>() ?? throw new InvalidOperationException("Explicit MV modelDir required"));
        var models = Toolchain["models"]?.AsArray().Select(node => node!.AsObject()).ToArray() ?? [];
        var required = new[] { "dinov3.gguf", "pixal3d_naf.gguf", "pixal3d_ss_flow_mv.gguf", "pixal3d_shape_flow_512_mv.gguf", "pixal3d_shape_flow_1024_mv.gguf", "pixal3d_tex_flow_1024_mv.gguf", "ss_dec.gguf", "shape_dec.gguf", "tex_dec.gguf" };
        foreach (var name in required)
            if (models.Count(model => w.Relative(ViewText(model, "path")) == directory + "/" + name) != 1)
                throw new InvalidOperationException("MV model inventory requires exactly one " + name + " in the selected directory");
        if (models.Any(model => ViewText(model, "path").Contains("_sv.gguf", StringComparison.Ordinal)))
            throw new InvalidOperationException("Single-view flow weights cannot condition a multi-view reconstruction");
    }

    async Task PreprocessViews(Stage stage, CancellationToken cancellation)
    {
        var set = CurrentProofSet();
        MultiViewGeometry.Validate(set);
        var views = set["views"]!.AsArray().Select(node => node!.AsObject()).ToArray();
        var processed = new List<(JsonObject View, string Cutout, AlphaMatte Matte, bool Preserved)>();
        foreach (var view in views)
        {
            cancellation.ThrowIfCancellationRequested();
            var image = ViewText(view, "image");
            var name = ViewText(view, "view");
            var size = PreparationImage(image);
            var matte = alpha.Inspect(w.Resolve(image));
            var preserved = matte?.Suitable == true;
            var cutout = image;
            if (!preserved)
            {
                var child = new Stage { Attempt = stage.Attempt + "/foreground/" + name };
                Directory.CreateDirectory(w.Resolve(child.Attempt));
                Models(child);
                var output = child.Attempt + "/foreground.glb";
                var arguments = Arguments("preprocessing", image, output, child.Attempt);
                if (!arguments.Contains("birefnet") || !arguments.Contains("--bg-only") || arguments.Contains("threshold"))
                    throw new InvalidOperationException("Multi-view preprocessing requires explicit BiRefNet --bg-only without threshold fallback");
                await RunEngine(child, arguments, cancellation);
                cutout = (Section("preprocessing")["outputPattern"]?.GetValue<string>() ?? "{outputStem}_cutout.png").Replace("{outputStem}", Path.ChangeExtension(output, null));
                matte = alpha.Inspect(w.Resolve(cutout));
                if (matte?.Suitable != true)
                    throw new InvalidOperationException("BiRefNet did not preserve usable alpha for " + name);
                foreach (var pair in child.Inputs) stage.Inputs[pair.Key] = pair.Value;
                foreach (var pair in child.ExternalInputs) stage.ExternalInputs[pair.Key] = pair.Value;
            }
            if (matte!.Width != size.Width || matte.Height != size.Height)
                throw new InvalidOperationException("Matting changed the source canvas for " + name + "; explicit camera-aware proof revision is required");
            processed.Add((view, cutout, matte, preserved));
        }
        var side = processed.Max(item => Math.Max(item.Matte.Width, item.Matte.Height));
        if (side is < 1 or > 4096) throw new InvalidOperationException("Prepared common square canvas exceeds the 16-megapixel padding budget");
        var directory = stage.Attempt + "/views";
        Directory.CreateDirectory(w.Resolve(directory));
        var frames = new JsonArray();
        var preparedViews = new JsonArray();
        foreach (var (view, cutout, matte, preserved) in processed)
        {
            var name = ViewText(view, "view");
            var index = Array.IndexOf(MultiViewGeometry.Views, name);
            var file = index.ToString("D2", CultureInfo.InvariantCulture) + "-" + name + ".png";
            var image = directory + "/" + file;
            alpha.PadSquare(w.Resolve(cutout), w.Resolve(image), side);
            var prepared = alpha.Inspect(w.Resolve(image)) ?? throw new InvalidOperationException("Prepared image is not decodable RGBA");
            if (!prepared.Suitable || prepared.Width != side || prepared.Height != side)
                throw new InvalidOperationException("Prepared frame has invalid square alpha canvas: " + name);
            var mask = stage.Attempt + "/masks/" + name + ".png";
            Directory.CreateDirectory(Path.GetDirectoryName(w.Resolve(mask))!);
            alpha.SaveMask(w.Resolve(mask), prepared);
            var padX = (side - matte.Width) / 2;
            var padY = (side - matte.Height) / 2;
            var offsetX = padX - (side - matte.Width) / 2.0;
            var offsetY = padY - (side - matte.Height) / 2.0;
            if (set["camera"]?["calibration"]?.GetValue<string>() == "measured" && (offsetX != 0 || offsetY != 0))
                throw new InvalidOperationException("Odd pixel padding cannot preserve measured principal point with the native FOV-only camera; revise the canvas first");
            var approvedFov = view["cameraAngleX"]?.GetValue<double>() ?? set["camera"]!["cameraAngleX"]!.GetValue<double>();
            var fov = MultiViewGeometry.PaddedFov(approvedFov, matte.Width, side);
            frames.Add(new JsonObject { ["file_path"] = file, ["camera_angle_x"] = fov, ["transform_matrix"] = view["cameraToWorld"]!.DeepClone() });
            var record = view.DeepClone().AsObject();
            record["approvedImage"] = view["image"]!.DeepClone();
            record["approvedSha256"] = view["sha256"]!.DeepClone();
            record["image"] = image;
            record["sha256"] = Hash(image);
            record["mask"] = mask;
            record["maskSha256"] = Hash(mask);
            record["cameraAngleX"] = fov;
            record["normalization"] = new JsonObject
            {
                ["operation"] = preserved ? "preserve-alpha-and-common-square-pad" : "birefnet-preserve-canvas-and-common-square-pad",
                ["cutout"] = cutout, ["cutoutSha256"] = Hash(cutout), ["width"] = matte.Width, ["height"] = matte.Height,
                ["canvasSide"] = side, ["padLeft"] = padX, ["padTop"] = padY,
                ["padRight"] = side - matte.Width - padX, ["padBottom"] = side - matte.Height - padY,
                ["sourceToWorking"] = new JsonArray(1, 0, padX, 0, 1, padY, 0, 0, 1),
                ["centerOffsetPixels"] = new JsonArray(offsetX, offsetY),
                ["calibrationLimit"] = "nominal camera assumptions and any half-pixel padding offset are recorded, not measured calibration"
            };
            preparedViews.Add(record);
            stage.Artifacts["image-" + name] = image;
            stage.Artifacts["mask-" + name] = mask;
        }
        var transforms = directory + "/transforms.json";
        w.Save(transforms, new JsonObject { ["mesh_scale"] = set["camera"]!["meshScale"]!.DeepClone(), ["camera_angle_x"] = set["camera"]!["cameraAngleX"]!.DeepClone(), ["frames"] = frames });
        var dataset = set.DeepClone().AsObject();
        dataset["views"] = preparedViews;
        dataset["approvedProofSet"] = m.ProofSet;
        dataset["approvedProofSetSha256"] = Hash(m.ProofSet);
        dataset["approvalFingerprint"] = ApprovalFingerprint("proof-set");
        dataset["transforms"] = transforms;
        dataset["transformsSha256"] = Hash(transforms);
        dataset["engineExportFrame"] = "pixal3d-mv-export";
        dataset["sixViewNativeAcceptance"] = "not-established-by-preprocessing";
        var report = stage.Attempt + "/dataset.json";
        w.Save(report, dataset);
        stage.Artifacts["transforms"] = transforms;
        stage.Artifacts["dataset"] = report;
        stage.Artifacts["normalized"] = ViewText(preparedViews[0]!.AsObject(), "image");
        foreach (var file in Directory.GetFiles(w.Resolve(stage.Attempt), "*", SearchOption.AllDirectories))
            if (!file.EndsWith("process.log", StringComparison.Ordinal)) stage.Artifacts.TryAdd("retained-" + stage.Artifacts.Count, w.Relative(file));
        ValidateMultiViewDataset(dataset);
    }

    void ValidateMultiViewDataset(JsonObject dataset)
    {
        MultiViewGeometry.Validate(dataset);
        if (ViewText(dataset, "approvedProofSetSha256") != Hash(m.ProofSet) || ViewText(dataset, "approvalFingerprint") != ApprovalFingerprint("proof-set"))
            throw new InvalidOperationException("Prepared dataset is stale against the approved six-view set");
        var transformsPath = ViewText(dataset, "transforms");
        if (Hash(transformsPath) != ViewText(dataset, "transformsSha256")) throw new InvalidOperationException("Camera dataset hash changed");
        var transforms = w.Load<JsonObject>(transformsPath);
        var frames = transforms["frames"]?.AsArray() ?? throw new InvalidOperationException("Missing native camera frames");
        if (frames.Count != 6 || transforms["mesh_scale"]?.GetValue<double>() != dataset["camera"]!["meshScale"]!.GetValue<double>())
            throw new InvalidOperationException("Exactly six native frames and the selected projection scale are required");
        int? side = null;
        var current = CurrentProofSet()["views"]!.AsArray();
        var hashes = new HashSet<string>(StringComparer.Ordinal);
        for (var index = 0; index < 6; index++)
        {
            var view = dataset["views"]![index]!.AsObject();
            var approved = current[index]!.AsObject();
            if (ViewText(view, "approvedImage") != ViewText(approved, "image") || ViewText(view, "approvedSha256") != ViewText(approved, "sha256"))
                throw new InvalidOperationException("Prepared view substituted its approved source");
            var image = ViewText(view, "image");
            if (Hash(image) != ViewText(view, "sha256") || !hashes.Add(Hash(image)) || Hash(ViewText(view, "mask")) != ViewText(view, "maskSha256"))
                throw new InvalidOperationException("Prepared image/mask is corrupt or duplicates another view");
            var frame = frames[index]!.AsObject();
            var local = ViewText(frame, "file_path");
            if (Path.GetFileName(local) != local || local.Contains('\\') || local is "." or ".." || w.Relative(Path.GetDirectoryName(w.Resolve(transformsPath)) + "/" + local) != image)
                throw new InvalidOperationException("Native frame path does not identify the exact prepared image");
            if (!JsonNode.DeepEquals(frame["transform_matrix"], view["cameraToWorld"]) || frame["camera_angle_x"]?.GetValue<double>() != view["cameraAngleX"]?.GetValue<double>())
                throw new InvalidOperationException("Native frame camera differs from reviewed conditioning data");
            var fov = view["cameraAngleX"]!.GetValue<double>();
            if (!double.IsFinite(fov) || fov <= 0 || fov >= Math.PI) throw new InvalidOperationException("Invalid prepared horizontal FOV");
            var normalization = view["normalization"]!.AsObject();
            var expectedFov = MultiViewGeometry.PaddedFov(approved["cameraAngleX"]?.GetValue<double>() ?? dataset["camera"]!["cameraAngleX"]!.GetValue<double>(), normalization["width"]!.GetValue<int>(), normalization["canvasSide"]!.GetValue<int>());
            if (Math.Abs(expectedFov - fov) > 1e-10) throw new InvalidOperationException("Prepared FOV does not preserve the approved view's focal length");
            var matte = alpha.Inspect(w.Resolve(image));
            if (matte?.Suitable != true || matte.Width != matte.Height || side is not null && matte.Width != side)
                throw new InvalidOperationException("Prepared views must share a nonempty transparent square canvas");
            side = matte.Width;
        }
    }

    async Task ReconstructViews(Stage stage, CancellationToken cancellation)
    {
        RequireMultiViewToolchain();
        Models(stage);
        var dataset = w.Load<JsonObject>(Artifact("preprocess", "dataset"));
        ValidateMultiViewDataset(dataset);
        var submitted = stage.Attempt + "/submitted";
        Directory.CreateDirectory(w.Resolve(submitted));
        var frames = w.Load<JsonObject>(ViewText(dataset, "transforms"));
        var submittedViews = dataset.DeepClone().AsObject();
        for (var index = 0; index < 6; index++)
        {
            var view = submittedViews["views"]![index]!.AsObject();
            var file = ViewText(frames["frames"]![index]!.AsObject(), "file_path");
            var target = submitted + "/" + file;
            File.Copy(w.Resolve(ViewText(view, "image")), w.Resolve(target), false);
            if (Hash(target) != ViewText(view, "sha256")) throw new InvalidOperationException("Submitted image copy hash mismatch");
            view["image"] = target;
            stage.Artifacts["input-" + ViewText(view, "view")] = target;
        }
        var transforms = submitted + "/transforms.json";
        w.Save(transforms, frames);
        submittedViews["transforms"] = transforms;
        submittedViews["transformsSha256"] = Hash(transforms);
        w.Save(stage.Attempt + "/submitted-dataset.json", submittedViews);
        stage.Artifacts["submittedDataset"] = stage.Attempt + "/submitted-dataset.json";
        stage.Artifacts["submittedTransforms"] = transforms;
        var output = stage.Attempt + "/raw.glb";
        var arguments = Arguments("reconstruction", submitted, output, stage.Attempt);
        void RequireArgument(string flag, string value)
        {
            var index = Array.IndexOf(arguments, flag);
            if (arguments.Count(item => item == flag) != 1 || index < 0 || index + 1 >= arguments.Length || arguments[index + 1] != value)
                throw new InvalidOperationException("Six-view inference requires exact " + flag + " " + value);
        }
        RequireArgument("--views", w.Resolve(submitted));
        RequireArgument("--models", w.Resolve(Toolchain["modelDir"]!.GetValue<string>()));
        RequireArgument("--pixal3d-weights", "mv");
        RequireArgument("--num-views", "6");
        RequireArgument("--res", "1024");
        if (arguments.Contains("--sv-image") || arguments.Contains("--image") || !arguments.Contains("--require-gpu") || arguments.Last() != w.Resolve(output))
            throw new InvalidOperationException("Single-view/CPU fallback or substituted output cannot satisfy six-view production");
        if (arguments.Any(argument => argument is "--mesh-scale" or "--fov" or "--canonical-views" or "--sv-image" or "--image"))
            throw new InvalidOperationException("Native camera/input overrides cannot replace the approved six-view dataset");
        var before = frames.ToJsonString();
        var submittedHash = Hash(stage.Artifacts["submittedDataset"]);
        await RunEngine(stage, arguments, cancellation);
        ValidateArtifact(output);
        var gltf = ReadGlbJson(output);
        if (gltf["asset"]?["version"]?.GetValue<string>() != "2.0" || gltf["meshes"] is not JsonArray meshes || meshes.Count == 0 || !meshes.Any(mesh => mesh?["primitives"] is JsonArray primitives && primitives.Count > 0))
            throw new InvalidOperationException("Native reconstruction did not produce a GLB mesh");
        if (Hash(stage.Artifacts["submittedDataset"]) != submittedHash) throw new InvalidOperationException("Native process changed the submitted input receipt");
        if (w.Load<JsonObject>(transforms).ToJsonString() != before) throw new InvalidOperationException("Native process changed submitted camera data");
        foreach (var view in submittedViews["views"]!.AsArray().Select(node => node!.AsObject()))
            if (Hash(ViewText(view, "image")) != ViewText(view, "sha256")) throw new InvalidOperationException("Native process changed a submitted conditioning image");
        var receipt = stage.Attempt + "/reconstruction-inputs.json";
        w.Save(receipt, new JsonObject
        {
            ["schemaVersion"] = 1, ["mode"] = "multi-view", ["viewCount"] = 6,
            ["dataset"] = stage.Artifacts["submittedDataset"], ["datasetSha256"] = Hash(stage.Artifacts["submittedDataset"]),
            ["transformsSha256"] = Hash(transforms), ["views"] = submittedViews["views"]!.DeepClone(),
            ["engineExportFrame"] = "pixal3d-mv-export", ["output"] = output, ["outputSha256"] = Hash(output),
            ["upstreamValidationLimit"] = "MV upstream validates four views; this receipt proves submitted inputs, not anatomical or visual acceptance"
        });
        stage.Artifacts["inputReceipt"] = receipt;
        stage.Artifacts["glb"] = output;
    }
}
