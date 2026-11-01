"""Real v2 CLI/Blender integration with six synthetic original views.

Reconstruction, model bytes and human receipts are SIMULATIONS, not live
Pixal3D inference, accepted model terms or production human acceptance.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BLENDER = os.environ.get("BLENDER_EXE", "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe")
CLI = ROOT / "commands/lib/bubo-host-adapter.cjs"
VIEWS = ("front", "right", "back", "left", "top", "bottom")
DISTANCE = 3.1192049980163574
FOV = 0.3490658503988659


def cameras(distance=DISTANCE):
    return {
        "front": [[1, 0, 0, 0], [0, 0, -1, -distance], [0, 1, 0, 0], [0, 0, 0, 1]],
        "right": [[0, 0, -1, -distance], [-1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
        "back": [[-1, 0, 0, 0], [0, 0, 1, distance], [0, 1, 0, 0], [0, 0, 0, 1]],
        "left": [[0, 0, 1, distance], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
        "top": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, distance], [0, 0, 0, 1]],
        "bottom": [[1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, -distance], [0, 0, 0, 1]],
    }


def main():
    if not Path(BLENDER).is_file():
        raise SystemExit("BLOCKED: real Blender 4.5 unavailable; set BLENDER_EXE")
    if not CLI.is_file():
        raise SystemExit("BLOCKED: build the native PROOF_TO_MODEL CLI first")
    evidence = ROOT / ".hephaera/.cache/tasks/proof-multiview-classification/evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="native-integration-", dir=evidence))
    project = work / "project"
    project.mkdir()
    (project / "STYLE.md").write_bytes((ROOT / "STYLE.md").read_bytes())
    scripts = project / "runtime/bubo/resources/proof-to-model/blender"
    shutil.copytree(ROOT / "runtime/bubo/resources/proof-to-model/blender", scripts)
    logs = []
    assertions = 0

    def check(condition, reason):
        nonlocal assertions
        if not condition:
            raise AssertionError(reason)
        assertions += 1

    def command(args, success=True):
        result = subprocess.run([str(a) for a in args], cwd=project, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, encoding="utf-8", timeout=300)
        logs.append({"command": [str(a) for a in args], "exitCode": result.returncode,
                     "stdout": result.stdout, "stderr": result.stderr})
        (work / "commands.json").write_text(json.dumps(logs, indent=2), encoding="utf-8")
        if success and result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        if not success and not result.returncode:
            raise AssertionError("Unsafe/incomplete operation unexpectedly succeeded")
        return result

    fixture = project / "fixture.py"
    fixture.write_text('''import bpy, json, math
from pathlib import Path
from mathutils import Matrix
folder = Path(__file__).parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1)
obj = bpy.context.object
obj.name = "FixtureHull"
obj.dimensions = (0.7, 0.5, 1)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
colors = ((1,0.02,0.02,1),(0.02,1,0.02,1),(0.02,0.02,1,1),
          (1,1,0.02,1),(1,0.02,1,1),(0.02,1,1,1))
for index, color in enumerate(colors):
    material = bpy.data.materials.new("SyntheticFace" + str(index))
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Emission Color"].default_value = color
    shader.inputs["Emission Strength"].default_value = 1
    shader.inputs["Roughness"].default_value = 1
    obj.data.materials.append(material)
for polygon in obj.data.polygons:
    axis = max(range(3), key=lambda index: abs(polygon.normal[index]))
    polygon.material_index = axis * 2 + int(polygon.normal[axis] < 0)
# Simulate the pinned raw MV export frame; finishing must correct this once.
obj.rotation_euler.z = math.pi
bpy.ops.export_scene.gltf(filepath=str(folder / "fixture.glb"), export_format="GLB")
obj.rotation_euler.z = 0
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 8
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 256
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
scene.world = bpy.data.worlds.new("Synthetic source world")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.12,0.12,0.12,1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
camera_data = bpy.data.cameras.new("Independent synthetic camera")
camera = bpy.data.objects.new("Independent synthetic camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "PERSP"
camera_data.sensor_fit = "HORIZONTAL"
camera_data.lens = camera_data.sensor_width / (2 * math.tan(''' + repr(FOV) + ''' / 2))
for name, matrix in json.loads(''' + repr(json.dumps(cameras())) + ''').items():
    camera.matrix_world = Matrix(matrix)
    scene.render.filepath = str(folder / ("source-" + name + ".png"))
    bpy.ops.render.render(write_still=True)
''', encoding="utf-8")
    command([BLENDER, "--background", "--factory-startup", "--disable-autoexec",
             "--python-exit-code", "1", "--python", fixture])

    helper = project / "helper"
    helper.mkdir()
    (helper / "Engine.csproj").write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
        '<OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework>'
        '<ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>', encoding="utf-8")
    (helper / "Program.cs").write_text('''// SIMULATED process: reads six inputs; does not load a model or infer geometry.
using System.Text.Json.Nodes;
using System.Security.Cryptography;
string Need(string flag) {
    if (args.Count(value => value == flag) != 1) throw new Exception("Exactly one " + flag + " required");
    var index = Array.IndexOf(args, flag);
    if (index < 0 || index + 1 >= args.Length) throw new Exception("Missing value for " + flag);
    return args[index + 1];
}
if (Need("--pixal3d-weights") != "mv" || Need("--num-views") != "6" || Need("--res") != "1024"
    || args.Count(value => value == "--require-gpu") != 1 || args.Contains("--sv-image"))
    throw new Exception("Fixture requires the actual six-view invocation contract");
var directory = Path.GetFullPath(Need("--views"));
var modelDirectory = Path.GetFullPath(Need("--models"));
var transformsPath = Path.Combine(directory, "transforms.json");
var transformsBytes = File.ReadAllBytes(transformsPath);
var transforms = JsonNode.Parse(transformsBytes)!.AsObject();
var frames = transforms["frames"]!.AsArray();
if (frames.Count != 6) throw new Exception("Missing six actual submitted frames");
var consumed = new JsonArray();
var identities = new HashSet<string>();
foreach (var frame in frames) {
    var name = frame!["file_path"]!.GetValue<string>();
    if (Path.GetFileName(name) != name || name.Contains('/') || name.Contains('\\\\'))
        throw new Exception("Unconfined submitted frame");
    var path = Path.Combine(directory, name);
    var bytes = File.ReadAllBytes(path);
    if (bytes.Length < 32 || !bytes.AsSpan(0, 8).SequenceEqual(new byte[] {137,80,78,71,13,10,26,10}))
        throw new Exception("Submitted frame is not actual PNG bytes");
    var sha = Convert.ToHexStringLower(SHA256.HashData(bytes));
    if (!identities.Add(sha)) throw new Exception("Duplicated submitted view bytes");
    consumed.Add(new JsonObject { ["path"] = path, ["sha256"] = sha, ["bytes"] = bytes.Length,
        ["cameraAngleX"] = frame["camera_angle_x"]!.DeepClone(),
        ["cameraToWorld"] = frame["transform_matrix"]!.DeepClone() });
}
var models = Directory.GetFiles(modelDirectory, "*.gguf").Order().Select(path => new {
    name = Path.GetFileName(path), sha256 = Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(path)))
}).ToArray();
if (models.Length != 9) throw new Exception("Nine synthetic, explicitly non-model fixtures required");
var output = args.Last();
File.Copy("fixture.glb", output, false);
File.WriteAllText(Path.ChangeExtension(output, ".consumed.json"), new JsonObject {
    ["schemaVersion"] = 1, ["simulation"] = true, ["liveInference"] = false,
    ["viewCount"] = frames.Count, ["transformsSha256"] = Convert.ToHexStringLower(SHA256.HashData(transformsBytes)),
    ["views"] = consumed, ["modelCount"] = models.Length,
    ["arguments"] = new JsonArray(args.Select(value => JsonValue.Create(value)).ToArray())
}.ToJsonString());
''', encoding="utf-8")
    command(["dotnet", "build", helper / "Engine.csproj", "--nologo", "-o", helper / "out"])
    engine = helper / "out" / ("Engine.exe" if os.name == "nt" else "Engine")
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    (project / "rights.json").write_text(json.dumps({"authorized": True,
        "source": "Original synthetic engineering fixture", "license": "Original test content; no third-party model rights"}))
    recipe = {"targetFaces": 100, "textureSize": 32, "cageExtrusion": .1,
              "maxRayDistance": .3, "uvMargin": .02, "lodRatios": [.5, .25],
              "colliderMaxFaces": 1000, "maxTriangles": 5000, "maxMaterials": 6,
              "maxTextureBytes": 1000000, "parts": [], "riggingRequired": False,
              "animationRequired": False, "proofPreparation": {"maxSetRevisions": 4}}
    (project / "recipe.json").write_text(json.dumps(recipe))
    (project / "brief.json").write_text(json.dumps({
        "purpose": "Synthetic static engineering fixture; no production acceptance",
        "scale": {"units": "metres", "metersPerUnit": 1}, "interfaces": []}))
    model_directory = helper / "models"
    model_directory.mkdir()
    model_names = ("dinov3.gguf", "pixal3d_naf.gguf", "pixal3d_ss_flow_mv.gguf",
                   "pixal3d_shape_flow_512_mv.gguf", "pixal3d_shape_flow_1024_mv.gguf",
                   "pixal3d_tex_flow_1024_mv.gguf", "ss_dec.gguf", "shape_dec.gguf", "tex_dec.gguf")
    models = []
    for name in model_names:
        path = model_directory / name
        path.write_bytes(("GGUF-SYNTHETIC-NOT-A-REAL-MODEL:" + name).encode())
        models.append({"path": path.relative_to(project).as_posix(), "sha256": digest(path),
                       "license": "Original synthetic test bytes, not the named real model",
                       "licenseAccepted": True})
    toolchain = {"schemaVersion": 1, "engine": {"path": engine.relative_to(project).as_posix(),
        "sha256": digest(engine), "version": "SIMULATED-six-input-process", "commit": "fixture-only"},
        "blender": {"path": BLENDER, "version": "4.5"}, "models": models,
        "modelDir": model_directory.relative_to(project).as_posix(), "modelFamily": "mv", "viewCount": 6,
        "files": [], "limits": {"timeoutSeconds": 300, "maxAttempts": 4},
        "preprocessing": {"arguments": []},
        "reconstruction": {"arguments": ["--views", "{input}", "--models", "{modelDir}",
            "--pixal3d-weights", "mv", "--num-views", "6", "--res", "1024", "--seed", "42",
            "--require-gpu", "{output}"]}}
    (project / "toolchain.json").write_text(json.dumps(toolchain))
    (project / "sources.json").write_text(json.dumps({"schemaVersion": 1, "images": [
        {"id": "source-" + view, "path": "source-" + view + ".png"} for view in VIEWS]}))
    check(len({digest(project / ("source-" + view + ".png")) for view in VIEWS}) == 6,
          "The six independent fixture cameras must produce six distinct real PNGs")
    manifest = ".hephaera/.cache/tasks/test/proof-to-model/fixture/v1/manifest.json"

    def cli(stage, *args, success=True):
        return command(["node", CLI, "proof-to-model", stage, "--root", project, "--manifest", manifest,
                        *args], success=success)

    def state():
        return json.loads((project / manifest).read_text(encoding="utf-8"))

    cli("init", "--task", "test", "--asset", "fixture", "--version", "v1",
        "--sources", "sources.json", "--rights", "rights.json", "--recipe", "recipe.json",
        "--brief", "brief.json", "--toolchain", "toolchain.json", "--actor", "fixture-builder")
    current = state()
    check(current["schemaVersion"] == 2, "Default init must select v2, not diagnostic mode")
    source_set = json.loads((project / current["sourceSet"]).read_text())
    check(len(source_set["images"]) == 6, "All six immutable originals must be registered")
    cli("reconstruct", success=False)
    source_ids = [image["id"] for image in source_set["images"]]
    classification = {"schemaVersion": 1, "sourceSetHash": digest(project / current["sourceSet"]),
        "sources": [{"sourceId": image["id"], "sha256": image["sha256"]} for image in source_set["images"]],
        "sourceViews": [{"sourceId": image["id"], "view": view, "usable": True,
                         "reason": "Controlled synthetic canonical camera; no inferred source calibration"}
                        for view, image in zip(VIEWS, source_set["images"])],
        "researchStatus": "not-required", "researchReason": "Original known geometric fixture; no anatomy or real source research claim.",
        "research": [], "subjects": [{"id": "fixture", "kind": "nonliving", "classification": "Synthetic six-color box",
            "sourceIds": source_ids, "claims": [{"id": "shape", "description": "Known test box with six different material faces",
                "sourceIds": source_ids, "confidence": "high", "disposition": "observed"}],
            "parts": [{"id": "body", "name": "Fixture body", "visibility": "visible", "disposition": "observed",
                       "sourceIds": source_ids, "claimIds": ["shape"]}]}],
        "relations": [], "unknowns": [], "conflicts": [],
        "preservationConstraints": ["Preserve fixture identity and side-specific colors"],
        "prohibitedSubstitutions": ["Do not claim this proves anatomical classification or live inference"]}
    (project / "classification.json").write_text(json.dumps(classification))
    cli("classify", "--classification", "classification.json")
    current = state()
    proof_plan = json.loads((project / current["stages"]["classify"]["artifacts"]["proof-plan"]).read_text())
    check(proof_plan["minimumGeneratedViews"] == 0 and proof_plan["generationExecution"] is False,
          "Six usable synthetic originals must require no generation")
    proof_set = {"schemaVersion": 1, "revision": 1,
        "sourceSetHash": digest(project / current["sourceSet"]), "classificationHash": digest(project / current["classification"]),
        "camera": {"convention": "blender-nerf-z-up", "calibration": "nominal-prescribed",
                   "meshScale": 1, "cameraAngleX": FOV, "distance": DISTANCE},
        "views": [{"view": view, "image": image["path"], "sha256": image["sha256"],
                   "origin": "source", "sourceIds": [image["id"]], "revision": 1,
                   "cameraToWorld": cameras()[view]} for view, image in zip(VIEWS, source_set["images"])]}
    (project / "proofs.json").write_text(json.dumps(proof_set))
    cli("prepare-proofs", "--proof-set", "proofs.json")
    cli("preprocess", success=False)

    def record(kind, reviewer, human):
        status = json.loads(cli("status").stdout)
        key = "proofSet" if kind == "proof-set" else kind
        fingerprint = status.get("approvalFingerprints", {}).get(key)
        check(bool(fingerprint), "status must expose the current approval fingerprint: " + key)
        receipt = f".hephaera/.cache/tasks/test/reviews/{kind}.json"
        (project / receipt).parent.mkdir(parents=True, exist_ok=True)
        (project / receipt).write_text(json.dumps({"kind": kind, "reviewer": reviewer,
            "decision": "approved", "fingerprint": fingerprint, "human": human,
            "reason": "SYNTHETIC TEST APPROVAL; not a real human or production decision"}))
        cli("record", "--kind", kind, "--reviewer", reviewer, "--evidence", receipt)

    record("proof-set", "fixture-proof-owner", True)
    cli("preprocess")
    current = state()
    prepared = json.loads((project / current["stages"]["preprocess"]["artifacts"]["dataset"]).read_text())
    check(len(prepared["views"]) == 6, "Preprocessing must retain all six actual views")
    check(all("mask-" + view in current["stages"]["preprocess"]["artifacts"] for view in VIEWS),
          "All six matte masks must be retained")
    record("preprocessing", "fixture-technical-reviewer", False)

    def reject_tampering(path, changed_bytes, reason):
        original = path.read_bytes()
        try:
            path.write_bytes(changed_bytes)
            cli("reconstruct", success=False)
            check(not list(project.glob(".art-staging/**/raw.consumed.json")), reason + ": must fail before process execution")
        finally:
            path.write_bytes(original)

    prepared_path = project / prepared["views"][2]["image"]
    reject_tampering(prepared_path, prepared_path.read_bytes() + b"tampered-frame", "Stale prepared pixels")
    transform_path = project / prepared["transforms"]
    camera_data = json.loads(transform_path.read_text())
    camera_data["frames"][5]["transform_matrix"][0][0] = -1
    reject_tampering(transform_path, json.dumps(camera_data).encode(), "Stale/flipped camera")
    original_path = project / source_set["images"][4]["path"]
    reject_tampering(original_path, original_path.read_bytes() + b"tampered-original", "Stale original evidence")

    cli("reconstruct")
    current = state()
    reconstruction = current["stages"]["reconstruct"]
    raw = project / reconstruction["artifacts"]["glb"]
    consumed = json.loads(raw.with_suffix(".consumed.json").read_text())
    input_receipt = json.loads((project / reconstruction["artifacts"]["inputReceipt"]).read_text())
    check(consumed["simulation"] is True and consumed["liveInference"] is False, "Process witness must remain labeled simulation")
    check(consumed["viewCount"] == input_receipt["viewCount"] == 6, "Process must actually read all six submitted views")
    check(consumed["modelCount"] == 9, "Fixture process must inspect the nine explicitly fake model identities")
    check(consumed["transformsSha256"] == input_receipt["transformsSha256"], "Process must read the exact submitted camera bytes")
    check(len({view["sha256"] for view in consumed["views"]}) == 6, "Six process-read PNG identities must be distinct")
    for actual, expected in zip(consumed["views"], input_receipt["views"]):
        check(Path(actual["path"]).resolve() == (project / expected["image"]).resolve(), "Process input path must match submitted receipt")
        check(actual["sha256"] == expected["sha256"] == digest(project / expected["image"]), "Process-read bytes must match actual retained input")
        check(actual["cameraToWorld"] == expected["cameraToWorld"], "Process-read camera must match approved orientation")
        check(actual["cameraAngleX"] == expected["cameraAngleX"], "Process-read FOV must match normalized camera")
    cli("finish")
    current = state()
    finished = json.loads((project / current["stages"]["finish"]["artifacts"]["result"]).read_text())
    correction = [stage for stage in finished["stages"] if stage["stage"] == "engineExportToProofFrame"]
    check(len(correction) == 1, "Actual Blender finishing must record exactly one engine-to-proof correction")
    check(correction[0]["inputFrame"] == "pixal3d-mv-export", "Correction must identify the real raw-frame contract")
    cli("review")
    current = state()
    reviewed = json.loads((project / current["stages"]["review"]["artifacts"]["result"]).read_text())
    check(reviewed["mode"] == "multi-view" and reviewed["measurements"]["views"] == 6, "Actual Blender review must render six production cameras")
    check(reviewed["alignment"]["inputFrame"] == "hephaera-proof-z-up", "Finished review must not apply raw correction twice")
    check(reviewed["alignment"]["engineExportToProofFrame"] == [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],
          "Already corrected finished geometry must use identity frame mapping")
    check(len([name for name in reviewed["artifacts"] if name.startswith("original-")]) == 6, "Review must show all six original source fixtures")
    check(all(view in reviewed["artifacts"] and "approved-" + view in reviewed["artifacts"]
              and "conditioning-" + view in reviewed["artifacts"] for view in VIEWS),
          "All six original/approved/conditioning/render comparisons must exist")
    check(reviewed["humanApproval"] == reviewed["independentReview"] == "pending", "Rendering cannot manufacture real approval")
    for path, expected in reviewed["outputHashes"].items():
        check(digest(project / path) == expected, "Every rendered/copied comparison artifact must match its receipt")

    cli("promote", "--destination", "assets/models/not-approved", success=False)
    record("independent", "fixture-reviewer", False)
    record("human", "fixture-runtime-owner", True)
    cli("validate")
    cli("promote", "--destination", "assets/models/synthetic-test-only")
    check((project / "assets/models/synthetic-test-only/asset.glb").is_file(), "Only the fixture project receives its explicitly synthetic promotion")
    current = state()
    exported = project / current["stages"]["finish"]["artifacts"]["glb"]
    with exported.open("ab") as stream:
        stream.write(b"tampered")
    cli("validate", success=False)
    print(f"PASS: {assertions} v2 CLI/real Blender assertions; all six process-read inputs, review cameras, approval gates and stale evidence checked")
    print("SIMULATED reconstruction, fake model bytes and synthetic approval receipts; no live Pixal3D inference or production acceptance.")
    print("Evidence:", work)
    (work / "verification.json").write_text(json.dumps({"schemaVersion": 1, "status": "pass",
        "assertions": assertions, "realBlender": True, "viewCount": 6, "liveInference": False,
        "modelBytes": "synthetic-non-models", "humanApprovals": "synthetic-test-only"}, indent=2))


if __name__ == "__main__":
    main()
