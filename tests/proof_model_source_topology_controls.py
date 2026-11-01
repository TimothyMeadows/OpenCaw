"""Real Blender fixture helpers for reviewed source-corner topology.

No autorun or process launch. Root registers run_regressions(topology, rigid,
api, work) in the bounded native suite. Geometry/rights/reviews are SIMULATED;
export, import, source guards, graph reconstruction and rejection are native.
"""
from pathlib import Path
import copy
import hashlib
import json
import struct


def _save(path, value):
    path.write_text(json.dumps(value, separators=(',', ':'), allow_nan=False) + '\n', encoding='utf-8')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _rewrite_document(path, change):
    raw = path.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + size])
    change(document)
    payload = json.dumps(document, separators=(',', ':')).encode('utf-8')
    payload += b' ' * (-len(payload) % 4)
    tail = raw[20 + size:]
    path.write_bytes(b'glTF' + struct.pack('<II', 2, 20 + len(payload) + len(tail)) +
                     struct.pack('<II', len(payload), 0x4E4F534A) + payload + tail)


def _alias_identical_fixture_indices(path, rigid, name):
    """Construct a real interop fixture without changing any corner attribute.

    Blender's exporter keys vertices by original vertex_index, so its normal
    export cannot itself prove support for render-index merging across owners.
    Only indices with byte-identical POSITION/NORMAL/UV rows are aliased here.
    The authoring capture still binds the resulting actual file through the
    existing mapper; no test/runtime ownership attribute is introduced.
    """
    reader = rigid._snv_Glb(path, 16777216)
    node = reader.document['nodes'][rigid._nfb_node_index(reader, name)]
    primitives = reader.document['meshes'][node['mesh']]['primitives']
    raw = bytearray(path.read_bytes())
    binary_start = 28 + struct.unpack_from('<I', raw, 12)[0]
    changed, bounds = 0, {}
    for primitive in primitives:
        attributes = {key: reader.accessor(index, 'float', 2 if key.startswith('TEXCOORD_') else 3)
                      for key, index in primitive['attributes'].items()}
        representative, aliases = {}, {}
        for index in range(len(attributes['POSITION'])):
            key = tuple((name, values[index].tobytes()) for name, values in sorted(attributes.items()))
            aliases[index] = representative.setdefault(key, index)
        accessor_index = primitive['indices']
        accessor = reader.document['accessors'][accessor_index]
        view = reader.document['bufferViews'][accessor['bufferView']]
        code = {5121: 'B', 5123: 'H', 5125: 'I'}[accessor['componentType']]
        width = struct.calcsize(code)
        indices = reader.accessor(accessor_index, 'index', 1).reshape(-1)
        mapped = [aliases[int(index)] for index in indices]
        for ordinal, (old, new) in enumerate(zip(indices, mapped)):
            if int(old) != new:
                changed += 1
                offset = binary_start + view.get('byteOffset', 0) + accessor.get('byteOffset', 0) + ordinal * width
                struct.pack_into('<' + code, raw, offset, new)
        bounds[accessor_index] = (min(mapped), max(mapped))
    path.write_bytes(raw)
    def update(document):
        for index, (minimum, maximum) in bounds.items():
            accessor = document['accessors'][index]
            if 'min' in accessor:
                accessor['min'] = [minimum]
            if 'max' in accessor:
                accessor['max'] = [maximum]
    _rewrite_document(path, update)
    return changed


def run_regressions(topology, rigid, api, work):
    import bpy
    import numpy as np
    from types import SimpleNamespace
    from mathutils import Matrix

    work = Path(work)
    work.mkdir(parents=True, exist_ok=True)
    # A private fixture project satisfies the same confined task-path rule.
    task = work / '.hephaera/.cache/tasks/source-topology-controls'
    task.mkdir(parents=True, exist_ok=False)
    prepared = work / 'source-topology.glb'
    receipt_path = task / 'source-topology.json'
    initial_objects = {obj.as_pointer() for obj in bpy.data.objects}
    initial_meshes = {mesh.as_pointer() for mesh in bpy.data.meshes}
    initial_materials = {mat.as_pointer() for mat in bpy.data.materials}
    ui = {'selected': [obj for obj in bpy.context.selected_objects],
          'active': bpy.context.view_layer.objects.active}
    rows = []

    def record(name, **data):
        rows.append({'case': name, 'pass': True, **data})

    def dispose(obj):
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    def inventory():
        return ({o.as_pointer() for o in bpy.data.objects}, {m.as_pointer() for m in bpy.data.meshes})

    def rejected(name, action):
        before = inventory()
        try:
            action()
        except (ValueError, RuntimeError, TypeError):
            assert inventory() == before, name + ': rejected operation leaked native data'
            record(name)
        else:
            raise AssertionError(name + ': malformed selected evidence accepted')

    def state(obj):
        return (rigid._normal_raw_mesh_state(obj.data), rigid._normal_node_state(obj))

    def changed_fields(before, after, prefix=''):
        """Compact exact field deltas; source states contain hashes, not geometry."""
        if type(before) is dict and type(after) is dict:
            result = []
            for key in sorted(set(before) | set(after)):
                path = prefix + '.' + key if prefix else key
                if key not in before or key not in after:
                    result.append({'path': path, 'before': before.get(key, '<MISSING>'),
                                   'after': after.get(key, '<MISSING>')})
                else:
                    result.extend(changed_fields(before[key], after[key], path))
            return result
        if type(before) in (list, tuple) and type(after) in (list, tuple) and len(before) == len(after):
            return [row for index, (a, b) in enumerate(zip(before, after))
                    for row in changed_fields(a, b, prefix + '[' + str(index) + ']')]
        return [] if before == after else [{'path': prefix, 'before': before, 'after': after}]

    tetra = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)]
    faces = [(0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3)]
    def pair(second, reverse=False):
        other = [tuple(reversed(f)) if reverse else f for f in faces]
        return tetra + second, faces + [tuple(i + 4 for i in f) for f in other]

    fixtures = {
        'LOW.seams': (tetra, faces),
        'LOW.point': pair([tuple(-v for v in p) for p in tetra], True),
        'LOW.edge': pair([(x, -y, -z) for x, y, z in tetra]),
        'LOW.cavity': pair([tuple(.125 + .125 * v for v in p) for p in tetra], True),
        # Same normal/UV at duplicate origin allows a real render index to serve
        # distinct authored owners; this intentionally open fixture is NOT usable.
        'LOW.merged': ([(0, 0, 0), (1, 0, 0), (0, 1, 0),
                        (0, 0, 0), (-1, 0, 0), (0, -1, 0)], [(0, 1, 2), (3, 4, 5)]),
    }
    objects = []
    try:
        mats = [bpy.data.materials.new('SourceTopology.Material.' + str(i)) for i in range(2)]
        for name, (points, triangles) in fixtures.items():
            mesh = bpy.data.meshes.new(name + '.mesh')
            mesh.from_pydata(points, [], triangles)
            for mat in mats:
                mesh.materials.append(mat)
            uv = mesh.uv_layers.new(name='UVMap')
            for pi, polygon in enumerate(mesh.polygons):
                polygon.material_index = pi % 2 if name != 'LOW.merged' else 0
                polygon.use_smooth = False
                for ci, li in enumerate(polygon.loop_indices):
                    uv.data[li].uv = [(0, 0), (.75, 0), (0, .75)][ci]
            obj = bpy.data.objects.new(name, mesh)
            bpy.context.collection.objects.link(obj)
            obj.matrix_world = Matrix.Translation((2, -3, 4)) @ Matrix.Rotation(.25, 4, 'Z') @ Matrix.Diagonal((1.25, .75, 1.5, 1))
            objects.append(obj)
        for obj in bpy.context.selected_objects:
            obj.select_set(False)
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        configured = {obj.name: state(obj) for obj in objects}
        # Complete the owned fixture's authored data/depsgraph before its
        # preservation baseline. Persist this transition so a prior lazy-state
        # hypothesis can be verified rather than silently assumed.
        for obj in objects:
            obj.data.update()
        bpy.context.view_layer.update()
        before = {obj.name: state(obj) for obj in objects}
        result = bpy.ops.export_scene.gltf(filepath=str(prepared), export_format='GLB',
                    use_selection=True, export_yup=True, export_extras=False)
        assert result == {'FINISHED'} and prepared.is_file()
        after_export = {obj.name: state(obj) for obj in objects}
        # Reorder actual exported primitives while keeping their accessor bytes;
        # native-loop/source-file order must be reconciled by the sole mapper.
        _rewrite_document(prepared, lambda doc: [mesh['primitives'].reverse() for mesh in doc['meshes']])
        aliased = _alias_identical_fixture_indices(prepared, rigid, 'LOW.merged')
        capture_error = None
        try:
            receipt = topology.capture(prepared, objects, rigid, max_file_bytes=16777216)
        except BaseException as error:
            capture_error = type(error).__name__ + ': ' + str(error)[:1024]
            raise
        finally:
            after_capture = {obj.name: state(obj) for obj in objects}
            source_guard_evidence = {
                'configuredBeforeFinalization': configured,
                'beforeExportAfterExplicitFinalization': before,
                'afterExport': after_export, 'afterCapture': after_capture,
                'configuredToFinalizedChangedFields': changed_fields(configured, before),
                'exportChangedFields': changed_fields(before, after_export),
                'captureChangedFields': changed_fields(after_export, after_capture),
                'allBeforeExportAfterExportAfterCaptureExact': before == after_export == after_capture,
                'captureException': capture_error,
                'finalizationIsFixtureSetupNotSourcePreservationWaiver': True,
            }
            with (work / 'source-topology-source-guards.json').open('x', encoding='utf-8') as stream:
                json.dump(source_guard_evidence, stream, indent=2, allow_nan=False)
                stream.write('\n')
        assert before == after_export, 'Export changed finalized fixture source fields: ' + json.dumps(source_guard_evidence['exportChangedFields'])
        assert after_export == after_capture, 'Capture changed fixture source fields: ' + json.dumps(source_guard_evidence['captureChangedFields'])
        assert {row['node'] for row in receipt['meshes']} == set(fixtures)
        record('authored-source-capture-preserved', meshes=len(objects), actualReorderedPrimitives=True,
               interopFixtureIdenticalAttributeIndexAliases=aliased)
        receipt_sha = _save(receipt_path, receipt)
        handoff = {'preparedGlbSha256': receipt['preparedGlbSha256'],
                   'parts': [{'lowObject': name} for name in fixtures]}
        for obj in objects:
            dispose(obj)
        objects = []
        for mat in mats:
            if mat.users == 0:
                bpy.data.materials.remove(mat)
        before_import = {obj.as_pointer() for obj in bpy.data.objects}
        assert bpy.ops.import_scene.gltf(filepath=str(prepared)) == {'FINISHED'}
        imported = {obj.name: obj for obj in bpy.data.objects if obj.as_pointer() not in before_import and obj.type == 'MESH'}
        assert set(imported) == set(fixtures)
        bindings = topology.load(receipt_path, prepared, handoff, rigid,
                         expected_receipt_sha256=receipt_sha, max_file_bytes=16777216)
        for name, obj in imported.items():
            before = state(obj)
            shadow = bindings[name].inspection_copy(obj, rigid)
            try:
                assert len(shadow.data.vertices) == len(fixtures[name][0])
                assert len(shadow.data.polygons) == len(fixtures[name][1])
                assert np.array_equal(np.asarray(shadow.matrix_world), np.asarray(obj.matrix_world))
                if name == 'LOW.merged':
                    try:
                        api.require_usable(shadow, name)
                    except ValueError:
                        pass
                    else:
                        raise AssertionError('Open fixture incorrectly usable')
                else:
                    api.require_usable(shadow, name)
                assert not bindings[name].native_loop_owners.flags.writeable
            finally:
                dispose(shadow)
            rich = bindings[name].reindex_copy(obj, rigid)
            try:
                assert [p.material_index for p in rich.data.polygons] == [p.material_index for p in obj.data.polygons]
                assert [p.use_smooth for p in rich.data.polygons] == [p.use_smooth for p in obj.data.polygons]
                assert [m.as_pointer() for m in rich.data.materials] == [m.as_pointer() for m in obj.data.materials]
                for a, b in zip(rich.data.uv_layers, obj.data.uv_layers):
                    assert rigid._nfa_field(a.data, 'uv', np.float32, 2).tobytes() == rigid._nfa_field(b.data, 'uv', np.float32, 2).tobytes()
                assert rich.data.attributes.get('custom_normal') is None
                normal_report = rigid._clod_author_normals(rich)
                assert normal_report['sourceNormalRestorationClaimed'] is False
            finally:
                dispose(rich)
            assert state(obj) == before
            record('native-copy-' + name, owners=len(fixtures[name][0]), sourceExact=True)
        # Real actual-index -> multi-owner support is measured on the actual
        # identical-attribute alias fixture, not inferred from seam splitting.
        merged = imported['LOW.merged']
        loop_vertices = rigid._nfa_field(merged.data.loops, 'vertex_index', np.int32, 1).reshape(-1)
        owner_map = {}
        for vi, owner in zip(loop_vertices, bindings[merged.name].native_loop_owners):
            owner_map.setdefault(int(vi), set()).add(int(owner))
        assert any(len(values) > 1 for values in owner_map.values()), 'Fixture did not produce an actual merged render index'
        record('actual-render-index-multiple-source-owners', renderVertices=len(merged.data.vertices), sourceOwners=6)
        for name in ('LOW.point', 'LOW.edge'):
            obj = imported[name]
            old = rigid._clod_copy(obj, 'Topology.LegacyNegative')
            try:
                rigid._clod_exact_weld(old)
                try:
                    api.require_usable(old, name)
                except ValueError:
                    pass
                else:
                    raise AssertionError('Coordinate contact weld unexpectedly passed: ' + name)
            finally:
                dispose(old)
            record('legacy-contact-weld-negative-' + name)
        # Bound provenance can survive internal UV authoring and a consistent
        # rebase, but cannot silently reuse a changed loop/edge graph.
        obj = imported['LOW.seams']
        original_co = rigid._nfa_field(obj.data.vertices, 'co', np.float32, 3)
        original_world = obj.matrix_world.copy()
        original_uv = rigid._nfa_field(obj.data.uv_layers[0].data, 'uv', np.float32, 2)
        shift = np.array((.5, .25, -.5), np.float32)
        obj.data.vertices.foreach_set('co', (original_co + shift).reshape(-1))
        obj.data.uv_layers[0].data.foreach_set('uv', (original_uv * np.float32(.5)).reshape(-1))
        obj.matrix_world = original_world @ Matrix.Translation(tuple(-shift))
        obj.data.update()
        bpy.context.view_layer.update()
        rebased = bindings[obj.name].reindex_copy(obj, rigid)
        dispose(rebased)
        obj.data.vertices.foreach_set('co', original_co.reshape(-1))
        obj.data.uv_layers[0].data.foreach_set('uv', original_uv.reshape(-1))
        obj.matrix_world = original_world
        obj.data.update()
        bpy.context.view_layer.update()
        record('private-graph-guard-allows-explicit-internal-uv-rebase')
        old_mesh = obj.data
        replacement = bpy.data.meshes.new('Topology.BadGraph')
        replacement.from_pydata(original_co.tolist(), [], [tuple(reversed(p.vertices)) for p in old_mesh.polygons])
        obj.data = replacement
        try:
            rejected('changed-loop-edge-graph', lambda: bindings[obj.name].inspection_copy(obj, rigid))
        finally:
            obj.data = old_mesh
            bpy.data.meshes.remove(replacement)

        def bad_case(name, mutate):
            bad = copy.deepcopy(receipt)
            mutate(bad)
            path = task / (name + '.json')
            digest = _save(path, bad)
            rejected(name, lambda: topology.load(path, prepared, handoff, rigid,
                           expected_receipt_sha256=digest, max_file_bytes=16777216))
        bad_case('unknown-root-field', lambda d: d.update(extra=True))
        bad_case('unknown-mesh-field', lambda d: d['meshes'][0].update(extra=True))
        bad_case('fractional-integer-token', lambda d: d.update(schemaVersion=1.0))
        bad_case('boolean-integer-token', lambda d: d['meshes'][0].update(fileNodeIndex=True))
        bad_case('duplicate-node', lambda d: d['meshes'].append(copy.deepcopy(d['meshes'][0])))
        bad_case('missing-mesh-list', lambda d: d.update(meshes=[]))
        bad_case('wrong-glb-hash', lambda d: d.update(preparedGlbSha256='0' * 64))
        bad_case('wrong-file-node', lambda d: d['meshes'][0].update(fileNodeIndex=1000000))
        bad_case('unknown-node', lambda d: d['meshes'][0].update(node='LOW.absent'))
        bad_case('wrong-owner-hash', lambda d: d['meshes'][0].update(ownersSha256='0' * 64))
        bad_case('invalid-owner-hex', lambda d: d['meshes'][0].update(ownersI32LEHex='G' * len(d['meshes'][0]['ownersI32LEHex'])))
        bad_case('omitted-owner-corner', lambda d: d['meshes'][0].update(ownersI32LEHex=d['meshes'][0]['ownersI32LEHex'][:-8]))
        bad_case('uncovered-owner', lambda d: d['meshes'][0].update(sourceVertexCount=d['meshes'][0]['sourceVertexCount'] + 1))
        duplicate = task / 'duplicate-fields.json'
        duplicate.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding='utf-8')
        rejected('duplicate-json-fields', lambda: topology.load(duplicate, prepared, handoff, rigid,
                 expected_receipt_sha256=hashlib.sha256(duplicate.read_bytes()).hexdigest(), max_file_bytes=16777216))
        deep = task / 'excess-depth.json'
        deep.write_text('[' * 13 + '0' + ']' * 13, encoding='utf-8')
        rejected('excess-json-depth', lambda: topology.load(deep, prepared, handoff, rigid,
                 expected_receipt_sha256=hashlib.sha256(deep.read_bytes()).hexdigest(), max_file_bytes=16777216))
        rejected('stale-receipt-sha', lambda: topology.load(receipt_path, prepared, handoff, rigid,
                 expected_receipt_sha256='0' * 64, max_file_bytes=16777216))
        outside = work / 'outside-task.json'
        outside.write_bytes(receipt_path.read_bytes())
        rejected('receipt-outside-task', lambda: topology.load(outside, prepared, handoff, rigid,
                 expected_receipt_sha256=receipt_sha, max_file_bytes=16777216))
        rejected('receipt-path-parent-traversal', lambda: topology.load(task / 'x/../source-topology.json', prepared, handoff, rigid,
                 expected_receipt_sha256=receipt_sha, max_file_bytes=16777216))
        # A valid file/count envelope cannot make inconsistent owner positions
        # or missing/ambiguous native corners trustworthy.
        bad_owners = copy.deepcopy(receipt)
        row = next(row for row in bad_owners['meshes'] if row['node'] == 'LOW.seams')
        owners = np.frombuffer(bytes.fromhex(row['ownersI32LEHex']), '<i4').copy()
        owners[0] = (int(owners[0]) + 1) % row['sourceVertexCount']
        row['ownersI32LEHex'] = owners.astype('<i4').tobytes().hex()
        row['ownersSha256'] = hashlib.sha256(owners.astype('<i4').tobytes()).hexdigest()
        path = task / 'inconsistent-owner-positions.json'
        digest = _save(path, bad_owners)
        bad_bindings = topology.load(path, prepared, handoff, rigid,
                            expected_receipt_sha256=digest, max_file_bytes=16777216)
        rejected('inconsistent-owner-position-corners', lambda: bad_bindings['LOW.seams'].inspection_copy(imported['LOW.seams'], rigid))
        selected = topology.load(receipt_path, prepared, handoff, rigid,
                     expected_receipt_sha256=receipt_sha, max_file_bytes=16777216)
        obj = imported['LOW.merged']
        before_co = rigid._nfa_field(obj.data.vertices, 'co', np.float32, 3)
        changed = before_co.copy()
        first, second = [tuple(p.vertices) for p in obj.data.polygons]
        for a, b in zip(first, second):
            changed[b] = before_co[a]
        obj.data.vertices.foreach_set('co', changed.reshape(-1))
        obj.data.update()
        try:
            rejected('ambiguous-native-oriented-corners', lambda: selected[obj.name].inspection_copy(obj, rigid))
        finally:
            obj.data.vertices.foreach_set('co', before_co.reshape(-1))
            obj.data.update()
        selected = topology.load(receipt_path, prepared, handoff, rigid,
                     expected_receipt_sha256=receipt_sha, max_file_bytes=16777216)
        obj = imported['LOW.seams']
        original_world = obj.matrix_world.copy()
        obj.matrix_world.translation.x += .125
        bpy.context.view_layer.update()
        try:
            rejected('initial-native-frame-mismatch', lambda: selected[obj.name].inspection_copy(obj, rigid))
        finally:
            obj.matrix_world = original_world
            bpy.context.view_layer.update()
        # These are explicitly injected synchronous failures in real native
        # allocation/cleanup paths, not evidence of host process cancellation.
        proxy = SimpleNamespace(**vars(rigid))
        readbacks = [0]
        def fail_new_loop_readback(data, prop, dtype, width):
            if prop == 'vertex_index':
                readbacks[0] += 1
                if readbacks[0] == 2:
                    raise ValueError('Injected owned-mesh readback failure')
            return rigid._nfa_field(data, prop, dtype, width)
        proxy._nfa_field = fail_new_loop_readback
        rejected('injected-after-owned-mesh-allocation-cleanup', lambda: bindings[obj.name].inspection_copy(obj, proxy))
        assert readbacks[0] == 2
        proxy = SimpleNamespace(**vars(rigid))
        guards = [0]
        def interrupt_postguard(value):
            guards[0] += 1
            if guards[0] == 2:
                raise KeyboardInterrupt('Injected post-copy cancellation')
            return rigid._normal_node_state(value)
        proxy._normal_node_state = interrupt_postguard
        inventory_before, source_before = inventory(), state(obj)
        try:
            bindings[obj.name].inspection_copy(obj, proxy)
        except KeyboardInterrupt:
            pass
        else:
            raise AssertionError('Injected synchronous interruption was swallowed')
        assert guards[0] == 2 and inventory() == inventory_before and state(obj) == source_before
        record('injected-post-copy-interruption-cleanup', hostProcessCancellationClaimed=False)
        # Native geometry classification treats opposite zero signs as the same
        # position, without changing any raw source/corner/boundary evidence.
        point_source = imported['LOW.point']
        point_before = state(point_source)
        zero_graph = bindings[point_source.name].reindex_copy(point_source, rigid)
        try:
            points = rigid._nfa_field(zero_graph.data.vertices, 'co', np.float32, 3)
            origins = np.flatnonzero(np.all(points == 0, axis=1))
            assert len(origins) >= 2
            points[origins[0], 0] = np.float32(0.0)
            points[origins[1], 0] = np.float32(-0.0)
            zero_graph.data.vertices.foreach_set('co', points.reshape(-1))
            zero_graph.data.update()
            bpy.context.view_layer.update()
            actual = rigid._nfa_field(zero_graph.data.vertices, 'co', np.float32, 3)
            bits = actual.view(np.uint32)
            assert bits[origins[0], 0] == 0 and bits[origins[1], 0] == 0x80000000
            zero_before = state(zero_graph)
            assert rigid._clod_has_coincident_owners(zero_graph.data) is True
            assert state(zero_graph) == zero_before
        finally:
            dispose(zero_graph)
        assert state(point_source) == point_before
        record('native-coincident-owner-signed-zero-classification-preserves-raw-bits')
        # Actual final-output path: LOW0 render vertices are not authored owners.
        # Keep its loaded graph through internal UV/rebase/name changes, export
        # the real current bytes, and capture via that proven private binding.
        point = imported['LOW.point']
        point_binding = bindings[point.name]
        point.name = 'LOW.runtime-point'
        coordinates = rigid._nfa_field(point.data.vertices, 'co', np.float32, 3)
        shift = np.array((.25, -.5, .125), np.float32)
        point.data.vertices.foreach_set('co', (coordinates + shift).reshape(-1))
        point.matrix_world = point.matrix_world @ Matrix.Translation(tuple(-shift))
        for layer in point.data.uv_layers:
            values = rigid._nfa_field(layer.data, 'uv', np.float32, 2)
            layer.data.foreach_set('uv', (values * np.float32(.5) + np.float32(.125)).reshape(-1))
        point.data.update()
        for value in bpy.context.selected_objects:
            value.select_set(False)
        point.select_set(True)
        bpy.context.view_layer.objects.active = point
        runtime = work / 'source-topology-runtime.glb'
        assert bpy.ops.export_scene.gltf(filepath=str(runtime), export_format='GLB', use_selection=True,
                                         export_yup=True, export_extras=False) == {'FINISHED'}
        before_capture = state(point)
        runtime_receipt = topology.capture(runtime, [point], rigid, max_file_bytes=16777216,
                                          bindings={point.name: point_binding})
        assert state(point) == before_capture
        assert runtime_receipt['meshes'][0]['sourceVertexCount'] == 8
        rejected('raw-owner-array-capture-override-forbidden', lambda: topology.capture(runtime, [point], rigid,
                 max_file_bytes=16777216, bindings={point.name: point_binding.native_loop_owners}))
        runtime_path = task / 'runtime-source-topology.json'
        runtime_sha = _save(runtime_path, runtime_receipt)
        for value in list(imported.values()):
            dispose(value)
        imported.clear()
        for material in list(bpy.data.materials):
            if material.as_pointer() not in initial_materials and material.users == 0:
                bpy.data.materials.remove(material)
        before_import = {value.as_pointer() for value in bpy.data.objects}
        assert bpy.ops.import_scene.gltf(filepath=str(runtime)) == {'FINISHED'}
        runtime_objects = [value for value in bpy.data.objects if value.as_pointer() not in before_import and value.type == 'MESH']
        assert len(runtime_objects) == 1 and runtime_objects[0].name == 'LOW.runtime-point'
        runtime_handoff = {'preparedGlbSha256': runtime_receipt['preparedGlbSha256'],
                           'parts': [{'lowObject': 'LOW.runtime-point'}]}
        runtime_bindings = topology.load(runtime_path, runtime, runtime_handoff, rigid,
                      expected_receipt_sha256=runtime_sha, max_file_bytes=16777216)
        shadow = runtime_bindings['LOW.runtime-point'].inspection_copy(runtime_objects[0], rigid)
        try:
            api.require_usable(shadow, 'Runtime source-owned point contact')
            assert len(shadow.data.vertices) == 8 and len(shadow.data.polygons) == 8
        finally:
            dispose(shadow)
        record('actual-runtime-roundtrip-renamed-uv-rebased-bound-low0', sourceOwners=8,
               receiptSha256=runtime_sha, preparedGlbSha256=runtime_receipt['preparedGlbSha256'])
        record('actual-native-export-import-complete', receiptSha256=receipt_sha,
               preparedGlbSha256=receipt['preparedGlbSha256'], nativeCases=len(rows),
               noDummyUvOrRuntimeOwnershipAttribute=True,
               physicalIntersectionAndNormalQualityClaimed=False)
    finally:
        for obj in list(bpy.data.objects):
            if obj.as_pointer() not in initial_objects:
                bpy.data.objects.remove(obj, do_unlink=True)
        for mesh in list(bpy.data.meshes):
            if mesh.as_pointer() not in initial_meshes and mesh.users == 0:
                bpy.data.meshes.remove(mesh)
        for material in list(bpy.data.materials):
            if material.as_pointer() not in initial_materials and material.users == 0:
                bpy.data.materials.remove(material)
        for obj in bpy.context.selected_objects:
            obj.select_set(False)
        for obj in ui['selected']:
            if obj.as_pointer() in initial_objects:
                obj.select_set(True)
        bpy.context.view_layer.objects.active = ui['active']
        assert {obj.as_pointer() for obj in bpy.data.objects} == initial_objects
        assert {mesh.as_pointer() for mesh in bpy.data.meshes} == initial_meshes
        assert {mat.as_pointer() for mat in bpy.data.materials} == initial_materials
    return {'status': 'NATIVE_SOURCE_TOPOLOGY_CONTROLS_PASS', 'cases': rows,
            'simulatedArtAndAdmission': True, 'nativeExportImport': True,
            'sourceAndInventoryGuardsExact': True, 'productionOrPhysicalQualityAdmission': False}
