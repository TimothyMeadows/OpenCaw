"""First-party, fixed Blender batch entrypoints. Native execution is not a sandbox."""
import argparse
import hashlib
import json
import math
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


def load_job(allow_subject=False, allow_multiview=False):
    import bpy
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    job_path = Path(args.job).resolve(strict=True)
    job = json.loads(job_path.read_text(encoding="utf-8-sig"))
    if job.get("schemaVersion") not in ((1, 2) if allow_multiview else (1,)):
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


REVIEW_VIEWS = ("front", "right", "back", "left", "top", "bottom")


def review_camera_matrix(view, distance):
    """Pinned cardinal rig plus explicit, nonsingular polar roll; row-major C2W."""
    return {
        "front": [[1, 0, 0, 0], [0, 0, -1, -distance], [0, 1, 0, 0], [0, 0, 0, 1]],
        "right": [[0, 0, -1, -distance], [-1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
        "back": [[-1, 0, 0, 0], [0, 0, 1, distance], [0, 1, 0, 0], [0, 0, 0, 1]],
        "left": [[0, 0, 1, distance], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]],
        "top": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, distance], [0, 0, 0, 1]],
        "bottom": [[1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, -distance], [0, 0, 0, 1]],
    }[view]


def finite_number(value, field, minimum=None, maximum=None):
    if type(value) not in (float, int) or not math.isfinite(value):
        raise ValueError(field + " must be finite")
    if minimum is not None and value <= minimum:
        raise ValueError(field + " is below its permitted range")
    if maximum is not None and value >= maximum:
        raise ValueError(field + " is above its permitted range")
    return float(value)


def review_input_image(root, item, field="image", hash_field="sha256"):
    import re
    path = confined(root, item[field])
    expected = item.get(hash_field)
    if not isinstance(expected, str) or not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise ValueError("Review image requires an exact SHA256")
    if not path.is_file() or digest(path) != expected:
        raise ValueError("Review image missing or changed: " + str(item[field]))
    return path


def review_multiview_inputs(job, root):
    """Check submitted originals, source membership and exact camera/input identities.

    This validates an audited job, not the semantic correctness of classification.
    Pipeline registration remains responsible for candidate/receipt provenance.
    """
    import re
    if job.get("schemaVersion") != 2 or job.get("mode") != "multi-view":
        raise ValueError("Six-view review requires an explicit v2 multi-view job")
    if job.get("inputFrame") not in ("pixal3d-mv-export", "opencaw-proof-z-up"):
        raise ValueError("Six-view review requires an explicit input geometry frame")
    proof_set, source_set, classification = (job.get(name) for name in ("proofSet", "sourceSet", "classification"))
    if not all(isinstance(item, dict) for item in (proof_set, source_set, classification)):
        raise ValueError("Six-view review requires proofSet, sourceSet and classification")
    if source_set.get("schemaVersion") != 1 or proof_set.get("schemaVersion") != 1:
        raise ValueError("Unsupported source/proof-set schema")
    camera = proof_set.get("camera", {})
    if camera.get("convention") != "blender-nerf-z-up" or camera.get("calibration") not in ("nominal-prescribed", "measured"):
        raise ValueError("Unknown camera convention or calibration")
    finite_number(camera.get("meshScale"), "meshScale", 0)
    distance = finite_number(camera.get("distance"), "camera distance", 0)
    finite_number(camera.get("cameraAngleX"), "cameraAngleX", 0, math.pi)
    originals = source_set.get("images")
    if not isinstance(originals, list) or not originals:
        raise ValueError("Original source images are required")
    source_ids, original_paths, checked = {}, set(), {}
    for item in originals:
        identifier = item.get("id")
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", identifier) or identifier in source_ids:
            raise ValueError("Original source IDs must be safe and unique")
        path = review_input_image(root, item, "path")
        if path in original_paths:
            raise ValueError("Duplicate original source image")
        original_paths.add(path)
        source_ids[identifier] = item["sha256"]
        checked[path] = item["sha256"]
    claims = classification.get("sources")
    if not isinstance(claims, list) or len(claims) != len(source_ids):
        raise ValueError("Classification must bind every original source exactly once")
    bindings = {}
    for item in claims:
        identifier = item.get("sourceId")
        if identifier in bindings or source_ids.get(identifier) != item.get("sha256"):
            raise ValueError("Classification image evidence is not an exact registered original")
        bindings[identifier] = item["sha256"]
    if bindings != source_ids:
        raise ValueError("Classification source bindings are incomplete")
    source_views = classification.get("sourceViews")
    if not isinstance(source_views, list) or len(source_views) != len(source_ids):
        raise ValueError("Classification must assess every original source view")
    coverage = {}
    for item in source_views:
        identifier = item.get("sourceId")
        if (identifier not in source_ids or identifier in coverage
                or item.get("view") not in REVIEW_VIEWS + ("oblique", "unknown")
                or type(item.get("usable")) is not bool or not isinstance(item.get("reason"), str)
                or not item["reason"].strip() or item["usable"] and item["view"] not in REVIEW_VIEWS):
            raise ValueError("Invalid original-source view coverage")
        coverage[identifier] = item
    for name in ("sourceSetHash", "classificationHash"):
        if not isinstance(proof_set.get(name), str) or not re.fullmatch(r"[a-f0-9]{64}", proof_set[name]):
            raise ValueError("Proof-set must bind source and classification hashes")
    if classification.get("sourceSetHash") != proof_set["sourceSetHash"]:
        raise ValueError("Classification and proof-set source identities differ")
    views = proof_set.get("views")
    if not isinstance(views, list) or tuple(item.get("view") for item in views) != REVIEW_VIEWS:
        raise ValueError("Exactly six ordered front/right/back/left/top/bottom views are required")
    view_paths = set()
    for item in views:
        path = review_input_image(root, item)
        if path in view_paths:
            raise ValueError("Each camera requires its own conditioning image")
        view_paths.add(path)
        checked[path] = item["sha256"]
        if item.get("origin") not in ("source", "generated"):
            raise ValueError("Proof origin must be source or generated")
        ancestry = item.get("sourceIds")
        if not isinstance(ancestry, list) or not ancestry or len(set(ancestry)) != len(ancestry) or any(identifier not in source_ids for identifier in ancestry):
            raise ValueError("Proof ancestry must refer to registered original sources")
        if "approvedImage" not in item or "approvedSha256" not in item:
            raise ValueError("Six-view review must retain the approved proof before preprocessing")
        approved = review_input_image(root, item, "approvedImage", "approvedSha256")
        checked[approved] = item["approvedSha256"]
        if item["origin"] == "source" and not any(
                item["approvedSha256"] == source_ids[identifier] and coverage[identifier]["usable"]
                and coverage[identifier]["view"] == item["view"] for identifier in ancestry):
            raise ValueError("A source proof must retain a usable original identity and matching view")
        fov = item.get("cameraAngleX", camera["cameraAngleX"])
        finite_number(fov, "per-view cameraAngleX", 0, math.pi)
        matrix, expected = item.get("cameraToWorld"), review_camera_matrix(item["view"], distance)
        if not isinstance(matrix, list) or len(matrix) != 4 or any(not isinstance(row, list) or len(row) != 4 for row in matrix):
            raise ValueError("cameraToWorld must be a 4x4 matrix")
        for row in range(4):
            for column in range(4):
                value = finite_number(matrix[row][column], "cameraToWorld")
                if abs(value - expected[row][column]) > 1e-6:
                    raise ValueError("Camera differs from the declared cardinal/polar rig: " + item["view"])
    return proof_set, source_set, classification, checked


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
