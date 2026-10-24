"""Render independent runtime-GLB views and an honest proof comparison surface."""
import html
import math
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import bounds, confined, digest, import_glb, inspect_glb, load_job, relative, triangles, write_json
import bpy
from mathutils import Vector


def main():
    job, root, source, output, result = load_job(allow_subject=True)
    recipe = job.get("recipe", {})
    rigging = recipe.get("riggingRequired") is True
    animation = recipe.get("animationRequired") is True
    document = inspect_glb(source, allow_rigging=rigging, allow_animation=animation)
    if rigging and not any(skin.get("joints") for skin in document.get("skins", [])):
        raise ValueError("Required rigging has no actual GLB skin/joints")
    if animation and not any(clip.get("channels") and clip.get("samplers") for clip in document.get("animations", [])):
        raise ValueError("Required animation has no actual GLB channels/samplers")
    proof = confined(root, job["proof"])
    source_hash, proof_hash = digest(source), digest(proof)
    loaded_proof = bpy.data.images.load(str(proof), check_existing=False)
    if min(loaded_proof.size) < 1:
        raise ValueError("Proof is not a decodable image")
    proof_copy = output / ("proof" + proof.suffix.lower())
    shutil.copyfile(proof, proof_copy)
    meshes = import_glb(source, allow_rigging=rigging, allow_animation=animation)
    triangle_count = sum(triangles(obj) for obj in meshes)
    material_count = len({material for obj in meshes for material in obj.data.materials if material})
    embedded_bytes = sum(document["bufferViews"][image["bufferView"]]["byteLength"]
                         for image in document.get("images", []))
    for field, actual in (("maxTriangles", triangle_count), ("maxMaterials", material_count),
                           ("maxTextureBytes", embedded_bytes)):
        if type(recipe.get(field)) is not int or recipe[field] < 1 or actual > recipe[field]:
            raise ValueError("Reviewed derivative exceeds or lacks declared " + field)
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if rigging and (not armatures or not any(len(obj.data.bones) for obj in armatures)
                    or not any(obj.vertex_groups and any(mod.type == "ARMATURE" and mod.object in armatures
                                                          for mod in obj.modifiers) for obj in meshes)):
        raise ValueError("Required rig did not import with actual deform bones/weights")
    actions = [{"name": action.name, "start": float(action.frame_range[0]), "end": float(action.frame_range[1])}
               for action in bpy.data.actions]
    if animation and (not actions or not any(action["end"] > action["start"] for action in actions)):
        raise ValueError("Required animation did not import a measurable timeline")
    if animation:
        bpy.context.scene.frame_set(round((actions[0]["start"] + actions[0]["end"]) / 2))
    visible = []
    for obj in meshes:
        if obj.get("collision") or obj.get("lodLevel", 0) != 0:
            obj.hide_render = True
        else:
            visible.append(obj)
    if not visible:
        raise ValueError("No LOD0 meshes to review")
    depsgraph = bpy.context.evaluated_depsgraph_get()
    box = bounds([obj.evaluated_get(depsgraph) for obj in visible])
    center = Vector([(a + b) / 2 for a, b in zip(box["min"], box["max"])])
    extent = max(b - a for a, b in zip(box["min"], box["max"]))
    if extent <= 0:
        raise ValueError("Degenerate bounds")
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 8
    scene.render.resolution_x = scene.render.resolution_y = 384
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world = bpy.data.worlds.new("Review world")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.12, 0.12, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.5
    for index, direction in enumerate(((2, -3, 4), (-3, 1, 2))):
        data = bpy.data.lights.new("Review light" + str(index), "AREA")
        data.energy = 500 * extent ** 2
        data.shape = "DISK"
        data.size = extent * 3
        obj = bpy.data.objects.new(data.name, data)
        scene.collection.objects.link(obj)
        obj.location = center + Vector(direction) * extent
        obj.rotation_euler = (center - obj.location).to_track_quat("-Z", "Y").to_euler()
    camera_data = bpy.data.cameras.new("Review camera")
    camera = bpy.data.objects.new("Review camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = extent * 1.8
    camera_data.clip_end = max(100, extent * 100)
    contacts = []
    for name, direction in (("front", (1, -2, 0.8)), ("back", (-1, 2, 0.8)),
                            ("side", (2, 0.5, 0.8)), ("top", (0.01, -0.01, 3))):
        camera.location = center + Vector(direction).normalized() * extent * 4
        camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = output / (name + ".png")
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        if not path.is_file() or path.stat().st_size < 100:
            raise ValueError("Camera render missing")
        contacts.append(path)
    page = output / "comparison.html"
    image_tags = "".join('<figure><img src="' + html.escape(p.name) + '"><figcaption>' + html.escape(p.stem) + '</figcaption></figure>' for p in [proof_copy] + contacts)
    page.write_text('<!doctype html><meta charset="utf-8"><title>Proof to model review</title>'
                    '<style>body{font-family:sans-serif;background:#222;color:#eee}main{display:flex;flex-wrap:wrap}img{width:384px;max-width:90vw}figure{margin:12px}</style>'
                    '<h1>Proof versus exported GLB</h1><p>Human and independent review pending. Images are evidence, not automatic acceptance.</p>'
                    '<p>Proof SHA256: ' + proof_hash + '<br>GLB SHA256: ' + source_hash + '</p><main>' + image_tags + '</main>', encoding="utf-8")
    if digest(source) != source_hash or digest(proof) != proof_hash:
        raise ValueError("Review inputs changed")
    report = output / "review-report.json"
    artifacts = {"comparison": relative(root, page), "proof": relative(root, proof_copy), "report": relative(root, report)}
    artifacts.update({p.stem: relative(root, p) for p in contacts})
    payload = {"schemaVersion": 1, "status": "prepared", "artifacts": artifacts,
               "measurements": {"views": len(contacts), "bounds": box, "visibleMeshes": len(visible),
                                "triangles": triangle_count, "materials": material_count,
                                "embeddedTextureBytes": embedded_bytes,
                                "subject": {"riggingRequired": rigging, "animationRequired": animation,
                                            "armatures": len(armatures), "bones": sum(len(obj.data.bones) for obj in armatures),
                                            "animations": actions, "reviewFrame": scene.frame_current}},
               "stages": [{"stage": "independentRuntimeRender", "inputSha256": source_hash,
                           "proofSha256": proof_hash, "renderEngine": "CYCLES", "device": "CPU"}],
               "outputHashes": {relative(root, p): digest(p) for p in [page, proof_copy] + contacts},
               "humanApproval": "pending", "independentReview": "pending"}
    write_json(report, payload)
    write_json(result, payload)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
