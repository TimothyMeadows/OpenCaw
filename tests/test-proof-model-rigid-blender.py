"""Real Blender rigid-finisher fixtures. All art/reviews/ancestry here are SIMULATED."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT/'runtime/bubo/resources/proof-to-model/blender'
BLENDER = os.environ.get('BLENDER_EXE') or shutil.which('blender') or 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False)+'\n', encoding='utf-8')


def edit_glb_document(path, change):
    data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0]
    document=json.loads(data[20:20+size]);change(document)
    payload=json.dumps(document,separators=(',',':')).encode('utf-8')
    payload+=b' '*((-len(payload))%4)
    tail=data[20+size:]
    path.write_bytes(b'glTF'+struct.pack('<II',2,20+len(payload)+len(tail))+struct.pack('<II',len(payload),0x4E4F534A)+payload+tail)


class RigidProduction(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path(BLENDER).is_file():
            raise unittest.SkipTest('Actual Blender4.5 unavailable')
        evidence = Path(os.environ.get('OPENCAW_PROOF_RIGID_EVIDENCE_ROOT',str(ROOT/'test/pipeline/tb')))
        evidence.resolve().relative_to(ROOT.resolve())
        cursor = evidence
        while cursor != ROOT:
            if cursor.is_symlink() or hasattr(cursor,'is_junction') and cursor.is_junction():
                raise ValueError('Evidence cannot traverse symlinks/junctions')
            cursor = cursor.parent
        evidence.mkdir(parents=True, exist_ok=True)
        cls.work = Path(tempfile.mkdtemp(prefix='r-',dir=evidence))
        cls.logs = []
        fixture = cls.work/'fixture.py'
        fixture.write_text('''import bpy
from pathlib import Path
bpy.ops.wm.read_factory_settings(use_empty=True)
folder = Path(__file__).parent
for label,position,color in [('body',(0,0,0),(0.8,0.04,0.02,1)),('head',(.5,0,0),(0.03,0.04,0.8,1)),('lamp',(.1,0,.4),(0.01,.3,.6,0.4))]:
    mat = bpy.data.materials.new('Fixture_'+label)
    mat.use_nodes = True
    shader = mat.node_tree.nodes['Principled BSDF']
    shader.inputs['Base Color'].default_value = color
    shader.inputs['Metallic'].default_value = .3
    shader.inputs['Roughness'].default_value = .4
    if label == 'lamp':
        shader.inputs['IOR'].default_value = 1.46
        shader.inputs['Alpha'].default_value = .4
        shader.inputs['Emission Color'].default_value = (0,.3,.6,1)
        shader.inputs['Emission Strength'].default_value = 2
        mat.surface_render_method = 'BLENDED'
    for role in ['HIGH','LOW']:
        divisions = 2 if role == 'HIGH' or label == 'lamp' else 1
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=divisions,radius=.15,location=position)
        obj = bpy.context.object
        obj.name = label+'_'+role
        obj.data.materials.append(mat)
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(island_margin=.02,scale_to_bounds=True)
        bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.export_scene.gltf(filepath=str(folder/'prepared.glb'),export_format='GLB',export_extras=True)
''',encoding='utf-8')
        cls.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',fixture], 'fixture')
        cls.raw = cls.work/'raw.glb'
        shutil.copyfile(cls.work/'prepared.glb',cls.raw)
        (cls.work/'authoring-source.txt').write_text('SIMULATED test-only source ancestry and technical review; not artist/human approval.\n')
        cls.recipe = {'targetFaces':100,'textureSize':64,'cageExtrusion':.1,'maxRayDistance':.3,'uvMargin':.02,
                      'lodRatios':[.5,.25],'colliderMaxFaces':64,'maxTriangles':5000,'maxMaterials':3,
                      'maxTextureBytes':1000000,'parts':[],'riggingRequired':False,'animationRequired':False}
        cls.base_parts = []
        for identity,parent,pivot in [('body',None,[0,0,0]),('head','body',[.5,0,0]),('lamp','head',[.1,0,.4])]:
            cls.base_parts.append({'id':identity,'parentId':parent,'pivot':pivot,'highObject':identity+'_HIGH','lowObject':identity+'_LOW',
                                   'maxTriangles':400,'maxVertexSurfaceErrorMetres':.1,'materialMode':'preserve' if identity=='lamp' else 'bake',
                                   'bakeGroup':None if identity=='lamp' else 'shell','collision':identity!='lamp',
                                   'collisionReason':'explicit engineering fixture external hull' if identity!='lamp' else 'internal optical presentation'})
        cls.wrapper = cls.work/'run.py'
        cls.wrapper.write_text('import sys\nsys.dont_write_bytecode=True\nsys.path.insert(0,'+repr(str(SCRIPTS))+')\nimport finish\n'
                               'def forbidden(*a,**k):raise AssertionError("Rigid path invoked QuadriFlow")\n'
                               'finish.run_quadriflow=forbidden\nfinish.main()\n',encoding='utf-8')

    @classmethod
    def run_process(cls, arguments, label, success=True):
        arguments = list(arguments)
        if str(arguments[0]) == str(BLENDER):
            arguments[1:1] = ['--threads', '2']
        environment = dict(os.environ)
        environment['PYTHONDONTWRITEBYTECODE']='1'
        temp = cls.work/'temp'
        temp.mkdir(exist_ok=True)
        for key in ('TEMP','TMP','TMPDIR'):
            environment[key]=str(temp)
        result = subprocess.run([str(a) for a in arguments],cwd=cls.work,env=environment,stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT,text=True,encoding='utf-8',timeout=300)
        (cls.work/(label+'.log')).write_text(result.stdout,encoding='utf-8')
        cls.logs.append({'label':label,'exitCode':result.returncode,'arguments':[str(a) for a in arguments]})
        save(cls.work/'runs.json',cls.logs)
        if success and result.returncode:
            raise AssertionError('Actual Blender failed '+label+':\n'+result.stdout[-12000:])
        if not success and not result.returncode:
            raise AssertionError('Rejected fixture succeeded '+label)
        return result

    def fixture(self, name, mutate=None):
        folder = self.work/name
        folder.mkdir()
        relative = lambda path:path.relative_to(self.work).as_posix()
        prepared = folder/'prepared.glb'
        shutil.copyfile(self.work/'prepared.glb',prepared)
        parts = json.loads(json.dumps(self.base_parts))
        source = {'path':'authoring-source.txt','sha256':sha(self.work/'authoring-source.txt'),'role':'SIMULATED controlled authoring source'}
        handoff = {'schemaVersion':1,'profile':'articulated','coordinateFrame':'opencaw-proof-z-up','sourceRawSha256':sha(self.raw),
                   'preparedGlb':relative(prepared),'preparedGlbSha256':sha(prepared),
                   'sourceToPreparedMatrix':[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],
                   'authoringEvidence':relative(folder/'authoring.json'),'authoringEvidenceSha256':'','parts':parts}
        authoring = {'schemaVersion':1,'kind':'rigid-part-authoring','sourceRawSha256':sha(self.raw),'preparedGlbSha256':sha(prepared),
                     'sources':[source],'repairs':[{'partId':p['id'],'sourceKind':'authored-detail','sourceDescription':'SIMULATED ico source',
                                                  'highTriangles':80 if p['id']!='lamp' else 80,
                                                  'lowTriangles':20 if p['id']!='lamp' else 80,
                                                  'intentionalChanges':'SIMULATED explicit fixture subdivision only'} for p in parts]}
        review_path = folder/'.opencaw/.cache/tasks/fixture/review.json'
        # All test state is confined to the fixture project, including its review.
        review_path = self.work/'.opencaw/.cache/tasks/fixture'/ (name+'-review.json')
        review_path.parent.mkdir(parents=True,exist_ok=True)
        settings = {'schemaVersion':2,'method':'rigid-parts','topologyPreparation':{'method':'none'},
                    'collision':{'method':'kdop-26','padding':.00001,'maxVolumeRatio':20},
                    'rigidParts':{'handoff':relative(folder/'handoff.json'),'handoffSha256':'','reviewEvidence':relative(review_path),
                                  'reviewEvidenceSha256':'','maxLod0Triangles':1000,'maxGlbBytes':10000000},
                    'resources':{'maxPrivateBytes':1073741824}}
        review = {'schemaVersion':1,'kind':'rigid-preparation','decision':'approved','human':False,'reviewer':'SIMULATED engineering review',
                  'reason':'SIMULATED controlled fixture only; not human acceptance','sourceRawSha256':sha(self.raw),
                  'preparedGlbSha256':sha(prepared),'handoffSha256':'','authoringEvidenceSha256':''}
        if mutate:
            mutate(handoff,authoring,review,settings,prepared)
        save(folder/'authoring.json',authoring)
        handoff['authoringEvidenceSha256']=sha(folder/'authoring.json')
        save(folder/'handoff.json',handoff)
        settings['rigidParts']['handoffSha256']=sha(folder/'handoff.json')
        review['handoffSha256']=sha(folder/'handoff.json')
        review['authoringEvidenceSha256']=sha(folder/'authoring.json')
        save(review_path,review)
        settings['rigidParts']['reviewEvidenceSha256']=sha(review_path)
        job = {'schemaVersion':1,'mode':'multi-view','root':str(self.work),'input':'raw.glb','inputFrame':'pixal3d-mv-export',
               'engineToProofScale':123,'outputDir':relative(folder/'outputs'),'result':relative(folder/'outputs/result.json'),
               'recipe':json.loads(json.dumps(self.recipe)),'finishingSettings':settings,'rigidHandoff':handoff,'taskEvidenceRoot':'.opencaw/.cache/tasks/fixture'}
        save(folder/'job.json',job)
        return folder,job

    def run_fixture(self,name,mutate=None,success=True):
        folder,job=self.fixture(name,mutate)
        before = sha(self.raw)
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],name,success)
        self.assertEqual(before,sha(self.raw))
        if success:
            return folder,json.loads((folder/'outputs/result.json').read_text())
        self.assertFalse((folder/'outputs/result.json').exists())
        return result.stdout

    def test_01_actual_grouped_atlas_preserve_alpha_emission_and_hierarchy(self):
        folder,result=self.run_fixture('positive')
        self.assertEqual(result['schemaVersion'],2)
        self.assertEqual(result['measurements']['lod0Triangles'],120)
        self.assertEqual(result['measurements']['materials'],2)
        self.assertEqual(len(result['measurements']['atlases']),1)
        self.assertEqual(len(result['measurements']['atlases'][0]['maps']),5)
        self.assertTrue(result['measurements']['atlases'][0]['packing']['exactLoopScatter'])
        self.assertFalse(result['stages'][0]['additionalFrameMappingApplied'])
        self.assertTrue(result['stages'][-1]['pivotsAndHierarchy'])
        self.assertEqual(result['humanApproval'],'pending')
        self.assertEqual(result['rigidHandoffSha256'],sha(folder/'handoff.json'))
        self.assertEqual(result['stages'][-1]['preserveMaterialIntentsVerified'],['Fixture_lamp'])
        self.assertFalse(result['measurements']['parts'][2]['collision']['applicable'])
        channels=next(item for item in result['stages'][-1]['materialChannelsAndPixels'] if item['material']=='ATLAS_shell')['textures']
        self.assertEqual({item['channel'] for item in channels},{'basecolor','normal','ao','roughness','metallic'})
        self.assertTrue(all(item['allPixelsVerified'] and item['pixels']==4096 for item in channels))
        probe=self.work/'atlas-probe.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid
from common import import_glb,inspect_glb
folder=Path('''+repr(str(folder))+''')
objects=import_glb(folder/'outputs/asset.glb')
material=bpy.data.materials['ATLAS_shell']
shader=material.node_tree.nodes['Principled BSDF']
image=rigid.texture_route(shader.inputs['Base Color'])['image']
pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4))
checked=0
for obj in objects:
    if obj.name not in ('body_LOD0','head_LOD0'):continue
    linear=np.asarray((.8,.04,.02) if obj.name=='body_LOD0' else (.03,.04,.8))
    expected=np.where(linear<=.0031308,linear*12.92,1.055*linear**(1/2.4)-.055)
    uv=obj.data.uv_layers.active
    for polygon in obj.data.polygons:
        point=sum((uv.data[i].uv for i in polygon.loop_indices),__import__('mathutils').Vector((0,0)))/len(polygon.loop_indices)
        x=min(image.size[0]-1,int(point.x*image.size[0]));y=min(image.size[1]-1,int(point.y*image.size[1]))
        assert np.max(np.abs(pixels[y,x,:3]-expected))<.01,(obj.name,polygon.index,pixels[y,x,:3],expected)
        checked+=1
assert checked==40
document=inspect_glb(folder/'outputs/asset.glb');data=(folder/'outputs/asset.glb').read_bytes()
description=rigid.material_document(document,data,next(m for m in document['materials'] if m['name']=='ATLAS_shell'))
rough=shader.inputs['Roughness'];metal=shader.inputs['Metallic']
rough_source=rough.links[0].from_socket;metal_source=metal.links[0].from_socket
material.node_tree.links.new(metal_source,rough)
try:rigid.verify_imported_material(material,description)
except ValueError as error:assert 'channel/colorspace differ' in str(error)
else:raise AssertionError('swapped ORM channel accepted')
material.node_tree.links.new(rough_source,rough)
obj=next(o for o in objects if o.name=='body_LOD0');snapshot=rigid.corner_snapshot(obj)
old_uv=obj.data.uv_layers.active.data[0].uv.copy()
obj.data.uv_layers.active.data[0].uv.x+=.2
try:rigid.verify_corners(snapshot,obj)
except ValueError:pass
else:raise AssertionError('corrupt UV correspondence accepted')
obj.data.uv_layers.active.data[0].uv=old_uv
normals=[tuple(normal.vector) for normal in obj.data.corner_normals]
normals[0]=tuple(-value for value in normals[0]);obj.data.normals_split_custom_set(normals)
try:rigid.verify_corners(snapshot,obj)
except ValueError as error:assert 'corner normals' in str(error)
else:raise AssertionError('corrupt normal correspondence accepted')
print('ALL40PART_TRIANGLE_COLOR_SAMPLES_AND_ORM_UV_NEGATIVES_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'atlas-correspondence')

    def test_02_stale_review_rejected(self):
        output=self.run_fixture('stale-review',lambda h,a,r,s,p:r.update(sourceRawSha256='0'*64),False)
        self.assertIn('Stale preparation review',output)

    def test_03_source_ancestry_hash_rejected(self):
        output=self.run_fixture('wrong-raw',lambda h,a,r,s,p:h.update(sourceRawSha256='0'*64),False)
        self.assertIn('raw ancestry',output)

    def test_04_cycle_rejected(self):
        output=self.run_fixture('cycle',lambda h,a,r,s,p:h['parts'][0].update(parentId='head'),False)
        self.assertIn('cyclic',output)

    def test_05_undeclared_mesh_rejected(self):
        output=self.run_fixture('wrong-object',lambda h,a,r,s,p:h['parts'][0].update(lowObject='Absent'),False)
        self.assertIn('account for all',output)

    def test_06_imported_count_evidence_rejected(self):
        output=self.run_fixture('wrong-count',lambda h,a,r,s,p:a['repairs'][0].update(highTriangles=100),False)
        self.assertIn('triangle evidence',output)

    def test_07_part_triangle_cap_rejected(self):
        output=self.run_fixture('part-cap',lambda h,a,r,s,p:h['parts'][0].update(maxTriangles=4),False)
        self.assertIn('part triangle limit',output)

    def test_08_error_bound_rejected(self):
        output=self.run_fixture('error-cap',lambda h,a,r,s,p:h['parts'][0].update(maxVertexSurfaceErrorMetres=.000001),False)
        self.assertIn('surface bound',output)

    def test_09_preserve_cannot_skip_reduced_body(self):
        output=self.run_fixture('fake-preserve',lambda h,a,r,s,p:h['parts'][0].update(materialMode='preserve',bakeGroup=None),False)
        self.assertIn('Preserve requires identical',output)

    def test_10_whole_lod0_cap_rejected(self):
        output=self.run_fixture('lod0-cap',lambda h,a,r,s,p:s['rigidParts'].update(maxLod0Triangles=4),False)
        self.assertIn('whole-asset triangle limit',output)

    def test_11_path_escape_rejected(self):
        output=self.run_fixture('path-escape',lambda h,a,r,s,p:h.update(preparedGlb='../outside.glb'),False)
        self.assertIn('relative path',output)

    def test_12_authoring_dependency_change_rejected(self):
        output=self.run_fixture('source-change',lambda h,a,r,s,p:a['sources'][0].update(sha256='0'*64),False)
        self.assertIn('changed rigid input',output)

    def test_13_wrong_review_task_rejected(self):
        folder,job=self.fixture('wrong-task')
        job['taskEvidenceRoot']='.opencaw/.cache/tasks/another'
        save(folder/'job.json',job)
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],'wrong-task',False)
        self.assertIn('different task',result.stdout)

    def test_14_duplicate_handoff_field_rejected(self):
        folder,job=self.fixture('duplicate')
        path=folder/'handoff.json'
        path.write_text(path.read_text().replace('"schemaVersion": 1,','"schemaVersion": 1, "schemaVersion": 1,',1))
        job['finishingSettings']['rigidParts']['handoffSha256']=sha(path)
        save(folder/'job.json',job)
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],'duplicate',False)
        self.assertIn('Duplicate JSON field',result.stdout)

    def test_15_fractional_settings_and_boolean_bounds_rejected(self):
        for label,value in [('fraction',4.5),('boolean',True)]:
            output=self.run_fixture(label,lambda h,a,r,s,p:s['rigidParts'].update(maxLod0Triangles=value),False)
            self.assertIn('bounded integer',output)

    def test_16_rounded_fractional_integer_token_rejected(self):
        folder,job=self.fixture('rounded-fraction')
        save(folder/'job.json',job)
        text=(folder/'job.json').read_text().replace('"maxLod0Triangles": 1000','"maxLod0Triangles": 1000.000000000000000001',1)
        (folder/'job.json').write_text(text)
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],'rounded-fraction',False)
        self.assertIn('bounded integer',result.stdout)

    def test_17_unknown_v2_field_rejected(self):
        output=self.run_fixture('unknown',lambda h,a,r,s,p:s.update(quadriFlow={'coordinateScale':1}),False)
        self.assertIn('requires exactly',output)

    def test_18_baking_emissive_optics_rejected(self):
        output=self.run_fixture('emissive-bake',lambda h,a,r,s,p:h['parts'][2].update(materialMode='bake',bakeGroup='shell'),False)
        self.assertIn('opaque/nonemissive',output)

    def test_19_runtime_name_collision_rejected(self):
        def mutate(h,a,r,s,p):
            h['parts'][2]['id']='body_LOD0';a['repairs'][2]['partId']='body_LOD0'
        output=self.run_fixture('name-collision',mutate,False)
        self.assertIn('naming collisions',output)

    def test_20_actual_glb_byte_limit_rejected(self):
        output=self.run_fixture('glb-limit',lambda h,a,r,s,p:s['rigidParts'].update(maxGlbBytes=1024),False)
        self.assertRegex(output,r'GLB exceeds explicit (?:byte budget|input byte bound)')

    def test_21_material_limit_rejected(self):
        folder,job=self.fixture('material-limit');job['recipe']['maxMaterials']=1;save(folder/'job.json',job)
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],'material-limit',False)
        self.assertIn('complete package exceeds',result.stdout)

    def test_22_collision_face_limit_rejected(self):
        folder,job=self.fixture('collider-limit');job['recipe']['colliderMaxFaces']=4;save(folder/'job.json',job)
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],'collider-limit',False)
        self.assertIn('colliderMaxFaces',result.stdout)

    def test_23_prepared_transform_not_double_applied(self):
        # The positive fixture uses engineToProofScale123 deliberately. Its
        # measured final hierarchy remains near the actual authored .5m pivots.
        folder,result=self.run_fixture('exact-hull',lambda h,a,r,s,p:s.update(collision={'method':'exact-hull'}))
        self.assertLess(result['stages'][-1]['bounds']['max'][0],1)
        self.assertTrue(all(p['collision'].get('method')=='exact-hull' for p in result['measurements']['parts'] if p['collision']['applicable']))

    def test_24_same_model_changed_part_bounds_invalidates_review(self):
        folder,job=self.fixture('changed-handoff')
        handoff=job['rigidHandoff'];handoff['parts'][0]['pivot'][0]=.01
        save(folder/'handoff.json',handoff)
        job['finishingSettings']['rigidParts']['handoffSha256']=sha(folder/'handoff.json')
        save(folder/'job.json',job)
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],'changed-handoff',False)
        self.assertIn('Stale preparation review: handoffSha256',result.stdout)

    def test_25_real_submicrometre_open_seam_is_not_welded_into_a_pass(self):
        def mutate(h,a,r,s,p):
            data=bytearray(p.read_bytes());size=struct.unpack_from('<I',data,12)[0]
            document=json.loads(data[20:20+size]);binary=20+size+8
            node=next(node for node in document['nodes'] if node.get('name')=='body_LOW')
            accessor=document['accessors'][document['meshes'][node['mesh']]['primitives'][0]['attributes']['POSITION']]
            view=document['bufferViews'][accessor['bufferView']]
            offset=binary+view.get('byteOffset',0)+accessor.get('byteOffset',0);stride=view.get('byteStride',12)
            seen={};changed=False
            for index in range(accessor['count']):
                point=struct.unpack_from('<fff',data,offset+index*stride)
                if point in seen:
                    struct.pack_into('<f',data,offset+index*stride,point[0]+5e-8);changed=True;break
                seen[point]=index
            assert changed,'Fixture needs actual UV-split duplicate vertices'
            p.write_bytes(data)
            for item in (h,a,r):item['preparedGlbSha256']=sha(p)
        output=self.run_fixture('open-small-seam',mutate,False)
        self.assertIn('closed manifold',output)

    def test_26_child_first_order_retains_declared_nonzero_nested_pivots(self):
        def mutate(h,a,r,s,p):
            h['parts'][0]['pivot']=[.2,.1,-.05]
            h['parts'].reverse()
        folder,result=self.run_fixture('child-first',mutate)
        self.assertTrue(result['stages'][-1]['pivotsAndHierarchy'])
        self.assertEqual(result['measurements']['parts'][0]['part'],'lamp')

    def test_27_fixed_preflight_is_actual_read_only_and_immutable(self):
        folder,job=self.fixture('preflight')
        original={p:sha(p) for p in [self.raw,folder/'prepared.glb',folder/'handoff.json',folder/'authoring.json']}
        report='.opencaw/.cache/tasks/fixture/preflight-result.json'
        command=[BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                 '--python',SCRIPTS/'rigid_finish.py','--','--preflight','--job',folder/'job.json','--report',report]
        self.run_process(command,'preflight')
        data=json.loads((self.work/report).read_text())
        self.assertEqual(data['status'],'inspected')
        self.assertTrue(data['readOnly'] and data['allHighLowPairsInspected'])
        self.assertFalse(data['nativeFinish'])
        self.assertEqual(data['partCount'],3)
        self.assertEqual(data['importedInspectionIdentitiesBefore'],data['importedInspectionIdentitiesAfter'])
        self.assertFalse((folder/'outputs').exists())
        self.assertEqual(original,{p:sha(p) for p in original})
        self.assertIn('immutable',self.run_process(command,'preflight-replay',False).stdout)
        command[-1]='../escaped.json'
        self.assertIn('relative path',self.run_process(command,'preflight-escape',False).stdout)

    def test_28_preserve_only_is_real_unchanged_geometry_without_fake_bakes(self):
        def mutate(h,a,r,s,p):
            def change(document):
                nodes={node['name']:node for node in document['nodes'] if 'name' in node}
                for identity in ('body','head'):
                    nodes[identity+'_LOW']['mesh']=nodes[identity+'_HIGH']['mesh']
            edit_glb_document(p,change)
            for part in h['parts']:part.update(materialMode='preserve',bakeGroup=None)
            for repair in a['repairs']:repair['lowTriangles']=80
            for item in (h,a,r):item['preparedGlbSha256']=sha(p)
        folder,result=self.run_fixture('preserve-only',mutate)
        self.assertEqual(result['measurements']['atlases'],[])
        self.assertEqual(result['measurements']['textureBytes'],0)
        self.assertEqual(result['measurements']['lod0Triangles'],240)
        self.assertEqual(len(result['stages'][-1]['preserveMaterialIntentsVerified']),3)

    def test_29_actual_preserved_texture_alpha_emission_and_colorspace(self):
        def mutate(h,a,r,s,p):
            helper=p.parent/'texture.py'
            helper.write_text('''import sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy
from common import import_glb
path=Path('''+repr(str(p))+''');import_glb(path)
material=bpy.data.materials['Fixture_lamp'];shader=material.node_tree.nodes['Principled BSDF']
image=bpy.data.images.new('PreservedChecker',width=8,height=8,alpha=True)
image.colorspace_settings.name='sRGB'
image.pixels.foreach_set([value for y in range(8) for x in range(8) for value in ((.1,.5,.8,1) if (x+y)%2 else (.8,.1,.2,1))])
image.filepath_raw=str(path.parent/'checker.png');image.file_format='PNG';image.save();image.pack()
node=material.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
multiply=material.node_tree.nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY'
multiply.inputs[0].default_value=1;multiply.inputs[2].default_value=(.6,.8,.4,1)
material.node_tree.links.new(node.outputs['Color'],multiply.inputs[1]);material.node_tree.links.new(multiply.outputs['Color'],shader.inputs['Base Color'])
orm=bpy.data.images.new('DistinctOrm',width=8,height=8,alpha=False);orm.colorspace_settings.name='Non-Color'
orm.pixels.foreach_set([value for y in range(8) for x in range(8) for value in ((.9,.6,.2,1) if (x+y)%2 else (.7,.4,.3,1))])
orm.filepath_raw=str(path.parent/'orm.png');orm.file_format='PNG';orm.save();orm.pack()
orm_node=material.node_tree.nodes.new('ShaderNodeTexImage');orm_node.image=orm
separate=material.node_tree.nodes.new('ShaderNodeSeparateColor');separate.mode='RGB'
material.node_tree.links.new(orm_node.outputs['Color'],separate.inputs['Color'])
for channel,input_name,factor in [('Green','Roughness',.5),('Blue','Metallic',.7)]:
    scalar=material.node_tree.nodes.new('ShaderNodeMath');scalar.operation='MULTIPLY';scalar.inputs[1].default_value=factor
    material.node_tree.links.new(separate.outputs[channel],scalar.inputs[0]);material.node_tree.links.new(scalar.outputs[0],shader.inputs[input_name])
emission=bpy.data.images.new('DistinctEmission',width=8,height=8,alpha=False);emission.colorspace_settings.name='sRGB'
emission.pixels.foreach_set([value for y in range(8) for x in range(8) for value in ((.2,.5,.7,1) if (x+y)%2 else (.4,.2,.6,1))])
emission.filepath_raw=str(path.parent/'emission.png');emission.file_format='PNG';emission.save();emission.pack()
emission_node=material.node_tree.nodes.new('ShaderNodeTexImage');emission_node.image=emission
material.node_tree.links.new(emission_node.outputs['Color'],shader.inputs['Emission Color'])
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB')
''',encoding='utf-8')
            self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',helper],'texture-fixture')
            for item in (h,a,r):item['preparedGlbSha256']=sha(p)
        folder,result=self.run_fixture('textured-preserve',mutate)
        lamp=next(m for m in result['stages'][-1]['materialChannelsAndPixels'] if m['material']=='Fixture_lamp')
        self.assertEqual({channel['channel'] for channel in lamp['textures']},{'basecolor','alpha','roughness','metallic','emission'})
        self.assertTrue(all(channel['actualConnectionVerified'] for channel in lamp['textures']))
        probe=folder/'preserve-factor-probe.py'
        probe.write_text('''import sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,rigid_finish as rigid
from common import import_glb,inspect_glb
path=Path('''+repr(str(folder/'outputs/asset.glb'))+''');import_glb(path)
doc=inspect_glb(path);description=rigid.material_document(doc,path.read_bytes(),next(m for m in doc['materials'] if m['name']=='Fixture_lamp'))
mat=bpy.data.materials['Fixture_lamp'];shader=mat.node_tree.nodes['Principled BSDF']
rigid.verify_imported_material(mat,description)
checks=0
for field in ['Roughness','Metallic','Alpha']:
    node=shader.inputs[field].links[0].from_node
    assert node.type=='MATH' and node.operation=='MULTIPLY'
    constant=next(socket for socket in node.inputs[:2] if not socket.is_linked)
    old=constant.default_value;constant.default_value=.17
    try:rigid.verify_imported_material(mat,description)
    except ValueError as error:assert 'factor differs' in str(error),str(error)
    else:raise AssertionError('Changed preserved multiplier accepted: '+field)
    constant.default_value=old;checks+=1
original_color=shader.inputs['Base Color'].links[0].from_socket
node=mat.node_tree.nodes.new('ShaderNodeMixRGB');node.blend_type='MULTIPLY'
node.inputs[0].default_value=1;node.inputs[2].default_value=(.1,.1,.1,1)
mat.node_tree.links.new(original_color,node.inputs[1]);mat.node_tree.links.new(node.outputs[0],shader.inputs['Base Color'])
try:rigid.verify_imported_material(mat,description)
except ValueError as error:assert 'factor differs' in str(error)
else:raise AssertionError('Changed preserved color factor accepted')
mat.node_tree.links.new(original_color,shader.inputs['Base Color']);mat.node_tree.nodes.remove(node);checks+=1
route=rigid.texture_route(shader.inputs['Base Color']);image=route['image']
tex=next(n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image==image)
old_space=image.colorspace_settings.name;image.colorspace_settings.name='Non-Color'
try:rigid.verify_imported_material(mat,description)
except ValueError as error:assert 'colorspace differ' in str(error)
else:raise AssertionError('Changed preserved colorspace accepted')
image.colorspace_settings.name=old_space;checks+=1
for property_name,value in [('interpolation','Closest'),('extension','EXTEND')]:
    old=tex.interpolation if property_name=='interpolation' else tex.extension
    if property_name=='interpolation':tex.interpolation=value
    else:tex.extension=value
    try:rigid.verify_imported_material(mat,description)
    except ValueError as error:assert 'sampler differs' in str(error)
    else:raise AssertionError('Changed preserved sampler accepted')
    if property_name=='interpolation':tex.interpolation=old
    else:tex.extension=old
    checks+=1
old_link=tex.inputs['Vector'].links[0].from_socket if tex.inputs['Vector'].is_linked else None
coordinate=mat.node_tree.nodes.new('ShaderNodeTexCoord');mat.node_tree.links.new(coordinate.outputs['Generated'],tex.inputs['Vector'])
try:rigid.verify_imported_material(mat,description)
except ValueError as error:assert 'Vector/transform route' in str(error)
else:raise AssertionError('Generated coordinates accepted as UV')
for link in list(tex.inputs['Vector'].links):mat.node_tree.links.remove(link)
if old_link:mat.node_tree.links.new(old_link,tex.inputs['Vector'])
checks+=1
uv=mat.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='MissingUv'
mat.node_tree.links.new(uv.outputs['UV'],tex.inputs['Vector'])
try:rigid.verify_imported_material(mat,description)
except ValueError as error:assert 'texCoord ownership differs' in str(error)
else:raise AssertionError('Wrong UV set accepted')
for link in list(tex.inputs['Vector'].links):mat.node_tree.links.remove(link)
if old_link:mat.node_tree.links.new(old_link,tex.inputs['Vector'])
checks+=1
old=shader.inputs['Emission Strength'].default_value;shader.inputs['Emission Strength'].default_value=.17
try:rigid.verify_imported_material(mat,description)
except ValueError as error:assert 'emission' in str(error) and 'differs' in str(error)
else:raise AssertionError('Changed preserved emission accepted')
shader.inputs['Emission Strength'].default_value=old;checks+=1
rigid.verify_imported_material(mat,description)
print('PRESERVED_FACTOR_UV_SAMPLER_COLORSPACE_EMISSION_NEGATIVES_PASS',checks)
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'preserved-factor-negatives')

    def test_30_rotated_nonuniform_preserve_rebase_carries_world_normals(self):
        def mutate(h,a,r,s,p):
            def change(document):
                for node in document['nodes']:
                    if node.get('name') in ('lamp_HIGH','lamp_LOW'):
                        node['rotation']=[0,.3826834323650898,0,.9238795325112867]
                        node['scale']=[1,.8,1.2]
            edit_glb_document(p,change)
            a['repairs'][2]['intentionalChanges']='SIMULATED rotated nonuniform optical part; actual normal-basis regression'
            for item in (h,a,r):item['preparedGlbSha256']=sha(p)
        folder,result=self.run_fixture('rotated-preserve',mutate)
        lamp=next(p for p in result['measurements']['parts'] if p['part']=='lamp')
        self.assertLessEqual(lamp['pivotRebase']['maxCornerNormalDrift'],2e-5)

    def test_31_case_aliasing_atlas_groups_fail_before_baking(self):
        output=self.run_fixture('group-case-alias',lambda h,a,r,s,p:h['parts'][1].update(bakeGroup='SHELL'),False)
        self.assertIn('alias generated atlas filenames',output)

    def test_32_bake_cannot_silently_drop_unsupported_material_lobes(self):
        def mutate(h,a,r,s,p):
            def change(document):
                material=next(m for m in document['materials'] if m['name']=='Fixture_body')
                material.setdefault('extensions',{})['KHR_materials_clearcoat']={'clearcoatFactor':.5}
                document.setdefault('extensionsUsed',[]).append('KHR_materials_clearcoat')
            edit_glb_document(p,change)
            for item in (h,a,r):item['preparedGlbSha256']=sha(p)
        output=self.run_fixture('unsupported-coat-bake',mutate,False)
        self.assertIn('cannot discard unsupported source lobe/property',output)

    def test_33_fixed_preflight_rejects_unrealized_mirror_before_mutation(self):
        def mutate(h,a,r,s,p):
            def change(document):
                for node in document['nodes']:
                    if node.get('name') in ('lamp_HIGH','lamp_LOW'):node['scale']=[-1,1,1]
            edit_glb_document(p,change)
            for item in (h,a,r):item['preparedGlbSha256']=sha(p)
        folder,job=self.fixture('mirrored-preflight',mutate)
        report='.opencaw/.cache/tasks/fixture/mirror-rejected.json'
        result=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',SCRIPTS/'rigid_finish.py','--','--preflight','--job',folder/'job.json','--report',report],
                                'mirrored-preflight',False)
        self.assertIn('positive realized world basis',result.stdout)
        self.assertFalse((folder/'outputs').exists())
        self.assertFalse((self.work/report).exists())

    def test_34_explicit_pixel_atlas_real_bake_export_reimport(self):
        folder,result=self.run_fixture('pixel-atlas',lambda h,a,r,s,p:s['rigidParts'].update(
            uvAtlas={'method':'smart-project-pixels','islandMarginPixels':2}))
        packing=result['measurements']['atlases'][0]['packing']
        atlas=packing['uvAtlas']
        self.assertEqual({k:atlas[k] for k in ('method','islandMarginPixels','marginMethod','islandMarginFraction','textureSize')},
                         {'method':'smart-project-pixels','islandMarginPixels':2,'marginMethod':'FRACTION','islandMarginFraction':2/64,'textureSize':64})
        self.assertEqual(atlas['zeroAreaTriangles'],0)
        self.assertEqual(atlas['triangles'],40)
        self.assertTrue(atlas['unitTile'] and packing['exactLoopScatter'])
        self.assertGreater(atlas['summedUvTriangleArea'],.1)
        self.assertLessEqual(atlas['maxGeometricHelperCornerNormalDrift'],2e-5)
        preservation=packing['runtimeLowNormalPreservation']
        self.assertEqual(len(preservation),2)
        self.assertTrue(all(item['localMeshAndRawDecodedNormalsBitExact'] for item in preservation))
        self.assertTrue(all(item['maxCornerNormalDrift']<=2e-5 and item['maxPositionDriftMetres']<=1e-6
                            for item in preservation))
        self.assertEqual(len(result['measurements']['atlases'][0]['maps']),5)
        channels=next(item for item in result['stages'][-1]['materialChannelsAndPixels'] if item['material']=='ATLAS_shell')['textures']
        self.assertEqual({item['channel'] for item in channels},{'basecolor','normal','ao','roughness','metallic'})
        self.assertTrue(all(item['allPixelsVerified'] and item['pixels']==4096 for item in channels))
        # Re-import in a second actual process and sample every part triangle's
        # centre against the distinct HIGH colours. This detects crossed packing
        # ownership as well as an export which merely carries nonempty textures.
        probe=folder/'probe.py'
        probe.write_text('''import sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid
from common import import_glb
from mathutils import Vector
objects=import_glb(Path('''+repr(str(folder/'outputs/asset.glb'))+'''))
material=bpy.data.materials['ATLAS_shell'];shader=material.node_tree.nodes['Principled BSDF']
image=rigid.texture_route(shader.inputs['Base Color'])['image']
pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4))
checked=0
for obj in objects:
    if obj.name not in ('body_LOD0','head_LOD0'):continue
    linear=np.asarray((.8,.04,.02) if obj.name=='body_LOD0' else (.03,.04,.8))
    expected=np.where(linear<=.0031308,linear*12.92,1.055*linear**(1/2.4)-.055)
    uv=obj.data.uv_layers.active
    for polygon in obj.data.polygons:
        coords=[uv.data[i].uv.copy() for i in polygon.loop_indices]
        area=abs((coords[1].x-coords[0].x)*(coords[2].y-coords[0].y)-(coords[1].y-coords[0].y)*(coords[2].x-coords[0].x))/2
        assert area>0 and all(0<=c<=1 for point in coords for c in point)
        point=sum(coords,Vector((0,0)))/3
        x=min(image.size[0]-1,int(point.x*image.size[0]));y=min(image.size[1]-1,int(point.y*image.size[1]))
        assert np.max(np.abs(pixels[y,x,:3]-expected))<.01,(obj.name,polygon.index,pixels[y,x,:3],expected)
        checked+=1
assert checked==40
print('EXPLICIT_PIXEL_ATLAS40INDEPENDENT_REIMPORT_COLOR_AND_UV_CHECKS_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'pixel-atlas-reimport')

    def test_35_native_pixel_settings_and_recipe_guards_before_work(self):
        folder,job=self.fixture('pixel-invalid-recipe',lambda h,a,r,s,p:s['rigidParts'].update(
            uvAtlas={'method':'smart-project-pixels','islandMarginPixels':9}))
        output=self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1',
                                 '--python',self.wrapper,'--','--job',folder/'job.json'],'pixel-invalid-recipe',False).stdout
        self.assertIn('textureSize/8',output)
        self.assertFalse(any((folder/'outputs').iterdir()))
        # Exercise the strict native JSON parser independently of the C# reader.
        probe=folder/'guards.py'
        probe.write_text('''import sys,json,copy
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import finish,rigid_finish as rigid
job=rigid.strict_json(Path('''+repr(str(folder/'job.json'))+'''),4194304,32)
base=job['finishingSettings'];base['rigidParts']['uvAtlas']['islandMarginPixels']=2
checks=0
bad=[None,[],{}, {'method':'automatic','islandMarginPixels':2},
     {'method':'smart-project-pixels'}, {'islandMarginPixels':2},
     {'method':'smart-project-pixels','islandMarginPixels':2,'extra':1}]
bad += [{'method':'smart-project-pixels','islandMarginPixels':v} for v in [True,'2',0,65,2.5,float('nan'),float('inf')]]
for atlas in bad:
    value=copy.deepcopy(base);value['rigidParts']['uvAtlas']=atlas
    try:rigid.validate_settings(value)
    except ValueError:checks+=1
    else:raise AssertionError('Malformed UV declaration admitted: '+repr(atlas))
path=Path(__file__).with_name('strict.json')
text=json.dumps(base)
for token in ['2.0000000000000000001','20000000000000000001e-19','1e-999999999','1e999999999','NaN','Infinity']:
    path.write_text(text.replace('"islandMarginPixels": 2','"islandMarginPixels": '+token))
    try:rigid.validate_settings(rigid.strict_json(path,65536,16))
    except ValueError:checks+=1
    else:raise AssertionError('Inexact/nonfinite pixel token admitted: '+token)
for field in ['"method": "smart-project-pixels"','"islandMarginPixels": 2']:
    path.write_text(text.replace(field,field+','+field))
    try:rigid.validate_settings(rigid.strict_json(path,65536,16))
    except ValueError:checks+=1
    else:raise AssertionError('Duplicate pixel field admitted')
for token in ['1','64','2.0','2e0','200e-2','0.2e1']:
    path.write_text(text.replace('"islandMarginPixels": 2','"islandMarginPixels": '+token))
    normalized=rigid.validate_settings(rigid.strict_json(path,65536,16));pixels=normalized['rigidParts']['uvAtlas']['islandMarginPixels']
    assert type(pixels) is int
    recipe=dict(job['recipe'],textureSize=pixels*8)
    assert rigid.resolve_uv_atlas(normalized,recipe)['islandMarginFraction']==1/8
    checks+=1
for value in [{'schemaVersion':1,'topologyPreparation':{'method':'none'},'collision':{'method':'exact-hull'},'rigidParts':base['rigidParts']},
              {'schemaVersion':1,'topologyPreparation':{'method':'none'},'collision':{'method':'exact-hull'},'uvAtlas':base['rigidParts']['uvAtlas']}]:
    try:finish.validate_finishing_settings(value)
    except ValueError:checks+=1
    else:raise AssertionError('V1 selected rigid-only pixel override')
legacy=copy.deepcopy(base);del legacy['rigidParts']['uvAtlas']
assert 'uvAtlas' not in rigid.validate_settings(legacy)['rigidParts']
assert rigid.resolve_uv_atlas(legacy,{'textureSize':1}) is None
print('NATIVE_PIXEL_SETTINGS_GUARDS_PASS',checks)
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'pixel-native-settings')

    def test_36_actual_pixel_packing_preserves_loop_geometry_and_normals(self):
        folder,job=self.fixture('pixel-loop-ancestry')
        probe=folder/'packing.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid
from common import import_glb
from mathutils import Euler
objects=import_glb(Path('''+repr(str(folder/'prepared.glb'))+'''))
lows=[next(o for o in objects if o.name==name) for name in ['body_LOW','head_LOW']]
for index,low in enumerate(lows):
    low['semanticPart']=str(index);low.rotation_euler=Euler((.2,.3*index,.1));low.scale=(1,.8,1.2)
bpy.context.view_layer.update()
def snapshot(low):
    return {'vertices':[tuple(v.co) for v in low.data.vertices],
            'loops':[loop.vertex_index for loop in low.data.loops],
            'polygons':[(tuple(p.loop_indices),p.use_smooth) for p in low.data.polygons],
            'matrix':list(sum((list(row) for row in low.matrix_world),[])),
            'normals':np.asarray([list(n.vector) for n in low.data.corner_normals])}
before=[snapshot(low) for low in lows]
original=bpy.ops.uv.smart_project;calls=[]
def observe(**kwargs):
    calls.append(kwargs);return original(**kwargs)
from types import SimpleNamespace as Namespace
rigid.bpy=Namespace(data=bpy.data,context=bpy.context,ops=Namespace(object=bpy.ops.object,mesh=bpy.ops.mesh,uv=Namespace(smart_project=observe)))
recipe={'uvMargin':.02,'textureSize':64}
atlas={'method':'smart-project-pixels','islandMarginPixels':2,'marginMethod':'FRACTION','islandMarginFraction':2/64,'textureSize':64}
report=rigid.pack_group(lows,recipe,'explicit',atlas)
assert calls==[{'margin_method':'FRACTION','island_margin':2/64,'scale_to_bounds':True}]
target=bpy.data.objects[report['target']];offset=0
for low,expected in zip(lows,before):
    actual=snapshot(low)
    assert all(actual[k]==expected[k] for k in ['vertices','loops','polygons','matrix'])
    assert np.max(np.abs(actual['normals']-expected['normals']))<=2e-5
    for polygon in low.data.polygons:
        for loop in polygon.loop_indices:
            assert tuple(low.data.uv_layers.active.data[loop].uv)==tuple(target.data.uv_layers.active.data[offset].uv)
            offset+=1
assert offset==report['loops']==120
calls.clear()
legacy=rigid.pack_group(lows,recipe,'legacy')
assert calls==[{'island_margin':.02,'scale_to_bounds':True}]
assert 'uvAtlas' not in legacy
print('ACTUAL_PIXEL_PACK_LOOP_VERTEX_TRANSFORM_NORMAL_ANCESTRY_AND_LEGACY_CALL_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'pixel-loop-ancestry')

    def test_37_finished_pixel_packing_faults_block_before_scatter(self):
        folder,job=self.fixture('pixel-pack-faults')
        probe=folder/'faults.py'
        probe.write_text('''import sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,rigid_finish as rigid
from common import import_glb
objects=import_glb(Path('''+repr(str(folder/'prepared.glb'))+'''))
low=next(o for o in objects if o.name=='body_LOW');low['semanticPart']='body'
original=bpy.ops.uv.smart_project
recipe={'uvMargin':.02,'textureSize':64}
atlas={'method':'smart-project-pixels','islandMarginPixels':2,'marginMethod':'FRACTION','islandMarginFraction':2/64,'textureSize':64}
for fault,message in [('collapsed','degenerate UV'),('bounds','outside unit'),('nonfinite','nonfinite'),('cancelled','did not finish')]:
    before=[tuple(v.uv) for v in low.data.uv_layers.active.data]
    def defective(**kwargs):
        status=original(**kwargs)
        if fault=='cancelled':return {'CANCELLED'}
        bpy.ops.object.mode_set(mode='OBJECT')
        data=bpy.context.object.data.uv_layers.active.data
        if fault=='collapsed':
            for i in range(3):data[i].uv=(.5,.5)
        elif fault=='bounds':data[0].uv.x=1.1
        else:data[0].uv.x=float('nan')
        bpy.ops.object.mode_set(mode='EDIT')
        return status
    from types import SimpleNamespace as Namespace
    rigid.bpy=Namespace(data=bpy.data,context=bpy.context,ops=Namespace(object=bpy.ops.object,mesh=bpy.ops.mesh,uv=Namespace(smart_project=defective)))
    try:rigid.pack_group([low],recipe,fault,atlas)
    except ValueError as error:assert message in str(error),str(error)
    else:raise AssertionError('Invalid FINISHED packing admitted: '+fault)
    if bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
    assert before==[tuple(v.uv) for v in low.data.uv_layers.active.data]
    assert list(Path(__file__).parent.glob('atlas_*.png'))==[]
print('INVALID_FINISHED_PIXEL_UVS_BLOCK_BEFORE_SOURCE_SCATTER_OR_BAKE_PASS4')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'pixel-pack-faults')

    def test_38_actual_chart_pressure_rejects_collapsed_finished_pack(self):
        folder,job=self.fixture('pixel-chart-pressure')
        probe=folder/'pressure.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,rigid_finish as rigid
bpy.ops.wm.read_factory_settings(use_empty=True)
points=[];faces=[]
for index in range(16384):
    x=(index%128)*.002;y=(index//128)*.002;start=len(points)
    points.extend([(x,y,0),(x+.001,y,0),(x,y+.001,0)]);faces.append((start,start+1,start+2))
mesh=bpy.data.meshes.new('independent-charts');mesh.from_pydata(points,[],faces);mesh.update()
low=bpy.data.objects.new('pressure_LOW',mesh);bpy.context.collection.objects.link(low)
low['semanticPart']='pressure';mesh.uv_layers.new(name='UVMap')
original_vertices=[tuple(v.co) for v in mesh.vertices]
results=[]
for pixels in [2,16]:
    atlas={'method':'smart-project-pixels','islandMarginPixels':pixels,'marginMethod':'FRACTION',
           'islandMarginFraction':pixels/4096,'textureSize':4096}
    before=[tuple(v.uv) for v in mesh.uv_layers.active.data]
    if pixels==2:
        report=rigid.pack_group([low],{'uvMargin':.015,'textureSize':4096},'pixels2',atlas)
        assert report['uvAtlas']['zeroAreaTriangles']==0
        assert report['uvAtlas']['summedUvTriangleArea']>.3
        results.append({'pixels':pixels,'accepted':True,'packing':report})
    else:
        try:rigid.pack_group([low],{'uvMargin':.015,'textureSize':4096},'pixels16',atlas)
        except ValueError as error:
            assert 'degenerate UV' in str(error) or 'outside unit' in str(error),str(error)
            results.append({'pixels':pixels,'accepted':False,'error':str(error)})
        else:raise AssertionError('Actual collapsed over-padded charts admitted')
        assert before==[tuple(v.uv) for v in mesh.uv_layers.active.data]
    assert original_vertices==[tuple(v.co) for v in mesh.vertices]
    assert faces==[tuple(p.vertices) for p in mesh.polygons]
Path(__file__).with_name('pressure-result.json').write_text(json.dumps(results,indent=2)+'\\n')
print('ACTUAL16K_CHART_PRESSURE2PX_VALID16PX_COLLAPSED_REJECTED_BEFORE_SCATTER_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'pixel-chart-pressure')


    def test_39_global_padding_preserves_all_occupied_pixels_and_black_at61px(self):
        folder=self.work/'global-padding-stress';folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('''import sys,json,hashlib
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid,finish
from common import activate
bpy.ops.wm.read_factory_settings(use_empty=True)
folder=Path(__file__).parent
scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2
vertices=[(-.4,-.4,-.4),(.4,-.4,-.4),(.4,.4,-.4),(-.4,.4,-.4),(-.4,-.4,.4),(.4,-.4,.4),(.4,.4,.4),(-.4,.4,.4)]
quads=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
faces=[t for a,b,c,d in quads for t in [(a,b,c),(a,c,d)]]
colors=[(.8,.02,.01),(0,0,0),(.02,.01,.85)]
pairs=[]
for i,color in enumerate(colors):
    mat=bpy.data.materials.new('SOURCE_'+str(i));mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Roughness'].default_value=.5
    pair=[]
    for role in ['HIGH','LOW']:
        mesh=bpy.data.meshes.new(role+str(i));mesh.from_pydata(vertices,[],faces);mesh.update()
        obj=bpy.data.objects.new(role+str(i),mesh);bpy.context.collection.objects.link(obj)
        obj.location=(3*i,0,0);mesh.materials.append(mat);obj['semanticPart']='part'+str(i);pair.append(obj)
    pairs.append(tuple(pair))
bpy.context.view_layer.update()
recipe={'textureSize':256,'uvMargin':61/256,'cageExtrusion':.05,'maxRayDistance':.1}
atlas=rigid.resolve_uv_atlas({'rigidParts':{'uvAtlas':{'method':'smart-project-pixels','islandMarginPixels':2}}},recipe)
def pixels(image):
    values=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(values)
    return values.reshape((-1,4))
native_padding=rigid.pad_atlas_image
unpadded=[];global_masks=[];reports=[]
def observed_padding(helper,image,covered,recipe,api):
    assert scene.render.bake.margin==0
    unpadded.append(pixels(image).copy());global_masks.append(covered.copy())
    value=native_padding(helper,image,covered,recipe,api)
    assert scene.render.bake.margin==0
    reports.append(value[1]);return value
rigid.pad_atlas_image=observed_padding
source_before={h.name:finish.mesh_identity(h) for h,l in pairs}
source_graphs={h.name:sorted((a.from_node.name,a.from_socket.name,a.to_node.name,a.to_socket.name) for a in h.data.materials[0].node_tree.links) for h,l in pairs}
material,maps,packing=rigid.bake_group(pairs,recipe,folder,'stress',finish,atlas)
assert len(unpadded)==5 and len(reports)==5
assert all(r['globalMarginPixels']==61 and r['perPartMarginPixels']==0 and r['sourceDestinationDistinct'] and r['sampler']=='Closest' for r in reports)
assert all(np.array_equal(mask,global_masks[0]) for mask in global_masks)
helper=bpy.data.objects[packing['target']]
assert helper.hide_get() and helper.hide_render and len(helper.data.materials)==0
white=bpy.data.materials.new('MASK_WHITE');white.use_nodes=True;white.node_tree.nodes.clear()
emit=white.node_tree.nodes.new('ShaderNodeEmission');emit.inputs['Color'].default_value=(1,1,1,1)
surface=white.node_tree.nodes.new('ShaderNodeOutputMaterial');white.node_tree.links.new(emit.outputs[0],surface.inputs['Surface'])
masks=[]
for i,(high,low) in enumerate(pairs):
    high_slots=list(high.data.materials);low_slots=list(low.data.materials)
    high.data.materials.clear();high.data.materials.append(white)
    target=bpy.data.materials.new('MASK_TARGET'+str(i));target.use_nodes=True
    low.data.materials.clear();low.data.materials.append(target)
    image=bpy.data.images.new('MASK'+str(i),width=256,height=256,alpha=False,float_buffer=True)
    image.colorspace_settings.name='Non-Color';image.generated_color=(0,0,0,1)
    texture=target.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image;target.node_tree.nodes.active=texture
    scene.render.bake.margin=0;scene.render.bake.use_clear=True
    activate(low);low.hide_set(False);low.hide_render=False;high.hide_set(False);high.hide_render=False;high.select_set(True)
    try:
        assert bpy.ops.object.bake(type='EMIT')=={'FINISHED'}
        values=pixels(image);assert np.isfinite(values).all()
        mask=values[:,0]>.5;assert np.count_nonzero(mask)>100;masks.append(mask)
        image.filepath_raw=str(folder/('mask'+str(i)+'.png'));image.file_format='PNG';image.save()
    finally:
        high.hide_render=low.hide_render=True;high.data.materials.clear();low.data.materials.clear()
        for mat in high_slots:high.data.materials.append(mat)
        for mat in low_slots:low.data.materials.append(mat)
assert not np.any(np.stack(masks).sum(axis=0)>1)
coverage=np.any(np.stack(masks),axis=0)
assert np.array_equal(coverage,global_masks[0])
measurements=[]
for index,(channel,entry) in enumerate(maps.items()):
    final=pixels(entry['image'])
    imported=bpy.data.images.load(str(entry['path']),check_existing=False)
    imported.colorspace_settings.name=entry['image'].colorspace_settings.name
    png=pixels(imported)
    assert np.isfinite(final).all() and np.isfinite(png).all()
    error=float(np.max(np.abs(final[coverage,:3]-unpadded[index][coverage,:3])))
    png_error=float(np.max(np.abs(png[coverage,:3]-unpadded[index][coverage,:3])))
    assert error<=1/255+2e-7 and png_error<=1/255+2e-7,(channel,error,png_error)
    if channel=='basecolor':
        decoded=np.where(png[:,:3]<=.04045,png[:,:3]/12.92,((png[:,:3]+.055)/1.055)**2.4)
        for mask,color in zip(masks,colors):assert np.max(np.abs(decoded[mask]-color))<.006
        assert np.max(decoded[masks[1]])==0,'True black source was overwritten'
    measurements.append({'channel':channel,'occupiedPixels':int(coverage.sum()),'maximumStoredPixelDifference':error,'maximumPngPixelDifference':png_error})
for high,low in pairs:
    assert finish.mesh_identity(high)==source_before[high.name]
    assert sorted((a.from_node.name,a.from_socket.name,a.to_node.name,a.to_socket.name) for a in high.data.materials[0].node_tree.links)==source_graphs[high.name]
assert not any(m.name.startswith('ATLAS_PADDING_') for m in bpy.data.materials)
assert not any(i.name.startswith('ATLAS_PADDING_') or i.name.endswith('_PADDED') for i in bpy.data.images)
(folder/'pixels.json').write_text(json.dumps({'status':'passed','packing':packing,'coveredPixels':int(coverage.sum()),'all5Maps':measurements,'trueBlackPreserved':True},indent=2)+'\\n')
print('GLOBAL61PX_PADDING_ALL5_MAPS_ALL_OCCUPIED_PIXELS_PNG_BLACK_SOURCE_STATE_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'global-padding-stress')

    def test_40_global_padding_native_failures_restore_scope(self):
        folder=self.work/'global-padding-status';folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid,finish
from unittest.mock import patch
class Proxy:
    def __init__(self,original,**changes):self.original=original;self.changes=changes
    def __getattr__(self,name):return self.changes.get(name,getattr(self.original,name))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add();helper=bpy.context.object
helper['semanticPart']='scope'
modifier=helper.modifiers.new('tri','TRIANGULATE');assert bpy.ops.object.modifier_apply(modifier=modifier.name)=={'FINISHED'}
recipe={'textureSize':32,'uvMargin':.1}
packing=rigid.pack_group([helper],recipe,'scope',{'islandMarginFraction':2/32})
helper=bpy.data.objects[packing['target']]
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
scene.render.threads_mode='FIXED';scene.render.threads=2
source=bpy.data.images.new('input',width=32,height=32,alpha=False);source.colorspace_settings.name='Non-Color'
source.generated_color=(.2,.3,.4,1)
def snapshot():
    return {'helper':rigid.inspection_identity(helper,finish),'materials':[m.as_pointer() for m in helper.data.materials],
            'indices':[p.material_index for p in helper.data.polygons],'visibility':(helper.hide_get(),helper.hide_viewport,helper.hide_render),
            'selection':[(o.name,o.select_get()) for o in scene.objects],'active':bpy.context.view_layer.objects.active.name,
            'bake':tuple(getattr(scene.render.bake,k) for k in ['margin','use_clear','use_selected_to_active']),
            'images':sorted(i.name for i in bpy.data.images),'allMaterials':sorted(m.name for m in bpy.data.materials)}
records=[]
for use_source in [False,True]:
    for label,returned in [('cancelled',{'CANCELLED'}),('empty',set()),('none',None),('mixed',{'FINISHED','CANCELLED'}),('throws','throw')]:
        before=snapshot()
        def failed(**kwargs):
            if returned=='throw':raise RuntimeError('controlled native exception')
            return returned
        proxy=Proxy(bpy,ops=Proxy(bpy.ops,object=Proxy(bpy.ops.object,bake=failed)))
        try:
            with patch.object(rigid,'bpy',proxy):rigid.atlas_self_bake(helper,recipe,finish,'controlled',3,source if use_source else None)
        except (ValueError,RuntimeError) as error:
            assert 'did not finish' in str(error) or 'controlled native exception' in str(error)
        else:raise AssertionError('Native failure admitted')
        assert snapshot()==before,(use_source,label,before,snapshot())
        records.append({'sourceImage':use_source,'case':label,'rejectedAndRestored':True})
Path(__file__).with_name('statuses.json').write_text(json.dumps(records,indent=2)+'\\n')
print('GLOBAL_PADDING10_NATIVE_FAILURE_SCOPES_RESTORED_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'global-padding-status')

    def test_41_global_padding_corrupt_coverage_and_occupied_pixels_rejected(self):
        folder=self.work/'global-padding-corruption';folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid,finish
from unittest.mock import patch
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add();low=bpy.context.object;low['semanticPart']='corrupt'
mod=low.modifiers.new('tri','TRIANGULATE');assert bpy.ops.object.modifier_apply(modifier=mod.name)=={'FINISHED'}
recipe={'textureSize':32,'uvMargin':.1}
packing=rigid.pack_group([low],recipe,'corrupt',{'islandMarginFraction':2/32})
helper=bpy.data.objects[packing['target']]
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
scene.render.threads_mode='FIXED';scene.render.threads=2
coverage,receipt=rigid.atlas_coverage(helper,recipe,finish)
native=rigid.atlas_self_bake
records=[]
for label,color in [('empty',(0,0,0,1)),('nonbinary',(.5,.5,.5,1)),('unequal',(1,0,1,1))]:
    before=sorted(i.name for i in bpy.data.images)
    def bad_mask(*args,**kwargs):
        image=native(*args,**kwargs);values=np.tile(np.asarray(color,np.float32),32*32);image.pixels.foreach_set(values);return image
    try:
        with patch.object(rigid,'atlas_self_bake',bad_mask):rigid.atlas_coverage(helper,recipe,finish)
    except ValueError as error:assert 'coverage' in str(error)
    else:raise AssertionError('Corrupt mask admitted')
    assert sorted(i.name for i in bpy.data.images)==before
    records.append({'case':'coverage-'+label,'rejectedAndCleaned':True})
for channel in ['basecolor','normal','ao','roughness','metallic']:
    source=bpy.data.images.new(channel,width=32,height=32,alpha=False)
    source.colorspace_settings.name='sRGB' if channel=='basecolor' else 'Non-Color';source.generated_color=(.2,.3,.4,1)
    before=rigid.atlas_pixels(source,32).copy();images=sorted(i.name for i in bpy.data.images)
    def bad_pixel(*args,**kwargs):
        image=native(*args,**kwargs);values=rigid.atlas_pixels(image,32)
        index=int(np.flatnonzero(coverage)[0]);values[index,0]=1
        image.pixels.foreach_set(values.reshape(-1));return image
    try:
        with patch.object(rigid,'atlas_self_bake',bad_pixel):rigid.pad_atlas_image(helper,source,coverage,recipe,finish)
    except ValueError as error:assert 'authoritative occupied pixel' in str(error)
    else:raise AssertionError('Corrupt occupied channel admitted')
    assert np.array_equal(before,rigid.atlas_pixels(source,32))
    assert sorted(i.name for i in bpy.data.images)==images
    records.append({'case':'occupied-'+channel,'rejectedAndCleaned':True})
Path(__file__).with_name('corruption.json').write_text(json.dumps(records,indent=2)+'\\n')
print('GLOBAL_PADDING3_CORRUPT_MASKS5_CORRUPT_CHANNELS_REJECTED_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'global-padding-corruption')


    def test_42_sparse_global_padding_retains_neutral_normal_background(self):
        folder=self.work/'global-padding-default';folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid,finish
bpy.ops.wm.read_factory_settings(use_empty=True)
mesh=bpy.data.meshes.new('sparse');mesh.from_pydata([(0,0,0),(1,0,0),(1,1,0),(0,1,0)],[],[(0,1,2),(0,2,3)]);mesh.update()
uv=mesh.uv_layers.new(name='UVMap')
for entry,value in zip(uv.data,[(.1,.1),(.3,.1),(.3,.3),(.1,.1),(.3,.3),(.1,.3)]):entry.uv=value
helper=bpy.data.objects.new('sparse-helper',mesh);bpy.context.collection.objects.link(helper)
helper.hide_render=True;helper.hide_set(True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
scene.render.threads_mode='FIXED';scene.render.threads=2
recipe={'textureSize':32,'uvMargin':1/32}
source=bpy.data.images.new('normal-source',width=32,height=32,alpha=False)
source.colorspace_settings.name='Non-Color';source.generated_color=(.5,.5,1,1)
before=rigid.atlas_pixels(source,32).copy()
covered,coverage=rigid.atlas_coverage(helper,recipe,finish)
destination,report=rigid.pad_atlas_image(helper,source,covered,recipe,finish)
after=rigid.atlas_pixels(destination,32)
far=31*32+31;assert not covered[far]
assert np.max(np.abs(after[covered,:3]-before[covered,:3]))<=1/255+2e-7
assert np.array_equal(after[far,:3],before[far,:3]),(after[far],before[far])
assert before[far,2]==1 and before[far,0]>.49 and before[far,1]>.49
Path(__file__).with_name('defaults.json').write_text(json.dumps({'occupiedPixels':int(covered.sum()),'farUnownedDefault':after[far,:3].tolist(),'allOccupiedPreserved':True,'globalMarginPixels':1},indent=2)+'\\n')
print('GLOBAL_SPARSE_NORMAL_DEFAULT_AND_OCCUPIED_PIXELS_PASS')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'global-padding-default')


    _STATIC_NORMAL_NUMERIC_FIXTURE = r'''
import bpy,numpy as np
from mathutils import Matrix,Euler,Vector
import rigid_finish as rigid,finish
from common import import_glb
def normal_identity(obj):
    return (tuple(tuple(item.value) for item in obj.data.attributes['custom_normal'].data),
            tuple(tuple(item.vector) for item in obj.data.corner_normals))
def owned_numeric_fixture():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root=bpy.data.objects.new('PROOF_TO_MODEL',None);bpy.context.collection.objects.link(root)
    pivot=bpy.data.objects.new('fixture-owned',None);bpy.context.collection.objects.link(pivot)
    pivot.parent=root;pivot.matrix_world=Matrix.Translation((.013,-.017,.029))
    mesh=bpy.data.meshes.new('IndependentlyAuthoredAsymmetricTetrahedron')
    mesh.from_pydata([(.01731,-.02317,.03191),(.02345,-.02126,.03413),
                     (.01849,-.01392,.03272),(.01989,-.02031,.03941)],[],
                    [(0,2,1),(0,1,3),(1,2,3),(2,0,3)])
    mesh.update()
    for face in mesh.polygons:face.use_smooth=True
    # Deliberately authored non-geometric corner directions. These independently
    # chosen numbers exercise native packed-normal and exporter quantization;
    # they are a preservation fixture, not a geometric-quality claim.
    authored=[]
    for face in mesh.polygons:
        for corner in range(3):
            authored.append(tuple((face.normal+Vector((.037*(corner+1),-.051,.023*(face.index+1)))).normalized()))
    mesh.normals_split_custom_set(authored)
    obj=bpy.data.objects.new('fixture-owned_LOD0',mesh);bpy.context.collection.objects.link(obj)
    obj['semanticPart']='fixture-owned';obj['lodLevel']=0
    obj.matrix_world=Matrix.Translation((.02,-.01,.04))@Euler((.11,.37,-.23)).to_matrix().to_4x4()@Matrix.Diagonal((1.1,.8,1.3,1.))
    material=bpy.data.materials.new('OwnedNumericMaterial');material.use_nodes=True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.12,.28,.41,1)
    mesh.materials.append(material);bpy.context.view_layer.update()
    original_normals=normal_identity(obj)
    before=rigid._preservation_runtime_state(obj,finish)
    rebase=rigid.rebase_low(obj,list(pivot.matrix_world.translation),pivot,finish)
    rigid._verify_runtime_preservation(before,obj,finish,'Numeric fixture pivot')
    assert obj.parent==pivot and rebase['maxPositionDriftMetres']<=1e-6 and rebase['maxCornerNormalDrift']<=2e-5
    assert normal_identity(obj)==original_normals
    before=rigid._preservation_runtime_state(obj,finish)
    recipe={'textureSize':64,'uvMargin':.02}
    atlas=rigid.resolve_uv_atlas({'rigidParts':{'uvAtlas':{'method':'smart-project-pixels','islandMarginPixels':2}}},recipe)
    packing=rigid.pack_group([obj],recipe,'owned-numeric',atlas)
    rigid._verify_runtime_preservation(before,obj,finish,'Numeric fixture UV scatter',exact_world=True)
    assert normal_identity(obj)==original_normals
    helper=bpy.data.objects[packing['target']];helper_mesh=helper.data
    bpy.data.objects.remove(helper,do_unlink=True)
    if helper_mesh.users==0:bpy.data.meshes.remove(helper_mesh)
    assert packing['exactLoopScatter'] and len(obj.data.uv_layers)==1
    bpy.ops.object.select_all(action='DESELECT')
    for item in [root,pivot,obj]:item.select_set(True)
    return obj,root,pivot,before,rebase,packing,original_normals
'''

    def test_43_static_normal_contract_preserves_numeric_working_data(self):
        folder=self.work/'static-normal-numeric';folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
folder=Path(__file__).parent
'''+self._STATIC_NORMAL_NUMERIC_FIXTURE+r'''
obj,root,pivot,before,rebase,packing,original_normals=owned_numeric_fixture()
expected=rigid.corner_snapshot(obj)
path=folder/'numeric.glb'
stored=rigid._snv_export_static_intent(path,[obj],finish,1_000_000)
rigid._verify_runtime_preservation(before,obj,finish,'Numeric fixture actual export',exact_world=True)
assert normal_identity(obj)==original_normals
assert stored['normalVerificationContract']=='opencaw-rigid-static-normals/v1'
assert stored['residualLimit']==2e-5 and stored['losslessClaim'] is False
assert stored['geometricNormalQualityMeasured'] is False and stored['runtimeQualityAccepted'] is False
assert stored['sourceContextUnchangedByExport'] and stored['workingRawDecodedWorldGuardsUnchanged']
assert sum(m['corners'] for m in stored['meshes'])==12
assert all(m['directionalLossCoverage']['allActualIndexedCornersMeasured'] for m in stored['meshes'])
assert all(m['maximumLocalCodecComponentResidual']<=2e-5 and m['maximumWorldCodecComponentResidual']<=2e-5 for m in stored['meshes'])
actual=import_glb(path)
assert len(actual)==1 and actual[0].parent.name=='fixture-owned'
anchors={item.name:item for item in bpy.context.scene.objects if item.type=='EMPTY'}
assert set(anchors)=={'PROOF_TO_MODEL','fixture-owned'} and anchors['fixture-owned'].parent.name=='PROOF_TO_MODEL'
assert np.max(np.abs(np.asarray(anchors['fixture-owned'].matrix_world.translation)-np.asarray((.013,-.017,.029))))<=1e-6
native=rigid._snv_verify_native_geometry_uv_materials(expected,actual[0])
strict_pass=True;strict_error=None
try:rigid.verify_corners(expected,actual[0])
except ValueError as error:
    strict_pass=False;strict_error=str(error)
    assert 'corner normals' in strict_error
assert native['oldStrictNormalPassed']==strict_pass
assert strict_pass is False,'Fixture stopped exercising DCC normal reencoding'
assert native['geometryUvMaterialsPassed'] and native['nativeNormalLosslessClaim'] is False
(folder/'evidence.json').write_text(json.dumps({'source':'independently authored asymmetric numeric tetrahedron',
    'workingRawDecodedWorldPreserved':True,'rebase':rebase,'packing':packing,'stored':stored,
    'independentNative':native,'oldStrictDccPassed':strict_pass,'oldStrictDccFailure':strict_error,
    'runtimeQualityAccepted':False,'finishInvoked':False},indent=2)+'\n')
print('NUMERIC_WORKING_PRESERVATION_STORED_CODEC_PASS_DCC_APPROXIMATION_QUALIFIED')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'static-normal-numeric')

    def test_44_static_normal_contract_rejects_tampering_and_failed_export(self):
        folder=self.work/'static-normal-negative';folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('''import sys,json,struct,copy
from pathlib import Path
from unittest.mock import patch
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
folder=Path(__file__).parent
'''+self._STATIC_NORMAL_NUMERIC_FIXTURE+r'''
obj,root,pivot,before,rebase,packing,original_normals=owned_numeric_fixture()
codec=rigid._snv_CODEC
context=rigid._snv_capture_source_context([obj],codec)
path=folder/'valid.glb'
rigid._snv_export_static_intent(path,[obj],finish,1_000_000)
parsed=rigid._snv_Glb(path,1_000_000);records=[]
def write_glb(target,document,binary):
    text=json.dumps(document,separators=(',',':')).encode();text+=b' '*((-len(text))%4)
    binary=bytes(binary);binary+=b'\0'*((-len(binary))%4)
    target.write_bytes(b'glTF'+struct.pack('<II',2,28+len(text)+len(binary))+
        struct.pack('<II',len(text),0x4e4f534a)+text+struct.pack('<II',len(binary),0x004e4942)+binary)
for label in ['corrupt-normal','missing-normal','stale-source']:
    document=copy.deepcopy(parsed.document);binary=bytearray(parsed.binary);expected=context
    attrs=document['meshes'][0]['primitives'][0]['attributes']
    if label=='corrupt-normal':
        accessor=document['accessors'][attrs['NORMAL']];view=document['bufferViews'][accessor['bufferView']]
        start=view.get('byteOffset',0)+accessor.get('byteOffset',0)
        struct.pack_into('<3f',binary,start,1.,0.,0.)
    elif label=='missing-normal':attrs.pop('NORMAL')
    else:
        expected=copy.deepcopy(context);expected['sources'][obj.name]['localNormals'][0,0,0]+=.001
    target=folder/(label+'.glb');write_glb(target,document,binary)
    try:rigid._snv_verify_stored_normal_intent(expected,target,codec,max_file_bytes=1_000_000)
    except ValueError as error:records.append({'case':label,'rejected':True,'error':str(error)})
    else:raise AssertionError('Bad stored normal/source accepted: '+label)
class Proxy:
    def __init__(self,original,**overrides):self.original=original;self.overrides=overrides
    def __getattr__(self,name):return self.overrides.get(name,getattr(self.original,name))
for label in ['cancelled','failed','interrupted']:
    target=folder/('export-'+label+'.glb')
    def defective(**kwargs):
        target.write_bytes(b'INCOMPLETE simulated operator output')
        if label=='interrupted':raise KeyboardInterrupt('synthetic cancellation')
        return {'CANCELLED'} if label=='cancelled' else None
    proxy=Proxy(bpy,ops=Proxy(bpy.ops,export_scene=Proxy(bpy.ops.export_scene,gltf=defective)))
    try:
        with patch.object(rigid,'bpy',proxy):rigid._snv_export_static_intent(target,[obj],finish,1_000_000)
    except (ValueError,KeyboardInterrupt) as error:
        assert not target.exists()
        rigid._verify_runtime_preservation(before,obj,finish,'Failed static export fixture',exact_world=True)
        assert normal_identity(obj)==original_normals
        records.append({'case':label,'injection':'synthetic operator output/status or cancellation',
                        'rejected':True,'freshOutputCleaned':True,'workingRawDecodedWorldExact':True,'error':str(error)})
    else:raise AssertionError('Failed static export admitted: '+label)
assert len(records)==6
(folder/'evidence.json').write_text(json.dumps({'cases':records,'finishInvoked':False,'runtimeQualityAccepted':False},indent=2)+'\n')
print('STORED_NORMAL_TAMPER_STALE_SOURCE_EXPORT_FAILURE_CANCELLATION_REJECTED')
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],'static-normal-negative')

    _PCA_COLLISION_FIXTURE = r'''
import bpy,numpy as np
from mathutils import Matrix,Euler,Vector
import rigid_finish as rigid,finish

def owned_box_pair(dimensions):
    # Independently authored closed boxes; SIMULATED engineering art/rights.
    # The shifted LOW makes containment cover both actual source point sets.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    root=bpy.data.objects.new('PCA_FIXTURE',None);bpy.context.collection.objects.link(root)
    pivot=bpy.data.objects.new('owned-box-pivot',None);bpy.context.collection.objects.link(pivot)
    pivot.parent=root;pivot.matrix_world=Matrix.Translation((.11,-.07,.06))
    rotation=Euler((.43,.71,-.37)).to_matrix().to_4x4()
    world=Matrix.Translation((.07,.04,.09))@rotation
    x,y,z=np.asarray(dimensions,np.float64)/2
    points=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),
            (-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
    faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    objects=[]
    for label,offset in [('HIGH',0.),('LOW',.0008)]:
        mesh=bpy.data.meshes.new('OwnedBox_'+label);mesh.from_pydata(points,[],faces);mesh.update()
        # Authored directions test raw/decoded preservation, not shading quality.
        normals=[tuple((face.normal+Vector((.013,.017,-.011))).normalized())
                 for face in mesh.polygons for unused in face.loop_indices]
        mesh.normals_split_custom_set(normals)
        obj=bpy.data.objects.new('OwnedBox_'+label,mesh);bpy.context.collection.objects.link(obj)
        if label=='LOW':obj.parent=pivot
        obj.matrix_world=world@Matrix.Translation((0,offset,0));objects.append(obj)
    bpy.context.view_layer.update()
    states=[rigid._preservation_runtime_state(obj,finish) for obj in objects]
    return objects,states,root,pivot,np.asarray(rotation,np.float64)[:3,:3]

def assert_sources_preserved(objects,states,label):
    for obj,before in zip(objects,states):
        rigid._verify_runtime_preservation(before,obj,finish,label,exact_world=True)

def write_evidence(payload):
    payload.update({'fixtureRightsAndArt':'SIMULATED independently authored engineering boxes; not human/model approval',
                    'blenderVersion':bpy.app.version_string,'actualOwlLoaded':False,
                    'finishInvoked':False,'runtimeQualityAccepted':False})
    (folder/'evidence.json').write_text(json.dumps(payload,indent=2,allow_nan=False)+'\n')
'''

    def _run_pca_probe(self,name,body):
        folder=self.work/name;folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('import sys,json\nfrom pathlib import Path\nsys.dont_write_bytecode=True\n'
                         'sys.path.insert(0,'+repr(str(SCRIPTS))+')\nfolder=Path(__file__).parent\n'
                         +self._PCA_COLLISION_FIXTURE+body,encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec',
                          '--python-exit-code','1','--python',probe],name)
        return json.loads((folder/'evidence.json').read_text())

    def test_45_principal_axes_thin_collider_real_glb_containment_and_preservation(self):
        evidence=self._run_pca_probe('pca-thin-roundtrip',r'''
objects,states,root,pivot,rotation=owned_box_pair((.3,.016,.006))
high,low=objects
settings={'frame':'principal-axes-v1','padding':.0005,'maxVolumeRatio':2}
collider,measured=finish.build_kdop26(high,low,settings,64)
assert_sources_preserved(objects,states,'PCA collider construction')
assert collider.parent==pivot and measured['orientationFrame']['frame']=='principal-axes-v1'
assert measured['closedManifold'] and measured['convex'] and measured['allSourceVerticesContained']
assert measured['coplanarFaceGroups']<=64 and 1<=measured['volumeRatio']<=2
basis=np.asarray(measured['orientationFrame']['basisColumnsWorld'])
assert np.max(np.abs(np.abs(basis.T@rotation)-np.eye(3)))<2e-6
assert measured['orientationFrame']['maximumOrthonormalResidual']<=1e-12
# The union of these equally oriented boxes is an independently known cuboid.
union_volume=.3*(.016+.0008)*.006
assert abs(measured['exactUnionHullVolume']-union_volume)<=union_volume*2e-5
collider.name='owned-box_COLLISION';collider['collision']=True;collider['semanticPart']='owned-box'
pivot['semanticPart']='owned-box';pivot['rigidAnchor']=True
source_points=np.concatenate([finish.world_vertices(obj) for obj in objects])
expected_world=np.asarray(collider.matrix_world,np.float64).copy()
bpy.ops.object.select_all(action='DESELECT')
for obj in [root,pivot,collider]:obj.select_set(True)
path=folder/'collider.glb'
stored=rigid._snv_export_static_intent(path,[collider],finish,1_000_000)
assert_sources_preserved(objects,states,'PCA collider GLB export')
before_import=set(bpy.data.objects)
assert bpy.ops.import_scene.gltf(filepath=str(path))=={'FINISHED'}
imported=[obj for obj in set(bpy.data.objects)-before_import if obj.type=='MESH']
assert len(imported)==1
actual=imported[0]
assert actual.get('collision') is True and actual.get('semanticPart')=='owned-box'
assert actual.parent.get('semanticPart')=='owned-box' and actual.parent.get('rigidAnchor') is True
assert np.max(np.abs(np.asarray(actual.matrix_world)-expected_world))<=1e-6
roundtrip=finish.collision_measure(actual,source_points)
assert roundtrip['closedManifold'] and roundtrip['consistentlyOriented'] and roundtrip['convex']
assert roundtrip['allSourceVerticesContained'] and roundtrip['coplanarFaceGroups']<=64
assert abs(roundtrip['volume']-measured['volume'])<=measured['volume']*1e-5
assert roundtrip['volume']/union_volume<=2
# Independent actual triangle-plane containment and signed tetrahedron volume.
vertices=finish.world_vertices(actual);centre=vertices.mean(axis=0)
actual.data.calc_loop_triangles();signed_volume=0.;maximum_outside=-float('inf')
for triangle in actual.data.loop_triangles:
    points=vertices[list(triangle.vertices)]
    normal=np.cross(points[1]-points[0],points[2]-points[0]);normal/=np.linalg.norm(normal)
    maximum_outside=max(maximum_outside,float(np.max((source_points-points[0])@normal)))
    a,b,c=points-centre;signed_volume+=float(a@np.cross(b,c))/6
assert maximum_outside<=0,maximum_outside
# Padding belongs to the selected support directions. Tiny triangulated bevel
# faces can amplify float32 plane-normal error, so do not relabel that error as
# a loss of the declared support padding.
directions=np.asarray(measured['directions'])
expected_limits=np.max(source_points@directions.T,axis=0)+settings['padding']
actual_limits=np.max(vertices@directions.T,axis=0)
support_residual=float(np.max(np.abs(actual_limits-expected_limits)))
assert support_residual<=1e-6,support_residual
assert signed_volume>0 and abs(signed_volume-roundtrip['volume'])<=roundtrip['volume']*1e-6
assert_sources_preserved(objects,states,'PCA collider native reimport')
write_evidence({'settings':settings,'construction':measured,'roundtrip':roundtrip,'stored':stored,
                'independentUnionVolume':union_volume,'independentTriangleVolume':signed_volume,
                'independentMaximumOutsideMetres':maximum_outside,'supportPaddingResidualMetres':support_residual,
                'sourceGeometryRawDecodedWorldExact':True})
print('PCA_THIN_COLLIDER_REAL_GLB_CONTAINMENT_VOLUME_SOURCE_PRESERVATION_PASS')
''')
        self.assertTrue(evidence['sourceGeometryRawDecodedWorldExact'])
        self.assertLessEqual(evidence['roundtrip']['volume']/evidence['independentUnionVolume'],2)

    def test_46_omitted_collision_frame_is_numerically_identical_to_explicit_world(self):
        evidence=self._run_pca_probe('pca-world-compatibility',r'''
objects,states,root,pivot,rotation=owned_box_pair((.14,.08,.04))
high,low=objects
settings={'padding':.0005,'maxVolumeRatio':20}
omitted,omitted_report=finish.build_kdop26(high,low,settings,64)
explicit,explicit_report=finish.build_kdop26(high,low,dict(settings,frame='world'),64)
assert omitted_report==explicit_report
assert omitted_report['orientationFrame']=={'frame':'world'}
assert finish.mesh_identity(omitted)==finish.mesh_identity(explicit)
assert np.array_equal(np.asarray(omitted.matrix_world),np.asarray(explicit.matrix_world))
assert np.array_equal(finish.world_vertices(omitted),finish.world_vertices(explicit))
assert omitted.parent==explicit.parent==pivot
assert_sources_preserved(objects,states,'Omitted and explicit world collision frame')
write_evidence({'omitted':omitted_report,'explicit':explicit_report,
                'geometryAndWorldCoordinatesBitExact':True,'sourceGeometryRawDecodedWorldExact':True})
print('OMITTED_AND_EXPLICIT_WORLD_COLLIDER_NUMERIC_COMPATIBILITY_PASS')
''')
        self.assertTrue(evidence['geometryAndWorldCoordinatesBitExact'])

    def test_47_principal_axes_invalid_inputs_stop_and_ties_are_canonical(self):
        evidence=self._run_pca_probe('pca-frame-boundaries',r'''
from unittest.mock import patch
objects,states,root,pivot,rotation=owned_box_pair((.12,.06,.02))
high,low=objects
settings={'padding':.0005,'maxVolumeRatio':2,'frame':'principal-axes-v1'}
records=[]
def rejection(label,operation,message,injection=None):
    before_objects=set(bpy.data.objects);before_meshes=set(bpy.data.meshes)
    try:operation()
    except ValueError as error:
        assert message in str(error),(label,str(error))
        assert set(bpy.data.objects)==before_objects and set(bpy.data.meshes)==before_meshes
        assert_sources_preserved(objects,states,'Rejected PCA frame '+label)
        records.append({'case':label,'rejected':True,'noFallbackOrNewGeometry':True,
                        'injection':injection,'error':str(error)})
    else:raise AssertionError('Invalid PCA frame admitted: '+label)
rejection('unknown-frame',lambda:finish.build_kdop26(high,low,dict(settings,frame='automatic'),64),'Unknown explicit')
valid={'schemaVersion':2,'method':'rigid-parts','topologyPreparation':{'method':'none'},'collision':dict(settings,method='kdop-26'),
       'rigidParts':{'handoff':'inputs/handoff.json','handoffSha256':'0'*64,
                     'reviewEvidence':'.opencaw/.cache/tasks/fixture/review.json','reviewEvidenceSha256':'0'*64,
                     'maxLod0Triangles':1000,'maxGlbBytes':1_000_000},'resources':{'maxPrivateBytes':1_073_741_824}}
assert rigid.validate_settings(valid)['collision']['frame']=='principal-axes-v1'
valid['collision']=dict(settings,method='kdop-26',frame='automatic')
rejection('unknown-settings-frame',lambda:rigid.validate_settings(valid),'Unknown explicit')
cube=np.asarray([(x,y,z) for x in (-1.,1.) for y in (-1.,1.) for z in (-1.,1.)])
bad_inputs={'rank-two':cube*np.asarray((1.,1.,0.)),
            'rank-one':np.asarray([(float(i),0.,0.) for i in range(4)]),
            'nearly-planar':cube*np.asarray((1.,1.,1e-8)),
            'nonfinite-nan':cube.copy(),'nonfinite-inf':cube.copy()}
bad_inputs['nonfinite-nan'][0,0]=np.nan;bad_inputs['nonfinite-inf'][0,0]=np.inf
for label,points in bad_inputs.items():
    message='finite N-by-3' if label.startswith('nonfinite') else 'degenerate or unsupported'
    # Only the coordinate provider is synthetic; actual PCA and builder run.
    def invalid_coordinates():
        with patch.object(finish,'world_vertices',return_value=points):
            finish.build_kdop26(high,low,settings,64)
    rejection(label,invalid_coordinates,message,
              'synthetic coordinate-provider output from independently authored points')
tied,tied_report=finish.principal_axes_frame(cube)
reordered,reordered_report=finish.principal_axes_frame(np.concatenate([cube[::-1],cube[[2,2,5]]]))
assert tied_report['eigenvalueClustersHalfOpen']==[[0,3]]
assert np.array_equal(tied,reordered) and np.max(np.abs(tied-np.eye(3)))<=1e-12
assert tied_report['uniquePointCount']==reordered_report['uniquePointCount']==8
assert abs(np.linalg.det(tied)-1)<=1e-12
# An unusable tied projector must stop rather than select world implicitly.
with patch.object(finish.np.linalg,'eigh',return_value=(np.ones(3),np.zeros((3,3)))):
    rejection('unresolvable-tied-eigenspace',lambda:finish.build_kdop26(high,low,settings,64),
              'tied eigenspace','synthetic eigensolver output; no valid tied basis supplied')
assert len(records)==8
write_evidence({'rejections':records,'canonicalTie':tied_report,
                'tieInvariantUnderReorderingAndDuplicatePoints':True,'sourceGeometryRawDecodedWorldExact':True})
print('PCA_INVALID_FRAME_RANK_NONFINITE_STOP_CANONICAL_TIES_NO_FALLBACK_PASS')
''')
        self.assertEqual(len(evidence['rejections']),8)
        self.assertTrue(evidence['tieInvariantUnderReorderingAndDuplicatePoints'])


    _CONSTRAINED_LOD_PRODUCER_FIXTURE = r'''
import copy, math
from unittest.mock import patch
import bpy, bmesh
import numpy as np
from mathutils.bvhtree import BVHTree
import finish, rigid_finish as rigid

records=[]
case_number=0

def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n')

def fixture(baked=False, contact=False, cavity=False):
    # Independently authored primitive art and SIMULATED technical admission.
    # Native finish.main and its actual selected fixed modules execute.
    global case_number
    case_number+=1
    root=folder/('c'+str(case_number));root.mkdir()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sources=[];parts=[];repairs=[]
    for identity,parent,position,compound in [('core',None,(0,0,.08),True),('marker','core',(.09,.01,.14),False)]:
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=.03)
        high=bpy.context.object
        if compound:
            vertices=[tuple(vertex.co) for vertex in high.data.vertices]
            faces=[tuple(face.vertices) for face in high.data.polygons]
            offset=len(vertices)
            vertices.extend([(.052,0,0),(.055,0,0),(.052,.003,0),(.052,0,.003)])
            faces.extend(tuple(offset+i for i in face) for face in [(0,2,1),(0,1,3),(1,2,3),(2,0,3)])
            if contact:
                vertices=[(0,0,0),(.025,0,0),(0,.025,0),(0,0,.025),
                          (0,0,0),(-.025,0,0),(0,-.025,0),(0,0,-.025)]
                shell=[(0,2,1),(0,1,3),(1,2,3),(2,0,3)]
                faces=shell+[(4+a,4+c,4+b) for a,b,c in shell]
            if cavity:
                vertices=[(0,0,0),(.025,0,0),(0,.025,0),(0,0,.025),
                          (.003,.003,.003),(.006,.003,.003),(.003,.006,.003),(.003,.003,.006)]
                shell=[(0,2,1),(0,1,3),(1,2,3),(2,0,3)]
                faces=shell+[(4+a,4+c,4+b) for a,b,c in shell]
            old=high.data;mesh=bpy.data.meshes.new('SIMULATED.closed-sphere-plus-tetra')
            mesh.from_pydata(vertices,[],faces);high.data=mesh;bpy.data.meshes.remove(old)
        high.name=identity+'_HIGH';high.location=position
        high.rotation_euler=(.13,-.09,.17);high.scale=(1.1,.9,1.05)
        material=bpy.data.materials.new('SIMULATED.Constant.'+identity);material.use_nodes=True
        shader=material.node_tree.nodes['Principled BSDF']
        shader.inputs['Base Color'].default_value=(.18,.26,.38,1)
        shader.inputs['Metallic'].default_value=.2;shader.inputs['Roughness'].default_value=.4
        high.data.materials.append(material)
        for face in high.data.polygons:face.use_smooth=True
        finish.activate(high);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
        assert bpy.ops.uv.smart_project(island_margin=.02,scale_to_bounds=True)=={'FINISHED'}
        bpy.ops.object.mode_set(mode='OBJECT')
        low=high.copy();low.data=high.data.copy();low.name=identity+'_LOW';bpy.context.collection.objects.link(low)
        sources.extend((high,low));count=finish.triangles(low)
        parts.append({'id':identity,'parentId':parent,'pivot':list(position),'highObject':high.name,'lowObject':low.name,
                      'maxTriangles':1000,'maxVertexSurfaceErrorMetres':.00001,
                      'materialMode':'bake' if baked else 'preserve','bakeGroup':'fixture_atlas' if baked else None,
                      'collision':True,'collisionReason':'SIMULATED closed structural primitive collider control'})
        if (contact or cavity) and compound:
            parts[-1]['collision']=False
            parts[-1]['collisionReason']='SIMULATED point-contact topology control; other part retains real collision coverage'
        repairs.append({'partId':identity,'sourceKind':'authored-detail','sourceDescription':'SIMULATED independent primitive fixture',
                        'highTriangles':count,'lowTriangles':count,'intentionalChanges':'Exact HIGH/LOW copies; no real model or human acceptance'})
    bpy.ops.object.select_all(action='DESELECT')
    for source in sources:source.select_set(True)
    assert bpy.ops.export_scene.gltf(filepath=str(root/'prepared.glb'),export_format='GLB',use_selection=True)=={'FINISHED'}
    shutil.copyfile(root/'prepared.glb',root/'raw.glb')
    (root/'source.txt').write_text('SIMULATED independent local primitive art/rights/review; no human acceptance.\n')
    authoring={'schemaVersion':1,'kind':'rigid-part-authoring','sourceRawSha256':sha(root/'raw.glb'),'preparedGlbSha256':sha(root/'prepared.glb'),
               'sources':[{'path':'source.txt','sha256':sha(root/'source.txt'),'role':'SIMULATED authored source'}],'repairs':repairs}
    topology_path='.opencaw/.cache/tasks/fixture/source-topology.json'
    if contact or cavity:
        import rigid_source_topology
        receipt=rigid_source_topology.capture(root/'prepared.glb',[obj for obj in sources if obj.name=='core_LOW'],
                                             rigid,max_file_bytes=10000000)
        write_json(root/topology_path,receipt)
        authoring['sources'].append({'path':topology_path,'sha256':sha(root/topology_path),'role':'SIMULATED reviewed native source topology'})
    write_json(root/'authoring.json',authoring)
    handoff={'schemaVersion':1,'profile':'articulated','coordinateFrame':'opencaw-proof-z-up','sourceRawSha256':sha(root/'raw.glb'),
             'preparedGlb':'prepared.glb','preparedGlbSha256':sha(root/'prepared.glb'),
             'sourceToPreparedMatrix':[[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]],
             'authoringEvidence':'authoring.json','authoringEvidenceSha256':sha(root/'authoring.json'),'parts':parts}
    write_json(root/'handoff.json',handoff)
    review_path='.opencaw/.cache/tasks/fixture/review.json'
    write_json(root/review_path,{'schemaVersion':1,'kind':'rigid-preparation','decision':'approved','human':False,
        'reviewer':'SIMULATED fixture technical admission','reason':'Independent numeric fixture; no human model acceptance',
        'sourceRawSha256':sha(root/'raw.glb'),'preparedGlbSha256':sha(root/'prepared.glb'),
        'handoffSha256':sha(root/'handoff.json'),'authoringEvidenceSha256':sha(root/'authoring.json')})
    recipe={'targetFaces':100,'textureSize':64,'cageExtrusion':.1,'maxRayDistance':.3,'uvMargin':.02,'lodRatios':[.5,.2],
            'colliderMaxFaces':64,'maxTriangles':400000,'maxMaterials':4,'maxTextureBytes':1000000,
            'parts':[],'riggingRequired':False,'animationRequired':False}
    settings={'schemaVersion':2,'method':'rigid-parts','topologyPreparation':{'method':'none'},
        'collision':{'method':'kdop-26','frame':'principal-axes-v1','padding':.0005,'maxVolumeRatio':2},
        'rigidParts':{'handoff':'handoff.json','handoffSha256':sha(root/'handoff.json'),'reviewEvidence':review_path,
                     'reviewEvidenceSha256':sha(root/review_path),'maxLod0Triangles':200000,'maxGlbBytes':10000000,
                     'lods':{'method':'original-component-finite-collapse-v1','maxVertexSurfaceErrorMetres':[.003,.01]}},
        'resources':{'maxPrivateBytes':1073741824}}
    if contact or cavity:
        settings['rigidParts']['sourceTopology']={'method':'reviewed-source-corners-v1','receipt':topology_path,
                                                 'receiptSha256':sha(root/topology_path)}
    job={'schemaVersion':1,'mode':'multi-view','root':str(root),'input':'raw.glb','inputFrame':'opencaw-proof-z-up',
         'outputDir':'out','result':'out/result.json','recipe':recipe,'finishingSettings':settings,
         'rigidHandoff':handoff,'taskEvidenceRoot':'.opencaw/.cache/tasks/fixture'}
    return root,job

def invoke(root,job):
    write_json(root/'job.json',job)
    protected=('raw.glb','prepared.glb','source.txt','authoring.json','handoff.json','.opencaw/.cache/tasks/fixture/review.json')
    before={name:sha(root/name) for name in protected}
    previous=sys.argv
    try:
        sys.argv=['blender','--','--job',str(root/'job.json')]
        finish.main()
    finally:
        sys.argv=previous
        assert all(sha(root/name)==value for name,value in before.items())

def independently_grouped_surface(obj):
    # Exact coordinate welding and graph traversal are authored here, separate
    # from runtime component inventory and surface_deviation implementation.
    mesh=obj.data;mesh.calc_loop_triangles()
    coordinates=[];index_by_coordinate={};remap=[]
    for vertex in mesh.vertices:
        key=tuple(vertex.co)
        if key not in index_by_coordinate:
            index_by_coordinate[key]=len(coordinates);coordinates.append(key)
        remap.append(index_by_coordinate[key])
    faces=[tuple(remap[i] for i in triangle.vertices) for triangle in mesh.loop_triangles]
    adjacent=[set() for unused in coordinates]
    for face in faces:
        for a,b in zip(face,face[1:]+face[:1]):adjacent[a].add(b);adjacent[b].add(a)
    remaining=set(range(len(coordinates)));groups=[]
    local=np.asarray(coordinates,np.float64);matrix=np.asarray(obj.matrix_world,np.float64)
    world=local@matrix[:3,:3].T+matrix[:3,3]
    while remaining:
        seed=min(remaining);stack=[seed];vertices=set()
        while stack:
            current=stack.pop()
            if current in vertices:continue
            vertices.add(current);stack.extend(adjacent[current]-vertices)
        remaining-=vertices
        triangles=[face for face in faces if face[0] in vertices]
        directed={}
        for face in triangles:
            for a,b in zip(face,face[1:]+face[:1]):directed[(a,b)]=directed.get((a,b),0)+1
        assert len(triangles)>=4
        assert all(count==1 and directed.get((b,a))==1 for (a,b),count in directed.items())
        origin=world[min(vertices)]
        volume=sum(float(np.dot(world[a]-origin,np.cross(world[b]-origin,world[c]-origin)))/6 for a,b,c in triangles)
        areas=[float(np.linalg.norm(np.cross(local[b]-local[a],local[c]-local[a])))/2 for a,b,c in triangles]
        assert volume>0 and min(areas)>1e-12
        coordinate_sha=hashlib.sha256(b''.join(sorted(np.asarray(local[i],np.float32).tobytes() for i in vertices))).hexdigest()
        groups.append({'vertices':sorted(vertices),'faces':triangles,'local':local,'world':world,'coordinateSha256':coordinate_sha,
                       'volume':volume,'triangles':len(triangles),'minimumLocalFaceArea':min(areas)})
    return groups

def independent_all_vertex_bound(reference,candidate):
    first=BVHTree.FromPolygons([tuple(v) for v in reference['world']],reference['faces'],all_triangles=True)
    second=BVHTree.FromPolygons([tuple(v) for v in candidate['world']],candidate['faces'],all_triangles=True)
    distances=[]
    for source,target in ((reference,second),(candidate,first)):
        distances.append(max(target.find_nearest(tuple(source['world'][index]))[3] for index in source['vertices']))
    return distances

def evidence(value):
    write_json(folder/'evidence.json',dict(value,nativeExecution=True,nativeFinisherFunctionsExercised=True,
        fixtureAdmissionAndTechnicalReview='SIMULATED',productionManifestUsed=False,
        productionFinishAttemptConsumed=False,actualOwlOrMasterLoaded=False,runtimeQualityAccepted=False))
'''

    def _run_constrained_lod_producer_probe(self,name,body):
        folder=self.work/name;folder.mkdir()
        probe=folder/'probe.py'
        probe.write_text('import sys,json,hashlib,shutil\nfrom pathlib import Path\n'
                         'sys.dont_write_bytecode=True\nsys.path.insert(0,'+repr(str(SCRIPTS))+')\n'
                         'folder=Path(__file__).parent\n'
                         'sha=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()\n'
                         +self._CONSTRAINED_LOD_PRODUCER_FIXTURE+body,encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],name)
        return json.loads((folder/'evidence.json').read_text())

    def test_48_selected_lod_public_producer_preserves_components_bounds_uv_normals_and_source(self):
        result=self._run_constrained_lod_producer_probe('lod48',r'''
observed=[]
original=rigid._clod_run_for_part
def observe(low,part,settings,api,output):
    before=rigid._preservation_runtime_state(low,api)
    references=independently_grouped_surface(low)
    lods,report,path=original(low,part,settings,api,output)
    rigid._verify_runtime_preservation(before,low,api,'Selected producer LOW0 raw/decoded/world/UV/normals',exact_world=True)
    by_sha={reference['coordinateSha256']:reference for reference in references}
    for lod,level in zip(lods,report['levels']):
        candidates=independently_grouped_surface(lod)
        assert len(candidates)==len(references)
        for component in level['components']:
            deviation=component['trials'][-1]['sameOriginalComponentEveryVertexDeviation']
            assert all(deviation[direction]['allVerticesMeasured']
                       and deviation[direction]['measuredMaximumPlusRepresentationErrorsMetres']<=level['maxVertexSurfaceErrorMetres']
                       for direction in ('sourceToCandidate','candidateToSource'))
        attribute=lod.data.attributes['constrained_lod_original_component']
        for declared in report['originalComponents']:
            expected=by_sha[declared['coordinateSha256']]
            # Match through exact component coordinate membership of the native
            # point-domain lineage, rather than nearest unrelated surfaces.
            owned_coordinates={tuple(vertex.co) for vertex,value in zip(lod.data.vertices,attribute.data) if value.value==declared['nativeId']}
            candidate=next(group for group in candidates
                           if {tuple(group['local'][i]) for i in group['vertices']}==owned_coordinates)
            measured=independent_all_vertex_bound(expected,candidate)
            assert max(measured)<=level['maxVertexSurfaceErrorMetres']
        normals=np.asarray([tuple(value.vector) for value in lod.data.corner_normals],np.float64)
        assert len(normals)==len(lod.data.loops) and np.isfinite(normals).all() and np.all(np.linalg.norm(normals,axis=1)>0)
        for layer in lod.data.uv_layers:
            uv=np.asarray([tuple(value.uv) for value in layer.data],np.float64)
            assert np.isfinite(uv).all() and np.all(uv>=0) and np.all(uv<=1)
        assert level['authoredDerivativeNormals']['sourceNormalRestorationClaimed'] is False
        if report['materialDependency']['policy']=='hard-zero-boundary-both-sides':
            assert all(check['positionsUvBothSidesMaterialAndMetadataBitExact'] for check in level['assembledBoundaryChecks'])
    if part['id']=='core':
        assert len(references)==2
        tiny=next(component for component in report['originalComponents'] if component['sourceTriangles']==4)
        assert all(next(component for component in level['components'] if component['sourceComponentId']==tiny['sourceComponentId'])['triangles']==4 for level in report['levels'])
    observed.append({'part':part['id'],'components':len(references),'sourceRawDecodedWorldUvNormalsExact':True,
                     'materialUvPolicy':report['materialDependency']['policy']})
    return lods,report,path
for baked in (False,True):
    root,job=fixture(baked=baked)
    with patch.object(rigid,'_clod_run_for_part',observe):invoke(root,job)
    result=json.loads((root/'out/result.json').read_text())
    assert result['stages'][-1]['pivotsAndHierarchy']
    assert result['measurements']['constrainedLodPackageBudget']['otherTriangles']>0
    assert bool(result['measurements']['atlases'])==baked
    assert all('constrainedLodNativeFaceAreaFloor' in check for check in result['stages'][-1]['checks']
               if '_LOD' in check['name'] and not check['name'].endswith('_LOD0'))
assert len(observed)==4
assert {part['materialUvPolicy'] for part in observed}=={'deterministic-unit-grid-triangles','hard-zero-boundary-both-sides'}
evidence({'parts':observed,'publicFinishMainInvoked':True,'actualOutputMeshes':len(result['stages'][-1]['checks']),
          'packageBudget':result['measurements']['constrainedLodPackageBudget']})
''')
        self.assertEqual([part['components'] for part in result['parts']],[2,1,2,1])
        self.assertTrue(result['publicFinishMainInvoked'])

    def test_49_selected_lod_unknown_material_operator_failure_cancel_and_owned_cleanup(self):
        result=self._run_constrained_lod_producer_probe('lod49',r'''
original_adapter=rigid._clod_run_for_part
original_apply=rigid._clod_apply_collapse
class Proxy:
    def __init__(self,original,**values):self.original,self.values=original,values
    def __getattr__(self,key):return self.values.get(key,getattr(self.original,key))
for label in ('mismatched-error-count','unknown-used-material','native-operator-cancelled','cancel-after-native-collapse'):
    root,job=fixture();witness=[];entered=[]
    if label=='mismatched-error-count':job['finishingSettings']['rigidParts']['lods']['maxVertexSurfaceErrorMetres']=[.003]
    def controlled(low,part,settings,api,output):
        entered.append(True)
        before=rigid._preservation_runtime_state(low,api)
        objects,meshes=set(bpy.data.objects),set(bpy.data.meshes)
        tree=low.data.materials[0].node_tree;noise=None
        def defective(*args):
            if label=='native-operator-cancelled':
                proxy=Proxy(bpy,ops=Proxy(bpy.ops,object=Proxy(bpy.ops.object,modifier_apply=lambda **kwargs:{'CANCELLED'})))
                with patch.object(rigid,'bpy',proxy):return original_apply(*args)
            value=original_apply(*args)
            witness.append('actual-native-collapse-completed')
            raise KeyboardInterrupt('Controlled LOD cancellation after native collapse')
        try:
            if label=='unknown-used-material':
                noise=tree.nodes.new('ShaderNodeTexNoise')
                return original_adapter(low,part,settings,api,output)
            with patch.object(rigid,'_clod_apply_collapse',defective):return original_adapter(low,part,settings,api,output)
        finally:
            if noise is not None:tree.nodes.remove(noise)
            assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
            rigid._verify_runtime_preservation(before,low,api,'Failed selected LOD LOW0 preservation',exact_world=True)
    try:
        with patch.object(rigid,'_clod_run_for_part',controlled):invoke(root,job)
    except (ValueError,KeyboardInterrupt) as error:
        expected={'mismatched-error-count':'match the authoritative','unknown-used-material':'unsupported','native-operator-cancelled':'no search fallback',
                  'cancel-after-native-collapse':'Controlled LOD cancellation'}[label]
        assert expected in str(error),str(error)
        assert not (root/'out/result.json').exists() and not (root/'out/asset.glb').exists()
        if label=='cancel-after-native-collapse':assert witness
        if label=='mismatched-error-count':assert not entered and not (root/'out/source.glb').exists()
        records.append({'case':label,'rejected':True,'ownedDerivativeObjectsAndMeshesCleaned':True if entered else None,
                        'helperInvoked':bool(entered),'earlyAdmissionNoDerivativeWork':not entered,
                        'sourceRawDecodedWorldUvNormalsExact':True,'error':str(error),
                        'fault':'Controlled native material/operator/cancellation injection; real producer path'})
    else:raise AssertionError('Invalid selected LOD producer admitted '+label)
evidence({'cases':records,'publicFinishMainInvoked':True})
''')
        self.assertEqual(len(result['cases']),4)
        self.assertTrue(all(case['ownedDerivativeObjectsAndMeshesCleaned'] for case in result['cases'] if case['helperInvoked']))

    def test_50_selected_lod_global_collider_budget_and_reimport_area_floor(self):
        result=self._run_constrained_lod_producer_probe('lod50',r'''
root,job=fixture()
job['finishingSettings']['rigidParts']['maxLod0Triangles']=164
job['recipe']['maxTriangles']=200
try:invoke(root,job)
except ValueError as error:
    assert 'Complete package exceeds unchanged' in str(error)
    assert error.report['lod0Triangles']==164 and error.report['otherTriangles']>0 and error.report['packageTriangles']>200
    assert not (root/'out/result.json').exists() and not (root/'out/asset.glb').exists()
    records.append({'case':'whole-package-budget-counts-colliders','rejectedBeforeExport':True,'counts':error.report})
else:raise AssertionError('Complete export budget waived')
root,job=fixture();original_import=rigid.import_glb;fault=[]
def subfloor_import(path):
    imported=original_import(path)
    if Path(path).name=='asset.glb':
        obj=next(obj for obj in imported if obj.get('lodLevel',0)==1 and not obj.get('collision'))
        del obj['lodLevel']
        for vertex in obj.data.vertices:vertex.co*=1e-5
        obj.data.update()
        measured=finish.topology_measure(obj,allow_degenerate=True)
        assert measured['degenerateFaces']>0;fault.append(obj.name)
    return imported
try:
    with patch.object(rigid,'import_glb',subfloor_import):invoke(root,job)
except ValueError as error:
    assert str(error)=='Retopology produced degenerate faces' and fault
    assert not (root/'out/result.json').exists()
    records.append({'case':'real-reimport-subfloor-missing-extra','rejected':True,'expectedDerivativeName':fault[0],
                    'unchangedLocalFaceAreaFloor':1e-12,'outputMetadataCannotSuppressGuard':True})
else:raise AssertionError('Reimport area floor waived')
root,job=fixture();original_apply=rigid._clod_apply_collapse
def subfloor_trial(candidate,ratio,boundary):
    status=original_apply(candidate,ratio,boundary)
    center=np.mean([tuple(vertex.co) for vertex in candidate.data.vertices],axis=0)
    for vertex in candidate.data.vertices:vertex.co=tuple(center+(np.asarray(vertex.co)-center)*1e-5)
    candidate.data.update()
    return status
with patch.object(rigid,'_clod_apply_collapse',subfloor_trial):invoke(root,job)
prepared=json.loads((root/'out/result.json').read_text())
components=[component for part in prepared['measurements']['parts'] for level in part['constrainedLods']['levels'] for component in level['components']]
assert all(component['terminalOriginalRetention'] for component in components)
assert any('1e-12 floor' in trial.get('reason','') for component in components for trial in component['trials'])
records.append({'case':'subfloor-native-trials-rejected-before-explicit-original-retention','prepared':True,
                'unchangedLocalFaceAreaFloor':1e-12,'terminalOriginalRetentionNeverWaivesAreaOrBudget':True})
evidence({'cases':records,'publicFinishMainInvoked':True,'scratchFailureNotAccepted':True})
''')
        self.assertEqual(len(result['cases']),3)
        self.assertTrue(result['cases'][1]['outputMetadataCannotSuppressGuard'])


    def test_51_selected_triangle_repair_exact_array_density_graph(self):
        folder=self.work/'exact_array_density_graph'
        folder.mkdir()
        probe=folder/'triangle_repair.py'
        probe.write_text('''import sys
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid,finish as api
bpy.ops.wm.read_factory_settings(use_empty=True)
def run_array_cases(rigid):
    import numpy as np
    policy={'method':'density-preserving-isolated-cells-v1','minCellPixels':4,'maxTriangles':2}
    source=np.array([[.1,.1],[.15,.1],[.1,.15]]*2+[[.3,.3]]*3,np.float32)
    before=source.tobytes();out,report=rigid.repair_triangle_uvs(source,64,2,policy)
    assert source.tobytes()==before and report['relocatedTriangles']==2
    assert report['graphBefore']['positiveEdges']==1 and report['graphAfter']['positiveEdges']==0
    assert report['exactStoredF32DensityPassCount']==1 and report['collapsedDensityExceptionCount']==1
    touched=set(report['relocatedFaceIndices']);assert len(touched)==2
    for face in set(range(3))-touched:assert source[face*3:face*3+3].tobytes()==out[face*3:face*3+3].tobytes()
    healthy=np.array([[-0.,.1],[.2,.1],[.1,.2],[.2,.1],[.2,.2],[.1,.2]],np.float32)
    same,r=rigid.repair_triangle_uvs(healthy,64,2,policy)
    assert same is healthy and r['relocatedTriangles']==0 and healthy.view(np.uint32)[0,0]==0x80000000
    def reject(data,config=policy,check=None,**options):
        bits=data.tobytes()
        try:rigid.repair_triangle_uvs(data,options.get('size',64),2,config,check)
        except (ValueError,RuntimeError):pass
        else:raise AssertionError('Expected strict UV authoring rejection')
        assert data.tobytes()==bits
    reject(source,dict(policy,maxTriangles=1))
    reject(source,dict(policy,other=1));reject(source,dict(policy,minCellPixels=True));reject(source,dict(policy,maxTriangles=16385))
    reject(source.astype(np.float64));reject(source,size=63)
    bad=source.copy();bad[0,0]=np.nan;reject(bad)
    reject(np.array([[0,0],[1,0],[0,1],[.1,.1],[.11,.1],[.1,.11]],np.float32))
    for stage in ('graph:pair-loop','before-chart:1','successful-final'):
        seen=[]
        def cancelled(value):
            seen.append(value)
            if value==stage:raise RuntimeError('Controlled cancellation')
        reject(source,check=cancelled);assert stage in seen
    return {'status':'PORTABLE_ARRAY_REGRESSION_PASS','sourceTriangles':3,'exactDensityAndCompleteOverlapGraph':True,
            'healthySignedZeroBitsPreserved':True,'strictNegativesAndCancellation':True}

result=run_array_cases(rigid)
assert result['status'].endswith('_PASS')
print(result)
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--threads','2','--python-exit-code','1','--python',probe],'exact_array_density_graph')

    def test_52_selected_triangle_repair_native_pack_scatter_raster(self):
        folder=self.work/'native_pack_scatter_raster'
        folder.mkdir()
        probe=folder/'triangle_repair.py'
        probe.write_text('''import sys
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
import bpy,numpy as np,rigid_finish as rigid,finish as api
bpy.ops.wm.read_factory_settings(use_empty=True)
def run_native_pack_cases(rigid,api):
    import bpy,numpy as np
    from types import SimpleNamespace
    mesh=bpy.data.meshes.new('independent_asymmetric_tetra_pair')
    vertices=[(0,0,0),(.13,0,0),(0,.19,0),(0,0,.23),(.4,.1,.2),(.57,.1,.2),(.4,.31,.2),(.4,.1,.49)]
    faces=[(0,2,1),(0,1,3),(1,2,3),(2,0,3),(4,6,5),(4,5,7),(5,6,7),(6,4,7)]
    mesh.from_pydata(vertices,[],faces);mesh.update();obj=bpy.data.objects.new('independent_uv_low',mesh)
    bpy.context.collection.objects.link(obj);obj['semanticPart']='independent-uv'
    layer=mesh.uv_layers.new(name='sourceUV');layer.data.foreach_set('uv',np.tile([.2,.3],len(mesh.loops)).astype(np.float32))
    obj.rotation_euler=(.1,.2,.3);obj.scale=(1,.8,1.2);bpy.context.view_layer.update()
    source_state=rigid._preservation_runtime_state(obj,api)
    def values():return rigid._preservation_field(obj.data.uv_layers.active.data,'uv',2,np.float32).tobytes()
    recipe={'textureSize':64,'uvMargin':.02}
    policy={'method':'density-preserving-isolated-cells-v1','minCellPixels':4,'maxTriangles':2}
    plain=rigid.resolve_uv_atlas({'rigidParts':{'uvAtlas':{'method':'smart-project-pixels','islandMarginPixels':2}}},recipe)
    selected=rigid.resolve_uv_atlas({'rigidParts':{'uvAtlas':{'method':'smart-project-pixels','islandMarginPixels':2,'triangleRepair':policy}}},recipe)
    original_bpy=rigid.bpy;original_smart=bpy.ops.uv.smart_project
    # The real native operator runs first. Only the resulting helper UVs are
    # deliberately replaced with this independently authored fault fixture.
    rows=[]
    for i in range(8):
        x=.35+(i%4)*.08;y=.4+(i//4)*.1
        rows.extend([(x,y),(x+.04,y),(x,y+.04)])
    fault=np.asarray(rows,np.float32);fault[3:6]=fault[:3];fault[6:9]=(.3,.3)
    def defective(**kwargs):
        status=original_smart(**kwargs)
        bpy.ops.object.mode_set(mode='OBJECT');bpy.context.object.data.uv_layers.active.data.foreach_set('uv',fault.reshape(-1));bpy.ops.object.mode_set(mode='EDIT')
        return status
    rigid.bpy=SimpleNamespace(data=bpy.data,context=bpy.context,ops=SimpleNamespace(object=bpy.ops.object,mesh=bpy.ops.mesh,uv=SimpleNamespace(smart_project=defective)))
    helpers=[]
    def reject(label,atlas):
        before=values();objects={o.as_pointer() for o in bpy.data.objects};meshes={m.as_pointer() for m in bpy.data.meshes}
        try:rigid.pack_group([obj],recipe,label,atlas)
        except (ValueError,RuntimeError):pass
        else:raise AssertionError('Expected native helper rejection '+label)
        assert values()==before and {o.as_pointer() for o in bpy.data.objects}==objects and {m.as_pointer() for m in bpy.data.meshes}==meshes
        rigid._verify_runtime_preservation(source_state,obj,api,label,exact_world=True)
    try:
        reject('no-selector-retains-original-zero-guard',plain)
        reject('cap-fails-cleanly',dict(selected,triangleRepair=dict(policy,maxTriangles=1)))
        original_verify=rigid._verify_runtime_preservation
        def fail_scatter(before,low,api,label,**kwargs):
            if label=='Explicit pixel UV scatter':raise RuntimeError('Controlled post-scatter failure')
            return original_verify(before,low,api,label,**kwargs)
        rigid._verify_runtime_preservation=fail_scatter
        try:reject('post-scatter-rollback',selected)
        finally:rigid._verify_runtime_preservation=original_verify
        packed=rigid.pack_group([obj],recipe,'portable-selected',selected);helpers.append(bpy.data.objects[packed['target']])
        repair=packed['uvAtlas']['triangleRepairResult'];assert repair['relocatedTriangles']==2 and repair['graphAfter']['positiveEdges']==0
        final=rigid._preservation_field(mesh.uv_layers.active.data,'uv',2,np.float32).reshape((-1,2))
        expected,r=rigid.repair_triangle_uvs(fault,64,2,policy);assert final.tobytes()==expected.tobytes()
        scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
        covered,coverage=rigid.atlas_coverage(helpers[-1],recipe,api);mask=covered.reshape((64,64));counts=[]
        for face in repair['relocatedFaceIndices']:
            p=final[face*3:face*3+3].astype(np.float64)*64;lower=np.floor(p.min(0)).astype(int);upper=np.ceil(p.max(0)).astype(int);inside=[]
            for y in range(lower[1],upper[1]):
                for x in range(lower[0],upper[0]):
                    q=np.asarray([x+.5,y+.5]);cross=[]
                    for a,b in zip(p,np.roll(p,-1,axis=0)):
                        v=b-a;w=q-a;cross.append(v[0]*w[1]-v[1]*w[0])
                    if min(cross)>0 or max(cross)<0:inside.append((x,y))
            assert inside and all(mask[y,x] for x,y in inside);counts.append(len(inside))
        rigid._verify_runtime_preservation(source_state,obj,api,'portable after native raster',exact_world=True)
        rigid.bpy=original_bpy
        legacy=rigid.pack_group([obj],recipe,'portable-healthy-legacy',plain);helpers.append(bpy.data.objects[legacy['target']]);bits=values()
        healthy=rigid.pack_group([obj],recipe,'portable-healthy-selected',selected);helpers.append(bpy.data.objects[healthy['target']])
        assert healthy['uvAtlas']['triangleRepairResult']['relocatedTriangles']==0 and values()==bits
        return {'status':'PORTABLE_NATIVE_PACK_REGRESSION_PASS','operatorFaultUvInjection':'explicit synthetic, after real SmartUV',
            'postScatterRollbackAndOwnedCleanup':True,'nativeWhiteEmitStrictInteriorTexels':counts,'healthyNativeUvBitsExact':True,
            'sourceGeometryAndRuntimeNormalsUnchanged':True,'actualAuthoredModelOrFullFinish':False}
    finally:
        rigid.bpy=original_bpy
        for helper in helpers:
            data=helper.data;bpy.data.objects.remove(helper,do_unlink=True)
            if data.users==0:bpy.data.meshes.remove(data)
        bpy.data.objects.remove(obj,do_unlink=True)
        if mesh.users==0:bpy.data.meshes.remove(mesh)

result=run_native_pack_cases(rigid,api)
assert result['status'].endswith('_PASS')
print(result)
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--threads','2','--python-exit-code','1','--python',probe],'native_pack_scatter_raster')


    def test_53_locked_lod_retention_skips_only_proven_impossible_native_trials(self):
        folder=self.work/'locked_lod_retention'
        folder.mkdir()
        probe=folder/'locked_lod.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
sys.path.insert(0,'''+repr(str(ROOT/'tests'))+''')
import bpy,rigid_finish as rigid,finish as api
from proof_model_locked_lod_controls import run_selected_regressions
bpy.ops.wm.read_factory_settings(use_empty=True)
folder=Path(__file__).parent
result=run_selected_regressions(rigid,api,folder)
(folder/'result.json').write_text(json.dumps(result,indent=2,allow_nan=False),encoding='utf-8')
print(result['status'])
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--threads','2','--python-exit-code','1','--python',probe],
                         'locked_lod_retention')
        result=json.loads((folder/'result.json').read_text(encoding='utf-8'))
        self.assertEqual(result['status'],'PORTABLE_LOCKED_LOD_RETENTION_CONTROLS_PASS')
        self.assertEqual([case['case'] for case in result['cases']],
                         ['locked-octa','duplicated-uv-cut-cube','partly-unlocked-textured-sphere'])
        self.assertEqual(result['legacyControlDerivation']['removedExactStatements'],3)
        self.assertTrue(result['checkpointCancellationAndCleanup'])
        self.assertTrue(result['terminalNativeTopologyGuardNotBypassed'])


    def test_54_packed_normal_probes_refresh_native_cache_and_verify_codes(self):
        folder=self.work/'normal_code_cache'
        folder.mkdir()
        probe=folder/'normal_codes.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
folder=Path(__file__).parent
'''+self._STATIC_NORMAL_NUMERIC_FIXTURE+'''
obj,root,pivot,before,rebase,packing,original_normals=owned_numeric_fixture()
source_guard=rigid._nfa_guard(obj)
workspace=obj.copy();workspace.data=obj.data.copy()
source_codes=rigid._nfa_codes(workspace.data)
baseline=rigid._nfa_normal(workspace.data)
zero=np.zeros_like(source_codes)
assert np.any(source_codes!=zero)
def protected():
    value=rigid._nfa_guard(workspace)
    value.pop('decoded');value['attrs'].pop('custom_normal')
    return value
guard=protected();objects=len(bpy.data.objects);meshes=len(bpy.data.meshes)
try:
    # Reproduce the old production sequence on this real native synthetic mesh.
    workspace.data.attributes['custom_normal'].data.foreach_set('value',zero.ravel())
    old_copy=workspace.data.copy()
    try:
        assert np.array_equal(rigid._nfa_codes(workspace.data),zero)
        assert np.array_equal(rigid._nfa_codes(old_copy),zero)
        stale=rigid._nfa_normal(old_copy)
        assert np.array_equal(stale.view(np.uint32),baseline.view(np.uint32))
    finally:bpy.data.meshes.remove(old_copy)
    refreshed=rigid._nfa_probe_codes(workspace.data,zero)
    assert refreshed is not None and np.isfinite(refreshed).all()
    assert not np.array_equal(refreshed.view(np.uint32),stale.view(np.uint32))
    # Independent automatic-normal reference: remove the packed attribute.
    automatic=obj.data.copy()
    try:
        automatic.attributes.remove(automatic.attributes['custom_normal']);automatic.update()
        expected=rigid._nfa_normal(automatic)
        auto_error=float(np.max(np.abs(refreshed.astype(float)-expected.astype(float))))
        assert auto_error<=2e-6
    finally:bpy.data.meshes.remove(automatic)
    banks=[]
    for label,codes in [('original',source_codes.copy()),('zero',zero),
                        ('alternate',np.tile(np.asarray([12000,-9000],np.int16),(len(zero),1)))]:
        requested=codes.copy();decoded=rigid._nfa_probe_codes(workspace.data,codes)
        assert decoded is not None and np.isfinite(decoded).all()
        assert np.array_equal(codes,requested) and np.array_equal(rigid._nfa_codes(workspace.data),codes)
        assert len(bpy.data.meshes)==meshes and len(bpy.data.objects)==objects
        assert protected()==guard and rigid._nfa_guard(obj)==source_guard
        banks.append({'bank':label,'requestedAndWorkspaceCodesSha256':rigid._nfa_digest(codes),
                      'decodedSha256':rigid._nfa_digest(decoded)})
    assert len({row['decodedSha256'] for row in banks})==3
    original_reader=rigid._nfa_codes
    readback_faults=[]
    for fault in ['workspace','fresh-copy']:
        def faulty_reader(mesh):
            value=original_reader(mesh)
            if fault=='workspace' or mesh.as_pointer()!=workspace.data.as_pointer():value[0,0]^=np.int16(1)
            return value
        rigid._nfa_codes=faulty_reader
        try:
            try:rigid._nfa_probe_codes(workspace.data,source_codes)
            except rigid._nfa_AdapterError as error:assert 'readback differs' in str(error)
            else:raise AssertionError('Faulty native raw-code readback accepted: '+fault)
        finally:rigid._nfa_codes=original_reader
        assert len(bpy.data.meshes)==meshes and len(bpy.data.objects)==objects
        readback_faults.append(fault)
    # These are injected readback/decode failures, not defective Blender results.
    original_normal=rigid._nfa_normal
    def invalid_decode(mesh):raise rigid._nfa_AdapterError('SIMULATED invalid native decode')
    rigid._nfa_normal=invalid_decode
    try:assert rigid._nfa_probe_codes(workspace.data,source_codes) is None
    finally:rigid._nfa_normal=original_normal
    assert len(bpy.data.meshes)==meshes
    invalid_codes=[source_codes.astype(np.int32),source_codes[:,0],source_codes[:,::-1]]
    for value in invalid_codes:
        unchanged=rigid._nfa_codes(workspace.data)
        try:rigid._nfa_probe_codes(workspace.data,value)
        except rigid._nfa_AdapterError:pass
        else:raise AssertionError('Unbounded/malformed packed-code probe accepted')
        assert np.array_equal(rigid._nfa_codes(workspace.data),unchanged) and len(bpy.data.meshes)==meshes
    prior_limit=rigid._nfa_LIMIT
    rigid._nfa_LIMIT=source_codes.nbytes-1
    try:
        try:rigid._nfa_probe_codes(workspace.data,source_codes)
        except rigid._nfa_AdapterError:pass
        else:raise AssertionError('Packed-code probe exceeded declared field budget')
    finally:rigid._nfa_LIMIT=prior_limit
    assert protected()==guard and rigid._nfa_guard(obj)==source_guard
    assert len(bpy.data.meshes)==meshes and len(bpy.data.objects)==objects
    result={'status':'ACTUAL_NATIVE_SYNTHETIC_NORMAL_CACHE_REGRESSION_PASS','blenderVersion':bpy.app.version_string,
            'syntheticMesh':True,'actualOwlOrProductionFinish':False,'stalePathRawCodesChangedButDecodedBitsUnchanged':True,
            'correctedZeroDecodeDiffersFromStale':True,'independentAutomaticNormalMaximumError':auto_error,'banks':banks,
            'injectedReadbackFaultsRejected':readback_faults,'invalidDecodeStillReturnsNoCandidate':True,
            'invalidArrayShapeTypeStrideAndFieldBudgetRejected':True,'sourceAndProtectedWorkspaceFieldsUnchanged':True,
            'scratchCleanupOnSuccessAndFailure':True,'productionNormalLimitsChanged':False}
finally:rigid._nfa_dispose(workspace)
assert len(bpy.data.meshes)==meshes-1 and len(bpy.data.objects)==objects-1
(folder/'result.json').write_text(json.dumps(result,indent=2,allow_nan=False),encoding='utf-8')
print(result['status'])
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],
                         'normal-code-cache')
        result=json.loads((folder/'result.json').read_text(encoding='utf-8'))
        self.assertEqual(result['status'],'ACTUAL_NATIVE_SYNTHETIC_NORMAL_CACHE_REGRESSION_PASS')
        self.assertEqual([row['bank'] for row in result['banks']],['original','zero','alternate'])
        self.assertTrue(result['sourceAndProtectedWorkspaceFieldsUnchanged'])
        self.assertTrue(result['scratchCleanupOnSuccessAndFailure'])


    def test_55_reviewed_source_topology_native_roundtrip_and_rejections(self):
        folder=self.work/'source_topology';folder.mkdir()
        probe=folder/'source_topology.py'
        probe.write_text('''import sys,json
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'''+repr(str(SCRIPTS))+''')
sys.path.insert(0,'''+repr(str(ROOT/'tests'))+''')
import bpy,rigid_finish as rigid,finish as api,rigid_source_topology as topology
from proof_model_source_topology_controls import run_regressions
bpy.ops.wm.read_factory_settings(use_empty=True)
folder=Path(__file__).parent
result=run_regressions(topology,rigid,api,folder)
(folder/'result.json').write_text(json.dumps(result,indent=2,allow_nan=False),encoding='utf-8')
print(result['status'])
''',encoding='utf-8')
        self.run_process([BLENDER,'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',probe],
                         'source-topology-native')
        result=json.loads((folder/'result.json').read_text(encoding='utf-8'))
        self.assertEqual(result['status'],'NATIVE_SOURCE_TOPOLOGY_CONTROLS_PASS')
        self.assertTrue(result['nativeExportImport'] and result['sourceAndInventoryGuardsExact'])
        self.assertGreaterEqual(len(result['cases']),15)


    def test_56_reviewed_contact_topology_runs_actual_bake_lods_and_independent_export(self):
        result=self._run_constrained_lod_producer_probe('source_topology_producer',r'''
root,job=fixture(baked=True,contact=True)
invoke(root,job)
result=json.loads((root/'out/result.json').read_text())
core=next(part for part in result['measurements']['parts'] if part['part']=='core')
assert core['topology']['reviewedSourceCornerTopology']['sourceVertexCount']==8
assert len(core['constrainedLods']['originalComponents'])==2
assert [level['triangles'] for level in core['constrainedLods']['levels']]==[8,8]
assert core['constrainedLods']['sourceLow0Immutable']
checks=next(stage for stage in result['stages'] if stage['stage']=='independentReimport')['checks']
owned=[row for row in checks if 'reviewedSourceTopology' in row]
assert {row['name'] for row in owned}=={'core_LOD0','core_LOD1','core_LOD2'}
assert all(row['reviewedSourceTopology']['nonManifoldEdges']==0 for row in owned)
receipt=root/result['artifacts']['sourceTopologyReceipt']
assert sha(receipt)==result['outputHashes'][result['artifacts']['sourceTopologyReceipt']]
assert result['measurements']['atlases'] and result['humanApproval']=='pending'
evidence({'status':'ACTUAL_REVIEWED_CONTACT_TOPOLOGY_PRODUCER_PASS','originalNativeOwners':8,
          'closedSourceComponents':2,'independentReimportOwnedMeshes':sorted(row['name'] for row in owned),
          'actualUvBakeLodsCollisionAndExport':True,'humanAcceptanceGranted':False,'receiptSha256':sha(receipt)})
''')
        self.assertEqual(result['status'],'ACTUAL_REVIEWED_CONTACT_TOPOLOGY_PRODUCER_PASS')
        self.assertFalse(result['humanAcceptanceGranted'])


    def test_57_reviewed_cavity_keeps_negative_boundary_and_legacy_still_rejects_it(self):
        result=self._run_constrained_lod_producer_probe('source_topology_cavity',r'''
root,job=fixture(baked=True,cavity=True)
invoke(root,job)
result=json.loads((root/'out/result.json').read_text())
core=next(part for part in result['measurements']['parts'] if part['part']=='core')
inventory=core['constrainedLods']['originalComponents']
assert sorted(row['topology']['worldSignedOrientation'] for row in inventory)==[-1,1]
negative=next(row for row in inventory if row['topology']['worldSignedOrientation']==-1)
for level in core['constrainedLods']['levels']:
    component=next(row for row in level['components'] if row['sourceComponentId']==negative['sourceComponentId'])
    assert component['terminalOriginalRetention'] and component['selectedGridRatio']==1
    assert component['trials'][-1]['topology']['worldSignedOrientation']==-1
    assert all(row['status']=='rejected' for row in component['trials'][:-1])
low=bpy.data.objects['core_LOD0']
before=rigid._preservation_runtime_state(low,finish)
objects=set(bpy.data.objects);meshes=set(bpy.data.meshes)
legacy=rigid.resolve_lod_settings(job['finishingSettings'],job['recipe'])
control=low.copy();control.data=low.data.copy();bpy.context.collection.objects.link(control)
material=bpy.data.materials.new('SIMULATED.LegacyCavity.Constant');material.use_nodes=True
control.data.materials.clear();control.data.materials.append(material)
for face in control.data.polygons:face.material_index=0
control.data.update();bpy.context.view_layer.update()
try:
    try:rigid._clod_build_constrained_lods(control,legacy,finish,name_prefix='LegacyCavity')
    except rigid._clod_ConstrainedLodError as error:assert 'signed world boundary orientation' in str(error)
    else:raise AssertionError('Unselected legacy positive-component policy accepted a negative cavity')
finally:
    data=control.data;bpy.data.objects.remove(control,do_unlink=True);bpy.data.meshes.remove(data)
    bpy.data.materials.remove(material)
assert set(bpy.data.objects)==objects and set(bpy.data.meshes)==meshes
rigid._verify_runtime_preservation(before,low,finish,'legacy negative rejection',exact_world=True)
evidence({'status':'ACTUAL_REVIEWED_CAVITY_LOD_PRESERVATION_PASS','boundarySigns':[-1,1],
          'negativeBoundaryRetainedExactlyAtEveryLevel':True,'legacyPositivePolicyStillRejectsNegative':True,
          'actualUvBakeExportAndIndependentReimport':True,'humanAcceptanceGranted':False})
''')
        self.assertEqual(result['status'],'ACTUAL_REVIEWED_CAVITY_LOD_PRESERVATION_PASS')
        self.assertTrue(result['negativeBoundaryRetainedExactlyAtEveryLevel'])


    def test_58_protected_contact_rings_reduce_and_reject_adversarial_native_outputs(self):
        result=self._run_constrained_lod_producer_probe('contact_ring_controls',r'''
sys.path.insert(0,str(Path('''+repr(str(ROOT/'tests'))+r''')))
import rigid_source_topology as topology
from proof_model_contact_lod_controls import replace_fixture_core,run_regressions
def factory(*,scale=1,edge_contact=False,textured=True,all_held=False):
    root,job=fixture(baked=True,cavity=True)
    job,bindings=replace_fixture_core(root,job,rigid,finish,topology,scale=scale,edge_contact=edge_contact,
                                    textured=textured,all_held=all_held,import_prepared=True)
    return root,job,bindings
observed=run_regressions(rigid,finish,topology,folder,factory)
evidence(observed)
''')
        self.assertEqual(result['status'],'NATIVE_PROTECTED_CONTACT_RING_CONTROLS_PASS')
        self.assertTrue(result['sourceAndOwnedCleanupExact'])
        self.assertTrue(result['actualReductionAwayFromProtectedContactTriangles'])
        self.assertTrue(result['negativeCavityExact'])
        self.assertGreaterEqual(len(result['cases']),19)
        self.assertEqual(len(result['exactRationalControls']),18)


    def test_59_protected_contact_rings_run_real_uv_bake_export_and_reimport(self):
        result=self._run_constrained_lod_producer_probe('contact_ring_producer',r'''
sys.path.insert(0,str(Path('''+repr(str(ROOT/'tests'))+r''')))
import rigid_source_topology as topology
from proof_model_contact_lod_controls import replace_fixture_core,contact_snapshot,verify_contact_snapshot
root,job=fixture(baked=True,cavity=True)
job,unused_bindings=replace_fixture_core(root,job,rigid,finish,topology,smooth=True)
observations=[]
frame_faults=[]
original_builder=rigid._clod_build_constrained_lods
original_reimport=topology.verify_contact_lod_reimport
def observe(low,settings,api,**kwargs):
    binding=kwargs.get('source_topology')
    assert binding is not None and settings['contactPolicy']=='protected-contact-rings-v1'
    reference=binding.reindex_copy(low,rigid,preserve_loops=True)
    report_path=folder/(low.name+'-actual-builder-report.json')
    report={}
    try:
        snapshot=contact_snapshot(reference) if low.name.startswith('core') else None
        output,report=original_builder(low,settings,api,**kwargs)
        # Keep the actual complete report even if a subsequent test assertion
        # fails; the production wrapper cannot attach this assertion's report.
        with report_path.open('x',encoding='utf-8')as stream:
            json.dump(report,stream,indent=2,allow_nan=False);stream.write('\n')
        if snapshot is not None:
            measured=[verify_contact_snapshot(snapshot,lod,api,level['maxVertexSurfaceErrorMetres'])
                      for lod,level in zip(output,settings['levels'])]
            assert any(row['triangles']<562 for row in measured)
            observations.append({'part':'core','protectedBeforeActualExport':measured,
                'actualBuilderReportSha256':sha(report_path),'sourceHardUvEdges':sum(snapshot['hardUvEdges'].values()),
                'sourceHadActualBakedAtlasUvs':bool(low.data.uv_layers),
                'sourceTopologyActualPreparedReceiptBound':True})
        return output,report
    except BaseException as error:
        if not report_path.exists():
            with report_path.open('x',encoding='utf-8')as stream:
                json.dump(getattr(error,'report',report),stream,indent=2,allow_nan=False);stream.write('\n')
        with (folder/(low.name+'-observer-error.json')).open('x',encoding='utf-8')as stream:
            json.dump({'error':str(error),'type':type(error).__name__,'actualBuilderReport':report_path.name,
                       'helperReportAvailable':bool(getattr(error,'report',report))},stream,indent=2,allow_nan=False)
        raise
    finally:
        data=reference.data;bpy.data.objects.remove(reference,do_unlink=True)
        if data.users==0:bpy.data.meshes.remove(data)
def verify_reimport_with_frame_faults(obj,context,low0,low_binding,lod_binding,api):
    from proof_model_contact_lod_controls import _snapshot
    actual=original_reimport(obj,context,low0,low_binding,lod_binding,api)
    # Actual imported objects; explicitly simulated post-import channel tamper.
    for label,target in (('LOW0-only',low0),('LOD-only',obj)):
        before=_snapshot(target);old=float(target.location.x)
        try:
            target.location.x=old+.001;bpy.context.view_layer.update()
            try:original_reimport(obj,context,low0,low_binding,lod_binding,api)
            except ValueError as error:
                assert 'frame'in str(error).lower(),str(error)
                frame_faults.append({'name':obj.name,'tampered':label,'execution':'ACTUAL_REIMPORT_THEN_SIMULATED_CHANNEL_TAMPER',
                                     'rejectedByRealFrameGuard':str(error)})
            else:raise AssertionError('Contact LOD frame divergence accepted '+label)
        finally:
            target.location.x=old;bpy.context.view_layer.update()
            assert _snapshot(target)==before,'Frame fault fixture failed exact restoration'
    return actual

with patch.object(rigid,'_clod_build_constrained_lods',observe),patch.object(topology,'verify_contact_lod_reimport',verify_reimport_with_frame_faults):
    invoke(root,job)
actual=json.loads((root/'out/result.json').read_text())
core=next(row for row in actual['measurements']['parts']if row['part']=='core')
assert observations and actual['measurements']['atlases']
assert core['constrainedLods']['sourceLow0Immutable']
assert any(row['triangles']<562 for row in core['constrainedLods']['levels'])
checks=next(row for row in actual['stages']if row['stage']=='independentReimport')['checks']
owned=[row for row in checks if 'reviewedSourceTopology'in row]
assert {'core_LOD0','core_LOD1','core_LOD2'}<={row['name']for row in owned}
assert all(row['reviewedSourceTopology']['nonManifoldEdges']==0 for row in owned)
assert all('constrainedLodNativeFaceAreaFloor'in row for row in checks
           if '_LOD'in row['name'] and not row['name'].endswith('_LOD0'))
receipt=root/actual['artifacts']['sourceTopologyReceipt']
assert sha(receipt)==actual['outputHashes'][actual['artifacts']['sourceTopologyReceipt']]
budget=actual['measurements']['constrainedLodPackageBudget']
assert budget['otherTriangles']>0 and budget['packageTriangles']<=job['recipe']['maxTriangles']
assert actual['humanApproval']=='pending'
assert frame_faults and {row['tampered']for row in frame_faults}=={'LOW0-only','LOD-only'}
evidence({'status':'ACTUAL_CONTACT_RING_UV_BAKE_EXPORT_REIMPORT_PASS','observations':observations,
          'actualRealBakeAndGlbAndIndependentReimport':True,'negativeCavityExactBeforeExport':True,
          'outputSourceTopologyReceiptSha256':sha(receipt),'packageBudget':budget,
          'injectedActualReimportFrameFaults':frame_faults,
          'transportUvUsesExistingGuardNotClaimedBitExactAfterGltfFlip':True,'humanAcceptanceGranted':False})
''')
        self.assertEqual(result['status'],'ACTUAL_CONTACT_RING_UV_BAKE_EXPORT_REIMPORT_PASS')
        self.assertTrue(result['actualRealBakeAndGlbAndIndependentReimport'])
        self.assertFalse(result['humanAcceptanceGranted'])


    def test_60_flat_source_owner_uv_helper_runs_real_bake_lods_export_and_reimport(self):
        result=self._run_constrained_lod_producer_probe('contact_owner_uv_producer',r'''
sys.path.insert(0,str(Path('''+repr(str(ROOT/'tests'))+r''')))
import rigid_source_topology as topology
from proof_model_contact_lod_controls import replace_fixture_core,contact_snapshot,verify_contact_snapshot,owner_uv_preconditions,observe_owner_uv_pack
root,job=fixture(baked=True,cavity=True)
job,unused_bindings=replace_fixture_core(root,job,rigid,finish,topology,smooth=False)
preconditions=owner_uv_preconditions(root,job,rigid,finish,topology)
assert preconditions['status']=='ACTUAL_OWNER_UV_PRECONDITIONS_PASS'
representations=json.loads((root/'contact-fixture-representations.json').read_text())
assert not representations['authoredSmoothNormalsSelected']
assert representations['actualExportedRenderVertices']>representations['authoredOwnerVertices']==285
packing_observations=[]
original_pack=rigid.pack_group
def observe_pack(lows,recipe,name,uv_atlas=None,*,source_topology=None):
    actual,proof=observe_owner_uv_pack(original_pack,lows,recipe,name,uv_atlas,source_topology,rigid)
    packing_observations.append(proof)
    return actual
observations=[]
frame_faults=[]
original_builder=rigid._clod_build_constrained_lods
original_reimport=topology.verify_contact_lod_reimport
def observe(low,settings,api,**kwargs):
    binding=kwargs.get('source_topology')
    assert binding is not None and settings['contactPolicy']=='protected-contact-rings-v1'
    reference=binding.reindex_copy(low,rigid,preserve_loops=True)
    report_path=folder/(low.name+'-actual-builder-report.json')
    report={}
    try:
        snapshot=contact_snapshot(reference) if low.name.startswith('core') else None
        output,report=original_builder(low,settings,api,**kwargs)
        # Keep the actual complete report even if a subsequent test assertion
        # fails; the production wrapper cannot attach this assertion's report.
        with report_path.open('x',encoding='utf-8')as stream:
            json.dump(report,stream,indent=2,allow_nan=False);stream.write('\n')
        if snapshot is not None:
            measured=[verify_contact_snapshot(snapshot,lod,api,level['maxVertexSurfaceErrorMetres'])
                      for lod,level in zip(output,settings['levels'])]
            assert any(row['triangles']<562 for row in measured)
            observations.append({'part':'core','protectedBeforeActualExport':measured,
                'actualBuilderReportSha256':sha(report_path),'sourceHardUvEdges':sum(snapshot['hardUvEdges'].values()),
                'sourceHadActualBakedAtlasUvs':bool(low.data.uv_layers),
                'sourceTopologyActualPreparedReceiptBound':True})
        return output,report
    except BaseException as error:
        if not report_path.exists():
            with report_path.open('x',encoding='utf-8')as stream:
                json.dump(getattr(error,'report',report),stream,indent=2,allow_nan=False);stream.write('\n')
        with (folder/(low.name+'-observer-error.json')).open('x',encoding='utf-8')as stream:
            json.dump({'error':str(error),'type':type(error).__name__,'actualBuilderReport':report_path.name,
                       'helperReportAvailable':bool(getattr(error,'report',report))},stream,indent=2,allow_nan=False)
        raise
    finally:
        data=reference.data;bpy.data.objects.remove(reference,do_unlink=True)
        if data.users==0:bpy.data.meshes.remove(data)
def verify_reimport_with_frame_faults(obj,context,low0,low_binding,lod_binding,api):
    from proof_model_contact_lod_controls import _snapshot
    actual=original_reimport(obj,context,low0,low_binding,lod_binding,api)
    # Actual imported objects; explicitly simulated post-import channel tamper.
    for label,target in (('LOW0-only',low0),('LOD-only',obj)):
        before=_snapshot(target);old=float(target.location.x)
        try:
            target.location.x=old+.001;bpy.context.view_layer.update()
            try:original_reimport(obj,context,low0,low_binding,lod_binding,api)
            except ValueError as error:
                assert 'frame'in str(error).lower(),str(error)
                frame_faults.append({'name':obj.name,'tampered':label,'execution':'ACTUAL_REIMPORT_THEN_SIMULATED_CHANNEL_TAMPER',
                                     'rejectedByRealFrameGuard':str(error)})
            else:raise AssertionError('Contact LOD frame divergence accepted '+label)
        finally:
            target.location.x=old;bpy.context.view_layer.update()
            assert _snapshot(target)==before,'Frame fault fixture failed exact restoration'
    return actual

with patch.object(rigid,'pack_group',observe_pack),patch.object(rigid,'_clod_build_constrained_lods',observe),patch.object(topology,'verify_contact_lod_reimport',verify_reimport_with_frame_faults):
    invoke(root,job)
actual=json.loads((root/'out/result.json').read_text())
core=next(row for row in actual['measurements']['parts']if row['part']=='core')
assert observations and actual['measurements']['atlases']
assert core['constrainedLods']['sourceLow0Immutable']
assert any(row['triangles']<562 for row in core['constrainedLods']['levels'])
checks=next(row for row in actual['stages']if row['stage']=='independentReimport')['checks']
owned=[row for row in checks if 'reviewedSourceTopology'in row]
assert {'core_LOD0','core_LOD1','core_LOD2'}<={row['name']for row in owned}
assert all(row['reviewedSourceTopology']['nonManifoldEdges']==0 for row in owned)
assert all('constrainedLodNativeFaceAreaFloor'in row for row in checks
           if '_LOD'in row['name'] and not row['name'].endswith('_LOD0'))
receipt=root/actual['artifacts']['sourceTopologyReceipt']
assert sha(receipt)==actual['outputHashes'][actual['artifacts']['sourceTopologyReceipt']]
budget=actual['measurements']['constrainedLodPackageBudget']
assert budget['otherTriangles']>0 and budget['packageTriangles']<=job['recipe']['maxTriangles']
assert actual['humanApproval']=='pending'
assert frame_faults and {row['tampered']for row in frame_faults}=={'LOW0-only','LOD-only'}
assert packing_observations and all(row['exactWorldCornerBitsAndLoopScatter']for row in packing_observations)
evidence({'status':'ACTUAL_FLAT_OWNER_UV_BAKE_EXPORT_REIMPORT_PASS','observations':observations,
          'preconditions':preconditions,'ownerConnectedPackingObservations':packing_observations,
          'sourceStayedFlatAndFragmented':True,
          'actualRealBakeAndGlbAndIndependentReimport':True,'negativeCavityExactBeforeExport':True,
          'outputSourceTopologyReceiptSha256':sha(receipt),'packageBudget':budget,
          'injectedActualReimportFrameFaults':frame_faults,
          'transportUvUsesExistingGuardNotClaimedBitExactAfterGltfFlip':True,'humanAcceptanceGranted':False})
''')
        self.assertEqual(result['status'],'ACTUAL_FLAT_OWNER_UV_BAKE_EXPORT_REIMPORT_PASS')
        self.assertTrue(result['actualRealBakeAndGlbAndIndependentReimport'])
        self.assertFalse(result['humanAcceptanceGranted'])



if __name__=='__main__':
    unittest.main(verbosity=2)
