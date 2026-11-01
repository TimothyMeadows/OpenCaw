"""Actual model-to-animation CLI/Blender integration on original fixtures.

Human receipts are explicitly synthetic test assertions. Browser results, when
available, use real Three.js and an existing browser; this test installs nothing.
"""
from pathlib import Path
import copy
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
TASK = ROOT / ".hephaera/.cache/tasks/model-to-animation-design"
BLENDER = os.environ.get("BLENDER_EXE") or shutil.which("blender") or "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"
CLI = ROOT / "commands/lib/bubo-host-adapter.cjs"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if not Path(BLENDER).is_file() or not CLI.is_file():
        raise SystemExit("BLOCKED: build the native motion CLI and configure existing Blender4.5; no installation attempted")
    evidence = TASK / "evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    # Keep nested review frame paths within the installed Blender's Windows
    # filesystem limits without changing OS settings or losing task ancestry.
    work = Path(tempfile.mkdtemp(prefix="m-", dir=evidence))
    project = work / "p"
    project.mkdir()
    calls = []
    passed = 0

    def check(condition, reason):
        nonlocal passed
        if not condition:
            raise AssertionError(reason)
        passed += 1
        print("PASS:", reason, flush=True)

    def invoke(args, name, expected=True):
        run = subprocess.run([str(item) for item in args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
        log = work / (str(len(calls)).zfill(3) + "-" + name + ".log")
        log.write_bytes(run.stdout + b"\nSTDERR:\n" + run.stderr)
        calls.append({"args": [str(item) for item in args], "exitCode": run.returncode, "log": str(log.relative_to(ROOT))})
        (work / "commands.json").write_text(json.dumps(calls, indent=2) + "\n", encoding="utf-8")
        if (run.returncode == 0) != expected:
            raise AssertionError(name + " unexpected exit " + str(run.returncode) + "\n" + log.read_text(encoding="utf-8", errors="replace")[-6000:])
        return run

    def write(relative, value):
        path = project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        return relative

    def command(operation, manifest=None, *args, expected=True):
        values = ["node", CLI, "model-to-animation", operation, "--root", project]
        if manifest:
            values += ["--manifest", manifest]
        values += args
        return invoke(values, operation, expected)

    def state(manifest):
        return json.loads((project / manifest).read_text(encoding="utf-8"))

    def artifact(manifest, stage, key):
        return state(manifest)["stages"][stage]["artifacts"][key]

    def status(manifest):
        return json.loads(command("status", manifest).stdout)

    def approve(manifest, kind, runtime=None):
        current = status(manifest)
        receipt = {"kind": kind, "reviewer": "fixture-independent" if kind == "independent" else "fixture-human",
                   "decision": "approved", "reason": "SYNTHETIC CONTROLLED TEST ASSERTION; not real production human acceptance",
                   "human": True, "fingerprint": current["approvalFingerprints"][kind]}
        if runtime is not None:
            receipt["runtime"] = runtime
        relative = ".hephaera/.cache/tasks/fixture/reviews/" + state(manifest)["asset"] + "-" + kind + ".json"
        write(relative, receipt)
        command("record", manifest, "--kind", kind, "--reviewer", receipt["reviewer"], "--evidence", relative)

    (project / "STYLE.md").write_bytes((ROOT / "STYLE.md").read_bytes())
    invoke(["node", ROOT / "commands/lib/engine-contract.cjs", "generate", project, "--inline", "THREEJS"], "engine-contract")
    write("rights.json", {"authorized": True, "provider": "owned", "license": "Original controlled fixture", "notes": "No Adobe dependencies or external artwork used"})
    invoke([BLENDER, "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python",
            ROOT / "tests/fixtures/model-animation/create_assets.py", "--", "--output", project / "inputs"], "original-fixtures")
    fixtures = {}

    def initialize(name, source_name=None, recipe=None, rights="rights.json"):
        source_name = source_name or name
        if recipe is not None:
            recipe_path = write("inputs/" + name + "-recipe.json", recipe)
        else:
            recipe_path = "inputs/" + source_name + "-recipe.json"
        command("init", None, "--task", "fixture", "--asset", name, "--version", "v1", "--actor", "fixture-builder",
                "--model", "inputs/" + source_name + ".glb", "--rights", rights, "--recipe", recipe_path, "--blender", BLENDER)
        return ".hephaera/.cache/tasks/fixture/model-to-animation/" + name + "/v1/manifest.json"

    # Actual provider exclusion and profile selection are checked before production.
    write("excluded-rights.json", {"authorized": True, "provider": "Adobe", "license": "unsupported test input"})
    command("init", None, "--task", "fixture", "--asset", "excluded", "--version", "v1", "--actor", "fixture-builder",
            "--model", "inputs/humanoid.glb", "--rights", "excluded-rights.json", "--recipe", "inputs/humanoid-recipe.json", "--blender", BLENDER, expected=False)
    check(not (project / ".art-staging/model-to-animation/excluded").exists(), "excluded provider creates no production staging")

    extraction_recipe = json.loads((project / "inputs/humanoid-recipe.json").read_text())
    extraction_run = next(clip for clip in extraction_recipe["clips"] if clip["id"] == "run")
    extraction_run["rootMotion"] = "extract"
    extraction_run["channels"].append({"target": {"bone": "root"}, "property": "location",
                                      "keyframes": [[0, [0, 0, 0]], [3, [0, 0, .5]], [6, [0, 0, 1]]]})
    for name in ("humanoid", "ship", "car", "humanoid-extract"):
        source_name = "humanoid" if name == "humanoid-extract" else name
        manifest = initialize(name, source_name, extraction_recipe if name == "humanoid-extract" else None)
        fixtures[name] = manifest
        before = sha(project / ("inputs/" + source_name + ".glb"))
        for stage in ("inspect", "prepare", "rig"):
            command(stage, manifest)
        command("author", manifest, expected=False)
        check("motion" not in state(manifest)["stages"], name + " requires rig/hierarchy approval before motion authoring")
        approve(manifest, "rig")
        for stage in ("author", "bake", "export", "review"):
            command(stage, manifest)
        command("validate", manifest)
        package = json.loads((project / artifact(manifest, "export", "package")).read_text())
        check(package["profile"] == {"humanoid": "skinned", "humanoid-extract": "skinned", "ship": "rigid", "car": "articulated"}[name], name + " retains its actual motion profile")
        check(package["engine"]["effectiveEngine"] == "THREEJS", name + " package consumes canonical engine selection")
        check(sha(project / ("inputs/" + source_name + ".glb")) == before, name + " leaves original geometry immutable")
        check(len(package["clips"]) == len(package["states"]), name + " exports actual declared motion set")
        for key in ("model", "source"):
            check(sha(project / package[key]["path"]) == package[key]["sha256"], name + " binds exact exported " + key + " bytes")
        report = json.loads((project / artifact(manifest, "review", "reviewReport")).read_text())
        check(report["frameCount"] == report["requestedFrameCount"] and report["frameCount"] > 1, name + " retains full-range native motion proofs")
        check(report["humanApproval"] == "pending" and package["verification"]["status"] == "pending", name + " native output does not manufacture acceptance")
        if name == "humanoid-extract":
            actual_run = next(clip for clip in package["clips"] if clip["id"] == "run")
            check(package["rig"]["rootBone"] == "root" and sum(abs(value) for value in actual_run["rootDisplacement"]) > .5,
                  "actual skinned extraction exports root identity and measured runtime displacement")
        command("promote", manifest, "--destination", "assets/models/" + name, expected=False)
        check(not (project / ("assets/models/" + name)).exists(), name + " cannot promote before motion/independent/runtime acceptance")

    human = fixtures["humanoid"]
    old_package = json.loads((project / artifact(human, "export", "package")).read_text())
    old_hashes = {item["id"]: item["motionSha256"] for item in old_package["clips"]}
    old_rig = status(human)["approvalFingerprints"]["rig"]
    old_motion_attempt = state(human)["stages"]["motion"]["attempt"]
    recipe = json.loads((project / "inputs/humanoid-recipe.json").read_text())
    replacement = copy.deepcopy(next(clip for clip in recipe["clips"] if clip["id"] == "run"))
    channel = next(item for item in replacement["channels"] if item["property"] == "rotation_quaternion")
    channel["keyframes"][1][1] = [math.sin(.42 / 2), 0, 0, math.cos(.42 / 2)]
    revision = write("inputs/run-revision.json", {"schemaVersion": 1, "clip": "run", "replacement": replacement, "reason": "Controlled one-clip revision fixture"})
    approve(human, "motion")
    command("author", human, "--revision", revision)
    check(status(human)["approvalFingerprints"]["rig"] == old_rig and any(item["kind"] == "rig" for item in state(human)["approvals"]), "one-clip revision preserves current rig acceptance")
    check(not any(item["kind"] == "motion" for item in state(human)["approvals"]), "one-clip revision invalidates complete motion acceptance")
    check((project / old_motion_attempt).is_dir(), "one-clip revision preserves prior immutable attempt")
    for stage in ("bake", "export", "review"):
        command(stage, human)
    revised_package = json.loads((project / artifact(human, "export", "package")).read_text())
    revised_hashes = {item["id"]: item["motionSha256"] for item in revised_package["clips"]}
    check(revised_hashes["run"] != old_hashes["run"], "targeted clip changes actual sampled motion identity")
    check(all(value == revised_hashes[key] for key, value in old_hashes.items() if key != "run"), "all eight unaffected clips preserve actual sampled motion identity")

    # Exercise the public retarget transport with actual source GLB and bone mapping.
    retarget = initialize("retarget-human", "humanoid")
    for stage in ("inspect", "prepare", "rig"):
        command(stage, retarget)
    approve(retarget, "rig")
    mapping = {"schemaVersion": 1, "provider": "owned", "rights": {"authorized": True, "license": "Original fixture motions"}, "rootTranslationScale": 1,
               "bones": [{"source": bone["name"], "target": bone["name"], "rotationOffset": [0, 0, 0, 1]} for bone in recipe["rig"]["bones"]],
               "clips": [{"id": clip["id"], "sourceClip": clip["id"]} for clip in recipe["clips"]]}
    map_path = write("inputs/mapping.json", mapping)
    command("retarget", retarget, "--motion-source", artifact(human, "export", "glb"), "--mapping", map_path)
    for stage in ("bake", "export", "review"):
        command(stage, retarget)
    retarget_package = json.loads((project / artifact(retarget, "export", "package")).read_text())
    check(len(retarget_package["clips"]) == 9, "public retarget path exports nine actual mapped motions")
    check(state(retarget)["stages"]["motion"]["operation"] == "retarget", "actual retarget lineage stays distinct from native authoring")

    # Actual failed Blender invocation cannot turn into a completed report.
    broken_recipe = json.loads((project / "inputs/car-recipe.json").read_text())
    broken_recipe["parts"][1]["node"] = "MissingIndependentWheel"
    broken = initialize("broken-car", "car", broken_recipe)
    command("inspect", broken, expected=False)
    check(state(broken)["stages"]["inspect"]["status"] == "failed", "actual missing-part Blender process records failure")
    check(not (project / state(broken)["stages"]["inspect"]["attempt"] / "result.json").exists(), "actual failed Blender stage leaves no passing-looking result")

    # Stale engine/source evidence fails without new stage production.
    engine_path = project / "ENGINE.md"
    engine_bytes = engine_path.read_bytes()
    invoke(["node", ROOT / "commands/lib/engine-contract.cjs", "generate", project, "--inline", "UNITY"], "changed-engine-contract")
    before_history = len(state(human)["history"])
    command("validate", human, expected=False)
    check(len(state(human)["history"]) == before_history, "changed engine fails before motion state writes or Blender launch")
    engine_path.write_bytes(engine_bytes)
    original = project / "inputs/humanoid.glb"
    original_bytes = original.read_bytes()
    original.write_bytes(original_bytes + b"changed")
    command("validate", human, expected=False)
    original.write_bytes(original_bytes)
    command("validate", human)
    check(True, "changed original source is rejected and exact byte restoration restores freshness")

    packages = [str(project / artifact(fixtures[name], "export", "package")) for name in ("humanoid", "ship", "car", "humanoid-extract")]
    browser_output = project / ".hephaera/.cache/tasks/fixture/engine"
    browser_args = [sys.executable, ROOT / "tests/test-model-animation-engine.py", "--project-root", project, "--output", browser_output]
    for package in packages:
        browser_args += ["--package", package]
    browser = subprocess.run([str(value) for value in browser_args], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    (work / "engine-bridge.log").write_bytes(browser.stdout)
    actual_browser = browser.returncode == 0
    if browser.returncode not in (0, 77):
        raise AssertionError(browser.stdout.decode(errors="replace")[-7000:])
    if browser.returncode == 77 and os.environ.get("HEPHAERA_REQUIRE_MOTION_BROWSER") == "1":
        raise AssertionError("Required actual browser acceptance is blocked; see engine-bridge.log")
    if actual_browser:
        observed = json.loads((browser_output / "engine-evidence.json").read_text())
        check(observed["status"] == "passed", "actual browser motion/effects evidence passes")
        ship = fixtures["ship"]
        for kind in ("motion", "independent"):
            approve(ship, kind)
        package_path = project / artifact(ship, "export", "package")
        package = json.loads(package_path.read_text())
        evidence_items = []
        for index, item in enumerate(observed["evidence"]):
            source = Path(item["path"])
            if not source.is_absolute():
                source = (project if observed.get("pathBase") == "project-root" else ROOT) / source
            relative = ".hephaera/.cache/tasks/fixture/runtime/" + str(index) + source.suffix
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            check(sha(target) == item["sha256"], "copied actual " + item["kind"] + " evidence retains its exact hash")
            evidence_items.append({"kind": item["kind"], "path": relative, "sha256": sha(target)})
        approve(ship, "human", {"status": "passed", "engine": "THREEJS", "modelSha256": package["model"]["sha256"], "packageSha256": sha(package_path), "evidence": evidence_items})
        command("promote", ship, "--destination", "assets/models/fixture-ship")
        promoted = json.loads((project / "assets/models/fixture-ship/motion-package.json").read_text())
        check(promoted["model"]["path"] == "assets/models/fixture-ship/model.glb" and promoted["source"]["path"] == "assets/models/fixture-ship/source.blend", "fixture promotion explicitly rebinds model and editable-source paths")
        check(sha(project / promoted["model"]["path"]) == promoted["model"]["sha256"], "fixture promotion preserves actual model bytes")
        command("promote", ship, "--destination", "assets/models/fixture-ship", expected=False)
        check(True, "fixture promotion cannot overwrite an accepted destination")
    else:
        print("BLOCKED: actual browser prerequisites unavailable; no automatic install or runtime approval fabricated", flush=True)

    verdict = {"schemaVersion": 1, "status": "pass", "assertions": passed, "realBlender": True, "realCli": True, "actualBrowser": actual_browser,
               "humanApprovals": "synthetic-test-only", "productionPromotion": False, "modelWeights": "none", "fixtures": fixtures}
    (work / "verification.json").write_text(json.dumps(verdict, indent=2) + "\n", encoding="utf-8")
    (evidence / "native-motion-latest.txt").write_text(str(work) + "\n", encoding="utf-8")
    print("PASS:", passed, "actual native motion CLI/Blender assertions; actual browser:", actual_browser)
    print("SYNTHETIC human assertions and controlled fixture promotion; no production acceptance or external assets.")
    print("Evidence:", work)


if __name__ == "__main__":
    main()
