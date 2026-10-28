"""Auditable static-asset finishing: QuadriFlow, UV/bake, LOD, hull, export/re-import."""
import sys
sys.dont_write_bytecode = True
import json
import hashlib
from itertools import combinations, product
import math
from pathlib import Path
import re
import shutil

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import (activate, bounds, digest, import_glb, inspect_glb, load_job, relative,
                    triangles, write_json)
import bpy
import bmesh
import numpy as np  # Bundled with Blender; no separate installation.
from mathutils import Matrix
from mathutils.bvhtree import BVHTree


def validate_finishing_settings(value):
    """Explicit optional controls; never select a repair or approximation implicitly."""
    if type(value) is dict and value.get("schemaVersion") == 2:
        from rigid_finish import validate_settings
        return validate_settings(value)
    if value is None:
        return {"schemaVersion": 1, "topologyPreparation": {"method": "none"},
                "collision": {"method": "exact-hull"}}
    def integer(value):
        return type(value) in (int, float) and math.isfinite(value) and value == int(value)
    if (type(value) is not dict or not {"schemaVersion", "topologyPreparation", "collision"} <= set(value)
            or set(value) - {"schemaVersion", "topologyPreparation", "collision", "quadriFlow"}
            or not integer(value["schemaVersion"]) or value["schemaVersion"] != 1):
        raise ValueError("finishingSettings requires schemaVersion1, topologyPreparation, collision and optional quadriFlow")
    preparation, collision = value["topologyPreparation"], value["collision"]
    if type(preparation) is not dict or type(collision) is not dict:
        raise ValueError("finishingSettings methods must be explicit objects")
    def number(item, field, minimum, maximum, inclusive=False):
        value = item.get(field)
        if (type(value) not in (int, float) or not math.isfinite(value) or value > maximum
                or (value < minimum if inclusive else value <= minimum)):
            raise ValueError("finishingSettings " + field + " is outside its finite bounds")
    if preparation.get("method") == "none":
        if set(preparation) != {"method"}:
            raise ValueError("none topologyPreparation accepts only method")
    elif preparation.get("method") == "voxel-remesh":
        if set(preparation) != {"method", "voxelSize", "maxEstimatedVoxels", "maxPreparedTriangles"}:
            raise ValueError("voxel-remesh requires exactly its explicit size and budgets")
        number(preparation, "voxelSize", 0, 1)
        for field, minimum, maximum in (("maxEstimatedVoxels", 1, 2_000_000_000),
                                        ("maxPreparedTriangles", 4, 20_000_000)):
            if not integer(preparation.get(field)) or not minimum <= preparation[field] <= maximum:
                raise ValueError("finishingSettings " + field + " is outside its integer bounds")
    else:
        raise ValueError("Unknown topologyPreparation method")
    if collision.get("method") == "exact-hull":
        if set(collision) != {"method"}:
            raise ValueError("exact-hull collision accepts only method")
    elif collision.get("method") == "kdop-26":
        if set(collision) != {"method", "padding", "maxVolumeRatio"}:
            raise ValueError("kdop-26 requires exactly padding and maxVolumeRatio")
        number(collision, "padding", 0, 1, True)
        number(collision, "maxVolumeRatio", 1, 100, True)
    else:
        raise ValueError("Unknown collision method")
    if "quadriFlow" in value:
        quadri_flow = value["quadriFlow"]
        if (type(quadri_flow) is not dict or "coordinateScale" not in quadri_flow
                or set(quadri_flow) - {"coordinateScale", "simplification"}):
            raise ValueError("quadriFlow requires coordinateScale and optional simplification")
        quadri_flow_scale(quadri_flow["coordinateScale"])
        if "simplification" in quadri_flow:
            validate_simplification(quadri_flow["simplification"])
    normalized = json.loads(json.dumps(value, allow_nan=False))
    normalized["schemaVersion"] = 1
    if preparation["method"] == "voxel-remesh":
        for field in ("maxEstimatedVoxels", "maxPreparedTriangles"):
            normalized["topologyPreparation"][field] = int(preparation[field])
    if "quadriFlow" in normalized:
        normalized["quadriFlow"]["coordinateScale"] = quadri_flow_scale(normalized["quadriFlow"]["coordinateScale"])
        if "simplification" in normalized["quadriFlow"]:
            normalized["quadriFlow"]["simplification"] = validate_simplification(normalized["quadriFlow"]["simplification"])
    return normalized


def quadri_flow_scale(value):
    if (type(value) not in (int, float) or not 1 <= value <= 1024
            or not math.isfinite(value) or value != int(value) or int(value) & (int(value) - 1)):
        raise ValueError("quadriFlow.coordinateScale must be an integer power of two inside 1..1024")
    return int(value)


def validate_simplification(value):
    """A closed explicit contract; no algorithm, region or budget is inferred."""
    fields = {"method", "targetTriangles", "maxVertexSurfaceErrorMetres", "protectedRegions"}
    if type(value) is not dict or set(value) != fields or value.get("method") != "collapse":
        raise ValueError("quadriFlow.simplification requires exactly collapse, targetTriangles, maxVertexSurfaceErrorMetres and protectedRegions")
    target = value["targetTriangles"]
    error = value["maxVertexSurfaceErrorMetres"]
    if (type(target) not in (int, float) or not 4 <= target <= 8_000_000
            or not math.isfinite(target) or target != int(target)):
        raise ValueError("simplification targetTriangles must be an integer inside4..8000000")
    if type(error) not in (int, float) or not 0 < error <= 1 or not math.isfinite(error):
        raise ValueError("simplification maxVertexSurfaceErrorMetres must be finite inside(0,1]")
    regions = value["protectedRegions"]
    if type(regions) is not list or len(regions) > 128:
        raise ValueError("simplification protectedRegions must be an array with at most128 entries")
    names = set()
    for region in regions:
        if type(region) is not dict or set(region) != {"id", "min", "max"}:
            raise ValueError("A protected region requires exactly id, min and max")
        name = region["id"]
        if (type(name) is not str or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", name, re.ASCII)
                or name in names):
            raise ValueError("Protected region IDs must be unique case-sensitive ASCII identifiers inside1..80characters")
        names.add(name)
        for key in ("min", "max"):
            point = region[key]
            if (type(point) is not list or len(point) != 3
                    or any(type(number) not in (int, float) or not -1e9 <= number <= 1e9
                           or not math.isfinite(number) for number in point)):
                raise ValueError("Protected region bounds require exactly three finite world-metre coordinates inside+/-1e9")
        if any(region["min"][axis] >= region["max"][axis] for axis in range(3)):
            raise ValueError("Protected region min must be strictly below max on every axis")
    result = json.loads(json.dumps(value, allow_nan=False))
    result["targetTriangles"] = int(target)
    return result


def mesh_identity(obj):
    """Geometry-only identity detects a warning/FINISHED no-op, not UI state."""
    digest = hashlib.sha256()
    for collection, attribute, width, dtype in ((obj.data.vertices, "co", 3, np.float32),
                                                (obj.data.loops, "vertex_index", 1, np.int32),
                                                (obj.data.polygons, "loop_total", 1, np.int32)):
        data = np.empty(len(collection) * width, dtype=dtype)
        collection.foreach_get(attribute, data)
        digest.update(str((len(collection), attribute)).encode("ascii"))
        digest.update(memoryview(data))
    return digest.hexdigest()


def world_vertices(obj):
    data = np.empty(len(obj.data.vertices) * 3, dtype=np.float64)
    obj.data.vertices.foreach_get("co", data)
    matrix = np.asarray(obj.matrix_world, dtype=np.float64)
    result = data.reshape((-1, 3)) @ matrix[:3, :3].T + matrix[:3, 3]
    if len(result) < 4 or not np.isfinite(result).all():
        raise ValueError("A finite three-dimensional source part is required")
    return result


def require_usable(obj, label):
    measured = topology_measure(obj)
    if (measured["vertices"] < 4 or measured["faces"] < 4 or measured["boundaryEdges"]
            or measured["nonManifoldEdges"] or measured["inconsistentWindingEdges"]
            or measured["nonManifoldVertices"] or measured["looseVertices"] or measured["signedVolume"] <= 1e-15):
        raise ValueError(label + " requires closed manifold, consistently oriented positive-volume topology: "
                         + json.dumps(measured, sort_keys=True))
    return measured


def quadriflow_input_measure(obj, coordinate_scale=1):
    """Match Blender 4.5's raw Mesh preflight, including its coordinate epsilon."""
    coordinate_scale = quadri_flow_scale(coordinate_scale)
    mesh = obj.data
    coordinates = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", coordinates)
    coordinates = coordinates.reshape((-1, 3))
    scaled = coordinates * np.float32(coordinate_scale)
    if (not np.isfinite(scaled).all()
            or not np.array_equal(scaled / np.float32(coordinate_scale), coordinates)):
        raise ValueError("QuadriFlow solver coordinates require a finite bit-exact power-of-two roundtrip")
    coordinates = scaled
    edges = np.empty(len(mesh.edges) * 2, dtype=np.int32)
    mesh.edges.foreach_get("vertices", edges)
    edges = edges.reshape((-1, 2))
    corner_edges = np.empty(len(mesh.loops), dtype=np.int32)
    corner_vertices = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get("edge_index", corner_edges)
    mesh.loops.foreach_get("vertex_index", corner_vertices)
    counts = np.bincount(corner_edges, minlength=len(edges))
    starts = np.bincount(corner_edges, weights=corner_vertices == edges[corner_edges, 0], minlength=len(edges))
    deltas = coordinates[edges[:, 0]] - coordinates[edges[:, 1]]
    maximum_axes = np.max(np.abs(deltas), axis=1)
    threshold = np.float32(1e-4)
    offending = np.flatnonzero(maximum_axes <= threshold)
    report = {"source": "Blender6dc0b208d1b5 object_remesh.cc mesh_is_manifold_consistent",
              "coordinateFrame": "selected solver-local float32; world geometry is unchanged", "coordinateScale": coordinate_scale,
              "componentwiseThreshold": float(threshold), "wireEdges": int(np.count_nonzero(counts == 0)),
              "moreThanTwoFaceEdges": int(np.count_nonzero(counts > 2)),
              "inconsistentDirectedEdges": int(np.count_nonzero((counts == 2) & (starts != 1))),
              "boundaryEdges": int(np.count_nonzero(counts == 1)), "shortEdges": len(offending),
              "minimumMaximumAxisDelta": float(maximum_axes.min()) if len(edges) else None,
              "maximumOffendingEuclideanLength": float(np.linalg.norm(deltas[offending].astype(np.float64), axis=1).max()) if len(offending) else 0.0}
    report["compatible"] = not any(report[key] for key in ("wireEdges", "moreThanTwoFaceEdges", "inconsistentDirectedEdges", "shortEdges"))
    return report, offending


def prepare_topology(low, settings, coordinate_scale=1):
    before = topology_measure(low, allow_degenerate=True)
    detail = {"method": settings["method"], "before": before, "settings": settings,
              "workingLowSeamWeldToleranceMetres": 1e-6, "workingLowNormals": "consistent-outward",
              "inputGeometrySha256": mesh_identity(low)}
    if settings["method"] == "voxel-remesh":
        points = world_vertices(low)
        extents = points.max(axis=0) - points.min(axis=0)
        scaled = extents / settings["voxelSize"]
        if not np.isfinite(scaled).all():
            raise ValueError("Estimated voxel grid exceeds finite bounds")
        dimensions = [math.ceil(float(value)) + 6 for value in scaled]
        estimate = math.prod(dimensions)
        detail.update({"worldBounds": {"min": points.min(axis=0).tolist(), "max": points.max(axis=0).tolist()},
                       "gridDimensions": dimensions, "estimatedVoxels": estimate,
                       "estimateMethod": "product(ceil(worldExtent / voxelSize) + 6); three padded cells per side"})
        if estimate > settings["maxEstimatedVoxels"]:
            raise ValueError("Estimated voxel grid exceeds maxEstimatedVoxels before voxel-remesh: " + str(estimate))
        activate(low)
        low.data.remesh_voxel_size = settings["voxelSize"]
        low.data.remesh_voxel_adaptivity = 0.0
        low.data.use_remesh_preserve_volume = True
        result = bpy.ops.object.voxel_remesh()
        if result != {"FINISHED"}:
            raise ValueError("Selected voxel-remesh did not finish: " + repr(result))
        count = triangles(low)
        if count > settings["maxPreparedTriangles"]:
            raise ValueError("Actual voxel-remesh exceeds maxPreparedTriangles: " + str(count))
        detail["operatorStatus"] = sorted(result)
    detail["after"] = require_usable(low, "Prepared retopology source")
    preflight, unused = quadriflow_input_measure(low, coordinate_scale)
    detail["quadriflowPrecondition"] = preflight
    if not preflight["compatible"]:
        raise ValueError("Prepared mesh fails exact QuadriFlow input precondition; select compatible explicit preparation or quadriFlow.coordinateScale, never a fallback: " + json.dumps(preflight))
    detail["preparedGeometrySha256"] = mesh_identity(low)
    detail["preparedTriangles"] = triangles(low)
    return detail


def triangle_indices(obj):
    """The actual Blender tessellation forwarded to native QuadriFlow."""
    obj.data.calc_loop_triangles()
    values = np.empty(len(obj.data.loop_triangles) * 3, dtype=np.int32)
    obj.data.loop_triangles.foreach_get("vertices", values)
    return values


def component_inventory(obj, identity_attribute=None):
    """Every connected vertex/edge/face, with candidate-carried source IDs."""
    mesh = obj.data
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh)
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        for vertex in bm.verts:
            vertex.tag = False
        labels = np.full(len(bm.verts), -1, dtype=np.int32)
        count = 0
        for seed in bm.verts:
            if seed.tag:
                continue
            seed.tag = True
            pending = [seed]
            while pending:
                vertex = pending.pop()
                labels[vertex.index] = count
                for edge in vertex.link_edges:
                    other = edge.other_vert(vertex)
                    if not other.tag:
                        other.tag = True
                        pending.append(other)
            count += 1
    finally:
        bm.free()
    if identity_attribute is None:
        source_ids = labels + 1
    else:
        attribute = mesh.attributes.get(identity_attribute)
        if attribute is None or attribute.data_type != "INT" or attribute.domain != "POINT":
            raise ValueError("Simplification lost its source component identity attribute")
        source_ids = np.empty(len(mesh.vertices), dtype=np.int32)
        attribute.data.foreach_get("value", source_ids)
    minimum_ids = np.full(count, np.iinfo(np.int32).max, dtype=np.int32)
    maximum_ids = np.full(count, np.iinfo(np.int32).min, dtype=np.int32)
    np.minimum.at(minimum_ids, labels, source_ids)
    np.maximum.at(maximum_ids, labels, source_ids)
    if np.any(minimum_ids != maximum_ids) or np.any(minimum_ids < 1) or len(np.unique(minimum_ids)) != count:
        raise ValueError("Simplification merged, split or corrupted source component IDs")
    edges = np.empty(len(mesh.edges) * 2, dtype=np.int32)
    mesh.edges.foreach_get("vertices", edges)
    edges = edges.reshape((-1, 2))
    starts = np.empty(len(mesh.polygons), dtype=np.int32)
    corners = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.polygons.foreach_get("loop_start", starts)
    mesh.loops.foreach_get("vertex_index", corners)
    v_counts = np.bincount(labels, minlength=count)
    e_counts = np.bincount(labels[edges[:, 0]], minlength=count)
    f_counts = np.bincount(labels[corners[starts]], minlength=count)
    local = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
    mesh.vertices.foreach_get("co", local)
    local = local.reshape((-1, 3))
    points = world_vertices(obj)
    lows, highs = np.full((count, 3), np.inf), np.full((count, 3), -np.inf)
    refs = local[np.minimum.reduceat(np.argsort(labels, kind="stable"), np.cumsum(np.r_[0, v_counts[:-1]]))]
    for axis in range(3):
        np.minimum.at(lows[:, axis], labels, points[:, axis])
        np.maximum.at(highs[:, axis], labels, points[:, axis])
    indices = triangle_indices(obj).reshape((-1, 3))
    volumes = np.zeros(count, dtype=np.float64)
    for start in range(0, len(indices), 131072):
        selected = indices[start:start + 131072]
        owners = labels[selected[:, 0]]
        relative = local[selected] - refs[owners, None, :]
        signed = np.einsum("ij,ij->i", relative[:, 0], np.cross(relative[:, 1], relative[:, 2])) / 6
        volumes += np.bincount(owners, weights=signed, minlength=count)
    if not np.isfinite(volumes).all():
        raise ValueError("Simplification component volumes are nonfinite")
    report = [{"id": int(minimum_ids[i]), "vertices": int(v_counts[i]), "edges": int(e_counts[i]),
               "faces": int(f_counts[i]), "eulerCharacteristic": int(v_counts[i] - e_counts[i] + f_counts[i]),
               "signedLocalVolume": float(volumes[i]), "worldBoundsMetres": {"min": lows[i].tolist(), "max": highs[i].tolist()}}
              for i in range(count)]
    return report, source_ids


def vertex_surface_measure(query_points, tree, origin):
    """All actual vertices, no sampling or nearest-vertex substitute."""
    distances = np.empty(len(query_points), dtype=np.float64)
    for index, point in enumerate(query_points):
        nearest, unused_normal, unused_face, distance = tree.find_nearest(tuple(point - origin))
        if nearest is None or not math.isfinite(distance) or distance < 0:
            raise ValueError("Simplification nearest-surface query failed")
        distances[index] = distance
    if not len(distances):
        raise ValueError("Simplification has no vertices to verify")
    maximum_index = int(np.argmax(distances))
    return {"vertices": len(distances), "queries": len(distances), "allVerticesMeasured": True,
            "maximumMetres": float(distances[maximum_index]), "rmsMetres": float(np.sqrt(np.mean(distances ** 2))),
            "p99Metres": float(np.percentile(distances, 99)), "maximumVertexIndex": maximum_index,
            "maximumWorldCoordinateMetres": query_points[maximum_index].tolist()}


def surface_deviation(source, candidate):
    """Actual Blender triangulation in a shared world-metre metric frame."""
    source_points, candidate_points = world_vertices(source), world_vertices(candidate)
    origin = (source_points.min(axis=0) + source_points.max(axis=0)) * 0.5
    metrics = []
    for target, target_points, queries in ((candidate, candidate_points, source_points),
                                            (source, source_points, candidate_points)):
        relative = target_points - origin
        # Blender BVHs use float32. Refuse an unresolvable metric rather than
        # presenting distant world-coordinate quantization as submillimetre proof.
        encoded = relative.astype(np.float32)
        if not np.isfinite(encoded).all():
            raise ValueError("Simplification surface metric exceeds finite Blender coordinates")
        indices = triangle_indices(target).reshape((-1, 3))
        tree = BVHTree.FromPolygons(encoded, indices, all_triangles=True, epsilon=0.0)
        if tree is None:
            raise ValueError("Simplification surface BVH is unavailable")
        measured = vertex_surface_measure(queries, tree, origin)
        measured["targetFloat32RepresentationErrorMetres"] = float(np.linalg.norm(encoded.astype(np.float64) - relative, axis=1).max())
        query_relative = queries - origin
        query_encoded = query_relative.astype(np.float32)
        if not np.isfinite(query_encoded).all():
            raise ValueError("Simplification surface queries exceed finite Blender coordinates")
        measured["queryFloat32RepresentationErrorMetres"] = float(np.linalg.norm(query_encoded.astype(np.float64) - query_relative, axis=1).max())
        measured["measuredMaximumPlusRepresentationErrorsMetres"] = (measured["maximumMetres"]
            + measured["targetFloat32RepresentationErrorMetres"] + measured["queryFloat32RepresentationErrorMetres"])
        metrics.append(measured)
        del tree
    return {"metric": "all vertices to opposite actual triangulated surface; unsigned Blender float32 BVH distances in world metres",
            "commonMetricOriginMetres": origin.tolist(), "sourceToCandidate": metrics[0], "candidateToSource": metrics[1],
            "limits": "All vertices, no subsampling. This is not a continuous-surface Hausdorff, edge/face-interior, silhouette, texture or visual-quality bound."}


def prepared_vertex_reference(obj, selected):
    """Immutable index identities and exact stored positions, not nearest matches."""
    coordinates = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
    obj.data.vertices.foreach_get("co", coordinates)
    indices = np.flatnonzero(selected)
    return {"ids": (indices + 1).astype(np.int32),
            "coordinates": coordinates.reshape((-1, 3))[indices].copy()}


def held_vertex_identity_report(reference, method):
    return {"heldVertices": len(reference["ids"]), "allOriginalIdsSurviveExactlyOnce": True,
            "float32CoordinatesBitIdentical": True, "verificationMethod": method,
            "heldIdsSha256": hashlib.sha256(memoryview(reference["ids"])).hexdigest(),
            "heldCoordinatesSha256": hashlib.sha256(memoryview(reference["coordinates"])).hexdigest(),
            "limits": "Holds selected original prepared vertices, not faces, shading or continuous patch interiors; independent topology and opposing-surface guards remain required."}


def verify_held_vertices(obj, reference, attribute_name):
    """Every selected source ID exactly once at its bit-identical local position."""
    if not len(reference["ids"]):
        return held_vertex_identity_report(reference, "no protected vertices selected")
    attribute = obj.data.attributes.get(attribute_name)
    if attribute is None or attribute.data_type != "INT" or attribute.domain != "POINT":
        raise ValueError("Simplification lost the protected original vertex identity attribute")
    identities = np.empty(len(obj.data.vertices), dtype=np.int32)
    attribute.data.foreach_get("value", identities)
    positions = np.flatnonzero(identities != 0)
    positions = positions[np.argsort(identities[positions], kind="stable")]
    if not np.array_equal(identities[positions], reference["ids"]):
        raise ValueError("Simplification changed protected original vertex identities: missing, duplicate, invented or corrupted ID")
    coordinates = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
    obj.data.vertices.foreach_get("co", coordinates)
    held = coordinates.reshape((-1, 3))[positions]
    if held.tobytes() != reference["coordinates"].tobytes():
        raise ValueError("Simplification changed bit-identical protected original vertex coordinates")
    return held_vertex_identity_report(reference, "candidate-carried original IDs and byte-for-byte float32 positions")


def retained_attribute_specs(mesh):
    topology = {"position", ".edge_verts", ".corner_vert", ".corner_edge"}
    supported = {"FLOAT", "INT", "INT8", "INT16_2D", "INT32_2D", "BOOLEAN", "STRING", "FLOAT_VECTOR", "FLOAT2", "FLOAT_COLOR", "BYTE_COLOR"}
    specs = []
    for attribute in mesh.attributes:
        if attribute.name in topology:
            continue
        if attribute.domain not in {"POINT", "EDGE", "FACE", "CORNER"} or attribute.data_type not in supported:
            raise ValueError("Exact retained-component attribute preservation is unavailable for " + attribute.name + ": " + attribute.data_type)
        specs.append((attribute.name, attribute.domain, attribute.data_type))
    return sorted(specs)


def retained_attribute_value(attribute, index):
    kind = attribute.data_type
    field = {"FLOAT": "value", "INT": "value", "INT8": "value", "INT16_2D": "value", "INT32_2D": "value", "BOOLEAN": "value", "STRING": "value",
             "FLOAT_VECTOR": "vector", "FLOAT2": "vector", "FLOAT_COLOR": "color", "BYTE_COLOR": "color"}[kind]
    value = getattr(attribute.data[index], field)
    if kind in {"INT", "INT8"}:
        return int(value)
    if kind in {"INT16_2D", "INT32_2D"}:
        return np.asarray(value, dtype="<i2" if kind == "INT16_2D" else "<i4").tobytes().hex()
    if kind == "BOOLEAN":
        return bool(value)
    if kind == "STRING":
        return str(value)
    return np.asarray(value, dtype="<f4").tobytes().hex()


def retained_mesh_snapshot(mesh, vertex_ids, face_ids, specs, original_group_count):
    """Exact original retained elements; no nearest-position correspondence."""
    point_indices = np.flatnonzero(vertex_ids != 0)
    face_indices = np.flatnonzero(face_ids != 0)
    if (len(np.unique(vertex_ids[point_indices])) != len(point_indices)
            or len(np.unique(face_ids[face_indices])) != len(face_indices)
            or np.any(vertex_ids[point_indices] < 1) or np.any(face_ids[face_indices] < 1)):
        raise ValueError("Retained component original element IDs are duplicated or invalid")
    for name, domain, kind in specs:
        attribute = mesh.attributes.get(name)
        if attribute is None or attribute.domain != domain or attribute.data_type != kind:
            raise ValueError("Retained component attribute definition changed: " + name)
    def values(domain, index):
        result = {}
        for name, owner, kind in specs:
            if owner != domain:
                continue
            # Mesh RNA lookups can lazily ensure other CustomData layers.
            # Retain descriptors, never Attribute wrappers across mesh reads.
            attribute = mesh.attributes.get(name)
            if attribute is None or attribute.domain != owner or attribute.data_type != kind:
                raise ValueError("Retained component attribute definition changed: " + name)
            result[name] = retained_attribute_value(attribute, index)
        return result
    points = {}
    for index in point_indices:
        vertex = mesh.vertices[int(index)]
        points[str(int(vertex_ids[index]))] = {"coordinates": np.asarray(vertex.co, dtype="<f4").tobytes().hex(),
            "attributes": values("POINT", int(index)),
            "weights": ({str(weight.group): np.asarray(weight.weight, dtype="<f4").tobytes().hex()
                        for weight in vertex.groups if weight.group < original_group_count} if original_group_count else {})}
    edges = {}
    edge_indices = np.empty(len(mesh.edges) * 2, dtype=np.int32)
    mesh.edges.foreach_get("vertices", edge_indices)
    edge_indices = edge_indices.reshape((-1, 2))
    for index in np.flatnonzero(np.all(vertex_ids[edge_indices] != 0, axis=1)):
        owners = sorted(int(value) for value in vertex_ids[edge_indices[index]])
        key = str(owners)
        if key in edges:
            raise ValueError("Retained component has duplicate original edge ownership")
        edges[key] = values("EDGE", int(index))
    faces = {}
    for index in face_indices:
        polygon = mesh.polygons[int(index)]
        ordered = [int(vertex_ids[vertex]) for vertex in polygon.vertices]
        if any(value < 1 for value in ordered):
            raise ValueError("A retained face acquired a main-component vertex")
        faces[str(int(face_ids[index]))] = {"orderedOriginalVertexIds": ordered,
            "material": polygon.material_index, "smooth": bool(polygon.use_smooth), "attributes": values("FACE", int(index)),
            "corners": [{"originalVertexId": int(vertex_ids[mesh.loops[loop].vertex_index]),
                         "attributes": values("CORNER", loop)} for loop in polygon.loop_indices]}
    indices = triangle_indices(type("MeshView", (), {"data": mesh})()).reshape((-1, 3))
    selected = np.all(vertex_ids[indices] != 0, axis=1)
    encoded_triangles = sorted(tuple(int(value) for value in face) for face in vertex_ids[indices[selected]])
    custom_normals = None
    if mesh.has_custom_normals:
        custom_normals = {str(int(face_ids[index])): [np.asarray(mesh.corner_normals[loop].vector, dtype="<f4").tobytes().hex()
            for loop in mesh.polygons[int(index)].loop_indices] for index in face_indices}
    return {"points": points, "edges": edges, "faces": faces,
            "orderedOriginalFaceIds": face_ids[face_indices].tolist(), "actualOrientedTriangles": encoded_triangles,
            "attributeDefinitions": specs, "materialSlots": [material.name_full if material else None for material in mesh.materials],
            "customCornerNormals": custom_normals}


def retained_snapshot_digest(snapshot):
    return hashlib.sha256(json.dumps(snapshot, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()).hexdigest()


def subset_component_mesh(source, component_attribute, main_identity, keep_main):
    """BMesh deletion copies existing geometry; it never reauthors retained faces."""
    result = source.copy()
    bm = bmesh.new()
    try:
        bm.from_mesh(result)
        identities = bm.verts.layers.int.get(component_attribute)
        if identities is None:
            raise ValueError("Component isolation lost its source IDs")
        remove = [vertex for vertex in bm.verts if (vertex[identities] == main_identity) != keep_main]
        bmesh.ops.delete(bm, geom=remove, context="VERTS")
        bm.to_mesh(result)
        result.update()
        return result
    except BaseException:
        if result.users == 0:
            bpy.data.meshes.remove(result)
        raise
    finally:
        bm.free()


def read_retained_ids(mesh, point_attribute, face_attribute):
    result = []
    for name, domain, count in ((point_attribute, "POINT", len(mesh.vertices)), (face_attribute, "FACE", len(mesh.polygons))):
        attribute = mesh.attributes.get(name)
        if attribute is None or attribute.data_type != "INT" or attribute.domain != domain:
            raise ValueError("Retained component original element identity attribute was lost")
        values = np.empty(count, dtype=np.int32)
        attribute.data.foreach_get("value", values)
        result.append(values)
    return result


def restore_missing_retained_attributes(mesh, expected, specs, group_count, point_attribute, face_attribute):
    """Reinstate omitted CustomData only; existing values and geometry still must match.

    BMesh may omit an explicit all-default layer (for example sharp_edge).
    Copy its stored values from the immutable snapshot by original element IDs;
    never infer correspondence from position or overwrite an existing layer.
    """
    missing = []
    for name, domain, kind in specs:
        attribute = mesh.attributes.get(name)
        if attribute is None:
            missing.append((name, domain, kind))
        elif attribute.domain != domain or attribute.data_type != kind:
            raise ValueError("Retained component attribute definition changed: " + name)
    if not missing:
        return {"restoredMissingAttributes": [], "policy": "existing attribute values are never overwritten"}
    vertex_ids, face_ids = read_retained_ids(mesh, point_attribute, face_attribute)
    # Validate ownership, positions, polygon/corner ordering, actual tessellation,
    # material assignments and group weights before copying any stored attribute.
    actual_geometry = retained_mesh_snapshot(mesh, vertex_ids, face_ids, [], group_count)
    expected_geometry = dict(expected, attributeDefinitions=[])
    expected_geometry["points"] = {key: dict(value, attributes={}) for key, value in expected["points"].items()}
    expected_geometry["edges"] = {key: {} for key in expected["edges"]}
    expected_geometry["faces"] = {key: dict(value, attributes={}, corners=[dict(corner, attributes={})
        for corner in value["corners"]]) for key, value in expected["faces"].items()}
    # Packed normals are stored attributes, restored below if the layer is absent.
    actual_geometry.pop("customCornerNormals")
    expected_geometry.pop("customCornerNormals")
    if actual_geometry != expected_geometry:
        raise ValueError("Retained component geometry or original element ownership changed before attribute restoration")

    def decode(kind, value):
        if kind in {"INT", "INT8"}:
            return int(value)
        if kind == "BOOLEAN":
            return bool(value)
        if kind == "STRING":
            return value
        dtype = "<i2" if kind == "INT16_2D" else "<i4" if kind == "INT32_2D" else "<f4"
        values = np.frombuffer(bytes.fromhex(value), dtype=dtype)
        return float(values[0]) if kind == "FLOAT" else tuple(values.tolist())

    point_indices = {int(identity): index for index, identity in enumerate(vertex_ids) if identity}
    face_indices = {int(identity): index for index, identity in enumerate(face_ids) if identity}
    edge_indices = {}
    for edge in mesh.edges:
        owners = [int(vertex_ids[index]) for index in edge.vertices]
        if all(owners):
            edge_indices[str(sorted(owners))] = edge.index
    restored = []
    for name, domain, kind in missing:
        try:
            mesh.attributes.new(name, kind, domain)
        except (RuntimeError, TypeError, ValueError) as error:
            raise ValueError("Cannot exactly restore missing retained-component attribute " + name + ": " + str(error)) from error
        field = {"FLOAT_VECTOR": "vector", "FLOAT2": "vector", "FLOAT_COLOR": "color", "BYTE_COLOR": "color"}.get(kind, "value")
        if domain == "POINT":
            entries = [(point_indices[int(identity)], value["attributes"][name]) for identity, value in expected["points"].items()]
        elif domain == "EDGE":
            entries = [(edge_indices[key], value[name]) for key, value in expected["edges"].items()]
        elif domain == "FACE":
            entries = [(face_indices[int(identity)], value["attributes"][name]) for identity, value in expected["faces"].items()]
        else:
            entries = [(mesh.polygons[face_indices[int(identity)]].loop_start + offset, corner["attributes"][name])
                for identity, value in expected["faces"].items() for offset, corner in enumerate(value["corners"])]
        for index, value in entries:
            # Re-resolve after every Mesh API access; CustomData can be reallocated.
            setattr(mesh.attributes[name].data[index], field, decode(kind, value))
        restored.append({"name": name, "domain": domain, "type": kind, "originalElementsCopied": len(entries)})
    mesh.update()
    return {"restoredMissingAttributes": restored, "policy": "exact immutable snapshot by original element IDs; existing values never overwritten"}


def verify_retained_snapshot(mesh, expected, specs, group_count, point_attribute, face_attribute):
    vertex_ids, face_ids = read_retained_ids(mesh, point_attribute, face_attribute)
    actual = retained_mesh_snapshot(mesh, vertex_ids, face_ids, specs, group_count)
    if actual != expected:
        changed = [key for key in expected if expected[key] != actual[key]]
        raise ValueError("Retained components changed original geometry, corner ordering or stored attributes: " + ", ".join(changed))
    return {"originalVertices": len(expected["points"]), "originalEdges": len(expected["edges"]),
            "originalPolygons": len(expected["faces"]), "actualTriangles": len(expected["actualOrientedTriangles"]),
            "snapshotSha256": retained_snapshot_digest(expected), "originalIdsAndCoordinatesAndCornersAndAttributesExact": True,
            "attributeTypes": sorted({kind for unused, domain, kind in specs})}


def simplify_quadriflow_input(low, selection, coordinate_scale=1, require_region_hits=True):
    """One explicit Collapse on an isolated copy, followed by independent guards."""
    if selection is None:
        return {"selected": False, "operatorCalls": 0}
    selection = validate_simplification(selection)
    coordinate_scale = quadri_flow_scale(coordinate_scale)
    bpy.context.view_layer.update()
    if low.modifiers:
        raise ValueError("Simplification requires an already prepared mesh without pending modifiers")
    before_topology = require_usable(low, "Simplification prepared source")
    before_hash, original_mesh = mesh_identity(low), low.data
    original_matrix = np.asarray(low.matrix_world, dtype=np.float32).copy()
    points = world_vertices(low)
    transform_determinant = float(np.linalg.det(np.asarray(low.matrix_world, dtype=np.float64)[:3, :3]))
    if not math.isfinite(transform_determinant) or abs(transform_determinant) <= 1e-15:
        raise ValueError("Simplification requires a finite nonsingular world transform")
    regions = selection["protectedRegions"]
    protected = np.zeros(len(points), dtype=bool)
    hits = {}
    for region in regions:
        inside = np.all((points >= region["min"]) & (points <= region["max"]), axis=1)
        hits[region["id"]] = int(np.count_nonzero(inside))
        protected |= inside
    if require_region_hits and any(count == 0 for count in hits.values()):
        raise ValueError("Configured protected region misses every prepared vertex: " + json.dumps(hits, sort_keys=True))
    input_triangles = triangles(low)
    report = {"selected": True, "settings": selection, "inputGeometrySha256": before_hash,
              "inputTriangles": input_triangles, "targetTriangleCapPerPart": selection["targetTriangles"],
              "protectedRegionHitCounts": hits, "protectedVertexCount": int(np.count_nonzero(protected)),
              "protection": {"selection": "exact inclusive world-metre boxes; no neighbor expansion",
                             "outsideWeight": 1.0, "insideWeight": 0.0, "vertexGroupFactor": 1000.0,
                             "invertVertexGroup": False,
                             "policy": "selected original prepared vertex IDs and stored coordinates must be unchanged"},
              "worldBoundsBeforeMetres": {"min": points.min(axis=0).tolist(), "max": points.max(axis=0).tolist()},
              "sourceTopology": before_topology, "operatorCalls": 0}
    before_components, component_ids = component_inventory(low)
    report["sourceComponents"] = before_components
    held_reference = prepared_vertex_reference(low, protected)
    original_group_names = [group.name for group in low.vertex_groups]
    if input_triangles <= selection["targetTriangles"]:
        preflight, unused = quadriflow_input_measure(low, coordinate_scale)
        if not preflight["compatible"]:
            raise ValueError("Already-within-cap mesh fails selected QuadriFlow input precondition")
        identity_measure = {"vertices": len(points), "queries": 0, "allVerticesMeasured": True,
                            "maximumMetres": 0.0, "rmsMetres": 0.0, "p99Metres": 0.0,
                            "measuredMaximumPlusRepresentationErrorsMetres": 0.0}
        report.update({"status": "already-within-cap", "outputGeometrySha256": before_hash,
                       "outputTriangles": input_triangles, "outputComponents": before_components,
                       "componentIdentitiesAndEulerPreserved": True, "quadriFlowPreflight": preflight,
                       "worldBoundsAfterMetres": report["worldBoundsBeforeMetres"],
                       "heldVertexProof": held_vertex_identity_report(held_reference, "exact unchanged mesh identity and original vertex indices"),
                       "surfaceError": {"metric": "exact unchanged mesh identity; every vertex is face-referenced on that same surface",
                                        "sourceToCandidate": dict(identity_measure), "candidateToSource": dict(identity_measure),
                                        "limits": "No BVH queries or simplification ran. Exact identity proves zero vertex-to-same-surface error, not continuous-surface or visual quality."}})
        return report
    attribute_name = "_opencaw_prepared_component_id"
    held_attribute_name = "_opencaw_prepared_vertex_id"
    retained_point_attribute = "_opencaw_retained_vertex_id"
    retained_face_attribute = "_opencaw_retained_face_id"
    if low.data.attributes.get(attribute_name):
        raise ValueError("Prepared mesh already contains the reserved simplification component attribute")
    if len(held_reference["ids"]) and low.data.attributes.get(held_attribute_name):
        raise ValueError("Prepared mesh already contains the reserved simplification vertex identity attribute")
    main_identity = before_components[0]["id"]
    main_input_triangles = input_triangles
    main_target_triangles = selection["targetTriangles"]
    retained_expected = None
    retained_specs = None
    retained_vertex_ids = retained_face_ids = None
    if len(before_components) > 1:
        if low.data.shape_keys is not None:
            raise ValueError("Exact disconnected-component reduction requires a prepared static mesh without shape keys")
        for name in (retained_point_attribute, retained_face_attribute):
            if low.data.attributes.get(name):
                raise ValueError("Prepared mesh already contains a reserved retained-component identity attribute: " + name)
        original_triangles = triangle_indices(low).reshape((-1, 3))
        counts = np.bincount(component_ids[original_triangles[:, 0]])
        main_identity = max((item["id"] for item in before_components), key=lambda identity: (int(counts[identity]), -identity))
        main_input_triangles = int(counts[main_identity])
        retained_triangles = input_triangles - main_input_triangles
        main_target_triangles = selection["targetTriangles"] - retained_triangles
        if main_target_triangles < 4:
            raise ValueError("Exact retained components leave fewer than four triangles inside the requested main-component cap")
        retained_vertex_ids = np.zeros(len(low.data.vertices), dtype=np.int32)
        retained_vertices = component_ids != main_identity
        retained_vertex_ids[retained_vertices] = np.flatnonzero(retained_vertices) + 1
        starts = np.empty(len(low.data.polygons), dtype=np.int32)
        corners = np.empty(len(low.data.loops), dtype=np.int32)
        low.data.polygons.foreach_get("loop_start", starts)
        low.data.loops.foreach_get("vertex_index", corners)
        retained_faces = component_ids[corners[starts]] != main_identity
        retained_face_ids = np.zeros(len(low.data.polygons), dtype=np.int32)
        retained_face_ids[retained_faces] = np.flatnonzero(retained_faces) + 1
        retained_specs = retained_attribute_specs(low.data)
        retained_expected = retained_mesh_snapshot(low.data, retained_vertex_ids, retained_face_ids, retained_specs, len(original_group_names))
        report["componentRetention"] = {"strategy": "reduce largest actual-triangle component; retain every other component exactly",
            "tieBreak": "lowest original component ID", "mainOriginalId": main_identity,
            "mainInputTriangles": main_input_triangles, "retainedTriangles": retained_triangles,
            "mainTargetTriangleCap": main_target_triangles,
            "retainedOriginalIds": [item["id"] for item in before_components if item["id"] != main_identity],
            "sourceSnapshotSha256": retained_snapshot_digest(retained_expected)}
    candidate = low.copy()
    candidate.data = original_mesh.copy()
    candidate.name = low.name + "_SIMPLIFICATION_CANDIDATE"
    bpy.context.collection.objects.link(candidate)
    candidate_mesh = candidate.data
    owned_meshes = {candidate_mesh}
    retained_mesh = None
    committed = False
    try:
        attribute = candidate.data.attributes.new(attribute_name, "INT", "POINT")
        attribute.data.foreach_set("value", component_ids)
        group = None
        group_name = None
        if np.any(protected):
            identities = np.zeros(len(points), dtype=np.int32)
            identities[protected] = held_reference["ids"]
            held_attribute = candidate.data.attributes.new(held_attribute_name, "INT", "POINT")
            held_attribute.data.foreach_set("value", identities)
            group = candidate.vertex_groups.new(name="OpenCawHeldDetailVertices")
            group.add(list(range(len(points))), 1.0, "REPLACE")
            group.add(np.flatnonzero(protected).tolist(), 0.0, "REPLACE")
            group_name = group.name
        if retained_expected is not None:
            for name, domain, values in ((retained_point_attribute, "POINT", retained_vertex_ids),
                                         (retained_face_attribute, "FACE", retained_face_ids)):
                marker = candidate.data.attributes.new(name, "INT", domain)
                marker.data.foreach_set("value", values)
            retained_mesh = subset_component_mesh(candidate.data, attribute_name, main_identity, False)
            owned_meshes.add(retained_mesh)
            report["componentRetention"]["isolationAttributeRestoration"] = restore_missing_retained_attributes(retained_mesh,
                retained_expected, retained_specs, len(original_group_names), retained_point_attribute, retained_face_attribute)
            report["componentRetention"]["isolationProof"] = verify_retained_snapshot(retained_mesh, retained_expected,
                retained_specs, len(original_group_names), retained_point_attribute, retained_face_attribute)
            main_mesh = subset_component_mesh(candidate.data, attribute_name, main_identity, True)
            owned_meshes.add(main_mesh)
            candidate.data = main_mesh
            if triangles(candidate) != main_input_triangles:
                raise ValueError("Component isolation changed the actual main-input triangle count")
            if candidate_mesh.users == 0:
                owned_meshes.discard(candidate_mesh)
                bpy.data.meshes.remove(candidate_mesh)
        main_has_protected_vertices = bool(np.any(protected & (component_ids == main_identity)))
        operator_input_mesh = candidate.data
        modifier = candidate.modifiers.new("OpenCawExplicitInputCollapse", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = main_target_triangles / main_input_triangles
        modifier.use_collapse_triangulate = True
        modifier.use_symmetry = False
        if group is not None and main_has_protected_vertices:
            modifier.vertex_group = group.name
            modifier.vertex_group_factor = 1000.0
            modifier.invert_vertex_group = False
        report["operator"] = {"type": "DECIMATE", "mode": "COLLAPSE", "ratio": modifier.ratio,
                              "useCollapseTriangulate": True, "useSymmetry": False,
                              "vertexGroupUsed": group is not None and main_has_protected_vertices,
                              "mainInputTriangles": main_input_triangles, "mainTargetTriangleCap": main_target_triangles}
        activate(candidate)
        report["operatorCalls"] = 1
        status = bpy.ops.object.modifier_apply(modifier=modifier.name)
        if status != {"FINISHED"}:
            raise ValueError("Selected simplification did not finish: " + repr(status))
        report["operatorStatus"] = sorted(status)
        main_output_triangles = triangles(candidate)
        if main_output_triangles > main_target_triangles:
            raise ValueError("Simplification exceeds its hard input triangle cap for the main component: " + str(main_output_triangles))
        if main_output_triangles >= main_input_triangles:
            raise ValueError("Simplification did not reduce the main-component geometry")
        if retained_mesh is not None:
            combined = bmesh.new()
            try:
                # Retained data defines the native CustomData layers first.
                # All geometry stays in the original local coordinate frame.
                combined.from_mesh(retained_mesh)
                combined.from_mesh(candidate.data)
                combined.to_mesh(candidate.data)
                candidate.data.update()
            finally:
                combined.free()
            report["componentRetention"]["recombinationAttributeRestoration"] = restore_missing_retained_attributes(candidate.data,
                retained_expected, retained_specs, len(original_group_names), retained_point_attribute, retained_face_attribute)
            report["componentRetention"]["recombinationProof"] = verify_retained_snapshot(candidate.data, retained_expected,
                retained_specs, len(original_group_names), retained_point_attribute, retained_face_attribute)
            report["componentRetention"]["mainOutputTriangles"] = main_output_triangles
        output_triangles = triangles(candidate)
        if output_triangles > selection["targetTriangles"]:
            raise ValueError("Simplification exceeds its hard input triangle cap: " + str(output_triangles))
        if mesh_identity(candidate) == before_hash or output_triangles >= input_triangles:
            raise ValueError("Simplification did not reduce the prepared geometry")
        bpy.context.view_layer.update()
        if not np.array_equal(original_matrix, np.asarray(candidate.matrix_world, dtype=np.float32)):
            raise ValueError("Simplification changed the prepared source transform")
        report["heldVertexProof"] = verify_held_vertices(candidate, held_reference, held_attribute_name)
        after_topology = require_usable(candidate, "Simplification output")
        after_components, unused = component_inventory(candidate, attribute_name)
        before_by_id = {item["id"]: item for item in before_components}
        after_by_id = {item["id"]: item for item in after_components}
        if set(before_by_id) != set(after_by_id):
            raise ValueError("Simplification lost or invented source component IDs")
        for identity, previous in before_by_id.items():
            current = after_by_id[identity]
            if (previous["eulerCharacteristic"] != current["eulerCharacteristic"]
                    or np.sign(previous["signedLocalVolume"]) != np.sign(current["signedLocalVolume"])):
                raise ValueError("Simplification changed source component Euler characteristic or orientation: " + str(identity))
            component_bound_change = max(abs(current["worldBoundsMetres"][key][axis] - previous["worldBoundsMetres"][key][axis])
                                         for key in ("min", "max") for axis in range(3))
            current["worldBoundsMaximumAxisChangeMetres"] = component_bound_change
        surface = surface_deviation(low, candidate)
        report["surfaceError"] = surface
        if any(surface[direction]["measuredMaximumPlusRepresentationErrorsMetres"] > selection["maxVertexSurfaceErrorMetres"]
               for direction in ("sourceToCandidate", "candidateToSource")):
            raise ValueError("Simplification exceeds maxVertexSurfaceErrorMetres: " + json.dumps(surface, sort_keys=True))
        if any(item["worldBoundsMaximumAxisChangeMetres"] > selection["maxVertexSurfaceErrorMetres"] for item in after_components):
            raise ValueError("Simplification changed a source component's world bounds beyond its error budget")
        after_points = world_vertices(candidate)
        after_bounds = {"min": after_points.min(axis=0).tolist(), "max": after_points.max(axis=0).tolist()}
        maximum_bound_change = max(abs(after_bounds[key][axis] - report["worldBoundsBeforeMetres"][key][axis])
                                   for key in ("min", "max") for axis in range(3))
        if maximum_bound_change > selection["maxVertexSurfaceErrorMetres"]:
            raise ValueError("Simplification world bounds exceed maxVertexSurfaceErrorMetres")
        preflight, unused = quadriflow_input_measure(candidate, coordinate_scale)
        if not preflight["compatible"]:
            raise ValueError("Simplified mesh fails selected QuadriFlow input precondition: " + json.dumps(preflight))
        if (mesh_identity(low) != before_hash or low.data != original_mesh
                or not np.array_equal(original_matrix, np.asarray(low.matrix_world, dtype=np.float32))):
            raise ValueError("Immutable prepared input changed during simplification")
        if group_name is not None:
            # Applying a real modifier can rebuild the deform-group wrappers
            # without changing the Mesh ID. Never reuse a stale RNA wrapper.
            remaining_group = candidate.vertex_groups.get(group_name)
            if remaining_group is not None:
                candidate.vertex_groups.remove(remaining_group)
        if [item.name for item in candidate.vertex_groups] != original_group_names:
            raise ValueError("Simplification changed original source vertex-group definitions")
        report.update({"status": "simplified", "outputTriangles": output_triangles,
                       "outputGeometrySha256": mesh_identity(candidate), "outputTopology": after_topology,
                       "outputComponents": after_components, "componentIdentitiesAndEulerPreserved": True,
                       "quadriFlowPreflight": preflight, "worldBoundsAfterMetres": after_bounds,
                       "worldBoundsMaximumAxisChangeMetres": maximum_bound_change,
                       "immutablePreparedInputPreserved": True,
                       "candidateDataBlockReplacedByModifier": candidate.data != operator_input_mesh})
        low.data = candidate.data
        committed = True
        return report
    finally:
        current_mesh = candidate.data
        bpy.data.objects.remove(candidate, do_unlink=True)
        # The source data is retained in memory. main() also owns an immutable
        # hidden PREPARATION_SOURCE object for editable-master persistence.
        if not committed:
            low.data = original_mesh
        for mesh in owned_meshes | {current_mesh}:
            try:
                alive = bpy.data.meshes.get(mesh.name) == mesh
            except ReferenceError:
                continue
            if alive and mesh != original_mesh and mesh != low.data and mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        activate(low)


def run_quadriflow(low, target, coordinate_scale=1):
    """Explicit numerical basis only; no physical weld, perturbation or fallback."""
    coordinate_scale = quadri_flow_scale(coordinate_scale)
    bpy.context.view_layer.update()
    preflight, unused = quadriflow_input_measure(low, coordinate_scale)
    if not preflight["compatible"]:
        raise ValueError("QuadriFlow did not finish: selected solver-space input precondition failed; "
                         "use explicit quadriFlow.coordinateScale only for otherwise valid geometry: " + json.dumps(preflight))
    require_usable(low, "QuadriFlow input")
    before = mesh_identity(low)
    original = low.data
    original_scale = low.scale.copy()
    original_matrix = np.asarray(low.matrix_world, dtype=np.float32).copy()
    original_world = world_vertices(low)
    original_triangles = triangle_indices(low)
    coordinates = np.empty(len(original.vertices) * 3, dtype=np.float32)
    original.vertices.foreach_get("co", coordinates)
    candidate = original.copy()
    succeeded = False
    try:
        low.data = candidate
        solver_coordinates = coordinates * np.float32(coordinate_scale)
        # Multiplication by a bounded power of two changes only the exponent.
        if (not np.isfinite(solver_coordinates).all()
                or not np.array_equal(solver_coordinates / np.float32(coordinate_scale), coordinates)):
            raise ValueError("QuadriFlow solver coordinates cannot preserve the input exactly")
        candidate.vertices.foreach_set("co", solver_coordinates)
        candidate.update()
        # Avoid matrix_world assignment: TRS decomposition can move vertices.
        # Keeping the actual rotation/location channels preserves an exact basis.
        low.scale = tuple(float(value) / coordinate_scale for value in original_scale)
        bpy.context.view_layer.update()
        if not np.array_equal(original_world, world_vertices(low)):
            raise ValueError("QuadriFlow solver basis changed world geometry; unsupported transform")
        actual_preflight, unused = quadriflow_input_measure(low)
        if not actual_preflight["compatible"]:
            raise ValueError("Actual QuadriFlow solver-space preflight failed")
        solver_triangles = triangle_indices(low)
        if not np.array_equal(original_triangles, solver_triangles):
            raise ValueError("QuadriFlow solver basis changed Blender tessellation")
        solver_input_hash = mesh_identity(low)
        activate(low)
        result = bpy.ops.object.quadriflow_remesh("EXEC_DEFAULT", mode="FACES", target_faces=target,
                                                  use_preserve_sharp=True, use_preserve_boundary=True,
                                                  use_mesh_symmetry=False, preserve_attributes=False, seed=0)
        if result != {"FINISHED"}:
            raise ValueError("QuadriFlow did not finish: " + repr(result))
        if mesh_identity(low) == solver_input_hash:
            raise ValueError("QuadriFlow left unchanged source geometry; warnings/no-ops cannot complete retopology")
        output = np.empty(len(low.data.vertices) * 3, dtype=np.float32)
        low.data.vertices.foreach_get("co", output)
        restored = output / np.float32(coordinate_scale)
        if (not np.isfinite(restored).all()
                or not np.array_equal(restored * np.float32(coordinate_scale), output)):
            raise ValueError("QuadriFlow output cannot restore original units exactly")
        low.data.vertices.foreach_set("co", restored)
        low.data.update()
        low.scale = original_scale
        bpy.context.view_layer.update()
        if not np.array_equal(original_matrix, np.asarray(low.matrix_world, dtype=np.float32)):
            raise ValueError("QuadriFlow did not restore the original object transform")
        after = mesh_identity(low)
        if after == before:
            raise ValueError("QuadriFlow returned unchanged geometry after restoring units")
        measured = require_usable(low, "QuadriFlow output in original units")
        report = {"operatorStatus": sorted(result), "preflight": preflight,
                  "actualSolverPreflight": actual_preflight, "inputGeometrySha256": before,
                  "outputGeometrySha256": after, "topology": measured,
                  "solverCoordinates": {"coordinateScale": coordinate_scale,
                    "scope": "temporary LOW mesh-local coordinates with reciprocal existing object scale",
                    "worldVertexErrorBeforeOperatorMetres": 0.0,
                    "inputLocalCoordinatesRoundTripBitExact": True,
                    "inputTessellationUnchanged": True,
                    "inputTessellationSha256": hashlib.sha256(memoryview(original_triangles)).hexdigest(),
                    "sourceTriangleCount": len(original_triangles) // 3,
                    "solverInputGeometrySha256": solver_input_hash,
                    "originalObjectScale": list(original_scale),
                    "unitsAndObjectTransformRestored": True,
                    "physicalVertexWeldOrPerturbation": False}}
        succeeded = True
        return report
    finally:
        low.scale = original_scale
        if not succeeded:
            low.data = original
        bpy.context.view_layer.update()
        unused_mesh = original if succeeded else candidate
        if unused_mesh.users == 0:
            bpy.data.meshes.remove(unused_mesh)


def exact_hull_volume(points):
    """Actual Blender convex hull of ALL source vertices, used as a ratio reference."""
    mesh = bmesh.new()
    try:
        for point in points:
            mesh.verts.new(point)
        result = bmesh.ops.convex_hull(mesh, input=list(mesh.verts), use_existing_faces=False)
        unused = list(set(result["geom_interior"]) | set(result["geom_unused"]))
        if unused:
            bmesh.ops.delete(mesh, geom=unused, context="VERTS")
        bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
        volume = mesh.calc_volume(signed=True)
        if not math.isfinite(volume) or volume <= 1e-15:
            raise ValueError("Source exact convex hull has no positive three-dimensional volume")
        return volume
    finally:
        mesh.free()


def collision_measure(obj, source_points):
    """Verify actual mesh face planes, independent of k-DOP support construction."""
    mesh = bmesh.new()
    try:
        mesh.from_mesh(obj.data)
        encoded_vertices = len(mesh.verts)
        matrix = np.asarray(obj.matrix_world, dtype=np.float64)
        linear, translation = matrix[:3, :3], matrix[:3, 3]
        transform_scale = float(np.linalg.norm(linear, ord=2))
        if not np.isfinite(matrix).all() or not math.isfinite(transform_scale) or transform_scale <= 0:
            raise ValueError("Collision proxy has no finite usable transform")
        # glTF duplicates coordinates at hard-normal seams. Verify the geometric
        # surface after merging only numerically coincident encoded vertices.
        # Never round translated world coordinates through BMesh float32 first.
        bmesh.ops.remove_doubles(mesh, verts=list(mesh.verts), dist=1e-6 / transform_scale)
        mesh.normal_update()
        if (not mesh.faces or any(not edge.is_manifold or not edge.is_contiguous for edge in mesh.edges)
                or any(not vertex.link_faces for vertex in mesh.verts)):
            raise ValueError("Collision proxy must be a closed consistently oriented manifold")
        mesh.verts.index_update()
        local_points = np.array([list(vertex.co) for vertex in mesh.verts], dtype=np.float64)
        offsets = local_points @ linear.T
        if not np.isfinite(offsets).all() or not np.isfinite(source_points).all():
            raise ValueError("Collision proxy has nonfinite geometry")
        size = float(np.max(np.ptp(offsets, axis=0)))
        tolerance = max(1e-7, size * 2e-6)
        # This conservative float64 operation bound must remain well below the
        # unchanged geometry tolerance. Reject unrecoverably remote/cancelled
        # coordinates instead of increasing tolerance to fit them.
        magnitude = max(float(np.max(np.abs(source_points))),
                        float(np.max(np.abs(local_points))) * float(np.max(np.sum(np.abs(linear), axis=1)))
                        + float(np.max(np.abs(translation))), 1.0)
        roundoff_bound = magnitude * np.finfo(np.float64).eps * 32
        if roundoff_bound > tolerance / 8:
            raise ValueError("Collision world coordinates exceed supported numerical precision; rebase the asset origin")
        centre = (offsets.min(axis=0) + offsets.max(axis=0)) / 2
        points = offsets - centre
        normals, limits, face_vertices, area_normals, volume = [], [], [], [], 0.0
        mesh.faces.index_update()
        for face in mesh.faces:
            polygon = points[[vertex.index for vertex in face.verts]]
            # Actual encoded vertices, transformed in float64, own these planes.
            # Blender's float32 normal/volume after a large world translation is
            # deliberately not used as an independent geometric measurement.
            origin = polygon[0]
            crosses = np.cross(polygon[1:-1] - origin, polygon[2:] - origin)
            area_normal = crosses.sum(axis=0)
            length = float(np.linalg.norm(area_normal))
            if not math.isfinite(length) or length <= 2e-14:
                raise ValueError("Collision proxy has degenerate planes")
            normal = area_normal / length
            normals.append(normal)
            limits.append(float(np.dot(normal, polygon.mean(axis=0))))
            face_vertices.append({vertex.index for vertex in face.verts})
            area_normals.append(area_normal)
            volume += float(np.einsum("ij,ij->i", np.broadcast_to(origin, polygon[1:-1].shape),
                                      np.cross(polygon[1:-1], polygon[2:])).sum()) / 6
        # Export triangulation can create skinny triangles whose individual
        # normals magnify sub-micrometre encoding error. Reconstruct adjacent
        # near-coplanar regions from ACTUAL vertices, never expected support
        # planes. Every merge must fit within one eighth of the unchanged
        # positional tolerance. This avoids treating a noisy extrapolated
        # triangle normal as a geometrically meaningful global half-space.
        parents = list(range(len(normals)))
        groups = {index: {"vertices": vertices, "area": area_normals[index],
                          "normal": normals[index], "limit": limits[index], "residual": 0.0}
                  for index, vertices in enumerate(face_vertices)}
        def component(index):
            while parents[index] != index:
                parents[index] = parents[parents[index]]
                index = parents[index]
            return index
        fit_limit = tolerance / 8
        for iteration in range(len(normals)):
            changed = False
            for edge in mesh.edges:
                first, second = [component(face.index) for face in edge.link_faces]
                if first == second:
                    continue
                a, b = groups[first], groups[second]
                if float(np.dot(a["normal"], b["normal"])) < math.cos(0.001):
                    continue
                indices = a["vertices"] | b["vertices"]
                sample = points[sorted(indices)]
                origin = sample.mean(axis=0)
                normal = np.linalg.svd(sample - origin, full_matrices=False)[2][-1]
                area = a["area"] + b["area"]
                if np.dot(normal, area) < 0:
                    normal = -normal
                residual = float(np.max(np.abs((sample - origin) @ normal)))
                if residual > fit_limit:
                    continue
                parents[second] = first
                groups[first] = {"vertices": indices, "area": area, "normal": normal,
                                 "limit": float(np.dot(normal, origin)), "residual": residual}
                del groups[second]
                changed = True
            if not changed:
                break
        normals = np.array([group["normal"] for group in groups.values()])
        limits = np.array([group["limit"] for group in groups.values()])
        planes = []
        for normal, limit in zip(normals, limits):
            if not any(np.linalg.norm(normal - other_normal) <= 1e-5 and abs(limit - other_limit) <= tolerance * 2
                       for other_normal, other_limit in planes):
                planes.append((normal, limit))
        # Bound each dense verification matrix to 8 MiB even for legacy hulls
        # with a caller-selected face cap larger than the normal 64 faces.
        rows = max(1, min(65536, (8 * 1024 * 1024) // (8 * len(normals))))
        def maximum_outside(values, world=False):
            result = -math.inf
            for start in range(0, len(values), rows):
                chunk = values[start:start + rows]
                if world:
                    chunk = (chunk - translation) - centre
                result = max(result, float(np.max(chunk @ normals.T - limits)))
            return result
        convex_error = maximum_outside(points)
        if convex_error > tolerance:
            raise ValueError("Collision proxy is not convex: maximum plane error " + str(convex_error))
        outside = maximum_outside(source_points, world=True)
        if outside > tolerance:
            raise ValueError("Collision proxy does not contain ALL source-part vertices: " + str(outside))
        if not math.isfinite(volume) or volume <= 1e-15:
            raise ValueError("Collision proxy has no finite positive volume")
        return {"vertices": len(mesh.verts), "encodedVertices": encoded_vertices,
                "coincidentSeamWeldToleranceMetres": 1e-6, "coplanarFaceGroups": len(planes),
                "verificationChunkRows": rows, "maxVerificationMatrixBytes": 8 * 1024 * 1024,
                "polygonFaces": len(mesh.faces), "triangles": triangles(obj),
                "closedManifold": True, "consistentlyOriented": True, "convex": True,
                "volume": volume, "bounds": {"min": (offsets.min(axis=0) + translation).tolist(),
                                               "max": (offsets.max(axis=0) + translation).tolist()},
                "numericalPrecision": {"method": "float64 local vertices and affine linear transform; centred face planes and tetrahedra",
                                       "roundoffBoundMetres": roundoff_bound,
                                       "maximumPermittedRoundoffMetres": tolerance / 8,
                                       "coplanarFitResidualLimitMetres": fit_limit,
                                       "maximumCoplanarFitResidualMetres": max(group["residual"] for group in groups.values()),
                                       "maximumMergeNormalAngleRadians": 0.001,
                                       "worldCoordinateRebasingRequired": False},
                "sourceVertexCount": len(source_points), "allSourceVerticesContained": True,
                "containmentToleranceMetres": tolerance, "maximumOutsideDistanceMetres": outside,
                "maximumConvexityErrorMetres": convex_error}
    finally:
        mesh.free()


def refine_exact_hull_facets(obj, source_points, face_cap):
    """Correct native hull connectivity without moving its original vertices.

    The native hull chooses topology on quantized points and reconnects the
    unquantized originals. A wrong diagonal can consequently remain concave.
    This construction adapter accepts only globally supporting replacement
    facets. It never changes the independent collision validator or its limits.
    """
    if type(face_cap) is not int or face_cap < 4 or len(obj.data.polygons) > face_cap:
        raise ValueError("Exact hull exceeds colliderMaxFaces before facet refinement")
    original = obj.data
    before_hash = mesh_identity(obj)
    before_matrix = np.asarray(obj.matrix_world, dtype=np.float32).copy()
    local_coordinates = np.empty(len(original.vertices) * 3, dtype=np.float32)
    original.vertices.foreach_get("co", local_coordinates)
    source = np.ascontiguousarray(source_points, dtype=np.float64)
    if source.ndim != 2 or source.shape[1] != 3 or not len(source) or not np.isfinite(source).all():
        raise ValueError("Exact hull refinement requires finite source points")
    source_hash = hashlib.sha256(memoryview(source)).hexdigest()
    faces = [tuple(polygon.vertices) for polygon in original.polygons]
    if not faces or any(len(face) != 3 for face in faces):
        raise ValueError("Exact hull refinement requires native triangular facets")
    topology = topology_measure(obj)
    if any(topology[key] for key in ("boundaryEdges", "nonManifoldEdges", "inconsistentWindingEdges",
                                     "nonManifoldVertices", "looseVertices")):
        raise ValueError("Exact hull refinement requires a closed consistently oriented native candidate")
    matrix = np.asarray(obj.matrix_world, dtype=np.float64)
    if not np.isfinite(matrix).all():
        raise ValueError("Exact hull refinement requires a finite transform")
    offsets = local_coordinates.reshape((-1, 3)).astype(np.float64) @ matrix[:3, :3].T
    centre = (offsets.min(axis=0) + offsets.max(axis=0)) / 2
    points = offsets - centre
    inputs = (points, (source - matrix[:3, 3]) - centre)
    tolerance = max(1e-7, float(np.max(np.ptp(offsets, axis=0))) * 2e-6)
    replacement_limit = tolerance / 8
    max_flips = min(256, 4 * len(faces))
    max_queries = 1000000000
    queries = 0
    rows = 65536

    def canonical(face):
        return min(face[index:] + face[:index] for index in range(3))

    def state(values):
        return tuple(sorted(canonical(face) for face in values))

    if len(set(state(faces))) != len(faces):
        raise ValueError("Exact hull candidate contains duplicate oriented facets")

    def support_error(face):
        nonlocal queries
        polygon = points[list(face)]
        normal = np.cross(polygon[1] - polygon[0], polygon[2] - polygon[0])
        length = float(np.linalg.norm(normal))
        if not math.isfinite(length) or length <= 2e-14:
            raise ValueError("Exact hull refinement encountered a degenerate facet")
        normal /= length
        limit = float(np.dot(normal, polygon.mean(axis=0)))
        maximum = -math.inf
        for values in inputs:
            for start in range(0, len(values), rows):
                chunk = values[start:start + rows]
                if queries + len(chunk) > max_queries:
                    raise ValueError("Exact hull facet refinement exceeded its point-plane support budget")
                maximum = max(maximum, float(np.max(chunk @ normal - limit)))
                queries += len(chunk)
        return maximum

    errors = [support_error(face) for face in faces]
    initial_error = max(errors)
    report = {"method": "point-preserving supporting-facet refinement of native exact hull",
              "nativeCandidateGeometrySha256": before_hash, "sourceWorldPointsSha256": source_hash,
              "hullVertexCount": len(original.vertices), "sourceVertexCount": len(source),
              "polygonFaces": len(faces), "colliderMaxFaces": face_cap,
              "convexityToleranceMetres": tolerance, "replacementSupportLimitMetres": replacement_limit,
              "maximumFlips": max_flips, "maximumPointPlaneQueries": max_queries,
              "supportChunkRows": rows, "maximumSupportVectorBytes": rows * 8,
              "initialMaximumOutsideMetres": initial_error, "flips": []}
    seen = {state(faces)}
    touched_diagonals = set()
    while max(errors) > tolerance:
        if len(report["flips"]) >= max_flips:
            raise ValueError("Exact hull facet refinement exceeded its deterministic flip budget")
        edges = {}
        for index, face in enumerate(faces):
            for offset in range(3):
                edge = tuple(sorted((face[offset], face[(offset + 1) % 3])))
                edges.setdefault(edge, []).append(index)
        choices = []
        for edge in sorted(edges):
            owners = edges[edge]
            if len(owners) != 2:
                raise ValueError("Exact hull facet refinement found a nonmanifold edge")
            if edge in touched_diagonals or max(errors[index] for index in owners) <= tolerance:
                continue
            first, second = owners
            face = faces[first]
            start = next(index for index in range(3) if {face[index], face[(index + 1) % 3]} == set(edge))
            u, v, a = face[start], face[(start + 1) % 3], face[(start + 2) % 3]
            other = faces[second]
            if not any(other[index] == v and other[(index + 1) % 3] == u for index in range(3)):
                raise ValueError("Exact hull facet refinement found inconsistent original winding")
            b = next(value for value in other if value not in edge)
            diagonal = tuple(sorted((a, b)))
            if a == b or diagonal in edges or diagonal in touched_diagonals:
                continue
            replacement = ((a, u, b), (a, b, v))
            unchanged = {canonical(value) for index, value in enumerate(faces) if index not in owners}
            if (canonical(replacement[0]) in unchanged or canonical(replacement[1]) in unchanged
                    or canonical(replacement[0]) == canonical(replacement[1])):
                continue
            try:
                replacement_errors = tuple(support_error(value) for value in replacement)
            except ValueError as error:
                if "degenerate facet" in str(error):
                    continue
                raise
            if max(replacement_errors) > replacement_limit:
                continue
            before_error = max(errors[index] for index in owners)
            choices.append((max(replacement_errors) - before_error, edge, diagonal, first, second,
                            replacement, replacement_errors, before_error))
        if not choices:
            raise ValueError("Exact hull candidate has unsupported facets with no point-preserving globally supporting adjacent flip")
        unused, edge, diagonal, first, second, replacement, replacement_errors, before_error = min(choices)
        faces[first], faces[second] = replacement
        errors[first], errors[second] = replacement_errors
        signature = state(faces)
        if signature in seen:
            raise ValueError("Exact hull facet refinement detected a repeated topology state")
        seen.add(signature)
        touched_diagonals.update((edge, diagonal))
        report["flips"].append({"retiredDiagonal": list(edge), "newDiagonal": list(diagonal),
                                "replacementOrientedFacets": [list(face) for face in replacement],
                                "beforeMaximumOutsideMetres": before_error,
                                "replacementMaximumOutsideMetres": max(replacement_errors),
                                "allSourceAndHullPointsTested": True})
    report.update({"pointPlaneQueries": queries, "finalMaximumOutsideMetres": max(errors),
                   "operatorCalls": 0, "vertexCoordinatesBitIdentical": True, "objectTransformUnchanged": True})
    if not report["flips"]:
        report["status"] = "already-supporting"
        return report
    candidate = original.copy()
    succeeded = False
    bm = bmesh.new()
    try:
        bm.from_mesh(candidate)
        bm.verts.ensure_lookup_table()
        for flip in report["flips"]:
            u, v = flip["retiredDiagonal"]
            edge = next((edge for edge in bm.verts[u].link_edges if bm.verts[v] in edge.verts), None)
            if edge is None:
                raise ValueError("Exact hull native facet adapter lost its recorded original diagonal")
            bmesh.ops.rotate_edges(bm, edges=[edge], use_ccw=False)
            report["operatorCalls"] += 1
        bm.to_mesh(candidate)
        candidate.update()
        coordinates = np.empty(len(candidate.vertices) * 3, dtype=np.float32)
        candidate.vertices.foreach_get("co", coordinates)
        actual_faces = [tuple(face.vertices) for face in candidate.polygons]
        if (coordinates.tobytes() != local_coordinates.tobytes() or len(actual_faces) != len(faces)
                or state(actual_faces) != state(faces)):
            raise ValueError("Exact hull native facet adapter changed vertex bytes or failed recorded oriented connectivity")
        obj.data = candidate
        if np.asarray(obj.matrix_world, dtype=np.float32).tobytes() != before_matrix.tobytes():
            raise ValueError("Exact hull facet refinement changed the original transform")
        # The unchanged independent validator remains the final authority.
        verified = collision_measure(obj, source)
        if hashlib.sha256(memoryview(source)).hexdigest() != source_hash:
            raise ValueError("Exact hull facet refinement changed immutable source points")
        report.update({"status": "refined", "outputGeometrySha256": mesh_identity(obj),
                       "independentMaximumConvexityErrorMetres": verified["maximumConvexityErrorMetres"],
                       "independentMaximumSourceOutsideMetres": verified["maximumOutsideDistanceMetres"]})
        succeeded = True
        return report
    finally:
        bm.free()
        if not succeeded:
            obj.data = original
        unused = original if succeeded else candidate
        if unused.users == 0:
            bpy.data.meshes.remove(unused)


def principal_axes_frame(source_world_points):
    """Return a deterministic right-handed PCA basis and explicit diagnostics.

    Columns of basis are world vectors. This function chooses directions only;
    the caller retains its existing centred world points and float32 origin.
    """
    points = np.asarray(source_world_points, dtype=np.float64)
    if points.ndim != 2 or points.shape[1] != 3 or len(points) < 4 or not np.isfinite(points).all():
        raise ValueError('Principal-axes frame requires finite N-by-3 source points')
    unique = np.unique(points, axis=0)
    if len(unique) < 4:
        raise ValueError('Principal-axes frame requires at least four unique points')
    try:
        with np.errstate(over='raise', invalid='raise', divide='raise'):
            covariance_centre = unique.mean(axis=0)
            centred = unique - covariance_centre
            covariance = centred.T @ centred / len(unique)
    except FloatingPointError:
        raise ValueError('Principal-axes covariance exceeds finite precision') from None
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    order = np.argsort(eigenvalues)[::-1]
    eigenvalues, eigenvectors = eigenvalues[order], eigenvectors[:, order]
    largest = float(eigenvalues[0])
    minimum_relative_eigenvalue = 1e-12
    relative_tie_tolerance = 1e-8
    if (not np.isfinite(eigenvalues).all() or largest <= 0
            or eigenvalues[-1] <= largest * minimum_relative_eigenvalue):
        raise ValueError('Principal-axes source is degenerate or unsupported nearly planar/linear geometry')
    clusters = []
    first = 0
    while first < 3:
        last = first + 1
        while last < 3 and abs(float(eigenvalues[last] - eigenvalues[first])) <= largest * relative_tie_tolerance:
            last += 1
        clusters.append((first, last))
        first = last
    axes, decisions = [], []
    for first, last in clusters:
        projector = eigenvectors[:, first:last] @ eigenvectors[:, first:last].T
        cluster_axes = []
        for unused in range(last - first):
            projected = []
            for world_axis in range(3):
                value = projector[:, world_axis].copy()
                for held in cluster_axes:
                    value -= held * float(held @ value)
                projected.append(value)
            lengths = [float(np.linalg.norm(value)) for value in projected]
            maximum = max(lengths)
            if maximum <= 1e-12:
                raise ValueError('Principal-axes tied eigenspace cannot establish a canonical axis')
            selected = next(i for i, length in enumerate(lengths) if maximum - length <= 1e-12)
            axis = projected[selected] / lengths[selected]
            cluster_axes.append(axis)
            decisions.append({'eigenvalueRangeHalfOpen': [first, last], 'projectedWorldAxis': selected})
        axes.extend(cluster_axes)
    basis = np.column_stack(axes)
    handedness_flip = bool(np.linalg.det(basis) < 0)
    if handedness_flip:
        basis[:, 2] *= -1
    orthogonal_error = float(np.max(np.abs(basis.T @ basis - np.eye(3))))
    determinant = float(np.linalg.det(basis))
    if not np.isfinite(basis).all() or orthogonal_error > 1e-12 or abs(determinant - 1) > 1e-12:
        raise ValueError('Principal-axes frame is not finite orthonormal and right-handed')
    return basis, {
        'frame': 'principal-axes-v1',
        'sampling': 'All exact unique source-world coordinates; lexicographic order; no UV/normal split weighting',
        'sourcePointCount': len(points), 'uniquePointCount': len(unique),
        'covarianceCentreWorld': covariance_centre.tolist(), 'covarianceFloat64': covariance.tolist(),
        'eigenvaluesDescending': eigenvalues.tolist(),
        'eigenvalueClustersHalfOpen': [list(pair) for pair in clusters],
        'tieRelativeTolerance': relative_tie_tolerance,
        'minimumEigenvalueRelativeToLargest': minimum_relative_eigenvalue,
        'axisDecisions': decisions, 'lastAxisFlippedForRightHandedness': handedness_flip,
        'basisColumnsWorld': basis.tolist(), 'basisDeterminant': determinant,
        'maximumOrthonormalResidual': orthogonal_error,
        'directionMapping': 'localDirection @ basisColumnsWorld.T',
        'pointStorage': 'Caller retains original centred world points and float32 bbox origin; orientation is applied only to support directions',
        'degenerateHandling': 'Reject unsupported covariance; no implicit world-frame or other fallback',
    }


def build_kdop26(high, low, settings, face_cap):
    bpy.context.view_layer.update()
    source = world_vertices(high)
    runtime = world_vertices(low)
    # Explicit preparation/retopology can move LOW beyond HIGH. A conservative
    # runtime proxy must contain both actual geometries, including at padding=0.
    support_points = np.concatenate((source, runtime), axis=0)
    centre = (support_points.min(axis=0) + support_points.max(axis=0)) / 2
    points = support_points - centre
    normals = np.array([direction for direction in product((-1, 0, 1), repeat=3) if any(direction)], dtype=np.float64)
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    frame = settings.get("frame", "world")
    if frame == "principal-axes-v1":
        basis, frame_report = principal_axes_frame(support_points)
        normals = normals @ basis.T
        if not np.isfinite(normals).all() or np.max(np.abs(np.linalg.norm(normals, axis=1) - 1)) > 1e-12:
            raise ValueError("Principal-axes directions are not finite unit world vectors")
    elif frame == "world":
        frame_report = {"frame": "world"}
    else:
        raise ValueError("Unknown explicit k-DOP frame")
    support = np.full(26, -math.inf)
    for start in range(0, len(points), 65536):
        support = np.maximum(support, np.max(points[start:start + 65536] @ normals.T, axis=0))
    support += settings["padding"]
    scale = float(np.max(np.ptp(points, axis=0)))
    tolerance = max(1e-9, scale * 1e-8)
    vertices = []
    # Exactly C(26,3)=2600 triples, independent of source mesh density.
    for triple in combinations(range(26), 3):
        planes = normals[list(triple)]
        if abs(float(np.linalg.det(planes))) < 1e-10:
            continue
        vertex = np.linalg.solve(planes, support[list(triple)])
        if np.max(normals @ vertex - support) > tolerance:
            continue
        if not any(np.linalg.norm(vertex - other) <= tolerance * 4 for other in vertices):
            vertices.append(vertex)
    if len(vertices) < 4 or len(vertices) > 128 or not np.isfinite(vertices).all():
        raise ValueError("k-DOP plane intersections did not produce a bounded usable polytope")
    faces = []
    for normal, limit in zip(normals, support):
        indices = [index for index, vertex in enumerate(vertices) if abs(float(np.dot(normal, vertex) - limit)) <= tolerance * 4]
        if len(indices) < 3:
            continue
        origin = np.mean([vertices[index] for index in indices], axis=0)
        reference = np.eye(3)[int(np.argmin(np.abs(normal)))]
        u = np.cross(normal, reference); u /= np.linalg.norm(u)
        v = np.cross(normal, u)
        indices.sort(key=lambda index: math.atan2(float(np.dot(vertices[index] - origin, v)), float(np.dot(vertices[index] - origin, u))))
        faces.append(indices)
    if len(faces) > face_cap:
        raise ValueError("Selected k-DOP exceeds colliderMaxFaces after coplanar plane-face merge")
    mesh = bpy.data.meshes.new(high.name + "_kdop26")
    # Store shape near its own origin, not as absolute float32 world positions.
    # Quantize the origin deliberately first, retaining its exact residual in
    # local vertices; Blender/glTF then reproduce that same float32 transform.
    origin = np.asarray(centre, dtype=np.float32).astype(np.float64)
    local_vertices = np.asarray(vertices) + (centre - origin)
    encoded_vertices = local_vertices.astype(np.float32).astype(np.float64)
    encoding_error = float(np.max(np.linalg.norm(encoded_vertices - local_vertices, axis=1)))
    encoding_limit = max(1e-7, scale * 2e-6) / 8
    if not np.isfinite(origin).all() or not math.isfinite(encoding_error) or encoding_error > encoding_limit:
        raise ValueError("k-DOP local float32 encoding exceeds supported numerical precision")
    mesh.from_pydata(encoded_vertices.tolist(), [], faces)
    mesh.update()
    collision = bpy.data.objects.new(high.name + "_COLLISION", mesh)
    bpy.context.collection.objects.link(collision)
    collision.parent = low.parent
    collision.matrix_world = Matrix.Translation(origin)
    bpy.context.view_layer.update()
    measured = collision_measure(collision, support_points)
    hull_volume = exact_hull_volume(points)
    ratio = measured["volume"] / hull_volume
    if not math.isfinite(ratio) or ratio < 1 - 1e-5 or ratio > settings["maxVolumeRatio"] + 1e-8:
        raise ValueError("Selected k-DOP volume ratio exceeds maxVolumeRatio: " + str(ratio))
    measured.update({"orientationFrame": frame_report, "method": "kdop-26", "approximation": "conservative 26-plane original-high and runtime-low union support polytope; not the exact union hull",
                     "coordinateFrame": "world-metres", "paddingMetres": settings["padding"],
                     "meshCoordinateFrame": "translation-relative; exactly representable float32 object origin",
                     "meshWorldOrigin": origin.tolist(), "maximumLocalEncodingErrorMetres": encoding_error,
                     "maximumPermittedLocalEncodingErrorMetres": encoding_limit,
                     "directions": normals.tolist(), "intersectionTriples": 2600,
                     "faceConstruction": "one ordered coplanar ngon per active support plane",
                     "sourcePart": high.name, "sourceGeometrySha256": mesh_identity(high),
                     "sourceWorldVerticesSha256": hashlib.sha256(memoryview(source)).hexdigest(),
                     "originalHighVertexCount": len(source), "runtimeLowVertexCount": len(runtime),
                     "runtimeLowPart": low.name, "runtimeLowGeometrySha256": mesh_identity(low),
                     "runtimeLowWorldVerticesSha256": hashlib.sha256(memoryview(runtime)).hexdigest(),
                     "verifiedPointSet": "original-high-and-runtime-low-union",
                     "exactUnionHullVolume": hull_volume, "volumeRatio": ratio,
                     "volumeRatioReference": "exact convex hull of original-high and runtime-low union",
                     "maxVolumeRatio": settings["maxVolumeRatio"], "colliderMaxFaces": face_cap})
    return collision, measured


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


def topology_measure(obj, allow_degenerate=False):
    mesh = bmesh.new()
    try:
        mesh.from_mesh(obj.data)
        if any(not math.isfinite(component) for vertex in mesh.verts for component in vertex.co):
            raise ValueError("Non-finite vertex coordinates")
        degenerate = sum(face.calc_area() <= 1e-12 for face in mesh.faces)
        if degenerate and not allow_degenerate:
            raise ValueError("Retopology produced degenerate faces")
        volume = mesh.calc_volume(signed=True)
        if not math.isfinite(volume):
            raise ValueError("Nonfinite signed mesh volume")
        return {"vertices": len(mesh.verts), "edges": len(mesh.edges), "faces": len(mesh.faces),
                "boundaryEdges": sum(edge.is_boundary for edge in mesh.edges),
                "nonManifoldEdges": sum(not edge.is_manifold for edge in mesh.edges),
                "inconsistentWindingEdges": sum(edge.is_manifold and not edge.is_contiguous for edge in mesh.edges),
                "nonManifoldVertices": sum(not vertex.is_manifold for vertex in mesh.verts),
                "looseVertices": sum(not vertex.link_faces for vertex in mesh.verts),
                "signedVolume": volume,
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
    for channel, bake_type in (("basecolor", "EMIT"), ("normal", "NORMAL"), ("ao", "AO"), ("roughness", "ROUGHNESS"), ("metallic", "EMIT")):
        image = bpy.data.images.new(f"part{index}_{channel}", recipe["textureSize"], recipe["textureSize"], alpha=False)
        image.colorspace_settings.name = "sRGB" if channel == "basecolor" else "Non-Color"
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        nodes.active = texture
        saved = []
        try:
            if channel in ("basecolor", "metallic"):
                seen = set()
                for source_mat in high.data.materials:
                    if not source_mat or not source_mat.use_nodes:
                        raise ValueError("Source material lacks nodes for " + channel + " baking")
                    if source_mat.as_pointer() in seen:
                        continue
                    seen.add(source_mat.as_pointer())
                    tree = source_mat.node_tree
                    surface = next((n for n in tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
                    links = [] if surface is None else [(link.from_socket, link.to_socket) for link in surface.inputs["Surface"].links]
                    if len(links) != 1 or links[0][0].node.type != "BSDF_PRINCIPLED":
                        raise ValueError(channel + " baking requires an explicitly connected Principled source surface")
                    shader = links[0][0].node
                    field = shader.inputs["Base Color" if channel == "basecolor" else "Metallic"]
                    emission = tree.nodes.new("ShaderNodeEmission")
                    # Register restoration before changing any links, including
                    # failure during a later material or the native bake call.
                    saved.append((tree, emission, links))
                    if field.is_linked:
                        tree.links.new(field.links[0].from_socket, emission.inputs["Color"])
                    elif channel == "basecolor":
                        emission.inputs["Color"].default_value = tuple(field.default_value)
                    else:
                        emission.inputs["Color"].default_value = (field.default_value,) * 3 + (1,)
                    emission.inputs["Strength"].default_value = 1
                    tree.links.new(emission.outputs[0], surface.inputs["Surface"])
            activate(low)
            high.select_set(True)
            high.hide_render = False
            status = bpy.ops.object.bake(type=bake_type)
            if status != {"FINISHED"}:
                raise ValueError("Bake did not finish: " + repr(status))
        finally:
            for tree, emission, links in reversed(saved):
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
                                         "maxRgb": maximum, "sha256": digest(path), "bakeType": bake_type,
                                         "sourceTransport": "principled-input-via-unit-emission" if channel in ("basecolor", "metallic") else "cycles-native",
                                         "colorSpace": image.colorspace_settings.name}}
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
    settings = validate_finishing_settings(job.get("finishingSettings"))
    if settings["schemaVersion"] == 2:
        from rigid_finish import finish_rigid
        return finish_rigid(job, root, source, output, result, recipe, settings, sys.modules[__name__])
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
    stages = [{"stage": "source", "sha256": original_hash, "meshNames": names},
              {"stage": "finishingSettings", "selection": "explicit" if job.get("finishingSettings") is not None else "legacy-default",
               "settings": settings}]
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
    collision_sources, collision_expected = {}, {}
    simplification_settings = settings.get("quadriFlow", {}).get("simplification")
    protected_region_totals = {region["id"]: 0 for region in simplification_settings["protectedRegions"]} if simplification_settings else {}
    root_object = bpy.data.objects.new("PROOF_TO_MODEL", None)
    bpy.context.collection.objects.link(root_object)
    for index, high in enumerate(highs):
        if not high.data.materials:
            raise ValueError("Source has no material correspondence")
        high_identity = mesh_identity(high)
        low = high.copy()
        low.data = high.data.copy()
        bpy.context.collection.objects.link(low)
        low.name = high.name + "_LOD0"
        # Bake/voxel dimensions are world metres even under transformed parents.
        world = low.matrix_world.copy()
        low.parent = None
        low.matrix_world = world
        activate(low)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        # glTF splits vertices at shading/UV seams. Weld only the working low
        # candidate before QuadriFlow; retain the untouched high for baking.
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.000001)
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        preparation = prepare_topology(low, settings["topologyPreparation"], settings.get("quadriFlow", {}).get("coordinateScale", 1))
        prepared = low.copy()
        prepared.data = low.data.copy()
        bpy.context.collection.objects.link(prepared)
        prepared.name = high.name + "_PREPARATION_SOURCE"
        prepared["sourcePart"] = names[index]
        prepared["sourceGeometrySha256"] = high_identity
        prepared["preparationMethod"] = settings["topologyPreparation"]["method"]
        prepared["preparedGeometrySha256"] = preparation["preparedGeometrySha256"]
        prepared.hide_render = True
        prepared.hide_set(True)
        preparation["preservedObject"] = prepared.name
        simplification = simplify_quadriflow_input(low, simplification_settings,
            settings.get("quadriFlow", {}).get("coordinateScale", 1), require_region_hits=len(highs) == 1)
        for identity, count in simplification.get("protectedRegionHitCounts", {}).items():
            protected_region_totals[identity] += count
        if mesh_identity(prepared) != preparation["preparedGeometrySha256"]:
            raise ValueError("Immutable voxel/prepared intermediate changed during simplification")
        target = max(6, round(recipe["targetFaces"] * len(high.data.polygons) / total_high))
        retopology = run_quadriflow(low, target, settings.get("quadriFlow", {}).get("coordinateScale", 1))
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
        if settings["collision"]["method"] == "kdop-26":
            collision, collision_report = build_kdop26(high, low, settings["collision"], recipe["colliderMaxFaces"])
        else:
            collision = low.copy()
            collision.data = low.data.copy()
            collision.data.materials.clear()
            bpy.context.collection.objects.link(collision)
            collision.name = names[index] + "_COLLISION"
            activate(collision)
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            # Operator defaults join merely near-coplanar triangles into warped
            # quads. Preserve the actual convex hull's planar triangle facets.
            hull_status = bpy.ops.mesh.convex_hull(delete_unused=True, use_existing_faces=False, join_triangles=False)
            bpy.ops.object.mode_set(mode="OBJECT")
            if hull_status != {"FINISHED"}:
                raise ValueError("Exact convex hull operator did not finish")
            if len(collision.data.polygons) > recipe["colliderMaxFaces"]:
                raise ValueError("Convex hull exceeds colliderMaxFaces; supply a simpler semantic part/recipe")
            facet_refinement = refine_exact_hull_facets(collision, world_vertices(low), recipe["colliderMaxFaces"])
            collision_report = collision_measure(collision, world_vertices(low))
            collision_report.update({"method": "exact-hull", "sourcePart": low.name,
                                     "sourceGeometrySha256": mesh_identity(low),
                                     "constructionRefinement": facet_refinement,
                                     "approximation": "exact convex hull of runtime low vertices; legacy behavior"})
        collision["collision"] = True
        collision["collisionMethod"] = settings["collision"]["method"]
        collision["semanticPart"] = names[index]
        collision_faces = len(collision.data.polygons)
        if collision_faces > recipe["colliderMaxFaces"]:
            raise ValueError("Convex hull exceeds colliderMaxFaces; supply a simpler semantic part/recipe")
        collision.hide_render = True
        exports.append(collision)
        collision_sources[collision.name] = (np.concatenate((world_vertices(high), world_vertices(low)), axis=0)
                                              if settings["collision"]["method"] == "kdop-26" else world_vertices(low))
        collision_expected[collision.name] = collision_report
        if mesh_identity(high) != high_identity:
            raise ValueError("Immutable imported high geometry changed during finishing")
        part_reports.append({"part": names[index], "targetFaces": target, "faces": len(low.data.polygons),
                             "triangles": base_triangles, "uv": uv, "topology": topology, "lods": lod_report,
                             "preparation": preparation, "retopology": retopology, "collision": collision_report,
                             "simplification": simplification,
                             "sourceGeometrySha256": high_identity, "immutableHighGeometryPreserved": True,
                             "bakeMaps": {channel: value["measurement"] for channel, value in maps.items()},
                             "colliderFaces": collision_faces, "sourceMaterials": len(high.data.materials)})
    if any(count == 0 for count in protected_region_totals.values()):
        raise ValueError("Configured protected regions must hit at least one prepared vertex across the asset: "
                         + json.dumps(protected_region_totals, sort_keys=True))
    if simplification_settings:
        stages.append({"stage": "explicitWorkingInputSimplification", "protectedRegionHitCountsAcrossParts": protected_region_totals,
                       "triangleCapScope": "each prepared semantic part / QuadriFlow call",
                       "protectedRegionScope": "asset world metres; each configured region hits at least one prepared vertex"})
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
    reimported_collision = []
    for obj in imported:
        if obj.get("collision"):
            if obj.name not in collision_sources:
                raise ValueError("Reimported collision has no exact source-part lineage")
            expected = collision_expected[obj.name]
            reference = collision_sources[obj.name]
            imported_low = []
            if expected["method"] == "kdop-26":
                imported_low = [candidate for candidate in imported if not candidate.get("collision")
                                and candidate.get("lodLevel") == 0
                                and candidate.get("semanticPart") == obj.get("semanticPart")]
                if len(imported_low) != 1:
                    raise ValueError("Reimported k-DOP requires exactly one matching actual LOD0 mesh")
                reference = np.concatenate((reference, world_vertices(imported_low[0])), axis=0)
            measured = collision_measure(obj, reference)
            if imported_low:
                measured["preExportReferenceVertexCount"] = len(collision_sources[obj.name])
                measured["postImportRuntimeLowVertexCount"] = len(imported_low[0].data.vertices)
                measured["verifiedPointSet"] = "original-high-and-pre-export-low-union-plus-actual-reimported-lod0"
            if (measured["coplanarFaceGroups"] > recipe["colliderMaxFaces"]
                    or abs(measured["volume"] - expected["volume"]) > max(1e-9, expected["volume"] * 1e-5)):
                raise ValueError("Independent collision re-import exceeds face cap or changes volume")
            measured["name"] = obj.name
            reimported_collision.append(measured)
        else:
            uv_measure(obj)
    if digest(source) != original_hash or digest(preserved) != original_hash:
        raise ValueError("Immutable source changed")
    stages.extend([{"stage": "quadriFlowUvBakeLodCollision", "parts": part_reports,
                    "bakeChannels": ["basecolor", "normal", "ao", "roughness", "metallic"],
                    "normalSpace": "TANGENT", "cageExtrusion": recipe["cageExtrusion"],
                    "maxRayDistance": recipe["maxRayDistance"]},
                   {"stage": "independentReimport", "meshCount": len(imported), "textures": len(imported_images),
                    "bounds": actual_bounds, "collision": reimported_collision, "verified": True}])
    report = output / "report.json"
    artifacts = {"blend": relative(root, blend), "glb": relative(root, glb),
                 "report": relative(root, report), "source": relative(root, preserved)}
    artifacts.update({"texture" + str(i): relative(root, path) for i, path in enumerate(textures)})
    payload = {"schemaVersion": 1, "status": "prepared", "artifacts": artifacts,
               "measurements": {"triangles": total_triangles, "materials": material_count,
                                "textureBytes": texture_bytes, "embeddedTextureBytes": packed_texture_bytes,
                                "parts": part_reports},
               "stages": stages, "inputSha256": original_hash, "finishingSettings": settings,
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
