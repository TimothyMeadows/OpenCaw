"""Real Blender integration, with an explicitly synthetic engineering fixture."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / ".styles/.pipelines/proof-to-model/blender"
import shutil
BLENDER = os.environ.get("BLENDER_EXE") or shutil.which("blender") or r"C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"


class BlenderProduction(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(BLENDER).is_file():
            raise unittest.SkipTest("Blender 4.5 executable unavailable; set BLENDER_EXE")
        evidence = ROOT / ".opencaw/.cache/tasks/proof-to-model/evidence"
        evidence.mkdir(parents=True, exist_ok=True)
        cls.work = Path(tempfile.mkdtemp(prefix="lane-blender-", dir=evidence))
        cls.recipe = {"targetFaces": 100, "textureSize": 32, "cageExtrusion": 0.1,
                      "maxRayDistance": 0.3, "uvMargin": 0.02, "lodRatios": [0.5, 0.25],
                      "colliderMaxFaces": 1000, "maxTriangles": 5000, "maxMaterials": 3,
                      "maxTextureBytes": 1000000, "parts": [], "riggingRequired": False,
                      "animationRequired": False}
        fixture = cls.work / "fixture.py"
        fixture.write_text('''import bpy
from pathlib import Path
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1)
obj = bpy.context.object
obj.name = "Hull"
material = bpy.data.materials.new("SyntheticEngineeringMaterial")
material.use_nodes = True
shader = material.node_tree.nodes.get("Principled BSDF")
shader.inputs["Base Color"].default_value = (0.65, 0.16, 0.05, 1)
shader.inputs["Roughness"].default_value = 0.45
shader.inputs["Metallic"].default_value = 0.2
obj.data.materials.append(material)
folder = Path(__file__).parent
bpy.ops.export_scene.gltf(filepath=str(folder / "synthetic.glb"), export_format="GLB")
image = bpy.data.images.new("Synthetic proof fixture", 32, 32)
image.generated_color = (0.65, 0.16, 0.05, 1)
image.filepath_raw = str(folder / "synthetic-proof.png")
image.file_format = "PNG"
image.save()
green = material.copy()
green.name = "SecondSourceMaterial"
green.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.05, 0.65, 0.16, 1)
obj.data.materials.append(green)
for polygon in obj.data.polygons:
    polygon.material_index = polygon.index % 2
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.5, location=(3, 0, 0))
satellite = bpy.context.object
satellite.name = "Satellite"
satellite.data.materials.append(green)
parent = bpy.data.objects.new("TransformedSourceHierarchy", None)
bpy.context.collection.objects.link(parent)
obj.parent = parent
satellite.parent = parent
parent.location = (3, 1, 2)
bpy.ops.export_scene.gltf(filepath=str(folder / "synthetic-multipart.glb"), export_format="GLB")
for other in list(bpy.context.scene.objects):
    if other != obj:
        bpy.data.objects.remove(other, do_unlink=True)
obj.parent = None
obj.location = (0, 0, 0)
bpy.ops.object.armature_add()
rig = bpy.context.object
rig.name = "GuidedFixtureRig"
group = obj.vertex_groups.new(name="Bone")
group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
modifier = obj.modifiers.new("Guided deformation", "ARMATURE")
modifier.object = rig
obj.parent = rig
bpy.ops.export_scene.gltf(filepath=str(folder / "synthetic-rig-only.glb"), export_format="GLB", export_animations=False)
bone = rig.pose.bones["Bone"]
bone.rotation_mode = "XYZ"
bone.rotation_euler[0] = 0
bone.keyframe_insert("rotation_euler", frame=1)
bone.rotation_euler[0] = 1.2
bone.keyframe_insert("rotation_euler", frame=25)
rig.animation_data.action.name = "GuidedFixtureMotion"
bpy.ops.export_scene.gltf(filepath=str(folder / "synthetic-guided.glb"), export_format="GLB", export_animations=True)
''', encoding="utf-8")
        cls.run_blender(fixture, None, "fixture")

    @classmethod
    def run_blender(cls, script, job, name, success=True):
        command = [BLENDER, "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python", str(script)]
        if job:
            command += ["--", "--job", str(job)]
        process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
        (cls.work / (name + ".log")).write_text(process.stdout, encoding="utf-8")
        if success and process.returncode != 0:
            raise AssertionError(process.stdout[-7000:])
        if not success and process.returncode == 0:
            raise AssertionError("Invalid job incorrectly succeeded")
        return process

    @classmethod
    def job(cls, name, **changes):
        relative_work = cls.work.relative_to(ROOT)
        output = relative_work / name
        value = {"schemaVersion": 1, "root": str(ROOT), "input": (relative_work / "synthetic.glb").as_posix(),
                 "outputDir": output.as_posix(), "result": (output / "result.json").as_posix(),
                 "recipe": dict(cls.recipe)}
        value.update(changes)
        path = cls.work / (name + ".json")
        path.write_text(json.dumps(value), encoding="utf-8")
        return path, value

    def test_01_real_finishing_and_review(self):
        source = self.work / "synthetic.glb"
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        job, value = self.job("finished")
        self.run_blender(SCRIPTS / "finish.py", job, "finish")
        result = json.loads((ROOT / value["result"]).read_text())
        self.assertEqual(result["status"], "prepared")
        self.assertEqual(result["humanApproval"], "pending")
        self.assertEqual(result["inputSha256"], before)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before)
        self.assertEqual(len([k for k in result["artifacts"] if k.startswith("texture")]), 5)
        self.assertTrue(result["stages"][-1]["verified"])
        self.assertGreater(result["measurements"]["textureBytes"], 0)
        self.assertEqual(len(result["measurements"]["parts"][0]["lods"]), 2)
        self.assertEqual(result["measurements"]["parts"][0]["topology"]["degenerateFaces"], 0)
        for channel, measurement in result["measurements"]["parts"][0]["bakeMaps"].items():
            self.assertGreater(measurement["maxRgb"], 0, channel)
            self.assertEqual(measurement["width"], 32)
        self.assertAlmostEqual(result["measurements"]["parts"][0]["bakeMaps"]["roughness"]["maxRgb"], 0.45, places=2)
        self.assertAlmostEqual(result["measurements"]["parts"][0]["bakeMaps"]["metallic"]["maxRgb"], 0.2, places=2)
        for relative, expected_hash in result["outputHashes"].items():
            self.assertEqual(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest(), expected_hash)
        review_job, review_value = self.job("reviewed", input=result["artifacts"]["glb"],
                                          proof=(self.work / "synthetic-proof.png").relative_to(ROOT).as_posix())
        self.run_blender(SCRIPTS / "review.py", review_job, "review")
        review = json.loads((ROOT / review_value["result"]).read_text())
        self.assertEqual(review["measurements"]["views"], 4)
        self.assertEqual(review["independentReview"], "pending")
        self.assertIn("Proof versus", (ROOT / review["artifacts"]["comparison"]).read_text())
        for relative in review["artifacts"].values():
            self.assertTrue((ROOT / relative).is_file())

    def test_02_missing_recipe_fails(self):
        job, value = self.job("bad-recipe", recipe={})
        self.run_blender(SCRIPTS / "finish.py", job, "bad-recipe", success=False)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_03_path_escape_fails(self):
        job, _ = self.job("escape", outputDir="../outside-proof-model-test", result="../outside-proof-model-test/result.json")
        self.run_blender(SCRIPTS / "finish.py", job, "escape", success=False)

    def test_04_animation_cannot_be_claimed(self):
        recipe = dict(self.recipe, animationRequired=True)
        job, value = self.job("animated", recipe=recipe)
        self.run_blender(SCRIPTS / "finish.py", job, "animated", success=False)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_05_immutable_attempt_cannot_overwrite(self):
        job, value = self.job("occupied")
        folder = ROOT / value["outputDir"]
        folder.mkdir()
        (folder / "prior.txt").write_text("prior immutable artifact")
        self.run_blender(SCRIPTS / "finish.py", job, "occupied", success=False)
        self.assertEqual((folder / "prior.txt").read_text(), "prior immutable artifact")

    def test_06_multipart_material_correspondence_and_transforms(self):
        relative_work = self.work.relative_to(ROOT)
        recipe = dict(self.recipe, targetFaces=180, parts=["Hull", "Satellite"])
        job, value = self.job("multipart", input=(relative_work / "synthetic-multipart.glb").as_posix(), recipe=recipe)
        self.run_blender(SCRIPTS / "finish.py", job, "multipart")
        result = json.loads((ROOT / value["result"]).read_text())
        parts = result["measurements"]["parts"]
        self.assertEqual({p["part"] for p in parts}, {"Hull", "Satellite"})
        self.assertEqual(sorted(p["sourceMaterials"] for p in parts), [1, 2])
        self.assertEqual(len([k for k in result["artifacts"] if k.startswith("texture")]), 10)
        self.assertEqual(result["stages"][-1]["meshCount"], 8)
        self.assertGreater(result["stages"][-1]["bounds"]["min"][0], 1)

    def test_07_measured_budget_blocks_success(self):
        job, value = self.job("over-budget", recipe=dict(self.recipe, maxTriangles=1))
        self.run_blender(SCRIPTS / "finish.py", job, "over-budget", success=False)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_08_embedded_resource_only(self):
        document = {"asset": {"version": "2.0"}, "buffers": [{"uri": "../../outside.bin", "byteLength": 1}]}
        encoded = json.dumps(document).encode()
        encoded += b" " * (-len(encoded) % 4)
        external = self.work / "external.glb"
        external.write_bytes(b"glTF" + struct.pack("<IIII", 2, len(encoded) + 20, len(encoded), 0x4E4F534A) + encoded)
        job, value = self.job("external", input=external.relative_to(ROOT).as_posix())
        process = self.run_blender(SCRIPTS / "finish.py", job, "external", success=False)
        self.assertIn("fully embedded", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_09_corrupt_glb_rejected(self):
        corrupt = self.work / "corrupt.glb"
        corrupt.write_bytes(b"glTFbroken")
        job, value = self.job("corrupt", input=corrupt.relative_to(ROOT).as_posix())
        self.run_blender(SCRIPTS / "finish.py", job, "corrupt", success=False)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_10_guided_rig_and_animation_review(self):
        recipe = dict(self.recipe, riggingRequired=True, animationRequired=True)
        job, value = self.job("guided-review", input=(self.work / "synthetic-guided.glb").relative_to(ROOT).as_posix(),
                              proof=(self.work / "synthetic-proof.png").relative_to(ROOT).as_posix(), recipe=recipe)
        self.run_blender(SCRIPTS / "review.py", job, "guided-review")
        result = json.loads((ROOT / value["result"]).read_text())
        subject = result["measurements"]["subject"]
        self.assertEqual(subject["armatures"], 1)
        self.assertEqual(subject["bones"], 1)
        self.assertEqual(subject["reviewFrame"], 13)
        self.assertGreater(len(subject["animations"]), 0)
        self.assertEqual(result["independentReview"], "pending")
        self.assertEqual(result["measurements"]["views"], 4)

    def test_11_missing_guided_structures_rejected(self):
        recipe = dict(self.recipe, riggingRequired=True, animationRequired=True)
        job, value = self.job("missing-guided", recipe=recipe,
                              proof=(self.work / "synthetic-proof.png").relative_to(ROOT).as_posix())
        process = self.run_blender(SCRIPTS / "review.py", job, "missing-guided", success=False)
        self.assertIn("Required rigging", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_12_static_finish_rejects_subject_derivative(self):
        job, value = self.job("no-automatic-rig-finishing", input=(self.work / "synthetic-guided.glb").relative_to(ROOT).as_posix())
        process = self.run_blender(SCRIPTS / "finish.py", job, "no-automatic-rig-finishing", success=False)
        self.assertIn("subject-specific workflow", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_13_missing_required_animation_rejected(self):
        job, value = self.job("missing-animation", input=(self.work / "synthetic-rig-only.glb").relative_to(ROOT).as_posix(),
                              proof=(self.work / "synthetic-proof.png").relative_to(ROOT).as_posix(),
                              recipe=dict(self.recipe, riggingRequired=True, animationRequired=True))
        process = self.run_blender(SCRIPTS / "review.py", job, "missing-animation", success=False)
        self.assertIn("Required animation", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_14_derivative_budget_revalidated(self):
        job, value = self.job("over-budget-derivative", input=(self.work / "synthetic-guided.glb").relative_to(ROOT).as_posix(),
                              proof=(self.work / "synthetic-proof.png").relative_to(ROOT).as_posix(),
                              recipe=dict(self.recipe, riggingRequired=True, animationRequired=True, maxTriangles=1))
        process = self.run_blender(SCRIPTS / "review.py", job, "over-budget-derivative", success=False)
        self.assertIn("maxTriangles", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
