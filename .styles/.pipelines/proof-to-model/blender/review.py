"""Render independent GLB views against immutable sources and approved proofs."""
import html
import json
import math
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (bounds, confined, digest, import_glb, inspect_glb, load_job, relative,
                    review_multiview_inputs, triangles, write_json)
import bpy
from mathutils import Matrix, Vector


def copy_image(path, output):
    image = bpy.data.images.load(str(path), check_existing=False)
    if min(image.size) < 1:
        raise ValueError("Review input is not a decodable image")
    size = list(image.size)
    bpy.data.images.remove(image)
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, output)
    return {"path": output, "size": size, "sha256": digest(path)}


def figure(path, caption, page):
    target = path.relative_to(page.parent).as_posix()
    return '<figure><img src="' + html.escape(target, quote=True) + '"><figcaption>' + html.escape(caption) + '</figcaption></figure>'


def main():
    job, root, source, output, result = load_job(allow_subject=True, allow_multiview=True)
    multi = job.get("schemaVersion") == 2
    checked = {source: digest(source)}
    originals, prepared, approved = [], {}, {}
    if multi:
        proof_set, source_set, classification, inputs = review_multiview_inputs(job, root)
        checked.update(inputs)
        for item in source_set["images"]:
            path = confined(root, item["path"])
            copy = copy_image(path, output / "originals" / (item["id"] + path.suffix.lower()))
            copy["id"] = item["id"]
            originals.append(copy)
        for item in proof_set["views"]:
            for field, copies, directory in (("image", prepared, "conditioning"), ("approvedImage", approved, "approved")):
                path = confined(root, item[field])
                copies[item["view"]] = copy_image(path, output / directory / (item["view"] + path.suffix.lower()))
        dimensions = {tuple(item["size"]) for item in prepared.values()}
        if len(dimensions) != 1 or any(width != height for width, height in dimensions):
            raise ValueError("Prepared review inputs must share one square canvas")
    else:
        if job.get("mode") != "single-view-diagnostic":
            raise ValueError("V1 review requires explicit single-view-diagnostic mode; six-view production must use v2")
        proof = confined(root, job["proof"])
        checked[proof] = digest(proof)
        diagnostic = copy_image(proof, output / ("proof" + proof.suffix.lower()))
    recipe = job.get("recipe", {})
    rigging = recipe.get("riggingRequired") is True
    animation = recipe.get("animationRequired") is True
    document = inspect_glb(source, allow_rigging=rigging, allow_animation=animation)
    if rigging and not any(skin.get("joints") for skin in document.get("skins", [])):
        raise ValueError("Required rigging has no actual GLB skin/joints")
    if animation and not any(clip.get("channels") and clip.get("samplers") for clip in document.get("animations", [])):
        raise ValueError("Required animation has no actual GLB channels/samplers")
    source_hash = checked[source]
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
    if not math.isfinite(extent) or extent <= 0:
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
    camera_data.clip_start = max(0.00001, extent * 0.0001)
    camera_data.clip_end = max(100, extent * 100)
    contacts, cameras = [], []
    if multi:
        camera_data.type = "PERSP"
        camera_data.sensor_fit = "HORIZONTAL"
        # Native conditioning projects a normalized cube / mesh_scale. One common
        # fit is explicit review evidence; it is not measured camera calibration.
        scale = 1.0 / (extent * proof_set["camera"]["meshScale"])
        # Only raw native exports need this mapping; finishing already records
        # its one-time correction. Never silently double-flip a corrected asset.
        export_to_proof = (Matrix.Diagonal((-1.0, -1.0, 1.0, 1.0))
                           if job["inputFrame"] == "pixal3d-mv-export" else Matrix.Identity(4))
        fit = Matrix.Scale(scale, 4) @ export_to_proof @ Matrix.Translation(-center)
        directions = proof_set["views"]
    else:
        camera_data.type = "ORTHO"
        camera_data.ortho_scale = extent * 1.8
        directions = [{"view": name, "direction": direction} for name, direction in
                      (("front", (1, -2, 0.8)), ("back", (-1, 2, 0.8)),
                       ("side", (2, 0.5, 0.8)), ("top", (0.01, -0.01, 3)))]
    for item in directions:
        name = item["view"]
        if multi:
            matrix = Matrix(item["cameraToWorld"])
            camera.matrix_world = export_to_proof @ matrix.to_3x3().to_4x4()
            camera.location = center + export_to_proof.to_3x3() @ matrix.translation / scale
            fov = item.get("cameraAngleX", proof_set["camera"]["cameraAngleX"])
            camera_data.lens = camera_data.sensor_width / (2 * math.tan(fov / 2))
            bpy.context.view_layer.update()
            cameras.append({"view": name, "cameraToWorld": item["cameraToWorld"], "cameraAngleX": fov,
                            "effectiveBlenderCameraToWorld": [list(row) for row in camera.matrix_world]})
        else:
            camera.location = center + Vector(item["direction"]).normalized() * extent * 4
            camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        path = output / (name + ".png")
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        if not path.is_file() or path.stat().st_size < 100:
            raise ValueError("Camera render missing")
        contacts.append(path)
    page = output / "comparison.html"
    if multi:
        title = "Original sources and six-view proof versus exported GLB"
        source_section = "<h2>Immutable original sources</h2><main>" + "".join(
            figure(item["path"], item["id"] + " original / SHA256 " + item["sha256"], page) for item in originals) + "</main>"
        rows = "".join('<section><h2>' + html.escape(item["view"]) + '</h2><main>' +
                       figure(approved[item["view"]]["path"], "Approved " + item["view"] + " proof", page) +
                       figure(prepared[item["view"]]["path"], "Prepared conditioning image", page) +
                       figure(path, "Independent exported-GLB render", page) + '</main></section>'
                       for item, path in zip(proof_set["views"], contacts))
        alignment = {"calibration": proof_set["camera"]["calibration"], "method": "shared-bounds-fit",
                     "convention": proof_set["camera"]["convention"], "meshScale": proof_set["camera"]["meshScale"],
                     "center": list(center), "uniformScale": scale, "meshToCameraFrame": [list(row) for row in fit],
                     "engineExportToProofFrame": [list(row) for row in export_to_proof],
                     "inputFrame": job["inputFrame"],
                     "orientation": "one declared input-frame mapping; no per-view rotation or refitting",
                     "limitation": "Camera orientations/FOV match submitted metadata. Common bounds fitting is nominal alignment, not measured pixel correspondence or proof of likeness."}
        content = source_section + '<p>' + html.escape(alignment["limitation"]) + '</p>' + rows
        content += '<h2>Source-only classification and unresolved interpretations</h2><pre>' + html.escape(json.dumps(classification, indent=2, ensure_ascii=False)) + '</pre>'
    else:
        title = "Proof versus exported GLB: single-view diagnostic"
        alignment = {"calibration": "unavailable:diagnostic", "method": "four-arbitrary-orthographic-views",
                     "limitation": "Diagnostic renders are not the six-view production camera contract."}
        content = '<p>' + html.escape(alignment["limitation"]) + '</p><main>' + figure(diagnostic["path"], "Diagnostic proof", page) + "".join(figure(path, path.stem, page) for path in contacts) + '</main>'
    page.write_text('<!doctype html><meta charset="utf-8"><title>' + html.escape(title) + '</title>'
                    '<style>body{font-family:sans-serif;background:#222;color:#eee}main{display:flex;flex-wrap:wrap}img{width:384px;max-width:90vw}figure{margin:12px}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style>'
                    '<h1>' + html.escape(title) + '</h1><p>Human and independent review pending. Images are evidence, not automatic acceptance.</p>'
                    '<p>GLB SHA256: ' + source_hash + '</p>' + content, encoding="utf-8")
    if any(not path.is_file() or digest(path) != expected for path, expected in checked.items()):
        raise ValueError("Review inputs changed")
    report = output / "review-report.json"
    artifacts = {"comparison": relative(root, page), "report": relative(root, report)}
    output_images = [page] + contacts
    if multi:
        for item in originals:
            artifacts["original-" + item["id"]] = relative(root, item["path"])
            output_images.append(item["path"])
        for name in approved:
            for prefix, copies in (("approved-", approved), ("conditioning-", prepared)):
                artifacts[prefix + name] = relative(root, copies[name]["path"])
                output_images.append(copies[name]["path"])
    else:
        artifacts["proof"] = relative(root, diagnostic["path"])
        output_images.append(diagnostic["path"])
    artifacts.update({path.stem: relative(root, path) for path in contacts})
    payload = {"schemaVersion": 1, "status": "prepared", "mode": job["mode"], "artifacts": artifacts,
               "measurements": {"views": len(contacts), "bounds": box, "visibleMeshes": len(visible),
                                "triangles": triangle_count, "materials": material_count,
                                "embeddedTextureBytes": embedded_bytes,
                                "subject": {"riggingRequired": rigging, "animationRequired": animation,
                                            "armatures": len(armatures), "bones": sum(len(obj.data.bones) for obj in armatures),
                                            "animations": actions, "reviewFrame": scene.frame_current}},
               "alignment": alignment, "cameras": cameras,
               "stages": [{"stage": "independentRuntimeRender", "inputSha256": source_hash,
                           "renderEngine": "CYCLES", "device": "CPU", "viewCount": len(contacts)}],
               "inputHashes": {relative(root, path): expected for path, expected in checked.items()},
               "outputHashes": {relative(root, path): digest(path) for path in output_images},
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
