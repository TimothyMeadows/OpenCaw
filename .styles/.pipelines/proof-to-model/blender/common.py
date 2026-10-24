"""First-party, fixed Blender batch entrypoints. Native execution is not a sandbox."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import sys


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def confined(root, value):
    value = Path(value)
    if value.is_absolute() or ".." in value.parts or not value.parts:
        raise ValueError("Expected a repository-relative path")
    candidate = root / value
    cursor = candidate
    while cursor != root:
        if cursor.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(cursor)):
            raise ValueError("Symbolic links/junctions are forbidden")
        cursor = cursor.parent
    candidate.resolve().relative_to(root)
    return candidate


def load_job(allow_subject=False):
    import bpy
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    job_path = Path(args.job).resolve(strict=True)
    job = json.loads(job_path.read_text(encoding="utf-8-sig"))
    if job.get("schemaVersion") != 1:
        raise ValueError("Unsupported job schema")
    root = Path(job["root"]).resolve(strict=True)
    job_path.relative_to(root)
    if bpy.app.version[:2] != (4, 5):
        raise RuntimeError("Blender 4.5 LTS is required")
    source = confined(root, job["input"])
    if source.suffix.lower() != ".glb":
        raise ValueError("Input must be an existing binary glTF")
    recipe = job.get("recipe", {})
    inspect_glb(source, allow_rigging=allow_subject and recipe.get("riggingRequired") is True,
                allow_animation=allow_subject and recipe.get("animationRequired") is True)
    output = confined(root, job["outputDir"])
    result = confined(root, job["result"])
    result.relative_to(output)
    if output.exists() and any(output.iterdir()):
        raise ValueError("Use a new/empty attempt directory; outputs are immutable")
    output.mkdir(parents=True, exist_ok=True)
    return job, root, source, output, result


def relative(root, path):
    return path.resolve().relative_to(root).as_posix()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def import_glb(path, allow_rigging=False, allow_animation=False):
    import bpy
    inspect_glb(path, allow_rigging=allow_rigging, allow_animation=allow_animation)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise ValueError("Input contains no mesh geometry")
    if not allow_rigging and any(o.type == "ARMATURE" for o in bpy.context.scene.objects):
        raise ValueError("Rigged input requires subject-specific finishing, not the static recipe")
    return meshes


def inspect_glb(path, allow_rigging=False, allow_animation=False):
    """Reject external dependencies before Blender can resolve any referenced URI."""
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError("Invalid GLB header")
    version, length, json_size, chunk_type = struct.unpack_from("<IIII", data, 4)
    if version != 2 or length != len(data) or chunk_type != 0x4E4F534A or 20 + json_size > length:
        raise ValueError("Invalid/truncated GLB container")
    document = json.loads(data[20:20 + json_size].decode("utf-8"))
    if any("uri" in item for key in ("buffers", "images") for item in document.get(key, [])):
        raise ValueError("Only fully embedded GLB resources are accepted")
    if (document.get("animations") and not allow_animation) or (document.get("skins") and not allow_rigging):
        raise ValueError("Animated/rigged input requires a subject-specific workflow")
    return document


def activate(obj):
    import bpy
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def bounds(objects):
    from mathutils import Vector
    points = [o.matrix_world @ Vector(v) for o in objects for v in o.bound_box]
    return {"min": [min(p[i] for p in points) for i in range(3)],
            "max": [max(p[i] for p in points) for i in range(3)]}
