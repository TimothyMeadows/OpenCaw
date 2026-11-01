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

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "runtime/bubo/resources/proof-to-model/blender"
import shutil
BLENDER = os.environ.get("BLENDER_EXE") or shutil.which("blender") or r"C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"


class BlenderProduction(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(BLENDER).is_file():
            raise unittest.SkipTest("Blender 4.5 executable unavailable; set BLENDER_EXE")
        configured = os.environ.get("HEPHAERA_PROOF_BLENDER_EVIDENCE_ROOT")
        evidence = Path(configured) if configured else ROOT / ".hephaera/.cache/tasks/proof-multiview-classification/evidence"
        if not evidence.is_absolute():
            evidence = ROOT / evidence
        if ".." in evidence.parts:
            raise ValueError("Blender test evidence root must be confined without parent traversal")
        evidence.relative_to(ROOT)
        cursor = evidence
        while cursor != ROOT:
            if cursor.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(cursor)):
                raise ValueError("Blender test evidence root cannot contain symbolic links/junctions")
            cursor = cursor.parent
        evidence.resolve().relative_to(ROOT.resolve())
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
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1)
obj = bpy.context.object
obj.name = "SixDistinctFaces"
obj.dimensions = (0.7, 0.5, 1.0)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
colors = ((1, 0.02, 0.02, 1), (0.02, 1, 0.02, 1), (0.02, 0.02, 1, 1),
          (1, 1, 0.02, 1), (1, 0.02, 1, 1), (0.02, 1, 1, 1))
for index, color in enumerate(colors):
    material = bpy.data.materials.new("KnownFace" + str(index))
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Emission Color"].default_value = color
    shader.inputs["Emission Strength"].default_value = 1
    shader.inputs["Roughness"].default_value = 1
    obj.data.materials.append(material)
for polygon in obj.data.polygons:
    normal = polygon.normal
    axis = max(range(3), key=lambda index: abs(normal[index]))
    polygon.material_index = axis * 2 + int(normal[axis] < 0)
obj.rotation_euler.z = 3.141592653589793
bpy.ops.export_scene.gltf(filepath=str(folder / "synthetic-six-view.glb"), export_format="GLB")
obj.rotation_euler.z = 0
bpy.ops.export_scene.gltf(filepath=str(folder / "synthetic-six-view-proof-frame.glb"), export_format="GLB")
from mathutils import Matrix
distance = 3.1192049980163574
cameras = {
    "front": [[1,0,0,0],[0,0,-1,-distance],[0,1,0,0],[0,0,0,1]],
    "right": [[0,0,-1,-distance],[-1,0,0,0],[0,1,0,0],[0,0,0,1]],
    "back": [[-1,0,0,0],[0,0,1,distance],[0,1,0,0],[0,0,0,1]],
    "left": [[0,0,1,distance],[1,0,0,0],[0,1,0,0],[0,0,0,1]],
    "top": [[1,0,0,0],[0,1,0,0],[0,0,1,distance],[0,0,0,1]],
    "bottom": [[1,0,0,0],[0,-1,0,0],[0,0,-1,-distance],[0,0,0,1]],
}
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 8
scene.render.resolution_x = scene.render.resolution_y = 384
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world = bpy.data.worlds.new("Known source world")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.12, 0.12, 1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
camera_data = bpy.data.cameras.new("Known camera")
camera = bpy.data.objects.new("Known camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera_data.type = "PERSP"
camera_data.sensor_fit = "HORIZONTAL"
import math
camera_data.lens = camera_data.sensor_width / (2 * math.tan(0.3490658503988659 / 2))
for name, matrix in cameras.items():
    camera.matrix_world = Matrix(matrix)
    scene.render.filepath = str(folder / ("known-" + name + ".png"))
    bpy.ops.render.render(write_still=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1)
obj = bpy.context.object
obj.name = "WoundedSource"
material = bpy.data.materials.new("WoundedSourcePBR")
material.use_nodes = True
shader = material.node_tree.nodes.get("Principled BSDF")
shader.inputs["Base Color"].default_value = (0.65, 0.16, 0.05, 1)
shader.inputs["Metallic"].default_value = 0.2
shader.inputs["Roughness"].default_value = 0.45
obj.data.materials.append(material)
import bmesh
mesh = bmesh.new()
mesh.from_mesh(obj.data)
mesh.faces.ensure_lookup_table()
bmesh.ops.delete(mesh, geom=[mesh.faces[0]], context="FACES_ONLY")
mesh.edges.ensure_lookup_table()
edge = next(edge for edge in mesh.edges if edge.is_manifold)
fin = mesh.verts.new((edge.verts[0].co + edge.verts[1].co) / 2 * 1.15)
mesh.faces.new((edge.verts[0], edge.verts[1], fin))
mesh.to_mesh(obj.data)
mesh.free()
bpy.ops.export_scene.gltf(filepath=str(folder / "synthetic-nonmanifold.glb"), export_format="GLB")
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
        value = {"schemaVersion": 1, "mode": "single-view-diagnostic", "root": str(ROOT), "input": (relative_work / "synthetic.glb").as_posix(),
                 "outputDir": output.as_posix(), "result": (output / "result.json").as_posix(),
                 "recipe": dict(cls.recipe)}
        value.update(changes)
        path = cls.work / (name + ".json")
        path.write_text(json.dumps(value), encoding="utf-8")
        return path, value

    @classmethod
    def multiview(cls, name, mutate=None, frame="pixal3d-mv-export"):
        work = cls.work.relative_to(ROOT)
        sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
        distance = 3.1192049980163574
        matrices = {
            "front": [[1, 0, 0, 0], [0, 0, -1, -distance], [0, 1, 0, 0], [0, 0, 0, 1]],
            "right": [[0, 0, -1, -distance], [-1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
            "back": [[-1, 0, 0, 0], [0, 0, 1, distance], [0, 1, 0, 0], [0, 0, 0, 1]],
            "left": [[0, 0, 1, distance], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
            "top": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, distance], [0, 0, 0, 1]],
            "bottom": [[1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, -distance], [0, 0, 0, 1]],
        }
        originals = ["front", "back"]
        source_set = {"schemaVersion": 1, "primarySourceId": "source-front", "images": [
            {"id": "source-" + view, "path": (work / ("known-" + view + ".png")).as_posix(),
             "sha256": sha(cls.work / ("known-" + view + ".png"))} for view in originals]}
        source_set_hash = hashlib.sha256(json.dumps(source_set).encode()).hexdigest()
        classification = {"schemaVersion": 1, "sourceSetHash": source_set_hash,
                          "sources": [{"sourceId": item["id"], "sha256": item["sha256"]} for item in source_set["images"]],
                          "sourceViews": [{"sourceId": "source-" + view, "view": view, "usable": True,
                                           "reason": "Known independent synthetic camera"} for view in originals],
                          "subjects": [{"id": "box", "kind": "nonliving", "classification": "Synthetic six-color box"}],
                          "research": [], "unknowns": [], "preservationConstraints": ["Preserve axis-specific face colors"],
                          "prohibitedSubstitutions": [], "conflicts": []}
        proof_set = {"schemaVersion": 1, "revision": 1, "sourceSetHash": source_set_hash,
                     "classificationHash": hashlib.sha256(json.dumps(classification).encode()).hexdigest(),
                     "camera": {"convention": "blender-nerf-z-up", "calibration": "nominal-prescribed", "meshScale": 1,
                                "cameraAngleX": 0.3490658503988659, "distance": distance}, "views": []}
        for view, matrix in matrices.items():
            image = cls.work / ("known-" + view + ".png")
            proof_set["views"].append({"view": view, "image": image.relative_to(ROOT).as_posix(), "sha256": sha(image),
                                       "approvedImage": image.relative_to(ROOT).as_posix(), "approvedSha256": sha(image),
                                       "origin": "source" if view in originals else "generated", "revision": 1,
                                       "sourceIds": ["source-" + view] if view in originals else ["source-front", "source-back"],
                                       "cameraToWorld": matrix})
        input_name = "synthetic-six-view.glb" if frame == "pixal3d-mv-export" else "synthetic-six-view-proof-frame.glb"
        job, value = cls.job(name, schemaVersion=2, mode="multi-view", inputFrame=frame, input=(work / input_name).as_posix(),
                             recipe=dict(cls.recipe, maxMaterials=6), sourceSet=source_set, classification=classification, proofSet=proof_set)
        if mutate:
            mutate(value)
            job.write_text(json.dumps(value), encoding="utf-8")
        return job, value

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
        self.assertEqual(review["mode"], "single-view-diagnostic")
        self.assertEqual(review["alignment"]["method"], "four-arbitrary-orthographic-views")
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

    def test_15_real_six_camera_source_and_proof_comparison(self):
        job, value = self.multiview("six-reviewed")
        self.run_blender(SCRIPTS / "review.py", job, "six-reviewed")
        result = json.loads((ROOT / value["result"]).read_text())
        self.assertEqual(result["mode"], "multi-view")
        self.assertEqual(result["measurements"]["views"], 6)
        self.assertEqual(result["alignment"]["method"], "shared-bounds-fit")
        self.assertEqual(result["alignment"]["calibration"], "nominal-prescribed")
        self.assertIn("not measured", result["alignment"]["limitation"])
        self.assertEqual(result["humanApproval"], "pending")
        self.assertEqual(result["independentReview"], "pending")
        self.assertEqual(len([name for name in result["artifacts"] if name.startswith("original-")]), 2)
        self.assertEqual(len([name for name in result["artifacts"] if name.startswith("approved-")]), 6)
        self.assertEqual(len([name for name in result["artifacts"] if name.startswith("conditioning-")]), 6)
        for expected, actual in zip(value["proofSet"]["views"], result["cameras"]):
            self.assertEqual(actual["view"], expected["view"])
            self.assertEqual(actual["cameraToWorld"], expected["cameraToWorld"])
            self.assertEqual(actual["cameraAngleX"], value["proofSet"]["camera"]["cameraAngleX"])
            for row in range(4):
                for column in range(4):
                    expected_mapping = (-1 if row in (0, 1) else 1) * expected["cameraToWorld"][row][column]
                    self.assertAlmostEqual(actual["effectiveBlenderCameraToWorld"][row][column], expected_mapping, places=5)
        page = (ROOT / result["artifacts"]["comparison"]).read_text(encoding="utf-8")
        self.assertIn("Immutable original sources", page)
        self.assertIn("Source-only classification", page)
        self.assertIn("source-front", page)
        for name, expected in result["outputHashes"].items():
            self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), expected)
        self.assert_six_camera_colors("six-reviewed")

    def assert_six_camera_colors(self, case):
        inspect = self.work / ("inspect-" + case + ".py")
        inspect.write_text('''import bpy, json
from pathlib import Path
folder = Path(__file__).parent
case = ''' + repr(case) + '''
report = json.loads((folder / case / "result.json").read_text())
results = {}
for view in report["cameras"]:
    name = view["view"]
    source = bpy.data.images.load(str(folder / ("known-" + name + ".png")), check_existing=False)
    rendered = bpy.data.images.load(str(folder / case / (name + ".png")), check_existing=False)
    center = ((rendered.size[1] // 2) * rendered.size[0] + rendered.size[0] // 2) * 4
    results[name] = {"source": list(source.pixels[center:center+3]), "rendered": list(rendered.pixels[center:center+3])}
(folder / (case + "-color-checks.json")).write_text(json.dumps(results))
''', encoding="utf-8")
        self.run_blender(inspect, None, "inspect-" + case)
        colors = json.loads((self.work / (case + "-color-checks.json")).read_text())
        identities = []
        for view, color in colors.items():
            # Review lighting deliberately differs. The six known face identities,
            # rather than photometric equality, detect orientation/double-flip errors.
            normalized = {}
            for kind in ("source", "rendered"):
                rgb = color[kind]
                chroma = max(rgb) - min(rgb)
                self.assertGreater(chroma, 0.08, view)
                normalized[kind] = [(channel - min(rgb)) / chroma for channel in rgb]
            self.assertLess(max(abs(a - b) for a, b in zip(normalized["source"], normalized["rendered"])), 0.15, view)
            identities.append(tuple(round(channel, 0) for channel in normalized["rendered"]))
        self.assertEqual(len(set(identities)), 6)

    def test_16_flipped_polar_camera_rejected(self):
        def mutate(value):
            value["proofSet"]["views"][-1]["cameraToWorld"][0][0] = -1
        job, value = self.multiview("flipped-bottom", mutate)
        process = self.run_blender(SCRIPTS / "review.py", job, "flipped-bottom", success=False)
        self.assertIn("cardinal/polar rig", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_17_stale_conditioning_hash_rejected(self):
        def mutate(value):
            value["proofSet"]["views"][3]["sha256"] = "0" * 64
        job, value = self.multiview("stale-conditioning", mutate)
        process = self.run_blender(SCRIPTS / "review.py", job, "stale-conditioning", success=False)
        self.assertIn("image missing or changed", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_18_non_original_classification_evidence_rejected(self):
        def mutate(value):
            value["classification"]["sources"][0]["sourceId"] = "generated-right"
        job, value = self.multiview("classification-contamination", mutate)
        process = self.run_blender(SCRIPTS / "review.py", job, "classification-contamination", success=False)
        self.assertIn("exact registered original", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_19_incomplete_six_view_coverage_rejected(self):
        job, value = self.multiview("missing-view", lambda value: value["proofSet"]["views"].pop())
        process = self.run_blender(SCRIPTS / "review.py", job, "missing-view", success=False)
        self.assertIn("Exactly six ordered", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_20_single_view_cannot_implicitly_satisfy_production_review(self):
        job, value = self.job("missing-diagnostic-mode", proof=(self.work / "synthetic-proof.png").relative_to(ROOT).as_posix())
        value.pop("mode")
        job.write_text(json.dumps(value), encoding="utf-8")
        process = self.run_blender(SCRIPTS / "review.py", job, "missing-diagnostic-mode", success=False)
        self.assertIn("explicit single-view-diagnostic", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_21_corrected_proof_frame_is_not_flipped_twice(self):
        job, value = self.multiview("six-corrected", frame="hephaera-proof-z-up")
        self.run_blender(SCRIPTS / "review.py", job, "six-corrected")
        result = json.loads((ROOT / value["result"]).read_text())
        self.assertEqual(result["alignment"]["inputFrame"], "hephaera-proof-z-up")
        self.assertEqual(result["alignment"]["engineExportToProofFrame"], [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
        for expected, actual in zip(value["proofSet"]["views"], result["cameras"]):
            for row in range(4):
                for column in range(4):
                    self.assertAlmostEqual(actual["effectiveBlenderCameraToWorld"][row][column], expected["cameraToWorld"][row][column], places=5)
        self.assert_six_camera_colors("six-corrected")

    @staticmethod
    def finish_settings(**changes):
        value = {"schemaVersion": 1,
                 "topologyPreparation": {"method": "voxel-remesh", "voxelSize": 0.08,
                                         "maxEstimatedVoxels": 1000000, "maxPreparedTriangles": 50000},
                 "collision": {"method": "kdop-26", "padding": 0.002, "maxVolumeRatio": 2}}
        value.update(changes)
        return value

    def helper_probe(self, name, code):
        script = self.work / (name + ".py")
        script.write_text("import sys, bpy, json, math\nfrom pathlib import Path\n"
                          + "sys.dont_write_bytecode = True\nsys.path.insert(0, " + repr(str(SCRIPTS)) + ")\n"
                          + "import finish\n" + code, encoding="utf-8")
        return self.run_blender(script, None, name)

    def test_22_actual_nonmanifold_input_blocks_without_selected_repair(self):
        job, value = self.job("no-implicit-repair", input=(self.work / "synthetic-nonmanifold.glb").relative_to(ROOT).as_posix())
        process = self.run_blender(SCRIPTS / "finish.py", job, "no-implicit-repair", success=False)
        self.assertIn("requires closed manifold", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_23_explicit_voxel_kdop_full_bake_export_and_reimport(self):
        source = self.work / "synthetic-nonmanifold.glb"
        before = hashlib.sha256(source.read_bytes()).hexdigest()
        settings = self.finish_settings()
        job, value = self.job("selected-repair", input=source.relative_to(ROOT).as_posix(),
                              finishingSettings=settings, recipe=dict(self.recipe, colliderMaxFaces=64))
        self.run_blender(SCRIPTS / "finish.py", job, "selected-repair")
        result = json.loads((ROOT / value["result"]).read_text())
        part = result["measurements"]["parts"][0]
        self.assertEqual(result["finishingSettings"], settings)
        self.assertGreater(part["preparation"]["before"]["nonManifoldEdges"], 0)
        self.assertEqual(part["preparation"]["after"]["nonManifoldEdges"], 0)
        self.assertEqual(part["retopology"]["operatorStatus"], ["FINISHED"])
        self.assertNotEqual(part["retopology"]["inputGeometrySha256"], part["retopology"]["outputGeometrySha256"])
        self.assertTrue(part["collision"]["allSourceVerticesContained"])
        self.assertLessEqual(part["collision"]["polygonFaces"], 26)
        self.assertGreater(part["collision"]["volumeRatio"], 1)
        self.assertLessEqual(part["collision"]["volumeRatio"], 2)
        self.assertTrue(part["immutableHighGeometryPreserved"])
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), before)
        self.assertTrue(result["stages"][-1]["verified"])
        blend = ROOT / result["artifacts"]["blend"]
        self.helper_probe("inspect-prepared-master", "bpy.ops.wm.open_mainfile(filepath=" + repr(str(blend)) + ")\n"
                          + "high=bpy.data.objects['WoundedSource']\nprepared=bpy.data.objects['WoundedSource_PREPARATION_SOURCE']\n"
                          + "assert high.hide_get() and high.hide_render and prepared.hide_get() and prepared.hide_render\n"
                          + "assert finish.mesh_identity(high)==" + repr(part["sourceGeometrySha256"]) + "\n"
                          + "assert finish.mesh_identity(prepared)==" + repr(part["preparation"]["preparedGeometrySha256"]) + "\n"
                          + "assert high.data is not prepared.data\n"
                          + "finish.collision_measure(bpy.data.objects['WoundedSource_COLLISION'],finish.world_vertices(high))\n")

    def test_24_voxel_preflight_budget_blocks_before_remesh(self):
        settings = self.finish_settings()
        settings["topologyPreparation"]["maxEstimatedVoxels"] = 1
        job, value = self.job("voxel-preflight", finishingSettings=settings)
        process = self.run_blender(SCRIPTS / "finish.py", job, "voxel-preflight", success=False)
        self.assertIn("before voxel-remesh", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_25_actual_prepared_triangle_cap_blocks(self):
        settings = self.finish_settings()
        settings["topologyPreparation"]["maxPreparedTriangles"] = 4
        job, value = self.job("prepared-cap", finishingSettings=settings)
        process = self.run_blender(SCRIPTS / "finish.py", job, "prepared-cap", success=False)
        self.assertIn("Actual voxel-remesh exceeds maxPreparedTriangles", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_26_malformed_settings_and_integer_semantics(self):
        settings = self.finish_settings()
        invalid = [dict(settings, schemaVersion=True), dict(settings, surprise=True), {},
                   dict(settings, topologyPreparation={"method": "none", "voxelSize": .1}),
                   dict(settings, topologyPreparation={"method": "voxel-remesh"}),
                   dict(settings, collision={"method": "exact-hull", "padding": 0}),
                   dict(settings, collision={"method": "box"})]
        for key, bad in (("voxelSize", 0), ("voxelSize", 1.1), ("voxelSize", float("nan")),
                         ("maxEstimatedVoxels", True), ("maxEstimatedVoxels", 2000000001),
                         ("maxPreparedTriangles", 3), ("maxPreparedTriangles", 5.5)):
            invalid.append(dict(settings, topologyPreparation=dict(settings["topologyPreparation"], **{key: bad})))
        for key, bad in (("padding", -1), ("padding", 1.1), ("padding", float("inf")),
                         ("maxVolumeRatio", .9), ("maxVolumeRatio", 101)):
            invalid.append(dict(settings, collision=dict(settings["collision"], **{key: bad})))
        self.helper_probe("invalid-settings", "values=" + repr(invalid).replace("nan", "float('nan')").replace("inf", "float('inf')") + "\n"
                          + "for value in values:\n try: finish.validate_finishing_settings(value)\n except ValueError: pass\n else: raise AssertionError('Malformed settings accepted')\n"
                          + "value=" + repr(settings) + "\nvalue['schemaVersion']=1.0\nvalue['topologyPreparation']['maxEstimatedVoxels']=1e6\n"
                          + "assert type(finish.validate_finishing_settings(value)['topologyPreparation']['maxEstimatedVoxels']) is int\n"
                          + "assert finish.validate_finishing_settings(None)['collision']=={'method':'exact-hull'}\n")

    def test_27_actual_quadriflow_warning_noop_is_rejected(self):
        self.helper_probe("quadri-noop", "bpy.ops.wm.read_factory_settings(use_empty=True)\n"
                          + "mesh=bpy.data.meshes.new('NonmanifoldTripod')\nmesh.from_pydata([(0,0,0),(1,0,0),(0,1,0),(0,-1,0),(0,0,1)],[],[(0,1,2),(1,0,3),(0,1,4)])\n"
                          + "obj=bpy.data.objects.new('BadQuadriFlowSource',mesh)\nbpy.context.collection.objects.link(obj)\n"
                          + "finish.activate(obj)\nstatus=bpy.ops.object.quadriflow_remesh(target_faces=100,seed=0)\nassert status in ({'CANCELLED'},{'FINISHED'})\n"
                          + "try: finish.run_quadriflow(obj,100)\nexcept ValueError as error: assert 'unchanged' in str(error) or 'did not finish' in str(error),str(error)\nelse: raise AssertionError('QuadriFlow warning/no-op was accepted')\n")

    def test_28_transformed_asymmetric_kdop_actual_geometry_and_reimport(self):
        self.helper_probe("kdop-transformed", """from mathutils import Matrix, Euler
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1)
high=bpy.context.object
high.name='AsymmetricAllVertexSource'
for vertex in high.data.vertices:
    vertex.co.x*=1.0+max(0,vertex.co.z)*.37
    vertex.co.z+=.15*vertex.co.y*vertex.co.y
parent=bpy.data.objects.new('SourceTransform',None)
bpy.context.collection.objects.link(parent)
parent.matrix_world=Matrix.Translation((2.7,-1.2,.8)) @ Euler((.31,-.29,.6)).to_matrix().to_4x4() @ Matrix.Diagonal((1.3,.7,1.1,1))
high.parent=parent
bpy.context.view_layer.update()
low=high.copy();low.data=high.data.copy();bpy.context.collection.objects.link(low)
low.parent=None;low.matrix_world=high.matrix_world.copy()
settings={'method':'kdop-26','padding':.003,'maxVolumeRatio':2}
proxy,report=finish.build_kdop26(high,low,settings,64)
assert report['allSourceVerticesContained'] and report['closedManifold'] and report['convex']
assert 4<=report['polygonFaces']<=26 and report['volume']>0 and 1<report['volumeRatio']<2
assert report['originalHighVertexCount']==len(high.data.vertices)
assert report['runtimeLowVertexCount']==len(low.data.vertices)
assert report['sourceVertexCount']==len(high.data.vertices)+len(low.data.vertices)
from mathutils.bvhtree import BVHTree
import bmesh
bm=bmesh.new();bm.from_mesh(proxy.data);bm.transform(proxy.matrix_world);tree=BVHTree.FromBMesh(bm)
# Independent odd-ray interior test on actual proxy triangles, not support formulas.
all_points=finish.np.concatenate((finish.world_vertices(high),finish.world_vertices(low)),axis=0)
for point in all_points:
    from mathutils import Vector
    origin=Vector(point);direction=Vector((.932,.217,.293)).normalized();hits=0
    for attempt in range(8):
        location,normal,index,distance=tree.ray_cast(origin,direction,100)
        if location is None:break
        hits+=1;origin=location+direction*.00001
    assert hits%2==1,(point,hits)
bm.free()
before=finish.collision_measure(proxy,all_points)
finish.activate(proxy)
file=Path(__file__).with_suffix('.glb')
bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True)
original_points=all_points
imported=finish.import_glb(file)
assert len(imported)==1
after=finish.collision_measure(imported[0],original_points)
assert abs(before['volume']-after['volume'])<.00001
assert after['allSourceVerticesContained'] and after['convex']
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps({'before':before,'reimported':after,'kdop':report},indent=2))
""")

    def test_29_kdop_limits_and_actual_bad_geometry_rejected(self):
        self.helper_probe("kdop-rejections", """bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=1)
high=bpy.context.object;low=high.copy();low.data=high.data.copy();bpy.context.collection.objects.link(low)
for settings,cap,reason in [({'method':'kdop-26','padding':.001,'maxVolumeRatio':2},4,'colliderMaxFaces'),({'method':'kdop-26','padding':.001,'maxVolumeRatio':1},64,'maxVolumeRatio')]:
    try:finish.build_kdop26(high,low,settings,cap)
    except ValueError as error:assert reason in str(error),str(error)
    else:raise AssertionError('Selected proxy cap was ignored')
proxy,report=finish.build_kdop26(high,low,{'method':'kdop-26','padding':.001,'maxVolumeRatio':2},64)
proxy.location.x=10;bpy.context.view_layer.update()
try:finish.collision_measure(proxy,finish.world_vertices(high))
except ValueError as error:assert 'ALL source' in str(error),str(error)
else:raise AssertionError('Actual outside source was accepted')
proxy.location.x=0;bpy.context.view_layer.update()
proxy.data.vertices[0].co*=.01;proxy.data.update()
try:finish.collision_measure(proxy,finish.world_vertices(high))
except ValueError as error:assert 'convex' in str(error) or 'ALL source' in str(error),str(error)
else:raise AssertionError('Actual nonconvex geometry was accepted')
""")

    def test_30_explicit_none_exact_hull_keeps_legacy_path(self):
        settings = {"schemaVersion": 1, "topologyPreparation": {"method": "none"},
                    "collision": {"method": "exact-hull"}}
        job, value = self.job("explicit-legacy", finishingSettings=settings)
        self.run_blender(SCRIPTS / "finish.py", job, "explicit-legacy")
        result = json.loads((ROOT / value["result"]).read_text())
        part = result["measurements"]["parts"][0]
        self.assertEqual(result["finishingSettings"], settings)
        self.assertEqual(part["preparation"]["method"], "none")
        self.assertEqual(part["collision"]["method"], "exact-hull")
        self.assertTrue(result["stages"][-1]["collision"][0]["allSourceVerticesContained"])

    def test_31_exact_hull_cap_blocks_before_dense_verification(self):
        job, value = self.job("exact-hull-cap", recipe=dict(self.recipe, colliderMaxFaces=4))
        script = self.work / "exact-cap-spy.py"
        script.write_text("import sys\nsys.dont_write_bytecode=True\nsys.path.insert(0," + repr(str(SCRIPTS)) + ")\n"
                          + "import finish\ndef forbidden(*args): raise AssertionError('Dense verification ran before face-cap rejection')\n"
                          + "finish.collision_measure=forbidden\nfinish.main()\n", encoding="utf-8")
        process = self.run_blender(script, job, "exact-hull-cap", success=False)
        self.assertIn("exceeds colliderMaxFaces", process.stdout)
        self.assertNotIn("Dense verification ran", process.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_32_kdop_contains_real_low_extension_at_zero_padding(self):
        self.helper_probe("kdop-low-extension", """bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
high=bpy.context.object;high.name='OriginalHighCube'
low=high.copy();low.data=high.data.copy();bpy.context.collection.objects.link(low);low.name='ActualExtendedLOD0'
low.data.vertices[0].co.x-=.75;low.data.update()
settings={'method':'kdop-26','padding':0,'maxVolumeRatio':2}
proxy,report=finish.build_kdop26(high,low,settings,64)
union=finish.np.concatenate((finish.world_vertices(high),finish.world_vertices(low)),axis=0)
assert report['verifiedPointSet']=='original-high-and-runtime-low-union'
assert report['originalHighVertexCount']==8 and report['runtimeLowVertexCount']==8 and report['sourceVertexCount']==16
assert report['bounds']['min'][0]<-1.7 and report['allSourceVerticesContained']
assert report['exactUnionHullVolume']>8 and 1<=report['volumeRatio']<=2
finish.collision_measure(proxy,union)
from mathutils.bvhtree import BVHTree
from mathutils import Vector
import bmesh
bm=bmesh.new();bm.from_mesh(proxy.data);bm.transform(proxy.matrix_world);tree=BVHTree.FromBMesh(bm)
location,normal,index,distance=tree.find_nearest(Vector(low.data.vertices[0].co))
assert distance<.00001,(location,distance)
bm.free()
# Genuine negative control: the old HIGH-only proxy misses the moved LOW vertex.
high_only,unused=finish.build_kdop26(high,high,settings,64)
try:finish.collision_measure(high_only,union)
except ValueError as error:assert 'ALL source' in str(error),str(error)
else:raise AssertionError('HIGH-only collision was accepted for extended runtime LOW')
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(report,indent=2))
""")

    def test_33_rotated_scaled_reflected_proxies_at_fifty_metre_translations(self):
        self.helper_probe("translated-precision", """import random
from mathutils import Matrix,Euler,Vector
from mathutils.bvhtree import BVHTree
import bmesh
import numpy as np
rng=random.Random(82149)
results=[]
def independently_check(obj,source):
    bm=bmesh.new();bm.from_mesh(obj.data);bm.transform(obj.matrix_world)
    bmesh.ops.triangulate(bm,faces=list(bm.faces));tree=BVHTree.FromBMesh(bm)
    vertices=np.array([list(vertex.co) for vertex in bm.verts],dtype=np.float64)
    centre=vertices.mean(axis=0)
    tolerance=max(1e-6,float(np.max(np.ptp(vertices,axis=0)))*3e-6)
    volume=sum(float(np.dot(np.asarray(face.verts[0].co)-centre,np.cross(np.asarray(face.verts[1].co)-centre,np.asarray(face.verts[2].co)-centre)))/6 for face in bm.faces)
    boundary=0
    for point in source:
        nearest,normal,index,distance=tree.find_nearest(Vector(point))
        assert nearest is not None
        if distance<=tolerance:boundary+=1;continue
        angle=0.0
        for face in bm.faces:
            a,b,c=[np.asarray(vertex.co,dtype=np.float64)-point for vertex in face.verts]
            la,lb,lc=[np.linalg.norm(value) for value in (a,b,c)]
            angle+=2*math.atan2(float(np.dot(a,np.cross(b,c))),la*lb*lc+float(np.dot(a,b))*lc+float(np.dot(b,c))*la+float(np.dot(c,a))*lb)
        assert abs(abs(angle)-4*math.pi)<1e-3,(point,angle,distance)
    bm.free()
    return {'volume':volume,'checked':len(source),'boundary':boundary,'tolerance':tolerance}
for case in range(8):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1)
    high=bpy.context.object;high.name='TranslatedHigh'
    for vertex in high.data.vertices:
        vertex.co.x*=.75+.3*vertex.co.z*vertex.co.z
        vertex.co.z+=.23*vertex.co.y*vertex.co.y
    parent=bpy.data.objects.new('TranslatedParent',None);bpy.context.collection.objects.link(parent)
    parent.matrix_world=Matrix.Translation(tuple(rng.uniform(-50,50) for _ in range(3))) @ Euler(tuple(rng.uniform(-2,2) for _ in range(3))).to_matrix().to_4x4() @ Matrix.Diagonal(((-1 if case%2 else 1)*rng.uniform(.3,2),.6,1.4,1))
    high.parent=parent;bpy.context.view_layer.update()
    low=high.copy();low.data=high.data.copy();bpy.context.collection.objects.link(low);low.parent=None;low.matrix_world=high.matrix_world.copy()
    low.data.vertices[case].co.x-=.9
    original=(finish.mesh_identity(high),finish.mesh_identity(low))
    references=np.concatenate((finish.world_vertices(high),finish.world_vertices(low)))
    proxy,measured=finish.build_kdop26(high,low,{'method':'kdop-26','padding':0 if case%2 else .002,'maxVolumeRatio':3},64)
    assert original==(finish.mesh_identity(high),finish.mesh_identity(low))
    assert measured['numericalPrecision']['roundoffBoundMetres']<=measured['numericalPrecision']['maximumPermittedRoundoffMetres']
    assert measured['maximumLocalEncodingErrorMetres']<=measured['maximumPermittedLocalEncodingErrorMetres']
    before=independently_check(proxy,references)
    assert abs(before['volume']-measured['volume'])<=max(1e-7,measured['volume']*1e-5)
    finish.activate(proxy);file=Path(__file__).parent/('translated-proxy-'+str(case)+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True)
    imported=finish.import_glb(file);assert len(imported)==1
    after=independently_check(imported[0],references)
    reimported=finish.collision_measure(imported[0],references)
    assert reimported['allSourceVerticesContained'] and reimported['convex']
    assert abs(after['volume']-measured['volume'])<=max(1e-7,measured['volume']*1e-5)
    results.append({'case':case,'reflected':bool(case%2),'measured':measured,'before':before,'reimported':after})
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(results,indent=2))
""")

    def test_34_unprovable_coordinate_precision_requires_explicit_rebasing(self):
        self.helper_probe("precision-rebase", """bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
high=bpy.context.object;high.location=(1e12,-1e12,1e12);bpy.context.view_layer.update()
try:finish.build_kdop26(high,high,{'method':'kdop-26','padding':0,'maxVolumeRatio':2},64)
except ValueError as error:assert 'supported numerical precision' in str(error),str(error)
else:raise AssertionError('Unprovable large-coordinate fidelity was silently accepted')
""")

    def test_35_basecolor_transport_is_independent_of_metallicity_and_preserves_textures(self):
        self.helper_probe("metal-basecolor", """import numpy as np
def snapshot(mat):
    tree=mat.node_tree
    def default(socket):
        value=getattr(socket,'default_value',None)
        if value is None or isinstance(value,(str,int,float,bool)):return value
        try:return list(value)
        except TypeError:return str(value)
    return {'nodes':sorted((node.name,node.bl_idname,getattr(getattr(node,'image',None),'name',None)) for node in tree.nodes),'links':sorted((link.from_node.name,link.from_socket.identifier,link.to_node.name,link.to_socket.identifier) for link in tree.links),'defaults':[(node.name,[(socket.identifier,default(socket)) for socket in node.inputs]) for node in tree.nodes]}
results=[];images={}
for case,metallic,linked in [('nonmetal',0,False),('partial',.5,False),('fullmetal',1,False),('linked-nonmetal',0,True),('linked-fullmetal',1,True)]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh=bpy.data.meshes.new('CoveredPlane');mesh.from_pydata([(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0)],[],[(0,1,2,3)]);mesh.uv_layers.new(name='SquareUV')
    for uv,value in zip(mesh.uv_layers.active.data,((.1,.1),(.9,.1),(.9,.9),(.1,.9))):uv.uv=value
    high=bpy.data.objects.new('Source',mesh);bpy.context.collection.objects.link(high)
    mat=bpy.data.materials.new('SourcePBR');mat.use_nodes=True;shader=mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(.6,.2,.1,1);shader.inputs['Metallic'].default_value=metallic;shader.inputs['Roughness'].default_value=.45
    if linked:
        image=bpy.data.images.new('LinearReferenceTexture',16,16,float_buffer=True)
        image.colorspace_settings.name='Non-Color'
        pixels=np.ones((16,16,4),dtype=np.float32);pixels[:,:8,:3]=(.6,.2,.1);pixels[:,8:,:3]=(.1,.5,.8);image.pixels.foreach_set(pixels.ravel())
        texture=mat.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image;texture.interpolation='Closest';mat.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
    high.data.materials.append(mat);high.data.materials.append(mat);high.data.materials.append(mat)
    low=high.copy();low.data=high.data.copy();bpy.context.collection.objects.link(low);low.name='Low';low.location.z=-.01;bpy.context.view_layer.update()
    before=snapshot(mat);original=finish.mesh_identity(high)
    output=Path(__file__).parent/('metal-basecolor-'+case);output.mkdir()
    maps=finish.bake_maps(high,low,{'textureSize':64,'uvMargin':.02,'cageExtrusion':.1,'maxRayDistance':.3},output,0)
    assert before==snapshot(mat),'Source graph/defaults/texture links changed'
    assert original==finish.mesh_identity(high)
    pixels=np.array(maps['basecolor']['image'].pixels).reshape((64,64,4))[16:48,16:48,:3]
    assert np.isfinite(pixels).all() and pixels.min()>.1
    images[case]=pixels
    results.append({'case':case,'metallic':metallic,'linkedTexture':linked,'meanSavedPixelRGB':pixels.mean(axis=(0,1)).tolist(),'minimum':float(pixels.min()),'maximum':float(pixels.max()),'graphRestored':True,'duplicateMaterialSlots':3,'measurement':maps['basecolor']['measurement']})
for case in ('partial','fullmetal'):assert np.max(np.abs(images['nonmetal']-images[case]))<=1e-3,case
assert np.max(np.abs(images['linked-nonmetal']-images['linked-fullmetal']))<=1e-3
assert np.max(np.abs(images['linked-fullmetal'][:,:8]-images['linked-fullmetal'][:,-8:]))>.2,'Linked texture variation was lost'
# Saved sRGB8 values are compared to the standard transfer of the known linear input.
expected=np.array([1.055*(value**(1/2.4))-.055 for value in (.6,.2,.1)])
assert np.max(np.abs(images['fullmetal'].mean(axis=(0,1))-expected))<=2/255
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(results,indent=2))
""")

    def test_36_native_bake_failure_restores_source_graph(self):
        self.helper_probe("bake-failure-restoration", """bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_plane_add(size=2);high=bpy.context.object
mat=bpy.data.materials.new('OriginalPBR');mat.use_nodes=True;shader=mat.node_tree.nodes.get('Principled BSDF')
shader.inputs['Base Color'].default_value=(.6,.2,.1,1);shader.inputs['Metallic'].default_value=1
high.data.materials.append(mat);high.data.materials.append(mat)
low=high.copy();low.data=high.data.copy();bpy.context.collection.objects.link(low);low.location.z=-.01
for layer in list(low.data.uv_layers):low.data.uv_layers.remove(layer)
tree=mat.node_tree
before=([node.name for node in tree.nodes],[(link.from_node.name,link.from_socket.identifier,link.to_node.name,link.to_socket.identifier) for link in tree.links],tuple(shader.inputs['Base Color'].default_value),shader.inputs['Metallic'].default_value)
folder=Path(__file__).parent/'native-bake-failure';folder.mkdir()
try:finish.bake_maps(high,low,{'textureSize':32,'uvMargin':.02,'cageExtrusion':.1,'maxRayDistance':.3},folder,0)
except RuntimeError as error:assert 'UV' in str(error),str(error)
else:raise AssertionError('Real missing-UV bake failure did not occur')
after=([node.name for node in tree.nodes],[(link.from_node.name,link.from_socket.identifier,link.to_node.name,link.to_socket.identifier) for link in tree.links],tuple(shader.inputs['Base Color'].default_value),shader.inputs['Metallic'].default_value)
assert before==after,'Source graph was not restored after actual Cycles failure'
""")

    def test_37_partial_material_setup_failure_restores_already_rewired_source(self):
        self.helper_probe("partial-material-restoration", """bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_plane_add(size=2);high=bpy.context.object
first=bpy.data.materials.new('FirstPBR');first.use_nodes=True
high.data.materials.append(first);unsupported=bpy.data.materials.new('UnsupportedSecondMaterial');high.data.materials.append(unsupported)
low=high.copy();low.data=high.data.copy();bpy.context.collection.objects.link(low)
tree=first.node_tree;before=([node.name for node in tree.nodes],[(link.from_node.name,link.to_node.name) for link in tree.links])
folder=Path(__file__).parent/'partial-material-failure';folder.mkdir()
try:finish.bake_maps(high,low,{'textureSize':32,'uvMargin':.02,'cageExtrusion':.1,'maxRayDistance':.3},folder,0)
except ValueError as error:assert 'lacks nodes' in str(error),str(error)
else:raise AssertionError('Unsupported source material was silently accepted')
assert before==([node.name for node in tree.nodes],[(link.from_node.name,link.to_node.name) for link in tree.links])
""")

    @staticmethod
    def short_edge_cube_source():
        return """def make_cube():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    vertices=[(0,0,0),(1,0,0),(1,1,0),(0,1,0),(0,0,1),(1,0,1),(1,1,1),(0,1,1),(.00009,.00009,.00009)]
    faces=[(0,3,2,1,8),(0,8,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
    mesh=bpy.data.meshes.new('DiagonalShortEdge');mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new('LowFixture',mesh);bpy.context.collection.objects.link(obj)
    return obj
"""

    def test_38_explicit_solver_basis_and_real_quadriflow_are_deterministic(self):
        self.helper_probe("solver-real-diagonal", self.short_edge_cube_source() + """results=[]
for repeat in range(2):
    low=make_cube();source=finish.mesh_identity(low)
    high=low.copy();high.data=low.data.copy();bpy.context.collection.objects.link(high)
    high_source=finish.mesh_identity(high)
    before,bad=finish.quadriflow_input_measure(low)
    assert before['shortEdges']==1 and before['maximumOffendingEuclideanLength']>1e-4
    report=finish.run_quadriflow(low,200,1024)
    assert report['operatorStatus']==['FINISHED'] and report['preflight']['compatible']
    assert report['solverCoordinates']['coordinateScale']==1024
    assert report['solverCoordinates']['worldVertexErrorBeforeOperatorMetres']==0
    assert report['solverCoordinates']['inputTessellationUnchanged']
    assert report['solverCoordinates']['unitsAndObjectTransformRestored']
    assert not report['solverCoordinates']['physicalVertexWeldOrPerturbation']
    assert report['inputGeometrySha256']==source and finish.mesh_identity(high)==high_source
    assert tuple(low.scale)==(1,1,1)
    results.append(report)
assert results[0]['outputGeometrySha256']==results[1]['outputGeometrySha256']
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(results,indent=2))
""")

    def test_39_default_solver_basis_never_selects_an_implicit_repair(self):
        self.helper_probe("solver-default-short", self.short_edge_cube_source() + """low=make_cube();before=finish.mesh_identity(low)
for operation in [lambda:finish.prepare_topology(low,{'method':'none'}),lambda:finish.run_quadriflow(low,200)]:
    try:operation()
    except ValueError as error:assert 'precondition' in str(error) and 'coordinateScale' in str(error),str(error)
    else:raise AssertionError('Default1 silently selected another numerical basis or repair')
    assert finish.mesh_identity(low)==before and tuple(low.scale)==(1,1,1)
""")

    def test_40_solver_basis_preserves_nearby_disconnected_components_before_operator(self):
        self.helper_probe("solver-component-identity", self.short_edge_cube_source() + """import bmesh
from types import SimpleNamespace
low=make_cube();bm=bmesh.new();bm.from_mesh(low.data)
extra=bmesh.ops.create_cube(bm,size=1)['verts']
for vertex in extra:vertex.co=tuple(a+b for a,b in zip(vertex.co,(.5,.5,1.50005)))
bm.to_mesh(low.data);bm.free();bpy.context.view_layer.update()
before=finish.mesh_identity(low);world=finish.world_vertices(low);counts=(len(low.data.vertices),len(low.data.edges),len(low.data.polygons))
def barrier(*args,**kwargs):
    # Explicit simulated operator barrier proves representation-only invariants.
    assert args==('EXEC_DEFAULT',) and kwargs['mode']=='FACES'
    assert kwargs['use_mesh_symmetry'] is False and kwargs['preserve_attributes'] is False
    assert finish.np.array_equal(world,finish.world_vertices(low))
    assert counts==(len(low.data.vertices),len(low.data.edges),len(low.data.polygons))
    mesh=bmesh.new();mesh.from_mesh(low.data);unvisited=set(mesh.verts);components=0
    while unvisited:
        components+=1;stack=[unvisited.pop()]
        while stack:
            for edge in stack.pop().link_edges:
                for vertex in edge.verts:
                    if vertex in unvisited:unvisited.remove(vertex);stack.append(vertex)
    mesh.free();assert components==2
    return {'CANCELLED'}
original_bpy=finish.bpy
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(quadriflow_remesh=barrier)))
try:
    try:finish.run_quadriflow(low,200,1024)
    except ValueError as error:assert 'CANCELLED' in str(error),str(error)
    else:raise AssertionError('Cancellation was accepted')
finally:finish.bpy=original_bpy
assert finish.mesh_identity(low)==before and finish.np.array_equal(world,finish.world_vertices(low))
""")

    def test_41_actual_solver_basis_keeps_transformed_worlds_and_original_units(self):
        self.helper_probe("solver-transformed-world", self.short_edge_cube_source() + """from mathutils import Matrix
results=[]
for name,matrix in [('translated',Matrix.Translation((.5,-2,3))),('rotated-nonuniform',Matrix.Translation((.5,-2,3))@Matrix.Rotation(.4,4,'Z')@Matrix.Diagonal((2,1.3,.5,1))),('reflected',Matrix.Translation((.5,-2,3))@Matrix.Diagonal((-2,1,.5,1)))]:
    low=make_cube();low.matrix_world=matrix;bpy.context.view_layer.update()
    scale=tuple(low.scale);matrix_before=finish.np.asarray(low.matrix_world).copy()
    result=finish.run_quadriflow(low,200,1024)
    assert result['solverCoordinates']['worldVertexErrorBeforeOperatorMetres']==0
    assert result['solverCoordinates']['inputTessellationUnchanged']
    assert tuple(low.scale)==scale and finish.np.array_equal(matrix_before,finish.np.asarray(low.matrix_world))
    assert result['topology']['boundaryEdges']==result['topology']['nonManifoldVertices']==0
    results.append({'id':name,'actualQuadriFlow':result['operatorStatus'],'coordinates':result['solverCoordinates']})
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(results,indent=2))
""")

    def test_42_solver_failure_cancel_noop_and_partial_mutation_restore_original(self):
        self.helper_probe("solver-rollback", self.short_edge_cube_source() + """from types import SimpleNamespace
for mode in ['cancel','throw','noop','partial-mutation']:
    low=make_cube();bpy.context.view_layer.update();source=finish.mesh_identity(low);original_data=low.data
    matrix=finish.np.asarray(low.matrix_world).copy();world=finish.world_vertices(low)
    def fail(*args,**kwargs):
        # Explicit fault injection, not an engine-completion claim.
        if mode=='partial-mutation':low.data.vertices[0].co.x+=10
        if mode=='throw':raise RuntimeError('SIMULATED native interruption')
        return {'FINISHED'} if mode=='noop' else {'CANCELLED'}
    original_bpy=finish.bpy
    finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(quadriflow_remesh=fail)))
    try:
        try:finish.run_quadriflow(low,200,1024)
        except (ValueError,RuntimeError):pass
        else:raise AssertionError('Unsuccessful/no-op operator was accepted: '+mode)
    finally:finish.bpy=original_bpy
    assert low.data==original_data and finish.mesh_identity(low)==source
    assert finish.np.array_equal(world,finish.world_vertices(low)) and finish.np.array_equal(matrix,finish.np.asarray(low.matrix_world))
""")

    def test_43_vertex_link_manifold_gate_rejects_bowtie_shells(self):
        self.helper_probe("bowtie-vertex-rejected", """import bmesh
bpy.ops.wm.read_factory_settings(use_empty=True)
bm=bmesh.new();first=bmesh.ops.create_cube(bm,size=1)['verts'];second=bmesh.ops.create_cube(bm,size=1)['verts']
for vertex in second:vertex.co=tuple(a+b for a,b in zip(vertex.co,(1,1,1)))
a=max(first,key=lambda vertex:sum(vertex.co));b=min(second,key=lambda vertex:sum(vertex.co))
bmesh.ops.weld_verts(bm,targetmap={b:a})
mesh=bpy.data.meshes.new('Bowtie');bm.to_mesh(mesh);bm.free();low=bpy.data.objects.new('Bowtie',mesh);bpy.context.collection.objects.link(low)
measured=finish.topology_measure(low)
assert measured['nonManifoldEdges']==0 and measured['nonManifoldVertices']>0
try:finish.require_usable(low,'Bowtie')
except ValueError as error:assert 'requires closed manifold' in str(error),str(error)
else:raise AssertionError('Disconnected vertex fan was accepted as manifold')
""")

    def test_44_solver_scale_selection_is_explicit_closed_and_bounded(self):
        self.helper_probe("solver-settings", """base={'schemaVersion':1,'topologyPreparation':{'method':'none'},'collision':{'method':'exact-hull'}}
assert finish.validate_finishing_settings(base)==base
for scale in [1,2,4,8,16,32,64,128,256,512,1024,1024.0]:
    value=dict(base,quadriFlow={'coordinateScale':scale})
    result=finish.validate_finishing_settings(value)
    assert type(result['quadriFlow']['coordinateScale']) is int and result['quadriFlow']['coordinateScale']==scale
for quadri_flow in [None,{},[],{'coordinateScale':True},{'coordinateScale':0},{'coordinateScale':-2},{'coordinateScale':3},{'coordinateScale':1025},{'coordinateScale':1.5},{'coordinateScale':'1024'},{'coordinateScale':float('inf')},{'coordinateScale':float('nan')},{'coordinateScale':1024,'fallback':True}]:
    try:finish.validate_finishing_settings(dict(base,quadriFlow=quadri_flow))
    except ValueError:pass
    else:raise AssertionError('Invalid coordinate selection accepted: '+str(quadri_flow))
""")

    def test_45_nonfinite_or_lossy_solver_coordinates_fail_without_mutation(self):
        self.helper_probe("solver-overflow", """bpy.ops.wm.read_factory_settings(use_empty=True)
mesh=bpy.data.meshes.new('Overflow');mesh.from_pydata([(1e36,0,0),(0,1e36,0),(0,0,1e36),(0,0,0)],[],[(0,2,1),(0,1,3),(0,3,2),(1,2,3)]);mesh.update()
low=bpy.data.objects.new('Overflow',mesh);bpy.context.collection.objects.link(low);before=finish.mesh_identity(low)
try:finish.quadriflow_input_measure(low,1024)
except ValueError as error:assert 'finite bit-exact' in str(error),str(error)
else:raise AssertionError('Overflowing solver coordinates were accepted')
assert finish.mesh_identity(low)==before
""")

    def test_46_output_topology_is_checked_after_restoring_original_units(self):
        self.helper_probe("solver-original-unit-guard", self.short_edge_cube_source() + """from types import SimpleNamespace
low=make_cube();source=finish.mesh_identity(low)
def degenerate(*args,**kwargs):
    # Explicit synthetic producer fault: tool-space size must not bypass metre-unit checks.
    for vertex in low.data.vertices:vertex.co*=1e-7
    return {'FINISHED'}
original_bpy=finish.bpy
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(quadriflow_remesh=degenerate)))
try:
    try:finish.run_quadriflow(low,200,1024)
    except ValueError as error:assert 'degenerate' in str(error) or 'positive-volume' in str(error),str(error)
    else:raise AssertionError('Tiny invalid output passed only because solver coordinates were larger')
finally:finish.bpy=original_bpy
assert finish.mesh_identity(low)==source and tuple(low.scale)==(1,1,1)
""")

    def test_47_actual_operator_completion_does_not_replace_output_topology_review(self):
        self.helper_probe("solver-actual-output-guard", """def plain_cube():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    vertices=[(0,0,0),(1,0,0),(1,1,0),(0,1,0),(0,0,1),(1,0,1),(1,1,1),(0,1,1)]
    faces=[(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
    mesh=bpy.data.meshes.new('Plain');mesh.from_pydata(vertices,[],faces);mesh.update()
    low=bpy.data.objects.new('Plain',mesh);bpy.context.collection.objects.link(low);return low
raw=plain_cube();finish.activate(raw)
status=bpy.ops.object.quadriflow_remesh('EXEC_DEFAULT',mode='FACES',target_faces=20,use_preserve_sharp=True,use_preserve_boundary=True,use_mesh_symmetry=False,preserve_attributes=False,seed=0)
assert status=={'FINISHED'}
measured=finish.topology_measure(raw)
invalid=any(measured[key] for key in ['boundaryEdges','nonManifoldEdges','nonManifoldVertices','inconsistentWindingEdges','looseVertices']) or measured['signedVolume']<=1e-15
low=plain_cube();before=finish.mesh_identity(low)
if invalid:
    try:finish.run_quadriflow(low,20)
    except ValueError as error:assert 'closed manifold' in str(error),str(error)
    else:raise AssertionError('Actual invalid completed output was accepted')
    assert finish.mesh_identity(low)==before
else:
    assert finish.run_quadriflow(low,20)['topology']['boundaryEdges']==0
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps({'actualStatus':sorted(status),'actualOutput':measured,'invalidOutputCorrectlyRejected':invalid},indent=2))
""")

    def test_48_changed_tessellation_stops_before_operator_and_restores_source(self):
        self.helper_probe("solver-tessellation-guard", self.short_edge_cube_source() + """from types import SimpleNamespace
low=make_cube();source=finish.mesh_identity(low);original_triangles=finish.triangle_indices;calls=[0,0]
def changed(obj):
    values=original_triangles(obj);calls[0]+=1
    # Explicit simulated incompatible tessellator, not actual Blender evidence.
    if calls[0]==2:values[:3]=values[:3][::-1]
    return values
def unreachable(*args,**kwargs):calls[1]+=1;raise AssertionError('Operator launched after tessellation drift')
original_bpy=finish.bpy;finish.triangle_indices=changed
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(quadriflow_remesh=unreachable)))
try:
    try:finish.run_quadriflow(low,200,1024)
    except ValueError as error:assert 'tessellation' in str(error),str(error)
    else:raise AssertionError('Changed tessellation was accepted')
finally:finish.bpy=original_bpy;finish.triangle_indices=original_triangles
assert calls[1]==0 and finish.mesh_identity(low)==source and tuple(low.scale)==(1,1,1)
""")


    @staticmethod
    def simplification_fixture_source():
        return """def sphere():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4,radius=1)
    return bpy.context.object
def selection(target=500,error=.5,regions=None):
    return {'method':'collapse','targetTriangles':target,'maxVertexSurfaceErrorMetres':error,'protectedRegions':regions or []}
"""

    def test_49_simplification_contract_is_explicit_closed_and_bounded(self):
        self.helper_probe("simplification-settings", """import copy
valid={'method':'collapse','targetTriangles':1000000,'maxVertexSurfaceErrorMetres':.0005,'protectedRegions':[]}
assert finish.validate_simplification(valid)==valid
assert finish.validate_simplification(dict(valid,targetTriangles=1000000.0))['targetTriangles']==1000000
region={'id':'Risk_1.a','min':[-1,-2,-3],'max':[1,2,3]}
assert finish.validate_simplification(dict(valid,protectedRegions=[region,dict(region,id='risk_1.a')]))
invalid=[None,{},dict(valid,method='automatic'),dict(valid,fallback=True),dict(valid,targetTriangles=True),
    dict(valid,targetTriangles=3),dict(valid,targetTriangles=8000001),dict(valid,targetTriangles=5.5),
    dict(valid,targetTriangles=10**1000),dict(valid,maxVertexSurfaceErrorMetres=0),dict(valid,maxVertexSurfaceErrorMetres=True),
    dict(valid,maxVertexSurfaceErrorMetres=float('nan')),dict(valid,maxVertexSurfaceErrorMetres=1.1),
    dict(valid,protectedRegions=None),dict(valid,protectedRegions=[region]*2),
    dict(valid,protectedRegions=[dict(region,id='bad\\n')]),dict(valid,protectedRegions=[dict(region,id='a\\u00e9')]),
    dict(valid,protectedRegions=[dict(region,id='')]),dict(valid,protectedRegions=[dict(region,id='a'*81)]),
    dict(valid,protectedRegions=[dict(region,min=[True,0,0])]),dict(valid,protectedRegions=[dict(region,min=[0,0])]),
    dict(valid,protectedRegions=[dict(region,min=[float('inf'),0,0])]),
    dict(valid,protectedRegions=[dict(region,max=[1e9+1,2,3])]),dict(valid,protectedRegions=[dict(region,max=[-1,2,3])]),
    dict(valid,protectedRegions=[dict(region,extra=1)])]
for value in invalid:
    try:finish.validate_simplification(value)
    except ValueError:pass
    else:raise AssertionError('Invalid simplification accepted: '+str(value))
base={'schemaVersion':1,'topologyPreparation':{'method':'none'},'collision':{'method':'exact-hull'}}
assert 'quadriFlow' not in finish.validate_finishing_settings(base)
configured=dict(base,quadriFlow={'coordinateScale':1024,'simplification':valid})
assert finish.validate_finishing_settings(configured)==configured
""")

    def test_50_actual_collapse_preserves_prepared_source_and_all_vertex_evidence(self):
        self.helper_probe("simplification-actual", self.simplification_fixture_source() + """low=sphere()
original=low.data;before=finish.mesh_identity(low);world=finish.world_vertices(low);objects=set(bpy.data.objects)
result=finish.simplify_quadriflow_input(low,selection(),1024)
assert result['operatorCalls']==1 and result['outputTriangles']<=500 and result['inputTriangles']>500
assert result['componentIdentitiesAndEulerPreserved'] and result['sourceComponents'][0]['eulerCharacteristic']==2
assert result['outputComponents'][0]['id']==result['sourceComponents'][0]['id']==1
assert low.data!=original and finish.mesh_identity(low)!=before and set(bpy.data.objects)==objects
saved=low.data;low.data=original
assert finish.mesh_identity(low)==before and finish.np.array_equal(world,finish.world_vertices(low))
low.data=saved
assert result['surfaceError']['sourceToCandidate']['queries']==len(original.vertices)
assert result['surfaceError']['candidateToSource']['queries']==len(low.data.vertices)
assert all(result['surfaceError'][direction]['allVerticesMeasured'] for direction in ['sourceToCandidate','candidateToSource'])
assert result['quadriFlowPreflight']['compatible']
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(result,indent=2))
""")

    def test_51_actual_verified_holds_retain_original_local_surface_vertices(self):
        self.helper_probe("simplification-held-protection", """from mathutils.bvhtree import BVHTree
bpy.ops.wm.read_factory_settings(use_empty=True)
measurements=[]
for protected in [False,True]:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=5,radius=1)
    low=bpy.context.object;source=finish.world_vertices(low);selected=source[source[:,2]>.7]
    regions=[{'id':'north-detail','min':[-1.1,-1.1,.7],'max':[1.1,1.1,1.1]}] if protected else []
    settings={'method':'collapse','targetTriangles':2000,'maxVertexSurfaceErrorMetres':1,'protectedRegions':regions}
    result=finish.simplify_quadriflow_input(low,settings,1024)
    tree=BVHTree.FromPolygons(finish.world_vertices(low),finish.triangle_indices(low).reshape((-1,3)),all_triangles=True)
    local=finish.vertex_surface_measure(selected,tree,finish.np.zeros(3))
    measurements.append({'protected':protected,'localMaximum':local['maximumMetres'],'global':result['surfaceError'],
        'protection':result['protection'],'hits':result['protectedRegionHitCounts'],'hold':result['heldVertexProof']})
assert measurements[0]['localMaximum']>0
assert measurements[1]['localMaximum'] < measurements[0]['localMaximum']*.5,measurements
assert measurements[1]['protection']['insideWeight']==0 and measurements[1]['protection']['outsideWeight']==1
assert measurements[1]['protection']['vertexGroupFactor']==1000
assert measurements[1]['hold']['heldVertices']>0 and measurements[1]['hold']['allOriginalIdsSurviveExactlyOnce'] and measurements[1]['hold']['float32CoordinatesBitIdentical']
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(measurements,indent=2))
""")

    def test_52_actual_world_metric_supports_rotated_nonuniform_and_reflected_objects(self):
        self.helper_probe("simplification-transformed", self.simplification_fixture_source() + """from mathutils import Matrix
results=[]
for reflected in [False,True]:
    low=sphere();low.matrix_world=Matrix.Translation((100,-2,3))@Matrix.Rotation(.4,4,'Z')@Matrix.Diagonal(((-2 if reflected else 2),.5,1.5,1))
    bpy.context.view_layer.update();matrix=finish.np.asarray(low.matrix_world).copy();world=finish.world_vertices(low)
    center=world.mean(axis=0);region={'id':'world-box','min':(center-finish.np.array([.7,.7,.7])).tolist(),'max':(center+finish.np.array([.7,.7,.7])).tolist()}
    result=finish.simplify_quadriflow_input(low,selection(target=900,error=.5,regions=[region]),1024)
    assert finish.np.array_equal(matrix,finish.np.asarray(low.matrix_world))
    assert result['protectedRegionHitCounts']['world-box']>0 and result['outputTriangles']<=900
    assert result['surfaceError']['sourceToCandidate']['measuredMaximumPlusRepresentationErrorsMetres']<=.5
    results.append({'reflected':reflected,'result':result})
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(results,indent=2))
""")

    def test_53_component_identity_rejects_equal_id_splits_and_mixed_id_merges(self):
        self.helper_probe("simplification-component-identity", """import bmesh
for mode in ['split','merge']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm=bmesh.new();bmesh.ops.create_cube(bm,size=1);second=bmesh.ops.create_cube(bm,size=1)['verts']
    for vertex in second:vertex.co.x+=3
    mesh=bpy.data.meshes.new('TwoShells');bm.to_mesh(mesh);bm.free()
    low=bpy.data.objects.new('TwoShells',mesh);bpy.context.collection.objects.link(low)
    inventory,ids=finish.component_inventory(low);assert len(inventory)==2
    if mode=='split':ids[:]=1
    else:ids[0]=2 if ids[0]==1 else 1
    attribute=mesh.attributes.new('Identity','INT','POINT');attribute.data.foreach_set('value',ids)
    try:finish.component_inventory(low,'Identity')
    except ValueError as error:assert 'merged, split or corrupted' in str(error),str(error)
    else:raise AssertionError('Invalid component identity was accepted: '+mode)
""")

    def test_54_simplification_cancel_throw_and_partial_failure_leave_no_owned_resources(self):
        self.helper_probe("simplification-operator-rollback", self.simplification_fixture_source() + """from types import SimpleNamespace
for mode in ['cancel','throw','partial']:
    low=sphere();before=finish.mesh_identity(low);original=low.data;objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
    def fault(*args,**kwargs):
        candidate=bpy.context.object
        if mode=='partial':candidate.data.vertices[0].co.x+=100
        if mode=='throw':raise RuntimeError('SIMULATED interrupted modifier')
        return {'CANCELLED'}
    original_bpy=finish.bpy
    finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(modifier_apply=fault)))
    try:
        try:finish.simplify_quadriflow_input(low,selection(),1024)
        except (ValueError,RuntimeError):pass
        else:raise AssertionError('Injected operator failure was accepted')
    finally:finish.bpy=original_bpy
    assert low.data==original and finish.mesh_identity(low)==before
    assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
    assert low.data.attributes.get('_hephaera_prepared_component_id') is None
""")

    def test_55_actual_full_surface_error_failure_rolls_back(self):
        self.helper_probe("simplification-error-rollback", self.simplification_fixture_source() + """low=sphere();source=finish.mesh_identity(low);original=low.data
objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
try:finish.simplify_quadriflow_input(low,selection(error=1e-12),1024)
except ValueError as error:assert 'exceeds maxVertexSurfaceErrorMetres' in str(error),str(error)
else:raise AssertionError('Actual surface deviation exceeded the explicit budget without rejection')
assert low.data==original and finish.mesh_identity(low)==source
assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
""")

    def test_56_hard_triangle_cap_stops_before_surface_verification(self):
        self.helper_probe("simplification-cap-before-proof", self.simplification_fixture_source() + """from types import SimpleNamespace
low=sphere();source=finish.mesh_identity(low);calls=[0]
def unchanged(*args,**kwargs):return {'FINISHED'} # Explicit simulated producer no-op.
def unreachable(*args,**kwargs):calls[0]+=1;raise AssertionError('Surface proof ran before the hard cap')
original_bpy=finish.bpy;original_metric=finish.surface_deviation
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(modifier_apply=unchanged)))
finish.surface_deviation=unreachable
try:
    try:finish.simplify_quadriflow_input(low,selection(),1024)
    except ValueError as error:assert 'hard input triangle cap' in str(error),str(error)
    else:raise AssertionError('Oversized producer result was accepted')
finally:finish.bpy=original_bpy;finish.surface_deviation=original_metric
assert calls[0]==0 and finish.mesh_identity(low)==source
""")

    def test_57_optional_absence_and_already_within_cap_make_no_operator_call(self):
        self.helper_probe("simplification-already-small", self.simplification_fixture_source() + """from types import SimpleNamespace
low=sphere();source=finish.mesh_identity(low)
assert finish.simplify_quadriflow_input(low,None)=={'selected':False,'operatorCalls':0}
def unreachable(*args,**kwargs):raise AssertionError('Unneeded modifier was launched')
original_bpy=finish.bpy
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(modifier_apply=unreachable)))
try:result=finish.simplify_quadriflow_input(low,selection(target=2000),1024)
finally:finish.bpy=original_bpy
assert result['status']=='already-within-cap' and result['operatorCalls']==0 and result['outputTriangles']==1280
assert result['surfaceError']['sourceToCandidate']['maximumMetres']==0
assert result['surfaceError']['sourceToCandidate']['queries']==0 and finish.mesh_identity(low)==source
""")

    def test_58_region_misses_are_rejected_or_explicitly_deferred_to_asset_aggregation(self):
        self.helper_probe("simplification-region-miss", self.simplification_fixture_source() + """low=sphere();source=finish.mesh_identity(low)
regions=[{'id':'other-part','min':[10,10,10],'max':[11,11,11]}]
try:finish.simplify_quadriflow_input(low,selection(target=2000,regions=regions),1024)
except ValueError as error:assert 'misses every prepared vertex' in str(error),str(error)
else:raise AssertionError('Single-part protection silently missed')
result=finish.simplify_quadriflow_input(low,selection(target=2000,regions=regions),1024,require_region_hits=False)
assert result['protectedRegionHitCounts']=={'other-part':0} and result['operatorCalls']==0
assert finish.mesh_identity(low)==source
""")

    def test_59_surface_metric_uses_triangle_interiors_and_every_vertex(self):
        self.helper_probe("simplification-triangle-metric", """bpy.ops.wm.read_factory_settings(use_empty=True)
def plane(name,vertices,faces):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);return obj
source=plane('Square',[(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0)],[(0,1,2),(0,2,3)])
candidate=plane('WithCenter',[(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0),(0,0,0)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)])
result=finish.surface_deviation(source,candidate)
assert result['sourceToCandidate']['queries']==4 and result['candidateToSource']['queries']==5
assert result['candidateToSource']['maximumMetres']<1e-7
assert 'not a continuous-surface Hausdorff' in result['limits']
""")

    def test_60_interrupted_surface_measurement_restores_input_and_resources(self):
        self.helper_probe("simplification-metric-interruption", self.simplification_fixture_source() + """low=sphere();source=finish.mesh_identity(low);original=low.data
objects=set(bpy.data.objects);meshes=set(bpy.data.meshes);actual=finish.vertex_surface_measure
def interrupt(*args,**kwargs):raise KeyboardInterrupt('SIMULATED interruption during surface proof')
finish.vertex_surface_measure=interrupt
try:
    try:finish.simplify_quadriflow_input(low,selection(),1024)
    except KeyboardInterrupt:pass
    else:raise AssertionError('Interrupted evidence was accepted')
finally:finish.vertex_surface_measure=actual
assert low.data==original and finish.mesh_identity(low)==source
assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
""")

    def test_61_actual_multipart_asset_aggregates_world_region_hits(self):
        settings = self.finish_settings(topologyPreparation={"method": "none"},
            collision={"method": "exact-hull"})
        settings["quadriFlow"] = {"coordinateScale": 1024, "simplification": {
            "method": "collapse", "targetTriangles": 5000, "maxVertexSurfaceErrorMetres": .1,
            "protectedRegions": [{"id": "satellite-only", "min": [5.4, .4, 1.4], "max": [6.6, 1.6, 2.6]}]}}
        job, value = self.job("multipart-protection", input=(self.work / "synthetic-multipart.glb").relative_to(ROOT).as_posix(), finishingSettings=settings)
        self.run_blender(SCRIPTS / "finish.py", job, "multipart-protection")
        result = json.loads((ROOT / value["result"]).read_text())
        counts = [part["simplification"]["protectedRegionHitCounts"]["satellite-only"] for part in result["measurements"]["parts"]]
        self.assertEqual(len(counts), 2)
        self.assertIn(0, counts)
        self.assertGreater(sum(counts), 0)
        stage = next(stage for stage in result["stages"] if stage["stage"] == "explicitWorkingInputSimplification")
        self.assertEqual(stage["protectedRegionHitCountsAcrossParts"]["satellite-only"], sum(counts))

    def test_62_all_multipart_region_misses_cannot_complete(self):
        settings = self.finish_settings(topologyPreparation={"method": "none"},
            collision={"method": "exact-hull"})
        settings["quadriFlow"] = {"coordinateScale": 1024, "simplification": {
            "method": "collapse", "targetTriangles": 5000, "maxVertexSurfaceErrorMetres": .1,
            "protectedRegions": [{"id": "miss", "min": [50, 50, 50], "max": [51, 51, 51]}]}}
        job, value = self.job("multipart-protection-miss", input=(self.work / "synthetic-multipart.glb").relative_to(ROOT).as_posix(), finishingSettings=settings)
        result = self.run_blender(SCRIPTS / "finish.py", job, "multipart-protection-miss", success=False)
        self.assertIn("across the asset", result.stdout)
        self.assertFalse((ROOT / value["result"]).exists())

    def test_63_source_vertex_groups_survive_real_protected_collapse(self):
        self.helper_probe("simplification-source-groups", self.simplification_fixture_source() + """low=sphere()
group=low.vertex_groups.new(name='ExistingSourceGroup');group.add([0,1,2],.75,'REPLACE')
source_mesh=low.data;source_hash=finish.mesh_identity(low)
definitions=[(item.name,item.index) for item in low.vertex_groups]
weights=[[(weight.group,weight.weight) for weight in vertex.groups] for vertex in source_mesh.vertices]
regions=[{'id':'small-north','min':[-.5,-.5,.8],'max':[.5,.5,1.1]}]
result=finish.simplify_quadriflow_input(low,selection(error=.5,regions=regions),1024)
assert [(item.name,item.index) for item in low.vertex_groups]==definitions
assert [entry for entry in low.vertex_groups if entry.name.startswith('HephaeraHeldDetailVertices')]==[]
saved=low.data;low.data=source_mesh
assert finish.mesh_identity(low)==source_hash
assert [[(weight.group,weight.weight) for weight in vertex.groups] for vertex in source_mesh.vertices]==weights
low.data=saved
assert result['operatorCalls']==1 and result['protectedVertexCount']>0
""")

    def test_64_corrupt_or_moved_held_vertex_proofs_reject_and_restore(self):
        self.helper_probe("simplification-held-proof-faults", self.simplification_fixture_source() + """from types import SimpleNamespace
for mode in ['missing-id','duplicate-id','invented-id','missing-attribute','moved-coordinate']:
    low=sphere();before=finish.mesh_identity(low);original=low.data;objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
    real_apply=bpy.ops.object.modifier_apply;calls=[0]
    def faulty(*args,**kwargs):
        calls[0]+=1;result=real_apply(*args,**kwargs);candidate=bpy.context.object
        attribute=candidate.data.attributes.get('_hephaera_prepared_vertex_id')
        values=finish.np.empty(len(candidate.data.vertices),dtype=finish.np.int32);attribute.data.foreach_get('value',values)
        selected=finish.np.flatnonzero(values)
        assert len(selected)>1
        if mode=='missing-attribute':candidate.data.attributes.remove(attribute)
        elif mode=='moved-coordinate':candidate.data.vertices[int(selected[0])].co.x+=.0001
        else:
            values[selected[0]]=0 if mode=='missing-id' else values[selected[1]] if mode=='duplicate-id' else 999999
            attribute.data.foreach_set('value',values)
        return result
    actual_bpy=finish.bpy
    finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(modifier_apply=faulty)))
    try:
        try:finish.simplify_quadriflow_input(low,selection(target=800,regions=[{'id':'north','min':[-.5,-.5,.8],'max':[.5,.5,1.1]}]),1024)
        except ValueError as error:assert 'protected original vertex' in str(error),str(error)
        else:raise AssertionError('Corrupt held evidence was accepted: '+mode)
    finally:finish.bpy=actual_bpy
    assert calls[0]==1 and low.data==original and finish.mesh_identity(low)==before
    assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
""")

    def test_65_already_within_cap_records_actual_protected_vertex_identity(self):
        self.helper_probe("simplification-unchanged-held-proof", self.simplification_fixture_source() + """low=sphere();before=finish.mesh_identity(low)
regions=[{'id':'north','min':[-.5,-.5,.8],'max':[.5,.5,1.1]}]
result=finish.simplify_quadriflow_input(low,selection(target=2000,regions=regions),1024)
assert result['operatorCalls']==0 and result['status']=='already-within-cap'
assert result['heldVertexProof']['heldVertices']==result['protectedVertexCount']>0
assert result['heldVertexProof']['float32CoordinatesBitIdentical']
assert 'unchanged mesh identity' in result['heldVertexProof']['verificationMethod']
assert finish.mesh_identity(low)==before and low.data.attributes.get('_hephaera_prepared_vertex_id') is None
""")

    def test_66_unachievable_cap_with_all_vertices_held_never_retries_or_raises_cap(self):
        self.helper_probe("simplification-held-cap-blocked", self.simplification_fixture_source() + """from types import SimpleNamespace
low=sphere();before=finish.mesh_identity(low);original=low.data;real_apply=bpy.ops.object.modifier_apply;calls=[0]
def counted(*args,**kwargs):calls[0]+=1;return real_apply(*args,**kwargs)
actual_bpy=finish.bpy
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(modifier_apply=counted)))
try:
    try:finish.simplify_quadriflow_input(low,selection(target=4,regions=[{'id':'all','min':[-1.1,-1.1,-1.1],'max':[1.1,1.1,1.1]}]),1024)
    except ValueError as error:assert 'hard input triangle cap' in str(error),str(error)
    else:raise AssertionError('Unachievable held-input cap was silently increased')
finally:finish.bpy=actual_bpy
assert calls[0]==1 and low.data==original and finish.mesh_identity(low)==before
""")

    def test_67_existing_reserved_held_attribute_is_preserved_and_refused(self):
        self.helper_probe("simplification-held-attribute-collision", self.simplification_fixture_source() + """low=sphere();before=finish.mesh_identity(low)
attribute=low.data.attributes.new('_hephaera_prepared_vertex_id','INT','POINT')
values=finish.np.full(len(low.data.vertices),77,dtype=finish.np.int32);attribute.data.foreach_set('value',values)
try:finish.simplify_quadriflow_input(low,selection(regions=[{'id':'north','min':[-.5,-.5,.8],'max':[.5,.5,1.1]}]),1024)
except ValueError as error:assert 'reserved simplification vertex identity' in str(error),str(error)
else:raise AssertionError('Existing identity attribute was overwritten')
actual=finish.np.empty(len(low.data.vertices),dtype=finish.np.int32);attribute.data.foreach_get('value',actual)
assert finish.np.array_equal(actual,values) and finish.mesh_identity(low)==before
""")

    def test_68_operator_transform_changes_reject_before_committing_geometry(self):
        self.helper_probe("simplification-transform-fault", self.simplification_fixture_source() + """from types import SimpleNamespace
low=sphere();before=finish.mesh_identity(low);world=finish.world_vertices(low);original=low.data
real_apply=bpy.ops.object.modifier_apply
def moved(*args,**kwargs):
    result=real_apply(*args,**kwargs);bpy.context.object.location.x+=.01;return result
actual_bpy=finish.bpy
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(modifier_apply=moved)))
try:
    try:finish.simplify_quadriflow_input(low,selection(),1024)
    except ValueError as error:assert 'source transform' in str(error),str(error)
    else:raise AssertionError('Output measured in a different transform was committed')
finally:finish.bpy=actual_bpy
assert low.data==original and finish.mesh_identity(low)==before and finish.np.array_equal(world,finish.world_vertices(low))
""")

    @staticmethod
    def retained_component_fixture_source():
        return """import bmesh
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4,radius=1)
low=bpy.context.object
bpy.ops.mesh.primitive_cube_add(size=.04)
small=bpy.context.object
for vertex in small.data.vertices:
    vertex.co.x+=3
    if vertex.co.x>3 and vertex.co.y>0 and vertex.co.z>0:vertex.co.z+=.025
bm=bmesh.new();bm.from_mesh(low.data);bm.from_mesh(small.data);bm.to_mesh(low.data);bm.free()
small_mesh=small.data;bpy.data.objects.remove(small,do_unlink=True)
if small_mesh.users==0:bpy.data.meshes.remove(small_mesh)
mesh=low.data
for name,kind,domain,field in [('OwnedPoint','FLOAT','POINT','value'),('OwnedEdge','INT','EDGE','value'),('OwnedFace','INT','FACE','value'),('OwnedCorner','FLOAT','CORNER','value')]:
    attribute=mesh.attributes.new(name,kind,domain)
    for index,item in enumerate(attribute.data):setattr(item,field,index+1 if kind=='INT' else (index+1)/8192)
uv=mesh.uv_layers.new(name='OwnedUV')
for index,item in enumerate(uv.data):item.uv=((index+1)/8192,(index+2)/8192)
for name,domain in [('OwnedPointColor','POINT'),('OwnedCornerColor','CORNER')]:
    color=mesh.color_attributes.new(name,'FLOAT_COLOR',domain)
    for index,item in enumerate(color.data):item.color=((index%11)/16,(index%7)/16,(index%5)/16,1)
material=bpy.data.materials.new('RetainedBronze');other=bpy.data.materials.new('RetainedCyan')
for item in [material,other,material]:mesh.materials.append(item)
for polygon in mesh.polygons:polygon.material_index=polygon.index%3;polygon.use_smooth=bool(polygon.index%2)
for name,weight in [('OwnedA',.375),('OwnedB',.125)]:
    group=low.vertex_groups.new(name=name)
    group.add([vertex.index for vertex in mesh.vertices if vertex.co.x>2],weight,'REPLACE')
mesh.update()
"""

    def test_69_exact_component_retention_avoids_held_vertex_triangulation_counterexample(self):
        self.helper_probe("simplification-retained-components", self.retained_component_fixture_source() + """before=finish.mesh_identity(low);original=low.data
retained_faces=sum(all(mesh.vertices[index].co.x>2 for index in polygon.vertices) for polygon in mesh.polygons)
naive=low.copy();naive.data=low.data.copy();bpy.context.collection.objects.link(naive)
group=naive.vertex_groups.new(name='HeldControl');group.add(list(range(len(mesh.vertices))),1.,'REPLACE')
group.add([vertex.index for vertex in mesh.vertices if vertex.co.x>2],0.,'REPLACE')
modifier=naive.modifiers.new('SingleNaiveControl','DECIMATE');modifier.ratio=512/finish.triangles(naive)
modifier.vertex_group=group.name;modifier.vertex_group_factor=1000.;modifier.use_collapse_triangulate=True
finish.activate(naive);assert bpy.ops.object.modifier_apply(modifier=modifier.name)=={'FINISHED'}
naive_faces=sum(all(naive.data.vertices[index].co.x>2 for index in polygon.vertices) for polygon in naive.data.polygons)
assert retained_faces==6 and naive_faces==12
assert sorted(finish.np.asarray(vertex.co,dtype=finish.np.float32).tobytes() for vertex in mesh.vertices if vertex.co.x>2)==sorted(finish.np.asarray(vertex.co,dtype=finish.np.float32).tobytes() for vertex in naive.data.vertices if vertex.co.x>2)
naive_mesh=naive.data;bpy.data.objects.remove(naive,do_unlink=True)
if naive_mesh.users==0:bpy.data.meshes.remove(naive_mesh)
result=finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':512,'maxVertexSurfaceErrorMetres':.5,
    'protectedRegions':[{'id':'small-shell','min':[2.9,-.1,-.1],'max':[3.1,.1,.1]}]},1024)
retention=result['componentRetention']
assert result['operatorCalls']==1 and result['outputTriangles']<=512
assert retention['retainedTriangles']==12 and retention['mainInputTriangles']==1280 and retention['mainTargetTriangleCap']==500
assert retention['isolationProof']['snapshotSha256']==retention['recombinationProof']['snapshotSha256']==retention['sourceSnapshotSha256']
assert retention['recombinationProof']['originalPolygons']==6 and retention['recombinationProof']['originalVertices']==8
assert result['heldVertexProof']['heldVertices']==8 and result['heldVertexProof']['float32CoordinatesBitIdentical']
assert [group.name for group in low.vertex_groups]==['OwnedA','OwnedB']
saved=low.data;low.data=original;assert finish.mesh_identity(low)==before;low.data=saved
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps({'naiveHeldPolygonChange':[retained_faces,naive_faces],'result':result},indent=2))
""")

    def test_70_retained_triangle_budget_rejects_before_modifier(self):
        self.helper_probe("simplification-retained-cap", self.retained_component_fixture_source() + """from types import SimpleNamespace
source=finish.mesh_identity(low);original=low.data;calls=[0]
def unreachable(*args,**kwargs):calls[0]+=1;raise AssertionError('Modifier launched without main triangle budget')
actual_bpy=finish.bpy
finish.bpy=SimpleNamespace(context=bpy.context,data=bpy.data,ops=SimpleNamespace(object=SimpleNamespace(modifier_apply=unreachable)))
try:
    try:finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':12,'maxVertexSurfaceErrorMetres':.5,'protectedRegions':[]},1024)
    except ValueError as error:assert 'fewer than four triangles' in str(error),str(error)
    else:raise AssertionError('Retained triangles silently exceeded the caller cap')
finally:finish.bpy=actual_bpy
assert calls[0]==0 and low.data==original and finish.mesh_identity(low)==source
""")

    def test_71_retained_attribute_and_face_identity_corruption_reject_and_cleanup(self):
        self.helper_probe("simplification-retained-corruption", self.retained_component_fixture_source() + """source=finish.mesh_identity(low);original=low.data
for mode in ['corner-attribute','face-identity']:
    actual_verify=finish.verify_retained_snapshot;calls=[0];objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
    def corrupted(mesh,*args,**kwargs):
        calls[0]+=1
        if calls[0]==2:
            marker=mesh.attributes['_hephaera_retained_face_id'];ids=finish.np.empty(len(mesh.polygons),dtype=finish.np.int32);marker.data.foreach_get('value',ids)
            selected=finish.np.flatnonzero(ids)
            if mode=='face-identity':marker.data[int(selected[0])].value=int(ids[selected[1]])
            else:mesh.attributes['OwnedCorner'].data[mesh.polygons[int(selected[0])].loop_start].value+=1
        return actual_verify(mesh,*args,**kwargs)
    finish.verify_retained_snapshot=corrupted
    try:
        try:finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':512,'maxVertexSurfaceErrorMetres':.5,'protectedRegions':[]},1024)
        except ValueError as error:assert 'Retained component' in str(error),str(error)
        else:raise AssertionError('Corrupt retained data was accepted: '+mode)
    finally:finish.verify_retained_snapshot=actual_verify
    assert calls[0]==2 and low.data==original and finish.mesh_identity(low)==source
    assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
""")

    def test_72_largest_component_ties_use_lowest_original_identity(self):
        self.helper_probe("simplification-retained-tie", """import bmesh
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=.1);low=bpy.context.object
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=.1);other=bpy.context.object
for vertex in other.data.vertices:vertex.co.x+=3
bm=bmesh.new();bm.from_mesh(low.data);bm.from_mesh(other.data);bm.to_mesh(low.data);bm.free()
other_mesh=other.data;bpy.data.objects.remove(other,do_unlink=True)
if other_mesh.users==0:bpy.data.meshes.remove(other_mesh)
result=finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':120,'maxVertexSurfaceErrorMetres':.1,'protectedRegions':[]},1024)
retention=result['componentRetention']
assert retention['mainOriginalId']==1 and retention['retainedOriginalIds']==[2]
assert retention['mainInputTriangles']==retention['retainedTriangles']==80 and retention['mainTargetTriangleCap']==40
assert result['outputTriangles']<=120 and result['operatorCalls']==1
""")

    def test_73_full_recombined_error_failure_preserves_original_and_owned_mesh_counts(self):
        self.helper_probe("simplification-retained-error-rollback", self.retained_component_fixture_source() + """source=finish.mesh_identity(low);original=low.data
objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
try:finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':512,'maxVertexSurfaceErrorMetres':1e-12,'protectedRegions':[]},1024)
except ValueError as error:assert 'exceeds maxVertexSurfaceErrorMetres' in str(error),str(error)
else:raise AssertionError('Recombined candidate bypassed the full opposing-surface guard')
assert low.data==original and finish.mesh_identity(low)==source
assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
""")

    def test_74_packed_custom_normals_are_retained_as_exact_signed_pairs(self):
        self.helper_probe("simplification-retained-packed-normals", self.retained_component_fixture_source() + """from mathutils import Vector
normal=tuple(Vector((.2,.3,.93)).normalized())
mesh.normals_split_custom_set([normal]*len(mesh.loops))
assert mesh.has_custom_normals and mesh.attributes['custom_normal'].data_type=='INT16_2D'
source=finish.mesh_identity(low);original=low.data
result=finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':512,'maxVertexSurfaceErrorMetres':.5,
    'protectedRegions':[{'id':'small-shell','min':[2.9,-.1,-.1],'max':[3.1,.1,.1]}]},1024)
proof=result['componentRetention']['recombinationProof']
assert 'INT16_2D' in proof['attributeTypes'] and proof['originalIdsAndCoordinatesAndCornersAndAttributesExact']
assert result['componentRetention']['sourceSnapshotSha256']==proof['snapshotSha256']
restored=result['componentRetention']['isolationAttributeRestoration']['restoredMissingAttributes']
assert any(item['name']=='sharp_edge' and item['originalElementsCopied']==12 for item in restored),restored
saved=low.data;low.data=original;assert finish.mesh_identity(low)==source;low.data=saved
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(result,indent=2))
""")

    def test_75_missing_retained_attributes_copy_exact_values_by_original_ids(self):
        self.helper_probe("simplification-retained-attribute-restoration", self.retained_component_fixture_source() + """actual_subset=finish.subset_component_mesh
def omitted(*args,**kwargs):
    result=actual_subset(*args,**kwargs)
    if not args[3]:
        for name in ['OwnedPoint','OwnedEdge','OwnedFace','OwnedCorner']:result.attributes.remove(result.attributes[name])
    return result
finish.subset_component_mesh=omitted
try:result=finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':512,'maxVertexSurfaceErrorMetres':.5,'protectedRegions':[]},1024)
finally:finish.subset_component_mesh=actual_subset
retention=result['componentRetention'];restored=retention['isolationAttributeRestoration']['restoredMissingAttributes']
assert {item['name'] for item in restored}=={'OwnedPoint','OwnedEdge','OwnedFace','OwnedCorner'}
assert retention['sourceSnapshotSha256']==retention['isolationProof']['snapshotSha256']==retention['recombinationProof']['snapshotSha256']
assert result['operatorCalls']==1
""")

    def test_76_attribute_restoration_never_hides_geometry_or_existing_data_corruption(self):
        self.helper_probe("simplification-retained-attribute-restoration-corruption", self.retained_component_fixture_source() + """source=finish.mesh_identity(low);original=low.data;actual_subset=finish.subset_component_mesh
for mode in ['coordinate','wrong-definition','existing-value']:
    objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
    def corrupted(*args,**kwargs):
        result=actual_subset(*args,**kwargs)
        if not args[3]:
            result.attributes.remove(result.attributes['OwnedCorner'])
            if mode=='coordinate':result.vertices[0].co.x+=.1
            elif mode=='wrong-definition':result.attributes.new('OwnedCorner','INT','CORNER')
            else:result.attributes['OwnedPoint'].data[0].value+=1
        return result
    finish.subset_component_mesh=corrupted
    try:
        try:finish.simplify_quadriflow_input(low,{'method':'collapse','targetTriangles':512,'maxVertexSurfaceErrorMetres':.5,'protectedRegions':[]},1024)
        except ValueError as error:assert 'Retained component' in str(error),str(error)
        else:raise AssertionError('Attribute restoration concealed '+mode)
    finally:finish.subset_component_mesh=actual_subset
    assert low.data==original and finish.mesh_identity(low)==source
    assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
""")


    @staticmethod
    def exact_hull_quantization_fixture_source():
        # Owned synthetic native-integration cube, real QF100/native hull result.
        # Frozen data keeps this regression independent of solver discovery/order.
        return """from mathutils import Matrix,Euler
import bmesh
data=json.loads('{"vertices":[[-0.34895190596580505,-0.25406908988952637,-0.17112812399864197],[-0.1741378754377365,-0.24931475520133972,-0.502387523651123],[0.17876982688903809,-0.24947743117809296,-0.5018926858901978],[0.34966370463371277,-0.2514764070510864,-0.3320002257823944],[-0.3519641160964966,0.24965287744998932,0.33715540170669556],[-0.349456250667572,-0.2523854672908783,0.3314082622528076],[0.34910571575164795,0.2539284825325012,0.33353984355926514],[0.3492821455001831,0.2531474530696869,0.16673225164413452],[-0.349619597196579,0.25164034962654114,-0.3299567997455597],[-0.3503462076187134,-0.08024013042449951,-0.49982425570487976],[0.3507162630558014,0.081605926156044,-0.49964335560798645],[-0.34786373376846313,0.251244455575943,0.5024884343147278],[-0.3495095372200012,0.08312666416168213,0.5013216137886047],[0.34860867261886597,-0.0844566822052002,0.5029522180557251],[0.34903040528297424,0.08319343626499176,0.5025891065597534],[0.34695395827293396,-0.2530239522457123,0.5035481452941895],[0.35097211599349976,-0.24983428418636322,0.3367603123188019],[-0.3494693636894226,-0.25232642889022827,0.16390924155712128],[0.34939417243003845,0.2524908185005188,-0.0002967876207549125],[0.34955716133117676,-0.25129786133766174,-0.5002739429473877],[-0.34941205382347107,-0.25257784128189087,-0.00352300307713449],[-0.3505968153476715,0.2508648931980133,-0.49963080883026123],[0.3477810025215149,0.25103557109832764,0.501372754573822],[-0.34941667318344116,-0.2522099018096924,0.5003608465194702],[0.3499999940395355,0.0849163755774498,0.3345377445220947],[-0.35007089376449585,-0.08442855626344681,0.49996429681777954],[-0.005721425171941519,0.2495652139186859,-0.5014975070953369],[0.17202597856521606,0.24949662387371063,-0.5017146468162537],[0.34947848320007324,0.2522740960121155,-0.336195707321167],[0.34967106580734253,-0.25143980979919434,-0.1653967648744583],[-0.34573376178741455,-0.2507252097129822,-0.3387380838394165],[0.3489472568035126,0.24748121201992035,-0.5038985013961792],[-0.3494260609149933,-0.2465931475162506,-0.5052730441093445]],"faces":[[24,14,16],[14,13,16],[13,15,16],[15,29,16],[29,3,16],[3,19,16],[19,10,16],[10,24,16],[7,6,24],[6,14,24],[10,7,24],[11,15,14],[15,13,14],[6,22,14],[22,11,14],[11,23,15],[23,0,15],[0,19,15],[19,3,15],[3,29,15],[0,1,19],[1,32,19],[32,2,19],[2,31,19],[31,10,19],[31,28,10],[28,18,10],[18,7,10],[18,28,7],[28,6,7],[11,22,6],[28,8,6],[8,11,6],[4,12,11],[12,23,11],[8,4,11],[12,25,23],[25,4,23],[4,5,23],[5,0,23],[20,32,0],[32,30,0],[30,1,0],[5,20,0],[30,32,1],[9,21,32],[21,31,32],[31,2,32],[20,17,32],[17,9,32],[21,26,31],[26,27,31],[27,28,31],[27,21,28],[21,8,28],[21,4,8],[25,12,4],[21,9,4],[9,5,4],[9,17,5],[17,20,5],[27,26,21]],"sourceWorldPoints":[[0.1723634898662567,0.25,0.33504000306129456],[0.17099228501319885,0.25,0.16742996871471405],[-0.004030716605484486,0.25,0.3349204659461975],[0.17091837525367737,0.25,-0.00021765507699456066],[0.3485925495624542,0.2502939701080322,-0.1678374707698822],[0.1707739382982254,0.25,-0.167991042137146],[-0.17383816838264465,-0.25,-0.002826076000928879],[-0.34895190596580505,-0.25406908988952637,-0.17112812399864197],[-0.1734483391046524,-0.25,-0.17061030864715576],[-0.0005217971047386527,-0.08264751732349396,-0.5],[-0.1741378754377365,-0.24931475520133972,-0.502387523651123],[-0.17665895819664001,-0.08177720010280609,-0.5],[-0.18239447474479675,0.2499999850988388,0.0022110426798462868],[-0.006978957913815975,0.25,-0.16719132661819458],[-0.18609556555747986,0.2499999850988388,-0.16496171057224274],[-0.3499999940395355,0.08256746083498001,-0.16455699503421783],[-0.3499999940395355,-0.08625957369804382,-0.0014414966572076082],[-0.3499999940395355,0.0815361812710762,0.00176337081938982],[0.3499999940395355,-0.08305340260267258,-0.16536356508731842],[0.3499999940395355,0.085251085460186,0.0005733919679187238],[0.3499999940395355,-0.0825684443116188,0.001222374034114182],[0.1748688519001007,-0.2499999850988388,3.305108839413151e-05],[0.3498058021068573,-0.25090792775154114,0.16880571842193604],[0.17496632039546967,-0.2499999850988388,0.16729390621185303],[0.17876982688903809,-0.24947743117809296,-0.5018926858901978],[0.0017847676062956452,-0.24940581619739532,-0.5020897388458252],[0.34966370463371277,-0.2514764070510864,-0.3320002257823944],[0.17567673325538635,-0.2499999850988388,-0.3354106843471527],[-0.18052423000335693,0.2499999850988388,0.33452481031417847],[-0.18723687529563904,0.2499999850988388,0.1688673198223114],[-0.3519641160964966,0.24965287744998932,0.33715540170669556],[-0.18058325350284576,-0.24959148466587067,0.5001772046089172],[-0.349456250667572,-0.2523854672908783,0.3314082622528076],[-0.17622160911560059,-0.2500000298023224,0.33328136801719666],[0.17389130592346191,0.24814388155937195,0.5007102489471436],[0.34910571575164795,0.2539284825325012,0.33353984355926514],[0.3492821455001831,0.2531474530696869,0.16673225164413452],[-0.18369537591934204,0.24931524693965912,-0.5002540946006775],[-0.349619597196579,0.25164034962654114,-0.3299567997455597],[-0.18369251489639282,0.2499999850988388,-0.33309024572372437],[-0.3497026264667511,0.251303106546402,-0.16304534673690796],[0.3499999940395355,-0.08342490345239639,-0.3318288028240204],[0.3499302566051483,-0.08416228741407394,-0.5001679062843323],[-0.3499999940395355,0.0844821184873581,-0.33105576038360596],[-0.3501974940299988,0.08530139178037643,-0.49958696961402893],[-0.3503462076187134,-0.08024013042449951,-0.49982425570487976],[-0.18125523626804352,0.08402477204799652,-0.5],[0.17389284074306488,0.08253178000450134,-0.5],[0.3507162630558014,0.081605926156044,-0.49964335560798645],[-0.34786373376846313,0.251244455575943,0.5024884343147278],[-0.3495095372200012,0.08312666416168213,0.5013216137886047],[0.17246262729167938,-0.08398479223251343,0.5],[0.34860867261886597,-0.0844566822052002,0.5029522180557251],[0.34903040528297424,0.08319343626499176,0.5025891065597534],[0.34695395827293396,-0.2530239522457123,0.5035481452941895],[0.35097211599349976,-0.24983428418636322,0.3367603123188019],[0.0014434835175052285,-0.25,-0.33666089177131653],[0.000915659184101969,-0.25,-0.16938449442386627],[0.17497538030147552,-0.2499999850988388,-0.16754518449306488],[-0.3499999940395355,-0.08392586559057236,-0.3338410556316376],[0.3499999940395355,0.08524062484502792,-0.3326811194419861],[-0.0034401884768158197,-0.08350234478712082,0.5],[0.17358636856079102,0.08240737020969391,0.5],[-0.006333868019282818,0.25,0.0006767361192032695],[5.2776278607780114e-05,-0.25,0.16634945571422577],[-0.17432381212711334,-0.25,0.16509632766246796],[-0.3499801456928253,0.25000640749931335,0.0032797912135720253],[-0.006767794024199247,0.25,0.16808779537677765],[-0.17290867865085602,-0.25,-0.33764922618865967],[-0.3494693636894226,-0.25232642889022827,0.16390924155712128],[0.34939417243003845,0.2524908185005188,-0.0002967876207549125],[0.34955716133117676,-0.25129786133766174,-0.5002739429473877],[-0.34941205382347107,-0.25257784128189087,-0.00352300307713449],[-0.3505968153476715,0.2508648931980133,-0.49963080883026123],[0.3477810025215149,0.25103557109832764,0.501372754573822],[-0.34941667318344116,-0.2522099018096924,0.5003608465194702],[0.3499999940395355,0.0849163755774498,0.3345377445220947],[-0.3499999940395355,-0.08559704571962357,0.33268749713897705],[-0.35007089376449585,-0.08442855626344681,0.49996429681777954],[0.3499999940395355,-0.08290286362171173,0.3358284831047058],[-0.3499999940395355,0.08185593038797379,0.3351825773715973],[0.3499999940395355,0.08535077422857285,0.16749104857444763],[-0.3499999940395355,-0.08601730316877365,0.165594682097435],[-0.17817513644695282,0.08311938494443893,0.5],[0.3499999940395355,-0.08267531543970108,0.1682616025209427],[0.17181496322155,-0.24989204108715057,0.5005510449409485],[0.1740756332874298,-0.2499999850988388,0.3337441682815552],[-0.17589612305164337,0.24961568415164948,0.5013935565948486],[-0.003931303042918444,-0.24961981177330017,0.5013261437416077],[-0.0016809486551210284,-0.25,0.334026038646698],[-0.0017079324461519718,0.2494708001613617,0.5018851161003113],[-0.005721425171941519,0.2495652139186859,-0.5014975070953369],[-0.006373456679284573,0.25,-0.3350931704044342],[0.17137067019939423,0.25,-0.3356713652610779],[0.0006094779237173498,-0.25,-0.0015609648544341326],[-0.34999826550483704,0.2502693235874176,0.1698637753725052],[-0.3499999940395355,-0.08595625311136246,-0.16806800663471222],[0.3499999940395355,0.08480048924684525,-0.1662372201681137],[-0.0035555262584239244,0.0832693874835968,-0.5],[0.17202597856521606,0.24949662387371063,-0.5017146468162537],[0.1759258657693863,-0.08329430967569351,-0.5],[-0.17928873002529144,-0.08346573263406754,0.5],[-0.002294552745297551,0.08285974711179733,0.5],[0.34947848320007324,0.2522740960121155,-0.336195707321167],[0.34967106580734253,-0.25143980979919434,-0.1653967648744583],[-0.34573376178741455,-0.2507252097129822,-0.3387380838394165],[0.34917736053466797,-0.25018131732940674,0.001431710901670158],[0.3489472568035126,0.24748121201992035,-0.5038985013961792],[-0.3494260609149933,-0.2465931475162506,-0.5052730441093445],[-0.3499999940395355,0.08156361430883408,0.16827227175235748]],"matrixWorld":[[1.0,0.0,0.0,0.0],[0.0,1.0,0.0,0.0],[0.0,0.0,1.0,0.0],[0.0,0.0,0.0,1.0]]}')
def make_hull_fixture():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh=bpy.data.meshes.new('QuantizedNativeHullCandidate')
    mesh.from_pydata(data['vertices'],[],data['faces']);mesh.update()
    obj=bpy.data.objects.new('ExactHullCandidate',mesh);bpy.context.collection.objects.link(obj)
    obj.matrix_world=Matrix(data['matrixWorld']);bpy.context.view_layer.update()
    return obj,finish.np.asarray(data['sourceWorldPoints'],dtype=finish.np.float64)
obj,source_points=make_hull_fixture()
"""

    def test_77_native_hull_quantization_connectivity_is_repaired_without_point_movement(self):
        self.helper_probe('exact-hull-native-facets',self.exact_hull_quantization_fixture_source()+"""before=finish.mesh_identity(obj)
coordinates=finish.np.asarray([list(vertex.co) for vertex in obj.data.vertices],dtype=finish.np.float32).tobytes()
world=finish.np.asarray(obj.matrix_world,dtype=finish.np.float32).tobytes();source_bytes=source_points.tobytes()
try:finish.collision_measure(obj,source_points)
except ValueError as error:assert 'not convex' in str(error) and '9.854722789' in str(error),str(error)
else:raise AssertionError('The actual bad native candidate no longer demonstrates the regression')
result=finish.refine_exact_hull_facets(obj,source_points,64)
measured=finish.collision_measure(obj,source_points)
assert result['status']=='refined' and result['operatorCalls']==1 and len(result['flips'])==1
assert result['flips'][0]['retiredDiagonal']==[5,9] and result['flips'][0]['newDiagonal']==[4,17]
assert result['flips'][0]['allSourceAndHullPointsTested']
assert result['polygonFaces']==len(obj.data.polygons)==62 and len(obj.data.vertices)==33
assert coordinates==finish.np.asarray([list(vertex.co) for vertex in obj.data.vertices],dtype=finish.np.float32).tobytes()
assert world==finish.np.asarray(obj.matrix_world,dtype=finish.np.float32).tobytes() and source_points.tobytes()==source_bytes
assert measured['convex'] and measured['allSourceVerticesContained'] and measured['closedManifold']
assert measured['containmentToleranceMetres']==result['convexityToleranceMetres']
assert measured['maximumConvexityErrorMetres']<1e-12 and measured['maximumOutsideDistanceMetres']<1e-12
assert finish.mesh_identity(obj)!=before
again=finish.refine_exact_hull_facets(obj,source_points,64)
assert again['status']=='already-supporting' and again['operatorCalls']==0 and not again['flips']
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps({'repair':result,'measurement':measured,'idempotent':again},indent=2))
""")

    def test_78_facet_refinement_is_deterministic_under_valid_affine_transforms(self):
        self.helper_probe('exact-hull-affine-facets',self.exact_hull_quantization_fixture_source()+"""records=[]
for case in range(5):
    obj,source_points=make_hull_fixture()
    if case>=2:
        transform=Matrix.Translation((31.7,-48.2,12.9))@Euler((.31,-.71,.19)).to_matrix().to_4x4()@Matrix.Diagonal((-.7 if case==4 else .7,1.3,.9,1))
        if case==4:
            bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.reverse_faces(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
        obj.matrix_world=transform@obj.matrix_world;bpy.context.view_layer.update()
        source_points=source_points@finish.np.asarray(transform,dtype=finish.np.float64)[:3,:3].T+finish.np.asarray(transform,dtype=finish.np.float64)[:3,3]
    coordinates=finish.np.asarray([list(vertex.co) for vertex in obj.data.vertices],dtype=finish.np.float32).tobytes()
    world=finish.np.asarray(obj.matrix_world,dtype=finish.np.float32).tobytes();source_bytes=source_points.tobytes()
    result=finish.refine_exact_hull_facets(obj,source_points,64);measured=finish.collision_measure(obj,source_points)
    assert result['status']=='refined' and len(result['flips'])==1 and result['operatorCalls']==1
    assert measured['convex'] and measured['allSourceVerticesContained'] and measured['volume']>0
    assert coordinates==finish.np.asarray([list(vertex.co) for vertex in obj.data.vertices],dtype=finish.np.float32).tobytes()
    assert world==finish.np.asarray(obj.matrix_world,dtype=finish.np.float32).tobytes() and source_points.tobytes()==source_bytes
    records.append(result)
assert records[0]==records[1]
assert records[2]==records[3]
Path(__file__).with_suffix('.measurements.json').write_text(json.dumps(records,indent=2))
""")

    def test_79_missing_true_support_vertex_cannot_be_repaired_by_diagonal_selection(self):
        self.helper_probe('exact-hull-missing-support',self.exact_hull_quantization_fixture_source()+"""original=obj.data;before=finish.mesh_identity(obj)
source_points=finish.np.concatenate((source_points,[[4.,5.,6.]]));source_bytes=source_points.tobytes()
meshes=set(bpy.data.meshes);objects=set(bpy.data.objects)
try:finish.refine_exact_hull_facets(obj,source_points,64)
except ValueError as error:assert 'no point-preserving globally supporting adjacent flip' in str(error),str(error)
else:raise AssertionError('A missing true support point was silently discarded')
assert obj.data==original and finish.mesh_identity(obj)==before and source_points.tobytes()==source_bytes
assert meshes==set(bpy.data.meshes) and objects==set(bpy.data.objects)
""")

    def test_80_hull_refinement_rejects_caps_nonfinite_degenerate_and_open_inputs(self):
        self.helper_probe('exact-hull-input-rejections',self.exact_hull_quantization_fixture_source()+"""for mode in ['cap','nan','degenerate','open']:
    obj,source_points=make_hull_fixture();cap=61 if mode=='cap' else 64
    if mode=='nan':source_points[0,0]=float('nan')
    if mode=='degenerate':obj.data.vertices[0].co=obj.data.vertices[1].co
    if mode=='open':
        bm=bmesh.new();bm.from_mesh(obj.data);bm.faces.ensure_lookup_table();bmesh.ops.delete(bm,geom=[bm.faces[0]],context='FACES_ONLY');bm.to_mesh(obj.data);bm.free()
    original=obj.data;before=finish.mesh_identity(obj);meshes=set(bpy.data.meshes)
    try:finish.refine_exact_hull_facets(obj,source_points,cap)
    except ValueError as error:
        assert any(word in str(error) for word in ['colliderMaxFaces','finite source','degenerate','closed consistently']),str(error)
    else:raise AssertionError('Invalid hull input accepted: '+mode)
    assert obj.data==original and finish.mesh_identity(obj)==before and meshes==set(bpy.data.meshes)
""")

    def test_81_hull_candidate_rolls_back_when_independent_validation_fails(self):
        self.helper_probe('exact-hull-validation-rollback',self.exact_hull_quantization_fixture_source()+"""original=obj.data;before=finish.mesh_identity(obj)
world=finish.np.asarray(obj.matrix_world,dtype=finish.np.float32).tobytes();source_bytes=source_points.tobytes()
meshes=set(bpy.data.meshes);objects=set(bpy.data.objects);actual=finish.collision_measure;calls=[0]
def rejected(*args,**kwargs):calls[0]+=1;raise ValueError('Injected unchanged validator failure')
finish.collision_measure=rejected
try:
    try:finish.refine_exact_hull_facets(obj,source_points,64)
    except ValueError as error:assert 'Injected unchanged validator failure' in str(error),str(error)
    else:raise AssertionError('Failed independent validation committed a collider')
finally:finish.collision_measure=actual
assert calls[0]==1 and obj.data==original and finish.mesh_identity(obj)==before
assert meshes==set(bpy.data.meshes) and objects==set(bpy.data.objects)
assert world==finish.np.asarray(obj.matrix_world,dtype=finish.np.float32).tobytes() and source_points.tobytes()==source_bytes
""")

    def test_82_forced_support_flip_budgets_and_native_noop_fail_closed(self):
        self.helper_probe('exact-hull-budget-noop',self.exact_hull_quantization_fixture_source()+"""import inspect
from types import SimpleNamespace
for mode in ['support-budget','flip-budget','native-noop']:
    obj,source_points=make_hull_fixture();original=obj.data;before=finish.mesh_identity(obj);meshes=set(bpy.data.meshes)
    actual_bmesh=finish.bmesh
    if mode=='native-noop':
        finish.bmesh=SimpleNamespace(new=actual_bmesh.new,ops=SimpleNamespace(rotate_edges=lambda *args,**kwargs:None))
        method=finish.refine_exact_hull_facets
    else:
        # Explicit test-only budget injection avoids allocating billions of points.
        code=inspect.getsource(finish.refine_exact_hull_facets)
        code=code.replace('max_queries = 1000000000','max_queries = 1') if mode=='support-budget' else code.replace('max_flips = min(256, 4 * len(faces))','max_flips = 0')
        namespace=dict(finish.__dict__);exec(code,namespace);method=namespace['refine_exact_hull_facets']
    try:
        try:method(obj,source_points,64)
        except ValueError as error:assert 'budget' in str(error) or 'failed recorded oriented connectivity' in str(error),str(error)
        else:raise AssertionError('Unsuccessful bounded adapter passed: '+mode)
    finally:finish.bmesh=actual_bmesh
    assert obj.data==original and finish.mesh_identity(obj)==before and meshes==set(bpy.data.meshes)
""")

    def test_83_true_concavity_and_wrong_location_remain_independent_rejections(self):
        self.helper_probe('exact-hull-still-rejects',self.exact_hull_quantization_fixture_source()+"""finish.refine_exact_hull_facets(obj,source_points,64)
for mode in ['concave','translated']:
    obj,source_points=make_hull_fixture();finish.refine_exact_hull_facets(obj,source_points,64)
    if mode=='concave':obj.data.vertices[0].co*=.01;obj.data.update()
    else:obj.location.x+=10;bpy.context.view_layer.update()
    before=finish.mesh_identity(obj);original=obj.data
    try:finish.collision_measure(obj,source_points)
    except ValueError as error:assert 'not convex' in str(error) or 'ALL source' in str(error),str(error)
    else:raise AssertionError('Independent validator accepted '+mode)
    assert obj.data==original and finish.mesh_identity(obj)==before
""")



if __name__ == "__main__":
    unittest.main(verbosity=2)
