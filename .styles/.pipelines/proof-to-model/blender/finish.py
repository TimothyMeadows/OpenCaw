"""Auditable static-asset finishing: QuadriFlow, UV/bake, LOD, hull, export/re-import."""
import json
import math
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (activate, bounds, digest, import_glb, inspect_glb, load_job, relative,
                    triangles, write_json)
import bpy
import bmesh
import numpy as np  # Bundled with Blender; no separate installation.
from mathutils import Matrix


def validate_recipe(recipe):
    integers = ("targetFaces", "textureSize", "colliderMaxFaces", "maxTriangles", "maxMaterials", "maxTextureBytes")
    for field in integers:
        if type(recipe.get(field)) is not int or recipe[field] < 1:
            raise ValueError(field + " must be a positive integer")
    for field in ("cageExtrusion", "maxRayDistance", "uvMargin"):
        value = recipe.get(field)
        if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
            raise ValueError(field + " must be positive and finite")
    if recipe["uvMargin"] >= 0.5:
        raise ValueError("uvMargin must be less than 0.5")
    ratios = recipe.get("lodRatios")
    if not isinstance(ratios, list) or not ratios:
        raise ValueError("Explicit nonempty lodRatios required")
    previous = 1.0
    for ratio in ratios:
        if type(ratio) not in (int, float) or not 0 < ratio < previous:
            raise ValueError("LOD ratios must strictly decrease within (0,1)")
        previous = ratio
    if not isinstance(recipe.get("parts"), list) or any(not isinstance(p, str) or not p for p in recipe["parts"]):
        raise ValueError("parts must be semantic mesh names")
    for field in ("riggingRequired", "animationRequired"):
        if type(recipe.get(field)) is not bool:
            raise ValueError(field + " must be explicit")
        if recipe[field]:
            raise ValueError(field + " requires subject-specific evidence; static finishing cannot complete it")


def uv_measure(obj):
    uv = obj.data.uv_layers.active
    if uv is None or len(uv.data) != len(obj.data.loops):
        raise ValueError("Missing UV coordinates")
    coordinates = [tuple(v.uv) for v in uv.data]
    if any(not math.isfinite(c) or c < -0.00001 or c > 1.00001 for v in coordinates for c in v):
        raise ValueError("UV coordinates outside unit tile")
    area = 0.0
    for poly in obj.data.polygons:
        coords = [uv.data[i].uv for i in poly.loop_indices]
        area += abs(sum(a.x * b.y - b.x * a.y for a, b in zip(coords, coords[1:] + coords[:1]))) / 2
    if area <= 0:
        raise ValueError("Degenerate UV layout")
    return {"loops": len(coordinates), "summedUvArea": area, "unitTile": True}


def topology_measure(obj):
    mesh = bmesh.new()
    try:
        mesh.from_mesh(obj.data)
        if any(not math.isfinite(component) for vertex in mesh.verts for component in vertex.co):
            raise ValueError("Non-finite vertex coordinates")
        degenerate = sum(face.calc_area() <= 1e-12 for face in mesh.faces)
        if degenerate:
            raise ValueError("Retopology produced degenerate faces")
        return {"vertices": len(mesh.verts), "edges": len(mesh.edges), "faces": len(mesh.faces),
                "boundaryEdges": sum(edge.is_boundary for edge in mesh.edges),
                "nonManifoldEdges": sum(not edge.is_manifold for edge in mesh.edges),
                "degenerateFaces": degenerate}
    finally:
        mesh.free()


def bake_maps(high, low, recipe, output, index):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = recipe["cageExtrusion"]
    scene.render.bake.max_ray_distance = recipe["maxRayDistance"]
    scene.render.bake.margin = max(1, int(recipe["textureSize"] * recipe["uvMargin"]))
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    material = bpy.data.materials.new(low.name + "_baked")
    material.use_nodes = True
    low.data.materials.clear()
    low.data.materials.append(material)
    nodes = material.node_tree.nodes
    principled = nodes.get("Principled BSDF")
    maps = {}
    for channel, bake_type in (("basecolor", "DIFFUSE"), ("normal", "NORMAL"), ("ao", "AO"), ("roughness", "ROUGHNESS"), ("metallic", "EMIT")):
        image = bpy.data.images.new(f"part{index}_{channel}", recipe["textureSize"], recipe["textureSize"], alpha=False)
        image.colorspace_settings.name = "sRGB" if channel == "basecolor" else "Non-Color"
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        nodes.active = texture
        saved = []
        if channel == "metallic":
            for source_mat in high.data.materials:
                if not source_mat or not source_mat.use_nodes:
                    raise ValueError("Source material lacks nodes for metallic baking")
                tree = source_mat.node_tree
                surface = next((n for n in tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
                shader = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if surface is None or shader is None:
                    raise ValueError("Metallic baking requires explicit Principled material correspondence")
                links = [(link.from_socket, link.to_socket) for link in surface.inputs["Surface"].links]
                emission = tree.nodes.new("ShaderNodeEmission")
                metal = shader.inputs["Metallic"]
                if metal.is_linked:
                    tree.links.new(metal.links[0].from_socket, emission.inputs["Color"])
                else:
                    emission.inputs["Color"].default_value = (metal.default_value,) * 3 + (1,)
                tree.links.new(emission.outputs[0], surface.inputs["Surface"])
                saved.append((tree, emission, links))
        activate(low)
        high.select_set(True)
        high.hide_render = False
        try:
            bpy.ops.object.bake(type=bake_type)
        finally:
            for tree, emission, links in saved:
                tree.nodes.remove(emission)
                for source_socket, destination_socket in links:
                    tree.links.new(source_socket, destination_socket)
        path = output / f"part{index}_{channel}.png"
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
        image.pack()
        pixels = np.empty(len(image.pixels), dtype=np.float32)
        image.pixels.foreach_get(pixels)
        if not pixels.size or not np.isfinite(pixels).all():
            raise ValueError("Baked image has missing/non-finite pixels")
        maximum = float(pixels.reshape((-1, 4))[:, :3].max())
        if channel in ("normal", "ao") and maximum <= 0:
            raise ValueError("Bake contains no normal/AO surface signal")
        maps[channel] = {"path": path, "image": image, "texture": texture,
                         "measurement": {"width": image.size[0], "height": image.size[1],
                                         "maxRgb": maximum, "sha256": digest(path)}}
    links = material.node_tree.links
    links.new(maps["basecolor"]["texture"].outputs["Color"], principled.inputs["Base Color"])
    links.new(maps["roughness"]["texture"].outputs["Color"], principled.inputs["Roughness"])
    links.new(maps["metallic"]["texture"].outputs["Color"], principled.inputs["Metallic"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.space = "TANGENT"
    links.new(maps["normal"]["texture"].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    # The glTF exporter discovers occlusion through its standard settings node.
    group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    group_node = nodes.new("ShaderNodeGroup")
    group_node.node_tree = group
    links.new(maps["ao"]["texture"].outputs["Color"], group_node.inputs["Occlusion"])
    return maps


def main():
    job, root, source, output, result = load_job()
    recipe = job["recipe"]
    validate_recipe(recipe)
    original_hash = digest(source)
    preserved = output / "source.glb"
    shutil.copyfile(source, preserved)
    if digest(preserved) != original_hash:
        raise ValueError("Source copy verification failed")
    highs = import_glb(preserved)
    names = [o.name for o in highs]
    if recipe["parts"] and set(recipe["parts"]) != set(names):
        raise ValueError("Semantic parts must exactly name every imported mesh: " + repr(names))
    if recipe["targetFaces"] < 6 * len(highs):
        raise ValueError("targetFaces too small for semantic parts")
    stages = [{"stage": "source", "sha256": original_hash, "meshNames": names}]
    if job.get("mode") == "multi-view":
        if job.get("inputFrame") != "pixal3d-mv-export":
            raise ValueError("Multi-view finishing requires the declared Pixal3D export frame")
        scale = job.get("engineToProofScale")
        if type(scale) not in (int, float) or not math.isfinite(scale) or scale <= 0:
            raise ValueError("A finite positive export-to-proof scale is required")
        mapping = Matrix.Diagonal((-scale, -scale, scale, 1.0))
        # Imported MV GLB is Rz(pi) from the proof Z-up frame. Apply the
        # documented mapping once, to all roots, before topology/baking.
        for obj in bpy.context.scene.objects:
            if obj.parent is None:
                obj.matrix_world = mapping @ obj.matrix_world
        bpy.context.view_layer.update()
        stages.append({"stage": "engineExportToProofFrame", "inputFrame": "pixal3d-mv-export",
                       "outputFrame": "opencaw-proof-z-up", "matrix": [list(row) for row in mapping],
                       "basis": "pinned MV projection/reference-frame/glTF axis composition; no per-view fitting"})
    total_high = sum(len(o.data.polygons) for o in highs)
    exports, lows, textures, part_reports = [], [], [], []
    root_object = bpy.data.objects.new("PROOF_TO_MODEL", None)
    bpy.context.collection.objects.link(root_object)
    for index, high in enumerate(highs):
        activate(high)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        if not high.data.materials:
            raise ValueError("Source has no material correspondence")
        low = high.copy()
        low.data = high.data.copy()
        bpy.context.collection.objects.link(low)
        low.name = high.name + "_LOD0"
        activate(low)
        # glTF splits vertices at shading/UV seams. Weld only the working low
        # candidate before QuadriFlow; retain the untouched high for baking.
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.000001)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        target = max(6, round(recipe["targetFaces"] * len(high.data.polygons) / total_high))
        bpy.ops.object.quadriflow_remesh(target_faces=target, use_preserve_sharp=True, use_preserve_boundary=True, seed=0)
        if not low.data.polygons:
            raise ValueError("QuadriFlow returned empty topology")
        world = low.matrix_world.copy()
        low.parent = root_object
        low.matrix_world = world
        low["semanticPart"] = names[index]
        low["lodLevel"] = 0
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(island_margin=recipe["uvMargin"], scale_to_bounds=True)
        bpy.ops.object.mode_set(mode="OBJECT")
        uv = uv_measure(low)
        topology = topology_measure(low)
        for poly in low.data.polygons:
            poly.use_smooth = True
        for other in highs:
            other.hide_render = other != high
        low.hide_render = False
        maps = bake_maps(high, low, recipe, output, index)
        textures.extend(value["path"] for value in maps.values())
        high.hide_render = True
        high.hide_set(True)
        low.hide_render = True  # Prevent a completed part affecting later part AO/bakes.
        exports.append(low)
        lows.append(low)
        lod_report = []
        base_triangles = triangles(low)
        previous_triangles = base_triangles
        for level, ratio in enumerate(recipe["lodRatios"], 1):
            lod = low.copy()
            lod.data = low.data.copy()
            bpy.context.collection.objects.link(lod)
            lod.name = names[index] + f"_LOD{level}"
            lod["lodLevel"] = level
            activate(lod)
            modifier = lod.modifiers.new("Measured LOD", "DECIMATE")
            modifier.ratio = ratio
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            count = triangles(lod)
            if count < 1 or count >= previous_triangles:
                raise ValueError("LOD did not reduce triangle count")
            previous_triangles = count
            exports.append(lod)
            lod.hide_render = True
            lod_report.append({"level": level, "ratio": ratio, "triangles": count})
        collision = low.copy()
        collision.data = low.data.copy()
        collision.data.materials.clear()
        bpy.context.collection.objects.link(collision)
        collision.name = names[index] + "_COLLISION"
        collision["collision"] = True
        activate(collision)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.convex_hull(delete_unused=True, use_existing_faces=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        collision_faces = len(collision.data.polygons)
        if collision_faces > recipe["colliderMaxFaces"]:
            raise ValueError("Convex hull exceeds colliderMaxFaces; supply a simpler semantic part/recipe")
        collision.hide_render = True
        exports.append(collision)
        part_reports.append({"part": names[index], "targetFaces": target, "faces": len(low.data.polygons),
                             "triangles": base_triangles, "uv": uv, "topology": topology, "lods": lod_report,
                             "bakeMaps": {channel: value["measurement"] for channel, value in maps.items()},
                             "colliderFaces": collision_faces, "sourceMaterials": len(high.data.materials)})
    total_triangles = sum(triangles(o) for o in exports)
    material_count = len({m.name for o in exports for m in o.data.materials if m})
    texture_bytes = sum(p.stat().st_size for p in textures)
    if total_triangles > recipe["maxTriangles"] or material_count > recipe["maxMaterials"] or texture_bytes > recipe["maxTextureBytes"]:
        raise ValueError("Finished package exceeds declared geometry/material/texture budget")
    for low in lows:
        low.hide_render = False
    bpy.ops.object.select_all(action="DESELECT")
    root_object.select_set(True)
    for obj in exports:
        obj.hide_set(False)
        obj.select_set(True)
    glb = output / "asset.glb"
    expected_names = set(o.name for o in exports)
    expected_bounds = bounds(exports)
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", use_selection=True,
                              export_extras=True, export_yup=True, export_materials="EXPORT")
    package_document = inspect_glb(glb)
    packed_texture_bytes = sum(package_document["bufferViews"][image["bufferView"]]["byteLength"]
                               for image in package_document.get("images", []))
    if packed_texture_bytes > recipe["maxTextureBytes"]:
        raise ValueError("Embedded runtime texture payload exceeds maxTextureBytes")
    blend = output / "asset.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    imported = import_glb(glb)
    actual_names = set(o.name for o in imported)
    if actual_names != expected_names or sum(triangles(o) for o in imported) != total_triangles:
        raise ValueError("Independent GLB re-import geometry/hierarchy differs")
    actual_bounds = bounds(imported)
    if any(abs(actual_bounds[key][i] - expected_bounds[key][i]) > 0.0001 for key in expected_bounds for i in range(3)):
        raise ValueError("Independent GLB bounds/transforms differ")
    if any(o.parent is None for o in imported):
        raise ValueError("GLB lost hierarchy")
    materials = {m for o in imported for m in o.data.materials if m}
    if len(materials) != material_count:
        raise ValueError("GLB lost material assignments")
    imported_images = [i for i in bpy.data.images if i.type == "IMAGE"]
    if len(imported_images) < 3 * len(highs) or any(i.size[0] != recipe["textureSize"] or i.size[1] != recipe["textureSize"] for i in imported_images):
        raise ValueError("GLB lost baked texture data/dimensions")
    for obj in imported:
        if not obj.get("collision"):
            uv_measure(obj)
    if digest(source) != original_hash or digest(preserved) != original_hash:
        raise ValueError("Immutable source changed")
    stages.extend([{"stage": "quadriFlowUvBakeLodCollision", "parts": part_reports,
                    "bakeChannels": ["basecolor", "normal", "ao", "roughness", "metallic"],
                    "normalSpace": "TANGENT", "cageExtrusion": recipe["cageExtrusion"],
                    "maxRayDistance": recipe["maxRayDistance"]},
                   {"stage": "independentReimport", "meshCount": len(imported), "textures": len(imported_images),
                    "bounds": actual_bounds, "verified": True}])
    report = output / "report.json"
    artifacts = {"blend": relative(root, blend), "glb": relative(root, glb),
                 "report": relative(root, report), "source": relative(root, preserved)}
    artifacts.update({"texture" + str(i): relative(root, path) for i, path in enumerate(textures)})
    payload = {"schemaVersion": 1, "status": "prepared", "artifacts": artifacts,
               "measurements": {"triangles": total_triangles, "materials": material_count,
                                "textureBytes": texture_bytes, "embeddedTextureBytes": packed_texture_bytes,
                                "parts": part_reports},
               "stages": stages, "inputSha256": original_hash,
               "outputHashes": {relative(root, p): digest(p) for p in [blend, glb, preserved] + textures},
               "blenderVersion": bpy.app.version_string, "humanApproval": "pending"}
    write_json(report, payload)
    write_json(result, payload)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
