"""Real controlled Blender bake fixtures; injected operator returns are synthetic."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "runtime/bubo/resources/proof-to-model/blender"
CHANNELS = ("basecolor", "normal", "ao", "roughness", "metallic")
INSIDE = "--inside-blender" in sys.argv


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


if INSIDE:
    import bpy
    import numpy as np
    from unittest.mock import patch

    sys.path.insert(0, str(SCRIPTS))
    import finish
    import rigid_finish

    EVIDENCE = Path(sys.argv[sys.argv.index("--inside-blender") + 1])
    RECORDS = []

    class Proxy:
        def __init__(self, original, **overrides):
            self.original, self.overrides = original, overrides

        def __getattr__(self, name):
            return self.overrides.get(name, getattr(self.original, name))

    def material_snapshot(material):
        tree = material.node_tree
        inputs = []
        for node in tree.nodes:
            for socket in node.inputs:
                if hasattr(socket, "default_value"):
                    value = socket.default_value
                    if not isinstance(value, (float, int, str, bool)):
                        value = tuple(value)
                    inputs.append((node.name, socket.identifier, value))
        return ([(node.name, node.bl_idname) for node in tree.nodes],
                sorted((link.from_node.name, link.from_socket.identifier,
                        link.to_node.name, link.to_socket.identifier) for link in tree.links), inputs)

    def fixture():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scene = bpy.context.scene
        scene.render.threads_mode = "FIXED"
        scene.render.threads = 2
        mesh = bpy.data.meshes.new("OwnedEngineeringPlane")
        mesh.from_pydata([(-1,-1,0),(1,-1,0),(1,1,0),(-1,1,0)], [], [(0,1,2),(0,2,3)])
        mesh.uv_layers.new(name="OwnedUV")
        for uv, value in zip(mesh.uv_layers.active.data,
                             ((.1,.1),(.9,.1),(.9,.9),(.1,.1),(.9,.9),(.1,.9))):
            uv.uv = value
        high = bpy.data.objects.new("OwnedHIGH", mesh)
        bpy.context.collection.objects.link(high)
        materials = []
        for index in range(2):
            material = bpy.data.materials.new("OwnedSource" + str(index))
            material.use_nodes = True
            shader = material.node_tree.nodes.get("Principled BSDF")
            shader.inputs["Roughness"].default_value = .45
            color = material.node_tree.nodes.new("ShaderNodeRGB")
            color.outputs[0].default_value = (.6,.2,.1,1)
            metal = material.node_tree.nodes.new("ShaderNodeValue")
            metal.outputs[0].default_value = .2
            material.node_tree.links.new(color.outputs[0], shader.inputs["Base Color"])
            material.node_tree.links.new(metal.outputs[0], shader.inputs["Metallic"])
            high.data.materials.append(material)
            materials.append(material)
        high.data.materials.append(materials[0])  # Exercise duplicate-slot restoration.
        low = high.copy()
        low.data = high.data.copy()
        low.name = "OwnedLOW"
        low["semanticPart"] = "owned-part"
        bpy.context.collection.objects.link(low)
        low.location.z = -.01
        bpy.context.view_layer.update()
        return high, low, materials

    class ActualBakeStatus(unittest.TestCase):
        def run_case(self, route, channel=None, returned=None, invalid_label=None, throws=False):
            high, low, materials = fixture()
            before = [material_snapshot(material) for material in materials]
            source_geometry = finish.mesh_identity(high)
            label = route + "-" + (channel or "positive")
            if invalid_label:
                label += "-" + invalid_label
            if throws:
                label += "-throw"
            output = EVIDENCE / label
            output.mkdir()
            recipe = {"textureSize":32, "uvMargin":.02, "cageExtrusion":.1, "maxRayDistance":.3}
            module = finish if route == "legacy" else rigid_finish
            native_bake = bpy.ops.object.bake
            calls = []

            def observed_bake(**kwargs):
                current = CHANNELS[len(calls)]
                calls.append({"channel":current, "bakeType":kwargs["type"]})
                # These checks run against real Blender nodes during production rewiring.
                for material in materials:
                    surface = next(node for node in material.node_tree.nodes
                                   if node.type == "OUTPUT_MATERIAL" and node.is_active_output)
                    shader = surface.inputs["Surface"].links[0].from_node
                    self.assertEqual(shader.type, "EMISSION" if current in ("basecolor", "metallic")
                                     else "BSDF_PRINCIPLED")
                if current == channel:
                    calls[-1]["syntheticOperatorReturn"] = repr(returned)
                    if throws:
                        raise RuntimeError("Synthetic native bake exception")
                    return returned
                status = native_bake(**kwargs)
                self.assertEqual(status, {"FINISHED"})
                calls[-1]["actualOperatorReturn"] = sorted(status)
                return status

            proxy = Proxy(bpy, ops=Proxy(bpy.ops, object=Proxy(bpy.ops.object, bake=observed_bake)))
            sentinel = object()
            accepted = sentinel
            failure = None
            try:
                with patch.object(module, "bpy", proxy):
                    if route == "legacy":
                        accepted = finish.bake_maps(high, low, recipe, output, 0)
                    else:
                        accepted = rigid_finish.bake_group([(high, low)], recipe, output, "owned", finish)
            except (ValueError, RuntimeError) as error:
                failure = error
            self.assertEqual(before, [material_snapshot(material) for material in materials],
                             "Source nodes, links or defaults changed after bake")
            self.assertEqual(source_geometry, finish.mesh_identity(high))
            if route == "rigid":
                self.assertTrue(high.hide_render and low.hide_render, str(failure))
            if channel is not None:
                self.assertIs(accepted, sentinel, "Failed bake returned an accepted map/report payload")
                self.assertIsNotNone(failure)
                self.assertIn("Synthetic native bake exception" if throws else "did not finish", str(failure))
                self.assertEqual([call["channel"] for call in calls], list(CHANNELS[:CHANNELS.index(channel)+1]))
                self.assertEqual(len(list(output.glob("*.png"))), CHANNELS.index(channel))
                self.assertFalse(any(output.glob("*" + channel + ".png")), "Failed map was saved")
                self.assertFalse(any(output.glob("*.json")), "Failed bake emitted a result/report")
                measurements = None
            else:
                self.assertIsNone(failure, str(failure))
                maps = accepted if route == "legacy" else accepted[1]
                self.assertEqual(set(maps), set(CHANNELS))
                self.assertEqual(len(list(output.glob("*.png"))), 5)
                measurements = {}
                for key, value in maps.items():
                    image = value["image"]
                    pixels = np.asarray(image.pixels[:], np.float32).reshape((-1,4))
                    self.assertTrue(np.isfinite(pixels).all())
                    self.assertGreater(float(pixels[:,:3].max()), 0)
                    self.assertEqual(tuple(image.size), (32,32))
                    self.assertIsNotNone(image.packed_file)
                    self.assertEqual(sha256(value["path"]), value["measurement"]["sha256"])
                    self.assertEqual(value["measurement"]["bakeType"],
                                     {"basecolor":"EMIT", "normal":"NORMAL", "ao":"AO",
                                      "roughness":"ROUGHNESS", "metallic":"EMIT"}[key])
                    measurements[key] = value["measurement"]
                self.assertAlmostEqual(measurements["roughness"]["maxRgb"], .45, places=2)
                self.assertAlmostEqual(measurements["metallic"]["maxRgb"], .2, places=2)
                target_material = low.data.materials[0]
                shader = target_material.node_tree.nodes.get("Principled BSDF")
                for socket in ("Base Color", "Roughness", "Metallic", "Normal"):
                    self.assertTrue(shader.inputs[socket].is_linked)
            RECORDS.append({"case":label, "route":route, "channel":channel,
                            "injection":"synthetic operator return/exception" if channel else None,
                            "calls":calls, "sourceGraphRestored":True, "sourceGeometryUnchanged":True,
                            "acceptedPayloadReturned":channel is None,
                            "failure":str(failure) if failure else None, "maps":measurements,
                            "savedMaps":[path.name for path in sorted(output.glob("*.png"))]})

    def install_cases():
        for route in ("legacy", "rigid"):
            def positive(self, route=route):
                self.run_case(route)
            setattr(ActualBakeStatus, "test_"+route+"_positive_real_five_map_bake", positive)
            for channel in CHANNELS:
                def cancelled(self, route=route, channel=channel):
                    self.run_case(route, channel, {"CANCELLED"})
                setattr(ActualBakeStatus, "test_"+route+"_cancelled_"+channel, cancelled)
            invalids = (("none", None), ("empty", set()), ("running", {"RUNNING_MODAL"}),
                        ("mixed", {"FINISHED", "CANCELLED"}), ("list", ["FINISHED"]),
                        ("string", "FINISHED"))
            for label, value in invalids:
                def invalid(self, route=route, label=label, value=value):
                    self.run_case(route, "basecolor", value, label)
                setattr(ActualBakeStatus, "test_"+route+"_invalid_"+label, invalid)
            for channel in ("basecolor", "metallic"):
                def exception(self, route=route, channel=channel):
                    self.run_case(route, channel, throws=True)
                setattr(ActualBakeStatus, "test_"+route+"_exception_"+channel, exception)

    install_cases()


class BlenderBakeStatusProcess(unittest.TestCase):
    @unittest.skipIf(INSIDE, "Host-only bounded Blender process")
    def test_actual_production_bake_return_status(self):
        blender = os.environ.get("BLENDER_EXE") or shutil.which("blender") or r"C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"
        if not Path(blender).is_file():
            self.skipTest("Blender 4.5 unavailable; set BLENDER_EXE")
        configured = os.environ.get("HEPHAERA_PROOF_BAKE_STATUS_EVIDENCE_ROOT")
        evidence = Path(configured) if configured else ROOT / ".hephaera/.cache/tasks/proof-multiview-classification/bake-status"
        if not evidence.is_absolute():
            evidence = ROOT / evidence
        self.assertNotIn("..", evidence.parts)
        evidence.relative_to(ROOT)
        cursor = evidence
        while cursor != ROOT:
            self.assertFalse(cursor.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(cursor)))
            cursor = cursor.parent
        evidence.resolve().relative_to(ROOT.resolve())
        evidence.mkdir(parents=True, exist_ok=True)
        work = Path(tempfile.mkdtemp(prefix="actual-bake-status-", dir=evidence))
        child_temp = work / "temp"
        child_temp.mkdir()
        env = dict(os.environ, TEMP=str(child_temp), TMP=str(child_temp), TMPDIR=str(child_temp),
                   PYTHONDONTWRITEBYTECODE="1", OMP_NUM_THREADS="2", OPENBLAS_NUM_THREADS="2")
        args = [blender, "--background", "--factory-startup", "--disable-autoexec", "--threads", "2",
                "--python-exit-code", "1", "--python", str(Path(__file__).resolve()),
                "--", "--inside-blender", str(work)]
        process = subprocess.run(args, capture_output=True, text=True, timeout=240, env=env)
        (work / "stdout.log").write_text(process.stdout, encoding="utf-8")
        (work / "stderr.log").write_text(process.stderr, encoding="utf-8")
        (work / "process.json").write_text(json.dumps({"args":args, "returncode":process.returncode,
            "timeoutSeconds":240, "blenderSha256":sha256(blender), "testSha256":sha256(__file__),
            "scripts":{path.name:sha256(path) for path in (SCRIPTS/"finish.py", SCRIPTS/"rigid_finish.py", SCRIPTS/"common.py")}}, indent=2), encoding="utf-8")
        print("Bake-status evidence:", work)
        self.assertEqual(process.returncode, 0, process.stdout[-6000:]+process.stderr[-6000:])
        result = json.loads((work/"cases.json").read_text(encoding="utf-8"))
        self.assertEqual(result["testsRun"], 28)
        self.assertTrue(result["successful"])
        self.assertEqual(len(result["cases"]), 28)


if __name__ == "__main__":
    if INSIDE:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(ActualBakeStatus)
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        (EVIDENCE / "cases.json").write_text(json.dumps({"testsRun":result.testsRun,
            "successful":result.wasSuccessful(), "blenderVersion":bpy.app.version_string,
            "failures":len(result.failures), "errors":len(result.errors), "cases":RECORDS}, indent=2), encoding="utf-8")
        if not result.wasSuccessful():
            raise RuntimeError("Controlled bake-status fixture failed")
    else:
        unittest.main(verbosity=2)
