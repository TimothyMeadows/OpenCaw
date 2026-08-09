"""Read-only Blender 4.5 scene inventory used by inspect-blender-scene.sh."""

import bpy
import hashlib
import json
import math
import pathlib
import re
import sys


def fail(message):
    raise RuntimeError(message)


def parse_args():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    values = {}
    index = 0
    while index < len(args):
        key = args[index]
        if key not in {"--root", "--scene-relative", "--profile", "--output"} or index + 1 >= len(args):
            fail("invalid inspector argument")
        values[key] = args[index + 1]
        index += 2
    if set(values) != {"--root", "--scene-relative", "--profile", "--output"}:
        fail("incomplete inspector arguments")
    return values


def stable_id(prefix, name):
    slug = re.sub(r"[^a-z0-9._-]+", "-", name.lower()).strip("-._") or "unnamed"
    digest = hashlib.sha256(name.encode("utf-8")).hexdigest()[:10]
    return f"{prefix}-{slug}-{digest}"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def vector(value):
    result = [float(component) for component in value]
    if len(result) != 3 or not all(math.isfinite(component) for component in result):
        fail("scene contains a non-finite transform")
    return result


def main():
    args = parse_args()
    root = pathlib.Path(args["--root"]).resolve(strict=True)
    scene_relative = pathlib.PurePosixPath(args["--scene-relative"])
    scene = (root / pathlib.Path(*scene_relative.parts)).resolve(strict=True)
    output = pathlib.Path(args["--output"])
    if not scene.is_relative_to(root) or scene.suffix.lower() != ".blend":
        fail("scene escapes repository root")
    loaded = pathlib.Path(bpy.data.filepath).resolve(strict=True)
    if loaded != scene:
        fail("loaded Blender file does not match requested scene")
    version = ".".join(str(part) for part in bpy.app.version)
    if bpy.app.version[:2] != (4, 5):
        fail("inspector requires Blender 4.5.x")

    collection_id = {item.name: stable_id("collection", item.name) for item in bpy.data.collections}
    object_id = {item.name: stable_id("object", item.name) for item in bpy.data.objects}
    mesh_id = {item.name: stable_id("mesh", item.name) for item in bpy.data.meshes}
    material_id = {item.name: stable_id("material", item.name) for item in bpy.data.materials}
    image_id = {item.name: stable_id("image", item.name) for item in bpy.data.images}
    node_id = {item.name: stable_id("node-group", item.name) for item in bpy.data.node_groups}

    armature_objects = [item for item in bpy.data.objects if item.type == "ARMATURE" and item.data]
    armature_id = {item.name: stable_id("armature", item.name) for item in armature_objects}
    action_owners = {}
    for item in armature_objects:
        animation = item.animation_data
        if animation and animation.action:
            action_owners[animation.action.name] = item.name
        if animation:
            for track in animation.nla_tracks:
                for strip in track.strips:
                    if strip.action:
                        action_owners[strip.action.name] = item.name
    action_id = {name: stable_id("action", name) for name in sorted(action_owners)}

    collections = []
    for item in bpy.data.collections:
        parent = next((candidate for candidate in bpy.data.collections if item.name in candidate.children), None)
        collections.append({"id": collection_id[item.name], "name": item.name, "parentId": collection_id[parent.name] if parent else None})

    modifiers = []
    modifier_ids_by_object = {}
    simulation_types = {"CLOTH", "FLUID", "SOFT_BODY", "PARTICLE_SYSTEM", "DYNAMIC_PAINT"}
    simulations = []
    for item in bpy.data.objects:
        modifier_ids_by_object[item.name] = []
        for modifier in item.modifiers:
            modifier_key = stable_id("modifier", f"{item.name}:{modifier.name}")
            modifier_ids_by_object[item.name].append(modifier_key)
            node_group = getattr(modifier, "node_group", None)
            modifiers.append({"id": modifier_key, "name": modifier.name, "objectId": object_id[item.name], "type": modifier.type, "nodeGroupId": node_id.get(node_group.name) if node_group else None})
            if modifier.type in simulation_types:
                simulation_key = stable_id("simulation", f"{item.name}:{modifier.name}")
                cache_path = f".blender-cache/{simulation_key}"
                simulations.append({"id": simulation_key, "name": modifier.name, "type": modifier.type, "objectId": object_id[item.name], "cache": {"required": True, "path": cache_path, "baked": False, "resolved": False}})
        if getattr(item, "rigid_body", None):
            simulation_key = stable_id("simulation", f"{item.name}:rigid-body")
            simulations.append({"id": simulation_key, "name": "Rigid Body", "type": "RIGID_BODY", "objectId": object_id[item.name], "cache": {"required": True, "path": f".blender-cache/{simulation_key}", "baked": False, "resolved": False}})

    objects = []
    for item in bpy.data.objects:
        materials = []
        if getattr(item, "data", None) and hasattr(item.data, "materials"):
            materials = [material_id[slot.name] for slot in item.data.materials if slot and slot.name in material_id]
        actions = []
        if item.name in armature_id:
            actions = [action_id[name] for name, owner in action_owners.items() if owner == item.name]
        node_groups = []
        for modifier in item.modifiers:
            group = getattr(modifier, "node_group", None)
            if group and group.name in node_id:
                node_groups.append(node_id[group.name])
        objects.append({
            "id": object_id[item.name], "name": item.name, "type": item.type,
            "parentId": object_id.get(item.parent.name) if item.parent else None,
            "collectionIds": sorted(collection_id[value.name] for value in item.users_collection),
            "meshId": mesh_id.get(item.data.name) if item.type == "MESH" and item.data else None,
            "materialIds": sorted(set(materials)),
            "armatureId": armature_id.get(item.name), "actionIds": sorted(actions),
            "nodeGroupIds": sorted(set(node_groups)), "modifierIds": modifier_ids_by_object[item.name],
            "transform": {"location": vector(item.location), "rotation": vector(item.rotation_euler), "scale": vector(item.scale)},
        })

    meshes = []
    for mesh in bpy.data.meshes:
        owners = sorted((item for item in bpy.data.objects if item.type == "MESH" and item.data == mesh), key=lambda item: item.name)
        if not owners:
            continue
        item = owners[0]
        non_manifold = sum(1 for edge in mesh.edges if not getattr(edge, "is_manifold", True))
        used_vertices = {index for edge in mesh.edges for index in edge.vertices}
        loose = sum(1 for vertex in mesh.vertices if vertex.index not in used_vertices)
        zero_area = sum(1 for polygon in mesh.polygons if polygon.area <= 1e-12)
        triangles = sum(max(0, len(polygon.vertices) - 2) for polygon in mesh.polygons)
        meshes.append({
            "id": mesh_id[mesh.name], "name": mesh.name, "objectId": object_id[item.name],
            "vertices": len(mesh.vertices), "edges": len(mesh.edges), "faces": len(mesh.polygons), "triangles": triangles,
            "materialIds": [material_id[slot.name] for slot in mesh.materials if slot and slot.name in material_id],
            "uvLayers": [layer.name for layer in mesh.uv_layers],
            "invalidTopology": {"nonManifoldEdges": non_manifold, "looseVertices": loose, "zeroAreaFaces": zero_area},
        })

    dependencies = []
    images = []
    for item in bpy.data.images:
        packed = bool(item.packed_file)
        exists = packed
        relative = ""
        digest = None
        inside = packed
        if not packed and item.filepath:
            resolved = pathlib.Path(bpy.path.abspath(item.filepath)).resolve()
            exists = resolved.is_file()
            inside = resolved.is_relative_to(root)
            relative = resolved.relative_to(root).as_posix() if inside else f"external/{hashlib.sha256(str(resolved).encode('utf-8')).hexdigest()}"
            digest = sha256_file(resolved) if exists else None
            dependencies.append({"id": stable_id("dependency", f"image:{item.name}"), "kind": "image", "path": relative, "packed": False, "exists": exists, "insideRoot": inside, "sha256": digest})
        images.append({"id": image_id[item.name], "name": item.name, "path": relative, "packed": packed, "exists": exists, "sha256": digest})
    for library in bpy.data.libraries:
        resolved = pathlib.Path(bpy.path.abspath(library.filepath)).resolve()
        exists = resolved.is_file()
        inside = resolved.is_relative_to(root)
        relative = resolved.relative_to(root).as_posix() if inside else f"external/{hashlib.sha256(str(resolved).encode('utf-8')).hexdigest()}"
        dependencies.append({"id": stable_id("dependency", f"library:{library.name}"), "kind": "library", "path": relative, "packed": False, "exists": exists, "insideRoot": inside, "sha256": sha256_file(resolved) if exists else None})

    materials = []
    for item in bpy.data.materials:
        material_images = set()
        material_groups = set()
        if item.use_nodes and item.node_tree:
            for node in item.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    material_images.add(image_id[node.image.name])
                if node.type == "GROUP" and node.node_tree:
                    material_groups.add(node_id[node.node_tree.name])
        materials.append({"id": material_id[item.name], "name": item.name, "imageIds": sorted(material_images), "nodeGroupIds": sorted(material_groups)})

    armatures = [{"id": armature_id[item.name], "name": item.name, "objectId": object_id[item.name], "skeletonId": hashlib.sha256("\n".join(bone.name for bone in item.data.bones).encode("utf-8")).hexdigest()} for item in armature_objects]
    actions = []
    for name, owner in sorted(action_owners.items()):
        action = bpy.data.actions[name]
        actions.append({"id": action_id[name], "name": name, "armatureId": armature_id[owner], "frameStart": float(action.frame_range[0]), "frameEnd": float(action.frame_range[1])})
    node_groups = []
    for item in bpy.data.node_groups:
        policy = None
        if item.bl_idname == "GeometryNodeTree":
            policy = item.get("opencaw_realization_policy") if item.get("opencaw_realization_policy") in {"keep-instances","realize-for-edit","realize-for-simulation","realize-for-render","realize-for-export","frozen-output"} else None
        node_groups.append({"id": node_id[item.name], "name": item.name, "type": item.bl_idname, "realizationPolicy": policy})

    findings = []
    for mesh in meshes:
        if any(mesh["invalidTopology"].values()):
            findings.append({"severity": "error", "code": "invalid-topology", "subject": mesh["id"], "message": "Mesh contains invalid topology counts."})
    for dependency in dependencies:
        if not dependency["exists"] or not dependency["insideRoot"]:
            findings.append({"severity": "error", "code": "dependency-unavailable", "subject": dependency["id"], "message": "Dependency is missing or outside the repository."})
    for simulation in simulations:
        findings.append({"severity": "warning", "code": "cache-unresolved", "subject": simulation["id"], "message": "Simulation cache requires explicit bake verification."})

    scene_data = bpy.context.scene
    camera = scene_data.camera
    report = {
        "schemaVersion": "opencaw-blender-scene/v1", "profile": args["--profile"], "blenderVersion": version,
        "source": {"path": scene_relative.as_posix(), "sha256": sha256_file(scene)},
        "units": {"system": scene_data.unit_settings.system, "scaleLength": float(scene_data.unit_settings.scale_length)},
        "render": {"engine": scene_data.render.engine, "resolutionX": int(scene_data.render.resolution_x), "resolutionY": int(scene_data.render.resolution_y), "fps": float(scene_data.render.fps) / float(scene_data.render.fps_base), "activeCamera": object_id.get(camera.name) if camera else None},
        "totals": {}, "collections": collections, "objects": objects, "meshes": meshes, "materials": materials,
        "images": images, "armatures": armatures, "actions": actions, "nodeGroups": node_groups,
        "modifiers": modifiers, "simulations": simulations, "dependencies": dependencies, "findings": findings,
    }
    report["totals"] = {name: len(report[name]) for name in ["collections","objects","meshes","materials","images","armatures","actions","nodeGroups","modifiers","simulations","dependencies"]}
    report["totals"]["cameras"] = sum(1 for item in objects if item["type"] == "CAMERA")
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
