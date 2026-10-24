"""Real CLI-to-Blender integration; reconstruction and approval receipts are synthetic fixtures.

This does not prove live Pixal3D inference, model rights, or production human approval.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
BLENDER = os.environ.get("BLENDER_EXE", "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe")
CLI = Path(os.environ.get("PROOF_TO_MODEL_DLL", str(
    ROOT / "commands/lib/proof-to-model/bin/Debug/net10.0/ProofToModel.dll")))


def main():
    if not Path(BLENDER).is_file():
        raise SystemExit("BLOCKED: real Blender 4.5 unavailable; set BLENDER_EXE")
    evidence = ROOT / ".opencaw/.cache/tasks/proof-to-model/evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="native-integration-", dir=evidence))
    project = work / "project"
    project.mkdir()
    (project / "STYLE.md").write_bytes((ROOT / "STYLE.md").read_bytes())
    scripts = project / ".styles/.pipelines/proof-to-model/blender"
    shutil.copytree(ROOT / ".styles/.pipelines/proof-to-model/blender", scripts)
    logs = []

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
    fixture.write_text('''import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3)
obj=bpy.context.object
obj.name="FixtureHull"
mat=bpy.data.materials.new("FixtureMaterial")
mat.use_nodes=True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=(0.7,0.2,0.05,1)
obj.data.materials.append(mat)
bpy.ops.export_scene.gltf(filepath="fixture.glb",export_format="GLB")
''', encoding="utf-8")
    command([BLENDER, "--background", "--factory-startup", "--disable-autoexec",
             "--python-exit-code", "1", "--python", fixture])

    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data))
    pixels = b"".join(b"\0" + bytes(v for x in range(32) for v in
                                      (180, 50, 10, 255 if 4 < x < 27 and 4 < y < 27 else 0))
                      for y in range(32))
    (project / "proof.png").write_bytes(b"\x89PNG\r\n\x1a\n" +
        chunk(b"IHDR", struct.pack(">IIBBBBB", 32, 32, 8, 6, 0, 0, 0)) +
        chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))

    helper = project / "helper"
    helper.mkdir()
    (helper / "Engine.csproj").write_text('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup>'
        '<OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework>'
        '<ImplicitUsings>enable</ImplicitUsings></PropertyGroup></Project>', encoding="utf-8")
    (helper / "Program.cs").write_text('''// Simulated reconstruction process for integration tests only.
var output = args[1];
File.Copy("fixture.glb", output, false);
var views = Path.ChangeExtension(output, null) + ".svviews";
Directory.CreateDirectory(views);
File.Copy(args[0], Path.Combine(views, "input.png"));
File.WriteAllText(Path.Combine(views, "transforms.json"), "{\\"fixture\\":true,\\"frames\\":[]}");
''', encoding="utf-8")
    command(["dotnet", "build", helper / "Engine.csproj", "--nologo", "-o", helper / "out"])
    engine = helper / "out" / ("Engine.exe" if os.name == "nt" else "Engine")
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    (project / "rights.json").write_text(json.dumps({"authorized": True,
        "source": "synthetic engineering fixture", "license": "original test fixture"}))
    recipe = {"targetFaces": 100, "textureSize": 32, "cageExtrusion": .1,
              "maxRayDistance": .3, "uvMargin": .02, "lodRatios": [.5, .25],
              "colliderMaxFaces": 1000, "maxTriangles": 5000, "maxMaterials": 3,
              "maxTextureBytes": 1000000, "parts": [], "riggingRequired": False,
              "animationRequired": False}
    (project / "recipe.json").write_text(json.dumps(recipe))
    (project / "brief.json").write_text(json.dumps({
        "purpose": "Synthetic static engineering fixture",
        "scale": {"units": "metres", "metersPerUnit": 1}, "interfaces": []}))
    toolchain = {"schemaVersion": 1, "engine": {"path": engine.relative_to(project).as_posix(),
        "sha256": digest(engine), "version": "synthetic-test-engine", "commit": "fixture"},
        "blender": {"path": BLENDER, "version": "4.5"}, "models": [],
        "modelDir": "helper", "files": [], "limits": {"timeoutSeconds": 300},
        "preprocessing": {"arguments": []},
        "reconstruction": {"arguments": ["{input}", "{output}"]}}
    (project / "toolchain.json").write_text(json.dumps(toolchain))
    manifest = ".opencaw/.cache/tasks/test/proof-to-model/fixture/v1/manifest.json"

    def cli(stage, *args, success=True):
        return command(["dotnet", CLI, stage, "--root", project, "--manifest", manifest,
                        *args], success=success)

    cli("init", "--task", "test", "--asset", "fixture", "--version", "v1",
        "--proof", "proof.png", "--rights", "rights.json", "--recipe", "recipe.json",
        "--brief", "brief.json",
        "--toolchain", "toolchain.json", "--actor", "fixture-builder")
    cli("reconstruct", success=False)

    def record(kind, reviewer, human):
        status = json.loads(cli("status").stdout)
        fingerprints = status.get("approvalFingerprints", {})
        fingerprint = fingerprints.get(kind)
        if not fingerprint:
            failure = cli("record", "--kind", kind, "--reviewer", reviewer,
                          "--evidence", "missing.json", success=False)
            raise AssertionError("status must expose approvalFingerprints: " + failure.stderr)
        receipt = f".opencaw/.cache/tasks/test/reviews/{kind}.json"
        (project / receipt).parent.mkdir(parents=True, exist_ok=True)
        (project / receipt).write_text(json.dumps({"kind": kind, "reviewer": reviewer,
            "decision": "approved", "fingerprint": fingerprint, "human": human,
            "reason": "SYNTHETIC TEST APPROVAL; not a real human or production decision"}))
        cli("record", "--kind", kind, "--reviewer", reviewer, "--evidence", receipt)

    record("proof", "fixture-proof-owner", True)
    cli("preprocess")
    record("preprocessing", "fixture-technical-reviewer", False)
    for stage in ("reconstruct", "finish", "review"):
        cli(stage)
    cli("promote", "--destination", "assets/models/not-approved", success=False)
    record("independent", "fixture-reviewer", False)
    record("human", "fixture-runtime-owner", True)
    cli("validate")
    cli("promote", "--destination", "assets/models/synthetic-test-only")
    assert (project / "assets/models/synthetic-test-only/asset.glb").is_file()
    current = json.loads((project / manifest).read_text())
    exported = project / current["stages"]["finish"]["artifacts"]["glb"]
    with exported.open("ab") as stream:
        stream.write(b"tampered")
    cli("validate", success=False)
    print("PASS: real native CLI -> Blender finish/review/reimport, approval gates and stale-output rejection")
    print("Reconstruction and approval identities were simulated fixtures, not live inference/acceptance.")
    print("Evidence:", work)


if __name__ == "__main__":
    main()
