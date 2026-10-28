"""Explicit reviewed HIGH/LOW rigid finishing. No QuadriFlow/fallback/backend selection."""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import json
import math
import numbers
import time
from pathlib import Path
import re
import shutil
import struct
import itertools
import heapq
from fractions import Fraction as _uvrepair_F
from decimal import Decimal

sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
import bmesh
import numpy as np
from mathutils import Matrix
from common import activate, bounds, confined, digest, import_glb, inspect_glb, relative, triangles, write_json


_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", re.ASCII)
_HASH = re.compile(r"[a-f0-9]{64}", re.ASCII)


class ExactFloat(float):
    """Retain a JSON token so rounded fractional integer declarations fail."""
    def __new__(cls, token):
        value = super().__new__(cls, token)
        value.token = token
        return value


def fields(value, names, label):
    if type(value) is not dict or set(value) != set(names):
        raise ValueError(label + " requires exactly: " + ", ".join(names))


def integer(value, minimum, maximum, label):
    if (type(value) is bool or not isinstance(value, (int,float)) or not math.isfinite(value)
            or value != int(value) or not minimum <= value <= maximum
            or isinstance(value,ExactFloat) and Decimal(value.token) != Decimal(int(value))):
        raise ValueError(label + " must be an exact bounded integer")
    return int(value)


def number(value, minimum, maximum, label, exclusive=False):
    if (type(value) is bool or not isinstance(value, (int,float)) or not math.isfinite(value) or value > maximum
            or (value <= minimum if exclusive else value < minimum)):
        raise ValueError(label + " must be a finite bounded number")
    return float(value)


def identifier(value, label):
    if type(value) is not str or not _ID.fullmatch(value):
        raise ValueError(label + " must be a safe ASCII identifier")
    return value


def text(value, label, maximum=4096):
    if type(value) is not str or not value.strip() or len(value) > maximum:
        raise ValueError(label + " must be nonempty bounded text")
    return value


def hash_value(value, label):
    if type(value) is not str or not _HASH.fullmatch(value):
        raise ValueError(label + " must be lowercase SHA256")
    return value


def relative_path(value, label):
    text(value, label, 4096)
    if ("\\" in value or "\x00" in value or ":" in value or value.startswith("/")
            or any(part in ("", ".", "..") for part in value.split("/"))):
        raise ValueError(label + " must be a normalized confined relative path")
    return value


def strict_json(path, maximum, depth):
    if not path.is_file() or path.stat().st_size > maximum:
        raise ValueError("Missing/oversized bounded JSON: " + str(path))
    def unique(pairs):
        result = {}
        for name, value in pairs:
            if name in result:
                raise ValueError("Duplicate JSON field: " + name)
            result[name] = value
        return result
    def nonfinite(value):
        raise ValueError("Nonfinite JSON value: " + value)
    value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique, parse_constant=nonfinite,parse_float=ExactFloat)
    def check(item, remaining):
        if remaining < 0:
            raise ValueError("JSON exceeds declared depth")
        if type(item) is dict:
            for child in item.values():
                check(child, remaining - 1)
        elif type(item) is list:
            for child in item:
                check(child, remaining - 1)
    check(value, depth)
    return value


def validate_settings(value):
    fields(value, ("schemaVersion", "method", "topologyPreparation", "collision", "rigidParts", "resources"), "Rigid finishing settings")
    if integer(value["schemaVersion"], 2, 2, "schemaVersion") != 2 or value["method"] != "rigid-parts":
        raise ValueError("Explicit schemaVersion2 rigid-parts method required")
    if value["topologyPreparation"] != {"method": "none"}:
        raise ValueError("Rigid pairs require explicit topologyPreparation:none; no automatic repair")
    collision = value["collision"]
    if type(collision) is not dict:
        raise ValueError("collision must be an explicit object")
    if collision.get("method") == "exact-hull":
        fields(collision, ("method",), "exact-hull")
    elif collision.get("method") == "kdop-26":
        fields(collision, ("method", "padding", "maxVolumeRatio") + (("frame",) if "frame" in collision else ()), "kdop-26")
        if "frame" in collision and collision["frame"] not in ("world", "principal-axes-v1"):
            raise ValueError("Unknown explicit k-DOP frame")
        number(collision["padding"], 0, 1, "padding")
        number(collision["maxVolumeRatio"], 1, 100, "maxVolumeRatio")
    else:
        raise ValueError("Unknown explicit collision method")
    rigid = value["rigidParts"]
    names = ("handoff", "handoffSha256", "reviewEvidence", "reviewEvidenceSha256", "maxLod0Triangles", "maxGlbBytes")
    optional = tuple(name for name in ("uvAtlas", "importNormals", "lods", "sourceTopology") if type(rigid) is dict and name in rigid)
    fields(rigid, names + optional, "rigidParts")
    if "sourceTopology" in rigid:
        topology = rigid["sourceTopology"]
        fields(topology, ("method", "receipt", "receiptSha256"), "rigidParts.sourceTopology")
        if topology["method"] != "reviewed-source-corners-v1":
            raise ValueError("sourceTopology must explicitly select reviewed-source-corners-v1")
        relative_path(topology["receipt"], "source topology receipt")
        if not topology["receipt"].endswith(".json"):
            raise ValueError("Source topology receipt must be an explicit JSON dependency")
        hash_value(topology["receiptSha256"], "source topology receipt SHA256")
        if "lods" not in rigid:
            raise ValueError("Reviewed source topology requires explicitly selected constrained LODs")
    if "lods" in rigid:
        lods = rigid["lods"]
        fields(lods, ("method", "maxVertexSurfaceErrorMetres") + (("contactPolicy",) if type(lods) is dict and "contactPolicy" in lods else ()), "rigidParts.lods")
        if "contactPolicy" in lods and (lods["contactPolicy"] != "protected-contact-rings-v1" or "sourceTopology" not in rigid):
            raise ValueError("Explicit protected-contact-rings-v1 requires reviewed source topology")
        if lods["method"] != "original-component-finite-collapse-v1":
            raise ValueError("lods must explicitly select original-component-finite-collapse-v1")
        errors = lods["maxVertexSurfaceErrorMetres"]
        if type(errors) is not list or not 1 <= len(errors) <= 8:
            raise ValueError("LOD error bounds must explicitly contain 1..8 world-metre limits")
        for error in errors:
            number(error, 0, 1, "LOD maxVertexSurfaceErrorMetres", exclusive=True)
    if "importNormals" in rigid:
        fields(rigid["importNormals"], ("method",), "rigidParts.importNormals")
        if rigid["importNormals"]["method"] != "stored-corner-fan-v1":
            raise ValueError("importNormals must explicitly select stored-corner-fan-v1")
    if "uvAtlas" in rigid:
        atlas = rigid["uvAtlas"]
        fields(atlas, ("method", "islandMarginPixels") + (("triangleRepair",) if type(atlas) is dict and "triangleRepair" in atlas else ()), "rigidParts.uvAtlas")
        if "triangleRepair" in atlas:
            repair = atlas["triangleRepair"]
            fields(repair, ("method", "minCellPixels", "maxTriangles"), "uvAtlas.triangleRepair")
            if repair["method"] != "density-preserving-isolated-cells-v1":
                raise ValueError("Unknown explicit UV triangle repair method")
            integer(repair["minCellPixels"], 4, 4, "triangleRepair.minCellPixels")
            integer(repair["maxTriangles"], 1, 16384, "triangleRepair.maxTriangles")
        if atlas["method"] != "smart-project-pixels":
            raise ValueError("uvAtlas must explicitly select smart-project-pixels")
        integer(atlas["islandMarginPixels"], 1, 64, "islandMarginPixels")
    for name in ("handoff", "reviewEvidence"):
        relative_path(rigid[name], name)
        hash_value(rigid[name + "Sha256"], name + "Sha256")
    integer(rigid["maxLod0Triangles"], 4, 8_000_000, "maxLod0Triangles")
    integer(rigid["maxGlbBytes"], 1024, 2_147_483_648, "maxGlbBytes")
    fields(value["resources"], ("maxPrivateBytes",), "resources")
    integer(value["resources"]["maxPrivateBytes"], 67_108_864, 68_719_476_736, "maxPrivateBytes")
    normalized = json.loads(json.dumps(value, allow_nan=False))
    if "uvAtlas" in rigid:
        normalized["rigidParts"]["uvAtlas"]["islandMarginPixels"] = integer(rigid["uvAtlas"]["islandMarginPixels"], 1, 64, "islandMarginPixels")
        if "triangleRepair" in rigid["uvAtlas"]:
            normalized["rigidParts"]["uvAtlas"]["triangleRepair"]["minCellPixels"] = integer(rigid["uvAtlas"]["triangleRepair"]["minCellPixels"], 4, 4, "triangleRepair.minCellPixels")
            normalized["rigidParts"]["uvAtlas"]["triangleRepair"]["maxTriangles"] = integer(rigid["uvAtlas"]["triangleRepair"]["maxTriangles"], 1, 16384, "triangleRepair.maxTriangles")
    return normalized


def resolve_lod_settings(settings, recipe):
    """Private public-to-helper shape only; no runtime producer implemented here."""
    lods = settings["rigidParts"].get("lods")
    if lods is None:
        return None
    ratios = recipe["lodRatios"]
    errors = lods["maxVertexSurfaceErrorMetres"]
    if type(ratios) is not list or not 1 <= len(ratios) <= 8 or len(ratios) != len(errors):
        raise ValueError("LOD error bounds must match the authoritative recipe.lodRatios count")
    for ratio in ratios:
        number(ratio, 0, 1, "recipe LOD ratio", exclusive=True)
        if ratio >= 1:
            raise ValueError("Recipe LOD ratio must be below1")
    resolved = {
        "schemaVersion": 1, "method": "original-component-finite-collapse-v1",
        "levels": [{"level": i + 1, "requestedRatio": ratio, "maxVertexSurfaceErrorMetres": errors[i]} for i, ratio in enumerate(ratios)],
        "search": {"method": "linear-requested-to-original", "intervals": 8,
                   "includePreviousSelectedRatio": True, "terminalRetention": "explicit-original-component"},
        "uvPolicy": {"method": "supported-material-aware-v1", "uvIndependent": "deterministic-unit-grid-triangles",
                     "uvDependent": "hard-zero-boundary-both-sides", "unsupported": "reject"},
        "normalPolicy": "authored-derivative-native-geometric-nonzero",
        "componentPolicy": "retain-every-original-closed-positive-component-min4",
        "budgets": {"maxLod0Triangles": settings["rigidParts"]["maxLod0Triangles"], "maxPackageTriangles": recipe["maxTriangles"]}}
    if "contactPolicy" in lods:
        resolved["contactPolicy"] = lods["contactPolicy"]
    return resolved


def resolve_uv_atlas(settings, recipe):
    atlas = settings["rigidParts"].get("uvAtlas")
    if atlas is None:
        return None
    pixels = integer(atlas["islandMarginPixels"], 1, 64, "islandMarginPixels")
    size = recipe["textureSize"]
    if pixels > size / 8:
        raise ValueError("uvAtlas islandMarginPixels must not exceed recipe.textureSize/8")
    if "triangleRepair" in atlas:
        _uvrepair_config(size, pixels, atlas["triangleRepair"])
        return {"method": "smart-project-pixels", "islandMarginPixels": pixels,
                "marginMethod": "FRACTION", "islandMarginFraction": pixels / size, "textureSize": size,
                "triangleRepair": dict(atlas["triangleRepair"])}
    return {"method": "smart-project-pixels", "islandMarginPixels": pixels,
            "marginMethod": "FRACTION", "islandMarginFraction": pixels / size, "textureSize": size}


def checked_file(root, name, expected):
    path = confined(root, relative_path(name, "dependency path"))
    if not path.is_file() or digest(path) != hash_value(expected, "dependency SHA256"):
        raise ValueError("Missing or changed rigid input: " + name)
    return path


def read_inputs(job, root, source, settings):
    # Re-read strict bytes even though the native runner also validates/snapshots.
    configuration = settings["rigidParts"]
    path = checked_file(root, configuration["handoff"], configuration["handoffSha256"])
    handoff = strict_json(path, 524288, 20)
    if job.get("rigidHandoff") != handoff:
        raise ValueError("Job rigidHandoff differs from the exact reviewed handoff")
    fields(handoff, ("schemaVersion", "profile", "coordinateFrame", "sourceRawSha256", "preparedGlb", "preparedGlbSha256",
                     "sourceToPreparedMatrix", "authoringEvidence", "authoringEvidenceSha256", "parts"), "Rigid handoff")
    integer(handoff["schemaVersion"], 1, 1, "handoff schemaVersion")
    if handoff["profile"] != "articulated" or handoff["coordinateFrame"] != "opencaw-proof-z-up":
        raise ValueError("Rigid handoff must explicitly declare articulated proof-frame geometry")
    if hash_value(handoff["sourceRawSha256"], "sourceRawSha256") != digest(source):
        raise ValueError("Rigid handoff raw ancestry differs from the actual reconstruction")
    matrix = handoff["sourceToPreparedMatrix"]
    if type(matrix) is not list or len(matrix) != 4 or any(type(row) is not list or len(row) != 4 for row in matrix):
        raise ValueError("sourceToPreparedMatrix must be an affine4x4")
    for row in matrix:
        for item in row:
            number(item, -1e9, 1e9, "sourceToPreparedMatrix component")
    if matrix[3] != [0, 0, 0, 1] or np.linalg.det(np.asarray(matrix, dtype=np.float64)[:3, :3]) <= 0:
        raise ValueError("sourceToPreparedMatrix must be finite affine with positive determinant")
    prepared = checked_file(root, handoff["preparedGlb"], handoff["preparedGlbSha256"])
    if prepared.suffix.lower() != ".glb":
        raise ValueError("Prepared geometry must be a fully embedded GLB")
    authoring_path = checked_file(root, handoff["authoringEvidence"], handoff["authoringEvidenceSha256"])
    authoring = strict_json(authoring_path, 524288, 16)
    fields(authoring, ("schemaVersion", "kind", "sourceRawSha256", "preparedGlbSha256", "sources", "repairs"), "Authoring evidence")
    integer(authoring["schemaVersion"], 1, 1, "authoring schemaVersion")
    if (authoring["kind"] != "rigid-part-authoring" or authoring["sourceRawSha256"] != handoff["sourceRawSha256"]
            or authoring["preparedGlbSha256"] != handoff["preparedGlbSha256"]):
        raise ValueError("Authoring evidence does not bind current raw/prepared ancestry")
    dependencies = {configuration["handoff"]: configuration["handoffSha256"], handoff["preparedGlb"]: handoff["preparedGlbSha256"],
                    handoff["authoringEvidence"]: handoff["authoringEvidenceSha256"]}
    if type(authoring["sources"]) is not list or not 1 <= len(authoring["sources"]) <= 64:
        raise ValueError("Authoring sources must contain1..64 actual dependencies")
    source_names = set()
    for dependency in authoring["sources"]:
        fields(dependency, ("path", "sha256", "role"), "Authoring source")
        checked_file(root, dependency["path"], dependency["sha256"])
        text(dependency["role"], "source role")
        if dependency["path"] in source_names:
            raise ValueError("Duplicate authoring source dependency")
        source_names.add(dependency["path"])
        dependencies[dependency["path"]] = dependency["sha256"]
    review_path = checked_file(root, configuration["reviewEvidence"], configuration["reviewEvidenceSha256"])
    if len(review_path.relative_to(root).parts) < 5 or tuple(review_path.relative_to(root).parts[:3]) != (".opencaw", ".cache", "tasks"):
        raise ValueError("Rigid preparation review must be task-local")
    # Match the active task directory from the stage job path, not another task.
    task_prefix = relative_path(job.get("taskEvidenceRoot"),"taskEvidenceRoot")
    if (len(task_prefix.split("/")) != 4 or task_prefix.split("/")[:3] != [".opencaw",".cache","tasks"]
            or not configuration["reviewEvidence"].startswith(task_prefix+"/")):
        raise ValueError("Review belongs to a different task")
    if "sourceTopology" in configuration:
        topology = configuration["sourceTopology"]
        if not topology["receipt"].startswith(task_prefix+"/"):
            raise ValueError("Source topology receipt belongs to a different task")
        if (topology["receipt"] not in source_names
                or dependencies.get(topology["receipt"]) != topology["receiptSha256"]):
            raise ValueError("Source topology receipt must be bound by reviewed authoring sources")
        checked_file(root, topology["receipt"], topology["receiptSha256"])
    review = strict_json(review_path, 65536, 8)
    fields(review, ("schemaVersion", "kind", "decision", "human", "reviewer", "reason", "sourceRawSha256", "preparedGlbSha256",
                    "handoffSha256", "authoringEvidenceSha256"), "Rigid preparation review")
    integer(review["schemaVersion"], 1, 1, "review schemaVersion")
    if review["kind"] != "rigid-preparation" or review["decision"] != "approved" or review["human"] is not False:
        raise ValueError("Current independent technical preparation review required; human acceptance is separate")
    text(review["reviewer"], "reviewer")
    text(review["reason"], "review reason")
    for field, expected in (("sourceRawSha256", handoff["sourceRawSha256"]), ("preparedGlbSha256", handoff["preparedGlbSha256"]),
                            ("handoffSha256", configuration["handoffSha256"]), ("authoringEvidenceSha256", handoff["authoringEvidenceSha256"])):
        if review[field] != expected:
            raise ValueError("Stale preparation review: " + field)
    dependencies[configuration["reviewEvidence"]] = configuration["reviewEvidenceSha256"]
    parts = handoff["parts"]
    if type(parts) is not list or not 1 <= len(parts) <= 128:
        raise ValueError("Rigid parts must contain1..128 entries")
    ids, meshes = set(), set()
    for part in parts:
        fields(part, ("id", "parentId", "pivot", "highObject", "lowObject", "maxTriangles", "maxVertexSurfaceErrorMetres",
                      "materialMode", "bakeGroup", "collision", "collisionReason"), "Rigid part")
        identity = identifier(part["id"], "part id")
        if identity in ids:
            raise ValueError("Duplicate rigid part id")
        ids.add(identity)
        if part["parentId"] is not None:
            identifier(part["parentId"], "parentId")
        pivot = part["pivot"]
        if type(pivot) is not list or len(pivot) != 3:
            raise ValueError("pivot requires three world-metre coordinates")
        for coordinate in pivot:
            number(coordinate, -1e9, 1e9, "pivot coordinate")
        for key in ("highObject", "lowObject"):
            name = text(part[key], key, 128)
            if name in meshes:
                raise ValueError("HIGH/LOW object identities must be disjoint and unique")
            meshes.add(name)
        integer(part["maxTriangles"], 4, 8_000_000, "part maxTriangles")
        number(part["maxVertexSurfaceErrorMetres"], 0, 1, "maxVertexSurfaceErrorMetres", True)
        if part["materialMode"] == "preserve":
            if part["bakeGroup"] is not None:
                raise ValueError("Preserve parts cannot declare a bakeGroup")
        elif part["materialMode"] == "bake":
            identifier(part["bakeGroup"], "bakeGroup")
        else:
            raise ValueError("Unknown part materialMode")
        if type(part["collision"]) is not bool:
            raise ValueError("collision applicability must be explicit")
        text(part["collisionReason"], "collisionReason")
    by_id = {part["id"]: part for part in parts}
    groups={part['bakeGroup'] for part in parts if part['materialMode']=='bake'}
    if len({group.casefold() for group in groups})!=len(groups):
        raise ValueError('Bake group names alias generated atlas filenames on case-insensitive filesystems')
    for part in parts:
        visited, current = set(), part
        while current["parentId"] is not None:
            if current["id"] in visited or current["parentId"] not in by_id:
                raise ValueError("Rigid parent hierarchy is cyclic or missing an owner")
            visited.add(current["id"])
            current = by_id[current["parentId"]]
    if type(authoring["repairs"]) is not list or len(authoring["repairs"]) != len(parts):
        raise ValueError("Authoring evidence must account for every rigid part")
    repair_ids = set()
    for repair in authoring["repairs"]:
        fields(repair, ("partId", "sourceKind", "sourceDescription", "highTriangles", "lowTriangles", "intentionalChanges"), "Part repair")
        if repair["partId"] not in ids or repair["partId"] in repair_ids or repair["sourceKind"] not in ("reconstruction-part", "authored-detail"):
            raise ValueError("Part repair identities/source kind differ from handoff")
        repair_ids.add(repair["partId"])
        text(repair["sourceDescription"], "sourceDescription")
        text(repair["intentionalChanges"], "intentionalChanges")
        integer(repair["highTriangles"], 1, 100_000_000, "highTriangles")
        integer(repair["lowTriangles"], 1, 8_000_000, "lowTriangles")
    if configuration.get('lods',{}).get('contactPolicy') == 'protected-contact-rings-v1':
        selection=configuration['sourceTopology']
        receipt_document=strict_json(checked_file(root,selection['receipt'],selection['receiptSha256']),67108864,32)
        _clod_contact_require_complete_receipt(receipt_document,parts)
    return handoff, prepared, authoring, dependencies


def _source_topology_bindings(root, settings, handoff, prepared):
    selection = settings["rigidParts"].get("sourceTopology")
    if selection is None:
        return {}
    import rigid_source_topology
    receipt = checked_file(root, selection["receipt"], selection["receiptSha256"])
    bindings = rigid_source_topology.load(
        receipt, prepared, handoff, sys.modules[__name__],
        expected_receipt_sha256=selection["receiptSha256"], max_file_bytes=2147483647)
    if settings['rigidParts'].get('lods',{}).get('contactPolicy') == 'protected-contact-rings-v1':
        if set(bindings) != {part['lowObject'] for part in handoff['parts']}:
            raise ValueError('Protected-contact LOD policy requires reviewed source-owner bindings for every selected LOW before import/UV/bake')
    return bindings


def material_document(document, data, material):
    """Canonical glTF material intent, resolving texture/image/sampler identities."""
    json_size = struct.unpack_from("<I", data, 12)[0]
    binary_start = 20 + json_size + 8
    def texture(info):
        entry = dict(info)
        index = entry.pop("index")
        definition = document["textures"][index]
        image = document["images"][definition["source"]]
        view = document["bufferViews"][image["bufferView"]]
        if view.get("buffer", 0) != 0:
            raise ValueError("Only one embedded image buffer is supported")
        start = binary_start + view.get("byteOffset", 0)
        end = start + view["byteLength"]
        if start < binary_start or end > len(data) or end <= start:
            raise ValueError("Invalid embedded image range")
        entry["imageSha256"] = hashlib.sha256(data[start:end]).hexdigest()
        entry["mimeType"] = image["mimeType"]
        entry["sampler"] = document.get("samplers", [])[definition["sampler"]] if "sampler" in definition else {}
        entry["texCoord"] = entry.get("texCoord", 0)
        return entry
    def normalize(item):
        if type(item) is dict:
            return {key: texture(value) if key.endswith("Texture") and type(value) is dict and "index" in value else normalize(value)
                    for key, value in item.items() if key not in ("name", "extras")}
        if type(item) is list:
            return [normalize(value) for value in item]
        return item
    result = normalize(material)
    pbr = result.setdefault("pbrMetallicRoughness", {})
    pbr.setdefault("baseColorFactor", [1, 1, 1, 1])
    pbr.setdefault("metallicFactor", 1)
    pbr.setdefault("roughnessFactor", 1)
    result.setdefault("emissiveFactor", [0, 0, 0])
    result.setdefault("alphaMode", "OPAQUE")
    result.setdefault("doubleSided", False)
    if result["alphaMode"] == "MASK":
        result.setdefault("alphaCutoff", 0.5)
    return result


def exact_preserve(high, low, api):
    if api.mesh_identity(high) != api.mesh_identity(low) or not np.array_equal(np.asarray(high.matrix_world), np.asarray(low.matrix_world)):
        raise ValueError("Preserve requires identical HIGH/LOW geometry and transforms, not reduced proxies")
    if [m.as_pointer() if m else None for m in high.data.materials] != [m.as_pointer() if m else None for m in low.data.materials]:
        raise ValueError("Preserve HIGH/LOW material identities differ")
    for attribute in ("material_index", "use_smooth"):
        if [getattr(p, attribute) for p in high.data.polygons] != [getattr(p, attribute) for p in low.data.polygons]:
            raise ValueError("Preserve material/shading correspondence differs")
    if len(high.data.uv_layers) != len(low.data.uv_layers):
        raise ValueError("Preserve UV layer count differs")
    for first, second in zip(high.data.uv_layers, low.data.uv_layers):
        if first.name!=second.name or first.active_render!=second.active_render:
            raise ValueError('Preserve UV names/render ownership differ')
        a = np.empty(len(first.data)*2, np.float32)
        b = np.empty(len(second.data)*2, np.float32)
        first.data.foreach_get("uv", a)
        second.data.foreach_get("uv", b)
        if a.tobytes() != b.tobytes():
            raise ValueError("Preserve UV coordinates differ")
    normal_a = np.empty(len(high.data.corner_normals)*3,np.float32)
    normal_b = np.empty(len(low.data.corner_normals)*3,np.float32)
    high.data.corner_normals.foreach_get("vector",normal_a)
    low.data.corner_normals.foreach_get("vector",normal_b)
    if normal_a.tobytes()!=normal_b.tobytes():
        raise ValueError("Preserve authored corner normals differ")
    specs = lambda mesh:[(attribute.name,attribute.domain,attribute.data_type) for attribute in mesh.color_attributes]
    if specs(high.data)!=specs(low.data):
        raise ValueError("Preserve vertex/corner color definitions differ")
    for first,second in zip(high.data.color_attributes,low.data.color_attributes):
        a = np.empty(len(first.data)*4,np.float32)
        b = np.empty(len(second.data)*4,np.float32)
        first.data.foreach_get("color",a)
        second.data.foreach_get("color",b)
        if a.tobytes()!=b.tobytes():
            raise ValueError("Preserve vertex/corner color values differ")
    return {"method": "exact authored HIGH/LOW geometry-transform-material-UV correspondence", "verified": True}


def validate_material(material, bake=False):
    if material is None or not material.use_nodes:
        raise ValueError("Rigid source requires explicit node materials")
    if material.animation_data is not None:
        raise ValueError("Animated source materials are not a static finishing input")
    outputs = [node for node in material.node_tree.nodes if node.type == "OUTPUT_MATERIAL" and node.is_active_output]
    if len(outputs) != 1 or len(outputs[0].inputs["Surface"].links) != 1:
        raise ValueError("Source material requires one explicit surface")
    shader = outputs[0].inputs["Surface"].links[0].from_node
    if shader.type != "BSDF_PRINCIPLED":
        raise ValueError("Portable rigid material must use Principled surface")
    if bake:
        for key in ("Emission Color", "Alpha", "Transmission Weight"):
            socket = shader.inputs[key]
            if (socket.is_linked or (key == "Alpha" and socket.default_value != 1)
                    or (key == "Transmission Weight" and socket.default_value != 0)):
                raise ValueError("Baked group must be opaque/nonemissive; preserve authored optical/electrical materials separately")
        if shader.inputs["Emission Strength"].default_value != 0 and any(shader.inputs["Emission Color"].default_value[:3]):
            raise ValueError("Baked group cannot discard source emission")
        for name,expected in (('IOR',1.5),('Specular IOR Level',.5),('Subsurface Weight',0),
                              ('Anisotropic',0),('Coat Weight',0),('Sheen Weight',0),('Thin Film Thickness',0)):
            socket=shader.inputs.get(name)
            if socket is not None and (socket.is_linked or abs(socket.default_value-expected)>1e-6):
                raise ValueError('Five-channel atlas cannot discard unsupported source lobe/property: '+name)
        tint=shader.inputs.get('Specular Tint')
        if tint is not None and (tint.is_linked or np.max(np.abs(np.asarray(tint.default_value)-1))>1e-6):
            raise ValueError('Five-channel atlas cannot discard source specular tint')
    for node in material.node_tree.nodes:
        if node.type == "SCRIPT" or node.type == "GROUP" and node.node_tree and node.node_tree.animation_data:
            raise ValueError("Executable/driven material source is forbidden")
        if node.type == "TEX_IMAGE":
            image = node.image
            if image is None or not image.packed_file or image.source != "FILE" or not all(image.size):
                raise ValueError("Only actual fully packed source images are accepted")
    return shader


_RUNTIME_ATTRIBUTE_TYPES = {
    'FLOAT':('value',1,np.float32), 'INT':('value',1,np.int32),
    'BOOLEAN':('value',1,np.bool_), 'FLOAT_VECTOR':('vector',3,np.float32),
    'FLOAT2':('vector',2,np.float32), 'INT32_2D':('value',2,np.int32),
    'INT16_2D':('value',2,np.int16), 'FLOAT_COLOR':('color',4,np.float32),
    'BYTE_COLOR':('color',4,np.float32), 'QUATERNION':('value',4,np.float32),
}


def _preservation_field(collection,prop,width,dtype):
    size=len(collection)*width*np.dtype(dtype).itemsize
    if size>67_108_864:
        raise ValueError('Runtime preservation field exceeds64MiB')
    values=np.empty(len(collection)*width,dtype)
    collection.foreach_get(prop,values)
    if np.issubdtype(values.dtype,np.floating) and not np.isfinite(values).all():
        raise ValueError('Runtime preservation field is nonfinite')
    return values


def _preservation_world_normals(obj,local):
    matrix=np.asarray(obj.matrix_world,np.float64)
    if not np.isfinite(matrix).all() or abs(np.linalg.det(matrix[:3,:3]))<=1e-12:
        raise ValueError('Runtime normal preservation requires a finite nonsingular frame')
    values=local.astype(np.float64) @ np.linalg.inv(matrix[:3,:3])
    magnitudes=np.linalg.norm(values,axis=1)
    if not np.isfinite(values).all() or not np.isfinite(magnitudes).all() or np.any(magnitudes<=0):
        raise ValueError('Runtime normal preservation requires finite nonzero corner normals')
    return values/magnitudes[:,None]


def _preservation_runtime_state(obj,api):
    mesh=obj.data
    definitions=[];fields={}
    uv_names={layer.name for layer in mesh.uv_layers}
    for attribute in mesh.attributes:
        if attribute.name in uv_names:
            continue
        if attribute.domain not in {'POINT','EDGE','FACE','CORNER'} or attribute.data_type not in _RUNTIME_ATTRIBUTE_TYPES:
            raise ValueError('Unsupported explicit runtime preservation field: '+attribute.name)
        definitions.append((attribute.name,attribute.domain,attribute.data_type))
        prop,width,dtype=_RUNTIME_ATTRIBUTE_TYPES[attribute.data_type]
        values=_preservation_field(attribute.data,prop,width,dtype)
        fields['attribute:'+attribute.name]=hashlib.sha256(memoryview(values)).hexdigest()
    for name,collection,prop,width,dtype in [
        ('positions',mesh.vertices,'co',3,np.float32),('edgeVertices',mesh.edges,'vertices',2,np.int32),
        ('loopVertices',mesh.loops,'vertex_index',1,np.int32),('loopEdges',mesh.loops,'edge_index',1,np.int32),
        ('faceStarts',mesh.polygons,'loop_start',1,np.int32),('faceSizes',mesh.polygons,'loop_total',1,np.int32),
        ('materials',mesh.polygons,'material_index',1,np.int32),('smooth',mesh.polygons,'use_smooth',1,np.bool_),
        ('edgeSharp',mesh.edges,'use_edge_sharp',1,np.bool_),('edgeSeams',mesh.edges,'use_seam',1,np.bool_)]:
        values=_preservation_field(collection,prop,width,dtype)
        fields[name]=hashlib.sha256(memoryview(values)).hexdigest()
    local=_preservation_field(mesh.corner_normals,'vector',3,np.float32).reshape((-1,3))
    if len(local)!=len(mesh.loops):
        raise ValueError('Runtime corner-normal count differs from exact loop ancestry')
    fields['decodedCornerNormals']=hashlib.sha256(memoryview(local)).hexdigest()
    return {'mesh':mesh.as_pointer(),'definitions':sorted(definitions),'fields':fields,
            'localNormals':local,'worldNormals':_preservation_world_normals(obj,local),
            'worldPositions':api.world_vertices(obj),'worldMatrix':np.asarray(obj.matrix_world,np.float64),
            'materials':[(mat.name,mat.as_pointer()) if mat else None for mat in mesh.materials]}


def _verify_runtime_preservation(before,obj,api,label,exact_world=False):
    after=_preservation_runtime_state(obj,api)
    if before['mesh']!=after['mesh'] or before['definitions']!=after['definitions'] or before['fields']!=after['fields'] or before['materials']!=after['materials']:
        raise ValueError(label+' changed actual runtime mesh data/raw or decoded normals')
    matrix_drift=float(np.max(np.abs(before['worldMatrix']-after['worldMatrix'])))
    position_drift=float(np.max(np.linalg.norm(before['worldPositions']-after['worldPositions'],axis=1)))
    normal_drift=float(np.max(np.abs(before['worldNormals']-after['worldNormals'])))
    if not all(math.isfinite(value) for value in (matrix_drift,position_drift,normal_drift)) or matrix_drift>1e-6 or position_drift>1e-6:
        raise ValueError(label+' changes actual world geometry beyond1micrometre')
    if normal_drift>2e-5:
        raise ValueError(label+' changes actual world corner normals')
    if exact_world and matrix_drift!=0:
        raise ValueError(label+' changed an immutable runtime object world frame')
    return {'maxPositionDriftMetres':position_drift,'maxCornerNormalDrift':normal_drift,
            'maxWorldMatrixDifference':matrix_drift,'localMeshAndRawDecodedNormalsBitExact':True}


def rebase_low(low,pivot,parent,api):
    """Keep mesh/local normals intact; encode a child offset under its pivot."""
    if low.type!='MESH' or parent is None or parent.type!='EMPTY' or bpy.context.mode!='OBJECT':
        raise ValueError('Pivot attachment requires an object-mode mesh and explicit semantic empty')
    pivot=np.asarray(pivot,np.float64)
    if pivot.shape!=(3,) or not np.isfinite(pivot).all():
        raise ValueError('Finite explicit world pivot required')
    bpy.context.view_layer.update()
    parent_matrix=np.asarray(parent.matrix_world,np.float64)
    if not np.isfinite(parent_matrix).all() or abs(np.linalg.det(parent_matrix[:3,:3]))<=1e-12:
        raise ValueError('Pivot attachment requires a finite nonsingular parent frame')
    if np.max(np.abs(parent_matrix[:3,3]-pivot))>1e-6:
        raise ValueError('Semantic parent origin differs from declared world pivot')
    cursor=parent
    while cursor is not None:
        if cursor==low:
            raise ValueError('Pivot attachment would create a parent cycle')
        cursor=cursor.parent
    before=_preservation_runtime_state(low,api)
    original_parent=low.parent
    original_inverse=low.matrix_parent_inverse.copy()
    original_transform={key:tuple(getattr(low,key)) for key in
                        ('location','rotation_euler','rotation_quaternion','rotation_axis_angle','scale',
                         'delta_location','delta_rotation_euler','delta_rotation_quaternion','delta_scale')}
    world=low.matrix_world.copy()
    relative=parent.matrix_world.inverted() @ world
    location,rotation,scale=relative.decompose()
    representable=Matrix.LocRotScale(location,rotation,scale)
    # The pinned GLB exporter serializes child transforms as TRS. Unsupported
    # relative shear cannot be silently lost or baked into protected mesh data.
    if float(np.max(np.abs(np.asarray(relative)-np.asarray(representable))))>1e-6:
        raise ValueError('Pivot child offset contains unsupported relative shear for the fixed GLB exporter')
    try:
        low.parent=parent
        low.matrix_parent_inverse=Matrix.Identity(4)
        low.matrix_basis=relative
        bpy.context.view_layer.update()
        result=_verify_runtime_preservation(before,low,api,'Pivot attachment')
        result.update({'method':'semantic-pivot-child-offset','meshDataReencoded':False,'normalSetterInvoked':False,
                       'semanticParent':parent.name,'childLocalMatrix':[list(row) for row in low.matrix_local],
                       'parentInverseIdentity':True,'relativeTransformTrsVerified':True})
        return result
    except BaseException:
        low.parent=original_parent
        low.matrix_parent_inverse=original_inverse
        for key,value in original_transform.items():
            setattr(low,key,value)
        bpy.context.view_layer.update()
        raise


def _capture_uv_layers(mesh):
    return {'active':mesh.uv_layers.active_index,
            'layers':[(layer.name,layer.active_render,layer.active_clone,
                       _preservation_field(layer.data,'uv',2,np.float32)) for layer in mesh.uv_layers]}


def _restore_uv_layers(mesh,snapshot):
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    for name,render,clone,values in snapshot['layers']:
        layer=mesh.uv_layers.new(name=name)
        layer.data.foreach_set('uv',values)
        layer.active_render=render
        layer.active_clone=clone
    if mesh.uv_layers:
        mesh.uv_layers.active_index=snapshot['active']


_uvrepair_MAX_FACES=200000


_uvrepair_MAX_FIELD=67108864


_uvrepair_MAX_REFERENCES=8000000


_uvrepair_MAX_VISITS=20000000


_uvrepair_MAX_PAIRS=5000000


_uvrepair_MAX_EDGES=1000000


_uvrepair_SECONDS=180


class _uvrepair_Error(ValueError):
    def __init__(self,message,evidence=None):
        super().__init__(message)
        self.evidence={} if evidence is None else evidence


class _uvrepair_Report(dict):
    """Compact JSON report; optional complete allocation records remain private."""
    pass


def _uvrepair_hash(values):return hashlib.sha256(values.tobytes()).hexdigest()


def _uvrepair_config(size,margin,configuration):
    if type(configuration) is not dict or set(configuration)!={'method','minCellPixels','maxTriangles'} or configuration['method']!='density-preserving-isolated-cells-v1':raise _uvrepair_Error('Explicit closed triangleRepair selection required')
    if type(configuration['minCellPixels']) is not int or configuration['minCellPixels']!=4:raise _uvrepair_Error('triangleRepair.minCellPixels must be4')
    if type(configuration['maxTriangles']) is not int or not 1<=configuration['maxTriangles']<=16384:raise _uvrepair_Error('triangleRepair.maxTriangles must be an integer1..16384')
    if type(size) is not int or not 8<=size<=8192 or size&(size-1):raise _uvrepair_Error('Selected triangle repair requires power-of-two textureSize8..8192')
    if type(margin) is not int or not 1<=margin<=64 or margin>size/8:raise _uvrepair_Error('Selected triangle repair requires explicit island margin1..64 and<=textureSize/8')
    return configuration['maxTriangles']


def _uvrepair_exact(uv):
    bits=uv.view(np.uint32)&np.uint32(0x7fffffff);exponents=((bits>>23)&255)[bits!=0]
    power=int(max(0,np.max(np.where(exponents>0,150-exponents.astype(np.int32),149)))) if len(exponents) else 0
    scaled=np.ldexp(uv.astype(np.float64),power)
    triangles=[tuple(int(x) for x in row) for row in scaled.reshape((-1,6))]
    axes=[];collapsed=[]
    for face,row in enumerate(triangles):
        x0,y0,x1,y1,x2,y2=row
        if (x1-x0)*(y2-y0)-(y1-y0)*(x2-x0)==0:axes.append(None);collapsed.append(face);continue
        value=[]
        for ax,ay,bx,by in [(x0,y0,x1,y1),(x1,y1,x2,y2),(x2,y2,x0,y0)]:
            nx,ny=ay-by,bx-ax;q0=nx*x0+ny*y0;q1=nx*x1+ny*y1;q2=nx*x2+ny*y2
            value.append((nx,ny,min(q0,q1,q2),max(q0,q1,q2)))
        axes.append(value)
    return triangles,axes,np.asarray(collapsed,np.int32),power


def _uvrepair_sat(first,second,first_axes,second_axes):
    for other,axes in ((second,first_axes),(first,second_axes)):
        x0,y0,x1,y1,x2,y2=other
        for nx,ny,lo,hi in axes:
            a=nx*x0+ny*y0;b=nx*x1+ny*y1;c=nx*x2+ny*y2
            if max(a,b,c)<=lo or min(a,b,c)>=hi:return False
    return True


def _uvrepair_graph(uv,checkpoint):
    triangles,axes,collapsed,power=_uvrepair_exact(uv)
    c=uv.reshape((-1,3,2));lower=c.min(axis=1).astype(np.float64);upper=c.max(axis=1).astype(np.float64)
    side=512;first=np.floor(lower*side).astype(np.int32);last=np.minimum(np.floor(upper*side).astype(np.int32),side-1)
    valid=np.asarray([axis is not None for axis in axes],np.bool_)
    refs=int(np.sum(((last[:,0]-first[:,0]+1).astype(np.int64)*(last[:,1]-first[:,1]+1))[valid]))
    if refs>_uvrepair_MAX_REFERENCES:raise _uvrepair_Error('Exact UV graph reference budget exceeded')
    checkpoint('graph:before-grid')
    bins=[None]*(side*side)
    for face in np.flatnonzero(valid):
        face=int(face)
        for y in range(int(first[face,1]),int(last[face,1])+1):
            for x in range(int(first[face,0]),int(last[face,0])+1):
                key=y*side+x
                if bins[key] is None:bins[key]=[]
                bins[key].append(face)
        if face%4096==0:checkpoint('graph:build-grid')
    lo_x,lo_y=lower[:,0].tolist(),lower[:,1].tolist();hi_x,hi_y=upper[:,0].tolist(),upper[:,1].tolist()
    fx,fy=first[:,0].tolist(),first[:,1].tolist();visits=pairs=0;positive=[]
    for key,items in enumerate(bins):
        if not items or len(items)<2:continue
        y,x=divmod(key,side);visits+=len(items)*(len(items)-1)//2
        if visits>_uvrepair_MAX_VISITS:raise _uvrepair_Error('Exact UV graph pair-visit budget exceeded')
        for ordinal,a in enumerate(items[:-1]):
            if ordinal%64==0:checkpoint('graph:pair-loop')
            for b in items[ordinal+1:]:
                if max(fx[a],fx[b])!=x or max(fy[a],fy[b])!=y:continue
                if max(lo_x[a],lo_x[b])>=min(hi_x[a],hi_x[b]) or max(lo_y[a],lo_y[b])>=min(hi_y[a],hi_y[b]):continue
                pairs+=1
                if pairs>_uvrepair_MAX_PAIRS:raise _uvrepair_Error('Exact UV graph candidate budget exceeded')
                if _uvrepair_sat(triangles[a],triangles[b],axes[a],axes[b]):
                    positive.append((a,b))
                    if len(positive)>_uvrepair_MAX_EDGES:raise _uvrepair_Error('Exact UV graph edge budget exceeded')
        if key%1024==0:checkpoint('graph:exact-pairs')
    edges=np.asarray(sorted(positive),np.uint32).reshape((-1,2))
    return edges,collapsed,{'allFacesChecked':len(c),'exactCollapsedFaces':len(collapsed),'positiveEdges':len(edges),
        'strictAabbCandidatePairs':pairs,'binPairVisits':visits,'gridReferences':refs,'dyadicDenominatorPower':power,
        'positiveEdgePayloadSha256':_uvrepair_hash(edges),'predicate':'Strict exact integer SAT; boundary contacts excluded; no epsilon.'}


def _uvrepair_float_areas(uv):
    c=uv.astype(np.float64).reshape((-1,3,2));a,b=c[:,1]-c[:,0],c[:,2]-c[:,0]
    return np.abs(a[:,0]*b[:,1]-a[:,1]*b[:,0])/2


def _uvrepair_cover(uv,edges,mandatory,size,checkpoint):
    count=len(uv)//3;pixels=uv.astype(np.float64).reshape((-1,3,2))*size
    e=np.stack((pixels[:,1]-pixels[:,0],pixels[:,2]-pixels[:,1],pixels[:,0]-pixels[:,2]),axis=1)
    q=np.sum(e*e,axis=2);chosen=np.argmax(q,axis=1);length=np.sqrt(q[np.arange(count),chosen])
    v,w=pixels[:,1]-pixels[:,0],pixels[:,2]-pixels[:,0];det=np.abs(v[:,0]*w[:,1]-v[:,1]*w[:,0])
    height=np.divide(det,length,out=np.zeros_like(det),where=length>0)
    width=np.full(count,4,np.int64);high=width.copy()
    nonzero=length>0;width[nonzero]=np.maximum(4,np.exp2(np.floor(np.log2(length[nonzero]))+1)).astype(np.int64)
    nonzero=height>0;high[nonzero]=np.maximum(4,np.exp2(np.floor(np.log2(height[nonzero]))+1)).astype(np.int64)
    # Cost uses a fixed minimum4px chart and2px nominal border, independently
    # of the later actual margin/packing. It affects selection only, never proof.
    pw=np.exp2(np.ceil(np.log2(width+4))).astype(np.int64);ph=np.exp2(np.ceil(np.log2(high+4))).astype(np.int64)
    weights=pw*ph;adj=[[] for _ in range(count)]
    for number,(a,b) in enumerate(edges):adj[int(a)].append(number);adj[int(b)].append(number)
    selected=np.zeros(count,np.bool_);selected[mandatory]=True
    live=~(selected[edges[:,0]]|selected[edges[:,1]]) if len(edges) else np.empty(0,np.bool_)
    degree=np.zeros(count,np.int32)
    for ei in np.flatnonzero(live):
        a,b=map(int,edges[ei]);degree[a]+=1;degree[b]+=1
    heap=[(_uvrepair_F(int(weights[i]),int(d)),i,int(d)) for i,d in enumerate(degree) if d];heapq.heapify(heap);order=[]
    while heap:
        ratio,face,old=heapq.heappop(heap)
        if selected[face] or degree[face]!=old or degree[face]==0:continue
        selected[face]=True;order.append(face)
        for ei in adj[face]:
            if not live[ei]:continue
            live[ei]=False;a,b=map(int,edges[ei]);other=b if a==face else a;degree[other]-=1
            if degree[other]>0 and not selected[other]:heapq.heappush(heap,(_uvrepair_F(int(weights[other]),int(degree[other])),other,int(degree[other])))
        degree[face]=0
        if len(order)%64==0:checkpoint('cover:greedy')
    if np.any(live):raise _uvrepair_Error('Deterministic cover left an uncovered edge')
    mandatory_set=set(map(int,mandatory))
    for face in reversed(order):
        if face not in mandatory_set and all(selected[int(b) if int(a)==face else int(a)] for a,b in edges[adj[face]]):selected[face]=False
    if len(edges) and not np.all(selected[edges[:,0]]|selected[edges[:,1]]):raise _uvrepair_Error('Reverse-pruned cover is incomplete')
    return np.flatnonzero(selected).astype(np.uint32)


def _uvrepair_fraction(value):return _uvrepair_F(float(value))


def _uvrepair_density(source,target,order,size):
    a,b,c=order;s=[[_uvrepair_fraction(x)*size for x in row] for row in source];t=[[_uvrepair_fraction(x)*size for x in row] for row in target]
    av=[[s[b][i]-s[a][i] for i in range(2)],[s[c][i]-s[a][i] for i in range(2)]]
    bv=[[t[b][i]-t[a][i] for i in range(2)],[t[c][i]-t[a][i] for i in range(2)]]
    dot=lambda x,y:sum((p*q for p,q in zip(x,y)),_uvrepair_F(0))
    c11=dot(bv[0],bv[0])-dot(av[0],av[0]);c22=dot(bv[1],bv[1])-dot(av[1],av[1]);c12=dot(bv[0],bv[1])-dot(av[0],av[1]);det=c11*c22-c12*c12
    payload={'c11':str(c11),'c22':str(c22),'c12':str(c12),'determinant':str(det)}
    certificate=hashlib.sha256(json.dumps(payload,sort_keys=True).encode()).hexdigest()
    return c11>=0 and c22>=0 and det>=0,certificate,(c11,c22,det)


def _uvrepair_ceil_sqrt(value):
    root=math.isqrt(value.numerator//value.denominator)
    return root if root*root==value else root+1


def repair_triangle_uvs(coordinates,size,margin,configuration,check=None):
    maximum=_uvrepair_config(size,margin,configuration)
    configuration=dict(configuration)
    if type(coordinates) is not np.ndarray or coordinates.dtype!=np.dtype(np.float32) or coordinates.ndim!=2 or coordinates.shape[1]!=2 or len(coordinates)%3 or not coordinates.flags.c_contiguous:raise _uvrepair_Error('Consecutive native float32 triangle-corner UV array required')
    count=len(coordinates)//3
    if not 1<=count<=_uvrepair_MAX_FACES or coordinates.nbytes>_uvrepair_MAX_FIELD or count*3*2*8>_uvrepair_MAX_FIELD:raise _uvrepair_Error('Fixed UV field/face allocation cap exceeded')
    if not np.isfinite(coordinates).all() or np.any(coordinates<0) or np.any(coordinates>1):raise _uvrepair_Error('Finite unit-tile input UVs required; no clamp')
    before=_uvrepair_hash(coordinates);started=time.monotonic();phase='start';partial={'relocated':0}
    def checkpoint(stage):
        nonlocal phase
        phase=stage
        if time.monotonic()-started>_uvrepair_SECONDS:raise _uvrepair_Error('Fixed UV repair wall budget exceeded',{'phase':phase,**partial})
        if check is not None:
            check(stage)
            if _uvrepair_hash(coordinates)!=before:raise _uvrepair_Error('Input UV array changed externally',{'phase':phase,**partial})
        if stage in ('healthy-final','successful-final') and _uvrepair_hash(coordinates)!=before:raise _uvrepair_Error('Input UV array changed externally',{'phase':phase,**partial})
    try:
        checkpoint('before-source-graph')
        edges,collapsed,graph_before=_uvrepair_graph(coordinates,checkpoint)
        native_zero=np.flatnonzero(_uvrepair_float_areas(coordinates)<=0)
        mandatory=np.union1d(collapsed,native_zero).astype(np.int32)
        if len(mandatory)>maximum:raise _uvrepair_Error('Required collapsed/native-zero relocations exceed maxTriangles')
        if not len(edges) and not len(mandatory):
            checkpoint('healthy-final')
            report=_uvrepair_Report(method=configuration['method'],policy=dict(configuration),textureSize=size,islandMarginPixels=margin,
                originalUvF32Sha256=before,finalUvF32Sha256=before,relocatedTriangles=0,relocatedFaceIndices=[],
                graphBefore=graph_before,graphAfter=graph_before,allUntouchedUvBitsExact=True,inputArrayReturnedUnchanged=True,
                noPositiveOverlapInCompleteFinalGraph=True,mipIsolationOrVisualQualityClaimed=False)
            report.allocation_proof=[]
            return coordinates,report
        checkpoint('before-cover')
        target_ids=_uvrepair_cover(coordinates,edges,mandatory,size,checkpoint)
        if len(target_ids)>maximum:raise _uvrepair_Error('Complete overlap cover plus collapsed faces exceeds maxTriangles',{'required':len(target_ids),'maximum':maximum})
        partial['selected']=len(target_ids);moved=np.zeros(count,np.bool_);moved[target_ids]=True
        c=coordinates.reshape((-1,3,2));pixels=c.astype(np.float64)*size;lower=pixels.min(axis=1);upper=pixels.max(axis=1)
        side=size//8
        if not 1<=side<=1024 or (side+1)**2*4>_uvrepair_MAX_FIELD:raise _uvrepair_Error('Fixed adaptive grid cap exceeded')
        first=np.maximum((np.ceil((lower-margin)/8)-1).astype(np.int32),0);last=np.minimum(np.floor((upper+margin)/8).astype(np.int32),side-1)
        a=first[~moved];b=last[~moved];diff=np.zeros((side+1,side+1),np.int32)
        np.add.at(diff,(a[:,1],a[:,0]),1);np.add.at(diff,(b[:,1]+1,a[:,0]),-1);np.add.at(diff,(a[:,1],b[:,0]+1),-1);np.add.at(diff,(b[:,1]+1,b[:,0]+1),1)
        occupied=np.cumsum(np.cumsum(diff,axis=0,dtype=np.int32),axis=1,dtype=np.int32)[:side,:side]>0
        free_before=int(np.count_nonzero(~occupied));rows=[int.from_bytes(np.packbits(~occupied[y],bitorder='little').tobytes(),'little') for y in range(side)]
        collapsed_set=set(map(int,collapsed));charts=[]
        for face in map(int,target_ids):
            if face in collapsed_set:charts.append((face,True,(0,1,2),4,4,_uvrepair_F(0)));continue
            p=[[_uvrepair_fraction(x)*size for x in row] for row in c[face]];pairs=[(0,1,2),(1,2,0),(2,0,1)]
            qvalues=[sum((p[b][i]-p[a][i])**2 for i in range(2)) for a,b,unused in pairs]
            a,b,third=pairs[max(range(3),key=lambda i:qvalues[i])]
            e=[p[b][i]-p[a][i] for i in range(2)];v=[p[third][i]-p[a][i] for i in range(2)];det=e[0]*v[1]-e[1]*v[0]
            if det<0:a,b=b,a;e=[p[b][i]-p[a][i] for i in range(2)];v=[p[third][i]-p[a][i] for i in range(2)];det=-det
            q=sum(x*x for x in e);height_squared=det*det/q
            width=max(4,_uvrepair_ceil_sqrt(q)+1);height=max(4,_uvrepair_ceil_sqrt(height_squared)+1)
            projection=sum(e[i]*v[i] for i in range(2))/q
            if not 0<=projection<=1:raise _uvrepair_Error('Longest-edge projection outside its exact interval')
            charts.append((face,False,(a,b,third),width,height,projection))
        charts.sort(key=lambda row:(-((row[3]+2*margin+7)//8)*((row[4]+2*margin+7)//8),-max((row[3]+2*margin+7)//8,(row[4]+2*margin+7)//8),row[0]))
        def find_space(gw,gh):
            if gw>side or gh>side:return None
            for y in range(side-gh+1):
                bits=rows[y]
                for yy in range(y+1,y+gh):
                    bits&=rows[yy]
                    if not bits:break
                if not bits:continue
                run=bits;length=1
                while length*2<=gw:run&=run>>length;length*=2
                if gw>length:run&=run>>(gw-length)
                if run:return y,(run&-run).bit_length()-1
            return None
        checkpoint('before-output-copy');result=coordinates.copy();proof=[];used=0;density_count=0;minima=None
        for ordinal,(face,is_collapsed,order,width,height,projection) in enumerate(charts):
            checkpoint('before-chart:'+str(ordinal));gw=(width+2*margin+7)//8;gh=(height+2*margin+7)//8;choices=[]
            for rotation,(w,h) in enumerate(((gw,gh),(gh,gw))):
                location=find_space(w,h)
                if location is not None:choices.append((*location,rotation,w,h))
            if not choices:raise _uvrepair_Error('Finite adaptive allocation has no space; no shrinking/repack fallback',{'phase':phase,**partial})
            y,x,rotation,gw,gh=min(choices);projection*=width
            local=[(_uvrepair_F(0),_uvrepair_F(0)),(_uvrepair_F(width),_uvrepair_F(0)),(projection,_uvrepair_F(height))] if rotation==0 else [(_uvrepair_F(height),_uvrepair_F(0)),(_uvrepair_F(height),_uvrepair_F(width)),(_uvrepair_F(0),projection)]
            target=np.empty((3,2),np.float32)
            for original_corner,(xx,yy) in zip(order,local):target[original_corner]=(float((x*8+margin+xx)/size),float((y*8+margin+yy)/size))
            if not np.isfinite(target).all() or np.any(target<0) or np.any(target>1):raise _uvrepair_Error('Stored adaptive triangle leaves unit tile')
            if is_collapsed:certificate=None
            else:
                valid,certificate,values=_uvrepair_density(c[face],target,order,size)
                if not valid:raise _uvrepair_Error('Exact stored-F32 density GramPSD failed; no tolerance waiver',{'face':face})
                density_count+=1;minima=values if minima is None else tuple(min(a,b) for a,b in zip(minima,values))
            actual=target.astype(np.float64)*size;lo=actual.min(0);hi=actual.max(0)
            # Exact stored dyadic target must stay inside its reserved parent
            # rectangle with margin on each side. Disjoint occupied blocks then
            # prove new/old and new/new separation >=margin (no UV epsilon).
            parent_lo=np.asarray((x*8,y*8));parent_hi=np.asarray(((x+gw)*8,(y+gh)*8))
            if np.any(lo-parent_lo<margin) or np.any(parent_hi-hi<margin):raise _uvrepair_Error('Stored adaptive triangle escaped its exact parent padding')
            result[face*3:face*3+3]=target;mask=((1<<gw)-1)<<x
            for yy in range(y,y+gh):rows[yy]&=~mask
            used+=gw*gh;partial['relocated']=ordinal+1
            proof.append({'sourceFace':face,'originalCollapsed':is_collapsed,'sourceCornerPermutation':list(order),'adaptiveInnerWidthHeightPixels':[width,height],
                'parentBlockXY':[x,y],'parentBlockWidthHeight':[gw,gh],'rotationDegrees':90*rotation,'newUvF32':target.tolist(),
                'exactStoredF32DensityGramPsd':None if is_collapsed else True,'exactGramCertificateSha256':certificate})
        if result.reshape((-1,3,2))[~moved].tobytes()!=c[~moved].tobytes():raise _uvrepair_Error('Untouched UV bits changed')
        if np.any(_uvrepair_float_areas(result)<=0):raise _uvrepair_Error('Final stored UV area guard failed')
        checkpoint('before-complete-final-graph');final_edges,final_collapsed,graph_after=_uvrepair_graph(result,checkpoint)
        if len(final_edges) or len(final_collapsed):raise _uvrepair_Error('Complete final UV graph is not zero',graph_after)
        checkpoint('successful-final')
        proof_sha=hashlib.sha256(json.dumps(proof,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        report=_uvrepair_Report(method=configuration['method'],policy=dict(configuration),textureSize=size,islandMarginPixels=margin,
            originalUvF32Sha256=before,finalUvF32Sha256=_uvrepair_hash(result),relocatedTriangles=len(target_ids),relocatedFaceIndices=target_ids.tolist(),
            originalCollapsedFaceIndices=collapsed.tolist(),nativeFloat64ZeroFaceIndices=native_zero.tolist(),
            graphBefore=graph_before,graphAfter=graph_after,allUntouchedUvBitsExact=True,inputArrayReturnedUnchanged=False,
            exactStoredF32DensityPassCount=density_count,collapsedDensityExceptionCount=len(collapsed),
            minimumExactDensityGramC11=None if minima is None else str(minima[0]),minimumExactDensityGramC22=None if minima is None else str(minima[1]),
            minimumExactDensityGramDeterminant=None if minima is None else str(minima[2]),
            allocationProofSha256=proof_sha,parentGridCellPixels=8,gridSide=side,freeParentBlocksBefore=free_before,usedParentBlocks=used,
            freeParentBlocksAfter=sum(row.bit_count() for row in rows),newChartMinimumSeparationPixels=margin,
            continuousMarginProof='All stored new AABBs lie margin inside distinct unoccupied grid-parent rectangles; all untouched closed AABBs expanded bymargin conservatively occupy every intersected cell.',
            noPositiveOverlapInCompleteFinalGraph=True,mipIsolationOrVisualQualityClaimed=False,
            limits='Exact UV graph/density/separation only. Actual raster/material/tangent bakes, derivative/package constraints and mip/visual acceptance remain separate.')
        report.allocation_proof=proof
        return result,report
    except _uvrepair_Error:raise
    except BaseException:raise


def _owner_uv_helper_inputs(lows,source_states,source_topology):
    """Validate the complete owner/scatter mapping before creating native data."""
    import rigid_source_topology
    if type(source_topology) is not dict or set(source_topology)!={low.name for low in lows}:
        raise ValueError('Source-owned UV helpers require every selected LOW binding')
    result=[]
    for low,state in zip(lows,source_states):
        binding=source_topology[low.name]
        if type(binding) is not rigid_source_topology.Binding:
            raise ValueError('Source-owned UV helper requires a reviewed native Binding')
        topology=binding.uv_helper_topology(low,sys.modules[__name__])
        world=np.asarray(state['worldPositions'],np.float32)
        native=topology['nativeLoopVertices']
        owners=topology['triangleOwners'].reshape(-1)
        if len(native)*3*np.dtype(np.float32).itemsize>67_108_864:
            raise ValueError('Source-owned UV helper corner field exceeds64MiB')
        points=world[topology['nativeVertexForOwner']].copy()
        original_corners=world[native]
        if not np.isfinite(world).all() or original_corners.tobytes()!=points[owners].tobytes():
            raise ValueError('Source-owned UV helper changes original world float32 corners')
        proof=dict(topology['proof'],
                   worldFloat32CornerSha256=hashlib.sha256(original_corners.tobytes()).hexdigest(),
                   worldFrameSha256=hashlib.sha256(state['worldMatrix'].astype('<f8').tobytes()).hexdigest(),
                   ownerTriangleSha256=hashlib.sha256(owners.astype('<i4',copy=False).tobytes()).hexdigest(),
                   exactWorldFloat32Corners=True, exactOriginalLoopScatter=True,
                   runtimeGraphOrNormalsChanged=False)
        result.append({'points':points,'faces':topology['triangleOwners'],'proof':proof})
    return result


def pack_group(lows,recipe,name,uv_atlas=None,*,source_topology=None):
    """Geometric-only pack/coverage helper; preserve real runtime LOW normals."""
    import finish as api
    if bpy.context.mode!='OBJECT' or not lows or len({low.as_pointer() for low in lows})!=len(lows):
        raise ValueError('Atlas packing requires distinct object-mode runtime LOWs')
    source_states=[_preservation_runtime_state(low,api) for low in lows]
    owner_inputs=None if source_topology is None else _owner_uv_helper_inputs(lows,source_states,source_topology)
    source_uv=[_capture_uv_layers(low.data) for low in lows]
    selection=[(obj,obj.select_get()) for obj in bpy.context.scene.objects]
    active=bpy.context.view_layer.objects.active
    mesh=obj=None
    scatter_started=False;complete=False
    try:
        points,faces,mapping=[],[],[]
        offset=0
        for low_index,(low,state) in enumerate(zip(lows,source_states)):
            owner_input=None if owner_inputs is None else owner_inputs[low_index]
            points.extend((state['worldPositions'] if owner_input is None else owner_input['points']).tolist())
            for polygon in low.data.polygons:
                if len(polygon.vertices)!=3:
                    raise ValueError('Prepared LOW must have stable triangulated topology before normal baking')
                vertices=polygon.vertices if owner_input is None else owner_input['faces'][polygon.index]
                faces.append(tuple(offset+int(i) for i in vertices))
                mapping.extend((low,li) for li in polygon.loop_indices)
            offset+=len(low.data.vertices) if owner_input is None else len(owner_input['points'])
        mesh=bpy.data.meshes.new('ATLAS_TARGET_'+name)
        mesh.from_pydata(points,[],faces)
        mesh.update()
        if len(mesh.loops)!=len(mapping):
            raise ValueError('Atlas join lost exact loop ancestry')
        # This helper is never a runtime normal carrier or the HIGH-to-LOW bake
        # target. Smart UV and white-EMIT coverage use its own flat geometry.
        for polygon in mesh.polygons:
            polygon.use_smooth=False
        helper_points=_preservation_field(mesh.vertices,'co',3,np.float32)
        if owner_inputs is not None:
            if len(mesh.loops)*3*np.dtype(np.float32).itemsize>67_108_864:
                raise ValueError('Joined source-owned UV helper corner field exceeds64MiB')
            helper_loops=_preservation_field(mesh.loops,'vertex_index',1,np.int32)
            helper_corners=helper_points.reshape((-1,3))[helper_loops]
            first=0
            for low,owner_input in zip(lows,owner_inputs):
                stop=first+len(low.data.loops)
                if hashlib.sha256(helper_corners[first:stop].tobytes()).hexdigest()!=owner_input['proof']['worldFloat32CornerSha256']:
                    raise ValueError('Native source-owned UV helper changed original corner bits/order')
                first=stop
        helper_normals=_preservation_field(mesh.corner_normals,'vector',3,np.float32).reshape((-1,3))
        if np.any(np.linalg.norm(helper_normals,axis=1)<=0):
            raise ValueError('Geometric UV helper has degenerate native face normals')
        obj=bpy.data.objects.new('ATLAS_TARGET_'+name,mesh)
        bpy.context.collection.objects.link(obj)
        activate(obj)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        if uv_atlas is None:
            status=bpy.ops.uv.smart_project(island_margin=recipe['uvMargin'],scale_to_bounds=True)
        else:
            status=bpy.ops.uv.smart_project(margin_method='FRACTION',island_margin=uv_atlas['islandMarginFraction'],scale_to_bounds=True)
        if status!={'FINISHED'}:
            raise ValueError('Explicit pixel UV packing did not finish' if uv_atlas else 'Global UV packing did not finish')
        bpy.ops.object.mode_set(mode='OBJECT')
        if len(mesh.loops)!=len(mapping) or [tuple(p.vertices) for p in mesh.polygons]!=faces:
            raise ValueError('Explicit pixel UV packing changed triangle/loop ancestry')
        if _preservation_field(mesh.vertices,'co',3,np.float32).tobytes()!=helper_points.tobytes():
            raise ValueError('Global UV packing changed geometric helper vertices')
        packed_normals=_preservation_field(mesh.corner_normals,'vector',3,np.float32).reshape((-1,3))
        helper_drift=float(np.max(np.abs(packed_normals-helper_normals)))
        if not math.isfinite(helper_drift) or helper_drift>2e-5:
            raise ValueError('Global UV packing changed geometric-only helper normals')
        coordinates=_preservation_field(mesh.uv_layers.active.data,'uv',2,np.float32).reshape((-1,2))
        if coordinates.shape!=(len(mapping),2):
            raise ValueError('Explicit pixel UV packing produced missing UVs')
        if uv_atlas is not None:
            if "triangleRepair" in uv_atlas:
                coordinates,triangle_repair=repair_triangle_uvs(coordinates,recipe['textureSize'],uv_atlas['islandMarginPixels'],uv_atlas['triangleRepair'])
                if triangle_repair['relocatedTriangles']:
                    mesh.uv_layers.active.data.foreach_set('uv',coordinates.reshape(-1))
                stored_uv=_preservation_field(mesh.uv_layers.active.data,'uv',2,np.float32).reshape((-1,2))
                if stored_uv.tobytes()!=coordinates.tobytes():
                    raise ValueError('Triangle repair native helper UV storage changed declared float32 bits')
                uv_atlas=dict(uv_atlas,triangleRepairResult=triangle_repair)
            if np.any(coordinates<0) or np.any(coordinates>1):
                raise ValueError('Explicit pixel UV packing produced UVs outside unit tile')
            corners=coordinates.astype(np.float64).reshape((-1,3,2))
            first,second=corners[:,1]-corners[:,0],corners[:,2]-corners[:,0]
            areas=np.abs(first[:,0]*second[:,1]-first[:,1]*second[:,0])/2
            if np.any(areas<=0):
                raise ValueError('Explicit pixel UV packing produced degenerate UV triangles')
            uv_atlas=dict(uv_atlas,triangles=len(areas),zeroAreaTriangles=0,unitTile=True,
                          summedUvTriangleArea=float(np.sum(areas)),
                          helperNormalPolicy='geometric-only; not authored runtime normals',
                          maxGeometricHelperCornerNormalDrift=helper_drift,
                          limits='Summed triangle area and requested margin do not prove raster coverage, spacing or lack of overlap')
        for low,before in zip(lows,source_states):
            _verify_runtime_preservation(before,low,api,'UV helper preparation',exact_world=True)
        scatter_started=True
        for low in lows:
            while low.data.uv_layers:
                low.data.uv_layers.remove(low.data.uv_layers[0])
            low.data.uv_layers.new(name='UVMap')
        for index,(low,loop) in enumerate(mapping):
            low.data.uv_layers.active.data[loop].uv=coordinates[index]
        preservation=[_verify_runtime_preservation(before,low,api,'Explicit pixel UV scatter',exact_world=True)
                      for low,before in zip(lows,source_states)]
        digest_uv=hashlib.sha256()
        for low in lows:
            values=_preservation_field(low.data.uv_layers.active.data,'uv',2,np.float32)
            digest_uv.update(memoryview(values))
        obj.hide_render=True
        obj.hide_set(True)
        report={'target':obj.name,'parts':[low['semanticPart'] for low in lows],'loops':len(mapping),
                'globalPack':True,'exactLoopScatter':True,'uvSha256':digest_uv.hexdigest(),
                'helperNormalPolicy':'geometric-only; never runtime or selected HIGH-to-LOW target',
                'helperNormalSetterInvoked':False,'maxGeometricHelperCornerNormalDrift':helper_drift,
                'runtimeLowNormalPreservation':preservation}
        if uv_atlas is not None:
            report['uvAtlas']=uv_atlas
        if owner_inputs is not None:
            report['sourceOwnerHelper']={'method':'reviewed-source-corners-v1',
                'scope':'geometric UV helper only; original runtime LOW indexed graph and normals unchanged',
                'parts':[row['proof'] for row in owner_inputs],
                'helperVertices':len(mesh.vertices),'triangles':len(mesh.polygons),
                'exactWorldFloat32Corners':True,'exactOriginalLoopScatter':True,
                'coordinateWeld':False,'sourceSmoothingOrNormalSetter':False}
        complete=True
        return report
    finally:
        if bpy.context.mode!='OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')
        if not complete and scatter_started:
            for low,previous in zip(lows,source_uv):
                _restore_uv_layers(low.data,previous)
        if not complete:
            if obj is not None:
                bpy.data.objects.remove(obj,do_unlink=True)
            if mesh is not None and mesh.users==0:
                bpy.data.meshes.remove(mesh)
        for item,selected in selection:
            item.select_set(selected)
        bpy.context.view_layer.objects.active=active




def atlas_self_bake(helper, recipe, api, name, margin, source=None):
    """One all-chart EMIT pass, with a distinct image and a restored helper scope."""
    if helper is None or helper.type != "MESH" or not helper.data.uv_layers.active:
        raise ValueError("Global atlas padding requires its existing packed UV helper")
    if bpy.context.mode != "OBJECT":
        raise ValueError("Global atlas padding requires object mode")
    before = inspection_identity(helper, api)
    mesh = helper.data
    original_materials = list(mesh.materials)
    original_indices = np.empty(len(mesh.polygons), np.int32)
    mesh.polygons.foreach_get("material_index", original_indices)
    selection = [(obj, obj.select_get()) for obj in bpy.context.scene.objects]
    active = bpy.context.view_layer.objects.active
    visibility = (helper.hide_get(), helper.hide_viewport, helper.hide_render)
    bake = bpy.context.scene.render.bake
    settings = {key:getattr(bake, key) for key in ("use_selected_to_active", "use_clear", "margin")}
    image, material, complete = None, None, False
    try:
        image = bpy.data.images.new(name, width=recipe["textureSize"], height=recipe["textureSize"],
                                    alpha=False, float_buffer=False)
        image.colorspace_settings.name = source.colorspace_settings.name if source else "Non-Color"
        image.generated_color = tuple(source.generated_color) if source else (0,0,0,1)
        if source:
            if source is image or source.is_float or source.channels not in (3,4):
                raise ValueError("Global padding requires distinct byte-backed source/destination images")
            image.generated_type = source.generated_type
            image.alpha_mode = source.alpha_mode
        material = bpy.data.materials.new("ATLAS_PADDING_"+name)
        material.use_nodes = True
        nodes = material.node_tree.nodes
        nodes.clear()
        emission = nodes.new("ShaderNodeEmission")
        emission.inputs["Strength"].default_value = 1
        emission.inputs["Color"].default_value = (1,1,1,1)
        surface = nodes.new("ShaderNodeOutputMaterial")
        material.node_tree.links.new(emission.outputs[0], surface.inputs["Surface"])
        if source:
            texture = nodes.new("ShaderNodeTexImage")
            texture.image = source
            texture.interpolation = "Closest"
            texture.extension = "EXTEND"
            uv = nodes.new("ShaderNodeUVMap")
            uv.uv_map = mesh.uv_layers.active.name
            material.node_tree.links.new(uv.outputs["UV"], texture.inputs["Vector"])
            material.node_tree.links.new(texture.outputs["Color"], emission.inputs["Color"])
        destination = nodes.new("ShaderNodeTexImage")
        destination.image = image
        for node in nodes:
            node.select = node == destination
        nodes.active = destination
        mesh.materials.clear()
        mesh.materials.append(material)
        for polygon in mesh.polygons:
            polygon.material_index = 0
        helper.hide_viewport = False
        helper.hide_set(False)
        helper.hide_render = False
        activate(helper)
        bake.use_selected_to_active = False
        bake.use_clear = source is None
        bake.margin = margin
        status = bpy.ops.object.bake(type="EMIT")
        if status != {"FINISHED"}:
            raise ValueError("Global atlas coverage/padding bake did not finish: " + repr(status))
        complete = True
    finally:
        mesh.materials.clear()
        for original in original_materials:
            mesh.materials.append(original)
        mesh.polygons.foreach_set("material_index", original_indices)
        helper.hide_viewport = visibility[1]
        helper.hide_render = visibility[2]
        helper.hide_set(visibility[0])
        for obj, selected in selection:
            obj.select_set(selected)
        bpy.context.view_layer.objects.active = active
        for key,value in settings.items():
            setattr(bake, key, value)
        if material is not None:
            bpy.data.materials.remove(material)
        if not complete and image is not None:
            bpy.data.images.remove(image)
    try:
        if inspection_identity(helper, api) != before:
            raise ValueError("Global atlas bake changed packed helper geometry/UV/normals/materials")
    except Exception:
        bpy.data.images.remove(image)
        raise
    return image


def atlas_pixels(image, size):
    if tuple(image.size) != (size,size) or len(image.pixels) != size*size*4 or image.is_float:
        raise ValueError("Global atlas requires complete byte-backed RGBA pixel buffers")
    values = np.empty(size*size*4, np.float32)
    image.pixels.foreach_get(values)
    for start in range(0,len(values),262144):
        chunk = values[start:start+262144]
        if not np.isfinite(chunk).all() or np.any(chunk < 0) or np.any(chunk > 1):
            raise ValueError("Global atlas has nonfinite/out-of-range byte pixels")
    return values.reshape((-1,4))


def atlas_coverage(helper, recipe, api):
    image = atlas_self_bake(helper, recipe, api, "ATLAS_PADDING_COVERAGE", 0)
    try:
        values = atlas_pixels(image, recipe["textureSize"])
        covered = np.empty(len(values), np.bool_)
        for start in range(0,len(values),65536):
            rgb = values[start:start+65536,:3]
            if np.any((rgb > 1e-6) & (rgb < 1-1e-6)) or np.any(np.abs(rgb-rgb[:,0:1]) > 1e-6):
                raise ValueError("Global atlas coverage is not a binary independent white EMIT mask")
            covered[start:start+65536] = rgb[:,0] > .5
        count = int(np.count_nonzero(covered))
        if count == 0:
            raise ValueError("Global atlas coverage has no occupied pixels")
        return covered, {"method":"all-chart-margin0-white-emit", "occupiedPixels":count,
                         "pixels":len(covered), "maskSha256":hashlib.sha256(memoryview(covered)).hexdigest(),
                         "blackIsValidData":True, "maskMarginPixels":0}
    finally:
        bpy.data.images.remove(image)


def pad_atlas_image(helper, source, covered, recipe, api):
    """Preserve every authoritative texel; let Cycles pad all charts together."""
    size = recipe["textureSize"]
    if covered.dtype != np.bool_ or covered.shape != (size*size,) or not np.any(covered):
        raise ValueError("Global atlas padding requires the complete nonempty coverage mask")
    before = atlas_pixels(source, size)
    original_hash = hashlib.sha256(memoryview(before)).hexdigest()
    margin = max(1, int(size * recipe["uvMargin"]))
    destination = atlas_self_bake(helper, recipe, api, source.name+"_PADDED", margin, source)
    try:
        source_after = atlas_pixels(source, size)
        if hashlib.sha256(memoryview(source_after)).hexdigest() != original_hash:
            raise ValueError("Global atlas padding changed its immutable unpadded source image")
        del source_after
        after = atlas_pixels(destination, size)
        maximum = 0.0
        chunk_pixels = 65536
        for start in range(0,len(covered),chunk_pixels):
            mask = covered[start:start+chunk_pixels]
            if not np.any(mask):
                continue
            delta = np.abs(after[start:start+chunk_pixels,:3][mask]-before[start:start+chunk_pixels,:3][mask])
            maximum = max(maximum, float(delta.max()))
            if maximum > 1/255 + 2e-7:
                raise ValueError("Global atlas padding changed an authoritative occupied pixel")
        return destination, {"method":"all-chart-self-image-emit", "sourceDestinationDistinct":True,
                             "sampler":"Closest", "wrap":"EXTEND", "perPartMarginPixels":0,
                             "globalMarginPixels":margin, "occupiedPixelsVerified":int(np.count_nonzero(covered)),
                             "sourcePixelSha256":original_hash, "maxStoredByteDrift":maximum*255,
                             "storedByteTolerance":1, "comparisonFloatEpsilon":2e-7,
                             "colorSpace":source.colorspace_settings.name,
                             "byteBacked":True, "generatedColor":list(source.generated_color),
                             "comparison":"all occupied RGB stored8-bit channels; sRGB code values for basecolor, Non-Color for data",
                             "comparisonChunkPixels":chunk_pixels,
                             "explicitBufferBoundBytes":size*size*33+chunk_pixels*3*4*4}
    except Exception:
        bpy.data.images.remove(destination)
        raise


def bake_group(pairs, recipe, output, group, api, uv_atlas=None, *, source_topology=None):
    lows = [low for high, low in pairs]
    packing = (pack_group(lows, recipe, group, uv_atlas) if source_topology is None else
               pack_group(lows, recipe, group, uv_atlas, source_topology=source_topology))
    material = bpy.data.materials.new("ATLAS_"+group)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    shader = nodes.get("Principled BSDF")
    for low in lows:
        low.data.materials.clear()
        low.data.materials.append(material)
        for polygon in low.data.polygons:
            polygon.material_index = 0
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.use_clear = False
    scene.render.bake.cage_extrusion = recipe["cageExtrusion"]
    scene.render.bake.max_ray_distance = recipe["maxRayDistance"]
    scene.render.bake.margin = 0 if uv_atlas is not None else max(1, int(recipe["textureSize"] * recipe["uvMargin"]))
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.use_pass_color = True
    scene.render.bake.normal_space = "TANGENT"
    scene.render.bake.normal_r, scene.render.bake.normal_g, scene.render.bake.normal_b = "POS_X", "POS_Y", "POS_Z"
    if uv_atlas is not None:
        helper = bpy.data.objects.get(packing["target"])
        covered, coverage_report = atlas_coverage(helper, recipe, api)
        packing["padding"] = {"coverage":coverage_report, "channels":{}}
    maps = {}
    for channel, bake_type in (("basecolor", "EMIT"), ("normal", "NORMAL"), ("ao", "AO"), ("roughness", "ROUGHNESS"), ("metallic", "EMIT")):
        image = bpy.data.images.new("ATLAS_"+group+"_"+channel, width=recipe["textureSize"], height=recipe["textureSize"], alpha=False)
        image.colorspace_settings.name = "sRGB" if channel == "basecolor" else "Non-Color"
        image.generated_color = (0.5,0.5,1,1) if channel == "normal" else (0,0,0,1)
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        texture.select = True
        nodes.active = texture
        for high, low in pairs:
            saved = []
            try:
                if channel in ("basecolor", "metallic"):
                    seen = set()
                    for source_material in high.data.materials:
                        if source_material.as_pointer() in seen:
                            continue
                        seen.add(source_material.as_pointer())
                        source_shader = validate_material(source_material, bake=True)
                        tree = source_material.node_tree
                        surface = next(node for node in tree.nodes if node.type == "OUTPUT_MATERIAL" and node.is_active_output)
                        links = [(link.from_socket, link.to_socket) for link in surface.inputs["Surface"].links]
                        emission = tree.nodes.new("ShaderNodeEmission")
                        saved.append((tree, emission, links))
                        field = source_shader.inputs["Base Color" if channel == "basecolor" else "Metallic"]
                        if field.is_linked:
                            tree.links.new(field.links[0].from_socket, emission.inputs["Color"])
                        elif channel == "basecolor":
                            emission.inputs["Color"].default_value = tuple(field.default_value)
                        else:
                            emission.inputs["Color"].default_value = (field.default_value,)*3+(1,)
                        emission.inputs["Strength"].default_value = 1
                        tree.links.new(emission.outputs[0], surface.inputs["Surface"])
                activate(low)
                low.hide_set(False)
                low.hide_render = False
                high.hide_set(False)
                high.hide_render = False
                high.select_set(True)
                status = bpy.ops.object.bake(type=bake_type)
                if status != {"FINISHED"}:
                    raise ValueError("Atlas bake did not finish: " + repr(status))
            finally:
                high.hide_render = True
                low.hide_render = True
                for tree, emission, links in reversed(saved):
                    tree.nodes.remove(emission)
                    for start, end in links:
                        tree.links.new(start, end)
        if uv_atlas is not None:
            padded, padding_report = pad_atlas_image(helper, image, covered, recipe, api)
            original_name = image.name
            texture.image = padded
            bpy.data.images.remove(image)
            image = padded
            image.name = original_name
            packing["padding"]["channels"][channel] = padding_report
        path = output/("atlas_"+group+"_"+channel+".png")
        image.filepath_raw = str(path)
        image.file_format = "PNG"
        image.save()
        image.pack()
        pixels = np.empty(len(image.pixels), np.float32)
        image.pixels.foreach_get(pixels)
        if not len(pixels) or not np.isfinite(pixels).all():
            raise ValueError("Atlas bake has missing/nonfinite pixels")
        maximum = float(pixels.reshape((-1,4))[:,:3].max())
        if channel in ("normal", "ao") and maximum <= 0:
            raise ValueError("Atlas bake has no normal/AO surface signal")
        maps[channel] = {"path": path, "image": image, "texture": texture,
                         "measurement": {"width": image.size[0], "height": image.size[1], "maxRgb": maximum,
                                         "sha256": digest(path), "bakeType": bake_type, "colorSpace": image.colorspace_settings.name,
                                         "sourceTransport": "principled-input-via-unit-emission" if channel in ("basecolor","metallic") else "cycles-native"}}
        del pixels
    links = material.node_tree.links
    for channel, socket in (("basecolor","Base Color"),("roughness","Roughness"),("metallic","Metallic")):
        links.new(maps[channel]["texture"].outputs["Color"], shader.inputs[socket])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.space = "TANGENT"
    links.new(maps["normal"]["texture"].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], shader.inputs["Normal"])
    settings = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    settings.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    node = nodes.new("ShaderNodeGroup")
    node.node_tree = settings
    links.new(maps["ao"]["texture"].outputs["Color"], node.inputs["Occlusion"])
    return material, maps, packing


def corner_snapshot(obj):
    """Every oriented triangle corner, UV and material; no mesh-count-only claim."""
    obj.data.calc_loop_triangles()
    points = np.asarray([list(obj.matrix_world @ vertex.co) for vertex in obj.data.vertices], np.float64)
    records = []
    layers=list(obj.data.uv_layers)
    normal_matrix = np.linalg.inv(np.asarray(obj.matrix_world,np.float64)[:3,:3]).T
    for triangle in obj.data.loop_triangles:
        positions = points[list(triangle.vertices)]
        coordinates = np.asarray([[list(layer.data[i].uv) for i in triangle.loops] for layer in layers], np.float64)
        normals = np.asarray([list(obj.data.corner_normals[i].vector) for i in triangle.loops],np.float64) @ normal_matrix.T
        normals /= np.linalg.norm(normals,axis=1)[:,None]
        first = min(range(3), key=lambda i: tuple(np.round(positions[i],6)))
        positions = np.roll(positions,-first,axis=0)
        coordinates = np.roll(coordinates,-first,axis=1)
        normals = np.roll(normals,-first,axis=0)
        mat = obj.data.materials[obj.data.polygons[triangle.polygon_index].material_index]
        records.append((tuple(np.round(positions,6).reshape(-1)), positions.reshape(-1), coordinates.reshape(-1), mat.name,normals.reshape(-1)))
    records.sort(key=lambda value: (value[0], value[3], tuple(np.round(value[2],6))))
    return {"positions": np.asarray([record[1] for record in records]),
            "uv": np.asarray([record[2] for record in records]), "materials": [record[3] for record in records],
            "normals":np.asarray([record[4] for record in records])}


def verify_corners(expected, obj):
    actual = corner_snapshot(obj)
    if (expected["positions"].shape != actual["positions"].shape or expected['uv'].shape!=actual['uv'].shape
            or expected["materials"] != actual["materials"]):
        raise ValueError("Independent re-import lost actual triangle/material correspondence")
    position = float(np.max(np.abs(expected["positions"]-actual["positions"])))
    uv = float(np.max(np.abs(expected["uv"]-actual["uv"])))
    normal = float(np.max(np.abs(expected["normals"]-actual["normals"])))
    if position > 1e-6 or uv > 2e-6:
        raise ValueError("Independent re-import changed triangle corners or UV correspondence")
    if normal>2e-5:
        raise ValueError("Independent re-import changed actual corner normals")
    return {"allOrientedTriangleCorners": True,"maxPositionDifferenceMetres":position,"maxUvDifference":uv,
            "maxCornerNormalDifference":normal}


def texture_route(socket, visited=None):
    """Inspect actual imported shader connections, including ORM channel ownership."""
    if len(socket.links) != 1:
        raise ValueError("Imported texture channel lacks one exact connection")
    output = socket.links[0].from_socket
    node = output.node
    visited = set() if visited is None else visited
    if node.as_pointer() in visited:
        raise ValueError("Cyclic imported material connection")
    visited.add(node.as_pointer())
    if node.type == "TEX_IMAGE":
        if node.image is None or not node.image.packed_file:
            raise ValueError("Imported texture is not actually embedded/decoded")
        if node.projection!='FLAT':
            raise ValueError('Unsupported imported texture projection')
        vector=node.inputs['Vector']
        uv_map=None
        if vector.is_linked:
            if len(vector.links)!=1:
                raise ValueError('Ambiguous imported texture Vector source')
            uv_source=vector.links[0].from_socket
            if uv_source.node.type=='UVMAP':
                uv_map=uv_source.node.uv_map
            elif uv_source.node.type!='TEX_COORD' or uv_source.name!='UV':
                raise ValueError('Unsupported imported texture Vector/transform route')
        return {"image":node.image,"component":3 if output.name=="Alpha" else None,"factor":1.0,
                'uvMap':uv_map,'interpolation':node.interpolation,'extension':node.extension}
    if node.type in ("SEPRGB","SEPARATE_COLOR"):
        route = texture_route(node.inputs[0],visited)
        component = {"R":0,"G":1,"B":2,"Red":0,"Green":1,"Blue":2}.get(output.name)
        if component is None or route["component"] is not None:
            raise ValueError("Unsupported imported texture channel selector")
        route["component"] = component
        if np.asarray(route['factor']).ndim:
            route['factor']=float(np.asarray(route['factor'])[component])
        return route
    if node.type == "NORMAL_MAP":
        if node.space != "TANGENT" or node.inputs["Strength"].is_linked:
            raise ValueError("Imported tangent normal convention/strength differs")
        route=texture_route(node.inputs["Color"],visited)
        route['normalScale']=float(node.inputs['Strength'].default_value)
        return route
    if node.type == "MATH" and node.operation == "MULTIPLY":
        linked = [item for item in node.inputs[:2] if item.is_linked]
        constants = [item for item in node.inputs[:2] if not item.is_linked]
        if len(linked)==len(constants)==1:
            route = texture_route(linked[0],visited)
            route["factor"] *= constants[0].default_value
            return route
    if node.type in ('MIX_RGB','MIX') and node.blend_type=='MULTIPLY':
        if node.type=='MIX' and node.data_type!='RGBA':
            raise ValueError('Unsupported imported noncolor factor transport')
        factor=node.inputs[0]
        inputs=node.inputs[1:3] if node.type=='MIX_RGB' else node.inputs[6:8]
        linked=[item for item in inputs if item.is_linked]
        constants=[item for item in inputs if not item.is_linked]
        if factor.is_linked or factor.default_value!=1 or len(linked)!=1 or len(constants)!=1:
            raise ValueError('Unsupported imported color blend/factor')
        route=texture_route(linked[0],visited)
        if route['component'] is not None:
            raise ValueError('Unsupported imported scalar/color factor conversion')
        route['factor']=np.asarray(route['factor'])*np.asarray(constants[0].default_value[:3])
        return route
    raise ValueError("Unsupported imported texture transport; explicit material correction required: "+node.type)


def verify_imported_material(material, description, atlas=None, meshes=None):
    shader = validate_material(material)
    pbr = description["pbrMetallicRoughness"]
    expected_ior=description.get('extensions',{}).get('KHR_materials_ior',{}).get('ior',1.5)
    if shader.inputs['IOR'].is_linked or abs(shader.inputs['IOR'].default_value-expected_ior)>1e-6:
        raise ValueError('Actual imported IOR differs from the encoded portable material')
    constants = (("Base Color",pbr["baseColorFactor"]),("Metallic",pbr["metallicFactor"]),
                 ("Roughness",pbr["roughnessFactor"]))
    for key,value in constants:
        socket = shader.inputs[key]
        if not socket.is_linked:
            actual = np.asarray(socket.default_value,dtype=np.float64)
            expected = np.asarray(value,dtype=np.float64)
            if key=="Base Color":
                # glTF's fourth base factor routes to the separate Alpha
                # socket; Blender keeps Base Color's own fourth slot at1.
                actual,expected = actual[:3],expected[:3]
            if np.max(np.abs(actual-expected))>1e-6:
                raise ValueError("Actual imported PBR factor differs: "+material.name+" / "+key)
    if not shader.inputs["Alpha"].is_linked and abs(shader.inputs["Alpha"].default_value-pbr["baseColorFactor"][3])>1e-6:
        raise ValueError("Actual imported alpha factor differs")
    strength = description.get("extensions",{}).get("KHR_materials_emissive_strength",{}).get("emissiveStrength",1)
    if not shader.inputs["Emission Color"].is_linked:
        actual_emission = np.asarray(shader.inputs["Emission Color"].default_value[:3])*shader.inputs["Emission Strength"].default_value
        expected_emission = np.asarray(description["emissiveFactor"])*strength
        if np.max(np.abs(actual_emission-expected_emission))>1e-6*max(1,strength):
            raise ValueError("Actual imported effective emission differs")
    elif abs(shader.inputs['Emission Strength'].default_value-strength)>1e-6*max(1,strength):
        raise ValueError('Actual imported linked emission strength differs')
    channels = [("basecolor",pbr.get("baseColorTexture"),shader.inputs["Base Color"],None,"sRGB"),
                ("roughness",pbr.get("metallicRoughnessTexture"),shader.inputs["Roughness"],1,"Non-Color"),
                ("metallic",pbr.get("metallicRoughnessTexture"),shader.inputs["Metallic"],2,"Non-Color"),
                ("normal",description.get("normalTexture"),shader.inputs["Normal"],None,"Non-Color"),
                ("emission",description.get("emissiveTexture"),shader.inputs["Emission Color"],None,"sRGB")]
    if description.get("occlusionTexture"):
        settings = [node for node in material.node_tree.nodes if node.type=="GROUP" and "Occlusion" in node.inputs]
        if len(settings)!=1:
            raise ValueError("Actual imported AO texture connection is missing/ambiguous")
        channels.append(("ao",description["occlusionTexture"],settings[0].inputs["Occlusion"],0,"Non-Color"))
    if pbr.get('baseColorTexture') and description['alphaMode']!='OPAQUE':
        channels.append(('alpha',pbr['baseColorTexture'],shader.inputs['Alpha'],3,'sRGB'))
    reports = []
    for channel,info,socket,component,space in channels:
        if info is None:
            continue
        route = texture_route(socket)
        image = route["image"]
        if (route["component"]!=component or hashlib.sha256(image.packed_file.data).hexdigest()!=info["imageSha256"]
                or image.colorspace_settings.name!=space):
            raise ValueError("Actual imported texture bytes/channel/colorspace differ: "+channel)
        expected_factor={'basecolor':pbr['baseColorFactor'][:3],'roughness':pbr['roughnessFactor'],
                         'metallic':pbr['metallicFactor'],'emission':description['emissiveFactor'],
                         'alpha':pbr['baseColorFactor'][3]}.get(channel,1)
        if np.max(np.abs(np.asarray(route['factor'])-np.asarray(expected_factor)))>1e-6:
            raise ValueError('Actual imported effective texture factor differs: '+channel)
        if info.get('extensions'):
            raise ValueError('Unsupported preserved texture transform/extension; explicit material/UV correction required')
        texcoord=info.get('texCoord',0)
        if type(texcoord) is not int or texcoord<0:
            raise ValueError('Invalid actual texture UV index')
        used=[obj for obj in bpy.context.scene.objects if obj.type=='MESH' and material in list(obj.data.materials)] if meshes is None else meshes
        if not used:
            raise ValueError('No actual mesh owns the imported material')
        for obj in used:
            if texcoord>=len(obj.data.uv_layers):
                raise ValueError('Actual texture UV set is missing')
            expected_uv=obj.data.uv_layers[texcoord].name
            if (route['uvMap'] is None and (texcoord!=0 or not obj.data.uv_layers[0].active_render)
                    or route['uvMap'] is not None and route['uvMap']!=expected_uv):
                raise ValueError('Actual texture Vector/texCoord ownership differs')
        sampler=info.get('sampler',{})
        nearest={9728,9984,9986};linear={9729,9985,9987}
        mag=sampler.get('magFilter');minimum=sampler.get('minFilter')
        if mag is not None and mag not in (9728,9729) or minimum is not None and minimum not in nearest|linear:
            raise ValueError('Unsupported actual texture sampler filter')
        classes={value in nearest for value in (mag,minimum) if value is not None}
        if len(classes)>1:
            raise ValueError('Mixed min/mag filter cannot be certified through this native material route')
        interpolation='Closest' if classes=={True} else 'Linear'
        wraps=[sampler.get('wrapS',10497),sampler.get('wrapT',10497)]
        if wraps[0]!=wraps[1] or wraps[0] not in (10497,33071,33648):
            raise ValueError('Mixed/unsupported sampler wrap needs explicit material correction')
        extension={10497:'REPEAT',33071:'EXTEND',33648:'MIRROR'}[wraps[0]]
        if route['interpolation']!=interpolation or route['extension']!=extension:
            raise ValueError('Actual imported texture sampler differs')
        if channel=='normal' and abs(route.get('normalScale',1)-info.get('scale',1))>1e-6:
            raise ValueError('Actual imported tangent normal scale differs')
        report = {"channel":channel,"imageSha256":info["imageSha256"],"component":component,
                  "colorSpace":space,"actualConnectionVerified":True,
                  'effectiveFactor':np.asarray(route['factor']).tolist(),'texCoord':texcoord,
                  'interpolation':interpolation,'extension':extension}
        if atlas is not None and channel in atlas:
            if np.max(np.abs(np.asarray(route['factor'])-1))>1e-6:
                raise ValueError("Actual atlas channel gained an undocumented multiplier")
            expected_image = bpy.data.images.load(str(atlas[channel]["path"]),check_existing=False)
            try:
                expected_image.colorspace_settings.name = space
                if tuple(expected_image.size)!=tuple(image.size):
                    raise ValueError("Re-imported atlas changes actual dimensions")
                expected_pixels = np.empty(len(expected_image.pixels),np.float32)
                actual_pixels = np.empty(len(image.pixels),np.float32)
                expected_image.pixels.foreach_get(expected_pixels)
                image.pixels.foreach_get(actual_pixels)
                a,b = expected_pixels.reshape((-1,4)),actual_pixels.reshape((-1,4))
                selected_expected = a[:,:3] if component is None else a[:,0]
                selected_actual = b[:,:3] if component is None else b[:,component]
                difference = float(np.max(np.abs(selected_expected-selected_actual)))
                if not math.isfinite(difference) or difference>1/255+1e-6:
                    raise ValueError("Actual re-imported atlas pixel/channel differs from its baked source: "+channel)
                report.update({"allPixelsVerified":True,"pixels":len(a),"maxEncodedChannelDifference":difference,
                               "maximumAllowed8bitEncodingDifference":1/255+1e-6})
                del expected_pixels,actual_pixels
            finally:
                bpy.data.images.remove(expected_image)
        reports.append(report)
    return {"material":material.name,"actualPbrFactorsVerified":True,"textures":reports}


def inspect_pairs(handoff, authoring, imported, recipe, settings, api, source_topology=None):
    """Read-only actual pair inspection; transient exact-weld topology copies only."""
    by_name = {obj.name: obj for obj in imported}
    parts = handoff["parts"]
    expected = {part[key] for part in parts for key in ("highObject","lowObject")}
    if set(by_name) != expected:
        raise ValueError("Prepared GLB must exactly account for all HIGH/LOW mesh names")
    if recipe["parts"] and set(recipe["parts"]) != {part["id"] for part in parts}:
        raise ValueError("Recipe semantic parts differ from the reviewed rigid handoff")
    runtime_names = ["PROOF_TO_MODEL"] + [part["id"] for part in parts]
    for part in parts:
        runtime_names.extend(part["id"]+"_LOD"+str(level) for level in range(len(recipe["lodRatios"])+1))
        if part["collision"]:
            runtime_names.append(part["id"]+"_COLLISION")
    if len(set(runtime_names)) != len(runtime_names):
        raise ValueError("Rigid semantic identities cause runtime naming collisions")
    repairs = {repair["partId"]: repair for repair in authoring["repairs"]}
    report_by_id, pairs, high_identities, preserve_names = {}, {}, {}, set()
    for part in parts:
        high, low = by_name[part["highObject"]], by_name[part["lowObject"]]
        determinants={}
        for label,obj in (('high',high),('low',low)):
            matrix=np.asarray(obj.matrix_world,np.float64)
            determinant=float(np.linalg.det(matrix[:3,:3]))
            if not np.isfinite(matrix).all() or not math.isfinite(determinant) or determinant<=0:
                raise ValueError('Rigid HIGH/LOW requires a positive realized world basis; apply authored mirrors before handoff')
            determinants[label]=determinant
        if high.modifiers or low.modifiers or high.animation_data or low.animation_data:
            raise ValueError("Reviewed rigid meshes must be actual static geometry, not modifiers/animation")
        if triangles(high) != repairs[part["id"]]["highTriangles"] or triangles(low) != repairs[part["id"]]["lowTriangles"]:
            raise ValueError("Authoring triangle evidence differs from the actual imported HIGH/LOW")
        if triangles(low) > part["maxTriangles"]:
            raise ValueError("Rigid LOW exceeds its explicit part triangle limit")
        high_identities[part["id"]] = api.mesh_identity(high)
        # A GLB has split UV/hard-normal vertices. Inspect topology on an exact
        # coincident-only welded COPY, never modify the reviewed authored LOW.
        binding = (source_topology or {}).get(low.name)
        if binding is not None:
            candidate = binding.inspection_copy(low, sys.modules[__name__])
        else:
            candidate = low.copy()
            candidate.data = low.data.copy()
            bpy.context.collection.objects.link(candidate)
            bm = bmesh.new()
            try:
                bm.from_mesh(candidate.data)
                coincident, targets = {}, {}
                for vertex in bm.verts:
                    key = tuple(vertex.co)
                    if key in coincident:
                        targets[vertex] = coincident[key]
                    else:
                        coincident[key] = vertex
                if targets:
                    bmesh.ops.weld_verts(bm,targetmap=targets)
                bm.to_mesh(candidate.data)
            finally:
                bm.free()
        try:
            topology = api.require_usable(candidate, "rigid LOW")
            if binding is not None:
                topology['reviewedSourceCornerTopology'] = binding.summary()
        finally:
            data = candidate.data
            bpy.data.objects.remove(candidate, do_unlink=True)
            bpy.data.meshes.remove(data)
        world_volume=topology['signedVolume']*determinants['low']
        if not math.isfinite(world_volume) or world_volume<=1e-15:
            raise ValueError('Rigid LOW has no usable positive world-metre volume')
        measured = api.surface_deviation(high, low)
        for direction in ("sourceToCandidate","candidateToSource"):
            if measured[direction]["measuredMaximumPlusRepresentationErrorsMetres"] > part["maxVertexSurfaceErrorMetres"]:
                raise ValueError("Rigid HIGH/LOW exceeds the declared every-vertex surface bound: "+part["id"])
        for material in high.data.materials:
            validate_material(material, bake=part["materialMode"]=="bake")
        preservation = None
        if part["materialMode"] == "preserve":
            preservation = exact_preserve(high,low,api)
            preserve_names.update(material.name for material in low.data.materials)
            if not low.data.uv_layers:
                if any(node.type=="TEX_IMAGE" for material in low.data.materials for node in material.node_tree.nodes):
                    raise ValueError("Textured preserve LOW requires actual retained UVs")
        pairs[part["id"]] = (high,low)
        report_by_id[part["id"]] = {"part":part["id"],"sourceHighObject":part["highObject"],"sourceLowObject":part["lowObject"],
                                    "sourceKind":repairs[part["id"]]["sourceKind"],"intentionalChanges":repairs[part["id"]]["intentionalChanges"],
                                    "triangles":triangles(low),"topology":topology,"highToLow":measured,"materialMode":part["materialMode"],
                                    "preservation":preservation,"sourceGeometrySha256":high_identities[part["id"]],
                                    "declaredMaxVertexSurfaceErrorMetres":part["maxVertexSurfaceErrorMetres"],
                                    "declaredMaxTriangles":part["maxTriangles"],"pivot":part["pivot"],"parentId":part["parentId"],
                                    'actualWorldDeterminants':determinants,'actualLowWorldSignedVolume':world_volume}
    lod0_count = sum(triangles(low) for high,low in pairs.values())
    if lod0_count > settings["rigidParts"]["maxLod0Triangles"]:
        raise ValueError("Rigid LOD0 exceeds explicit whole-asset triangle limit")
    return report_by_id,pairs,high_identities,preserve_names,lod0_count


def inspection_identity(obj, api):
    result = hashlib.sha256(api.mesh_identity(obj).encode('ascii'))
    result.update(np.asarray(obj.matrix_world,dtype=np.float64).tobytes())
    for layer in obj.data.uv_layers:
        data = np.empty(len(layer.data)*2,np.float32)
        layer.data.foreach_get('uv',data)
        result.update(memoryview(data))
    normals = np.empty(len(obj.data.corner_normals)*3,np.float32)
    obj.data.corner_normals.foreach_get('vector',normals)
    result.update(memoryview(normals))
    result.update(json.dumps([mat.name if mat else None for mat in obj.data.materials]).encode('utf-8'))
    return result.hexdigest()


def preflight(job_path, report_relative):
    """Pure actual-input inspection; never invokes finish, bakes, UV, LOD or export."""
    import finish as api
    job_path = Path(job_path).resolve(strict=True)
    job = strict_json(job_path,4_194_304,32)
    root = Path(job['root']).resolve(strict=True)
    job_path.relative_to(root)
    if bpy.app.version[:2]!=(4,5):
        raise ValueError('Blender4.5 LTS required')
    source = confined(root,relative_path(job['input'],'input'))
    inspect_glb(source)
    settings = validate_settings(job.get('finishingSettings'))
    # Existing recipe API deliberately accepts built-in JSON numeric types.
    # Keep its unchanged semantics after strict v2 token validation.
    recipe = json.loads(json.dumps(job['recipe'],allow_nan=False))
    api.validate_recipe(recipe)
    resolve_uv_atlas(settings, recipe)
    resolve_lod_settings(settings, recipe)
    report_relative = relative_path(report_relative,'preflight report')
    if not report_relative.startswith(relative_path(job.get('taskEvidenceRoot'),'taskEvidenceRoot')+'/'):
        raise ValueError('Preflight report must remain inside the active task')
    report_path = confined(root,report_relative)
    if report_path.exists() or report_path.with_suffix(report_path.suffix+'.tmp').exists():
        raise ValueError('Preflight evidence is immutable; use a fresh report')
    handoff,prepared,authoring,dependencies = read_inputs(job,root,source,settings)
    original_hash = digest(source)
    source_topology = _source_topology_bindings(root, settings, handoff, prepared)
    imported = import_glb(prepared)
    normal_import_initial=None
    if 'importNormals' in settings['rigidParts']:
        imported,normal_import_initial=_normal_decode_imported(prepared,imported,api,expected_sha256=handoff['preparedGlbSha256'],max_file_bytes=2147483647)
    before = {obj.name:inspection_identity(obj,api) for obj in imported}
    reports,pairs,identities,preserve,lod0 = inspect_pairs(handoff,authoring,imported,recipe,settings,api,source_topology)
    after = {obj.name:inspection_identity(obj,api) for obj in imported}
    if before!=after or digest(source)!=original_hash:
        raise ValueError('Read-only preflight changed source geometry, UV, normals or file bytes')
    for name,expected in dependencies.items():
        checked_file(root,name,expected)
    group_count = len({part['bakeGroup'] for part in handoff['parts'] if part['materialMode']=='bake'})
    minimum_materials = len(preserve)+group_count
    if minimum_materials>recipe['maxMaterials']:
        raise ValueError('Explicit bake/preserve material allocation exceeds recipe')
    payload = {'schemaVersion':1,'mode':'rigid-parts-preflight','status':'inspected','readOnly':True,
               'nativeFinish':False,'allHighLowPairsInspected':True,'partCount':len(pairs),
               'jobSha256':digest(job_path),'inputSha256':original_hash,
               'rigidHandoffSha256':settings['rigidParts']['handoffSha256'],
               'preparedInputSha256':handoff['preparedGlbSha256'],'authoringEvidenceSha256':handoff['authoringEvidenceSha256'],
               'measurements':{'lod0Triangles':lod0,'parts':[reports[part['id']] for part in handoff['parts']],
                               'minimumRuntimeMaterialAllocation':minimum_materials},
               'dependencyHashes':dependencies,'importedInspectionIdentitiesBefore':before,'importedInspectionIdentitiesAfter':after,
               'scriptHashes':{name:digest(Path(__file__).with_name(name)) for name in ('finish.py','rigid_finish.py','common.py','review.py','rigid_source_topology.py')},
               'humanApproval':'not-granted',
               'limits':'Actual read-only input inspection only. No source edit, UV authoring, bake, LOD/collision/export, native stage start or human approval. Runtime artifact and visual/motion acceptance remain unproven. Caller must enforce the selected native memory/time policy.'}
    if normal_import_initial is not None:
        payload.update({'readOnly':False,'readOnlyFiles':True,'normalImportInitial':normal_import_initial,
            'workingRepresentationConversion':True,
            'limits':'Actual immutable-file inspection with explicitly selected imported working normal conversion before the inspection baseline. No original source/master write, bake, LOD/collision/export, native stage start or human approval. Caller owns native resource enforcement.'})
    write_json(report_path,payload)
    return payload


# Statically embedded stored-normal accessor verification helpers.
_snv_RESIDUAL_LIMIT = 2e-05
_snv_POSITION_LIMIT = 1e-06
_snv_UV_LIMIT = 2e-06
_snv_MAX_FIELD_BYTES = 67108864
_snv_FORMAT_UNIT_EPSILON = 8 * float(np.finfo(np.float32).eps)
_snv_MAX_FRAME_CONDITION = 1000000.0
_snv_AXIS = np.asarray([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]], np.float64)
_snv_AXIS4 = np.eye(4)
_snv_AXIS4[:3, :3] = _snv_AXIS
_snv_CODEC = {'id': 'blender-4.5.10-static-round4-f32-normalize-then-yup/v1', 'primitiveExtractSha256': '0f4b21d34a640f8e2c88766f0a3dbed938d2cbfa6d555bbc8eb62ad2d9477de3', 'constantsSha256': 'be59f961a8f6d08068a7aaae4b91a72c5fadd832ca9b228276732b40f0f68a38', 'roundDigits': 4, 'floatArithmetic': 'float32', 'normalizationBeforeAxisConversion': True, 'axisConversion': 'BlenderXYZ-to-glTF-XZ-minusY', 'staticUnskinnedOnly': True}

class _snv_StoredNormalError(ValueError):
    pass

def _snv_checked_codec(descriptor):
    if descriptor != _snv_CODEC:
        raise _snv_StoredNormalError('Wrong or unpinned exporter normal codec')

def _snv_check_installed_codec(primitive_path, constants_path):
    for path, key in [(primitive_path, 'primitiveExtractSha256'), (constants_path, 'constantsSha256')]:
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != _snv_CODEC[key]:
            raise _snv_StoredNormalError('Installed exporter source pin differs')
    return dict(_snv_CODEC)

def _snv_finite_array(value, shape_tail, label, dtype=np.float32):
    array = np.asarray(value, dtype=dtype)
    if array.shape[-len(shape_tail):] != shape_tail or array.nbytes > _snv_MAX_FIELD_BYTES or (not np.isfinite(array).all()):
        raise _snv_StoredNormalError('Malformed/nonfinite/oversized ' + label)
    return array

def _snv_unit(array, label):
    magnitudes = np.linalg.norm(np.asarray(array, np.float64), axis=-1)
    if not np.isfinite(magnitudes).all() or np.any(magnitudes <= 0):
        raise _snv_StoredNormalError('Finite nonzero ' + label + ' required')
    return np.asarray(array, np.float64) / magnitudes[..., None]

def _snv_exporter_codec(local_normals, descriptor):
    _snv_checked_codec(descriptor)
    source = _snv_finite_array(local_normals, (3,), 'source local normals')
    if np.any(np.linalg.norm(source.astype(np.float64), axis=-1) <= 0):
        raise _snv_StoredNormalError('Zero source normal is outside this declared intent contract')
    try:
        with np.errstate(over='raise', invalid='raise', divide='raise'):
            rounded = np.round(source, 4)
            magnitudes = np.linalg.norm(rounded, axis=-1, keepdims=True)
    except FloatingPointError:
        raise _snv_StoredNormalError('Nonfinite float32 exporter codec intermediate') from None
    if not np.isfinite(rounded).all() or not np.isfinite(magnitudes).all():
        raise _snv_StoredNormalError('Nonfinite float32 exporter codec intermediate')
    if np.any(magnitudes == 0):
        raise _snv_StoredNormalError('Rounded-zero exporter fallback would lose source direction')
    encoded = rounded / magnitudes
    result = encoded[..., [0, 2, 1]].copy()
    result[..., 2] *= -1
    return result

def _snv_matrix(value, label):
    matrix = np.asarray(value, np.float64)
    if matrix.shape != (4, 4) or not np.isfinite(matrix).all() or (not np.array_equal(matrix[3], [0, 0, 0, 1])):
        raise _snv_StoredNormalError('Malformed/nonaffine ' + label)
    determinant = float(np.linalg.det(matrix[:3, :3]))
    condition = float(np.linalg.cond(matrix[:3, :3]))
    if not math.isfinite(determinant) or determinant <= 1e-12 or (not math.isfinite(condition)) or (condition > _snv_MAX_FRAME_CONDITION):
        raise _snv_StoredNormalError('Unsupported singular/reflected/ill-conditioned ' + label)
    return matrix

def _snv_digest_snapshot(snapshot):
    digest = hashlib.sha256()
    metadata = {key: snapshot[key] for key in ('name', 'parent', 'world', 'materials', 'codec')}
    digest.update(json.dumps(metadata, sort_keys=True, separators=(',', ':'), allow_nan=False).encode())
    for key in ('localPositions', 'localNormals', 'uvs'):
        array = np.asarray(snapshot[key], np.float32)
        digest.update(key.encode())
        digest.update(str(array.shape).encode())
        digest.update(array.tobytes())
    return digest.hexdigest()

def _snv_snapshot_from_triangles(name, parent, world, positions, normals, uvs, materials, descriptor):
    _snv_checked_codec(descriptor)
    if not isinstance(name, str) or not name or (parent is not None and (not isinstance(parent, str) or not parent)):
        raise _snv_StoredNormalError('Explicit unique source node identity required')
    positions = _snv_finite_array(positions, (3, 3), 'source triangle positions').copy()
    normals = _snv_finite_array(normals, (3, 3), 'source triangle normals').copy()
    uvs = np.asarray(uvs, np.float32)
    if positions.ndim != 3 or normals.shape != positions.shape or len(positions) == 0 or (uvs.ndim != 4) or (uvs.shape[0] != len(positions)) or (uvs.shape[2:] != (3, 2)) or (uvs.nbytes > _snv_MAX_FIELD_BYTES) or (not np.isfinite(uvs).all()):
        raise _snv_StoredNormalError('Invalid source triangle/UV ancestry')
    if len(materials) != len(positions) or any((item is not None and (not isinstance(item, str) or not item) for item in materials)):
        raise _snv_StoredNormalError('Invalid source material ownership')
    world = _snv_matrix(world, 'source node world')
    _snv_exporter_codec(normals, descriptor)
    snapshot = {'name': name, 'parent': parent, 'world': world.tolist(), 'materials': list(materials), 'codec': dict(descriptor), 'localPositions': positions, 'localNormals': normals, 'uvs': uvs.copy()}
    snapshot['sha256'] = _snv_digest_snapshot(snapshot)
    return snapshot

def _snv_capture_source_object(obj, descriptor):
    """Read exact native LOCAL source vectors before export; never output-derived."""
    mesh = obj.data
    if obj.type != 'MESH' or obj.modifiers or obj.constraints or (obj.animation_data is not None) or mesh.shape_keys:
        raise _snv_StoredNormalError('Applied static unskinned source mesh required')
    mesh.calc_loop_triangles()
    positions = []
    normals = []
    uvs = []
    materials = []
    for triangle in mesh.loop_triangles:
        positions.append([tuple(mesh.vertices[vi].co) for vi in triangle.vertices])
        normals.append([tuple(mesh.corner_normals[li].vector) for li in triangle.loops])
        uvs.append([[tuple(layer.data[li].uv) for li in triangle.loops] for layer in mesh.uv_layers])
        mi = mesh.polygons[triangle.polygon_index].material_index
        mat = mesh.materials[mi] if mesh.materials else None
        materials.append(mat.name if mat else None)
    uv_array = np.asarray(uvs, np.float32).reshape((len(positions), len(mesh.uv_layers), 3, 2))
    return _snv_snapshot_from_triangles(obj.name, obj.parent.name if obj.parent else None, [list(row) for row in obj.matrix_world], positions, normals, uv_array, materials, descriptor)

def _snv_context_from_sources(snapshots, node_frames):
    """node_frames is independently captured export node intent incl ancestors."""
    names = [snapshot['name'] for snapshot in snapshots]
    if len(set(names)) != len(names) or not names:
        raise _snv_StoredNormalError('Ambiguous source mesh names')
    nodes = {}
    for name, record in node_frames.items():
        if not isinstance(name, str) or not name or set(record) != {'parent', 'world'}:
            raise _snv_StoredNormalError('Invalid declared node frame')
        nodes[name] = {'parent': record['parent'], 'world': _snv_matrix(record['world'], 'declared node world').tolist()}
    for snapshot in snapshots:
        _snv_checked_codec(snapshot['codec'])
        if snapshot.get('sha256') != _snv_digest_snapshot(snapshot) or snapshot['name'] not in nodes:
            raise _snv_StoredNormalError('Stale source snapshot')
        if nodes[snapshot['name']] != {'parent': snapshot['parent'], 'world': snapshot['world']}:
            raise _snv_StoredNormalError('Source frame differs from declared node frame')
    for name, record in nodes.items():
        if record['parent'] is not None and record['parent'] not in nodes:
            raise _snv_StoredNormalError('Declared parent frame is missing')
    context = {'codec': dict(_snv_CODEC), 'sources': {snapshot['name']: snapshot for snapshot in snapshots}, 'nodes': nodes}
    context['sha256'] = _snv_digest_context(context)
    return context

def _snv_digest_context(context):
    data = {'codec': context['codec'], 'nodes': context['nodes'], 'sourceSnapshots': {name: source['sha256'] for name, source in context['sources'].items()}}
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()

def _snv_capture_source_context(objects, descriptor):
    snapshots = [_snv_capture_source_object(obj, descriptor) for obj in objects]
    frames = {}
    for obj in objects:
        cursor = obj
        while cursor is not None:
            record = {'parent': cursor.parent.name if cursor.parent else None, 'world': [list(row) for row in cursor.matrix_world]}
            if cursor.name in frames and frames[cursor.name] != record:
                raise _snv_StoredNormalError('Ambiguous source ancestor name')
            frames[cursor.name] = record
            cursor = cursor.parent
    return _snv_context_from_sources(snapshots, frames)

def _snv_integer(value, label, minimum=0, maximum=None):
    if type(value) is not int or value < minimum or (maximum is not None and value > maximum):
        raise _snv_StoredNormalError('Invalid integer ' + label)
    return value

def _snv_unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise _snv_StoredNormalError('Duplicate JSON field')
        result[key] = value
    return result

def _snv_json_vector(value, size, label):
    if type(value) is not list or len(value) != size or any((type(item) not in (int, float) or not math.isfinite(item) for item in value)):
        raise _snv_StoredNormalError('Malformed numeric ' + label)
    return np.asarray(value, np.float64)

class _snv_Glb:
    """Narrow bounded reader for embedded uncompressed static FLOAT attributes."""

    def __init__(self, path, max_file_bytes):
        maximum = _snv_integer(max_file_bytes, 'explicit GLB byte bound', 20, 2147483647)
        path = Path(path)
        if path.stat().st_size > maximum:
            raise _snv_StoredNormalError('GLB exceeds explicit input byte bound')
        raw = path.read_bytes()
        if len(raw) > maximum:
            raise _snv_StoredNormalError('GLB exceeds byte bound after read')
        if len(raw) < 28 or struct.unpack_from('<4sII', raw) != (b'glTF', 2, len(raw)):
            raise _snv_StoredNormalError('Invalid GLB header')
        chunks = []
        offset = 12
        while offset < len(raw):
            if offset % 4 or offset + 8 > len(raw):
                raise _snv_StoredNormalError('Malformed GLB chunk boundary')
            size, kind = struct.unpack_from('<II', raw, offset)
            if size % 4 or offset + 8 + size > len(raw):
                raise _snv_StoredNormalError('Malformed GLB chunk range')
            chunks.append((kind, memoryview(raw)[offset + 8:offset + 8 + size]))
            offset += 8 + size
        if [kind for kind, data in chunks] != [1313821514, 5130562]:
            raise _snv_StoredNormalError('Exactly JSON/BIN chunks required')
        self.document = json.loads(bytes(chunks[0][1]), object_pairs_hook=_snv_unique_object)
        self.binary = chunks[1][1]
        self.raw = raw
        self.cache = {}
        doc = self.document
        if doc.get('asset', {}).get('version') != '2.0' or len(doc.get('buffers', [])) != 1 or 'uri' in doc['buffers'][0]:
            raise _snv_StoredNormalError('One embedded glTF2 buffer required')
        self.declared = _snv_integer(doc['buffers'][0].get('byteLength'), 'buffer length', 1)
        if not self.declared <= len(self.binary) <= self.declared + 3:
            raise _snv_StoredNormalError('Embedded BIN length differs')
        if doc.get('skins') or doc.get('animations'):
            raise _snv_StoredNormalError('Skin/motion normal transforms unsupported')
        if doc.get('extensionsRequired'):
            raise _snv_StoredNormalError('Required extensions unsupported by this static normal contract')
        for view in doc.get('bufferViews', []):
            if _snv_integer(view.get('buffer', 0), 'view buffer') != 0 or view.get('extensions'):
                raise _snv_StoredNormalError('Unsupported compressed/external buffer view')
            start = _snv_integer(view.get('byteOffset', 0), 'view offset')
            size = _snv_integer(view.get('byteLength'), 'view length', 1)
            if start + size > self.declared:
                raise _snv_StoredNormalError('Buffer view exceeds declared buffer')
        for image in doc.get('images', []):
            if 'uri' in image:
                raise _snv_StoredNormalError('External image URI unsupported')
        self.worlds, self.parents = self._node_worlds()

    def accessor(self, index, kind, width):
        index = _snv_integer(index, 'accessor index', 0, len(self.document.get('accessors', [])) - 1)
        key = (index, kind, width)
        if key in self.cache:
            return self.cache[key]
        a = self.document['accessors'][index]
        if a.get('sparse') or a.get('normalized', False) or a.get('extensions') or ('normalized' in a and type(a['normalized']) is not bool):
            raise _snv_StoredNormalError('Sparse/normalized/compressed accessor unsupported')
        allowed = {'float': {5126: np.dtype('<f4')}, 'index': {5121: np.dtype('u1'), 5123: np.dtype('<u2'), 5125: np.dtype('<u4')}}[kind]
        component = _snv_integer(a.get('componentType'), 'accessor component type')
        if component not in allowed or a.get('type') != {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3'}[width]:
            raise _snv_StoredNormalError('Accessor type does not match declared semantic')
        dtype = allowed[component]
        count = _snv_integer(a.get('count'), 'accessor count', 1)
        if count * width * dtype.itemsize > _snv_MAX_FIELD_BYTES:
            raise _snv_StoredNormalError('Accessor field exceeds64MiB')
        vi = _snv_integer(a.get('bufferView'), 'accessor view', 0, len(self.document.get('bufferViews', [])) - 1)
        view = self.document['bufferViews'][vi]
        if kind == 'index' and 'byteStride' in view:
            raise _snv_StoredNormalError('Strided index accessor unsupported')
        off = _snv_integer(a.get('byteOffset', 0), 'accessor offset')
        stride = _snv_integer(view.get('byteStride', width * dtype.itemsize), 'accessor stride', width * dtype.itemsize, 252)
        absolute = view.get('byteOffset', 0) + off
        if off % dtype.itemsize or absolute % dtype.itemsize or stride % dtype.itemsize or (off + (count - 1) * stride + width * dtype.itemsize > view['byteLength']):
            raise _snv_StoredNormalError('Accessor alignment/range malformed')
        array = np.ndarray((count, width), dtype, buffer=self.binary, offset=absolute, strides=(stride, dtype.itemsize))
        if not np.isfinite(array).all():
            raise _snv_StoredNormalError('Accessor contains nonfinite values')
        for label, fn in [('min', np.min), ('max', np.max)]:
            if label in a and (not np.array_equal(np.asarray(a[label]), fn(array, axis=0))):
                raise _snv_StoredNormalError('Stale accessor extrema')
        self.cache[key] = array
        return array

    def _node_worlds(self):
        doc = self.document
        nodes = doc.get('nodes', [])
        if not nodes or len(nodes) > 100000 or len(doc.get('scenes', [])) != 1 or (_snv_integer(doc.get('scene', 0), 'scene index') != 0):
            raise _snv_StoredNormalError('One explicit static scene required')
        parents = {}
        names = set()
        locals_ = []
        for i, node in enumerate(nodes):
            name = node.get('name')
            if not isinstance(name, str) or not name or name in names or (node.get('skin') is not None) or node.get('weights') or node.get('extensions'):
                raise _snv_StoredNormalError('Ambiguous/unsupported node identity or transform path')
            names.add(name)
            if 'matrix' in node:
                if any((field in node for field in ('translation', 'rotation', 'scale'))) or len(node['matrix']) != 16:
                    raise _snv_StoredNormalError('Mixed/malformed node matrix and TRS')
                local = _snv_json_vector(node['matrix'], 16, 'node matrix').reshape((4, 4)).T
            else:
                t = _snv_json_vector(node.get('translation', [0, 0, 0]), 3, 'node translation')
                s = _snv_json_vector(node.get('scale', [1, 1, 1]), 3, 'node scale')
                q = _snv_json_vector(node.get('rotation', [0, 0, 0, 1]), 4, 'node rotation')
                if t.shape != (3,) or s.shape != (3,) or q.shape != (4,) or (not np.isfinite(np.concatenate([t, s, q])).all()) or (abs(float(np.linalg.norm(q)) - 1) > _snv_FORMAT_UNIT_EPSILON):
                    raise _snv_StoredNormalError('Malformed/nonunit node TRS')
                x, y, z, w = q
                rotation = np.asarray([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
                local = np.eye(4)
                local[:3, :3] = rotation @ np.diag(s)
                local[:3, 3] = t
            locals_.append(_snv_matrix(local, 'GLB node local'))
            children = node.get('children', [])
            if len(set(children)) != len(children):
                raise _snv_StoredNormalError('Repeated node child')
            for child in children:
                child = _snv_integer(child, 'node child', 0, len(nodes) - 1)
                if child in parents:
                    raise _snv_StoredNormalError('Ambiguous multiple node paths')
                parents[child] = i
        roots = doc['scenes'][0].get('nodes', [])
        if len(set(roots)) != len(roots) or any((_snv_integer(root, 'scene root', 0, len(nodes) - 1) in parents for root in roots)):
            raise _snv_StoredNormalError('Invalid scene roots')
        worlds = {}
        stack = [(root, np.eye(4), 0) for root in reversed(roots)]
        while stack:
            index, parent_world, depth = stack.pop()
            if index in worlds or depth > 128:
                raise _snv_StoredNormalError('Cyclic/deep/ambiguous node graph')
            worlds[index] = _snv_matrix(parent_world @ locals_[index], 'GLB node world')
            stack.extend(((child, worlds[index], depth + 1) for child in reversed(nodes[index].get('children', []))))
        if len(worlds) != len(nodes):
            raise _snv_StoredNormalError('Unreachable/stale node graph')
        return (worlds, parents)

def _snv_canonical(positions, uvs, material):
    p = np.asarray(positions, np.float64)
    if float(np.linalg.norm(np.cross(p[1] - p[0], p[2] - p[0]))) <= 0:
        raise _snv_StoredNormalError('Degenerate source/stored triangle cannot establish corner ancestry')
    corners = [tuple(positions[i].tolist()) + tuple(uvs[:, i, :].reshape(-1).tolist()) for i in range(3)]
    first = min(range(3), key=lambda i: corners[i])
    order = [first, (first + 1) % 3, (first + 2) % 3]
    return ((tuple((corners[i] for i in order)), material), order)

def _snv_verify_stored_normal_intent(context, path, descriptor, *, max_file_bytes):
    _snv_checked_codec(descriptor)
    if context.get('codec') != descriptor:
        raise _snv_StoredNormalError('Stale/wrong context codec')
    if context.get('sha256') != _snv_digest_context(context):
        raise _snv_StoredNormalError('Stale source/node context')
    for snapshot in context['sources'].values():
        if snapshot.get('sha256') != _snv_digest_snapshot(snapshot):
            raise _snv_StoredNormalError('Stale source snapshot')
    glb = _snv_Glb(path, max_file_bytes)
    doc = glb.document
    actual_names = {node['name']: i for i, node in enumerate(doc['nodes'])}
    if set(actual_names) != set(context['nodes']):
        raise _snv_StoredNormalError('Extra/missing declared node frame')
    for name, expected in context['nodes'].items():
        i = actual_names[name]
        p = glb.parents.get(i)
        actual_parent = doc['nodes'][p]['name'] if p is not None else None
        expected_world = _snv_AXIS4 @ _snv_matrix(expected['world'], 'expected source world') @ _snv_AXIS4.T
        if actual_parent != expected['parent'] or np.max(np.abs(glb.worlds[i] - expected_world)) > _snv_POSITION_LIMIT:
            raise _snv_StoredNormalError('Stored node ownership/world frame differs from source intent')
    mesh_nodes = {node['name']: i for i, node in enumerate(doc['nodes']) if 'mesh' in node}
    if set(mesh_nodes) != set(context['sources']):
        raise _snv_StoredNormalError('Extra/missing mesh node')
    material_names = [mat.get('name') for mat in doc.get('materials', [])]
    if any((not isinstance(name, str) or not name for name in material_names)) or len(set(material_names)) != len(material_names):
        raise _snv_StoredNormalError('Ambiguous material identities')
    reports = []
    used_meshes = set()
    for name, index in mesh_nodes.items():
        source = context['sources'][name]
        positions = source['localPositions'][:, :, [0, 2, 1]].copy()
        positions[:, :, 2] *= -1
        uvs = source['uvs'].copy()
        uvs[:, :, :, 1] *= -1
        uvs[:, :, :, 1] += np.float32(1)
        predicted = _snv_exporter_codec(source['localNormals'], descriptor)
        records = {}
        for fi in range(len(positions)):
            key, order = _snv_canonical(positions[fi], uvs[fi], source['materials'][fi])
            if key in records:
                raise _snv_StoredNormalError('Ambiguous source oriented triangle/material/UV key')
            records[key] = (fi, order)
        mi = _snv_integer(doc['nodes'][index]['mesh'], 'mesh index', 0, len(doc.get('meshes', [])) - 1)
        used_meshes.add(mi)
        mesh = doc['meshes'][mi]
        if mesh.get('weights') or mesh.get('extensions'):
            raise _snv_StoredNormalError('Morph/compressed mesh unsupported')
        seen = set()
        max_local = max_world = max_local_l2 = max_world_l2 = max_unit = loss_local = loss_world = actual_loss_local = actual_loss_world = 0.0
        corners = exact = exact_values = 0
        measured_local_losses = []
        measured_world_losses = []
        source_matrix = np.asarray(source['world'], np.float64)
        expected_normal_matrix = np.linalg.inv(source_matrix[:3, :3])
        actual_normal_matrix = np.linalg.inv(glb.worlds[index][:3, :3])
        for primitive in mesh.get('primitives', []):
            if _snv_integer(primitive.get('mode', 4), 'primitive mode') != 4 or primitive.get('targets') or primitive.get('extensions'):
                raise _snv_StoredNormalError('Nontriangle/morph/compressed primitive unsupported')
            attrs = primitive.get('attributes', {})
            required = {'POSITION', 'NORMAL'} | {'TEXCOORD_' + str(i) for i in range(source['uvs'].shape[1])}
            if set(attrs) != required:
                raise _snv_StoredNormalError('Missing NORMAL/UV or unsupported extra primitive attributes')
            pos = glb.accessor(attrs['POSITION'], 'float', 3)
            normal = glb.accessor(attrs['NORMAL'], 'float', 3)
            uv_arrays = [glb.accessor(attrs['TEXCOORD_' + str(i)], 'float', 2) for i in range(source['uvs'].shape[1])]
            if normal.shape != pos.shape or any((len(uv) != len(pos) for uv in uv_arrays)):
                raise _snv_StoredNormalError('Attribute counts differ')
            unit_error = np.abs(np.linalg.norm(normal.astype(np.float64), axis=1) - 1)
            if np.any(unit_error > _snv_FORMAT_UNIT_EPSILON):
                raise _snv_StoredNormalError('Stored NORMAL is not finite unit float32 data')
            max_unit = max(max_unit, float(unit_error.max()))
            indices = glb.accessor(primitive.get('indices'), 'index', 1).reshape(-1)
            if len(indices) % 3 or np.any(indices >= len(pos)):
                raise _snv_StoredNormalError('Malformed triangle indices')
            material = material_names[_snv_integer(primitive['material'], 'material index', 0, len(material_names) - 1)] if 'material' in primitive else None
            for tri in indices.reshape((-1, 3)):
                if len(set(map(int, tri))) != 3:
                    raise _snv_StoredNormalError('Repeated triangle index')
                uv = np.asarray([layer[tri] for layer in uv_arrays], np.float32).reshape((len(uv_arrays), 3, 2))
                key, actual_order = _snv_canonical(pos[tri], uv, material)
                if key not in records or key in seen:
                    raise _snv_StoredNormalError('Extra/unmatched/ambiguous stored triangle')
                seen.add(key)
                fi, expected_order = records[key]
                actual = normal[tri][actual_order]
                wanted = predicted[fi][expected_order]
                max_local = max(max_local, float(np.max(np.abs(actual.astype(np.float64) - wanted.astype(np.float64)))))
                max_local_l2 = max(max_local_l2, float(np.linalg.norm(actual.astype(np.float64) - wanted.astype(np.float64), axis=1).max()))
                source_local = _snv_unit(source['localNormals'][fi][expected_order], 'source normal')
                predicted_blender = wanted.astype(np.float64) @ _snv_AXIS
                actual_blender = actual.astype(np.float64) @ _snv_AXIS
                source_world = _snv_unit(source_local @ expected_normal_matrix, 'source world normal') @ _snv_AXIS.T
                predicted_world = _snv_unit(predicted_blender @ expected_normal_matrix, 'codec world normal') @ _snv_AXIS.T
                actual_world = _snv_unit(actual.astype(np.float64) @ actual_normal_matrix, 'stored world normal')
                max_world = max(max_world, float(np.max(np.abs(actual_world - predicted_world))))
                max_world_l2 = max(max_world_l2, float(np.linalg.norm(actual_world - predicted_world, axis=1).max()))
                loss_local = max(loss_local, float(np.linalg.norm(_snv_unit(predicted_blender, 'codec local') - source_local, axis=1).max()))
                loss_world = max(loss_world, float(np.linalg.norm(predicted_world - source_world, axis=1).max()))
                local_losses = np.linalg.norm(_snv_unit(actual_blender, 'stored local') - source_local, axis=1)
                world_losses = np.linalg.norm(actual_world - source_world, axis=1)
                actual_loss_local = max(actual_loss_local, float(local_losses.max()))
                actual_loss_world = max(actual_loss_world, float(world_losses.max()))
                measured_local_losses.extend(map(float, local_losses))
                measured_world_losses.extend(map(float, world_losses))
                corners += 3
                exact += int(np.count_nonzero(np.all(actual.view(np.uint32) == wanted.view(np.uint32), axis=1)))
                exact_values += int(np.count_nonzero(np.all(actual == wanted, axis=1)))
        if len(seen) != len(records):
            raise _snv_StoredNormalError('Missing source triangles')
        if max_local > _snv_RESIDUAL_LIMIT or max_world > _snv_RESIDUAL_LIMIT:
            raise _snv_StoredNormalError('Stored NORMAL differs from declared forward codec intent')
        reports.append({'node': name, 'corners': corners, 'bitExactCodecCorners': exact, 'exactFloat32ValueCodecCorners': exact_values, 'signedZeroOnlyBitDifferenceCorners': exact_values - exact, 'maximumLocalCodecComponentResidual': max_local, 'maximumWorldCodecComponentResidual': max_world, 'maximumLocalCodecVectorResidual': max_local_l2, 'maximumWorldCodecVectorResidual': max_world_l2, 'maximumStoredUnitLengthError': max_unit, 'sourceToCodecLocalDirectionalError': loss_local, 'sourceToCodecWorldDirectionalError': loss_world, 'sourceToStoredLocalDirectionalError': actual_loss_local, 'sourceToStoredWorldDirectionalError': actual_loss_world, 'sourceSnapshotSha256': source['sha256']})
        reports[-1]['directionalLossCoverage'] = {'allActualIndexedCornersMeasured': True, 'corners': len(measured_local_losses), 'localL2ErrorsFloat64Sha256': hashlib.sha256(np.asarray(measured_local_losses, dtype='<f8').tobytes()).hexdigest(), 'worldL2ErrorsFloat64Sha256': hashlib.sha256(np.asarray(measured_world_losses, dtype='<f8').tobytes()).hexdigest()}
    if used_meshes != set(range(len(doc.get('meshes', [])))):
        raise _snv_StoredNormalError('Unreferenced/stale extra mesh')
    if {key[0] for key in glb.cache} != set(range(len(doc.get('accessors', [])))):
        raise _snv_StoredNormalError('Unreferenced/stale extra accessor')
    return {'status': 'DECLARED_STORED_CODEC_INTENT_PASS', 'referenceIsNewExplicitContractProposal': True, 'oldNativeGuardEvaluatedByThisCheck': False, 'losslessClaim': False, 'runtimeQualityAccepted': False, 'codec': dict(descriptor), 'residualLimit': _snv_RESIDUAL_LIMIT, 'formatUnitLengthEpsilon': _snv_FORMAT_UNIT_EPSILON, 'maximumSupportedFrameCondition': _snv_MAX_FRAME_CONDITION, 'numpyVersion': np.__version__, 'sourceContextSha256': context['sha256'], 'glbSha256': hashlib.sha256(glb.raw).hexdigest(), 'meshes': reports}

def _snv_verify_native_geometry_uv_materials(expected, obj):
    """Existing oriented native geometry/UV/material checks; normals separate."""
    actual = corner_snapshot(obj)
    if expected['positions'].shape != actual['positions'].shape or expected['uv'].shape != actual['uv'].shape or expected['materials'] != actual['materials']:
        raise _snv_StoredNormalError('Native reimport lost triangle/material correspondence')
    position = float(np.max(np.abs(expected['positions'] - actual['positions'])))
    uv = float(np.max(np.abs(expected['uv'] - actual['uv'])))
    if position > _snv_POSITION_LIMIT or uv > _snv_UV_LIMIT:
        raise _snv_StoredNormalError('Native reimport changed geometry/UV correspondence')
    normal = float(np.max(np.abs(expected['normals'] - actual['normals'])))
    return {'geometryUvMaterialsPassed': True, 'maxPositionDifferenceMetres': position, 'maxUvDifference': uv, 'dccReencodedNormalComponentDifference': normal, 'oldStrictNormalLimit': _snv_RESIDUAL_LIMIT, 'oldStrictNormalPassed': normal <= _snv_RESIDUAL_LIMIT, 'nativeNormalLosslessClaim': False}

_snv_CONTRACT_ID = 'opencaw-rigid-static-normals/v1'
_snv_EXPORT_OPTIONS = {'export_format':'GLB','use_selection':True,'export_extras':True,
    'export_yup':True,'export_materials':'EXPORT','export_texcoords':True,'export_normals':True,
    'export_tangents':False,'export_attributes':False,'export_apply':False,
    'export_animations':False,'export_skins':False,'export_morph':False}


def _snv_export_static_intent(path, objects, api, max_file_bytes):
    """Export static data once; verify the versioned stored-normal contract.

    Sources and world frames are captured before export. The original strict
    verify_corners remains available; native DCC approximation is separate.
    """
    path=Path(path)
    if path.exists():
        raise _snv_StoredNormalError('Stored-intent export requires a fresh output path')
    if not objects or len({obj.name for obj in objects})!=len(objects):
        raise _snv_StoredNormalError('Unique explicit static export meshes required')
    addon=Path(bpy.app.binary_path).resolve().parent/(''+str(bpy.app.version[0])+'.'+str(bpy.app.version[1]))/'scripts'/'addons_core'/'io_scene_gltf2'
    codec=_snv_check_installed_codec(addon/'blender'/'exp'/'primitive_extract.py',addon/'io'/'com'/'constants.py')
    for obj in objects:
        if obj.type!='MESH' or obj.data.color_attributes:
            raise _snv_StoredNormalError('Unsupported nonmesh or COLOR source data; no color transport is claimed')
        if obj.data.uv_layers and obj.data.uv_layers.active is None:
            raise _snv_StoredNormalError('UV layers require an explicit active source layer')
        cursor=obj
        while cursor is not None:
            if cursor.type not in {'MESH','EMPTY'} or cursor.constraints or cursor.animation_data is not None:
                raise _snv_StoredNormalError('Only static mesh/empty source ancestors are supported')
            cursor=cursor.parent
    before=[_preservation_runtime_state(obj,api) for obj in objects]
    source_context=_snv_capture_source_context(objects,codec)
    try:
        status=bpy.ops.export_scene.gltf(filepath=str(path),**_snv_EXPORT_OPTIONS)
        if status!={'FINISHED'}:
            raise _snv_StoredNormalError('Static GLB export did not finish: '+repr(status))
        for obj,state in zip(objects,before):
            _verify_runtime_preservation(state,obj,api,'Static GLB export source',exact_world=True)
        after_context=_snv_capture_source_context(objects,codec)
        if source_context['sha256']!=after_context['sha256']:
            raise _snv_StoredNormalError('Export changed source-local/frame intent')
        result=_snv_verify_stored_normal_intent(source_context,path,codec,max_file_bytes=max_file_bytes)
        result.update({'referenceIsNewExplicitContractProposal':False,
            'normalVerificationContract':_snv_CONTRACT_ID,
            'sourceContextUnchangedByExport':True,'workingRawDecodedWorldGuardsUnchanged':True,
            'exportOptions':dict(_snv_EXPORT_OPTIONS),
            'dccNormalApproximationReportedSeparately':True,
            'geometricNormalQualityMeasured':False,'geometricQualityAccepted':False,
            'runtimeQualityAccepted':False})
        return result
    except BaseException:
        if path.is_file():
            path.unlink()
        raise



# Statically embedded selected stored-corner-fan decoder.
"""STAGED bounded stored-vector fan adapter; no I/O, export or source mutation.

Only tiny donor setters are allowed. Actual candidate fields change solely in
declared sharp edges and complete affected raw-normal corner fans. The proposed
2e-4 restored-vector precision contract is a study parameter, not admission.
"""
_nfa_TYPES = {'FLOAT': ('value', np.float32, 1), 'INT': ('value', np.int32, 1), 'BOOLEAN': ('value', np.bool_, 1), 'FLOAT_VECTOR': ('vector', np.float32, 3), 'FLOAT2': ('vector', np.float32, 2), 'INT32_2D': ('value', np.int32, 2), 'INT16_2D': ('value', np.int16, 2), 'FLOAT_COLOR': ('color', np.float32, 4), 'BYTE_COLOR': ('color', np.float32, 4), 'QUATERNION': ('value', np.float32, 4)}
_nfa_LIMIT = 67108864

class _nfa_AdapterError(RuntimeError):

    def __init__(self, message, evidence=None):
        super().__init__(message)
        self.evidence = evidence

def _nfa_field(data, prop, dtype, width):
    if len(data) * width * np.dtype(dtype).itemsize > _nfa_LIMIT:
        raise _nfa_AdapterError('Field exceeds64MiB before allocation')
    values = np.empty(len(data) * width, dtype)
    data.foreach_get(prop, values)
    if np.issubdtype(dtype, np.floating) and (not np.isfinite(values).all()):
        raise _nfa_AdapterError('Nonfinite native field')
    return values.reshape((-1, width))

def _nfa_normal(mesh):
    return _nfa_field(mesh.corner_normals, 'vector', np.float32, 3)

def _nfa_codes(mesh):
    return _nfa_field(mesh.attributes['custom_normal'].data, 'value', np.int16, 2)

def _nfa_probe_codes(mesh, codes):
    if (not isinstance(codes, np.ndarray) or codes.dtype != np.int16
            or codes.shape != (len(mesh.loops), 2) or not codes.flags.c_contiguous
            or codes.nbytes > _nfa_LIMIT):
        raise _nfa_AdapterError('Bounded contiguous native short2 probe codes required')
    mesh.attributes['custom_normal'].data.foreach_set('value', codes.ravel())
    # Raw attribute writes do not invalidate Blender's decoded-normal cache.
    mesh.update()
    if not np.array_equal(_nfa_codes(mesh), codes):
        raise _nfa_AdapterError('Probe workspace raw-code readback differs')
    scratch = mesh.copy()
    try:
        if not np.array_equal(_nfa_codes(scratch), codes):
            raise _nfa_AdapterError('Probe fresh-copy raw-code readback differs')
        try:
            return _nfa_normal(scratch)
        except _nfa_AdapterError:
            return None
    finally:
        bpy.data.meshes.remove(scratch)

def _nfa_digest(array):
    return hashlib.sha256(array.tobytes()).hexdigest()

def _nfa_cancel(check, stage):
    if check is not None:
        check(stage)

def _nfa_guard(obj):
    mesh = obj.data
    attrs = {}
    for attr in mesh.attributes:
        if attr.data_type not in _nfa_TYPES or attr.domain not in ('POINT', 'EDGE', 'FACE', 'CORNER'):
            raise _nfa_AdapterError('Unsupported attribute/domain before copy')
        prop, dtype, width = _nfa_TYPES[attr.data_type]
        attrs[attr.name] = {'domain': attr.domain, 'type': attr.data_type, 'sha256': _nfa_digest(_nfa_field(attr.data, prop, dtype, width))}
    return {'object': obj.name, 'mesh': mesh.name, 'world': [list(r) for r in obj.matrix_world], 'parent': obj.parent.as_pointer() if obj.parent else None, 'basis': [list(r) for r in obj.matrix_basis], 'parentInverse': [list(r) for r in obj.matrix_parent_inverse], 'coords': _nfa_digest(_nfa_field(mesh.vertices, 'co', np.float32, 3)), 'edges': _nfa_digest(_nfa_field(mesh.edges, 'vertices', np.int32, 2)), 'loopVertices': _nfa_digest(_nfa_field(mesh.loops, 'vertex_index', np.int32, 1)), 'loopEdges': _nfa_digest(_nfa_field(mesh.loops, 'edge_index', np.int32, 1)), 'starts': _nfa_digest(_nfa_field(mesh.polygons, 'loop_start', np.int32, 1)), 'totals': _nfa_digest(_nfa_field(mesh.polygons, 'loop_total', np.int32, 1)), 'materials': _nfa_digest(_nfa_field(mesh.polygons, 'material_index', np.int32, 1)), 'smooth': _nfa_digest(_nfa_field(mesh.polygons, 'use_smooth', np.bool_, 1)), 'seams': _nfa_digest(_nfa_field(mesh.edges, 'use_seam', np.bool_, 1)), 'uv': [[u.name, u.active_render, u.active_clone, _nfa_digest(_nfa_field(u.data, 'uv', np.float32, 2))] for u in mesh.uv_layers], 'activeUv': mesh.uv_layers.active_index, 'slots': [[m.name, m.as_pointer()] if m else None for m in mesh.materials], 'attrs': attrs, 'decoded': _nfa_digest(_nfa_normal(mesh))}

def _nfa_dispose(obj):
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if not mesh.users:
        bpy.data.meshes.remove(mesh)

def _nfa_fresh(obj):
    old = obj.data
    obj.data = old.copy()
    if not old.users:
        bpy.data.meshes.remove(old)

def _nfa_unit(values):
    length = np.linalg.norm(values.astype(np.float64), axis=1)
    if not np.isfinite(values).all() or np.any(length <= 0):
        raise _nfa_AdapterError('Finite nonzero native vectors required')
    return values.astype(np.float64) / length[:, None]

def _nfa_verify_unchanged(before, after):
    for key in before:
        if key in ('object', 'mesh', 'decoded', 'attrs'):
            continue
        if before[key] != after[key]:
            raise _nfa_AdapterError('Protected working field changed: ' + key)
    expected = {k: v for k, v in before['attrs'].items() if k not in ('custom_normal', 'sharp_edge')}
    actual = {k: v for k, v in after['attrs'].items() if k not in ('custom_normal', 'sharp_edge')}
    if expected != actual:
        raise _nfa_AdapterError('Protected attribute changed')

def _nfa_validate_binding(source, binding, input_sha):
    if binding.get('kind') == 'whole-input-sparse-stored-fan-binding':
        content = {k: v for k, v in binding.items() if k != 'sha256'}
        if binding['sourceInputSha256'] != input_sha or hashlib.sha256(json.dumps(content, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest() != binding['sha256']:
            raise _nfa_AdapterError('Stale sparse input binding')
        if _nfa_guard(source) != binding['sourceGuard']:
            raise _nfa_AdapterError('Whole source differs from captured raw import identity')
        if source.name != binding['sourceObject'] or [list(r) for r in source.matrix_world] != binding['sourceWorld']:
            raise _nfa_AdapterError('Whole source object/frame binding differs')
        loops = np.asarray([l.vertex_index for l in source.data.loops], np.int32)
        expected = np.flatnonzero(np.isin(loops, np.asarray(binding['potentialAffectedVertices'], np.int32))).tolist()
        if binding['targetLoopIds'] != expected:
            raise _nfa_AdapterError('Incomplete whole changed-endpoint fan targets')
        stored = np.asarray(binding['storedScopeTargets'], np.float32)
        if stored.shape != (len(expected), 3) or not np.isfinite(stored).all() or np.any(np.abs(np.linalg.norm(stored.astype(np.float64), axis=1) - 1) > _snv_FORMAT_UNIT_EPSILON):
            raise _nfa_AdapterError('Finite unit actual stored fan targets required')
        if len(binding['storedCornerBindings']) != len(expected):
            raise _nfa_AdapterError('Missing exact stored ancestry')
        keys = [(r['primitive'], r['triangle'], r['accessorVertex'], r['globalLoop']) for r in binding['storedCornerBindings']]
        if len(set(keys)) != len(keys):
            raise _nfa_AdapterError('Ambiguous sparse source corner ancestry')
        targets = _nfa_normal(source.data).copy()
        lengths = np.linalg.norm(targets.astype(np.float64), axis=1)
        valid = lengths > 0
        targets[valid] = (targets[valid].astype(np.float64) / lengths[valid, None]).astype(np.float32)
        targets[expected] = stored
        if not np.isfinite(targets).all() or np.any(np.linalg.norm(targets.astype(np.float64), axis=1) <= 0):
            raise _nfa_AdapterError('Sparse binding left an unbound native zero')
        return targets
    if binding['sourceInputSha256'] != input_sha:
        raise _nfa_AdapterError('Stale input binding')
    content = {k: v for k, v in binding.items() if k != 'sha256'}
    if hashlib.sha256(json.dumps(content, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest() != binding['sha256']:
        raise _nfa_AdapterError('Stale or tampered binding digest')
    if source.name != binding['sourceObject'] or [list(r) for r in source.matrix_world] != binding['sourceWorld']:
        raise _nfa_AdapterError('Object/frame differs from declared input binding')
    if not np.array_equal(_nfa_field(source.data.vertices, 'co', np.float32, 3).view(np.uint32), np.asarray(binding['coords'], np.float32).view(np.uint32)):
        raise _nfa_AdapterError('Bound positions differ')
    if [list(p.vertices) for p in source.data.polygons] != [p['vertices'] for p in binding['faces']]:
        raise _nfa_AdapterError('Bound oriented faces differ')
    if [p.material_index for p in source.data.polygons] != [p['material'] for p in binding['faces']]:
        raise _nfa_AdapterError('Bound material ownership differs')
    if [m.name for m in source.data.materials] != binding['materialSlots']:
        raise _nfa_AdapterError('Material slot names differ')
    if len(source.data.uv_layers) != 1 or not np.array_equal(_nfa_field(source.data.uv_layers[0].data, 'uv', np.float32, 2).view(np.uint32), np.asarray(binding['uvs'], np.float32).view(np.uint32)):
        raise _nfa_AdapterError('Bound corner UVs differ')
    target = np.asarray(binding['storedTargets'], np.float32)
    if target.shape != (len(source.data.loops), 3) or not np.isfinite(target).all() or np.any(np.abs(np.linalg.norm(target.astype(np.float64), axis=1) - 1) > _snv_FORMAT_UNIT_EPSILON):
        raise _nfa_AdapterError('Bound finite unit stored NORMALs required')
    if len(binding['storedCornerBindings']) != len(target):
        raise _nfa_AdapterError('Missing or ambiguous stored corner ancestry')
    keys = [(r['primitive'], r['triangle'], r['accessorVertex'], r['globalLoop']) for r in binding['storedCornerBindings']]
    if len(set(keys)) != len(keys):
        raise _nfa_AdapterError('Ambiguous stored corner ancestry')
    return target

def _nfa_small_donor(candidate, active_vertices, target, loops_by_vertex, source_loop_edges):
    mesh = candidate.data
    face_ids = sorted({li // 3 for v in active_vertices for li in loops_by_vertex[v]})
    vertex_ids = sorted({v for fi in face_ids for v in mesh.polygons[fi].vertices})
    loop_ids = [li for fi in face_ids for li in mesh.polygons[fi].loop_indices]
    if len(face_ids) > 1024 or len(vertex_ids) > 2048 or len(loop_ids) > 3072:
        raise _nfa_AdapterError('Bounded small donor budget exceeded before allocation')
    remap = {v: i for i, v in enumerate(vertex_ids)}
    data = bpy.data.meshes.new('CONTROL.small-normal-donor.mesh')
    obj = None
    try:
        data.from_pydata([tuple(mesh.vertices[v].co) for v in vertex_ids], [], [[remap[v] for v in mesh.polygons[fi].vertices] for fi in face_ids])
        data.update()
        for mat in mesh.materials:
            data.materials.append(mat)
        for p, fi in zip(data.polygons, face_ids):
            p.use_smooth = mesh.polygons[fi].use_smooth
            p.material_index = mesh.polygons[fi].material_index
        donor_edges = np.full(len(data.edges), -1, np.int32)
        for loop, source_li in zip(data.loops, loop_ids):
            sid = int(source_loop_edges[source_li])
            prior = int(donor_edges[loop.edge_index])
            if prior not in (-1, sid):
                raise _nfa_AdapterError('Ambiguous source edge ancestry in small donor')
            donor_edges[loop.edge_index] = sid
        for edge in data.edges:
            original = mesh.edges[int(donor_edges[edge.index])]
            edge.use_edge_sharp = original.use_edge_sharp
            edge.use_seam = original.use_seam
        for layer in mesh.uv_layers:
            uv = data.uv_layers.new(name=layer.name)
            uv.data.foreach_set('uv', np.asarray([tuple(layer.data[li].uv) for li in loop_ids], np.float32).ravel())
        attr = data.attributes.new(name='custom_normal', type='INT16_2D', domain='CORNER')
        attr.data.foreach_set('value', np.asarray([tuple(mesh.attributes['custom_normal'].data[li].value) for li in loop_ids], np.int16).ravel())
        data.update()
        obj = bpy.data.objects.new('CONTROL.small-normal-donor', data)
        _nfa_fresh(obj)
        return (obj, {'vertices': vertex_ids, 'faces': face_ids, 'loops': loop_ids, 'edges': donor_edges.tolist()})
    except BaseException:
        if obj is not None:
            _nfa_dispose(obj)
        elif not data.users:
            bpy.data.meshes.remove(data)
        raise

def _nfa__adapt_attempt(source, binding, *, expected_input_sha256, name, check=None, max_masks_per_vertex=256, restoration_limit=0.0002, forbidden=None, remaining_calls=None, remaining_probes=None, remaining_global_calls=4096, remaining_global_probes=131072, batch_budget=None):
    """Return detached hidden adapter copy or fail with partial bounded evidence."""
    if type(max_masks_per_vertex) is not int or max_masks_per_vertex != 256 or type(restoration_limit) not in (int, float) or (restoration_limit != 0.0002):
        raise _nfa_AdapterError('Only explicit staged256mask/2e-4 study controls supported')
    forbidden = {} if forbidden is None else forbidden
    remaining_calls = {} if remaining_calls is None else remaining_calls
    remaining_probes = {} if remaining_probes is None else remaining_probes
    _nfa_cancel(check, 'before-bind')
    if source.type != 'MESH':
        raise _nfa_AdapterError('Static mesh input required')
    target = _nfa_validate_binding(source, binding, expected_input_sha256)
    stored_matrix = _snv_matrix(binding['storedNodeWorld'], 'independent incoming stored-node frame')
    if np.max(np.abs(stored_matrix - np.asarray(source.matrix_world, np.float64))) > 1e-06:
        raise _nfa_AdapterError('Bound stored frame differs from realized native frame')
    _snv_matrix(np.asarray(source.matrix_world, np.float64), 'adapter source frame')
    before_guard = _nfa_guard(source)
    before = _nfa_normal(source.data)
    original_codes = _nfa_codes(source.data)
    zero = np.flatnonzero(np.linalg.norm(before.astype(np.float64), axis=1) == 0).tolist()
    if zero != binding['zeroLoops']:
        raise _nfa_AdapterError('Native zero scope differs from exact binding')
    if source.type != 'MESH' or source.modifiers or source.constraints or source.animation_data or source.data.shape_keys:
        raise _nfa_AdapterError('Static object mesh required')
    if bpy.data.objects.get(name) is not None:
        raise _nfa_AdapterError('Fresh candidate name required')
    loop_vertex = np.asarray([l.vertex_index for l in source.data.loops], np.int32)
    potential = set(binding['potentialAffectedVertices'])
    source_edge_vertices = _nfa_field(source.data.edges, 'vertices', np.int32, 2)
    source_loop_edges = _nfa_field(source.data.loops, 'edge_index', np.int32, 1).reshape(-1)
    source_sharp = _nfa_field(source.data.edges, 'use_edge_sharp', np.bool_, 1).reshape(-1)
    zero_vertices = np.unique(loop_vertex[zero])
    zero_edge_ids = np.flatnonzero(np.isin(source_edge_vertices, zero_vertices).any(axis=1))
    edge_index_by_key = {tuple(sorted(source_edge_vertices[i].tolist())): int(i) for i in zero_edge_ids}
    zero_set = set(zero)
    initial_nonzero = np.flatnonzero(np.linalg.norm(before.astype(np.float64), axis=1) > 0)
    initial_nonzero_mask = np.ones(len(before), np.bool_)
    initial_nonzero_mask[zero] = False
    vertex_order = sorted(set((int(loop_vertex[i]) for i in zero)))
    if len(vertex_order) > 64 or len(zero) > 512:
        raise _nfa_AdapterError('Declared global zero-scope eligibility cap exceeded')
    if np.any(_nfa_field(source.data.polygons, 'loop_total', np.int32, 1) != 3) or not np.array_equal(_nfa_field(source.data.polygons, 'loop_start', np.int32, 1).reshape(-1), np.arange(len(source.data.polygons)) * 3):
        raise _nfa_AdapterError('Static consecutive triangulated source required')
    loops_by_vertex = {v: np.flatnonzero(loop_vertex == v).tolist() for v in potential}
    candidate = None
    current = None
    donor = None
    reports = []
    changed_loops = set()
    chosen_edges = set()
    packing_in_attempt = [0]
    probes_in_attempt = [0]
    source_matrix = np.asarray(source.matrix_world, np.float64)
    inverse = np.linalg.inv(source_matrix[:3, :3])
    stored_inverse = np.linalg.inv(stored_matrix[:3, :3])

    def directions(values, stored=False):
        return _nfa_unit(values @ (stored_inverse if stored else inverse))

    def metrics(obj, scope, resolved):
        values = _nfa_normal(obj.data)
        required = sorted(set(scope) | set(resolved) | changed_loops)
        if required:
            local_error = np.linalg.norm(_nfa_unit(values[required]) - _nfa_unit(target[required]), axis=1)
            world_error = np.linalg.norm(directions(values[required].astype(np.float64)) - directions(target[required].astype(np.float64), stored=True), axis=1)
            maximum = float(max(np.max(local_error), np.max(world_error)))
            encoded = _snv_exporter_codec(values[required], _snv_CODEC)
            local = encoded[:, [0, 2, 1]].copy()
            local[:, 1] *= np.float32(-1)
            output_error = float(max(np.max(np.linalg.norm(_nfa_unit(local) - _nfa_unit(target[required]), axis=1)), np.max(np.linalg.norm(directions(local.astype(np.float64)) - directions(target[required].astype(np.float64), stored=True), axis=1))))
        else:
            maximum = output_error = 0.0
        unaffected = initial_nonzero_mask.copy()
        unaffected[required] = False
        affected_valid = [i for i in required if i not in zero_set]
        if np.any(unaffected):
            new_out = values[unaffected]
            old_out = before[unaffected]
            if np.array_equal(new_out.view(np.uint32), old_out.view(np.uint32)):
                other = world_other = 0.0
            else:
                other = float(np.max(np.abs(new_out - old_out)))
                world_other = float(np.max(np.abs(directions(new_out.astype(np.float64)) - directions(old_out.astype(np.float64)))))
        else:
            other = world_other = 0.0
        outside_exact = np.array_equal(values[unaffected].view(np.uint32), before[unaffected].view(np.uint32))
        ledger = []
        degradation = 0.0
        for li in affected_valid:
            old_local = float(np.linalg.norm(_nfa_unit(before[li:li + 1]) - _nfa_unit(target[li:li + 1])))
            new_local = float(np.linalg.norm(_nfa_unit(values[li:li + 1]) - _nfa_unit(target[li:li + 1])))
            old_world = float(np.linalg.norm(directions(before[li:li + 1].astype(np.float64)) - directions(target[li:li + 1].astype(np.float64), stored=True)))
            new_world = float(np.linalg.norm(directions(values[li:li + 1].astype(np.float64)) - directions(target[li:li + 1].astype(np.float64), stored=True)))
            degradation = max(degradation, new_local - old_local, new_world - old_world)
            ledger.append({'loop': li, 'storedInput': target[li].tolist(), 'oldNative': before[li].tolist(), 'newNative': values[li].tolist(), 'inputToOldLocalDirectionalError': old_local, 'inputToNewLocalDirectionalError': new_local, 'sourceRelativeLocalDegradation': new_local - old_local, 'inputToOldWorldDirectionalError': old_world, 'inputToNewWorldDirectionalError': new_world, 'sourceRelativeWorldDegradation': new_world - old_world})
        return {'maximumInputStoredToWorkingDirectionalError': maximum, 'maximumInputStoredToPredictedOutputDirectionalError': output_error, 'maximumUnaffectedNativeComponentDrift': other, 'maximumUnaffectedWorldComponentDrift': world_other, 'unaffectedDecodedUint32BitExact': bool(outside_exact), 'maximumAffectedNonzeroSourceRelativeDegradation': degradation, 'affectedNonzeroCornerSourceErrorLedger': ledger, 'pass': maximum <= restoration_limit and output_error <= restoration_limit and (other <= 2e-05) and (world_other <= 2e-05) and outside_exact and (degradation <= 2e-05)}

    def refine(candidate, scope, attempt, probe_counter, probe_limit):
        violating = [row for row in attempt['affectedNonzeroCornerSourceErrorLedger'] if max(row['sourceRelativeLocalDegradation'], row['sourceRelativeWorldDegradation']) > 2e-05]
        rows = []
        raw = _nfa_codes(candidate.data)
        active_vertices = {int(loop_vertex[li]) for li in scope}
        probe, probe_map = _nfa_small_donor(candidate, active_vertices, target, loops_by_vertex, source_loop_edges)
        donor_index = {source_li: li for li, source_li in enumerate(probe_map['loops'])}
        try:
            base = _nfa_codes(probe.data)
            for row in violating:
                li = row['loop']
                if li not in donor_index:
                    continue
                if probe_counter[0] + 289 > probe_limit or probes_in_attempt[0] + 289 > remaining_global_probes:
                    rows.append({'loop': li, 'budgetExhausted': True, 'maximumProbesRemaining': probe_limit})
                    break
                dli = donor_index[li]
                centre = raw[li].astype(np.int32)
                best = None
                count = 0
                for da in range(-8, 9):
                    for db in range(-8, 9):
                        code = centre + np.asarray((da, db), np.int32)
                        if np.any(code < -32768) or np.any(code > 32767):
                            continue
                        if count % 16 == 0:
                            _nfa_cancel(check, 'before-code-probe:' + str(li) + ':' + str(count))
                        _normal_batch_tick(batch_budget, 'packedCodeProbes', binding['sourceObject'])
                        trial = base.copy()
                        trial[dli] = code.astype(np.int16)
                        decoded = _nfa_probe_codes(probe.data, trial)
                        vector = None if decoded is None else decoded[dli].copy()
                        count += 1
                        probe_counter[0] += 1
                        probes_in_attempt[0] += 1
                        if vector is None or np.linalg.norm(vector) <= 0:
                            continue
                        new_local = float(np.linalg.norm(_nfa_unit(vector[None, :]) - _nfa_unit(target[li:li + 1])))
                        new_world = float(np.linalg.norm(directions(vector[None, :].astype(np.float64)) - directions(target[li:li + 1].astype(np.float64), stored=True)))
                        degradation = max(new_local - row['inputToOldLocalDirectionalError'], new_world - row['inputToOldWorldDirectionalError'])
                        encoded = _snv_exporter_codec(vector[None, :], _snv_CODEC)
                        encoded = encoded[:, [0, 2, 1]].copy()
                        encoded[:, 1] *= np.float32(-1)
                        output_error = float(max(np.linalg.norm(_nfa_unit(encoded) - _nfa_unit(target[li:li + 1])), np.linalg.norm(directions(encoded.astype(np.float64)) - directions(target[li:li + 1].astype(np.float64), stored=True))))
                        eligible = degradation <= 2e-05 and new_local <= 0.0002 and (new_world <= 0.0002) and (output_error <= 0.0002)
                        score = (not eligible, max(new_local, new_world), max(0.0, degradation), abs(da) + abs(db), da, db)
                        if best is None or score < best[0]:
                            best = (score, code.copy(), vector.copy(), degradation, output_error)
                if best is None:
                    rows.append({'loop': li, 'probes': count, 'noFiniteCode': True})
                    continue
                rows.append({'loop': li, 'probes': count, 'radius': 8, 'centreCode': centre.tolist(), 'selectedCode': best[1].tolist(), 'selectedDecoded': best[2].tolist(), 'eligible': not best[0][0], 'maximumInputStoredToNewNativeError': best[0][1], 'sourceRelativeDegradation': best[3], 'predictedOutputError': best[4]})
                if not best[0][0]:
                    raw[li] = best[1].astype(np.int16)
                    base[dli] = raw[li]
            candidate.data.attributes['custom_normal'].data.foreach_set('value', raw.ravel())
            candidate.data.update()
            _nfa_fresh(candidate)
        finally:
            _nfa_dispose(probe)
        return rows
    _nfa_cancel(check, 'before-copy')
    try:
        current = source.copy()
        current.data = source.data.copy()
        current.name = name
        current.hide_render = True
        current.hide_viewport = True
        resolved = []
        for vertex in vertex_order:
            _nfa_cancel(check, 'before-vertex:' + str(vertex))
            incident = [tuple(sorted(source_edge_vertices[i].tolist())) for i in np.flatnonzero((source_edge_vertices[:, 0] == vertex) | (source_edge_vertices[:, 1] == vertex))]
            if not 2 <= len(incident) <= 8:
                raise _nfa_AdapterError('Unsupported zero-vertex valence; bounded2..8 required', reports)
            if any((v not in potential for edge in incident for v in edge)):
                raise _nfa_AdapterError('Incomplete changed-endpoint fan binding')
            target_loops = [i for i in zero if int(loop_vertex[i]) == vertex]
            already = _nfa_normal(current.data)
            if all((np.linalg.norm(already[i]) > 0 for i in target_loops)):
                trial = metrics(current, target_loops, resolved)
                if trial['pass']:
                    resolved.extend(target_loops)
                    reports.append({'vertex': vertex, 'resolvedByEarlierAdjacentFan': True, 'metrics': trial})
                    continue
            masks = []
            for size in [2, 1] + list(range(3, len(incident) + 1)):
                masks.extend(itertools.combinations(incident, size))
            if len(masks) > max_masks_per_vertex:
                raise _nfa_AdapterError('Mask budget exceeded before native donor creation')
            attempts = []
            chosen = None
            probe_counter = [0]
            for mi, mask in enumerate(masks):
                marker = tuple(sorted((tuple(sorted(e)) for e in mask)))
                if marker in forbidden.get(vertex, set()):
                    continue
                if len(attempts) >= remaining_calls.get(vertex, 256):
                    break
                if packing_in_attempt[0] >= remaining_global_calls:
                    raise _nfa_AdapterError('Global native packing cap reached before donor creation', {'vertices': reports, 'packingCalls': packing_in_attempt[0], 'codeProbes': probes_in_attempt[0]})
                _nfa_cancel(check, 'before-mask:' + str(vertex) + ':' + str(mi))
                active_vertices = {v for e in mask for v in e}
                prior_vertices = {int(loop_vertex[li]) for li in changed_loops}
                if len(active_vertices | prior_vertices) > 128:
                    raise _nfa_AdapterError('Complete-call affected-vertex cap128 reached before candidate/donor work')
                _normal_batch_tick(batch_budget, 'maskEvaluations', binding['sourceObject'], active_vertices)
                candidate = current.copy()
                candidate.data = current.data.copy()
                donor = None
                scope = sorted((li for v in active_vertices for li in loops_by_vertex[v]))
                for obj in (candidate,):
                    for edge in mask:
                        obj.data.edges[edge_index_by_key[edge]].use_edge_sharp = True
                    obj.data.update()
                    _nfa_fresh(obj)
                _nfa_cancel(check, 'after-mask-copy')
                donor, donor_map = _nfa_small_donor(candidate, active_vertices, target, loops_by_vertex, source_loop_edges)
                packing_in_attempt[0] += 1
                donor.data.normals_split_custom_set(target[donor_map['loops']].tolist())
                donor.data.update()
                mismatch = [tuple(sorted((donor_map['vertices'][v] for v in e.vertices))) for e in donor.data.edges if any((donor_map['vertices'][v] in active_vertices for v in e.vertices)) and e.use_edge_sharp != candidate.data.edges[donor_map['edges'][e.index]].use_edge_sharp]
                if mismatch:
                    attempt = {'mask': [list(e) for e in mask], 'donorBasisSharpMismatch': True, 'pass': False}
                else:
                    raw = _nfa_codes(current.data)
                    encoded = _nfa_codes(donor.data)
                    scope_set = set(scope)
                    for donor_li, source_li in enumerate(donor_map['loops']):
                        if source_li in scope_set:
                            raw[source_li] = encoded[donor_li]
                    candidate.data.attributes['custom_normal'].data.foreach_set('value', raw.ravel())
                    candidate.data.update()
                    _nfa_fresh(candidate)
                    try:
                        attempt = {'mask': [list(e) for e in mask], **metrics(candidate, scope, resolved + target_loops)}
                    except (_nfa_AdapterError, ValueError):
                        attempt = {'mask': [list(e) for e in mask], 'nonfiniteOrZeroOrCodecUnsupported': True, 'pass': False}
                    if not attempt['pass'] and 'maximumInputStoredToWorkingDirectionalError' in attempt and (attempt['maximumInputStoredToWorkingDirectionalError'] <= 0.0002) and (attempt['maximumInputStoredToPredictedOutputDirectionalError'] <= 0.0002) and (attempt['maximumUnaffectedNativeComponentDrift'] <= 2e-05) and (attempt['maximumUnaffectedWorldComponentDrift'] <= 2e-05) and (attempt['maximumAffectedNonzeroSourceRelativeDegradation'] > 2e-05):
                        refined = refine(candidate, scope, attempt, probe_counter, remaining_probes.get(vertex, 8192))
                        attempt = {'mask': [list(e) for e in mask], **metrics(candidate, scope, resolved + target_loops), 'packedCodeRefinement': refined}
                attempts.append(attempt)
                _nfa_dispose(donor)
                donor = None
                if attempt['pass']:
                    chosen = {'mask': [list(e) for e in mask], 'attemptIndex': mi, 'nativePackingCalls': len(attempts), 'metrics': attempt, 'affectedLoops': scope, 'completeChangedEndpointFans': sorted(active_vertices)}
                    chosen_edges.update(mask)
                    changed_loops.update(scope)
                    _nfa_dispose(current)
                    current = candidate
                    candidate = None
                    resolved.extend(target_loops)
                    break
                _nfa_dispose(candidate)
                candidate = None
            reports.append({'vertex': vertex, 'sourceVertex': vertex if binding.get('globalIndexIdentity') else binding['sourceVertexIds'][vertex], 'valence': len(incident), 'attempts': attempts, 'chosen': chosen, 'nativeCodeProbes': probe_counter[0], 'maximumNativeCodeProbes': 8192})
            if chosen is None:
                raise _nfa_AdapterError('No admissible bounded sharp-fan restoration at source vertex ' + str(vertex if binding.get('globalIndexIdentity') else binding['sourceVertexIds'][vertex]), reports)
        final = _nfa_normal(current.data)
        if np.any(np.linalg.norm(final.astype(np.float64), axis=1) == 0):
            raise _nfa_AdapterError('Adapter left native zero normals', reports)
        _nfa_cancel(check, 'before-final-guards')
        final_metrics = metrics(current, sorted(changed_loops), zero)
        if not final_metrics['pass']:
            raise _nfa_AdapterError('Final precision ledger rejected', reports)
        outside = [i for i in range(len(before)) if i not in changed_loops]
        if not np.array_equal(_nfa_codes(current.data)[outside], original_codes[outside]):
            raise _nfa_AdapterError('Raw normal codes changed outside complete affected fans')
        if not np.array_equal(final[outside].view(np.uint32), before[outside].view(np.uint32)):
            raise _nfa_AdapterError('Decoded normal UINT32 bits changed outside complete affected fans')
        allowed = np.zeros(len(source_sharp), np.bool_)
        for edge in chosen_edges:
            allowed[edge_index_by_key[edge]] = True
        final_sharp = _nfa_field(current.data.edges, 'use_edge_sharp', np.bool_, 1).reshape(-1)
        if not np.array_equal(final_sharp[~allowed], source_sharp[~allowed]):
            raise _nfa_AdapterError('Sharpness changed outside declared incident edges')
        current.name = name
        if current.name != name:
            raise _nfa_AdapterError('Candidate name identity changed')
        _nfa_verify_unchanged(before_guard, _nfa_guard(current))
        scratch = current.data.copy()
        try:
            if _nfa_normal(scratch).tobytes() != final.tobytes():
                raise _nfa_AdapterError('Fresh copy cache decoded normals differ')
        finally:
            bpy.data.meshes.remove(scratch)
        if _nfa_guard(source) != before_guard:
            raise _nfa_AdapterError('Protected source changed')
        _nfa_cancel(check, 'after-final-guards')
        result = {'sourceObject': binding['sourceObject'], 'inputSha256': expected_input_sha256, 'bindingSha256': binding['sha256'], 'zeroLoops': zero, 'zeroVertices': vertex_order, 'vertices': reports, 'changedLoops': sorted(changed_loops), 'sharpEdges': [list(e) for e in sorted(chosen_edges)], 'finalLedger': final_metrics, 'allRawCodesOutsideChangedFansExact': True, 'allDecodedUint32OutsideChangedFansExact': True, 'maximumAffectedVerticesPerCall': 128, 'affectedVertices': sorted({int(loop_vertex[li]) for li in changed_loops}), 'allOtherFieldsExact': True, 'sourceUnchanged': True, 'freshCopyCacheExact': True, 'sourceDecodedSha256': _nfa_digest(before), 'workingDecodedSha256': _nfa_digest(final), 'proposedRestorationPrecision': restoration_limit, 'workingAndCodecBoundsUnchanged': 2e-05, 'nativePackedCodeProbes': sum((r.get('nativeCodeProbes', 0) for r in reports)), 'maximumPackedCodeProbesPerVertex': 8192, 'maskBudgetPerVertex': max_masks_per_vertex, 'nativePackingCalls': sum((r.get('chosen', {}).get('nativePackingCalls', 0) for r in reports if r.get('chosen'))), 'affectedNonzeroSourceRelativeDegradationLimit': 2e-05, 'donorBudget': {'faces': 1024, 'vertices': 2048, 'loops': 3072}, 'precisionContractActivated': False}
        return (current, result)
    except BaseException:
        for obj in (donor, candidate, current):
            if obj is not None:
                _nfa_dispose(obj)
        raise

def _nfa_adapt_copy(source, binding, *, expected_input_sha256, name, check=None, max_masks_per_vertex=256, restoration_limit=0.0002, batch_budget=None):
    """Finite mask restart for a coupled pair, with TOTAL pervertex budgets."""
    if source.type != 'MESH' or source.mode != 'OBJECT' or source.modifiers or source.constraints or source.animation_data or source.data.shape_keys or source.data.animation_data:
        raise _nfa_AdapterError('Static object-mode actual mesh required')
    forbidden = {}
    calls = {}
    probes = {}
    restarts = []
    before = _nfa_guard(source)
    restart_edges = _nfa_field(source.data.edges, 'vertices', np.int32, 2)
    for restart in range(32):
        _normal_batch_tick(batch_budget, 'jointRestartStates', binding['sourceObject'])
        try:
            obj, report = _nfa__adapt_attempt(source, binding, expected_input_sha256=expected_input_sha256, name=name, check=check, max_masks_per_vertex=max_masks_per_vertex, restoration_limit=restoration_limit, forbidden=forbidden, remaining_calls={v: 256 - n for v, n in calls.items()}, remaining_probes={v: 8192 - n for v, n in probes.items()}, remaining_global_calls=4096 - sum(calls.values()), remaining_global_probes=131072 - sum(probes.values()), batch_budget=batch_budget)
        except _nfa_AdapterError as error:
            evidence = error.evidence
            if not isinstance(evidence, list):
                raise
            for row in evidence:
                vertex = row['vertex']
                calls[vertex] = calls.get(vertex, 0) + len(row.get('attempts', []))
                probes[vertex] = probes.get(vertex, 0) + row.get('nativeCodeProbes', 0)
            restarts.append({'restart': restart, 'error': str(error), 'vertices': evidence})
            if _nfa_guard(source) != before:
                raise _nfa_AdapterError('Source changed during bounded pair restart')
            if len(evidence) < 2:
                raise _nfa_AdapterError(str(error), {'boundedRestarts': restarts, 'totalCalls': calls, 'totalCodeProbes': probes})
            failed = evidence[-1]
            previous = evidence[-2]
            if failed.get('chosen') is not None or not previous.get('chosen'):
                raise _nfa_AdapterError(str(error), {'boundedRestarts': restarts, 'totalCalls': calls, 'totalCodeProbes': probes})
            a, b = (previous['vertex'], failed['vertex'])
            neighbors_a = {a} | set(restart_edges[(restart_edges[:, 0] == a) | (restart_edges[:, 1] == a)].reshape(-1).tolist())
            neighbors_b = {b} | set(restart_edges[(restart_edges[:, 0] == b) | (restart_edges[:, 1] == b)].reshape(-1).tolist())
            if not neighbors_a.intersection(neighbors_b):
                raise _nfa_AdapterError('Rejected noncoupled restart', {'boundedRestarts': restarts})
            marker = tuple(sorted((tuple(sorted(e)) for e in previous['chosen']['mask'])))
            if marker in forbidden.get(a, set()):
                raise _nfa_AdapterError('Pair search made no progress', {'boundedRestarts': restarts})
            forbidden.setdefault(a, set()).add(marker)
            if any((n > 256 for n in calls.values())) or any((n > 8192 for n in probes.values())) or sum(calls.values()) > 4096 or (sum(probes.values()) > 131072):
                raise _nfa_AdapterError('Declared total pervertex budget exceeded', {'boundedRestarts': restarts, 'totalCalls': calls, 'totalCodeProbes': probes})
            continue
        for row in report['vertices']:
            vertex = row['vertex']
            calls[vertex] = calls.get(vertex, 0) + len(row.get('attempts', []))
            probes[vertex] = probes.get(vertex, 0) + row.get('nativeCodeProbes', 0)
        if any((n > 256 for n in calls.values())) or any((n > 8192 for n in probes.values())) or sum(calls.values()) > 4096 or (sum(probes.values()) > 131072):
            _nfa_dispose(obj)
            raise _nfa_AdapterError('Declared total pervertex budget exceeded after success')
        report.update({'boundedPairRestarts': restarts, 'totalNativePackingCallsByVertex': calls, 'totalNativeCodeProbesByVertex': probes, 'maximumPairRestarts': 32, 'totalPerVertexMaskBudget': 256, 'totalPerVertexCodeProbeBudget': 8192, 'maximumZeroVerticesPerMesh': 64, 'maximumZeroCornersPerMesh': 512, 'maximumNativePackingCallsPerMesh': 4096, 'maximumCodeDecodeProbesPerMesh': 131072})
        return (obj, report)
    raise _nfa_AdapterError('Bounded pair restart count exhausted', {'boundedRestarts': restarts, 'totalCalls': calls, 'totalCodeProbes': probes})

"""Exact scoped GLB NORMAL/corner binding for the staged native decoder study."""

def _nfb_validate_document(reader):
    """NORMAL eligibility applies even when this raw import has no zero fan."""
    doc = reader.document
    stack = [(root, 0) for root in doc['scenes'][0].get('nodes', [])]
    while stack:
        node, depth = stack.pop()
        if depth > 32:
            raise _nfa_AdapterError('Stored source path exceeds declared depth32')
        stack.extend(((child, depth + 1) for child in doc['nodes'][node].get('children', [])))
    for mesh in reader.document['meshes']:
        if mesh.get('extensions') or mesh.get('weights'):
            raise _nfa_AdapterError('Only explicit static uncompressed mesh data supported')
        for primitive in mesh['primitives']:
            if primitive.get('extensions') or set(primitive['attributes']) - {'POSITION', 'NORMAL', 'TEXCOORD_0'}:
                raise _nfa_AdapterError('Unsupported primitive extension or attribute representation')
            if primitive.get('mode', 4) != 4 or primitive.get('targets'):
                raise _nfa_AdapterError('Static indexed triangle document required')
            if not {'POSITION', 'NORMAL'} <= set(primitive['attributes']):
                raise _nfa_AdapterError('Incoming stored POSITION and NORMAL are mandatory')
            positions = reader.accessor(primitive['attributes']['POSITION'], 'float', 3)
            normals = reader.accessor(primitive['attributes']['NORMAL'], 'float', 3)
            if len(normals) != len(positions) or np.any(np.abs(np.linalg.norm(normals.astype(np.float64), axis=1) - 1) > _snv_FORMAT_UNIT_EPSILON):
                raise _nfa_AdapterError('Incoming stored NORMAL is nonunit or has stale cardinality')
            indices = reader.accessor(primitive['indices'], 'index', 1)
            if indices.size % 3 or np.any(indices >= len(positions)):
                raise _nfa_AdapterError('Incoming stored triangle indices are malformed')

def _nfb_verify_native_frame(obj, reader):
    ni = _nfb_node_index(reader, obj.name)
    conversion = np.eye(4)
    conversion[:3, :3] = np.asarray(((1, 0, 0), (0, 0, -1), (0, 1, 0)), np.float64)
    expected = conversion @ reader.worlds[ni] @ conversion.T
    _snv_matrix(np.asarray(obj.matrix_world, np.float64), 'native import adapter frame')
    if np.max(np.abs(expected - np.asarray(obj.matrix_world, np.float64))) > 1e-06:
        raise _nfa_AdapterError('Native node frame differs from exact source path')
    return expected

def _nfb_native_records(obj, face_records):
    """Read current native vectors bound to original oriented scoped triangles."""
    wanted = {_nfb_canonical(r['coords'], r['uvs'], r['material'])[0]: r for r in face_records}
    if len(wanted) != len(face_records):
        raise _nfa_AdapterError('Ambiguous requested native face records')
    coords = _nfa_field(obj.data.vertices, 'co', np.float32, 3)
    points = np.asarray([p for r in face_records for p in r['coords']], np.float32)
    coords[coords == 0] = 0
    points[points == 0] = 0
    vertices = np.isin(coords.view('V12').reshape(-1), points.view('V12').reshape(-1))
    loop_vertices = _nfa_field(obj.data.loops, 'vertex_index', np.int32, 1).reshape(-1)
    if len(loop_vertices) % 3:
        raise _nfa_AdapterError('Native triangle cardinality differs')
    selected = np.flatnonzero(vertices[loop_vertices].reshape((-1, 3)).all(axis=1))
    normals = _nfa_normal(obj.data)
    found = {}
    for fi in selected:
        record = _nfb_face_record(obj, int(fi))
        key, order = _nfb_canonical(record['coords'], record['uvs'], record['material'])
        if key not in wanted:
            continue
        if key in found:
            raise _nfa_AdapterError('Ambiguous current native source triangle')
        wanted_order = _nfb_canonical(wanted[key]['coords'], wanted[key]['uvs'], wanted[key]['material'])[1]
        rows = {}
        for rank, ci in enumerate(order):
            rows[wanted_order[rank]] = normals[record['loops'][ci]].tolist()
        found[key] = rows
    if set(found) != set(wanted):
        raise _nfa_AdapterError('Missing current native source triangle')
    return [found[_nfb_canonical(r['coords'], r['uvs'], r['material'])[0]] for r in face_records]

def _nfb_canonical(points, uv, material):
    key, order = _snv_canonical(np.asarray(points, np.float32), np.asarray(uv, np.float32)[None, :, :], material)
    return (key, order)

def _nfb_node_index(reader, name):
    matches = [i for i, n in enumerate(reader.document['nodes']) if n.get('name') == name and 'mesh' in n]
    if len(matches) != 1:
        raise _nfa_AdapterError('Missing or ambiguous named stored mesh node')
    return matches[0]

def _nfb_collect_stored(reader, name, face_records):
    """Return unique oriented POS+UV+material rows from actual safe GLB accessors."""
    ni = _nfb_node_index(reader, name)
    wanted = {}
    for record in face_records:
        key, order = _nfb_canonical(record['coords'], record['uvs'], record['material'])
        if key in wanted:
            raise _nfa_AdapterError('Ambiguous native oriented triangle/UV/material key')
        wanted[key] = (record, order)
    points = np.asarray([p for r in face_records for p in r['coords']], np.float32)
    points[points == 0] = 0
    matches = {}
    mesh = reader.document['meshes'][reader.document['nodes'][ni]['mesh']]
    for pi, primitive in enumerate(mesh['primitives']):
        if primitive.get('mode', 4) != 4 or primitive.get('targets') or (not {'POSITION', 'NORMAL', 'TEXCOORD_0'} <= set(primitive['attributes'])):
            raise _nfa_AdapterError('Static indexed triangles with POSITION/NORMAL/UV0 required')
        if any((name.startswith('TEXCOORD_') and name != 'TEXCOORD_0' for name in primitive['attributes'])):
            raise _nfa_AdapterError('Additional UV layers unsupported by this narrow source binding')
        vertices = reader.accessor(primitive['attributes']['POSITION'], 'float', 3).copy()
        vertices = vertices[:, [0, 2, 1]].copy()
        vertices[:, 1] *= np.float32(-1)
        vertices[vertices == 0] = 0
        indices = reader.accessor(primitive['indices'], 'index', 1).reshape((-1, 3))
        if np.any(indices >= len(vertices)):
            raise _nfa_AdapterError('Out-of-range stored triangle index')
        keep = np.isin(vertices.view('V12').reshape(-1), points.view('V12').reshape(-1))
        candidates = np.flatnonzero(keep[indices].all(axis=1))
        if not len(candidates):
            continue
        normal = reader.accessor(primitive['attributes']['NORMAL'], 'float', 3).copy()
        normal = normal[:, [0, 2, 1]].copy()
        normal[:, 1] *= np.float32(-1)
        if len(normal) != len(vertices) or np.any(np.abs(np.linalg.norm(normal.astype(np.float64), axis=1) - 1) > _snv_FORMAT_UNIT_EPSILON):
            raise _nfa_AdapterError('Actual stored NORMAL must be finite/unit for every source accessor row')
        uv = reader.accessor(primitive['attributes']['TEXCOORD_0'], 'float', 2).copy()
        uv[:, 1] = np.float32(1) - uv[:, 1]
        if len(uv) != len(vertices):
            raise _nfa_AdapterError('Stored UV/NORMAL/POSITION cardinality differs')
        material = reader.document['materials'][primitive['material']]['name']
        for ti in candidates:
            triangle = indices[ti]
            coords = vertices[triangle]
            triangle_uv = uv[triangle]
            key, order = _nfb_canonical(coords, triangle_uv, material)
            if key not in wanted:
                continue
            if key in matches:
                raise _nfa_AdapterError('Ambiguous stored oriented triangle/UV/material ancestry')
            record, native_order = wanted[key]
            mapped = {}
            for rank, source_corner in enumerate(order):
                native_corner = native_order[rank]
                mapped[native_corner] = {'vector': normal[triangle[source_corner]].tolist(), 'primitive': pi, 'triangle': int(ti), 'accessorVertex': int(triangle[source_corner]), 'sourceCorner': int(source_corner)}
            matches[key] = mapped
    if set(matches) != set(wanted):
        raise _nfa_AdapterError('Missing exact source corner binding')
    return [matches[_nfb_canonical(r['coords'], r['uvs'], r['material'])[0]] for r in face_records]

def _nfb_face_record(obj, fi):
    mesh = obj.data
    p = mesh.polygons[fi]
    if p.loop_total != 3:
        raise _nfa_AdapterError('Exact oriented source triangles required')
    return {'face': fi, 'loops': list(p.loop_indices), 'coords': [list(mesh.vertices[v].co) for v in p.vertices], 'uvs': [list(mesh.uv_layers.active.data[li].uv) for li in p.loop_indices], 'material': mesh.materials[p.material_index].name}

def _nfb_build_binding(obj, reader, input_sha):
    _nfb_validate_document(reader)
    actual_raw_sha256 = hashlib.sha256(reader.raw).hexdigest()
    if actual_raw_sha256 != input_sha:
        raise _nfa_AdapterError('Caller input hash differs from actual immutable GLB reader bytes')
    mesh = obj.data
    if obj.type != 'MESH' or len(mesh.uv_layers) != 1 or (not mesh.uv_layers.active):
        raise _nfa_AdapterError('Narrow normal decoder binding requires one actual UV layer')
    actual = _nfa_normal(mesh)
    zero = np.flatnonzero(np.linalg.norm(actual.astype(np.float64), axis=1) == 0).tolist()
    if not zero:
        return None
    ni = _nfb_node_index(reader, obj.name)
    conversion = np.eye(4)
    conversion[:3, :3] = np.asarray(((1, 0, 0), (0, 0, -1), (0, 1, 0)), np.float64)
    stored_frame = conversion @ reader.worlds[ni] @ conversion.T
    if np.max(np.abs(stored_frame - np.asarray(obj.matrix_world, np.float64))) > 1e-06:
        raise _nfa_AdapterError('Stored/node native world frame differs from existing serialization bound')
    loop_vertices = _nfa_field(mesh.loops, 'vertex_index', np.int32, 1).reshape(-1)
    zero_vertices = np.unique(loop_vertices[zero])
    edge_vertices = _nfa_field(mesh.edges, 'vertices', np.int32, 2)
    incident = edge_vertices[np.isin(edge_vertices, zero_vertices).any(axis=1)]
    potential = np.unique(incident).tolist()
    target_loops = np.flatnonzero(np.isin(loop_vertices, potential)).tolist()
    starts = _nfa_field(mesh.polygons, 'loop_start', np.int32, 1).reshape(-1)
    totals = _nfa_field(mesh.polygons, 'loop_total', np.int32, 1).reshape(-1)
    if not np.array_equal(starts, np.arange(len(starts)) * 3) or np.any(totals != 3):
        raise _nfa_AdapterError('Stable triangulated native source required')
    face_ids = sorted({li // 3 for li in target_loops})
    faces = [_nfb_face_record(obj, fi) for fi in face_ids]
    matched = _nfb_collect_stored(reader, obj.name, faces)
    targets = {}
    ancestry = {}
    records = []
    for face, corners in zip(faces, matched):
        for ci, li in enumerate(face['loops']):
            if li not in set(target_loops):
                continue
            targets[li] = corners[ci]['vector']
            ancestry[li] = {'globalLoop': li, 'globalFace': face['face'], 'material': face['material'], **{k: v for k, v in corners[ci].items() if k != 'vector'}}
            records.append({'loop': li, 'face': face['face'], 'corner': ci, 'coords': face['coords'], 'uvs': face['uvs'], 'material': face['material'], 'storedInput': corners[ci]['vector'], 'oldNative': actual[li].tolist()})
    if sorted(targets) != target_loops:
        raise _nfa_AdapterError('Incomplete complete-endpoint fan target coverage')
    binding = {'kind': 'whole-input-sparse-stored-fan-binding', 'sourceInputSha256': input_sha, 'actualReaderRawByteSha256': actual_raw_sha256, 'sourceObject': obj.name, 'sourceWorld': [list(r) for r in obj.matrix_world], 'storedNodeWorld': stored_frame.tolist(), 'sourceGuard': _nfa_guard(obj), 'globalIndexIdentity': True, 'zeroLoops': zero, 'zeroVertices': zero_vertices.tolist(), 'potentialAffectedVertices': potential, 'targetLoopIds': target_loops, 'storedScopeTargets': [targets[li] for li in target_loops], 'storedCornerBindings': [ancestry[li] for li in target_loops], 'scopeCornerRecords': records, 'outerDonorFillerPolicy': 'Existing nonzero native vectors normalized only for unwritten donor boundary corners; no geometry-normal substitution. Actual written fan targets always exact stored NORMALs.', 'precisionContractActivated': False}
    binding['sha256'] = hashlib.sha256(json.dumps(binding, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()
    return binding

"""Fixed whole decoder-cohort work reservations, including rejected work."""
_normal_BATCH_LIMITS={'maskEvaluations':8192,'jointCandidateStates':4096,'jointRestartStates':4096,'packedCodeProbes':131072,'historicalAffectedSourceVertices':128}

class _normal_BatchBudgetExhausted(RuntimeError):
    """Cohort abort; never a candidate-ineligibility or coupled-retry error."""
    def __init__(self,message,budget):
        super().__init__(message);self.evidence=_normal_batch_summary(budget,verbose=False)

def _normal_new_batch_budget():
    return {'counts':{name:0 for name in _normal_BATCH_LIMITS if name!='historicalAffectedSourceVertices'},
        'triedVerticesBySource':{},'acceptedPreparedVerticesBySource':{},'perSourceWork':{}}

def _normal_batch_tick(budget,kind,source,vertices=()):
    if budget is None:return
    counts=budget['counts'];limits=_normal_BATCH_LIMITS
    if kind=='maskEvaluations':
        trial={int(vertex) for vertex in vertices}
        previous=budget['triedVerticesBySource'].get(source,set());proposed=previous|trial
        historical=sum(len(value) for name,value in budget['triedVerticesBySource'].items() if name!=source)+len(proposed)
        if historical>limits['historicalAffectedSourceVertices']:raise _normal_BatchBudgetExhausted('Whole normal decoder historical affected-vertex budget exhausted before candidate writes',budget)
        for key in ('maskEvaluations','jointCandidateStates'):
            if counts[key]>=limits[key]:raise _normal_BatchBudgetExhausted('Whole normal decoder '+key+' budget exhausted before candidate allocation',budget)
        counts['maskEvaluations']+=1;counts['jointCandidateStates']+=1
        budget['triedVerticesBySource'][source]=proposed
        row=budget['perSourceWork'].setdefault(source,{'maskEvaluations':0,'jointCandidateStates':0,'jointRestartStates':0,'packedCodeProbes':0})
        row['maskEvaluations']+=1;row['jointCandidateStates']+=1
    elif kind in ('jointRestartStates','packedCodeProbes'):
        if counts[kind]>=limits[kind]:raise _normal_BatchBudgetExhausted('Whole normal decoder '+kind+' budget exhausted before native operation',budget)
        counts[kind]+=1
        row=budget['perSourceWork'].setdefault(source,{'maskEvaluations':0,'jointCandidateStates':0,'jointRestartStates':0,'packedCodeProbes':0});row[kind]+=1
    else:raise _normal_BatchBudgetExhausted('Unknown internal normal decoder budget unit',budget)

def _normal_batch_accept(budget,source,evidence):
    if source in budget['acceptedPreparedVerticesBySource']:raise _normal_BatchBudgetExhausted('Duplicate selected source namespace in decoder cohort',budget)
    accepted=set(evidence['affectedVertices'])
    if not accepted<=budget['triedVerticesBySource'].get(source,set()):raise _normal_BatchBudgetExhausted('Accepted source vertices were not reserved before writes',budget)
    budget['acceptedPreparedVerticesBySource'][source]=accepted

def _normal_batch_summary(budget,verbose=True):
    counts=dict(budget['counts']);counts['historicalAffectedSourceVertices']=sum(len(value) for value in budget['triedVerticesBySource'].values())
    counts['acceptedPreparedAffectedVertices']=sum(len(value) for value in budget['acceptedPreparedVerticesBySource'].values())
    result={'limits':dict(_normal_BATCH_LIMITS),'consumed':counts,'scope':'One complete normal_decode_imported call across all selected mesh nodes and all rejected attempts/restarts.',
        'definitions':{'maskEvaluations':'One attempted incident-edge mask, reserved before candidate mesh allocation.',
            'jointCandidateStates':'One complete current accepted-mask-prefix plus trial-mask candidate configuration, reserved before allocation. One-to-one with masks in this implementation; independently capped.',
            'jointRestartStates':'One whole per-mesh adapt_attempt start including every rejected coupled restart, reserved before the attempt.',
            'packedCodeProbes':'One valid neighboring short-code trial decoded on a scratch donor, reserved individually before its allocation/write.',
            'historicalAffectedSourceVertices':'Union of all endpoints of every actually tried mask, namespaced by selected source NODE/object and native vertex index, including rejected trials/restarts.',
            'acceptedPreparedAffectedVertices':'Final accepted per-node working fan union, reported separately from historical work.'},
        'perSourceWork':budget['perSourceWork'],'perMeshAndPerVertexLimitsRemainAdditional':True,'exhaustionAbortsCohortWithoutCandidateRetry':True}
    if verbose:
        result['historicalVerticesBySource']={name:sorted(values) for name,values in budget['triedVerticesBySource'].items()}
        result['acceptedPreparedVerticesBySource']={name:sorted(values) for name,values in budget['acceptedPreparedVerticesBySource'].items()}
    return result


"""Private read-only corner ancestry, with compact JSON loss summaries."""
def _normal_readonly(values,dtype):
    array=np.asarray(values,dtype=dtype)
    if array.nbytes>_snv_MAX_FIELD_BYTES:raise _nfa_AdapterError('Private source corner field exceeds64MiB')
    array=array.copy();array.flags.writeable=False;return array

def _normal_vector_stats(values):
    if len(values)*3*8>_snv_MAX_FIELD_BYTES:raise _nfa_AdapterError('Float64 normal diagnostic field exceeds64MiB before allocation')
    values=np.asarray(values,np.float64);finite=np.isfinite(values).all(axis=1)
    length=np.linalg.norm(values[finite],axis=1)
    return {'corners':len(values),'nonfiniteCorners':int(np.count_nonzero(~finite)),
        'zeroCorners':int(np.count_nonzero(length==0)),'minimumFiniteLength':float(length.min()) if len(length) else None,
        'maximumFiniteLength':float(length.max()) if len(length) else None}

def _normal_corner_owner(mapping,primitive_ranges,loop):
    ordinal=int(mapping[loop])
    for primitive,start,count in primitive_ranges:
        if start<=ordinal<start+count:return {'nativeLoop':int(loop),'sourcePrimitive':int(primitive),'sourceTriangle':(ordinal-start)//3,'sourceCorner':(ordinal-start)%3,'indexedCornerOrdinal':ordinal}
    raise _nfa_AdapterError('Source corner ordinal has no declared primitive owner')

class _normal_SourceContext:
    def __init__(self,input_sha,obj,source_frame,targets,raw,mapping,primitive_ranges,geometry):
        self.input_sha=input_sha;self.object_name=obj.name
        self.source_frame=_normal_readonly(source_frame,np.float64);self.raw_frame=_normal_readonly(obj.matrix_world,np.float64)
        self.targets=_normal_readonly(targets,np.float32);self.raw=_normal_readonly(raw,np.float32)
        self.mapping=_normal_readonly(mapping,np.int32);self.primitive_ranges=tuple(tuple(x) for x in primitive_ranges)
        self.geometry=dict(geometry);self.payload_sha=self.fingerprint()
    def fingerprint(self):
        value={'input':self.input_sha,'object':self.object_name,'geometry':self.geometry,'primitiveRanges':self.primitive_ranges,
            'sourceFrame':_nfa_digest(self.source_frame),'rawFrame':_nfa_digest(self.raw_frame),'sourceNormals':_nfa_digest(self.targets),
            'rawNormals':_nfa_digest(self.raw),'cornerMap':_nfa_digest(self.mapping)}
        return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()
    def validate(self,row):
        if any(array.flags.writeable for array in (self.source_frame,self.raw_frame,self.targets,self.raw,self.mapping)) or self.payload_sha!=self.fingerprint() or row['sourceInputSha256']!=self.input_sha or row['object']!=self.object_name or row['allCornerContextSha256']!=self.payload_sha or row['storedNodeWorld']!=self.source_frame.tolist() or row['rawNativeWorld']!=self.raw_frame.tolist():
            raise _nfa_AdapterError('Required private original-corner ancestry is missing or stale')

class _normal_ImportRow(dict):
    """Only metadata is serialized; immutable arrays remain privately owned."""
    pass

class _normal_LineageRow(dict):
    pass

def _normal_all_corner_loss(context,actual,actual_frame):
    targets=context.targets;actual=np.asarray(actual,np.float32)
    if len(targets)*3*8>_snv_MAX_FIELD_BYTES:raise _nfa_AdapterError('Float64 source/realized normal field exceeds64MiB before allocation')
    if actual.shape!=targets.shape:raise _nfa_AdapterError('All-corner loss coverage differs from original ancestry')
    frame=_snv_matrix(actual_frame,'all-corner realized frame');source_frame=_snv_matrix(context.source_frame,'all-corner source frame')
    a=targets.astype(np.float64);b=actual.astype(np.float64)
    lengths=np.linalg.norm(b,axis=1);valid=np.isfinite(b).all(axis=1)&(lengths>0)
    local=np.full(len(a),np.nan,np.float64);world=local.copy()
    a/=np.linalg.norm(a,axis=1)[:,None]
    if np.any(valid):
        normalized=b[valid]/lengths[valid,None];local[valid]=np.linalg.norm(a[valid]-normalized,axis=1)
        aw=a[valid]@np.linalg.inv(source_frame[:3,:3]);bw=normalized@np.linalg.inv(frame[:3,:3])
        aw/=np.linalg.norm(aw,axis=1)[:,None];bw/=np.linalg.norm(bw,axis=1)[:,None]
        world[valid]=np.linalg.norm(aw-bw,axis=1)
    count=int(np.count_nonzero(valid));maximum_local=float(np.max(local[valid])) if count else None;maximum_world=float(np.max(world[valid])) if count else None
    if count:
        score=np.where(valid,np.maximum(local,world),-1);worst=int(np.argmax(score))
    else:worst=0
    witness={**_normal_corner_owner(context.mapping,context.primitive_ranges,worst),'sourceLocalVector':targets[worst].tolist(),
        'realizedLocalVector':actual[worst].tolist(),'localDirectionalError':float(local[worst]) if valid[worst] else None,
        'worldDirectionalError':float(world[worst]) if valid[worst] else None}
    invalid=np.flatnonzero(~valid)
    return {'indexedCornerCoverage':len(a),'sourceMappedNormalF32Sha256':_nfa_digest(targets),'realizedNormalF32Sha256':_nfa_digest(actual),
        'sourceCornerMapInt32Sha256':_nfa_digest(context.mapping),'sourceWorld':source_frame.tolist(),'realizedWorld':frame.tolist(),
        'sourceStats':_normal_vector_stats(targets),'realizedStats':_normal_vector_stats(actual),
        'maximumLocalDirectionalError':maximum_local,'maximumWorldDirectionalError':maximum_world,
        'cornersAbove2e4LocalDiagnostic':int(np.count_nonzero(local[valid]>2e-4)),
        'cornersAbove2e4WorldDiagnostic':int(np.count_nonzero(world[valid]>2e-4)),
        'cornersAbove2e4EitherDiagnostic':int(np.count_nonzero(np.maximum(local[valid],world[valid])>2e-4)),
        'allCornersWithin2e4Diagnostic':not len(invalid) and maximum_local<=2e-4 and maximum_world<=2e-4,
        'localDirectionalLossFloat64Sha256':_nfa_digest(local),'worldDirectionalLossFloat64Sha256':_nfa_digest(world),
        'worstMappedCorner':witness,'firstInvalidNativeLoops':invalid[:8].tolist(),
        'diagnosticOnlyNoOutsideFanGuardOrQualityAcceptance':True}


"""Private staged transaction: prepare copied meshes, then commit object.data."""
_normal_IMPORT_CONTRACT='opencaw-rigid-input-normals/v1'

def _normal_ui(obj):
    return {'hideViewport':obj.hide_viewport,'hideRender':obj.hide_render,'hidden':obj.hide_get(),'selected':obj.select_get()}

def _normal_node_state(obj):
    return {'name':obj.name,'parent':obj.parent.as_pointer() if obj.parent else None,
        'world':[list(r) for r in obj.matrix_world],'basis':[list(r) for r in obj.matrix_basis],
        'parentInverse':[list(r) for r in obj.matrix_parent_inverse],'ui':_normal_ui(obj)}

def _normal_transform_channels(obj):
    return {'mode':obj.rotation_mode,'location':tuple(obj.location),'scale':tuple(obj.scale),
        'quaternion':tuple(obj.rotation_quaternion),'euler':tuple(obj.rotation_euler),'axisAngle':tuple(obj.rotation_axis_angle),
        'deltaLocation':tuple(obj.delta_location),'deltaScale':tuple(obj.delta_scale),
        'deltaQuaternion':tuple(obj.delta_rotation_quaternion),'deltaEuler':tuple(obj.delta_rotation_euler)}

def _normal_restore_channels(obj,value):
    # Restore native channels, never decompose matrix_basis/world on rollback.
    obj.rotation_mode=value['mode'];obj.location=value['location'];obj.scale=value['scale']
    obj.rotation_quaternion=value['quaternion'];obj.rotation_euler=value['euler'];obj.rotation_axis_angle=value['axisAngle']
    if value['mode']=='QUATERNION':obj.rotation_quaternion=value['quaternion']
    elif value['mode']=='AXIS_ANGLE':obj.rotation_axis_angle=value['axisAngle']
    else:obj.rotation_euler=value['euler']
    obj.delta_location=value['deltaLocation'];obj.delta_scale=value['deltaScale']
    obj.delta_rotation_quaternion=value['deltaQuaternion'];obj.delta_rotation_euler=value['deltaEuler']
    if value['mode']=='QUATERNION':obj.delta_rotation_quaternion=value['deltaQuaternion']

def _normal_corner_keys(positions,uvs,materials):
    """Vectorized exact oriented keys; zero signs have no geometric meaning."""
    count=len(positions);width=3*(3+2*uvs.shape[1])
    if count*(width*4+4)>_snv_MAX_FIELD_BYTES:raise _nfa_AdapterError('Source triangle key field including material IDs exceeds64MiB before allocation')
    if count*9*8>_snv_MAX_FIELD_BYTES:raise _nfa_AdapterError('Float64 triangle geometric field exceeds64MiB before allocation')
    positions=np.asarray(positions,np.float32).copy();uvs=np.asarray(uvs,np.float32).copy()
    positions[positions==0]=0;uvs[uvs==0]=0
    p=positions.astype(np.float64)
    if np.any(np.linalg.norm(np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]),axis=1)<=0):raise _nfa_AdapterError('Degenerate source triangle cannot bind normal import')
    corners=np.concatenate((positions,uvs.transpose((0,2,1,3)).reshape((count,3,-1))),axis=2)
    first=np.lexsort(tuple(corners[:,:,i] for i in reversed(range(corners.shape[2]))),axis=1)[:,0]
    order=(first[:,None]+np.arange(3))%3
    canonical=corners[np.arange(count)[:,None],order].reshape((count,width)).copy()
    dtype=np.dtype([('corners',np.uint32,(width,)),('material',np.int32)])
    keys=np.empty(count,dtype);keys['corners']=canonical.view(np.uint32);keys['material']=materials
    raw=keys.view(np.dtype(('V',keys.dtype.itemsize))).reshape(-1)
    if len(np.unique(raw))!=count:raise _nfa_AdapterError('Ambiguous source oriented triangle/POS/UV/material ownership')
    return raw,order

def _normal_source_geometry(obj,reader,*,preexport=False):
    """Every selected mesh is source-bound before a zero-free skip."""
    mesh=obj.data
    if obj.type!='MESH' or obj.mode!='OBJECT' or obj.modifiers or obj.constraints or obj.animation_data or mesh.shape_keys or mesh.animation_data or mesh.use_fake_user:
        raise _nfa_AdapterError('Only static applied imported meshes are eligible')
    totals=_nfa_field(mesh.polygons,'loop_total',np.int32,1).reshape(-1)
    starts=_nfa_field(mesh.polygons,'loop_start',np.int32,1).reshape(-1)
    if np.any(totals!=3) or not np.array_equal(starts,np.arange(len(starts))*3):raise _nfa_AdapterError('Consecutive native source triangles required')
    names=[mat.get('name') for mat in reader.document.get('materials',[])]
    if any(not isinstance(name,str) or not name for name in names) or len(set(names))!=len(names):raise _nfa_AdapterError('Ambiguous stored material identity')
    native_material=[]
    material_ids={name:i for i,name in enumerate(names)}
    for polygon in mesh.polygons:
        material=mesh.materials[polygon.material_index] if mesh.materials else None
        if material is not None and material.name not in material_ids:raise _nfa_AdapterError('Native material is not source-bound')
        native_material.append(material_ids[material.name] if material else -1)
    ni=_nfb_node_index(reader,obj.name)
    mesh_id=_snv_integer(reader.document['nodes'][ni]['mesh'],'source mesh ownership index',0,len(reader.document['meshes'])-1)
    source_mesh=reader.document['meshes'][mesh_id]
    source_positions=[];source_uvs=[];source_material=[];source_normals=[];normal_payloads=[];layer_counts=[];triangle_count=0;primitive_ranges=[]
    for pi,primitive in enumerate(source_mesh['primitives']):
        attrs=primitive['attributes'];indices=reader.accessor(primitive['indices'],'index',1).reshape((-1,3))
        layers=1 if 'TEXCOORD_0' in attrs else 0
        primitive_ranges.append((pi,triangle_count*3,len(indices)*3));triangle_count+=len(indices)
        if triangle_count*(3*(3+2*layers)*4+4)>_snv_MAX_FIELD_BYTES:raise _nfa_AdapterError('Expanded source corner/key field including material IDs exceeds64MiB before allocation')
        position=reader.accessor(attrs['POSITION'],'float',3).copy()
        normal=reader.accessor(attrs['NORMAL'],'float',3)
        normal_payloads.append({'primitive':pi,'accessor':attrs['NORMAL'],'rows':len(normal),'f32PayloadSha256':_nfa_digest(normal)})
        normal=normal[:,[0,2,1]].copy();normal[:,1]*=np.float32(-1);source_normals.append(normal[indices])
        if not preexport:position=position[:,[0,2,1]].copy();position[:,1]*=np.float32(-1)
        material=_snv_integer(primitive['material'],'source material ownership index',0,len(names)-1) if 'material' in primitive else -1
        source_positions.append(position[indices]);source_material.extend([material]*len(indices))
        layer_counts.append(layers)
        if layers:
            uv=reader.accessor(attrs['TEXCOORD_0'],'float',2).copy()
            if not preexport:uv[:,1]=np.float32(1)-uv[:,1]
            if len(uv)!=len(position):raise _nfa_AdapterError('Stored UV/POS cardinality differs')
            source_uvs.append(uv[indices][:,None,:,:])
        else:source_uvs.append(np.empty((len(indices),0,3,2),np.float32))
    if not source_positions or len(set(layer_counts))!=1 or layer_counts[0]!=len(mesh.uv_layers):raise _nfa_AdapterError('Native and stored nonempty UV/primitive inventory differs')
    source_positions=np.concatenate(source_positions);source_uvs=np.concatenate(source_uvs)
    vertices=_nfa_field(mesh.vertices,'co',np.float32,3)
    loop_vertices=_nfa_field(mesh.loops,'vertex_index',np.int32,1).reshape(-1)
    native_positions=vertices[loop_vertices].reshape((-1,3,3))
    native_uvs=np.empty((len(mesh.polygons),len(mesh.uv_layers),3,2),np.float32)
    for index,layer in enumerate(mesh.uv_layers):native_uvs[:,index]=_nfa_field(layer.data,'uv',np.float32,2).reshape((-1,3,2))
    if preexport:
        native_positions=native_positions[:,:,[0,2,1]].copy();native_positions[:,:,2]*=np.float32(-1)
        native_uvs=native_uvs.copy();native_uvs[:,:,:,1]=np.float32(1)-native_uvs[:,:,:,1]
    if source_positions.shape!=native_positions.shape:raise _nfa_AdapterError('Native and stored triangle inventory differs')
    expected,source_order=_normal_corner_keys(source_positions,source_uvs,np.asarray(source_material,np.int32))
    actual,native_order=_normal_corner_keys(native_positions,native_uvs,np.asarray(native_material,np.int32))
    if not np.array_equal(np.sort(actual),np.sort(expected)):raise _nfa_AdapterError('Native oriented triangle/POS/UV/material differs from immutable source')
    source_sorted=np.argsort(expected);native_sorted=np.argsort(actual)
    normals=np.concatenate(source_normals);targets=np.empty_like(normals);mapping=np.empty((len(expected),3),np.int32)
    targets[native_sorted[:,None],native_order[native_sorted]]=normals[source_sorted[:,None],source_order[source_sorted]]
    ordinals=np.arange(len(expected)*3,dtype=np.int32).reshape((-1,3))
    mapping[native_sorted[:,None],native_order[native_sorted]]=ordinals[source_sorted[:,None],source_order[source_sorted]]
    return ({'triangles':len(expected),'indexedCorners':len(expected)*3,'sourceOrientedCornerKeysSha256':hashlib.sha256(np.sort(expected).tobytes()).hexdigest(),
        'nativeOrientedCornerKeysSha256':hashlib.sha256(np.sort(actual).tobytes()).hexdigest(),
        'sourceNORMALAccessorPayloads':normal_payloads,'sourceNormalMappedF32Sha256':_nfa_digest(targets),
        'allSelectedGeometryAndCornerOwnershipBound':True,'signedCoordinateZeroIgnoredForGeometryOnly':True},targets.reshape((-1,3)),mapping.reshape(-1),primitive_ranges)

def _normal_dispose_plan(plan):
    """Track owned object and mesh separately across partial scratch disposal."""
    obj=plan['candidate']
    if obj is not None:
        try:pointer=obj.as_pointer()
        except ReferenceError:pointer=0
        if pointer:bpy.data.objects.remove(obj,do_unlink=True)
        plan['candidate']=None
    mesh=plan['ownedMesh']
    try:pointer=mesh.as_pointer()
    except ReferenceError:pointer=0
    if pointer and mesh.users-int(mesh.use_fake_user)==0:bpy.data.meshes.remove(mesh)

def _normal_raw_mesh_state(mesh):
    """Actual retained raw Mesh bytes, independent of its former object users."""
    attrs={}
    for attr in mesh.attributes:
        if attr.data_type not in _nfa_TYPES or attr.domain not in ('POINT','EDGE','FACE','CORNER'):raise _nfa_AdapterError('Unsupported raw mesh attribute/domain')
        prop,dtype,width=_nfa_TYPES[attr.data_type]
        attrs[attr.name]={'domain':attr.domain,'type':attr.data_type,'sha256':_nfa_digest(_nfa_field(attr.data,prop,dtype,width))}
    return {'name':mesh.name,'fakeUser':mesh.use_fake_user,'attrs':attrs,
        'coords':_nfa_digest(_nfa_field(mesh.vertices,'co',np.float32,3)),
        'edges':_nfa_digest(_nfa_field(mesh.edges,'vertices',np.int32,2)),
        'loopVertices':_nfa_digest(_nfa_field(mesh.loops,'vertex_index',np.int32,1)),
        'loopEdges':_nfa_digest(_nfa_field(mesh.loops,'edge_index',np.int32,1)),
        'starts':_nfa_digest(_nfa_field(mesh.polygons,'loop_start',np.int32,1)),
        'totals':_nfa_digest(_nfa_field(mesh.polygons,'loop_total',np.int32,1)),
        'materials':_nfa_digest(_nfa_field(mesh.polygons,'material_index',np.int32,1)),
        'smooth':_nfa_digest(_nfa_field(mesh.polygons,'use_smooth',np.bool_,1)),
        'seams':_nfa_digest(_nfa_field(mesh.edges,'use_seam',np.bool_,1)),
        'uv':[[u.name,u.active_render,u.active_clone,_nfa_digest(_nfa_field(u.data,'uv',np.float32,2))] for u in mesh.uv_layers],
        'activeUv':mesh.uv_layers.active_index,'slots':[[m.name,m.as_pointer()] if m else None for m in mesh.materials],
        'decoded':_nfa_digest(_nfa_normal(mesh))}

def _normal_state_sha(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()

def _normal_decode_imported(path, imported, api, *, expected_sha256, max_file_bytes, check=None):
    """Selected profile only. Return the SAME object list and explicit ledger."""
    path=Path(path).resolve(strict=True)
    if not isinstance(expected_sha256,str) or not _HASH.fullmatch(expected_sha256):raise _nfa_AdapterError('Exact expected input SHA256 required')
    _snv_integer(max_file_bytes,'normal import input byte bound',1,2147483647)
    reader=_snv_Glb(path,max_file_bytes)
    if hashlib.sha256(reader.raw).hexdigest()!=expected_sha256:raise _nfa_AdapterError('Normal import bytes differ from declared authority')
    _nfb_validate_document(reader)
    mesh_nodes={node['name']:i for i,node in enumerate(reader.document['nodes']) if 'mesh' in node}
    used_meshes={_snv_integer(reader.document['nodes'][index]['mesh'],'declared mesh ownership index',0,len(reader.document['meshes'])-1) for index in mesh_nodes.values()}
    if used_meshes!=set(range(len(reader.document['meshes']))):raise _nfa_AdapterError('Unreferenced source mesh ownership is unsupported')
    if type(imported) is not list or any(obj.type!='MESH' for obj in imported) or len({obj.as_pointer() for obj in imported})!=len(imported) or len({obj.name for obj in imported})!=len(imported) or {obj.name for obj in imported}!=set(mesh_nodes):
        raise _nfa_AdapterError('Every declared source mesh object must appear exactly once')
    before={obj.as_pointer():_nfa_guard(obj) for obj in imported}
    ui={obj.as_pointer():_normal_ui(obj) for obj in imported}
    old_data={obj.as_pointer():obj.data for obj in imported}
    raw_states={mesh.as_pointer():_normal_raw_mesh_state(mesh) for mesh in set(old_data.values())}
    active=bpy.context.view_layer.objects.active
    active_pointer=active.as_pointer() if active else None
    plans=[];rows=[];transferred=[];success=False;node_snapshots={};retained=[];raw_current_states={};batch_budget=_normal_new_batch_budget()
    def checkpoint(stage):
        if check is not None:check(stage)
    def validate_commit():
        for mesh in set(old_data.values()):
            current_raw=_normal_raw_mesh_state(mesh);raw_current_states[mesh.as_pointer()]=current_raw
            if current_raw!=raw_states[mesh.as_pointer()]:raise _nfa_AdapterError('Retained raw mesh bytes/decoded fields/fakeUser changed')
        converted={plan['object'].as_pointer():plan for plan in plans}
        for obj in imported:
            pointer=obj.as_pointer()
            if pointer not in converted:
                if obj.data is not old_data[pointer] or _nfa_guard(obj)!=before[pointer]:raise _nfa_AdapterError('COMMIT changed an unconverted imported source object or mesh')
            else:
                plan=converted[pointer];actual=_nfa_guard(obj);expected=plan['guard']
                if obj.data is not plan['ownedMesh'] or obj.data.use_fake_user or {k:v for k,v in actual.items() if k not in ('object','mesh')}!={k:v for k,v in expected.items() if k not in ('object','mesh')}:
                    raise _nfa_AdapterError('Committed working data differs from validated detached candidate')
        actual_active=bpy.context.view_layer.objects.active
        if digest(path)!=expected_sha256 or any(_normal_ui(obj)!=ui[obj.as_pointer()] for obj in imported) or (actual_active.as_pointer() if actual_active else None)!=active_pointer or any(_normal_node_state(row['object'])!=row['state'] for row in node_snapshots.values()):
            raise _nfa_AdapterError('COMMIT changed input file or object/node/UI ownership')
    try:
        # All selected frames/features/geometry are admitted before the first
        # candidate, including every zero-free mesh and ancestor node path.
        for obj in imported:
            checkpoint('normal:before-source:'+obj.name)
            ni=mesh_nodes[obj.name];stored_frame=_nfb_verify_native_frame(obj,reader)
            current=obj;index=ni;depth=0
            while True:
                if current.as_pointer() not in node_snapshots:
                    node_snapshots[current.as_pointer()]={'object':current,'state':_normal_node_state(current),'parent':current.parent,
                        'channels':_normal_transform_channels(current),'parentInverse':current.matrix_parent_inverse.copy()}
                if current.name!=reader.document['nodes'][index]['name'] or current.type not in {'MESH','EMPTY'} or current.constraints or current.animation_data:
                    raise _nfa_AdapterError('Native source node path identity or static features differ')
                conversion=np.eye(4);conversion[:3,:3]=np.asarray(((1,0,0),(0,0,-1),(0,1,0)),np.float64)
                expected_frame=conversion@reader.worlds[index]@conversion.T
                _snv_matrix(np.asarray(current.matrix_world,np.float64),'selected native source node frame')
                if np.max(np.abs(expected_frame-np.asarray(current.matrix_world,np.float64)))>1e-6:raise _nfa_AdapterError('Selected native source ancestor frame differs')
                parent_index=reader.parents.get(index)
                if parent_index is None:
                    if current.parent is not None:raise _nfa_AdapterError('Extra native source parent')
                    break
                if current.parent is None:raise _nfa_AdapterError('Missing native source parent')
                current=current.parent;index=parent_index;depth+=1
                if depth>32:raise _nfa_AdapterError('Native source depth exceeds32')
            geometry,targets,source_mapping,primitive_ranges=_normal_source_geometry(obj,reader)
            values=_nfa_normal(obj.data);zeros=np.flatnonzero(np.linalg.norm(values.astype(np.float64),axis=1)==0).tolist()
            geometry_identity={key:before[obj.as_pointer()][key] for key in ('coords','edges','loopVertices','loopEdges','starts','totals')}
            context=_normal_SourceContext(expected_sha256,obj,stored_frame,targets,values,source_mapping,primitive_ranges,geometry_identity)
            row=_normal_ImportRow({'object':obj.name,'rawMesh':obj.data.name,'sourceInputSha256':expected_sha256,'storedNodeWorld':stored_frame.tolist(),'rawNativeWorld':[list(r) for r in obj.matrix_world],
                'maximumFrameComponentResidual':float(np.max(np.abs(stored_frame-np.asarray(obj.matrix_world,np.float64)))),
                'geometry':geometry,'rawNativeZeroCorners':len(zeros),'rawDecodedSha256':_nfa_digest(values),'converted':False,
                'allCornerLineageRequired':True,'allCornerLineageAvailable':True,'allCornerContextSha256':context.payload_sha,
                'allCornerSourceToRawNative':_normal_all_corner_loss(context,values,obj.matrix_world)})
            row._normal_context=context;rows.append(row)
        if {key[0] for key in reader.cache}!=set(range(len(reader.document.get('accessors',[])))):raise _nfa_AdapterError('Unreferenced or unsupported source accessor ownership')
        for index,(obj,row) in enumerate(zip(imported,rows)):
            if not row['rawNativeZeroCorners']:continue
            checkpoint('normal:before-prepare:'+obj.name)
            binding=_nfb_build_binding(obj,reader,expected_sha256)
            candidate,evidence=_nfa_adapt_copy(obj,binding,expected_input_sha256=expected_sha256,name='_NORMAL_FAN_'+expected_sha256[:10]+'_'+str(index),check=check,batch_budget=batch_budget)
            plan={'object':obj,'candidate':candidate,'ownedMesh':candidate.data};plans.append(plan);plan['guard']=_nfa_guard(candidate)
            _normal_batch_accept(batch_budget,binding['sourceObject'],evidence)
            row.update({'converted':True,'bindingSha256':binding['sha256'],'decoder':evidence,'sourceCornerRecords':binding['scopeCornerRecords']})
        if digest(path)!=expected_sha256 or any(_nfa_guard(obj)!=before[obj.as_pointer()] or _normal_ui(obj)!=ui[obj.as_pointer()] for obj in imported):raise _nfa_AdapterError('PREPARE changed raw imported source identity or UI')
        checkpoint('normal:before-commit')
        for index,plan in enumerate(plans):
            obj=plan['object'];checkpoint('normal:before-commit:'+str(index))
            obj.data=plan['candidate'].data;transferred.append(obj)
            checkpoint('normal:after-commit:'+str(index))
        bpy.context.view_layer.update()
        validate_commit()
        checkpoint('normal:after-commit-guards')
        for obj,row in zip(imported,rows):
            row['workingMesh']=obj.data.name;row['workingDecodedSha256']=_nfa_digest(_nfa_normal(obj.data))
            working_values=_nfa_normal(obj.data)
            row['workingFiniteNonzero']=bool(np.isfinite(working_values).all() and np.all(np.linalg.norm(working_values.astype(np.float64),axis=1)>0))
            if not row['workingFiniteNonzero']:raise _nfa_AdapterError('Selected decoder left native zero directions')
            row._normal_context.validate(row)
            row['allCornerSourceToWorkingNative']=_normal_all_corner_loss(row._normal_context,_nfa_normal(obj.data),obj.matrix_world)
        # All raw meshes remain alive, so even a failure after some scratch
        # objects are disposed can restore every original data binding.
        for index,plan in enumerate(plans):
            checkpoint('normal:before-candidate-cleanup:'+str(index))
            _normal_dispose_plan(plan)
            checkpoint('normal:after-candidate-cleanup:'+str(index))
        validate_commit()
        for mesh in set(old_data.values()):
            owners=[obj for obj in imported if old_data[obj.as_pointer()] is mesh]
            if any(obj.data is not mesh for obj in owners):
                before_sha=_normal_state_sha(raw_states[mesh.as_pointer()]);current_sha=_normal_state_sha(raw_current_states[mesh.as_pointer()])
                retained.append({'name':mesh.name,'currentUsers':mesh.users,'fakeUser':mesh.use_fake_user,
                    'isOrphan':mesh.users==0,'sourceObjects':[before[obj.as_pointer()]['object'] for obj in owners],
                    'beforeRawMeshStateSha256':before_sha,'currentRawMeshStateSha256':current_sha,'rawBytesDecodedFieldsAndFakeUserExact':before_sha==current_sha,
                    'sourceGuardSha256':[_normal_state_sha(before[obj.as_pointer()]) for obj in owners]})
        success=True
    except BaseException:
        for obj in imported:obj.data=old_data[obj.as_pointer()]
        for mesh in set(old_data.values()):
            if mesh.use_fake_user!=raw_states[mesh.as_pointer()]['fakeUser']:mesh.use_fake_user=raw_states[mesh.as_pointer()]['fakeUser']
        for row in node_snapshots.values():
            obj=row['object'];state=row['state']
            if obj.name!=state['name']:obj.name=state['name']
            if obj.parent is not row['parent']:obj.parent=row['parent']
            if not np.array_equal(np.asarray(obj.matrix_parent_inverse),np.asarray(row['parentInverse'])):obj.matrix_parent_inverse=row['parentInverse']
            if _normal_transform_channels(obj)!=row['channels']:_normal_restore_channels(obj,row['channels'])
            if obj.hide_viewport!=state['ui']['hideViewport']:obj.hide_viewport=state['ui']['hideViewport']
            if obj.hide_render!=state['ui']['hideRender']:obj.hide_render=state['ui']['hideRender']
            if obj.hide_get()!=state['ui']['hidden']:obj.hide_set(state['ui']['hidden'])
            if obj.select_get()!=state['ui']['selected']:obj.select_set(state['ui']['selected'])
        actual_active=bpy.context.view_layer.objects.active
        if (actual_active.as_pointer() if actual_active else None)!=active_pointer:bpy.context.view_layer.objects.active=active
        bpy.context.view_layer.update()
        if any(_normal_raw_mesh_state(mesh)!=raw_states[mesh.as_pointer()] for mesh in set(old_data.values())) or any(_nfa_guard(obj)!=before[obj.as_pointer()] or _normal_ui(obj)!=ui[obj.as_pointer()] for obj in imported):raise _nfa_AdapterError('Normal import rollback restored data bindings but raw content was altered externally; no raw-content preservation claim')
        raise
    finally:
        for plan in plans:_normal_dispose_plan(plan)
    report={'contract':_normal_IMPORT_CONTRACT,'method':'stored-corner-fan-v1','inputSha256':expected_sha256,
        'wholeBatchWorkBudget':_normal_batch_summary(batch_budget),
        'selectedMeshes':len(imported),'convertedMeshes':len(plans),'allSelectedFramesAndCornerOwnershipCheckedBeforeZeroSkip':True,
        'prepareRawImportedObjectsAndMeshesUnchanged':True,'commitDeliberatelyRebindsConvertedObjectData':bool(plans),
        'rawImportedMemoryUnchangedAfterCommitClaim':not bool(plans),'immutableFileUnchanged':True,
        'existingObjectNamesParentsFramesAndUiPreserved':True,'ownedCopiesOnlyAndSharedAliasesRetained':True,
        'retainedRawMeshes':retained,'retainedRawOrphanCount':sum(row['isOrphan'] for row in retained),
        'rawRetentionLifetime':'Until the next owned read_factory_settings scene reset (including common.import_glb) or native process exit. No live raw Mesh references are retained in this JSON report.',
        'rawOrphanRetentionIsIntentionalBoundedSourceEvidence':True,'adapterDeletedRawMeshes':False,
        'workingInspectionBaselineMustBeCapturedAfterDecoder':True,'cumulativeOriginalToFinalNativeQualityClaim':False,
        'meshes':rows}
    return imported,report

def _normal_set_preview_visibility(exports):
    """Only actual LOD0 meshes visible in the saved editable native artifact."""
    visible={obj.as_pointer() for obj in exports if obj.get('lodLevel')==0 and not obj.get('collision')}
    if not visible:raise ValueError('Runtime native preview requires explicit LOD0 meshes')
    shown=[];hidden=[]
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH':continue
        show=obj.as_pointer() in visible;obj.hide_set(not show);obj.hide_render=not show
        (shown if show else hidden).append(obj.name)
    return {'visibleLod0':sorted(shown),'hiddenHighAlternateLodsAndColliders':sorted(hidden),'appliedAfterVerifiedFullExport':True}


"""Complete unchanged LOW0 corner ancestry; authored LODs use PRE intent."""
def _normal_direction_error(a,source_world,b,working_world):
    a=np.asarray(a,np.float64);b=np.asarray(b,np.float64)
    if not np.isfinite(a).all() or not np.isfinite(b).all() or np.linalg.norm(a)<=0 or np.linalg.norm(b)<=0:return None
    local=float(np.linalg.norm(a/np.linalg.norm(a)-b/np.linalg.norm(b)))
    aw=a@np.linalg.inv(np.asarray(source_world,np.float64)[:3,:3]);bw=b@np.linalg.inv(np.asarray(working_world,np.float64)[:3,:3])
    return {'local':local,'world':float(np.linalg.norm(aw/np.linalg.norm(aw)-bw/np.linalg.norm(bw)))}

def _normal_capture_low_lineage(pairs,origin_by_part):
    result=[]
    if set(pairs)!=set(origin_by_part):raise _nfa_AdapterError('Every LOW0 requires explicit original-corner ancestry')
    for identity,origin in origin_by_part.items():
        if not isinstance(origin,_normal_ImportRow) or not origin.get('allCornerLineageRequired') or not origin.get('allCornerLineageAvailable') or not hasattr(origin,'_normal_context'):
            raise _nfa_AdapterError('Required complete LOW0 lineage was lost or serialized without private context')
        context=origin._normal_context;context.validate(origin)
        low=pairs[identity][1];guard=_nfa_guard(low)
        if {key:guard[key] for key in context.geometry}!=context.geometry:raise _nfa_AdapterError('LOW0 changed original vertex/edge/face/loop ancestry before export')
        row=_normal_LineageRow({'part':identity,'runtimeObject':low.name,'initialSourceObject':origin['object'],
            'originalInputSha256':context.input_sha,'originalInputWorld':context.source_frame.tolist(),
            'originalCornerContextSha256':context.payload_sha,'allCornerLineageRequired':True,'allCornerLineageAvailable':True,
            'indexedCornerCoverage':len(context.targets),'coverage':'Every indexed corner of geometry-preserved LOW0. Authored LOD/collider directions bind independent PRE-export intent only.',
            'originalToInitialRawNative':origin['allCornerSourceToRawNative'],
            'preExportWorkingWorld':[list(r) for r in low.matrix_world],
            'originalToPreExportWorking':_normal_all_corner_loss(context,_nfa_normal(low.data),low.matrix_world),
            'initialChangedFanLoops':origin['decoder']['changedLoops'] if origin['converted'] else []})
        row._source_context=context;row._pre_object=low;row._pre_working=_normal_readonly(_nfa_normal(low.data),np.float32)
        result.append(row)
    return result

def _normal_bind_verified_lineage(lineage,path,verified_sha,max_file_bytes):
    reader=_snv_Glb(path,max_file_bytes)
    if hashlib.sha256(reader.raw).hexdigest()!=verified_sha:raise _nfa_AdapterError('Final lineage bytes differ from independently verified PRE-context output')
    axis=np.eye(4);axis[:3,:3]=np.asarray(((1,0,0),(0,0,-1),(0,1,0)),np.float64)
    for row in lineage:
        if not isinstance(row,_normal_LineageRow) or not hasattr(row,'_source_context') or row['originalCornerContextSha256']!=row._source_context.fingerprint():
            raise _nfa_AdapterError('Required complete LOW0 lineage is missing or stale')
        info,stored,mapping,ranges=_normal_source_geometry(row._pre_object,reader,preexport=True)
        ni=_nfb_node_index(reader,row['runtimeObject']);frame=axis@reader.worlds[ni]@axis.T
        row['verifiedFinalGlbSha256']=verified_sha;row['actualStoredWorld']=frame.tolist()
        row['preExportToActualStoredCompleteCornerBinding']=info
        row['originalToActualFinalStored']=_normal_all_corner_loss(row._source_context,stored,frame)
        row._stored=_normal_readonly(stored,np.float32);row._working_to_file=_normal_readonly(mapping,np.int32)
        row._reader=reader;row._final_ranges=tuple(ranges);row._pre_object=None
        encoded=_snv_exporter_codec(row._pre_working,_snv_CODEC)
        codec=encoded[:,[0,2,1]].copy();codec[:,1]*=np.float32(-1)
        row['originalToPredictedFinalCodec']=_normal_all_corner_loss(row._source_context,codec,row['preExportWorkingWorld'])
        changed=row['initialChangedFanLoops'];maximum=0.
        for loop in changed:
            error=_normal_direction_error(row._source_context.targets[loop],row['originalInputWorld'],stored[loop],frame)
            if error is None:raise _nfa_AdapterError('Converted LOW0 fan final stored direction is invalid')
            maximum=max(maximum,max(error.values()))
        row['changedFanOnlyMaximumOriginalToActualFinalStoredDirectionalError']=maximum
        row['changedFanOriginalToFinalStoredWithin2e4']=maximum<=2e-4
        if maximum>2e-4:raise _nfa_AdapterError('Original converted LOW0 fan to actual final stored direction exceeds2e-4')

def _normal_read_lineage_native(lineage,objects,phase):
    by_name={obj.name:obj for obj in objects}
    for row in lineage:
        if not isinstance(row,_normal_LineageRow) or not hasattr(row,'_reader') or row._reader is None:raise _nfa_AdapterError('Required verified output corner lineage is unavailable')
        obj=by_name[row['runtimeObject']];_nfb_verify_native_frame(obj,row._reader)
        info,stored,mapping,ranges=_normal_source_geometry(obj,row._reader)
        count=len(mapping)
        if count!=len(row._working_to_file) or not np.array_equal(np.sort(mapping),np.arange(count)):raise _nfa_AdapterError('Final native corner ancestry is incomplete or ambiguous')
        inverse=np.empty(count,np.int32);inverse[mapping]=np.arange(count,dtype=np.int32)
        order=inverse[row._working_to_file]
        if not np.array_equal(stored[order].view(np.uint32),row._stored.view(np.uint32)):raise _nfa_AdapterError('Final native source-normal ancestry differs from verified stored payload')
        values=_nfa_normal(obj.data)[order]
        row['originalTo'+phase+'Native']=_normal_all_corner_loss(row._source_context,values,obj.matrix_world)
        row[phase+'NativeFullCornerBinding']=info
        row[phase+'NativeCornerOrderMapSha256']=_nfa_digest(order)
        maximum=0.;invalid=0
        for loop in row['initialChangedFanLoops']:
            error=_normal_direction_error(row._source_context.targets[loop],row['originalInputWorld'],values[loop],obj.matrix_world)
            if error is None:invalid+=1
            else:maximum=max(maximum,max(error.values()))
        row['changedFanOnlyMaximumOriginalTo'+phase+'NativeDirectionalError']=maximum
        row['invalidChangedFanOriginalTo'+phase+'NativeCorners']=invalid
        row['changedFanOriginalTo'+phase+'NativeWithin2e4']=not invalid and maximum<=2e-4
        if phase=='EffectiveFinal':row._reader=None
    return lineage

def _normal_raw_dcc_diagnostic(expected,obj):
    zeros=int(np.count_nonzero(np.linalg.norm(_nfa_normal(obj.data).astype(np.float64),axis=1)==0))
    with np.errstate(invalid='ignore',divide='ignore'):report=_snv_verify_native_geometry_uv_materials(expected,obj)
    if not math.isfinite(report['dccReencodedNormalComponentDifference']):report['dccReencodedNormalComponentDifference']=None;report['oldStrictNormalPassed']=False
    report.update({'rawNativeZeroCorners':zeros,'invalidNormalComparisonBecauseOfZeroDirections':bool(zeros),'adapterAppliedToThisDiagnostic':False})
    return report


# Static reviewed component-preserving LOD implementation.
_clod_COMPONENT_ATTRIBUTE = 'constrained_lod_original_component'


class _clod_ConstrainedLodError(ValueError):

    def __init__(self, message, report=None):
        super().__init__(message)
        self.report = {} if report is None else report


class _clod_Rejected(ValueError):
    """Measured candidate rejection; operational failures never enter search."""


# Derived from task-local independently authored exact dyadic predicates; no external geometry code.
def _clod_ix_integer_points(points):
    rows = []
    exponent = 0
    for point in points:
        if len(point) != 3:
            raise ValueError('Expected three coordinates')
        row = []
        for value in point:
            value = float(value)
            if not math.isfinite(value):
                raise ValueError('Nonfinite coordinate')
            numerator, denominator = value.as_integer_ratio()
            power = denominator.bit_length() - 1
            exponent = max(exponent, power)
            row.append((numerator, power))
        rows.append(row)
    return ([tuple((n << exponent - e for n, e in row)) for row in rows], exponent)

def _clod_ix_sub(a, b):
    return tuple((x - y for x, y in zip(a, b)))

def _clod_ix_cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

def _clod_ix_dot(a, b):
    return sum((x * y for x, y in zip(a, b)))

def _clod_ix_normal(t):
    return _clod_ix_cross(_clod_ix_sub(t[1], t[0]), _clod_ix_sub(t[2], t[0]))

def _clod_ix_orient2(a, b, c, axes):
    x, y = axes
    return (b[x] - a[x]) * (c[y] - a[y]) - (b[y] - a[y]) * (c[x] - a[x])

def _clod_ix_same_strict_side(values):
    return all((x > 0 for x in values)) or all((x < 0 for x in values))

def _clod_ix_unique(points):
    return list(dict.fromkeys(points))

def _clod_ix_rational(point):
    return tuple((_uvrepair_F(value) for value in point))

def _clod_ix_on_segment(point, a, b):
    direction = _clod_ix_sub(b, a)
    if not any(direction):
        return point == a
    if any(_clod_ix_cross(_clod_ix_sub(point, a), direction)):
        return False
    axis = max(range(3), key=lambda i: abs(direction[i]))
    return min(a[axis], b[axis]) <= point[axis] <= max(a[axis], b[axis])

def _clod_ix_confined_to_shared(points, shared):
    if len(shared) == 1:
        return all((point == shared[0] for point in points))
    if len(shared) == 2:
        return all((_clod_ix_on_segment(point, *shared) for point in points))
    return False

def _clod_ix_plane_cut(triangle, distances):
    out = [_clod_ix_rational(point) for point, distance in zip(triangle, distances) if distance == 0]
    for i, j in ((0, 1), (1, 2), (2, 0)):
        a, b = (distances[i], distances[j])
        if a * b < 0:
            out.append(tuple((_uvrepair_F(a * triangle[j][k] - b * triangle[i][k], a - b) for k in range(3))))
    return _clod_ix_unique(out)

def _clod_ix_strict_inside(point, triangle, triangle_normal):
    drop = max(range(3), key=lambda i: abs(triangle_normal[i]))
    axes = tuple((i for i in range(3) if i != drop))
    signs = [_clod_ix_orient2(triangle[i], triangle[(i + 1) % 3], point, axes) for i in range(3)]
    return _clod_ix_same_strict_side(signs)

def _clod_ix_coplanar_polygon(a, b, n):
    drop = max(range(3), key=lambda i: abs(n[i]))
    axes = tuple((i for i in range(3) if i != drop))
    winding = _clod_ix_orient2(*b, axes)
    polygon = [_clod_ix_rational(point) for point in a]
    for i in range(3):
        if not polygon:
            break
        start, end = (b[i], b[(i + 1) % 3])
        result = []
        previous = polygon[-1]
        old = _clod_ix_orient2(start, end, previous, axes) * (1 if winding > 0 else -1)
        for point in polygon:
            current = _clod_ix_orient2(start, end, point, axes) * (1 if winding > 0 else -1)
            if (old >= 0) != (current >= 0):
                ratio = old / (old - current)
                result.append(tuple((previous[k] + ratio * (point[k] - previous[k]) for k in range(3))))
            if current >= 0:
                result.append(point)
            previous, old = (point, current)
        polygon = _clod_ix_unique(result)
    area2 = sum((p[axes[0]] * q[axes[1]] - p[axes[1]] * q[axes[0]] for p, q in zip(polygon, polygon[1:] + polygon[:1])))
    return (polygon, abs(area2), drop)

def _clod_ix_classify(a, b):
    """Return exact intersection class, never infer adjacency from indices alone."""
    a, b = (tuple(map(tuple, a)), tuple(map(tuple, b)))
    na, nb = (_clod_ix_normal(a), _clod_ix_normal(b))
    if not any(na) or not any(nb):
        return {'kind': 'DEGENERATE_INPUT', 'dimension': None, 'sharedVertices': len(set(a) & set(b))}
    shared = sorted(set(a) & set(b))
    da = [_clod_ix_dot(nb, _clod_ix_sub(point, b[0])) for point in a]
    db = [_clod_ix_dot(na, _clod_ix_sub(point, a[0])) for point in b]
    base = {'sharedVertices': len(shared), 'predicate': 'exact-integer-plane-and-rational-intersection'}
    if _clod_ix_same_strict_side(da) or _clod_ix_same_strict_side(db):
        return dict(base, kind='DISJOINT_PLANE', dimension=-1)
    if not any(da) and (not any(db)):
        polygon, area2, drop = _clod_ix_coplanar_polygon(a, b, na)
        if not polygon:
            return dict(base, kind='DISJOINT_COPLANAR', dimension=-1)
        if area2:
            return dict(base, kind='COPLANAR_POSITIVE_AREA_OVERLAP', dimension=2, intersection=polygon, projectedTwiceArea=area2, projectionDropAxis=drop)
        if _clod_ix_confined_to_shared(polygon, shared):
            return dict(base, kind='SHARED_FEATURE_ONLY', dimension=0 if len(polygon) == 1 else 1, proof='Exact clipped polygon has zero area and lies wholly on the common geometric vertex/edge.')
        return dict(base, kind='COPLANAR_NONSHARED_CONTACT', dimension=0 if len(polygon) == 1 else 1, intersection=polygon)
    if len(shared) == 2:
        return dict(base, kind='SHARED_FEATURE_ONLY', dimension=1, proof='Exact noncoplanar planes share an edge; both triangle-plane slices are exactly that common edge.')
    if len(shared) == 1 and any((_clod_ix_same_strict_side([d for point, d in zip(t, ds) if point != shared[0]]) for t, ds in ((a, da), (b, db)))):
        return dict(base, kind='SHARED_FEATURE_ONLY', dimension=0, proof='The two nonshared vertices are strictly on one side of the opposite plane; its triangle slice is the common point only.')
    line = _clod_ix_cross(na, nb)
    if not any(line):
        raise ArithmeticError('Unresolved exact parallel-plane case')
    axis = max(range(3), key=lambda i: abs(line[i]))
    ca, cb = (_clod_ix_plane_cut(a, da), _clod_ix_plane_cut(b, db))
    if not ca or not cb:
        return dict(base, kind='DISJOINT_PLANE_SLICE', dimension=-1)
    sa, sb = (sorted(ca, key=lambda p: p[axis]), sorted(cb, key=lambda p: p[axis]))
    low = max(sa[0][axis], sb[0][axis])
    high = min(sa[-1][axis], sb[-1][axis])
    if low > high:
        return dict(base, kind='DISJOINT_LINE_INTERVAL', dimension=-1)

    def point_at(value):
        if sa[0][axis] == sa[-1][axis]:
            return sa[0]
        ratio = (value - sa[0][axis]) / (sa[-1][axis] - sa[0][axis])
        return tuple((sa[0][k] + ratio * (sa[-1][k] - sa[0][k]) for k in range(3)))
    points = _clod_ix_unique([point_at(low), point_at(high)])
    if _clod_ix_confined_to_shared(points, shared):
        return dict(base, kind='SHARED_FEATURE_ONLY', dimension=0 if low == high else 1, proof='Exact intersection interval endpoints both lie on the common feature; convexity confines the whole interval.')
    if low == high:
        return dict(base, kind='NONSHARED_POINT_CONTACT', dimension=0, intersection=points)
    midpoint = tuple(((x + y) / 2 for x, y in zip(*points)))
    proper = _clod_ix_strict_inside(midpoint, a, na) and _clod_ix_strict_inside(midpoint, b, nb)
    return dict(base, kind='PROPER_TRANSVERSE_INTERIOR_CROSSING' if proper else 'NONCOPLANAR_NONSHARED_SEGMENT_CONTACT', dimension=1, intersection=points)

_clod_CONTACT_POLICY = 'protected-contact-rings-v1'
_clod_OWNER_ATTRIBUTE = 'opencaw_contact_owner'
_clod_CONTACT_LIMITS = {'inputTriangles':262144,'nodePairs':16777216,'leafPairs':67108864,'exactPairs':16777216}

def _clod_contact_tick(work, kind, cancel=None):
    if cancel is not None and work[kind] % (256 if kind == 'nodePairs' else 64) == 0:cancel()
    if work[kind] >= _clod_CONTACT_LIMITS[kind]:
        raise _clod_ConstrainedLodError('Protected-contact complete-call physical work cap exhausted before operation', {'contactPhysicalWork':dict(work),'contactPhysicalLimits':dict(_clod_CONTACT_LIMITS)})
    work[kind] += 1

def _clod_contact_owners(mesh):
    attribute=mesh.attributes.get(_clod_OWNER_ATTRIBUTE)
    if attribute is None or attribute.domain!='POINT' or attribute.data_type!='INT':raise _clod_ConstrainedLodError('Protected source-owner POINT identity missing')
    return _nfa_field(attribute.data,'value',np.int32,1).reshape(-1)

def _clod_contact_set_owners(mesh, values):
    values=np.asarray(values,np.int32)
    if values.shape!=(len(mesh.vertices),) or np.any(values<0):raise _clod_ConstrainedLodError('Explicit bounded contact owner inventory required')
    attribute=mesh.attributes.get(_clod_OWNER_ATTRIBUTE)
    if attribute is None:attribute=mesh.attributes.new(_clod_OWNER_ATTRIBUTE,'INT','POINT')
    if attribute.domain!='POINT' or attribute.data_type!='INT':raise _clod_ConstrainedLodError('Reserved contact owner attribute collision')
    attribute.data.foreach_set('value',values)
    if _clod_contact_owners(mesh).tobytes()!=values.tobytes():raise _clod_ConstrainedLodError('Native contact owner identity readback differs')

def _clod_contact_face_key(ids):
    ids=tuple(int(x)for x in ids)
    return min(ids,ids[1:]+ids[:1],ids[2:]+ids[:2])

def _clod_contact_cert_sha(cert):
    digest=hashlib.sha256(json.dumps({k:cert[k]for k in ('componentId','negative','coreOwners','uvMetadata','activeUv','materialNames')},sort_keys=True,separators=(',',':')).encode())
    for key in ('ownerIds','positions','faces','materials','uvs'):
        value=cert[key]
        if value.flags.writeable:raise _clod_ConstrainedLodError('Private contact proof arrays became mutable')
        digest.update(key.encode());digest.update(str(value.shape).encode());digest.update(value.tobytes())
    return digest.hexdigest()

def _clod_contact_snapshot(reference, component_id, negative=False):
    mesh=reference.data;owners=_clod_contact_owners(mesh);points=_nfa_field(mesh.vertices,'co',np.float32,3)
    if np.any(owners<=0) or len(np.unique(owners))!=len(owners):raise _clod_ConstrainedLodError('Original complete owner identity must be unique and positive')
    normalized=points.copy();normalized[normalized==0]=np.float32(0)
    unused,inverse,counts=np.unique(normalized,axis=0,return_inverse=True,return_counts=True)
    core=np.flatnonzero(counts[inverse]>1);core_set=set(core.tolist())
    faces=[];materials=[];uvs=[];held=set()
    for face in mesh.polygons:
        vi=tuple(face.vertices)
        if len(vi)!=3:raise _clod_ConstrainedLodError('Contact source requires actual triangles')
        if negative or any(index in core_set for index in vi):
            held.update(vi);faces.append(owners[list(vi)]);materials.append(face.material_index)
            uvs.append([[tuple(layer.data[li].uv)for li in face.loop_indices]for layer in mesh.uv_layers])
    held=sorted(held);triangles=np.asarray(faces,np.int32).reshape((-1,3))
    if len({_clod_contact_face_key(row)for row in triangles})!=len(triangles):raise _clod_ConstrainedLodError('Ambiguous duplicate protected source face')
    cert={'componentId':component_id,'negative':bool(negative),'coreOwners':sorted(int(owners[i])for i in core),'uvMetadata':[(u.name,u.active_render,u.active_clone)for u in mesh.uv_layers],
        'activeUv':mesh.uv_layers.active_index,'materialNames':[m.name if m else None for m in mesh.materials],
        'ownerIds':_normal_readonly(owners[held],np.int32),'positions':_normal_readonly(points[held],np.float32),
        'faces':_normal_readonly(triangles,np.int32),'materials':_normal_readonly(materials,np.int32),
        'uvs':_normal_readonly(np.asarray(uvs,np.float32).reshape((len(triangles),len(mesh.uv_layers),3,2)),np.float32)}
    cert['sha256']=_clod_contact_cert_sha(cert)
    return cert

def _clod_contact_summary(cert):
    if _clod_contact_cert_sha(cert)!=cert['sha256']:raise _clod_ConstrainedLodError('Stale private contact certificate')
    return {'method':_clod_CONTACT_POLICY,'certificateSha256':cert['sha256'],'componentId':cert['componentId'],'negativeExactRetention':cert['negative'],
        'coincidentCoreOwners':len(cert['coreOwners']),'protectedOwnerVertices':len(cert['ownerIds']),'protectedTriangles':len(cert['faces']),
        'positionsSha256':hashlib.sha256(cert['positions'].tobytes()).hexdigest(),'originalOwnerIdsSha256':hashlib.sha256(cert['ownerIds'].tobytes()).hexdigest(),
        'protectedWindingMaterialUvBitExactRequired':True,'coordinateOnlyOwnerMatchingUsed':False}

def _clod_contact_verify(mesh, cert, *, decoded_file_uv=False):
    if _clod_contact_cert_sha(cert)!=cert['sha256']:raise _clod_ConstrainedLodError('Altered private contact proof')
    owners=_clod_contact_owners(mesh);expected_ids=set(int(x)for x in cert['ownerIds']);positions={}
    for i,owner in enumerate(owners):
        if int(owner)in expected_ids:
            if int(owner)in positions:raise _clod_Rejected('Protected source owner duplicated/merged by derivative')
            positions[int(owner)]=np.asarray(tuple(mesh.vertices[i].co),np.float32)
    if set(positions)!=expected_ids:raise _clod_Rejected('Protected original owner omitted')
    for owner,point in zip(cert['ownerIds'],cert['positions']):
        actual=positions[int(owner)]
        if decoded_file_uv:
            if not np.array_equal(actual,point):raise _clod_Rejected('Protected native source-owned position changed after declared axis decode')
        elif actual.tobytes()!=point.tobytes():raise _clod_Rejected('Protected F32 owner position changed')
    if len(cert['faces'])and len(mesh.uv_layers)!=len(cert['uvMetadata']):raise _clod_Rejected('Protected UV layer inventory changed')
    if len(cert['faces'])and not decoded_file_uv and ([(u.name,u.active_render,u.active_clone)for u in mesh.uv_layers]!=cert['uvMetadata']or mesh.uv_layers.active_index!=cert['activeUv']):raise _clod_Rejected('Protected UV metadata changed')
    expected={_clod_contact_face_key(row):i for i,row in enumerate(cert['faces'])};found=set();core=set(cert['coreOwners'])
    for face in mesh.polygons:
        ids=tuple(int(owners[v])for v in face.vertices)
        if len(ids)!=3:raise _clod_Rejected('Contact derivative has nontriangle polygon')
        key=_clod_contact_face_key(ids)
        if key not in expected:
            if any(owner in core for owner in ids)or cert['negative']and any(owner in expected_ids for owner in ids):raise _clod_Rejected('Contact owner gained an unreviewed incident triangle')
            continue
        if key in found:raise _clod_Rejected('Protected triangle duplicated')
        found.add(key);i=expected[key];old=tuple(int(x)for x in cert['faces'][i]);shift=next(k for k in range(3)if ids[k:]+ids[:k]==old)
        if decoded_file_uv:
            material=mesh.materials[face.material_index].name if mesh.materials else None
            target=cert['materialNames'][int(cert['materials'][i])]if cert['materialNames']else None
            if material!=target:raise _clod_Rejected('Protected material identity changed on decoded derivative')
        elif face.material_index!=int(cert['materials'][i]):raise _clod_Rejected('Protected material slot changed')
        for layer_index,layer in enumerate(mesh.uv_layers):
            current=np.asarray([tuple(layer.data[li].uv)for li in face.loop_indices],np.float32);current=np.roll(current,-shift,axis=0)
            target=cert['uvs'][i,layer_index]
            if decoded_file_uv:
                target=target.copy();target[:,1]=np.float32(1)- (np.float32(1)-target[:,1])
            if current.tobytes()!=target.tobytes():raise _clod_Rejected('Protected corner UV changed outside declared exact file/decode representation')
    if found!=set(expected):raise _clod_Rejected('Protected full triangle/winding omitted or changed')
    return dict(_clod_contact_summary(cert),actualVerified=True,workingUVBitExact=not decoded_file_uv,declaredFileDecodedUvExact=decoded_file_uv,signedCoordinateZeroIgnoredForDecodedGeometryOnly=decoded_file_uv)

def _clod_contact_uv_snapshot(mesh):
    owners=_clod_contact_owners(mesh);held=set();records=[]
    for (a,b),sides in _clod_edge_records(mesh).items():
        if len(sides)!=2:raise _clod_ConstrainedLodError('Owner-bound UV source must be closed')
        if sides[0]!=sides[1]:
            held.update((a,b));oa,ob=int(owners[a]),int(owners[b])
            if oa>ob:oa,ob=ob,oa;sides=[(mat,tuple(raw[8:]+raw[:8]for raw in values))for mat,values in sides]
            records.append(((oa,ob),sorted((mat,[raw.hex()for raw in values])for mat,values in sides)))
    return {'vertices':sorted(held),'ownerPositions':{int(owners[v]):_clod_point_key(mesh.vertices[v]).hex()for v in held},'edges':sorted(records),
        'positions':[_clod_point_key(mesh.vertices[v]).hex()for v in held],'uvMetadata':[(u.name,u.active_render,u.active_clone)for u in mesh.uv_layers],'activeUv':mesh.uv_layers.active_index}

def _clod_contact_uv_verify(mesh, before):
    owners=_clod_contact_owners(mesh);actual_positions={};actual=[]
    for i,owner in enumerate(owners):
        if int(owner)in before['ownerPositions']:
            if int(owner)in actual_positions:raise _clod_Rejected('UV-held original owner duplicated')
            actual_positions[int(owner)]=_clod_point_key(mesh.vertices[i]).hex()
    for (a,b),sides in _clod_edge_records(mesh).items():
        if len(sides)!=2:raise _clod_Rejected('Owner UV candidate no longer closed')
        if sides[0]!=sides[1]:
            oa,ob=int(owners[a]),int(owners[b])
            if oa<=0 or ob<=0:raise _clod_Rejected('Derivative created unowned UV/material boundary')
            if oa>ob:oa,ob=ob,oa;sides=[(mat,tuple(raw[8:]+raw[:8]for raw in values))for mat,values in sides]
            actual.append(((oa,ob),sorted((mat,[raw.hex()for raw in values])for mat,values in sides)))
    if actual_positions!=before['ownerPositions']or sorted(actual)!=before['edges']or [(u.name,u.active_render,u.active_clone)for u in mesh.uv_layers]!=before['uvMetadata']or mesh.uv_layers.active_index!=before['activeUv']:raise _clod_Rejected('Original owner-bound complete UV/material boundary changed')
    return {'sourceOwnerPositionsBothUvSidesAndMaterialExact':True,'heldOwnerVertices':len(actual_positions),'boundarySha256':hashlib.sha256(repr(before).encode()).hexdigest()}

def _clod_contact_trial_owners(candidate, cert, boundary):
    owners=_clod_contact_owners(candidate.data);keep=set(int(x)for x in cert['ownerIds'])
    if boundary is not None:keep.update(boundary['ownerPositions'])
    held=[i for i,owner in enumerate(owners)if int(owner)in keep]
    values=np.asarray([int(owner)if int(owner)in keep else 0 for owner in owners],np.int32)
    _clod_contact_set_owners(candidate.data,values)
    return {'vertices':held}

def _clod_contact_assemble(source, selected, name):
    output=_clod_assemble(source,selected,name)
    try:_clod_contact_set_owners(output.data,np.concatenate([_clod_contact_owners(obj.data)for obj in selected]));return output
    except BaseException:_clod_dispose(output);raise

def _clod_contact_physical(obj, cert, work, cancel=None):
    points=_nfa_field(obj.data.vertices,'co',np.float32,3);faces=_nfa_field(obj.data.loops,'vertex_index',np.int32,1).reshape((-1,3))
    if len(faces)>_clod_CONTACT_LIMITS['inputTriangles']or not np.isfinite(points).all():raise _clod_ConstrainedLodError('Selected contact physical input exceeds fixed finite/triangle support cap')
    integer,exponent=_clod_ix_integer_points(points);triangles=points[faces];low=triangles.min(axis=1);high=triangles.max(axis=1);centers=low.astype(np.float64)+high.astype(np.float64)
    nodes=[]
    def build(indices):
        lo=low[indices].min(axis=0);hi=high[indices].max(axis=0);index=len(nodes);nodes.append(None)
        if len(indices)<=8:nodes[index]=(lo,hi,None,None,indices);return index
        axis=int(np.argmax(hi.astype(np.float64)-lo.astype(np.float64)));ordered=indices[np.lexsort((indices,centers[indices,axis]))];middle=len(ordered)//2
        left,right=build(ordered[:middle]),build(ordered[middle:]);nodes[index]=(lo,hi,left,right,None);return index
    if cancel is not None:cancel()
    root=build(np.arange(len(faces),dtype=np.int32));stack=[(root,root)];owners=_clod_contact_owners(obj.data);protected={_clod_contact_face_key(row)for row in cert['faces']};counts={};checked=0
    while stack:
        _clod_contact_tick(work,'nodePairs',cancel);a,b=stack.pop();na,nb=nodes[a],nodes[b]
        if np.any(na[1]<nb[0])or np.any(nb[1]<na[0]):continue
        if a==b:
            if na[4]is None:stack.extend(((na[2],na[2]),(na[3],na[3]),(na[2],na[3])));continue
            pairs=((int(na[4][i]),int(na[4][j]))for i in range(len(na[4]))for j in range(i+1,len(na[4])))
        elif na[4]is None or nb[4]is None:
            if nb[4]is not None or na[4]is None and float(np.max(na[1]-na[0]))>=float(np.max(nb[1]-nb[0])):stack.extend(((na[2],b),(na[3],b)))
            else:stack.extend(((a,nb[2]),(a,nb[3])))
            continue
        else:pairs=((int(i),int(j))for i in na[4]for j in nb[4])
        for i,j in pairs:
            _clod_contact_tick(work,'leafPairs',cancel)
            if np.any(high[i]<low[j])or np.any(high[j]<low[i]):continue
            _clod_contact_tick(work,'exactPairs',cancel);checked+=1
            result=_clod_ix_classify([integer[v]for v in faces[i]],[integer[v]for v in faces[j]]);kind=result['kind'];counts[kind]=counts.get(kind,0)+1
            if kind.startswith('DISJOINT'):continue
            if kind=='SHARED_FEATURE_ONLY':
                geometric=set(integer[v]for v in faces[i])&set(integer[v]for v in faces[j]);topological=set(int(v)for v in faces[i])&set(int(v)for v in faces[j])
                if len(geometric)==len(topological):continue
                if _clod_contact_face_key(owners[faces[i]])in protected and _clod_contact_face_key(owners[faces[j]])in protected:continue
                kind='NEW_UNREVIEWED_DISTINCT_OWNER_CONTACT'
            error=_clod_Rejected('Exact within-boundary improper intersection: '+kind+' faces='+str((i,j)))
            error.contactPhysical={'kind':kind,'faces':[i,j],'actualF32Triangles':triangles[[i,j]].tolist(),'integerCoordinateScalePowerOfTwo':exponent,'exactPairsThisScan':checked,'completeCallWork':dict(work),'limits':dict(_clod_CONTACT_LIMITS)}
            raise error
    signature=_clod_triangle_signature(obj,include_uv=False)
    return {'method':'exact-f32-dyadic-plane-rational-BVH-v1','completeWithinBoundary':True,'properCrossings':0,'coplanarPositiveArea':0,'unreviewedContact':0,
        'exactPairsThisScan':checked,'classes':counts,'sourceProtectedContactsOnly':True,'geometrySignature':signature,'integerCoordinateScalePowerOfTwo':exponent,
        'completeCallWork':dict(work),'limits':dict(_clod_CONTACT_LIMITS),'crossBoundaryClearanceClaimed':False}


def _clod_contact_check_allowed_owners(candidate, cert, boundary):
    allowed=set(int(x)for x in cert['ownerIds'])
    if boundary is not None:allowed.update(boundary['ownerPositions'])
    values=_clod_contact_owners(candidate.data)
    if np.any(values<0)or any(int(owner)>0 and int(owner)not in allowed for owner in values):
        raise _clod_Rejected('Native collapse invented an unprotected original-owner identity')


def _clod_contact_component_signatures(obj):
    mesh=obj.data;attribute=mesh.attributes.get(_clod_COMPONENT_ATTRIBUTE)
    if attribute is None:raise _clod_ConstrainedLodError('Protected physical lineage absent')
    identities=_nfa_field(attribute.data,'value',np.int32,1).reshape(-1);rows={}
    for face in mesh.polygons:
        ids={int(identities[v])for v in face.vertices}
        if len(ids)!=1:raise _clod_ConstrainedLodError('Physical component lineage merged')
        corners=[np.asarray(tuple(mesh.vertices[v].co),np.float32).tobytes()for v in face.vertices]
        rows.setdefault(ids.pop(),[]).append((face.material_index,min(tuple(corners[k:]+corners[:k])for k in range(3))))
    return {identity:hashlib.sha256(repr(sorted(values)).encode()).hexdigest()for identity,values in rows.items()}


def _clod_contact_require_complete_receipt(document, parts):
    if type(document)is not dict or type(document.get('meshes'))is not list:
        raise ValueError('Protected-contact policy requires an explicit reviewed topology mesh list')
    names={row.get('node')for row in document['meshes']if type(row)is dict and type(row.get('node'))is str}
    if not {part['lowObject']for part in parts}<=names:
        raise ValueError('Protected-contact LOD policy requires complete reviewed LOW ownership coverage during input admission')


def _clod_fields(value, names, label):
    if type(value) is not dict or set(value) != set(names):
        raise _clod_ConstrainedLodError(label + ' requires exactly ' + ', '.join(names))


def _clod_integer(value, low, high, label):
    if type(value) is not int or not low <= value <= high:
        raise _clod_ConstrainedLodError(label + ' must be an explicit bounded integer')
    return value


def _clod_number(value, low, high, label):
    if type(value) not in (int, float) or not math.isfinite(value) or (not low < value <= high):
        raise _clod_ConstrainedLodError(label + ' must be finite and within its explicit bound')
    return float(value)


def _clod_validate_settings(value):
    _clod_fields(value, ('schemaVersion', 'method', 'levels', 'search', 'uvPolicy', 'normalPolicy', 'componentPolicy', 'budgets') + (('contactPolicy',) if type(value) is dict and 'contactPolicy' in value else ()), 'Constrained LOD settings')
    if 'contactPolicy' in value and value['contactPolicy'] != _clod_CONTACT_POLICY:
        raise _clod_ConstrainedLodError('Unknown explicit protected-contact LOD policy')
    if value['schemaVersion'] != 1 or type(value['schemaVersion']) is not int or value['method'] != 'original-component-finite-collapse-v1':
        raise _clod_ConstrainedLodError('Explicit constrained LOD schema1/method required')
    if type(value['levels']) is not list or not 1 <= len(value['levels']) <= 8:
        raise _clod_ConstrainedLodError('One to eight explicit LOD levels required')
    previous = 1.0
    for index, level in enumerate(value['levels'], 1):
        _clod_fields(level, ('level', 'requestedRatio', 'maxVertexSurfaceErrorMetres'), 'LOD level')
        if _clod_integer(level['level'], 1, 8, 'level') != index:
            raise _clod_ConstrainedLodError('LOD levels must be consecutive from1')
        ratio = _clod_number(level['requestedRatio'], 0, 1, 'requestedRatio')
        bound = _clod_number(level['maxVertexSurfaceErrorMetres'], 0, 1, 'maxVertexSurfaceErrorMetres')
        if ratio >= previous:
            raise _clod_ConstrainedLodError('Requested ratios must strictly decrease')
        previous = ratio
    search = value['search']
    _clod_fields(search, ('method', 'intervals', 'includePreviousSelectedRatio', 'terminalRetention'), 'search')
    _clod_integer(search['intervals'], 1, 32, 'search.intervals')
    if search['method'] != 'linear-requested-to-original' or search['includePreviousSelectedRatio'] is not True or search['terminalRetention'] != 'explicit-original-component':
        raise _clod_ConstrainedLodError('Explicit finite grid, previous selection and original terminal policy required')
    if value['uvPolicy'] != {'method': 'supported-material-aware-v1', 'uvIndependent': 'deterministic-unit-grid-triangles', 'uvDependent': 'hard-zero-boundary-both-sides', 'unsupported': 'reject'}:
        raise _clod_ConstrainedLodError('Unsupported or implicit LOD UV policy')
    if value['normalPolicy'] != 'authored-derivative-native-geometric-nonzero':
        raise _clod_ConstrainedLodError('Explicit derivative-authored normal policy required')
    if value['componentPolicy'] not in ('retain-every-original-closed-positive-component-min4', 'retain-every-reviewed-signed-boundary-min4'):
        raise _clod_ConstrainedLodError('Original closed component/min4 policy required')
    _clod_fields(value['budgets'], ('maxLod0Triangles', 'maxPackageTriangles'), 'budgets')
    lod0 = _clod_integer(value['budgets']['maxLod0Triangles'], 4, 8000000, 'maxLod0Triangles')
    total = _clod_integer(value['budgets']['maxPackageTriangles'], 4, 32000000, 'maxPackageTriangles')
    if total < lod0:
        raise _clod_ConstrainedLodError('Complete package budget cannot be smaller than its LOW0 budget')
    return json.loads(json.dumps(value, allow_nan=False))


def _clod_ratio_grid(requested, intervals, previous_ratio=None):
    requested = _clod_number(requested, 0, 1, 'requested ratio')
    _clod_integer(intervals, 1, 32, 'ratio intervals')
    values = [requested + (1.0 - requested) * i / intervals for i in range(intervals + 1)]
    values[-1] = 1.0
    if previous_ratio is not None:
        previous_ratio = _clod_number(previous_ratio, 0, 1, 'previous selected ratio')
        if previous_ratio >= requested:
            values.append(previous_ratio)
    return sorted(set(values))


def _clod_numeric_default(socket):
    if not hasattr(socket, 'default_value'):
        return
    value = socket.default_value
    if isinstance(value, numbers.Number):
        if not math.isfinite(value):
            raise _clod_ConstrainedLodError('Nonfinite material socket default')
    elif value is not None and (not isinstance(value, str)):
        try:
            values = np.asarray(tuple(value), np.float64)
        except (TypeError, ValueError):
            raise _clod_ConstrainedLodError('Unsupported material socket default') from None
        if not np.isfinite(values).all():
            raise _clod_ConstrainedLodError('Nonfinite material vector default')


def _clod_classify_material_dependencies(obj):
    """Conservative supported graph classification over actually used slots.

All nodes in a used material are considered, including export-visible AO
metadata. Unused material slots are copied but do not broaden UV dependency.
No texture-interior or visual equivalence is inferred from this classification.
"""
    if obj.type != 'MESH' or obj.data.color_attributes:
        raise _clod_ConstrainedLodError('Mesh without vertex/corner colors required')
    used = sorted({polygon.material_index for polygon in obj.data.polygons})
    if not used or any((index >= len(obj.data.materials) or obj.data.materials[index] is None for index in used)):
        raise _clod_ConstrainedLodError('Every used polygon requires an explicit material slot')
    uv_names = {layer.name for layer in obj.data.uv_layers}
    reports = []
    dependent = False
    allowed = {'OUTPUT_MATERIAL', 'BSDF_PRINCIPLED', 'TEX_IMAGE', 'UVMAP', 'TEX_COORD', 'NORMAL_MAP', 'SEPRGB', 'SEPARATE_COLOR', 'RGB', 'VALUE', 'MATH', 'MIX_RGB', 'MIX', 'GROUP'}
    for index in used:
        material = obj.data.materials[index]
        tree = material.node_tree
        if not material.use_nodes or tree is None or material.animation_data is not None or (tree.animation_data is not None):
            raise _clod_ConstrainedLodError('Used materials must be static supported node graphs')
        outputs = [node for node in tree.nodes if node.type == 'OUTPUT_MATERIAL']
        principled = [node for node in tree.nodes if node.type == 'BSDF_PRINCIPLED']
        if len(outputs) != 1 or not outputs[0].is_active_output or len(principled) != 1 or (len(outputs[0].inputs['Surface'].links) != 1) or (outputs[0].inputs['Surface'].links[0].from_node != principled[0]) or outputs[0].inputs['Volume'].is_linked or outputs[0].inputs['Displacement'].is_linked:
            raise _clod_ConstrainedLodError('One Principled surface without volume/displacement required')
        shader = principled[0]
        anisotropy = shader.inputs.get('Anisotropic')
        if anisotropy is not None and (anisotropy.is_linked or anisotropy.default_value != 0):
            raise _clod_ConstrainedLodError('Anisotropic material dependency unsupported')
        tangent = shader.inputs.get('Tangent')
        if tangent is not None and tangent.is_linked:
            raise _clod_ConstrainedLodError('Explicit material tangent transport unsupported')
        material_dependent = False
        node_types = []
        for node in tree.nodes:
            node_types.append(node.type)
            if node.type not in allowed or node.mute:
                raise _clod_ConstrainedLodError('Unknown/unsupported used material node: ' + node.type)
            for socket in node.inputs:
                if len(socket.links) > 1:
                    raise _clod_ConstrainedLodError('Ambiguous material input links')
                _clod_numeric_default(socket)
            if node.type == 'TEX_IMAGE':
                image = node.image
                if image is None or image.source != 'FILE' or (not image.packed_file) or (getattr(image, 'animation_data', None) is not None) or (not all(image.size)) or (node.projection != 'FLAT') or (node.extension not in {'REPEAT', 'EXTEND'}) or (node.interpolation not in {'Closest', 'Linear'}):
                    raise _clod_ConstrainedLodError('Only static packed flat regular image texture routes are supported')
                vector = node.inputs['Vector']
                if vector.is_linked:
                    link = vector.links[0]
                    if link.from_node.type != 'UVMAP' and (not (link.from_node.type == 'TEX_COORD' and link.from_socket.name == 'UV')):
                        raise _clod_ConstrainedLodError('Unsupported texture coordinate/transform dependency')
                material_dependent = True
            elif node.type == 'UVMAP':
                if node.from_instancer or (node.uv_map and node.uv_map not in uv_names):
                    raise _clod_ConstrainedLodError('Missing/instanced UV map dependency')
                material_dependent = True
            elif node.type == 'TEX_COORD':
                if any((link.from_socket.name != 'UV' for link in tree.links if link.from_node == node)):
                    raise _clod_ConstrainedLodError('Non-UV generated/object coordinate dependency unsupported')
                material_dependent = True
            elif node.type == 'NORMAL_MAP':
                if node.space != 'TANGENT' or node.inputs['Strength'].is_linked or (node.uv_map and node.uv_map not in uv_names):
                    raise _clod_ConstrainedLodError('Unsupported normal-map dependency')
                material_dependent = True
            elif node.type == 'SEPARATE_COLOR' and node.mode != 'RGB':
                raise _clod_ConstrainedLodError('Unsupported color-channel mode')
            elif node.type == 'MATH':
                if node.operation != 'MULTIPLY' or len([s for s in node.inputs[:2] if s.is_linked]) != 1:
                    raise _clod_ConstrainedLodError('Unsupported scalar material computation')
            elif node.type in {'MIX_RGB', 'MIX'}:
                sockets = node.inputs[1:3] if node.type == 'MIX_RGB' else node.inputs[6:8]
                if node.blend_type != 'MULTIPLY' or (node.type == 'MIX' and node.data_type != 'RGBA') or node.inputs[0].is_linked or (node.inputs[0].default_value != 1) or (len([s for s in sockets if s.is_linked]) != 1):
                    raise _clod_ConstrainedLodError('Unsupported color material computation')
            elif node.type == 'GROUP':
                group = node.node_tree
                inputs = [] if group is None else [item for item in group.interface.items_tree if item.item_type == 'SOCKET' and item.in_out == 'INPUT']
                outputs_group = [] if group is None else [item for item in group.interface.items_tree if item.item_type == 'SOCKET' and item.in_out == 'OUTPUT']
                if group is None or not re.fullmatch('glTF Material Output(?:\\.\\d{3})?', group.name) or group.animation_data is not None or len(group.nodes) or len(group.links) or (len(inputs) != 1) or (inputs[0].name != 'Occlusion') or (inputs[0].socket_type != 'NodeSocketFloat') or outputs_group:
                    raise _clod_ConstrainedLodError('Unknown material group/export dependency')
        parents = {node.as_pointer(): [link.from_node.as_pointer() for link in tree.links if link.to_node == node] for node in tree.nodes}
        visiting, visited = (set(), set())

        def visit(identity):
            if identity in visiting:
                raise _clod_ConstrainedLodError('Cyclic used material dependency graph')
            if identity in visited:
                return
            visiting.add(identity)
            for parent in parents[identity]:
                visit(parent)
            visiting.remove(identity)
            visited.add(identity)
        for identity in parents:
            visit(identity)
        if material_dependent and (not uv_names):
            raise _clod_ConstrainedLodError('UV-dependent material requires retained source UV layers')
        dependent |= material_dependent
        reports.append({'slot': index, 'material': material.name, 'uvDependent': material_dependent, 'nodeTypes': sorted(node_types), 'allNodesConservativelyConsidered': True})
    return {'policy': 'hard-zero-boundary-both-sides' if dependent else 'deterministic-unit-grid-triangles', 'usedMaterialSlots': used, 'materials': reports, 'unusedMaterialSlotsIgnoredForClassification': sorted(set(range(len(obj.data.materials))) - set(used)), 'uvDependencyCertifiedAbsent': not dependent, 'textureInteriorOrAppearanceEquivalenceClaimed': False}


def _clod_triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _clod_dispose(obj):
    if obj is None:
        return
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def _clod_copy(obj, name):
    candidate = obj.copy()
    mesh = None
    try:
        mesh = obj.data.copy()
        candidate.data = mesh
        candidate.name = name
        bpy.context.collection.objects.link(candidate)
        return candidate
    except BaseException:
        bpy.data.objects.remove(candidate, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)
        raise


def _clod_components(mesh):
    parents = list(range(len(mesh.vertices)))

    def find(value):
        while parents[value] != value:
            parents[value] = parents[parents[value]]
            value = parents[value]
        return value
    for edge in mesh.edges:
        a, b = edge.vertices
        parents[find(b)] = find(a)
    groups = {}
    for index in range(len(parents)):
        groups.setdefault(find(index), []).append(index)
    return list(groups.values())


def _clod_coordinate_sha(mesh, vertices):
    rows = sorted((np.asarray(tuple(mesh.vertices[index].co), np.float32).tobytes() for index in vertices))
    return hashlib.sha256(b''.join(rows)).hexdigest()


def _clod_triangle_signature(obj, include_uv=True):
    mesh = obj.data
    mesh.calc_loop_triangles()
    rows = []
    for triangle in mesh.loop_triangles:
        corners = []
        for vi, li in zip(triangle.vertices, triangle.loops):
            values = tuple(mesh.vertices[vi].co)
            if include_uv:
                values += tuple((value for layer in mesh.uv_layers for value in layer.data[li].uv))
            corners.append(np.asarray(values, np.float32).tobytes())
        rows.append((mesh.polygons[triangle.polygon_index].material_index, min((tuple(corners[i:] + corners[:i]) for i in range(3)))))
    return hashlib.sha256(repr(sorted(rows)).encode()).hexdigest()


def _clod_exact_weld(obj):
    before = _clod_triangle_signature(obj)
    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        seen, targets = ({}, {})
        for vertex in bm.verts:
            key = tuple(vertex.co)
            if key in seen:
                targets[vertex] = seen[key]
            else:
                seen[key] = vertex
        if targets:
            bmesh.ops.weld_verts(bm, targetmap=targets)
        bm.to_mesh(obj.data)
    finally:
        bm.free()
    obj.data.update()
    if _clod_triangle_signature(obj) != before:
        raise _clod_ConstrainedLodError('Exact-coordinate derivative weld changed triangle positions/UV/material/winding')
    return len(targets)


def _clod_extract_component(obj, selected, name):
    candidate = _clod_copy(obj, name)
    bm = bmesh.new()
    try:
        bm.from_mesh(candidate.data)
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        selected = set(selected)
        bmesh.ops.delete(bm, geom=[vertex for vertex in bm.verts if vertex.index not in selected], context='VERTS')
        bm.to_mesh(candidate.data)
    except BaseException:
        _clod_dispose(candidate)
        raise
    finally:
        bm.free()
    candidate.data.update()
    return candidate


def _clod_topology(obj, expected_components, *, expected_sign=1):
    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        bm.normal_update()
        areas = [face.calc_area() for face in bm.faces]
        if any((not math.isfinite(area) or area <= 1e-12 for area in areas)):
            raise _clod_Rejected('Derivative face area is nonfinite or at/below unchanged native 1e-12 floor')
        if not bm.faces or any((not e.is_manifold or not e.is_contiguous for e in bm.edges)) or any((not v.is_manifold or not v.link_faces for v in bm.verts)):
            raise _clod_Rejected('Derivative is not closed consistently oriented nondegenerate manifold geometry')
        groups = _clod_components(obj.data)
        if len(groups) != expected_components:
            raise _clod_Rejected('Derivative lost, split or merged original components')
        determinant = float(np.linalg.det(np.asarray(obj.matrix_world, np.float64)[:3, :3]))
        local_volume = float(bm.calc_volume(signed=True))
        world_volume = local_volume * determinant
        if not math.isfinite(world_volume) or world_volume == 0:
            raise _clod_Rejected('Derivative has no finite nonzero world component volume')
        sign = 1 if world_volume > 0 else -1
        if expected_sign is not None and (type(expected_sign) is not int or expected_sign not in (-1, 1) or sign != expected_sign):
            raise _clod_Rejected('Derivative changed its required signed world boundary orientation')
        return {'closedManifold': True, 'consistentlyOriented': True, 'nondegenerate': True, 'components': len(groups), 'triangles': _clod_triangles(obj), 'worldSignedVolume': world_volume, 'worldSignedOrientation': sign, 'minimumLocalFaceArea': min(areas), 'nativeLocalFaceAreaFloor': 1e-12, 'absoluteWholeLowVolumeThresholdReusedForComponents': False}
    finally:
        bm.free()


def _clod_edge_records(mesh):
    records = {}
    for face in mesh.polygons:
        loops = list(face.loop_indices)
        for index, first in enumerate(loops):
            second = loops[(index + 1) % len(loops)]
            a, b = (mesh.loops[first].vertex_index, mesh.loops[second].vertex_index)
            key = tuple(sorted((a, b)))
            if a > b:
                first, second = (second, first)
            side = (face.material_index, tuple((np.asarray((*layer.data[first].uv, *layer.data[second].uv), np.float32).tobytes() for layer in mesh.uv_layers)))
            records.setdefault(key, []).append(side)
    return records


def _clod_point_key(vertex):
    return np.asarray(tuple(vertex.co), np.float32).tobytes()


def _clod_has_coincident_owners(mesh):
    # Only geometric contact classification ignores the sign of zero. Source,
    # UV and boundary evidence retain their original native bits.
    points = _nfa_field(mesh.vertices, 'co', np.float32, 3)
    points[points == 0] = np.float32(0)
    return len(np.unique(points, axis=0)) != len(points)


def _clod_boundary_snapshot(mesh):
    held, records = (set(), [])
    for (a, b), sides in _clod_edge_records(mesh).items():
        if len(sides) != 2:
            raise _clod_ConstrainedLodError('Closed original component edge must own exactly two UV/material sides')
        if sides[0] != sides[1]:
            held.update((a, b))
            points = [_clod_point_key(mesh.vertices[a]), _clod_point_key(mesh.vertices[b])]
            if points[0] > points[1]:
                points.reverse()
                sides = [(mat, tuple((raw[8:] + raw[:8] for raw in values))) for mat, values in sides]
            records.append((tuple((raw.hex() for raw in points)), sorted(((mat, [raw.hex() for raw in values]) for mat, values in sides))))
    return {'vertices': sorted(held), 'positions': sorted((_clod_point_key(mesh.vertices[index]).hex() for index in held)), 'edges': sorted(records), 'uvMetadata': [(u.name, u.active_render, u.active_clone) for u in mesh.uv_layers], 'activeUv': mesh.uv_layers.active_index}


def _clod_verify_boundaries(mesh, before, allow_other_components=False):
    points = {_clod_point_key(vertex).hex() for vertex in mesh.vertices}
    actual = {}
    actual_boundaries = []
    for (a, b), sides in _clod_edge_records(mesh).items():
        if len(sides) != 2:
            raise _clod_Rejected('UV-boundary candidate is no longer closed')
        endpoints = [_clod_point_key(mesh.vertices[a]), _clod_point_key(mesh.vertices[b])]
        if endpoints[0] > endpoints[1]:
            endpoints.reverse()
            sides = [(mat, tuple((raw[8:] + raw[:8] for raw in values))) for mat, values in sides]
        key = tuple((raw.hex() for raw in endpoints))
        if key in actual:
            raise _clod_Rejected('Coincident derivative edges make boundary ownership ambiguous')
        actual[key] = sorted(((mat, [raw.hex() for raw in values]) for mat, values in sides))
        if sides[0] != sides[1]:
            actual_boundaries.append((key, actual[key]))
    if not set(before['positions']) <= points or any((actual.get(tuple(edge)) != sides for edge, sides in before['edges'])) or (not allow_other_components and sorted(actual_boundaries) != before['edges']) or ([(u.name, u.active_render, u.active_clone) for u in mesh.uv_layers] != before['uvMetadata']) or (mesh.uv_layers.active_index != before['activeUv']):
        raise _clod_Rejected('Held position/UV-chart/material boundary or both UV sides changed')
    return {'heldVertices': len(before['vertices']), 'heldEdges': len(before['edges']), 'positionsUvBothSidesMaterialAndMetadataBitExact': True, 'entireComponentBoundarySetExactNoNewSeams': not allow_other_components, 'sourceBoundarySha256': hashlib.sha256(repr(before).encode()).hexdigest()}


def _clod_activate(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _clod_apply_collapse(obj, ratio, boundary):
    _clod_activate(obj)
    modifier = obj.modifiers.new('Constrained original component collapse', 'DECIMATE')
    modifier.decimate_type = 'COLLAPSE'
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    modifier.delimit = set()
    held = [] if boundary is None else boundary['vertices']
    if boundary is not None:
        group = obj.vertex_groups.new(name='Constrained exact-zero UV material boundary')
        group.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
        if held:
            group.add(held, 0.0, 'REPLACE')
        held_set = set(held)
        if any((group.weight(index) != (0.0 if index in held_set else 1.0) for index in range(len(obj.data.vertices)))):
            raise _clod_ConstrainedLodError('Native boundary weight readback differs')
        modifier.vertex_group = group.name
        modifier.vertex_group_factor = 1.0
        modifier.invert_vertex_group = False
    declared = {'type': modifier.decimate_type, 'effectiveRatio': modifier.ratio, 'triangulate': modifier.use_collapse_triangulate, 'delimiterUvProtectionClaimed': False, 'boundaryZeroWeights': len(held), 'vertexGroupFactor': modifier.vertex_group_factor, 'invertVertexGroup': modifier.invert_vertex_group}
    status = bpy.ops.object.modifier_apply(modifier=modifier.name)
    if status != {'FINISHED'}:
        raise _clod_ConstrainedLodError('Native COLLAPSE failed/cancelled; no search fallback: ' + repr(status))
    return declared


def _clod_unit_grid_uv(obj):
    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
    finally:
        bm.free()
    mesh = obj.data
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    layer = mesh.uv_layers.new(name='UVMap')
    grid = math.ceil(math.sqrt(len(mesh.polygons)))
    for index, face in enumerate(mesh.polygons):
        if len(face.loop_indices) != 3:
            raise _clod_Rejected('Deterministic unused-UV authoring requires triangles')
        x, y = (index % grid, index // grid)
        corners = [((x + 0.15) / grid, (y + 0.15) / grid), ((x + 0.85) / grid, (y + 0.15) / grid), ((x + 0.15) / grid, (y + 0.85) / grid)]
        for loop, uv in zip(face.loop_indices, corners):
            layer.data[loop].uv = uv
    return {'method': 'deterministic-unit-grid-triangles', 'grid': grid, 'triangles': len(mesh.polygons), 'sourceUvModified': False, 'unusedDerivativeMetadataExplicitlyAuthored': True, 'clampUsed': False}


def _clod_uv_measure(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    if not mesh.uv_layers:
        raise _clod_Rejected('Selected derivative requires finite nondegenerate unit-tile UV metadata')
    reports = []
    for layer in mesh.uv_layers:
        values = np.empty(len(mesh.loops) * 2, np.float32)
        layer.data.foreach_get('uv', values)
        values = values.reshape((-1, 2))
        if not np.isfinite(values).all() or np.any(values < 0) or np.any(values > 1):
            raise _clod_Rejected('Derivative UVs are nonfinite or outside the unit tile; never clamped')
        for triangle in mesh.loop_triangles:
            a, b, c = values[list(triangle.loops)].astype(np.float64)
            if abs(float(np.cross(b - a, c - a))) <= 0:
                raise _clod_Rejected('Derivative UV triangle is degenerate')
        reports.append({'layer': layer.name, 'loops': len(values), 'unitTile': True, 'nondegenerateTriangles': len(mesh.loop_triangles), 'sha256': hashlib.sha256(values.tobytes()).hexdigest()})
    return reports


def _clod_author_normals(obj):
    mesh = obj.data
    attribute = mesh.attributes.get('custom_normal')
    removed = attribute is not None
    if attribute is not None:
        mesh.attributes.remove(attribute)
    mesh.update()
    values = np.empty(len(mesh.corner_normals) * 3, np.float32)
    mesh.corner_normals.foreach_get('vector', values)
    vectors = values.reshape((-1, 3))
    if len(vectors) != len(mesh.loops) or not np.isfinite(vectors).all() or np.any(np.linalg.norm(vectors.astype(np.float64), axis=1) <= 0):
        raise _clod_Rejected('Authored derivative native geometric normals are nonfinite/zero')
    return {'method': 'native-geometric-from-derivative-smooth-sharp-flags', 'corners': len(vectors), 'inheritedDerivativeCustomCodesRemoved': removed, 'sourceNormalRestorationClaimed': False, 'nonzeroFinite': True, 'sha256': hashlib.sha256(values.tobytes()).hexdigest()}


def _clod_component_attribute(obj, identity):
    attribute = obj.data.attributes.get(_clod_COMPONENT_ATTRIBUTE)
    if attribute is not None:
        obj.data.attributes.remove(attribute)
    attribute = obj.data.attributes.new(_clod_COMPONENT_ATTRIBUTE, 'INT', 'POINT')
    attribute.data.foreach_set('value', np.full(len(obj.data.vertices), identity, np.int32))


def _clod_assemble(source, selected, name):
    points, faces, owners, smooth, uv_values, identities, sharp = ([], [], [], [], [], [], [])
    metadata = [(u.name, u.active_render, u.active_clone) for u in selected[0].data.uv_layers]
    for component in selected:
        mesh = component.data
        if [(u.name, u.active_render, u.active_clone) for u in mesh.uv_layers] != metadata:
            raise _clod_ConstrainedLodError('Derivative component UV metadata differs at assembly')
        offset = len(points)
        points.extend((tuple(vertex.co) for vertex in mesh.vertices))
        attribute = mesh.attributes.get(_clod_COMPONENT_ATTRIBUTE)
        if attribute is None:
            raise _clod_ConstrainedLodError('Original component identity missing before assembly')
        identities.extend((item.value for item in attribute.data))
        for face in mesh.polygons:
            faces.append(tuple((offset + index for index in face.vertices)))
            owners.append(face.material_index)
            smooth.append(face.use_smooth)
            uv_values.append([[tuple(layer.data[loop].uv) for loop in face.loop_indices] for layer in mesh.uv_layers])
        sharp.extend(((tuple((offset + index for index in edge.vertices)), edge.use_edge_sharp, edge.use_seam) for edge in mesh.edges))
    mesh = bpy.data.meshes.new(name + '.mesh')
    obj = None
    try:
        mesh.from_pydata(points, [], faces)
        for material in source.data.materials:
            mesh.materials.append(material)
        for layer_index, (layer_name, render, clone) in enumerate(metadata):
            layer = mesh.uv_layers.new(name=layer_name)
            layer.active_render, layer.active_clone = (render, clone)
            for face, values in zip(mesh.polygons, uv_values):
                for loop, uv in zip(face.loop_indices, values[layer_index]):
                    layer.data[loop].uv = uv
        mesh.uv_layers.active_index = selected[0].data.uv_layers.active_index
        for face, material, use_smooth in zip(mesh.polygons, owners, smooth):
            face.material_index, face.use_smooth = (material, use_smooth)
        edge_flags = {tuple(sorted(vertices)): (held_sharp, seam) for vertices, held_sharp, seam in sharp}
        for edge in mesh.edges:
            edge.use_edge_sharp, edge.use_seam = edge_flags[tuple(sorted(edge.vertices))]
        attribute = mesh.attributes.new(_clod_COMPONENT_ATTRIBUTE, 'INT', 'POINT')
        attribute.data.foreach_set('value', np.asarray(identities, np.int32))
        mesh.update()
        if (_nfa_field(mesh.vertices, 'co', np.float32, 3).tobytes() != np.asarray(points, np.float32).tobytes()
                or _nfa_field(mesh.loops, 'vertex_index', np.int32, 1).tobytes() != np.asarray(faces, np.int32).tobytes()
                or np.any(_nfa_field(mesh.polygons, 'loop_total', np.int32, 1) != 3)):
            raise _clod_ConstrainedLodError('Assembly changed the exact authored indexed component graph')
        obj = source.copy()
        obj.data = mesh
        obj.name = name
        bpy.context.collection.objects.link(obj)
        if obj.name != name:
            raise _clod_ConstrainedLodError('Final derivative identity collision')
        bpy.context.view_layer.update()
        return obj
    except BaseException:
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
        raise


def _clod_verify_lineage(obj, expected_ids):
    attribute = obj.data.attributes.get(_clod_COMPONENT_ATTRIBUTE)
    if attribute is None or attribute.domain != 'POINT' or attribute.data_type != 'INT':
        raise _clod_ConstrainedLodError('Derivative lost its original component identity field')
    found = []
    for vertices in _clod_components(obj.data):
        owners = {attribute.data[index].value for index in vertices}
        if len(owners) != 1:
            raise _clod_ConstrainedLodError('Derivative merged different original component identities')
        found.append(owners.pop())
    if sorted(found) != sorted(expected_ids) or len(set(found)) != len(found):
        raise _clod_ConstrainedLodError('Derivative lost, split, duplicated or invented an original component')
    return found


def _clod_verify_package_budgets(lod0_objects, lod_objects, other_objects, settings, api):
    settings = _clod_validate_settings(settings)
    groups = [list(lod0_objects), list(lod_objects), list(other_objects)]
    objects = sum(groups, [])
    if not groups[0] or len({obj.as_pointer() for obj in objects}) != len(objects) or any((obj.type != 'MESH' for obj in objects)):
        raise _clod_ConstrainedLodError('Complete unique mesh inventory including LOW0 and other exports required')
    counts = [sum((_clod_triangles(obj) for obj in group)) for group in groups]
    if counts[0] > settings['budgets']['maxLod0Triangles'] or sum(counts) > settings['budgets']['maxPackageTriangles']:
        raise _clod_ConstrainedLodError('Complete package exceeds unchanged LOW0/aggregate triangle budgets', {'lod0Triangles': counts[0], 'lodTriangles': counts[1], 'otherTriangles': counts[2], 'packageTriangles': sum(counts), 'budgets': settings['budgets']})
    return {'lod0Triangles': counts[0], 'lodTriangles': counts[1], 'otherTriangles': counts[2], 'packageTriangles': sum(counts), 'budgets': settings['budgets'], 'completeInventoryIsCallerResponsibility': True, 'budgetWaiverUsed': False}


def _clod_build_constrained_lods(low0, settings, api, *, name_prefix=None, component_lineage=None, cancel=None, progress=None, source_topology=None):
    settings = _clod_validate_settings(settings)
    contact_policy = settings.get('contactPolicy') == _clod_CONTACT_POLICY
    if contact_policy and cancel is not None:
        original_cancel=cancel
        def contact_cancel():
            try:original_cancel()
            except _clod_Rejected as error:raise _clod_ConstrainedLodError('Contact cancellation callback aborted') from error
        cancel=contact_cancel
    if contact_policy and source_topology is None:
        raise _clod_ConstrainedLodError('Protected-contact LODs require an actual reviewed source-owner binding for this part')
    if contact_policy:
        import rigid_source_topology
        if type(source_topology) is not rigid_source_topology.Binding:
            raise _clod_ConstrainedLodError('Protected-contact LODs require the actual private reviewed binding type')
    if (settings['componentPolicy'] == 'retain-every-reviewed-signed-boundary-min4') != (source_topology is not None):
        raise _clod_ConstrainedLodError('Signed-boundary LOD policy requires the selected reviewed source-corner binding')
    if bpy.context.mode != 'OBJECT' or low0.type != 'MESH' or low0.modifiers or low0.animation_data or low0.constraints or low0.data.shape_keys:
        raise _clod_ConstrainedLodError('Static object-mode applied LOW0 required')
    prefix = low0.name if name_prefix is None else name_prefix
    if type(prefix) is not str or not re.fullmatch('[A-Za-z0-9][A-Za-z0-9._-]{0,79}', prefix):
        raise _clod_ConstrainedLodError('Safe explicit derivative name prefix required')
    if any((bpy.data.objects.get(prefix + '_LOD' + str(level['level'])) is not None for level in settings['levels'])):
        raise _clod_ConstrainedLodError('Derivative output identities already exist')
    report = {'method': settings['method'], 'settings': settings, 'source': low0.name, 'levels': [], 'sourceLow0Immutable': False, 'sourceNormalRestorationClaimed': False, 'callerNonContactAdmissionRequired': True, 'wholePackageBudgetVerifiedByThisPartBuilder': False, 'runtimeQualityAccepted': False, 'humanApproval': 'not-granted'}
    owned = []
    outputs = []
    successful = False
    contact_initial_names = source_topology.contact_lod_names() if contact_policy else None
    contact_certificates = []
    contact_work = {name:0 for name in ('nodePairs','leafPairs','exactPairs')}
    if contact_policy:
        report['contactPolicy'] = _clod_CONTACT_POLICY
        report['contactPhysicalLimits'] = dict(_clod_CONTACT_LIMITS)
        report['contactPhysicalWork'] = contact_work
    before = _preservation_runtime_state(low0, api)
    selection = [(obj, obj.select_get()) for obj in bpy.context.scene.objects]
    active = bpy.context.view_layer.objects.active

    def checkpoint():
        if cancel is not None:
            cancel()
        if progress is not None:
            progress(report)
    try:
        dependency = _clod_classify_material_dependencies(low0)
        report['materialDependency'] = dependency
        source_count = _clod_triangles(low0)
        if contact_policy and source_count > _clod_CONTACT_LIMITS['inputTriangles']:
            raise _clod_ConstrainedLodError('Protected-contact part exceeds fixed source triangle support cap')
        if source_count > settings['budgets']['maxLod0Triangles']:
            raise _clod_ConstrainedLodError('Part LOW0 alone exceeds the unchanged global LOW0 cap')
        if source_topology is not None:
            welded = source_topology.reindex_copy(low0, sys.modules[__name__], preserve_loops=True)
        else:
            welded = _clod_copy(low0, 'Constrained.WeldedOriginal')
        owned.append(welded)
        if contact_policy:
            _clod_contact_set_owners(welded.data,np.arange(1,len(welded.data.vertices)+1,dtype=np.int32))
        if source_topology is not None:
            api.require_usable(welded, 'reviewed source-owned complete LOW0')
            report['reviewedSourceTopology'] = source_topology.summary()
            report['exactWeldRemovedSeamVertices'] = None
            report['signedBoundaryPolicy'] = 'retain negative boundaries and components with distinct coincident owners internally; reduce other original positive components with existing guards'
        else:
            report['exactWeldRemovedSeamVertices'] = _clod_exact_weld(welded)
        components = sorted(_clod_components(welded.data), key=lambda vertices: (_clod_coordinate_sha(welded.data,vertices),hashlib.sha256(_clod_contact_owners(welded.data)[vertices].tobytes()).hexdigest()) if contact_policy else _clod_coordinate_sha(welded.data,vertices))
        external = None
        if component_lineage is not None:
            if type(component_lineage) is not list:
                raise _clod_ConstrainedLodError('Explicit component lineage must be a list')
            external = {}
            for row in component_lineage:
                _clod_fields(row, ('id', 'coordinateSha256'), 'component lineage')
                if type(row['id']) not in (int, str) or type(row['id']) is bool or type(row['coordinateSha256']) is not str or (not re.fullmatch('[a-f0-9]{64}', row['coordinateSha256'])) or (row['coordinateSha256'] in external) or (row['id'] in external.values()):
                    raise _clod_ConstrainedLodError('Ambiguous/malformed external original component lineage')
                external[row['coordinateSha256']] = row['id']
        references = []
        inventory = []
        for number, vertices in enumerate(components, 1):
            reference = _clod_extract_component(welded, vertices, 'Constrained.OriginalComponent')
            owned.append(reference)
            topology = (_clod_topology(reference, 1) if source_topology is None
                        else _clod_topology(reference, 1, expected_sign=None))
            count = _clod_triangles(reference)
            if count < 4:
                raise _clod_ConstrainedLodError('Original closed component has fewer than four triangles')
            coordinate_sha = _clod_coordinate_sha(welded.data, vertices)
            if external is not None and coordinate_sha not in external:
                raise _clod_ConstrainedLodError('Original component is not in the supplied exact lineage')
            identity = external[coordinate_sha] if external is not None else number
            _clod_component_attribute(reference, number)
            boundary = (_clod_contact_uv_snapshot(reference.data) if contact_policy else _clod_boundary_snapshot(reference.data)) if dependency['policy'] == 'hard-zero-boundary-both-sides' else None
            if contact_policy:
                certificate = _clod_contact_snapshot(reference,number,negative=topology['worldSignedOrientation']<0)
                _clod_contact_verify(reference.data,certificate)
                report['sourcePhysicalInProgress']={'nativeId':number,'coordinateSha256':coordinate_sha}
                certificate['sourcePhysical'] = _clod_contact_physical(reference,certificate,contact_work,cancel)
                contact_certificates.append(certificate)
            references.append((reference, boundary))
            retained_contact = source_topology is not None and _clod_has_coincident_owners(reference.data)
            inventory.append({'nativeId': number, 'sourceComponentId': identity, 'coordinateSha256': coordinate_sha, 'sourceTriangles': count, 'topology': topology,
                              'exactRetentionRequired': topology['worldSignedOrientation'] < 0 or retained_contact and not contact_policy,
                              'hasDistinctOwnersAtCoincidentPositions': retained_contact})
            if contact_policy:
                inventory[-1]['sourceOwnerIdsSha256'] = hashlib.sha256(_clod_contact_owners(reference.data).tobytes()).hexdigest()
                inventory[-1]['protectedContactRing'] = _clod_contact_summary(certificate)
                inventory[-1]['originalWithinBoundaryPhysical'] = certificate['sourcePhysical']
        if external is not None and set(external) != {row['coordinateSha256'] for row in inventory}:
            raise _clod_ConstrainedLodError('Supplied original component lineage is missing/extra')
        report['originalComponents'] = inventory
        report['lineageSource'] = 'caller-bound-exact-component-coordinates' if external is not None else 'LOW0-exact-welded-source-components-only'
        if contact_policy:
            report['signedBoundaryPolicy']='retain every negative boundary exactly; reduce positive surroundings with complete original-owner contact rings held'
            report['lineageSource']='reviewed-source-owner-indexed-components'
        previous_counts = [row['sourceTriangles'] for row in inventory]
        previous_ratios = [None] * len(inventory)
        for level in settings['levels']:
            level_report = {'level': level['level'], 'requestedRatio': level['requestedRatio'], 'maxVertexSurfaceErrorMetres': level['maxVertexSurfaceErrorMetres'], 'components': []}
            report['levels'].append(level_report)
            selected = []
            for index, ((reference, boundary), original) in enumerate(zip(references, inventory)):
                component_report = {'sourceComponentId': original['sourceComponentId'], 'coordinateSha256': original['coordinateSha256'], 'trials': []}
                level_report['components'].append(component_report)
                certificate = contact_certificates[index] if contact_policy else None
                protected_bound = None
                if contact_policy:
                    held_ids=set(int(x)for x in certificate['ownerIds'])
                    if boundary is not None:held_ids.update(boundary['ownerPositions'])
                    protected_bound=max(4,2*len(held_ids)-4)
                    component_report['protectedOwnerReductionBound']={'distinctOriginalOwnerIds':len(held_ids),'minimumTriangles':protected_bound,'coordinateAliasesRemainDistinct':True}
                if boundary is not None:
                    # Exact boundary verification requires every distinct held
                    # float32 point. A closed connected orientable triangular
                    # manifold has F=2V-4+4g, g>=0, and the profile retains min4.
                    protected_positions = len(set(boundary['positions']))
                    protected_bound = max(protected_bound or 0,4,2*protected_positions-4)
                    component_report['protectedPositionReductionBound'] = {
                        'method': 'closed-orientable-triangle-Euler-v1',
                        'distinctProtectedPositions': protected_positions,
                        'minimumTriangles': protected_bound,
                        'originalTriangles': original['sourceTriangles'],
                        'originalClosedPositiveReferenceValidated': original['topology']['worldSignedOrientation'] > 0,
                        'originalClosedConsistentlyOrientedReferenceValidated': True,
                    }
                grid = _clod_ratio_grid(level['requestedRatio'], settings['search']['intervals'], previous_ratios[index])
                component_report['finiteRatioGrid'] = grid
                chosen = None
                for ratio in grid:
                    checkpoint()
                    trial = {'gridRatio': ratio, 'effectiveNativeRatio': max(ratio, 4 / original['sourceTriangles']), 'status': 'running', 'terminalOriginalRetentionCandidate': ratio == 1.0}
                    component_report['trials'].append(trial)
                    candidate = None
                    try:
                        if ratio < 1.0 and original['exactRetentionRequired']:
                            trial['requiredSourceBoundaryRetention'] = {'method': 'reviewed-signed-contact-boundary-retention-v1',
                                'signedOrientation': original['topology']['worldSignedOrientation'],
                                'distinctContactOwners': original['hasDistinctOwnersAtCoincidentPositions'],
                                'nativeInvoked': False, 'candidateCopyInvoked': False}
                            raise _clod_Rejected('Reviewed negative/contact boundary requires exact original retention; no containment-changing reduction')
                        if ratio < 1.0 and trial['effectiveNativeRatio'] >= 1.0:
                            raise _clod_Rejected('Four-triangle component floor prevents reduction; defer to explicit terminal retention')
                        if ratio < 1.0 and protected_bound is not None and protected_bound >= original['sourceTriangles']:
                            trial['noReductionCertificate'] = dict(
                                (component_report['protectedOwnerReductionBound'] if contact_policy else component_report['protectedPositionReductionBound']),
                                nativeInvoked=False,
                                candidateCopyInvoked=False,
                            )
                            raise _clod_Rejected('Exact protected-position Euler bound prevents reduction; defer to explicit original terminal retention')
                        candidate = _clod_copy(reference, 'Constrained.Trial')
                        owned.append(candidate)
                        collapse_boundary = _clod_contact_trial_owners(candidate,certificate,boundary) if contact_policy else boundary
                        if ratio < 1.0:
                            trial['nativeModifier'] = _clod_apply_collapse(candidate, trial['effectiveNativeRatio'], collapse_boundary)
                        trial['topology'] = (_clod_topology(candidate, 1) if source_topology is None
                                             else _clod_topology(candidate, 1, expected_sign=original['topology']['worldSignedOrientation']))
                        count = _clod_triangles(candidate)
                        if count < 4 or count > previous_counts[index] or count > original['sourceTriangles']:
                            raise _clod_Rejected('Component floor/non-increasing original-count constraint failed')
                        if ratio < 1.0 and count == original['sourceTriangles']:
                            raise _clod_Rejected('Native no-reduction result; defer to explicit original terminal retention')
                        if contact_policy:
                            _clod_contact_check_allowed_owners(candidate,certificate,boundary)
                            trial['protectedContactTriangles'] = _clod_contact_verify(candidate.data,certificate)
                            if boundary is not None:trial['boundary'] = _clod_contact_uv_verify(candidate.data,boundary)
                            elif not len(certificate['faces']):trial['unusedDerivativeUvAuthorship'] = _clod_unit_grid_uv(candidate)
                            else:trial['unusedUvRegenerationSuppressedForProtectedTriangles'] = True
                            if ratio == 1.0 and _clod_triangle_signature(candidate,include_uv=False)==certificate['sourcePhysical']['geometrySignature']:
                                trial['withinBoundaryPhysical'] = dict(certificate['sourcePhysical'],reusedExactOriginalGeometry=True)
                            else:trial['withinBoundaryPhysical'] = _clod_contact_physical(candidate,certificate,contact_work,cancel)
                        else:
                            if boundary is not None and not original['hasDistinctOwnersAtCoincidentPositions']:
                                trial['boundary'] = _clod_verify_boundaries(candidate.data, boundary)
                            elif boundary is None:
                                trial['unusedDerivativeUvAuthorship'] = _clod_unit_grid_uv(candidate)
                        if original['exactRetentionRequired'] and _clod_triangle_signature(candidate, include_uv=contact_policy or boundary is not None) != _clod_triangle_signature(reference, include_uv=contact_policy or boundary is not None):
                            raise _clod_Rejected('Reviewed retained signed/contact boundary geometry/material/winding/UV changed')
                        trial['uv'] = _clod_uv_measure(candidate)
                        trial['authoredDerivativeNormals'] = _clod_author_normals(candidate)
                        _clod_verify_lineage(candidate, [original['nativeId']])
                        checkpoint()
                        deviation = api.surface_deviation(reference, candidate)
                        trial['sameOriginalComponentEveryVertexDeviation'] = deviation
                        if any((deviation[direction]['measuredMaximumPlusRepresentationErrorsMetres'] > level['maxVertexSurfaceErrorMetres'] for direction in ('sourceToCandidate', 'candidateToSource'))):
                            raise _clod_Rejected('Two-way all-vertex same-component surface bound failed')
                        trial.update(status='accepted-original-retention' if ratio == 1.0 else 'accepted-reduction', triangles=count, actualRatio=count / original['sourceTriangles'])
                        chosen = candidate
                        component_report.update(selectedGridRatio=ratio, triangles=count, terminalOriginalRetention=ratio == 1.0, terminalReason='All earlier finite candidates rejected' if ratio == 1.0 else None)
                        previous_counts[index], previous_ratios[index] = (count, ratio)
                        selected.append(chosen)
                        checkpoint()
                        break
                    except _clod_Rejected as error:
                        trial.update(status='rejected', reason=str(error))
                        if contact_policy and hasattr(error,'contactPhysical'):trial['withinBoundaryPhysical']=error.contactPhysical
                        if candidate is not None:
                            owned.remove(candidate)
                            _clod_dispose(candidate)
                        checkpoint()
                    except BaseException as error:
                        trial.update(status='aborted-operational-or-cancelled', reason=str(error))
                        raise
                if chosen is None:
                    raise _clod_ConstrainedLodError('Finite grid exhausted without an admissible original component')
            output = (_clod_contact_assemble if contact_policy else _clod_assemble)(low0,selected,prefix+'_LOD'+str(level['level']))
            owned.append(output)
            output['lodLevel'] = level['level']
            output['constrainedLodMethod'] = settings['method']
            if dependency['policy'] == 'deterministic-unit-grid-triangles' and not contact_policy:
                level_report['wholeDerivativeUnusedUvAuthorship'] = _clod_unit_grid_uv(output)
            elif source_topology is None:
                level_report['assembledBoundaryChecks'] = [_clod_verify_boundaries(output.data, boundary, allow_other_components=True) for unused, boundary in references]
            else:
                level_report['assembledBoundaryVerification'] = 'Every complete source-owned component independently verified below; coordinate-only cross-component lookup is not used'
            lineage_ids = _clod_verify_lineage(output, [row['nativeId'] for row in inventory])
            level_report.update(name=output.name, triangles=_clod_triangles(output), topology=_clod_topology(output, len(inventory)), uv=_clod_uv_measure(output), authoredDerivativeNormals=_clod_author_normals(output), originalNativeComponentIdsExactlyOnce=lineage_ids)
            level_report['assembledOriginalComponents'] = []
            attribute = output.data.attributes[_clod_COMPONENT_ATTRIBUTE]
            for original, (reference, boundary), selected_component in zip(inventory, references, selected):
                vertices = [index for index, item in enumerate(attribute.data) if item.value == original['nativeId']]
                final_component = _clod_extract_component(output, vertices, 'Constrained.VerifyAssembledComponent')
                owned.append(final_component)
                try:
                    actual_topology = (_clod_topology(final_component, 1) if source_topology is None
                                       else _clod_topology(final_component, 1, expected_sign=original['topology']['worldSignedOrientation']))
                    selected_signature = _clod_triangle_signature(selected_component, include_uv=contact_policy or boundary is not None)
                    actual_signature = _clod_triangle_signature(final_component, include_uv=contact_policy or boundary is not None)
                    selected_frame = np.asarray(selected_component.matrix_world)
                    actual_frame = np.asarray(final_component.matrix_world)
                    if actual_signature != selected_signature or not np.array_equal(actual_frame, selected_frame):
                        level_report['failedAssembledComponentIdentity'] = {
                            'sourceComponentId': original['sourceComponentId'],
                            'selectedGeometryUvMaterialSignature': selected_signature,
                            'assembledGeometryUvMaterialSignature': actual_signature,
                            'selectedWorld': selected_frame.tolist(), 'assembledWorld': actual_frame.tolist(),
                            'maximumWorldMatrixComponentDifference': float(np.max(np.abs(actual_frame-selected_frame)))}
                        raise _clod_ConstrainedLodError('Assembly changed selected component geometry/material/winding/world ancestry')
                    final_deviation = api.surface_deviation(reference, final_component)
                    if any((final_deviation[direction]['measuredMaximumPlusRepresentationErrorsMetres'] > level['maxVertexSurfaceErrorMetres'] for direction in ('sourceToCandidate', 'candidateToSource'))):
                        raise _clod_ConstrainedLodError('Final assembled component exceeds its same-component world surface bound')
                    contact_check = None
                    contact_uv_check = None
                    if contact_policy:
                        certificate=contact_certificates[original['nativeId']-1]
                        contact_check=_clod_contact_verify(final_component.data,certificate)
                        if boundary is not None:contact_uv_check=_clod_contact_uv_verify(final_component.data,boundary)
                    if contact_policy:
                        uv_sides = contact_uv_check
                    else:
                        uv_sides = None if boundary is None else (
                            {'completeRetainedCornerUvGeometryMaterialSignatureExact': True} if original['hasDistinctOwnersAtCoincidentPositions']
                            else _clod_verify_boundaries(final_component.data, boundary))
                    level_report['assembledOriginalComponents'].append({'sourceComponentId': original['sourceComponentId'], 'topology': actual_topology, 'selectedGeometryMaterialWindingAndWorldFrameExact': True, 'uvSidesExact': uv_sides, 'sameOriginalComponentEveryVertexDeviation': final_deviation})
                    if contact_policy:
                        level_report['assembledOriginalComponents'][-1]['protectedContactTriangles']=contact_check
                        level_report['assembledOriginalComponents'][-1]['withinBoundaryPhysicalReusedByExactSelectedGeometry']=True
                finally:
                    owned.remove(final_component)
                    _clod_dispose(final_component)
            if contact_policy:
                level_report['contactExportReimportProof']=source_topology.remember_contact_lod(output,contact_certificates,[row['trials'][-1]['withinBoundaryPhysical'] for row in level_report['components']],sys.modules[__name__])
            outputs.append(output)
            for component in selected:
                owned.remove(component)
                _clod_dispose(component)
            checkpoint()
        if source_count + sum((_clod_triangles(obj) for obj in outputs)) > settings['budgets']['maxPackageTriangles']:
            raise _clod_ConstrainedLodError('This part alone exceeds the unchanged aggregate package budget')
        _verify_runtime_preservation(before, low0, api, 'Constrained LOD immutable LOW0', exact_world=True)
        report['sourceLow0Immutable'] = True
        report['status'] = 'constrained-original-components-pass'
        report['sourceLow0RawDecodedWorldNormalsPreserved'] = True
        report['localNecessaryBudgetCheck'] = {'lod0Triangles': source_count, 'partWithLodsTriangles': source_count + sum((_clod_triangles(obj) for obj in outputs)), 'wholePackageVerificationStillRequired': True}
        successful = True
        return (outputs, report)
    except BaseException as error:
        report['status'] = 'failed-or-cancelled'
        report['error'] = str(error)
        if contact_policy and hasattr(error,'contactPhysical'):report['contactPhysicalFailure']=error.contactPhysical
        try:
            _verify_runtime_preservation(before, low0, api, 'Failed constrained LOD immutable LOW0', exact_world=True)
            report['sourceLow0Immutable'] = True
        except BaseException as guard_error:
            report['sourceGuardFailure'] = str(guard_error)
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            error.report = report
            raise
        raise _clod_ConstrainedLodError(str(error), report) from error
    finally:
        for obj in reversed(owned):
            if not successful or obj not in outputs:
                _clod_dispose(obj)
        for obj, selected in selection:
            obj.select_set(selected)
        bpy.context.view_layer.objects.active = active
        if contact_policy and not successful:
            source_topology.discard_contact_lods_after(contact_initial_names)


def _clod_write_progress_snapshot(path, payload):
    """Replace only this attempt's progress file after a complete JSON write."""
    pending = path.with_name(path.name + '.pending')
    if pending.exists():
        raise ValueError('Preserved incomplete progress write requires a fresh attempt')
    write_json(pending, payload)
    pending.replace(path)


def _clod_run_for_part(low, part, lod_settings, api, output, source_topology=None):
    evidence = output / ('constrained-lod-search-' + part['id'] + '.json')
    if evidence.exists() or evidence.with_name(evidence.name + '.pending').exists():
        raise ValueError('Fresh constrained LOD search evidence required')
    observed, written, last = 0, 0, None
    contact_names = source_topology.contact_lod_names() if source_topology is not None and lod_settings.get('contactPolicy') == _clod_CONTACT_POLICY else None

    def snapshot(status, report, error=None, helper_available=True):
        nonlocal written
        payload = {
            'schemaVersion': 1, 'status': status, 'sourcePart': part['id'],
            'report': report, 'runtimeQualityAccepted': False,
            'helperReportAvailability': 'provided' if helper_available else 'unavailable',
            'progressReporting': {
                'policy': 'atomic-one-second-progress-v1',
                'minimumIntervalSeconds': 1.0, 'checkpointsObserved': observed,
                'snapshotsWritten': written + 1,
                'completeTerminalReport': status != 'searching' and helper_available,
                'completeTerminalRecord': status != 'searching',
                'hardInterruptionMayLeaveNewerUnwrittenCheckpoints': True,
            },
        }
        if error is not None:
            payload['error'] = str(error)
        _clod_write_progress_snapshot(evidence, payload)
        written += 1

    def checkpoint(report):
        nonlocal observed, last
        observed += 1
        now = time.monotonic()
        if not math.isfinite(now) or last is not None and now < last:
            raise ValueError('Invalid monotonic progress clock')
        if last is None or now - last >= 1.0:
            snapshot('searching', report)
            last = now

    try:
        effective_settings = lod_settings
        if source_topology is not None:
            effective_settings = json.loads(json.dumps(lod_settings, allow_nan=False))
            effective_settings['componentPolicy'] = 'retain-every-reviewed-signed-boundary-min4'
        topology_arguments = {} if source_topology is None else {'source_topology': source_topology}
        lods, report = _clod_build_constrained_lods(
            low, effective_settings, api, name_prefix=part['id'], progress=checkpoint, **topology_arguments)
    except BaseException as error:
        # Geometric/cancellation failures retain the complete available report.
        # An IO failure preserves .pending and the prior complete snapshot;
        # a reporting error propagates rather than claiming terminal success.
        snapshot('failed-or-cancelled', getattr(error, 'report', {}), error, hasattr(error, 'report'))
        raise
    try:
        snapshot('prepared', report)
    except BaseException:
        if contact_names is not None:
            try:
                for lod in lods:
                    _clod_dispose(lod)
            finally:
                source_topology.discard_contact_lods_after(contact_names)
        else:
            for lod in lods:
                _clod_dispose(lod)
        raise
    return lods, report, evidence


def finish_rigid(job, root, source, output, result, recipe, settings, api):
    if "--job" in sys.argv:
        strict_job = strict_json(Path(sys.argv[sys.argv.index("--job")+1]), 4_194_304, 32)
        validate_settings(strict_job.get("finishingSettings"))
        if strict_job != job:
            raise ValueError("Strict current job bytes differ")
    lod_settings = resolve_lod_settings(settings, recipe)
    uv_atlas = resolve_uv_atlas(settings, recipe)
    handoff, prepared, authoring, dependencies = read_inputs(job, root, source, settings)
    original_hash = digest(source)
    source_topology = _source_topology_bindings(root, settings, handoff, prepared)
    prepared_document = inspect_glb(prepared)
    prepared_bytes = prepared.read_bytes()
    prepared_materials = {material["name"]: material_document(prepared_document, prepared_bytes, material)
                          for material in prepared_document.get("materials", [])}
    raw_copy, prepared_copy = output/"source.glb", output/"rigid-source.glb"
    shutil.copyfile(source, raw_copy)
    shutil.copyfile(prepared, prepared_copy)
    imported = import_glb(prepared_copy)
    normal_import_initial=normal_import_final=None
    if 'importNormals' in settings['rigidParts']:
        imported,normal_import_initial=_normal_decode_imported(prepared_copy,imported,api,expected_sha256=handoff['preparedGlbSha256'],max_file_bytes=2147483647)
    parts = handoff["parts"]
    report_by_id,pairs,high_identities,preserve_names,lod0_count = inspect_pairs(handoff,authoring,imported,recipe,settings,api,source_topology)
    topology_by_part = {part['id']: source_topology.get(part['lowObject']) for part in parts}
    owner_uv=lod_settings is not None and lod_settings.get('contactPolicy')=='protected-contact-rings-v1'
    normal_origin_by_part={}
    if normal_import_initial is not None:
        origin_by_name={row['object']:row for row in normal_import_initial['meshes']}
        normal_origin_by_part={part['id']:origin_by_name[pairs[part['id']][1].name] for part in parts}
    for part in parts:
        high,low = pairs[part["id"]]
        # Source GLB can instance HIGH/LOW. Own LOW before any mutation.
        low.data = low.data.copy()
        if part["materialMode"]=="preserve" and not low.data.uv_layers and not owner_uv:
            activate(low)
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(island_margin=recipe["uvMargin"],scale_to_bounds=True)
            bpy.ops.object.mode_set(mode="OBJECT")
        high.name = "SOURCE_HIGH_"+part["id"]
        low.name = "SOURCE_LOW_"+part["id"]
        high.hide_render = low.hide_render = True
    # Free original empty names without moving source data. Runtime part names
    # are deterministic, distinct from source import hierarchy/datablocks.
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            obj.name = "SOURCE_NODE_"+obj.name
    root_object = bpy.data.objects.new("PROOF_TO_MODEL", None)
    bpy.context.collection.objects.link(root_object)
    root_object["profile"] = "articulated"
    root_object["finishingMethod"] = "rigid-parts"
    root_object["sourceRawSha256"] = original_hash
    nodes = {}
    for part in parts:
        node = bpy.data.objects.new(part["id"],None)
        bpy.context.collection.objects.link(node)
        if node.name != part["id"]:
            raise ValueError("Runtime part identity collision")
        node["semanticPart"] = part["id"]
        node["rigidAnchor"] = True
        nodes[part["id"]] = node
    for part in parts:
        node = nodes[part["id"]]
        node.parent = root_object if part["parentId"] is None else nodes[part["parentId"]]
    bpy.context.view_layer.update()
    # Parent transforms must be resolved before assigning a child's world pivot.
    # Handoff order is not a hierarchy order and must not become one implicitly.
    pending = {part["id"]:part for part in parts}
    while pending:
        ready = [identity for identity,part in pending.items() if part["parentId"] not in pending]
        if not ready:
            raise ValueError("Rigid hierarchy cannot be evaluated topologically")
        for identity in ready:
            nodes[identity].matrix_world = Matrix.Translation(pending[identity]["pivot"])
        bpy.context.view_layer.update()
        for identity in ready:
            if np.max(np.abs(np.asarray(nodes[identity].matrix_world)-np.asarray(Matrix.Translation(pending[identity]["pivot"]))))>1e-6:
                raise ValueError("Runtime anchor differs from the declared actual world pivot")
            del pending[identity]
    for part in parts:
        high,low = pairs[part["id"]]
        rebase = rebase_low(low,part["pivot"],nodes[part["id"]],api)
        low.name = part["id"]+"_LOD0"
        low["semanticPart"] = part["id"]
        low["lodLevel"] = 0
        if owner_uv and part['materialMode']=='preserve' and not low.data.uv_layers:
            report_by_id[part['id']]['sourceOwnerUvPacking']=pack_group(
                [low],recipe,part['id'],uv_atlas,source_topology={low.name:topology_by_part[part['id']]})
        report_by_id[part["id"]]["pivotRebaseMaxWorldDriftMetres"] = rebase['maxPositionDriftMetres']
        report_by_id[part["id"]]["pivotRebase"] = rebase
    groups = {}
    for part in parts:
        if part["materialMode"] == "bake":
            groups.setdefault(part["bakeGroup"],[]).append(pairs[part["id"]])
    textures, atlas_reports, atlas_maps = [], [], {}
    for group, members in groups.items():
        if owner_uv:
            group_topology={low.name:topology_by_part[low['semanticPart']] for high,low in members}
            material,maps,packing = bake_group(members,recipe,output,group,api,uv_atlas,source_topology=group_topology)
        else:
            material,maps,packing = bake_group(members,recipe,output,group,api,uv_atlas)
        atlas_maps[material.name] = maps
        textures.extend(value["path"] for value in maps.values())
        atlas_reports.append({"group":group,"material":material.name,"packing":packing,
                              "sourceTargetPairs":[{"high":high.name,"low":low.name} for high,low in members],
                              "maps":{channel:value["measurement"] for channel,value in maps.items()},
                              "normalSpace":"TANGENT","normalAxes":["+X","+Y","+Z"],
                              "cageExtrusion":recipe["cageExtrusion"],"maxRayDistance":recipe["maxRayDistance"],
                              "transport":("globally joined/packed atlas; per-part margin0 HIGH-to-LOW accumulation; all-chart image padding with occupied-pixel verification"
                                           if uv_atlas is not None else "globally joined/packed atlas; exact loop scatter; per-part selected HIGH-to-LOW image accumulation without clearing other parts")})
    exports,collision_sources,collision_expected = [],{},{}
    for part in parts:
        high,low = pairs[part["id"]]
        uv = api.uv_measure(low)
        report = report_by_id[part["id"]]
        report["uv"] = uv
        exports.append(low)
        lods, previous = [], triangles(low)
        if lod_settings is None:
            for level,ratio in enumerate(recipe["lodRatios"],1):
                lod = low.copy()
                lod.data = low.data.copy()
                bpy.context.collection.objects.link(lod)
                lod.name = part["id"]+"_LOD"+str(level)
                lod["lodLevel"] = level
                activate(lod)
                modifier = lod.modifiers.new("Measured rigid LOD","DECIMATE")
                modifier.ratio = ratio
                bpy.ops.object.modifier_apply(modifier=modifier.name)
                count = triangles(lod)
                if not 1 <= count < previous:
                    raise ValueError("Rigid LOD does not reduce actual triangle count")
                previous = count
                api.uv_measure(lod)
                lod.hide_render = True
                exports.append(lod)
                lods.append({"level":level,"ratio":ratio,"triangles":count,"sourcePart":part["id"]})
        else:
            topology_arguments = {} if topology_by_part[part['id']] is None else {'source_topology': topology_by_part[part['id']]}
            constrained_lods, constrained_report, constrained_evidence = _clod_run_for_part(low, part, lod_settings, api, output, **topology_arguments)
            if len(constrained_lods) != len(recipe["lodRatios"]):
                raise ValueError("Constrained LOD output count differs from authoritative recipe")
            for lod, measured, ratio in zip(constrained_lods, constrained_report["levels"], recipe["lodRatios"]):
                level = measured["level"]
                if (lod.name != part["id"]+"_LOD"+str(level) or lod.parent != low.parent
                        or np.max(np.abs(np.asarray(lod.matrix_world)-np.asarray(low.matrix_world)))>1e-6):
                    raise ValueError("Constrained LOD changed exact part name/parent/world pivot frame")
                lod["semanticPart"] = part["id"]
                lod["lodLevel"] = level
                api.uv_measure(lod)
                lod.hide_render = True
                exports.append(lod)
                lods.append({"level":level,"ratio":ratio,"triangles":triangles(lod),"sourcePart":part["id"],
                             "method":lod_settings["method"],"actualOriginalComponentSearch":measured})
            report["constrainedLods"] = constrained_report
            report["constrainedLodEvidence"] = {"path":relative(root,constrained_evidence),"sha256":digest(constrained_evidence)}
        report["lods"] = lods
        if part["collision"]:
            if settings["collision"]["method"] == "kdop-26":
                collision,measured = api.build_kdop26(high,low,settings["collision"],recipe["colliderMaxFaces"])
                reference = np.concatenate((api.world_vertices(high),api.world_vertices(low)),axis=0)
            else:
                collision = low.copy()
                collision.data = low.data.copy()
                collision.data.materials.clear()
                bpy.context.collection.objects.link(collision)
                activate(collision)
                bpy.ops.object.mode_set(mode="EDIT")
                bpy.ops.mesh.select_all(action="SELECT")
                status = bpy.ops.mesh.convex_hull(delete_unused=True,use_existing_faces=False,join_triangles=False)
                bpy.ops.object.mode_set(mode="OBJECT")
                if status != {"FINISHED"} or len(collision.data.polygons)>recipe["colliderMaxFaces"]:
                    raise ValueError("Rigid exact hull did not complete within explicit face limit")
                refinement = api.refine_exact_hull_facets(collision,api.world_vertices(low),recipe["colliderMaxFaces"])
                reference = api.world_vertices(low)
                measured = api.collision_measure(collision,reference)
                measured.update({"method":"exact-hull","constructionRefinement":refinement})
            collision.name = part["id"]+"_COLLISION"
            collision["collision"] = True
            collision["collisionMethod"] = settings["collision"]["method"]
            collision["semanticPart"] = part["id"]
            collision.hide_render = True
            measured.update({"sourcePart":part["id"],"applicable":True,"reason":part["collisionReason"]})
            collision_sources[collision.name] = reference
            collision_expected[collision.name] = measured
            report["collision"] = measured
            exports.append(collision)
        else:
            report["collision"] = {"applicable":False,"reason":part["collisionReason"],"generated":False}
        if api.mesh_identity(high) != high_identities[part["id"]]:
            raise ValueError("Immutable reviewed HIGH geometry changed")
        high.hide_set(True)
        report["immutableHighGeometryPreserved"] = True
    constrained_package_budget = None
    if lod_settings is not None:
        package_lod0 = [pairs[part["id"]][1] for part in parts]
        package_lods = [obj for obj in exports if not obj.get("collision") and obj.get("lodLevel",0)>0]
        package_other = [obj for obj in exports if obj.get("collision")]
        complete_inventory = package_lod0+package_lods+package_other
        if (len(complete_inventory)!=len(exports)
                or {obj.as_pointer() for obj in complete_inventory}!={obj.as_pointer() for obj in exports}):
            raise ValueError("Constrained LOD budget inventory does not cover every actual export exactly once")
        constrained_package_budget = _clod_verify_package_budgets(package_lod0,package_lods,package_other,lod_settings,api)
    total_triangles = sum(triangles(obj) for obj in exports)
    material_count = len({mat for obj in exports for mat in obj.data.materials if mat})
    texture_bytes = sum(path.stat().st_size for path in textures)
    if total_triangles>recipe["maxTriangles"] or material_count>recipe["maxMaterials"] or texture_bytes>recipe["maxTextureBytes"]:
        raise ValueError("Rigid complete package exceeds recipe geometry/material/texture budgets")
    normal_lineage=_normal_capture_low_lineage(pairs,normal_origin_by_part) if normal_import_initial is not None else []
    expected_derivative_lod_names = {obj.name for obj in package_lods} if lod_settings is not None else set()
    expected_geometry = {obj.name:corner_snapshot(obj) for obj in exports if not obj.get("collision")}
    expected_nodes = {node.name:{"parent":node.parent.name,"world":np.asarray(node.matrix_world).copy()} for node in nodes.values()}
    expected_parents = {obj.name:obj.parent.name for obj in exports}
    expected_names = {obj.name for obj in exports}
    expected_bounds = bounds(exports)
    for part in parts:
        pairs[part["id"]][1].hide_render = False
    bpy.ops.object.select_all(action="DESELECT")
    root_object.select_set(True)
    for obj in list(nodes.values())+exports:
        obj.hide_set(False)
        obj.select_set(True)
    glb,blend = output/"asset.glb",output/"asset.blend"
    stored_normal_verification = _snv_export_static_intent(glb, exports, api, settings["rigidParts"]["maxGlbBytes"])
    if glb.stat().st_size>settings["rigidParts"]["maxGlbBytes"]:
        raise ValueError("Rigid GLB exceeds explicit byte budget")
    topology_export_path = topology_export_cache = None
    topology_export_bindings = {}
    if source_topology:
        import rigid_source_topology
        selected_parts = {identity for identity, binding in topology_by_part.items() if binding is not None}
        topology_objects = [obj for obj in exports if not obj.get('collision') and obj.get('semanticPart') in selected_parts]
        current_bindings = {pairs[identity][1].name: topology_by_part[identity] for identity in selected_parts}
        topology_receipt = rigid_source_topology.capture(
            glb, topology_objects, sys.modules[__name__],
            max_file_bytes=settings['rigidParts']['maxGlbBytes'], bindings=current_bindings)
        receipt_bytes = (json.dumps(topology_receipt, allow_nan=False, separators=(',', ':'))+'\n').encode('utf-8')
        if len(receipt_bytes) > 67108864:
            raise ValueError('Generated topology receipt exceeds unchanged64MiB receipt bound')
        topology_export_path = output/'source-topology.json'
        # The output is a normal immutable stage artifact. An identical task-local
        # evidence copy lets the strict receipt loader verify this real export.
        task_prefix = relative_path(job['taskEvidenceRoot'], 'taskEvidenceRoot')
        attempt_key = hashlib.sha256(relative(root, output).encode('utf-8')).hexdigest()
        topology_export_cache = confined(root, task_prefix+'/rigid-topology-exports/'+attempt_key+'.json')
        topology_export_cache.parent.mkdir(parents=True, exist_ok=True)
        for receipt_path in (topology_export_path, topology_export_cache):
            with receipt_path.open('xb') as stream:
                stream.write(receipt_bytes)
        topology_export_bindings = rigid_source_topology.load(
            topology_export_cache, glb,
            {'preparedGlbSha256': stored_normal_verification['glbSha256'],
             'parts': [{'lowObject': obj.name} for obj in topology_objects]},
            sys.modules[__name__], expected_receipt_sha256=digest(topology_export_path),
            max_file_bytes=settings['rigidParts']['maxGlbBytes'])
    contact_export_contexts = {}
    if lod_settings is not None and lod_settings.get('contactPolicy') == _clod_CONTACT_POLICY:
        import rigid_source_topology
        contact_export_contexts = rigid_source_topology.capture_contact_lods(
            glb, package_lods, {part['id']:pairs[part['id']][1] for part in parts}, topology_by_part,
            sys.modules[__name__],max_file_bytes=settings['rigidParts']['maxGlbBytes'])
        if set(contact_export_contexts) != expected_derivative_lod_names:
            raise ValueError('Protected-contact export proof does not cover every actual LOD')
    if normal_import_initial is not None:
        _normal_bind_verified_lineage(normal_lineage,glb,stored_normal_verification['glbSha256'],settings['rigidParts']['maxGlbBytes'])
    document = inspect_glb(glb)
    data = glb.read_bytes()
    output_materials = {mat["name"]:material_document(document,data,mat) for mat in document.get("materials",[])}
    for name in preserve_names:
        if name not in prepared_materials or output_materials.get(name) != prepared_materials[name]:
            raise ValueError("Preserve material/texture/PBR(includingIOR)/emission/alpha intent changed through actual GLB export: "+name)
    packed_bytes = sum(document["bufferViews"][image["bufferView"]]["byteLength"] for image in document.get("images",[]))
    if packed_bytes>recipe["maxTextureBytes"]:
        raise ValueError("Rigid embedded runtime textures exceed recipe byte budget")
    native_preview_visibility=_normal_set_preview_visibility(exports)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    actual = import_glb(glb)
    raw_normal_diagnostics={}
    if normal_import_initial is not None:
        raw_normal_diagnostics={obj.name:_normal_raw_dcc_diagnostic(expected_geometry[obj.name],obj) for obj in actual if obj.name in expected_geometry}
        _normal_read_lineage_native(normal_lineage,actual,'RawFinal')
        actual,normal_import_final=_normal_decode_imported(glb,actual,api,expected_sha256=stored_normal_verification['glbSha256'],max_file_bytes=settings['rigidParts']['maxGlbBytes'])
        _normal_read_lineage_native(normal_lineage,actual,'EffectiveFinal')
    actual_by_name = {obj.name:obj for obj in actual}
    if set(actual_by_name)!=expected_names or sum(triangles(obj) for obj in actual)!=total_triangles:
        raise ValueError("Independent rigid re-import lost mesh/triangle identities")
    actual_nodes = {obj.name:obj for obj in bpy.context.scene.objects if obj.type=="EMPTY"}
    actual_root = actual_nodes.get("PROOF_TO_MODEL")
    if (set(actual_nodes)!=set(expected_nodes)|{"PROOF_TO_MODEL"} or actual_root is None or actual_root.parent is not None
            or np.max(np.abs(np.asarray(actual_root.matrix_world)-np.eye(4)))>1e-6):
        raise ValueError("Independent rigid re-import changed the stationary outer root or node inventory")
    for name,expected_node in expected_nodes.items():
        node = actual_nodes.get(name)
        if (node is None or node.parent is None or node.parent.name!=expected_node["parent"]
                or node.get("semanticPart")!=name or node.get("rigidAnchor")!=True
                or float(np.max(np.abs(np.asarray(node.matrix_world)-expected_node["world"])))>1e-6):
            raise ValueError("Independent rigid re-import lost actual pivots/parent hierarchy")
    reimported = []
    for name,obj in actual_by_name.items():
        if obj.parent is None or obj.parent.name!=expected_parents[name]:
            raise ValueError("Independent rigid re-import changed mesh parent ownership")
        if name in collision_sources:
            expected_collision = collision_expected[name]
            reference = collision_sources[name]
            if expected_collision["method"]=="kdop-26":
                low = actual_by_name[obj["semanticPart"]+"_LOD0"]
                reference = np.concatenate((reference,api.world_vertices(low)),axis=0)
            measured = api.collision_measure(obj,reference)
            if (measured["coplanarFaceGroups"]>recipe["colliderMaxFaces"]
                    or abs(measured["volume"]-expected_collision["volume"])>max(1e-9,expected_collision["volume"]*1e-5)):
                raise ValueError("Independent rigid collision re-import changes cap/volume/containment")
            reimported.append({"name":name,"collision":measured})
        else:
            derivative_face_area = None
            if name in expected_derivative_lod_names:
                derivative_face_area = api.topology_measure(obj)
            api.uv_measure(obj)
            reimported.append({"name":name,"geometryUvMaterials":_snv_verify_native_geometry_uv_materials(expected_geometry[name],obj)})
            if name in topology_export_bindings:
                topology_copy = topology_export_bindings[name].inspection_copy(obj, sys.modules[__name__])
                try:
                    topology_result = api.require_usable(topology_copy, 'independent source-owned rigid export')
                    topology_result['cornerOwnership'] = topology_export_bindings[name].summary()
                    reimported[-1]['reviewedSourceTopology'] = topology_result
                finally:
                    topology_data = topology_copy.data
                    bpy.data.objects.remove(topology_copy, do_unlink=True)
                    bpy.data.meshes.remove(topology_data)
            if derivative_face_area is not None:
                reimported[-1]["constrainedLodNativeFaceAreaFloor"] = derivative_face_area
    if contact_export_contexts:
        import rigid_source_topology
        rows_by_name={row['name']:row for row in reimported}
        for name,context in contact_export_contexts.items():
            low_name=context['sourcePart']+'_LOD0'
            rows_by_name[name]['protectedContactRings']=rigid_source_topology.verify_contact_lod_reimport(
                actual_by_name[name],context,actual_by_name[low_name],topology_export_bindings[low_name],
                topology_export_bindings[name],sys.modules[__name__])
    actual_bounds = bounds(actual)
    if any(abs(actual_bounds[key][axis]-expected_bounds[key][axis])>1e-6 for key in expected_bounds for axis in range(3)):
        raise ValueError("Independent rigid re-import changes package bounds")
    if len({mat for obj in actual for mat in obj.data.materials if mat})!=material_count:
        raise ValueError("Independent rigid re-import lost material assignments")
    reimported_materials = []
    for mat in {mat for obj in actual for mat in obj.data.materials if mat}:
        validate_material(mat)
        if mat.name not in output_materials:
            raise ValueError("Actual re-imported material identity is undeclared")
        reimported_materials.append(verify_imported_material(mat,output_materials[mat.name],atlas_maps.get(mat.name)))
        for node in mat.node_tree.nodes:
            if node.type=="TEX_IMAGE" and any(dimension>recipe["textureSize"] for dimension in node.image.size):
                raise ValueError("Independent rigid texture dimensions exceed declared resolution")
    if digest(source)!=original_hash or digest(raw_copy)!=original_hash or digest(prepared_copy)!=handoff["preparedGlbSha256"]:
        raise ValueError("Immutable raw/prepared sources changed")
    for name,expected_hash in dependencies.items():
        checked_file(root,name,expected_hash)
    report_path = output/"report.json"
    artifacts = {"blend":relative(root,blend),"glb":relative(root,glb),"report":relative(root,report_path),
                 "source":relative(root,raw_copy),"rigidSource":relative(root,prepared_copy)}
    if topology_export_path is not None:
        if digest(topology_export_cache) != digest(topology_export_path):
            raise ValueError('Task-local export topology evidence differs from immutable stage output')
        if set(topology_export_bindings) != {row['name'] for row in reimported if 'reviewedSourceTopology' in row}:
            raise ValueError('Independent source-owned export topology coverage is incomplete')
        artifacts['sourceTopologyReceipt'] = relative(root, topology_export_path)
    artifacts.update({"texture"+str(index):relative(root,path) for index,path in enumerate(textures)})
    measurements = {"triangles":total_triangles,"lod0Triangles":lod0_count,"materials":material_count,
                    "textureBytes":texture_bytes,"embeddedTextureBytes":packed_bytes,"glbBytes":glb.stat().st_size,
                    "parts":[report_by_id[part["id"]] for part in parts],"atlases":atlas_reports}
    if constrained_package_budget is not None:
        measurements["constrainedLodPackageBudget"] = constrained_package_budget
    payload = {"schemaVersion":2,"status":"prepared","artifacts":artifacts,"measurements":measurements,
               "stages":[{"stage":"explicitRigidParts","method":"rigid-parts","inputFrame":handoff["coordinateFrame"],
                          "sourceToPreparedMatrix":handoff["sourceToPreparedMatrix"],"additionalFrameMappingApplied":False,
                          "handoffSha256":settings["rigidParts"]["handoffSha256"],"authoringEvidenceSha256":handoff["authoringEvidenceSha256"]},
                         {"stage":"rigidUvBakeLodCollision","parts":measurements["parts"],"atlases":atlas_reports},
                         {"stage":"storedNormalIntent","verification":stored_normal_verification},
                         {"stage":"independentReimport","verified":True,"meshCount":len(actual),"bounds":actual_bounds,
                          "normalVerificationBoundary":"stored-codec-intent; DCC normal approximation separately reported",
                          "oldStrictDccNormalComparisonPassed":all(row.get("geometryUvMaterials",{}).get("oldStrictNormalPassed",True) for row in reimported),
                          "pivotsAndHierarchy":True,"checks":reimported,"materialChannelsAndPixels":reimported_materials,
                          "preserveMaterialIntentsVerified":sorted(preserve_names)}],
               "inputSha256":original_hash,"preparedInputSha256":handoff["preparedGlbSha256"],
               "rigidHandoffSha256":settings["rigidParts"]["handoffSha256"],"finishingSettings":settings,
               "outputHashes":{relative(root,path):digest(path) for path in [blend,glb,raw_copy,prepared_copy]+textures+([topology_export_path] if topology_export_path is not None else [])},
               "blenderVersion":bpy.app.version_string,"humanApproval":"pending"}
    payload['nativePreviewVisibility']=native_preview_visibility
    if normal_import_initial is not None:
        payload.update({'normalImportInitial':normal_import_initial,'normalImportFinal':normal_import_final,
            'normalImportLow0Lineage':normal_lineage})
        for stage in payload['stages']:
            if stage['stage']=='independentReimport':
                stage['adaptedDccNormalComparisonPassed']=stage['oldStrictDccNormalComparisonPassed']
                stage['oldStrictDccNormalComparisonPassed']=all(row['oldStrictNormalPassed'] for row in raw_normal_diagnostics.values())
                stage['rawNativeDccDiagnostics']=raw_normal_diagnostics
                stage['normalVerificationBoundary']='independent PRE-context stored codec; raw DCC and explicitly selected conversion reported separately'
    write_json(report_path,payload)
    write_json(result,payload)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description='Fixed read-only rigid-parts preflight; not a native finish')
    parser.add_argument('--preflight',action='store_true',required=True)
    parser.add_argument('--job',required=True)
    parser.add_argument('--report',required=True)
    arguments=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else None)
    try:
        preflight(arguments.job,arguments.report)
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
