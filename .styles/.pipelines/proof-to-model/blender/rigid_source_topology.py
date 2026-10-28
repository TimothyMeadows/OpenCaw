"""Explicit reviewed source-corner ownership; never a coordinate-weld fallback.

The caller admits the task-local dependency against settings/authoring evidence.
This module validates its bytes and selected LOW/node identities, then reuses the
rigid finisher's sole oriented corner mapper. Copies belong to the caller. No
receipt establishes manifoldness, physical clearance, normals or model quality.
"""
import hashlib
import json
from pathlib import Path
import re

import bpy
import numpy as np


METHOD = 'reviewed-source-corners-v1'
_MAX_BYTES = 67108864
_MAX_CORNERS = 16777216
_HASH = re.compile(r'[a-f0-9]{64}', re.ASCII)
_HEX = re.compile(r'[a-f0-9]*', re.ASCII)
_ROOT_FIELDS = {'schemaVersion', 'kind', 'preparedGlbSha256', 'meshes'}
_MESH_FIELDS = {'node', 'fileNodeIndex', 'sourceVertexCount', 'indexedCorners',
                'ownersI32LEHex', 'ownersSha256'}


def _integer(value, minimum, maximum, label):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError(label + ' must be a bounded integer token')
    return value


def _hash(value, label):
    if type(value) is not str or not _HASH.fullmatch(value):
        raise ValueError(label + ' must be lowercase SHA256')
    return value


def _name(value):
    if type(value) is not str or not value or len(value) > 256 or '\x00' in value:
        raise ValueError('Source topology requires an exact bounded node name')
    return value


def _path(value, *, receipt=False):
    path = Path(value)
    if '..' in path.parts:
        raise ValueError('Source topology path traversal is forbidden')
    path = path.absolute()
    for cursor in (path, *path.parents):
        if cursor.is_symlink() or getattr(cursor, 'is_junction', lambda: False)():
            raise ValueError('Source topology paths cannot traverse links/junctions')
    path = path.resolve(strict=True)
    if not path.is_file():
        raise ValueError('Source topology input must be an existing regular file')
    if receipt:
        parts = path.parts
        roots = [i for i in range(len(parts) - 3)
                 if parts[i:i + 3] == ('.opencaw', '.cache', 'tasks')]
        if not roots or any(i + 4 >= len(parts) for i in roots) or path.suffix != '.json':
            raise ValueError('Receipt must be a confined task-local .json dependency')
    return path


def _digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            result.update(block)
    return result.hexdigest()


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate source topology field: ' + key)
        result[key] = value
    return result


def _read_receipt(path, expected):
    if path.stat().st_size > _MAX_BYTES:
        raise ValueError('Source topology receipt exceeds64MiB')
    raw = path.read_bytes()
    if len(raw) > _MAX_BYTES or hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError('Source topology receipt bytes differ from admitted SHA256')
    text = raw.decode('utf-8')
    # Bound nesting before json.loads, including malformed deep documents.
    depth = 0
    quoted = escaped = False
    for char in text:
        if quoted:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char in '[{':
            depth += 1
            if depth > 12:
                raise ValueError('Source topology receipt exceeds depth12')
        elif char in ']}':
            depth -= 1
    def invalid_constant(value):
        raise ValueError('Nonfinite JSON token: ' + value)
    return json.loads(text, object_pairs_hook=_unique, parse_constant=invalid_constant)


def _reader(path, rigid, maximum):
    _integer(maximum, 20, 2147483647, 'Prepared GLB byte bound')
    reader = rigid._snv_Glb(path, maximum)
    # Reuse the existing bounded GLB eligibility and world-frame implementation.
    rigid._nfb_validate_document(reader)
    return reader, hashlib.sha256(reader.raw).hexdigest()


def _entry(row, reader):
    if type(row) is not dict or set(row) != _MESH_FIELDS:
        raise ValueError('Source topology mesh has unknown/missing fields')
    node = _name(row['node'])
    index = _integer(row['fileNodeIndex'], 0, 1000000, 'File node index')
    vertices = _integer(row['sourceVertexCount'], 1, 8000000, 'Source vertex count')
    corners = _integer(row['indexedCorners'], 3, _MAX_CORNERS, 'Indexed corners')
    if corners % 3:
        raise ValueError('Indexed corner count must be a multiple of3')
    payload = row['ownersI32LEHex']
    if type(payload) is not str or len(payload) != corners * 8 or not _HEX.fullmatch(payload):
        raise ValueError('Owner bytes require exact lowercase LEi32 hex cardinality')
    raw = bytes.fromhex(payload)
    if hashlib.sha256(raw).hexdigest() != _hash(row['ownersSha256'], 'Owners SHA256'):
        raise ValueError('Owner bytes differ from their SHA256')
    owners = np.frombuffer(raw, dtype='<i4')
    if np.any(owners < 0) or np.any(owners >= vertices) or len(np.unique(owners)) != vertices:
        raise ValueError('Every declared source owner must be covered and in range')
    nodes = reader.document['nodes']
    if index >= len(nodes) or nodes[index].get('name') != node or 'mesh' not in nodes[index]:
        raise ValueError('Receipt file node identity differs from actual GLB')
    matches = [i for i, value in enumerate(nodes) if value.get('name') == node]
    if matches != [index]:
        raise ValueError('Receipt node is missing or ambiguous')
    mesh = reader.document['meshes'][nodes[index]['mesh']]
    actual = sum(reader.accessor(p['indices'], 'index', 1).size for p in mesh['primitives'])
    if actual != corners:
        raise ValueError('Receipt indexed corners differ from actual GLB primitives')
    return owners, vertices


def _readonly(array):
    result = np.asarray(array).copy()
    result.flags.writeable = False
    return result


def _topology(obj, rigid):
    mesh = obj.data
    if obj.type != 'MESH' or obj.mode != 'OBJECT' or obj.modifiers or obj.constraints or obj.animation_data or mesh.shape_keys or mesh.animation_data:
        raise ValueError('Source topology requires a static object-mode mesh')
    values = {
        'vertices': len(mesh.vertices),
        'loopVertices': rigid._nfa_field(mesh.loops, 'vertex_index', np.int32, 1).reshape(-1),
        'loopEdges': rigid._nfa_field(mesh.loops, 'edge_index', np.int32, 1).reshape(-1),
        'edges': rigid._nfa_field(mesh.edges, 'vertices', np.int32, 2),
        'starts': rigid._nfa_field(mesh.polygons, 'loop_start', np.int32, 1).reshape(-1),
        'totals': rigid._nfa_field(mesh.polygons, 'loop_total', np.int32, 1).reshape(-1),
    }
    count = len(values['loopVertices'])
    if not 3 <= count <= _MAX_CORNERS or np.any(values['totals'] != 3) or not np.array_equal(values['starts'], np.arange(len(values['starts'])) * 3):
        raise ValueError('Consecutive source triangles and stable loop order are required')
    return values


def _topology_sha(values):
    digest = hashlib.sha256(str(values['vertices']).encode('ascii'))
    for key in ('loopVertices', 'loopEdges', 'edges', 'starts', 'totals'):
        digest.update(key.encode('ascii'))
        digest.update((str(values[key].shape) + '\0').encode('ascii'))
        digest.update(values[key].astype('<i4', copy=False).tobytes())
    return digest.hexdigest()


def _owner_positions(obj, rigid, owners, count, topology):
    points = rigid._nfa_field(obj.data.vertices, 'co', np.float32, 3)
    if not np.isfinite(points).all():
        raise ValueError('Source owner positions must be finite')
    current = points[topology['loopVertices']]
    first = np.full(count, len(owners), np.int32)
    np.minimum.at(first, owners, np.arange(len(owners), dtype=np.int32))
    if np.any(first == len(owners)):
        raise ValueError('Current loop graph omits a declared owner')
    result = current[first].copy()
    # Numeric float32 equality deliberately ignores signed zero for geometry only.
    if not np.array_equal(current, result[owners]):
        raise ValueError('One source owner has inconsistent current corner positions')
    return result


def _source_guard(obj, rigid):
    return (rigid._normal_raw_mesh_state(obj.data), rigid._normal_node_state(obj))


def _dispose(obj, mesh):
    if obj is not None:
        try:
            if obj.as_pointer():
                bpy.data.objects.remove(obj, do_unlink=True)
        except ReferenceError:
            pass
    if mesh is not None:
        try:
            if mesh.as_pointer() and mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        except ReferenceError:
            pass


class Binding:
    """Trusted in-RAM source-corner binding, established by load(), not JSON."""
    __slots__ = ('_reader', '_prepared_path', '_prepared_sha', '_receipt_sha', '_node',
                 '_index', '_count', '_file_owners', '_file_sha', '_loop_owners',
                 '_loop_sha', '_graph_sha', '_object_pointer', '_contact_lods')

    def __init__(self, reader, prepared_path, prepared_sha, receipt_sha, row, owners, count):
        self._reader, self._prepared_path = reader, prepared_path
        self._prepared_sha, self._receipt_sha = prepared_sha, receipt_sha
        self._node, self._index, self._count = row['node'], row['fileNodeIndex'], count
        self._file_owners = _readonly(owners)
        self._file_sha = row['ownersSha256']
        self._loop_owners = self._loop_sha = self._graph_sha = self._object_pointer = None
        self._contact_lods = {}

    @property
    def native_loop_owners(self):
        if self._loop_owners is None:
            raise ValueError('Bind the actual imported object before accessing loop owners')
        view = self._loop_owners.view()
        view.flags.writeable = False
        return view

    def summary(self):
        return {'method': METHOD, 'node': self._node, 'fileNodeIndex': self._index,
                'sourceVertexCount': self._count, 'indexedCorners': len(self._file_owners),
                'preparedGlbSha256': self._prepared_sha, 'receiptSha256': self._receipt_sha,
                'ownersSha256': self._file_sha, 'nativeLoopsBound': self._loop_owners is not None,
                'physicalTopologyOrNormalQualityClaimed': False}

    def _bind(self, obj, rigid):
        if self._loop_owners is None and obj.name != self._node:
            raise ValueError('Source topology binding requires its unchanged node name')
        rigid._snv_matrix(np.asarray(obj.matrix_world, np.float64), 'source-owned current frame')
        if self._file_owners.flags.writeable or hashlib.sha256(self._file_owners.tobytes()).hexdigest() != self._file_sha:
            raise ValueError('Private source ownership was altered')
        topology = _topology(obj, rigid)
        if len(topology['loopVertices']) != len(self._file_owners):
            raise ValueError('Current native corner count differs from receipt')
        if self._loop_owners is None:
            if _digest(self._prepared_path) != self._prepared_sha:
                raise ValueError('Prepared GLB changed before native ownership binding')
            rigid._nfb_verify_native_frame(obj, self._reader)
            geometry, unused_normals, mapping, unused_ranges = rigid._normal_source_geometry(obj, self._reader)
            mapping = np.asarray(mapping)
            if mapping.shape != (len(self._file_owners),) or not np.array_equal(np.sort(mapping), np.arange(len(mapping))):
                raise ValueError('Existing mapper did not prove a full stored-corner bijection')
            if not geometry.get('allSelectedGeometryAndCornerOwnershipBound'):
                raise ValueError('Existing mapper did not bind selected geometry')
            owners = _readonly(self._file_owners[mapping])
            _owner_positions(obj, rigid, owners, self._count, topology)
            self._loop_owners = owners
            self._loop_sha = hashlib.sha256(owners.tobytes()).hexdigest()
            self._graph_sha, self._object_pointer = _topology_sha(topology), obj.as_pointer()
        else:
            if self._loop_owners.flags.writeable or hashlib.sha256(self._loop_owners.tobytes()).hexdigest() != self._loop_sha:
                raise ValueError('Private native-loop ownership was altered')
            if obj.as_pointer() != self._object_pointer or _topology_sha(topology) != self._graph_sha:
                raise ValueError('Bound loop indices/order/start/count/edge graph changed')
        return topology, _owner_positions(obj, rigid, self._loop_owners, self._count, topology)

    def _validate_current_graph(self, obj, rigid):
        """Private provenance survives a caller-owned rename/UV edit/rebase only
        while the same object and complete indexed loop/edge graph survive.
        This validates current consistency, not original coordinates or normals.
        """
        if self._loop_owners is None:
            raise ValueError('Final-output capture requires an already bound source object')
        return self._bind(obj, rigid)

    def _copy(self, obj, rigid, rich):
        before = _source_guard(obj, rigid)
        mesh = candidate = None
        try:
            topology, points = self._bind(obj, rigid)
            mesh = bpy.data.meshes.new(self._node + '.source-owned.mesh')
            mesh.from_pydata(points.tolist(), [], self._loop_owners.reshape((-1, 3)).tolist())
            mesh.update()
            if not np.array_equal(rigid._nfa_field(mesh.loops, 'vertex_index', np.int32, 1).reshape(-1), self._loop_owners):
                raise ValueError('Native source-owned reconstruction changed loop order')
            # Preserve the parent's transform channels and basis. Assigning a
            # world matrix to a new object can re-encode rotation by an ULP.
            candidate = obj.copy()
            candidate.data = mesh
            candidate.name = self._node + '.source-owned'
            bpy.context.collection.objects.link(candidate)
            bpy.context.view_layer.update()
            if rich:
                for material in obj.data.materials:
                    mesh.materials.append(material)
                for source, target in zip(obj.data.polygons, mesh.polygons):
                    target.material_index, target.use_smooth = source.material_index, source.use_smooth
                for layer in obj.data.uv_layers:
                    target = mesh.uv_layers.new(name=layer.name)
                    target.active_render, target.active_clone = layer.active_render, layer.active_clone
                    values = rigid._nfa_field(layer.data, 'uv', np.float32, 2)
                    target.data.foreach_set('uv', values.reshape(-1))
                    if rigid._nfa_field(target.data, 'uv', np.float32, 2).tobytes() != values.tobytes():
                        raise ValueError('Reindexed UV corner bits differ')
                if obj.data.uv_layers:
                    mesh.uv_layers.active_index = obj.data.uv_layers.active_index
                edge_flags = {}
                for polygon in obj.data.polygons:
                    loops = tuple(polygon.loop_indices)
                    for i, loop in enumerate(loops):
                        key = tuple(sorted((int(self._loop_owners[loop]), int(self._loop_owners[loops[(i + 1) % 3]]))))
                        edge = obj.data.edges[int(topology['loopEdges'][loop])]
                        flags = (edge.use_seam, edge.use_edge_sharp)
                        if key in edge_flags and edge_flags[key] != flags:
                            raise ValueError('Source-owned edge has ambiguous seam/sharp flags')
                        edge_flags[key] = flags
                for edge in mesh.edges:
                    edge.use_seam, edge.use_edge_sharp = edge_flags[tuple(sorted(edge.vertices))]
                # A new graph has a new custom-normal basis. Leave codes absent;
                # caller authors derivative geometric normals and verifies them.
                if mesh.attributes.get('custom_normal') is not None:
                    raise ValueError('Unexpected inherited source-normal codes')
            mesh.update()
            rigid._snv_matrix(np.asarray(candidate.matrix_world, np.float64), 'source-owned copy frame')
            if not np.array_equal(np.asarray(candidate.matrix_world), np.asarray(obj.matrix_world)):
                raise ValueError('Source-owned copy frame differs')
            return candidate
        except BaseException:
            _dispose(candidate, mesh)
            raise
        finally:
            try:
                unchanged = _source_guard(obj, rigid) == before
            except BaseException:
                _dispose(candidate, mesh)
                raise
            if not unchanged:
                # The source is never restored from evidence or silently repaired.
                _dispose(candidate, mesh)
                raise ValueError('Reviewed source changed during source-owned copy')

    def contact_lod_names(self):
        return frozenset(self._contact_lods)

    def discard_contact_lods_after(self, original_names):
        for name in tuple(self._contact_lods):
            if name not in original_names:
                del self._contact_lods[name]

    def remember_contact_lod(self, obj, certificates, physical_proofs, rigid):
        return _remember_contact_lod(self,obj,certificates,physical_proofs,rigid)

    def inspection_copy(self, obj, rigid):
        """Topology-only owned copy; caller must run unchanged topology guards."""
        return self._copy(obj, rigid, False)

    def reindex_copy(self, obj, rigid, preserve_loops=True):
        """Owned LOD input with exact UV/material/smooth corners; normals unauthored."""
        if preserve_loops is not True:
            raise ValueError('Only explicit loop-order-preserving reconstruction is supported')
        return self._copy(obj, rigid, True)

    def uv_helper_topology(self, obj, rigid):
        """Read-only owner graph for a geometric UV helper, never a runtime edit."""
        before = _source_guard(obj, rigid)
        try:
            topology, unused_points = self._bind(obj, rigid)
            owners = self.native_loop_owners
            first = np.full(self._count, len(owners), np.int32)
            np.minimum.at(first, owners, np.arange(len(owners), dtype=np.int32))
            if np.any(first == len(owners)):
                raise ValueError('UV helper cannot omit a reviewed source owner')
            return {
                'nativeVertexForOwner': _readonly(topology['loopVertices'][first]),
                'triangleOwners': _readonly(owners.reshape((-1, 3))),
                'nativeLoopVertices': _readonly(topology['loopVertices']),
                'proof': dict(self.summary(), currentGraphSha256=_topology_sha(topology),
                              nativeLoopOwnersSha256=self._loop_sha,
                              nativeVertexCount=topology['vertices'],
                              helperVertexCount=self._count,
                              triangleCount=len(owners) // 3,
                              sourceMutation=False, coordinateWeld=False),
            }
        finally:
            if _source_guard(obj, rigid) != before:
                raise ValueError('Reviewed source changed during UV helper mapping')


def capture(path, objects, rigid, *, max_file_bytes, bindings=None):
    """Return receipt DICT from authored native owner IDs in actual FILE order."""
    path = _path(path)
    reader, prepared_sha = _reader(path, rigid, max_file_bytes)
    if type(objects) not in (list, tuple) or not 1 <= len(objects) <= 512:
        raise ValueError('Capture requires an explicitly bounded object list')
    if len({obj.name for obj in objects}) != len(objects) or len({obj.as_pointer() for obj in objects}) != len(objects):
        raise ValueError('Capture requires1..512 unique authored LOW objects')
    if bindings is None:
        bindings = {}
    if type(bindings) is not dict or set(bindings) - {obj.name for obj in objects} or any(type(value) is not Binding for value in bindings.values()):
        raise ValueError('Capture bindings must be private Binding values keyed by selected current node names')
    rows = []
    estimated_bytes = len(json.dumps({'schemaVersion': 1, 'kind': 'rigid-source-corner-topology',
        'preparedGlbSha256': prepared_sha, 'meshes': []}, separators=(',', ':')).encode('utf-8'))
    for obj in objects:
        before = _source_guard(obj, rigid)
        rigid._nfb_verify_native_frame(obj, reader)
        geometry, unused_normals, mapping, unused_ranges = rigid._normal_source_geometry(obj, reader, preexport=True)
        topology = _topology(obj, rigid)
        binding = bindings.get(obj.name)
        if binding is not None:
            binding._validate_current_graph(obj, rigid)
            native_owners = binding.native_loop_owners
            count = binding._count
        else:
            native_owners = topology['loopVertices']
            count = len(obj.data.vertices)
        count = _integer(count, 1, 8000000, 'Authored source vertex count')
        corners = _integer(geometry['indexedCorners'], 3, _MAX_CORNERS, 'Authored indexed corners')
        row = {'node': obj.name, 'fileNodeIndex': rigid._nfb_node_index(reader, obj.name),
               'sourceVertexCount': count, 'indexedCorners': corners,
               'ownersI32LEHex': '', 'ownersSha256': '0' * 64}
        estimated_bytes += len(json.dumps(row, separators=(',', ':'), ensure_ascii=False).encode('utf-8')) + corners * 8 + bool(rows)
        if estimated_bytes > _MAX_BYTES:
            raise ValueError('Captured receipt exceeds64MiB before owner/hex allocation')
        mapping = np.asarray(mapping)
        if mapping.shape != (corners,) or not np.array_equal(np.sort(mapping), np.arange(corners)):
            raise ValueError('Existing authoring mapper did not prove every FILE corner')
        owners = np.empty(corners, dtype='<i4')
        owners[mapping] = native_owners
        raw = owners.tobytes()
        row.update(ownersI32LEHex=raw.hex(), ownersSha256=hashlib.sha256(raw).hexdigest())
        _entry(row, reader)
        if _source_guard(obj, rigid) != before:
            raise ValueError('Authored source changed during topology capture')
        rows.append(row)
    receipt = {'schemaVersion': 1, 'kind': 'rigid-source-corner-topology',
               'preparedGlbSha256': prepared_sha, 'meshes': rows}
    if len(json.dumps(receipt, separators=(',', ':'), ensure_ascii=False).encode('utf-8')) > _MAX_BYTES:
        raise ValueError('Captured receipt exceeds64MiB; never truncate owners')
    if _digest(path) != prepared_sha:
        raise ValueError('Prepared GLB changed during source topology capture')
    return receipt


def load(receipt_path, prepared_path, handoff, rigid, *, expected_receipt_sha256, max_file_bytes):
    """Validate selected immutable evidence; return node->private Binding subset."""
    receipt_path, prepared_path = _path(receipt_path, receipt=True), _path(prepared_path)
    expected = _hash(expected_receipt_sha256, 'Expected receipt SHA256')
    document = _read_receipt(receipt_path, expected)
    if type(document) is not dict or set(document) != _ROOT_FIELDS or type(document['schemaVersion']) is not int or document['schemaVersion'] != 1 or document['kind'] != 'rigid-source-corner-topology':
        raise ValueError('Unknown/malformed source topology receipt version or fields')
    if type(handoff) is not dict:
        raise ValueError('Reviewed rigid handoff object is required')
    reader, prepared_sha = _reader(prepared_path, rigid, max_file_bytes)
    if _hash(document['preparedGlbSha256'], 'Prepared GLB SHA256') != prepared_sha or handoff.get('preparedGlbSha256') != prepared_sha:
        raise ValueError('Receipt/prepared GLB/reviewed handoff hashes differ')
    parts = handoff.get('parts')
    if type(parts) is not list or not parts or any(type(part) is not dict for part in parts):
        raise ValueError('Reviewed rigid handoff parts are required')
    lows = [part.get('lowObject') for part in parts]
    if any(type(node) is not str for node in lows) or len(set(lows)) != len(lows):
        raise ValueError('Reviewed handoff LOW names must be unique')
    rows = document['meshes']
    if type(rows) is not list or not 1 <= len(rows) <= 512:
        raise ValueError('Receipt requires1..512 selected LOW mesh entries')
    result = {}
    for row in rows:
        owners, count = _entry(row, reader)
        if row['node'] not in lows or row['node'] in result:
            raise ValueError('Receipt mesh is not a unique selected handoff LOW')
        result[row['node']] = Binding(reader, prepared_path, prepared_sha, expected, row, owners, count)
    return result


def _contact_lod_frames(low0, lod, expected, *, decoded=False):
    a=np.asarray(low0.matrix_world,np.float64);b=np.asarray(lod.matrix_world,np.float64);expected=np.asarray(expected,np.float64)
    if any(value.shape!=(4,4)or not np.isfinite(value).all()for value in (a,b,expected)):raise ValueError('Finite explicit protected LOW0/LOD frames required')
    relative=float(np.max(np.abs(a-b)));source=float(max(np.max(np.abs(a-expected)),np.max(np.abs(b-expected))))
    if decoded:
        if relative>1e-6 or source>1e-6:raise ValueError('Decoded protected LOW0/LOD world frames diverged from their common source frame')
    elif not np.array_equal(a,expected)or not np.array_equal(b,expected):raise ValueError('Working protected LOW0/LOD world frame changed before capture')
    return {'workingFramesExact':not decoded,'decodedFrameMaximumDifference':relative,'maximumDifferenceFromWorkingSourceFrame':source,'decodedFrameExistingMaximumAllowedError':1e-6 if decoded else 0}

def _contact_lod_sha(record):
    digest=hashlib.sha256((record['name']+'\0'+record['geometrySha256']).encode())
    for key in ('owners','components','frame'):
        value=record[key]
        if value.flags.writeable:raise ValueError('Private contact LOD arrays became mutable')
        digest.update(key.encode());digest.update(value.tobytes())
    for cert in record['certificates']:digest.update(cert['sha256'].encode())
    for proof in record['physicalProofs']:digest.update(proof.encode())
    return digest.hexdigest()

def _remember_contact_lod(binding, obj, certificates, physical_proofs, rigid):
    if obj.name in binding._contact_lods:raise ValueError('Contact LOD identity already registered')
    owners=rigid._clod_contact_owners(obj.data)
    if np.any(owners<0):raise ValueError('Protected owner identity must use nonnegative0/unheld sentinel')
    attribute=obj.data.attributes.get(rigid._clod_COMPONENT_ATTRIBUTE)
    if attribute is None:raise ValueError('Contact LOD component lineage absent')
    components=rigid._nfa_field(attribute.data,'value',np.int32,1).reshape(-1)
    for cert in certificates:
        if rigid._clod_contact_cert_sha(cert)!=cert['sha256']:raise ValueError('Altered original protected triangle certificate')
    if type(physical_proofs)is not list or len(physical_proofs)!=len(certificates):raise ValueError('Complete selected boundary physical proofs required')
    signatures=rigid._clod_contact_component_signatures(obj)
    for cert,proof in zip(certificates,physical_proofs):
        if proof.get('completeWithinBoundary')is not True or any(proof.get(key)!=0 for key in ('properCrossings','coplanarPositiveArea','unreviewedContact'))or proof.get('geometrySignature')!=signatures.get(cert['componentId']):raise ValueError('Selected exact physical proof is not bound to actual assembled boundary geometry')
    row={'physicalProofs':tuple(json.dumps(proof,sort_keys=True,separators=(',',':'),allow_nan=False)for proof in physical_proofs),'name':obj.name,'owners':_readonly(owners),'components':_readonly(components),'frame':_readonly(np.asarray(obj.matrix_world,np.float64)),
        'geometrySha256':rigid._clod_triangle_signature(obj,include_uv=True),'certificates':tuple(certificates)}
    row['sha256']=_contact_lod_sha(row);binding._contact_lods[obj.name]=row
    return {'method':'protected-contact-rings-v1','name':obj.name,'privateProofSha256':row['sha256'],'protectedTriangles':sum(len(c['faces'])for c in certificates),'negativeBoundariesRetainedExactly':sum(c['negative']for c in certificates),'reimportVerificationRequired':True}

def _contact_rows(obj, loop_owners, rigid, *, forward_file=False):
    topology=_topology(obj,rigid);positions=rigid._nfa_field(obj.data.vertices,'co',np.float32,3)[topology['loopVertices']].reshape((-1,3,3))
    uvs=np.empty((len(obj.data.polygons),len(obj.data.uv_layers),3,2),np.float32)
    for i,layer in enumerate(obj.data.uv_layers):uvs[:,i]=rigid._nfa_field(layer.data,'uv',np.float32,2).reshape((-1,3,2))
    if forward_file:
        positions=positions[:,:,[0,2,1]].copy();positions[:,:,2]*=np.float32(-1)
        uvs=uvs.copy();uvs[:,:,:,1]=np.float32(1)-uvs[:,:,:,1]
    labels=np.asarray(loop_owners,np.int32).reshape((-1,3));rows={}
    for index,face in enumerate(obj.data.polygons):
        ids=tuple(int(x)for x in labels[index])
        if any(v<=0 for v in ids):continue
        key=rigid._clod_contact_face_key(ids)
        shift=next(k for k in range(3)if ids[k:]+ids[:k]==key)
        material=obj.data.materials[face.material_index].name if obj.data.materials else None
        point=np.roll(positions[index],-shift,axis=0).copy();point[point==0]=np.float32(0)
        value=(point.tobytes(),np.roll(uvs[index],-shift,axis=1).tobytes(),material)
        if key in rows:raise ValueError('Ambiguous duplicate original-owner protected FILE/native triangle')
        rows[key]=value
    return rows

def capture_contact_lods(path, objects, low0_by_part, bindings, rigid, *, max_file_bytes):
    """Private PRE-to-real-FILE proof; no runtime owner attributes are required."""
    reader,glb_sha=_reader(_path(path),rigid,max_file_bytes);by_name={obj.name:obj for obj in objects};result={}
    if len(by_name)!=len(objects):raise ValueError('Unique actual contact LOD export objects required')
    for part,binding in bindings.items():
        if binding is None:continue
        if type(binding)is not Binding:raise ValueError('Private selected source binding required')
        if not binding._contact_lods:continue
        low=low0_by_part[part];binding._validate_current_graph(low,rigid)
        unused,unused_normals,low_mapping,unused_ranges=rigid._normal_source_geometry(low,reader,preexport=True)
        low_rows=_contact_rows(low,binding.native_loop_owners+1,rigid,forward_file=True)
        for name,stored in binding._contact_lods.items():
            obj=by_name.get(name)
            if obj is None or _contact_lod_sha(stored)!=stored['sha256']:raise ValueError('Missing/stale private contact LOD expectation')
            if rigid._clod_triangle_signature(obj,include_uv=True)!=stored['geometrySha256']or not np.array_equal(np.asarray(obj.matrix_world),stored['frame']):raise ValueError('Contact LOD changed between assembly and real export')
            frame_check=_contact_lod_frames(low,obj,stored['frame'])
            native_owners=rigid._clod_contact_owners(obj.data)
            if native_owners.tobytes()!=stored['owners'].tobytes():raise ValueError('Private protected owner IDs changed before export')
            unused,unused_normals,mapping,unused_ranges=rigid._normal_source_geometry(obj,reader,preexport=True)
            mapping=np.asarray(mapping,np.int32);topology=_topology(obj,rigid)
            if not np.array_equal(np.sort(mapping),np.arange(len(mapping))):raise ValueError('Actual contact FILE mapping is not a full corner bijection')
            file_original=np.empty(len(mapping),np.int32);file_original[mapping]=native_owners[topology['loopVertices']]
            file_indexed=np.empty(len(mapping),np.int32);file_indexed[mapping]=topology['loopVertices']
            lod_rows=_contact_rows(obj,native_owners[topology['loopVertices']],rigid,forward_file=True)
            keys={rigid._clod_contact_face_key(row)for cert in stored['certificates']for row in cert['faces']}
            if any(key not in low_rows or key not in lod_rows or low_rows[key]!=lod_rows[key]for key in keys):raise ValueError('Protected LOD FILE triangle differs from original LOW0 FILE positions/winding/material/UV')
            row={'sourcePart':part,'glbSha256':glb_sha,'name':name,'record':stored,'fileOriginalOwners':_readonly(file_original),'fileIndexedOwners':_readonly(file_indexed),
                'preExportFrameCheck':frame_check,'protectedKeys':tuple(sorted(keys)),'workingProtectedTrianglesVerified':True,'actualLow0AndLodFileUvPositionMaterialExact':True}
            row['fileOriginalOwnersSha256']=hashlib.sha256(file_original.tobytes()).hexdigest();row['fileIndexedOwnersSha256']=hashlib.sha256(file_indexed.tobytes()).hexdigest()
            result[name]=row
    if {name for binding in bindings.values()if binding is not None for name in binding._contact_lods}!=set(result):raise ValueError('Incomplete protected contact export coverage')
    return result

def verify_contact_lod_reimport(obj, context, low0, low0_binding, lod_binding, rigid):
    """Bind actual FILE corners, rebuild proven indexed shadow, never mutate imports."""
    if type(lod_binding)is not Binding or type(low0_binding)is not Binding or context['name']!=obj.name:raise ValueError('Explicit protected contact/LOW0 reimport identities required')
    if lod_binding._prepared_sha!=context['glbSha256']or low0_binding._prepared_sha!=context['glbSha256']:raise ValueError('Contact verification used stale actual GLB')
    stored=context['record']
    if _contact_lod_sha(stored)!=stored['sha256']:raise ValueError('Altered protected LOD private source proof')
    for key,hashkey in (('fileOriginalOwners','fileOriginalOwnersSha256'),('fileIndexedOwners','fileIndexedOwnersSha256')):
        value=context[key]
        if value.flags.writeable or hashlib.sha256(value.tobytes()).hexdigest()!=context[hashkey]:raise ValueError('Private actual FILE owner map changed')
    if not np.array_equal(context['fileIndexedOwners'],lod_binding._file_owners):raise ValueError('Actual source-topology receipt and protected FILE owner maps differ')
    topology,unused=lod_binding._bind(obj,rigid);low0_binding._bind(low0,rigid)
    frame_check=_contact_lod_frames(low0,obj,stored['frame'],decoded=True)
    unused,unused_normals,mapping,unused_ranges=rigid._normal_source_geometry(obj,lod_binding._reader)
    labels=context['fileOriginalOwners'][np.asarray(mapping,np.int32)]
    low_rows=_contact_rows(low0,low0_binding.native_loop_owners+1,rigid)
    lod_rows=_contact_rows(obj,labels,rigid)
    if any(key not in low_rows or key not in lod_rows or low_rows[key]!=lod_rows[key]for key in context['protectedKeys']):raise ValueError('Actual decoded LOD protected UV/positions/material differ from actual decoded LOW0')
    shadow=lod_binding.reindex_copy(obj,rigid,preserve_loops=True)
    try:
        if len(shadow.data.vertices)!=len(stored['owners']):raise ValueError('Actual indexed protected LOD owner count changed')
        rigid._clod_contact_set_owners(shadow.data,stored['owners'])
        attribute=shadow.data.attributes.new(rigid._clod_COMPONENT_ATTRIBUTE,'INT','POINT');attribute.data.foreach_set('value',stored['components'])
        rigid._clod_verify_lineage(shadow,[cert['componentId']for cert in stored['certificates']])
        checks=[rigid._clod_contact_verify(shadow.data,cert,decoded_file_uv=True)for cert in stored['certificates']]
        return {'method':'protected-contact-rings-v1','actualFileCornerBijection':True,'originalOwnerIdsFromHashBoundSidecarNotRenderIndices':True,
            'workingProtectedUVExact':True,'sourceAndActualFrameChecks':frame_check,'protectedLow0AndLodStoredFileUvExact':True,'actualDecodedLow0AndLodUvExact':True,
            'rawPreEqualsRawNativeUvClaimed':False,'negativeBoundariesRetainedExactly':sum(c['negative']for c in stored['certificates']),
            'protectedComponentChecks':checks,'physicalPropertiesReusedFromExactChosenTriangleGeometryAndBoundActualFileGraph':True,
            'crossBoundaryClearanceClaimed':False,'privateProofSha256':stored['sha256']}
    finally:_dispose(shadow,shadow.data)
