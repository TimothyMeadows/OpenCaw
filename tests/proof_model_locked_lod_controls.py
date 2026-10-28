"""Independent primitive controls for proven-impossible constrained LOD trials.

Fixture geometry, rights and admission are SIMULATED. Blender operations are real.
This test helper is not a production runtime companion.
"""


def legacy_function_ast(source):
    """Bypass three exact optimization statements only for the default policy."""
    import ast
    import copy
    import hashlib
    import textwrap

    tree = ast.parse(textwrap.dedent(source))
    assert len(tree.body) == 1 and isinstance(tree.body[0], ast.FunctionDef)
    function = tree.body[0]
    assert function.name == '_clod_build_constrained_lods'
    fragments = (
        "protected_bound = None",
        """if boundary is not None:
    protected_positions = len(set(boundary['positions']))
    protected_bound = max(protected_bound or 0, 4, 2 * protected_positions - 4)
    component_report['protectedPositionReductionBound'] = {
        'method': 'closed-orientable-triangle-Euler-v1',
        'distinctProtectedPositions': protected_positions,
        'minimumTriangles': protected_bound,
        'originalTriangles': original['sourceTriangles'],
        'originalClosedPositiveReferenceValidated': original['topology']['worldSignedOrientation'] > 0,
        'originalClosedConsistentlyOrientedReferenceValidated': True,
    }""",
        """if ratio < 1.0 and protected_bound is not None and protected_bound >= original['sourceTriangles']:
    trial['noReductionCertificate'] = dict(
        (component_report['protectedOwnerReductionBound'] if contact_policy else component_report['protectedPositionReductionBound']),
        nativeInvoked=False,
        candidateCopyInvoked=False,
    )
    raise _clod_Rejected('Exact protected-position Euler bound prevents reduction; defer to explicit original terminal retention')""",
    )
    dump = lambda node: ast.dump(node, include_attributes=False)
    expected = [dump(ast.parse(fragment).body[0]) for fragment in fragments]
    matches = [[node for node in ast.walk(function) if dump(node) == target] for target in expected]
    assert all(len(nodes) == 1 for nodes in matches), 'Expected exactly one of each reviewed optimization statement'
    removed = {id(nodes[0]) for nodes in matches}
    contact_setup = ast.parse("""if contact_policy:
    held_ids = set(int(x) for x in certificate['ownerIds'])
    if boundary is not None:
        held_ids.update(boundary['ownerPositions'])
    protected_bound = max(4, 2 * len(held_ids) - 4)
    component_report['protectedOwnerReductionBound'] = {
        'distinctOriginalOwnerIds': len(held_ids),
        'minimumTriangles': protected_bound,
        'coordinateAliasesRemainDistinct': True,
    }""").body[0]
    contact_matches = [node for node in ast.walk(function) if dump(node) == dump(contact_setup)]
    assert len(contact_matches) == 1, 'Expected the unchanged reviewed contact-policy bound setup'
    # Require the setup immediately before the ratio grid, and the early
    # rejection immediately after the unchanged four-triangle rejection.
    lists = [value for node in ast.walk(function) for value in vars(node).values()
             if isinstance(value, list) and value and all(isinstance(item, ast.stmt) for item in value)]
    setup = next(items for items in lists if matches[0][0] in items)
    index = setup.index(matches[0][0])
    assert setup[index + 1] is contact_matches[0] and setup[index + 2] is matches[1][0]
    grid = setup[index + 3]
    assert isinstance(grid, ast.Assign) and isinstance(grid.value, ast.Call)
    assert isinstance(grid.value.func, ast.Name) and grid.value.func.id == '_clod_ratio_grid'
    trials = next(items for items in lists if matches[2][0] in items)
    index = trials.index(matches[2][0])
    preceding, following = trials[index - 1], trials[index + 1]
    assert isinstance(preceding, ast.If) and isinstance(following, ast.Assign)
    assert ast.unparse(preceding.test) == "ratio < 1.0 and trial['effectiveNativeRatio'] >= 1.0"
    assert any(isinstance(node, ast.Constant) and node.value ==
               'Four-triangle component floor prevents reduction; defer to explicit terminal retention'
               for node in ast.walk(preceding))
    assert ast.unparse(following) == "candidate = _clod_copy(reference, 'Constrained.Trial')"

    class BypassDefaultOptimization(ast.NodeTransformer):
        def visit(self, node):
            if id(node) in removed:
                return ast.copy_location(ast.If(test=ast.Name(id='contact_policy', ctx=ast.Load()),
                                                body=[node], orelse=[]), node)
            return super().visit(node)

    # Keep every original body and all contact machinery. Only default execution
    # skips these three statements; the selected contact path is unchanged.
    original = copy.deepcopy(function)
    expected_legacy = copy.deepcopy(function)
    for node in list(ast.walk(expected_legacy)):
        for field, value in vars(node).items():
            if isinstance(value, list):
                setattr(node, field, [ast.copy_location(ast.If(
                    test=ast.Name(id='contact_policy', ctx=ast.Load()), body=[item], orelse=[]), item)
                    if isinstance(item, ast.stmt) and dump(item) in expected else item for item in value])
    legacy = BypassDefaultOptimization().visit(function)
    assert dump(legacy) == dump(expected_legacy), 'Unexpected legacy-control AST change'
    wrappers = [node for node in ast.walk(legacy) if isinstance(node, ast.If)
                and isinstance(node.test, ast.Name) and node.test.id == 'contact_policy'
                and not node.orelse and len(node.body) == 1 and dump(node.body[0]) in expected]
    assert len(wrappers) == 3, 'Expected exactly three default-only optimization bypasses'
    permitted = {id(node) for root in [contact_matches[0], *[nodes[0] for nodes in matches]]
                 for node in ast.walk(root)}
    assert all(id(node) in permitted for node in ast.walk(legacy)
               if isinstance(node, ast.Name) and node.id in ('protected_bound', 'protected_positions')
               or isinstance(node, ast.Constant) and node.value in
               ('protectedPositionReductionBound', 'protectedOwnerReductionBound', 'noReductionCertificate')), 'Unrecognized optimization reference remains'
    normalized = lambda node: hashlib.sha256(dump(node).encode('utf-8')).hexdigest()
    return ast.fix_missing_locations(legacy), {
        'removedExactStatements': 3,
        'removalScope': 'default/no-contact execution only; exact original bodies retained under contact_policy guards',
        'physicalStatementBodiesDeleted': 0,
        'contactPolicyStatementBodiesUnchanged': True,
        'allOtherFunctionNodesUnchanged': True,
        'currentFunctionAstSha256': normalized(original),
        'legacyFunctionAstSha256': normalized(legacy),
        'legacySource': 'current selected module; exact reviewed default-only optimizer bypass',
    }


def derive_legacy_control(fast):
    import ast
    import inspect
    import types

    function, receipt = legacy_function_ast(inspect.getsource(fast._clod_build_constrained_lods))
    legacy = types.ModuleType('proof_model_locked_lod_legacy_control')
    legacy.__dict__.update(fast.__dict__)
    # Bind reused module-function code to the private control namespace so
    # actual nested helper calls are counted without patching the fast module.
    for name, value in fast.__dict__.items():
        if isinstance(value, types.FunctionType) and value.__globals__ is fast.__dict__:
            cloned = types.FunctionType(value.__code__, legacy.__dict__, value.__name__, value.__defaults__, value.__closure__)
            cloned.__kwdefaults__ = value.__kwdefaults__
            cloned.__annotations__ = dict(value.__annotations__)
            cloned.__dict__.update(value.__dict__)
            legacy.__dict__[name] = cloned
    exec(compile(ast.Module(body=[function], type_ignores=[]), '<exact-reviewed-legacy-control>', 'exec'), legacy.__dict__)
    return legacy, receipt


def run_selected_regressions(fast, api, work):
    legacy, receipt = derive_legacy_control(fast)
    result = run_regressions(legacy, fast, api, work)
    result['legacyControlDerivation'] = receipt
    return result


def run_regressions(legacy, fast, api, work):
    import bpy,bmesh,hashlib,numpy as np,time
    from mathutils import Matrix,Euler
    from pathlib import Path
    settings={'schemaVersion':1,'method':'original-component-finite-collapse-v1',
      'levels':[{'level':1,'requestedRatio':.5,'maxVertexSurfaceErrorMetres':.003},{'level':2,'requestedRatio':.2,'maxVertexSurfaceErrorMetres':.01}],
      'search':{'method':'linear-requested-to-original','intervals':8,'includePreviousSelectedRatio':True,'terminalRetention':'explicit-original-component'},
      'uvPolicy':{'method':'supported-material-aware-v1','uvIndependent':'deterministic-unit-grid-triangles','uvDependent':'hard-zero-boundary-both-sides','unsupported':'reject'},
      'normalPolicy':'authored-derivative-native-geometric-nonzero','componentPolicy':'retain-every-original-closed-positive-component-min4',
      'budgets':{'maxLod0Triangles':2000,'maxPackageTriangles':5000}}
    # Independently authored two-by-two PNG: no private fixture or art input.
    import struct,zlib
    work=Path(work);work.mkdir(parents=True,exist_ok=True)
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    pixels=(b'\x00'+bytes((128,128,128,255))*2)*2
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,2,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')
    image_path=work/'simulated.png';image_path.write_bytes(png)
    image=bpy.data.images.load(str(image_path),check_existing=False);image.pack()
    material=bpy.data.materials.new('SIMULATED independent static packed UV material');material.use_nodes=True
    shader=material.node_tree.nodes.get('Principled BSDF');texture=material.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image
    texture.projection='FLAT';texture.extension='EXTEND';texture.interpolation='Closest'
    uvnode=material.node_tree.nodes.new('ShaderNodeUVMap');uvnode.uv_map='UVMap'
    material.node_tree.links.new(uvnode.outputs['UV'],texture.inputs['Vector']);material.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
    def field(data,prop,width,dtype):
        values=np.empty(len(data)*width,dtype);data.foreach_get(prop,values);return values
    def digest(value):return hashlib.sha256(value).hexdigest()
    def snapshot(obj):
        m=obj.data
        return {'coordinates':digest(field(m.vertices,'co',3,np.float32).tobytes()),'loops':digest(field(m.loops,'vertex_index',1,np.int32).tobytes()),
          'starts':digest(field(m.polygons,'loop_start',1,np.int32).tobytes()),'sizes':digest(field(m.polygons,'loop_total',1,np.int32).tobytes()),
          'materials':digest(field(m.polygons,'material_index',1,np.int32).tobytes()),'smooth':[p.use_smooth for p in m.polygons],
          'normals':digest(field(m.corner_normals,'vector',3,np.float32).tobytes()),
          'uv':[(u.name,u.active_render,u.active_clone,digest(field(u.data,'uv',2,np.float32).tobytes()))for u in m.uv_layers],
          'activeUv':m.uv_layers.active_index,'world':np.asarray(obj.matrix_world,np.float64).tobytes().hex(),
          'lineage':[x.value for x in m.attributes['constrained_lod_original_component'].data]if 'constrained_lod_original_component'in m.attributes else None,
          'edgeFlags':[(tuple(e.vertices),e.use_seam,e.use_edge_sharp)for e in m.edges]}
    def construct(name,points,faces,uv):
        mesh=bpy.data.meshes.new(name+'.mesh');mesh.from_pydata(points,[],faces);mesh.update()
        layer=mesh.uv_layers.new(name='UVMap');layer.data.foreach_set('uv',np.asarray(uv,np.float32).reshape(-1));mesh.materials.append(material)
        obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj['semanticPart']=name
        obj.matrix_world=Matrix.Translation((.013,.021,.034))@Euler((.11,-.17,.09)).to_matrix().to_4x4()@Matrix.Diagonal((1.1,.9,1.2,1.))
        bpy.context.view_layer.update();return obj
    octa_points=[(.05,0,0),(-.05,0,0),(0,.05,0),(0,-.05,0),(0,0,.05),(0,0,-.05)]
    octa_faces=[(4,0,2),(4,2,1),(4,1,3),(4,3,0),(5,2,0),(5,1,2),(5,3,1),(5,0,3)]
    octa_uv=[]
    for i in range(8):
        x=.05+.2*(i%4);y=.05+.3*(i//4);octa_uv.extend([(x,y),(x+.1,y),(x,y+.15)])
    octa=construct('LockedOcta',octa_points,octa_faces,octa_uv)
    corners=[(-.04,-.04,-.04),(.04,-.04,-.04),(.04,.04,-.04),(-.04,.04,-.04),(-.04,-.04,.04),(.04,-.04,.04),(.04,.04,.04),(-.04,.04,.04)]
    quads=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    points=[];faces=[];values=[]
    for i,quad in enumerate(quads):
        offset=len(points);points.extend(corners[v]for v in quad);faces.extend([(offset,offset+1,offset+2),(offset,offset+2,offset+3)])
        x=.03+.3*(i%3);y=.04+.4*(i//3);a,b,c,d=(x,y),(x+.2,y),(x+.2,y+.25),(x,y+.25)
        values.extend([a,b,c,a,c,d])
    cube=construct('DuplicatedUvCutCube',points,faces,values)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=.06)
    sphere=bpy.context.object;sphere.name='PartlyUnlockedTexturedSphere'
    sphere.data.uv_layers.active.name='UVMap';sphere.data.materials.append(material)
    bm=bmesh.new()
    try:bm.from_mesh(sphere.data);bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='FIXED',ngon_method='EAR_CLIP');bm.to_mesh(sphere.data)
    finally:bm.free()
    sphere.data.update();bpy.context.view_layer.update()
    cases=[]
    for label,source,locked in [('locked-octa',octa,True),('duplicated-uv-cut-cube',cube,True),('partly-unlocked-textured-sphere',sphere,False)]:
        before=legacy._preservation_runtime_state(source,api);source_bits=snapshot(source)
        welded=legacy._clod_copy(source,'Control.Welded')
        try:
            removed=legacy._clod_exact_weld(welded);topology=legacy._clod_topology(welded,1);boundary=legacy._clod_boundary_snapshot(welded.data)
            V,E,F=len(welded.data.vertices),len(welded.data.edges),api.triangles(welded);p=len(set(boundary['positions']));bound=max(4,2*p-4)
            assert V-E+F==2 and 3*F==2*E and topology['worldSignedVolume']>0
            assert (bound>=F)==locked
            expected={
                'locked-octa':(6,12,8,6,6,0),
                'duplicated-uv-cut-cube':(8,18,12,8,24,16),
                'partly-unlocked-textured-sphere':(86,252,168,31,86,0),
            }[label]
            assert (V,E,F,p,len(source.data.vertices),removed)==expected, (label,V,E,F,p,removed)
        finally:legacy._clod_dispose(welded)
        observations=[]
        for module in [legacy,fast]:
            old_apply=module._clod_apply_collapse;old_copy=module._clod_copy;calls=[];copies=[];outputs=[];started=time.perf_counter()
            def counted(obj,ratio,held):calls.append(ratio);return old_apply(obj,ratio,held)
            def counted_copy(obj,name):copies.append(name);return old_copy(obj,name)
            module._clod_apply_collapse=counted;module._clod_copy=counted_copy;objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
            try:
                outputs,report=module._clod_build_constrained_lods(source,settings,api,name_prefix='Comparison')
                bits=[snapshot(obj)for obj in outputs]
                selected=[[(c['selectedGridRatio'],c['triangles'],c['terminalOriginalRetention'],c['finiteRatioGrid'])for c in level['components']]for level in report['levels']]
                assert report['sourceLow0Immutable']and report['sourceLow0RawDecodedWorldNormalsPreserved']
                assert all(level['authoredDerivativeNormals']['nonzeroFinite']for level in report['levels'])
                for level in report['levels']:
                    assert level['topology']['closedManifold']and level['topology']['consistentlyOriented']and level['topology']['worldSignedVolume']>0
                    for comp in level['components']:
                        assert comp['trials'][-1]['status'].startswith('accepted')
                        for direction in ['sourceToCandidate','candidateToSource']:
                            assert comp['trials'][-1]['sameOriginalComponentEveryVertexDeviation'][direction]['allVerticesMeasured']
                observations.append({'nativeCollapseCalls':len(calls),'nativeRatios':calls,'nativeCopyCalls':len(copies),'nativeTrialCopyCalls':copies.count('Constrained.Trial'),'nativeCopyNames':copies,
                                     'outputs':bits,'selected':selected,'report':report,'elapsedSeconds':time.perf_counter()-started})
            finally:
                module._clod_apply_collapse=old_apply;module._clod_copy=old_copy
                for obj in outputs:module._clod_dispose(obj)
                assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
                legacy._verify_runtime_preservation(before,source,api,'Portable LOD comparison source',exact_world=True)
                assert snapshot(source)==source_bits
        a,b=observations;assert a['outputs']==b['outputs']and a['selected']==b['selected']
        def sequence(report):
            return [[[(t['gridRatio'],t['effectiveNativeRatio'],t['status'])for t in c['trials']]for c in level['components']]for level in report['levels']]
        assert sequence(a['report'])==sequence(b['report'])
        if locked:
            assert a['nativeCollapseCalls']==16 and b['nativeCollapseCalls']==0
            assert a['nativeTrialCopyCalls']==18 and b['nativeTrialCopyCalls']==2
            assert a['nativeCopyCalls']==22 and b['nativeCopyCalls']==6
            assert all(c['selectedGridRatio']==1.0 and c['triangles']==F and c['terminalOriginalRetention']
                       for level in b['report']['levels']for c in level['components'])
            assert b['nativeTrialCopyCalls']==2 and a['nativeTrialCopyCalls']-b['nativeTrialCopyCalls']==a['nativeCollapseCalls']
            skipped=[t for level in b['report']['levels']for c in level['components']for t in c['trials']if t['gridRatio']<1]
            assert skipped and all(t['status']=='rejected'and t['noReductionCertificate']['nativeInvoked']is False and t['noReductionCertificate']['candidateCopyInvoked']is False for t in skipped)
        else:
            visited=[t for level in a['report']['levels']for component in level['components']for t in component['trials']if t['gridRatio']<1]
            expected_ratios=[t['gridRatio']for t in visited]
            expected=len(expected_ratios)
            assert all(t['effectiveNativeRatio']==t['gridRatio']for t in visited)
            assert a['nativeCollapseCalls']==b['nativeCollapseCalls']==expected>0, (a['nativeCollapseCalls'],b['nativeCollapseCalls'],expected)
            assert a['nativeRatios']==b['nativeRatios']==expected_ratios
            assert any(c['selectedGridRatio']<1 and c['triangles']<F
                       for level in b['report']['levels']for c in level['components'])
            assert a['nativeCopyCalls']==b['nativeCopyCalls']and a['nativeTrialCopyCalls']==b['nativeTrialCopyCalls']
            assert all('noReductionCertificate'not in t for level in b['report']['levels']for c in level['components']for t in c['trials'])
        cases.append({'case':label,'originalEuler':{'V':V,'E':E,'F':F,'genus':0},'distinctProtectedPositions':p,'lowerBound':bound,
                      'sourceRawVertexCount':len(source.data.vertices),'nativeExactWeldRemovedVertices':removed,
                      'legacy':a,'fast':b,'rawOutputAndSelectionBitExact':True,'everyTrialRatioEffectiveRatioStatusSequenceExact':True,'sourceGeometryUvNormalsAndWorldStateExact':True})
    # A skipped trial still checkpoints and never bypasses source/cancel cleanup.
    objects=set(bpy.data.objects);meshes=set(bpy.data.meshes);before=fast._preservation_runtime_state(octa,api);uv_before=snapshot(octa);calls=[0]
    def cancel():
        calls[0]+=1
        if calls[0]==3:raise KeyboardInterrupt('Portable checkpoint cancellation')
    try:fast._clod_build_constrained_lods(octa,settings,api,name_prefix='Cancelled',cancel=cancel)
    except KeyboardInterrupt:pass
    else:raise AssertionError('Expected cancellation')
    assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes and snapshot(octa)==uv_before
    fast._verify_runtime_preservation(before,octa,api,'Cancelled optimized source',exact_world=True)
    # Terminal ratio1 must execute topology and cannot become an unchecked copy.
    old_topology=fast._clod_topology;terminal=[]
    def terminal_failure(obj,count):
        if obj.name.startswith('Constrained.Trial'):terminal.append(obj.name);raise fast._clod_Rejected('Portable terminal topology fault')
        return old_topology(obj,count)
    fast._clod_topology=terminal_failure
    try:
        try:fast._clod_build_constrained_lods(octa,settings,api,name_prefix='TerminalFault')
        except fast._clod_ConstrainedLodError as error:assert 'Finite grid exhausted'in str(error)
        else:raise AssertionError('Terminal topology guard skipped')
    finally:fast._clod_topology=old_topology
    assert terminal and set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes and snapshot(octa)==uv_before
    fast._verify_runtime_preservation(before,octa,api,'Terminal failure optimized source',exact_world=True)
    return {'status':'PORTABLE_LOCKED_LOD_RETENTION_CONTROLS_PASS','cases':cases,'checkpointCancellationAndCleanup':True,'terminalNativeTopologyGuardNotBypassed':True,
            'nativeExecution':True,'nativeFinisherFunctionsExercised':True,'fixtureArtRightsAndAdmission':'SIMULATED independent primitives, not real asset acceptance',
            'actualAssetLoaded':False,'productionManifestConsumed':False,'productionFinishAttemptConsumed':False}
