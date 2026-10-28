"""Fixed native motion batch mechanics. File guards are not an OS sandbox."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
from urllib.parse import urlparse

sys.dont_write_bytecode = True
PROFILES = ("skinned", "articulated", "rigid")
OPERATIONS = ("inspect", "prepare", "rig", "author", "retarget", "bake", "export", "review")
BUDGETS = ("maxTriangles", "maxBones", "maxInfluences", "maxMaterials", "maxTextureBytes", "maxRuntimeBytes", "maxClips", "maxClipSeconds", "maxSamples", "maxPreviewFrames", "maxAttempts", "timeoutSeconds", "maxLogBytes")


def no_excluded_providers(value,key=""):
    provider_keys={"provider","vendor","tool","authoringtool","sourceprovider","sourcetool","sourceorigin","createdwith","generator"}
    uri_keys={"source","sourceuri","sourceurl","url","origin"}
    if isinstance(value,dict):
        for name,child in value.items():
            no_excluded_providers(child,name.replace('-','').replace('_','').lower())
    elif isinstance(value,list):
        for child in value:no_excluded_providers(child,key)
    elif isinstance(value,str):
        product=key in provider_keys and re.search(r"\b(adobe|mixamo|firefly|substance(?:\s*3d|\s+painter|\s+designer)?|after\s+effects|photoshop|illustrator)\b",value,re.I)
        vendor_identity=key in uri_keys and re.fullmatch(r"\s*(adobe(?:\s+(?:mixamo|firefly|photoshop|illustrator|after\s+effects|substance(?:\s*3d|\s+painter|\s+designer)?))?|mixamo|firefly|substance(?:\s*3d|\s+painter|\s+designer)?|after\s+effects|photoshop|illustrator)\s*",value,re.I)
        host=urlparse(value).hostname if key in uri_keys else None
        vendor=host and re.search(r"(^|\.)(adobe\.com|adobe\.io|mixamo\.com|substance3d\.com)$",host,re.I)
        if product or vendor_identity or vendor:raise ValueError("Excluded authoring/provider provenance")


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def identity(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def confined(root, value):
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise ValueError("Expected a normalized repository-relative path")
    path = Path(value)
    if path.is_absolute() or any(part in (".", "..", "") for part in value.split("/")):
        raise ValueError("Expected a normalized repository-relative path")
    candidate = root / path
    cursor = candidate
    while cursor != root:
        if cursor.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(cursor)):
            raise ValueError("Symbolic links and junctions are forbidden")
        cursor = cursor.parent
    candidate.resolve().relative_to(root)
    return candidate


def finite(value, name, minimum=None, maximum=None, integer=False):
    if type(value) not in (int, float) or not math.isfinite(value) or (integer and type(value) is not int):
        raise ValueError(name + " must be a finite " + ("integer" if integer else "number"))
    if minimum is not None and value < minimum or maximum is not None and value > maximum:
        raise ValueError(name + " exceeds its declared bounds")
    return value


def vector(value, count, name):
    if not isinstance(value, list) or len(value) != count:
        raise ValueError(name + " requires " + str(count) + " components")
    return [finite(item, name) for item in value]


def text(value, name):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(name + " requires nonempty text")
    return value


def safe_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", value) or value == "..":
        raise ValueError("Unsafe semantic identity")
    return value


def save_json(path, value):
    if path.exists():
        raise ValueError("Immutable output already exists: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def read_glb(path, maximum=512 * 1024 * 1024):
    size = path.stat().st_size
    if size < 20 or size > maximum:
        raise ValueError("GLB is empty or exceeds its input budget")
    with path.open("rb") as stream:
        magic, version, length = struct.unpack("<III", stream.read(12))
        if magic != 0x46546C67 or version != 2 or length != size:
            raise ValueError("Invalid GLB container")
        document = None
        while stream.tell() < size:
            header = stream.read(8)
            if len(header) != 8:
                raise ValueError("Truncated GLB chunk")
            count, kind = struct.unpack("<II", header)
            if count % 4 or stream.tell() + count > size:
                raise ValueError("Malformed GLB chunk length")
            data = stream.read(count)
            if kind == 0x4E4F534A:
                if document is not None or len(data) > 32 * 1024 * 1024:
                    raise ValueError("Ambiguous or oversized GLB JSON")
                document = json.loads(data.decode("utf-8").rstrip(" \0"))
        if not isinstance(document, dict) or document.get("asset", {}).get("version") != "2.0":
            raise ValueError("Missing glTF2 document")
    for item in document.get("buffers", []) + document.get("images", []):
        uri = item.get("uri")
        if uri is not None and (not isinstance(uri, str) or not uri.startswith("data:")):
            raise ValueError("External GLB dependencies are not permitted")
    no_excluded_providers(document.get("asset",{}))
    if not document.get("meshes"):
        raise ValueError("GLB has no meshes")
    return document


def validate_recipe(recipe, profile):
    required = ("schemaVersion", "profile", "fps", "requiredClips", "rig", "parts", "anchors", "clips", "states", "transitions", "parameters", "effects", "budgets", "review")
    if not isinstance(recipe, dict) or any(key not in recipe for key in required):
        raise ValueError("Motion recipe omits required production settings")
    no_excluded_providers(recipe)
    if recipe["schemaVersion"] != 1 or recipe["profile"] != profile or profile not in PROFILES:
        raise ValueError("Recipe profile/version disagrees with the job")
    finite(recipe["fps"], "fps", 1, 120, True)
    budget = recipe["budgets"]
    if not isinstance(budget, dict):
        raise ValueError("Explicit production budgets required")
    for key in BUDGETS:
        minimum = 0 if profile != "skinned" and key in ("maxBones", "maxInfluences") else 1
        finite(budget.get(key), key, minimum, 1073741824, key != "maxClipSeconds")
    if budget["maxBones"] > 1024 or budget["maxInfluences"] > 8 or budget["maxClips"] > 256 or budget["maxPreviewFrames"] > 10000 or budget["maxSamples"] > 1000000:
        raise ValueError("Motion recipe exceeds native safety bounds")
    if budget["timeoutSeconds"] > 86400 or budget["maxLogBytes"] < 1024:
        raise ValueError("Invalid process bounds")
    for key in ("requiredClips", "parts", "anchors", "clips", "states", "transitions", "parameters", "effects"):
        if not isinstance(recipe[key], list):
            raise ValueError(key + " must be an array")
    for key in ("clips", "anchors", "states", "parameters", "effects"):
        ids = [safe_id(item.get("id")) for item in recipe[key]]
        if len(ids) != len(set(ids)):
            raise ValueError("Duplicate " + key + " identity")
    if not recipe["clips"] or len(recipe["clips"]) > budget["maxClips"]:
        raise ValueError("Recipe requires a bounded nonempty motion set")
    known = {item["id"] for item in recipe["clips"]}
    if not set(recipe["requiredClips"]) <= known:
        raise ValueError("Required clip coverage is missing")
    states = {item["id"] for item in recipe["states"]}
    for state in recipe["states"]:
        if state.get("clip") is not None and state["clip"] not in known:
            raise ValueError("State references a missing clip")
    for transition in recipe["transitions"]:
        if transition.get("from") not in states or transition.get("to") not in states:
            raise ValueError("Transition references a missing state")
        text(transition.get("trigger"), "Transition trigger")
        finite(transition.get("duration"), "Transition duration", 0, 30)
    for parameter in recipe["parameters"]:
        low = finite(parameter.get("min"), "Parameter minimum")
        high = finite(parameter.get("max"), "Parameter maximum")
        finite(parameter.get("default"), "Parameter default", low, high)
        if low >= high:
            raise ValueError("Parameter range must increase")
        text(parameter.get("unit"), "Parameter unit")
    anchors = {item["id"] for item in recipe["anchors"]}
    for effect in recipe["effects"]:
        if effect.get("type") not in ("particles", "trail", "material") or effect.get("anchor") not in anchors or effect.get("space") not in ("local", "world"):
            raise ValueError("Effect requires a known anchor, type and space")
        finite(effect.get("maxParticles"), "Effect particle cap", 1, 100000, True)
        finite(effect.get("lifetime"), "Effect lifetime", .001, 120)
    total = 0
    for clip in recipe["clips"]:
        text(clip.get("role"), "Clip role")
        start = finite(clip.get("startFrame"), "startFrame", 0, 1000000, True)
        end = finite(clip.get("endFrame"), "endFrame", 1, 1000000, True)
        if start >= end or (end - start) / recipe["fps"] > budget["maxClipSeconds"]:
            raise ValueError("Clip range or duration exceeds its budget")
        if type(clip.get("loop")) is not bool or clip.get("rootMotion") not in ("in-place", "extract"):
            raise ValueError("Clip requires loop and root-motion policies")
        if not isinstance(clip.get("channels"), list) or not isinstance(clip.get("markers"), list):
            raise ValueError("Clip channels/markers must be arrays")
        for marker in clip["markers"]:
            finite(marker.get("time"), "Marker time", 0, (end - start) / recipe["fps"])
            text(marker.get("event"), "Marker event")
        total += end - start + 1
    if total > budget["maxSamples"]:
        raise ValueError("Clip samples exceed the recipe budget")
    review = recipe["review"]
    if not isinstance(review, dict) or review.get("renderer") not in ("BLENDER_WORKBENCH", "CYCLES", "BLENDER_EEVEE_NEXT"):
        raise ValueError("Explicit supported review renderer required")
    finite(review.get("fps"), "Review FPS", 1, 60, True)
    vector(review.get("resolution"), 2, "Review resolution")
    for value in review["resolution"]:
        finite(value, "Review resolution", 32, 2048, True)
    if not isinstance(review.get("cameras"), list) or not 1 <= len(review["cameras"]) <= 8:
        raise ValueError("One to eight review cameras required")
    if len(review["cameras"])!=len(set(review["cameras"])):
        raise ValueError("Review camera identities must be unique")
    for camera in review["cameras"]:
        if camera not in ("front", "right", "back", "left", "top", "bottom", "three-quarter"):
            raise ValueError("Unknown review camera")
    return recipe


def load_job():
    import bpy
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    path = Path(args.job).absolute()
    if not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("Missing or oversized native job")
    job = json.loads(path.read_text(encoding="utf-8-sig"))
    allowed = {"schemaVersion", "root", "operation", "input", "outputDir", "result", "asset", "version", "profile", "recipe", "motionSource", "mapping", "revisionClip"}
    if set(job) - allowed or job.get("schemaVersion") != 1 or job.get("operation") not in OPERATIONS:
        raise ValueError("Invalid native motion job")
    if job.get("revisionClip") is not None:
        safe_id(job["revisionClip"])
        if job["operation"]!="author":
            raise ValueError("A targeted revision is an explicit authoring operation")
    root = Path(job["root"]).absolute()
    if not root.is_dir() or root.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(root)):
        raise ValueError("Invalid project root")
    path.resolve().relative_to(root.resolve())
    if bpy.app.version[:2] != (4, 5):
        raise ValueError("Blender4.5 LTS is required")
    asset, version = safe_id(job.get("asset")), safe_id(job.get("version"))
    prefix = ".art-staging/model-to-animation/" + asset + "/" + version + "/attempts/"
    if not job["outputDir"].startswith(prefix):
        raise ValueError("Output must remain in this asset's immutable attempts")
    output = confined(root, job["outputDir"])
    result = confined(root, job["result"])
    result.relative_to(output)
    bootstrap = {"scripts", "job.json", "process.log", "version.log", "blender-version.log"}
    if job["operation"] == "retarget":
        bootstrap.update(("motion-source.glb", "mapping.json"))
    if job["operation"] in ("author","retarget"):
        bootstrap.add("effective-recipe.json")
    if job["operation"]=="author" and job.get("revisionClip") is not None:
        bootstrap.add("clip-revision.json")
    if output.exists() and any(item.name not in bootstrap for item in output.iterdir()):
        raise ValueError("Use a new immutable attempt directory")
    if result.exists() or (output / "report.json").exists():
        raise ValueError("Attempt outputs already exist")
    output.mkdir(parents=True, exist_ok=True)
    source = confined(root, job["input"])
    if not source.is_file() or source.suffix.lower() not in (".glb", ".blend"):
        raise ValueError("Native input must be GLB or a previous working blend")
    if source.suffix.lower() == ".blend" and not job["input"].startswith(prefix):
        raise ValueError("Only this asset's prior working blend may be loaded")
    if source.suffix.lower() == ".glb":
        read_glb(source)
    recipe = validate_recipe(job.get("recipe"), job.get("profile"))
    return job, root, source, output, result, recipe


def load_scene(source, fps):
    import bpy
    if source.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
        if bpy.context.scene.render.fps != fps:
            raise ValueError("Working blend FPS differs from the selected recipe")
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = fps
        bpy.ops.import_scene.gltf(filepath=str(source), loglevel=0)
        # The glTF importer creates hidden bone-display meshes; these are UI
        # helpers, not authored model geometry or runtime dependencies.
        helpers={bone.custom_shape for obj in bpy.context.scene.objects if obj.type=="ARMATURE" for bone in obj.pose.bones if bone.custom_shape is not None}
        for obj in list(bpy.context.scene.objects):
            if obj.type=="ARMATURE":
                for bone in obj.pose.bones:
                    bone.custom_shape=None
        for helper in helpers:
            bpy.data.objects.remove(helper,do_unlink=True)
    for obj in bpy.data.objects:
        if obj.library or obj.is_instancer:
            raise ValueError("Linked/instanced dependencies require an explicit realized working copy")
        if obj.animation_data and obj.animation_data.drivers:
            raise ValueError("Executable/input drivers require explicitly baked safe channels")
    for image in bpy.data.images:
        if image.source == "FILE" and image.packed_file is None:
            raise ValueError("Unpacked external images are not allowed")
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.view_layer.update()


def all_curves(action):
    for layer in action.layers:
        for strip in layer.strips:
            if strip.type != "KEYFRAME":
                raise ValueError("Unsupported action strip")
            for bag in strip.channelbags:
                yield from bag.fcurves


def owned_curves(action):
    owners={slot.handle:slot.identifier[2:] for slot in action.slots}
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    yield owners[bag.slot_handle],curve


def objects():
    import bpy
    return list(bpy.context.scene.objects)


def meshes():
    return [obj for obj in objects() if obj.type == "MESH"]


def armatures():
    return [obj for obj in objects() if obj.type == "ARMATURE"]


def rig_identity():
    result = []
    for rig in sorted(armatures(), key=lambda value: value.name):
        result.append({"node": rig.name, "bones": [{"name": bone.name, "parent": bone.parent.name if bone.parent else None, "head": list(bone.head_local), "tail": list(bone.tail_local), "deform": bone.use_deform} for bone in rig.data.bones]})
    return {"id": identity(result), "armatures": result, "boneCount": sum(len(rig["bones"]) for rig in result)}


def inventory(recipe, require_skin=False):
    import bpy
    from mathutils import Vector
    budget = recipe["budgets"]
    triangles = sum(sum(len(poly.vertices) - 2 for poly in mesh.data.polygons) for mesh in meshes())
    materials = {material.name for mesh in meshes() for material in mesh.data.materials if material}
    texture_bytes = sum(image.size[0] * image.size[1] * 4 for image in bpy.data.images if image.type != "RENDER_RESULT")
    bounds = [obj.matrix_world @ Vector(corner) for obj in meshes() for corner in obj.bound_box]
    if not bounds or triangles < 1:
        raise ValueError("Scene has no real mesh geometry")
    for point in bounds:
        vector(list(point), 3, "Mesh bounds")
    bones = rig_identity()["boneCount"]
    maximum = 0
    unweighted = 0
    bad_normalization = 0
    if armatures():
        names = {bone.name for rig in armatures() for bone in rig.data.bones if bone.use_deform}
        for mesh in meshes():
            if not any(mod.type == "ARMATURE" and mod.object in armatures() for mod in mesh.modifiers):
                if require_skin:
                    raise ValueError("Skinned mesh lacks a declared armature modifier: " + mesh.name)
                continue
            groups = {group.index: group.name for group in mesh.vertex_groups}
            for vertex in mesh.data.vertices:
                weights = [group.weight for group in vertex.groups if groups.get(group.group) in names and group.weight > 1e-8]
                if not weights:
                    unweighted += 1
                elif abs(sum(weights) - 1) > .001:
                    bad_normalization += 1
                maximum = max(maximum, len(weights))
    if require_skin and (not bones or unweighted or bad_normalization or maximum < 1):
        raise ValueError("Invalid skin weights or unweighted vertices")
    if triangles > budget["maxTriangles"] or bones > budget["maxBones"] or len(materials) > budget["maxMaterials"] or texture_bytes > budget["maxTextureBytes"] or maximum > budget["maxInfluences"]:
        raise ValueError("Measured model exceeds the declared production budget")
    return {"triangles": triangles, "bones": bones, "materials": len(materials), "textureBytes": texture_bytes, "maxInfluences": maximum, "unweightedVertices": unweighted, "badNormalizedVertices": bad_normalization,
            "bounds": {"min": [min(point[i] for point in bounds) for i in range(3)], "max": [max(point[i] for point in bounds) for i in range(3)]}, "objects": [{"name": obj.name, "type": obj.type, "parent": obj.parent.name if obj.parent else None} for obj in objects()]}


def relative(root, path):
    return path.relative_to(root).as_posix()


def save_blend(root, output):
    import bpy
    path = output / "asset.blend"
    if path.exists():
        raise ValueError("Immutable working blend exists")
    for image in bpy.data.images:
        if image.source != "VIEWER" and image.type != "RENDER_RESULT" and image.packed_file is None:
            image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(path), check_existing=False)
    return relative(root, path)
